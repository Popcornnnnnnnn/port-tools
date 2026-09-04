package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
)

var version = "architecture-spike"

type capabilities struct {
	SchemaVersion int      `json:"schemaVersion"`
	Version       string   `json:"version"`
	Runtime       string   `json:"runtime"`
	APIVersions   []string `json:"apiVersions"`
	Implemented   []string `json:"implementedCapabilities"`
	ProxyEngine   string   `json:"selectedProxyEngine"`
	Privileges    string   `json:"privileges"`
}

func currentCapabilities() capabilities {
	return capabilities{
		SchemaVersion: 1,
		Version:       version,
		Runtime:       "self-contained-go-binary",
		APIVersions:   []string{"v1"},
		Implemented:   []string{"health", "capabilities"},
		ProxyEngine:   "net/http/httputil.ReverseProxy",
		Privileges:    "current-user-unprivileged",
	}
}

func writeJSON(response http.ResponseWriter, value any) {
	response.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(response).Encode(value); err != nil {
		http.Error(response, err.Error(), http.StatusInternalServerError)
	}
}

func main() {
	selfTest := flag.Bool("self-test", false, "print bundled-core capabilities and exit")
	socketPath := flag.String("socket", "", "serve the v1 API on this Unix socket")
	flag.Parse()

	if *selfTest {
		write := json.NewEncoder(os.Stdout)
		if err := write.Encode(currentCapabilities()); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if *socketPath == "" {
		fmt.Fprintln(os.Stderr, "choose --self-test or provide --socket")
		os.Exit(2)
	}

	if err := os.Remove(*socketPath); err != nil && !os.IsNotExist(err) {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	listener, err := net.Listen("unix", *socketPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer listener.Close()
	defer os.Remove(*socketPath)
	if err := os.Chmod(*socketPath, 0o600); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, map[string]any{"status": "ok", "schemaVersion": 1})
	})
	mux.HandleFunc("GET /v1/capabilities", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, currentCapabilities())
	})
	server := &http.Server{Handler: mux}
	stopping := make(chan os.Signal, 1)
	signal.Notify(stopping, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stopping
		server.Close()
	}()
	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
