import type { Box, CodebaseGraph, RenderedArea } from "./graph";

export type SpatialLayout = {
  bounds: Box;
  areas: Record<string, Box>;
  diagrams: Record<string, Box & { scale: number }>;
};

type Region = {
  id: string;
  original: Box;
  x: number;
  y: number;
  anchorX: number;
  anchorY: number;
  width: number;
  height: number;
};

const reference = { width: 2000, height: 650 };
const margin = 24;
const gap = 18;
const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

/** Fit a cached local diagram without changing its region or its aspect ratio. */
export function placeDiagram(region: Box, rendered: Pick<RenderedArea, "width" | "height">): Box & { scale: number } {
  const inset = 12;
  const header = 32;
  const scale = Math.min((region.width - inset * 2) / rendered.width, (region.height - header - inset * 2) / rendered.height);
  const width = rendered.width * scale;
  const height = rendered.height * scale;
  return {
    x: region.x + (region.width - width) / 2,
    y: region.y + header + inset + (region.height - header - inset * 2 - height) / 2,
    width,
    height,
    scale,
  };
}

/**
 * Give the canonical area's center enough room to become a readable map region.
 * This is independent of the camera and expanded area: navigation cannot relayout it.
 * The small relaxation spreads crowded neighbors, rather than assigning grid cells.
 */
export function createSpatialLayout(graph: CodebaseGraph): SpatialLayout {
  const ordered = [...graph.areas].sort((a, b) => a.id.localeCompare(b.id));
  if (!ordered.length) return { bounds: { x: 0, y: 0, ...reference }, areas: {}, diagrams: {} };

  const regions: Region[] = ordered.map(area => {
    const original = graph.layout.areas[area.id];
    if (!original || ![original.x, original.y, original.width, original.height].every(Number.isFinite) || original.width <= 0 || original.height <= 0) {
      throw new Error(`Area ${area.id} has no usable canonical layout.`);
    }
    const aspect = Math.log2(original.width / original.height);
    return {
      id: area.id,
      original,
      x: 0,
      y: 0,
      anchorX: original.x + original.width / 2,
      anchorY: original.y + original.height / 2,
      width: 300 + clamp(aspect * 10, -8, 24),
      height: 146 + clamp(-aspect * 3, -2, 8),
    };
  });
  const minX = Math.min(...regions.map(region => region.anchorX));
  const maxX = Math.max(...regions.map(region => region.anchorX));
  const minY = Math.min(...regions.map(region => region.anchorY));
  const maxY = Math.max(...regions.map(region => region.anchorY));
  for (const region of regions) {
    region.anchorX = maxX === minX ? reference.width / 2 : 170 + (region.anchorX - minX) / (maxX - minX) * (reference.width - 340);
    region.anchorY = maxY === minY ? reference.height / 2 : 90 + (region.anchorY - minY) / (maxY - minY) * (reference.height - 180);
    region.x = region.anchorX;
    region.y = region.anchorY;
  }

  const north = regions.reduce((best, region) => region.anchorY < best.anchorY ? region : best);
  const south = regions.reduce((best, region) => region.anchorY > best.anchorY ? region : best);
  for (let iteration = 0; iteration < 512; iteration++) {
    let separation = 0;
    for (let index = 0; index < regions.length; index++) {
      const first = regions[index];
      for (const second of regions.slice(index + 1)) {
        const overlapX = (first.width + second.width) / 2 + gap - Math.abs(second.x - first.x);
        const overlapY = (first.height + second.height) / 2 + gap - Math.abs(second.y - first.y);
        if (overlapX <= 0 || overlapY <= 0) continue;
        if (overlapX < overlapY * 2) {
          const movement = (overlapX + 0.01) / 2 * Math.sign(second.anchorX - first.anchorX || second.x - first.x || 1);
          first.x -= movement;
          second.x += movement;
          separation = Math.max(separation, Math.abs(movement));
        } else {
          const movement = (overlapY + 0.01) / 2 * Math.sign(second.anchorY - first.anchorY || second.y - first.y || 1);
          first.y -= movement;
          second.y += movement;
          separation = Math.max(separation, Math.abs(movement));
        }
      }
    }
    // Let close neighbors spread sideways without reversing the map's broad
    // north/south order. Near-level canonical centers can remain near-level.
    for (let index = 0; index < regions.length; index++) {
      const first = regions[index];
      for (const second of regions.slice(index + 1)) {
        const direction = Math.sign(second.anchorY - first.anchorY);
        const inversion = 1 - (second.y - first.y) * direction;
        if (Math.abs(second.anchorY - first.anchorY) > 20 && inversion > 0) {
          const movement = inversion / 2 * direction;
          first.y -= movement;
          second.y += movement;
          separation = Math.max(separation, Math.abs(movement));
        }
      }
    }
    // Keep the original northern/southern landmarks at the ends of the map.
    // Their neighbors may need more room, but should not pass those landmarks.
    if (north !== south) {
      north.y = Math.min(north.y, ...regions.filter(region => region !== north).map(region => region.y - 8));
      south.y = Math.max(south.y, ...regions.filter(region => region !== south).map(region => region.y + 8));
    }
    if (iteration < 150) {
      const pull = 0.02 * (1 - iteration / 150);
      for (const region of regions) {
        region.x += (region.anchorX - region.x) * pull;
        region.y += (region.anchorY - region.y) * pull;
      }
    } else if (separation < 0.001) break;
  }

  // Only translate the result; never shrink readable regions to fit the viewport.
  const left = Math.min(...regions.map(region => region.x - region.width / 2)) - margin;
  const top = Math.min(...regions.map(region => region.y - region.height / 2)) - margin;
  const right = Math.max(...regions.map(region => region.x + region.width / 2)) + margin;
  const bottom = Math.max(...regions.map(region => region.y + region.height / 2)) + margin;
  const areas: SpatialLayout["areas"] = {};
  const diagrams: SpatialLayout["diagrams"] = {};
  for (const region of regions) {
    const box = { x: region.x - region.width / 2 - left, y: region.y - region.height / 2 - top, width: region.width, height: region.height };
    areas[region.id] = box;
    diagrams[region.id] = placeDiagram(box, region.original);
  }
  return { bounds: { x: 0, y: 0, width: right - left, height: bottom - top }, areas, diagrams };
}
