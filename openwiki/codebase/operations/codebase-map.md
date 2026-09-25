---
type: Codebase guide
title: Codebase map viewer
description: Follow the canonical Mermaid file into a static Next.js page, inspect source provenance, and run the viewer's build and browser checks.
tags: [intentive, codebase, development, diagrams]
resource: repo://tools/codebase-map
verified:
  - by: openwiki/0.5.2
    at: 2026-09-25T12:41:08.389Z
sources:
  - id: openwiki-source-3b73c81eefcd909208670ce0
    resource: repo://.github/checks-manifest.yaml
  - id: openwiki-source-16d213dfcc8beae17f8096fe
    resource: repo://.github/scripts/prepare_codebase_map_check.py
  - id: openwiki-source-898a1f4e66854529123c0957
    resource: repo://tools/codebase-map/app/components/diagram-viewer.tsx
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
  - id: openwiki-source-06044ee38485672b205128e8
    resource: repo://tools/codebase-map/lib/diagram-source.mjs
  - id: openwiki-source-ea8e6f766ab18449d6c0d798
    resource: repo://tools/codebase-map/lib/map-geometry.ts
  - id: openwiki-source-173442aaa3e3f9cbea8df65b
    resource: repo://tools/codebase-map/lib/mermaid-runtime.ts
  - id: openwiki-source-3db6130123d0c0614cc19cb5
    resource: repo://tools/codebase-map/next.config.ts
  - id: openwiki-source-cadbf0c250f5afb51126591d
    resource: repo://tools/codebase-map/package.json
  - id: openwiki-source-fa2531a1c23faf0486307e94
    resource: repo://tools/codebase-map/tests/browser/viewer.spec.ts
  - id: openwiki-source-e05a82755d8635ac88952e98
    resource: repo://tools/codebase-map/tests/map-geometry.test.mjs
generated: { by: "codex", at: "2026-09-25T12:41:08.389Z" }
---
# Codebase map viewer

The viewer is a public, read-only architecture browser for the active product. It
displays the reviewed Mermaid map with pan, zoom, fit and fullscreen controls.
It does not host owner-local product data or generate architecture from source.

## From repository to browser

`app/page.tsx` calls `loadDiagram` during Next.js static generation. The loader
reads `docs/architecture/intentive-codeflow.mmd` relative to the repository root;
there is no independently maintained copy or runtime GitHub request. Missing,
empty and over-200,000-character input fails the build.

The loader associates the map with `VERCEL_GIT_COMMIT_SHA`, then `GITHUB_SHA`, or
Git HEAD for a clean local checkout. Hosted builds require a full commit SHA.
Edited local checkouts have no immutable source link. The header and footer link
to the exact Mermaid file at the identified GitHub commit, rather than moving main.

## From overview to local flow

The browser keeps the `DiagramViewer` source/commit/source-URL contract. The
Mermaid 12 adapter in `lib/mermaid-runtime.ts` parses the complete flowchart and
copies areas, node membership, labels, shapes, classes, styles and directed edges
before another Mermaid operation can mutate its parser database. All Mermaid
operations share a serial queue. Unsupported or incomplete graph structures fail
explicitly rather than silently dropping content.

`lib/map-geometry.ts` assigns each area a permanent position in a five-column
grid. The overview shows numbered titles and platform labels, with no node graph
or connections. Titles remain at least 14 screen pixels; small screens pan across
the board. Expanding an area does not change other areas' coordinates.

`use-map-camera.ts` owns the camera and active area. A card or Jump to area opens
one flow near its first nodes at a readable summary scale. Wheel/pinch entry uses
the area under the gesture anchor, expanding above twice the overview scale and
collapsing below 1.5 times that scale. Continuing forward zoom while the first
layout loads retains readable entry; panning or reversing zoom cancels a pending
entry adjustment. Panning retains the active area. Resize preserves the world
center and scale unless the camera is still in its fitted overview state.
Overview, Fit, Home, Escape and F return to the board. Fullscreen failures show a
notice, and reduced-motion styling disables animations and transitions.

Each area is rendered on first use with Mermaid ELK, strict security, a
200,000-character limit and a 2,000-edge limit. The generated local definition
contains its own nodes and internal edges, including styles and source labels.
The renderer caches the resulting SVG and measured node geometry by graph and
area, including in-flight promises. Rejected entries are removed for retry.
Subsequent navigation reuses the cached layout; camera gestures transform it.
Secondary label lines retain layout space while hidden, becoming visible when
the effective node font reaches 14 pixels. This avoids moving nodes or routes
as source references appear.

`map-connections.tsx` draws all incident cross-area edges in a separate layer,
anchoring one end to the local node and the other to the remote area boundary.
It suppresses connections between collapsed areas, preserves edge identities,
directions, labels and dotted/thick styles, and routes through grid gutters with
local node/header obstacle avoidance. Full labels are available on hover or
keyboard focus. Offscreen destinations appear as full-title buttons in a separate
scrollable strip below the canvas, so navigation labels do not cover nodes.
Clicking a route or its destination changes the active area.

Parsing failures show the global retry state. Local layout failures show an area
retry while overview navigation remains available. Effect cancellation and graph
identity checks prevent obsolete renders from replacing the current source or
area. There is no additional API, database, editor or maintained overview diagram.

## Develop and check

Use the repository-pinned Node version. From the repository root:

```sh
npm --prefix tools/codebase-map ci
npm --prefix tools/codebase-map exec -- playwright install chromium
npm --prefix tools/codebase-map run dev
npm --prefix tools/codebase-map run check
```

`check` generates route types, type-checks, exercises source/commit and geometry
tests, builds a static export, and runs Chromium against that export. Browser
checks cover the pinned parser and all local views: 23 areas, 210 nodes and 422
connections. They exercise dense areas 07/15, areas 20/21 without internal edges,
readable entry, progressive labels, cached SVG reuse, fixed positions, wheel
hysteresis, sustained touch pinch, keyboard focus, destination navigation,
resize/fullscreen, reduced motion, local/global retry and exact commit links.
Geometry tests cover grid gutters and measured local-node obstacle avoidance.
No live model, backend or GitHub service is involved in these checks.

The shared check manifest selects this suite for viewer, map and relevant tooling
changes in both local and CI lanes. GitHub Actions uses the same manifest selection
to install locked packages and Chromium before the check. Local prerequisites are
the explicit installation commands above.

## Maintenance and publishing

Follow the [authored same-PR map review rule](../../INSTRUCTIONS.md#pr-closeout):
review product flows and source anchors, update affected paths in the same PR, and
record an update or reviewed-unchanged result in the PR checklist. The Mermaid map
also describes its own publishing flow.

The [viewer setup](../../../tools/codebase-map/README.md) specifies a dedicated
Vercel project with `tools/codebase-map` as its root, access to files outside that
directory, public access, main production and Git previews. Deployment skipping
is disabled so code-only changes can refresh the displayed revision. The committed
Next.js configuration exports a static site. The Git connection and remote project
settings must be verified on Vercel; repository configuration alone does not prove
a live deployment or access grant.

Publishing the committed map and verifying that it renders are distinct from
checking whether its flows accurately describe the code. The coding agent and PR
review own the latter. An open browser tab remains a snapshot until reloaded.

[Development](development.md) · [System architecture](../architecture/overview.md) ·
[Qualification boundaries](qualification.md) · [Start here](../../quickstart.md)
