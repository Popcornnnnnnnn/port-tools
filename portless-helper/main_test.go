package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestHealthEndpointIdentifiesHelper(t *testing.T) {
	target, _ := url.Parse("http://127.0.0.1:1")
	request := httptest.NewRequest(http.MethodGet, "http://port-tools.localhost"+healthPath, nil)
	response := httptest.NewRecorder()
	newPortlessHandler(target).ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("health response = %d headers=%v", response.Code, response.Header())
	}
	if body := response.Body.String(); body == "" || body[0] != '{' {
		t.Fatalf("health body = %q", body)
	}
}

func TestProxyPreservesPublicHost(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		_, _ = io.WriteString(response, request.Host+" "+request.URL.Path)
	}))
	defer upstream.Close()
	target, _ := url.Parse(upstream.URL)
	request := httptest.NewRequest(http.MethodGet, "http://demo.localhost/example", nil)
	request.Host = "demo.localhost"
	response := httptest.NewRecorder()
	newPortlessHandler(target).ServeHTTP(response, request)
	if response.Code != http.StatusOK || response.Body.String() != "demo.localhost /example" {
		t.Fatalf("proxy response = %d %q", response.Code, response.Body.String())
	}
}

func TestHealthEndpointDoesNotInterceptOtherHosts(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.WriteHeader(http.StatusNoContent)
	}))
	defer upstream.Close()
	target, _ := url.Parse(upstream.URL)
	request := httptest.NewRequest(http.MethodGet, "http://demo.localhost"+healthPath, nil)
	request.Host = "demo.localhost"
	response := httptest.NewRecorder()
	newPortlessHandler(target).ServeHTTP(response, request)
	if response.Code != http.StatusNoContent {
		t.Fatalf("non-health host response = %d", response.Code)
	}
}
