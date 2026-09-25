import type { Box, CodebaseGraph, MapEdge, RenderedArea } from "./graph";

export const AREA_WIDTH = 360;
export const AREA_HEIGHT = 240;
export const AREA_GAP = 40;
export const AREA_COLUMNS = 5;
export const AREA_HEADER = 54;
export const AREA_PADDING = 20;

export type Point = { x: number; y: number };
export type DiagramPlacement = Box & { scale: number };
export type RoutedConnection = {
  edge: MapEdge;
  remoteAreaId: string;
  remoteBox: Box;
  points: Point[];
  path: string;
};

/** Grid coordinates belong to the source order, never to the selected area. */
export function getAreaBox(index: number): Box {
  return {
    x: (index % AREA_COLUMNS) * (AREA_WIDTH + AREA_GAP),
    y: Math.floor(index / AREA_COLUMNS) * (AREA_HEIGHT + AREA_GAP),
    width: AREA_WIDTH,
    height: AREA_HEIGHT,
  };
}

export function getWorldBounds(count: number): Box {
  if (count <= 0) return { x: 0, y: 0, width: 0, height: 0 };
  return {
    x: -AREA_GAP / 2,
    y: -AREA_GAP / 2,
    width: Math.min(count, AREA_COLUMNS) * (AREA_WIDTH + AREA_GAP),
    height: Math.ceil(count / AREA_COLUMNS) * (AREA_HEIGHT + AREA_GAP),
  };
}

export function getDiagramPlacement(area: Box, rendered: Pick<RenderedArea, "width" | "height">): DiagramPlacement {
  const availableWidth = area.width - AREA_PADDING * 2;
  const availableHeight = area.height - AREA_HEADER - AREA_PADDING * 2;
  const scale = Math.min(availableWidth / rendered.width, availableHeight / rendered.height);
  const width = rendered.width * scale;
  const height = rendered.height * scale;
  return {
    x: area.x + (area.width - width) / 2,
    y: area.y + AREA_HEADER + AREA_PADDING + (availableHeight - height) / 2,
    width,
    height,
    scale,
  };
}

function laneOffset(id: string): number {
  let hash = 0;
  for (const char of id) hash = ((hash * 31) + char.charCodeAt(0)) | 0;
  return ((hash >>> 0) % 7 - 3) * 2;
}

function compactPoints(points: Point[]): Point[] {
  const distinct = points.filter((point, index) => !index || point.x !== points[index - 1].x || point.y !== points[index - 1].y);
  return distinct.filter((point, index) => {
    const previous = distinct[index - 1];
    const next = distinct[index + 1];
    return !previous || !next || !((previous.x === point.x && point.x === next.x) || (previous.y === point.y && point.y === next.y));
  });
}

function crossesBox(start: Point, end: Point, box: Box): boolean {
  if (start.x === end.x) return start.x > box.x && start.x < box.x + box.width && Math.max(start.y, end.y) > box.y && Math.min(start.y, end.y) < box.y + box.height;
  return start.y > box.y && start.y < box.y + box.height && Math.max(start.x, end.x) > box.x && Math.min(start.x, end.x) < box.x + box.width;
}

type SearchEntry = { state: number; cost: number; priority: number };

/** Small binary heap keeps routing bounded when an area has many incident edges. */
class RouteQueue {
  private entries: SearchEntry[] = [];

  push(entry: SearchEntry) {
    let index = this.entries.length;
    this.entries.push(entry);
    while (index > 0) {
      const parent = Math.floor((index - 1) / 2);
      if (this.entries[parent].priority <= entry.priority) break;
      this.entries[index] = this.entries[parent];
      index = parent;
    }
    this.entries[index] = entry;
  }

  pop(): SearchEntry | undefined {
    const first = this.entries[0];
    const last = this.entries.pop();
    if (this.entries.length && last) {
      let index = 0;
      while (index * 2 + 1 < this.entries.length) {
        let child = index * 2 + 1;
        if (child + 1 < this.entries.length && this.entries[child + 1].priority < this.entries[child].priority) child++;
        if (last.priority <= this.entries[child].priority) break;
        this.entries[index] = this.entries[child];
        index = child;
      }
      this.entries[index] = last;
    }
    return first;
  }
}

/** Route from the selected node to its existing gutter without crossing local labels/shapes. */
function escapeRoute(start: Point, end: Point, area: Box, source: Box, blockers: Box[], clearance: number): Point[] | null {
  const obstacles = [source, ...blockers.map(box => ({ x: box.x - clearance, y: box.y - clearance, width: box.width + clearance * 2, height: box.height + clearance * 2 }))];
  const clear = (a: Point, b: Point) => !obstacles.some(box => crossesBox(a, b, box));
  if (clear(start, end)) return [start, end];
  const direction = start.y === end.y ? 0 : 1;
  const stub = direction === 0
    ? { x: start.x + Math.sign(end.x - start.x) * Math.max(0.25, clearance), y: start.y }
    : { x: start.x, y: start.y + Math.sign(end.y - start.y) * Math.max(0.25, clearance) };
  if (!clear(start, stub)) return null;
  const margin = AREA_GAP - 2;
  const xs = [...new Set([stub.x, end.x, area.x - margin, area.x + area.width + margin, ...obstacles.flatMap(box => [box.x, box.x + box.width])])]
    .filter(x => x >= area.x - margin && x <= area.x + area.width + margin).sort((a, b) => a - b);
  const ys = [...new Set([stub.y, end.y, area.y - margin, area.y + area.height + margin, ...obstacles.flatMap(box => [box.y, box.y + box.height])])]
    .filter(y => y >= area.y - margin && y <= area.y + area.height + margin).sort((a, b) => a - b);
  const point = (vertex: number): Point => ({ x: xs[Math.floor(vertex / ys.length)], y: ys[vertex % ys.length] });
  const startVertex = xs.indexOf(stub.x) * ys.length + ys.indexOf(stub.y);
  const endVertex = xs.indexOf(end.x) * ys.length + ys.indexOf(end.y);
  const distances = new Float64Array(xs.length * ys.length * 2).fill(Infinity);
  const previous = new Int32Array(distances.length).fill(-1);
  const queue = new RouteQueue();
  const startState = startVertex * 2 + direction;
  distances[startState] = 0;
  queue.push({ state: startState, cost: 0, priority: 0 });
  let entry: SearchEntry | undefined;
  while ((entry = queue.pop())) {
    if (entry.cost !== distances[entry.state]) continue;
    const vertex = Math.floor(entry.state / 2);
    if (vertex === endVertex) {
      const path: Point[] = [];
      for (let state = entry.state; state !== -1; state = previous[state]) path.push(point(Math.floor(state / 2)));
      return compactPoints([start, ...path.reverse()]);
    }
    const current = point(vertex);
    const x = Math.floor(vertex / ys.length);
    const y = vertex % ys.length;
    for (const [nextX, nextY, axis] of [[x - 1, y, 0], [x + 1, y, 0], [x, y - 1, 1], [x, y + 1, 1]]) {
      if (nextX < 0 || nextX >= xs.length || nextY < 0 || nextY >= ys.length) continue;
      const nextVertex = nextX * ys.length + nextY;
      const next = point(nextVertex);
      if (!clear(current, next)) continue;
      const state = nextVertex * 2 + axis;
      const distance = Math.abs(next.x - current.x) + Math.abs(next.y - current.y);
      const cost = entry.cost + distance + (entry.state % 2 === axis ? 0 : 4);
      if (cost >= distances[state]) continue;
      distances[state] = cost;
      previous[state] = entry.state;
      queue.push({ state, cost, priority: cost + Math.abs(next.x - end.x) + Math.abs(next.y - end.y) });
    }
  }
  return null;
}

/** Preserve each edge and its direction, using the gutters around other tiles. */
export function getAreaConnections(graph: CodebaseGraph, activeAreaId: string, rendered: RenderedArea): RoutedConnection[] {
  const activeIndex = graph.areas.findIndex(area => area.id === activeAreaId);
  if (activeIndex < 0) return [];
  const activeBox = getAreaBox(activeIndex);
  const placement = getDiagramPlacement(activeBox, rendered);
  const activeNodes = new Map(graph.areas[activeIndex].nodeIds.flatMap(id => {
    const box = rendered.nodes[id];
    return box ? [[id, { x: placement.x + box.x * placement.scale, y: placement.y + box.y * placement.scale, width: box.width * placement.scale, height: box.height * placement.scale }] as const] : [];
  }));
  const areaIndexes = new Map(graph.areas.map((area, index) => [area.id, index]));
  const incident = graph.edges.filter(edge => {
    const sourceArea = graph.nodes[edge.source]?.areaId;
    const targetArea = graph.nodes[edge.target]?.areaId;
    return sourceArea !== targetArea && (sourceArea === activeAreaId || targetArea === activeAreaId);
  });
  const remoteCounts = new Map<string, number>();
  for (const edge of incident) {
    const remoteId = graph.nodes[edge.source].areaId === activeAreaId ? graph.nodes[edge.target].areaId : graph.nodes[edge.source].areaId;
    remoteCounts.set(remoteId, (remoteCounts.get(remoteId) ?? 0) + 1);
  }
  const remoteSlots = new Map<string, number>();

  return incident.flatMap(edge => {
    const outgoing = graph.nodes[edge.source].areaId === activeAreaId;
    const activeNodeId = outgoing ? edge.source : edge.target;
    const remoteAreaId = graph.nodes[outgoing ? edge.target : edge.source].areaId;
    const remoteIndex = areaIndexes.get(remoteAreaId);
    if (remoteIndex === undefined) return [];
    const remoteBox = getAreaBox(remoteIndex);
    const slot = remoteSlots.get(remoteAreaId) ?? 0;
    remoteSlots.set(remoteAreaId, slot + 1);
    const fraction = (slot + 1) / ((remoteCounts.get(remoteAreaId) ?? 1) + 1);
    const node = activeNodes.get(activeNodeId) ?? placement;
    const lane = laneOffset(edge.id);
    const columnDelta = remoteIndex % AREA_COLUMNS - activeIndex % AREA_COLUMNS;
    const rowDelta = Math.floor(remoteIndex / AREA_COLUMNS) - Math.floor(activeIndex / AREA_COLUMNS);
    let points: Point[];

    if (columnDelta !== 0) {
      const direction = Math.sign(columnDelta);
      const start = { x: direction > 0 ? node.x + node.width : node.x, y: node.y + node.height / 2 };
      const end = {
        x: direction > 0 ? remoteBox.x : remoteBox.x + remoteBox.width,
        y: remoteBox.y + AREA_HEADER + 12 + (remoteBox.height - AREA_HEADER - 24) * fraction,
      };
      const exitX = (direction > 0 ? activeBox.x + activeBox.width : activeBox.x) + direction * (AREA_GAP / 2 + lane);
      const entryX = end.x - direction * (AREA_GAP / 2 - lane);
      if (Math.abs(columnDelta) === 1) {
        points = [start, { x: exitX, y: start.y }, { x: exitX, y: end.y }, end];
      } else {
        const gutterY = rowDelta > 0 ? activeBox.y + activeBox.height + AREA_GAP / 2 + lane : activeBox.y - 12 + lane;
        points = [start, { x: exitX, y: start.y }, { x: exitX, y: gutterY }, { x: entryX, y: gutterY }, { x: entryX, y: end.y }, end];
      }
    } else {
      const direction = Math.sign(rowDelta);
      const start = { x: node.x + node.width / 2, y: direction > 0 ? node.y + node.height : node.y };
      const end = { x: remoteBox.x + 20 + (remoteBox.width - 40) * fraction, y: direction > 0 ? remoteBox.y : remoteBox.y + remoteBox.height };
      const exitY = (direction > 0 ? activeBox.y + activeBox.height : activeBox.y) + direction * (AREA_GAP / 2 + lane);
      const entryY = end.y - direction * (AREA_GAP / 2 - lane);
      if (Math.abs(rowDelta) === 1) {
        points = [start, { x: start.x, y: exitY }, { x: end.x, y: exitY }, end];
      } else {
        const gutterX = activeBox.x + activeBox.width + 12 + lane;
        points = [start, { x: start.x, y: exitY }, { x: gutterX, y: exitY }, { x: gutterX, y: entryY }, { x: end.x, y: entryY }, end];
      }
    }

    const blockers = [...activeNodes].filter(([id]) => id !== activeNodeId).map(([, box]) => box);
    blockers.push({ ...activeBox, height: AREA_HEADER });
    const escape = escapeRoute(points[0], points[1], activeBox, node, blockers, Math.min(3, placement.scale * 8))
      ?? escapeRoute(points[0], points[1], activeBox, node, blockers, 0);
    if (!escape) throw new Error(`Cannot route connection ${edge.id} out of overlapping node geometry.`);
    points = [...escape, ...points.slice(2)];
    points = compactPoints(outgoing ? points : points.reverse());
    return [{ edge, remoteAreaId, remoteBox, points, path: points.map((point, index) => `${index ? "L" : "M"}${point.x},${point.y}`).join(" ") }];
  });
}
