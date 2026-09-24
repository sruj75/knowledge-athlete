# Intentive codebase map

A public, read-only Next.js viewer for the canonical
[Mermaid product map](../../docs/architecture/intentive-codeflow.mmd).
The build reads that file directly and statically exports one page. Mermaid renders
the diagram in the browser with ELK layout; pan, zoom, fit and fullscreen operate
on the rendered SVG without repeating layout. There is no database, runtime GitHub
request or browser editor.

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
cover the full map, pan/zoom, fit, resize, fullscreen and malformed-input recovery.
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
