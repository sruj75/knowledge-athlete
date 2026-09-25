"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { loadGraph } from "../../lib/mermaid-runtime";
import type { CodebaseGraph } from "../../lib/graph";
import { createSpatialLayout } from "../../lib/spatial-layout";
import { MapAreas } from "./map-areas";
import { MapConnections } from "./map-connections";
import { MapFooter, MapHeader, MapNavigation, MapToolbar } from "./map-chrome";
import { useMapCamera } from "./use-map-camera";

type DiagramViewerProps = { source: string; commit: string | null; sourceUrl: string | null };

export function DiagramViewer({ source, commit, sourceUrl }: DiagramViewerProps) {
  const shellRef = useRef<HTMLDivElement>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const [graph, setGraph] = useState<CodebaseGraph | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const [attempt, setAttempt] = useState(0);
  const [highlighted, setHighlighted] = useState<string | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [supportsFullscreen, setSupportsFullscreen] = useState(false);
  const [notice, setNotice] = useState("");
  const layout = useMemo(() => graph ? createSpatialLayout(graph) : null, [graph]);
  const camera = useMapCamera(graph, layout, viewportRef);
  const areas = graph?.areas ?? [];
  const active = areas.find(area => area.id === camera.activeAreaId);

  useEffect(() => {
    let cancelled = false;
    setStatus("loading");
    setGraph(null);
    loadGraph(source).then(value => {
      if (!cancelled) { setGraph(value); setStatus("ready"); }
    }).catch(() => { if (!cancelled) setStatus("error"); });
    return () => { cancelled = true; };
  }, [source, attempt]);

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

  return <div className="map-shell" ref={shellRef} onKeyDown={event => {
    if (!event.defaultPrevented && !viewportRef.current?.contains(event.target as Node)) camera.handlers.onKeyDown(event);
  }}>
    <MapHeader sourceUrl={sourceUrl} />
    <MapNavigation graph={graph} areas={areas} active={active} onOverview={camera.overview} onNavigate={camera.focusArea} />
    <main className="map-main">
      <div className={`diagram-viewport${camera.dragging ? " is-dragging" : ""}`} data-testid="diagram-viewport" ref={viewportRef}
        tabIndex={0} role="region" aria-label="Interactive codebase map" aria-describedby="canvas-instructions" aria-busy={status === "loading"} {...camera.handlers}>
        {graph && layout && <MapConnections graph={graph} layout={layout} transform={camera.transform} viewport={camera.viewport}
          activeAreaId={camera.activeAreaId} highlightedAreaId={highlighted ?? camera.activeAreaId} onNavigate={camera.focusArea} />}
        <div className="diagram-content" data-testid="diagram-content" data-scale={camera.transform.scale} data-x={camera.transform.x} data-y={camera.transform.y}
          data-overview-scale={camera.overviewScale} data-active-area={camera.activeAreaId ?? ""} data-area-count={areas.length}
          data-node-count={graph ? Object.keys(graph.nodes).length : 0} data-edge-count={graph?.edges.length ?? 0}
          style={{ transform: `translate(${camera.transform.x}px, ${camera.transform.y}px) scale(${camera.transform.scale})` }}>
          {graph && layout && <MapAreas graph={graph} layout={layout} activeAreaId={camera.activeAreaId} focusAttempt={camera.focusAttempt} transform={camera.transform} viewport={camera.viewport}
            onNavigate={camera.focusArea} onHighlight={setHighlighted} />}
        </div>
      </div>
      {status === "loading" && <div className="canvas-state" role="status" data-testid="diagram-loading"><div className="loading-orbit" aria-hidden="true"><span /><span /><span /></div><h2>Opening the codebase</h2><p>Finding the areas of your system.</p></div>}
      {status === "error" && <div className="canvas-state" role="alert" data-testid="diagram-error"><h2>The map couldn’t be drawn</h2><p>Try again, or check the diagram source for errors.</p><button className="retry-button" type="button" onClick={() => setAttempt(value => value + 1)}>Try again</button></div>}
      <MapToolbar disabled={status !== "ready"} percent={camera.transform.scale / camera.overviewScale * 100} onZoom={camera.zoomAt} onOverview={camera.overview}
        fullscreen={fullscreen} supportsFullscreen={supportsFullscreen} onFullscreen={() => void toggleFullscreen()} />
      <p className="canvas-hint" id="canvas-instructions">Scroll to zoom · Drag to explore · Click a subsystem to focus<span className="visually-hidden">. Arrow keys pan, plus and minus zoom, Home, Escape and F return to overview.</span></p>
      {camera.focusError && <div className="canvas-notice focus-error" role="alert">
        <span>Couldn’t open {areas.find(area => area.id === camera.focusError)?.title ?? "this subsystem"}.</span>
        <button type="button" onClick={() => camera.focusArea(camera.focusError!)}>Retry opening area</button>
      </div>}
      {notice && <p className="canvas-notice" role="status">{notice}</p>}
    </main>
    <MapFooter commit={commit} sourceUrl={sourceUrl} />
  </div>;
}
