package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var sharedRuntimeHints = []string{
	"com.docker.backend", "docker daemon", "dockerd", "launchd",
	"orbstack helper", "port-tools-core",
}

type StopProcessRecord struct {
	PID             int     `json:"pid"`
	ParentPID       *int    `json:"parentPid,omitempty"`
	Name            *string `json:"name,omitempty"`
	Owner           *string `json:"owner,omitempty"`
	Command         *string `json:"command,omitempty"`
	CWD             *string `json:"cwd,omitempty"`
	Started         *string `json:"started,omitempty"`
	ProjectRoot     string  `json:"projectRoot,omitempty"`
	ApplicationRoot string  `json:"applicationRoot,omitempty"`
	Reason          string  `json:"reason,omitempty"`
}

type StopListenerTarget struct {
	PID         int    `json:"pid"`
	Address     string `json:"address"`
	Port        int    `json:"port"`
	CurrentPIDs []int  `json:"currentPids,omitempty"`
}

type GracefulStopPlan struct {
	Signal                  string               `json:"signal"`
	PIDs                    []int                `json:"pids"`
	VerifyListenersReleased []StopListenerTarget `json:"verifyListenersReleased"`
}

type ForceStopPlan struct {
	Signal                         string `json:"signal"`
	AllowedInThisAction            bool   `json:"allowedInThisAction"`
	RequiresSeparateExplicitAction bool   `json:"requiresSeparateExplicitAction"`
}

type StopServiceSummary struct {
	ID               string         `json:"id"`
	Listener         ListenerRecord `json:"listener"`
	ProjectRoot      string         `json:"projectRoot,omitempty"`
	ApplicationRoot  string         `json:"applicationRoot,omitempty"`
	ManagementSource string         `json:"managementSource"`
}

type StopPlanRecord struct {
	SchemaVersion int                 `json:"schemaVersion"`
	Mode          string              `json:"mode"`
	SignalSent    bool                `json:"signalSent"`
	Decision      string              `json:"decision"`
	Reasons       []string            `json:"reasons"`
	Service       StopServiceSummary  `json:"service"`
	RootProcess   StopProcessRecord   `json:"rootProcess"`
	Descendants   []StopProcessRecord `json:"descendants"`
	Exclusions    []StopProcessRecord `json:"exclusions"`
	GracefulPlan  GracefulStopPlan    `json:"gracefulPlan"`
	ForcePlan     ForceStopPlan       `json:"forcePlan"`
	PlanToken     string              `json:"planToken,omitempty"`
	ExpiresAt     string              `json:"expiresAt,omitempty"`
}

type GracefulStopResult struct {
	SchemaVersion                           int                  `json:"schemaVersion"`
	Mode                                    string               `json:"mode"`
	Service                                 StopServiceSummary   `json:"service"`
	Decision                                string               `json:"decision"`
	Reasons                                 []string             `json:"reasons"`
	Signal                                  string               `json:"signal"`
	SignalSent                              bool                 `json:"signalSent"`
	SignaledPIDs                            []int                `json:"signaledPids"`
	TimeoutSeconds                          float64              `json:"timeoutSeconds"`
	ListenersReleased                       bool                 `json:"listenersReleased"`
	RemainingListeners                      []StopListenerTarget `json:"remainingListeners"`
	ForceStopPerformed                      bool                 `json:"forceStopPerformed"`
	ForceStopRequiresSeparateExplicitAction bool                 `json:"forceStopRequiresSeparateExplicitAction"`
	Success                                 bool                 `json:"success"`
}

type storedStopPlan struct {
	ServiceID   string
	Fingerprint string
	Plan        StopPlanRecord
	ExpiresAt   time.Time
}

type stopManager struct {
	mutex sync.Mutex
	plans map[string]storedStopPlan
}

func newStopManager() *stopManager {
	return &stopManager{plans: map[string]storedStopPlan{}}
}

func findServiceByID(id string) (ServiceRecord, error) {
	document, err := scanServices()
	if err != nil {
		return ServiceRecord{}, err
	}
	for _, service := range document.Services {
		if service.ID == id {
			return service, nil
		}
	}
	return ServiceRecord{}, errors.New("service no longer exists")
}

func basicProcessSnapshot() map[int]StopProcessRecord {
	output := runText("/bin/ps", "-axo", "pid=,ppid=,user=,comm=")
	processes := map[int]StopProcessRecord{}
	for _, line := range strings.Split(output, "\n") {
		parts := strings.Fields(strings.TrimSpace(line))
		if len(parts) < 4 {
			continue
		}
		pid, pidError := strconv.Atoi(parts[0])
		parentPID, parentError := strconv.Atoi(parts[1])
		if pidError != nil || parentError != nil {
			continue
		}
		owner := parts[2]
		name := filepath.Base(strings.Join(parts[3:], " "))
		processes[pid] = StopProcessRecord{PID: pid, ParentPID: pointer(parentPID), Owner: pointer(owner), Name: pointer(name)}
	}
	return processes
}

func descendantPIDs(rootPID int, processes map[int]StopProcessRecord) []int {
	children := map[int][]int{}
	for pid, process := range processes {
		if process.ParentPID != nil {
			children[*process.ParentPID] = append(children[*process.ParentPID], pid)
		}
	}
	for parent := range children {
		sort.Ints(children[parent])
	}
	var descendants []int
	pending := append([]int(nil), children[rootPID]...)
	for len(pending) > 0 {
		pid := pending[0]
		pending = pending[1:]
		descendants = append(descendants, pid)
		pending = append(pending, children[pid]...)
	}
	return descendants
}

func enrichStopProcess(process StopProcessRecord) StopProcessRecord {
	listener := discoveredListener{PID: process.PID}
	if process.Name != nil {
		listener.ProcessName = *process.Name
	}
	if process.Owner != nil {
		listener.Owner = *process.Owner
	}
	metadata, project, application, _, _ := processMetadata(listener)
	process.ParentPID = metadata.ParentPID
	process.Name = metadata.Name
	process.Owner = metadata.Owner
	process.Command = metadata.Command
	process.CWD = metadata.CWD
	process.Started = metadata.Started
	if project != nil {
		process.ProjectRoot = project.Root
	}
	if application != nil {
		process.ApplicationRoot = application.Root
	}
	return process
}

func stopManagementSource(service ServiceRecord) string {
	if service.Management.Source != "" {
		return service.Management.Source
	}
	identity := strings.ToLower(valueOrEmpty(service.Process.Name) + " " + valueOrEmpty(service.Process.Command))
	if strings.Contains(identity, "docker") {
		return "docker"
	}
	return "unmanaged"
}

func valueOrEmpty(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func buildStopPlan(service ServiceRecord) (StopPlanRecord, string) {
	projectRoot := ""
	if service.Project != nil {
		projectRoot = service.Project.Root
	}
	applicationRoot := ""
	if service.Application != nil {
		applicationRoot = service.Application.Root
	}
	managementSource := stopManagementSource(service)
	plan := StopPlanRecord{
		SchemaVersion: 1,
		Mode:          "dry-run",
		Decision:      "eligible",
		Reasons:       []string{},
		Service: StopServiceSummary{
			ID: service.ID, Listener: service.Listener, ProjectRoot: projectRoot,
			ApplicationRoot: applicationRoot, ManagementSource: managementSource,
		},
		Descendants:  []StopProcessRecord{},
		Exclusions:   []StopProcessRecord{},
		GracefulPlan: GracefulStopPlan{Signal: "SIGTERM", PIDs: []int{}, VerifyListenersReleased: []StopListenerTarget{}},
		ForcePlan:    ForceStopPlan{Signal: "SIGKILL", AllowedInThisAction: false, RequiresSeparateExplicitAction: true},
	}

	currentUser := runText("/usr/bin/id", "-un")
	processes := basicProcessSnapshot()
	root, exists := processes[service.Process.PID]
	if exists {
		root = enrichStopProcess(root)
	}
	plan.RootProcess = root
	if service.Process.Owner == nil || *service.Process.Owner != currentUser {
		plan.Reasons = append(plan.Reasons, "target is not owned by the current user")
	}
	if !exists {
		plan.Reasons = append(plan.Reasons, "target PID no longer exists")
	} else if root.Owner == nil || *root.Owner != currentUser {
		plan.Reasons = append(plan.Reasons, "current PID owner does not match the scanned owner")
	} else if service.Process.Started != nil && valueOrEmpty(root.Started) != *service.Process.Started {
		plan.Reasons = append(plan.Reasons, "PID identity changed since the service was scanned")
	} else if service.Process.Command != nil && valueOrEmpty(root.Command) != *service.Process.Command {
		plan.Reasons = append(plan.Reasons, "process command changed since the service was scanned")
	}
	if managementSource == "docker" {
		plan.Reasons = append(plan.Reasons, "Docker-published services must be managed through the container, not its daemon")
	}
	if projectRoot == "" {
		plan.Reasons = append(plan.Reasons, "target has no unambiguous Git-project ownership evidence")
	}
	identity := strings.ToLower(valueOrEmpty(service.Process.Name) + " " + valueOrEmpty(service.Process.Command))
	if hint, shared := stringContainsAny(identity, sharedRuntimeHints); shared {
		plan.Reasons = append(plan.Reasons, "target appears to be a shared or system runtime: "+hint)
	}
	if service.Process.PID == os.Getpid() {
		plan.Reasons = append(plan.Reasons, "Port Tools cannot stop its own core process")
	}

	descendants := descendantPIDs(service.Process.PID, processes)
	included := []StopProcessRecord{}
	if exists {
		root.ProjectRoot = projectRoot
		root.ApplicationRoot = applicationRoot
		included = append(included, root)
	}
	for _, pid := range descendants {
		child := enrichStopProcess(processes[pid])
		reason := ""
		if child.Owner == nil || *child.Owner != currentUser {
			reason = "different owner"
		} else if child.ProjectRoot != projectRoot {
			reason = "same-project ownership not established"
		} else if applicationRoot != "" && child.ApplicationRoot != applicationRoot {
			reason = "same-application ownership not established"
		}
		if reason != "" {
			child.Reason = reason
			plan.Exclusions = append(plan.Exclusions, child)
		} else {
			included = append(included, child)
			plan.Descendants = append(plan.Descendants, child)
		}
	}

	includedPIDs := map[int]bool{}
	for _, process := range included {
		includedPIDs[process.PID] = true
	}
	if listeners, err := discoverListeners(); err == nil {
		for _, listener := range listeners {
			if includedPIDs[listener.PID] {
				plan.GracefulPlan.VerifyListenersReleased = append(plan.GracefulPlan.VerifyListenersReleased, StopListenerTarget{
					PID: listener.PID, Address: listener.Address, Port: listener.Port,
				})
			}
		}
	}
	targetListenerPresent := false
	for _, target := range plan.GracefulPlan.VerifyListenersReleased {
		if target.PID == service.Process.PID && target.Address == service.Listener.Address && target.Port == service.Listener.Port {
			targetListenerPresent = true
			break
		}
	}
	if !targetListenerPresent {
		plan.Reasons = append(plan.Reasons, "target listener changed before the stop plan was created")
	}
	sort.Slice(plan.GracefulPlan.VerifyListenersReleased, func(left, right int) bool {
		leftTarget := plan.GracefulPlan.VerifyListenersReleased[left]
		rightTarget := plan.GracefulPlan.VerifyListenersReleased[right]
		if leftTarget.Port != rightTarget.Port {
			return leftTarget.Port < rightTarget.Port
		}
		if leftTarget.Address != rightTarget.Address {
			return leftTarget.Address < rightTarget.Address
		}
		return leftTarget.PID < rightTarget.PID
	})
	for index := len(descendants) - 1; index >= 0; index-- {
		if includedPIDs[descendants[index]] {
			plan.GracefulPlan.PIDs = append(plan.GracefulPlan.PIDs, descendants[index])
		}
	}
	if includedPIDs[service.Process.PID] {
		plan.GracefulPlan.PIDs = append(plan.GracefulPlan.PIDs, service.Process.PID)
	}
	if len(plan.Reasons) > 0 {
		plan.Decision = "refused"
		plan.GracefulPlan.PIDs = []int{}
	}

	fingerprintValue := struct {
		Service     StopServiceSummary
		Root        StopProcessRecord
		Descendants []StopProcessRecord
		Exclusions  []StopProcessRecord
		PIDs        []int
		Listeners   []StopListenerTarget
	}{plan.Service, plan.RootProcess, plan.Descendants, plan.Exclusions, plan.GracefulPlan.PIDs, plan.GracefulPlan.VerifyListenersReleased}
	encoded, _ := json.Marshal(fingerprintValue)
	digest := sha256.Sum256(encoded)
	return plan, hex.EncodeToString(digest[:])
}

func (manager *stopManager) createPlan(serviceID string) (StopPlanRecord, error) {
	service, err := findServiceByID(serviceID)
	if err != nil {
		return StopPlanRecord{}, err
	}
	plan, fingerprint := buildStopPlan(service)
	if plan.Decision != "eligible" {
		return plan, nil
	}
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		return StopPlanRecord{}, err
	}
	token := hex.EncodeToString(tokenBytes)
	expiresAt := time.Now().Add(2 * time.Minute)
	plan.PlanToken = token
	plan.ExpiresAt = expiresAt.UTC().Format(time.RFC3339Nano)
	manager.mutex.Lock()
	for key, stored := range manager.plans {
		if time.Now().After(stored.ExpiresAt) {
			delete(manager.plans, key)
		}
	}
	manager.plans[token] = storedStopPlan{ServiceID: serviceID, Fingerprint: fingerprint, Plan: plan, ExpiresAt: expiresAt}
	manager.mutex.Unlock()
	return plan, nil
}

func remainingStopListeners(targets []StopListenerTarget) []StopListenerTarget {
	listeners, err := discoverListeners()
	if err != nil {
		return append([]StopListenerTarget(nil), targets...)
	}
	remaining := []StopListenerTarget{}
	for _, target := range targets {
		currentPIDs := map[int]bool{}
		for _, listener := range listeners {
			if listener.Address == target.Address && listener.Port == target.Port {
				currentPIDs[listener.PID] = true
			}
		}
		if len(currentPIDs) > 0 {
			current := target
			for pid := range currentPIDs {
				current.CurrentPIDs = append(current.CurrentPIDs, pid)
			}
			sort.Ints(current.CurrentPIDs)
			remaining = append(remaining, current)
		}
	}
	return remaining
}

func (manager *stopManager) gracefulStop(serviceID, token string, timeoutSeconds float64) (GracefulStopResult, error) {
	manager.mutex.Lock()
	stored, exists := manager.plans[token]
	delete(manager.plans, token)
	manager.mutex.Unlock()
	if !exists || stored.ServiceID != serviceID {
		return GracefulStopResult{}, errors.New("stop plan token is invalid or already used")
	}
	if time.Now().After(stored.ExpiresAt) {
		return GracefulStopResult{}, errors.New("stop plan token expired; review the service again")
	}
	if timeoutSeconds <= 0 || timeoutSeconds > 30 {
		timeoutSeconds = 5
	}
	result := GracefulStopResult{
		SchemaVersion: 1, Mode: "graceful", Service: stored.Plan.Service, Decision: "eligible",
		Reasons: []string{}, Signal: "SIGTERM", SignaledPIDs: []int{}, TimeoutSeconds: timeoutSeconds,
		RemainingListeners:                      append([]StopListenerTarget(nil), stored.Plan.GracefulPlan.VerifyListenersReleased...),
		ForceStopRequiresSeparateExplicitAction: true,
	}
	service, err := findServiceByID(serviceID)
	if err != nil {
		result.Decision = "refused"
		result.Reasons = append(result.Reasons, "target disappeared during final revalidation")
		return result, nil
	}
	confirmation, fingerprint := buildStopPlan(service)
	if confirmation.Decision != "eligible" || fingerprint != stored.Fingerprint {
		result.Decision = "refused"
		result.Reasons = append(result.Reasons, "target process tree changed during final revalidation")
		return result, nil
	}
	for _, pid := range confirmation.GracefulPlan.PIDs {
		if err := syscall.Kill(pid, syscall.SIGTERM); err != nil {
			if errors.Is(err, syscall.ESRCH) {
				continue
			}
			if errors.Is(err, syscall.EPERM) {
				result.Decision = "partial"
				result.Reasons = append(result.Reasons, fmt.Sprintf("permission denied while signalling PID %d", pid))
				break
			}
			result.Decision = "partial"
			result.Reasons = append(result.Reasons, fmt.Sprintf("failed to signal PID %d: %v", pid, err))
			break
		}
		result.SignalSent = true
		result.SignaledPIDs = append(result.SignaledPIDs, pid)
	}
	deadline := time.Now().Add(time.Duration(timeoutSeconds * float64(time.Second)))
	remaining := remainingStopListeners(confirmation.GracefulPlan.VerifyListenersReleased)
	for len(remaining) > 0 && time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
		remaining = remainingStopListeners(confirmation.GracefulPlan.VerifyListenersReleased)
	}
	result.RemainingListeners = remaining
	result.ListenersReleased = len(remaining) == 0
	result.Success = result.Decision == "eligible" && result.ListenersReleased
	return result, nil
}
