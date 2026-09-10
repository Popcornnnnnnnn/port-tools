package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"
)

func usage() {
	fmt.Fprintln(os.Stderr, "usage: port-tools-core <serve|request|watch|scan|self-test> [options]")
}

func unixTransport(socketPath string) *http.Transport {
	return &http.Transport{
		DialContext: func(contextValue context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{Timeout: 2 * time.Second}).DialContext(contextValue, "unix", socketPath)
		},
	}
}

func requestUnix(socketPath, method, path, body string) ([]byte, int, error) {
	transport := unixTransport(socketPath)
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 8 * time.Second}
	request, err := http.NewRequest(method, "http://port-tools"+path, bytes.NewBufferString(body))
	if err != nil {
		return nil, 0, err
	}
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := client.Do(request)
	if err != nil {
		return nil, 0, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 16*1024*1024))
	return data, response.StatusCode, err
}

func watchUnix(socketPath string) error {
	transport := unixTransport(socketPath)
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport}
	request, _ := http.NewRequest(http.MethodGet, "http://port-tools/v1/events", nil)
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("watch failed with status %d", response.StatusCode)
	}
	_, err = io.Copy(os.Stdout, response.Body)
	return err
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "self-test":
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{
			"schemaVersion": 1,
			"version":       version,
			"runtime":       "self-contained-go-binary",
			"capabilities":  []string{"services", "events", "preferences", "routes", "reverse-proxy", "portless-public-urls", "safe-stop", "force-stop"},
		})
	case "scan":
		document, err := scanServices()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		_ = json.NewEncoder(os.Stdout).Encode(document)
	case "serve":
		flags := flag.NewFlagSet("serve", flag.ExitOnError)
		socketPath := flags.String("socket", "", "private Unix socket path")
		statePath := flags.String("state", "", "route state path")
		proxyAddress := flags.String("proxy", "127.0.0.1:17890", "loopback route proxy address")
		parentPID := flags.Int("parent-pid", 0, "exit when this parent process exits")
		instanceToken := flags.String("instance-token", "", "opaque owner instance token")
		_ = flags.Parse(os.Args[2:])
		if *socketPath == "" || *statePath == "" {
			fmt.Fprintln(os.Stderr, "serve requires --socket and --state")
			os.Exit(2)
		}
		if err := serveCore(*socketPath, *statePath, *proxyAddress, *parentPID, *instanceToken); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "request":
		flags := flag.NewFlagSet("request", flag.ExitOnError)
		socketPath := flags.String("socket", "", "private Unix socket path")
		method := flags.String("method", http.MethodGet, "HTTP method")
		path := flags.String("path", "/v1/health", "API path")
		body := flags.String("body", "", "JSON request body")
		_ = flags.Parse(os.Args[2:])
		if *socketPath == "" {
			fmt.Fprintln(os.Stderr, "request requires --socket")
			os.Exit(2)
		}
		data, status, err := requestUnix(*socketPath, *method, *path, *body)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		_, _ = os.Stdout.Write(data)
		if status < 200 || status >= 300 {
			fmt.Fprintln(os.Stderr, "request failed with status "+strconv.Itoa(status))
			os.Exit(1)
		}
	case "watch":
		flags := flag.NewFlagSet("watch", flag.ExitOnError)
		socketPath := flags.String("socket", "", "private Unix socket path")
		_ = flags.Parse(os.Args[2:])
		if *socketPath == "" {
			fmt.Fprintln(os.Stderr, "watch requires --socket")
			os.Exit(2)
		}
		if err := watchUnix(*socketPath); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	default:
		usage()
		os.Exit(2)
	}
}
