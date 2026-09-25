"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { KeyboardEvent, PointerEvent, RefObject } from "react";
import type { MapArea, RenderedArea } from "../../lib/graph";
import { getAreaBox, getDiagramPlacement, getWorldBounds } from "../../lib/map-geometry";

export type Point = { x: number; y: number };
export type Transform = Point & { scale: number };
export type Viewport = { width: number; height: number };
const MIN_OVERVIEW_SCALE = .48;
const INITIAL: Transform = { x: 0, y: 0, scale: 1 };

export function useMapCamera(areas: MapArea[], viewportRef: RefObject<HTMLDivElement | null>) {
  const areasRef = useRef(areas);
  areasRef.current = areas;
  const [transform, setTransform] = useState(INITIAL);
  const transformRef = useRef(INITIAL);
  const [viewport, setViewport] = useState<Viewport>({ width: 0, height: 0 });
  const viewportSizeRef = useRef(viewport);
  const [activeAreaId, setActiveAreaId] = useState<string | null>(null);
  const activeRef = useRef<string | null>(null);
  const overviewScale = useRef(1);
  const pendingFocus = useRef<{ id: string; entry: boolean } | null>(null);
  const fitted = useRef(true);
  const pointers = useRef(new Map<number, Point>());
  const dragStart = useRef<Point | null>(null);
  const moved = useRef(false);
  const [dragging, setDragging] = useState(false);

  const update = useCallback((next: Transform) => {
    transformRef.current = next;
    setTransform(next);
  }, []);

  const chooseArea = useCallback((id: string | null) => {
    activeRef.current = id;
    setActiveAreaId(id);
  }, []);

  const overview = useCallback(() => {
    const size = viewportSizeRef.current;
    if (!areasRef.current.length || !size.width || !size.height) return;
    const bounds = getWorldBounds(areasRef.current.length);
    const scale = Math.max(MIN_OVERVIEW_SCALE, Math.min(
      (size.width - 40) / bounds.width, (size.height - 40) / bounds.height, 1,
    ));
    overviewScale.current = scale;
    pendingFocus.current = null;
    chooseArea(null);
    fitted.current = true;
    // Small screens start at the first area; the grid remains pan-able in both axes.
    update({ scale,
      x: size.width >= bounds.width * scale ? (size.width - bounds.width * scale) / 2 - bounds.x * scale : 20 - bounds.x * scale,
      y: size.height >= bounds.height * scale ? (size.height - bounds.height * scale) / 2 - bounds.y * scale : 20 - bounds.y * scale,
    });
  }, [chooseArea, update]);

  const focusArea = useCallback((id: string) => {
    if (!areasRef.current.some(area => area.id === id)) return;
    pendingFocus.current = { id, entry: false };
    fitted.current = false;
    chooseArea(id);
  }, [chooseArea]);

  const revealArea = useCallback((id: string, rendered: RenderedArea) => {
    if (pendingFocus.current?.id !== id || activeRef.current !== id) return;
    const entryScale = pendingFocus.current.entry ? transformRef.current.scale : 0;
    pendingFocus.current = null;
    const index = areasRef.current.findIndex(area => area.id === id);
    const placement = getDiagramPlacement(getAreaBox(index), rendered);
    const size = viewportSizeRef.current;
    // Enter near the beginning, with readable summaries rather than fitting long flows into tiny text.
    const scale = Math.max(entryScale, overviewScale.current * 2.1, 12 / (rendered.fontSize * placement.scale));
    const first = Object.values(rendered.nodes).sort((a, b) => a.y - b.y || a.x - b.x)[0];
    const startY = first?.y ?? 0;
    update({ scale,
      x: size.width / 2 - (placement.x + (first ? first.x + first.width / 2 : rendered.width / 2) * placement.scale) * scale,
      y: 68 - (placement.y + startY * placement.scale) * scale,
    });
  }, [update]);

  const areaAt = useCallback((anchor: Point, current: Transform) => {
    const point = { x: (anchor.x - current.x) / current.scale, y: (anchor.y - current.y) / current.scale };
    let nearest: MapArea | undefined;
    let distance = Infinity;
    areasRef.current.forEach((area, index) => {
      const box = getAreaBox(index);
      const dx = Math.max(box.x - point.x, 0, point.x - box.x - box.width);
      const dy = Math.max(box.y - point.y, 0, point.y - box.y - box.height);
      const next = dx * dx + dy * dy;
      if (next < distance) { nearest = area; distance = next; }
    });
    return nearest?.id;
  }, []);

  const zoomAt = useCallback((factor: number, point?: Point) => {
    if (!areasRef.current.length) return;
    if (!pendingFocus.current?.entry || factor < 1) pendingFocus.current = null;
    const current = transformRef.current;
    const size = viewportSizeRef.current;
    const anchor = point ?? { x: size.width / 2, y: size.height / 2 };
    const scale = Math.max(overviewScale.current, Math.min(200, current.scale * factor));
    const ratio = scale / current.scale;
    fitted.current = false;
    if (activeRef.current && scale < overviewScale.current * 1.5) {
      chooseArea(null);
      pendingFocus.current = null;
    } else if (!activeRef.current && scale > overviewScale.current * 2) {
      const id = areaAt(anchor, current);
      if (id) {
        pendingFocus.current = { id, entry: true };
        chooseArea(id);
      }
    }
    update({ x: anchor.x - (anchor.x - current.x) * ratio, y: anchor.y - (anchor.y - current.y) * ratio, scale });
  }, [areaAt, chooseArea, update]);

  useEffect(() => { overview(); }, [areas, overview]);

  useEffect(() => {
    const element = viewportRef.current;
    if (!element) return;
    const observer = new ResizeObserver(() => {
      const previous = viewportSizeRef.current;
      const next = { width: element.clientWidth, height: element.clientHeight };
      viewportSizeRef.current = next;
      setViewport(next);
      if (!previous.width || fitted.current) overview();
      else update({ ...transformRef.current,
        x: transformRef.current.x + (next.width - previous.width) / 2,
        y: transformRef.current.y + (next.height - previous.height) / 2,
      });
    });
    observer.observe(element);
    const wheel = (event: WheelEvent) => {
      if (!areasRef.current.length) return;
      event.preventDefault();
      const box = element.getBoundingClientRect();
      const units = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? box.height : 1;
      zoomAt(Math.exp(-event.deltaY * units * .002), { x: event.clientX - box.left, y: event.clientY - box.top });
    };
    element.addEventListener("wheel", wheel, { passive: false });
    return () => { observer.disconnect(); element.removeEventListener("wheel", wheel); };
  }, [overview, update, viewportRef, zoomAt]);

  const position = (event: PointerEvent<HTMLDivElement>) => {
    const box = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  };
  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0 || !areasRef.current.length) return;
    const target = event.target as Element;
    if (target.closest("a,input,select,[data-no-pan]")) return;
    if (!target.closest("button")) event.currentTarget.focus({ preventScroll: true });
    const point = position(event);
    pointers.current.set(event.pointerId, point);
    dragStart.current = point;
    moved.current = false;
    if (pointers.current.size > 1) moved.current = true;
  };
  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const previous = pointers.current.get(event.pointerId);
    if (!previous) return;
    const before = [...pointers.current.values()];
    const next = position(event);
    pointers.current.set(event.pointerId, next);
    if (!moved.current && dragStart.current && Math.hypot(next.x - dragStart.current.x, next.y - dragStart.current.y) < 5) return;
    moved.current = true;
    fitted.current = false;
    setDragging(true);
    event.currentTarget.setPointerCapture(event.pointerId);
    event.preventDefault();
    if (before.length === 1) {
      pendingFocus.current = null;
      update({ ...transformRef.current, x: transformRef.current.x + next.x - previous.x, y: transformRef.current.y + next.y - previous.y });
      return;
    }
    const after = [...pointers.current.values()];
    const distance = Math.hypot(before[1].x - before[0].x, before[1].y - before[0].y);
    if (!distance) return;
    const center = { x: (before[0].x + before[1].x) / 2, y: (before[0].y + before[1].y) / 2 };
    zoomAt(Math.hypot(after[1].x - after[0].x, after[1].y - after[0].y) / distance, center);
    update({ ...transformRef.current, x: transformRef.current.x + (after[0].x + after[1].x) / 2 - center.x, y: transformRef.current.y + (after[0].y + after[1].y) / 2 - center.y });
  };
  const onPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    pointers.current.delete(event.pointerId);
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    setDragging(pointers.current.size > 0 && moved.current);
  };
  const onClickCapture = (event: React.MouseEvent<HTMLDivElement>) => {
    if (moved.current) { event.preventDefault(); event.stopPropagation(); moved.current = false; }
  };
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.metaKey || event.ctrlKey || event.altKey || !areasRef.current.length) return;
    if ((event.target as Element).closest("select,input")) return;
    const current = transformRef.current;
    const step = event.shiftKey ? 160 : 64;
    if (["Escape", "Home", "f", "F"].includes(event.key)) overview();
    else if (["+", "="].includes(event.key)) zoomAt(1.3);
    else if (["-", "_"].includes(event.key)) zoomAt(1 / 1.3);
    else if (event.key.startsWith("Arrow")) {
      pendingFocus.current = null;
      fitted.current = false;
      update({ ...current, x: current.x + (event.key === "ArrowLeft" ? step : event.key === "ArrowRight" ? -step : 0),
        y: current.y + (event.key === "ArrowUp" ? step : event.key === "ArrowDown" ? -step : 0) });
    } else return;
    event.preventDefault();
  };
  return { transform, viewport, activeAreaId, dragging, overviewScale: overviewScale.current, focusArea, revealArea, overview, zoomAt,
    handlers: { onPointerDown, onPointerMove, onPointerUp, onPointerCancel: onPointerUp,
      onLostPointerCapture: (event: PointerEvent<HTMLDivElement>) => {
        // Touch buttons implicitly capture first. Their transfer to the canvas is not a gesture end.
        if (event.target === event.currentTarget && !event.currentTarget.hasPointerCapture(event.pointerId)) onPointerUp(event);
      }, onClickCapture, onKeyDown } };
}
