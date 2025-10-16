# mTLS and SVID Rotation Testing Guide

This guide covers Phase 2 and Phase 3 of SDK testing:
- **Phase 2**: mTLS between two services
- **Phase 3**: SVID rotation monitoring

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SPIRE Agent                          │
│                   (DaemonSet)                           │
│                                                         │
│  - Issues SVIDs to both services                        │
│  - Automatically rotates SVIDs before expiry            │
│  - Pushes updates via Workload API                      │
└──────────────┬──────────────────────┬───────────────────┘
               │                      │
               │ Socket               │ Socket
               │ /run/spire/sockets/  │ /run/spire/sockets/
               │                      │
    ┌──────────▼──────────┐  mTLS   ┌▼──────────────────┐
    │   Service A         │◄────────┤   Service B       │
    │   (Server)          │         │   (Client)        │
    │                     │         │                   │
    │  - HTTPS Server     │         │  - Makes requests │
    │  - Validates client │         │  - Every 15 sec   │
    │  - Port 8443        │         │  - Uses mTLS      │
    └─────────────────────┘         └───────────────────┘
```

## What This Tests

### ✅ mTLS (Mutual TLS)
- Both client and server authenticate each other using SVIDs
- Only services with valid SPIFFE IDs can communicate
- Automatic certificate validation

### ✅ SVID Rotation
- Agent rotates SVIDs before expiry (default: 1 hour TTL, rotates at 30 min)
- Both services automatically pick up new SVIDs
- Zero downtime during rotation
- mTLS connections continue seamlessly

### ✅ Real-World Scenario
- Service-to-service communication
- Background monitoring
- Continuous operation

## Step 1: Deploy Service A (Server)

```bash
kubectl apply -f service-a-server.yaml
```

Wait for it to be ready:
```bash
kubectl get pod -n spire service-a-server -w
```

Check logs:
```bash
kubectl logs -n spire service-a-server -f
```

**Expected output:**
```
=== Service A (Server) - mTLS Test ===
Starting server with SPIFFE mTLS...
✅ Server SPIFFE ID: spiffe://authsec.dev/service-a-server
📅 Initial SVID Expiry: 2025-10-15 12:30:00 +0000 UTC
🔢 Initial Serial: 123456789

🚀 Server listening on :8443 with mTLS enabled
📊 Monitoring SVID rotation in background...
```

## Step 2: Deploy Service B (Client)

```bash
kubectl apply -f service-b-client.yaml
```

Wait for it to be ready:
```bash
kubectl get pod -n spire service-b-client -w
```

Check logs:
```bash
kubectl logs -n spire service-b-client -f
```

**Expected output:**
```
=== Service B (Client) - mTLS Test ===
Starting client with SPIFFE mTLS...
✅ Client SPIFFE ID: spiffe://authsec.dev/service-b-client
📅 Initial SVID Expiry: 2025-10-15 12:30:00 +0000 UTC
🔢 Initial Serial: 987654321

🚀 Starting to make mTLS requests to service-a...
📊 Monitoring SVID rotation in background...

────────────────────────────────────────────────────────────
✅ mTLS Request Successful at 10:15:30
📋 Client Serial: 987654321
📥 Server Response:
{
  "message": "mTLS Connection Successful!",
  "server_spiffe_id": "spiffe://authsec.dev/service-a-server",
  "client_spiffe_id": "spiffe://authsec.dev/service-b-client",
  "server_svid_expiry": "2025-10-15 12:30:00 +0000 UTC",
  "server_svid_serial": "123456789",
  "timestamp": "2025-10-15T10:15:30Z"
}
────────────────────────────────────────────────────────────
```

## Step 3: Monitor Both Services

Open two terminal windows:

**Terminal 1 - Service A logs:**
```bash
kubectl logs -n spire service-a-server -f
```

**Terminal 2 - Service B logs:**
```bash
kubectl logs -n spire service-b-client -f
```

## Step 4: Watch for SVID Rotation

Both services monitor their SVIDs every 10 seconds. When the SPIRE Agent rotates the SVID (typically after 30 minutes with 1-hour TTL), you'll see:

**In Service A logs:**
```
============================================================
🔄 SVID ROTATION DETECTED!
============================================================
Old Serial: 123456789
New Serial: 111222333444
New Expiry: 2025-10-15 13:30:00 +0000 UTC
Rotation Time: 2025-10-15T11:00:00Z
============================================================
```

**In Service B logs:**
```
============================================================
🔄 CLIENT SVID ROTATION DETECTED!
============================================================
Old Serial: 987654321
New Serial: 555666777888
New Expiry: 2025-10-15 13:30:00 +0000 UTC
Rotation Time: 2025-10-15T11:00:00Z
============================================================
```

**Important**: mTLS requests continue to work during and after rotation!

## Step 5: Verify mTLS Validation

You can verify that mTLS is actually validating identities by checking the server logs. Each request shows:
- Client's SPIFFE ID (extracted from client certificate)
- Server's SPIFFE ID
- Both SVIDs' serial numbers and expiry

This proves mutual authentication is working.

## Testing SVID Rotation Faster (Optional)

By default, SVIDs have 1-hour TTL and rotate at 50% lifetime (30 minutes). To test rotation faster, you can:

### Option 1: Reduce TTL in SPIRE Server config (on central server)

Edit SPIRE Server config to set shorter TTL:
```hcl
server {
    default_x509_svid_ttl = "5m"  # 5 minute TTL (rotates at 2.5 min)
}
```

### Option 2: Wait for natural rotation

The current setup will rotate in ~30 minutes. You can leave the pods running and check back.

## What Success Looks Like

✅ **mTLS Working**:
- Service B successfully makes requests to Service A
- Both services show valid SPIFFE IDs in logs
- No certificate errors

✅ **SVID Rotation Working**:
- Both services detect rotation (different serial numbers)
- New expiry times are extended
- mTLS requests continue without interruption
- No manual intervention needed

✅ **Zero Downtime**:
- Requests succeed before, during, and after rotation
- No connection errors during rotation
- Automatic and transparent to application

## Cleanup

```bash
kubectl delete -f service-a-server.yaml
kubectl delete -f service-b-client.yaml
kubectl delete pod -n spire sdk-test-app  # from previous test
```

## Troubleshooting

### Service B can't connect to Service A

**Check service DNS:**
```bash
kubectl exec -n spire service-b-client -- nslookup service-a.spire.svc.cluster.local
```

**Check if Service A is listening:**
```bash
kubectl exec -n spire service-a-server -- netstat -tlnp | grep 8443
```

### "x509: certificate signed by unknown authority"

This means the SPIRE Agent isn't providing trust bundles. Check:
```bash
kubectl logs -n spire spire-agent-spire-agent-2kjxd
```

### Rotation not happening

Check agent logs for rotation activity:
```bash
kubectl logs -n spire spire-agent-spire-agent-2kjxd | grep -i rotate
```

### Pods stuck in build phase

The first deployment takes ~30 seconds to download Go dependencies and build. Be patient!

## Key Learnings

1. **mTLS is automatic** - Just use the SDK's TLS config, no manual cert management
2. **Rotation is automatic** - Agent handles it, SDK receives updates seamlessly
3. **Zero application code** for rotation - The `X509Source` automatically updates
4. **Production-ready** - This is the same pattern used in production microservices

## Next Steps

After this test passes:
1. ✅ You've validated the entire SPIFFE/SPIRE flow
2. ✅ SDK is production-ready
3. ✅ You can roll out to real services
4. 📦 Publish SDK to separate GitHub repository
5. 📚 Create developer onboarding documentation
