import type { CodebaseGraph, MapNode } from "./graph";

export type AreaFlow = {
  edgeId: string;
  remoteAreaId: string;
  localNodeId: string;
  remoteNodeId: string;
  label: string;
};

export type AreaFlows = {
  incoming: AreaFlow[];
  outgoing: AreaFlow[];
  related: AreaFlow[];
};

const entities: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };

function plainText(value: string): string {
  return value.replace(/<br\s*\/?\s*>/gi, "\n").replace(/<\/(?:p|div|li)\s*>/gi, "\n")
    .replace(/<[^>]*>/g, "")
    .replace(/&(#x[\da-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (entity, name: string) => {
      if (!name.startsWith("#")) return entities[name.toLowerCase()];
      const hexadecimal = name[1].toLowerCase() === "x";
      const code = Number.parseInt(name.slice(hexadecimal ? 2 : 1), hexadecimal ? 16 : 10);
      return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : entity;
    });
}

function firstLine(node: MapNode): string {
  return plainText(node.label).split(/\r?\n/).map(line => line.replace(/\s+/g, " ").trim()).find(Boolean) || node.id;
}

/** Derive boundary flows from arrowheads and node membership, retaining source edge order. */
export function deriveAreaFlows(graph: CodebaseGraph, areaId: string): AreaFlows {
  const flows: AreaFlows = { incoming: [], outgoing: [], related: [] };
  for (const edge of graph.edges) {
    const source = graph.nodes[edge.source];
    const target = graph.nodes[edge.target];
    const sourceLocal = source.areaId === areaId;
    const targetLocal = target.areaId === areaId;
    if (sourceLocal === targetLocal) continue;

    const local = sourceLocal ? source : target;
    const remote = sourceLocal ? target : source;
    const entry = { edgeId: edge.id, remoteAreaId: remote.areaId, localNodeId: local.id, remoteNodeId: remote.id };
    const label = plainText(edge.label).replace(/\s+/g, " ").trim();
    const append = (from: MapNode, to: MapNode) => {
      const destination = from.areaId === areaId ? flows.outgoing : flows.incoming;
      destination.push({ ...entry, label: label || `${firstLine(from)} → ${firstLine(to)}` });
    };
    if (edge.arrowEnd) append(source, target);
    if (edge.arrowStart) append(target, source);
    if (!edge.arrowStart && !edge.arrowEnd) {
      flows.related.push({ ...entry, label: label || `${firstLine(source)} — ${firstLine(target)}` });
    }
  }
  return flows;
}
