import { useState } from "react";
import {
  ArrowClockwise, ArrowSquareOut, CaretDown, Check, Code, Copy, DotsThree,
  FolderOpen, GitBranch, GlobeSimple, Info, LinkSimple,
  Network, Power, ShieldCheck, StopCircle, TerminalWindow,
  Warning, X,
} from "@phosphor-icons/react";

const initialProjects = [
  {
    id: "port-tools", name: "port-tools", branch: "main", worktree: "~/Workspace/port-tools",
    services: [
      { id: "prototype", name: "Menu prototype", framework: "Vite", port: 41731, alias: "port-tools.localhost:4111", age: "12m", state: "verified", exposure: "loopback", pid: 92631, command: "npm run dev -- --port 41731", title: "Port Tools — Menu prototype", evidence: ["HTTP 200 responded in 18 ms", "Content-Type is text/html", "Vite client and project package matched"] },
      { id: "fixture", name: "Scanner fixtures", framework: "Python HTTP", port: 4945, alias: "", age: "4h", state: "verified", exposure: "loopback", pid: 81104, command: "python3 evaluation/fixtures/http_fixture.py", title: "Port tools fixture", evidence: ["HTTP 200 responded in 7 ms", "Page title matched fixture metadata", "Script lives inside this project"] },
    ],
  },
  {
    id: "phone-studio", name: "phone-3d-ui-studio", branch: "codex/receiver-buffer", worktree: "~/Workspace/phone-3d-ui-studio",
    services: [
      { id: "studio", name: "3D Studio", framework: "Vite", port: 4317, alias: "phone-studio.localhost:4111", age: "14h 55m", state: "verified", exposure: "loopback", pid: 61407, command: "npm run dev -- --port 4317", title: "Phone 3D UI Studio", evidence: ["HTTP 200 responded in 22 ms", "Vite HMR endpoint detected", "Git worktree and package name matched"] },
      { id: "receiver", name: "WebRTC receiver", framework: "Vite", port: 4319, alias: "", age: "9m", state: "verified", exposure: "lan", pid: 92904, command: "npm run receiver -- --host 0.0.0.0", title: "Receiver benchmark", evidence: ["HTTP 200 responded in 31 ms", "Content-Type is text/html", "Bound to 0.0.0.0 and reachable on the LAN"] },
    ],
  },
  {
    id: "boonray", name: "Boonray", branch: "main", worktree: "~/Workspace/Boonray",
    services: [
      { id: "station-control", name: "stationControl", framework: "Vite", port: 32222, alias: "station-control.localhost:4111", age: "2d 11h", state: "forgotten", exposure: "loopback", pid: 56642, command: "npm run dev -- --port 32222", title: "Station Control", evidence: ["HTTP 200 responded in 24 ms", "Process has been running for 2d 11h", "Parent terminal is no longer running"] },
    ],
  },
];

function StatusPill({ service }) {
  if (service.exposure === "lan") return <span className="pill warning"><Network size={12} weight="bold" />LAN exposed</span>;
  if (service.state === "forgotten") return <span className="pill stale"><Warning size={12} weight="fill" />Possibly forgotten</span>;
  return null;
}

function Modal({ children, onClose, label }) {
  return <div className="modal-backdrop" onMouseDown={onClose}><section className="modal" aria-label={label} role="dialog" aria-modal="true" onMouseDown={(event) => event.stopPropagation()}>{children}</section></div>;
}

export function App() {
  const [projects, setProjects] = useState(initialProjects);
  const [expanded, setExpanded] = useState(new Set(["port-tools", "phone-studio", "boonray"]));
  const [selectedId, setSelectedId] = useState(null);
  const [modal, setModal] = useState(null);
  const [aliasDraft, setAliasDraft] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  const [toast, setToast] = useState("");

  const services = projects.flatMap((project) => project.services.map((service) => ({ ...service, project })));
  const selected = services.find((service) => service.id === selectedId) ?? null;
  const flash = (message) => { setToast(message); window.setTimeout(() => setToast(""), 2200); };
  const toggleProject = (projectId) => setExpanded((current) => { const next = new Set(current); next.has(projectId) ? next.delete(projectId) : next.add(projectId); return next; });
  const refresh = () => { setRefreshing(true); window.setTimeout(() => { setRefreshing(false); flash("Scan complete · 5 development apps found"); }, 750); };
  const beginAlias = (service) => { setSelectedId(service.id); setAliasDraft(service.alias ? service.alias.split(".localhost")[0] : service.project.name.replace(/[^a-z0-9]+/gi, "-").toLowerCase()); setModal("alias"); };
  const saveAlias = () => {
    const slug = aliasDraft.trim().toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "");
    if (!slug || !selected) return;
    setProjects((current) => current.map((project) => ({ ...project, services: project.services.map((service) => service.id === selected.id ? { ...service, alias: `${slug}.localhost:4111` } : service) })));
    setModal(null); flash(`Stable name saved · ${slug}.localhost:4111`);
  };
  const stopService = () => {
    if (!selected) return;
    setProjects((current) => current.map((project) => ({ ...project, services: project.services.filter((service) => service.id !== selected.id) })).filter((project) => project.services.length > 0));
    setModal(null); setSelectedId(null); flash(`Stopped ${selected.name} gracefully · port ${selected.port} released`);
  };

  if (new URLSearchParams(window.location.search).has("qa")) {
    return <main className="qa-stage"><figure><figcaption>Visual source · Port Menu</figcaption><img src="/@fs/Users/forge/Workspace/port-tools/evaluation/screenshots/01-port-menu-inventory.png" alt="Port Menu source screenshot" /></figure><figure><figcaption>Direction 1 · Project-first control center</figcaption><iframe src="/" title="Port Tools implementation" /></figure></main>;
  }

  return (
    <main className="stage">
      <div className="mac-menu-bar" aria-hidden="true"><GlobeSimple size={15} weight="fill" /><span className="menu-title">Port Tools</span><span className="menu-spacer" /><span>Thu Sep 4&nbsp;&nbsp;11:42</span></div>
      <section className="panel" aria-label="Port Tools prototype">
        <header className="panel-header">
          <div><div className="title-line"><h1>Port Tools</h1><span className="demo-badge">DEMO</span></div><p>{services.length} Web apps</p></div>
          <div className="header-actions"><button className="icon-button" aria-label="Refresh services" onClick={refresh}><ArrowClockwise size={18} className={refreshing ? "spin" : ""} /></button><button className="icon-button" aria-label="More options" onClick={() => flash("Settings are outside this prototype")}><DotsThree size={21} weight="bold" /></button></div>
        </header>
        <div className="inventory">
          {projects.map((project) => {
            const isOpen = expanded.has(project.id);
            return <article className="project" key={project.id}>
              <button className="project-heading" onClick={() => toggleProject(project.id)} aria-expanded={isOpen}><span className="project-status" /><span className="project-copy"><strong>{project.name}</strong><span><GitBranch size={14} />{project.branch}</span></span><small>{project.services.length}</small><CaretDown size={16} className={isOpen ? "caret open" : "caret"} /></button>
              {isOpen && <div className="service-list">{project.services.map((service) => {
                const isSelected = service.id === selectedId;
                return <div className={`service ${isSelected ? "selected" : ""}`} key={service.id}>
                  <div className="service-main" role="button" tabIndex="0" onClick={() => setSelectedId(isSelected ? null : service.id)} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") setSelectedId(isSelected ? null : service.id); }} aria-expanded={isSelected}><span className="service-copy"><span className="service-name-line"><strong>{service.name}</strong><StatusPill service={service} /></span><span className="address-line">{service.alias ? <><LinkSimple size={13} /><b>{service.alias}</b><i>·</i><span>:{service.port}</span></> : <><TerminalWindow size={13} /><b>127.0.0.1:{service.port}</b><i>·</i><button className="inline-link" onClick={(event) => { event.stopPropagation(); beginAlias({ ...service, project }); }}>Name it</button></>}<time>{service.age}</time></span></span><CaretDown size={14} className={isSelected ? "caret open" : "caret"} /></div>
                  {isSelected && <div className="service-detail"><div className="detail-actions"><button className="primary" onClick={() => flash(`Would open ${service.alias || `127.0.0.1:${service.port}`}`)}><ArrowSquareOut size={15} />Open</button><button onClick={() => flash("Address copied")}><Copy size={15} />Copy</button><button onClick={() => beginAlias({ ...service, project })}><LinkSimple size={15} />{service.alias ? "Rename" : "Name"}</button><button className="danger-quiet" onClick={() => setModal("stop")}><StopCircle size={15} />Stop</button></div><button className="evidence-button" onClick={() => setModal("evidence")}><Info size={15} /><span>Why this is a Web app</span><span>{service.framework} · HTTP 200</span><CaretDown size={13} /></button><button className="path-button" onClick={() => flash(`Would reveal ${project.worktree}`)}><FolderOpen size={14} />{project.worktree}</button></div>}
                </div>;
              })}</div>}
            </article>;
          })}
          <button className="collapsed-section" onClick={() => flash("2 valid Web endpoints without project evidence")}><CaretDown size={14} className="caret" /><span>Other Web endpoints</span><small>2</small></button>
          <button className="collapsed-section" onClick={() => flash("28 non-Web or unknown listeners stay out of the default view")}><CaretDown size={14} className="caret" /><span>Other listeners</span><small>28</small></button>
        </div>
      </section>
      {toast && <div className="toast"><Check size={16} weight="bold" />{toast}</div>}
      {modal === "evidence" && selected && <Modal label="Web classification evidence" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon green"><Code size={20} /></div><div><h2>Why this is a Web app</h2><p>{selected.name} · port {selected.port}</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="evidence-list">{selected.evidence.map((item) => <div key={item}><Check size={16} weight="bold" /><span>{item}</span></div>)}</div><dl className="facts"><div><dt>Page title</dt><dd>{selected.title}</dd></div><div><dt>Process</dt><dd>{selected.command}</dd></div><div><dt>Bind scope</dt><dd>{selected.exposure === "lan" ? "All interfaces · visible on LAN" : "Loopback only · this Mac"}</dd></div></dl><div className="modal-footer"><button className="primary wide" onClick={() => setModal(null)}>Got it</button></div></Modal>}
      {modal === "alias" && selected && <Modal label="Claim a stable local name" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon blue"><LinkSimple size={20} /></div><div><h2>Give this app a stable name</h2><p>It will keep working when the port changes.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><label className="field-label">Local name</label><div className="alias-field"><input autoFocus value={aliasDraft} onChange={(event) => setAliasDraft(event.target.value)} /><span>.localhost:4111</span></div><p className="field-help"><ShieldCheck size={14} weight="fill" />Local to this Mac · no hosts file or admin access</p><div className="route-preview"><span>Current</span><b>127.0.0.1:{selected.port}</b><span>Becomes</span><b>{aliasDraft || "your-name"}.localhost:4111</b></div><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="primary" disabled={!aliasDraft.trim()} onClick={saveAlias}>Save name</button></div></Modal>}
      {modal === "stop" && selected && <Modal label="Review graceful stop" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon red"><Power size={20} /></div><div><h2>Stop {selected.name}?</h2><p>Review the exact process before anything happens.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="impact-card"><div><span>Process</span><b>{selected.framework} · PID {selected.pid}</b></div><div><span>Command</span><code>{selected.command}</code></div><div><span>Will release</span><b>127.0.0.1:{selected.port}</b></div><div><span>Will keep running</span><b>{services.length - 1} other development apps</b></div></div><p className="stop-note"><Info size={15} />Port Tools sends a graceful stop and verifies the port is released. Force stop is not used automatically.</p><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="danger" onClick={stopService}><StopCircle size={16} />Stop gracefully</button></div></Modal>}
    </main>
  );
}
