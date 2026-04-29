#!/usr/bin/env bash
#
# ntlm-gate.sh — Path 3A NTLM-bypass fix.
#
# Replaces the earlier unconditional iptables DNAT (which forwarded every
# DC-adjacent port to the DC regardless of client identity) with a
# conditional DNAT that only fires for client IPs present in the
# `authnull_active` ipset. The gateway's ad-gateway-proxy process maintains
# that set by mirroring MFA session cache stamps — a client's IP lands in
# the set when they approve MFA and expires on the same TTL.
#
# Without this:  a client whose Kerberos AS-REQ failed MFA silently falls
# back to NTLM over SMB (port 445), which rode the old catch-all DNAT
# straight to the DC, completely bypassing our policy layer.
#
# With this:     no DNAT → SMB SYN hits nothing → RST → NTLM fallback
# cannot complete. Only Kerberos (port 88) and LDAP (389) remain reachable
# on the gateway, and those are MFA-gated by the proxy process itself.
#
# Run as root on the gateway VA. Idempotent — safe to re-run.

set -euo pipefail

DC_IP="${DC_IP:-10.4.0.17}"
GW_IP="${GW_IP:-10.4.0.8}"
IPSET_NAME="${IPSET_NAME:-authnull_active}"
IPSET_TTL="${IPSET_TTL:-300}"                 # must match proxy's mfa_session_ttl

# Ports the proxy itself terminates. Never DNAT these away.
# 445/tcp — Path 3B SMB MITM. The proxy listens on :445 and MFA-gates
# every SESSION_SETUP itself, so we no longer want the kernel to DNAT
# this port to the DC behind our back.
PROXY_PORTS_TCP="22,88,389,445,18443,19813"
PROXY_PORTS_UDP="88,389"

echo "==> Checking ipset is installed"
if ! command -v ipset >/dev/null; then
    echo "FATAL: 'ipset' not found. Install with: apt-get install -y ipset" >&2
    exit 1
fi

echo "==> Enabling IPv4 forwarding"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-ad-gateway.conf <<EOF
net.ipv4.ip_forward=1
EOF

echo "==> Ensuring ipset '$IPSET_NAME' exists (hash:ip, timeout=$IPSET_TTL)"
ipset create "$IPSET_NAME" hash:ip timeout "$IPSET_TTL" -exist

echo "==> Flushing old nat-table PREROUTING / POSTROUTING rules owned by us"
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

echo "==> Installing conditional DNAT: DC-bound ports from active IPs only"
# TCP: everything destined for the gateway EXCEPT our own listeners,
# AND only if source IP is in the active-session set, DNAT to DC.
iptables -t nat -A PREROUTING -d "$GW_IP" -p tcp \
    -m multiport ! --dports "$PROXY_PORTS_TCP" \
    -m set --match-set "$IPSET_NAME" src \
    -j DNAT --to-destination "$DC_IP"

# UDP: same pattern. Kerberos UDP (88) and CLDAP (389) are terminated by
# the proxy, every other UDP only flows for active sessions.
iptables -t nat -A PREROUTING -d "$GW_IP" -p udp \
    -m multiport ! --dports "$PROXY_PORTS_UDP" \
    -m set --match-set "$IPSET_NAME" src \
    -j DNAT --to-destination "$DC_IP"

echo "==> MASQUERADE so responses from DC route back to client"
iptables -t nat -A POSTROUTING -d "$DC_IP" -j MASQUERADE

echo "==> Persisting rules"
if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save
    # ipset rules aren't saved by netfilter-persistent; save them separately.
    mkdir -p /etc/ipset
    ipset save > /etc/ipset/ipset.conf
    # Restore on boot — lightweight systemd unit.
    cat > /etc/systemd/system/authnull-ipset-restore.service <<'UNIT'
[Unit]
Description=Restore AuthNull ipsets before network rules
DefaultDependencies=no
After=local-fs.target
Before=netfilter-persistent.service
ConditionFileNotEmpty=/etc/ipset/ipset.conf

[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -! -f /etc/ipset/ipset.conf

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable authnull-ipset-restore.service >/dev/null
    echo "==> ipset + iptables persistence wired into systemd"
else
    echo "WARN: netfilter-persistent not installed — rules will not survive reboot."
    echo "      apt-get install -y iptables-persistent, then re-run this script."
fi

echo
echo "==> Current nat-table PREROUTING rules:"
iptables -t nat -L PREROUTING -n --line-numbers

echo
echo "==> Current ipset contents:"
ipset list "$IPSET_NAME"

cat <<EOF

Path 3A NTLM gate is now ACTIVE.

- DC-adjacent ports (135, 139, 445, 3268, 3269, 464, dynamic RPC) are only
  forwarded to the DC ($DC_IP) for clients whose IP is in ipset
  '$IPSET_NAME'.
- The ad-gateway-proxy process populates that ipset when an MFA session
  is stamped (user approves a phone push, or a machine-account Kerberos
  auth passes through).
- TTL on entries is $IPSET_TTL seconds — must match proxy.yml's
  'mfa_session_ttl'.

Verify end-to-end after a fresh MFA approval:

    ipset list $IPSET_NAME           # should show the client IP
    # then, from a fresh non-MFA'd client:
    # nc -w2 $GW_IP 445              # should RST immediately
EOF
