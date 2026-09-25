"use client";

import { useEffect, useRef, useState } from "react";
import type { CSSProperties } from "react";
import { loadGraph, renderArea } from "../../lib/mermaid-runtime";
import type { CodebaseGraph, MapArea, RenderedArea } from "../../lib/graph";
import { getAreaBox, getDiagramPlacement } from "../../lib/map-geometry";
import { MapConnections } from "./map-connections";
import { MapFooter, MapHeader, MapNavigation, MapToolbar } from "./map-chrome";
import { useMapCamera } from "./use-map-camera";

type DiagramViewerProps = { source: string; commit: string | null; sourceUrl: string | null };
type Status = "loading" | "ready" | "error";
const EMPTY_AREAS: MapArea[] = [];

export function DiagramViewer({ source, commit, sourceUrl }: DiagramViewerProps) {
  const shellRef = useRef<HTMLDivElement>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const [graph, setGraph] = useState<CodebaseGraph | null>(null);
  const [status, setStatus] = useState<Status>("loading");
  const [attempt, setAttempt] = useState(0);
  const [areaAttempt, setAreaAttempt] = useState(0);
  const [areaStatus, setAreaStatus] = useState<Status>("loading");
  const [result, setResult] = useState<{ graph: CodebaseGraph; id: string; rendered: RenderedArea } | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [supportsFullscreen, setSupportsFullscreen] = useState(false);
  const [notice, setNotice] = useState("");
  const [destinationContainer, setDestinationContainer] = useState<HTMLDivElement | null>(null);
  const areas = graph?.areas ?? EMPTY_AREAS;
  const camera = useMapCamera(areas, viewportRef);
  const { activeAreaId, revealArea } = camera;
  const active = areas.find(area => area.id === activeAreaId);
  const rendered = result?.graph === graph && result?.id === activeAreaId ? result.rendered : null;
  const placement = rendered && active ? getDiagramPlacement(getAreaBox(areas.indexOf(active)), rendered) : null;
  const detail = Boolean(rendered && placement && rendered.fontSize * placement.scale * camera.transform.scale >= 14);

  useEffect(() => {
    let cancelled = false;
    setStatus("loading");
    setGraph(null);
    setResult(null);
    loadGraph(source).then(value => {
      if (!cancelled) { setGraph(value); setStatus("ready"); }
    }).catch(() => { if (!cancelled) setStatus("error"); });
    return () => { cancelled = true; };
  }, [source, attempt]);

  useEffect(() => {
    if (!graph || !activeAreaId) return;
    let cancelled = false;
    setAreaStatus("loading");
    renderArea(graph, activeAreaId).then(value => {
      if (cancelled) return;
      setResult({ graph, id: activeAreaId, rendered: value });
      setAreaStatus("ready");
      revealArea(activeAreaId, value);
    }).catch(() => { if (!cancelled) setAreaStatus("error"); });
    return () => { cancelled = true; };
  }, [graph, activeAreaId, areaAttempt, revealArea]);

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

  const titleSize = Math.max(14, Math.min(18, camera.transform.scale * 28));
  return <div className="map-shell" ref={shellRef} onKeyDown={event => {
    if (!event.defaultPrevented && !viewportRef.current?.contains(event.target as Node)) camera.handlers.onKeyDown(event);
  }}>
    <MapHeader sourceUrl={sourceUrl} />
    <MapNavigation areas={areas} active={active} onOverview={camera.overview} onNavigate={camera.focusArea} />
    <main className="map-main">
      <div className={`diagram-viewport${camera.dragging ? " is-dragging" : ""}`} data-testid="diagram-viewport" ref={viewportRef}
        style={{ bottom: active ? 118 : 70 }}
        tabIndex={0} role="region" aria-label="Interactive codebase map" aria-describedby="canvas-instructions" aria-busy={status === "loading"} {...camera.handlers}>
        <div className="diagram-content" data-testid="diagram-content" data-scale={camera.transform.scale} data-x={camera.transform.x} data-y={camera.transform.y}
          data-overview-scale={camera.overviewScale} data-active-area={activeAreaId ?? ""} data-area-count={areas.length}
          data-node-count={graph ? Object.keys(graph.nodes).length : 0} data-edge-count={graph?.edges.length ?? 0}
          style={{ transform: `translate(${camera.transform.x}px, ${camera.transform.y}px) scale(${camera.transform.scale})`,
            "--map-scale": camera.transform.scale, "--title-font": `${titleSize / camera.transform.scale}px`,
            "--meta-font": `${11 / camera.transform.scale}px`, "--title-leading": `${(titleSize + 4) / camera.transform.scale}px`,
          } as CSSProperties}>
          {areas.map((area, index) => {
            const box = getAreaBox(index);
            const selected = activeAreaId === area.id;
            const centerX = (box.x + box.width / 2) * camera.transform.scale + camera.transform.x;
            const centerY = (box.y + box.height / 2) * camera.transform.scale + camera.transform.y;
            const reachable = centerX >= 0 && centerX <= camera.viewport.width && centerY >= 0 && centerY <= camera.viewport.height;
            return <button key={area.id} type="button" className={`area-card${selected ? " is-active" : ""}`} data-testid={`area-card-${area.id}`}
              data-area-id={area.id} data-world-x={box.x} data-world-y={box.y} aria-label={area.fullTitle} aria-expanded={selected}
              tabIndex={selected || !reachable ? -1 : 0}
              style={{ left: box.x, top: box.y, width: box.width, height: box.height }} onClick={() => camera.focusArea(area.id)}>
              <span className="area-card-copy"><span className="area-card-meta"><span className="area-card-number">{area.number}</span><span>{area.platform || "System"}</span></span>
                <span className="area-card-title">{area.title}</span><span className="area-card-open" aria-hidden="true">Explore area ↗</span></span>
            </button>;
          })}
          {active && rendered && placement && <div className={`area-diagram${detail ? " show-details" : ""}`} data-testid="area-diagram" data-area-id={active.id}
            style={{ left: placement.x, top: placement.y, width: rendered.width, height: rendered.height, transform: `scale(${placement.scale})` }}
            dangerouslySetInnerHTML={{ __html: rendered.svg }} />}
        </div>
        {graph && active && rendered && <MapConnections graph={graph} activeAreaId={active.id} rendered={rendered} transform={camera.transform} viewport={camera.viewport} onNavigate={camera.focusArea} destinationContainer={destinationContainer} />}
      </div>
      <div className="connected-area-dock" ref={setDestinationContainer} hidden={!active} />
      {status === "loading" && <div className="canvas-state" role="status" data-testid="diagram-loading"><div className="loading-orbit" aria-hidden="true"><span /><span /><span /></div><h2>Opening the codebase</h2><p>Finding the areas of your system.</p></div>}
      {status === "error" && <div className="canvas-state" role="alert" data-testid="diagram-error"><h2>The map couldn’t be drawn</h2><p>Try again, or check the diagram source for errors.</p><button className="retry-button" type="button" onClick={() => setAttempt(value => value + 1)}>Try again</button></div>}
      {active && !rendered && areaStatus === "loading" && <div className="area-state" role="status" data-testid="area-loading">Opening {active.title}…</div>}
      {active && areaStatus === "error" && <div className="area-state" role="alert" data-testid="area-error"><strong>This area couldn’t be drawn.</strong><span>You can still explore the other areas.</span><button type="button" className="retry-button" onClick={() => setAreaAttempt(value => value + 1)}>Retry area</button></div>}
      <MapToolbar disabled={status !== "ready"} percent={camera.transform.scale / camera.overviewScale * 100} onZoom={camera.zoomAt} onOverview={camera.overview}
        fullscreen={fullscreen} supportsFullscreen={supportsFullscreen} onFullscreen={() => void toggleFullscreen()} />
      <p className="canvas-hint" id="canvas-instructions">{active ? "Scroll to explore · Drag to pan · Escape for overview" : "Choose an area · Scroll to zoom · Drag to pan"}<span className="visually-hidden">. Arrow keys pan, plus and minus zoom, Home and F return to overview.</span></p>
      {notice && <p className="canvas-notice" role="status">{notice}</p>}
    </main>
    <MapFooter commit={commit} sourceUrl={sourceUrl} />
  </div>;
}
