"use client";

import { useLayoutEffect, useMemo, useRef, useState } from "react";
import type { KeyboardEvent, MouseEvent, PointerEvent, RefObject, UIEvent } from "react";
import type { CodebaseGraph, Point, RenderedArea, Transform, Viewport } from "../../lib/graph";
import type { SpatialLayout } from "../../lib/spatial-layout";

const PADDING = 32;
const OVERVIEW = "overview";
const CONTROLS = "a,button,input,select,textarea,[role=button],[data-no-pan]";
type SavedPosition = Point & { offset: Point };
type Drag = { pointerId: number; start: Point; scroll: Point };

/** Navigate between fixed overview and full-size diagrams with native scrolling. */
export function useMapNavigation(
  graph: CodebaseGraph | null,
  layout: SpatialLayout | null,
  activeAreaId: string | null,
  rendered: RenderedArea | null,
  viewportRef: RefObject<HTMLDivElement | null>,
  onOverview: () => void,
) {
  const [viewport, setViewport] = useState<Viewport>({ width: 0, height: 0 });
  const [dragging, setDragging] = useState(false);
  const positions = useRef(new Map<string, SavedPosition>());
  const appliedView = useRef<string | null>(null);
  const fixedOverviewScale = useRef<{ layout: SpatialLayout; scale: number } | null>(null);
  const drag = useRef<Drag | null>(null);
  const moved = useRef(false);
  const view = activeAreaId ?? OVERVIEW;
  const ready = !!graph && !!layout && (!activeAreaId || !!rendered);

  const { overviewTransform, overviewSize } = useMemo(() => {
    const bounds = layout?.bounds;
    if (!bounds || !viewport.width || !viewport.height) {
      return { overviewTransform: { x: PADDING, y: PADDING, scale: 1 }, overviewSize: viewport };
    }
    const locked = fixedOverviewScale.current;
    const scale = locked?.layout === layout ? locked.scale : Math.max(
      viewport.width >= 700 ? .5 : 14 / 18,
      Math.min(
        Math.max(1, viewport.width - PADDING * 2) / bounds.width,
        Math.max(1, viewport.height - PADDING * 2) / bounds.height,
        1,
      ),
    );
    const size = {
      width: Math.max(viewport.width, Math.ceil(bounds.width * scale + PADDING * 2)),
      height: Math.max(viewport.height, Math.ceil(bounds.height * scale + PADDING * 2)),
    };
    const transform: Transform = {
      x: (size.width - bounds.width * scale) / 2 - bounds.x * scale,
      y: (size.height - bounds.height * scale) / 2 - bounds.y * scale,
      scale,
    };
    return { overviewTransform: transform, overviewSize: size };
  }, [layout, viewport]);

  const detailOffset: Point = {
    x: Math.max(PADDING, (viewport.width - (rendered?.width ?? 0)) / 2),
    y: Math.max(PADDING, (viewport.height - (rendered?.height ?? 0)) / 2),
  };
  const offset = activeAreaId ? detailOffset : overviewTransform;

  useLayoutEffect(() => {
    const element = viewportRef.current;
    if (!element) return;
    const measure = () => {
      const next = { width: element.clientWidth, height: element.clientHeight };
      setViewport(previous => previous.width === next.width && previous.height === next.height ? previous : next);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [viewportRef]);

  useLayoutEffect(() => {
    positions.current.clear();
    appliedView.current = null;
    fixedOverviewScale.current = null;
  }, [graph, layout]);

  useLayoutEffect(() => {
    drag.current = null;
    moved.current = false;
    setDragging(false);
  }, [view]);

  useLayoutEffect(() => {
    const element = viewportRef.current;
    if (!element || !ready || !viewport.width || !viewport.height) {
      appliedView.current = null;
      return;
    }
    const saved = positions.current.get(view);
    let x = saved ? saved.x + offset.x - saved.offset.x : 0;
    let y = saved ? saved.y + offset.y - saved.offset.y : 0;
    if (!saved && activeAreaId && rendered) {
      const first = Object.values(rendered.nodes).sort((a, b) => a.y - b.y || a.x - b.x)[0];
      if (first) {
        x = offset.x + first.x + first.width / 2 - viewport.width / 2;
        y = offset.y + first.y - PADDING;
      }
    }
    // Set native scroll only after the correct view's content is mounted. A loading
    // placeholder must never replace the saved position with its clamped zeroes.
    element.scrollLeft = x;
    element.scrollTop = y;
    appliedView.current = view;
    positions.current.set(view, {
      x: element.scrollLeft, y: element.scrollTop, offset: { x: offset.x, y: offset.y },
    });
  }, [activeAreaId, graph, layout, offset.x, offset.y, ready, rendered, view, viewport, viewportRef]);

  const onScroll = (event: UIEvent<HTMLDivElement>) => {
    if (!ready || appliedView.current !== view) return;
    const element = event.currentTarget;
    positions.current.set(view, {
      x: element.scrollLeft, y: element.scrollTop, offset: { x: offset.x, y: offset.y },
    });
    // Once the overview is explored, resizing changes its viewport, not its scale.
    if (!activeAreaId && layout && (element.scrollLeft > 0 || element.scrollTop > 0)) {
      fixedOverviewScale.current = { layout, scale: overviewTransform.scale };
    }
  };
  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    moved.current = false;
    if (event.pointerType !== "mouse" || event.button !== 0 || !ready) return;
    if ((event.target as Element).closest(CONTROLS)) return;
    event.currentTarget.focus({ preventScroll: true });
    drag.current = {
      pointerId: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      scroll: { x: event.currentTarget.scrollLeft, y: event.currentTarget.scrollTop },
    };
  };
  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const current = drag.current;
    if (!current || current.pointerId !== event.pointerId) return;
    if ((event.buttons & 1) === 0) {
      drag.current = null;
      setDragging(false);
      return;
    }
    const dx = event.clientX - current.start.x;
    const dy = event.clientY - current.start.y;
    if (!moved.current && Math.hypot(dx, dy) < 5) return;
    moved.current = true;
    setDragging(true);
    event.currentTarget.setPointerCapture(event.pointerId);
    event.preventDefault();
    event.currentTarget.scrollLeft = current.scroll.x - dx;
    event.currentTarget.scrollTop = current.scroll.y - dy;
  };
  const onPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    if (drag.current?.pointerId !== event.pointerId) return;
    drag.current = null;
    setDragging(false);
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
  };
  const onClickCapture = (event: MouseEvent<HTMLDivElement>) => {
    if (!moved.current) return;
    moved.current = false;
    event.preventDefault();
    event.stopPropagation();
  };
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey || event.key !== "Escape" || !activeAreaId) return;
    if ((event.target as Element).closest("input,select,textarea,[data-no-pan]")) return;
    event.preventDefault();
    onOverview();
  };

  return {
    viewport, overviewTransform, overviewSize, detailOffset, dragging,
    handlers: {
      onScroll, onPointerDown, onPointerMove, onPointerUp,
      onPointerCancel: onPointerUp, onLostPointerCapture: onPointerUp,
      onClickCapture, onKeyDown,
    },
  };
}
