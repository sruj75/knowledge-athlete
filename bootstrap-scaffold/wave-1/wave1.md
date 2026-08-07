# Wave 1 Meta-Orchestrator Plan

## Mission

Coordinate the nine dedicated Wave 1 implementation agents. Each agent owns one
existing `S-XX` TDD plan and executes that plan's red-green cycles sequentially.

The user owns genuinely new product behavior and irreversible external actions.
Within the approved requirements, this Wave 1 meta-orchestrator autonomously
dispatches, sequences, and coordinates the nine slices. It is not a tenth
implementation agent and does not silently rewrite requirements or implement the
nine slices itself.

Wave 1 contains exactly these agents and plans:

| Agent | Slice | Plan |
|---|---|---|
| S-01 | Cloud Agent VM | [`s-01 tdd.md`](./s-01%20tdd.md) |
| S-02 | Wearable/Omi WAL | [`s-02 tdd.md`](./s-02%20tdd.md) |
| S-03 | Hosted STT providers | [`s-03 tdd.md`](./s-03%20tdd.md) |
| S-04 | Repository zombies | [`s-04 tdd.md`](./s-04%20tdd.md) |
| S-05 | Managed-Pi-only agent | [`s-05 tdd.md`](./s-05%20tdd.md) |
| S-06 | Apps/connectors/remote MCP | [`s-06 tdd.md`](./s-06%20tdd.md) |
| S-07 | Customer BYOK | [`s-07 tdd.md`](./s-07%20tdd.md) |
| S-08 | Account identity | [`s-08 tdd.md`](./s-08%20tdd.md) |
| S-09 | Telemetry/support | [`s-09 tdd.md`](./s-09%20tdd.md) |

Do not create S-08A/S-08B, a tenth subagent, or another Wave 1 TDD plan. If live
source facts require a delivery split, retain the same S-XX owner and record the
exact downstream handoffs in the deletion map and slice plan. Proceed
autonomously when this only repairs ownership of already-approved behavior;
escalate only when it would choose new product behavior or authorize a risky
live action.

## Required subagent model

Every S-01 through S-09 implementation subagent must be started explicitly with:

```text
model: gpt-5.6-sol
reasoning effort: xhigh (Extra High)
```

Do not rely on a workspace, user, or Conductor default to supply these values.
The meta-orchestrator records the model and reasoning effort in every dispatch
packet and status ledger. If that exact model or reasoning level is unavailable,
mark that slice blocked, continue other eligible dispatches, and report the exact
configuration blocker. Do not silently downgrade, substitute another model, or
let one subagent inherit a different configuration.

## Parallelism and one-commit delivery

At Wave kickoff, dispatch or queue one dedicated subagent for every S-01 through
S-09 plan, subject to available agent capacity. Dispatch authorizes immediate
intake, research, and dependency-independent local implementation. A dispatched
agent pauses only the exact cycle that needs an unmet dependency, unavailable
external input, or an earlier owner's shared-surface integration; do not confuse
a blocked cycle with a reason to withhold the agent itself.

Parallelism exists **between** eligible S-XX slices. Inside one S-XX, its TDD
cycles remain sequential: one RED -> minimum GREEN cycle at a time, then the
requirements-backed after-green simplification and review.

Each S-XX is delivered as exactly **one Git commit** made by its owning subagent:

1. Keep the slice changes uncommitted while executing its ordered TDD cycles.
2. Use the cycle evidence ledger and Conductor workspace state as intermediate
   checkpoints; do not create one commit per cycle.
3. Complete after-green simplification, real-path verification, full applicable
   checks, and the pre-review scope audit.
4. The S-XX subagent stages only its proven slice files and creates its single
   candidate S-XX commit. The meta-orchestrator does not commit on its behalf.
5. Run `engineering:code-review` against the pinned pre-slice baseline so its
   required three-dot `HEAD` diff and commit list contain that candidate commit.
6. Fix only same-slice review findings, rerun affected verification, and amend
   the same unpushed candidate commit. Do not create a review-fix commit.
7. Re-run both review axes after a material amendment, then prove the workspace
   is clean and the slice branch is exactly one commit ahead of its pinned slice
   baseline.

This Wave 1 one-commit rule supersedes any individual TDD plan wording about
committing each vertical cycle separately. The cycles remain separately tested
and evidenced, but they are combined into the one outcome-oriented S-XX commit.
No push, PR, merge, deploy, migration, or live cleanup is implied by that commit.

## Authority order

Authority is domain-scoped rather than one blanket precedence list:

1. [`../requirements-challenge.md`](../requirements-challenge.md) controls
   approved product behavior.
2. This `wave1.md` controls Wave 1 dispatch, model, parallelism, gate
   classification, scope containment, the S-08 ownership repair, and one-commit
   delivery.
3. [`../deletion-map.md`](../deletion-map.md) controls the remaining slice
   ownership, dependencies, and execution order.
4. The applicable `s-xx tdd.md` controls implementation details and ordered
   cycles except where this file narrows a plan-level gate to its exact affected
   cycle.
5. Live source at the pinned implementation baseline controls current codeflow
   facts.
6. Research notes are evidence only; they do not override an approved product
   decision.

The meta-orchestrator may correct a proven factual reference or report a
conflict. It may not choose a new product behavior, broaden a deletion, weaken a
keep boundary, invent an API compatibility shell, or treat unresolved product
behavior as approved.

Before controlling Conductor workspaces or agents, read the bundled Conductor
skill completely:

`/Applications/Conductor.app/Contents/Resources/conductor-skill/skills/conductor/SKILL.md`

Each slice owner follows the implementation, TDD, and review workflow named in
its own plan. Before the first product test, each public seam must be traced to a
controlling IR decision or to existing retained behavior protected by that IR.
User input is required only when those sources leave a genuine new product choice
unresolved. The owner executes one RED -> minimum GREEN tracer at a time.
Existing green characterization tests are keep fences, not retroactive RED
tests.

## Mandatory skill workflow for every S-XX

Every implementation subagent must use the following skills as an integrated
workflow. Mentioning them in a plan is not enough; the subagent records each
invocation and result in its slice evidence.

### 1. Start with `engineering:implement`

Invoke
[`engineering:implement`](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/implement/SKILL.md)
with the exact `s-xx tdd.md` as the implementation specification and the pinned
slice baseline as execution context. This is the mandatory wrapper for the
slice, not an optional convenience.

While implementing, follow its feedback contract:

- use `engineering:tdd` at the requirements-backed seams;
- run focused typechecking and individual test files regularly;
- run the complete applicable component suite once at the end;
- use `engineering:code-review` once the candidate slice commit exists; and
- leave the completed work committed on the current branch as the one S-XX
  commit.

### 2. Use `engineering:tdd` for every changed behavior

Invoke
[`engineering:tdd`](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/tdd/SKILL.md)
throughout the ordered cycles:

- no product test before its public seam is traced to the controlling IR or an
  existing retained-behavior keep fence;
- test behavior through the module's public interface, not private call order;
- mock only true external/system adapters, not the product's own internal
  modules;
- execute one failing test -> minimum passing implementation at a time;
- do not write all tests first; and
- keep refactoring and simplification outside RED -> GREEN, in the after-green
  review stage.

### 3. Use `engineering:codebase-design` only when needed

Invoke
[`engineering:codebase-design`](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/codebase-design/SKILL.md)
when the active plan or live source requires choosing, moving, narrowing, or
deepening a real module interface or seam. Use it for testability and ownership
clarity, not as permission to redesign retained behavior.

The conditional design pass must stay inside the current S-XX boundary:

- prefer a deep module with a small interface;
- make the interface the public test surface;
- accept real external adapters at the seam rather than mocking internal
  collaborators;
- do not introduce a hypothetical seam for one surviving adapter; and
- do not create compatibility layers, speculative abstractions, or a redesign
  of `KEEP AS IS` behavior.

If no real interface or seam decision is needed, record
`engineering:codebase-design: not needed` with one sentence explaining why.

### 4. Use `engineering:code-review` before finalizing the one commit

After implementation, after-green simplification, complete tests, scope audit,
and the owning subagent's single candidate commit, invoke
[`engineering:code-review`](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/code-review/SKILL.md).

The review contract is fixed:

- fixed point: the exact pinned pre-slice baseline, verified with
  `git rev-parse`;
- diff: `git diff <slice-baseline>...HEAD`;
- commit list: `git log <slice-baseline>..HEAD --oneline`, containing exactly
  the one candidate S-XX commit;
- Spec source: the exact `s-xx tdd.md`, its controlling IR sections, and the
  applicable Wave 1 ownership/handoff rules;
- Standards sources: root and applicable component `AGENTS.md`, `PRODUCT.md`,
  matched invariant/architecture guides, plus the review skill's smell baseline;
- two independent, parallel, read-only review subagents: one Standards axis and
  one Spec axis; and
- both review subagents also use `gpt-5.6-sol` with `xhigh` reasoning.

The two review reports remain separate. The implementation subagent and
meta-orchestrator classify every finding before action. Fix only same-slice
findings. Hand other-slice findings to their exact S-XX owner. If same-slice
fixes change code, rerun affected tests, amend the same unpushed candidate
commit, and repeat both review axes when the diff changed materially.

The temporary Standards and Spec reviewers are review-only helpers. They do not
become new S-XX owners, do not receive TDD plans, do not edit code, and do not
change the fixed total of nine Wave 1 implementation subagents.

## Verified planning baseline

The Wave 1 planning audit established the following at document creation:

- `python3 bootstrap-scaffold/validate-requirements-ledger.py` passes with 714
  indexed rows, 714 detailed sections, and every row reviewed.
- The nine plans cover every Wave 1 primary IR assignment in the deletion map.
- The supplemental source pass added IR-938 through IR-941. Wave 1 S-06 owns the
  complete external task-export deletion; S-04 owns the nested install-workflow
  zombie and two no-caller packaged media files; S-04 protects the universal
  libwebp cache for its later IR-939/S-29 release owner.
- Direct Limitless hardware support is an S-02 deletion under IR-014. S-06 owns
  only the separate hosted Limitless ZIP importer under IR-824.
- S-05's caller audit resolved both `omi-tools-stdio` and
  `LocalAgentAPIServer` for deletion. The retained Pi tool path is
  `pi-mono-extension -> OMI_BRIDGE_PIPE -> ChatToolExecutor`.
- S-01 deletes only the VM overlap of IR-003/IR-011. S-11 owns normal Chat
  backend-journal removal and S-15 owns the complete shared cloud screen-history
  deletion.
- S-05 owns moving retained Ask Mode into Advanced AI Setup while removing the
  old AI Chat Settings entrance. S-21 later verifies shell/search residue; it
  must not repeat or redesign the move.
- S-06 preserves existing Memory/Task/Conversation behavior for their later
  local-authority slices. It does not claim those migrations as Wave 1 work.
- S-09 protects local Rewind while deleting Crisp. It leaves the exact
  non-Crisp cloud screen-history remainder to S-15 and must not call that cloud
  synchronization retained.
- S-08 contains a real roadmap conflict resolved by the Wave 1 ownership repair
  below. Dispatch it normally and gate only the affected cycles.

Re-run the ledger validator and re-read every referenced live IR at Wave kickoff
and whenever the requirements document changes. A passing structural validator
does not prove narrative summaries are semantically current.

## Decision and safety boundary

Once the user asks to execute this Wave 1 plan, the meta-orchestrator
autonomously:

- dispatches or queues all nine S-XX agents and sequences their eligible work;
- derives public test seams from the controlling IRs and retained behavior;
- resolves implementation, module, test, shared-file, and ownership-handoff
  choices that preserve those approved product decisions;
- performs read-only discovery, local edits, local tests, named-development-bundle
  verification, review, and local slice commits; and
- advances code-complete slices without asking for ceremonial approval.

User input is required only for:

- a genuinely new or reopened product behavior not resolved by the authority
  order;
- a legacy-data transition that chooses loss, purge, tombstone, recovery, or
  another user-visible retention outcome;
- external project/account identifiers or secret locations that cannot be
  discovered from the owned environment;
- a released-API transition when the approved requirement and repository policy
  do not determine a safe path; and
- any push, PR, merge, deploy, production migration, live service/secret
  deletion, queue drain, data purge, or other hard-to-reverse external action.

The meta-orchestrator and slice agents must:

- never rename their current branches;
- never edit Windows or a Windows-only control;
- preserve user-owned and unrelated worktree changes;
- never stop, restart, or test against the production Omi macOS bundles;
- use uniquely named development bundles for real-path checks;
- never put a secret into Git, a plan, a log, a prompt, or a test fixture;
- perform read-only inventory before any live mutation;
- request fresh user authorization for every push/PR/merge/deploy, production
  migration, service deletion, secret deletion, queue drain, data purge, or
  other hard-to-reverse operation; and
- distinguish repository code closure from operational cloud closure.

## Initial dispatch ledger

This is the dispatch posture at plan creation. Recheck it at kickoff rather than
assuming it stayed current. `DISPATCH` means create or queue the agent and run
intake now; a per-cycle gate can pause one change without preventing dispatch or
unrelated safe cycles.

| Slice | Dispatch | Implementation boundary at intake |
|---|---|---|
| S-01 | **DISPATCH** | Preserve its requirements-backed seams. If the restored baseline exposes a real released-client conflict, pause only that cycle. Live VM/GCE/GKE/GCS/Firestore/IAM decommission remains a separate user-authorized action. |
| S-02 | **DISPATCH** | Preserve its requirements-backed seams. Direct Limitless hardware is inside S-02. Live wearable resource/data cleanup remains a separate user-authorized action. |
| S-03 | **DISPATCH** | Reconcile the IR-228 copy wording, `stt_service` ownership/removal timing, and one-element provider-order configuration against the authority order. Proceed when existing decisions determine the result; pause only a genuinely unresolved product behavior. |
| S-04 | **DISPATCH** | Preserve the requirements-backed public CLI seam, present Mac/backend guards, mixed workflow's retained T0 job, and universal libwebp handoff. Delete the nested install-workflow contract and two no-caller media files. Do not touch Windows or implement S-29's future owned Codemagic file. |
| S-05 | **DISPATCH** | Preserve its requirements-backed seams and the resolved deletion of stdio plus port 47778. Keep `OMI_BRIDGE_PIPE`, Pi, Agent Pills, Ask Mode behavior, and port 47777 automation. |
| S-06 | **DISPATCH** | Derive the released-OpenAPI endpoint sunset from the approved route deletions and existing compatibility policy. Pause only an endpoint-removal cycle for which those authorities provide no safe answer. |
| S-07 | **DISPATCH** | Perform read-only cardinality inventory first and continue deterministic managed-only work. Pause the legacy `users.byok` / `blocked_byok` / `requires_byok` transition and any write migration until the exact retention/requeue policy and live authorization exist. |
| S-08 | **DISPATCH** | Use the narrow Wave 1 ownership repair below. Proceed through requirements-backed fences and safe local removal cycles. Owned Firebase/Apple/Google/backend values gate only configuration and real-service proof; an unresolved auth-invariant or released-onboarding-API conflict gates only its affected cycle. |
| S-09 | **DISPATCH** | Begin intake and identity-independent observability work. Its identity attach/detach cycle waits for S-08's canonical seam. Owned PostHog, Sentry, LangSmith, and GCP values gate only their configuration and real-service proof; S-27 may retain later Cloud Logging retention proof. |

Dispatch and local implementation do not authorize push, merge, deploy,
migration, or decommission.

## S-08 Wave 1 ownership repair

Do not hide this conflict in implementation details.

The deletion map originally placed the complete S-08 postcondition in Wave 1,
but the source-grounded S-08 plan proves that:

- complete local Export My Data needs the final S-10 through S-14 local owners;
- deletion-worker pruning needs S-18, S-23, and S-24 to retire their writers and
  data safely;
- task retargeting and queue/IAM/region ownership need S-25 and S-27; and
- making S-08 depend on those later slices creates cycles because S-23/S-27 and
  S-09 already need S-08 identity semantics.

Wave 1 therefore adopts the narrow S-08 tranche as an ownership repair, not as a
new product decision:

- S-08 owns auth/session fences, owned identity configuration when inputs exist,
  onboarding-record removal, deletion-reason removal, and explicit downstream
  handoff contracts.
- S-10 through S-14 own complete local export readers; S-18, S-23, and S-24 own
  rejected-provider/data cleanup; S-25 owns task retargeting; and S-27 owns the
  queue/IAM/region foundation and live validation.
- The meta-orchestrator records those acceptance handoffs in the deletion map
  and S-08 plan before the affected RED. This bookkeeping preserves the approved
  IR outcomes and does not create S-08A/S-08B, another agent, or another plan.

Dispatch S-08 and S-09 at kickoff. S-08 progresses through its safe tranche;
S-09 progresses through identity-independent work and waits only at the exact
identity-coupled cycle until S-08 publishes the canonical seam. If live source
proves that this repair would change product behavior rather than ownership,
pause that affected cycle and surface the exact new product choice.

## Preferred Wave 1 execution order

Parallel development is allowed only when there is no dependency or shared-owner
conflict. Nine dedicated agents do not imply nine simultaneous writers.

### Stage 0 — pin and protect the wave

The meta-orchestrator records:

- freshly fetched `origin/main` SHA;
- the wave integration baseline SHA;
- each workspace/branch and clean-or-dirty status;
- existing user-owned changes;
- current requirements-validator output;
- plan status, controlling-IR/public-seam evidence, and any exact user-only gate;
  and
- the shared-file lease ledger below.

If agents start from different baselines, stop and normalize the dispatch plan
before code changes. Never silently rebase or discard another workspace's work.

### Stage 1 — make repository feedback usable

Run S-04 first. It removes impossible absent-tree controls and repairs the
retained preflight/check selection. Integrate or otherwise publish its exact
baseline to the remaining slice workspaces before their repository-control
closure cycles.

S-04 must leave S-01/S-02/S-03 product-specific runtime entries for their owning
slices, preserve the mixed desktop/backend T0 self-check, and leave fresh
Codemagic plus universal-libwebp ownership to S-29. Its exact hosted
conversation/memory parity artifacts remain handoffs to S-10/S-12.

### Stage 2 — ready independent product boundaries

After S-04's baseline is available, S-01, S-02, and S-05 may work in parallel
on disjoint product owners. Their shared manifest/router/settings edits still
integrate in the lease order below.

- S-01 closes cloud Agent VM/proxy/mirroring only.
- S-02 closes every direct wearable adapter, Omi WAL, and wearable ingestion.
- S-05 closes alternate agent entrances and leaves one managed-Pi path.

### Stage 3 — provider and external-product deletions

- S-03 begins after intake and resolves planning wording against the authority
  order; only a genuine remaining product conflict pauses its affected cycle.
- S-07 begins with read-only inventory and deterministic managed-only work.
  Integrate S-03's Deepgram/provider changes before S-07 removes customer-key
  propagation from the same STT surfaces. Pause only the legacy-data transition
  or live migration that needs user input.
- S-06 begins after intake, then integrates S-05's private bridge boundary and
  S-02's direct-wearable boundary before its shared deletions so it cannot
  preserve the wrong transport or hardware adapter. Follow the approved route
  decisions and existing compatibility policy; pause only an affected endpoint
  cycle if they truly conflict. IR-938's external
  task OAuth/export, candidate integration outbox/drain machinery, and Apple
  Reminders sync delete in the same S-06 connector cycle while ordinary local
  Tasks and candidate acceptance stay protected for S-13.

### Stage 4 — identity, then observability

- Dispatch S-08 on the Wave 1 ownership repair above and dispatch S-09 for its
  identity-independent cycles.
- Once S-08 publishes the canonical account/sign-in/sign-out/account-switch
  seam, S-09 may adapt identity attachment and detachment around it.
- S-09 may not turn the PostHog preference into a Sentry, local diagnostics, or
  LangSmith master switch.

### Stage 5 — integrated closure

Run the integrated retained paths, component suites, preflight, residue
classification, independent review, and operational handoff audit. Report two
separate milestones:

- **Wave 1 code-complete:** requirements-authorized repository changes and local
  real-path verification are complete.
- **Wave 1 fully closed:** every required live migration/decommission has also
  received user authorization and verified completion, or the user explicitly
  accepts a named later operational owner.

Do not report “Wave 1 complete” while silently carrying an unauthorized migration,
active rejected service, unknown legacy-data population, or unresolved
user-only decision.

## Shared-owner and integration ledger

The meta-orchestrator keeps this ledger current. A later slice rebases or merges
the already-integrated owner before editing the same surface. A lease is
coordination, not permission to alter another slice's behavior.

| Shared surface | Integration order / owner rule |
|---|---|
| `.github/checks-manifest.yaml`, preflight, absent-tree workflow routing | S-04 first. Later slices remove only their now-exclusive entries: S-01 -> S-02 -> S-03 -> S-06 -> S-09. |
| `.github/workflows/desktop-backend-contracts.yml` and root conversation/memory fixtures | S-04 preserves the mixed workflow and retained T0 job. S-10 removes only hosted conversation parity cases/fixture/triggers; S-12 removes hosted memory parity cases/fixture/triggers, then removes the final `testing/contracts/` discovery-registry entry and updates its guard tests. |
| `desktop/macos/vendor/libwebp/**` | S-04 protects the current universal cache; S-29 re-owns its version/checksum/architecture/minimum-OS/signing/fallback release contract. |
| `backend/runtime_images.json`, deployment manifests and shared workflows | S-04 removes impossible owners first; product owners then integrate S-01 -> S-02 -> S-03 -> S-06 -> S-09. Never delete a shared service until its last accepted workload has an owner. |
| `backend/main.py`, `desktop_backend.py`, route policy, OpenAPI, generated non-Windows Swift | Integrate endpoint deletions sequentially: S-01 -> S-02 -> S-03 -> S-06 -> S-07 -> Wave 1 S-08 tranche -> S-09. Each slice regenerates from the source owner; no hand-edit of generated Swift. |
| Mac Settings/navigation/search and onboarding routing | S-05 owns agent settings/Ask Mode move; S-06 removes Apps/connectors/FDA/Automation; S-07 removes BYOK UI; the Wave 1 S-08 tranche owns account fields; S-09 owns analytics/privacy/support. Preserve later S-17/S-21 boundaries. |
| Pi/runtime/tool manifests | S-05 owns adapter/transport narrowing. S-06 removes rejected connector/calendar/KG tools only after consuming S-05. S-07 then removes BYOK propagation without changing Pi behavior. |
| STT policy, listen/voice-message contracts, provider env | S-03 owns hosted-provider collapse. S-07 follows for customer-key removal. S-16 later owns the wider transient-listen protocol and server-conversation cleanup. |
| Wearable versus Limitless import | S-02 deletes direct Limitless hardware with every wearable adapter. S-06 deletes only the hosted ZIP importer. Neither may use the other's surface as a keep fence. |
| Chat journal and screen history adjacent to S-01 | S-01 removes VM copies only. S-11 owns normal backend journal projection; S-15 owns shared Firestore/Pinecone/MCP screen history. |
| Auth identity and telemetry identity | Wave 1 S-08 identity/sign-out seam first, S-09 consumption second. No second Firebase observer or independent identity cache. |
| Live cloud inventory/decommission | The product slice inventories and proposes. Only the user authorizes mutation. S-23 through S-27 retain later shared data/service/platform owners. |

When an unexpected shared file appears, pause the affected cycle, name both
owners, and update this ledger before either agent edits it. Do not resolve a
conflict by leaving a compatibility alias or moving unrelated behavior into the
currently active slice.

## Scope containment — no slice drift

Each S-XX plan is an ownership fence for its whole lifetime: intake, RED/GREEN
implementation, simplification, code review, review fixes, final verification,
and the one slice commit. Finishing the named behavior does not authorize the
subagent to continue into an adjacent slice.

The meta-orchestrator actively audits scope at five checkpoints:

1. **Before implementation:** record the slice baseline, expected owners/files,
   allowed shared-file leases, protected adjacent slices, and exact
   `OUT OF SCOPE / DEFERRED` boundary.
2. **After every RED/GREEN cycle:** inspect the changed-file list and behavior
   diff from the slice baseline. Every change must map to the active plan, its
   named cycle, requirements-backed after-green simplification, or a leased
   shared-file row.
3. **Before the candidate commit and code review:** freeze feature scope and
   classify the complete uncommitted diff. Only then may the owning subagent
   stage its proven slice files and create the one candidate commit that the
   reviewers will inspect.
4. **After code-review fixes:** re-audit the entire baseline-to-HEAD diff before
   amending the same candidate commit. Review feedback is not permission to
   repair another S-XX, perform attractive cleanup, or follow a dependency into
   its owner.
5. **Before CODE_COMPLETE/CLOSED:** require zero unowned changes, exactly one
   final S-XX commit above the baseline, a clean worktree, and an exact handoff
   for every adjacent finding or surviving shared owner.

The meta-orchestrator must supervise these checkpoints; it may not accept a
subagent's “scope is clean” statement without evidence. Inspect the subagent
workspace/branch diff directly when accessible. If it is not directly
accessible, require the exact status, changed-file, stat, and scoped-diff output
before allowing the slice to advance. No running subagent may pass a required
checkpoint merely because other slices are busy in parallel.

At each checkpoint, use the pinned slice baseline and inspect at least:

```bash
git status --short
git diff --name-status <slice-baseline>
git diff --stat <slice-baseline>
git diff <slice-baseline> -- <changed-shared-file>
```

Before the candidate commit, those commands inspect the uncommitted changes
from the baseline. After the subagent creates or amends that commit, also prove:

```bash
git rev-list --count <slice-baseline>..HEAD
git log --oneline <slice-baseline>..HEAD
git status --short
```

The required result is one slice commit and a clean worktree.

A shared file does not make every behavior in that file part of the active
slice. The agent changes only the rows, branches, routes, symbols, tests, or
generated output required by its named boundary and leaves every other owner's
behavior intact.

Classify code-review findings before fixing them:

| Finding class | Required action |
|---|---|
| Same-slice correctness, test, safety, documentation, or simplification defect | Fix inside the current slice and rerun affected evidence before the one commit. |
| Defect or cleanup owned by another existing S-XX | Do not fix it here. Record the exact file/symbol/behavior and hand it to the meta-orchestrator for that owner. |
| Genuine new requirement or product-behavior conflict | Stop the affected cycle, explain it to the user in plain English, and wait for that product decision. |
| Ownership, sequencing, module, test, or handoff choice that preserves approved behavior | Resolve it autonomously, update the plan/ledger, and continue. |
| Unrelated pre-existing or user-owned change | Preserve it and exclude it from the slice diff, staging, and evidence. |

The repository's “leave it better” rule applies only when the small related
defect is inside the same approved S-XX boundary and can be verified there. A
problem belonging to another named slice is not an opportunistic same-commit
fix; it is a handoff.

If scope drift is detected, stop new edits immediately. Do not hide it in a
larger commit, relabel it as refactoring, stage it, or discard ambiguous or
user-owned work. Identify which edits were made by the current subagent, restore
only proven agent-owned out-of-scope edits to the slice baseline, rerun affected
current-slice tests, and send the unimplemented finding to its real S-XX owner.
The slice returns to `RUNNING` until the complete scope audit is clean.

## Slice state machine

Track every S-XX in exactly one state:

```text
RESEARCHED
  -> BLOCKED
  -> READY
  -> RUNNING
  -> COMMIT_READY
  -> REVIEW
  -> CODE_COMPLETE
  -> OPERATIONAL_PENDING (only when a separately authorized live action remains)
  -> CLOSED
```

- `BLOCKED -> READY` requires the named gate evidence. User input is additionally
  required only when the exact gate matches the decision and safety boundary
  above.
- `READY -> RUNNING` requires a pinned baseline, clean intake, dependency
  satisfaction, and shared-file lease.
- `RUNNING -> COMMIT_READY` requires every ordered TDD cycle to have its
  RED/GREEN evidence, after-green simplification, real-path/component checks,
  and a clean, fully classified uncommitted slice diff.
- `COMMIT_READY -> REVIEW` requires the owning S-XX subagent—not the
  meta-orchestrator—to stage only its proven slice files, create the one
  candidate commit, prove exactly one commit exists above the pinned baseline,
  and leave a clean worktree for the fixed-point review.
- `REVIEW -> CODE_COMPLETE` requires independent Standards and Spec Compliance
  review, classification of every finding, same-slice fixes amended into that
  same unpushed commit, affected checks and materially impacted review axes
  rerun, and final proof of exactly one scoped commit plus a clean worktree.
- `CODE_COMPLETE -> OPERATIONAL_PENDING` is allowed only when the plan explicitly
  separates safe repository work from a live migration/decommission.
- `CLOSED` requires the plan's acceptance criteria and handoff ledger. The meta
  agent cannot convert an unknown or unauthorized live action into “not needed.”

## Dispatch contract for each S-XX agent

Send each dedicated agent its exact plan path plus this packet:

```markdown
You own only S-XX for Wave 1.

Required execution configuration:
- model: gpt-5.6-sol
- reasoning effort: xhigh (Extra High)

Confirm both values in your intake response. If either value is not active,
stop before editing and report the mismatch.

Read, in order:
1. root and applicable component AGENTS.md files;
2. bootstrap-scaffold/requirements-challenge.md sections named by your plan;
3. bootstrap-scaffold/deletion-map.md operating rules and your S-XX entry;
4. bootstrap-scaffold/wave-1/s-xx tdd.md completely;
5. the `engineering:implement`, `engineering:tdd`, and
   `engineering:code-review` SKILL.md files named by wave1.md;
6. `engineering:codebase-design` when a real interface or seam choice is
   needed, otherwise record why it is not needed; and
7. the live source owners at the pinned wave baseline.

Before editing, report:
- branch/workspace, HEAD, origin/main, merge-base, and worktree status;
- active model and reasoning effort;
- plan state, controlling-IR/public-seam evidence, and any exact user-only gate;
- dependencies and shared-file leases;
- exact keep/adapt/delete/out-of-scope boundary;
- expected changed owners/files and adjacent S-XX boundaries you must not enter;
- baseline commands/results and any blocker.

Do not treat a plan-level BLOCKED label as a prohibition on dispatch or intake.
Research, requirements-backed characterization, and safe cycles may proceed.
Pause only the exact test or code change that depends on the named gate. Resolve
ownership, sequencing, module, test, and handoff choices autonomously when they
preserve approved behavior. If the remaining blocker is a genuine new product
choice, unavailable owned external input, or risky live action, report it
precisely and continue any unaffected work.

For each eligible cycle, execute one RED -> minimum GREEN at a time through the
public behavioral seams. Refactor/simplify only after the relevant deletion is green.
Keep the work uncommitted during these cycles. Record commands, intended
failure, passing result, changed owners, shared-file handoffs, real-path
evidence, and operational follow-up.

After every cycle, before the candidate commit, and after every review-fix pass,
compare the complete diff with this S-XX plan. Do not fix or clean up behavior
owned by another slice, even when a reviewer notices it. Report that exact
finding to the meta-orchestrator as a handoff. Code review does not expand your
scope.

After the TDD cycles, after-green simplification, final applicable suite, real
path, and pre-review scope audit, stage only this slice's proven files and
create exactly one candidate S-XX commit yourself. Run `engineering:code-review`
against the pinned baseline with separate Standards and Spec reviewers. Fix
only same-slice findings and amend this same unpushed commit; never add a review
fix commit. Rerun affected checks and both review axes after a material change.
Finally, report the finalized SHA, prove the branch is exactly one commit ahead
of the pinned baseline, and leave a clean worktree. Do not leave the
meta-orchestrator to make your commit and do not create per-cycle commits.

Do not rename the branch, edit Windows, touch production Omi bundles, push, open
a PR, merge, deploy, migrate production data, or delete live resources without
fresh user authorization.
```

The meta-orchestrator must not shorten this into “implement the plan.” Every
agent needs the authority order, current baseline, readiness gate, shared-owner
lease, and safety boundary.

## Evidence required from every TDD cycle and final slice commit

For each cycle collect:

| Evidence | Required record |
|---|---|
| Public seam | The user-observable contract exercised; never only private call order or source-string placement. |
| RED | Exact command, failing assertion/error, and why it failed for the intended missing behavior. |
| GREEN | Exact command and passing result after the minimum implementation. |
| Keep fence | Adjacent retained behavior and result. |
| Scope | Files/owners changed and any newly discovered shared owner. |
| Skills | `engineering:implement`, `engineering:tdd`, and `engineering:code-review` invocation/results; plus the `engineering:codebase-design` result when used or its one-sentence `not needed` record. |
| Commit | No per-cycle commit. Record the owning subagent's candidate SHA before review, every amendment after same-slice fixes, and the final proof that exactly one local S-XX commit remains above the pinned baseline. |
| Real path | Named development bundle, local backend, hermetic external fake, or other plan-required exercise. |
| Residue | Classified survivors: retained, historical, Windows, shared, generated, or exact later S-XX handoff. |
| Operations | No live action needed, or exact inventory plus user-authorization status. |

A compile-only result, a no-op compatibility service, a passing test that never
observed RED, or an unclassified grep result is not closure evidence.

## Meta-orchestrator review loop

For each slice:

1. Verify the branch diff is scoped to its S-XX plan and preserves unrelated
   user changes.
2. Compare every changed behavior with the exact controlling IR decision.
3. Check all seven action classes are honored: KEEP AS IS, ADAPT, DELETE,
   SIMPLIFY / OPTIMIZE AFTER, ACCELERATE AFTER, AUTOMATE LAST, and OUT OF SCOPE /
   DEFERRED. `none` is valid where the plan says `none`.
4. Verify one vertical RED/GREEN tracer at a time and that final simplification
   happened after green rather than inside RED.
5. Verify shared files used the agreed predecessor baseline and no other slice's
   behavior was silently absorbed.
6. Require focused checks, full applicable component suites, real user-path
   exercise, documentation updates, residue classification, and `git diff
   --check`.
7. After the owning subagent creates its one candidate commit, require the
   slice plan's independent Standards and Spec Compliance review; classify
   every finding as same-slice, another S-XX, a new decision, or
   unrelated/user-owned before any fix is made.
8. After review fixes, re-run the changed-file and behavior ownership audit from
   the original slice baseline. A clean reviewer result does not prove a scoped
   diff.
9. Verify every other-slice finding has an exact handoff and was not partially
   implemented by the current subagent.
10. Verify the subagent amended same-slice review fixes into the original
    unpushed candidate rather than adding commits, then prove exactly one final
    slice commit remains, the worktree is clean, and the commit contains no
    other agent's or user's changes.
11. Record code closure and operational closure separately.

If an agent discovers that a plan's public seam is wrong, compare it with the
authority order first. When one path preserves the approved behavior, update the
plan and continue autonomously. Stop only the affected cycle when a genuine new
product behavior remains unresolved; show the user the current codeflow, the
conflicting requirement, the choices, and a plain-English recommendation. Ask no
more than three or four related product decisions at a time.

## Wave status report

Use this compact report after every material transition:

```markdown
Wave 1 baseline: <sha>

| Slice | State | Last green cycle | Commit/branch | Blocker or next action |
|---|---|---|---|---|
| S-01 | ... | ... | ... | ... |
...
| S-09 | ... | ... | ... | ... |

Shared-file lease: <owner/surface>
Model/reasoning audit: <S-XX = gpt-5.6-sol/xhigh>
Skill audit: <implement/TDD/review evidence; codebase-design used or not-needed reason>
Scope audit: <checkpoint/result and exact S-XX handoffs>
Commit audit: <S-XX owner-created commit SHA; exactly one above slice baseline>
Ready for user review: <slices>
User-only decisions needed next: <exact unresolved product/data/external choice or none>
Operational approvals pending: <exact resources/actions or none>
```

Do not bury a blocker in a long implementation summary. Lead with what is ready,
what is blocked, why it matters, and the exact next action. Do not imply that
ordinary dispatch, test seams, sequencing, or ownership bookkeeping needs user
approval.

## Wave 1 closure checklist

- [ ] Requirements ledger revalidated at the final baseline.
- [ ] Exactly nine S-XX agents used exactly nine TDD plans.
- [ ] Every S-XX subagent ran with `gpt-5.6-sol` and `xhigh` reasoning, recorded at dispatch and intake.
- [ ] Every S-XX recorded `engineering:implement`, `engineering:tdd`, and `engineering:code-review` evidence, plus `engineering:codebase-design` evidence or its explicit `not needed` reason.
- [ ] Every public seam was traced to a controlling IR or retained-behavior keep fence before its first product test.
- [ ] The S-08 Wave 1 ownership repair and downstream handoffs were recorded.
- [ ] Shared-file integration order and every handoff were honored.
- [ ] Scope was audited before implementation, after every RED/GREEN cycle, before review, after review fixes, and before commit/closure.
- [ ] Every review finding outside the active slice was handed to its exact S-XX owner instead of being implemented opportunistically.
- [ ] Every final slice diff contains zero unowned behavior or unexplained file changes.
- [ ] Each S-XX owning subagent created one candidate commit before review and finalized that same commit by amendment; exactly one commit remains and no meta-agent, per-cycle, or review-fix commits exist.
- [ ] S-01 removed VM-only copies without consuming S-11/S-15 work.
- [ ] S-02 removed every direct wearable adapter, including Limitless.
- [ ] S-03 left Mac-local Parakeet and managed Modulate working.
- [ ] S-04 left a runnable retained Mac/backend repository control plane.
- [ ] S-05 left one managed-Pi bridge and removed alternate entrances.
- [ ] S-06 removed external products without claiming later local-authority work.
- [ ] S-07 removed customer keys without stranding legacy work.
- [ ] The Wave 1 S-08 identity tranche and all downstream handoffs are proven.
- [ ] S-09 re-owned retained observability without coupling unlike consent systems.
- [ ] Every slice completed its ordered RED/GREEN evidence and after-green simplification.
- [ ] Focused tests, full applicable suites, preflight, real paths, docs, and classified residue are recorded.
- [ ] Independent Standards and Spec Compliance reviews are resolved.
- [ ] No Windows edit, production Omi-bundle action, compatibility shell, unowned TODO, secret, or unrelated user change landed.
- [ ] Code-complete and operationally-closed status are reported separately.
- [ ] No push, PR, merge, deploy, migration, or destructive live cleanup occurred without its own user authorization.
