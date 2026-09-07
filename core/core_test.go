package main

import (
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseEndpoint(t *testing.T) {
	tests := []struct {
		input   string
		address string
		port    int
		scope   string
	}{
		{"127.0.0.1:4317", "127.0.0.1", 4317, "loopback"},
		{"*:4319", "*", 4319, "all-interfaces"},
		{"[::1]:8080", "::1", 8080, "loopback"},
	}
	for _, test := range tests {
		address, port, scope, ok := parseEndpoint(test.input)
		if !ok || address != test.address || port != test.port || scope != test.scope {
			t.Fatalf("parseEndpoint(%q) = %q, %d, %q, %v", test.input, address, port, scope, ok)
		}
	}
	if _, _, _, ok := parseEndpoint("not-an-endpoint"); ok {
		t.Fatal("invalid endpoint was accepted")
	}
}

func TestPresentationRoleSeparatesPagesFromHTTPServices(t *testing.T) {
	htmlType := "text/html; charset=utf-8"
	jsonType := "application/json"
	ok := 200
	redirect := 302
	notFound := 404
	title := "Demo"
	if role := presentationRole(&HTTPRecord{Status: &ok, ContentType: &htmlType}, nil); role != "page" {
		t.Fatalf("HTML 200 role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &ok, ContentType: &jsonType}, nil); role != "service" {
		t.Fatalf("JSON 200 role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &redirect}, nil); role != "page" {
		t.Fatalf("redirect role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &notFound, Title: &title}, pointer("vite")); role != "service" {
		t.Fatalf("404 role = %q", role)
	}
}

func TestProjectAndApplicationWithoutGitExecutable(t *testing.T) {
	root := t.TempDir()
	gitDirectory := filepath.Join(root, ".git")
	if err := os.MkdirAll(filepath.Join(gitDirectory, "refs", "heads"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gitDirectory, "HEAD"), []byte("ref: refs/heads/main\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gitDirectory, "config"), []byte("[remote \"origin\"]\n\turl = https://secret@example.com/team/demo.git\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	appRoot := filepath.Join(root, "apps", "web")
	if err := os.MkdirAll(appRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(appRoot, "package.json"), []byte(`{"name":"workspace-web"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	project := findProject(appRoot)
	if project == nil || project.Root != root || project.Branch == nil || *project.Branch != "main" {
		t.Fatalf("unexpected project: %#v", project)
	}
	if project.RemoteURL == nil || strings.Contains(*project.RemoteURL, "secret@") {
		t.Fatalf("remote credentials were not sanitized: %#v", project.RemoteURL)
	}
	application := findApplication(appRoot, "npm run dev", root)
	if application == nil || application.Name != "workspace-web" || application.RelativePath != filepath.Join("apps", "web") {
		t.Fatalf("unexpected application: %#v", application)
	}
}

func TestRoutePersistenceAndCollision(t *testing.T) {
	statePath := filepath.Join(t.TempDir(), "routes.json")
	manager, err := newRouteManager(statePath, 17890)
	if err != nil {
		t.Fatal(err)
	}
	created, err := manager.put("Demo-App", RouteRecord{Port: 4317, ProjectRoot: "/project", ApplicationRoot: "/project"})
	if err != nil {
		t.Fatal(err)
	}
	if created.Alias != "demo-app" || created.URL != "http://demo-app.localhost:17890" {
		t.Fatalf("unexpected route: %#v", created)
	}
	if _, err := manager.put("demo-app", RouteRecord{Port: 9000, ProjectRoot: "/other"}); err == nil {
		t.Fatal("route collision was accepted")
	}
	renamed, err := manager.put("renamed-app", RouteRecord{Port: 4317, ProjectRoot: "/project", ApplicationRoot: "/project"}, "demo-app")
	if err != nil || renamed.Alias != "renamed-app" {
		t.Fatalf("route rename failed: route=%#v err=%v", renamed, err)
	}
	if _, exists := manager.get("demo-app"); exists {
		t.Fatal("old alias remained after rename")
	}
	reloaded, err := newRouteManager(statePath, 17890)
	if err != nil || len(reloaded.list()) != 1 {
		t.Fatalf("route did not persist: routes=%#v err=%v", reloaded.list(), err)
	}
	info, err := os.Stat(statePath)
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("route state permissions = %v, err=%v", info.Mode().Perm(), err)
	}
}

func TestRemoveSocketIfOwnedDoesNotRemoveReplacement(t *testing.T) {
	temporaryRoot, err := os.MkdirTemp("/tmp", "pt-socket-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(temporaryRoot) })
	socketPath := filepath.Join(temporaryRoot, "core.sock")
	first, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	first.(*net.UnixListener).SetUnlinkOnClose(false)
	firstInfo, err := os.Stat(socketPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := first.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(socketPath); err != nil {
		t.Fatal(err)
	}
	replacement, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	replacement.(*net.UnixListener).SetUnlinkOnClose(false)
	defer replacement.Close()

	removeSocketIfOwned(socketPath, firstInfo)
	if _, err := os.Stat(socketPath); err != nil {
		t.Fatalf("replacement socket was removed: %v", err)
	}
	replacementInfo, err := os.Stat(socketPath)
	if err != nil {
		t.Fatal(err)
	}
	removeSocketIfOwned(socketPath, replacementInfo)
	if _, err := os.Stat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("owned socket still exists: %v", err)
	}
}

func TestReverseProxyAndMissingUpstreamDiagnostic(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("Content-Type", "text/plain")
		_, _ = io.WriteString(response, "proxied "+request.URL.Path)
	}))
	defer upstream.Close()
	_, rawPort, _ := net.SplitHostPort(strings.TrimPrefix(upstream.URL, "http://"))
	port, _ := net.LookupPort("tcp", rawPort)

	manager, err := newRouteManager(filepath.Join(t.TempDir(), "routes.json"), 17890)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.put("demo", RouteRecord{Port: port}); err != nil {
		t.Fatal(err)
	}
	proxy := httptest.NewServer((&coreServer{routes: manager}).proxyHandler())
	defer proxy.Close()
	request, _ := http.NewRequest(http.MethodGet, proxy.URL+"/hello", nil)
	request.Host = "demo.localhost:17890"
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusOK || string(body) != "proxied /hello" {
		t.Fatalf("proxy response = %d %q", response.StatusCode, body)
	}

	if _, err := manager.put("missing", RouteRecord{Port: 1}); err != nil {
		t.Fatal(err)
	}
	request, _ = http.NewRequest(http.MethodGet, proxy.URL, nil)
	request.Host = "missing.localhost:17890"
	response, err = http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	body, _ = io.ReadAll(response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusBadGateway || !strings.Contains(string(body), "Local app unavailable") {
		t.Fatalf("missing-upstream response = %d %q", response.StatusCode, body)
	}
}
