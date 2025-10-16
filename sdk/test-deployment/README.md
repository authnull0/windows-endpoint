# SDK Integration Test

This directory contains everything needed to test the SPIFFE SDK end-to-end with your SPIRE Agent.

## Prerequisites

1. SPIRE Agent running in your cluster (already deployed as daemonset)
2. Headless API running and accessible
3. kubectl configured to access your cluster

## Step 1: Register the Test Workload

You have two options:

### Option A: Using Postman

**POST** `http://localhost:7001/spiresvc/api/v1/workloads`

Use the payload in `register-workload.json`:

```json
{
  "spiffe_id": "spiffe://authsec.dev/test-sdk-app",
  "parent_id": "spiffe://authsec.dev/spire/agent/join_token/9f1ad98e-7f09-4903-ad31-0dfe772ce0d4",
  "type": "application",
  "selectors": [
    "k8s:ns:spire",
    "k8s:sa:default",
    "k8s:pod-label:app:test-sdk"
  ],
  "register_with_spire": true
}
```

### Option B: Using curl

```bash
curl -X POST http://localhost:7001/spiresvc/api/v1/workloads \
  -H "Content-Type: application/json" \
  -d @register-workload.json
```

**Expected Response:**
```json
{
  "id": "some-uuid",
  "spiffe_id": "spiffe://authsec.dev/test-sdk-app",
  "status": "active",
  "message": "Workload registered successfully with SPIRE"
}
```

## Step 2: Deploy the Test Pod

```bash
kubectl apply -f sdk-test-pod.yaml
```

## Step 3: Watch the Test Progress

```bash
# Watch pod status
kubectl get pods -n spire -w

# Once pod is running, watch the logs
kubectl logs -n spire sdk-test-app -f
```

## Expected Output

If everything works correctly, you should see:

```
=== SDK Integration Test ===
Connecting to SPIRE Agent...
✅ Successfully connected to SPIRE Agent

=== SVID Retrieved Successfully ===
SPIFFE ID: spiffe://authsec.dev/test-sdk-app
Certificate Count: 1
Expiry: 2025-10-15 11:30:45 +0000 UTC
Serial Number: 123456789

🎉 SDK Integration Test PASSED!
The SDK successfully:
  1. Connected to SPIRE Agent
  2. Retrieved X.509 SVID
  3. Validated certificate chain

Keeping pod alive for inspection... (will exit in 5 minutes)
```

## Step 4: Verify SVID Metadata (Optional)

Check if the SVID metadata was captured in your database:

```bash
# Query your Headless API
curl http://localhost:7001/spiresvc/api/v1/svid-metadata?spiffe_id=spiffe://authsec.dev/test-sdk-app
```

## Step 5: Cleanup

```bash
kubectl delete pod -n spire sdk-test-app
```

Optionally delete the workload registration:
```bash
curl -X DELETE http://localhost:7001/spiresvc/api/v1/workloads/test-sdk-app
```

## Troubleshooting

### Pod stays in ContainerCreating
- Check if SPIRE Agent socket is accessible: `kubectl exec -n spire spire-agent-spire-agent-2kjxd -- ls -la /run/spire/sockets/`

### "Failed to get X509 SVID"
- Verify workload is registered: `curl http://localhost:7001/spiresvc/api/v1/workloads`
- Check selectors match the pod labels
- Verify parent_id matches your agent's SPIFFE ID

### "Failed to create X509 source"
- Check agent socket path in pod: `kubectl exec -n spire sdk-test-app -- ls -la /run/spire/sockets/`
- Verify agent is running: `kubectl get pods -n spire -l app=spire-agent`

### Build fails in pod
- The pod downloads dependencies and builds on startup, this may take 1-2 minutes
- Check logs for Go module errors

## What This Test Validates

✅ SDK can connect to SPIRE Agent via Unix socket
✅ Workload attestation works (k8s selectors)
✅ SVID issuance is successful
✅ Certificate chain is valid
✅ SPIFFE ID matches registration
✅ End-to-end flow: Registration → Attestation → SVID Issuance → SDK Retrieval

## Next Steps

Once this test passes, you can:
1. Test mTLS between two services (Phase 2)
2. Test SVID rotation (Phase 3)
3. Roll out SDK to production services
