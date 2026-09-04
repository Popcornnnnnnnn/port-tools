import { useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowClockwise, ArrowSquareOut, CaretRight, Check, Code, Copy,
  DotsThree, FolderOpen, GitBranch, GlobeSimple, Info, LinkSimple,
  MagnifyingGlass, Network, Power, Question, ShieldCheck, StopCircle,
  TerminalWindow, Warning, X,
} from "@phosphor-icons/react";

const WEB_CLASSIFICATIONS = new Set(["confirmed-web", "suspected-web"]);
const EXPANDED_STORAGE_KEY = "port-tools.prototype.expanded-projects";
const ALIAS_STORAGE_KEY = "port-tools.prototype.aliases";

function loadStoredSet(key) {
  try {
    const value = JSON.parse(window.localStorage.getItem(key) || "[]");
    return Array.isArray(value) ? new Set(value) : new Set();
  } catch {
    return new Set();
  }
}

function loadStoredObject(key) {
  try {
    const value = JSON.parse(window.localStorage.getItem(key) || "{}");
    return value && typeof value === "object" ? value : {};
  } catch {
    return {};
  }
}

function compactPath(path) {
  if (!path) return "Unknown location";
  return path.replace(/^\/Users\/[^/]+/, "~");
}

function compactRemote(remote) {
  if (!remote) return "";
  return remote
    .replace(/^git@([^:]+):/, "$1/")
    .replace(/^https?:\/\//, "")
    .replace(/\.git$/, "");
}

function formatAge(started) {
  if (!started) return "";
  const timestamp = Date.parse(started);
  if (!Number.isFinite(timestamp)) return "";
  const minutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60000));
  if (minutes < 1) return "<1m";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ${minutes % 60}m`;
  return `${Math.floor(hours / 24)}d ${hours % 24}h`;
}

function serviceUrl(service) {
  const listener = service.listener || {};
  const address = ["0.0.0.0", "::", "*"].includes(listener.address)
    ? "127.0.0.1"
    : listener.address || "127.0.0.1";
  const protocol = service.observation?.protocol === "https" ? "https" : "http";
  const host = address.includes(":") ? `[${address}]` : address;
  return `${protocol}://${host}:${listener.port}`;
}

function commandAppName(service) {
  const command = service.process?.command || "";
  const match = command.match(/(?:^|\s)([^\s/]+\.(?:js|mjs|cjs|ts|py|rb))(?:\s|$)/i)
    || command.match(/(?:^|\s)(\/[^\s]+\.(?:js|mjs|cjs|ts|py|rb))(?:\s|$)/i);
  if (!match) return "";
  const filename = match[1].split("/").pop();
  return filename.replace(/\.(?:js|mjs|cjs|ts|py|rb)$/i, "");
}

function serviceName(service, application) {
  return service.observation?.http?.title
    || application?.name
    || service.observation?.framework
    || commandAppName(service)
    || service.process?.name
    || `Web service :${service.listener?.port}`;
}

function serviceSearchText(service) {
  return [
    service.id,
    service.listener?.port,
    service.listener?.address,
    service.process?.name,
    service.process?.command,
    service.process?.cwd,
    service.project?.name,
    service.project?.branch,
    service.project?.root,
    service.project?.remoteUrl,
    service.application?.name,
    service.application?.relativePath,
    service.observation?.framework,
    service.observation?.http?.title,
  ].filter(Boolean).join(" ").toLowerCase();
}

function groupInventory(services) {
  const groups = new Map();
  services.forEach((service) => {
    const project = service.project;
    const management = service.management || {};
    const projectIdentity = project?.root
      || service.application?.root
      || (management.source === "docker" && `docker:${management.containerName || management.containerId}`)
      || `process:${service.process?.pid}`;
    if (!groups.has(projectIdentity)) {
      groups.set(projectIdentity, {
        id: projectIdentity,
        name: project?.repositoryName || project?.name || management.containerName || service.application?.name || "Unassigned Web app",
        project,
        services: [],
        apps: new Map(),
      });
    }
    const group = groups.get(projectIdentity);
    const application = service.application;
    const appIdentity = application?.root || projectIdentity;
    if (!group.apps.has(appIdentity)) {
      group.apps.set(appIdentity, {
        id: appIdentity,
        name: application?.name || commandAppName(service) || group.name,
        application,
        services: [],
      });
    }
    group.services.push(service);
    group.apps.get(appIdentity).services.push(service);
  });
  return [...groups.values()].map((group) => ({
    ...group,
    apps: [...group.apps.values()].map((app) => ({
      ...app,
      services: app.services.sort((a, b) => a.listener.port - b.listener.port),
    })),
  }));
}

function StatusPill({ service }) {
  if (service.listener?.bindScope !== "loopback") {
    return <span className="pill warning"><Network size={12} weight="bold" />LAN exposed</span>;
  }
  if (service.observation?.classification === "suspected-web") {
    return <span className="pill stale"><Warning size={12} weight="fill" />Likely Web</span>;
  }
  return <span className="pill verified"><ShieldCheck size={12} weight="fill" />Web verified</span>;
}

function Modal({ children, onClose, label }) {
  return <div className="modal-backdrop" onMouseDown={onClose}><section className="modal" aria-label={label} role="dialog" aria-modal="true" onMouseDown={(event) => event.stopPropagation()}>{children}</section></div>;
}

export function App() {
  const [inventory, setInventory] = useState(null);
  const [expanded, setExpanded] = useState(() => loadStoredSet(EXPANDED_STORAGE_KEY));
  const [hasStoredExpansion] = useState(() => window.localStorage.getItem(EXPANDED_STORAGE_KEY) !== null);
  const [aliases, setAliases] = useState(() => loadStoredObject(ALIAS_STORAGE_KEY));
  const [selectedId, setSelectedId] = useState(null);
  const [modal, setModal] = useState(null);
  const [aliasDraft, setAliasDraft] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  const [scanError, setScanError] = useState("");
  const [toast, setToast] = useState("");
  const [query, setQuery] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const searchRef = useRef(null);
  const scanInFlight = useRef(false);

  const allServices = inventory?.services || [];
  const webServices = allServices.filter((service) => WEB_CLASSIFICATIONS.has(service.observation?.classification));
  const developmentServices = webServices.filter((service) => service.relevance?.developerRelevant);
  const otherWebCount = webServices.length - developmentServices.length;
  const otherListenerCount = allServices.length - webServices.length;
  const projects = useMemo(() => groupInventory(developmentServices), [developmentServices]);
  const selected = developmentServices.find((service) => service.id === selectedId) || null;

  const filteredProjects = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return projects;
    return projects.map((project) => {
      const projectText = [project.name, project.project?.branch, project.project?.root, project.project?.remoteUrl].filter(Boolean).join(" ").toLowerCase();
      if (projectText.includes(needle)) return project;
      const apps = project.apps.map((app) => {
        const appText = [app.name, app.application?.relativePath, app.application?.manifest].filter(Boolean).join(" ").toLowerCase();
        if (appText.includes(needle)) return app;
        return { ...app, services: app.services.filter((service) => serviceSearchText(service).includes(needle)) };
      }).filter((app) => app.services.length > 0);
      return { ...project, apps, services: apps.flatMap((app) => app.services) };
    }).filter((project) => project.services.length > 0);
  }, [projects, query]);

  const flash = (message) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 2300);
  };

  const refresh = async ({ quiet = false } = {}) => {
    if (scanInFlight.current) return;
    scanInFlight.current = true;
    if (!quiet) setRefreshing(true);
    try {
      const response = await fetch("/api/inventory", { cache: "no-store" });
      if (!response.ok) throw new Error(`Scan returned ${response.status}`);
      const next = await response.json();
      setInventory(next);
      setScanError("");
      if (!quiet) flash(`Scan complete · ${next.services.filter((service) => WEB_CLASSIFICATIONS.has(service.observation?.classification) && service.relevance?.developerRelevant).length} development Web apps`);
    } catch (error) {
      setScanError(error instanceof Error ? error.message : "Live scan unavailable");
    } finally {
      scanInFlight.current = false;
      setRefreshing(false);
    }
  };

  useEffect(() => {
    refresh({ quiet: true });
    const interval = window.setInterval(() => refresh({ quiet: true }), 30000);
    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!inventory || hasStoredExpansion || expanded.size > 0) return;
    setExpanded(new Set(projects.map((project) => project.id)));
  }, [inventory, projects, hasStoredExpansion, expanded.size]);

  useEffect(() => {
    window.localStorage.setItem(EXPANDED_STORAGE_KEY, JSON.stringify([...expanded]));
  }, [expanded]);

  useEffect(() => {
    window.localStorage.setItem(ALIAS_STORAGE_KEY, JSON.stringify(aliases));
  }, [aliases]);

  useEffect(() => {
    const handleShortcut = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setSearchOpen(true);
        window.setTimeout(() => searchRef.current?.focus(), 0);
      }
      if (event.key === "Escape" && searchOpen) {
        setQuery("");
        setSearchOpen(false);
      }
    };
    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, [searchOpen]);

  const toggleProject = (projectId) => {
    if (query.trim()) return;
    setExpanded((current) => {
      const next = new Set(current);
      next.has(projectId) ? next.delete(projectId) : next.add(projectId);
      return next;
    });
  };

  const beginAlias = (service) => {
    setSelectedId(service.id);
    setAliasDraft(aliases[service.id] || service.application?.name?.replace(/[^a-z0-9]+/gi, "-").toLowerCase() || "local-app");
    setModal("alias");
  };

  const saveAlias = () => {
    const slug = aliasDraft.trim().toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "");
    if (!slug || !selected) return;
    setAliases((current) => ({ ...current, [selected.id]: slug }));
    setModal(null);
    flash(`Prototype name saved · ${slug}.localhost`);
  };

  const copyAddress = async (service) => {
    const value = aliases[service.id] ? `${aliases[service.id]}.localhost` : serviceUrl(service);
    await navigator.clipboard?.writeText(value);
    flash("Address copied");
  };

  const copyProjectPath = async (path) => {
    await navigator.clipboard?.writeText(path || "");
    flash("Project path copied");
  };

  if (new URLSearchParams(window.location.search).has("qa")) {
    return <main className="qa-stage"><figure><figcaption>Selected sources · Direction 1 + Direction 3</figcaption><div className="source-stack"><img src="/@fs/Users/forge/Workspace/port-tools/design/prototypes/comparison/source-direction1.jpg" alt="Project-first source" /><img src="/@fs/Users/forge/Workspace/port-tools/design/prototypes/search-first/implementation-main.jpg" alt="Search-first source" /></div></figure><figure><figcaption>Implementation · Live hybrid prototype</figcaption><iframe src="/" title="Port Tools implementation" /></figure></main>;
  }

  return (
    <main className="stage">
      <div className="mac-menu-bar" aria-hidden="true"><GlobeSimple size={15} weight="fill" /><span className="menu-title">Port Tools</span><span className="menu-spacer" /><span>Local prototype</span></div>
      <section className="panel" aria-label="Port Tools live prototype">
        <header className="panel-header">
          <div>
            <div className="title-line"><h1>Port Tools</h1><span className="live-badge"><i />LIVE</span></div>
            <p>{inventory ? `${projects.length} projects · ${developmentServices.length} Web apps` : "Scanning local Web apps…"}</p>
          </div>
          <div className="header-actions">
            <button className={`icon-button ${searchOpen ? "active" : ""}`} aria-label="Search apps" onClick={() => { setSearchOpen((value) => !value); window.setTimeout(() => searchRef.current?.focus(), 0); }}><MagnifyingGlass size={18} /></button>
            <button className="icon-button" aria-label="Refresh services" onClick={() => refresh()}><ArrowClockwise size={18} className={refreshing ? "spin" : ""} /></button>
            <button className="icon-button" aria-label="More options" onClick={() => flash("Settings come with the native menu bar build")}><DotsThree size={21} weight="bold" /></button>
          </div>
        </header>

        {searchOpen && <label className="search-field"><MagnifyingGlass size={16} /><input ref={searchRef} autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Project, app, port, branch…" aria-label="Search projects, apps, ports, or branches" />{query ? <button aria-label="Clear search" onClick={() => setQuery("")}><X size={14} /></button> : <kbd>⌘K</kbd>}</label>}

        <div className="inventory">
          {scanError && <div className="scan-error"><Warning size={15} weight="fill" /><span><b>Live scan unavailable</b>{scanError}</span><button onClick={() => refresh()}>Retry</button></div>}
          {!inventory && !scanError && <div className="loading-state"><ArrowClockwise size={18} className="spin" /><span>Checking active Web services…</span></div>}
          {inventory && filteredProjects.length === 0 && <div className="empty-state"><MagnifyingGlass size={22} /><strong>{query ? "No matching Web apps" : "No development Web apps found"}</strong><span>{query ? "Try a project name, app, port, or branch." : "They will appear automatically when you start one."}</span></div>}

          {filteredProjects.map((project) => {
            const isOpen = query.trim() ? true : expanded.has(project.id);
            const warningCount = project.services.filter((service) => service.listener?.bindScope !== "loopback" || service.observation?.classification === "suspected-web").length;
            const remote = compactRemote(project.project?.remoteUrl);
            return <article className="project" key={project.id}>
              <button className="project-heading" onClick={() => toggleProject(project.id)} aria-expanded={isOpen}>
                <CaretRight size={13} weight="bold" className={isOpen ? "project-caret open" : "project-caret"} />
                <span className={`project-status ${warningCount ? "attention" : ""}`} />
                <span className="project-copy"><strong>{project.name}</strong><span><GitBranch size={13} />{project.project?.branch || "No Git branch"}{remote && <><i>·</i>{remote}</>}</span></span>
                <span className={`project-summary ${warningCount ? "attention" : ""}`}>{warningCount ? `${warningCount} attention` : `${project.services.length} ${project.services.length === 1 ? "service" : "services"}`}</span>
              </button>

              {isOpen && <div className="project-body">
                {project.apps.map((app) => <section className="app-group" key={app.id}>
                  {project.apps.length > 1 && <div className="app-heading"><span>{app.name}</span><small>{app.application ? `${app.application.manifest} · ${app.application.relativePath}` : "command path"}</small></div>}
                  <div className="service-list">{app.services.map((service) => {
                    const isSelected = service.id === selectedId;
                    const alias = aliases[service.id];
                    const url = serviceUrl(service);
                    const displayAddress = alias ? `${alias}.localhost` : url.replace(/^https?:\/\//, "");
                    return <div className={`service ${isSelected ? "selected" : ""}`} key={service.id}>
                      <div className="service-main" role="button" tabIndex="0" onClick={() => setSelectedId(isSelected ? null : service.id)} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") setSelectedId(isSelected ? null : service.id); }} aria-expanded={isSelected}>
                        <span className="service-copy">
                          <span className="service-name-line"><strong>{serviceName(service, app.application)}</strong><StatusPill service={service} /></span>
                          <span className="address-line">{alias ? <LinkSimple size={13} /> : <TerminalWindow size={13} />}<b>{displayAddress}</b>{alias && <><i>·</i><span>:{service.listener.port}</span></>}<time>{formatAge(service.process?.started)}</time></span>
                        </span>
                      </div>
                      {isSelected && <div className="service-detail">
                        <div className="detail-actions">
                          <button className="primary" onClick={() => window.open(url, "_blank", "noopener,noreferrer")}><ArrowSquareOut size={15} />Open</button>
                          <button onClick={() => copyAddress(service)}><Copy size={15} />Copy</button>
                          <button onClick={() => beginAlias(service)}><LinkSimple size={15} />{alias ? "Rename" : "Name"}</button>
                          <button className="danger-quiet" onClick={() => setModal("stop")}><StopCircle size={15} />Stop</button>
                        </div>
                        <button className="evidence-button" onClick={() => setModal("evidence")}><Question size={15} weight="bold" /><span>Why this is a Web app</span><span>{service.observation?.framework || service.observation?.protocol} · HTTP {service.observation?.http?.status || "?"}</span><CaretRight size={13} /></button>
                        {project.project?.root && <button className="path-button" onClick={() => copyProjectPath(project.project.root)}><FolderOpen size={14} />{compactPath(project.project.root)}</button>}
                      </div>}
                    </div>;
                  })}</div>
                </section>)}
              </div>}
            </article>;
          })}

          {inventory && !query && <>
            <button className="collapsed-section" onClick={() => flash(`${otherWebCount} Web endpoints have no reliable project evidence`)}><span>Other Web endpoints</span><small>{otherWebCount}</small></button>
            <button className="collapsed-section" onClick={() => flash(`${otherListenerCount} non-Web or unknown listeners stay out of the default view`)}><span>Other listeners</span><small>{otherListenerCount}</small></button>
          </>}
        </div>
        <footer className="panel-footer"><span>{inventory?.generatedAt ? `Updated ${new Date(inventory.generatedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}` : "Local only"}</span><span>⌘K Search</span></footer>
      </section>

      {toast && <div className="toast"><Check size={16} weight="bold" />{toast}</div>}

      {modal === "evidence" && selected && <Modal label="Web classification evidence" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon green"><Code size={20} /></div><div><h2>Why this is a Web app</h2><p>{serviceName(selected, selected.application)} · port {selected.listener.port}</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="evidence-list">{(selected.observation?.evidence || []).map((item, index) => <div key={`${item.kind}-${index}`}><Check size={16} weight="bold" /><span>{item.kind.replace(/-/g, " ")}{item.value !== true ? ` · ${item.value}` : ""}</span></div>)}</div><dl className="facts"><div><dt>Project</dt><dd>{selected.project?.name || "Unassigned"}</dd></div><div><dt>Application</dt><dd>{selected.application?.name || "Project root"}</dd></div><div><dt>Process</dt><dd>{selected.process?.command}</dd></div><div><dt>Bind scope</dt><dd>{selected.listener?.bindScope === "loopback" ? "Loopback only · this Mac" : "Visible beyond loopback"}</dd></div></dl><div className="modal-footer"><button className="primary wide" onClick={() => setModal(null)}>Done</button></div></Modal>}

      {modal === "alias" && selected && <Modal label="Test a stable local name" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon blue"><LinkSimple size={20} /></div><div><h2>Test a stable name</h2><p>This prototype remembers the name, but does not route traffic yet.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><label className="field-label" htmlFor="local-name">Local name</label><div className="alias-field"><input id="local-name" autoFocus value={aliasDraft} onChange={(event) => setAliasDraft(event.target.value)} /><span>.localhost</span></div><p className="field-help"><Info size={14} />Saved in this browser for the trial.</p><div className="route-preview"><span>Current</span><b>{serviceUrl(selected).replace(/^https?:\/\//, "")}</b><span>Preview</span><b>{aliasDraft || "your-name"}.localhost</b></div><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="primary" disabled={!aliasDraft.trim()} onClick={saveAlias}>Save preview</button></div></Modal>}

      {modal === "stop" && selected && <Modal label="Preview graceful stop" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon red"><Power size={20} /></div><div><h2>Stop {serviceName(selected, selected.application)}?</h2><p>Review the impact without touching the real process.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="impact-card"><div><span>Process</span><b>{selected.process?.name} · PID {selected.process?.pid}</b></div><div><span>Command</span><code>{selected.process?.command}</code></div><div><span>Would release</span><b>{serviceUrl(selected).replace(/^https?:\/\//, "")}</b></div><div><span>Project</span><b>{selected.project?.name || "Unassigned"}</b></div></div><p className="stop-note"><Info size={15} />Trial mode never stops a real process. The packaged app will revalidate ownership before enabling this action.</p><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="danger" onClick={() => { setModal(null); flash("Preview complete · no process was stopped"); }}><StopCircle size={16} />Preview stop</button></div></Modal>}
    </main>
  );
}
