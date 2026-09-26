"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { loadGraph, renderArea } from "../../lib/mermaid-runtime";
import type { CodebaseGraph, RenderedArea } from "../../lib/graph";
import { createSpatialLayout } from "../../lib/spatial-layout";
import { MapAreas } from "./map-areas";
import { MapConnections } from "./map-connections";
import { MapFooter, MapHeader, MapNavigation, MapToolbar } from "./map-chrome";
import { useMapNavigation } from "./use-map-navigation";

type DiagramViewerProps = { source: string; commit: string | null; sourceUrl: string | null };

export function DiagramViewer({ source, commit, sourceUrl }: DiagramViewerProps) {
  const shellRef = useRef<HTMLDivElement>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const [overviewCanvas, setOverviewCanvas] = useState<HTMLDivElement | null>(null);
  const [graph, setGraph] = useState<CodebaseGraph | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const [attempt, setAttempt] = useState(0);
  const [activeAreaId, setActiveAreaId] = useState<string | null>(null);
  const [detail, setDetail] = useState<{ graph: CodebaseGraph; id: string; rendered: RenderedArea } | null>(null);
  const [detailFailed, setDetailFailed] = useState(false);
  const [detailAttempt, setDetailAttempt] = useState(0);
  const [highlighted, setHighlighted] = useState<string | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [supportsFullscreen, setSupportsFullscreen] = useState(false);
  const [notice, setNotice] = useState("");
  const layout = useMemo(() => graph ? createSpatialLayout(graph) : null, [graph]);
  const rendered = detail?.graph === graph && detail?.id === activeAreaId ? detail.rendered : null;
  const overview = useCallback(() => { setActiveAreaId(null); setHighlighted(null); }, []);
  const navigate = useCallback((id: string) => {
    if (id === activeAreaId) return;
    setDetailFailed(false);
    setActiveAreaId(id);
    setHighlighted(null);
  }, [activeAreaId]);
  const openFromMap = useCallback((id: string) => {
    navigate(id);
    viewportRef.current?.focus({ preventScroll: true });
  }, [navigate]);
  const navigation = useMapNavigation(graph, layout, activeAreaId, rendered, viewportRef, overview);
  const areas = graph?.areas ?? [];
  const active = areas.find(area => area.id === activeAreaId);

  useEffect(() => {
    let cancelled = false;
    setStatus("loading");
    setGraph(null);
    setActiveAreaId(null);
    setDetail(null);
    loadGraph(source).then(value => {
      if (!cancelled) { setGraph(value); setStatus("ready"); }
    }).catch(() => { if (!cancelled) setStatus("error"); });
    return () => { cancelled = true; };
  }, [source, attempt]);

  useEffect(() => {
    if (!graph || !activeAreaId) return;
    let cancelled = false;
    setDetailFailed(false);
    renderArea(graph, activeAreaId).then(value => {
      if (!cancelled) setDetail({ graph, id: activeAreaId, rendered: value });
    }).catch(() => { if (!cancelled) setDetailFailed(true); });
    return () => { cancelled = true; };
  }, [graph, activeAreaId, detailAttempt]);

  useEffect(() => {
    setSupportsFullscreen(Boolean(document.fullscreenEnabled));
    const sync = () => setFullscreen(document.fullscreenElement === shellRef.current);
    document.addEventListener("fullscreenchange", sync);
    return () => document.removeEventListener("fullscreenchange", sync);
  }, []);

  async function toggleFullscreen() {
    setNotice("");
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await shellRef.current?.requestFullscreen();
    } catch { setNotice("Fullscreen is unavailable in this browser."); }
  }

  const contentSize = activeAreaId ? {
    width: Math.max(navigation.viewport.width, (rendered?.width ?? 0) + 64),
    height: Math.max(navigation.viewport.height, (rendered?.height ?? 0) + 64),
  } : navigation.overviewSize;
  const transform = navigation.overviewTransform;
  return <div className="map-shell" ref={shellRef} onKeyDown={event => {
    if (!event.defaultPrevented && event.key === "Escape" && !(event.target as Element).closest("select")) {
      overview();
      shellRef.current?.querySelector<HTMLButtonElement>(".map-breadcrumb button")?.focus({ preventScroll: true });
    }
  }}>
    <MapHeader sourceUrl={sourceUrl} />
    <MapNavigation graph={graph} areas={areas} active={active} onOverview={overview} onNavigate={navigate} />
    <main className="map-main">
      <div className={`diagram-viewport${navigation.dragging ? " is-dragging" : ""}`} data-testid="diagram-viewport" ref={viewportRef}
        tabIndex={0} role="region" aria-label="Interactive codebase map" aria-describedby="canvas-instructions"
        aria-busy={status === "loading" || Boolean(activeAreaId && !rendered && !detailFailed)} {...navigation.handlers}>
        <div className="diagram-content" data-testid="diagram-content" data-active-area={activeAreaId ?? ""} data-area-count={areas.length}
          data-node-count={graph ? Object.keys(graph.nodes).length : 0} data-edge-count={graph?.edges.length ?? 0} style={contentSize}>
          {!activeAreaId && graph && layout && <>
            <div className="overview-connections" ref={setOverviewCanvas} />
            <div className="overview-regions" style={{ transform: `translate(${transform.x}px, ${transform.y}px) scale(${transform.scale})` }}>
              <MapAreas graph={graph} layout={layout} scale={transform.scale} onNavigate={openFromMap} onHighlight={setHighlighted} />
            </div>
          </>}
          {activeAreaId && rendered && <div className="area-diagram" data-testid="area-diagram" data-area-id={activeAreaId}
            style={{ left: navigation.detailOffset.x, top: navigation.detailOffset.y, width: rendered.width, height: rendered.height }}
            dangerouslySetInnerHTML={{ __html: rendered.svg }} />}
        </div>
      </div>
      {graph && layout && <MapConnections graph={graph} layout={layout} transform={transform} viewport={navigation.overviewSize}
        canvas={activeAreaId ? null : overviewCanvas} activeAreaId={activeAreaId} highlightedAreaId={highlighted} onNavigate={openFromMap} />}
      {status === "loading" && <div className="canvas-state" role="status" data-testid="diagram-loading"><div className="loading-orbit" aria-hidden="true"><span /><span /><span /></div><h2>Opening the codebase</h2><p>Finding the areas of your system.</p></div>}
      {status === "error" && <div className="canvas-state" role="alert" data-testid="diagram-error"><h2>The map couldn’t be drawn</h2><p>Try again, or check the diagram source for errors.</p><button className="retry-button" type="button" onClick={() => setAttempt(value => value + 1)}>Try again</button></div>}
      {activeAreaId && !rendered && <div className="canvas-state" role={detailFailed ? "alert" : "status"}>
        <h2>{detailFailed ? "This subsystem couldn’t be drawn" : "Opening subsystem"}</h2><p>{active?.title}</p>
        {detailFailed && <button className="retry-button" type="button" onClick={() => { setDetailAttempt(value => value + 1); viewportRef.current?.focus({ preventScroll: true }); }}>Retry this area</button>}
      </div>}
      <MapToolbar fullscreen={fullscreen} supportsFullscreen={supportsFullscreen} onFullscreen={() => void toggleFullscreen()} />
      <p className="canvas-hint" id="canvas-instructions">{active ? "Scroll or drag to explore · Escape returns to Overview" : "Click a subsystem to open · Scroll or drag to explore"}</p>
      {notice && <p className="canvas-notice" role="status">{notice}</p>}
    </main>
    <MapFooter commit={commit} sourceUrl={sourceUrl} />
  </div>;
}
