"use client";

import type { CodebaseGraph, MapArea } from "../../lib/graph";
import type { SpatialLayout } from "../../lib/spatial-layout";

type Props = {
  graph: CodebaseGraph;
  layout: SpatialLayout;
  scale: number;
  onNavigate: (id: string) => void;
  onHighlight: (id: string | null) => void;
};

function MapRegion({ area, layout, scale, onNavigate, onHighlight }: Omit<Props, "graph"> & { area: MapArea }) {
  const region = layout.areas[area.id];
  const compact = scale < .6;
  const platform = area.platform || "System";
  const kind = platform.includes("Backend") ? "backend" : platform.includes("Mac") ? "desktop" : "system";
  return <section className={`map-region region-${kind}`} data-testid={`area-region-${area.id}`} data-area-id={area.id}
    data-world-x={region.x} data-world-y={region.y} data-world-width={region.width} data-world-height={region.height}
    aria-label={area.fullTitle} style={{ left: region.x, top: region.y, width: region.width, height: region.height, borderWidth: 1 / scale }}
    onPointerEnter={() => onHighlight(area.id)} onPointerLeave={() => onHighlight(null)}>
    <button className="region-summary" type="button" data-testid={`area-card-${area.id}`} aria-label={area.fullTitle}
      style={{ padding: (compact ? 4 : 8) / scale, gap: (compact ? 3 : 6) / scale }} onClick={() => onNavigate(area.id)}>
      <span className="region-meta" style={{ fontSize: (compact ? 9 : 10) / scale }}><span>{area.number}</span><span>{platform}</span></span>
      <span className="area-card-title" style={{ fontSize: Math.max(14, Math.min(19, 17 * scale)) / scale, lineHeight: compact ? 1.2 : 1.25 }}>{area.title}</span>
      <span className="region-enter" aria-hidden="true" style={{ fontSize: 12 / scale }}>↗</span>
    </button>
  </section>;
}

export function MapAreas(props: Props) {
  return <>{props.graph.areas.map(area => <MapRegion key={area.id} {...props} area={area} />)}</>;
}
