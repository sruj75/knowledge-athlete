import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { diagramPath, loadDiagram } from "../lib/diagram-source.mjs";

function fixture(t, source = "flowchart TD\nA --> B") {
  const root = mkdtempSync(path.join(os.tmpdir(), "intentive-map-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(path.join(root, "docs/architecture"), { recursive: true });
  writeFileSync(path.join(root, diagramPath), source);
  return { appDirectory: path.join(root, "tools/codebase-map"), environment: {}, git: () => { throw new Error("No Git"); } };
}

test("loads the canonical file and pins source links to the deployment commit", (t) => {
  const options = fixture(t);
  const commit = "a".repeat(40);
  const first = loadDiagram({ ...options, environment: { VERCEL: "1", VERCEL_GIT_COMMIT_SHA: commit, GITHUB_SHA: "b".repeat(40) } });
  assert.equal(first.commit, commit);
  assert.equal(first.sourceUrl, `https://github.com/sruj75/knowledge-athlete/blob/${commit}/${diagramPath}`);
  writeFileSync(path.resolve(options.appDirectory, "../..", diagramPath), "flowchart TD\nCode --> UpdatedMap");
  assert.match(loadDiagram(options).source, /UpdatedMap/);
});

test("missing, empty and oversized canonical diagrams fail instead of using stale copies", (t) => {
  const options = fixture(t, " ");
  assert.throws(() => loadDiagram(options), /empty/);
  const file = path.resolve(options.appDirectory, "../..", diagramPath);
  writeFileSync(file, "x".repeat(200_001));
  assert.throws(() => loadDiagram(options), /limit/);
  rmSync(file);
  assert.throws(() => loadDiagram(options), /ENOENT/);
});

test("dirty local work is not attributed to an unchanged GitHub commit", (t) => {
  const options = fixture(t);
  assert.equal(loadDiagram({ ...options, git: () => " M docs/architecture/intentive-codeflow.mmd" }).commit, null);
  assert.equal(loadDiagram(options).sourceUrl, null);
});

test("clean local and CI builds identify their source; hosted builds require valid metadata", (t) => {
  const options = fixture(t);
  const commit = "c".repeat(40);
  assert.equal(loadDiagram({ ...options, git: args => args[0] === "status" ? "" : commit }).commit, commit);
  assert.equal(loadDiagram({ ...options, environment: { GITHUB_SHA: commit } }).commit, commit);
  assert.throws(() => loadDiagram({ ...options, environment: { VERCEL: "1" } }), /require/);
  assert.throws(() => loadDiagram({ ...options, environment: { VERCEL_GIT_COMMIT_SHA: "main" } }), /full Git SHA/);
});
