import assert from "node:assert/strict";
import test from "node:test";
import { deriveAreaFlows } from "../lib/area-flows.ts";

function fixture(edges) {
  const nodes = {
    A: { id: "A", areaId: "AREA_A", label: "Start work<br/>Start.swift:10", shape: "rect", classes: [] },
    A2: { id: "A2", areaId: "AREA_A", label: "Finish work<br/>Finish.swift:20", shape: "diamond", classes: [] },
    B: { id: "B", areaId: "AREA_B", label: "Read archive<br/>Archive.ts:30", shape: "rect", classes: [] },
    C: { id: "C", areaId: "AREA_C", label: "Refresh account\nAccount.py:40", shape: "rect", classes: [] },
  };
  const areas = ["AREA_A", "AREA_B", "AREA_C"].map((id, index) => ({
    id, number: String(index + 1), title: id, fullTitle: id, platform: "", nodeIds: Object.values(nodes).filter(node => node.areaId === id).map(node => node.id),
  }));
  return { areas, nodes, edges, layout: { bounds: { x: 0, y: 0, width: 1, height: 1 }, areas: {} } };
}

const edge = (id, source, target, values = {}) => ({ id, source, target, label: "", stroke: "normal", arrowStart: false, arrowEnd: true, ...values });
const ids = flows => Object.fromEntries(Object.entries(flows).map(([key, values]) => [key, values.map(flow => flow.edgeId)]));

test("boundary membership determines incoming and outgoing flows in source order", () => {
  const graph = fixture([
    edge("from-b", "B", "A", { label: "Archived context" }),
    edge("internal", "A", "A2"),
    edge("to-c", "A2", "C", { label: "Account request" }),
    edge("unrelated", "B", "C"),
    edge("from-c", "C", "A"),
    edge("to-b", "A", "B"),
  ]);
  const flows = deriveAreaFlows(graph, "AREA_A");
  assert.deepEqual(ids(flows), { incoming: ["from-b", "from-c"], outgoing: ["to-c", "to-b"], related: [] });
  assert.deepEqual(flows.incoming[0], { edgeId: "from-b", remoteAreaId: "AREA_B", localNodeId: "A", remoteNodeId: "B", label: "Archived context" });
  assert.deepEqual(flows.outgoing[0], { edgeId: "to-c", remoteAreaId: "AREA_C", localNodeId: "A2", remoteNodeId: "C", label: "Account request" });
  assert.equal(flows.incoming[1].label, "Refresh account → Start work");
  assert.equal(flows.outgoing[1].label, "Start work → Read archive");
});

test("a reverse arrow follows its arrowhead instead of the serialized source order", () => {
  const graph = fixture([edge("reverse", "A", "B", { arrowStart: true, arrowEnd: false })]);
  const local = deriveAreaFlows(graph, "AREA_A");
  assert.deepEqual(ids(local), { incoming: ["reverse"], outgoing: [], related: [] });
  assert.equal(local.incoming[0].label, "Read archive → Start work");
  const remote = deriveAreaFlows(graph, "AREA_B");
  assert.deepEqual(ids(remote), { incoming: [], outgoing: ["reverse"], related: [] });
  assert.deepEqual(remote.outgoing[0], { edgeId: "reverse", remoteAreaId: "AREA_A", localNodeId: "B", remoteNodeId: "A", label: "Read archive → Start work" });
});

test("a bidirectional boundary edge appears once in each direction with one preserved identity", () => {
  const graph = fixture([edge("both", "A", "B", { arrowStart: true, arrowEnd: true })]);
  const flows = deriveAreaFlows(graph, "AREA_A");
  assert.deepEqual(ids(flows), { incoming: ["both"], outgoing: ["both"], related: [] });
  assert.equal(flows.incoming[0].label, "Read archive → Start work");
  assert.equal(flows.outgoing[0].label, "Start work → Read archive");
  assert.equal(flows.incoming[0].localNodeId, flows.outgoing[0].localNodeId);
  assert.equal(flows.incoming[0].remoteNodeId, flows.outgoing[0].remoteNodeId);
  assert.notEqual(flows.incoming[0], flows.outgoing[0]);
});

test("undirected edges remain related instead of inventing an inflow or outflow", () => {
  const graph = fixture([
    edge("shared", "B", "A", { arrowEnd: false, label: "Shared archive" }),
    edge("unlabelled", "A", "C", { arrowEnd: false }),
    edge("internal-related", "A", "A2", { arrowEnd: false }),
    edge("internal-both", "A", "A2", { arrowStart: true }),
  ]);
  const flows = deriveAreaFlows(graph, "AREA_A");
  assert.deepEqual(ids(flows), { incoming: [], outgoing: [], related: ["shared", "unlabelled"] });
  assert.deepEqual(flows.related[0], { edgeId: "shared", remoteAreaId: "AREA_B", localNodeId: "A", remoteNodeId: "B", label: "Shared archive" });
  assert.equal(flows.related[1].label, "Start work — Refresh account");
});

test("edge labels become meaningful plain text and retain their full content", () => {
  const graph = fixture([edge("labelled", "A", "B", { label: "  <strong>Account &amp; usage</strong><br />refresh &#x2192; &#65;&nbsp;  " })]);
  assert.equal(deriveAreaFlows(graph, "AREA_A").outgoing[0].label, "Account & usage refresh → A");
});

test("empty labels fall back to node summaries without source references or blank labels", () => {
  const graph = fixture([
    edge("empty", "A", "B", { label: "<br/>\n&nbsp;" }),
    edge("missing-summary", "C", "A", { label: " \t " }),
  ]);
  graph.nodes.A.label = "<b>Start &lt;owner&gt;</b><BR/>Start.swift:10";
  graph.nodes.B.label = "<p>Read archive</p><p>Archive.ts:30</p>";
  graph.nodes.C.label = "<br/> \n";
  const flows = deriveAreaFlows(graph, "AREA_A");
  assert.equal(flows.outgoing[0].label, "Start <owner> → Read archive");
  assert.equal(flows.incoming[0].label, "C → Start <owner>");
  assert.doesNotMatch(JSON.stringify(flows), /\.swift|\.ts|\.py/);
});

test("derivation leaves its graph untouched and isolated or unknown areas have no flows", () => {
  const graph = fixture([edge("labelled", "A", "B", { label: "Request" })]);
  const original = JSON.stringify(graph);
  const flows = deriveAreaFlows(graph, "AREA_A");
  flows.outgoing[0].label = "Changed presentation";
  assert.equal(JSON.stringify(graph), original);
  assert.equal(deriveAreaFlows(graph, "AREA_A").outgoing[0].label, "Request");
  assert.deepEqual(deriveAreaFlows(graph, "AREA_C"), { incoming: [], outgoing: [], related: [] });
  assert.deepEqual(deriveAreaFlows(graph, "UNKNOWN"), { incoming: [], outgoing: [], related: [] });
});
