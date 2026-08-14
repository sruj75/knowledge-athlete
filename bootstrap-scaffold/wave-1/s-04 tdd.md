# S-04 TDD Plan — Remove Impossible Controls and Repository Zombies

Status: closed on 2026-08-14; implementation and retained-surface verification complete, with two user-approved verification waivers recorded below
Slice: S-04
Wave: 1
Authorizing and protecting decisions: IR-009, IR-010, IR-892, IR-897, IR-935, IR-939, IR-940, IR-941
Depends on: none; coordinate shared registries with S-01, S-02, and S-03
Delivery: one PR-sized change, implemented as separate testable commits

Postcondition: `make preflight` and retained CI controls execute against existing Mac/backend sources; absent-product automation and unowned packages are gone; the future Codemagic definition remains assigned to S-29; no Windows file or Windows-only control changes.

## Current Flow and Public Contracts

Current failures:

- `make preflight` exits during manifest validation because 35 explicit paths are absent.
- `scripts/pr-preflight --suggest` then fails because `docs/product/invariants/` is absent.
- Runtime-image validation fails on `plugins/Dockerfile`.
- The OpenAPI runner fails before schema generation because Python 3.11.1 needs the pinned `async-timeout` dependency.
- Release guards read a nonexistent root `codemagic.yaml`.

The agreed TDD seam is the public CLI boundary:

- `make preflight` must resolve and execute retained checks.
- `run_checks.py --changed-files … --output json` must select Mac/backend guards without resolving absent products.
- `make runtime-image-source-closure` must validate the surviving registry.
- Release-process guard CLIs must validate present GitHub-side candidate, qualification, promotion, recovery, and rollback controls without treating missing Codemagic as success.
- `generate_swift_openapi_types.py --check` will default to the live backend app-client schema; explicit `--spec` remains available for fixture tests. No product HTTP API or data migration is introduced.

Use `engineering:codebase-design` only for the three mixed boundaries: backend-to-Mac OpenAPI ownership, GitHub release controls versus future Codemagic ownership, and generic invariant machinery versus concrete guards.

## Ownership and Action Map

| Action | Exact behavior and source boundary |
|---|---|
| KEEP AS IS | Present Mac source/tests and all non-Windows packaging, preview, qualification, promotion, update, rollback, and release controls; canonical backend tests/deploy/WIF/Firestore/runtime-image guards; local/offline harness; concrete brand/auth guards; the universal `vendor/libwebp` cache protected for S-29; the `desktop-core-e2e-t0` job in the mixed desktop/backend contract workflow; historical changelogs. Record Windows matches but never open, inspect, or change Windows files or Windows-only workflows. |
| ADAPT | Narrow the check manifest, repo workflow, change-detection action, local hooks, pre-push prediction, deployment policies, agent-document checks, OpenAPI workflow, production-routing checker, and release guards to present owners. Rename the mixed mobile production-routing checker to a desktop/backend-owned checker. Remove generic invariant-citation plumbing while retaining concrete guards. |
| DELETE | Absent-product workflows: docs deploy/sync, firmware, mobile, web/admin/app/frontend/personas, plugin deploy, public-build preflight, CLI, and Rust SDK. Delete exclusive public-build actions/config/scripts/tests; Ray-Ban/app/web-only checks and helpers; plugin runtime-image ownership; absent documentation claims; `desktop/shared-rust/**` plus the desktop Cargo workspace; all of `desktop/macos/demo/**`; the nested undiscoverable `desktop/macos/.github/workflows/test-install.yml` and its exclusive contract test/fixtures; unreferenced packaged `enable_notifications.gif` and `rewind-demo.mp4`. |
| SIMPLIFY / OPTIMIZE AFTER | After deletion is green, remove dead routing outputs, empty policy kinds, obsolete release parameters, stale ignore patterns, and names that still imply mobile/public-build ownership. Do not add compatibility aliases or “missing means pass” branches. |
| ACCELERATE AFTER | `none`; record before/after preflight elapsed time and selected-check count, but do not widen S-04 into performance work. |
| AUTOMATE LAST | `none`; the existing manifest validator, retained checker CLIs, and regression tests are the stable automation. |
| OUT OF SCOPE / DEFERRED | S-01 agent-VM/proxy entries, S-02 retained sync/WAL decisions, S-03 Parakeet entries and workflows, S-29’s owned `codemagic.yaml`, external website/legal hosting, runtime product deletions assigned to later slices, and every Windows concern. |

Mixed-boundary decisions:

- Preserve `agent-vm`/`agent-proxy` and Parakeet runtime-image entries for S-01/S-03; remove only `plugins`.
- Retain the backend-to-Mac OpenAPI seam. Remove active Flutter/docs/web compatibility checks. Leave the mixed TypeScript generator untouched because it contains the excluded Windows client.
- Pin `async-timeout==4.0.3` in the OpenAPI runner environment.
- Make Swift generation derive its default schema directly from `export_openapi.generate_openapi("app-client")`, using a stable generated-file source label. If the live schema changes generated DTOs, commit the exact regenerated output and exercise affected adapters and desktop compilation.
- Keep fixture-based release parsers and present GitHub release workflows. Remove live reads, digests, and assertions for the absent inherited Codemagic document. S-29 adds fresh live-document guards alongside the owned file.
- Protect `desktop/macos/vendor/libwebp/` for S-29. S-04 may correct stale ownership text but does not delete, rebuild, or substitute the two universal dylibs.
- Keep `.github/workflows/desktop-backend-contracts.yml` and its retained T0 self-check. Record the exact later S-10/S-12 handoff for the hosted conversation/memory parity job, root fixtures, and path triggers; after S-12 removes the final contract file, it also owns the `testing/contracts/` discovery-registry and guard-test cleanup. S-04 must not delete either behavior family early.
- Delete the impossible generic product-invariant registry checker and PR citation requirement. Keep `PRODUCT.md` and concrete source-backed guards, rewriting live agent/contributor guidance so it references only present files.

## Ordered TDD Cycles

1. **Protect manifest selection**
   - RED: add one subprocess regression covering Mac and backend changed-file fixtures through `run_checks.py --output json`; it currently exits during manifest validation.
   - GREEN: remove invalid absent-only entries and triggers while preserving selected Mac/backend IDs.
   - Prove the actual manifest validates; do not substitute a synthetic-only manifest test.

2. **Restore PR preflight**
   - RED: capture the current `scripts/pr-preflight --suggest` failure on the missing invariant registry.
   - GREEN: remove the generic invariant checker, manifest entry, citation plumbing, and stale templates/docs references. Preserve failure-class, diff-hygiene, architecture, lifecycle, changelog, and concrete product guards.
   - Acceptance: `--suggest` exits successfully and still emits applicable failure-class guidance.

3. **Repair runtime-image ownership**
   - RED: `make runtime-image-source-closure` fails on `plugins/Dockerfile`.
   - GREEN: remove only the plugin image, deploy workflow, triggers, and exclusive support. Do not touch S-01 or S-03 registry ownership.
   - Acceptance: the real runtime-image CLI passes.

4. **Delete the public-build vertical**
   - RED: record the existing public-build checker’s missing web/Dockerfile failures; first run retained deployment-secret and concurrency negative tests as keep fences.
   - GREEN: delete public-build workflows, actions, configs, scripts, tests, deployment-setting kind, and dead failure-class scope hints; narrow shared concurrency/secret policies.
   - Acceptance: retained backend/Mac mutations are still rejected by their negative tests.

5. **Narrow CI and local routing**
   - RED: add cases showing repository-control, backend, and Mac changes currently request absent Flutter/web/firmware phases.
   - GREEN: delete exclusive workflows and narrow `detect-changes`, `repo-checks`, `pre_push_ci_prediction.py`, `scripts/pre-push`, pre-commit configuration, hatch disclosure, and workflow-contract tests.
   - Delete the nested undiscoverable `desktop/macos/.github/workflows/test-install.yml`, its exclusive exact-file shell contract, and both YAML fixtures rather than moving the Omi lane to the root. Preserve Python formatting, generic workflow linting, backend selection, Mac selection, and existing Windows branches byte-for-byte.

6. **Repair backend-to-Mac OpenAPI**
   - RED: run the real OpenAPI environment against Swift generation; it currently fails on `async_timeout` and the missing committed docs schema.
   - GREEN: pin the dependency, make the Swift generator default to the live backend app-client surface, and narrow the OpenAPI workflow to backend route policy plus Swift freshness. Remove active Dart/docs/web snapshot and compatibility lanes.
   - Acceptance: a fresh custom runner environment generates the schema hermetically and `--check` validates the committed Swift output.

7. **Split the Codemagic boundary**
   - RED: present release-process guards currently fail while opening root `codemagic.yaml`.
   - GREEN: keep runnable candidate-tag intake, observation, qualification, promotion, retry, rollback, and preview controls; remove inherited full-document fixtures/digests and checked-in-file assertions.
   - Acceptance: release guards pass without reading Codemagic, and no fallback treats a missing file as valid. Documentation explicitly assigns the build definition to S-29.

8. **Repair live repository documentation**
   - RED: the retained agent-reference checker reports missing docs/app/firmware/web references.
   - GREEN: update `AGENTS.md`, `PRODUCT.md`, `CONTRIBUTING.md`, backend/Mac guides, templates, and `FORK.md` to distinguish live controls, historical evidence, and deferred S-29 ownership.
   - Keep historical changelogs unchanged.

9. **Delete unowned packages**
   - Establish a passing Mac compile/test baseline first; these no-consumer deletions do not justify a synthetic source-string test.
   - Delete `desktop/shared-rust/**`, `desktop/Cargo.toml`, `desktop/Cargo.lock`, all 32 Remotion files under `desktop/macos/demo/`, and the no-caller packaged resources `Desktop/Sources/Resources/enable_notifications.gif` and `rewind-demo.mp4`, including exclusive ignore/provenance entries.
   - Re-run the same Mac compile/tests, resource/package checks, named-bundle smoke, and residue searches. Preserve every reachable Notifications/Rewind asset and live behavior plus the separate universal libwebp cache.

10. **Review and simplify after green**
    - Remove dead parameters, empty outputs, obsolete names, duplicate routing, and stale comments exposed by deletion.
    - No unrelated refactor, new abstraction, or deferred-work marker.
    - Keep each cycle green before starting the next.

## Verification, Commits, and Review

Start execution with `engineering:implement` using this file. Preserve the existing dirty scaffold files, remain on the current branch, run `make setup` before the first commit, and do not push or open a PR unless separately requested.

Required closure:

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py
python3 .github/scripts/test_run_checks.py
python3 .github/scripts/test_pr_preflight.py
python3 .github/scripts/test_check_deployment_secret_boundary.py
python3 .github/scripts/check-deployment-concurrency.py --self-test
python3 .github/scripts/check-deployment-concurrency.py
python3 .github/scripts/test_pre_push_ci_prediction.py
bash scripts/test-pre-push-diff-base.sh
python3 .github/scripts/check_agent_doc_references.py
bash scripts/run-release-process-guards.sh
make runtime-image-source-closure
make preflight
(cd backend && bash test.sh)
(cd desktop/macos && bash test.sh)
git diff --check
```

Also:

- Run pinned actionlint over every changed surviving workflow.
- Launch only a named development bundle, such as `OMI_APP_NAME=omi-s04-controls OMI_SKIP_TUNNEL=1 ./run.sh --full --no-wait`; never touch production/Omi Beta bundles.
- Prove no live absent-product workflow, nested `test-install.yml` contract, public-build, `plugins/Dockerfile`, shared-Rust, Remotion, no-caller notification/Rewind media, or stale Codemagic reference remains.
- Prove the mixed desktop/backend workflow still runs its retained T0 job and records S-10/S-12 as the later owners of the hosted conversation/memory parity job and root fixtures.
- Prove both vendored libwebp dylibs remain universal and unchanged for S-29.
- Prove the diff contains no Windows path or Windows-only workflow.
- Draft a temporary PR body, run `scripts/pr-preflight --suggest`, then validate it with `scripts/pr-preflight --pr-body-file`.
- Use `Failure-Class: new` on the focused OpenAPI runner repair commit; planned deletion/narrowing commits use `chore:` subjects and need no fix trailer.

Commit by testable surface: manifest/governance, public-build/runtime ownership, CI routing, OpenAPI repair, release-boundary split, and unowned-package/docs cleanup.

Finish with `engineering:code-review` against `origin/main`, using this plan as the spec. Run its independent Standards and Spec reviews, additionally inspect the S-04-only diff from the recorded pre-implementation HEAD, resolve all actionable findings, rerun closure, and mark the plan `closed` with commands and results recorded.

## Closure Results — 2026-08-14

Pre-implementation HEAD and merge base: `de122a91974e39fe6c64e0d299298615ea5ac9ad`.
The implementation is contained in eleven testable commits from `163d452`
through the final closure commit; nothing was pushed and no PR was opened.

### Required and focused verification

- `python3 bootstrap-scaffold/validate-requirements-ledger.py` — PASS: 714 indexed rows and 714 detailed sections.
- `python3 .github/scripts/test_run_checks.py` — PASS: 40 tests.
- `python3 .github/scripts/test_pr_preflight.py` — PASS: 35 tests, 3 skipped fixture cases.
- `python3 .github/scripts/test_check_deployment_secret_boundary.py` — PASS: 8 tests.
- `python3 .github/scripts/check-deployment-concurrency.py --self-test` and the live checker — PASS: 19 persistent writers and 1 run-scoped exemption.
- `python3 .github/scripts/test_pre_push_ci_prediction.py`, `bash scripts/test-pre-push-diff-base.sh`, and `python3 .github/scripts/check_agent_doc_references.py` — PASS.
- `bash scripts/run-release-process-guards.sh` — PASS without reading a root Codemagic document.
- `make runtime-image-source-closure` — PASS for 11 retained runtime images.
- `backend/scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check` — PASS from the hermetic runner; the committed Swift DTOs match the live app-client schema.
- `BACKEND_PYTEST_WORKERS=1 bash test.sh` from `backend/` — PASS for all 800 discovered unit-test files. The default eight-worker run reported 15 duration-guard failures under host load; the same 15 files passed through the same runner with one worker before the complete serial pass.
- `bash test.sh` from `desktop/macos/` — PASS: launcher/shell contracts, 45 Python companion tests, debug compilation, and 441 isolated Swift suites.
- Pinned actionlint 1.7.12 — PASS for all 5 changed surviving workflows.
- `scripts/failure-class validate --base origin/main --head HEAD --pr-body-file .context/s04-pr-body.md` — PASS; the focused OpenAPI repair commit has a parseable `Failure-Class: new` trailer and the PR-scope draft correctly declares `none` for the mixed planned registry cleanup.
- `git diff --check` and the final residue/scope probes — PASS.

### Preflight measurement and explicit waivers

- Before S-04, detached at `de122a91974e`, `make preflight` selected 10 always-on local checks and failed manifest resolution on 35 absent explicit paths in 1.74 seconds.
- After S-04, the local manifest resolves and selects 95 retained checks. With a local PR-body draft and a canonical temporary-directory path, execution advanced through the retained checks and stopped after 23.42 seconds at the Firestore-emulator prerequisite because the machine has Java 19 and the retained test requires Java 21+.
- The user explicitly waived completion of `make preflight` (including the equivalent full `scripts/pr-preflight --pr-body-file` execution) and instructed that Java 21 must not be installed. The attempted Homebrew Java 21 formula was removed immediately; the pre-existing Java 19 installation remains.
- The user explicitly waived the named `omi-s04-controls` development-bundle smoke after the launcher required unavailable local backend configuration. The attempt was stopped; production `Omi.app` and `Omi Beta.app` were not targeted.

### Preservation, residue, and review proof

- Deleted-surface probes confirm no live public-build action/config, `plugins/Dockerfile`, `desktop/shared-rust`, desktop Cargo workspace, Remotion demo, nested `test-install.yml`, or the two no-caller media resources remain.
- `.github/workflows/desktop-backend-contracts.yml` retains `desktop-core-e2e-t0` and records the exact S-10/S-12 hosted conversation/memory handoff.
- Both `desktop/macos/vendor/libwebp` dylibs remain byte-identical to `origin/main`, with SHA-256 values `3515af9fc46957cbd3f879ee36b9bbc0283cf6e2bbd51032a943ec8a9e64b2ff` and `5a92b18c7deee56b134d1079712e41e77d151584c20e894a3a9c176e9f9ed119`; each remains universal `x86_64 arm64`.
- The changed-path set contains no Windows path. Windows-named workflows are skipped before any read by the S-04 guards; no Windows file or Windows-only workflow was opened or changed.
- Independent Standards and Spec reviews were rerun against the final S-04 diff. Their actionable findings were resolved: closure/waiver wording was corrected, stale deleted-test duration entries were removed, and the manifest reason now names only the retained actionlint hatch. The Standards reviewer withdrew an initial concern after confirming that retained readiness behavior tests remain and only absent-doc assertions were deleted.
