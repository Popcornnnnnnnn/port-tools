import { useMemo, useRef, useState } from "react";
import {
  ArrowSquareOut, Check, Copy, Info, LinkSimple, MagnifyingGlass,
  PencilSimple, Power, Question, ShieldCheck, Stop, X,
} from "@phosphor-icons/react";

const initialApps = [
  { id: "prototype", name: "Menu prototype", address: "port-tools.localhost:4111", project: "port-tools", branch: "main", port: 41731, age: "12m", status: "verified", framework: "Vite", pid: 92631, command: "npm run dev -- --port 41731", evidence: ["HTTP 200 responded in 18 ms", "Content-Type is text/html", "Project package and Vite client matched"] },
  { id: "receiver", name: "WebRTC receiver", address: "127.0.0.1:4319", project: "phone-3d-ui-studio", branch: "codex/receiver-buffer", port: 4319, age: "9m", status: "lan", framework: "Vite", pid: 92904, command: "npm run receiver -- --host 0.0.0.0", evidence: ["HTTP 200 responded in 31 ms", "Content-Type is text/html", "Bound to 0.0.0.0 and reachable on the LAN"] },
  { id: "station-control", name: "stationControl", address: "station-control.localhost:4111", project: "Boonray", branch: "main", port: 32222, age: "2d 11h", status: "forgotten", framework: "Vite", pid: 56642, command: "npm run dev -- --port 32222", evidence: ["HTTP 200 responded in 24 ms", "Process has been running for 2d 11h", "Parent terminal is no longer running"] },
  { id: "fixture", name: "Scanner fixtures", address: "127.0.0.1:4945", project: "port-tools", branch: "main", port: 4945, age: "4h", status: "verified", framework: "Python HTTP", pid: 81104, command: "python3 evaluation/fixtures/http_fixture.py", evidence: ["HTTP 200 responded in 7 ms", "Page title matched fixture metadata", "Script lives inside this project"] },
  { id: "studio", name: "3D Studio", address: "phone-studio.localhost:4111", project: "phone-3d-ui-studio", branch: "codex/receiver-buffer", port: 4317, age: "14h 55m", status: "verified", framework: "Vite", pid: 61407, command: "npm run dev -- --port 4317", evidence: ["HTTP 200 responded in 22 ms", "Vite HMR endpoint detected", "Git worktree and package name matched"] },
];

const statusCopy = { verified: "Web verified", lan: "LAN exposed", forgotten: "Possibly forgotten" };

function Status({ value }) {
  return <span className={`status ${value}`}><span className="status-dot" />{statusCopy[value]}</span>;
}

function Modal({ label, children, onClose }) {
  return <div className="modal-backdrop" onMouseDown={onClose}><section className="modal" role="dialog" aria-modal="true" aria-label={label} onMouseDown={(event) => event.stopPropagation()}>{children}</section></div>;
}

export function App() {
  const [apps, setApps] = useState(initialApps);
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState("prototype");
  const [modal, setModal] = useState(null);
  const [aliasDraft, setAliasDraft] = useState("");
  const [toast, setToast] = useState("");
  const searchRef = useRef(null);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return apps;
    return apps.filter((app) => [app.name, app.address, app.project, app.branch, app.port].join(" ").toLowerCase().includes(needle));
  }, [apps, query]);
  const selected = apps.find((app) => app.id === selectedId) ?? null;
  const visibleSelected = filtered.find((app) => app.id === selectedId) ?? filtered[0] ?? null;

  const flash = (message) => { setToast(message); window.setTimeout(() => setToast(""), 2100); };
  const changeQuery = (value) => {
    setQuery(value);
    const needle = value.trim().toLowerCase();
    const next = !needle ? apps : apps.filter((app) => [app.name, app.address, app.project, app.branch, app.port].join(" ").toLowerCase().includes(needle));
    if (next[0]) setSelectedId(next[0].id);
  };
  const moveSelection = (step) => {
    if (!filtered.length) return;
    const current = Math.max(0, filtered.findIndex((app) => app.id === visibleSelected?.id));
    const next = (current + step + filtered.length) % filtered.length;
    setSelectedId(filtered[next].id);
  };
  const openSelected = () => { if (visibleSelected) flash(`Would open ${visibleSelected.address}`); };
  const handleKeyDown = (event) => {
    if (event.key === "ArrowDown") { event.preventDefault(); moveSelection(1); }
    if (event.key === "ArrowUp") { event.preventDefault(); moveSelection(-1); }
    if (event.key === "Enter") { event.preventDefault(); openSelected(); }
    if (event.key === "Escape") { setQuery(""); searchRef.current?.blur(); }
  };
  const beginRename = (app) => {
    setSelectedId(app.id);
    setAliasDraft(app.address.includes(".localhost") ? app.address.split(".localhost")[0] : app.name.replace(/[^a-z0-9]+/gi, "-").toLowerCase());
    setModal("rename");
  };
  const saveAlias = () => {
    const slug = aliasDraft.trim().toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "");
    if (!selected || !slug) return;
    setApps((current) => current.map((app) => app.id === selected.id ? { ...app, address: `${slug}.localhost:4111` } : app));
    setModal(null); flash(`Stable name saved · ${slug}.localhost:4111`);
  };
  const stopSelected = () => {
    if (!selected) return;
    const remaining = apps.filter((app) => app.id !== selected.id);
    setApps(remaining); setSelectedId(remaining[0]?.id ?? null); setModal(null); flash(`Stopped ${selected.name} gracefully · port ${selected.port} released`);
  };

  if (new URLSearchParams(window.location.search).has("qa")) {
    return <main className="qa-stage"><figure><figcaption>Visual target · Direction 3</figcaption><img src="/@fs/Users/forge/Workspace/port-tools/design/prototypes/search-first/qa-source-cropped.png" alt="Search-first command launcher visual target" /></figure><figure><figcaption>Implementation · Search-first launcher</figcaption><iframe src="/?embed=1" title="Port Tools direction 3 implementation" /></figure></main>;
  }

  const embedded = new URLSearchParams(window.location.search).has("embed");
  return (
    <main className={`stage ${embedded ? "embedded" : ""}`} onKeyDown={(event) => { if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); searchRef.current?.focus(); } }}>
      <section className="launcher" aria-label="Port Tools search-first prototype">
        <header><h1>Port Tools</h1><span>{apps.length} web apps</span></header>
        <label className="search-field"><MagnifyingGlass size={19} /><input ref={searchRef} autoFocus value={query} onChange={(event) => changeQuery(event.target.value)} onKeyDown={handleKeyDown} placeholder="Search apps, ports, or projects" aria-label="Search apps, ports, or projects" /><kbd>⌘K</kbd></label>

        <div className="results" aria-live="polite">
          {filtered.length ? filtered.map((app) => {
            const active = app.id === visibleSelected?.id;
            return <article className={`result ${active ? "selected" : ""}`} key={app.id}>
              <button className="result-row" onClick={() => setSelectedId(app.id)} aria-pressed={active}>
                <span className={`app-dot ${app.status}`} />
                <span className="app-copy"><strong>{app.name}</strong><span>{app.address}</span><small>{app.project}/{app.branch} · :{app.port} · {app.age}</small></span>
                <Status value={app.status} />
              </button>
              {active && <div className="action-strip">
                <button className="primary-action" onClick={openSelected}><ArrowSquareOut size={15} />Open</button>
                <button onClick={() => flash("Address copied")}><Copy size={15} />Copy</button>
                <button onClick={() => beginRename(app)}><PencilSimple size={15} />Rename</button>
                <button onClick={() => setModal("stop")}><Stop size={15} />Stop</button>
                <span className="action-separator" />
                <button className="why-action" onClick={() => setModal("evidence")}><Question size={15} weight="bold" />Why Web?</button>
              </div>}
            </article>;
          }) : <div className="empty-state"><MagnifyingGlass size={24} /><strong>No matching Web apps</strong><span>Try a project name, port, or local address.</span></div>}
        </div>

        <footer><span><kbd>↑↓</kbd> Select</span><span><kbd>↵</kbd> Open</span><span><kbd>esc</kbd> Close</span><b>DEMO</b></footer>
      </section>
      {toast && <div className="toast"><Check size={15} weight="bold" />{toast}</div>}

      {modal === "evidence" && selected && <Modal label="Web classification evidence" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon green"><ShieldCheck size={20} weight="fill" /></div><div><h2>Why this is a Web app</h2><p>{selected.name} · port {selected.port}</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="evidence-list">{selected.evidence.map((item) => <div key={item}><Check size={16} weight="bold" /><span>{item}</span></div>)}</div><div className="modal-footer"><button className="primary wide" onClick={() => setModal(null)}>Done</button></div></Modal>}

      {modal === "rename" && selected && <Modal label="Rename local address" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon blue"><LinkSimple size={20} /></div><div><h2>Rename local address</h2><p>The name keeps working when the port changes.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><label className="field-label" htmlFor="local-name">Local name</label><div className="alias-field"><input id="local-name" autoFocus value={aliasDraft} onChange={(event) => setAliasDraft(event.target.value)} /><span>.localhost:4111</span></div><p className="field-help"><ShieldCheck size={14} weight="fill" />Local to this Mac · no hosts file or admin access</p><div className="route-preview"><span>Current</span><b>{selected.address}</b><span>Becomes</span><b>{aliasDraft || "your-name"}.localhost:4111</b></div><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="primary" disabled={!aliasDraft.trim()} onClick={saveAlias}>Save name</button></div></Modal>}

      {modal === "stop" && selected && <Modal label="Review graceful stop" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon red"><Power size={20} /></div><div><h2>Stop {selected.name}?</h2><p>Review the exact process before anything happens.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="impact-card"><div><span>Process</span><b>{selected.framework} · PID {selected.pid}</b></div><div><span>Command</span><code>{selected.command}</code></div><div><span>Will release</span><b>127.0.0.1:{selected.port}</b></div><div><span>Keeps running</span><b>{apps.length - 1} other Web apps</b></div></div><p className="stop-note"><Info size={15} />This prototype simulates a graceful stop and port-release check. It never touches a real process.</p><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="danger" onClick={stopSelected}><Stop size={16} />Stop gracefully</button></div></Modal>}
    </main>
  );
}
