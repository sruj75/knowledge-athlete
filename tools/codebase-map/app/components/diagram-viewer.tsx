"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { CSSProperties, KeyboardEvent, PointerEvent, ReactNode } from "react";

type DiagramViewerProps = {
  source: string;
  commit: string | null;
  sourceUrl: string | null;
};

type Point = { x: number; y: number };
type Transform = Point & { scale: number };
type Dimensions = { width: number; height: number };
type RenderStatus = "loading" | "ready" | "error";

const INITIAL_TRANSFORM: Transform = { x: 0, y: 0, scale: 1 };
const MAX_SCALE = 4;
let nextRenderId = 0;
let mermaidPromise: Promise<typeof import("mermaid")["default"]> | undefined;

function loadMermaid() {
  mermaidPromise ??= import("mermaid")
    .then(({ default: mermaid }) => {
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        suppressErrorRendering: true,
        layout: "elk",
        maxTextSize: 200_000,
        maxEdges: 2_000,
        theme: "base",
        fontFamily: 'Arial, Helvetica, sans-serif',
        themeVariables: {
          primaryColor: "#ffffff",
          primaryTextColor: "#242a30",
          primaryBorderColor: "#aeb7be",
          lineColor: "#8a949e",
          secondaryColor: "#f5f7f8",
          tertiaryColor: "#fafbfc",
          clusterBkg: "#fafbfc",
          clusterBorder: "#dce1e5",
          edgeLabelBackground: "#ffffff",
          fontSize: "14px",
        },
        flowchart: {
          htmlLabels: true,
          useMaxWidth: false,
          curve: "basis",
          nodeSpacing: 44,
          rankSpacing: 64,
        },
      });
      return mermaid;
    })
    .catch((error: unknown) => {
      mermaidPromise = undefined;
      throw error;
    });

  return mermaidPromise;
}

function Icon({ children }: { children: ReactNode }) {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

function SourceIcon() {
  return (
    <Icon>
      <path d="m8 7-5 5 5 5m8-10 5 5-5 5m-3-13-2 16" />
    </Icon>
  );
}

export function DiagramViewer({ source, commit, sourceUrl }: DiagramViewerProps) {
  const shellRef = useRef<HTMLDivElement>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const dimensionsRef = useRef<Dimensions | null>(null);
  const transformRef = useRef(INITIAL_TRANSFORM);
  const pointersRef = useRef(new Map<number, Point>());
  const [transform, setTransform] = useState(INITIAL_TRANSFORM);
  const [status, setStatus] = useState<RenderStatus>("loading");
  const [attempt, setAttempt] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [supportsFullscreen, setSupportsFullscreen] = useState(false);
  const [notice, setNotice] = useState("");

  const updateTransform = useCallback((next: Transform) => {
    transformRef.current = next;
    setTransform(next);
  }, []);

  const fitDiagram = useCallback(() => {
    const viewport = viewportRef.current;
    const dimensions = dimensionsRef.current;
    if (!viewport || !dimensions) return;

    const width = viewport.clientWidth;
    const height = viewport.clientHeight;
    if (!width || !height) return;
    const padding = width < 600 ? 24 : 64;
    const scale = Math.min(
      Math.max(1, width - padding * 2) / dimensions.width,
      Math.max(1, height - padding * 2) / dimensions.height,
      1,
    );
    updateTransform({
      x: (width - dimensions.width * scale) / 2,
      y: (height - dimensions.height * scale) / 2,
      scale,
    });
  }, [updateTransform]);

  const clampScale = useCallback((scale: number) => {
    const viewport = viewportRef.current;
    const dimensions = dimensionsRef.current;
    if (!viewport || !dimensions) return scale;
    const fitScale = Math.min(
      viewport.clientWidth / dimensions.width,
      viewport.clientHeight / dimensions.height,
      1,
    );
    return Math.min(MAX_SCALE, Math.max(fitScale / 8, scale));
  }, []);

  const zoomAt = useCallback(
    (factor: number, point?: Point) => {
      const viewport = viewportRef.current;
      if (!viewport || !dimensionsRef.current) return;
      const anchor = point ?? {
        x: viewport.clientWidth / 2,
        y: viewport.clientHeight / 2,
      };
      const current = transformRef.current;
      const scale = clampScale(current.scale * factor);
      const ratio = scale / current.scale;
      updateTransform({
        x: anchor.x - (anchor.x - current.x) * ratio,
        y: anchor.y - (anchor.y - current.y) * ratio,
        scale,
      });
    },
    [clampScale, updateTransform],
  );

  useEffect(() => {
    let cancelled = false;
    const content = contentRef.current;
    const staging = document.createElement("div");
    const id = `intentive-map-${++nextRenderId}`;
    staging.setAttribute("aria-hidden", "true");
    staging.style.cssText =
      "position:absolute;left:-100000px;top:0;width:1600px;visibility:hidden;pointer-events:none;";

    dimensionsRef.current = null;
    pointersRef.current.clear();
    setDragging(false);
    setStatus("loading");
    content?.replaceChildren();

    async function render() {
      try {
        const mermaid = await loadMermaid();
        if (cancelled) return;
        document.body.append(staging);
        const { svg } = await mermaid.render(id, source, staging);
        if (cancelled || !content) return;

        content.innerHTML = svg;
        const diagram = content.querySelector("svg");
        if (!diagram) throw new Error("No diagram returned");
        const viewBox = diagram.viewBox.baseVal;
        if (
          !Number.isFinite(viewBox.width) ||
          !Number.isFinite(viewBox.height) ||
          viewBox.width <= 0 ||
          viewBox.height <= 0
        ) {
          throw new Error("Invalid diagram dimensions");
        }
        dimensionsRef.current = {
          width: viewBox.width,
          height: viewBox.height,
        };
        diagram.setAttribute("width", String(viewBox.width));
        diagram.setAttribute("height", String(viewBox.height));
        diagram.setAttribute("role", "img");
        diagram.setAttribute("aria-label", "Intentive codebase architecture diagram");
        diagram.style.maxWidth = "none";
        diagram.style.width = `${viewBox.width}px`;
        diagram.style.height = `${viewBox.height}px`;
        fitDiagram();
        setStatus("ready");
      } catch {
        if (!cancelled) {
          content?.replaceChildren();
          dimensionsRef.current = null;
          setStatus("error");
        }
      } finally {
        staging.remove();
      }
    }

    void render();
    return () => {
      cancelled = true;
      // An in-flight Mermaid render owns its staging element until it settles.
      // Removing it early would interrupt text measurement during remounts.
    };
  }, [source, attempt, fitDiagram]);

  useEffect(() => {
    const viewport = viewportRef.current;
    if (!viewport) return;
    let frame = 0;
    const observer = new ResizeObserver(() => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(fitDiagram);
    });
    observer.observe(viewport);

    function handleWheel(event: WheelEvent) {
      if (!viewport || !dimensionsRef.current) return;
      event.preventDefault();
      const bounds = viewport.getBoundingClientRect();
      const units = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? bounds.height : 1;
      zoomAt(Math.exp(-event.deltaY * units * 0.002), {
        x: event.clientX - bounds.left,
        y: event.clientY - bounds.top,
      });
    }

    viewport.addEventListener("wheel", handleWheel, { passive: false });
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
      viewport.removeEventListener("wheel", handleWheel);
    };
  }, [fitDiagram, zoomAt]);

  useEffect(() => {
    setSupportsFullscreen(Boolean(document.fullscreenEnabled));
    const syncFullscreen = () => {
      setFullscreen(document.fullscreenElement === shellRef.current);
    };
    document.addEventListener("fullscreenchange", syncFullscreen);
    return () => document.removeEventListener("fullscreenchange", syncFullscreen);
  }, []);

  const pointerPosition = (event: PointerEvent<HTMLDivElement>): Point => {
    const bounds = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
  };

  function handlePointerDown(event: PointerEvent<HTMLDivElement>) {
    if (status !== "ready" || event.button !== 0) return;
    event.preventDefault();
    event.currentTarget.focus({ preventScroll: true });
    event.currentTarget.setPointerCapture(event.pointerId);
    pointersRef.current.set(event.pointerId, pointerPosition(event));
    setDragging(true);
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>) {
    const pointers = pointersRef.current;
    const previous = pointers.get(event.pointerId);
    if (!previous) return;
    const before = [...pointers.values()];
    const point = pointerPosition(event);
    pointers.set(event.pointerId, point);
    const current = transformRef.current;

    if (pointers.size === 1) {
      updateTransform({
        ...current,
        x: current.x + point.x - previous.x,
        y: current.y + point.y - previous.y,
      });
      return;
    }

    const after = [...pointers.values()];
    const oldDistance = Math.hypot(before[1].x - before[0].x, before[1].y - before[0].y);
    const newDistance = Math.hypot(after[1].x - after[0].x, after[1].y - after[0].y);
    if (oldDistance === 0) return;
    const oldCenter = { x: (before[0].x + before[1].x) / 2, y: (before[0].y + before[1].y) / 2 };
    const newCenter = { x: (after[0].x + after[1].x) / 2, y: (after[0].y + after[1].y) / 2 };
    const scale = clampScale(current.scale * (newDistance / oldDistance));
    const ratio = scale / current.scale;
    updateTransform({
      x: newCenter.x - (oldCenter.x - current.x) * ratio,
      y: newCenter.y - (oldCenter.y - current.y) * ratio,
      scale,
    });
  }

  function endPointer(event: PointerEvent<HTMLDivElement>) {
    pointersRef.current.delete(event.pointerId);
    setDragging(pointersRef.current.size > 0);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (status !== "ready" || event.metaKey || event.ctrlKey || event.altKey) return;
    const current = transformRef.current;
    const distance = event.shiftKey ? 160 : 64;
    switch (event.key) {
      case "+":
      case "=":
        zoomAt(1.3);
        break;
      case "-":
      case "_":
        zoomAt(1 / 1.3);
        break;
      case "f":
      case "F":
      case "Home":
        fitDiagram();
        break;
      case "ArrowLeft":
        updateTransform({ ...current, x: current.x + distance });
        break;
      case "ArrowRight":
        updateTransform({ ...current, x: current.x - distance });
        break;
      case "ArrowUp":
        updateTransform({ ...current, y: current.y + distance });
        break;
      case "ArrowDown":
        updateTransform({ ...current, y: current.y - distance });
        break;
      default:
        return;
    }
    event.preventDefault();
  }

  async function toggleFullscreen() {
    setNotice("");
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await shellRef.current?.requestFullscreen();
    } catch {
      setNotice("Fullscreen is unavailable in this browser.");
    }
  }

  const disabled = status !== "ready";
  const percent = transform.scale * 100;
  const zoomLabel = `${percent < 1 ? percent.toFixed(1) : Math.round(percent)}%`;

  return (
    <div className="map-shell" ref={shellRef}>
      <header className="map-header">
        <div className="map-brand" aria-label="Intentive">
          <svg className="brand-mark" width="30" height="30" viewBox="0 0 30 30" fill="none" aria-hidden="true">
            <path d="M8 8h14M8 8v14m0 0h14M22 8v14M8 8l14 14" stroke="currentColor" strokeWidth="1.5" />
            <rect x="4.5" y="4.5" width="7" height="7" rx="2" fill="currentColor" />
            <rect x="18.5" y="4.5" width="7" height="7" rx="2" fill="currentColor" />
            <rect x="4.5" y="18.5" width="7" height="7" rx="2" fill="currentColor" />
            <rect x="18.5" y="18.5" width="7" height="7" rx="2" fill="currentColor" />
          </svg>
          <span>Intentive</span>
        </div>
        <span className="header-divider" aria-hidden="true" />
        <div className="map-title">
          <h1>Codebase map</h1>
          <span className="map-subtitle">The system, connected.</span>
        </div>
        {sourceUrl && (
          <a className="source-link" href={sourceUrl} aria-label="View source" target="_blank" rel="noreferrer">
            <SourceIcon />
            <span>View source</span>
            <span className="external-arrow" aria-hidden="true">↗</span>
          </a>
        )}
      </header>

      <main className="map-main">
        <div className="canvas-label" aria-hidden="true">
          <span className="canvas-label-line" />
          SYSTEM OVERVIEW
        </div>
        <div
          className={`diagram-viewport${dragging ? " is-dragging" : ""}`}
          data-testid="diagram-viewport"
          ref={viewportRef}
          tabIndex={0}
          role="region"
          aria-label="Interactive codebase map"
          aria-describedby="canvas-instructions"
          aria-busy={status === "loading"}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={endPointer}
          onPointerCancel={endPointer}
          onLostPointerCapture={endPointer}
          onKeyDown={handleKeyDown}
        >
          <div
            className="diagram-content"
            data-testid="diagram-content"
            data-scale={transform.scale}
            data-x={transform.x}
            data-y={transform.y}
            ref={contentRef}
            style={{
              transform: `translate(${transform.x}px, ${transform.y}px) scale(${transform.scale})`,
              visibility: status === "ready" ? "visible" : "hidden",
              "--diagram-stroke-scale": 1 / transform.scale,
            } as CSSProperties}
          />
        </div>

        {status === "loading" && (
          <div className="canvas-state" role="status" data-testid="diagram-loading">
            <div className="loading-orbit" aria-hidden="true"><span /><span /><span /></div>
            <h2>Drawing the codebase</h2>
            <p>Bringing every connection into view.</p>
          </div>
        )}

        {status === "error" && (
          <div className="canvas-state" role="alert" data-testid="diagram-error">
            <div className="error-icon"><SourceIcon /></div>
            <h2>The map couldn’t be drawn</h2>
            <p>Try again, or check the diagram source for errors.</p>
            <button className="retry-button" type="button" onClick={() => setAttempt((value) => value + 1)}>
              Try again
            </button>
          </div>
        )}

        <div className="canvas-toolbar" role="group" aria-label="Diagram controls">
          <button className="tool-button" type="button" aria-label="Zoom out" title="Zoom out (−)" disabled={disabled} onClick={() => zoomAt(1 / 1.3)}>
            <Icon><path d="M5 12h14" /></Icon>
          </button>
          <button
            className="zoom-value"
            type="button"
            aria-label={`Zoom to 100%, current zoom ${zoomLabel}`}
            title="Zoom to 100%"
            disabled={disabled}
            onClick={() => zoomAt(1 / transformRef.current.scale)}
          >
            {status === "ready" ? zoomLabel : "—"}
          </button>
          <button className="tool-button" type="button" aria-label="Zoom in" title="Zoom in (+)" disabled={disabled} onClick={() => zoomAt(1.3)}>
            <Icon><path d="M5 12h14M12 5v14" /></Icon>
          </button>
          <span className="toolbar-divider" aria-hidden="true" />
          <button className="tool-button fit-button" type="button" aria-label="Fit diagram" title="Fit diagram (F)" disabled={disabled} onClick={fitDiagram}>
            <Icon><path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5" /><rect x="8" y="8" width="8" height="8" rx="1" /></Icon>
            <span>Fit</span>
          </button>
          {supportsFullscreen && (
            <>
              <span className="toolbar-divider" aria-hidden="true" />
              <button className="tool-button" type="button" aria-label={fullscreen ? "Exit fullscreen" : "Enter fullscreen"} title={fullscreen ? "Exit fullscreen" : "Enter fullscreen"} onClick={() => void toggleFullscreen()}>
                <Icon><path d={fullscreen ? "M3 8h5V3m8 0v5h5M8 21v-5H3m18 0h-5v5" : "M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"} /></Icon>
              </button>
            </>
          )}
        </div>
        <p className="canvas-hint" id="canvas-instructions">
          Scroll to zoom <span aria-hidden="true">·</span> Drag to pan
          <span className="visually-hidden">. Use arrow keys to pan, plus and minus to zoom, and F to fit the diagram.</span>
        </p>
        {notice && <p className="canvas-notice" role="status">{notice}</p>}
      </main>

      <footer className="map-footer">
        <div className="version-info">
          <span className="version-dot" aria-hidden="true" />
          {commit ? (
            <>
              <span>Built from</span>
              {sourceUrl ? (
                <a href={sourceUrl} className="commit-link" data-testid="commit-link" target="_blank" rel="noreferrer" title={`View diagram at commit ${commit}`}>
                  {commit.slice(0, 7)} <span aria-hidden="true">↗</span>
                </a>
              ) : <code>{commit.slice(0, 7)}</code>}
            </>
          ) : <span>Local build · commit unavailable</span>}
        </div>
        <span className="footer-caption">One codebase. The whole picture.</span>
      </footer>
    </div>
  );
}
