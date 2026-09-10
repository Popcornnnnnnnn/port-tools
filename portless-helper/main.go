package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

const (
	healthHost      = "port-tools.localhost"
	healthPath      = "/__port_tools/health"
	defaultListenV4 = "127.0.0.1:80"
	defaultListenV6 = "[::1]:80"
	defaultTarget   = "http://127.0.0.1:17890"
)

var version = "development"

func normalizedHost(value string) string {
	host := value
	if parsedHost, _, err := net.SplitHostPort(value); err == nil {
		host = parsedHost
	}
	return strings.TrimSuffix(strings.ToLower(host), ".")
}

func newPortlessHandler(target *url.URL) http.Handler {
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.FlushInterval = -1
	originalDirector := proxy.Director
	proxy.Director = func(request *http.Request) {
		originalHost := request.Host
		originalDirector(request)
		request.Host = originalHost
	}
	proxy.ErrorHandler = func(response http.ResponseWriter, _ *http.Request, err error) {
		http.Error(response, fmt.Sprintf("Port Tools is not available on %s: %s", target.Host, err), http.StatusBadGateway)
	}
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if normalizedHost(request.Host) == healthHost && request.URL.Path == healthPath {
			response.Header().Set("Cache-Control", "no-store")
			response.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(response).Encode(map[string]any{
				"schemaVersion": 1,
				"service":       "port-tools-portless-helper",
				"status":        "ok",
				"version":       version,
			})
			return
		}
		proxy.ServeHTTP(response, request)
	})
}

func listen(address, network string) (net.Listener, error) {
	listener, err := net.Listen(network, address)
	if err != nil {
		return nil, fmt.Errorf("listen on %s: %w", address, err)
	}
	return listener, nil
}

func run(listenV4, listenV6 string, target *url.URL) error {
	listeners := make([]net.Listener, 0, 2)
	if listenV4 != "" {
		listener, err := listen(listenV4, "tcp4")
		if err != nil {
			return err
		}
		listeners = append(listeners, listener)
	}
	if listenV6 != "" {
		listener, err := listen(listenV6, "tcp6")
		if err != nil {
			for _, active := range listeners {
				_ = active.Close()
			}
			return err
		}
		listeners = append(listeners, listener)
	}
	if len(listeners) == 0 {
		return fmt.Errorf("at least one loopback listener is required")
	}

	handler := newPortlessHandler(target)
	servers := make([]*http.Server, 0, len(listeners))
	errorsChannel := make(chan error, len(listeners))
	for _, listener := range listeners {
		server := &http.Server{
			Handler:           handler,
			ReadHeaderTimeout: 5 * time.Second,
			IdleTimeout:       90 * time.Second,
		}
		servers = append(servers, server)
		go func(server *http.Server, listener net.Listener) {
			errorsChannel <- server.Serve(listener)
		}(server, listener)
	}

	interrupts := make(chan os.Signal, 1)
	signal.Notify(interrupts, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(interrupts)
	select {
	case <-interrupts:
	case err := <-errorsChannel:
		if err != nil && err != http.ErrServerClosed {
			return err
		}
	}

	shutdownContext, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	for _, server := range servers {
		_ = server.Shutdown(shutdownContext)
	}
	return nil
}

func main() {
	listenV4 := flag.String("listen-v4", defaultListenV4, "IPv4 loopback address")
	listenV6 := flag.String("listen-v6", defaultListenV6, "IPv6 loopback address")
	targetValue := flag.String("target", defaultTarget, "fixed Port Tools route proxy")
	selfTest := flag.Bool("self-test", false, "print build identity and exit")
	flag.Parse()
	if *selfTest {
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{
			"schemaVersion": 1,
			"service":       "port-tools-portless-helper",
			"version":       version,
		})
		return
	}
	if os.Getenv("PORT_TOOLS_PORTLESS_TEST_MODE") != "1" &&
		(*listenV4 != defaultListenV4 || *listenV6 != defaultListenV6 || *targetValue != defaultTarget) {
		log.Fatal("custom helper endpoints are available only in test mode")
	}
	target, err := url.Parse(*targetValue)
	if err != nil || target.Scheme != "http" || !net.ParseIP(target.Hostname()).IsLoopback() {
		log.Fatalf("invalid target %q", *targetValue)
	}
	if err := run(*listenV4, *listenV6, target); err != nil {
		log.Fatal(err)
	}
}
