package spiffesdk

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

// SpiffeSDK provides complete SPIFFE integration for microservices
// It connects to the local SPIRE Agent to receive SVIDs
type SpiffeSDK struct {
	config       *Config
	headlessAPI  *HeadlessAPI  // Optional: for certificate verification only
	workloadAPI  *workloadapi.X509Source  // Primary: connects to SPIRE Agent
	httpClient   *http.Client
	tlsConfig    *tls.Config
	mu           sync.RWMutex
	ctx          context.Context
	cancel       context.CancelFunc
}

// Config holds SDK configuration
type Config struct {
	// Service Identity
	ServiceName     string `json:"service_name"`
	SPIFFEID        string `json:"spiffe_id"`  // Informational only - agent determines identity

	// SPIRE Agent Configuration
	SocketPath      string `json:"socket_path"`  // Default: /run/spire/sockets/agent.sock
	TrustDomain     string `json:"trust_domain"`

	// Optional: Headless API for certificate verification
	HeadlessAPIURL  string `json:"headless_api_url,omitempty"`
}

// Removed SVIDCache - no longer needed as workloadAPI.X509Source handles this automatically

// HeadlessAPI client for headless SPIRE service
type HeadlessAPI struct {
	BaseURL    string
	HTTPClient *http.Client
}

// NewSpiffeSDK creates a new SPIFFE SDK instance
// The SDK connects to the local SPIRE Agent - workload must be pre-registered
func NewSpiffeSDK(config *Config) (*SpiffeSDK, error) {
	ctx, cancel := context.WithCancel(context.Background())

	// Set default socket path if not provided
	if config.SocketPath == "" {
		config.SocketPath = "/run/spire/sockets/agent.sock"
	}

	sdk := &SpiffeSDK{
		config: config,
		ctx:    ctx,
		cancel: cancel,
	}

	// Initialize optional headless API for certificate verification
	if config.HeadlessAPIURL != "" {
		sdk.headlessAPI = &HeadlessAPI{
			BaseURL: config.HeadlessAPIURL,
			HTTPClient: &http.Client{
				Timeout: 10 * time.Second,
			},
		}
	}

	return sdk, nil
}

// Initialize connects to the local SPIRE Agent and retrieves SVIDs
// NOTE: Workload must be pre-registered via Headless API or SPIRE Server before calling this
func (s *SpiffeSDK) Initialize() error {
	fmt.Printf("Connecting to SPIRE Agent at %s\n", s.config.SocketPath)

	// Step 1: Connect to SPIRE Agent Workload API
	if err := s.initWorkloadAPI(); err != nil {
		return fmt.Errorf("failed to connect to SPIRE Agent: %w (ensure workload is registered and agent is running)", err)
	}

	fmt.Println("✅ Connected to SPIRE Agent successfully")

	// Step 2: Setup TLS configuration using workload API
	if err := s.setupTLSConfig(); err != nil {
		return fmt.Errorf("TLS setup failed: %w", err)
	}

	fmt.Println("✅ TLS configuration established")
	fmt.Printf("✅ SPIFFE ID: %s\n", s.GetSPIFFEID())

	// Note: SPIRE Agent handles automatic SVID rotation, no manual renewal needed!
	return nil
}

// GetSPIFFEID returns the SPIFFE ID assigned to this workload by the SPIRE Agent
func (s *SpiffeSDK) GetSPIFFEID() string {
	if s.workloadAPI == nil {
		return ""
	}

	svid, err := s.workloadAPI.GetX509SVID()
	if err != nil {
		return ""
	}

	return svid.ID.String()
}

// GetX509SVID returns the current X.509 SVID
// This is automatically rotated by the SPIRE Agent
func (s *SpiffeSDK) GetX509SVID() (*x509.Certificate, error) {
	if s.workloadAPI == nil {
		return nil, fmt.Errorf("workload API not initialized")
	}

	svid, err := s.workloadAPI.GetX509SVID()
	if err != nil {
		return nil, fmt.Errorf("failed to get X509 SVID: %w", err)
	}

	if len(svid.Certificates) == 0 {
		return nil, fmt.Errorf("no certificates in SVID")
	}

	return svid.Certificates[0], nil
}

// GetHTTPClient returns an HTTP client configured with SPIFFE mTLS for internal service calls
// Use this for calling other services in the same trust domain
func (s *SpiffeSDK) GetHTTPClient() *http.Client {
	return &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: s.tlsConfig,
		},
		Timeout: 30 * time.Second,
	}
}

// NewInternalHTTPClient creates an HTTP client that automatically uses mTLS for internal services
// and regular HTTP for external services
func (s *SpiffeSDK) NewInternalHTTPClient(internalDomains []string) *http.Client {
	return &http.Client{
		Transport: &smartTransport{
			sdk:             s,
			internalDomains: internalDomains,
			mtlsTransport: &http.Transport{
				TLSClientConfig: s.tlsConfig,
			},
			regularTransport: http.DefaultTransport,
		},
		Timeout: 30 * time.Second,
	}
}

// smartTransport switches between mTLS and regular HTTP based on target
type smartTransport struct {
	sdk              *SpiffeSDK
	internalDomains  []string
	mtlsTransport    http.RoundTripper
	regularTransport http.RoundTripper
}

func (t *smartTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	// Check if this is an internal service call
	host := req.URL.Host
	if host == "" {
		host = req.Host
	}

	for _, domain := range t.internalDomains {
		// Check for exact match or suffix match (e.g., .svc.cluster.local)
		if host == domain || (len(domain) > 0 && domain[0] == '.' && hasSuffix(host, domain)) {
			// Use mTLS for internal services
			return t.mtlsTransport.RoundTrip(req)
		}
		// Check if host contains the domain (for k8s services like service.namespace.svc.cluster.local)
		if len(domain) > 1 && domain[0] != '.' && (host == domain || hasSuffix(host, "."+domain)) {
			return t.mtlsTransport.RoundTrip(req)
		}
	}
	// Use regular HTTP for external services
	return t.regularTransport.RoundTrip(req)
}

func hasSuffix(s, suffix string) bool {
	return len(s) >= len(suffix) && s[len(s)-len(suffix):] == suffix
}

// GetHTTPServer returns an HTTP server configured with SPIFFE mTLS and validation middleware
func (s *SpiffeSDK) GetHTTPServer(addr string, handler http.Handler, validateIncoming bool) *http.Server {
	var finalHandler http.Handler
	if validateIncoming {
		// Wrap with validation middleware
		finalHandler = s.IncomingValidationMiddleware(handler)
	} else {
		finalHandler = handler
	}

	return &http.Server{
		Addr:      addr,
		Handler:   finalHandler,
		TLSConfig: tlsconfig.MTLSServerConfig(s.workloadAPI, s.workloadAPI, tlsconfig.AuthorizeAny()),
	}
}

// ValidateIncomingSVID validates an incoming certificate using Headless API
// Note: This requires HeadlessAPIURL to be configured
func (s *SpiffeSDK) ValidateIncomingSVID(cert string) (*ValidationResult, error) {
	if s.headlessAPI == nil {
		return nil, fmt.Errorf("headless API not configured - set HeadlessAPIURL in config")
	}

	payload := map[string]string{
		"certificate": cert,
	}

	return s.headlessAPI.VerifyCertificate(payload)
}

// IncomingValidationMiddleware for HTTP servers
func (s *SpiffeSDK) IncomingValidationMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Extract client certificate from TLS connection
		if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
			clientCert := r.TLS.PeerCertificates[0]

			// Convert to PEM format for validation
			certPEM := s.certToPEM(clientCert)

			result, err := s.ValidateIncomingSVID(certPEM)
			if err != nil || !result.Valid {
				http.Error(w, "Invalid client certificate", http.StatusUnauthorized)
				return
			}

			// Add SPIFFE ID to request context
			ctx := context.WithValue(r.Context(), "spiffe_id", result.SPIFFEID)
			r = r.WithContext(ctx)
		}

		next.ServeHTTP(w, r)
	})
}

// OutgoingAttachmentMiddleware for HTTP clients
func (s *SpiffeSDK) OutgoingAttachmentMiddleware(rt http.RoundTripper) http.RoundTripper {
	return &spiffeMTLSTransport{
		sdk:       s,
		transport: rt,
	}
}

// spiffeMTLSTransport implements http.RoundTripper with SPIFFE mTLS
type spiffeMTLSTransport struct {
	sdk       *SpiffeSDK
	transport http.RoundTripper
}

func (t *spiffeMTLSTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	// Clone the request and add SPIFFE TLS config
	req = req.Clone(req.Context())

	// Use the SPIFFE-configured transport
	if t.transport == nil {
		t.transport = &http.Transport{
			TLSClientConfig: t.sdk.tlsConfig,
		}
	}

	return t.transport.RoundTrip(req)
}

// Helper functions and types...

type ValidationResult struct {
	Valid     bool   `json:"valid"`
	SPIFFEID  string `json:"spiffe_id"`
	Subject   string `json:"subject"`
	Issuer    string `json:"issuer"`
	NotBefore string `json:"not_before"`
	NotAfter  string `json:"not_after"`
}

type SVIDResponse struct {
	ID         string    `json:"id"`
	WorkloadID string    `json:"workload_id"`
	SPIFFEID   string    `json:"spiffe_id"`
	X509SVID   string    `json:"x509_svid"`
	PrivateKey string    `json:"private_key"`
	Bundle     string    `json:"bundle"`
	ExpiresAt  time.Time `json:"expires_at"`
	IssuedAt   time.Time `json:"issued_at"`
}

// Implementation of helper methods...
func (s *SpiffeSDK) initWorkloadAPI() error {
	// Connect to SPIRE Agent Workload API socket
	// This will fail if:
	// 1. SPIRE Agent is not running
	// 2. Workload is not registered in SPIRE Server
	// 3. Socket path is incorrect

	ctx, cancel := context.WithTimeout(s.ctx, 10*time.Second)
	defer cancel()

	source, err := workloadapi.NewX509Source(
		ctx,
		workloadapi.WithClientOptions(
			workloadapi.WithAddr("unix://"+s.config.SocketPath),
		),
	)
	if err != nil {
		return fmt.Errorf("failed to connect to SPIRE Agent socket: %w", err)
	}

	s.workloadAPI = source
	return nil
}

func (s *SpiffeSDK) setupTLSConfig() error {
	// Create SPIFFE-aware TLS config
	s.tlsConfig = tlsconfig.MTLSClientConfig(s.workloadAPI, s.workloadAPI, tlsconfig.AuthorizeAny())
	return nil
}

func (s *SpiffeSDK) certToPEM(cert *x509.Certificate) string {
	// Convert x509.Certificate to PEM format
	certPEM := &pem.Block{
		Type:  "CERTIFICATE",
		Bytes: cert.Raw,
	}
	return string(pem.EncodeToMemory(certPEM))
}

// HeadlessAPI methods (optional - for certificate verification only)

func (api *HeadlessAPI) VerifyCertificate(payload map[string]string) (*ValidationResult, error) {
	if api == nil {
		return nil, fmt.Errorf("headless API not configured")
	}
	jsonData, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", api.BaseURL+"/spiresvc/api/v1/verify/certificate", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := api.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	var result ValidationResult
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode verification response: %w", err)
	}

	return &result, nil
}

// Close cleans up resources
func (s *SpiffeSDK) Close() error {
	s.cancel()
	if s.workloadAPI != nil {
		return s.workloadAPI.Close()
	}
	return nil
}