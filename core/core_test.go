package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func makeGitFixture(t *testing.T, root string) string {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(root, ".git", "refs", "heads"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".git", "HEAD"), []byte("ref: refs/heads/main\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return root
}

func startTCPProbeFixture(t *testing.T, response func([]byte) []byte) discoveredListener {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		for {
			connection, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer connection.Close()
				buffer := make([]byte, 4096)
				count, readError := connection.Read(buffer)
				if readError == nil && count > 0 {
					_, _ = connection.Write(response(buffer[:count]))
				}
			}()
		}
	}()
	return discoveredListener{
		PID:       os.Getpid() + 1000,
		Address:   "127.0.0.1",
		Port:      listener.Addr().(*net.TCPAddr).Port,
		BindScope: "loopback",
	}
}

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
	if role := presentationRole(&HTTPRecord{Status: &ok, ContentType: &htmlType, BytesRead: 42}, nil, []byte("<main>Demo</main>"), ""); role != "page" {
		t.Fatalf("HTML 200 role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &ok, ContentType: &htmlType, BytesRead: 0}, nil, nil, ""); role != "service" {
		t.Fatalf("empty HTML 200 role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &ok, ContentType: &jsonType}, nil, nil, ""); role != "service" {
		t.Fatalf("JSON 200 role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &redirect}, nil, nil, ""); role != "page" {
		t.Fatalf("redirect role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &notFound, Title: &title}, pointer("vite"), nil, "vite"); role != "service" {
		t.Fatalf("404 role = %q", role)
	}
	unauthorized := 401
	if role := presentationRole(&HTTPRecord{Status: &unauthorized}, nil, nil, "node /opt/homebrew/bin/dsh web --no-open"); role != "page" {
		t.Fatalf("authenticated Web UI role = %q", role)
	}
	if role := presentationRole(&HTTPRecord{Status: &unauthorized}, nil, nil, "uvicorn api:app"); role != "service" {
		t.Fatalf("authenticated API role = %q", role)
	}
	forbidden := 403
	genericCommand := "global-tool web --no-open --port 9000"
	if role := presentationRole(&HTTPRecord{Status: &forbidden}, nil, nil, genericCommand); role != "page" {
		t.Fatalf("generic authenticated Web UI role = %q", role)
	}
	if relevance := classifyRelevance(ProcessRecord{Command: &genericCommand}, nil, ManagementRecord{}); !relevance.DeveloperRelevant || relevance.Category != "developer-tool" {
		t.Fatalf("generic authenticated Web UI relevance = %#v", relevance)
	}
}

func TestObserveClassifiesSwaggerUIAsService(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = io.WriteString(response, `<!doctype html><title>LiteLLM API - Swagger UI</title><div id="swagger-ui"></div><script>SwaggerUIBundle({url: '/openapi.json'})</script>`)
	}))
	t.Cleanup(server.Close)
	port := server.Listener.Addr().(*net.TCPAddr).Port
	listener := discoveredListener{PID: os.Getpid() + 1000, Address: "127.0.0.1", Port: port, BindScope: "loopback"}

	observation := observe(listener, ProcessRecord{}, ManagementRecord{Source: "unmanaged"})
	if observation.Role != "service" {
		t.Fatalf("Swagger UI role = %q", observation.Role)
	}
	if len(observation.Evidence) < 2 || observation.Evidence[1].Kind != "api-documentation-ui" || observation.Evidence[1].Value != "swagger-ui" {
		t.Fatalf("Swagger UI evidence = %#v", observation.Evidence)
	}
}

func TestObserveIdentifiesChromeDevToolsProtocol(t *testing.T) {
	var port int
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/":
			response.Header().Set("Content-Type", "text/html; charset=UTF-8")
		case "/json/version":
			response.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(response).Encode(map[string]string{
				"Browser":              "Chrome/Test",
				"Protocol-Version":     "1.3",
				"webSocketDebuggerUrl": "ws://127.0.0.1:" + strconv.Itoa(port) + "/devtools/browser/test",
			})
		case "/json/list":
			response.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(response, `[{"type":"page"}]`)
		default:
			http.NotFound(response, request)
		}
	}))
	t.Cleanup(server.Close)
	port = server.Listener.Addr().(*net.TCPAddr).Port
	listener := discoveredListener{PID: os.Getpid() + 1000, Address: "127.0.0.1", Port: port, BindScope: "loopback"}
	name := "Google Chrome"
	command := "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=" + strconv.Itoa(port)
	observation := observe(listener, ProcessRecord{Name: &name, Command: &command}, ManagementRecord{Source: "unmanaged"})
	if observation.Protocol != "cdp" || observation.Role != "service" || observation.CDP == nil {
		t.Fatalf("CDP observation = %#v", observation)
	}
	if observation.CDP.Browser != "Chrome/Test" || observation.CDP.TargetCount != 1 {
		t.Fatalf("CDP identity = %#v", observation.CDP)
	}
}

func TestObserveFindsWebUIAtConventionalPath(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/":
			response.Header().Set("Content-Type", "application/json; charset=utf-8")
			_, _ = io.WriteString(response, `{"endpoints":["POST /v1/chat/completions"],"message":"CLI Proxy API Server"}`)
		case "/management.html":
			response.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = io.WriteString(response, `<!doctype html><title>CLI Proxy API Management Center</title><div id="app"></div>`)
		default:
			http.NotFound(response, request)
		}
	}))
	t.Cleanup(server.Close)
	listener := discoveredListener{PID: os.Getpid() + 1000, Address: "127.0.0.1", Port: server.Listener.Addr().(*net.TCPAddr).Port, BindScope: "loopback"}

	observation := observe(listener, ProcessRecord{}, ManagementRecord{Source: "unmanaged"})
	if observation.Role != "page" {
		t.Fatalf("management UI role = %q", observation.Role)
	}
	if observation.HTTP == nil || observation.HTTP.Path != "/management.html" {
		t.Fatalf("management UI record = %#v", observation.HTTP)
	}
	if observation.HTTP.Title == nil || *observation.HTTP.Title != "CLI Proxy API Management Center" {
		t.Fatalf("management UI title = %#v", observation.HTTP.Title)
	}
}

func TestObserveKeepsAPIWithoutWebUIAsService(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/" {
			response.Header().Set("Content-Type", "application/json; charset=utf-8")
			_, _ = io.WriteString(response, `{"endpoints":["POST /v1/chat/completions"]}`)
			return
		}
		http.NotFound(response, request)
	}))
	t.Cleanup(server.Close)
	listener := discoveredListener{PID: os.Getpid() + 1000, Address: "127.0.0.1", Port: server.Listener.Addr().(*net.TCPAddr).Port, BindScope: "loopback"}

	observation := observe(listener, ProcessRecord{}, ManagementRecord{Source: "unmanaged"})
	if observation.Role != "service" {
		t.Fatalf("API-only role = %q", observation.Role)
	}
	if observation.HTTP == nil || observation.HTTP.Path != "" {
		t.Fatalf("API-only record = %#v", observation.HTTP)
	}
}

func TestObserveClassifiesExplicitNonHTTPResponses(t *testing.T) {
	echo := startTCPProbeFixture(t, func(data []byte) []byte { return data })
	echoObservation := observe(echo, ProcessRecord{}, ManagementRecord{})
	if echoObservation.Classification != "non-web" || echoObservation.Protocol != "tcp" {
		t.Fatalf("echo observation = %#v", echoObservation)
	}

	redis := startTCPProbeFixture(t, func([]byte) []byte {
		return []byte("-ERR unknown command 'GET', with args beginning with: '/'\r\n")
	})
	redisObservation := observe(redis, ProcessRecord{}, ManagementRecord{})
	if redisObservation.Classification != "non-web" || redisObservation.Protocol != "redis" {
		t.Fatalf("redis observation = %#v", redisObservation)
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

func TestCommandProjectCandidatesIgnoreInterpreterRepository(t *testing.T) {
	interpreterRoot := makeGitFixture(t, filepath.Join(t.TempDir(), "runtime-repository"))
	projectRoot := makeGitFixture(t, filepath.Join(t.TempDir(), "application-repository"))
	interpreter := filepath.Join(interpreterRoot, "bin", "python")
	script := filepath.Join(projectRoot, "server.py")
	if err := os.MkdirAll(filepath.Dir(interpreter), 0o700); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{interpreter, script} {
		if err := os.WriteFile(path, []byte("fixture"), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	candidates := projectCandidatesFromCommand(interpreter+" "+script+" --port 5173", "/tmp")
	if len(candidates) != 1 || candidates[projectRoot] == nil {
		t.Fatalf("candidate projects = %#v", candidates)
	}
}

func TestCommandProjectCandidatesIgnoreHomebrewRepository(t *testing.T) {
	homebrewRoot := makeGitFixture(t, filepath.Join(t.TempDir(), "homebrew"))
	if err := os.WriteFile(
		filepath.Join(homebrewRoot, ".git", "config"),
		[]byte("[remote \"origin\"]\n\turl = https://github.com/Homebrew/brew\n"),
		0o600,
	); err != nil {
		t.Fatal(err)
	}
	launcher := filepath.Join(homebrewRoot, "bin", "global-web-cli")
	if err := os.MkdirAll(filepath.Dir(launcher), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(launcher, []byte("fixture"), 0o700); err != nil {
		t.Fatal(err)
	}
	if candidates := projectCandidatesFromCommand("node "+launcher+" web --no-open", "/tmp"); len(candidates) != 0 {
		t.Fatalf("Homebrew toolchain became project evidence: %#v", candidates)
	}
}

func TestLogicalIdentitySurvivesPIDAndPortChange(t *testing.T) {
	projectRoot := makeGitFixture(t, t.TempDir())
	project := findProject(projectRoot)
	command := filepath.Join(projectRoot, "server.py") + " --port 5173"
	if err := os.WriteFile(filepath.Join(projectRoot, "server.py"), []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	process := ProcessRecord{Name: pointer("Python"), Command: &command, CWD: &projectRoot}
	first := stableLogicalID(discoveredListener{PID: 10, Port: 5173}, process, project, nil, ManagementRecord{Source: "unmanaged"})
	second := stableLogicalID(discoveredListener{PID: 20, Port: 6173}, process, project, nil, ManagementRecord{Source: "unmanaged"})
	if first != second {
		t.Fatalf("logical identity changed: %q != %q", first, second)
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

func TestRouteStateMigrationAndLogicalRebind(t *testing.T) {
	statePath := filepath.Join(t.TempDir(), "routes.json")
	legacy := `{"schemaVersion":1,"routes":{"demo":{"port":4317,"scheme":"http","hostMode":"rewrite","tlsPolicy":"verify","projectRoot":"/project"}}}`
	if err := os.WriteFile(statePath, []byte(legacy), 0o600); err != nil {
		t.Fatal(err)
	}
	manager, err := newRouteManager(statePath, 17890)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(statePath)
	var migrated routeState
	if err := json.Unmarshal(data, &migrated); err != nil || migrated.SchemaVersion != 2 {
		t.Fatalf("route migration failed: %s, %v", data, err)
	}
	if _, err := manager.put("stable", RouteRecord{Port: 5000, LogicalServiceID: "logical-1", ProjectRoot: "/project"}); err != nil {
		t.Fatal(err)
	}
	document := ScanDocument{Services: []ServiceRecord{{
		ID: "instance-2", LogicalID: "logical-1", Listener: ListenerRecord{Port: 6000},
		Project: &ProjectRecord{Root: "/project"},
	}}}
	manager.attach(&document)
	if document.Services[0].Route == nil || document.Services[0].Route.Port != 6000 {
		t.Fatalf("logical route was not rebound: %#v", document.Services[0].Route)
	}
}

func TestCorruptRouteStateIsBackedUp(t *testing.T) {
	root := t.TempDir()
	statePath := filepath.Join(root, "routes.json")
	if err := os.WriteFile(statePath, []byte("not-json"), 0o600); err != nil {
		t.Fatal(err)
	}
	manager, err := newRouteManager(statePath, 17890)
	if err != nil || len(manager.list()) != 0 {
		t.Fatalf("manager = %#v, error = %v", manager, err)
	}
	matches, err := filepath.Glob(statePath + ".corrupt-*")
	if err != nil || len(matches) != 1 {
		t.Fatalf("corrupt backup matches = %v, error = %v", matches, err)
	}
	if _, err := os.Stat(statePath); !os.IsNotExist(err) {
		t.Fatalf("invalid original route state still exists: %v", err)
	}
}

func TestInventoryPreferencesAndConservativeStaleness(t *testing.T) {
	manager, err := newInventoryStateManager(filepath.Join(t.TempDir(), "inventory.json"))
	if err != nil {
		t.Fatal(err)
	}
	parent := 42
	started := time.Now().Add(-25 * time.Hour).Format("Mon Jan 2 15:04:05 2006")
	if _, ok := parseProcessStarted(&started); !ok {
		t.Fatalf("test process start did not parse: %q", started)
	}
	document := ScanDocument{Services: []ServiceRecord{{
		ID: "instance", LogicalID: "logical", Process: ProcessRecord{ParentPID: &parent, Started: &started},
		Management: ManagementRecord{Source: "unmanaged"}, Observation: ObservationRecord{Classification: "confirmed-web"},
	}}}
	if err := manager.apply(&document); err != nil {
		t.Fatal(err)
	}
	pinned := true
	name := "Pinned app"
	if _, err := manager.updatePreferences("logical", servicePreferencesPatch{Pinned: &pinned, DisplayName: &name}); err != nil {
		t.Fatal(err)
	}
	newParent := 1
	document.Services[0].Process.ParentPID = &newParent
	if err := manager.apply(&document); err != nil {
		t.Fatal(err)
	}
	service := document.Services[0]
	if !service.Preferences.Pinned || service.Preferences.DisplayName != name || service.Staleness.PossiblyForgotten {
		t.Fatalf("unexpected persisted state: %#v", service)
	}
	unpinned := false
	empty := ""
	if _, err := manager.updatePreferences("logical", servicePreferencesPatch{Pinned: &unpinned, DisplayName: &empty}); err != nil {
		t.Fatal(err)
	}
	if err := manager.apply(&document); err != nil {
		t.Fatal(err)
	}
	if document.Services[0].Staleness.PossiblyForgotten {
		t.Fatalf("healthy old reparented service was marked possibly forgotten: %#v", document.Services[0].Staleness)
	}
	document.Services[0].Observation.Classification = "unknown"
	failedEntry := inventoryStateEntry{History: ServiceHistoryRecord{
		InitialParentPID:         &parent,
		ConsecutiveProbeFailures: 3,
		FirstFailedProbe:         time.Now().Add(-11 * time.Minute).UTC().Format(time.RFC3339Nano),
	}}
	staleness := stalenessForService(document.Services[0], failedEntry, time.Now())
	if !staleness.PossiblyForgotten {
		t.Fatalf("old detached failing service was not marked possibly forgotten: %#v", staleness)
	}
}

func TestIdleCDPIsPossiblyLeftRunning(t *testing.T) {
	parent := 1
	started := time.Now().Add(-25 * time.Hour).Format("Mon Jan 2 15:04:05 2006")
	service := ServiceRecord{
		Process:    ProcessRecord{ParentPID: &parent, Started: &started},
		Management: ManagementRecord{Source: "unmanaged"},
		Observation: ObservationRecord{
			Protocol: "cdp",
			CDP:      &CDPRecord{TargetCount: 0},
		},
	}
	entry := inventoryStateEntry{History: ServiceHistoryRecord{InitialParentPID: &parent}}
	staleness := stalenessForService(service, entry, time.Now())
	if !staleness.PossiblyForgotten || !strings.Contains(strings.Join(staleness.Reasons, "\n"), "Chrome DevTools has no active targets") {
		t.Fatalf("idle CDP staleness = %#v", staleness)
	}
	service.Observation.CDP.TargetCount = 1
	activeStaleness := stalenessForService(service, entry, time.Now())
	if activeStaleness.PossiblyForgotten {
		t.Fatalf("active CDP was marked possibly left running: %#v", activeStaleness)
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

func TestPrepareUnixSocketRefusesLiveOwner(t *testing.T) {
	temporaryRoot, err := os.MkdirTemp("/tmp", "pt-live-socket-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(temporaryRoot) })
	socketPath := filepath.Join(temporaryRoot, "core.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	listener.(*net.UnixListener).SetUnlinkOnClose(false)
	defer listener.Close()

	if err := prepareUnixSocket(socketPath); err == nil {
		t.Fatal("live Unix socket owner was not refused")
	}
	if _, err := os.Stat(socketPath); err != nil {
		t.Fatalf("live Unix socket was removed: %v", err)
	}
}

func TestPrepareUnixSocketRemovesStaleSocket(t *testing.T) {
	temporaryRoot, err := os.MkdirTemp("/tmp", "pt-stale-socket-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(temporaryRoot) })
	socketPath := filepath.Join(temporaryRoot, "core.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	listener.(*net.UnixListener).SetUnlinkOnClose(false)
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}

	if err := prepareUnixSocket(socketPath); err != nil {
		t.Fatalf("stale Unix socket was not accepted: %v", err)
	}
	if _, err := os.Stat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("stale Unix socket still exists: %v", err)
	}
}

func TestPrepareUnixSocketRefusesRegularFile(t *testing.T) {
	socketPath := filepath.Join(t.TempDir(), "core.sock")
	if err := os.WriteFile(socketPath, []byte("preserve me"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := prepareUnixSocket(socketPath); err == nil {
		t.Fatal("regular file at socket path was not refused")
	}
	data, err := os.ReadFile(socketPath)
	if err != nil || string(data) != "preserve me" {
		t.Fatalf("regular file was changed: data=%q err=%v", data, err)
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
	if _, err := manager.put("demo", RouteRecord{Port: port, LogicalServiceID: "demo"}); err != nil {
		t.Fatal(err)
	}
	manager.attach(&ScanDocument{Services: []ServiceRecord{{ID: "demo-instance", LogicalID: "demo", Listener: ListenerRecord{Address: "127.0.0.1", Port: port}, Process: ProcessRecord{PID: os.Getpid()}}}})
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
	if response.StatusCode != http.StatusServiceUnavailable || !strings.Contains(string(body), "Original service unavailable") {
		t.Fatalf("missing-upstream response = %d %q", response.StatusCode, body)
	}
}

func TestSavedRouteFollowsOnlyItsOriginalService(t *testing.T) {
	manager, err := newRouteManager(filepath.Join(t.TempDir(), "routes.json"), 17890)
	if err != nil {
		t.Fatal(err)
	}
	first := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) { _, _ = io.WriteString(response, "original") }))
	defer first.Close()
	second := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) { _, _ = io.WriteString(response, "restarted") }))
	defer second.Close()
	portOf := func(server *httptest.Server) int {
		_, value, _ := net.SplitHostPort(strings.TrimPrefix(server.URL, "http://"))
		port, _ := strconv.Atoi(value)
		return port
	}
	oldPort, newPort := portOf(first), portOf(second)
	if _, err := manager.put("saved", RouteRecord{Port: oldPort, LogicalServiceID: "original", ProjectRoot: "/project-a"}); err != nil {
		t.Fatal(err)
	}
	proxy := httptest.NewServer((&coreServer{routes: manager}).proxyHandler())
	defer proxy.Close()
	get := func() (int, string) {
		request, _ := http.NewRequest(http.MethodGet, proxy.URL, nil)
		request.Host = "saved.localhost:17890"
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		body, _ := io.ReadAll(response.Body)
		return response.StatusCode, string(body)
	}
	service := func(logicalID string, port int) ServiceRecord {
		return ServiceRecord{ID: logicalID + "-instance", LogicalID: logicalID, Listener: ListenerRecord{Address: "127.0.0.1", Port: port}, Process: ProcessRecord{PID: os.Getpid()}, Project: &ProjectRecord{Root: "/project-a"}}
	}
	manager.attach(&ScanDocument{Services: []ServiceRecord{service("original", oldPort)}})
	if status, body := get(); status != 200 || body != "original" {
		t.Fatalf("original route = %d %q", status, body)
	}
	manager.attach(&ScanDocument{Services: []ServiceRecord{service("other", oldPort)}})
	if status, body := get(); status != 503 || !strings.Contains(body, "Original service unavailable") {
		t.Fatalf("reused port = %d %q", status, body)
	}
	manager.attach(&ScanDocument{})
	if status, _ := get(); status != 503 {
		t.Fatalf("offline route status = %d", status)
	}
	manager.attach(&ScanDocument{Services: []ServiceRecord{service("other", oldPort), service("original", newPort)}})
	if status, body := get(); status != 200 || body != "restarted" {
		t.Fatalf("rebound route = %d %q", status, body)
	}
	if route, _ := manager.get("saved"); route.Port != newPort {
		t.Fatalf("route did not persist rebound port: %#v", route)
	}
}

func TestLegacyRouteRequiresUniqueProjectOwner(t *testing.T) {
	manager, err := newRouteManager(filepath.Join(t.TempDir(), "routes.json"), 17890)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.put("legacy", RouteRecord{Port: 8000, ProjectRoot: "/original"}); err != nil {
		t.Fatal(err)
	}
	service := ServiceRecord{ID: "other", LogicalID: "other", Listener: ListenerRecord{Address: "127.0.0.1", Port: 8000}, Process: ProcessRecord{PID: os.Getpid()}, Project: &ProjectRecord{Root: "/other"}}
	manager.attach(&ScanDocument{Services: []ServiceRecord{service}})
	if _, ok := manager.getResolved("legacy"); ok {
		t.Fatal("legacy route accepted a different project")
	}
	service.Project.Root, service.LogicalID = "/original", "original"
	manager.attach(&ScanDocument{Services: []ServiceRecord{service}})
	if _, ok := manager.getResolved("legacy"); !ok {
		t.Fatal("legacy route did not resolve")
	}
	if route, _ := manager.get("legacy"); route.LogicalServiceID != "original" {
		t.Fatalf("legacy route was not promoted: %#v", route)
	}
}

func TestIPv6OnlyRouteUsesIPv6Loopback(t *testing.T) {
	listener, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Skipf("IPv6 loopback unavailable: %v", err)
	}
	upstream := httptest.NewUnstartedServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) { _, _ = io.WriteString(response, "ipv6") }))
	upstream.Listener = listener
	upstream.Start()
	defer upstream.Close()
	port := listener.Addr().(*net.TCPAddr).Port
	manager, err := newRouteManager(filepath.Join(t.TempDir(), "routes.json"), 17890)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.put("v6", RouteRecord{Port: port, LogicalServiceID: "v6"}); err != nil {
		t.Fatal(err)
	}
	manager.attach(&ScanDocument{Services: []ServiceRecord{{ID: "v6-instance", LogicalID: "v6", Listener: ListenerRecord{Address: "::1", Port: port}, Process: ProcessRecord{PID: os.Getpid()}}}})
	if route, _ := manager.get("v6"); route.Address != "::1" {
		t.Fatalf("IPv6 upstream not saved: %#v", route)
	}
	proxy := httptest.NewServer((&coreServer{routes: manager}).proxyHandler())
	defer proxy.Close()
	request, _ := http.NewRequest(http.MethodGet, proxy.URL, nil)
	request.Host = "v6.localhost:17890"
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if response.StatusCode != 200 || string(body) != "ipv6" {
		t.Fatalf("IPv6 route = %d %q", response.StatusCode, body)
	}
}

func TestFailedObservationRefreshesSoonerThanHealthyObservation(t *testing.T) {
	var status atomic.Int64
	status.Store(503)
	upstream := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "text/html")
		response.WriteHeader(int(status.Load()))
		_, _ = io.WriteString(response, "<title>ready</title>")
	}))
	defer upstream.Close()
	_, portText, _ := net.SplitHostPort(strings.TrimPrefix(upstream.URL, "http://"))
	port, _ := strconv.Atoi(portText)
	listener := discoveredListener{PID: os.Getpid(), Address: "127.0.0.1", Port: port}
	process := ProcessRecord{}
	management := ManagementRecord{Source: "unmanaged"}
	first := observeCached(listener, process, management)
	if first.HTTP == nil || *first.HTTP.Status != 503 {
		t.Fatalf("starting observation = %#v", first)
	}
	var cacheKey string
	observationCache.Lock()
	for key := range observationCache.entries {
		if strings.Contains(key, "\x00"+portText+"\x00") {
			cacheKey = key
			break
		}
	}
	if cacheKey == "" {
		observationCache.Unlock()
		t.Fatal("observation was not cached")
	}
	shortTTL := time.Until(observationCache.entries[cacheKey].expiresAt)
	observationCache.Unlock()
	if shortTTL > 4*time.Second {
		t.Fatalf("starting response cached too long: %v", shortTTL)
	}
	status.Store(200)
	if cached := observeCached(listener, process, management); *cached.HTTP.Status != 503 {
		t.Fatalf("starting response was not throttled: %#v", cached)
	}
	observationCache.Lock()
	entry := observationCache.entries[cacheKey]
	entry.expiresAt = time.Now().Add(-time.Millisecond)
	observationCache.entries[cacheKey] = entry
	observationCache.Unlock()
	ready := observeCached(listener, process, management)
	if ready.HTTP == nil || *ready.HTTP.Status != 200 {
		t.Fatalf("ready response was not observed: %#v", ready)
	}
	observationCache.Lock()
	healthyTTL := time.Until(observationCache.entries[cacheKey].expiresAt)
	observationCache.Unlock()
	if healthyTTL < 25*time.Second {
		t.Fatalf("healthy response cache was shortened: %v", healthyTTL)
	}
	status.Store(503)
	if cached := observeCached(listener, process, management); *cached.HTTP.Status != 200 {
		t.Fatalf("healthy response was not throttled: %#v", cached)
	}
}

func TestLongRunningUnknownTCPListenerKeepsNormalProbeThrottle(t *testing.T) {
	listener := discoveredListener{PID: os.Getpid(), Address: "127.0.0.1", Port: 1}
	started := time.Now().Add(-time.Hour).Format("Mon Jan 2 15:04:05 2006")
	process := ProcessRecord{Started: &started}
	first := observeCached(listener, process, ManagementRecord{Source: "unmanaged"})
	if first.Classification != "unknown" {
		t.Fatalf("unreachable TCP classification = %q", first.Classification)
	}
	observationCache.Lock()
	var ttl time.Duration
	for key, entry := range observationCache.entries {
		if strings.Contains(key, "\x001\x00") && strings.Contains(key, started) {
			ttl = time.Until(entry.expiresAt)
			break
		}
	}
	observationCache.Unlock()
	if ttl < 25*time.Second {
		t.Fatalf("long-running unknown listener probe throttle = %v", ttl)
	}
	second := observeCached(listener, process, ManagementRecord{Source: "unmanaged"})
	if second.ProbedAt != first.ProbedAt {
		t.Fatal("long-running unknown listener was probed again before cache expiry")
	}
}

func TestReverseProxyReleasesUpstreamConnections(t *testing.T) {
	var openConnections atomic.Int64
	upstream := httptest.NewUnstartedServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(response, "ok")
	}))
	upstream.Config.ConnState = func(_ net.Conn, state http.ConnState) {
		switch state {
		case http.StateNew:
			openConnections.Add(1)
		case http.StateClosed:
			openConnections.Add(-1)
		}
	}
	upstream.Start()
	t.Cleanup(upstream.Close)
	_, rawPort, _ := net.SplitHostPort(strings.TrimPrefix(upstream.URL, "http://"))
	port, _ := net.LookupPort("tcp", rawPort)

	manager, err := newRouteManager(filepath.Join(t.TempDir(), "routes.json"), 17890)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.put("demo", RouteRecord{Port: port, LogicalServiceID: "demo"}); err != nil {
		t.Fatal(err)
	}
	manager.attach(&ScanDocument{Services: []ServiceRecord{{ID: "demo-instance", LogicalID: "demo", Listener: ListenerRecord{Address: "127.0.0.1", Port: port}, Process: ProcessRecord{PID: os.Getpid()}}}})
	proxy := httptest.NewServer((&coreServer{routes: manager}).proxyHandler())
	t.Cleanup(proxy.Close)
	client := &http.Client{Transport: &http.Transport{DisableKeepAlives: true}}
	t.Cleanup(client.CloseIdleConnections)

	for range 20 {
		request, _ := http.NewRequest(http.MethodGet, proxy.URL, nil)
		request.Host = "demo.localhost:17890"
		response, err := client.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = io.Copy(io.Discard, response.Body)
		_ = response.Body.Close()
	}

	deadline := time.Now().Add(time.Second)
	for openConnections.Load() != 0 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if count := openConnections.Load(); count != 0 {
		t.Fatalf("reverse proxy retained %d upstream connections", count)
	}
}

func TestRouteManagerSwitchesBetweenPortlessAndFallbackURLs(t *testing.T) {
	manager, err := newRouteManager(filepath.Join(t.TempDir(), "routes.json"), 17890)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.put("demo", RouteRecord{Port: 4317}); err != nil {
		t.Fatal(err)
	}
	if got := manager.list()[0].URL; got != "http://demo.localhost:17890" {
		t.Fatalf("fallback URL = %q", got)
	}
	if err := manager.setPublicPort(80); err != nil {
		t.Fatal(err)
	}
	if got := manager.list()[0].URL; got != "http://demo.localhost" {
		t.Fatalf("portless URL = %q", got)
	}
	if err := manager.setPublicPort(0); err != nil {
		t.Fatal(err)
	}
	if got := manager.list()[0].URL; got != "http://demo.localhost:17890" {
		t.Fatalf("restored fallback URL = %q", got)
	}
	if err := manager.setPublicPort(443); err == nil {
		t.Fatal("unexpected public port was accepted")
	}
}

func TestInventoryEventDigestIgnoresVolatileTimestamps(t *testing.T) {
	document := ScanDocument{Services: []ServiceRecord{{
		ID: "instance", LogicalID: "logical",
		Listener:    ListenerRecord{Address: "127.0.0.1", Port: 4000},
		Observation: ObservationRecord{Classification: "confirmed-web", Protocol: "http", ProbedAt: "first"},
		History:     ServiceHistoryRecord{FirstSeen: "old", LastSeen: "first"},
	}}}
	first := inventoryEventDigest(document)
	document.GeneratedAt = "later"
	document.Services[0].History.LastSeen = "later"
	document.Services[0].Observation.ProbedAt = "later"
	second := inventoryEventDigest(document)
	if first != second {
		t.Fatal("volatile scan timestamps changed the inventory event digest")
	}
	document.Services[0].Listener.Port = 4001
	if inventoryEventDigest(document) == first {
		t.Fatal("listener change did not change the inventory event digest")
	}
}

func TestStopTokensExpireAndAreSingleUse(t *testing.T) {
	manager := newStopManager()
	manager.plans["expired-graceful"] = storedStopPlan{
		ServiceID: "service", ExpiresAt: time.Now().Add(-time.Second),
	}
	if _, err := manager.gracefulStop("service", "expired-graceful", 1); err == nil || !strings.Contains(err.Error(), "expired") {
		t.Fatalf("expired graceful token error = %v", err)
	}
	if _, err := manager.gracefulStop("service", "expired-graceful", 1); err == nil || !strings.Contains(err.Error(), "already used") {
		t.Fatalf("reused graceful token error = %v", err)
	}

	manager.forcePlans["expired-force"] = storedForcePlan{
		ServiceID: "service", ExpiresAt: time.Now().Add(-time.Second),
	}
	if _, err := manager.forceStop("service", "expired-force"); err == nil || !strings.Contains(err.Error(), "expired") {
		t.Fatalf("expired force token error = %v", err)
	}
	if _, err := manager.forceStop("service", "expired-force"); err == nil || !strings.Contains(err.Error(), "already used") {
		t.Fatalf("reused force token error = %v", err)
	}
}

func TestForcePlanRefusesManagedAndAmbiguousTargets(t *testing.T) {
	for name, plan := range map[string]StopPlanRecord{
		"managed": {
			Service: StopServiceSummary{ID: "service", ManagementSource: "docker"},
		},
		"ambiguous": {
			Service:    StopServiceSummary{ID: "service", ManagementSource: "unmanaged"},
			Exclusions: []StopProcessRecord{{PID: 42, Reason: "same-project ownership not established"}},
		},
	} {
		t.Run(name, func(t *testing.T) {
			manager := newStopManager()
			manager.gracefulAttempts[name] = storedGracefulAttempt{
				ServiceID: "service", Plan: plan, ExpiresAt: time.Now().Add(time.Minute),
			}
			record, err := manager.createForcePlan("service", name)
			if err != nil || record.Decision != "refused" {
				t.Fatalf("force plan = %#v, error = %v", record, err)
			}
		})
	}
}
