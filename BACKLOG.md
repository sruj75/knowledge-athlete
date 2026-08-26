# Backlog

This file owns work that the product owner has intentionally deferred. An open
entry is not accepted, waived, or silently treated as green. It names the point
at which the work becomes mandatory again and the evidence required to close it.

## BL-001: Final all-waves provider and continuity qualification

**Status:** OPEN — deferred on 2026-08-26 by explicit product-owner decision

**Run when:** every deletion-map wave has been implemented, before the final
all-waves closeout or any release claim

**Next-wave effect:** does not block starting S-26 or S-28, provided they include
the complete Waves 3–4 repair tree

### Why this is deferred

The Waves 3–4 repository repairs and local acceptance are strong enough to
continue sweeping later vertical slices. The remaining rows require approved
non-production provider credentials and a verified deployed development
identity that were not available. The offline echo provider can prove lifecycle
mechanics, but it cannot truthfully prove that a real provider remembers and
recalls earlier context.

This scheduling decision does **not** close the combined Waves 3–4 closeout and
does **not** relax its original acceptance contract. It moves the unavailable
live qualification to one explicit gate at the end of all waves.

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
2. With approved non-production credentials, run the real
   OpenAI/Gemini/Auto/failover, language, reconnect, and tool rows.
3. Run the live-provider continuity path from typed turn, through physical PTT,
   to blind recall. An echo/fake response is not a pass.
4. With a verified development deployment identity, run the required
   provider-mint/deploy-inline and direct-provider probe without exposing tokens
   or provider secrets.
5. Record the exact SHA, commands, manifests, and outcomes in the final
   all-waves closeout and its PR record, while continuing to link every original
   per-slice acceptance record.

If credentials or deployment identity are still unavailable, or any row is red,
BL-001 and the combined Waves 3–4 closeout stay open. Later-wave implementation
may continue, but the final all-waves closeout and release claim may not.

## BL-002: S-25 verified live-resource inventory and operational handoff

**Status:** OPEN — repository inventory exists; live classifications remain
`unknown`

**Run when:** after every deletion-map wave is implemented and before any live
resource decommission or operational-closure claim

**Next-wave effect:** does not block repository implementation of later slices

The sanitized S-25 inventory is recorded in
[`bootstrap-scaffold/wave-4/s-25 tdd.md`](bootstrap-scaffold/wave-4/s-25%20tdd.md#191-sanitized-live-resource-inventory-handoff--2026-08-26).
Finish this entry by using a verified GCP operator, environment, and project
identity to classify every retained, rejected, shared, already-absent, or
unknown resource. Any deploy, drain, deletion, IAM, secret, image, network, data,
or production mutation remains separately authorized work and must record
before/after and rollback evidence.

Run S-27's manual `foundation-readiness` mode first and retain its sanitized
read-only output. A matching inventory does not replace the separately
authorized behavioral and denial probes.

## BL-003: S-27 deferred broad verification

**Status:** OPEN — focused repository checks passed; broad host-dependent gates
were unavailable

**Run when:** the local host has enough free disk and a healthy container
runtime, and GitHub Actions can execute detector jobs; before the final
all-waves closeout

**Next-wave effect:** does not block repository implementation of later slices

At S-27 commit `2853357f`, focused tests and deterministic contracts passed, but
the locked full backend/Pyright lane could not be completed, Colima could not
run the backend image smoke, and PR #50 detector jobs failed before executing
any steps. Close this entry by running `backend/test-preflight.sh`,
`backend/test.sh`, `backend/scripts/typecheck.sh`, and
`make runtime-image-smoke SERVICE=backend` on one clean SHA, then recording
hosted checks that execute rather than fail at detection. Live GCP and
named-bundle acceptance stay owned by BL-002 and BL-001 respectively.
