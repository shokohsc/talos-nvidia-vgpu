package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDLSInsecureSkipVerifyDisabledByDefault(t *testing.T) {
	t.Setenv(insecureSkipVerifyEnv, "")
	if dlsInsecureSkipVerifyEnabled() {
		t.Fatal("TLS verification bypass must be disabled by default")
	}
}

func TestDLSInsecureSkipVerifyRequiresTrue(t *testing.T) {
	for _, value := range []string{"false", "1", "yes", "TRUE "} {
		t.Setenv(insecureSkipVerifyEnv, value)
		if got := dlsInsecureSkipVerifyEnabled(); got != (value == "TRUE ") {
			t.Fatalf("unexpected result for %q: got %v", value, got)
		}
	}
}

func TestLoadRootCAsAppendsConfiguredBundle(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate test CA key: %v", err)
	}
	template := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("create test CA certificate: %v", err)
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatalf("parse test CA certificate: %v", err)
	}

	bundlePath := filepath.Join(t.TempDir(), "custom-ca.pem")
	if err := os.WriteFile(bundlePath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0600); err != nil {
		t.Fatalf("write test CA bundle: %v", err)
	}
	t.Setenv("NVIDIA_DLS_CA_BUNDLE", bundlePath)

	roots, err := loadRootCAs()
	if err != nil {
		t.Fatalf("load root CAs: %v", err)
	}
	if _, err := cert.Verify(x509.VerifyOptions{Roots: roots}); err != nil {
		t.Fatalf("custom CA was not added to root pool: %v", err)
	}
}

func TestLoadRootCAsRejectsMissingBundle(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing-ca.pem")
	t.Setenv("NVIDIA_DLS_CA_BUNDLE", missing)

	if _, err := loadRootCAs(); err == nil {
		t.Fatal("expected missing CA bundle to return an error")
	}
}

func TestLoadRootCAsRejectsInvalidBundle(t *testing.T) {
	bundlePath := filepath.Join(t.TempDir(), "invalid-ca.pem")
	if err := os.WriteFile(bundlePath, []byte("not a PEM certificate"), 0600); err != nil {
		t.Fatalf("write invalid CA bundle: %v", err)
	}
	t.Setenv("NVIDIA_DLS_CA_BUNDLE", bundlePath)

	if _, err := loadRootCAs(); err == nil {
		t.Fatal("expected invalid CA bundle to return an error")
	}
}
