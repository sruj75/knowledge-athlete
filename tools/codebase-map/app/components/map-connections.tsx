"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import type { Box, CodebaseGraph, MapEdge, Point } from "../../lib/graph";
import type { SpatialLayout } from "../../lib/spatial-layout";
import type { Transform, Viewport } from "./use-map-camera";

type Props = { graph: CodebaseGraph; layout: SpatialLayout; transform: Transform; viewport: Viewport; highlightedAreaId: string | null; activeAreaId: string | null; onNavigate: (id: string) => void };
type Link = { id: string; from: string; to: string; edges: MapEdge[]; path: string; start: Point; end: Point; forward: boolean; backward: boolean };
const plain = (value: string) => value.replace(/<br\s*\/?\s*>/gi, " · ").replace(/<[^>]*>/g, "");
function port(box: Box, other: Box): Point {
  const center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  const dx = other.x + other.width / 2 - center.x, dy = other.y + other.height / 2 - center.y;
  const fraction = Math.min(dx ? box.width / 2 / Math.abs(dx) : Infinity, dy ? box.height / 2 / Math.abs(dy) : Infinity);
  return { x: center.x + dx * fraction, y: center.y + dy * fraction };
}
function linksFor(graph: CodebaseGraph, layout: SpatialLayout): Link[] {
  const links = new Map<string, Link>();
  for (const edge of graph.edges) {
    const source = graph.nodes[edge.source].areaId, target = graph.nodes[edge.target].areaId;
    if (source === target) continue;
    const [from, to] = [source, target].sort();
    const id = `${from}-${to}`;
    let link = links.get(id);
    if (!link) {
      const a = layout.areas[from], b = layout.areas[to];
      const start = port(a, b), end = port(b, a);
      const dx = end.x - start.x, dy = end.y - start.y;
      const bend = Math.min(90, Math.hypot(dx, dy) / 3);
      const horizontalA = Math.abs(start.x - a.x) < .01 || Math.abs(start.x - a.x - a.width) < .01;
      const horizontalB = Math.abs(end.x - b.x) < .01 || Math.abs(end.x - b.x - b.width) < .01;
      const c1 = { x: start.x + (horizontalA ? Math.sign(dx) * bend : 0), y: start.y + (horizontalA ? 0 : Math.sign(dy) * bend) };
      const c2 = { x: end.x - (horizontalB ? Math.sign(dx) * bend : 0), y: end.y - (horizontalB ? 0 : Math.sign(dy) * bend) };
      link = { id, from, to, edges: [], start, end, forward: false, backward: false, path: `M${start.x},${start.y} C${c1.x},${c1.y} ${c2.x},${c2.y} ${end.x},${end.y}` };
      links.set(id, link);
    }
    link.edges.push(edge);
    link.forward ||= source === from ? edge.arrowEnd : edge.arrowStart;
    link.backward ||= source === from ? edge.arrowStart : edge.arrowEnd;
  }
  return [...links.values()];
}

/** The overview shows relationships between regions; individual edges stay inspectable. */
export function MapConnections({ graph, layout, transform, viewport, highlightedAreaId, activeAreaId, onNavigate }: Props) {
  const marker = `region-arrow-${useId().replace(/[^\w-]/g, "")}`;
  const links = useMemo(() => linksFor(graph, layout), [graph, layout]);
  const [hovered, setHovered] = useState<string | null>(null);
  const [destinationsOpen, setDestinationsOpen] = useState(false);
  const [inspected, setInspected] = useState<string | null>(null);
  const inspector = useRef<HTMLElement>(null);
  useEffect(() => {
    if (!inspected) return;
    const previous = document.activeElement;
    inspector.current?.querySelector<HTMLButtonElement>("button")?.focus({ preventScroll: true });
    return () => { if (previous instanceof HTMLElement || previous instanceof SVGElement) previous.focus({ preventScroll: true }); };
  }, [inspected]);
  const selected = links.find(link => link.id === inspected);
  const preview = links.find(link => link.id === hovered);
  const destinations = links.filter(link => link.from === activeAreaId || link.to === activeAreaId);
  const area = (id: string) => graph.areas.find(candidate => candidate.id === id)!;
  const arrow = (start: boolean, end: boolean) => start && end ? "↔" : start ? "←" : end ? "→" : "—";
  const names = (link: Link) => `${area(link.from).number} ${area(link.from).title} ${arrow(link.backward, link.forward)} ${area(link.to).number} ${area(link.to).title}`;
  return <>
    <svg className="region-connections" width={viewport.width} height={viewport.height} aria-label="Subsystem connections">
      <defs><marker id={marker} viewBox="0 0 8 8" refX="7" refY="4" markerWidth={5 / transform.scale} markerHeight={5 / transform.scale} markerUnits="userSpaceOnUse" orient="auto-start-reverse"><path d="M0 0 L8 4 L0 8z" fill="#94a7b3" /></marker></defs>
      <g transform={`translate(${transform.x} ${transform.y}) scale(${transform.scale})`}>
        {links.map(link => {
          const emphasized = hovered === link.id || inspected === link.id;
          const related = highlightedAreaId && (link.from === highlightedAreaId || link.to === highlightedAreaId);
          const visible = Math.max(link.start.x, link.end.x) * transform.scale + transform.x >= 0 && Math.min(link.start.x, link.end.x) * transform.scale + transform.x <= viewport.width && Math.max(link.start.y, link.end.y) * transform.scale + transform.y >= 0 && Math.min(link.start.y, link.end.y) * transform.scale + transform.y <= viewport.height;
          return <g key={link.id} className="map-connection-group" data-connection-group={link.id} data-edge-ids={JSON.stringify(link.edges.map(edge => edge.id))}
            role="button" tabIndex={visible ? 0 : -1} aria-label={`${names(link)}. ${link.edges.length} connections. Inspect connections.`}
            onPointerEnter={() => setHovered(link.id)} onPointerLeave={() => setHovered(null)} onFocus={() => setHovered(link.id)} onBlur={() => setHovered(null)}
            onPointerDown={event => event.stopPropagation()} onClick={event => { event.stopPropagation(); setInspected(link.id); }}
            onKeyDown={event => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); event.stopPropagation(); setInspected(link.id); } }}>
            <path d={link.path} className="region-connection-line" fill="none" stroke={emphasized || related ? "#51798a" : "#9bafbb"} strokeWidth={emphasized ? 2 : related ? 1.6 : 1} opacity={emphasized ? .95 : highlightedAreaId ? related ? .65 : .1 : .35} vectorEffect="non-scaling-stroke" strokeDasharray={link.edges.every(edge => edge.stroke === "dotted") ? "4 4" : undefined} markerStart={link.backward ? `url(#${marker})` : undefined} markerEnd={link.forward ? `url(#${marker})` : undefined} />
            <path d={link.path} fill="none" stroke="transparent" strokeWidth={9} vectorEffect="non-scaling-stroke" style={{ pointerEvents: "stroke", cursor: "pointer" }} />
          </g>;
        })}
      </g>
    </svg>
    {preview && !selected && <div className="connection-preview" role="tooltip"><span>{names(preview)}</span><strong>{preview.edges.length} connections · Click to inspect</strong></div>}
    {activeAreaId && destinations.length > 0 && <nav className="connected-areas" aria-label="Connected subsystems" data-no-pan
      onPointerDown={event => event.stopPropagation()} onWheelCapture={event => event.stopPropagation()}
      onKeyDown={event => { event.stopPropagation(); if (event.key === "Escape") setDestinationsOpen(false); }}>
      <button className="connected-toggle" type="button" aria-expanded={destinationsOpen} onClick={() => setDestinationsOpen(value => !value)}>{destinations.length} connected subsystems <span aria-hidden="true">{destinationsOpen ? "−" : "+"}</span></button>
      {destinationsOpen && <div className="connected-list">{destinations.map(link => {
        const id = link.from === activeAreaId ? link.to : link.from;
        return <div key={id}><button type="button" onClick={() => { setDestinationsOpen(false); onNavigate(id); }}><span>{area(id).number}</span>{area(id).title}<span aria-hidden="true">↗</span></button><button type="button" aria-label={`Inspect connections with ${area(id).title}`} onClick={() => { setDestinationsOpen(false); setInspected(link.id); }}>{link.edges.length} links</button></div>;
      })}</div>}
    </nav>}
    {selected && <aside ref={inspector} className="connection-inspector" aria-label="Connection details" data-no-pan onPointerDown={event => event.stopPropagation()} onWheelCapture={event => event.stopPropagation()} onKeyDown={event => { event.stopPropagation(); if (event.key === "Escape") setInspected(null); }}>
      <div className="connection-inspector-heading"><span>{selected.edges.length} connections</span><button type="button" aria-label="Close connection details" onClick={() => setInspected(null)}>×</button></div>
      <div className="connection-endpoints">{[selected.from, selected.to].map(id => <button key={id} type="button" onClick={() => { setInspected(null); onNavigate(id); }}><span>{area(id).number}</span>{area(id).title}<span>↗</span></button>)}</div>
      <ol tabIndex={0} aria-label="Individual connections">{selected.edges.map(edge => <li key={edge.id} data-edge-id={edge.id}><strong>{plain(graph.nodes[edge.source].label).split(" · ")[0]} {arrow(edge.arrowStart, edge.arrowEnd)} {plain(graph.nodes[edge.target].label).split(" · ")[0]}</strong><p>{plain(edge.label) || "Direct connection"}{edge.stroke === "dotted" ? " · dotted" : edge.stroke === "thick" ? " · emphasized" : ""}</p><small>{plain(graph.nodes[edge.source].label)}<br />{plain(graph.nodes[edge.target].label)}</small></li>)}</ol>
    </aside>}
  </>;
}
