package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var version = "development"

type coreServer struct {
	routes *routeManager
}

func writeJSON(response http.ResponseWriter, status int, value any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(value)
}

func writeError(response http.ResponseWriter, status int, err error) {
	writeJSON(response, status, map[string]any{"error": err.Error(), "status": status})
}

func (server *coreServer) apiHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, map[string]any{"status": "ok", "schemaVersion": 1})
	})
	mux.HandleFunc("GET /v1/capabilities", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, map[string]any{
			"schemaVersion":           1,
			"version":                 version,
			"runtime":                 "self-contained-go-binary",
			"apiVersions":             []string{"v1"},
			"implementedCapabilities": []string{"health", "services", "routes", "reverse-proxy"},
			"selectedProxyEngine":     "net/http/httputil.ReverseProxy",
			"privileges":              "current-user-unprivileged",
		})
	})
	mux.HandleFunc("GET /v1/services", func(response http.ResponseWriter, _ *http.Request) {
		document, err := scanServices()
		if err != nil {
			writeError(response, http.StatusInternalServerError, err)
			return
		}
		server.routes.attach(&document)
		writeJSON(response, http.StatusOK, document)
	})
	mux.HandleFunc("GET /v1/routes", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, map[string]any{"schemaVersion": 1, "routes": server.routes.list()})
	})
	mux.HandleFunc("PUT /v1/routes/{alias}", func(response http.ResponseWriter, request *http.Request) {
		var mutation struct {
			RouteRecord
			PreviousAlias string `json:"previousAlias,omitempty"`
		}
		if err := json.NewDecoder(io.LimitReader(request.Body, 64*1024)).Decode(&mutation); err != nil {
			writeError(response, http.StatusBadRequest, fmt.Errorf("invalid route: %w", err))
			return
		}
		route, err := server.routes.put(request.PathValue("alias"), mutation.RouteRecord, mutation.PreviousAlias)
		if err != nil {
			writeError(response, http.StatusConflict, err)
			return
		}
		writeJSON(response, http.StatusOK, route)
	})
	mux.HandleFunc("DELETE /v1/routes/{alias}", func(response http.ResponseWriter, request *http.Request) {
		if err := server.routes.remove(request.PathValue("alias")); err != nil {
			writeError(response, http.StatusNotFound, err)
			return
		}
		writeJSON(response, http.StatusOK, map[string]any{"alias": request.PathValue("alias"), "removed": true})
	})
	return mux
}

func aliasFromHost(value string) string {
	host := value
	if parsedHost, _, err := net.SplitHostPort(value); err == nil {
		host = parsedHost
	}
	host = strings.TrimSuffix(strings.ToLower(host), ".")
	if !strings.HasSuffix(host, ".localhost") {
		return ""
	}
	alias := strings.TrimSuffix(host, ".localhost")
	if strings.Contains(alias, ".") {
		return ""
	}
	return alias
}

var diagnosticPage = template.Must(template.New("diagnostic").Parse(`<!doctype html>
<html><head><meta charset="utf-8"><title>{{.Title}}</title>
<style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;max-width:620px;margin:12vh auto;padding:0 24px;color:#202124}code{background:#f2f3f5;padding:2px 5px;border-radius:5px}p{line-height:1.55;color:#5f6368}</style></head>
<body><h1>{{.Title}}</h1><p>{{.Message}}</p><p>Port Tools kept the local name; start the upstream service and reload this page.</p></body></html>`))

func diagnostic(response http.ResponseWriter, status int, title, message string) {
	response.Header().Set("Content-Type", "text/html; charset=utf-8")
	response.WriteHeader(status)
	_ = diagnosticPage.Execute(response, map[string]string{"Title": title, "Message": message})
}

func (server *coreServer) proxyHandler() http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		alias := aliasFromHost(request.Host)
		if alias == "" {
			diagnostic(response, http.StatusNotFound, "Unknown local name", "Use an <alias>.localhost address created by Port Tools.")
			return
		}
		route, ok := server.routes.get(alias)
		if !ok {
			diagnostic(response, http.StatusNotFound, "Alias not configured", fmt.Sprintf("%s.localhost has no saved route.", alias))
			return
		}
		target, _ := url.Parse(fmt.Sprintf("%s://127.0.0.1:%d", route.Scheme, route.Port))
		proxy := httputil.NewSingleHostReverseProxy(target)
		proxy.FlushInterval = -1
		originalDirector := proxy.Director
		proxy.Director = func(upstream *http.Request) {
			originalHost := upstream.Host
			originalDirector(upstream)
			if route.HostMode == "preserve" {
				upstream.Host = originalHost
			} else {
				upstream.Host = target.Host
			}
			upstream.Header.Set("X-Forwarded-Host", originalHost)
		}
		proxy.Transport = &http.Transport{
			Proxy:             http.ProxyFromEnvironment,
			DialContext:       (&net.Dialer{Timeout: 2 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
			ForceAttemptHTTP2: true,
			TLSClientConfig:   &tls.Config{InsecureSkipVerify: route.TLSPolicy == "insecure-local", MinVersion: tls.VersionTLS12},
		}
		proxy.ErrorHandler = func(response http.ResponseWriter, _ *http.Request, err error) {
			diagnostic(response, http.StatusBadGateway, "Local app unavailable", fmt.Sprintf("%s.localhost points to 127.0.0.1:%d (%s).", alias, route.Port, err.Error()))
		}
		proxy.ServeHTTP(response, request)
	})
}

func serveCore(socketPath, statePath, proxyAddress string, parentPID int) error {
	if err := os.MkdirAll(filepathDir(socketPath), 0o700); err != nil {
		return err
	}
	_ = os.Remove(socketPath)
	apiListener, err := net.Listen("unix", socketPath)
	if err != nil {
		return err
	}
	defer apiListener.Close()
	defer os.Remove(socketPath)
	if err := os.Chmod(socketPath, 0o600); err != nil {
		return err
	}

	proxyListener, err := net.Listen("tcp4", proxyAddress)
	if err != nil {
		return fmt.Errorf("start local route proxy: %w", err)
	}
	defer proxyListener.Close()
	proxyPort := proxyListener.Addr().(*net.TCPAddr).Port
	proxyListeners := []net.Listener{proxyListener}
	if host, _, splitError := net.SplitHostPort(proxyAddress); splitError == nil && host == "127.0.0.1" {
		ipv6Listener, ipv6Error := net.Listen("tcp6", fmt.Sprintf("[::1]:%d", proxyPort))
		if ipv6Error != nil {
			return fmt.Errorf("start IPv6 loopback route proxy: %w", ipv6Error)
		}
		defer ipv6Listener.Close()
		proxyListeners = append(proxyListeners, ipv6Listener)
	}
	routes, err := newRouteManager(statePath, proxyPort)
	if err != nil {
		return err
	}
	server := &coreServer{routes: routes}
	apiHTTP := &http.Server{Handler: server.apiHandler()}
	proxyHTTP := &http.Server{Handler: server.proxyHandler()}
	contextValue, cancel := context.WithCancel(context.Background())
	defer cancel()
	interrupts := make(chan os.Signal, 1)
	signal.Notify(interrupts, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(interrupts)
	go func() {
		select {
		case <-contextValue.Done():
		case <-interrupts:
			cancel()
		}
	}()
	if parentPID > 1 {
		go monitorParentPortable(contextValue, parentPID, cancel)
	}
	errorsChannel := make(chan error, 1+len(proxyListeners))
	go func() { errorsChannel <- apiHTTP.Serve(apiListener) }()
	for _, listener := range proxyListeners {
		listener := listener
		go func() { errorsChannel <- proxyHTTP.Serve(listener) }()
	}
	select {
	case <-contextValue.Done():
	case err := <-errorsChannel:
		if err != nil && err != http.ErrServerClosed {
			cancel()
			return err
		}
	}
	shutdownContext, shutdownCancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer shutdownCancel()
	_ = apiHTTP.Shutdown(shutdownContext)
	_ = proxyHTTP.Shutdown(shutdownContext)
	return nil
}

func filepathDir(path string) string {
	index := strings.LastIndex(path, string(os.PathSeparator))
	if index <= 0 {
		return "."
	}
	return path[:index]
}

func monitorParentPortable(contextValue context.Context, parentPID int, cancel context.CancelFunc) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-contextValue.Done():
			return
		case <-ticker.C:
			output := runText("/bin/ps", "-p", strconv.Itoa(parentPID), "-o", "pid=")
			if strings.TrimSpace(output) == "" {
				cancel()
				return
			}
		}
	}
}
