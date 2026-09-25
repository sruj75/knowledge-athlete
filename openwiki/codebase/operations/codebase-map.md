---
type: Codebase guide
title: Codebase map viewer
description: Follow the canonical Mermaid file into a continuous spatial map with cached local flows, exact source provenance, and browser acceptance checks.
tags: [intentive, codebase, development, diagrams]
resource: repo://tools/codebase-map
verified:
  - by: openwiki/0.5.2
    at: 2026-09-25T17:08:48.248Z
sources:
  - id: openwiki-source-3b73c81eefcd909208670ce0
    resource: repo://.github/checks-manifest.yaml
  - id: openwiki-source-16d213dfcc8beae17f8096fe
    resource: repo://.github/scripts/prepare_codebase_map_check.py
  - id: openwiki-source-898a1f4e66854529123c0957
    resource: repo://tools/codebase-map/app/components/diagram-viewer.tsx
  - id: openwiki-source-c12807270fd9a39fb19a6dba
    resource: repo://tools/codebase-map/app/components/map-areas.tsx
  - id: openwiki-source-1892ff9017909640ba033da6
    resource: repo://tools/codebase-map/app/components/map-chrome.tsx
  - id: openwiki-source-ecd9009c9d912324e4bb30e4
    resource: repo://tools/codebase-map/app/components/map-connections.tsx
  - id: openwiki-source-cf62d61de08902f4bae41c4b
    resource: repo://tools/codebase-map/app/components/use-map-camera.ts
  - id: openwiki-source-c4a16291c647622764e26cc3
    resource: repo://tools/codebase-map/app/globals.css
  - id: openwiki-source-8f88765748afaa418d7fe532
    resource: repo://tools/codebase-map/app/page.tsx
  - id: openwiki-source-cb37abc91bb20553b8ef91a1
    resource: repo://tools/codebase-map/lib/area-flows.ts
  - id: openwiki-source-06044ee38485672b205128e8
    resource: repo://tools/codebase-map/lib/diagram-source.mjs
  - id: openwiki-source-173442aaa3e3f9cbea8df65b
    resource: repo://tools/codebase-map/lib/mermaid-runtime.ts
  - id: openwiki-source-8bbeb014599a36e4dfa9ba9e
    resource: repo://tools/codebase-map/lib/spatial-layout.ts
  - id: openwiki-source-3db6130123d0c0614cc19cb5
    resource: repo://tools/codebase-map/next.config.ts
  - id: openwiki-source-cadbf0c250f5afb51126591d
    resource: repo://tools/codebase-map/package.json
  - id: openwiki-source-74eca9dc530951021748ada2
    resource: repo://tools/codebase-map/tests/area-flows.test.mjs
  - id: openwiki-source-fa2531a1c23faf0486307e94
    resource: repo://tools/codebase-map/tests/browser/viewer.spec.ts
  - id: openwiki-source-add0ec364ed6744f53f1bc54
    resource: repo://tools/codebase-map/tests/spatial-layout.test.mjs
generated: { by: "codex", at: "2026-09-25T17:08:48.248Z" }
---
# Codebase map viewer

The viewer is a public, read-only architecture browser. It shows subsystem regions
and reveals their internal flows as the camera moves closer. It does not host
owner-local product data or generate architecture from source code.

## From repository to browser

`app/page.tsx` calls `loadDiagram` during Next.js static generation. The loader
reads `docs/architecture/intentive-codeflow.mmd` relative to the repository root;
there is no independently maintained copy or runtime GitHub request. Missing,
empty and over-200,000-character input fails the build.

The loader associates the map with `VERCEL_GIT_COMMIT_SHA`, then `GITHUB_SHA`, or
Git HEAD for a clean local checkout. Hosted builds require a full commit SHA.
Edited local checkouts have no immutable source link. The header and footer link
to the exact Mermaid file at the identified GitHub commit, rather than moving main.

## Geographic overview and local flows

The browser retains the `DiagramViewer` source/commit/source-URL contract.
`lib/mermaid-runtime.ts` isolates the pinned Mermaid 12 parser and copies areas,
node membership, labels, shapes, classes, styles and directed edges before
another Mermaid operation can mutate the parser database. Rendering uses strict
security, a 200,000-character limit and a 2,000-edge limit. Mermaid operations
share a serial queue. Unsupported or incomplete graph structures fail explicitly.

A full Mermaid ELK render supplies the original subsystem geography. The pure
`lib/spatial-layout.ts` projection enlarges subsystem regions and separates
crowded neighbors while retaining broad geographic order. Region coordinates
remain fixed during navigation; no numbered grid is maintained. Overview titles
stay at least 14 screen pixels, and smaller screens pan across the map.

`map-areas.tsx` requests local detail for visible regions and explicit destinations.
Each internal flow is generated from the copied model's nodes, internal edges,
labels, shapes and styles, then rendered with Mermaid ELK. This prevents long
cross-subsystem routes from stretching its internal layout. The renderer caches
SVG and measured node geometry by graph and area, including in-flight promises.
Rejected cache entries are removed for retry. Revisiting an area, zooming and
panning reuse its cached geometry without invoking Mermaid again.

Local SVGs fit uniformly inside their fixed regions. Node titles fade into view
as their effective font size grows; secondary source lines become visible at
14 pixels. Hidden lines retain their layout space, so nodes and routes do not
move when references appear. More than one visible subsystem can reveal detail,
including when the user pans across the map without selecting another area.

## Subsystem inflow and outflow

Directly below the active subsystem title, `map-chrome.tsx` displays Inflow and
Outflow lists with the canonical data/event labels and clickable source or
destination subsystems. The reserved panel height keeps the canvas dimensions
stable when selection changes. Lists scroll independently, reset for a new area,
and move keyboard focus to the destination title after following a flow. Escape
returns to Overview and keeps focus inside the viewer.

`lib/area-flows.ts` derives these lists from node membership and actual arrowheads.
Internal edges are excluded, reverse arrows invert the direction, and bidirectional
edges appear on both sides. Unlabelled edges use the first endpoint label lines;
undirected relationships are counted separately without inventing a direction.
These are the map's recorded data and control exchanges, not inferred payload
schemas, measured throughput, or a stock-and-flow simulation. Empty lists mean no
flows are recorded in this map, not proof that the subsystem has no external inputs.

## Camera and navigation

`use-map-camera.ts` owns the affine camera and selected area. Wheel and pinch
zoom preserve the world point under the gesture anchor; loading or revealing a
local flow does not request a camera move. Clicking a subsystem or using Jump to
area waits for its local layout, then moves to its first nodes at a readable
scale. User input, another destination, or resizing cancels pending focus and
animation, preventing a late render from moving the camera after a gesture.

Resize preserves the world center and scale while exploring, or refits an
untouched overview. If a preserved scale is below a new overview minimum, Zoom
out does not increase it. Overview, Fit, Home, Escape and F return to the map.
Reduced-motion preferences disable camera animation. Fullscreen failures show a
notice.

`map-connections.tsx` draws grouped cross-subsystem relationships in a separate
SVG layer, anchored to region boundaries. Grouped arrows reflect source edge
directions; fully dotted groups retain dotted lines. The complete constituent
edge identities, labels, directions and styles remain inspectable. Hover or
keyboard focus names the endpoints. Clicking or pressing Enter opens a persistent,
scrollable inspector with individual edges and destination buttons. A close view's
Connected subsystems control keeps offscreen destinations accessible.

Global parse/layout failures retain the page-level retry state. Local failures
have a region retry; failed explicit navigation also shows a viewport-level
retry so an offscreen destination cannot hide recovery. Effect cancellation and
request identity checks prevent obsolete renders from replacing the current
source or overriding a newer gesture.

## Develop and check

Use the repository-pinned Node version. From the repository root:

```sh
npm --prefix tools/codebase-map ci
npm --prefix tools/codebase-map exec -- playwright install chromium
npm --prefix tools/codebase-map run dev
npm --prefix tools/codebase-map run check
```

The check generates route types, type-checks, exercises source provenance and
spatial-layout tests, builds the static export, and runs Chromium against it.
Browser checks account for all 23 areas, 210 nodes and 422 connections, including
dense areas 07/15 and areas 20/21 without internal edges. They cover title
containment, cached layouts, stable coordinates, continuous wheel/pinch anchors,
pan-only reveal, animation cancellation, reserved source-label space, connected
destinations, mouse/touch/keyboard controls, resize/fullscreen, reduced motion,
retry recovery and exact commit links. Pure tests cover deterministic geographic
projection, non-overlap, local placement and boundary-flow direction. Browser checks
account for all 261 cross-subsystem edges on both the inflow and outflow sides,
including destination navigation, scroll reset and keyboard focus. No live backend
or model is involved.

The shared manifest selects this suite for viewer, map and relevant tooling
changes in both local and CI lanes. GitHub Actions uses the same selection to
install locked packages and Chromium before the check. Local prerequisites are
the explicit installation commands above.

## Maintenance and publishing

Follow the [authored same-PR map review rule](../../INSTRUCTIONS.md#pr-closeout):
review product flows and source anchors, update affected paths in the same PR, and
record an update or reviewed-unchanged result in the PR checklist. The Mermaid map
also describes its own publishing flow.

The [viewer setup](../../../tools/codebase-map/README.md) specifies a dedicated
Vercel project with `tools/codebase-map` as its root, access to files outside that
directory, public access, main production and Git previews. Deployment skipping
is disabled so code-only changes refresh the displayed revision. The committed
Next.js configuration exports a static site. The remote Git connection and project
settings require Vercel observation; repository configuration alone does not
prove a live deployment or access grant.

Publishing and rendering the committed map do not establish that its flows
accurately describe the product. Agents and PR review own that assessment. An
open browser tab remains a snapshot until reloaded.

[Development](development.md) · [System architecture](../architecture/overview.md) ·
[Qualification boundaries](qualification.md) · [Start here](../../quickstart.md)
