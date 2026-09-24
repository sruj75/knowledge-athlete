---
type: Codebase guide
title: Codebase map viewer
description: Follow the canonical Mermaid file into a static Next.js page, inspect source provenance, and run the viewer's build and browser checks.
tags: [intentive, codebase, development, diagrams]
resource: repo://tools/codebase-map
verified:
  - by: openwiki/0.5.2
    at: 2026-09-24T12:25:42.469Z
sources:
  - id: openwiki-source-3b73c81eefcd909208670ce0
    resource: repo://.github/checks-manifest.yaml
  - id: openwiki-source-16d213dfcc8beae17f8096fe
    resource: repo://.github/scripts/prepare_codebase_map_check.py
  - id: openwiki-source-898a1f4e66854529123c0957
    resource: repo://tools/codebase-map/app/components/diagram-viewer.tsx
  - id: openwiki-source-c4a16291c647622764e26cc3
    resource: repo://tools/codebase-map/app/globals.css
  - id: openwiki-source-8f88765748afaa418d7fe532
    resource: repo://tools/codebase-map/app/page.tsx
  - id: openwiki-source-06044ee38485672b205128e8
    resource: repo://tools/codebase-map/lib/diagram-source.mjs
  - id: openwiki-source-3db6130123d0c0614cc19cb5
    resource: repo://tools/codebase-map/next.config.ts
  - id: openwiki-source-cadbf0c250f5afb51126591d
    resource: repo://tools/codebase-map/package.json
  - id: openwiki-source-fa2531a1c23faf0486307e94
    resource: repo://tools/codebase-map/tests/browser/viewer.spec.ts
generated: { by: "codex", at: "2026-09-24T12:25:42.469Z" }
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

The client component loads Mermaid 12, uses ELK layout and strict security, and
allows up to 200,000 characters and 2,000 edges. It measures the rendered SVG and
fits it into the viewport. Mouse/touch, keyboard and toolbar controls change the
viewport transform without recomputing graph layout. Resize refits the diagram;
the SVG stays mounted. Inverse-zoom stroke widths preserve the overview's lines,
while zooming in exposes multiline labels and source references.

Loading and error states replace an unavailable diagram. Retry starts another
render; cancellation prevents a completed obsolete render from replacing the
current source. Fullscreen failures display a notice rather than breaking the map.

## Develop and check

Use the repository-pinned Node version. From the repository root:

```sh
npm --prefix tools/codebase-map ci
npm --prefix tools/codebase-map exec -- playwright install chromium
npm --prefix tools/codebase-map run dev
npm --prefix tools/codebase-map run check
```

`check` generates route types, type-checks, exercises source/commit-loading tests,
builds a static export, and runs Chromium against that export. The browser checks
render the complete canonical map and exercise navigation, resize, fullscreen,
malformed-input retry/recovery and immutable source-link behavior. No live model,
backend or GitHub service is involved in these checks.

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
