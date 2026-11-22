package main

import (
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestProbeBackoffPolicy(t *testing.T) {
	now := time.Date(2026, 10, 25, 0, 0, 0, 0, time.Local)
	for _, test := range []struct {
		name        string
		observation ObservationRecord
		process     ProcessRecord
		initialTTL  time.Duration
		backoff     bool
		settled     bool
	}{
		{"JSON 404", ObservationRecord{Role: "service", HTTP: &HTTPRecord{Status: pointer(404), ContentType: pointer("application/json; charset=utf-8")}}, ProcessRecord{}, 30 * time.Second, true, false},
		{"JSON 503", ObservationRecord{Role: "service", HTTP: &HTTPRecord{Status: pointer(503), ContentType: pointer("application/json")}}, ProcessRecord{}, 3 * time.Second, true, false},
		{"problem JSON", ObservationRecord{Role: "service", HTTP: &HTTPRecord{Status: pointer(429), ContentType: pointer("Application/Problem+JSON")}}, ProcessRecord{}, 30 * time.Second, true, false},
		{"unknown", ObservationRecord{Classification: "unknown"}, ProcessRecord{}, 30 * time.Second, true, false},
		{"young unknown", ObservationRecord{Classification: "unknown"}, ProcessRecord{Started: pointer(now.Add(-time.Second).Format("Mon Jan 2 15:04:05 2006"))}, 3 * time.Second, true, false},
		{"suspected page", ObservationRecord{Classification: "suspected-web", Role: "page"}, ProcessRecord{}, 3 * time.Second, true, false},
		{"invalid HTTP response", ObservationRecord{Classification: "non-web", Protocol: "tcp"}, ProcessRecord{}, 30 * time.Second, true, false},
		{"HTTP 501 DMAP", ObservationRecord{Role: "service", HTTP: &HTTPRecord{Status: pointer(501), ContentType: pointer("application/x-dmap-tagged")}}, ProcessRecord{}, 30 * time.Second, true, false},
		{"HTTP 501 HTML error", ObservationRecord{Role: "service", HTTP: &HTTPRecord{Status: pointer(501), ContentType: pointer("text/html;charset=utf-8"), Title: pointer("Error response")}}, ProcessRecord{}, 30 * time.Second, true, false},
		{"HTML startup", ObservationRecord{HTTP: &HTTPRecord{Status: pointer(503), ContentType: pointer("text/html"), Title: pointer("Starting")}}, ProcessRecord{}, 3 * time.Second, false, false},
		{"CDP", ObservationRecord{Classification: "confirmed-web", Protocol: "cdp", Role: "service", HTTP: &HTTPRecord{Status: pointer(200), ContentType: pointer("text/html")}}, ProcessRecord{}, 30 * time.Second, false, false},
		{"young non-JSON 404", ObservationRecord{Role: "service", HTTP: &HTTPRecord{Status: pointer(404), ContentType: pointer("text/plain")}}, ProcessRecord{Started: pointer(now.Add(-5 * time.Second).Format("Mon Jan 2 15:04:05 2006"))}, 30 * time.Second, false, false},
		{"HTML page", ObservationRecord{Role: "page", HTTP: &HTTPRecord{Status: pointer(200), ContentType: pointer("text/html"), Title: pointer("Dashboard")}}, ProcessRecord{}, 0, false, true},
		{"JSON with title", ObservationRecord{HTTP: &HTTPRecord{Status: pointer(404), ContentType: pointer("application/json"), Title: pointer("Management")}}, ProcessRecord{}, 0, false, true},
		{"protected page", ObservationRecord{Role: "page", HTTP: &HTTPRecord{Status: pointer(401), ContentType: pointer("application/json")}}, ProcessRecord{}, 0, false, true},
		{"redirect", ObservationRecord{Role: "page", HTTP: &HTTPRecord{Status: pointer(302), ContentType: pointer("application/json")}}, ProcessRecord{}, 0, false, true},
		{"successful JSON", ObservationRecord{HTTP: &HTTPRecord{Status: pointer(200), ContentType: pointer("application/json")}}, ProcessRecord{}, 0, false, true},
		{"mature non-JSON 404", ObservationRecord{Role: "service", HTTP: &HTTPRecord{Status: pointer(404), ContentType: pointer("text/plain")}}, ProcessRecord{Started: pointer(now.Add(-time.Hour).Format("Mon Jan 2 15:04:05 2006"))}, 0, false, true},
		{"Redis", ObservationRecord{Classification: "non-web", Protocol: "redis"}, ProcessRecord{}, 0, false, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			var entry cachedObservation
			if test.settled {
				entry = nextCachedObservation(test.observation, test.process, entry, now)
				if !entry.settled || entry.retryDelay != 0 || !entry.expiresAt.IsZero() {
					t.Fatalf("expected settled observation, got %#v", entry)
				}
			} else {
				retryTTLs := []time.Duration{test.initialTTL, time.Minute, 2 * time.Minute, 4 * time.Minute, 5 * time.Minute, 5 * time.Minute}
				for attempt, want := range retryTTLs {
					entry = nextCachedObservation(test.observation, test.process, entry, now)
					if entry.settled {
						t.Fatalf("attempt %d unexpectedly settled: %#v", attempt+1, entry)
					}
					if !test.backoff {
						want = test.initialTTL
					}
					if got := entry.expiresAt.Sub(now); got != want {
						t.Fatalf("attempt %d: TTL = %v, want %v", attempt+1, got, want)
					}
				}
			}
			// Recovery clears accumulated scheduling state, even for the same identity.
			healthy := ObservationRecord{Role: "page", HTTP: &HTTPRecord{Status: pointer(200), ContentType: pointer("text/html")}}
			entry = nextCachedObservation(healthy, test.process, entry, now)
			if !entry.settled || entry.retryDelay != 0 || !entry.expiresAt.IsZero() {
				t.Fatalf("healthy observation retained backoff or was not settled: %#v", entry)
			}
			entry = nextCachedObservation(test.observation, test.process, entry, now)
			if test.settled {
				if !entry.settled || entry.retryDelay != 0 {
					t.Fatalf("settled observation lost settled state: %#v", entry)
				}
			} else if entry.expiresAt.Sub(now) != test.initialTTL {
				t.Fatal("new failure inherited backoff after recovery")
			}
		})
	}
}

// Each fixture has a unique listener identity. Keep helpers independent of the
// cache key's representation so these checks exercise the real cache lookup.
func resetProbeCache(t *testing.T) {
	t.Helper()
	observationCache.Lock()
	previous := observationCache.entries
	observationCache.entries = map[string]cachedObservation{}
	observationCache.Unlock()
	t.Cleanup(func() {
		observationCache.Lock()
		observationCache.entries = previous
		observationCache.Unlock()
	})
}

func onlyProbeCacheEntry(t *testing.T) cachedObservation {
	t.Helper()
	observationCache.Lock()
	defer observationCache.Unlock()
	if len(observationCache.entries) != 1 {
		t.Fatalf("expected one cache entry, got %d", len(observationCache.entries))
	}
	for _, entry := range observationCache.entries {
		return entry
	}
	return cachedObservation{}
}

func expireProbeCache(t *testing.T) {
	t.Helper()
	observationCache.Lock()
	defer observationCache.Unlock()
	for key, entry := range observationCache.entries {
		entry.expiresAt = time.Now().Add(-time.Millisecond)
		observationCache.entries[key] = entry
	}
}

func TestObserveCachedBacksOffJSONErrorsAndRecovers(t *testing.T) {
	for _, status := range []int{401, 404, 429, 503} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			resetProbeCache(t)
			var requests atomic.Int64
			var ready atomic.Bool
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				requests.Add(1)
				if r.URL.Path != "/" || !strings.HasPrefix(r.UserAgent(), "port-tools-core/") {
					t.Errorf("unexpected probe: %s %s", r.URL.Path, r.UserAgent())
				}
				if ready.Load() {
					w.Header().Set("Content-Type", "text/html")
					_, _ = io.WriteString(w, "<title>Ready</title>")
					return
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(status)
				_, _ = io.WriteString(w, `{"error":"not a page"}`)
			}))
			defer server.Close()
			listener := discoveredListener{PID: 1234, Address: "127.0.0.1", Port: server.Listener.Addr().(*net.TCPAddr).Port}
			for attempt := 0; attempt < 7; attempt++ {
				observation := observeCached(listener, ProcessRecord{}, ManagementRecord{})
				if observation.HTTP == nil || *observation.HTTP.Status != status || observation.Role != "service" {
					t.Fatalf("error evidence changed: %#v", observation)
				}
				for scan := 0; scan < 5; scan++ {
					cached := observeCached(listener, ProcessRecord{}, ManagementRecord{})
					if cached.ProbedAt != observation.ProbedAt {
						t.Fatal("rescan replaced cached probe evidence")
					}
				}
				if got := requests.Load(); got != int64(attempt+1) {
					t.Fatalf("root requests = %d after %d attempts", got, attempt+1)
				}
				if attempt > 0 && onlyProbeCacheEntry(t).retryDelay < time.Minute {
					t.Fatal("repeated JSON error retained short retry")
				}
				if attempt == 1 {
					// Simulate an ordinary 30-second rescan within the minute-long
					// backoff, without waiting or changing the accumulated retry delay.
					observationCache.Lock()
					for key, entry := range observationCache.entries {
						entry.expiresAt = entry.expiresAt.Add(-30 * time.Second)
						observationCache.entries[key] = entry
					}
					observationCache.Unlock()
					observeCached(listener, ProcessRecord{}, ManagementRecord{})
					if requests.Load() != 2 {
						t.Fatal("ordinary rescan repeated root request during backoff")
					}
				}
				expireProbeCache(t)
			}
			ready.Store(true)
			recovered := observeCached(listener, ProcessRecord{}, ManagementRecord{})
			recoveredEntry := onlyProbeCacheEntry(t)
			if recovered.Role != "page" || *recovered.HTTP.Title != "Ready" || !recoveredEntry.settled || recoveredEntry.retryDelay != 0 {
				t.Fatalf("page did not settle after bounded backoff: %#v (entry=%#v)", recovered, recoveredEntry)
			}
			beforeSettled := requests.Load()
			expireProbeCache(t)
			if cached := observeCached(listener, ProcessRecord{}, ManagementRecord{}); cached.ProbedAt != recovered.ProbedAt || requests.Load() != beforeSettled {
				t.Fatal("settled listener was re-probed after expiresAt passed")
			}
			ready.Store(false)
			observationCache.Lock()
			for key, entry := range observationCache.entries {
				entry.settled = false
				entry.expiresAt = time.Now().Add(-time.Millisecond)
				observationCache.entries[key] = entry
			}
			observationCache.Unlock()
			observeCached(listener, ProcessRecord{}, ManagementRecord{})
			want := 30 * time.Second
			if status >= 500 {
				want = 3 * time.Second
			}
			if got := onlyProbeCacheEntry(t).retryDelay; got != want {
				t.Fatalf("recovery did not reset backoff: %v", got)
			}
		})
	}
}

// Exercise HTTPS fallback after an HTTP connection failure. Unlike a real
// TLS-only listener, httptest otherwise answers plain HTTP with a valid 400.
type dropFirstProbeListener struct {
	net.Listener
	dropped bool
}

func (listener *dropFirstProbeListener) Accept() (net.Conn, error) {
	if !listener.dropped {
		connection, err := listener.Listener.Accept()
		if err != nil {
			return nil, err
		}
		_ = connection.Close()
		listener.dropped = true
	}
	return listener.Listener.Accept()
}

func TestObserveCachedPreservesPageAndProtocolDiscovery(t *testing.T) {
	for _, scheme := range []string{"http", "https"} {
		for _, page := range []string{"root", "protected", "management"} {
			t.Run(scheme+"/"+page, func(t *testing.T) {
				resetProbeCache(t)
				var requests atomic.Int64
				server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					requests.Add(1)
					if page == "protected" {
						w.Header().Set("Content-Type", "application/json")
						w.WriteHeader(401)
						return
					}
					if page == "management" && r.URL.Path == "/" {
						w.Header().Set("Content-Type", "application/json")
						_, _ = io.WriteString(w, `{"message":"API with management page"}`)
						return
					}
					w.Header().Set("Content-Type", "text/html")
					_, _ = io.WriteString(w, "<title>Management</title>")
				}))
				if scheme == "https" {
					server.Listener = &dropFirstProbeListener{Listener: server.Listener}
					server.StartTLS()
				} else {
					server.Start()
				}
				defer server.Close()
				// Use the URL because the HTTPS test wraps the original listener.
				_, portText, err := net.SplitHostPort(strings.TrimPrefix(server.URL, scheme+"://"))
				if err != nil {
					t.Fatal(err)
				}
				port, err := strconv.Atoi(portText)
				if err != nil {
					t.Fatal(err)
				}
				listener := discoveredListener{PID: 1234, Address: "127.0.0.1", Port: port}
				process := ProcessRecord{Command: pointer("dsh web --no-open")}
				observation := observeCached(listener, process, ManagementRecord{})
				if observation.Protocol != scheme || observation.Role != "page" || onlyProbeCacheEntry(t).retryDelay != 0 {
					t.Fatalf("page discovery changed: %#v", observation)
				}
				if page == "management" && observation.HTTP.Path != "/management.html" {
					t.Fatalf("management page path = %q", observation.HTTP.Path)
				}
				before := requests.Load()
				observeCached(listener, process, ManagementRecord{})
				if requests.Load() != before {
					t.Fatal("page observation was not cached")
				}
			})
		}
	}
}

func TestObserveCachedBackoffIdentityChanges(t *testing.T) {
	for _, change := range []string{"PID", "address", "port", "start", "command", "source", "container", "container port"} {
		t.Run(change, func(t *testing.T) {
			resetProbeCache(t)
			var requests atomic.Int64
			handler := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				requests.Add(1)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(404)
			})
			server := httptest.NewServer(handler)
			defer server.Close()
			listener := discoveredListener{PID: 1234, Address: "127.0.0.1", Port: server.Listener.Addr().(*net.TCPAddr).Port}
			process := ProcessRecord{Started: pointer("Mon Oct 19 01:00:00 2026"), Command: pointer("api-proxy")}
			management := ManagementRecord{Source: "unmanaged"}
			observeCached(listener, process, management)
			expireProbeCache(t)
			observeCached(listener, process, management)
			if onlyProbeCacheEntry(t).retryDelay != time.Minute {
				t.Fatal("fixture did not accumulate backoff")
			}
			switch change {
			case "PID":
				listener.PID++
			case "address":
				listener.Address = "0.0.0.0"
			case "port":
				other := httptest.NewServer(handler)
				defer other.Close()
				listener.Port = other.Listener.Addr().(*net.TCPAddr).Port
			case "start":
				process.Started = pointer("Mon Oct 19 02:00:00 2026")
			case "command":
				process.Command = pointer("different-proxy")
			case "source":
				management.Source = "docker"
			case "container":
				management.ContainerID = "new-container"
			case "container port":
				management.ContainerPort = "8080/tcp"
			}
			observeCached(listener, process, management)
			if requests.Load() != 3 {
				t.Fatal("changed identity inherited cached probe suppression")
			}
			observationCache.Lock()
			defer observationCache.Unlock()
			var fresh int
			for _, entry := range observationCache.entries {
				if entry.retryDelay == 30*time.Second {
					fresh++
				}
			}
			if fresh != 1 {
				t.Fatal("changed identity inherited accumulated backoff")
			}
		})
	}
}

func TestObserveCachedBacksOffFailedAndTimedOutProbes(t *testing.T) {
	for _, failure := range []string{"disconnect", "timeout", "partial response"} {
		t.Run(failure, func(t *testing.T) {
			resetProbeCache(t)
			var requests atomic.Int64
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				requests.Add(1)
				if failure != "disconnect" {
					if failure == "partial response" {
						w.Header().Set("Content-Type", "application/json")
						_, _ = io.WriteString(w, `{"message":"unfinished`)
						w.(http.Flusher).Flush()
					}
					// Wait for the real probe deadline without adding fixture sleeps.
					<-r.Context().Done()
					return
				}
				connection, _, err := w.(http.Hijacker).Hijack()
				if err != nil {
					t.Error(err)
					return
				}
				_ = connection.Close()
			}))
			defer server.Close()
			listener := discoveredListener{PID: 1234, Address: "127.0.0.1", Port: server.Listener.Addr().(*net.TCPAddr).Port}
			process := ProcessRecord{Command: pointer("vite")}
			for attempt := 0; attempt < 2; attempt++ {
				observation := observeCached(listener, process, ManagementRecord{})
				classification, role := "suspected-web", "page"
				if failure == "partial response" {
					classification, role = "non-web", "service"
				}
				if observation.HTTP != nil || observation.Classification != classification || observation.Role != role {
					t.Fatalf("failure evidence changed: %#v", observation)
				}
				before := requests.Load()
				if before == 0 {
					t.Fatal("fixture did not receive root probes")
				}
				for scan := 0; scan < 5; scan++ {
					observeCached(listener, process, ManagementRecord{})
				}
				if requests.Load() != before {
					t.Fatal("failed probes repeated before cache expiry")
				}
				want := 3 * time.Second
				if failure == "partial response" {
					want = 30 * time.Second
				}
				if attempt == 1 {
					want = time.Minute
				}
				if onlyProbeCacheEntry(t).retryDelay != want {
					t.Fatal("failed probe did not accumulate backoff")
				}
				expireProbeCache(t)
			}
		})
	}
}

func TestObserveCachedDoesNotReprobeSettledListeners(t *testing.T) {
	for _, kind := range []struct {
		name         string
		contentType  string
		body         string
		wantRequests int64
		wantRole     string
	}{
		{"HTML page", "text/html; charset=utf-8", "<title>Watchpost</title>", 1, "page"},
		{"JSON API", "application/json", `{"service":"watchpost"}`, int64(1 + len(webUIPaths)), "service"},
	} {
		t.Run(kind.name, func(t *testing.T) {
			resetProbeCache(t)
			var requests atomic.Int64
			handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				requests.Add(1)
				if r.URL.Path == "/" {
					w.Header().Set("Content-Type", kind.contentType)
					_, _ = io.WriteString(w, kind.body)
					return
				}
				http.NotFound(w, r)
			})
			server := httptest.NewServer(handler)
			defer server.Close()

			listener := discoveredListener{PID: 4321, Address: "127.0.0.1", Port: server.Listener.Addr().(*net.TCPAddr).Port}
			process := ProcessRecord{Started: pointer("Sat Nov 21 18:40:35 2026"), Command: pointer("watchpost serve")}
			management := ManagementRecord{Source: "unmanaged"}

			first := observeCached(listener, process, management)
			if first.Role != kind.wantRole || requests.Load() != kind.wantRequests {
				t.Fatalf("initial observation = %#v, requests = %d (want %d)", first, requests.Load(), kind.wantRequests)
			}
			if !onlyProbeCacheEntry(t).settled {
				t.Fatal("healthy 200 listener was not marked settled")
			}

			observationCache.Lock()
			for key, entry := range observationCache.entries {
				entry.expiresAt = time.Now().Add(-24 * time.Hour)
				observationCache.entries[key] = entry
			}
			observationCache.Unlock()

			for scan := 0; scan < 5; scan++ {
				cached := observeCached(listener, process, management)
				if cached.ProbedAt != first.ProbedAt {
					t.Fatal("settled listener refreshed observation")
				}
			}
			if got := requests.Load(); got != kind.wantRequests {
				t.Fatalf("settled listener re-probed: got %d requests, want %d", got, kind.wantRequests)
			}

			// Identity changes must bypass the settled cache and probe immediately.
			for _, change := range []string{"PID", "Started", "Command", "Port", "ContainerID"} {
				nextListener := listener
				nextProcess := process
				nextManagement := management
				switch change {
				case "PID":
					nextListener.PID++
				case "Started":
					nextProcess.Started = pointer("Sun Nov 22 09:00:00 2026")
				case "Command":
					nextProcess.Command = pointer("watchpost serve --port 8788")
				case "Port":
					other := httptest.NewServer(handler)
					defer other.Close()
					nextListener.Port = other.Listener.Addr().(*net.TCPAddr).Port
				case "ContainerID":
					nextManagement.ContainerID = "container-123"
				}
				before := requests.Load()
				observeCached(nextListener, nextProcess, nextManagement)
				if requests.Load() != before+kind.wantRequests {
					t.Fatalf("identity change %s did not trigger fresh probe", change)
				}
			}
		})
	}
}

func TestObserveCachedBacksOffHTTP501(t *testing.T) {
	for _, tc := range []struct {
		name        string
		contentType string
		body        string
	}{
		{"DMAP 501", "application/x-dmap-tagged", ""},
		{"Python 501", "text/html;charset=utf-8", "<title>Error response</title>"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resetProbeCache(t)
			var requests atomic.Int64
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				requests.Add(1)
				w.Header().Set("Content-Type", tc.contentType)
				w.WriteHeader(http.StatusNotImplemented)
				_, _ = io.WriteString(w, tc.body)
			}))
			defer server.Close()

			listener := discoveredListener{PID: 5555, Address: "127.0.0.1", Port: server.Listener.Addr().(*net.TCPAddr).Port}
			observeCached(listener, ProcessRecord{}, ManagementRecord{})
			entry := onlyProbeCacheEntry(t)
			if entry.settled || entry.retryDelay != 30*time.Second || time.Until(entry.expiresAt) < 25*time.Second {
				t.Fatalf("501 initial cache state = %#v (ttl=%v)", entry, time.Until(entry.expiresAt))
			}

			expireProbeCache(t)
			observeCached(listener, ProcessRecord{}, ManagementRecord{})
			if got := onlyProbeCacheEntry(t).retryDelay; got != time.Minute {
				t.Fatalf("501 second retryDelay = %v, want 1m", got)
			}

			expireProbeCache(t)
			observeCached(listener, ProcessRecord{}, ManagementRecord{})
			if got := onlyProbeCacheEntry(t).retryDelay; got != 2*time.Minute {
				t.Fatalf("501 third retryDelay = %v, want 2m", got)
			}
		})
	}
}

func TestPruneObservationCacheRemovesDepartedSettledListeners(t *testing.T) {
	resetProbeCache(t)
	scanStartedAt := time.Now()
	activeKey := "active-settled"
	departedKey := "departed-settled"
	concurrentKey := "concurrent-settled"
	recentPendingKey := "recent-pending"
	stalePendingKey := "stale-pending"

	observationCache.Lock()
	observationCache.entries = map[string]cachedObservation{
		activeKey:        {settled: true, lastSeenAt: scanStartedAt.Add(-time.Minute)},
		departedKey:      {settled: true, lastSeenAt: scanStartedAt.Add(-time.Minute)},
		concurrentKey:    {settled: true, lastSeenAt: scanStartedAt.Add(time.Millisecond)},
		recentPendingKey: {settled: false, expiresAt: scanStartedAt.Add(-time.Minute), lastSeenAt: scanStartedAt.Add(-time.Minute)},
		stalePendingKey:  {settled: false, expiresAt: scanStartedAt.Add(-3 * time.Minute), lastSeenAt: scanStartedAt.Add(-3 * time.Minute)},
	}
	observationCache.Unlock()

	pruneObservationCache(map[string]struct{}{activeKey: {}}, scanStartedAt)

	observationCache.Lock()
	defer observationCache.Unlock()
	if _, ok := observationCache.entries[activeKey]; !ok {
		t.Fatal("active settled entry was pruned")
	}
	if _, ok := observationCache.entries[departedKey]; ok {
		t.Fatal("departed settled entry was retained")
	}
	if _, ok := observationCache.entries[concurrentKey]; !ok {
		t.Fatal("concurrent entry newer than scan start was pruned")
	}
	if _, ok := observationCache.entries[recentPendingKey]; !ok {
		t.Fatal("recent non-settled entry within grace window was pruned")
	}
	if _, ok := observationCache.entries[stalePendingKey]; ok {
		t.Fatal("stale non-settled entry past grace window was retained")
	}
}
