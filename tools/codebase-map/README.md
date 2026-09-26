# Intentive codebase map

A public, read-only Next.js viewer for the canonical
[Mermaid product map](../../docs/architecture/intentive-codeflow.mmd).
The build reads that file directly and statically exports one page. The browser
renders its 23 areas, 210 nodes and 422 connections with Mermaid ELK. The overview
uses the original diagram's geography to place readable subsystem regions.
Clicking a subsystem opens its internal flow at a fixed readable size. There is no database, runtime GitHub request,
browser editor, or separately maintained overview map.

## Explore the map

- Click a subsystem or use **Jump to area** to open its internal flow. Full node
  labels and source references appear immediately at their natural 14-pixel size.
- Scroll, swipe, or drag to move around the map or an open diagram. The viewer
  has no zoom gestures, zoom buttons, or animated detail transitions. Browser
  accessibility zoom remains available.
- **Overview** or `Escape` returns to the subsystem map. Each view remembers its
  scroll position. Resize preserves the open subsystem and explored position;
  small diagrams remain centered. Fullscreen provides more room to explore.
- Directly below the selected subsystem's title, **Inflow** lists incoming
  data/events and their source subsystem; **Outflow** lists outgoing data/events
  and their destination. Scroll either list to read every flow, or click a
  source/destination to follow it. These lists use the canonical edge labels and
  arrow directions, including control signals; they do not infer payload schemas,
  runtime rates, or Meadows-style stocks from a generic connection. Unlabelled
  edges use their endpoint names, and missing flows are described as unrecorded.
- In the overview, connections between subsystems are grouped into routes.
  Hover or focus one to see its endpoints, then click or press Enter for the
  scrollable list of individual connections. Destination buttons open either
  subsystem. Escape closes the inspector while it has focus. In an open flow,
  **Connected subsystems** keeps its destinations and connections accessible.
- On small screens, scroll to explore the overview instead of shrinking titles
  below 14 pixels. Opening a subsystem preserves the same readable node size.

A complete Mermaid render supplies the relative geographic positions. A
deterministic overlap pass gives subsystem regions room for readable titles;
these positions do not change during navigation. Each internal flow is generated
from the parsed nodes, edges, labels, shapes and styles, laid out locally with ELK,
and cached on first use. This keeps cross-subsystem routes from spreading the
internal nodes apart. Scrolling, dragging and revisiting a loaded area reuse its SVG
and geometry without invoking Mermaid again.

Cross-subsystem connections are grouped by endpoint pair, preserving every edge
identity, direction, label and style in the inspector. Only internal edges are
rendered inside each subsystem. The global graph and local diagrams share the
same copied parser model; no diagram content is manually duplicated.

Invalid source or a failed initial layout shows a page-level error with retry.
An area render failure has its own retry control while overview navigation stays
available. Reloading starts a fresh cache for the current deployment.

## Develop and verify

Use the repository's Node version (`nvm use` from the repository root):

```sh
npm --prefix tools/codebase-map ci
npm --prefix tools/codebase-map exec -- playwright install chromium
npm --prefix tools/codebase-map run dev
```

Run the same check used by the shared local/CI manifest:

```sh
npm --prefix tools/codebase-map run check
```

This type-checks, tests the canonical-source/commit loading contract, builds the
static site, and runs Chromium against the actual exported diagram. Browser tests
cover desktop/mobile overview readability, click and keyboard navigation, native
scrolling and touch swipes, full source labels, stable region positions, cached
layouts, restored scroll positions, resize, fullscreen,
dense areas, connection inspection, complete inflow/outflow accounting, and
source/layout failure recovery.
CI installs dependencies and Chromium only when the manifest selects the viewer.
Tests use the local server and bundled assets, with no external services.

The isolated package overrides Mermaid's transitive `lodash-es` pin to 4.18.1,
which includes the fixes for [GHSA-r5fr-rjxr-66jc](https://github.com/advisories/GHSA-r5fr-rjxr-66jc)
and [GHSA-f23m-r3pf-42rh](https://github.com/advisories/GHSA-f23m-r3pf-42rh).

To inspect the production build locally, run `npm --prefix tools/codebase-map run preview`
and open `http://127.0.0.1:4173`. Build first with `npm --prefix tools/codebase-map run build`.

## Keep the map accurate

When code changes alter product flows, the coding agent updates the Mermaid map
and its source references in the same PR. For other changes, record that the map
was reviewed and remains accurate in the PR checklist. Complete the native
OpenWiki update before closeout.

Deployments publish the committed map; they do not infer new architecture from
code. Passing render checks proves that the diagram is usable, not that its
description of the product is semantically correct.

The map includes its own viewer/publishing flow. Keep this section updated if the
viewer or deployment contract changes.

## Vercel project settings

Connect a dedicated `intentive-codebase-map` project to
`sruj75/knowledge-athlete`, separate from the landing-page projects:

| Setting | Value |
| --- | --- |
| Framework | Next.js |
| Root directory | `tools/codebase-map` |
| Include files outside the root directory in the build | Enabled |
| Node.js | 22.x |
| Install command | `npm ci` |
| Build command | `npm run build` |
| Production branch | `main` |
| Skip deployments for unchanged projects | Disabled |
| Git previews | Enabled |
| Access | Public, including preview deployments |

Leave the output directory at its framework default; `next.config.ts` enables
static export. Start with the assigned `vercel.app` address. No custom domain,
provider keys, GitHub write token or application environment file is required.

Vercel must expose its system Git environment variables. The build embeds
`VERCEL_GIT_COMMIT_SHA` and links to that exact file revision on GitHub. CI uses
`GITHUB_SHA`; a clean local checkout uses Git HEAD. Edited local checkouts show a
local-state label instead of claiming an immutable revision. A hosted build with
missing/invalid commit metadata or a missing/empty/oversized diagram fails.

After setup, verify a feature-branch preview's commit/source link and rendered map.
After the PR merges, verify the production address shows the merged SHA and map.
Code-only merges also deploy so the displayed commit remains aligned with main.
An already-open tab is a snapshot; reload it to see a newer deployment.
