package main

import (
	"fmt"
	"log"
	"net/http"
	"time"

	// Import the SDK package
	spiffesdk "github.com/authsec-ai/spiffe-sdk"
)

// Example: Payment Service Integration with SPIRE Agent
//
// PREREQUISITES:
// 1. SPIRE Agent running as DaemonSet on this node
// 2. Workload pre-registered in SPIRE Server (via Headless API or spire-server CLI)
//
// Registration example (done by Admin/DevOps):
//   POST https://dev.api.authsec.dev/spiresvc/api/v1/workloads
//   {
//     "spiffe_id": "spiffe://authsec.dev/payment-service",
//     "parent_id": "spiffe://authsec.dev/agent/k8s-node-1",
//     "type": "application",
//     "selectors": [
//       "k8s:ns:authsec",
//       "k8s:sa:payment-sa",
//       "k8s:pod-label:app:payment-service"
//     ]
//   }

func main() {
	// 1. Configure the SPIFFE SDK
	// NOTE: Minimal config - just socket path and optional verification API
	config := &spiffesdk.Config{
		ServiceName: "payment-service",
		SocketPath:  "/run/spire/sockets/agent.sock", // SPIRE Agent socket
		TrustDomain: "authsec.dev",

		// Optional: For certificate verification via Headless API
		HeadlessAPIURL: "https://dev.api.authsec.dev/spiresvc",
	}

	// 2. Create SDK instance
	sdk, err := spiffesdk.NewSpiffeSDK(config)
	if err != nil {
		log.Fatal("Failed to create SPIFFE SDK:", err)
	}
	defer sdk.Close()

	// 3. Connect to SPIRE Agent
	// This will:
	// - Connect to local SPIRE Agent socket
	// - Agent validates pod identity (K8s attestation)
	// - Agent fetches SVID from SPIRE Server
	// - SDK receives SVID automatically
	if err := sdk.Initialize(); err != nil {
		log.Fatal("Failed to initialize SPIFFE SDK:", err)
	}

	fmt.Println("✅ Payment Service initialized with SPIFFE identity")
	fmt.Printf("✅ Received SPIFFE ID: %s\n", sdk.GetSPIFFEID())

	// 4. Set up HTTP server with SPIFFE middleware
	mux := http.NewServeMux()

	// Add business logic handlers
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/process", processPaymentHandler(sdk))
	mux.HandleFunc("/validate", validatePaymentHandler(sdk))

	// 5. Wrap with SPIFFE incoming validation middleware
	protectedHandler := sdk.IncomingValidationMiddleware(mux)

	// 6. Start server
	server := &http.Server{
		Addr:      ":8080",
		Handler:   protectedHandler,
		TLSConfig: sdk.GetHTTPClient().Transport.(*http.Transport).TLSClientConfig,
	}

	fmt.Println("🚀 Payment Service starting on :8080 with SPIFFE mTLS")
	log.Fatal(server.ListenAndServeTLS("", ""))
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, `{"status": "healthy", "service": "payment-service"}`)
}

func processPaymentHandler(sdk *spiffesdk.SpiffeSDK) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Extract caller's SPIFFE ID from context
		spiffeID := r.Context().Value("spiffe_id")

		// Validate that caller is authorized (e.g., customer-service)
		if spiffeID != "spiffe://authsec.dev/customer-service" {
			http.Error(w, "Unauthorized caller", http.StatusForbidden)
			return
		}

		// Process payment logic here
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{
			"status": "success",
			"transaction_id": "txn_12345",
			"authenticated_caller": "%v",
			"timestamp": "%s"
		}`, spiffeID, time.Now().Format(time.RFC3339))
	}
}

func validatePaymentHandler(sdk *spiffesdk.SpiffeSDK) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Example of calling external service with SPIFFE mTLS
		client := sdk.GetHTTPClient()

		// Make call to user service for validation
		resp, err := client.Get("https://user-service.authsec.svc.cluster.local:8080/validate")
		if err != nil {
			http.Error(w, "Failed to validate with user service", http.StatusInternalServerError)
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"validation": "completed", "method": "spiffe_mtls"}`)
	}
}