# Waves 3–4 closeout TDD and evidence record

## 1. Closeout identity

| Field | Value |
|---|---|
| Scope | Unnumbered integrated closeout for S-19 through S-25 |
| Registry prerequisite | PR #45, merge commit `402d9fea` |
| Repair baseline | `origin/main` at `402d9fea` |
| Named development bundle | `omi-wave34-closeout-final` (`com.omi.omi-wave34-closeout-final`) |
| Billing mode | `disabled` |
| External mutation | None |

## 2. Corrected outcome on 2026-08-26

The individual S-19 through S-25 repository implementations retain the status
proved by each owning slice's original acceptance record. The **combined Waves
3–4 closeout remains open** under its stricter implementation plan: that plan
requires final-head component/Tier-2 evidence plus natural physical PTT and the
OpenAI/Gemini/Auto/failover provider lane, and explicitly says missing
development credentials or an unrun physical/provider row leaves the closeout
open.

This record no longer treats IR-891's ordinary-development allowance, or the
more permissive `NOT_RUN` disposition in the S-19/S-22 slice plans, as permission
to relax the combined closeout contract. S-26 and S-28 therefore remain blocked
on this combined closeout and its landing state.

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
| `64c2f2d6` | Removed the raw local-profile owner identifier from the rejected-commit log and automation response, retaining only `owner_present`. |
| `1ad4ddb5` | Repaired managed OpenAI TTS auth/quota classification at the typed backend boundary so provider failures cannot be inferred from English text or invalidate Firebase sessions. |

The residue commits do not change a public HTTP, WebSocket, OpenAPI, or schema
interface. The later repairs restore already-required desktop, harness, setup,
and authentication behavior rather than introduce a new product requirement.
Legacy parity GCS variables are inert because no exporter reads them. The
existing string fair-use actions and duplicated Settings search ownership remain
design notes rather than closeout blockers.

## 4. Repository evidence and final-head rule

The following 2026-08-23 results are historical integration evidence from the
repair tree; they are not a claim that every slice-specific matrix was rerun by
one generic harness:

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

The 2026-08-26 boundary repairs were developed with behavioral RED/GREEN tests.
Focused backend tests pass 7/7; focused auth/realtime Swift tests pass 37/37;
the agent-logic harness passes; the official backend runner passes all 219
discovered test files; and `desktop/macos/test.sh` passes all launcher/packaging
guards, 50 desktop-backend tests, and 386 isolated Swift suites. Because this
document itself changes the commit, final-head Tier-2, continuity, E2E, preflight,
and physical/provider outcomes must be attached to the draft PR after this
record's commit. No older manifest may be relabelled as final-head proof.

## 5. Named-bundle acceptance and open qualification lanes

### Tier-2 and PTT acceptance

The historical `omi-wave34-closeout` bundle (`com.omi.omi-wave34-closeout`) ran on
bridge port 47825 against the isolated local profile. The complete Tier-2 run at
`desktop/macos/.harness/desktop-core/20260823T134455Z-t2` passed 31/31 flows plus
the spatial-overlay suite. This repaired the earlier capture lifecycle,
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

These observations belong to the 2026-08-23 repair head. The combined closeout
still requires the corresponding natural physical PTT and continuity evidence
on the final committed head; controller or manager injection is supporting
evidence, not a substitute.

### Real-provider matrix — `BLOCKED / NOT_RUN`

`PROVIDER_MODE=real make dev-check USER=alice` stopped before any provider request
because `OPENAI_API_KEY`, `MODULATE_API_KEY`, `GEMINI_API_KEY`, and
`ANTHROPIC_API_KEY` are unavailable. OpenAI, Gemini, Auto, cross-provider
failover, language, reconnect, and tool rows that require those credentials are
therefore `NOT_RUN`, not passed. No provider transaction occurred.

On 2026-08-26 the non-production auth path was checked again. Omi Dev had no
captured ID token, and the historical closeout bundle's Keychain credential was
not available to the non-interactive probe process. No bearer token or provider
secret was exposed, and no provider transaction occurred. The required deployed
mint/direct-provider probe and OpenAI/Gemini/Auto/failover matrix remain open.

## 6. Slice ledger

| Slice | Original acceptance authority | Combined-closeout disposition |
|---|---|---|
| S-19 | [S-19 section 19](../wave-3/s-19%20tdd.md#19-integrated-closeout-record--2026-08-23), PR #38, `684d97a4` | Per-slice repository status retained. Final-head physical/provider integration qualification remains open under this combined plan. |
| S-20 | [S-20 section 19](../wave-3/s-20%20tdd.md#19-integrated-closeout-record--2026-08-23), PR #39, `16e86b97` | Per-slice repository status retained; `95d5da6d` and `2d0f44fc` are the closeout repairs. |
| S-21 | [S-21 section 19](../wave-3/s-21%20tdd.md#19-integrated-closeout-record--2026-08-23), PR #41, `ee35939d` | Per-slice repository status retained; `home-stage` is integration regression evidence only. |
| S-22 | [S-22 section 19](../wave-3/s-22%20tdd.md#19-integrated-closeout-record--2026-08-23), PR #40, `5d6573ff` | Per-slice repository status retained. The combined provider matrix remains open; `1ad4ddb5` repairs its typed auth boundary. |
| S-23 | [S-23 section 19](s-23%20tdd.md#19-integrated-closeout-record--2026-08-23), PR #42, `06a917e7` | Per-slice repository status retained; `4b032fce` removed successor residue. |
| S-24 | [S-24 section 19](s-24%20tdd.md#19-integrated-closeout-record--2026-08-23), PR #43, `ac3ba541` | Per-slice repository status retained; `a57b3f8d` removed parity-export residue. |
| S-25 | [S-25 section 19](s-25%20tdd.md#19-integrated-closeout-record--2026-08-23), PR #44, `fbdb339f` | Per-slice repository status retained; live state is `unknown` in the sanitized inventory handoff and operational closure remains open. |

The generic Tier-2 and continuity runs are cross-slice regression sweeps. They
do not replace, or retroactively re-prove, the distinct acceptance matrices
linked above.

## 7. S-25 Windows scope exception

The four-line cleanup in `desktop/windows/scripts/diag-listen-probe.mjs` is not
reverted. It is a retrospective S-25 scope exception: restoring those lines would
advertise the retired `backend-listen` service. No Windows file is changed by this
closeout.

## 8. Operational handoffs that remain open

- Keep accepting the legacy account-deletion audience/payload until a separately
  authorized operator records verified queue-drain and rollback-window evidence.
- Use the sanitized S-25 inventory/handoff in
  [`s-25 tdd.md`](s-25%20tdd.md#191-sanitized-live-resource-inventory-handoff--2026-08-26).
  Its live classifications remain `unknown` until an operator can verify the
  authoritative environment/project identity. Decommissioning still requires a
  separately authorized mutation operation with exact environment, ownership,
  retention, rollback, and before/after evidence.
- Exercise real account deletion only under separate authorization using a
  disposable owned development identity.

No cloud, data, IAM, provider, production-app, billing, or Windows mutation was
performed. `BILLING_MODE=disabled` remained unchanged.

## 9. Closeout boundary

The combined Waves 3–4 closeout is **open**. It can close only when one final
committed SHA has passing component/E2E/Tier-2/continuity evidence, natural
authenticated physical PTT is rerun on that head, and the required non-production
OpenAI/Gemini/Auto/failover plus deployed mint/direct-provider probe is recorded.
Unavailable credentials are a truthful blocker, not an implied pass and not a
reason to relax the accepted closeout contract.

S-26 and S-28 remain blocked on that closeout and on the repair branch landing on
`main`. Live resource decommission, real account deletion, deployment, and
release remain separately authorized work even after repository closeout.
