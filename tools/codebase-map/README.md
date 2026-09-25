# Intentive codebase map

A public, read-only Next.js viewer for the canonical
[Mermaid product map](../../docs/architecture/intentive-codeflow.mmd).
The build reads that file directly and statically exports one page. The browser
parses its 23 areas, 210 nodes and 422 connections into one graph. It opens on a
board of readable area cards; clicking an area or zooming into it reveals its
nodes and connections. There is no database, runtime GitHub request or browser
editor, and no separately maintained overview map.

## Explore the map

- Pan by dragging, zoom with the wheel or a two-finger pinch, or focus the canvas
  and use arrow keys and `+` / `-`. Fullscreen gives the map more space.
- Click a card or use **Jump to area** to focus one area. **Fit diagram** and
  **Overview** return to the board.
- Zoom in to reveal source references and secondary node details. Overview cards
  retain readable titles on smaller screens; pan to reach cards outside the view.
- Follow connections beyond the current area through their named destination
  controls in the scrollable strip below the canvas. Every incoming and outgoing connection remains represented, including
  areas whose nodes connect only to other areas.

Area positions stay fixed while exploring. Each area's Mermaid ELK layout is
rendered on demand and cached for the current source. Panning, zooming, resizing,
and revisiting an area reuse its SVG. Only one area expands at a time. Zoom enters
an area at twice the overview scale and returns to cards below 1.5 times that scale,
preventing repeated expansion and collapse near one threshold. Secondary node
details appear when their effective font size reaches 14 pixels.

An area layout failure shows a local retry control while the board and area
navigation remain available. Invalid source shows a page-level error. Reloading
the page reads the current deployment and starts a fresh layout cache.

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
cover desktop/mobile overview readability, click/wheel/pinch/keyboard navigation,
source detail, fixed positions, cached layouts, resize, fullscreen, dense areas,
connections across areas, and source/layout failure recovery.
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
