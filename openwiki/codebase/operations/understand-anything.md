---
type: Operations guide
title: Understand Anything across workspaces
description: Explain committed graph freshness, Conductor closeout, the pinned scanner and the restricted weekly report publisher.
tags: [intentive, codebase, operations]
sources:
  - id: openwiki-source-311b902b81b9fbe111c8359f
    resource: repo://.conductor/settings.toml
  - id: openwiki-source-3b73c81eefcd909208670ce0
    resource: repo://.github/checks-manifest.yaml
  - id: openwiki-source-2086e730056d335da93dacd1
    resource: repo://.github/scripts/publish_guardrail_pulse.py
  - id: openwiki-source-54e240f9ab6a71a2b90a1c33
    resource: repo://.github/workflows/guardrail-baseline-pulse.yml
  - id: openwiki-source-525cd1c034c50a5bed667e46
    resource: repo://.github/workflows/repo-checks.yml
  - id: openwiki-source-012f2c78e3b1446dfc35803f
    resource: repo://Makefile
  - id: openwiki-source-f6dfb300ae1aff0b8b4f105b
    resource: repo://scripts/pre-push
  - id: openwiki-source-469fc7e842e55e4e2ff57324
    resource: repo://scripts/test_ua_graph.py
  - id: openwiki-source-b24c59cad9cbd7492bfe46b6
    resource: repo://scripts/ua_graph_validate.mjs
  - id: openwiki-source-3b9ccb56b9b2e5c92a9c0860
    resource: repo://scripts/ua_graph.py
generated: { by: "codex", at: "2026-09-18T08:55:03.537Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-18T08:55:03.537Z
---
# Understand Anything across workspaces

The graph travels with the code in the same PR. Conductor's Create PR prompt finishes source changes, tests and the native OpenWiki lifecycle, commits those inputs, completes Understand Anything analysis, then commits the persistent `.ua` output before checking and publishing. A new worktree inherits the graph from its starting commit. There is no archive-time publisher or shared global graph in this handoff.

## One owner finishes the workspace

The closeout prompt selects the enabled Codex `understand-anything@understand-anything` system fork and resolves its active skill directory, together with `UNDERSTAND_NO_WORKTREE_REDIRECT=1`. It preserves system maps, the existing analysis scope, language and auto-update setting and requires Luna semantic-analysis agents. One session owns the worktree's `.ua`: a hook request and explicit closeout are coalesced into the same update, and the session waits for analysis and finalization before staging persistent output. The authored procedure requires honoring the analyzer's project lease rather than starting a competing writer or adopting another session's token.

The generation plugin is separate from the pinned offline checking runtime returned by `scripts/ua-graph root`. If the system fork is unavailable, closeout reports the missing installation rather than running stock generation over the product maps. Installing a fork does not itself prove that a graph has been generated or accepted; the validated persistent output must still be saved and checked.

If the old analysis commit is unavailable, generation performs a full analysis with the saved settings. Advancing metadata alone is not completion. Failed or partial analysis stops publication and leaves the saved baseline available for diagnosis. Create PR does not merge the PR or archive the workspace. When newer main changes analyzed inputs, integrating that base requires another refresh before merge.

The [authored PR closeout procedure](../../INSTRUCTIONS.md#pr-closeout) defines the required sequence; [Conductor settings](../../../.conductor/settings.toml) direct Create PR to follow it. General engineering and wiki rules remain in the [authored brief](../../INSTRUCTIONS.md); this generated guide does not replace them.

## Prepare once, check committed content

`make setup` includes runtime preparation. The three public commands are:

```sh
scripts/ua-graph setup
scripts/ua-graph root
scripts/ua-graph check --ref HEAD
```

Setup downloads and builds an external cached runtime pinned to Understand Anything commit `6df3065f1d8ddc2ce3615314d1d493f36d6b1c80` (version 2.9.7), Node 22.22.0 and pnpm 10.6.2. It installs the upstream skill workspace and its dependencies with the frozen lockfile, builds core, verifies scanner source and records built JavaScript and helper hashes. Readiness also loads the stock batching and incremental helpers without executing generation; a scanner-only installation is incomplete. The cache identity includes platform and architecture. An exclusive setup lock prevents competing cache preparations.

`root` exposes a verified plugin directory. `check` uses that prepared runtime without downloads, model calls or repository source changes. Missing or damaged preparation produces a setup error. CI uses the same preparation action before graph freshness, Hygiene, metadata preflight and release eligibility.

The checker resolves the requested commit and exports its raw Git blobs into an isolated checkout. The canonical scanner applies the candidate's existing exclusions. The checker then requires an exact fingerprint inventory, matching analyzed content hashes, whole-file graph coverage, valid raw graph structure and references, and consistent metadata. It rejects missing, malformed and partial artifacts instead of repairing them. A fresh graph in the index or working tree cannot make stale committed content pass.

The three saved baseline hashes must agree with each other, but need not equal the commit being checked or identify an available historical Git object. Consequently a graph-only commit, or a change excluded by the saved scope, can pass without repeated generation. This checks committed content consistency; it does not assess whether an LLM's prose explains the code well.

## Local and remote enforcement

`ua-graph-freshness` is selected for every candidate in both shared-manifest lanes. Pre-push runs it against every distinct pushed commit, including when the broader PR-preflight shortcut applies. Deleting a ref has no new commit to validate. The independent **UA Graph Freshness** Actions job runs for PR events and pushes to main, without a changed-path filter. Default PR checkout validates GitHub's combined PR-and-base merge candidate.

The [qualification guide](qualification.md) describes the surrounding manifest and release checks. Regression tests exercise committed versus uncommitted graphs, additions/deletions/renames, exclusions, malformed output, unavailable historical baselines, actual pushed refs and a disposable worktree handoff. The handoff test removes workspace A after merging code and graph, then verifies that workspace B can check its inherited graph independently.

## Weekly report publication and activation

The weekly/manual pulse workflow is restricted to main and serialized. It uses a dedicated App token from the `guardrail-pulse-publisher` environment to publish history, while issue reporting retains `GITHUB_TOKEN`. The publisher fetches fresh main and validates that its candidate changes only `.github/guardrail-pulse-history.jsonl` by appending one valid report row. It rejects other files, changed prefixes, deletions, renames, mode changes, additional commits and dirty checkout output. A competing push causes a fresh fetch, regeneration and validation, for at most three attempts; it never force-pushes. Report-only changes remain outside the current graph analysis scope.

Workflow code alone does not activate the remote exception or branch requirement. The [authored delivery rules](../../INSTRUCTIONS.md#delivery-guidance) require publication rollout to provision the **Intentive Guardrail Pulse** App with repository-only Contents write and Metadata read, install it only on this repository, and set `GUARDRAIL_PULSE_APP_CLIENT_ID` and `GUARDRAIL_PULSE_APP_PRIVATE_KEY` in the main-restricted environment. Only that App should receive the audited `always` bypass. GitHub's bypass is broader than a file path, so the publishing workflow enforces the one-file boundary.

After the check succeeds on main and report publication is ready, rollout can require **UA Graph Freshness** from GitHub Actions, an up-to-date base and regular-merge PRs. These external settings are separate activation work, not evidence supplied by this checkout. Normal code PRs receive no report exception.

See [development and wiki maintenance](development.md) for setup and [quickstart](../../quickstart.md) for other task routes.
