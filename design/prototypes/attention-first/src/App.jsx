import { useMemo, useState } from "react";
import {
  ArrowClockwise, ArrowSquareOut, Check, Copy, DotsThree, GlobeSimple, Info,
  LinkSimple, Power, ShieldCheck, StopCircle, Warning, X,
} from "@phosphor-icons/react";

const initialServices = [
  { id: "receiver", name: "WebRTC receiver", project: "phone-3d-ui-studio", branch: "codex/receiver-buffer", port: 4319, alias: "", age: "9m", attention: "lan", framework: "Vite", pid: 92904, command: "npm run receiver -- --host 0.0.0.0", evidence: ["HTTP 200 responded in 31 ms", "Content-Type is text/html", "Bound to 0.0.0.0 and reachable on the LAN"] },
  { id: "station-control", name: "stationControl", project: "Boonray", branch: "main", port: 32222, alias: "station-control.localhost:4111", age: "2d 11h", attention: "forgotten", framework: "Vite", pid: 56642, command: "npm run dev -- --port 32222", evidence: ["HTTP 200 responded in 24 ms", "Process has been running for 2d 11h", "Parent terminal is no longer running"] },
  { id: "prototype", name: "Menu prototype", project: "port-tools", branch: "main", port: 41731, alias: "port-tools.localhost:4111", age: "12m", framework: "Vite", pid: 92631, command: "npm run dev -- --port 41731", evidence: ["HTTP 200 responded in 18 ms", "Content-Type is text/html", "Vite client and project package matched"] },
  { id: "fixture", name: "Scanner fixtures", project: "port-tools", branch: "main", port: 4945, alias: "", age: "4h", framework: "Python HTTP", pid: 81104, command: "python3 evaluation/fixtures/http_fixture.py", evidence: ["HTTP 200 responded in 7 ms", "Page title matched fixture metadata", "Script lives inside this project"] },
  { id: "studio", name: "3D Studio", project: "phone-3d-ui-studio", branch: "codex/receiver-buffer", port: 4317, alias: "phone-studio.localhost:4111", age: "14h 55m", framework: "Vite", pid: 61407, command: "npm run dev -- --port 4317", evidence: ["HTTP 200 responded in 22 ms", "Vite HMR endpoint detected", "Git worktree and package name matched"] },
];

const getAddress = (service) => service.alias || `127.0.0.1:${service.port}`;

function Modal({ children, label, onClose }) {
  return <div className="modal-backdrop" onMouseDown={onClose}><section className="modal" role="dialog" aria-modal="true" aria-label={label} onMouseDown={(event) => event.stopPropagation()}>{children}</section></div>;
}

function StatusPill({ attention }) {
  if (attention === "lan") return <span className="pill attention">LAN exposed</span>;
  if (attention === "forgotten") return <span className="pill attention">Possibly forgotten</span>;
  return <span className="pill verified">Web verified</span>;
}

function ServiceCopy({ service }) {
  const secondary = service.id === "receiver"
    ? `${service.project} · :${service.port}`
    : service.attention
      ? `${service.project} · ${getAddress(service)} · ${service.age}`
      : `${getAddress(service)} · ${service.project}/${service.branch} · ${service.age}`;
  return <span className="service-copy"><strong>{service.name}</strong><span>{secondary}</span></span>;
}

export function App() {
  const [services, setServices] = useState(initialServices);
  const [selectedId, setSelectedId] = useState(null);
  const [modal, setModal] = useState(null);
  const [aliasDraft, setAliasDraft] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  const [toast, setToast] = useState("");

  const selected = services.find((service) => service.id === selectedId) ?? null;
  const needsAttention = useMemo(() => services.filter((service) => service.attention), [services]);
  const ready = useMemo(() => services.filter((service) => !service.attention), [services]);
  const flash = (message) => { setToast(message); window.setTimeout(() => setToast(""), 2200); };
  const choose = (service, nextModal) => { setSelectedId(service.id); setModal(nextModal); };
  const beginAlias = (service) => {
    setSelectedId(service.id);
    setAliasDraft(service.alias ? service.alias.split(".localhost")[0] : service.name.replace(/[^a-z0-9]+/gi, "-").toLowerCase());
    setModal("alias");
  };
  const refresh = () => { setRefreshing(true); window.setTimeout(() => { setRefreshing(false); flash(`Scan complete · ${services.length} Web apps found`); }, 750); };
  const saveAlias = () => {
    const slug = aliasDraft.trim().toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "");
    if (!selected || !slug) return;
    setServices((current) => current.map((service) => service.id === selected.id ? { ...service, alias: `${slug}.localhost:4111` } : service));
    setModal(null); flash(`Stable name saved · ${slug}.localhost:4111`);
  };
  const stopService = () => {
    if (!selected) return;
    setServices((current) => current.filter((service) => service.id !== selected.id));
    setModal(null); setSelectedId(null); flash(`Stopped ${selected.name} gracefully · port ${selected.port} released`);
  };

  if (new URLSearchParams(window.location.search).has("qa")) {
    return <main className="qa-stage"><figure><figcaption>Visual target · Direction 2</figcaption><img src="/@fs/Users/forge/Workspace/port-tools/design/prototypes/attention-first/qa-source-cropped.png" alt="Attention-first visual target" /></figure><figure><figcaption>Implementation · Attention-first triage</figcaption><iframe src="/?embed=1" title="Port Tools direction 2 implementation" /></figure></main>;
  }

  const embedded = new URLSearchParams(window.location.search).has("embed");
  return (
    <main className={`stage ${embedded ? "embedded" : ""}`}>
      {!embedded && <div className="mac-menu-bar" aria-hidden="true"><GlobeSimple size={15} weight="fill" /><span className="menu-title">Port Tools</span><span className="menu-spacer" /><span>Thu Sep 4&nbsp;&nbsp;11:42</span></div>}
      <section className="panel" aria-label="Port Tools attention-first prototype">
        <header className="panel-header">
          <div className="title-line"><h1>Port Tools</h1></div>
          <div className="header-tools"><span className="attention-count"><span />{needsAttention.length} need attention</span><button className="icon-button" aria-label="Refresh services" onClick={refresh}><ArrowClockwise size={17} className={refreshing ? "spin" : ""} /></button><button className="icon-button" aria-label="More options" onClick={() => flash("Settings are outside this prototype")}><DotsThree size={21} weight="bold" /></button></div>
        </header>

        <div className="inventory">
          {needsAttention.length > 0 && <section className="attention-section" aria-labelledby="needs-attention"><h2 id="needs-attention">Needs attention</h2>{needsAttention.map((service) => <div className="service-row attention-row" key={service.id}><span className="status-dot amber" /><ServiceCopy service={service} /><StatusPill attention={service.attention} /><button className="text-action" onClick={() => choose(service, "review")}>Review</button></div>)}</section>}
          <section className="ready-section" aria-labelledby="ready-to-open"><h2 id="ready-to-open">Ready to open</h2>{ready.map((service) => <div className="service-row ready-row" key={service.id} role="button" tabIndex="0" onClick={() => choose(service, "detail")} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") choose(service, "detail"); }}><span className="status-dot green" /><ServiceCopy service={service} /><StatusPill />{service.alias ? <button className="row-hit" aria-label={`Inspect ${service.name}`} tabIndex="-1" /> : <button className="text-action name-action" onClick={(event) => { event.stopPropagation(); beginAlias(service); }}>Name</button>}</div>)}</section>
        </div>

        <footer className="panel-footer"><span><b>DEMO</b> · {services.length} web apps</span><button onClick={() => flash("Dashboard is outside this menu prototype")}>Open dashboard</button></footer>
      </section>
      {toast && <div className="toast"><Check size={16} weight="bold" />{toast}</div>}

      {modal === "review" && selected && <Modal label={`Review ${selected.name}`} onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon amber"><Warning size={20} weight="fill" /></div><div><h3>{selected.attention === "lan" ? "Visible on your local network" : "This app may have been forgotten"}</h3><p>{selected.name} · {getAddress(selected)}</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="review-summary">{selected.attention === "lan" ? <><p>It is a verified Web app, but it listens on every network interface instead of only this Mac.</p><dl><div><dt>Bind scope</dt><dd>0.0.0.0:{selected.port}</dd></div><div><dt>Reachable from</dt><dd>Devices on this LAN</dd></div></dl></> : <><p>It still responds normally, but its age and missing parent terminal make it worth reviewing.</p><dl><div><dt>Running for</dt><dd>{selected.age}</dd></div><div><dt>Terminal</dt><dd>No active parent found</dd></div></dl></>}</div><div className="evidence-strip"><Info size={15} /><span>{selected.evidence.join(" · ")}</span></div><div className="modal-footer"><button onClick={() => { setModal(null); flash("Kept visible in Needs attention"); }}>Keep for now</button><button onClick={() => setModal("stop")}><StopCircle size={15} />Review stop</button><button className="primary" onClick={() => flash(`Would open ${getAddress(selected)}`)}><ArrowSquareOut size={15} />Open app</button></div></Modal>}

      {modal === "detail" && selected && <Modal label={`${selected.name} details`} onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon green"><ShieldCheck size={20} weight="fill" /></div><div><h3>{selected.name}</h3><p>Verified Web app · {selected.framework}</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="detail-address"><span>Local address</span><strong>{getAddress(selected)}</strong></div><div className="detail-facts"><div><span>Project</span><b>{selected.project}</b></div><div><span>Branch</span><b>{selected.branch}</b></div><div><span>Port</span><b>{selected.port}</b></div><div><span>Running</span><b>{selected.age}</b></div></div><button className="why-button" onClick={() => setModal("evidence")}><Info size={15} /><span>Why Port Tools classifies this as Web</span></button><div className="modal-footer"><button onClick={() => flash("Address copied")}><Copy size={15} />Copy</button><button onClick={() => beginAlias(selected)}><LinkSimple size={15} />{selected.alias ? "Rename" : "Name"}</button><button onClick={() => setModal("stop")}><StopCircle size={15} />Stop</button><button className="primary" onClick={() => flash(`Would open ${getAddress(selected)}`)}><ArrowSquareOut size={15} />Open</button></div></Modal>}

      {modal === "evidence" && selected && <Modal label="Web classification evidence" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon green"><ShieldCheck size={20} weight="fill" /></div><div><h3>Why this is a Web app</h3><p>{selected.name} · port {selected.port}</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="evidence-list">{selected.evidence.map((item) => <div key={item}><Check size={16} weight="bold" /><span>{item}</span></div>)}</div><div className="modal-footer"><button className="primary wide" onClick={() => setModal("detail")}>Done</button></div></Modal>}

      {modal === "alias" && selected && <Modal label="Claim a stable local name" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon blue"><LinkSimple size={20} /></div><div><h3>Give this app a stable name</h3><p>It keeps working when the port changes.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><label className="field-label" htmlFor="local-name">Local name</label><div className="alias-field"><input id="local-name" autoFocus value={aliasDraft} onChange={(event) => setAliasDraft(event.target.value)} /><span>.localhost:4111</span></div><p className="field-help"><ShieldCheck size={14} weight="fill" />Local to this Mac · no hosts file or admin access</p><div className="route-preview"><span>Current</span><b>127.0.0.1:{selected.port}</b><span>Becomes</span><b>{aliasDraft || "your-name"}.localhost:4111</b></div><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="primary" disabled={!aliasDraft.trim()} onClick={saveAlias}>Save name</button></div></Modal>}

      {modal === "stop" && selected && <Modal label="Review graceful stop" onClose={() => setModal(null)}><div className="modal-header"><div className="modal-icon red"><Power size={20} /></div><div><h3>Stop {selected.name}?</h3><p>Review the exact process before anything happens.</p></div><button className="icon-button" aria-label="Close" onClick={() => setModal(null)}><X size={18} /></button></div><div className="impact-card"><div><span>Process</span><b>{selected.framework} · PID {selected.pid}</b></div><div><span>Command</span><code>{selected.command}</code></div><div><span>Will release</span><b>127.0.0.1:{selected.port}</b></div><div><span>Keeps running</span><b>{services.length - 1} other Web apps</b></div></div><p className="stop-note"><Info size={15} />This prototype simulates a graceful stop and port-release check. It never touches a real process.</p><div className="modal-footer"><button onClick={() => setModal(null)}>Cancel</button><button className="danger" onClick={stopService}><StopCircle size={16} />Stop gracefully</button></div></Modal>}
    </main>
  );
}
