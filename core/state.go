package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const inventoryStateSchemaVersion = 1

type inventoryStateEntry struct {
	History             ServiceHistoryRecord     `json:"history"`
	Preferences         ServicePreferencesRecord `json:"preferences"`
	LastProjectRoot     string                   `json:"lastProjectRoot,omitempty"`
	LastApplicationRoot string                   `json:"lastApplicationRoot,omitempty"`
	LastObservedProbeAt string                   `json:"lastObservedProbeAt,omitempty"`
}

type inventoryStateFile struct {
	SchemaVersion int                            `json:"schemaVersion"`
	Services      map[string]inventoryStateEntry `json:"services"`
}

type servicePreferencesPatch struct {
	DisplayName            *string `json:"displayName,omitempty"`
	Pinned                 *bool   `json:"pinned,omitempty"`
	Ignored                *bool   `json:"ignored,omitempty"`
	ClassificationOverride *string `json:"classificationOverride,omitempty"`
}

type inventoryStateManager struct {
	mutex       sync.Mutex
	path        string
	state       inventoryStateFile
	lastPersist time.Time
}

func newInventoryStateManager(path string) (*inventoryStateManager, error) {
	manager := &inventoryStateManager{
		path:  path,
		state: inventoryStateFile{SchemaVersion: inventoryStateSchemaVersion, Services: map[string]inventoryStateEntry{}},
	}
	if err := manager.load(); err != nil {
		return nil, err
	}
	return manager, nil
}

func (manager *inventoryStateManager) load() error {
	data, err := os.ReadFile(manager.path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var state inventoryStateFile
	if err := json.Unmarshal(data, &state); err != nil || state.SchemaVersion != inventoryStateSchemaVersion || state.Services == nil {
		backup := fmt.Sprintf("%s.corrupt-%d", manager.path, time.Now().Unix())
		if renameError := os.Rename(manager.path, backup); renameError != nil {
			return fmt.Errorf("backup invalid inventory state: %w", renameError)
		}
		return nil
	}
	manager.state = state
	return nil
}

func (manager *inventoryStateManager) persistLocked() error {
	if err := os.MkdirAll(filepath.Dir(manager.path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(manager.state, "", "  ")
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(manager.path), "inventory-*.json")
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
	return os.Rename(temporaryPath, manager.path)
}

func probeSucceeded(observation ObservationRecord) bool {
	return observation.Classification == "confirmed-web" || observation.Classification == "non-web"
}

func parseProcessStarted(value *string) (time.Time, bool) {
	if value == nil || *value == "" {
		return time.Time{}, false
	}
	parsed, err := time.ParseInLocation("Mon Jan 2 15:04:05 2006", *value, time.Local)
	return parsed, err == nil
}

func (manager *inventoryStateManager) apply(document *ScanDocument) error {
	manager.mutex.Lock()
	defer manager.mutex.Unlock()
	now := time.Now().UTC()
	nowText := now.Format(time.RFC3339Nano)
	seen := map[string]bool{}
	for index := range document.Services {
		service := &document.Services[index]
		seen[service.LogicalID] = true
		entry, exists := manager.state.Services[service.LogicalID]
		if !exists {
			entry.History = ServiceHistoryRecord{
				FirstSeen:        nowText,
				LastSeen:         nowText,
				InitialParentPID: service.Process.ParentPID,
			}
		}
		entry.History.LastSeen = nowText
		if !exists || service.Observation.ProbedAt != entry.LastObservedProbeAt {
			probeAt := service.Observation.ProbedAt
			if probeAt == "" {
				probeAt = nowText
			}
			entry.LastObservedProbeAt = probeAt
			if probeSucceeded(service.Observation) {
				entry.History.LastSuccessfulProbe = probeAt
				entry.History.FirstFailedProbe = ""
				entry.History.ConsecutiveProbeFailures = 0
			} else {
				if entry.History.ConsecutiveProbeFailures == 0 {
					entry.History.FirstFailedProbe = probeAt
				}
				entry.History.ConsecutiveProbeFailures++
			}
		}
		if service.Project != nil {
			entry.LastProjectRoot = service.Project.Root
		}
		if service.Application != nil {
			entry.LastApplicationRoot = service.Application.Root
		}

		service.History = entry.History
		service.Preferences = entry.Preferences
		service.Staleness = stalenessForService(*service, entry, now)
		manager.state.Services[service.LogicalID] = entry
	}

	for logicalID, entry := range manager.state.Services {
		if seen[logicalID] || entry.Preferences.Pinned || entry.Preferences.DisplayName != "" {
			continue
		}
		lastSeen, err := time.Parse(time.RFC3339Nano, entry.History.LastSeen)
		if err == nil && now.Sub(lastSeen) > 30*24*time.Hour {
			delete(manager.state.Services, logicalID)
		}
	}
	// The menu can scan every three seconds while open. Keep history current in
	// memory, but avoid rewriting the state file on every poll. Preference edits
	// still persist immediately through updatePreferences.
	if manager.lastPersist.IsZero() || now.Sub(manager.lastPersist) >= 30*time.Second {
		if err := manager.persistLocked(); err != nil {
			return err
		}
		manager.lastPersist = now
	}
	return nil
}

func stalenessForService(service ServiceRecord, entry inventoryStateEntry, now time.Time) StalenessRecord {
	record := StalenessRecord{Reasons: []string{}}
	if service.Management.Source != "unmanaged" || entry.Preferences.Pinned || entry.Preferences.DisplayName != "" {
		return record
	}
	started, ok := parseProcessStarted(service.Process.Started)
	if !ok || now.Sub(started) < 24*time.Hour {
		return record
	}
	if entry.History.InitialParentPID != nil && service.Process.ParentPID != nil &&
		(*service.Process.ParentPID == 1 || *service.Process.ParentPID != *entry.History.InitialParentPID) {
		record.Reasons = append(record.Reasons, "original parent process is gone")
	}
	if entry.LastProjectRoot != "" {
		if _, err := os.Stat(entry.LastProjectRoot); os.IsNotExist(err) {
			record.Reasons = append(record.Reasons, "project directory is missing")
		}
	}
	if entry.History.ConsecutiveProbeFailures >= 3 && entry.History.FirstFailedProbe != "" {
		firstFailure, err := time.Parse(time.RFC3339Nano, entry.History.FirstFailedProbe)
		if err == nil && now.Sub(firstFailure) >= 10*time.Minute {
			record.Reasons = append(record.Reasons, "three probes failed for at least ten minutes")
		}
	}
	record.PossiblyForgotten = len(record.Reasons) > 0
	return record
}

func (manager *inventoryStateManager) updatePreferences(logicalID string, patch servicePreferencesPatch) (ServicePreferencesRecord, error) {
	manager.mutex.Lock()
	defer manager.mutex.Unlock()
	entry, exists := manager.state.Services[logicalID]
	if !exists {
		return ServicePreferencesRecord{}, errors.New("logical service does not exist")
	}
	if patch.DisplayName != nil {
		entry.Preferences.DisplayName = *patch.DisplayName
	}
	if patch.Pinned != nil {
		entry.Preferences.Pinned = *patch.Pinned
	}
	if patch.Ignored != nil {
		entry.Preferences.Ignored = *patch.Ignored
	}
	if patch.ClassificationOverride != nil {
		switch *patch.ClassificationOverride {
		case "", "auto", "page", "service", "listener":
			entry.Preferences.ClassificationOverride = *patch.ClassificationOverride
		default:
			return ServicePreferencesRecord{}, errors.New("classificationOverride must be auto, page, service, or listener")
		}
	}
	manager.state.Services[logicalID] = entry
	if err := manager.persistLocked(); err != nil {
		return ServicePreferencesRecord{}, err
	}
	manager.lastPersist = time.Now().UTC()
	return entry.Preferences, nil
}
