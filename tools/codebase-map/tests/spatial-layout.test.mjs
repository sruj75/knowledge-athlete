import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { createSpatialLayout } from "../lib/spatial-layout.ts";

const source = readFileSync(new URL("../../../docs/architecture/intentive-codeflow.mmd", import.meta.url), "utf8");
const areaIds = [...source.matchAll(/subgraph\s+(AREA_\d+)\[/g)].map(match => match[1]);

function fixture() {
  const areas = areaIds.map((id, index) => ({ id, number: String(index + 1).padStart(2, "0"), title: id, fullTitle: id, platform: "", nodeIds: [] }));
  const boxes = Object.fromEntries(areas.map((area, index) => [area.id, {
    x: 400 + Math.sin(index * 1.2) * 220,
    y: index * 140,
    width: 120 + (index % 3) * 80,
    height: 100 + (index % 4) * 30,
  }]));
  // Deliberate geographic anchors, with different sizes and dense neighbors.
  boxes.AREA_02.x = 0;
  boxes.AREA_16.x = 1400;
  boxes.AREA_13.y = 800;
  boxes.AREA_15.y = 2200;
  boxes.AREA_21 = { x: 500, y: 0, width: 240, height: 100 };
  boxes.AREA_23 = { x: 1200, y: -140, width: 120, height: 240 };
  return { areas, nodes: {}, edges: [], layout: { bounds: { x: 0, y: -140, width: 1600, height: 3500 }, areas: boxes, nodes: {}, edges: {} } };
}

const center = box => ({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
const overlaps = (first, second) => first.x < second.x + second.width && first.x + first.width > second.x && first.y < second.y + second.height && first.y + first.height > second.y;

test("the source's 23 areas become readable, non-overlapping irregular regions", () => {
  const layout = createSpatialLayout(fixture());
  assert.equal(areaIds.length, 23);
  assert.deepEqual(Object.keys(layout.areas), [...areaIds].sort());
  for (const [id, box] of Object.entries(layout.areas)) {
    assert.ok(box.width >= 292 && box.width <= 324, id);
    assert.ok(box.height >= 144 && box.height <= 154, id);
    assert.ok(box.x >= 0 && box.y >= 0, id);
    assert.ok(box.x + box.width <= layout.bounds.width, id);
    assert.ok(box.y + box.height <= layout.bounds.height, id);
    for (const [otherId, other] of Object.entries(layout.areas)) {
      if (otherId !== id) assert.equal(overlaps(box, other), false, `${id} overlaps ${otherId}`);
    }
  }
  assert.ok(new Set(Object.values(layout.areas).map(box => box.x)).size > 5);
});

test("layout is stable across repeated calls and input ordering without mutating canonical geometry", () => {
  const graph = fixture();
  const original = JSON.stringify(graph);
  const layout = createSpatialLayout(graph);
  assert.deepEqual(createSpatialLayout(graph), layout);
  assert.deepEqual(createSpatialLayout({ ...graph, areas: [...graph.areas].reverse() }), layout);
  assert.equal(JSON.stringify(graph), original);
});

test("canonical north/south and broad east/west landmarks survive crowded-region separation", () => {
  const layout = createSpatialLayout(fixture());
  const point = id => center(layout.areas[id]);
  assert.ok(point("AREA_13").y < point("AREA_15").y);
  assert.ok(point("AREA_02").x < point("AREA_16").x);
  assert.ok(point("AREA_23").x > point("AREA_21").x);
  assert.ok(point("AREA_23").y < point("AREA_21").y);
});

test("coincident canonical centers still produce finite, separate regions", () => {
  const graph = fixture();
  for (const id of areaIds) graph.layout.areas[id] = { x: 0, y: 0, width: 200, height: 200 };
  const layout = createSpatialLayout(graph);
  const boxes = Object.values(layout.areas);
  for (let index = 0; index < boxes.length; index++) {
    assert.ok(Object.values(boxes[index]).every(Number.isFinite));
    for (const other of boxes.slice(index + 1)) assert.equal(overlaps(boxes[index], other), false);
  }
});

test("missing canonical geometry fails clearly; an empty model has an empty overview", () => {
  const graph = fixture();
  delete graph.layout.areas.AREA_01;
  assert.throws(() => createSpatialLayout(graph), /AREA_01.*canonical layout/);
  const empty = createSpatialLayout({ ...graph, areas: [] });
  assert.deepEqual(empty.areas, {});
  assert.ok(empty.bounds.width > 0 && empty.bounds.height > 0);
});
