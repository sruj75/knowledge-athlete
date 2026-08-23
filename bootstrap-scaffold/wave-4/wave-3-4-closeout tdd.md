# Waves 3–4 closeout TDD and evidence record

## 1. Closeout identity

| Field | Value |
|---|---|
| Scope | Unnumbered integrated closeout for S-19 through S-25 |
| Registry prerequisite | PR #45, merge commit `402d9fea` |
| Repair baseline | `origin/main` at `402d9fea` |
| Named development bundle | `omi-wave34-closeout` (`com.omi.omi-wave34-closeout`) |
| Billing mode | `disabled` |
| External mutation | None |

## 2. Outcome on 2026-08-23

The residue repairs are implemented, but Waves 3–4 are **not repository-closed**.
The required backend suite is green; the required desktop suite, complete Tier-2
matrix, manager/controller PTT probes, physical/provider matrix, and hermetic E2E
runner are not all green. S-26 and S-28 therefore remain blocked. This record must
not be changed to repository-closed until every required lane below passes on the
same integrated source tree.

## 3. Landed lifecycle prerequisite and repair commits

| Commit | Result |
|---|---|
| `402d9fea` (PR #45) | Registry-only transition marked `FC-public-web-routing-parity` dormant with authoring-time UTC `dormant_since`; no retirement tooling changed. |
| `a57b3f8d` | Made parity-pack capture local-only; deleted the GCS exporter, retry thread, export tests, runtime export settings, and deployment classifications while retaining redacted local cassettes/replay and `google-cloud-storage` for update/preview distribution. |
| `4b032fce` | Removed the OpenRouter fake response/endpoints/comments and deployment secret vocabulary while retaining OpenAI, Anthropic, Gemini, embeddings, and realtime providers. |
| `95d5da6d` | Added one existing `record_fallback` event per failed fair-use pending-review create/read/consume operation with `component=fair_use`, operation-specific `from_mode`, `to_mode=redis_unavailable`, `reason=other`, and `outcome=degraded`. |
| `2d0f44fc` | Removed raw UID values from the adjacent fair-use Redis error logs. |

The repair commits do not change a public HTTP, WebSocket, OpenAPI, Swift, schema,
or product interface. Legacy parity GCS variables are inert because no exporter
reads them. The existing string fair-use actions and duplicated Settings search
ownership remain design notes rather than closeout blockers.

## 4. Green repository evidence

- 162 focused backend tests passed across parity capture/runtime settings,
  OpenRouter absence, fair-use fallback/log hygiene, fallback observability,
  route policy, and test discovery.
- The development harness selection passed 54 tests with 8 intentionally skipped.
- Route-policy and deployment-secret boundary checks passed.
- The requirements ledger passed with 714 indexed rows and 714 detailed sections.
- The full backend suite passed in the official runner with
  `BACKEND_PYTEST_WORKERS=1`; three timing-sensitive files that failed only under
  the initial saturated parallel run also passed 41/41 in a one-worker rerun.
- Retained/removed route, `/v4/listen`, WebSocket authentication, and authenticated
  metrics coverage passed 60/60 through the assembled FastAPI app.
- The hermetic account-deletion Cloud Tasks file passed 4/4 directly, including
  completion, redelivery, enqueue recovery, and legacy payload/audience handling.
- `git diff --check` and the final requirements validation passed. The explicit
  PR-body preflight passed all 25 selected CI-lane checks with `Failure-Class:
  none`. The first `make preflight` reached the same checks but read already-merged
  PR #45 metadata; it must be rerun after the separate repair draft exists.

## 5. Red and unavailable required evidence

### Desktop component suite

`desktop/macos/test.sh` built the application and passed the launcher plus 48
desktop-backend tests, but exited 1 with 17 Swift suites red:

`APIClientAuthRecoveryTests`, `ActionItemLocalIdentityMutationTests`,
`ChatErrorStateTests`, `ConversationDeletionCascadeTests`,
`DesktopAutomationSecondaryActionTests`, `DesktopChatDriftGuardTests`,
`DesktopCoordinatorServiceTests`, `HardeningSeamActionTests`,
`LiveTranscriptionFailureStateTests`, `LocalMemoryLifecycleRunnerTests`,
`MemoryLocalAuthorityTests`, `RealtimeHubSessionHandoffPolicyTests`,
`RealtimeManagedAuthenticationTests`, `TaskDetailMetadataProjectionTests`,
`TasksSortOrderBandingTests`, `TasksStoreOwnerBoundaryTests`, and
`TasksViewModelCompletedToggleTests`.

### Hermetic E2E runner

The official `backend/testing/e2e/run.sh` could not run because GNU `timeout` is
not installed. Direct execution passed 12/14 tests; the two harness self-tests
expect `BlockedNetworkError` while the suite conftest currently raises
`AssertionError`. The account-deletion file itself remains green 4/4. This is a
reported acceptance failure, not a waived gate.

### Named-bundle Tier-2 and PTT evidence

The exact named bundle launched on bridge port 47934, remained signed in and past
onboarding across restart, and never touched either production Omi bundle. The
complete offline Tier-2 run at
`desktop/macos/.harness/desktop-core/20260823T112114Z-t2` passed 26/31 flows plus
the spatial-overlay suite. Five flows failed:

| Flow | Observed failure |
|---|---|
| `capture-lifecycle` | Local detail stayed `processing`, not `completed`. |
| `home-stage` | Home remained in `chat`, not the expected collapsed `hub`. |
| `memory-depth` | Search/tag projection returned no matching row. |
| `recording-finalization` | Finalized local detail stayed `processing`. |
| `speaker-naming` | The second segment was absent, so the speaker assignment did not apply. |

The controller screen probe reached `terminal_success` with no pending tool, but
reported `screen_evidence_last_completion=not_run`; it therefore failed the
required screen-evidence contract. The manager probe injected all 42,800 PCM
bytes with no invalid/stale transitions, then terminated `owner_changed` rather
than a successful provider result. No development provider credentials were
available for real OpenAI, Gemini, Auto, failover, language, held/locked,
barge-in, reconnect, or local-tool provider rows. Natural physical PTT and real
screen capture were not accepted. Fake/offline evidence does not substitute for
those rows.

## 6. Slice ledger

| Slice | Integrated implementation | Closeout repair/evidence disposition |
|---|---|---|
| S-19 | PR #38, `684d97a4` | Integrated; PTT physical/provider and manager/controller acceptance remain open. |
| S-20 | PR #39, `16e86b97` | Fair-use fallback/log repairs are `95d5da6d` and `2d0f44fc`; full desktop acceptance remains open. |
| S-21 | PR #41, `ee35939d` | Integrated; `home-stage` remains red in the closeout bundle. |
| S-22 | PR #40, `5d6573ff` | Failure-class lifecycle closed in `402d9fea`; OpenRouter residue removed in `4b032fce`; real provider matrix remains open. |
| S-23 | PR #42, `06a917e7` | OpenRouter successor residue removed in `4b032fce`; required integrated acceptance remains open. |
| S-24 | PR #43, `ac3ba541` | Hosted parity export residue removed in `a57b3f8d`; required integrated acceptance remains open. |
| S-25 | PR #44, `fbdb339f` | Runtime/deployment parity residue removed in `a57b3f8d`; required integrated acceptance remains open. |

## 7. S-25 Windows scope exception

The four-line cleanup in `desktop/windows/scripts/diag-listen-probe.mjs` is not
reverted. It is a retrospective S-25 scope exception: restoring those lines would
advertise the retired `backend-listen` service. No Windows file is changed by this
closeout.

## 8. Operational handoffs that remain open

- Keep accepting the legacy account-deletion audience/payload until a separately
  authorized operator records verified queue-drain and rollback-window evidence.
- Inventory and decommission live cloud/provider resources only in a separately
  authorized read-only-then-mutation operation with exact environment, ownership,
  retention, rollback, and before/after evidence.
- Exercise real account deletion only under separate authorization using a
  disposable owned development identity.

No cloud, data, IAM, provider, production-app, billing, or Windows mutation was
performed. `BILLING_MODE=disabled` remained unchanged.

## 9. Reopen-to-close conditions

Repository closeout may be recorded only after the desktop component suite,
official hermetic E2E runner, complete Tier-2 matrix, manager/controller screen
probes, and natural physical/provider matrix are all green on the integrated
repair commit. Until then, the deletion map must describe S-19 through S-25 as
implemented but closeout-blocked, and S-26/S-28 must not begin on a claimed
closed predecessor state.
