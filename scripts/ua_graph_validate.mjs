// Read-only validation of the original graph. Never call upstream validateGraph:
// that API sanitizes/drops invalid records before reporting success.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const [plugin, candidate, scanPath] = process.argv.slice(2);
const fail = message => { throw new Error(message); };
const read = name => JSON.parse(readFileSync(join(candidate, '.ua', name), 'utf8'));
const safePath = value => typeof value === 'string' && value.length > 0 && !value.includes('\\') &&
  !value.includes('\0') && value.split('/').every(part => part && part !== '.' && part !== '..' && part.toLowerCase() !== '.git');
const list = values => [...values].sort().slice(0, 12).join(', ');
const strings = value => Array.isArray(value) && value.every(item => typeof item === 'string');
const count = value => Number.isInteger(value) && value >= 0;
const validFingerprint = value => value && typeof value.hasStructuralAnalysis === 'boolean' && count(value.totalLines) &&
  strings(value.exports) && Array.isArray(value.functions) && value.functions.every(fn => fn &&
    typeof fn.name === 'string' && strings(fn.params) && typeof fn.exported === 'boolean' && count(fn.lineCount) &&
    (fn.owner == null || typeof fn.owner === 'string') && (fn.returnType === undefined || typeof fn.returnType === 'string')) &&
  Array.isArray(value.classes) && value.classes.every(cls => cls && typeof cls.name === 'string' &&
    strings(cls.methods) && strings(cls.properties) && typeof cls.exported === 'boolean' && count(cls.lineCount)) &&
  Array.isArray(value.imports) && value.imports.every(item => item && typeof item.source === 'string' && strings(item.specifiers));
const timestamp = value => typeof value === 'string' && Number.isFinite(Date.parse(value));

try {
  const { KnowledgeGraphSchema } = await import(pathToFileURL(join(plugin, 'packages/core/dist/index.js')).href);
  const graph = read('knowledge-graph.json');
  const fingerprints = read('fingerprints.json');
  const meta = read('meta.json');
  const config = read('config.json');
  const scan = JSON.parse(readFileSync(scanPath, 'utf8'));
  const parsed = KnowledgeGraphSchema.safeParse(graph);
  if (!parsed.success) fail(`Graph schema invalid: ${parsed.error.issues.map(issue => issue.path.join('.') + ': ' + issue.message).slice(0, 8).join('; ')}`);
  if (graph.kind && graph.kind !== 'codebase') fail('Expected a codebase graph');
  if (!graph.nodes.length) fail('Graph has no nodes');
  if (typeof config?.autoUpdate !== 'boolean' || typeof config?.outputLanguage !== 'string' || !config.outputLanguage.trim()) fail('Invalid graph config');
  const baseline = meta?.gitCommitHash;
  if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(baseline) || baseline !== graph.project.gitCommitHash || baseline !== fingerprints?.gitCommitHash) fail('Graph, fingerprints and metadata have inconsistent baseline commits');
  if (meta?.version !== graph.version || fingerprints?.version !== '1.0.0' || !graph.version.trim() ||
      !timestamp(meta?.lastAnalyzedAt) || !timestamp(fingerprints?.generatedAt) ||
      !timestamp(graph.project.analyzedAt)) fail('Invalid analysis metadata');
  if (scan.scriptCompleted !== true || !Array.isArray(scan.files) || !Array.isArray(scan.failures) || scan.failures.length || scan.totalFiles !== scan.files.length) fail('Canonical scan is incomplete');
  const expected = new Set(scan.files.map(file => file.path));
  if (expected.size !== scan.files.length || [...expected].some(path => !safePath(path))) fail('Canonical scan has invalid or duplicate paths');
  if (!fingerprints.files || typeof fingerprints.files !== 'object' || Array.isArray(fingerprints.files)) fail('Invalid fingerprint inventory');
  const saved = new Set(Object.keys(fingerprints.files));
  const missing = [...expected].filter(path => !saved.has(path));
  const removed = [...saved].filter(path => !expected.has(path));
  if (missing.length || removed.length) fail(`Fingerprint inventory differs; new/uncovered (${missing.length}): ${list(missing)}; removed/excluded (${removed.length}): ${list(removed)}`);
  if (!Number.isInteger(meta.analyzedFiles) || meta.analyzedFiles !== expected.size) fail('Metadata analyzedFiles does not match the canonical inventory');
  const changed = [];
  for (const path of expected) {
    const fingerprint = fingerprints.files[path];
    if (!validFingerprint(fingerprint) || fingerprint.filePath !== path || !/^[a-f0-9]{64}$/.test(fingerprint.contentHash)) fail(`Invalid fingerprint for ${path}`);
    // Stock fingerprint.ts hashes Node's UTF-8 decoded string, not Git's blob or raw bytes.
    const hash = createHash('sha256').update(readFileSync(join(candidate, path), 'utf8')).digest('hex');
    if (hash !== fingerprint.contentHash) changed.push(path);
  }
  if (changed.length) fail(`Stale graph: changed analyzed files (${changed.length}): ${list(changed)}. Finish the UA refresh and commit its persistent files.`);
  const ids = new Set();
  const covered = new Set();
  const wholeTypes = new Set(['file', 'config', 'document', 'service', 'pipeline', 'schema', 'resource']);
  for (const node of graph.nodes) {
    if (!node.id.trim() || ids.has(node.id)) fail(`Empty or duplicate node ID: ${node.id}`);
    ids.add(node.id);
    if (node.type === 'file' && node.filePath === undefined) fail(`File node lacks a path: ${node.id}`);
    if (node.filePath !== undefined) {
      if (!safePath(node.filePath) || !expected.has(node.filePath)) fail(`Node has an invalid or out-of-scope path: ${node.id}`);
      // The stock finalizer's hasAnalyzedFileCoverage contract, without normalizing raw input.
      if ((wholeTypes.has(node.type) && node.id === `${node.type}:${node.filePath}`) ||
          (['table', 'endpoint'].includes(node.type) && node.id.startsWith(`${node.type}:${node.filePath}:`))) covered.add(node.filePath);
    }
    if (node.lineRange && (!node.lineRange.every(Number.isInteger) || node.lineRange[0] < 1 || node.lineRange[1] < node.lineRange[0])) fail(`Invalid line range: ${node.id}`);
  }
  const uncovered = [...expected].filter(path => !covered.has(path));
  if (uncovered.length) fail(`Graph lacks whole-file coverage (${uncovered.length}): ${list(uncovered)}`);
  for (const edge of graph.edges) {
    if (!ids.has(edge.source) || !ids.has(edge.target)) fail(`Dangling graph edge: ${edge.source} -> ${edge.target}`);
  }
  const layerIds = new Set();
  for (const layer of graph.layers) {
    if (!layer.id.trim() || layerIds.has(layer.id)) fail(`Empty or duplicate layer ID: ${layer.id}`);
    layerIds.add(layer.id);
  }
  for (const group of [...graph.layers, ...graph.tour]) {
    if (group.nodeIds.some(id => !ids.has(id))) fail('Layer or tour references a missing node');
  }
  console.log(`${expected.size} analyzed files; raw graph and fingerprints valid`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
