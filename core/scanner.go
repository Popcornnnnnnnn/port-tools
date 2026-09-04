package main

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var titlePattern = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)

var webCommandHints = []string{
	"vite", "next dev", "next-server", "webpack-dev-server", "uvicorn",
	"gunicorn", "flask run", "django", "http.server",
}

var applicationManifests = []string{"package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile"}

type discoveredListener struct {
	PID         int
	ProcessName string
	UID         int
	Owner       string
	Address     string
	Port        int
	BindScope   string
}

func runText(name string, arguments ...string) string {
	command := exec.Command(name, arguments...)
	command.Stderr = io.Discard
	output, err := command.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func parseEndpoint(value string) (string, int, string, bool) {
	index := strings.LastIndex(value, ":")
	if index < 0 {
		return "", 0, "", false
	}
	address := value[:index]
	port, err := strconv.Atoi(value[index+1:])
	if err != nil || port < 1 || port > 65535 {
		return "", 0, "", false
	}
	address = strings.TrimSuffix(strings.TrimPrefix(address, "["), "]")
	scope := "interface"
	switch address {
	case "*", "0.0.0.0", "::":
		scope = "all-interfaces"
	case "127.0.0.1", "::1":
		scope = "loopback"
	}
	return address, port, scope, true
}

func discoverListeners() ([]discoveredListener, error) {
	output := runText("/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-FpcuLn")
	if output == "" {
		return nil, errors.New("lsof returned no listener inventory")
	}
	currentUID := os.Getuid()
	current := discoveredListener{}
	seen := map[string]bool{}
	listeners := []discoveredListener{}
	for _, line := range strings.Split(output, "\n") {
		if len(line) < 2 {
			continue
		}
		value := line[1:]
		switch line[0] {
		case 'p':
			current = discoveredListener{}
			current.PID, _ = strconv.Atoi(value)
		case 'c':
			current.ProcessName = value
		case 'u':
			current.UID, _ = strconv.Atoi(value)
		case 'L':
			current.Owner = value
		case 'n':
			if current.UID != currentUID {
				continue
			}
			address, port, scope, ok := parseEndpoint(value)
			if !ok {
				continue
			}
			key := fmt.Sprintf("%d:%s:%d", current.PID, address, port)
			if seen[key] {
				continue
			}
			seen[key] = true
			listener := current
			listener.Address = address
			listener.Port = port
			listener.BindScope = scope
			listeners = append(listeners, listener)
		}
	}
	return listeners, nil
}

func pointer[T any](value T) *T { return &value }

func processMetadata(listener discoveredListener) (ProcessRecord, *ProjectRecord, *ApplicationRecord) {
	pid := strconv.Itoa(listener.PID)
	command := runText("/bin/ps", "-p", pid, "-o", "command=")
	parentText := runText("/bin/ps", "-p", pid, "-o", "ppid=")
	started := runText("/bin/ps", "-p", pid, "-o", "lstart=")
	cwdOutput := runText("/usr/sbin/lsof", "-a", "-p", pid, "-d", "cwd", "-Fn")
	var cwd string
	for _, line := range strings.Split(cwdOutput, "\n") {
		if strings.HasPrefix(line, "n") {
			cwd = line[1:]
			break
		}
	}
	process := ProcessRecord{PID: listener.PID}
	if listener.ProcessName != "" {
		process.Name = pointer(listener.ProcessName)
	}
	if listener.Owner != "" {
		process.Owner = pointer(listener.Owner)
	}
	if command != "" {
		process.Command = pointer(command)
	}
	if value, err := strconv.Atoi(strings.TrimSpace(parentText)); err == nil {
		process.ParentPID = pointer(value)
	}
	if started != "" {
		process.Started = pointer(started)
	}
	if cwd != "" {
		process.CWD = pointer(cwd)
	}

	project := findProject(cwd)
	if project == nil {
		for _, field := range strings.Fields(command) {
			candidate := strings.Trim(field, `"'`)
			if !filepath.IsAbs(candidate) && cwd != "" {
				candidate = filepath.Join(cwd, candidate)
			}
			info, err := os.Stat(candidate)
			if err != nil {
				continue
			}
			if !info.IsDir() {
				candidate = filepath.Dir(candidate)
			}
			if found := findProject(candidate); found != nil {
				project = found
				break
			}
		}
	}
	var application *ApplicationRecord
	if project != nil {
		application = findApplication(cwd, command, project.Root)
	}
	return process, project, application
}

func resolveGitDirectory(root string) (string, bool) {
	dotGit := filepath.Join(root, ".git")
	info, err := os.Stat(dotGit)
	if err != nil {
		return "", false
	}
	if info.IsDir() {
		return dotGit, true
	}
	data, err := os.ReadFile(dotGit)
	if err != nil {
		return "", false
	}
	line := strings.TrimSpace(string(data))
	if !strings.HasPrefix(line, "gitdir:") {
		return "", false
	}
	path := strings.TrimSpace(strings.TrimPrefix(line, "gitdir:"))
	if !filepath.IsAbs(path) {
		path = filepath.Join(root, path)
	}
	return filepath.Clean(path), true
}

func readTrimmed(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func gitRemote(configPath string) string {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return ""
	}
	inOrigin := false
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(raw)
		if strings.HasPrefix(line, "[") {
			inOrigin = line == `[remote "origin"]`
			continue
		}
		if inOrigin && strings.HasPrefix(line, "url") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				return sanitizeRemote(strings.TrimSpace(parts[1]))
			}
		}
	}
	return ""
}

func sanitizeRemote(value string) string {
	if separator := strings.Index(value, "://"); separator >= 0 {
		prefix := value[:separator+3]
		remainder := value[separator+3:]
		if at := strings.LastIndex(remainder, "@"); at >= 0 {
			remainder = remainder[at+1:]
		}
		return prefix + remainder
	}
	return value
}

func findProject(start string) *ProjectRecord {
	if start == "" {
		return nil
	}
	current, err := filepath.Abs(start)
	if err != nil {
		return nil
	}
	for {
		gitDirectory, ok := resolveGitDirectory(current)
		if ok {
			commonDirectory := gitDirectory
			if value := readTrimmed(filepath.Join(gitDirectory, "commondir")); value != "" {
				if !filepath.IsAbs(value) {
					value = filepath.Join(gitDirectory, value)
				}
				commonDirectory = filepath.Clean(value)
			}
			repositoryRoot := filepath.Dir(commonDirectory)
			repositoryName := filepath.Base(repositoryRoot)
			worktreeName := filepath.Base(current)
			isWorktree := filepath.Clean(gitDirectory) != filepath.Join(current, ".git")
			project := &ProjectRecord{
				Root:           current,
				Name:           repositoryName,
				RepositoryName: pointer(repositoryName),
				WorktreeName:   pointer(worktreeName),
				IsWorktree:     pointer(isWorktree),
			}
			head := readTrimmed(filepath.Join(gitDirectory, "HEAD"))
			if strings.HasPrefix(head, "ref: refs/heads/") {
				branch := strings.TrimPrefix(head, "ref: refs/heads/")
				project.Branch = pointer(branch)
			}
			if remote := gitRemote(filepath.Join(commonDirectory, "config")); remote != "" {
				project.RemoteURL = pointer(remote)
			}
			return project
		}
		parent := filepath.Dir(current)
		if parent == current {
			return nil
		}
		current = parent
	}
}

func pathWithin(path, root string) bool {
	relative, err := filepath.Rel(root, path)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator))
}

func findApplication(cwd, command, projectRoot string) *ApplicationRecord {
	candidates := []string{}
	if cwd != "" {
		candidates = append(candidates, cwd)
	}
	for _, field := range strings.Fields(command) {
		candidate := strings.Trim(field, `"'`)
		if !filepath.IsAbs(candidate) && cwd != "" {
			candidate = filepath.Join(cwd, candidate)
		}
		if info, err := os.Stat(candidate); err == nil {
			if !info.IsDir() {
				candidate = filepath.Dir(candidate)
			}
			if !strings.Contains(candidate, string(filepath.Separator)+"node_modules"+string(filepath.Separator)) {
				candidates = append(candidates, candidate)
			}
		}
	}
	var best *ApplicationRecord
	for _, candidate := range candidates {
		current, err := filepath.Abs(candidate)
		if err != nil || !pathWithin(current, projectRoot) {
			continue
		}
		for pathWithin(current, projectRoot) {
			for _, manifest := range applicationManifests {
				manifestPath := filepath.Join(current, manifest)
				if info, err := os.Stat(manifestPath); err == nil && !info.IsDir() {
					name := filepath.Base(current)
					if manifest == "package.json" {
						var packageFile struct {
							Name string `json:"name"`
						}
						if data, err := os.ReadFile(manifestPath); err == nil && json.Unmarshal(data, &packageFile) == nil && packageFile.Name != "" {
							name = packageFile.Name
						}
					}
					relative, _ := filepath.Rel(projectRoot, current)
					if relative == "" {
						relative = "."
					}
					candidateRecord := &ApplicationRecord{Root: current, RelativePath: relative, Name: name, Manifest: manifest}
					if best == nil || len(candidateRecord.Root) > len(best.Root) {
						best = candidateRecord
					}
					break
				}
			}
			if current == projectRoot {
				break
			}
			current = filepath.Dir(current)
		}
	}
	return best
}

func stableServiceID(listener discoveredListener) string {
	identity := fmt.Sprintf("%d:%s:%d", listener.PID, listener.Address, listener.Port)
	digest := sha256.Sum256([]byte(identity))
	return hex.EncodeToString(digest[:])[:12]
}

func stringContainsAny(value string, needles []string) (string, bool) {
	lower := strings.ToLower(value)
	for _, needle := range needles {
		if strings.Contains(lower, needle) {
			return needle, true
		}
	}
	return "", false
}

func probeURL(listener discoveredListener, scheme string) (*HTTPRecord, []byte, error) {
	host := "127.0.0.1"
	if listener.Address == "::1" {
		host = "[::1]"
	}
	transport := &http.Transport{
		DialContext: (&net.Dialer{Timeout: 350 * time.Millisecond}).DialContext,
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: true, // Classification probe only; no response body is persisted.
			ServerName:         "localhost",
			MinVersion:         tls.VersionTLS12,
		},
		DisableKeepAlives: true,
	}
	client := &http.Client{
		Transport: transport,
		Timeout:   900 * time.Millisecond,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	request, _ := http.NewRequestWithContext(context.Background(), http.MethodGet, fmt.Sprintf("%s://%s:%d/", scheme, host, listener.Port), nil)
	request.Header.Set("User-Agent", "port-tools-core/0.1")
	request.Header.Set("Accept", "text/html,*/*;q=0.1")
	response, err := client.Do(request)
	if err != nil {
		return nil, nil, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 65536))
	if err != nil {
		return nil, nil, err
	}
	status := response.StatusCode
	contentType := response.Header.Get("Content-Type")
	server := response.Header.Get("Server")
	record := &HTTPRecord{Status: &status, BytesRead: len(body)}
	if contentType != "" {
		record.ContentType = &contentType
	}
	if server != "" {
		record.Server = &server
	}
	if match := titlePattern.FindSubmatch(body); len(match) == 2 {
		title := strings.Join(strings.Fields(html.UnescapeString(string(match[1]))), " ")
		if title != "" {
			record.Title = &title
		}
	}
	return record, body, nil
}

func detectFramework(command string, body []byte) *string {
	lowerCommand := strings.ToLower(command)
	lowerBody := strings.ToLower(string(body))
	var framework string
	switch {
	case strings.Contains(lowerBody, "/@vite/client") || strings.Contains(lowerCommand, "vite"):
		framework = "vite"
	case strings.Contains(lowerBody, "/_next/") || strings.Contains(lowerCommand, "next dev") || strings.Contains(lowerCommand, "next-server"):
		framework = "next"
	case strings.Contains(lowerCommand, "uvicorn"):
		framework = "fastapi"
	default:
		return nil
	}
	return &framework
}

func presentationRole(response *HTTPRecord, framework *string) string {
	if response == nil || response.Status == nil {
		return "service"
	}
	status := *response.Status
	if status >= 300 && status < 400 {
		return "page"
	}
	if status < 200 || status >= 300 {
		return "service"
	}
	if response.Title != nil || framework != nil {
		return "page"
	}
	if response.ContentType != nil {
		contentType := strings.ToLower(*response.ContentType)
		if strings.Contains(contentType, "text/html") || strings.Contains(contentType, "application/xhtml+xml") {
			return "page"
		}
	}
	return "service"
}

func suspectedRole(hint string) string {
	switch hint {
	case "vite", "next dev", "next-server", "webpack-dev-server":
		return "page"
	default:
		return "service"
	}
}

func observe(listener discoveredListener, process ProcessRecord) ObservationRecord {
	command := ""
	if process.Command != nil {
		command = *process.Command
	}
	if response, body, err := probeURL(listener, "http"); err == nil {
		framework := detectFramework(command, body)
		evidence := []EvidenceRecord{{Kind: "valid-http-response", Value: *response.Status}}
		if framework != nil {
			evidence = append(evidence, EvidenceRecord{Kind: "framework-marker", Value: *framework})
		}
		return ObservationRecord{Classification: "confirmed-web", Protocol: "http", Role: presentationRole(response, framework), Confidence: 1, Framework: framework, HTTP: response, Evidence: evidence}
	}
	if response, body, err := probeURL(listener, "https"); err == nil {
		framework := detectFramework(command, body)
		evidence := []EvidenceRecord{{Kind: "tls-handshake", Value: "succeeded"}, {Kind: "valid-http-response", Value: *response.Status}}
		if framework != nil {
			evidence = append(evidence, EvidenceRecord{Kind: "framework-marker", Value: *framework})
		}
		return ObservationRecord{Classification: "confirmed-web", Protocol: "https", Role: presentationRole(response, framework), Confidence: 1, Framework: framework, HTTP: response, Evidence: evidence}
	}
	if hint, ok := stringContainsAny(command, webCommandHints); ok {
		return ObservationRecord{Classification: "suspected-web", Protocol: "unknown", Role: suspectedRole(hint), Confidence: 0.55, Evidence: []EvidenceRecord{{Kind: "command-hint", Value: hint}, {Kind: "probe-failed", Value: "no valid HTTP response"}}}
	}
	return ObservationRecord{Classification: "unknown", Protocol: "tcp", Role: "service", Confidence: 0.2, Evidence: []EvidenceRecord{{Kind: "no-valid-http-response", Value: "no response"}}}
}

func classifyRelevance(process ProcessRecord, project *ProjectRecord) RelevanceRecord {
	if project != nil {
		return RelevanceRecord{Category: "developer-project", DeveloperRelevant: true, Confidence: 0.95, Evidence: []EvidenceRecord{{Kind: "git-project", Value: project.Root}}}
	}
	command := ""
	if process.Command != nil {
		command = *process.Command
	}
	if hint, ok := stringContainsAny(command, webCommandHints); ok {
		return RelevanceRecord{Category: "developer-tool", DeveloperRelevant: true, Confidence: 0.7, Evidence: []EvidenceRecord{{Kind: "command-hint", Value: hint}}}
	}
	return RelevanceRecord{Category: "unattributed-web-endpoint", DeveloperRelevant: false, Confidence: 0.6, Evidence: []EvidenceRecord{{Kind: "no-project-or-framework-evidence", Value: true}}}
}

func scanServices() (ScanDocument, error) {
	listeners, err := discoverListeners()
	if err != nil {
		return ScanDocument{}, err
	}
	services := make([]ServiceRecord, len(listeners))
	semaphore := make(chan struct{}, 20)
	var wait sync.WaitGroup
	for index, listener := range listeners {
		index, listener := index, listener
		if listener.PID == os.Getpid() {
			services[index] = ServiceRecord{}
			continue
		}
		wait.Add(1)
		go func() {
			defer wait.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()
			process, project, application := processMetadata(listener)
			services[index] = ServiceRecord{
				ID:          stableServiceID(listener),
				Listener:    ListenerRecord{Address: listener.Address, Port: listener.Port, BindScope: listener.BindScope},
				Process:     process,
				Project:     project,
				Application: application,
				Observation: observe(listener, process),
				Relevance:   classifyRelevance(process, project),
			}
		}()
	}
	wait.Wait()
	filtered := services[:0]
	for _, service := range services {
		if service.ID != "" {
			filtered = append(filtered, service)
		}
	}
	services = filtered
	sort.Slice(services, func(left, right int) bool { return services[left].Listener.Port < services[right].Listener.Port })
	hostname, _ := os.Hostname()
	return newScanDocument(services, hostname), nil
}
