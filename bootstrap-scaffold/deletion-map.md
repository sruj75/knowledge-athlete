# Mac v1 Simplification, Adaptation, and Deletion Map

## Purpose

This file turns the reviewed requirements in
[`requirements-challenge.md`](./requirements-challenge.md) into an executable,
dependency-ordered map.

It is **not** another requirements ledger, **not** a delete-everything list, and
**not** one ticket per IR. The 31 `S-XX` entries are stable implementation
slices. Each one has exactly one TDD plan containing a variable number of
sequential red-green cycles discovered during source-grounded planning.

The requirements ledger decides **what** the product keeps, deletes, or adapts.
This map decides **in what order** those decisions can safely be implemented
and what each `S-XX` plan is allowed to change.

Every `S-XX` plan applies the five-step algorithm to its approved boundary, and
each TDD cycle inside that plan handles one small, working vertical codeflow:

1. **Question every requirement:** already resolved by the inherited IRs, then
   rechecked against the live code before implementation.
2. **Delete:** remove only the explicitly rejected parts and processes.
3. **Simplify or optimize:** simplify the retained/adapted implementation only
   after deletion proves what still needs to exist.
4. **Accelerate cycle time:** shorten the measured edit/test/run/release loop for
   this slice after its correct shape is stable.
5. **Automate:** automate only stable, repeated work whose inputs, outputs, and
   failure behavior are now understood.

Deletion is one action class inside a slice, not the default action. `KEEP AS
IS` also means Step 3 has no authorization to redesign that behavior.

## Destination

Ship a macOS-first product with these boundaries:

- normal chat and the managed Pi agent run locally on the Mac;
- private product data is local-authoritative unless a reviewed requirement
  explicitly retains a cloud boundary;
- the one retained Python backend is narrowed to approved account, billing,
  quota, managed-model, transient STT, update, release, and operational work;
- retained cloud services use our Firebase, Google Cloud, Dodo Payments,
  Modulate, PostHog, Sentry, LangSmith, and other approved accounts;
- Omi wearable, per-user Agent VM, duplicate cloud data, rejected providers,
  connector products, and their control planes are gone; and
- Windows is ignored completely. It is not inspected, changed, repaired, or
  deleted during this macOS effort.

## Snapshot

- Requirements source: `bootstrap-scaffold/requirements-challenge.md`
- Ledger validation: **PASS — 714 indexed rows, 714 detailed sections, all
  reviewed**
- Snapshot time: **2026-08-07 11:24:34 IST**
- Source commit inspected: `f293b62603145af15ce230a230f88017dce95f4a`
- Scope of this file: planning only; no product code is authorized or changed
  by this map

The requirements ledger is being edited in parallel. Before implementing any
slice, re-read the live section for every referenced IR and run:

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py
```

If the live ledger disagrees with this snapshot, the live ledger wins and this
map must be refreshed before implementation continues.

## Decisions so far

- [`requirements-challenge.md`](./requirements-challenge.md) contains 714
  reviewed code-grounded product decisions. It is the decision authority; this
  map does not reopen them.
- Those decisions resolve into exactly 31 `S-XX` implementation slices and
  therefore exactly 31 TDD plans. The source cross-check in
  [`deletion-slice-research.md`](./deletion-slice-research.md) supplies planning
  evidence; it does not pre-decide the number of red-green cycles inside a plan.
- Local authority is established before cloud data/storage/compute is removed,
  and infrastructure is deleted only after its final workload disappears.

## Operating rules

1. **Question first, then delete.** A slice implements only decisions already
   reviewed in the requirements ledger.
2. **Classify every touched behavior.** Every `S-XX` TDD plan must contain an explicit
   table with `KEEP AS IS`, `ADAPT`, `DELETE`, `SIMPLIFY AFTER`, and
   `OUT OF SCOPE / DEFERRED`. An empty class is written as `none`; a missing
   class is not authorization to infer work.
3. **Trace the whole path.** Do not stop after deleting a screen or a Swift
   service. Follow every exclusive caller and dependency through the Python
   backend, storage, jobs, infrastructure, tests, configuration, and docs.
4. **Protect the keep boundary first.** Write or identify the small behavioral
   tests that prove the adjacent retained path before removing its sibling.
5. **Adapt before deleting cloud authority.** For local-authority migrations,
   first make the existing local implementation authoritative, migrate every
   caller, prove the behavior, and only then delete synchronization, remote
   storage, backend routes, and infrastructure.
6. **Apply Step 3 inside each vertical slice.** Once the retained/adapted path
   works and the rejected sibling is deleted, simplify the surviving design and
   remove exclusive duplication, stale fields, compatibility state, tests,
   config, and docs in the same PR. This is the five-step algorithm's
   simplify/optimize step, not generic cosmetic cleanup.
7. **Apply Steps 4 and 5 only after correctness.** Record any measured friction
   in the slice's edit/test/run loop. Accelerate it when the improvement is
   inside the slice and verifiable; automate only a stable repeated action. It
   is valid to write `none` when a small slice has no useful acceleration or
   automation work.
8. **Use the final cleanup only for proven residue.** The last cleanup may
   remove cross-cutting residue already made dead by closed owner slices. It may
   not perform a missing data migration, decide a product requirement, or hide
   a broken intermediate state.
9. **No compatibility shells.** Do not leave no-op services, deprecated aliases,
   duplicate adapters, dormant provider switches, or fake success responses.
10. **Delete exclusive support surfaces with their owner.** This includes tests,
   generated contracts, secrets, manifests, metrics, alerts, runbooks, and
   deployment workflows.
11. **Do not mix similarly named systems.** In particular:
   - `desktop/macos/agent/` and managed Pi are the retained local runtime;
   - managed Pi currently receives tools through
     `pi-mono-extension -> OMI_BRIDGE_PIPE -> ChatToolExecutor`;
   - `omi-tools-stdio` is a separate MCP process path whose completed S-05 caller
     audit found no retained production consumer; S-05 deletes it while keeping
     Pi's `OMI_BRIDGE_PIPE` tool path;
   - `DesktopAutomationBridge` is a retained test-only automation boundary;
   - `LocalAgentAPIServer` is a rejected production HTTP entrance for other
     local programs and belongs to a separate deletion slice; and
   - `desktop/macos/agent-cloud/` is a rejected orphan of the cloud Agent VM.
12. **Historical records are not live dependencies.** Changelog entries may keep
   old names when they accurately describe old releases.
13. **Windows does not exist for this audit.** A mixed search result is not
   permission to edit a Windows file or a Windows-only workflow.
14. **One implementation slice, one closure proof.** A slice is not done while
    an exclusive producer, consumer, route, collection, job, secret, manifest,
    test, or operational document remains live.

### Delivery boundary

- There is exactly one `s-xx tdd.md` plan per numbered slice. The number of
  red-green cycles inside the plan is discovered while planning that slice; the
  discarded 86-packet draft is not an execution list.
- The default delivery boundary is one named issue/PR per `S-XX`. Split delivery
  only when source evidence proves that one change cannot preserve a safe,
  independently verifiable working state. A split does not create another
  numbered slice or TDD plan.
- Dependency-independent slices may proceed concurrently. Cycles inside one
  `S-XX` plan remain sequential so each tracer bullet can respond to what the
  previous cycle established.

### What "vertical" means here

A vertical slice is **outcome-complete**, not **file-isolated**. It follows one
product behavior from its user entry point through Mac code, backend routes,
storage, jobs, infrastructure, tests, generated contracts, and docs, then proves
that the retained neighboring behavior still works. It does not imply that the
slice owns a unique set of files or can be implemented in any order.

Several slices legitimately meet at shared control planes such as
`backend/main.py`, route policy, OpenAPI and generated Swift, runtime-image and
deployment manifests, Mac navigation and Settings, managed-Pi tool manifests,
STT configuration, and Firebase identity. These are like shared plumbing:
different end-to-end product outcomes can still pass through the same trunk.
The shared surface is changed in owner order; it is not duplicated or divided
artificially by file.

Use these labels instead of treating every pause as a generic conflict:

| Label | Meaning | Required response |
|---|---|---|
| **Requirement decision** | Two approved requirements demand incompatible final behavior. | Stop the affected cycle and record one explicit product interpretation in the requirements ledger. |
| **Shared-surface order** | Multiple slices change different behavior in the same registry, contract, manifest, or runtime. | Integrate the earlier owner first; the later slice consumes that result and changes only its own behavior. |
| **Dependency** | A slice needs an authority or keep boundary established by another slice. | Run the predecessor first, or defer only the dependent cycle when the plan defines a safe earlier tranche. |
| **Released-contract gate** | Deletion would break an API or client contract already released to users. | Use an explicit version/sunset transition with migration evidence; do not add a fake compatibility shell or weaken the ordinary gate. |
| **Live-data / operation gate** | Deployed jobs, records, services, secrets, or traffic may still depend on the retiring path. | Inventory read-only first, choose and test the transition, and obtain the separately required authorization before the mutation or decommission. |

Finding one of these during source-grounded planning does not mean the vertical
slice design failed. Exposing the shared trunk or unsafe deletion before code is
removed is part of the regression protection. Stop only the affected cycle;
continue other safe work inside the slice when its plan preserves a working
intermediate state.

`Ready to start` means the plan has at least one safe, requirements-backed
repository cycle that can begin without guessing. It does not mean every later
cycle is unblocked, every live mutation is authorized, or the slice can already
be marked closed. A cycle-local gate pauses only the work that consumes its
missing decision, external input, or later-owner result.

### Required `S-XX` TDD plan

No `S-XX` implementation starts until its one TDD plan contains all of the
following and each public behavioral seam is traced to an authorizing IR or an
existing retained-behavior contract.

```markdown
## S-XX TDD Plan — One outcome-oriented name

Status: researched | blocked | ready to start | in progress | closed
Slice: S-XX
Wave: 1 through 6
Authorizing and protecting decisions: exact IR IDs
Depends on: exact S-XX slices

Postcondition: one sentence describing what works when this S-XX closes.

| Action | Exact behavior and source boundary |
|---|---|
| KEEP AS IS | Regression fences this S-XX may not redesign |
| ADAPT | Existing behavior whose authority/provider/ownership changes |
| DELETE | Step 2: complete named codeflow removed after the keep boundary is protected |
| SIMPLIFY / OPTIMIZE AFTER | Step 3: make the surviving implementation simpler only after deletion |
| ACCELERATE AFTER | Step 4: measured slice-local cycle-time improvement, or `none` |
| AUTOMATE LAST | Step 5: stable repeated work automated after the loop is understood, or `none` |
| OUT OF SCOPE / DEFERRED | Adjacent behavior this S-XX must not touch |

Current codeflow: real entry points, authorities, mixed seams, tests, manifests.

Public seams: user-observable interfaces to test. Trace each seam to an exact
authorizing decision or retained-behavior contract before its first test.

Ordered TDD cycles:
1. RED: one failing behavioral test at an agreed seam.
   GREEN: only the minimum implementation needed to pass it.
2. Repeat one vertical tracer bullet at a time; do not write every test first.

Review and simplify after green: Step 3 refactoring is a separate review stage,
not part of the red-green loop.

Verification: retained real path, network/offline boundary where relevant,
residue searches, component tests, docs, measured cycle-time evidence, and any
stable automation added last.
```

If a plan lacks any field, its `S-XX` remains a research item. A missing field is
not authorization to fill the gap with a guess during implementation.

## Dependency graph

The roadmap contains six dependency-ordered waves, 31 implementation slices,
and 31 TDD plans. Slices in the same wave may proceed concurrently only when
their TDD plans show no dependency or shared-owner conflict.

```text
WAVE 1 — independent removals and stable ownership boundaries
  S-01 cloud Agent VM             S-05 managed-Pi-only agent
  S-02 wearable/WAL               S-06 Apps/connectors/remote MCP
  S-03 hosted STT providers       S-07 customer BYOK
  S-04 repository zombies         S-08 account identity
                                  S-09 telemetry/support

WAVE 2 — make retained Mac behavior authoritative
  S-10 conversations/transcripts  S-13 tasks/goals
  S-11 Chat/Home                  S-14 Focus/Insights/proactive/profile
  S-12 memories                   S-15 Rewind cloud-copy removal
  S-16 transient cloud listen     S-17 narrowed onboarding/permissions
  S-18 Dodo billing/quota

WAVE 3 — reconnect retained cross-domain behavior to local owners
  S-19 PTT local grounding/tools
  S-20 fair-use local evidence and retained enforcement
  S-21 navigation/settings shell
  S-22 managed-model portfolio and transient compute

WAVE 4 — delete the cloud products that have lost their final callers
  S-23 rejected hosted products and product data
  S-24 hosted search/vector/object-data authority
  S-25 jobs, workers, duplicate services, and GKE control planes

WAVE 5 — collapse and re-own the surviving platform
  S-26 canonical Python backend and development harness
  S-27 Cloud Run/Redis/Firestore/GCS deployment foundation
  S-28 Mac storage namespace and installation identity
  S-29 build, signing, update, preview, and public/legal release system

WAVE 6 — truth and ship
  S-30 final product identity, copy, privacy, and legal truth pass
  S-31 end-to-end closure, cycle-time measurement, and automation
```

### Cross-slice integration constraints

These are source-ownership constraints, not an execution-control system. A
later slice changes only its own behavior on a shared surface and consumes the
already-integrated predecessor shape first.

| Shared surface | Required owner order |
|---|---|
| Repository checks, preflight, and absent-tree workflow routing | S-04 narrows the shared control plane first. S-01, S-02, S-03, S-06, and S-09 later remove only entries made exclusive by their own product deletions. |
| Mixed desktop/backend contracts | S-04 preserves the retained T0 job. S-10 removes the hosted-conversation cases and fixtures; S-12 removes the hosted-memory cases and the final discovery-registry residue. |
| `desktop/macos/vendor/libwebp/**` | S-04 preserves the current universal cache; S-29 owns its final provenance, architecture, signing, and rebuild contract. |
| Runtime images, deployment manifests, and shared workflows | Integrate S-04 before product-specific cleanup, then S-01 -> S-02 -> S-03 -> S-06 -> S-09. A shared service remains until its final retained workload has an owner. |
| Backend routes, route policy, OpenAPI, and generated non-Windows Swift | Integrate endpoint changes in the order S-01 -> S-02 -> S-03 -> S-06 -> S-07 -> S-08 -> S-09. Regenerate from the source contract; do not hand-edit generated Swift. |
| Pi runtime and tool manifests | S-05 narrows the retained transport before S-06 removes rejected connector/calendar/knowledge tools; S-07 then removes BYOK propagation without changing Pi behavior. |
| STT policy and provider configuration | S-03 removes hosted providers before S-07 removes customer-key propagation from the same surfaces. S-16 later owns the wider transient-listen protocol. |
| Wearable and Limitless paths | S-02 deletes direct wearable hardware, including direct Limitless support. S-06 deletes only the hosted Limitless ZIP importer. |
| Agent VM-adjacent journals and screen history | S-01 removes VM copies only. S-11 owns normal backend-journal removal; S-15 owns shared cloud screen-history removal. |
| Account and telemetry identity | S-08 publishes the canonical account/sign-in/sign-out seam before S-09 adapts identity attachment and detachment. |

Repository closure and live operational closure remain separate. Migrations,
decommissions, data deletion, deploys, and other external mutations follow the
authorization and safety rules in `AGENTS.md`.

### Wave 1 manual implementation order and stop points

For one human implementing Wave 1 sequentially, use this integration order:

```text
S-04 -> S-01 -> S-02 -> S-05 -> S-03 -> S-06 -> S-07 -> S-08 -> S-09
```

Start each slice from the already-integrated result of the previous slice. The
order protects shared controls first, then removes product-specific behavior,
then adapts identity and telemetry after their inputs are stable. It does not
authorize implementing past an open gate in the slice's TDD plan.

| Slice | Why it is in this position | Important stop point |
|---|---|---|
| **S-04** | Narrows repository checks, manifests, and absent-tree workflow routing before product slices edit those shared controls. | Do not delete a mixed Mac/backend check merely to make preflight green; classify its real owners first. |
| **S-01** | Removes the Agent VM before later runtime and route cleanup while preserving local managed Pi. | If the restored released OpenAPI contract proves a shipped client still needs a removed VM endpoint, stop the merge for an explicit contract-sunset decision. Live VM/resource decommission remains separate. |
| **S-02** | Removes wearable/WAL behavior before STT and connector cleanup touch shared jobs, images, and manifests. | Delete only wearable-owned behavior. Shared `backend-sync` or infrastructure remains until its final workload is gone; live cleanup is a separately authorized operation. |
| **S-05** | Establishes one retained managed-Pi runtime and private `OMI_BRIDGE_PIPE` tool path before S-06 and S-07 prune adjacent tools and credentials. | Do not proceed with an uncertain transport boundary: keep the verified Pi bridge while deleting only the separately proven-unused entrances. |
| **S-03** | Removes hosted STT providers before customer-key propagation is removed from the same STT surfaces. | The provider-copy decision is adopted: keep Local VAD Gate behavior and use “managed cloud transcription usage.” S-03 owns complete `stt_service` deletion and fixed-Modulate policy; revalidate those decisions at the pinned baseline. |
| **S-06** | Consumes S-05's retained Pi boundary, then removes Apps, connectors, public MCP, sharing, and their route/deployment residue. | Cycles 0-2 may start. Before Cycle 3 or another route-removal cycle, record never-released evidence or land the adopted release-level version/sunset predecessor with client migration proof. |
| **S-07** | Removes BYOK after S-03 and S-05 have stabilized the shared STT and Pi surfaces. | Legacy migration is structurally inapplicable: this unreleased fork owns no deployed users/jobs. Delete inherited readers/writers without reading or mutating upstream Omi data. |
| **S-08** | Publishes the canonical identity/session/sign-out boundary consumed by S-09 and later slices. | Start config-independent fences immediately in the plan's safe phase order. Owned-identity, invariant, and released-contract inputs gate only their named cycles; Cycles 6-9 still wait for later owners and authorizations. |
| **S-09** | Re-owns telemetry/diagnostics and removes rejected observability products without coupling their authorities. | Start the configuration-independent deletion phase after the S-08 keep fences. Owned projects and the canonical identity seam gate configuration/identity cycles and live closure; never guess their identifiers or secrets. |

At every stop point, record the missing decision or evidence in the active TDD
plan. Do not silently invent a compatibility path, weaken a guard, or declare
the slice closed. Resume from the same cycle after the gate closes, then apply
the shared closure contract below.

### TDD plan artifacts

Creating this map does not implement any slice. Each TDD plan remains a separate
source-grounded artifact.

Wave 1 has nine TDD plans:

```text
bootstrap-scaffold/wave-1/s-01 tdd.md
bootstrap-scaffold/wave-1/s-02 tdd.md
bootstrap-scaffold/wave-1/s-03 tdd.md
bootstrap-scaffold/wave-1/s-04 tdd.md
bootstrap-scaffold/wave-1/s-05 tdd.md
bootstrap-scaffold/wave-1/s-06 tdd.md
bootstrap-scaffold/wave-1/s-07 tdd.md
bootstrap-scaffold/wave-1/s-08 tdd.md
bootstrap-scaffold/wave-1/s-09 tdd.md
```

Later waves use the same one-plan-per-slice structure inside `wave-2/` through
`wave-6/` and together produce exactly 31 `s-xx tdd.md` files across `S-01`
through `S-31`.

The exact blocking edges and each slice's keep/delete boundary are recorded in
the complete slice register below. The current v1 provider choice is resolved:
retain Gemini Live and OpenAI Realtime with Auto, explicit switching, and
failover unless a later requirement deliberately reopens that decision.

## Shared closure contract

A keep/adapt/delete/simplify slice closes only when all of the following are true:

- the live ledger still authorizes the boundary;
- the complete caller and dependency inventory has been recorded;
- the retained neighboring behavior has focused behavioral coverage;
- every in-tree caller has moved to the retained path or has been deleted;
- exclusive UI, runtime, API, persistence, job, infrastructure, configuration,
  secret, metric, alert, test, fixture, generated contract, and doc surfaces are
  deleted;
- repository searches find no unexplained live reference to the retired
  product, endpoint, provider, collection, environment variable, or artifact;
- the relevant component suites pass;
- the real retained user path has been exercised; and
- product/component docs describe the new boundary without promising deleted
  behavior.

Passing a compile after replacing a service with a no-op does not satisfy this
contract.

---

## Detailed root slice briefs

### S-01 — Remove cloud Agent VM and local-database mirroring

**Type:** complete vertical deletion<br>
**Status:** repository Cycles 0-4 landed in `eb73915`; Wave 1 closeout removes
the inherited Agent-VM failure-class definition, while any separately claimed
live-cloud decommission remains explicitly gated<br>
**Authorizing decisions:** IR-001, the VM half of IR-002, and IR-934<br>
**Scope-partition decisions:** IR-003 belongs to S-11 and IR-011 belongs to
S-15; S-01 removes only their VM-mirroring overlap

#### Outcome

Signing in, onboarding, launching Home, sleeping, changing account owner, or
running low on memory never provisions or manages a per-user GCE VM and never
uploads or polls the Mac's local databases for that VM. Normal desktop chat,
managed Pi work, local tools, and local journals continue to work.

#### Current codeflow to remove

```text
Onboarding / signed-in Home warmup
  -> AgentVMService provision/status polling
  -> backend /v2/agent/provision and /v2/agent/status
  -> per-user GCE VM
  -> compressed omi.db upload
  -> AgentSyncService polls GRDB every 3 seconds
  -> VM /sync receives incremental rows
  -> agent-proxy routes remote/mobile WebSocket chat
  -> VM Python runtime queries copied SQLite
  -> Firestore/GCE/GKE/reaper/workflows operate the product
```

#### Keep boundary

- `desktop/macos/agent/`, its local Node kernel, and `omi-agentd.sqlite3`
- managed Pi foreground/background agent behavior and Agent Pill lifecycle
- Swift `ChatToolExecutor` and its retained local tools
- the verified private managed-Pi extension/bridge path; S-05 separately deletes
  the unused `omi-tools-stdio` process
- local SQL, semantic search, daily recap, Rewind, tasks, goals, memories, and
  other reviewed local tool behavior
- the local conversation journal and visible local turn projection
- `DesktopAutomationBridge`

This slice must not remove those surfaces merely because the rejected VM had
tools with similar names.

#### Delete boundary by layer

1. **Mac entry and lifecycle**
   - onboarding and Home provisioning triggers;
   - `AgentVMService.swift` and `AgentSyncService.swift`;
   - owner-change, sleep, and memory-pressure hooks used only for Agent sync;
   - VM status/provision client models, methods, settings, and UI state.
2. **Canonical backend bridge**
   - `backend/routers/desktop_agent_vm.py` and route registrations;
   - VM-only portions of `backend/routers/agent_tools.py`;
   - exclusive `agentVm` Firestore helpers, policies, schemas, and bindings.
3. **Remote runtime**
   - `backend/agent_vm/`;
   - `backend/agent-proxy/` and `backend/charts/agent-proxy/`;
   - VM reaper code and `backend/charts/agent-vm-reaper/`;
   - the incomplete `desktop/macos/agent-cloud/` snapshot.
4. **Operations and contracts**
   - VM/proxy image registration, workflows, deploy checks, secrets, service
     accounts, metrics, alerts, failure-class records, tests, fixtures, and
     live docs that have no surviving owner.
5. **VM-only copies of retained local data access**
   - VM copies of SQL/semantic/daily-recap tools;
   - AgentSync's screenshot-table mirror into the VM copy.

   General backend journal projection is S-11. Firestore/Pinecone/MCP
   screen-history persistence and retrieval is S-15. S-01 must hand those
   shared owners off rather than deleting or declaring them retained.

#### Vertical closure order

1. Lock the retained local chat + local tool path with focused tests.
2. Disconnect Mac provisioning and synchronization producers.
3. Remove backend provisioning/status/tool-bridge entrances and exclusive
   Firestore state.
4. Delete the VM, proxy, reaper, and orphaned cloud snapshot.
5. Remove deploy/config/observability/generated/test/doc residue.
6. Exercise normal chat, a local tool call, and a managed Pi background run.

#### Dependencies

None. The kept local runtime is already a separate path.

#### Unblocks

- accurate inventory of the canonical backend without VM-only routes;
- removal of VM image builds, GCE lifecycle permissions, proxy GKE resources,
  and VM Firestore state;
- later deletion of cloud product-data copies that no retained caller needs.

#### Technical checks before editing

- Separate shared helpers from VM-only branches in `agent_tools.py`.
- Find every source of `AgentSyncService.shared` lifecycle coupling.
- Find every runtime-image, deployment-policy, alert, and release check that
  names the VM, proxy, or reaper.
- Classify every screen-activity helper as VM-only or an exact S-15 handoff;
  never use S-01 to delete local Rewind or S-15's shared cloud-copy boundary.

#### Forbidden scope

- Do not delete or replace the managed Pi runtime.
- Do not delete local tools or the verified managed-Pi extension/bridge path;
  S-05 owns the already-decided deletion of the separate stdio path.
- Do not delete the test-only automation bridge.
- Do not bundle IR-922's `LocalAgentAPIServer` deletion into this slice; it is
  a separate external-local-access codeflow sharing some tools.
- Do not edit Windows.

---

### S-02 — Remove wearable devices, Omi WAL, and device-audio ingestion

**Type:** complete vertical deletion<br>
**Status:** repository code-complete and independently reviewed on 2026-08-14;
destructive live closeout remains separately gated, so operational closeout is pending<br>
**Authorizing decisions:** IR-012, IR-013, IR-014, IR-359, and IR-823

#### Outcome

The Mac records and transcribes only its approved Mac audio sources. It no
longer discovers, pairs with, reconnects to, decodes, controls, recovers audio
from, displays, updates, or ingests data from an Omi or third-party wearable.
No wearable frame or stored-audio file enters the Python backend.

#### Current codeflow to remove

```text
BLE discovery/pairing/device session
  -> device-specific connection + transport + codec
  -> live encoded frames OR device-storage/Wi-Fi recovery
  -> BleAudioService / BleAudioProcessor
  -> Omi WAL files and metadata under Application Support
  -> POST /v1 or /v2/sync-local-files
  -> async sync job + GET /v2/sync-local-files/{job_id}
  -> decode/VAD/STT/conversation cloud pipeline
  -> device UI, battery, button, storage, photo, and firmware surfaces
```

#### Keep boundary

- Mac microphone and system-audio capture
- meeting detection and the three-way System Audio mode
- continuous transcription through Mac-local Parakeet or managed Modulate
- PTT/realtime voice and manual microphone selection
- local `TranscriptionStorage` and normal `omi.db`/GRDB durability
- SQLite's ordinary `omi.db-wal` transaction file
- generic diarization and conversation-local manual speaker labels

The Omi WAL is a separate raw-device-audio subsystem. Its deletion must never
be implemented by disabling SQLite WAL or normal local transcription storage.

#### Delete boundary by layer

1. **Product and state entrance**
   - BLE audio-source cases, forced-cloud policy, device source labels, wearable
     button routing, device providers, pairing/reconnect/storage/photo UI, and
     settings or onboarding steps that exist only for direct devices.
2. **Device runtime**
   - `Desktop/Sources/Bluetooth/` device discovery, transports, connection
     implementations, sessions, command queues, battery/button/storage state;
   - `BleAudioService`, `BleAudioProcessor`, exclusive codecs and decoders;
   - wearable camera/photo and firmware-specific runtime branches.
3. **Local raw-frame durability**
   - the SwiftPM `OmiWAL` target and `Desktop/Sources/OmiWAL/`;
   - `Desktop/Sources/WAL/`, including local chunks, metadata, retry,
     reconciliation, Wi-Fi sync, storage sync, and their UI.
4. **Backend ingestion**
   - `/v1/sync-local-files`, `/v2/sync-local-files`, job polling, and internal
     sync-job execution;
   - exclusive upload staging, dedupe/content ledgers, queue branches,
     decoding, backfill/fresh dispatch, conversation persistence, device photo,
     and firmware APIs.
5. **Operations and contracts**
   - device/WAL route schemas, generated bindings outside excluded Windows,
     workers, schedules, secrets, metrics, tests, fixtures, docs, and deploy
     configuration with no retained caller.

#### Vertical closure order

1. Lock Mac microphone/system-audio transcription and local persistence with
   focused tests.
2. Remove device entry points and BLE source routing from the Mac state graph.
3. Delete direct-device transports, codecs, services, UI, and Omi WAL storage.
4. Delete the upload/poll endpoints and their exclusive backend processing.
5. Remove jobs, configuration, contracts, tests, telemetry, and docs.
6. Exercise continuous Mac transcription, local persistence, and PTT.

#### Dependencies

None for the product deletion. If a shared backend-sync deployment still owns a
different retained workload, delete only this workload now and leave final
deployment deletion to the later backend re-inventory.

#### Unblocks

- removal of wearable ingestion queues, raw-file staging, and job polling;
- removal of Bluetooth permissions/capabilities and device support burden;
- a much smaller transcription state machine with only Mac audio sources;
- an evidence-based decision on whether any shared sync worker remains.

#### Technical checks before editing

- Inventory every `DeviceProvider`, `.bleDevice`, device-type, and storage-sync
  use before deleting shared-looking models.
- Prove that codec code has no retained Mac-file or PTT caller.
- Split wearable sync work from any unrelated job sharing the same deployment.
- Verify that `/sync-local-files` has no general Mac audio-import caller.

#### Forbidden scope

- Do not delete continuous transcription because the wearable producer is gone.
- Do not delete Mac microphone/system audio, PTT, or retained cloud STT.
- Do not delete GRDB or SQLite WAL durability.
- Do not remove a shared backend deployment until all of its workloads have
  independent decisions.
- Do not edit Windows.

---

### S-03 — Remove hosted GPU Parakeet and every Deepgram branch

**Type:** provider deletion plus routing cleanup<br>
**Status:** ready to start; the provider seams and requirements interpretations
are adopted, with live Modulate exercise retained as closure evidence<br>
**Authorizing decisions:** IR-019, IR-062, IR-887, IR-888, and IR-889

#### Outcome

The only continuous-STT engines are Mac-local Parakeet and managed Modulate.
The backend no longer runs a GPU transcription service, knows a Deepgram
provider mode, carries provider credentials for either rejected branch, or
maintains an emergency inactive chart.

#### Current provider boundary

```text
KEEP
  Mac-local Parakeet
  managed Modulate Velma-2

DELETE
  canonical backend remote-Parakeet client/routing
    -> separately deployed backend/parakeet GPU service
    -> Helm/GKE/image/workflow/capacity/monitoring control plane

  public managed-Deepgram compatibility
  optional self-hosted Deepgram streaming
    -> backend/charts/deepgram-self-hosted
```

#### Keep boundary

- the Parakeet engine embedded in the Mac app
- managed Modulate in its reviewed live, PTT, and prerecorded roles
- `/v4/listen` as transient managed STT, not cloud conversation authority
- provider-neutral audio framing, transcript events, fallback telemetry, and
  generic within-conversation speaker labels used by Modulate
- PTT/realtime behavior not specifically owned by the deleted providers
- the later model decision between Gemini Live and OpenAI Realtime remains
  separate

#### Delete boundary by layer

1. **Hosted Parakeet service**
   - `backend/parakeet/`, its model downloads, GPU worker, batch/streaming
     engines, VAD/diarization, capacity admission, health, and metrics;
   - `backend/charts/parakeet/`, `gcp_parakeet.yml`, GPU test workflow, image,
     secrets, alerts, dashboards, runbooks, and service-specific tests.
2. **Canonical backend Parakeet client**
   - remote-Parakeet client and provider-order branches;
   - `HOSTED_PARAKEET_API_URL`, admission/capacity fallback, remote model tokens,
     runtime image entries, and exclusive tests/config/docs.
3. **Managed Deepgram compatibility**
   - SDK/client, provider aliases, model names, keys, endpoint configuration,
     disabled selection branches, BYOK residue, tests, benchmarks that exist
     only to compare the retired provider, and live documentation.
4. **Self-hosted Deepgram product**
   - `backend/charts/deepgram-self-hosted/` in full, including bundled charts,
     model/license credentials, GKE setup, monitoring, samples, and docs;
   - self-hosted routing flags and non-public endpoint handling in the backend.
5. **Routing cleanup**
   - collapse retained provider policy to local Parakeet versus managed
     Modulate without inactive compatibility tokens or a third-provider slot.

#### Vertical closure order

1. Lock the reviewed local-Parakeet and managed-Modulate behaviors with focused
   tests, including the main error/fallback path.
2. Remove hosted Parakeet and Deepgram from canonical provider selection.
3. Delete backend clients, aliases, credentials, and configuration.
4. Delete both self-operated service trees and their control planes.
5. Remove service-specific tests, benchmarks, monitoring, manifests, and docs.
6. Exercise one Mac-local transcript and one managed-Modulate transcript; also
   exercise the retained PTT path affected by provider cleanup.

#### Dependencies

None. The retained serving choices already exist. Coordinate only with the
separate BYOK deletion so each shared key/settings occurrence has one owner.

#### Unblocks

- removal of all GPU cluster cost and operations for STT;
- a two-engine transcription policy instead of several dormant choices;
- deletion of Parakeet/Deepgram runtime images, secrets, alerts, and workflows;
- simpler local development and production configuration.

#### Technical checks before editing

- Distinguish every Mac-local `Parakeet` reference from remote hosted Parakeet.
- Identify provider-neutral helpers before removing provider-specific code.
- Trace PTT comments and fallbacks that still say Deepgram but now execute a
  retained path; rewrite behavior and tests, not only labels.
- Decide ownership of each Deepgram developer-key/BYOK occurrence with the
  broader IR-062 slice so it is not deleted twice or left behind.

#### Forbidden scope

- Do not delete Mac-local Parakeet.
- Do not replace Modulate with another self-hosted engine.
- Do not redesign the entire PTT or realtime voice lifecycle.
- Do not make the deferred Gemini Live versus OpenAI Realtime model decision.
- Do not edit Windows.

---

### S-04 — Remove impossible controls and unowned repository zombies

**Type:** repository/control-plane deletion and narrowing<br>
**Status:** closed on 2026-08-14; retained-surface verification complete with the full-preflight and named-bundle smoke waivers recorded in the S-04 TDD plan<br>
**Authorizing decisions:** IR-009, IR-010, IR-892, IR-897, IR-935, IR-940, and IR-941

#### Outcome

Repository preflight and CI describe the source trees that actually exist. They
do not fail while trying to resolve missing mobile, web, firmware, SDK, CLI,
plugin, MCP, docs-app, or public-build products. Mac and canonical-backend
controls remain intact, unowned source packages with no retained build/runtime
consumer are gone, and Windows remains completely untouched.

#### Current broken controlflow

```text
make preflight / CI workflow selection
  -> .github/checks-manifest.yaml and workflow triggers
  -> runtime/public-build contracts
  -> commands and Dockerfiles under absent source trees
  -> manifest resolution fails before useful retained checks can run
```

Verified absent product trees include `app/`, `web/`, `omi/`, `omiGlass/`,
`plugins/`, `sdks/`, `mcp/`, and `docs/`. The missing root `codemagic.yaml` is
different: IR-892 requires adding an owned Mac build/release definition later,
not deleting the retained need for it.

#### Keep boundary

- macOS source, tests, packaging, signing, notarization, qualification, update,
  preview, Beta, Stable, rollback, and release controls selected in the ledger
- canonical Python backend build, test, deploy, WIF, and retained service checks
- repository-wide guardrails that operate on present source
- the adapted local/offline backend harness from IR-891
- the small external public/legal site requirement from IR-896
- the future owned `codemagic.yaml` implementation from IR-892
- the universal `vendor/libwebp` release cache from IR-939, protected for S-29
- all Windows files and Windows-only controls, without evaluating them

#### Delete or narrow boundary

1. **Impossible workflows**
   - workflows exclusive to absent mobile/web/firmware/SDK/CLI/plugin/MCP/docs
     source and their exclusive composite actions.
2. **Impossible manifests**
   - absent-image entries in `backend/runtime_images.json`;
   - absent Dockerfiles, canaries, and targets in
     `config/public-build-contract.json` and related values;
   - triggers and commands in `.github/checks-manifest.yaml` that can only
     address absent components.
3. **Exclusive support code**
   - preflight scripts, fixtures, tests, settings, secrets, docs, and
     cross-component contracts whose only owner is an absent product.
4. **Mixed controls**
   - narrow rather than delete a mixed script or manifest when it also protects
     the present Mac or canonical backend.
5. **Unowned present-tree zombies**
   - the unused `desktop/shared-rust/` crate plus its standalone Cargo workspace;
   - the standalone Omi-branded Remotion project under `desktop/macos/demo/`;
   - the undiscoverable nested `desktop/macos/.github/workflows/test-install.yml`
     plus its exclusive exact-file contract test and fixtures;
   - unreferenced packaged `enable_notifications.gif` and `rewind-demo.mp4`;
   - live integration/privacy claims exclusive to those unowned artifacts.
6. **Mixed desktop/backend contract workflow**
   - preserve `.github/workflows/desktop-backend-contracts.yml` and its retained
     `desktop-core-e2e-t0` self-check in S-04;
   - record an exact handoff for S-10 and S-12 to remove only the rejected hosted
     conversation/memory parity job, path triggers, test cases, root fixtures,
     and final test-discovery registry/guard-test residue.

#### Vertical closure order

1. Build an owner table for every selected workflow/check/manifest entry:
   present Mac, present backend, absent product, Windows-only, or mixed.
2. Freeze retained Mac/backend guard behavior with focused script tests.
3. Delete entries and workflows exclusively owned by absent products.
4. Narrow mixed controls to present owners without weakening their checks.
5. Remove exclusive scripts, fixtures, secrets, and docs.
6. Prove manifest resolution succeeds and retained checks are actually selected.

#### Dependencies

None for the absent-tree cleanup. Coordinate shared registry files with S-01,
S-02, and S-03 so each service-specific entry is removed by its owning slice
and the general cleanup does not hide unfinished work.

#### Unblocks

- useful `make preflight` execution against the repository that exists;
- accurate CI ownership before later Mac release adaptation;
- simpler runtime-image and public-build contracts;
- reliable evidence for every later implementation slice.

#### Technical checks before editing

- Classify a workflow by its actual paths and commands, not its filename.
- Detect mixed Mac/backend/absent ownership before deleting shared scripts.
- Treat historical text differently from live workflow/config references.
- Record Windows-only matches as ignored; do not open or edit them.
- Keep IR-892's missing Codemagic definition on the adaptation map.
- Do not delete `desktop/macos/vendor/libwebp/`; S-29 must wire and re-own its
  universal-architecture/provenance checks under IR-939.

#### Closure evidence

The S-04 TDD plan records the eleven implementation commits, before/after
preflight measurements, 95 retained selected checks, full backend and macOS
suite results, independent Standards and Spec reviews, residue proofs, and the
two explicit user waivers. The resulting diff contains no Windows path and
preserves the T0 plus S-10/S-12 handoff and both universal libwebp dylibs.

#### Forbidden scope

- Do not delete a retained Mac or backend guard merely to make preflight green.
- Do not restore absent product trees to satisfy their old automation.
- Do not pretend the later Mac build/release re-ownership work is complete.
- Do not inspect, modify, delete, or repair Windows or Windows-only automation.

---

## Implementation slice register beyond the four root briefs

The remaining `S-XX` slices are named below. Each has one TDD plan. The bullets
are requirements and source-research inputs to that future plan, not a prewritten
list of red-green cycles. The plan may discover any number of vertical tracer
bullets, but the `S-XX` ownership boundary and its approved product decisions
remain stable.

Where a research status says **split**, it means split into sequential tracer
bullets or review stages inside that slice's one TDD plan. It never creates an
extra numbered slice or plan.

### S-05 — Keep one managed-Pi local agent and delete every alternate entrance

**Type:** local runtime narrowing<br>
**Research status:** ready to start; the caller audit resolved `omi-tools-stdio`
for deletion<br>
**Depends on:** none<br>
**Primary decisions:** IR-015, IR-048, IR-049, IR-113, IR-213 through IR-218, IR-603
through IR-606, IR-800 through IR-802, IR-922 through IR-924, IR-936, IR-937

- **Keep:** managed Pi for normal/background work, the local Node kernel,
  `AgentRuntimeProcess`, `ChatToolExecutor`, scoped typed
  tools, local journal, Ask Mode exactly as it is, Agent Pills, and bounded
  exactly-once completion context into voice.
- **Delete:** Claude ACP, Hermes, OpenClaw, provider overrides, Playwright
  browser control, broad shell/file/native-app execution, Claude Code skills and
  project configuration compatibility, the shipped Prompt Lab, dormant Opus and
  cosmetic Haiku callers, `LocalAgentAPIServer`, `omi-tools-stdio`, and the
  broken ACP bridge.
- **Adapt:** strip rejected BYOK, skills, broad-execution, audit, Opus, and Omi
  identity residue from `pi-mono-extension` without replacing its retained
  managed-provider/tool behavior.
- **Resolved transport boundary:** the retained managed Pi uses the packaged
  extension and `OMI_BRIDGE_PIPE`; no retained production caller consumes
  `omi-tools-stdio`, so the stdio process is deleted without replacing it.
- **Close when:** only managed Pi can start product agent work, its verified
  private bridge exposes only retained tools, the external port `47778` surface is gone, and
  normal Chat plus a background Agent Pill pass real-path verification.

### S-06 — Delete Apps, marketplace, connectors, remote MCP, and broad indexing

**Type:** complete multi-entry product deletion<br>
**Implementation status:** repository deletion landed in `ff528f8`; the
never-released product record satisfies the route-removal gate, and Wave 1
closeout removed generated dispatch residue from retired file-scan/email tools
plus the hosted-MCP-exclusive failure-class record<br>
**Depends on:** none; coordinate the private Pi tool-bridge keep boundary with S-05<br>
**Primary decisions:** IR-015, IR-045 through IR-047, IR-050 through IR-051,
IR-106, IR-135, IR-141 through IR-142, IR-212 through IR-213, IR-256, IR-258
through IR-261, IR-310, IR-375, IR-512, IR-637, IR-816 through IR-818, IR-824,
IR-938

- **Keep:** the verified managed-Pi extension/bridge tool path, explicit local attachments, local
  Memory/Task/Conversation relationships, one personalized assistant, and the
  retained scoped tools.
- **Delete:** the Apps tab and every marketplace UI; installation, reviews,
  paid-app billing, creator/admin and third-party API surfaces; hosted MCP,
  OAuth/API keys, outbound marketplace MCP, first-party import/export
  connectors, external-agent setup writers, Calendar creation, public Persona,
  hosted sharing, file indexing, Full Disk Access scanning, and Brain Map /
  knowledge graph; Todoist, Asana, Google Tasks, ClickUp, and Apple Reminders
  task export, OAuth, automatic sync, pending/batch-sync routes, export metadata,
  credentials, and exclusive support code; the integration-only
  `candidate_integration_outbox`, lease helpers, drain route, composite index,
  generated binding, tests, and workflow-invariant clause. Candidate
  creation/acceptance itself remains protected.
- **Coordinate:** S-06 deletes the hosted Limitless ZIP importer under IR-824.
  Direct `LimitlessDeviceConnection` hardware support is already rejected by
  IR-014 and belongs to S-02; it is not an S-06 keep boundary.
- **Close when:** no UI, route, collection, OAuth grant, webhook, worker,
  marketplace charge, connector credential, remote MCP schema, indexer, or
  deployment remains, while the retained local agent can still call its tools.

### S-07 — Delete the customer BYOK plan and all key propagation

**Type:** complete access-plan deletion<br>
**Implementation status:** Wave 1 repository implementation complete on
2026-08-15; legacy migration is structurally inapplicable because this
unreleased fork owns no deployed user or job population<br>
**Depends on:** none; coordinate Deepgram key residue with S-03 and Pi extension
residue with S-05<br>
**Primary decisions:** IR-058, IR-062, IR-606, IR-937

- **Keep:** product-managed provider credentials, subscriber credential minting,
  ordinary development/test secrets, Vertex/AI Studio product routing, and
  managed quota enforcement.
- **Delete:** the free BYOK plan, Settings UI, the four raw customer-key
  `UserDefaults` values found by source research, validation, request/WebSocket
  headers, Node/runtime environment propagation, Firestore
  fingerprints, paywall/quota bypass, account copy, and provider-selection
  branches that exist only for customer keys.
- **Legacy-data decision:** delete inherited `users.byok`, `blocked_byok`, and
  `requires_byok` readers/writers without a migration. There is no owned live
  population to inventory or mutate, and upstream Omi data is outside this
  product's authority.
- **Close when:** no customer-supplied model key can change entitlement or reach
  a provider, and every retained hosted call uses a product-owned credential.

### S-08 — Re-own Firebase identity and narrow account lifecycle/data export

**Type:** retained cloud-control adaptation<br>
**Implementation status:** config-independent Wave 1 repository tranche
implemented on 2026-08-15; the locked macOS session blocked the final live
acquisition click, and owned-identity/auth-invariant gates plus later closure remain
dependency-gated<br>
**Depends on:** owned Firebase / Apple / Google identity inputs and restoration or
deliberate replacement of the missing auth invariant; S-09 consumes the resulting
identity/sign-out seam<br>
**Primary decisions:** IR-006, IR-120, IR-124, IR-170 through IR-190, IR-830,
IR-868, IR-877, IR-878

- **Keep:** Apple and Google hosted sign-in, Firebase custom-token exchange,
  blocking session validation, recovery, fail-closed foreground refresh, explicit
  sign-out, confirmed account deletion, durable queued worker, immediate sign-out
  after acceptance, completed tombstones, and minimal account-control Firestore.
- **Wave 1 adaptation:** re-own Firebase/Apple/Google identity, protect
  the current auth/session/sign-out seams, remove the backend acquisition-source
  mirror, remove unused deletion-reason fields, and publish a narrow retained
  deletion-orchestrator/account-metadata contract for later owners.
- **Later closure dependencies:** a complete local Export My Data flow needs the final
  S-10 through S-14 authorities; safe deletion-worker pruning needs S-18/S-23/S-24;
  task retargeting and queue/IAM/region ownership need S-25/S-27. Making S-08
  depend on all of them creates cycles because downstream slices already consume
  S-08 identity semantics.
- **Adopted ownership boundary:** S-08 owns the retained auth/session fences,
  owned identity configuration, onboarding acquisition-mirror removal,
  deletion-reason removal, and explicit account-deletion/account-metadata
  handoff contracts. S-10 through S-14 own complete local export readers; S-18,
  S-23, and S-24 own rejected-provider/data cleanup; S-25 owns task retargeting;
  and S-27 owns queue/IAM/region infrastructure and live validation. The same
  S-08 plan retains final export composition and acceptance after its reader
  dependencies close; no S-08A/S-08B or extra plan is created.
- **Close the Wave 1 tranche when:** owned sign-in/recovery/sign-out
  behavior works, rejected onboarding/deletion-reason fields are gone, S-09 has
  an explicit identity seam, and every deferred export/deletion/queue obligation
  has a named acceptance handoff. Full IR closure waits for the named downstream
  dependencies and final acceptance.
- **2026-08-15 repository handoff:** retained auth/session/sign-out suites stayed
  green; acquisition now has one local-plus-analytics owner and no backend write;
  the backend onboarding routes/helpers and deletion survey payload are gone;
  explicit sign-out entry points have a behavioral ordering fence; and the durable
  deletion worker names its retained cleanup boundary while the downstream
  account/control metadata allowlist remains a handoff contract for its real
  consumers. The onboarding transition is a deliberate same-release Mac/backend
  hard removal (old clients receive 404, no compatibility shell); the bodyless
  deletion endpoint still accepts and ignores legacy JSON. The regenerated Swift
  app client is in scope and the Windows client is not. Current provider cleanup,
  queue/service identity, export composition, and identity configuration remain
  with their named gates rather than being removed or guessed here. Focused
  backend/macOS suites, both route/lifecycle E2E cases, strict desktop flow
  coverage, generated-contract checks, and the full Swift test-bundle compile
  passed; broad component runs stopped on unrelated backend timing-ratchet and
  Memory Atlas suite-timeout debt recorded in the S-08 plan.

### S-09 — Re-own telemetry, diagnostics, issue reporting, and model tracing

**Type:** retained observability adaptation<br>
**Implementation status:** configuration-independent deletion is complete in
local commits; identity, owned-project configuration, and S-27 live proof keep
the slice open at their cycle-local gates<br>
**Depends on:** the canonical S-08 account identity/sign-out seam, not unimplemented
later export or queue cleanup<br>
**Primary decisions:** IR-114 through IR-117, IR-183, IR-204 through IR-211,
IR-254, IR-805, IR-827, IR-828, IR-832, IR-836, IR-837, IR-879, IR-886

- **Keep:** Sentry, PostHog, privacy-bounded PTT lifecycle diagnostics, local
  query tracing/rotating JSONL, Enhanced Diagnostics, Report an Issue, offline
  diagnostic export, LangSmith traces/runs/feedback, Prompt Hub with TTL cache
  and repository fallback, lightweight authenticated metrics, sanitized Cloud
  Logging, and 30-day log retention.
- **Adapt:** point every retained SDK, DSN, key, host, project, environment,
  identity attach/detach, disclosure, and sampling rule to our accounts; add a
  local PostHog analytics toggle while keeping Sentry diagnostics separate.
- **Delete:** deprecated PTT events, Crisp, Sentry-to-cloud-Task bridge, in-app
  ratings, duplicate privacy cards/fake Active states, and the self-hosted
  Prometheus/Grafana/Loki/Alloy/Alertmanager product.
- **Close when:** consent/opt-out, sign-in/sign-out identity, issue submission,
  incident breadcrumbs, LangSmith prompt/trace correlation, and redaction are
  verified in owned development projects before production keys are installed.

### S-10 — Make conversations and transcripts local-authoritative

**Type:** local-authority adaptation<br>
**Research status:** split; current local store is a server cache plus recorder<br>
**Depends on:** S-02 and S-03 for the final source/provider shape<br>
**Primary decisions:** IR-004, IR-020 through IR-023, IR-121 through IR-123,
IR-293 through IR-405, IR-727, IR-732

- **Keep:** the existing Conversations list/detail UX, Quick Note, live
  transcript, merge, search, folders, starring, pagination, local speaker names,
  summary/action-item enrichment, translation, location opt-in, language,
  timezone, input-device name, discard policy, stable segment IDs, formatting,
  and local deletion cascades selected in the ledger.
- **Adapt first:** make GRDB own session, segment, detail, folder, title, emoji,
  summary, action-item, speaker-name, translation, completion, and merge state;
  move retained model outputs through validated Mac commits.
- **Delete after proof:** transcript promotion/sync, server conversation
  ownership/finalization/reconciliation, cloud playback audio, recording sync,
  reusable people, voice embeddings, sharing, billing locks, device provenance,
  generic external-data bags, cloud processing aliases, replacement/comparison
  pipelines, backend-only mutation APIs rejected by the ledger, the
  conversation-only cases in `backend/testing/contracts/test_desktop_backend_parity.py`,
  root `contract_tests/fixtures/conversations.json`, and only their job/path
  portion of the mixed `desktop-backend-contracts.yml` workflow.
- **Close when:** recording, finalization, list/detail/search/edit/merge/delete,
  speaker naming, and enrichment work through local authority with the network
  unavailable; backend teardown itself completes in S-23.

### S-11 — Make Chat and Home local-authoritative

**Type:** local-authority adaptation plus shell consolidation<br>
**Research status:** split<br>
**Depends on:** S-05, S-06, S-07, S-10, and S-12<br>
**Primary decisions:** IR-003, IR-040 through IR-045, IR-500 through IR-530,
IR-721, IR-722, IR-731, IR-932

- **Keep:** the local kernel journal, multiple Chats, local greeting/title,
  explicit local attachments, one assistant, Home as the canonical Chat host,
  local task/Focus/Insight rows, capture/listening controls, responsive layout,
  send/stop, shared drafts, error presentation, and shell navigation selected in
  the ledger.
- **Adapt first:** make the local journal and local session catalog own messages,
  thread metadata, starring, titles, greetings, attachment paths, navigation,
  and typed/voice continuity; add the compact Chats catalog to Home.
- **Delete after proof:** backend journal outbox/reconciliation, backend
  chat-session metadata, cloud greeting/title persistence, message ratings,
  cloud file uploads, app/persona Chat, hidden `ChatPage`, page-only modals,
  dashboard intelligence, connector tray, old counters, and retired voice
  outbox importer.
- **Close when:** create/switch/rename/star/delete/reopen Chat, send with a local
  attachment, restart recovery, and managed-Pi inference work without backend
  message/session storage.

### S-12 — Make Memories local-authoritative and delete knowledge authority

**Type:** local-authority adaptation<br>
**Research status:** split; current local store is a bidirectional cache<br>
**Depends on:** S-06 and S-10 for connector/graph and source-conversation shape<br>
**Primary decisions:** IR-024, IR-033, IR-256 through IR-292, IR-710, IR-728
through IR-730, IR-815

- **Keep:** Short-term/Long-term/Archive, category filters, search, Add Memory,
  bulk default deletion, inspector, edit, four-second Undo, tags, Tips reasoning,
  Context, source-conversation navigation, local screenshot links, pagination,
  Retry/empty/no-results states, and local provenance selected in the ledger.
- **Adapt first:** make `MemoryStorage`/GRDB own creation, normalization admission,
  lifecycle transitions, search vectors, edits, delete/Undo, source links,
  extraction, conflict handling, and all Chat/PTT/proactive consumers.
- **Delete after proof:** `/v3/memories` authority, Firestore memory lifecycle,
  public/private/persona fields, Workflow category, device provenance, review and
  scoring metadata, generic reasoning, protected-string compatibility, old
  model routes, graph projections, cloud memory-maintenance jobs, the memory-only
  parity cases in `backend/testing/contracts/test_desktop_backend_parity.py`,
  root `contract_tests/fixtures/memories.json`, and only their job/path portion
  of the mixed `desktop-backend-contracts.yml` workflow. Once this final contract
  file is gone, remove `testing/contracts/` from `WORKFLOW_COVERED_PREFIXES` and
  update `test_check_unit_test_discovery.py` in the same S-12 change.
- **Close when:** every visible and agent-driven Memory mutation survives restart
  locally and no retained caller reads canonical memory state from Firestore.

### S-13 — Make Tasks and one simple Goals product local-authoritative

**Type:** local-authority adaptation and feature reduction<br>
**Research status:** split<br>
**Depends on:** S-06 and S-10 for connector/sharing and source-conversation shape<br>
**Primary decisions:** IR-025 through IR-032, IR-098 through IR-105, IR-616
through IR-658, IR-825

- **Keep:** the grouped To Do/Done list, inline creation, autosave, complete /
  reopen, repeating tasks, date/priority editing, details, five-second Undo,
  ordering, keyboard navigation, provenance, pagination, Task Assistant controls
  retained by the ledger, and one local Goal with title, optional description,
  and active/completed state.
- **Adapt first:** make `ActionItemStorage`/GRDB own all mutations, ordering,
  recurrence, source links, Task Assistant extraction, settings, and agent/voice
  reads and writes; keep existing cloud behavior patterns where they are useful
  but commit locally.
- **Delete after proof:** Firestore action items, candidates/task intelligence,
  Suggested queue, workstreams/task-attached agents, Board, advanced filters,
  full create sheet, dormant recurring AI scheduler, tags/categories/source
  classifications, generic metadata, analytics task type, sharing, bulk delete,
  indentation, staged prioritization/re-score, relevance scores, productivity
  scores, and both cloud goal systems/sync.
- **Close when:** normal UI, Chat, PTT, proactive extraction, recurrence, Undo,
  drag/keyboard actions, and Goals all use the same local authority.

### S-14 — Make Focus, Insights, proactive advice, and AI Profile local-authoritative

**Type:** local-authority adaptation<br>
**Research status:** split<br>
**Depends on:** S-10, S-12, S-13, and S-15<br>
**Primary decisions:** IR-029 through IR-038, IR-229 through IR-231, IR-505,
IR-508, IR-659 through IR-682, IR-723, IR-724, IR-814, IR-829

- **Keep:** existing Gemini Focus judgment, automatic task/memory extraction,
  Advisor analysis, Live Suggestions, simple today/recent Focus, local Insight
  history, delete/dismiss/read actions, the combined Insights/Focus hub, local
  notifications, once-daily Home questions, and the daily local AI Profile.
- **Adapt first:** preserve current behavioral patterns while sourcing Rewind,
  conversations, tasks, memories, profile inputs, and settings locally; make
  Focus/Insight/profile/settings writes owner-scoped and local-authoritative.
- **Delete after proof:** backend synchronization, duplicate caches, server
  Mentor settings, cloud proactive notification model, memory copies of
  Insights, cloud Focus sessions, Daily Summary UI/job/history/deep link, and
  other cloud-only profile projections.
- **Close when:** account switching cannot leak projections, every local action
  survives restart, notifications continue into local Chat, and no retained
  assistant requires product-data reads from the backend.

### S-15 — Preserve local Rewind and delete every cloud copy/read path

**Type:** deletion around an already-local authority<br>
**Research status:** ready after caller/residue inventory<br>
**Depends on:** S-01 and S-06 so VM and remote-MCP readers are gone<br>
**Primary decisions:** IR-011, IR-053, IR-088 through IR-091, IR-232 through
IR-240, IR-683 through IR-699, IR-806, IR-807, IR-899 through IR-921

- **Keep exactly as reviewed:** local capture, video/OCR/SQLite, embeddings,
  text plus vector search, selected-day timeline, grouping, navigation,
  retention, excluded apps, battery optimization, Storage card, permission and
  recovery screens, all explicitly retained reachable and dormant UI quirks,
  local daily recap, and the Gemini embedding proxy as transient compute.
- **Delete:** Firestore/Pinecone screen-activity writers/readers, backend agent
  tools, hosted MCP surfaces, indexes, deletion hooks, generated non-Windows
  clients, and Settings/search residue for rejected cloud controls.
- **Close when:** capture/OCR/search/recovery/retention and PTT Rewind grounding
  work locally while repository searches prove no live cloud screen-history
  producer or consumer remains.

### S-16 — Keep `/v4/listen` as transient STT and delete server conversation ownership

**Type:** transport narrowing and local-authority adaptation<br>
**Research status:** split<br>
**Depends on:** S-02, S-03, and S-10<br>
**Primary decisions:** IR-017 through IR-023, IR-384 through IR-405, IR-726,
IR-887 through IR-889, IR-898

- **Keep:** microphone plus System Audio, meeting detection, Always / Meetings
  only / Never modes, Mac-local Parakeet, managed Modulate, reconnect/watchdog,
  server-configured in-process VAD, generic diarization, transient translation,
  and the ready/failure truth needed by the Mac.
- **Adapt:** `/v4/listen` accepts the narrowed PCM protocol, emits transient
  transcript/translation/speaker events, and never becomes a conversation
  owner; the Mac commits all retained output to GRDB.
- **Delete:** server session creation/finalization/rollover, conversation IDs and
  reconciliation, browser listen, multi-channel/custom-STT/provider hints,
  stable device identity, call/onboarding modes, cloud lifecycle statuses,
  hosted NLLB, and cloud language/preferences authority.
- **Close when:** Intel/fallback streaming and Apple-Silicon local streaming both
  create the same local conversation shape without a server conversation row.

### S-17 — Narrow onboarding and macOS permissions to the retained product

**Type:** user-flow adaptation and dead-flow deletion<br>
**Research status:** split<br>
**Depends on:** S-06, S-07, and S-08<br>
**Primary decisions:** IR-050 through IR-052, IR-124 through IR-169, IR-733
through IR-735

- **Keep:** the conversational onboarding shell; opening trust screen; global
  Skip; name, acquisition, language, microphone, System Audio, Screen Recording,
  Accessibility, open-shortcut, PTT-shortcut, live PTT demo, listening choice,
  genuine-completion opener, Launch at Login, monitoring, resume/back/typing /
  transcript behavior, reset paths, Return actions, layout, and lifecycle
  diagnostics exactly where retained by the ledger.
- **Adapt:** store answers locally except the Firebase Auth display name and
  bounded PostHog acquisition event; use Accessibility only for global PTT and
  precise Rewind/Focus; rewrite every promise after final architecture/rebrand.
- **Delete:** role, Full Disk Access/file scan, Automation, agent/context
  connector screens, Calendar claims, backend onboarding record, legacy login
  migration, old paged onboarding, orphaned suggestions, and unreachable
  AI-driven onboarding engine.
- **Close when:** completion, Skip, quit/resume, Back revisions, reset, sign-out,
  and relaunch all operate on the narrowed local state without starting capture
  merely because a permission was granted.

### S-18 — Replace Stripe with Dodo while preserving billing behavior

**Type:** provider adaptation and plan simplification<br>
**Research status:** split; exact Dodo contract is a required start gate<br>
**Depends on:** S-07 and S-08<br>
**Primary decisions:** IR-006, IR-007, IR-191 through IR-203, IR-700, IR-831,
IR-835

- **Keep:** default-off three-day trial, plan card, rich catalog cards, embedded
  provider-hosted checkout, bounded reconciliation poll, hosted billing portal,
  usage card, local preflight, backend authoritative quota, and managed
  subscriber access.
- **Adapt:** customer/product/price/webhook/checkout/portal/subscription models to
  Dodo, including bounded/unlimited entitlement mapping used by fair use.
- **Delete:** Stripe-specific code and secrets after parity, Omi legacy plan
  migration, promotion codes, local checkout simulator, product-owned plan
  changes/reactivation, duplicate catalog reconstruction, unfinished paid
  overage, BYOK/free-plan bypass, and unused detailed usage readers.
- **Close when:** checkout, webhook reconciliation, portal, entitlement changes,
  quota denial, and cancellation work end to end using Dodo test then production
  configuration without a Stripe or Omi plan identifier.

### S-19 — Reconnect PTT to local product data and remove rejected tools

**Type:** cross-domain adaptation<br>
**Research status:** split; PTT lifecycle remains a regression fence<br>
**Depends on:** S-05 through S-07 and S-10 through S-16, especially local
Conversations, Memories, Tasks, Focus/Insights, Rewind, and transient listen<br>
**Primary decisions:** IR-054 through IR-119, IR-600 through IR-602, IR-924
through IR-926, IR-932

- **Keep as behavioral guardrails:** global hold and double-tap, shortcut and mic
  selection, cues/playback muting, admission/recovery/language logic, realtime
  speech-to-speech, OpenAI/Gemini switching/failover, barge-in and interrupted
  continuity, screen capture/vision/report protocol, local journal continuity,
  warm sessions, relay and batch recovery, UI states, diagnostics, and usage
  counting explicitly retained by the ledger.
- **Adapt:** conversation listing/search, memory listing/search, task reads/writes,
  daily recap, Rewind search, permission tools, completed Agent Pill context,
  notch task receipts, and notification context to their authoritative local
  stores with owner fencing.
- **Delete:** `point_click`, Calendar creation, customer BYOK, unread session
  audit documents, unused context identity fields, duplicate Task Added banner,
  deprecated PostHog start/end events, higher-model escalation/live-web tool,
  and the retired UserDefaults outbox importer.
- **Close when:** the complete PTT lifecycle passes with local personal data and
  no deleted tool/provider/account path is advertised to either realtime model.

### S-20 — Move fair-use evidence local and keep only enforcement facts in cloud

**Type:** split-authority adaptation<br>
**Research status:** split; local semantic-model adapter is a required start gate<br>
**Depends on:** S-10, S-16, and S-18<br>
**Primary decisions:** IR-610 through IR-615, IR-700 through IR-709

- **Keep:** the existing classification semantics, threshold bands, combined
  quota/fair-use path, warning/final-warning/restrict lifecycle, restricted
  30-minute managed-cloud allowance, protected support operations, account-life
  event history, and explicitly accepted partial kill-switch behavior.
- **Adapt:** assemble recent conversation evidence from local GRDB, run the same
  classifier semantics through genuinely local inference, retain content evidence
  locally, and send only verdict/usage/enforcement facts to the backend; map
  bounded/unlimited through Dodo.
- **Delete:** hosted conversation evidence, content-bearing case fields, public
  case lookup, unused signed-in status route, and false Settings direction.
- **Close when:** threshold, recovery, support reset, repeat-strike counting,
  restricted cloud allowance, and local fallback/blocked presentation pass with
  no private conversation text in the backend case record.

### S-21 — Simplify navigation, Settings, and the surviving Home shell

**Type:** UI convergence after product deletion<br>
**Research status:** split; must land after domain owners<br>
**Depends on:** S-05 through S-07; S-09 through S-15; S-17, S-18, and S-20<br>
**Primary decisions:** IR-191 through IR-255, IR-500 through IR-530, IR-616,
IR-659, IR-681, IR-930, IR-933<br>
**Protecting handoff:** S-05 implements IR-801 and IR-802 while deleting the
provider/settings entrances; S-21 verifies the resulting shell and removes only
leftover navigation/search residue

- **Keep:** Home, Memory, Tasks, Insights/Focus, Conversations inside the
  retained grouping, Rewind, Plan/Usage, Privacy/Data, Advanced Settings, About,
  and every interaction explicitly retained in their domain slices.
- **Adapt:** expose one combined Insights item, map Command-number shortcuts to
  Home/Memory/Tasks/Insights, verify S-05's moved Ask Mode is correctly reachable
  from Advanced AI Setup and remove only leftover shell/search routing, make Your
  Stats read local stores, and narrow startup/foreground refresh to surviving owners.
- **Delete:** the Apps destination, empty AI Chat destination, old Home mode,
  hidden standalone Chat route, Brain Map, connector trays, rejected cards,
  Feature Tiers/gating, Apps Installed metric, phantom/broken Settings search
  rows, external Help Center, and dead page-only modals/counters.
- **Close when:** every visible destination has a surviving owner, every search
  result navigates to a real control, and deleted products are unreachable by
  sidebar, menu, shortcut, deep link, automation, or restored state.

### S-22 — Narrow managed models to explicit retained transient workloads

**Type:** model portfolio deletion and result-ownership adaptation<br>
**Research status:** split; retained caller/model inventory lands first<br>
**Depends on:** S-05, S-07, S-10, S-11, S-12, S-13, S-14, and S-16<br>
**Primary decisions:** IR-053, IR-113, IR-600 through IR-609, IR-710 through
IR-732, IR-827, IR-828

- **Keep explicit routes only:** managed Claude normal Chat; both current realtime
  providers and the decided v1 Auto/switch/failover policy; Gemini Flash/Lite
  generation, translation, and embeddings; Vertex plus platform-key AI Studio;
  OpenAI memory normalization/extraction/conflict, conversation summary/action
  items, greeting, and discard; LangSmith and Prompt Hub.
- **Adapt:** every retained model call receives bounded local inputs, returns a
  transient result, and lets the Mac validate/commit it to the owning local
  store; provider calls live directly in the canonical backend where cloud
  mediation is required.
- **Delete:** higher-model/live-web voice escalation, cosmetic Pill model call,
  Chat Prompt Lab, Opus/Haiku/ChatLab residue, attempt-cost documents, independent
  LLM gateway, global premium/max/BYOK profiles, Perplexity/Sonar, all public web
  search, callerless ElevenLabs, unused Gemini Pro/streaming, OpenRouter, NLLB,
  old memory/chat/persona/proactive/glasses routes, and rejected provider config.
- **Failure-class lifecycle:** the public-web implementation PR deletes
  `backend/desktop_fixtures/public-web-routing-contract.fixture.json` and its
  Pi-adapter/doc consumers. After that PR merges, the same owner opens a separate
  registry-lifecycle PR that marks `FC-public-web-routing-parity` dormant with
  `dormant_since`; do not combine the transition or erase the historical record.
- **Close when:** every model identifier has a named retained caller and result
  owner, every removed route has no caller/config/secret/test, and no user data
  becomes durable merely because compute ran in the backend.

### S-23 — Delete rejected hosted products and their product-data schemas

**Type:** backend product teardown<br>
**Research status:** split by product owner<br>
**Depends on:** S-01, S-02, S-06, S-08, S-10 through S-14, S-17, S-18, S-20,
and S-22<br>
**Primary decisions:** IR-039, IR-043, IR-121 through IR-123, IR-186 through
IR-187, IR-289 through IR-290, IR-310, IR-338, IR-359, IR-369 through IR-383,
IR-714 through IR-725, IR-805, IR-814 through IR-835

- **Delete as complete products:** Daily Summary; cloud recordings/playback and
  training opt-in; persistent voice recognition/People; public sharing/persona;
  Twilio calls; Wrapped; cloud announcements; Trends; wearable firmware/photo /
  glasses; Limitless import; task productivity scores; FCM; cloud ratings;
  Joan; detailed usage readers; Sentry-to-Tasks; obsolete model routes; and all
  exclusive collections, buckets, schemas, indexes, jobs, generated non-Windows
  clients, tests, analytics, runbooks, and secrets.
- **Keep:** local notifications and What's New, local conversation/task/memory
  data, Mac Sparkle, managed quota totals, account deletion, export, and any
  shared primitive proven to have a retained caller.
- **Close when:** a route/storage owner matrix shows no rejected product route or
  data schema remains in either Python entrypoint, OpenAPI, Firestore registry,
  GCS policy, Redis namespace, account-deletion enumeration, or docs.

### S-24 — Delete hosted search, vector, and product-object authority

**Type:** infrastructure deletion after local search authority<br>
**Research status:** split by Typesense, Pinecone, and object/file storage<br>
**Depends on:** S-10, S-11, S-12, S-13, S-15, S-19, and S-23<br>
**Primary decisions:** IR-011, IR-044, IR-053, IR-093, IR-095, IR-256, IR-291,
IR-806 through IR-809

- **Keep:** GRDB/FTS5, local vectors, local Rewind OCR/vector search, local
  conversation hybrid search, local memory search, explicit local Chat files,
  transient embedding compute, and one GCS bucket only for signed updates and
  previews.
- **Delete:** Typesense and synchronization, Pinecone and every namespace/repair
  path, cloud attachment/OpenAI Files copies, product-data GCS paths, hosted
  graph/vector consumers, rejected credentials, alerts, migrations, and tests.
- **Close when:** every retained search executes against local indexes, deleting
  a local record maintains its local index, and cloud storage inventory contains
  no private product-data path.

### S-25 — Delete jobs, workers, duplicate services, and GKE control planes

**Type:** service-topology collapse<br>
**Research status:** split by independently deployed service/job<br>
**Depends on:** S-01 through S-03, S-06, S-22, S-23, and S-24<br>
**Primary decisions:** IR-016, IR-120, IR-608, IR-810 through IR-818, IR-836,
IR-839, IR-868

- **Delete:** both backend-sync deployments, conversation finalizers, playback /
  wearable workers, Pusher, separate `backend-listen` GKE, hosted VAD, standalone
  diarizer, Notifications job, memory-maintenance job, backend-integration,
  Plugins workflow/service residue, LLM gateway, and self-hosted monitoring.
- **Move before delete:** target the retained durable account-deletion Cloud Task
  and reconciler at the canonical backend with truthful route/service-account
  naming; retain in-process VAD and provider-returned generic speaker labels.
- **Close when:** deployment manifests and cloud inventory show only the
  canonical backend plus explicitly retained managed dependencies, with no
  traffic, queue, secret, alert, or runtime image pointing at a retired service.

### S-26 — Consolidate one canonical Python backend and its development harness

**Type:** backend boundary adaptation<br>
**Research status:** split; prune product routes before consolidating entrypoints<br>
**Depends on:** S-04, S-25, and the local/control-authority slices S-08 and
S-10 through S-20<br>
**Primary decisions:** IR-008, IR-803, IR-804, IR-808, IR-839 through IR-849,
IR-890, IR-891

- **Keep:** one Python application, one canonical URL per environment, retained
  auth/billing/quota/fair-use/model/STT/update/account-deletion/metrics routes,
  narrow Redis coordination, safe Firestore index control, exact-image release
  semantics, and an isolated local/offline harness.
- **Adapt:** merge desktop/product Python entrypoints and configuration, rename
  stale Rust/service terminology, prune route policies/OpenAPI/runtime manifests
  and Firestore indexes to survivors, and make emulator/fakes/profiles exercise
  exactly Firebase, Redis, Dodo/provider, STT, and account-deletion boundaries
  that remain.
- **Delete:** duplicate service URLs/routers, dormant `backend_required` exact-SHA
  client scaffolding, rejected-product keys/indexes/scenarios, and any harness
  service absent from production.
- **Close when:** one local command starts the complete surviving stack, one URL
  serves the Mac, route-policy/OpenAPI/runtime/index manifests agree, and focused
  offline tests have no hidden dependency on a deleted service.

### S-27 — Re-own the retained Cloud Run, Redis, Firestore, GCS, and deploy foundation

**Type:** infrastructure adaptation<br>
**Research status:** split into independently verifiable platform changes<br>
**Depends on:** S-08, S-09, S-18, S-20, and S-26<br>
**Primary decisions:** IR-808, IR-809, IR-838 through IR-886, IR-890, IR-891

- **Platform shape:** one development and one production Cloud Run service in
  `us-west1`; 2 vCPU/4 GiB; concurrency 20; 60-minute timeout; dev min/max 0/3,
  prod 1/10; no affinity; second-generation execution; explicit probes; about
  eight-second shutdown; instance-based billing; stable `run.app` URLs.
- **Identity/security:** GitHub WIF, dedicated least-privilege runtime accounts,
  ADC, exact Secret Manager versions, internet reachability with per-route auth,
  empty default-deny CORS, non-root container, and narrow writable temp paths.
- **Dependencies:** separate 1-GiB dev Basic and prod Standard-HA Memorystore in
  `us-west1`, private-range networking, AUTH and verified TLS; retained GCS update
  bucket; exact Firestore indexes; one account-deletion queue per environment.
- **Build/release operations:** controlled pinned Python 3.11 slim base, regional
  Artifact Registry, full-commit tag plus immutable digest, no `latest`, retained
  build cache, dry-run cleanup of untagged artifacts older than 30 days, exact
  release images retained, candidate/promotion/rollback/break-glass bound to
  exact main.
- **Observability/cost:** Cloud Logging with sanitized payloads and 30-day
  retention, production health/5xx alerts, 50/80/100 percent monthly budgets,
  no custom revision cleanup job, no external log archive.
- **Close when:** development and production can deploy, authenticate, stream,
  bill, queue account deletion, roll back, and survive retained failure modes
  using only our projects and declared manifests.

### S-28 — Establish clean Mac storage namespaces and installation identity

**Type:** local identity migration without inherited-data takeover<br>
**Research status:** one coherent migration after local data schemas stabilize<br>
**Depends on:** S-08, S-10 through S-15, and S-17<br>
**Primary decisions:** IR-929, IR-931

- **Keep:** guarded atomic self-install from DMG/App Translocation, no downgrade,
  relaunch, and the retained local stores/lifecycles.
- **Adapt:** assign our bundle IDs, app/group/Keychain services, Application
  Support paths, databases, defaults, login item, caches, logs, update identity,
  and test-bundle namespaces; start clean product stores and owner fencing.
- **Delete:** automatic Omi data import/takeover migrations, Omi process
  termination, old-app deletion, inherited absolute paths, and mixed namespaces.
- **Close when:** clean install, upgrade from our own first build, reset, sign-out,
  multi-account switch, and uninstall/reinstall tests never read or mutate an Omi
  installation.

### S-29 — Re-own Mac build, signing, updates, previews, and public/legal destinations

**Type:** release-system adaptation<br>
**Research status:** split; owned external identities/configuration are start gates<br>
**Depends on:** S-04, S-09, S-26, S-27, and S-28<br>
**Primary decisions:** IR-010, IR-243 through IR-253, IR-804, IR-821, IR-892
through IR-897, IR-927 through IR-929, IR-939

- **Keep:** Sparkle manual/automatic update behavior, safe activity gate, local
  What's New, Stable/Beta choice with local preference, required-update blocker,
  runtime self-install, candidate intake, dedicated M1 qualification, immutable
  evidence, Beta/Stable manifests, promotion/rollback/break glass, and signed
  branch previews.
- **Adapt:** add the owned Codemagic workflow; our Developer ID, notarization,
  bundle/feed/signing identities, bot/runner/environment, GCS/GitHub artifacts,
  backend release authority, preview lifecycle, website, Terms, Privacy, support,
  and GitHub Releases links; verify and bundle the retained universal libwebp /
  libsharpyuv cache with version, checksum, architecture, minimum-OS, signing,
  and rebuild-fallback ownership; repair update install gating against retained
  local activity state.
- **Delete:** Omi cloud announcements, inherited Codemagic assumptions, external
  Help Center, impossible absent-source controls, Omi domains/keys/buckets, and
  `backend_required` dormant exact-SHA mode.
- **Close when:** a named dev bundle and a clean signed candidate install, update,
  Beta/Stable promotion, rollback, preview create/delete, and public links are
  exercised under owned infrastructure.

### S-30 — Perform the final product-identity, copy, privacy, and legal truth pass

**Type:** cross-cutting truth/rebrand pass after architecture stabilizes<br>
**Research status:** ready only after architecture/release predecessors close<br>
**Depends on:** S-17, S-09, S-21, S-27, S-28, and S-29<br>
**Primary decisions:** IR-115, IR-126, IR-165, IR-174, IR-204 through IR-207,
IR-247 through IR-253, IR-269, IR-287, IR-514, IR-521, IR-858, IR-887, IR-892
through IR-896, IR-927 through IR-931

- Rebrand every visible Omi name, logo, image, color token, URL, email, legal
  claim, provider disclosure, bundle identity, notification, analytics event,
  log/service name, and operator document that represents the current product.
- Rewrite privacy, onboarding, sign-in, Home, Memory, recording, cloud-compute,
  telemetry, billing, update, and support claims against the architecture that
  actually survived. Preserve historical changelogs as history.
- Keep “never use purple” and the selected neutral Mac appearance; do not add a
  redundant provider-disclosure card rejected by IR-802.
- **Close when:** repository searches plus a user-visible screen/link inventory
  find no current Omi identity or false local/cloud/privacy promise.

### S-31 — Prove closure, measure cycle time, and automate the surviving loop

**Type:** final integration and acceleration<br>
**Research status:** release-acceptance plan, not a bulk feature/deletion operation<br>
**Depends on:** S-01 through S-30<br>
**Primary decisions:** all reviewed IRs as acceptance guardrails

- Re-run the full source-owner inventory for routes, Firestore/Redis/GCS, jobs,
  images, secrets, workflows, generated contracts, docs, and app navigation.
- Run component suites and repository preflight; exercise onboarding, auth,
  billing, capture/transcription, Rewind, Conversations, Memories, Tasks/Goals,
  Insights/Focus, Chat, PTT, account deletion/export, install/update, and release
  paths in owned development infrastructure.
- Measure clean setup, edit-to-test, edit-to-dev-bundle, backend deploy, candidate
  qualification, and rollback time. Delete or parallelize only measured waste,
  then automate the stable retained path.
- Close only with no unexplained rejected-product reference, no compatibility
  shell, a clean requirements-ledger validation, documented commands/evidence,
  and an implementation roadmap with no remaining code-decision fog.

## Protected-behavior register

The roadmap contains large deletions, but deletion is not the default for every
complex neighboring behavior. These families are explicit regression fences:

- **PTT and realtime voice:** IR-054 through IR-119, IR-600 through IR-602,
  IR-924 through IR-926, and IR-932 govern the reviewed
  activation, capture, provider, interruption, screen, fallback, continuity,
  presentation, and diagnostic behaviors except the branches explicitly deleted
  or adapted by S-03, S-07, S-19, S-20, S-09, and S-22.
- **Onboarding and authentication:** IR-125 through IR-190 and IR-733 through
  IR-735 retain the selected flow/lifecycle details except the exact screens,
  cloud writes, and claims removed or adapted by S-08 and S-17.
- **Memories:** IR-256 through IR-292 retain the chosen UI/lifecycle behavior
  while S-12 changes authority and removes explicitly rejected fields/features.
- **Conversations and transcription:** IR-293 through IR-405 retain the chosen
  list/detail/transcript behavior while S-10 and S-16 change authority and prune
  explicitly rejected protocols.
- **Home:** IR-500 through IR-530 retain the chosen responsive shell and
  interactions while S-11/S-21 remove only named dead branches.
- **Tasks:** IR-616 through IR-658 retain the chosen list, editing, recurrence,
  details, Undo, ordering, keyboard, and Assistant behavior while S-13 removes
  named dead fields and views.
- **Focus and Insights:** IR-659 through IR-682 retain the selected presentation
  and actions while S-14 localizes authority.
- **Rewind:** IR-683 through IR-699 and IR-899 through IR-921 are especially
  strict: preserve every explicitly accepted behavior and quirk while S-15
  removes only cloud copies and rejected Settings residue.
- **Managed Pi:** IR-923, IR-924, and IR-937 protect the complete local lifecycle
  and packaged extension core while S-05 strips alternate adapters and residue.
- **Backend/release safety:** IR-838 through IR-895 retain health, candidate,
  promotion, rollback, emergency, logging, security, and release guarantees
  while S-26 through S-29 narrow and re-own them.

## Complete IR routing matrix

This matrix accounts for all 714 reviewed ledger rows. A range can route to
multiple slices because one requirement may cross client, backend, and
infrastructure boundaries; the detailed decision still lives in the ledger.

| Ledger family | Implementation route |
|---|---|
| IR-001 through IR-016 | S-01, S-04, S-05, S-06, S-25, S-26; retained boundaries protected above |
| IR-017 through IR-023 | S-02, S-03, S-10, S-16 |
| IR-024 through IR-038 | S-12, S-13, S-14 |
| IR-039 through IR-053 | S-05, S-06, S-07, S-11, S-15, S-17, S-23 |
| IR-054 through IR-119 | S-03, S-05, S-07, S-09, S-10 through S-16, S-19, S-20, S-22; PTT guard register applies |
| IR-120 through IR-124 | S-08, S-10, S-17, S-23, S-25 |
| IR-125 through IR-169 | S-17 and S-30; onboarding guard register applies |
| IR-170 through IR-211 | S-08, S-09, S-18, S-30 |
| IR-212 through IR-255 | S-05, S-06, S-07, S-09, S-15, S-18, S-21, S-29, S-30 |
| IR-256 through IR-292 | S-06, S-10, S-12, S-23, S-24, S-30; Memories guard register applies |
| IR-293 through IR-405 | S-02, S-03, S-10, S-16, S-23, S-24; Conversations guard register applies |
| IR-500 through IR-530 | S-11, S-12, S-13, S-14, S-21, S-30; Home guard register applies |
| IR-600 through IR-615 | S-05, S-07, S-09, S-19, S-20, S-22 |
| IR-616 through IR-658 | S-13 and S-21; Tasks guard register applies |
| IR-659 through IR-699 | S-14, S-15, S-21; Focus/Insights/Rewind guards apply |
| IR-700 through IR-735 | S-10, S-12, S-14, S-17, S-20, S-22, S-23 |
| IR-800 through IR-837 | S-05, S-06, S-08, S-09, S-11, S-18, S-22 through S-26 |
| IR-838 through IR-891 | S-03, S-08, S-09, S-18, S-20, S-22, S-25 through S-27 |
| IR-892 through IR-897 | S-04, S-29, S-30 |
| IR-898 through IR-921 | S-02, S-15, S-16; Rewind guard register applies |
| IR-922 through IR-937 | S-01, S-04, S-05, S-09, S-11, S-28 through S-30 |
| IR-938 | S-06, including candidate integration outbox/drain cleanup; S-13 protects ordinary local tasks/candidate acceptance and must not recreate export |
| IR-939 | S-29; S-04 protects the present vendored cache during cleanup |
| IR-940 | S-04; S-29 protects the separately retained release/qualification system |
| IR-941 | S-04; live Notifications and Rewind remain protected behaviors |

## Realtime provider choice for v1 — keep both

The reviewed v1 requirement is decided: keep Auto, Gemini Live, OpenAI Realtime,
explicit switching, and failover. Choosing only one provider would be an optional
future simplification, not an open requirement or Wave blocker. Therefore:

- this choice does not block deletion/localization work;
- S-19 and S-22 must preserve both current providers and their tests;
- no new abstraction or migration should be added in anticipation; and
- if a future decision reopens consolidation, create one narrow successor slice that removes
  the losing provider end to end without changing the rest of PTT.

## Out of scope

- Any product-code deletion or adaptation during creation of this map
- Windows source, behavior, build, test, generated clients, release, docs, and
  automation
- New product features not already selected in the requirements ledger
- Re-deciding retained behavior merely because it is complex
- Any future consolidation of the decided v1 Gemini Live plus OpenAI Realtime portfolio
- Replacing battle-tested retained behavior with a speculative rewrite
- Opening issues, pushing branches, or creating a PR without a separate request

## Map maintenance

When a slice closes:

1. record the implementation commit and verification evidence here;
2. mark the slice closed rather than deleting its history;
3. re-run the requirements-ledger validator;
4. re-inventory the paths the slice was expected to unblock; and
5. update dependencies and split the slice's internal TDD cycle sequence only
   when implementation evidence shows independently verifiable codeflows. Do
   not create another `S-XX` or TDD plan without a new requirements-backed
   roadmap decision.

This keeps the plan attached to the real codebase instead of turning it into a
fixed hypothetical roadmap.
