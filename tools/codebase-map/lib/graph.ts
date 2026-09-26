export type Box = { x: number; y: number; width: number; height: number };
export type Point = { x: number; y: number };
export type Transform = Point & { scale: number };
export type Viewport = { width: number; height: number };

export type GraphLayout = {
  bounds: Box;
  areas: Record<string, Box>;
};

export type MapArea = {
  id: string;
  number: string;
  title: string;
  platform: string;
  fullTitle: string;
  nodeIds: string[];
};

export type MapNode = {
  id: string;
  areaId: string;
  label: string;
  shape: string;
  classes: string[];
};

export type MapEdge = {
  id: string;
  source: string;
  target: string;
  label: string;
  stroke: "normal" | "dotted" | "thick";
  arrowStart: boolean;
  arrowEnd: boolean;
};

export type CodebaseGraph = {
  areas: MapArea[];
  nodes: Record<string, MapNode>;
  edges: MapEdge[];
  layout: GraphLayout;
};

export type RenderedArea = {
  svg: string;
  width: number;
  height: number;
  nodes: Record<string, Box>;
  fontSize: number;
};
