package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"sync"
	"sync/atomic"
	"time"
)

var aliasPattern = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$`)

type routeState struct {
	SchemaVersion int                    `json:"schemaVersion"`
	Routes        map[string]RouteRecord `json:"routes"`
}

type routeManager struct {
	mutex      sync.RWMutex
	statePath  string
	proxyPort  int
	publicPort atomic.Int64
	routes     map[string]RouteRecord
}

func newRouteManager(statePath string, proxyPort int) (*routeManager, error) {
	manager := &routeManager{
		statePath: statePath,
		proxyPort: proxyPort,
		routes:    map[string]RouteRecord{},
	}
	manager.publicPort.Store(int64(proxyPort))
	if err := manager.load(); err != nil {
		return nil, err
	}
	return manager, nil
}

func normalizeAlias(value string) (string, error) {
	alias := stringLower(value)
	if !aliasPattern.MatchString(alias) {
		return "", errors.New("alias must use lowercase letters, numbers, and internal hyphens")
	}
	return alias, nil
}

func stringLower(value string) string {
	result := make([]byte, len(value))
	for index := range value {
		character := value[index]
		if character >= 'A' && character <= 'Z' {
			character += 'a' - 'A'
		}
		result[index] = character
	}
	return string(result)
}

func (manager *routeManager) routeURL(alias string) string {
	publicPort := int(manager.publicPort.Load())
	if publicPort == 80 {
		return fmt.Sprintf("http://%s.localhost", alias)
	}
	return fmt.Sprintf("http://%s.localhost:%d", alias, publicPort)
}

func (manager *routeManager) setPublicPort(port int) error {
	if port == 0 {
		port = manager.proxyPort
	}
	if port != 80 && port != manager.proxyPort {
		return errors.New("public port must be 80 or the route proxy port")
	}
	manager.publicPort.Store(int64(port))
	return nil
}

func (manager *routeManager) currentPublicPort() int {
	return int(manager.publicPort.Load())
}

func (manager *routeManager) load() error {
	data, err := os.ReadFile(manager.statePath)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var state routeState
	if decodeError := json.Unmarshal(data, &state); decodeError != nil ||
		(state.SchemaVersion != 1 && state.SchemaVersion != 2) || state.Routes == nil {
		backup := fmt.Sprintf("%s.corrupt-%d", manager.statePath, time.Now().Unix())
		if renameError := os.Rename(manager.statePath, backup); renameError != nil {
			return fmt.Errorf("backup invalid route state: %w", renameError)
		}
		return nil
	}
	for alias, route := range state.Routes {
		route.Alias = alias
		if route.LastResolvedPort == 0 {
			route.LastResolvedPort = route.Port
		}
		route.URL = manager.routeURL(alias)
		manager.routes[alias] = route
	}
	if state.SchemaVersion == 1 {
		return manager.persistLocked()
	}
	return nil
}

func (manager *routeManager) persistLocked() error {
	if err := os.MkdirAll(filepath.Dir(manager.statePath), 0o700); err != nil {
		return err
	}
	state := routeState{SchemaVersion: 2, Routes: manager.routes}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(manager.statePath), "routes-*.json")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporaryPath, manager.statePath)
}

func (manager *routeManager) put(alias string, proposed RouteRecord, previousAliases ...string) (RouteRecord, error) {
	normalized, err := normalizeAlias(alias)
	if err != nil {
		return RouteRecord{}, err
	}
	if proposed.Port < 1 || proposed.Port > 65535 {
		return RouteRecord{}, errors.New("upstream port must be between 1 and 65535")
	}
	if proposed.Scheme == "" {
		proposed.Scheme = "http"
	}
	if proposed.Scheme != "http" && proposed.Scheme != "https" {
		return RouteRecord{}, errors.New("upstream scheme must be http or https")
	}
	if proposed.HostMode == "" {
		proposed.HostMode = "rewrite"
	}
	if proposed.HostMode != "rewrite" && proposed.HostMode != "preserve" {
		return RouteRecord{}, errors.New("host mode must be rewrite or preserve")
	}
	if proposed.TLSPolicy == "" {
		proposed.TLSPolicy = "verify"
	}
	if proposed.TLSPolicy != "verify" && proposed.TLSPolicy != "insecure-local" {
		return RouteRecord{}, errors.New("TLS policy must be verify or insecure-local")
	}
	proposed.Alias = normalized
	proposed.LastResolvedPort = proposed.Port
	proposed.URL = manager.routeURL(normalized)

	manager.mutex.Lock()
	defer manager.mutex.Unlock()
	originalRoutes := make(map[string]RouteRecord, len(manager.routes))
	for key, value := range manager.routes {
		originalRoutes[key] = value
	}
	previousAlias := ""
	if len(previousAliases) > 0 && previousAliases[0] != "" {
		previousAlias, err = normalizeAlias(previousAliases[0])
		if err != nil {
			return RouteRecord{}, err
		}
	}
	if existing, exists := manager.routes[normalized]; exists {
		if existing.LogicalServiceID != "" && proposed.LogicalServiceID != "" {
			if existing.LogicalServiceID != proposed.LogicalServiceID {
				return RouteRecord{}, errors.New("alias already belongs to a different service")
			}
		} else if existing.Port != proposed.Port || existing.ProjectRoot != proposed.ProjectRoot || existing.ApplicationRoot != proposed.ApplicationRoot {
			return RouteRecord{}, errors.New("alias already belongs to a different service")
		}
	}
	if previousAlias != "" && previousAlias != normalized {
		previous, exists := manager.routes[previousAlias]
		if !exists {
			return RouteRecord{}, errors.New("previous alias no longer exists")
		}
		if previous.Port != proposed.Port || previous.ProjectRoot != proposed.ProjectRoot || previous.ApplicationRoot != proposed.ApplicationRoot {
			return RouteRecord{}, errors.New("previous alias belongs to a different service")
		}
		delete(manager.routes, previousAlias)
	}
	manager.routes[normalized] = proposed
	if err := manager.persistLocked(); err != nil {
		manager.routes = originalRoutes
		return RouteRecord{}, err
	}
	return proposed, nil
}

func (manager *routeManager) remove(alias string) error {
	normalized, err := normalizeAlias(alias)
	if err != nil {
		return err
	}
	manager.mutex.Lock()
	defer manager.mutex.Unlock()
	removed, exists := manager.routes[normalized]
	if !exists {
		return errors.New("alias does not exist")
	}
	delete(manager.routes, normalized)
	if err := manager.persistLocked(); err != nil {
		manager.routes[normalized] = removed
		return err
	}
	return nil
}

func (manager *routeManager) get(alias string) (RouteRecord, bool) {
	manager.mutex.RLock()
	defer manager.mutex.RUnlock()
	route, ok := manager.routes[alias]
	return route, ok
}

func (manager *routeManager) list() []RouteRecord {
	manager.mutex.RLock()
	defer manager.mutex.RUnlock()
	routes := make([]RouteRecord, 0, len(manager.routes))
	for alias, route := range manager.routes {
		route.URL = manager.routeURL(alias)
		routes = append(routes, route)
	}
	sort.Slice(routes, func(left, right int) bool { return routes[left].Alias < routes[right].Alias })
	return routes
}

func (manager *routeManager) attach(document *ScanDocument) {
	manager.mutex.Lock()
	defer manager.mutex.Unlock()
	changed := false
	logicalCounts := map[string]int{}
	for _, service := range document.Services {
		logicalCounts[service.LogicalID]++
	}
	for serviceIndex := range document.Services {
		service := &document.Services[serviceIndex]
		projectRoot := ""
		applicationRoot := ""
		if service.Project != nil {
			projectRoot = service.Project.Root
		}
		if service.Application != nil {
			applicationRoot = service.Application.Root
		}
		for alias, route := range manager.routes {
			logicalMatch := route.LogicalServiceID != "" && route.LogicalServiceID == service.LogicalID && logicalCounts[service.LogicalID] == 1
			legacyMatch := route.LogicalServiceID == "" && route.Port == service.Listener.Port && route.ProjectRoot == projectRoot && route.ApplicationRoot == applicationRoot
			if logicalMatch || legacyMatch {
				if logicalMatch && route.Port != service.Listener.Port {
					route.Port = service.Listener.Port
					route.LastResolvedPort = service.Listener.Port
					manager.routes[alias] = route
					changed = true
				}
				route.URL = manager.routeURL(alias)
				service.Route = &route
				break
			}
		}
	}
	if changed {
		_ = manager.persistLocked()
	}
}
