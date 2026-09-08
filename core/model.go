package main

import "time"

type ListenerRecord struct {
	Address   string `json:"address"`
	Port      int    `json:"port"`
	BindScope string `json:"bindScope"`
}

type ProcessRecord struct {
	PID       int     `json:"pid"`
	ParentPID *int    `json:"parentPid,omitempty"`
	Name      *string `json:"name,omitempty"`
	Owner     *string `json:"owner,omitempty"`
	Command   *string `json:"command,omitempty"`
	CWD       *string `json:"cwd,omitempty"`
	Started   *string `json:"started,omitempty"`
}

type ProjectRecord struct {
	Root           string  `json:"root"`
	Name           string  `json:"name"`
	RepositoryName *string `json:"repositoryName,omitempty"`
	WorktreeName   *string `json:"worktreeName,omitempty"`
	Branch         *string `json:"branch,omitempty"`
	RemoteURL      *string `json:"remoteUrl,omitempty"`
	IsWorktree     *bool   `json:"isWorktree,omitempty"`
}

type ApplicationRecord struct {
	Root         string `json:"root"`
	RelativePath string `json:"relativePath"`
	Name         string `json:"name"`
	Manifest     string `json:"manifest"`
}

type HTTPRecord struct {
	Status      *int    `json:"status,omitempty"`
	ContentType *string `json:"contentType,omitempty"`
	Server      *string `json:"server,omitempty"`
	Title       *string `json:"title,omitempty"`
	BytesRead   int     `json:"bytesRead"`
}

type EvidenceRecord struct {
	Kind  string `json:"kind"`
	Value any    `json:"value,omitempty"`
}

type ObservationRecord struct {
	Classification string           `json:"classification"`
	Protocol       string           `json:"protocol"`
	Role           string           `json:"role"`
	Confidence     float64          `json:"confidence"`
	Framework      *string          `json:"framework,omitempty"`
	HTTP           *HTTPRecord      `json:"http,omitempty"`
	Evidence       []EvidenceRecord `json:"evidence"`
	ProbedAt       string           `json:"probedAt"`
}

type RelevanceRecord struct {
	Category          string           `json:"category"`
	DeveloperRelevant bool             `json:"developerRelevant"`
	Confidence        float64          `json:"confidence"`
	Evidence          []EvidenceRecord `json:"evidence"`
}

type ManagementRecord struct {
	Source        string            `json:"source"`
	ContainerID   string            `json:"containerId,omitempty"`
	ContainerName string            `json:"containerName,omitempty"`
	Image         string            `json:"image,omitempty"`
	ContainerPort string            `json:"containerPort,omitempty"`
	Labels        map[string]string `json:"labels,omitempty"`
}

type RouteRecord struct {
	Alias            string `json:"alias"`
	Port             int    `json:"port"`
	LastResolvedPort int    `json:"lastResolvedPort,omitempty"`
	Scheme           string `json:"scheme"`
	HostMode         string `json:"hostMode"`
	TLSPolicy        string `json:"tlsPolicy"`
	LogicalServiceID string `json:"logicalServiceId,omitempty"`
	ProjectRoot      string `json:"projectRoot,omitempty"`
	ApplicationRoot  string `json:"applicationRoot,omitempty"`
	URL              string `json:"url"`
}

type ServiceHistoryRecord struct {
	FirstSeen                string `json:"firstSeen"`
	LastSeen                 string `json:"lastSeen"`
	LastSuccessfulProbe      string `json:"lastSuccessfulProbe,omitempty"`
	FirstFailedProbe         string `json:"firstFailedProbe,omitempty"`
	ConsecutiveProbeFailures int    `json:"consecutiveProbeFailures"`
	InitialParentPID         *int   `json:"initialParentPid,omitempty"`
}

type ServicePreferencesRecord struct {
	DisplayName            string `json:"displayName,omitempty"`
	Pinned                 bool   `json:"pinned"`
	Ignored                bool   `json:"ignored"`
	ClassificationOverride string `json:"classificationOverride,omitempty"`
}

type StalenessRecord struct {
	PossiblyForgotten bool     `json:"possiblyForgotten"`
	Reasons           []string `json:"reasons"`
}

type ServiceRecord struct {
	ID                 string                   `json:"id"`
	LogicalID          string                   `json:"logicalId"`
	Listener           ListenerRecord           `json:"listener"`
	Process            ProcessRecord            `json:"process"`
	Project            *ProjectRecord           `json:"project,omitempty"`
	Application        *ApplicationRecord       `json:"application,omitempty"`
	ProjectEvidence    string                   `json:"projectEvidence,omitempty"`
	ProjectCandidates  []string                 `json:"projectCandidates"`
	HostProcessProject *ProjectRecord           `json:"hostProcessProject,omitempty"`
	Management         ManagementRecord         `json:"management"`
	Observation        ObservationRecord        `json:"observation"`
	Relevance          RelevanceRecord          `json:"relevance"`
	History            ServiceHistoryRecord     `json:"history"`
	Preferences        ServicePreferencesRecord `json:"preferences"`
	Staleness          StalenessRecord          `json:"staleness"`
	Route              *RouteRecord             `json:"route,omitempty"`
}

type ScanDocument struct {
	SchemaVersion int             `json:"schemaVersion"`
	GeneratedAt   string          `json:"generatedAt"`
	Host          string          `json:"host"`
	Services      []ServiceRecord `json:"services"`
}

func newScanDocument(services []ServiceRecord, hostname string) ScanDocument {
	return ScanDocument{
		SchemaVersion: 1,
		GeneratedAt:   time.Now().UTC().Format(time.RFC3339Nano),
		Host:          hostname,
		Services:      services,
	}
}
