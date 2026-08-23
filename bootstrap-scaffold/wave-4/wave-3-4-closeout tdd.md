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

Waves 3–4 are **repository-closed on the integrated repair tree**. The backend
and desktop component suites, official hermetic E2E runner, complete Tier-2
matrix, manager/controller PTT probes, and natural physical PTT path are green.
The real-provider rows are explicitly `NOT_RUN` because the non-production
provider credentials are unavailable. That is the disposition required by the
S-19 and S-22 plans, and IR-891 makes real-provider mode optional for ordinary
development verification. It is not an implied pass and does not block repository
closure. S-26 and S-28 may begin from this closeout tree after it lands on `main`.

## 3. Lifecycle prerequisite and repair commits

| Commit | Result |
|---|---|
| `402d9fea` (PR #45) | Registry-only transition marked `FC-public-web-routing-parity` dormant with authoring-time UTC `dormant_since`; no retirement tooling changed. |
| `a57b3f8d` | Made parity-pack capture local-only; deleted the GCS exporter, retry thread, export tests, runtime export settings, and deployment classifications while retaining redacted local cassettes/replay and `google-cloud-storage` for update/preview distribution. |
| `4b032fce` | Removed the OpenRouter fake response/endpoints/comments and deployment secret vocabulary while retaining OpenAI, Anthropic, Gemini, embeddings, and realtime providers. |
| `95d5da6d` | Added one existing `record_fallback` event per failed fair-use pending-review create/read/consume operation with `component=fair_use`, operation-specific `from_mode`, `to_mode=redis_unavailable`, `reason=other`, and `outcome=degraded`. |
| `2d0f44fc` | Removed raw UID values from the adjacent fair-use Redis error logs. |
| `b15d07e3` | Repaired the stale desktop suite contracts, Tier-2 flows, local-profile PTT lifecycle, provider/Firebase 401 boundary, owner-fenced kernel finalization, signing identity lookup, and their behavioral regressions. |
| `53369edf` | Made the official hermetic E2E wrapper portable without GNU `timeout` while retaining process-group cleanup and timeout failure semantics. |
| `058bba2b` | Made setup reuse an already-installed compatible Python before consulting the stale download catalog, with a rerun regression test. |
| `e8b07c18` | Extracted the DEBUG-only local-profile PTT acceptance transport from the oversized realtime controller and ratcheted both affected line-count baselines down. |

The residue commits do not change a public HTTP, WebSocket, OpenAPI, or schema
interface. The later repairs restore already-required desktop, harness, setup,
and authentication behavior rather than introduce a new product requirement.
Legacy parity GCS variables are inert because no exporter reads them. The
existing string fair-use actions and duplicated Settings search ownership remain
design notes rather than closeout blockers.

## 4. Green repository evidence

- 162 focused backend tests passed across parity capture/runtime settings,
  OpenRouter absence, fair-use fallback/log hygiene, fallback observability,
  route policy, and test discovery.
- The development harness selection passed 54 tests with 8 intentionally skipped.
- Route-policy and deployment-secret boundary checks passed.
- The full backend suite passed all 219 selected test files in the official runner
  with `BACKEND_PYTEST_WORKERS=1`.
- `desktop/macos/test.sh` passed the launcher and packaging guards, all 48
  desktop-backend tests, and all 386 isolated Swift suites.
- Retained/removed route, `/v4/listen`, WebSocket authentication, and authenticated
  metrics coverage passed 60/60 through the assembled FastAPI app.
- The hermetic account-deletion Cloud Tasks file passed 4/4 directly, including
  completion, redelivery, enqueue recovery, and legacy payload/audience handling.
- The official `backend/testing/e2e/run.sh` passed 14/14 tests through its portable
  wrapper, including both harness self-tests and the account-deletion paths.
- `make setup` and its rerun/linked-worktree regression tests passed.
- `git diff --check` and the final requirements validation passed. The requirements
  ledger remains complete at 714 indexed rows and 714 detailed sections.
- The explicit local PR body passed `make preflight`: all 40 selected local-lane
  checks passed with `Failure-Class: FC-split-mutation-authority`.

## 5. Named-bundle acceptance and explicit unavailable evidence

### Tier-2 and PTT acceptance

The exact `omi-wave34-closeout` bundle (`com.omi.omi-wave34-closeout`) ran on
bridge port 47825 against the isolated local profile. The complete Tier-2 run at
`desktop/macos/.harness/desktop-core/20260823T134455Z-t2` passed 31/31 flows plus
the spatial-overlay suite. This closes the earlier capture lifecycle,
`home-stage`, memory-depth, recording-finalization, and speaker-naming failures.

- The controller current-screen probe reached `terminal_success` with
  `terminal_reason=success`, zero pending tools, `provider_finished=true`,
  `screen_evidence_last_completion=completed`, and no active screen-evidence
  protocol.
- The manager probe admitted all 58,234 PCM bytes and reached
  `terminal_success`/`success` with zero invalid or stale transitions while the
  authenticated owner remained signed in.
- A natural physical Option-key hold/release drove the real shortcut and capture
  lifecycle, observed recording while held, and reached
  `terminal_success`/`success` with zero invalid or stale transitions while the
  owner remained signed in.

### Real-provider matrix — `NOT_RUN`

`PROVIDER_MODE=real make dev-check USER=alice` stopped before any provider request
because `OPENAI_API_KEY`, `MODULATE_API_KEY`, `GEMINI_API_KEY`, and
`ANTHROPIC_API_KEY` are unavailable. OpenAI, Gemini, Auto, cross-provider
failover, language, reconnect, and tool rows that require those credentials are
therefore `NOT_RUN`, not passed. No provider transaction occurred.

Draft PR #46 still points at `ccac5c06`; the repaired commits were not pushed
because no publication authorization was given. Its old-head GitHub jobs remain
failed/skipped under the account billing/spending gate, so there is no CI claim
for this local repair tree. That publishing state is separate from the completed
local repository acceptance above.

## 6. Slice ledger

| Slice | Integrated implementation | Closeout repair/evidence disposition |
|---|---|---|
| S-19 | PR #38, `684d97a4` | Repository-closed: manager, controller screen, natural physical PTT, desktop, and Tier-2 acceptance are green; credential-dependent provider rows are explicitly `NOT_RUN`. |
| S-20 | PR #39, `16e86b97` | Repository-closed: fair-use fallback/log repairs are `95d5da6d` and `2d0f44fc`; component and named-bundle acceptance are green. |
| S-21 | PR #41, `ee35939d` | Repository-closed: `home-stage` and the complete Tier-2 matrix are green. |
| S-22 | PR #40, `5d6573ff` | Repository-closed: lifecycle transition and OpenRouter cleanup are complete; unavailable live-provider rows are recorded `NOT_RUN` as required by its plan. |
| S-23 | PR #42, `06a917e7` | Repository-closed: successor residue is gone and integrated component/Tier-2 acceptance is green. |
| S-24 | PR #43, `ac3ba541` | Repository-closed: parity export residue is gone and integrated component/Tier-2 acceptance is green. |
| S-25 | PR #44, `fbdb339f` | Repository-closed: runtime/deployment residue is gone and backend, E2E, component, and preflight gates are green. |

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

## 9. Closeout boundary

Repository closeout is green on the integrated repair tree through `6d5d2120`:
the desktop component suite, official hermetic E2E runner, complete Tier-2
matrix, controller screen probe, manager probe, natural physical PTT path, and
all deterministic preflight gates passed. The real-provider rows remain visibly
`NOT_RUN` until credentials are available; they are optional evidence under the
owning plans and IR-891, not a retroactive repository blocker.

S-26 and S-28 are ready to start only from a branch containing this complete
closeout tree. Because the local commits have not been pushed or merged, a new
successor branch must wait for this repair branch to land on `main` or explicitly
include the same commits. Live resource inventory/decommission, real account
deletion, deployment, release, and provider qualification remain separately
authorized work.
