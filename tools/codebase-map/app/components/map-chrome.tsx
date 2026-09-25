"use client";

import type { MapArea } from "../../lib/graph";

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
    <div className="map-title"><h1>Codebase map</h1><span className="map-subtitle">Zoom into subsystems and follow their connections.</span></div>
    {sourceUrl && <a className="source-link" href={sourceUrl} aria-label="View source" target="_blank" rel="noreferrer"><span>View source</span><span className="source-symbol" aria-hidden="true">↗</span></a>}
  </header>;
}

export function MapNavigation({ areas, active, onOverview, onNavigate }: {
  areas: MapArea[]; active?: MapArea; onOverview: () => void; onNavigate: (id: string) => void;
}) {
  return <nav className="map-navigation" aria-label="Map navigation">
    <div className="map-breadcrumb">
      <button type="button" onClick={onOverview} aria-current={active ? undefined : "page"}>Overview</button>
      {active ? <><span aria-hidden="true">/</span><span className="current-area" title={active.fullTitle}>{active.number} · {active.title}</span></>
        : <span className="area-total">{areas.length} areas</span>}
    </div>
    <label className="area-jump"><span className="visually-hidden">Jump to area</span>
      <select aria-label="Jump to area" value={active?.id ?? ""} onChange={event => event.target.value ? onNavigate(event.target.value) : onOverview()} disabled={!areas.length}>
        <option value="">Jump to area…</option>
        {areas.map(area => <option key={area.id} value={area.id}>{area.number} · {area.title}</option>)}
      </select>
    </label>
  </nav>;
}

export function MapToolbar({ disabled, percent, onZoom, onOverview, fullscreen, supportsFullscreen, onFullscreen }: {
  disabled: boolean; percent: number; onZoom: (factor: number) => void; onOverview: () => void;
  fullscreen: boolean; supportsFullscreen: boolean; onFullscreen: () => void;
}) {
  const label = `${Math.round(percent)}%`;
  return <div className="canvas-toolbar" role="group" aria-label="Diagram controls">
    <button className="tool-button" type="button" aria-label="Zoom out" title="Zoom out (−)" disabled={disabled} onClick={() => onZoom(1 / 1.3)}>−</button>
    <span className="zoom-value" aria-label={`Current zoom ${label}`}>{disabled ? "—" : label}</span>
    <button className="tool-button" type="button" aria-label="Zoom in" title="Zoom in (+)" disabled={disabled} onClick={() => onZoom(1.3)}>+</button>
    <span className="toolbar-divider" aria-hidden="true" />
    <button className="tool-button fit-button" type="button" aria-label="Fit diagram" title="Return to overview (F)" disabled={disabled} onClick={onOverview}>⌗ <span>Fit</span></button>
    {supportsFullscreen && <><span className="toolbar-divider" aria-hidden="true" />
      <button className="tool-button" type="button" aria-label={fullscreen ? "Exit fullscreen" : "Enter fullscreen"} title="Fullscreen" onClick={onFullscreen}>⛶</button>
    </>}
  </div>;
}

export function MapFooter({ commit, sourceUrl }: { commit: string | null; sourceUrl: string | null }) {
  return <footer className="map-footer"><div className="version-info"><span className="version-dot" aria-hidden="true" />
    {commit ? <><span>Built from</span>{sourceUrl ? <a href={sourceUrl} className="commit-link" data-testid="commit-link" target="_blank" rel="noreferrer" title={`View diagram at commit ${commit}`}>{commit.slice(0, 7)} ↗</a> : <code>{commit.slice(0, 7)}</code>}</>
      : <span>Local build · commit unavailable</span>}
  </div><span className="footer-caption">One codebase. A clearer view.</span></footer>;
}
