package main

import (
	"fmt"
	"log"
	"net/http"

	// Import the SDK package
	spiffesdk "github.com/authsec-ai/spiffe-sdk"
)

// Example: Customer Service Integration with SPIRE Agent
//
// PREREQUISITES:
// 1. SPIRE Agent running as DaemonSet on this node
// 2. Workload pre-registered in SPIRE Server (via Headless API)
//
// Registration example (done by Admin/DevOps):
//   POST https://dev.api.authsec.dev/spiresvc/api/v1/workloads
//   {
//     "spiffe_id": "spiffe://authsec.dev/customer-service",
//     "parent_id": "spiffe://authsec.dev/agent/k8s-node-1",
//     "type": "application",
//     "selectors": [
//       "k8s:ns:authsec",
//       "k8s:sa:customer-sa",
//       "k8s:pod-label:app:customer-service"
//     ]
//   }

func main() {
	// 1. Configure the SPIFFE SDK (minimal config)
	config := &spiffesdk.Config{
		ServiceName: "customer-service",
		SocketPath:  "/run/spire/sockets/agent.sock",
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
	if err := sdk.Initialize(); err != nil {
		log.Fatal("Failed to initialize SPIFFE SDK:", err)
	}

	fmt.Println("✅ Customer Service initialized with SPIFFE identity")
	fmt.Printf("✅ Received SPIFFE ID: %s\n", sdk.GetSPIFFEID())

	// 4. Set up HTTP server with SPIFFE middleware
	mux := http.NewServeMux()

	// Add business logic handlers
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/customer/", customerHandler)
	mux.HandleFunc("/internal/payment", paymentServiceHandler(sdk))

	// 5. Wrap with SPIFFE incoming validation middleware
	protectedHandler := sdk.IncomingValidationMiddleware(mux)

	// 6. Start HTTPS server with SPIFFE TLS
	server := &http.Server{
		Addr:      ":8080",
		Handler:   protectedHandler,
		TLSConfig: sdk.GetHTTPClient().Transport.(*http.Transport).TLSClientConfig,
	}

	fmt.Println("🚀 Customer Service starting on :8080 with SPIFFE mTLS")
	log.Fatal(server.ListenAndServeTLS("", "")) // Certificates come from SPIFFE
}

// Business logic handlers
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, `{"status": "healthy", "service": "customer-service"}`)
}

func customerHandler(w http.ResponseWriter, r *http.Request) {
	// Extract SPIFFE ID from context (set by incoming validation middleware)
	spiffeID := r.Context().Value("spiffe_id")

	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{
		"message": "Customer data",
		"authenticated_caller": "%v",
		"customer_id": "12345"
	}`, spiffeID)
}

// Example of making outgoing calls to other services with SPIFFE mTLS
func paymentServiceHandler(sdk *spiffesdk.SpiffeSDK) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Create HTTP client with SPIFFE mTLS for outgoing calls
		client := sdk.GetHTTPClient()

		// Make authenticated call to payment service
		resp, err := client.Get("https://payment-service.authsec.svc.cluster.local:8080/process")
		if err != nil {
			http.Error(w, "Failed to call payment service", http.StatusInternalServerError)
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"message": "Payment processed via SPIFFE mTLS"}`)
	}
}
