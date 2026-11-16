// nvidia-dls-token-fetcher retrieves a FastAPI-DLS NVIDIA NLS client token.
package main

import (
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	baseURL := flag.String("url", "https://dls.home.arpa", "FastAPI-DLS HTTPS base URL")
	output := flag.String("output", "/etc/nvidia/ClientConfigToken/client_configuration_token.tok", "token output path")
	flag.Parse()

	parsed, err := url.Parse(strings.TrimRight(*baseURL, "/"))
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil {
		fatal("DLS URL must be a valid HTTPS URL without embedded credentials")
	}
	parsed.Path = strings.TrimRight(parsed.Path, "/") + "/-/client-token"
	parsed.RawQuery = ""
	parsed.Fragment = ""

	roots, err := loadRootCAs()
	if err != nil {
		fatal("configure TLS root CAs: %v", err)
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.TLSClientConfig = &tls.Config{
		RootCAs:    roots,
		MinVersion: tls.VersionTLS12,
	}

	client := &http.Client{
		Transport: transport,
		Timeout:   30 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if req.URL.Scheme != "https" {
				return fmt.Errorf("refusing redirect to non-HTTPS URL")
			}
			if len(via) >= 5 {
				return fmt.Errorf("too many redirects")
			}
			return nil
		},
	}
	req, err := http.NewRequest(http.MethodGet, parsed.String(), nil)
	if err != nil {
		fatal("create token request: %v", err)
	}
	req.Header.Set("Accept", "application/octet-stream, text/plain")
	req.Header.Set("User-Agent", "talos-nvidia-vgpu/1.0")

	resp, err := client.Do(req)
	if err != nil {
		fatal("retrieve token from %s: %v", parsed.Redacted(), err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fatal("token endpoint returned HTTP %s", resp.Status)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20+1))
	if err != nil {
		fatal("read token response: %v", err)
	}
	if len(body) == 0 || len(body) > 1<<20 || strings.TrimSpace(string(body)) == "" {
		fatal("token endpoint returned an empty or oversized response")
	}

	if err := os.MkdirAll(filepath.Dir(*output), 0700); err != nil {
		fatal("create token directory: %v", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(*output), ".client-token-*")
	if err != nil {
		fatal("create temporary token file: %v", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(0700); err != nil {
		tmp.Close()
		fatal("secure temporary token file: %v", err)
	}
	if _, err := tmp.Write(body); err != nil {
		tmp.Close()
		fatal("write token: %v", err)
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		fatal("sync token: %v", err)
	}
	if err := tmp.Close(); err != nil {
		fatal("close token: %v", err)
	}
	if err := os.Rename(tmpName, *output); err != nil {
		fatal("install token atomically: %v", err)
	}
	fmt.Printf("Retrieved NVIDIA client token from %s\n", parsed.Redacted())
}

const defaultCABundlePath = "/etc/ssl/certs/ca-certificates.crt"

// loadRootCAs preserves Go's system roots and explicitly appends the Talos
// trust bundle. This avoids relying on implicit CA discovery inside the
// isolated extension-service container.
func loadRootCAs() (*x509.CertPool, error) {
	roots, err := x509.SystemCertPool()
	if err != nil || roots == nil {
		// The mounted Talos bundle below is a complete CA bundle on this
		// platform, so it can also serve as the fallback when Go cannot
		// discover a system pool inside the service container.
		roots = x509.NewCertPool()
	}

	bundlePath := strings.TrimSpace(os.Getenv("NVIDIA_DLS_CA_BUNDLE"))
	if bundlePath == "" {
		bundlePath = defaultCABundlePath
	}
	caPEM, err := os.ReadFile(bundlePath)
	if err != nil {
		return nil, fmt.Errorf("read CA bundle %q: %w", bundlePath, err)
	}
	if ok := roots.AppendCertsFromPEM(caPEM); !ok {
		return nil, fmt.Errorf("CA bundle %q contains no valid PEM certificates", bundlePath)
	}
	return roots, nil
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "nvidia-dls-token-fetcher: "+format+"\n", args...)
	os.Exit(1)
}
