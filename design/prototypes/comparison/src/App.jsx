import { useState } from "react";

const directions = [
  {
    id: "project",
    number: "1",
    name: "项目优先",
    note: "按项目和分支浏览",
    tradeoff: "上下文完整，列表层级最多",
    url: "http://127.0.0.1:45123/",
    width: 394,
    height: 700,
  },
  {
    id: "attention",
    number: "2",
    name: "异常优先",
    note: "先处理暴露与遗忘",
    tradeoff: "总览最直接，搜索较弱",
    url: "http://127.0.0.1:45124/",
    width: 394,
    height: 700,
  },
  {
    id: "search",
    number: "3",
    name: "搜索优先",
    note: "键盘快速查找打开",
    tradeoff: "操作最快，被动发现较弱",
    url: "http://127.0.0.1:45125/",
    width: 420,
    height: 560,
  },
];

export function App() {
  const [selectedId, setSelectedId] = useState("search");
  const selected = directions.find((direction) => direction.id === selectedId);

  return (
    <main className="comparison-page">
      <header className="page-header">
        <div><span className="eyebrow">PORT TOOLS</span><h1>三个方向放在一起看</h1><p>先比较信息层级和密度，再在下面完整体验选中的方向。</p></div>
        <span className="prototype-label">INTERACTIVE PROTOTYPES</span>
      </header>

      <section className="overview" aria-label="三个设计方向概览">
        {directions.map((direction) => {
          const active = direction.id === selectedId;
          const scale = direction.id === "search" ? 0.405 : 0.43;
          return <button className={`direction-card ${active ? "active" : ""}`} key={direction.id} onClick={() => setSelectedId(direction.id)} aria-pressed={active}>
            <span className="card-heading"><b>{direction.number}</b><span><strong>{direction.name}</strong><small>{direction.note}</small></span></span>
            <span className="thumbnail" style={{ height: direction.id === "search" ? 242 : 301 }}>
              <iframe title={`方向 ${direction.number} 缩略图`} src={direction.url} style={{ width: direction.width, height: direction.height, transform: `scale(${scale})` }} tabIndex="-1" />
            </span>
            <span className="tradeoff">{direction.tradeoff}</span>
          </button>;
        })}
      </section>

      <section className="focus-area" aria-label={`方向 ${selected.number} 完整体验`}>
        <header><div><span>当前放大</span><h2>方向 {selected.number} · {selected.name}</h2><p>{selected.note}；{selected.tradeoff}。</p></div><span className="live-status"><i />可交互</span></header>
        <div className="full-preview" style={{ minHeight: selected.height + 34 }}>
          <iframe key={selected.id} title={`方向 ${selected.number} 完整交互版本`} src={selected.url} style={{ width: selected.width, height: selected.height }} />
        </div>
      </section>
    </main>
  );
}
