import type { Mermaid } from "mermaid";
import type { FlowDB } from "mermaid/dist/diagrams/flowchart/flowDb.js";
import type { Box, CodebaseGraph, MapArea, MapEdge, MapNode, RenderedArea } from "./graph";

type FlowDatabase = Pick<FlowDB, "getSubGraphs" | "getVertices" | "getEdges" | "getClasses" | "getDirection">;
type Styles = {
  classes: Record<string, string[]>;
  nodes: Record<string, string[]>;
  edges: Record<string, { styles: string[]; classes: string[]; length: number; curve?: string }>;
  direction: string;
  areaDirections: Record<string, string>;
};

const FONT_SIZE = 14;
const MAX_TEXT_SIZE = 200_000;
const MAX_EDGES = 2_000;
const graphStyles = new WeakMap<CodebaseGraph, Styles>();
const renderedAreas = new WeakMap<CodebaseGraph, Map<string, Promise<RenderedArea>>>();
let mermaidPromise: Promise<Mermaid> | undefined;
let operationQueue: Promise<void> = Promise.resolve();
let renderSequence = 0;
let graphLoad: { source: string; promise: Promise<CodebaseGraph> } | undefined;

// The adapter is intentionally pinned to Mermaid 12. Its public parse() only
// reports the diagram type; these flowchart database getters expose membership.
function flowDatabase(value: unknown): FlowDatabase {
  if (value === null || typeof value !== "object") throw new Error("Mermaid returned no flowchart model.");
  for (const method of ["getSubGraphs", "getVertices", "getEdges", "getClasses", "getDirection"] as const) {
    if (!(method in value) || typeof (value as Record<string, unknown>)[method] !== "function") {
      throw new Error("This Mermaid version does not expose the expected flowchart model.");
    }
  }
  return value as FlowDatabase;
}

function serialized<T>(operation: () => Promise<T>): Promise<T> {
  const result = operationQueue.then(operation);
  operationQueue = result.then(() => undefined, () => undefined);
  return result;
}

async function mermaidRuntime(): Promise<Mermaid> {
  if (typeof document === "undefined") throw new Error("The codebase diagram must be loaded in a browser.");
  mermaidPromise ??= import("mermaid").then(({ default: mermaid }) => {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      suppressErrorRendering: true,
      layout: "elk",
      maxTextSize: MAX_TEXT_SIZE,
      maxEdges: MAX_EDGES,
      theme: "base",
      fontFamily: "Arial, Helvetica, sans-serif",
      themeVariables: {
        primaryColor: "#ffffff",
        primaryTextColor: "#242a30",
        primaryBorderColor: "#aeb7be",
        lineColor: "#8a949e",
        secondaryColor: "#f5f7f8",
        tertiaryColor: "#fafbfc",
        clusterBkg: "#fafbfc",
        clusterBorder: "#dce1e5",
        edgeLabelBackground: "#ffffff",
        fontSize: `${FONT_SIZE}px`,
      },
      flowchart: { htmlLabels: true, useMaxWidth: false, curve: "basis", nodeSpacing: 44, rankSpacing: 64 },
    });
    return mermaid;
  }).catch((error: unknown) => {
    mermaidPromise = undefined;
    throw error;
  });
  return mermaidPromise;
}

// Mermaid encodes its #entity; syntax before parsing and restores it after SVG
// rendering. Restore it here as well so the copied model contains real labels.
function restoreEntities(value: string): string {
  return value.replace(/ﬂ°°/g, "&#").replace(/ﬂ°/g, "&").replace(/¶ß/g, ";");
}

function areaTitle(id: string, rawTitle: string, index: number, nodeIds: string[]): MapArea {
  const fullTitle = restoreEntities(rawTitle);
  const parts = fullTitle.split(/\s*·\s*/);
  const number = /^\d+$/.test(parts[0]) ? parts.shift()! : String(index + 1).padStart(2, "0");
  const platform = parts.length > 1 ? parts.pop()! : "";
  return { id, number, title: parts.join(" · ") || fullTitle, platform, fullTitle, nodeIds };
}

const shapeNames: Record<string, string> = {
  square: "rect", squareRect: "rect", rect: "rect",
  round: "rounded", roundedRect: "rounded", rounded: "rounded",
  diamond: "diamond", cylinder: "cyl", cyl: "cyl", circle: "circle",
  doublecircle: "dbl-circ", "dbl-circ": "dbl-circ", ellipse: "ellipse",
  stadium: "stadium", subroutine: "subproc", subproc: "subproc",
  hexagon: "hex", hex: "hex", odd: "odd", trapezoid: "trap-b",
  inv_trapezoid: "trap-t", lean_right: "lean-r", lean_left: "lean-l",
  "trap-b": "trap-b", "trap-t": "trap-t", "lean-r": "lean-r", "lean-l": "lean-l",
};

export function loadGraph(source: string): Promise<CodebaseGraph> {
  if (graphLoad?.source === source) return graphLoad.promise;
  const promise = serialized(async () => {
    if (source.length > MAX_TEXT_SIZE) throw new Error(`The diagram exceeds the ${MAX_TEXT_SIZE.toLocaleString()} character limit.`);
    const mermaid = await mermaidRuntime();
    const diagram = await mermaid.mermaidAPI.getDiagramFromText(source);
    if (!diagram.type.startsWith("flowchart")) throw new Error("The codebase map must be a Mermaid flowchart with named areas.");
    const db = flowDatabase(diagram.db);
    const subgraphs = db.getSubGraphs();
    const vertices = db.getVertices();
    const rawEdges = db.getEdges();
    if (!subgraphs.length) throw new Error("The codebase map needs at least one named subgraph area.");
    const areaIds = new Set(subgraphs.map((area) => area.id));
    if (areaIds.size !== subgraphs.length) throw new Error("Every codebase area must have a unique ID.");
    const membership = new Map<string, string>();
    const areas = subgraphs.map((area, index) => {
      if (area.nodes.some((id) => areaIds.has(id))) throw new Error("Nested areas are not supported; use flat named subgraphs.");
      if (!area.nodes.length) throw new Error(`Area ${area.id} has no nodes.`);
      if (area.metadata?.view === "collapsed") throw new Error(`Area ${area.id} must retain its complete source nodes.`);
      for (const id of area.nodes) {
        if (membership.has(id)) throw new Error(`Node ${id} belongs to more than one area.`);
        if (!vertices.has(id)) throw new Error(`Area ${area.id} references unknown node ${id}.`);
        membership.set(id, area.id);
      }
      return areaTitle(area.id, area.title, index, [...area.nodes]);
    });
    const nodes: Record<string, MapNode> = Object.create(null);
    const styles: Styles = {
      classes: Object.create(null), nodes: Object.create(null), edges: Object.create(null),
      direction: db.getDirection() || "TB", areaDirections: Object.create(null),
    };
    for (const area of subgraphs) styles.areaDirections[area.id] = area.dir || styles.direction;
    for (const [id, definition] of db.getClasses()) styles.classes[id] = [...definition.styles];
    for (const [id, vertex] of vertices) {
      const areaId = membership.get(id);
      if (!areaId) throw new Error(`Node ${id} must belong to one named area.`);
      const shape = shapeNames[vertex.type || "square"];
      if (!shape || vertex.icon || vertex.img) throw new Error(`Node ${id} uses an unsupported shape: ${vertex.type || "image/icon"}.`);
      if (vertex.labelType === "markdown") throw new Error(`Node ${id} uses a Markdown label; use a plain label with line breaks.`);
      if (vertex.link || vertex.haveCallback) throw new Error(`Node ${id} has a click action; this map supports area navigation only.`);
      nodes[id] = { id, areaId, label: restoreEntities(vertex.text || id), shape, classes: [...vertex.classes] };
      styles.nodes[id] = [...vertex.styles];
    }
    const edgeIds = new Set<string>();
    const edges: MapEdge[] = rawEdges.map((edge, index) => {
      if (!nodes[edge.start] || !nodes[edge.end]) throw new Error("Every connection must link two nodes inside named areas.");
      const id = edge.id || `edge-${index}`;
      if (edgeIds.has(id)) throw new Error(`Connection ID ${id} is repeated.`);
      edgeIds.add(id);
      const type = edge.type || "arrow_open";
      if (!["arrow_point", "double_arrow_point", "arrow_open"].includes(type)) {
        throw new Error(`Connection ${id} uses an unsupported arrow type: ${type}.`);
      }
      if (edge.stroke === "invisible" || edge.animate || edge.labelType === "markdown") {
        throw new Error(`Connection ${id} uses unsupported invisible, animated, or Markdown styling.`);
      }
      styles.edges[id] = {
        styles: [...(rawEdges.defaultStyle || []), ...(edge.style || [])],
        classes: [...edge.classes], length: edge.length || 1,
        curve: edge.interpolate || rawEdges.defaultInterpolate,
      };
      return {
        id, source: edge.start, target: edge.end, label: restoreEntities(edge.text),
        stroke: edge.stroke || "normal", arrowStart: type === "double_arrow_point", arrowEnd: type !== "arrow_open",
      };
    });
    const graph: CodebaseGraph = { areas, nodes, edges };
    graphStyles.set(graph, styles);
    return graph;
  });
  graphLoad = { source, promise };
  void promise.catch(() => {
    if (graphLoad?.promise === promise) graphLoad = undefined;
  });
  return promise;
}

function quotedLabel(value: string): string {
  return value.replace(/"/g, "#quot;").replace(/\r?\n/g, "<br/>");
}

function edgeArrow(edge: MapEdge, length: number): string {
  if (edge.stroke === "dotted") return `${edge.arrowStart ? "<" : ""}-.${".".repeat(Math.max(0, length - 1))}-${edge.arrowEnd ? ">" : ""}`;
  const line = (edge.stroke === "thick" ? "=" : "-").repeat(Math.max(2, length + (edge.arrowEnd ? 1 : 2)));
  return `${edge.arrowStart ? "<" : ""}${line}${edge.arrowEnd ? ">" : ""}`;
}

function areaSource(graph: CodebaseGraph, area: MapArea, renderId: string, styles: Styles) {
  const aliases = new Map(area.nodeIds.map((id, index) => [id, `n${index}`]));
  const internalEdges = graph.edges.filter((edge) => graph.nodes[edge.source].areaId === area.id && graph.nodes[edge.target].areaId === area.id);
  const lines = [`flowchart ${styles.areaDirections[area.id]}`];
  const classAliases = new Map(Object.keys(styles.classes).map((id, index) => [id, `map_style_${index}`]));
  for (const id of area.nodeIds) {
    const node = graph.nodes[id];
    const alias = aliases.get(id)!;
    lines.push(`${alias}@{ shape: ${node.shape}, label: ${JSON.stringify(node.label)} }`);
    const classes = [`map_node_${alias}`, ...node.classes.map((name) => classAliases.get(name)).filter((name) => name !== undefined)];
    if (classAliases.has("default")) classes.push(classAliases.get("default")!);
    for (const name of classes) lines.push(`class ${alias} ${name};`);
    if (styles.nodes[id]?.length) lines.push(`style ${alias} ${styles.nodes[id].join(",")};`);
  }
  for (const [index, edge] of internalEdges.entries()) {
    const alias = `${renderId}_edge_${index}`;
    const detail = styles.edges[edge.id];
    const label = edge.label ? `|"${quotedLabel(edge.label)}"|` : "";
    lines.push(`${aliases.get(edge.source)} ${alias}@${edgeArrow(edge, detail.length)}${label} ${aliases.get(edge.target)}`);
    for (const name of detail.classes) {
      const mapped = classAliases.get(name);
      if (mapped) lines.push(`class ${alias} ${mapped};`);
    }
    if (detail.styles.length) lines.push(`linkStyle ${index} ${detail.styles.join(",")};`);
    if (detail.curve) lines.push(`${alias}@{ curve: ${JSON.stringify(detail.curve)} }`);
  }
  for (const [id, alias] of classAliases) lines.push(`classDef ${alias} ${styles.classes[id].join(",")};`);
  return { source: lines.join("\n"), aliases, internalEdges };
}

function wrapSecondaryLines(node: SVGGraphicsElement) {
  const label = node.querySelector(".nodeLabel");
  if (!label) return;
  const content = label.querySelector("p") || label;
  const firstBreak = content.querySelector("br");
  if (!firstBreak) return;
  const range = document.createRange();
  range.setStartBefore(firstBreak);
  range.setEnd(content, content.childNodes.length);
  const details = document.createElement("span");
  details.className = "node-details";
  details.append(range.extractContents());
  content.append(details);
}

function nodeBounds(node: SVGGraphicsElement, svg: SVGSVGElement): Box {
  const bounds = node.getBBox();
  const parentMatrix = svg.getCTM();
  const childMatrix = node.getCTM();
  if (!parentMatrix || !childMatrix) throw new Error("The local diagram could not be measured.");
  const matrix = parentMatrix.inverse().multiply(childMatrix);
  const points = [
    new DOMPoint(bounds.x, bounds.y), new DOMPoint(bounds.x + bounds.width, bounds.y),
    new DOMPoint(bounds.x, bounds.y + bounds.height), new DOMPoint(bounds.x + bounds.width, bounds.y + bounds.height),
  ].map((point) => point.matrixTransform(matrix));
  const x = Math.min(...points.map((point) => point.x));
  const y = Math.min(...points.map((point) => point.y));
  const width = Math.max(...points.map((point) => point.x)) - x;
  const height = Math.max(...points.map((point) => point.y)) - y;
  if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
    throw new Error("The local diagram returned invalid node bounds.");
  }
  return { x, y, width, height };
}

export function renderArea(graph: CodebaseGraph, areaId: string): Promise<RenderedArea> {
  let cache = renderedAreas.get(graph);
  if (!cache) { cache = new Map(); renderedAreas.set(graph, cache); }
  const cached = cache.get(areaId);
  if (cached) return cached;
  const promise = serialized(async () => {
    const area = graph.areas.find((candidate) => candidate.id === areaId);
    const styles = graphStyles.get(graph);
    if (!area || !styles) throw new Error(`Unknown codebase area ${areaId}.`);
    const mermaid = await mermaidRuntime();
    const renderId = `intentive_area_${++renderSequence}`;
    const generated = areaSource(graph, area, renderId, styles);
    const staging = document.createElement("div");
    staging.setAttribute("aria-hidden", "true");
    staging.style.cssText = "position:absolute;left:-100000px;top:0;width:1600px;visibility:hidden;pointer-events:none;";
    document.body.append(staging);
    try {
      const result = await mermaid.render(renderId, generated.source, staging);
      staging.innerHTML = result.svg;
      const svg = staging.querySelector("svg");
      if (!svg) throw new Error(`Area ${area.fullTitle} returned no diagram.`);
      const { x, y, width, height } = svg.viewBox.baseVal;
      if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
        throw new Error(`Area ${area.fullTitle} returned invalid dimensions.`);
      }
      const normalized = document.createElementNS("http://www.w3.org/2000/svg", "g");
      normalized.setAttribute("transform", `translate(${-x}, ${-y})`);
      for (const child of [...svg.children]) {
        if (!["defs", "style", "title", "desc"].includes(child.tagName.toLowerCase())) normalized.append(child);
      }
      svg.append(normalized);
      svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
      svg.setAttribute("width", String(width));
      svg.setAttribute("height", String(height));
      svg.style.maxWidth = "none";
      svg.style.width = `${width}px`;
      svg.style.height = `${height}px`;
      svg.setAttribute("role", "img");
      svg.setAttribute("aria-label", area.fullTitle);
      svg.setAttribute("data-area-id", area.id);
      const nodes: Record<string, Box> = Object.create(null);
      for (const [id, alias] of generated.aliases) {
        const node = svg.querySelector<SVGGraphicsElement>(`g.node.map_node_${alias}`);
        if (!node) throw new Error(`Node ${id} is missing from area ${area.fullTitle}.`);
        node.setAttribute("data-node-id", id);
        wrapSecondaryLines(node);
        nodes[id] = nodeBounds(node, svg);
      }
      for (const [index, edge] of generated.internalEdges.entries()) {
        const path = svg.querySelector(`path[data-id="${renderId}_edge_${index}"]`);
        if (!path) throw new Error(`Connection ${edge.id} is missing from area ${area.fullTitle}.`);
        path.setAttribute("data-edge-id", edge.id);
        path.setAttribute("data-edge-kind", "internal");
        path.setAttribute("data-source-id", edge.source);
        path.setAttribute("data-target-id", edge.target);
      }
      return { svg: svg.outerHTML, width, height, nodes, fontSize: FONT_SIZE };
    } finally {
      staging.remove();
    }
  });
  cache.set(areaId, promise);
  void promise.catch(() => {
    if (cache.get(areaId) === promise) cache.delete(areaId);
  });
  return promise;
}
