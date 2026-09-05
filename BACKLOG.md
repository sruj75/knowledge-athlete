# Backlog

This file owns work that the product owner has intentionally deferred. An open
entry is not accepted, waived, or silently treated as green. It names the point
at which the work becomes mandatory again and the evidence required to close it.

## BL-001: Final all-waves provider and continuity qualification

**Status:** OPEN — provider/deployment inputs now exist; final real-provider and
continuity qualification is not yet recorded

**Run when:** every deletion-map wave has been implemented, before the final
all-waves closeout or any release claim

**Next-wave effect:** does not block starting S-26 or S-28, provided they include
the complete Waves 3–4 repair tree

### Why this was deferred

At the 2026-08-26 deferral, the Waves 3–4 repository repairs and local
acceptance were strong enough to continue sweeping later vertical slices. The
remaining rows required approved non-production provider credentials and a
verified deployed development identity that were not then available. The
offline echo provider could prove lifecycle mechanics, but it could not
truthfully prove that a real provider remembered and recalled earlier context.

This scheduling decision does **not** close the combined Waves 3–4 closeout and
does **not** relax its original acceptance contract. It moves the unavailable
live qualification to one explicit gate at the end of all waves.

### Current status — 2026-09-04

The original availability blocker is resolved. The approved development
Gemini, OpenAI TTS, Modulate, and Langfuse credentials are bound to the verified
`knowledge-athlete-dev` deployment, whose active revision
`knowledge-athlete-dev-0ea29f5-33868830964-1` serves exact source SHA
`0ea29f5c30cdf93ae3a76ac70f21d7a8bb148977`. Their development checks passed.
BL-001 remains open because the natural physical-PTT, real-provider continuity,
same-provider reconnect/tools, buffered Modulate recovery, deploy-inline mint,
and direct-provider rows have not all been rerun and recorded on one current
final SHA. This update does not relabel the historical baseline below.

### Proven baseline before deferral

At commit `30c50f7f4af7d5c3659768fe2b76215301143d37`:

- the backend, desktop, hermetic E2E, agent-logic, and requirements suites passed;
- offline Tier-2 passed 31/31 flows plus the spatial-overlay suite;
- natural authenticated physical PTT captured 235,530 bytes over 7.4 seconds
  and reached terminal success with no invalid or stale transitions;
- offline continuity terminalized cleanly, but blind recall failed against the
  echo fake; and
- the real OpenAI/Gemini/Auto/failover matrix and deployed
  provider-mint/direct-provider probe were `NOT_RUN` because the required
  credentials and verified deployment identity were unavailable.

The owning evidence record is
[`bootstrap-scaffold/wave-4/wave-3-4-closeout tdd.md`](bootstrap-scaffold/wave-4/wave-3-4-closeout%20tdd.md).
Each slice's original acceptance record remains the authority for its own
matrix; one generic Tier-2 run does not replace those records.

### Required exit evidence

Run all of the following on one final committed SHA after every wave is
implemented:

1. Rerun the component suites, hermetic E2E, agent-logic harness, full Tier-2
   matrix, and natural authenticated physical PTT.
2. With the approved non-production credentials, run the current retained
   provider rows: Gemini Live language/reconnect/tools, OpenAI TTS, and buffered
   Modulate recovery. The former Auto/provider-selection and Anthropic paths are
   no longer part of the Intentive product contract.
3. Run the live-provider continuity path from typed turn, through physical PTT,
   to blind recall. An echo/fake response is not a pass.
4. Using the verified development deployment identity, run the required
   provider-mint/deploy-inline and direct-provider probe without exposing tokens
   or provider secrets.
5. Record the exact SHA, commands, manifests, and outcomes in the final
   all-waves closeout and its PR record, while continuing to link every original
   per-slice acceptance record.

Until every required current-contract row is green on one final SHA, BL-001 and
the combined Waves 3–4 closeout stay open. The final all-waves closeout and
release claim may not treat provider availability alone as qualification.

## BL-002: S-25 verified live-resource inventory and operational handoff

**Status:** OPEN — verified operator/project identity and an initial live
inventory now exist; final classification and operational handoff remain

**Run when:** after every deletion-map wave is implemented and before any live
resource decommission or operational-closure claim

**Current effect:** does not block repository work; blocks live-resource or
operational-closure claims

The sanitized historical S-25 inventory is recorded in
[`bootstrap-scaffold/wave-4/s-25 tdd.md`](bootstrap-scaffold/wave-4/s-25%20tdd.md#191-sanitized-live-resource-inventory-handoff--2026-08-26).
At that deferral, live classifications were not inferred from source because a
verified operator identity was unavailable.

As of 2026-09-04, `srujan@heyintentive.com` is the verified GCP operator for the
`knowledge-athlete` project, and a sanitized read-only inventory has confirmed
the development Cloud Run service, runtime identity, Artifact Registry,
development update bucket, Cloud Build bucket, and account-deletion queue. This
resolves the identity/availability blocker, not BL-002 itself. Finish this entry
by formally classifying every retained, rejected, shared, already-absent, or
unknown resource and recording the required development operational evidence.
Any deploy, drain, deletion, IAM, secret, image, network, data, or production
mutation remains separately authorized work and must record before/after and
rollback evidence.

Run S-27's manual `foundation-readiness` mode first and retain its sanitized
read-only output. A matching inventory does not replace the separately
authorized behavioral and denial probes.

## BL-003: S-27 deferred broad verification

**Status:** OPEN — broad local evidence exists; final-source hosted verification
and reconciliation remain outstanding

**Run when:** the final source is pushed and GitHub Actions can execute the
selected checks; before the final all-waves closeout

**Next-wave effect:** does not block repository implementation of later slices

At S-27 commit `2853357f`, focused tests and deterministic contracts passed, but
the locked full backend/Pyright lane could not be completed, Colima could not
run the backend image smoke, and PR #50 detector jobs failed before executing
any steps. That paragraph is the historical S-27 baseline.

The 2026-09-05 local command set on exact source
`c632eeddcc36e8568afa4cddcebec1af678e41c3` now records:

- `backend/test-preflight.sh`: 16 passing checks, eight optional integration
  warnings; `backend/scripts/typecheck.sh`: 0 errors, 497 existing warnings.
- `backend/test.sh`: 2,730 passing tests, 70 deselected, no assertion failures;
  nonzero exit from the existing 0.12-second local CPU ratchet in unaffected
  tests that also reproduce on `origin/main`. Do not relabel this a runner pass.
- `make runtime-image-smoke SERVICE=backend`: healthy Docker, 11.42 MB context,
  image `b9cdb3d192c5`, and all 147 reachable third-party imports passing under
  the registered runtime privilege/protected-path checks.

The original `c632eedd` preflight used a desktop-changelog bypass; hosted CI
correctly rejected it. Commit `5e5112d3` adds the missing release note, and
`0c3cee98` isolates the release notification test target without weakening app
flags or normal test discovery. The latter passed all 92 selected preflight
checks without a changelog bypass, plus the full desktop runner and three real
optimized notification tests locally. PR #71 now tests that exact pushed SHA.

These results supersede the old unavailable-Docker/detector blockers, but do not
combine different SHAs into one final acceptance record. Reconcile the required
broad commands and hosted results on the final source before closing BL-003.
Live GCP and named-bundle acceptance remain BL-002 and BL-001 respectively.
