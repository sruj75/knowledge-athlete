"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { KeyboardEvent, PointerEvent, RefObject } from "react";
import type { CodebaseGraph } from "../../lib/graph";
import { placeDiagram, type SpatialLayout } from "../../lib/spatial-layout";
import { renderArea } from "../../lib/mermaid-runtime";

export type Point = { x: number; y: number };
export type Transform = Point & { scale: number };
export type Viewport = { width: number; height: number };
const INITIAL: Transform = { x: 0, y: 0, scale: 1 };
const MAX_SCALE = 200;
const FOCUS_DURATION = 300;

export function useMapCamera(
  graph: CodebaseGraph | null,
  layout: SpatialLayout | null,
  viewportRef: RefObject<HTMLDivElement | null>,
) {
  const graphRef = useRef(graph);
  graphRef.current = graph;
  const layoutRef = useRef(layout);
  layoutRef.current = layout;
  const [transform, setTransform] = useState(INITIAL);
  const transformRef = useRef(INITIAL);
  const [viewport, setViewport] = useState<Viewport>({ width: 0, height: 0 });
  const viewportSizeRef = useRef(viewport);
  const [activeAreaId, setActiveAreaId] = useState<string | null>(null);
  const [focusError, setFocusError] = useState<string | null>(null);
  const [focusAttempt, setFocusAttempt] = useState(0);
  const activeRef = useRef<string | null>(null);
  const overviewScale = useRef(1);
  const fitted = useRef(true);
  const animationFrame = useRef<number | null>(null);
  const focusVersion = useRef(0);
  const pointers = useRef(new Map<number, Point>());
  const dragStart = useRef<Point | null>(null);
  const moved = useRef(false);
  const [dragging, setDragging] = useState(false);

  const update = useCallback((next: Transform) => {
    transformRef.current = next;
    setTransform(next);
  }, []);

  const cancelAnimation = useCallback(() => {
    focusVersion.current += 1;
    if (animationFrame.current !== null) cancelAnimationFrame(animationFrame.current);
    animationFrame.current = null;
  }, []);

  const chooseArea = useCallback((id: string | null) => {
    if (activeRef.current === id) return;
    activeRef.current = id;
    setActiveAreaId(id);
  }, []);

  const moveTo = useCallback((target: Transform, animate: boolean) => {
    cancelAnimation();
    if (!animate || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      update(target);
      return;
    }
    const start = transformRef.current;
    const size = viewportSizeRef.current;
    const center = { x: size.width / 2, y: size.height / 2 };
    const startWorld = { x: (center.x - start.x) / start.scale, y: (center.y - start.y) / start.scale };
    const targetWorld = { x: (center.x - target.x) / target.scale, y: (center.y - target.y) / target.scale };
    const started = performance.now();
    const tick = (now: number) => {
      const progress = Math.min(1, (now - started) / FOCUS_DURATION);
      const eased = 1 - Math.pow(1 - progress, 3);
      const scale = start.scale * Math.pow(target.scale / start.scale, eased);
      update({ scale,
        x: center.x - (startWorld.x + (targetWorld.x - startWorld.x) * eased) * scale,
        y: center.y - (startWorld.y + (targetWorld.y - startWorld.y) * eased) * scale,
      });
      animationFrame.current = progress < 1 ? requestAnimationFrame(tick) : null;
    };
    animationFrame.current = requestAnimationFrame(tick);
  }, [cancelAnimation, update]);

  const fittedTransform = useCallback(() => {
    const bounds = layoutRef.current?.bounds;
    const size = viewportSizeRef.current;
    if (!bounds || !size.width || !size.height) return null;
    // Titles stay readable in screen space. Smaller screens explore the map by panning.
    const scale = Math.max(size.width >= 700 ? .5 : 14 / 18, Math.min(
      Math.max(1, size.width - 64) / bounds.width,
      Math.max(1, size.height - 64) / bounds.height,
      1,
    ));
    return { scale,
      x: (size.width - bounds.width * scale) / 2 - bounds.x * scale,
      y: (size.height - bounds.height * scale) / 2 - bounds.y * scale,
    };
  }, []);

  const resetOverview = useCallback((animate: boolean) => {
    setFocusError(null);
    const target = fittedTransform();
    if (!target) return;
    overviewScale.current = target.scale;
    chooseArea(null);
    fitted.current = true;
    moveTo(target, animate);
  }, [chooseArea, fittedTransform, moveTo]);
  const overview = useCallback(() => resetOverview(true), [resetOverview]);

  const focusArea = useCallback((id: string) => {
    const graph = graphRef.current;
    const spatial = layoutRef.current;
    const region = spatial?.areas[id];
    if (!graph || !spatial || !region) return;
    setFocusAttempt(value => value + 1);
    setFocusError(null);
    cancelAnimation();
    const request = focusVersion.current;
    fitted.current = false;
    chooseArea(id);
    void renderArea(graph, id).then(rendered => {
      // A late render must never override a newer gesture, resize, or destination.
      if (request !== focusVersion.current || graphRef.current !== graph || layoutRef.current !== spatial || activeRef.current !== id) return;
      const placement = placeDiagram(region, rendered);
      const size = viewportSizeRef.current;
      const first = Object.values(rendered.nodes).sort((a, b) => a.y - b.y || a.x - b.x)[0];
      const scale = Math.min(MAX_SCALE, Math.max(overviewScale.current * 1.4, 12 / (rendered.fontSize * placement.scale)));
      const startX = placement.x + (first ? first.x + first.width / 2 : rendered.width / 2) * placement.scale;
      const startY = placement.y + (first?.y ?? 0) * placement.scale;
      moveTo({ scale, x: size.width / 2 - startX * scale, y: 64 - startY * scale }, true);
    }).catch(() => {
      if (request === focusVersion.current && graphRef.current === graph && layoutRef.current === spatial && activeRef.current === id) setFocusError(id);
    });
  }, [cancelAnimation, chooseArea, moveTo]);

  const areaAt = useCallback((anchor: Point, current: Transform) => {
    const spatial = layoutRef.current;
    if (!spatial) return undefined;
    const point = { x: (anchor.x - current.x) / current.scale, y: (anchor.y - current.y) / current.scale };
    return graphRef.current?.areas.find(area => {
      const box = spatial.areas[area.id];
      return box && point.x >= box.x && point.x <= box.x + box.width && point.y >= box.y && point.y <= box.y + box.height;
    })?.id;
  }, []);

  const zoomAt = useCallback((factor: number, point?: Point) => {
    if (!layoutRef.current || !Number.isFinite(factor) || factor <= 0) return;
    cancelAnimation();
    const current = transformRef.current;
    const size = viewportSizeRef.current;
    const anchor = point ?? { x: size.width / 2, y: size.height / 2 };
    // A resize can preserve a scale below the new overview floor. It must not
    // turn zoom-out into zoom-in or make a small wheel gesture jump to that floor.
    const minimum = Math.min(current.scale, overviewScale.current);
    const scale = Math.max(minimum, Math.min(MAX_SCALE, current.scale * factor));
    const ratio = scale / current.scale;
    fitted.current = false;
    if (scale < overviewScale.current * 1.3) chooseArea(null);
    else if (factor > 1) {
      const id = areaAt(anchor, current);
      if (id) chooseArea(id);
    }
    // Detail visibility follows this scale; it never requests another camera move.
    update({ x: anchor.x - (anchor.x - current.x) * ratio, y: anchor.y - (anchor.y - current.y) * ratio, scale });
  }, [areaAt, cancelAnimation, chooseArea, update]);

  useEffect(() => { resetOverview(false); }, [graph, layout, resetOverview]);
  useEffect(() => cancelAnimation, [cancelAnimation]);

  useEffect(() => {
    const element = viewportRef.current;
    if (!element) return;
    const observer = new ResizeObserver(() => {
      cancelAnimation();
      const previous = viewportSizeRef.current;
      const next = { width: element.clientWidth, height: element.clientHeight };
      viewportSizeRef.current = next;
      setViewport(next);
      if (!previous.width || fitted.current) resetOverview(false);
      else {
        const fit = fittedTransform();
        if (fit) overviewScale.current = fit.scale;
        update({ ...transformRef.current,
          x: transformRef.current.x + (next.width - previous.width) / 2,
          y: transformRef.current.y + (next.height - previous.height) / 2,
        });
      }
    });
    observer.observe(element);
    const wheel = (event: WheelEvent) => {
      if (!layoutRef.current) return;
      event.preventDefault();
      const box = element.getBoundingClientRect();
      const units = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? box.height : 1;
      zoomAt(Math.exp(-event.deltaY * units * .002), { x: event.clientX - box.left, y: event.clientY - box.top });
    };
    element.addEventListener("wheel", wheel, { passive: false });
    return () => { observer.disconnect(); element.removeEventListener("wheel", wheel); };
  }, [cancelAnimation, fittedTransform, resetOverview, update, viewportRef, zoomAt]);

  const position = (event: PointerEvent<HTMLDivElement>) => {
    const box = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  };
  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0 || !layoutRef.current) return;
    const target = event.target as Element;
    if (target.closest("a,input,select,[data-no-pan]")) return;
    cancelAnimation();
    if (!target.closest("button")) event.currentTarget.focus({ preventScroll: true });
    const point = position(event);
    pointers.current.set(event.pointerId, point);
    dragStart.current = point;
    moved.current = pointers.current.size > 1;
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
      update({ ...transformRef.current, x: transformRef.current.x + next.x - previous.x, y: transformRef.current.y + next.y - previous.y });
      return;
    }
    const after = [...pointers.current.values()];
    const distance = Math.hypot(before[1].x - before[0].x, before[1].y - before[0].y);
    if (!distance) return;
    const center = { x: (before[0].x + before[1].x) / 2, y: (before[0].y + before[1].y) / 2 };
    zoomAt(Math.hypot(after[1].x - after[0].x, after[1].y - after[0].y) / distance, center);
    update({ ...transformRef.current,
      x: transformRef.current.x + (after[0].x + after[1].x) / 2 - center.x,
      y: transformRef.current.y + (after[0].y + after[1].y) / 2 - center.y,
    });
  };
  const onPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    pointers.current.delete(event.pointerId);
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    const remaining = [...pointers.current.values()];
    dragStart.current = remaining[0] ?? null;
    setDragging(remaining.length > 0 && moved.current);
  };
  const onClickCapture = (event: React.MouseEvent<HTMLDivElement>) => {
    if (moved.current) { event.preventDefault(); event.stopPropagation(); moved.current = false; }
  };
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.metaKey || event.ctrlKey || event.altKey || !layoutRef.current) return;
    if ((event.target as Element).closest("select,input")) return;
    const step = event.shiftKey ? 160 : 64;
    if (["Escape", "Home", "f", "F"].includes(event.key)) overview();
    else if (["+", "="].includes(event.key)) zoomAt(1.3);
    else if (["-", "_"].includes(event.key)) zoomAt(1 / 1.3);
    else if (event.key.startsWith("Arrow")) {
      cancelAnimation();
      fitted.current = false;
      const current = transformRef.current;
      update({ ...current,
        x: current.x + (event.key === "ArrowLeft" ? step : event.key === "ArrowRight" ? -step : 0),
        y: current.y + (event.key === "ArrowUp" ? step : event.key === "ArrowDown" ? -step : 0),
      });
    } else return;
    event.preventDefault();
  };
  return { transform, viewport, activeAreaId, focusError, focusAttempt, dragging, overviewScale: overviewScale.current, focusArea, overview, zoomAt,
    handlers: { onPointerDown, onPointerMove, onPointerUp, onPointerCancel: onPointerUp,
      onLostPointerCapture: (event: PointerEvent<HTMLDivElement>) => {
        // Touch buttons implicitly capture first. Their transfer to the canvas is not a gesture end.
        if (event.target === event.currentTarget && !event.currentTarget.hasPointerCapture(event.pointerId)) onPointerUp(event);
      }, onClickCapture, onKeyDown } };
}
