import assert from "node:assert/strict";
import test from "node:test";
import { AREA_WIDTH, AREA_HEIGHT, AREA_GAP, getAreaBox, getWorldBounds, getDiagramPlacement, getAreaConnections } from "../lib/map-geometry.ts";

function fixture() {
  const areas = Array.from({ length: 23 }, (_, index) => ({
    id: `AREA_${index + 1}`, number: String(index + 1).padStart(2, "0"), title: `Area ${index + 1}`, platform: "Mac", fullTitle: `Area ${index + 1}`, nodeIds: [`NODE_${index + 1}`],
  }));
  const nodes = Object.fromEntries(areas.map(area => [area.nodeIds[0], { id: area.nodeIds[0], areaId: area.id, label: area.title, shape: "rect", classes: [] }]));
  const rendered = { svg: "", width: 500, height: 200, fontSize: 14, nodes: Object.fromEntries(areas.map(area => [area.nodeIds[0], { x: 100, y: 50, width: 200, height: 80 }])) };
  return { graph: { areas, nodes, edges: [] }, rendered };
}

function edge(source, target, id = `${source}-${target}`, stroke = "normal") {
  return { id, source: `NODE_${source}`, target: `NODE_${target}`, label: `Connect ${source} to ${target}`, stroke, arrowStart: false, arrowEnd: true };
}

function segmentCrossesInterior(start, end, box) {
  if (start.x === end.x) return start.x > box.x && start.x < box.x + box.width && Math.max(start.y, end.y) > box.y && Math.min(start.y, end.y) < box.y + box.height;
  if (start.y === end.y) return start.y > box.y && start.y < box.y + box.height && Math.max(start.x, end.x) > box.x && Math.min(start.x, end.x) < box.x + box.width;
  assert.fail("Routes must use orthogonal gutter segments");
}

test("23 areas retain a fixed five-column grid, including the partial final row", () => {
  assert.equal(AREA_WIDTH, 360);
  assert.equal(AREA_HEIGHT, 240);
  assert.equal(AREA_GAP, 40);
  assert.deepEqual(getAreaBox(0), { x: 0, y: 0, width: 360, height: 240 });
  assert.deepEqual(getAreaBox(4), { x: 1600, y: 0, width: 360, height: 240 });
  assert.deepEqual(getAreaBox(5), { x: 0, y: 280, width: 360, height: 240 });
  assert.deepEqual(getAreaBox(22), { x: 800, y: 1120, width: 360, height: 240 });
  assert.deepEqual(getWorldBounds(23), { x: -20, y: -20, width: 2000, height: 1400 });
  assert.deepEqual(getWorldBounds(0), { x: 0, y: 0, width: 0, height: 0 });
});

test("local diagrams fit below the tile header with fixed padding and unchanged aspect ratio", () => {
  const area = getAreaBox(6);
  for (const rendered of [{ width: 1000, height: 100 }, { width: 100, height: 1000 }]) {
    const placed = getDiagramPlacement(area, rendered);
    assert.ok(placed.x >= area.x + 20);
    assert.ok(placed.y >= area.y + 54 + 20);
    assert.ok(placed.x + placed.width <= area.x + area.width - 20);
    assert.ok(placed.y + placed.height <= area.y + area.height - 20);
    assert.ok(Math.abs(placed.width / placed.height - rendered.width / rendered.height) < 1e-12);
    assert.equal(placed.width, rendered.width * placed.scale);
  }
});

test("every active incident cross-edge remains distinct, directed and styled; other edges stay absent", () => {
  const { graph, rendered } = fixture();
  graph.edges = [edge(1, 6, "outbound", "thick"), edge(6, 1, "inbound", "dotted"), edge(1, 1, "internal"), edge(8, 9, "collapsed")];
  const before = JSON.stringify({ graph, rendered });
  const routes = getAreaConnections(graph, "AREA_1", rendered);
  assert.deepEqual(routes.map(route => route.edge.id), ["outbound", "inbound"]);
  assert.equal(routes[0].edge.stroke, "thick");
  assert.equal(routes[1].edge.stroke, "dotted");
  assert.equal(routes[0].edge, graph.edges[0]);
  const placement = getDiagramPlacement(getAreaBox(0), rendered);
  const node = rendered.nodes.NODE_1;
  const activePort = { x: placement.x + (node.x + node.width / 2) * placement.scale, y: placement.y + (node.y + node.height) * placement.scale };
  assert.deepEqual(routes[0].points[0], activePort);
  assert.deepEqual(routes[1].points.at(-1), activePort);
  assert.equal(routes[0].points.at(-1).y, getAreaBox(5).y);
  assert.equal(routes[1].points[0].y, getAreaBox(5).y);
  assert.equal(JSON.stringify({ graph, rendered }), before);
  assert.deepEqual(getAreaConnections(graph, "AREA_missing", rendered), []);
});

test("all source/remote combinations use gutters and never pass through an unrelated tile", () => {
  const { graph, rendered } = fixture();
  for (let active = 0; active < graph.areas.length; active++) {
    graph.edges = graph.areas.flatMap((_, remote) => remote === active ? [] : [edge(active + 1, remote + 1)]);
    const routes = getAreaConnections(graph, graph.areas[active].id, rendered);
    assert.equal(routes.length, 22);
    for (const route of routes) {
      const remote = graph.areas.findIndex(area => area.id === route.remoteAreaId);
      for (let index = 0; index < graph.areas.length; index++) {
        if (index === active || index === remote) continue;
        const box = getAreaBox(index);
        for (let segment = 1; segment < route.points.length; segment++) {
          assert.equal(segmentCrossesInterior(route.points[segment - 1], route.points[segment], box), false, `${route.edge.id} crosses area ${index + 1}`);
        }
      }
    }
  }
});

function worldNode(area, rendered, nodeId) {
  const placement = getDiagramPlacement(area, rendered);
  const node = rendered.nodes[nodeId];
  return { x: placement.x + node.x * placement.scale, y: placement.y + node.y * placement.scale, width: node.width * placement.scale, height: node.height * placement.scale };
}

function assertAvoids(routes, obstacles) {
  for (const route of routes) {
    for (const [id, box] of Object.entries(obstacles)) {
      for (let index = 1; index < route.points.length; index++) {
        assert.equal(segmentCrossesInterior(route.points[index - 1], route.points[index], box), false, `${route.edge.id} crosses ${id}`);
      }
    }
  }
}

test("escape detours around a local node directly between the source and its remote area", () => {
  const { graph, rendered } = fixture();
  graph.areas[0].nodeIds.push("BLOCKER");
  graph.nodes.BLOCKER = { id: "BLOCKER", areaId: "AREA_1", label: "Settings", shape: "rect", classes: ["surface"] };
  rendered.nodes.NODE_1 = { x: 50, y: 90, width: 80, height: 40 };
  rendered.nodes.BLOCKER = { x: 200, y: 70, width: 100, height: 80 };
  graph.edges = [edge(1, 2, "outbound"), edge(2, 1, "inbound")];
  const routes = getAreaConnections(graph, "AREA_1", rendered);
  const source = worldNode(getAreaBox(0), rendered, "NODE_1");
  const blocker = worldNode(getAreaBox(0), rendered, "BLOCKER");
  assert.equal(routes.length, 2);
  assertAvoids(routes, { source, blocker });
  const port = { x: source.x + source.width, y: source.y + source.height / 2 };
  assert.deepEqual(routes[0].points[0], port);
  assert.deepEqual(routes[1].points.at(-1), port);
  assert.equal(routes[0].points[1].y, port.y);
  assert.ok(routes[0].points[1].x > port.x);
  assert.ok(routes[0].points.some(point => point.y <= blocker.y || point.y >= blocker.y + blocker.height));
});

test("upward escapes avoid the area heading as well as local nodes", () => {
  const { graph, rendered } = fixture();
  graph.edges = [edge(6, 1)];
  const routes = getAreaConnections(graph, "AREA_6", rendered);
  assertAvoids(routes, { heading: { ...getAreaBox(5), height: 54 }, node: worldNode(getAreaBox(5), rendered, "NODE_6") });
  assert.equal(routes[0].points[0].y, worldNode(getAreaBox(5), rendered, "NODE_6").y);
});

test("measured Area 01 rectangles and permission/owner diamonds remain clear for every escape direction", () => {
  const { graph } = fixture();
  // Actual normalized Mermaid 12 / ELK SVG bounds from Area 01. APP's eastward
  // connection previously crossed the SETTINGS rectangle and its label.
  const rendered = {
    svg: "", fontSize: 14, width: 797.5247192382812, height: 1299.984375,
    nodes: {
      APP: { x: 168.44921875, y: 379.75, width: 306.75, height: 87 },
      DUPLICATE: { x: 194.82421875, y: 8, width: 255, height: 255 },
      AUTH: { x: 235.296875, y: 719.9166870117188, width: 158.84375, height: 87 },
      PERM: { x: 452.75909423828125, y: 573, width: 307.375, height: 307.375 },
      OWNER: { x: 8, y: 981.375, width: 310.609375, height: 310.609375 },
      WARM: { x: 358.109375, y: 981.375, width: 245.46875, height: 108 },
      SETTINGS: { x: 619.7825317382812, y: 364, width: 158.859375, height: 108 },
      STOP: { x: 43.296875, y: 573, width: 152, height: 108 },
    },
  };
  const nodeIds = Object.keys(rendered.nodes);
  // Put the measured area in the middle so every compass direction is exercised.
  graph.areas[11].nodeIds = nodeIds;
  for (const id of nodeIds) graph.nodes[id] = { id, areaId: "AREA_12", label: id, shape: ["DUPLICATE", "PERM", "OWNER"].includes(id) ? "diamond" : "rect", classes: [] };
  graph.edges = nodeIds.flatMap(id => graph.areas.flatMap((area, index) => index === 11 ? [] : [
    { ...edge(12, index + 1, `${id}-out-${index}`), source: id },
    { ...edge(index + 1, 12, `${id}-in-${index}`), target: id },
  ]));
  const routes = getAreaConnections(graph, "AREA_12", rendered);
  assert.equal(routes.length, nodeIds.length * 22 * 2);
  const boxes = Object.fromEntries(nodeIds.map(id => [id, worldNode(getAreaBox(11), rendered, id)]));
  assertAvoids(routes, boxes);
  for (const route of routes) {
    const activeId = nodeIds.includes(route.edge.source) ? route.edge.source : route.edge.target;
    const endpoint = route.edge.source === activeId ? route.points[0] : route.points.at(-1);
    const box = boxes[activeId];
    assert.ok(endpoint.x === box.x || endpoint.x === box.x + box.width || endpoint.y === box.y || endpoint.y === box.y + box.height);
  }
});
