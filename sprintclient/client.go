package sprintclient

import (
    "crypto/tls"
    "net"
    "net/http"
    "time"
)

// SprintClient is a lightweight HTTP client placeholder.
type SprintClient struct {
    sprintURL string
    coreURL   string
    rpcUser   string
    rpcPass   string
    client    *http.Client
}

// NewSprintClient returns a new client with reasonable defaults.
func NewSprintClient(sprintURL, coreURL, rpcUser, rpcPass string) *SprintClient {
    transport := &http.Transport{
        Proxy: http.ProxyFromEnvironment,
        DialContext: (&net.Dialer{
            Timeout:   30 * time.Second,
            KeepAlive: 30 * time.Second,
        }).DialContext,
        ForceAttemptHTTP2:   true,
        MaxIdleConns:        100,
        IdleConnTimeout:     90 * time.Second,
        TLSHandshakeTimeout: 10 * time.Second,
        TLSClientConfig: &tls.Config{
            MinVersion: tls.VersionTLS12,
        },
    }

    return &SprintClient{
        sprintURL: sprintURL,
        coreURL:   coreURL,
        rpcUser:   rpcUser,
        rpcPass:   rpcPass,
        client: &http.Client{
            Timeout:   10 * time.Second,
            Transport: transport,
        },
    }
}
package sprintclient

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"time"
)

// SprintClient handles both Sprint API and Core RPC as fallback
type SprintClient struct {
	sprintURL string
	coreURL   string
	rpcUser   string
	package sprintclient

	import (
		"crypto/tls"
		"net"
		"net/http"
		"time"
	)

	// SprintClient is a lightweight HTTP client for Sprint/Core endpoints.
	type SprintClient struct {
		sprintURL string
		coreURL   string
		rpcUser   string
		rpcPass   string
		client    *http.Client
	}

	// NewSprintClient returns a new client with reasonable defaults.
	func NewSprintClient(sprintURL, coreURL, rpcUser, rpcPass string) *SprintClient {
		transport := &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			DialContext: (&net.Dialer{
				Timeout:   30 * time.Second,
				KeepAlive: 30 * time.Second,
			}).DialContext,
			ForceAttemptHTTP2:   true,
			MaxIdleConns:        100,
			IdleConnTimeout:     90 * time.Second,
			TLSHandshakeTimeout: 10 * time.Second,
			TLSClientConfig: &tls.Config{
				MinVersion: tls.VersionTLS12,
			},
		}

		return &SprintClient{
			sprintURL: sprintURL,
			coreURL:   coreURL,
			rpcUser:   rpcUser,
			rpcPass:   rpcPass,
			client: &http.Client{
				Timeout:   10 * time.Second,
				Transport: transport,
			},
		}
	}
