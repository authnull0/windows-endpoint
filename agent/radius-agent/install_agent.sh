#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}==> $1${NC}"
}

print_status "Updating the system..."
sudo apt-get update -y || { echo -e "${RED}System update failed!${NC}"; exit 1; }

print_status "Installing FreeRADIUS and required utilities..."
sudo apt-get install -y freeradius freeradius-utils || { echo -e "${RED}FreeRADIUS installation failed!${NC}"; exit 1; }
dpkg -l | grep '^ii.*freeradius' || { echo -e "${RED}FreeRADIUS not installed correctly!${NC}"; exit 1; }

print_status "Configuring FreeRADIUS authentication methods..."
[ -f /etc/freeradius/3.0/sites-enabled/default ] || { echo -e "${RED}Default site file missing!${NC}"; exit 1; }
sudo cp /etc/freeradius/3.0/sites-enabled/default /etc/freeradius/3.0/sites-enabled/default.bak
sudo sed -i '/^authorize {/,/^}/ s/^}/    authnull_2fa\n    if (ok) {\n        update control {\n            Auth-Type := Accept\n        }\n        update reply {\n            Reply-Message := "2FA Successful"\n        }\n    } else {\n        reject\n    }\n}/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/^authenticate {/,/^}/ s/^}/    authnull_2fa\n}/' /etc/freeradius/3.0/sites-enabled/default

print_status "Configuring FreeRADIUS exec module..."
cat << 'EOF' | sudo tee /etc/freeradius/3.0/mods-available/exec > /dev/null
exec {
    wait = yes
    input_pairs = request
    output_pairs = reply
    shell_escape = yes
    timeout = 10
    pass_through = yes
}
EOF
[ -f /etc/freeradius/3.0/mods-enabled/exec ] || sudo ln -sf /etc/freeradius/3.0/mods-available/exec /etc/freeradius/3.0/mods-enabled/

print_status "Installing 2FA script (authnull_2fa)..."
sudo wget https://github.com/authnull0/windows-endpoint/raw/main/agent/radius-build/authnull_2fa -O authnull_2fa || { echo -e "${RED}Failed to download authnull_2fa!${NC}"; exit 1; }
file authnull_2fa | grep -q "executable" || { echo -e "${RED}authnull_2fa is not an executable!${NC}"; exit 1; }
sudo mv authnull_2fa /usr/local/bin/
sudo chmod 755 /usr/local/bin/authnull_2fa
sudo chown root:root /usr/local/bin/authnull_2fa

print_status "Configuring FreeRADIUS 2FA module..."
cat << 'EOF' | sudo tee /etc/freeradius/3.0/mods-available/authnull_2fa > /dev/null
exec authnull_2fa {
    wait = yes
    program = "/usr/local/bin/authnull_2fa \
        \"%{User-Name}@authnull.com\" \"%{User-Password}\" \"%{CHAP-Password}\" \
        \"%{Calling-Station-Id}\" \"%{NAS-IP-Address}\" \"%{NAS-Port}\" \
        \"%{NAS-Identifier}\" \"%{NAS-Port-Type}\" \"%{Framed-IP-Address}\" \
        \"%{Called-Station-Id}\" \"%{Service-Type}\" \"%{Framed-Protocol}\" \
        \"%{Filter-Id}\" \"%{Class}\" \"%{Session-Timeout}\" \
        \"%{Idle-Timeout}\" \"%{Acct-Session-Id}\" \"%{Acct-Input-Octets}\" \
        \"%{Acct-Output-Octets}\" \"%{Vendor-Specific}\" \"%{State}\" \
        \"%{Reply-Message}\""
    shell_escape = yes
    output = Reply-Message
}
EOF
[ -f /etc/freeradius/3.0/mods-enabled/authnull_2fa ] || sudo ln -sf /etc/freeradius/3.0/mods-available/authnull_2fa /etc/freeradius/3.0/mods-enabled/

print_status "Installing and configuring Fluent Bit..."
curl -o fluent-bit-install.sh https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh || { echo -e "${RED}Failed to download Fluent Bit installer!${NC}"; exit 1; }
sudo sh fluent-bit-install.sh || { echo -e "${RED}Fluent Bit installation failed!${NC}"; exit 1; }
rm -f fluent-bit-install.sh
sudo mkdir -p /etc/fluent-bit/
cat << 'EOF' | sudo tee /etc/fluent-bit/parsers.conf > /dev/null
[PARSER]
    Name        json_parser
    Format      json
    Time_Key    time
    Time_Format %Y-%m-%dT%H:%M:%S
EOF
cat << 'EOF' | sudo tee /etc/fluent-bit/fluent-bit.conf > /dev/null
[SERVICE]
    Flush             1
    Log_Level         debug
    Parsers_File      /etc/fluent-bit/parsers.conf
[INPUT]
    Name              tail
    Path              /var/log/radius_2fa.log
    Tag               radius_log
    Mem_Buf_Limit     5MB
    Read_from_Head    On
    Parser            json_parser
[FILTER]
    Name    grep
    Match   radius_log
    Regex   eventType radius_auth
[OUTPUT]
    Name    stdout
    Match   radius_log
    Format  json
[OUTPUT]
    Name        http
    Match       radius_log
    Host        monitoring.authnull.com
    Port        443
    URI         /
    tls         on
    tls.verify  on
    Retry_Limit false
    Header      Content-Type application/json
    Format      json
EOF

print_status "Testing FreeRADIUS configuration..."
sudo freeradius -C || { echo -e "${RED}FreeRADIUS configuration test failed!${NC}"; exit 1; }

print_status "FreeRADIUS with 2FA and Fluent Bit setup completed successfully!"