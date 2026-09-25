"use client";

import { useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { Box, CodebaseGraph, MapArea, RenderedArea } from "../../lib/graph";
import { getAreaBox, getAreaConnections } from "../../lib/map-geometry";
import type { Point, RoutedConnection } from "../../lib/map-geometry";

type Props = {
  graph: CodebaseGraph;
  activeAreaId: string;
  rendered: RenderedArea;
  transform: Point & { scale: number };
  viewport: { width: number; height: number };
  destinationContainer: HTMLDivElement | null;
  onNavigate: (id: string) => void;
};

type Destination = { area: MapArea; connections: RoutedConnection[]; side: "top" | "right" | "bottom" | "left" };

const plainLabel = (label: string) => label.replace(/<br\s*\/?\s*>/gi, " · ").replace(/<[^>]*>/g, "");
const overlaps = (a: Box, b: Box) => a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
const segmentVisible = (a: Point, b: Point, viewport: Box) => a.x === b.x
  ? a.x >= viewport.x && a.x <= viewport.x + viewport.width && Math.max(a.y, b.y) >= viewport.y && Math.min(a.y, b.y) <= viewport.y + viewport.height
  : a.y >= viewport.y && a.y <= viewport.y + viewport.height && Math.max(a.x, b.x) >= viewport.x && Math.min(a.x, b.x) <= viewport.x + viewport.width;

function connectionText(connection: RoutedConnection, graph: CodebaseGraph) {
  const { edge } = connection;
  const source = graph.nodes[edge.source];
  const target = graph.nodes[edge.target];
  const sourceArea = graph.areas.find(area => area.id === source.areaId)!;
  const targetArea = graph.areas.find(area => area.id === target.areaId)!;
  const direction = edge.arrowStart ? edge.arrowEnd ? "↔" : "←" : edge.arrowEnd ? "→" : "—";
  return `${sourceArea.number} ${sourceArea.title}: ${plainLabel(source.label)} ${direction} ${targetArea.number} ${targetArea.title}: ${plainLabel(target.label)}${edge.label ? ` — ${plainLabel(edge.label)}` : ""}`;
}

/** An SVG in screen coordinates wraps the unchanged, cached world-space routes. */
export function MapConnections({ graph, activeAreaId, rendered, transform, viewport, destinationContainer, onNavigate }: Props) {
  const markerId = `connection-arrow-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
  const layerRef = useRef<HTMLDivElement>(null);
  const [revealed, setRevealed] = useState<{ id: string; point: Point } | null>(null);
  const routes = useMemo(() => getAreaConnections(graph, activeAreaId, rendered), [graph, activeAreaId, rendered]);
  const { scale } = transform;
  const project = (point: Point): Point => ({ x: point.x * scale + transform.x, y: point.y * scale + transform.y });

  const destinations = useMemo(() => {
    const groups = new Map<string, RoutedConnection[]>();
    for (const route of routes) groups.set(route.remoteAreaId, [...(groups.get(route.remoteAreaId) ?? []), route]);
    const result: Destination[] = [];
    for (const [areaId, connections] of groups) {
      const world = connections[0].remoteBox;
      const box = { x: world.x * scale + transform.x, y: world.y * scale + transform.y, width: world.width * scale, height: world.height * scale };
      if (overlaps(box, { x: 0, y: 0, ...viewport })) continue;
      const dx = box.x + box.width / 2 - viewport.width / 2;
      const dy = box.y + box.height / 2 - viewport.height / 2;
      const side = Math.abs(dx) / Math.max(1, viewport.width) > Math.abs(dy) / Math.max(1, viewport.height)
        ? dx > 0 ? "right" : "left"
        : dy > 0 ? "bottom" : "top";
      const area = graph.areas.find(item => item.id === areaId)!;
      result.push({ area, connections, side });
    }
    return result;
  }, [routes, graph, scale, transform.x, transform.y, viewport.width, viewport.height]);

  const labels = new Map<string, { point: Point; width: number }>();
  const occupied: Box[] = [
    ...graph.areas.map((_, index) => {
      const box = getAreaBox(index);
      return { x: box.x * scale + transform.x, y: box.y * scale + transform.y, width: box.width * scale, height: box.height * scale };
    }),
  ];
  for (const route of routes) {
    const label = plainLabel(route.edge.label);
    if (!label) continue;
    const width = label.length * 6.1 + 16;
    const segments = route.points.slice(1).map((point, index) => ({ start: route.points[index], end: point }))
      .filter(segment => segment.start.y === segment.end.y)
      .sort((a, b) => Math.abs(b.end.x - b.start.x) - Math.abs(a.end.x - a.start.x));
    for (const segment of segments) {
      if (Math.abs(segment.end.x - segment.start.x) * scale < width + 32) continue;
      const point = { x: (segment.start.x + segment.end.x) / 2, y: segment.start.y };
      const screen = project(point);
      const bounds = { x: screen.x - width / 2, y: screen.y - 10, width, height: 20 };
      if (bounds.x < 8 || bounds.y < 8 || bounds.x + width > viewport.width - 8 || bounds.y + 20 > viewport.height - 8 || occupied.some(other => overlaps(bounds, other))) continue;
      occupied.push(bounds);
      labels.set(route.edge.id, { point, width });
      break;
    }
  }

  const revealedRoute = routes.find(route => route.edge.id === revealed?.id);
  const worldViewport = { x: -transform.x / scale, y: -transform.y / scale, width: viewport.width / scale, height: viewport.height / scale };
  return (
    <div className="map-connections" ref={layerRef} style={{ position: "absolute", inset: 0, pointerEvents: "none", overflow: "clip" }}>
      <svg width={viewport.width} height={viewport.height} className="map-connection-svg" aria-label="Connections to other areas" style={{ position: "absolute", inset: 0, overflow: "visible" }}>
        <defs>
          <marker id={markerId} viewBox="0 0 8 8" refX="7" refY="4" markerWidth={8 / scale} markerHeight={8 / scale} markerUnits="userSpaceOnUse" orient="auto-start-reverse">
            <path d="M0 0 L8 4 L0 8 z" fill="#718896" />
          </marker>
        </defs>
        <g transform={`translate(${transform.x} ${transform.y}) scale(${scale})`}>
          {routes.map(route => {
            const text = connectionText(route, graph);
            const label = labels.get(route.edge.id);
            const selected = revealed?.id === route.edge.id;
            const visible = Boolean(label) || route.points.some((point, index) => index > 0 && segmentVisible(route.points[index - 1], point, worldViewport));
            return (
              <g key={route.edge.id} className={`map-connection${selected ? " is-revealed" : ""}`} data-edge-id={route.edge.id} data-remote-area-id={route.remoteAreaId}
                tabIndex={visible ? 0 : -1} role="button" aria-label={`${text}. Open connected area.`}
                onPointerDown={event => event.stopPropagation()}
                onClick={event => { event.stopPropagation(); onNavigate(route.remoteAreaId); }}
                onKeyDown={event => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); event.stopPropagation(); onNavigate(route.remoteAreaId); } }}
                onFocus={() => setRevealed({ id: route.edge.id, point: { x: viewport.width / 2, y: viewport.height - 70 } })}
                onBlur={() => setRevealed(null)}
                onPointerEnter={event => { const bounds = layerRef.current?.getBoundingClientRect(); setRevealed({ id: route.edge.id, point: { x: event.clientX - (bounds?.left ?? 0), y: event.clientY - (bounds?.top ?? 0) } }); }}
                onPointerLeave={() => setRevealed(null)}>
                <title>{text}</title>
                <path className="map-connection-line" d={route.path} fill="none" stroke={selected ? "#315f75" : "#8da0ad"} strokeWidth={route.edge.stroke === "thick" ? 2.6 : selected ? 1.9 : 1.2} strokeDasharray={route.edge.stroke === "dotted" ? "4 4" : undefined} vectorEffect="non-scaling-stroke" strokeLinejoin="round" markerStart={route.edge.arrowStart ? `url(#${markerId})` : undefined} markerEnd={route.edge.arrowEnd ? `url(#${markerId})` : undefined} />
                <path className="map-connection-hit" d={route.path} fill="none" stroke="transparent" strokeWidth={12} vectorEffect="non-scaling-stroke" style={{ pointerEvents: "stroke", cursor: "pointer" }} />
                {label && <g className="map-connection-label" transform={`translate(${label.point.x} ${label.point.y}) scale(${1 / scale})`}>
                  <rect x={-label.width / 2} y={-10} width={label.width} height={20} rx={4} fill="white" fillOpacity={0.95} />
                  <text textAnchor="middle" dominantBaseline="central" fontSize={11} fill="#536875">{plainLabel(route.edge.label)}</text>
                </g>}
              </g>
            );
          })}
        </g>
      </svg>
      {destinationContainer && createPortal(<div className="map-connection-destinations" role="group" aria-label="Connected areas outside the viewport"
        style={{ pointerEvents: "auto" }}
        onKeyDown={event => {
          if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
          const buttons = [...event.currentTarget.querySelectorAll<HTMLButtonElement>("button")];
          const index = buttons.indexOf(document.activeElement as HTMLButtonElement);
          if (index < 0) return;
          event.preventDefault();
          event.stopPropagation();
          const next = Math.max(0, Math.min(buttons.length - 1, index + (event.key === "ArrowRight" ? 1 : -1)));
          buttons[next]?.focus({ preventScroll: true });
        }}>
        {destinations.map(destination => (
          <button key={destination.area.id} type="button" className="map-connection-destination" data-area-id={destination.area.id} data-destination-area={destination.area.id}
            style={{ position: "relative", flex: "0 0 auto", height: 32, whiteSpace: "nowrap", pointerEvents: "auto" }}
            title={destination.connections.map(connection => connectionText(connection, graph)).join("\n")}
            aria-label={`Open ${destination.area.number} ${destination.area.title}, ${destination.connections.length} ${destination.connections.length === 1 ? "connection" : "connections"}`}
            onFocus={event => {
              const button = event.currentTarget;
              const dock = destinationContainer;
              if (!dock) return;
              const bounds = button.getBoundingClientRect();
              const viewport = dock.getBoundingClientRect();
              if (bounds.left < viewport.left + 4) dock.scrollLeft += bounds.left - viewport.left - 4;
              else if (bounds.right > viewport.right - 4) dock.scrollLeft += bounds.right - viewport.right + 4;
            }}
            onPointerDown={event => event.stopPropagation()}
            onClick={event => { event.stopPropagation(); onNavigate(destination.area.id); }}>
            <span aria-hidden="true">{destination.side === "top" ? "↑" : destination.side === "right" ? "→" : destination.side === "bottom" ? "↓" : "←"}</span>
            <span style={{ overflow: "visible", textOverflow: "clip", maxWidth: "none" }}>{destination.area.number} · {destination.area.title}</span>
            <span className="map-connection-count">{destination.connections.length}</span>
          </button>
        ))}
      </div>, destinationContainer)}
      {revealedRoute && revealed && <div className="map-connection-tooltip" role="tooltip"
        style={{ position: "absolute", left: Math.max(12, Math.min(viewport.width - Math.min(380, viewport.width - 24) - 12, revealed.point.x + 14)), bottom: 12, maxWidth: Math.min(380, viewport.width - 24), maxHeight: Math.max(0, viewport.height - 24), overflowY: "auto", pointerEvents: "auto" }}>
        {connectionText(revealedRoute, graph)}
      </div>}
    </div>
  );
}
