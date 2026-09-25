"use client";

import { useEffect, useState } from "react";
import type { Box, CodebaseGraph, MapArea, RenderedArea } from "../../lib/graph";
import { NODE_FONT_SIZE, renderArea } from "../../lib/mermaid-runtime";
import { placeDiagram, type SpatialLayout } from "../../lib/spatial-layout";
import type { Transform, Viewport } from "./use-map-camera";

type Props = {
  graph: CodebaseGraph;
  layout: SpatialLayout;
  activeAreaId: string | null;
  focusAttempt: number;
  transform: Transform;
  viewport: Viewport;
  onNavigate: (id: string) => void;
  onHighlight: (id: string | null) => void;
};
const intersects = (a: Box, b: Box) => a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
const clamp = (value: number) => Math.min(1, Math.max(0, value));

function MapRegion({ graph, area, layout, transform, viewport, active, focusAttempt, onNavigate, onHighlight }: Omit<Props, "activeAreaId"> & { area: MapArea; active: boolean }) {
  const region = layout.areas[area.id];

  const screen = { x: region.x * transform.scale + transform.x, y: region.y * transform.scale + transform.y, width: region.width * transform.scale, height: region.height * transform.scale };
  const visible = intersects(screen, { x: -100, y: -100, width: viewport.width + 200, height: viewport.height + 200 });

  const [result, setResult] = useState<{ graph: CodebaseGraph; rendered: RenderedArea } | null>(null);
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const rendered = result?.graph === graph ? result.rendered : null;
  const placement = rendered ? placeDiagram(region, rendered) : layout.diagrams[area.id];
  const effectiveFont = NODE_FONT_SIZE * placement.scale * transform.scale;
  const wanted = active || (visible && screen.width >= 320);
  const navigationAttempt = active ? focusAttempt : 0;
  useEffect(() => {
    if (!wanted || rendered) return;
    let cancelled = false;
    setFailed(false);
    renderArea(graph, area.id).then(value => {
      if (!cancelled) setResult({ graph, rendered: value });
    }).catch(() => { if (!cancelled) setFailed(true); });
    return () => { cancelled = true; };
  }, [area.id, graph, rendered, wanted, attempt, navigationAttempt]);
  const reveal = rendered ? clamp((effectiveFont - 4) / 3) : 0;
  const titleSize = Math.max(14, Math.min(19, 17 * transform.scale)) / transform.scale;
  const compact = transform.scale < .6;
  const platform = area.platform || "System";
  const kind = platform.includes("Backend") ? "backend" : platform.includes("Mac") ? "desktop" : "system";
  return <section className={`map-region region-${kind}${active ? " is-active" : ""}`} data-testid={`area-region-${area.id}`} data-area-id={area.id}
    data-world-x={region.x} data-world-y={region.y} data-world-width={region.width} data-world-height={region.height}
    aria-label={area.fullTitle} style={{ left: region.x, top: region.y, width: region.width, height: region.height, borderWidth: 1 / transform.scale }}
    onPointerEnter={() => onHighlight(area.id)} onPointerLeave={() => onHighlight(null)}>
    <button className="region-summary" type="button" data-testid={`area-card-${area.id}`} aria-label={area.fullTitle} aria-expanded={reveal > .5}
      tabIndex={visible && reveal < .5 ? 0 : -1} style={{ opacity: 1 - reveal, pointerEvents: reveal < .5 ? "auto" : "none", padding: (compact ? 4 : 8) / transform.scale, gap: (compact ? 3 : 6) / transform.scale }}
      onClick={() => onNavigate(area.id)}>
      <span className="region-meta" style={{ fontSize: (compact ? 9 : 10) / transform.scale }}><span>{area.number}</span><span>{platform}</span></span>
      <span className="area-card-title" style={{ fontSize: titleSize, lineHeight: compact ? 1.2 : 1.25 }}>{area.title}</span>
      <span className="region-enter" aria-hidden="true" style={{ fontSize: 12 / transform.scale }}>↗</span>
    </button>
    <div className="region-detail-heading" style={{ opacity: reveal, fontSize: Math.max(12, Math.min(16, 14 * transform.scale)) / transform.scale }} aria-hidden={reveal < .5}>
      <span>{area.number}</span><span>{area.title}</span>
    </div>
    {rendered && <div className={`area-diagram${effectiveFont >= 14 ? " show-details" : ""}`} data-testid="area-diagram" data-area-id={area.id} data-readable={reveal >= .5}
      style={{ left: placement.x - region.x, top: placement.y - region.y, width: rendered.width, height: rendered.height, transform: `scale(${placement.scale})`, opacity: reveal, visibility: reveal ? "visible" : "hidden" }}
      dangerouslySetInnerHTML={{ __html: rendered.svg }} />}
    {wanted && !rendered && <div className="region-loading" style={{ fontSize: 13 / transform.scale }} role={failed ? "alert" : "status"}>
      {failed ? <button type="button" onClick={() => { setAttempt(value => value + 1); onNavigate(area.id); }}>Retry this area</button> : "Loading detail…"}
    </div>}
  </section>;
}

export function MapAreas(props: Props) {
  return <>{props.graph.areas.map(area => <MapRegion key={area.id} {...props} area={area} active={props.activeAreaId === area.id} />)}</>;
}
