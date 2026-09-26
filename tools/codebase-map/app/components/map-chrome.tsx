"use client";

import { useEffect, useMemo, useRef } from "react";
import type { CodebaseGraph, MapArea } from "../../lib/graph";
import { deriveAreaFlows } from "../../lib/area-flows";

export function MapHeader({ sourceUrl }: { sourceUrl: string | null }) {
  return <header className="map-header">
    <div className="map-brand" aria-label="Intentive">
      <svg className="brand-mark" width="30" height="30" viewBox="0 0 30 30" fill="none" aria-hidden="true">
        <path d="M8 8h14M8 8v14m0 0h14M22 8v14M8 8l14 14" stroke="currentColor" strokeWidth="1.5" />
        <rect x="4.5" y="4.5" width="7" height="7" rx="2" fill="currentColor" />
        <rect x="18.5" y="4.5" width="7" height="7" rx="2" fill="currentColor" />
        <rect x="4.5" y="18.5" width="7" height="7" rx="2" fill="currentColor" />
        <rect x="18.5" y="18.5" width="7" height="7" rx="2" fill="currentColor" />
      </svg><span>Intentive</span>
    </div>
    <span className="header-divider" aria-hidden="true" />
    <div className="map-title"><h1>Codebase map</h1><span className="map-subtitle">Open a subsystem and follow its connections.</span></div>
    {sourceUrl && <a className="source-link" href={sourceUrl} aria-label="View source" target="_blank" rel="noreferrer"><span>View source</span><span className="source-symbol" aria-hidden="true">↗</span></a>}
  </header>;
}

export function MapNavigation({ graph, areas, active, onOverview, onNavigate }: {
  graph: CodebaseGraph | null; areas: MapArea[]; active?: MapArea; onOverview: () => void; onNavigate: (id: string) => void;
}) {
  const flows = useMemo(() => graph && active ? deriveAreaFlows(graph, active.id) : null, [graph, active]);
  const currentTitle = useRef<HTMLSpanElement>(null);
  const overviewButton = useRef<HTMLButtonElement>(null);
  const followingFlow = useRef(false);
  useEffect(() => {
    if (!followingFlow.current) return;
    followingFlow.current = false;
    currentTitle.current?.focus({ preventScroll: true });
  }, [active?.id]);
  return <nav className="map-navigation" aria-label="Map navigation">
    <div className="map-navigation-row">
    <div className="map-breadcrumb">
      <button ref={overviewButton} type="button" onClick={onOverview} aria-current={active ? undefined : "page"}>Overview</button>
      {active ? <><span aria-hidden="true">/</span><span ref={currentTitle} tabIndex={-1} className="current-area" title={active.fullTitle}
        onKeyDown={event => { if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); onOverview(); overviewButton.current?.focus({ preventScroll: true }); } }}>{active.number} · {active.title}</span></>
        : <span className="area-total">{areas.length} areas</span>}
    </div>
    <label className="area-jump"><span className="visually-hidden">Jump to area</span>
      <select aria-label="Jump to area" value={active?.id ?? ""} onChange={event => event.target.value ? onNavigate(event.target.value) : onOverview()} disabled={!areas.length}>
        <option value="">Jump to area…</option>
        {areas.map(area => <option key={area.id} value={area.id}>{area.number} · {area.title}</option>)}
      </select>
    </label>
    </div>
    <section className={`subsystem-flows${flows?.related.length ? " has-undirected" : ""}`} aria-label="Subsystem inflow and outflow" data-area-id={active?.id ?? ""}
      onKeyDown={event => { event.stopPropagation(); if (event.key === "Escape") { event.preventDefault(); onOverview(); overviewButton.current?.focus({ preventScroll: true }); } }}>
      {(["incoming", "outgoing"] as const).map(direction => <div className={`flow-column flow-${direction}`} key={direction}>
        <h2><span aria-hidden="true">{direction === "incoming" ? "↘" : "↗"}</span>{direction === "incoming" ? "Inflow" : "Outflow"}
          {flows && <span className="flow-count">{flows[direction].length}</span>}</h2>
        {flows ? <ul key={`${active!.id}-${direction}`} aria-label={direction === "incoming" ? "Inflow" : "Outflow"} tabIndex={0}>
          {flows[direction].map(flow => {
            const remote = areas.find(area => area.id === flow.remoteAreaId)!;
            return <li key={flow.edgeId} data-flow-edge-id={flow.edgeId}>
              <span className="flow-label">{flow.label}</span>
              <button type="button" onClick={() => { followingFlow.current = true; onNavigate(remote.id); }} aria-label={`${direction === "incoming" ? "From" : "To"} ${remote.number} · ${remote.title}`}>
                <span>{direction === "incoming" ? "From" : "To"}</span> {remote.number} · {remote.title}<span aria-hidden="true"> ↗</span>
              </button>
            </li>;
          })}
          {!flows[direction].length && <li className="flow-empty">No {direction === "incoming" ? "incoming" : "outgoing"} flows recorded in the map.</li>}
        </ul> : <p className="flow-empty">{direction === "incoming" ? "What enters a subsystem, and where it comes from." : "What leaves a subsystem, and where it goes."}<span> Select a subsystem to explore.</span></p>}
      </div>)}
      {!!flows?.related.length && <span className="undirected-flows">{flows.related.length} additional connections have no direction recorded.</span>}
    </section>
  </nav>;
}

export function MapToolbar({ fullscreen, supportsFullscreen, onFullscreen }: {
  fullscreen: boolean; supportsFullscreen: boolean; onFullscreen: () => void;
}) {
  if (!supportsFullscreen) return null;
  return <div className="canvas-toolbar" role="group" aria-label="Diagram controls">
    <button className="tool-button" type="button" aria-label={fullscreen ? "Exit fullscreen" : "Enter fullscreen"} title="Fullscreen" onClick={onFullscreen}>⛶</button>
  </div>;
}

export function MapFooter({ commit, sourceUrl }: { commit: string | null; sourceUrl: string | null }) {
  return <footer className="map-footer"><div className="version-info"><span className="version-dot" aria-hidden="true" />
    {commit ? <><span>Built from</span>{sourceUrl ? <a href={sourceUrl} className="commit-link" data-testid="commit-link" target="_blank" rel="noreferrer" title={`View diagram at commit ${commit}`}>{commit.slice(0, 7)} ↗</a> : <code>{commit.slice(0, 7)}</code>}</>
      : <span>Local build · commit unavailable</span>}
  </div><span className="footer-caption">One codebase. A clearer view.</span></footer>;
}
