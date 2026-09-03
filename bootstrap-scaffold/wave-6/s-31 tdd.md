# S-31 TDD plan — prove closure, measure cycle time, and automate the surviving loop

## 1. Title and slice identity

| Field | Value |
|---|---|
| Wave | **6 — truth and ship** |
| Slice | **S-31** |
| Name | **Prove closure, measure cycle time, and automate the surviving loop** |
| Type | Final integration, evidence, acceleration, and release acceptance |
| Primary decisions | **All 714 reviewed IR decisions as acceptance guardrails** |
| Roadmap authority | [`../deletion-map.md`](../deletion-map.md), S-31, the complete IR routing matrix, protected-behavior register, and shared closure contract |
| Decision authority | [`../requirements-challenge.md`](../requirements-challenge.md), all 714 indexed rows and all 714 detailed `### Decision` sections |
| Open closure authorities | [`../../BACKLOG.md`](../../BACKLOG.md), BL-001 and BL-002 |
| Payment activation authority | [`../dodo-integration.md`](../dodo-integration.md) |
| Earlier integrated evidence | [`../wave-4/wave-3-4-closeout tdd.md`](../wave-4/wave-3-4-closeout%20tdd.md) and every owning S-01 through S-25 plan |
| Future named development bundle | **`omi-wave6-s31`**; use the post-S-28 bundle identifier reported by the built app rather than guessing an inherited `com.omi.*` identifier |
| Planned implementation shape | **17 ordered TDD and acceptance cycles** |

This is the one S-31 implementation plan. Its planning body does not implement
a product feature, certify the planning baseline, or authorize a deployment or
payment. Section 19 records the later repository implementation evidence; it
does not turn missing operational evidence into closure. S-31 may integrate and
prove the final system, remove only residue whose owner is already closed,
improve only a measured surviving loop, and automate only a stable repeated
action. It may not absorb unfinished S-01 through S-30 product work.

## 2. Planning status and pinned baseline

**Status:** researched and structurally ready, but implementation is blocked
until S-01 through S-30 are integrated. The current baseline contains the
complete Waves 3–4 repair tree and no Wave 5 or S-30 implementation.

The required planning baseline is:

```text
22ad2f16ff8d63fd761c918b92f4c5d961814624
```

Planning-time checks on 2026-08-26 established:

```text
git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD
  PASS
git rev-parse HEAD
  22ad2f16ff8d63fd761c918b92f4c5d961814624
git rev-parse origin/main
  22ad2f16ff8d63fd761c918b92f4c5d961814624
git status --short --branch
  ## plan-waves-5-6-slices
```

The requirements validator also passed before drafting:

```text
Requirements ledger validation: PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

The indexed status column contains only reviewed variants; there is no
unreviewed ledger row. That structural result is not semantic or implementation
closure. Every detailed decision was treated as a final acceptance guardrail,
and the routing matrix in section 4 is the complete numeric coverage proof.

Current architecture differs materially from the required S-31 entry state:

- `backend/runtime_images.json` still registers `backend/main.py` and
  `backend/desktop_backend.py` as separate images/entrypoints; S-26 owns their
  consolidation and the surviving harness.
- `backend/deploy/runtime_env.yaml` and backend workflows still use inherited
  `us-central1` and Omi-named infrastructure assumptions; S-27 owns the
  `us-west1` retained foundation and owned identities.
- Mac bundle, storage, Keychain, update, URL-scheme, and test namespaces still
  carry inherited Omi identity; S-28 owns clean product namespaces.
- GitHub contains candidate, qualification, preview, promotion, recovery, and
  rollback controls, but the tracked Mac build/sign/notarize provider definition
  is absent; S-29 owns it and the owned external release identities.
- Visible identity, copy, disclosure, and public/legal truth have not received
  S-30's final pass.
- BL-001 and BL-002 remain open. `BILLING_MODE=disabled` is still the mandatory
  free-MVP state; Dodo test and live acceptance have not run.

No component suite, named bundle, provider request, cloud inventory, Dodo
resource, candidate, release, deployment, or production app was operated while
writing this plan. Commands below are future execution requirements, not claims
of passing evidence.

### 2.1 Execution-context refresh — 2026-08-29

This dated refresh supersedes the current-state bullets above when S-31 is
executed; it does not certify a final SHA or mark any S-31 cycle green.

- S-26 through S-29 are integrated on `origin/main` through
  `2a966c29f27e7604a129df3a9f595ff055d391a5`. The current provider-setup branch
  is `98ff1714b125b09b17d3ca741d090232be95901c`. S-30 is still unimplemented, so
  G0 remains closed.
- Development, Beta, and Stable Firebase app registrations now exist in
  `knowledge-athlete`; Google Auth is configured. Apple Auth remains enabled but
  unqualified pending the Apple Developer membership and owned identifiers.
- Development Cloud Run now serves owned revision
  `knowledge-athlete-dev-00002-pjn` from immutable `knowledge-athlete` Artifact
  Registry digest
  `sha256:3129ea2d5d2a67bb23d4c2db42894b5de33f005660cd733dfc1b443e797379c8`.
  The public health route and Google authorize/Redis-session redirect boundary
  passed. This setup proof is intentionally not the final-SHA deploy, streaming,
  recovery, rollback, alert, or provider evidence required by Cycles 13–16.
- The permanent-cost development shape is zero minimum/one maximum instance,
  request-based CPU, one vCPU, 2 GiB, Upstash TLS Redis, and disabled billing.
  The single inherited backend image currently consumes 789.033 MB of registry
  storage, about 277 MB beyond the provider's 0.5 GiB-month free allowance
  (roughly USD 0.03/month at the observed price). S-31 must measure current cost
  truth rather than describe this as literally zero-cost.
- The owner has approved one free Upstash database for development and early
  MVP production until traction. This conflicts with S-31's planned
  separate-dev/prod Redis acceptance row. Before that row can be green, either
  the authoritative requirement must explicitly accept the temporary shared
  topology or production must receive an isolated Redis resource; S-31 must not
  silently reinterpret the existing row.
- Codemagic, repository-owned workflow IDs, the new Sparkle keypair, Firebase
  build inputs, and Sentry symbol upload are configured. Apple
  signing/notarization, preview storage/registry, production origins/URLs,
  GitHub release application, trusted Apple Silicon runner, and real signed
  candidate/channel evidence remain open.
- Retained-caller analysis narrows the managed-provider gate: Gemini owns
  managed text, embeddings, and realtime voice; OpenAI owns TTS only; Modulate
  owns managed batch and streaming STT; PostHog owns product
  telemetry; and Langfuse owns model tracing and prompt management. Google
  Calendar, both Anthropic credentials, Artificial Analysis, provider
  selection, OpenAI text/realtime, and Vertex inference are deleted and must
  not be provisioned. The Gemini and Langfuse repository paths are implemented,
  but the active Cloud Run revision does not bind their exact secret versions.
  The owned Modulate key is now prepared with a 500-credit and two-model limit,
  but it likewise has no live-provider evidence. S-31 must prove the single
  Gemini Developer API route and must not recreate `USE_VERTEX_AI=true` or any
  deleted provider merely to satisfy an inherited declaration.

These facts reduce setup ambiguity but do not weaken G2, G5, or the one-final-SHA
rule. Missing real-provider, Apple, preview, production, runner, and S-30 inputs
remain explicit blocked evidence rows, never inferred green prerequisites.

### 2.2 Gemini-first provider refresh — 2026-09-01

The provider gate is now intentionally smaller than §2.1's audited Omi state.
One development `GEMINI_API_KEY` owns Gemini 3.7 Flash, the existing Flash-Lite
workloads, embeddings, and Gemini Live. One `OPENAI_API_KEY` remains TTS-only.
Anthropic, Artificial Analysis, `USE_VERTEX_AI`, OpenAI text/embeddings/realtime,
provider selection, and the omni relay are deleted from the runtime contract.
The owned Modulate key is now stored as exact development Secret Manager version
1 and limited to the retained batch and streaming models, but live batch recovery
cannot be claimed until an authorized development deployment binds and exercises
it. The dormant Gemini secret may be inspected, but an exact version must not be
bound to Cloud Run without separate deployment authorization. Langfuse tracing
and prompt management are already implemented;
their exact development secret bindings and one real fail-open trace remain
required S-31 evidence.

## 3. Outcome

S-31 closes only when one immutable committed SHA after S-01 through S-30 has a
complete, internally consistent evidence graph proving all retained behavior,
all approved deletions, all adapted ownership, all S-31-required external
acceptance, and every one of the 714 reviewed decisions. Post-Wave-6 S-18/Dodo
test/live acceptance is accounted for by a complete successor handoff, not by
running it inside S-31.

The final result must prove, without inference:

1. repository source, contracts, generated artifacts, docs, and tests describe
   only the surviving macOS product and retained backend;
2. component, hermetic backend, fault, Tier-2, named-bundle, account-lifecycle,
   physical PTT, real-provider, provider-mint, and continuity lanes pass on the
   same final SHA;
3. BL-002's verified read-only live inventory classifies every retained,
   rejected, shared, already-absent, or unknown resource before any mutation;
4. the canonical development backend can deploy, authenticate, stream, enqueue
   durable account deletion, recover, and roll back under owned infrastructure;
5. `BILLING_MODE=disabled` remains the truthful free-MVP release state with no
   catalog, checkout/portal action, provider construction, request, or entitlement
   mutation, and the complete S-18/Dodo test-then-live handoff is recorded for
   separate execution only after S-31 closes all six waves;
6. a signed/notarized candidate from that SHA installs, updates, qualifies,
   promotes, previews, and rolls back through the owned release system, with
   Stable remaining a separate explicit operation;
7. clean install, upgrade from this product's own first build, reset, sign-out,
   account switch, export, uninstall/reinstall, and local-owner isolation never
   read or mutate an Omi installation;
8. setup, focused-test, local-stack, named-bundle, deploy, candidate,
   qualification, and rollback times are measured before any acceleration; and
9. only the highest-value stable repeated bottleneck is accelerated or
   automated, followed by a complete final-SHA rerun if repository state changed.

Passing repository tests is not a release claim. Missing credentials, operator
identity, payment resources, signing identity, runner access, deployment proof,
or any red acceptance row leaves S-31 open. There is no waiver-by-absence and no
`NOT_RUN`-as-green disposition.

## 4. Authorizing requirements

### 4.1 Complete 714-decision routing

The following matrix is the complete numeric coverage of the live requirements
ledger. Each family is accepted through its owning S-01 through S-30 evidence
plus the final S-31 lanes named here. A range may have multiple earlier owners;
S-31 composes their final behavior and does not reopen their decisions.

| Ledger family | Earlier owner route | S-31 final acceptance focus |
|---|---|---|
| IR-001 through IR-016 | S-01, S-04, S-05, S-06, S-25, S-26 | No Agent VM, alternate agent entrance, wearable sync service, duplicate backend, or impossible control; managed Pi and local tools still work. |
| IR-017 through IR-023 | S-02, S-03, S-10, S-16 | Mac capture plus transient `/v4/listen`, local conversation commit, Modulate, local Parakeet, language/vocabulary, and generic speakers. |
| IR-024 through IR-038 | S-12, S-13, S-14 | Local Memories, Tasks/Goals, Focus/Insights/profile/proactive authority, restart durability, and owner isolation. |
| IR-039 through IR-053 | S-05, S-06, S-07, S-11, S-15, S-17, S-23 | Local Chat/Home/Rewind and scoped tools survive; hosted products, connectors, BYOK, and cloud copies do not. |
| IR-054 through IR-119 | S-03, S-05, S-07, S-09 through S-16, S-19, S-20, S-22 | Complete physical PTT/realtime lifecycle through Gemini Live, same-provider recovery, local grounding, privacy, continuity, diagnostics, and exact deleted tools. |
| IR-120 through IR-124 | S-08, S-10, S-17, S-23, S-25 | Durable account deletion, narrowed account metadata, truthful export, and removed cloud product/account residue. |
| IR-125 through IR-169 | S-17, S-30 | Narrow onboarding, permissions, Skip/completion/restart behavior, and final truthful copy. |
| IR-170 through IR-211 | S-08, S-09, S-18, S-30 | Owned auth/telemetry/privacy, account lifecycle, Dodo behavior, and truthful disclosure. |
| IR-212 through IR-255 | S-05, S-06, S-07, S-09, S-15, S-18, S-21, S-29, S-30 | Settings, shell, notifications, PTT controls, update/public links, and removed developer/connector/provider surfaces. |
| IR-256 through IR-292 | S-06, S-10, S-12, S-23, S-24, S-30 | Full local Memory behavior and provenance with no hosted Memory/search/vector authority. |
| IR-293 through IR-405 | S-02, S-03, S-10, S-16, S-23, S-24 | Full local Conversations/transcription behavior with no server product authority or cloud product objects. |
| IR-500 through IR-530 | S-11 through S-14, S-21, S-30 | Home/Chat shell and projections from one local product mind. |
| IR-600 through IR-615 | S-05, S-07, S-09, S-19, S-20, S-22 | Explicit fixed managed model portfolio, fair-use split authority, typed workload ownership, and observability. |
| IR-616 through IR-658 | S-13, S-21 | Local task/goal UX, recurrence, order, Undo, assistant, and deleted task-intelligence/productivity surfaces. |
| IR-659 through IR-699 | S-14, S-15, S-21 | Exact Focus/Insights/Rewind behaviors, including deliberately retained quirks. |
| IR-700 through IR-735 | S-10, S-12, S-14, S-17, S-20, S-22, S-23 | Model-result ownership, fair-use behavior, onboarding lifecycle, and deleted hosted products. |
| IR-800 through IR-837 | S-05, S-06, S-08, S-09, S-11, S-18, S-22 through S-26 | Managed Pi only, canonical backend/product teardown, billing, account/export, and retained observability. |
| IR-838 through IR-891 | S-03, S-08, S-09, S-18, S-20, S-22, S-25 through S-27 | Owned Cloud Run/WIF/IAM/Redis/Firestore/GCS/Tasks/Artifact Registry, health, security, release semantics, and local/offline harness. |
| IR-892 through IR-897 | S-04, S-29, S-30 | Owned Mac build/sign/notarize/release/preview/public site and no impossible absent-tree controls. |
| IR-898 through IR-921 | S-02, S-15, S-16 | Three-way System Audio and every explicitly retained Rewind behavior/quirk. |
| IR-922 through IR-937 | S-01, S-04, S-05, S-09, S-11, S-28 through S-30 | No local HTTP agent API or orphan runtimes; managed Pi, clean storage identity, updates, and final brand truth. |
| IR-938 | S-06 with S-13 protection | No external task export; local task candidate acceptance remains. |
| IR-939 | S-29 with S-04 protection | Owned universal libwebp/libsharpyuv provenance, architecture, signing, minimum-OS, and rebuild evidence. |
| IR-940 | S-04 with S-29 protection | Nested undiscoverable installer workflow remains deleted; owned release qualification remains. |
| IR-941 | S-04 | Unreferenced media remains deleted; live Notifications and Rewind remain protected. |

The apparent numeric gaps are IDs that do not exist in the 714-row ledger; this
is the same complete routing partition validated by
`validate-requirements-ledger.py`. S-31 must rerun that validator at entry and
at final closure and must record any changed detailed decision as a stop.

### 4.2 Cross-cutting authorities that cannot be diluted

- **Protected behavior:** the deletion map's PTT, onboarding/authentication,
  Memories, Conversations/transcription, Home, Tasks, Focus/Insights, Rewind,
  managed-Pi, and backend/release registers are acceptance fences, not cleanup
  suggestions.
- **BL-001:** one final SHA must pass component, hermetic E2E, agent-logic,
  Tier-2, natural authenticated physical PTT, Gemini Live, same-provider
  reconnect, tools, typed-to-PTT blind recall, deploy-inline mint, and the
  buffered batch-recovery lane. A fake/echo response cannot prove live-provider
  continuity; until the prepared Modulate key is deployed, the hermetic STT seam
  proves only the Modulate path's client behavior.
- **BL-002:** repository absence cannot classify a live resource. Verified
  operator/environment/project identity is mandatory before read-only inventory,
  and mutation needs separate authorization.
- **Dodo:** free MVP and `BILLING_MODE=disabled` remain the entry state. Test mode
  is post-Wave-6 and separately authorized; live mode is a second, distinct
  authorization and resource set.
- **One-final-SHA rule:** every S-31 evidence manifest must resolve to the same
  full SHA. A documentation, test, acceleration, or automation commit invalidates
  older candidate evidence and triggers the rerun rules in Cycles 10–16. The
  later S-18/Dodo handoff records its own post-Wave-6 execution SHA and may not be
  relabelled as S-31 evidence.
- **No released inherited population:** do not restore compatibility for Omi
  users, cloud data, local stores, APIs, bundle IDs, payment IDs, or resources.
  Compatibility retained by explicit drain/upgrade decisions is the only
  exception and remains evidence-gated.

## 5. Dependencies and entry gates

### G0 — all predecessor implementations, not plans, are integrated

S-31 requires integrated S-01 through S-30. The current baseline satisfies only
the existing implementation/repair tree through S-25. Before Cycle 0, fetch and
integrate the current `origin/main`, then prove every owning implementation and
handoff is present. Planning files are not implementation evidence.

The exact Wave 5/6 shapes S-31 expects to consume are:

- **S-26:** one canonical Python application/image/URL per environment and one
  production-shaped local/offline harness; route policy, OpenAPI, generated
  non-Windows Swift, runtime images, Firestore indexes, and fixtures agree.
- **S-27:** owned development/production `us-west1` Cloud Run, WIF, dedicated
  runtime identities, exact secret versions, separate TLS/AUTH Redis, retained
  Firestore indexes/GCS/account-deletion queue, Artifact Registry digests,
  budgets, logs, alerts, deploy, promotion, rollback, and break glass.
- **S-28:** owned bundle/app-group/Keychain/URL/login-item/storage/cache/log/test
  namespaces with clean stores, owner fencing, and no Omi takeover behavior.
- **S-29:** owned build-provider definition, Developer ID/notarization/Sparkle
  identities, signed candidate and preview production, qualification,
  Beta/Stable promotion, recovery/rollback, public site, and release links.
- **S-30:** current product surfaces contain no Omi identity or false
  local/cloud/privacy/billing/update/support claim; historical changelogs and
  required MIT provenance remain truthful history.

If any shape is absent, stop the consuming S-31 cycle and return the defect to
the owning slice. Do not create an S-31 compatibility adapter or duplicate path.

### G1 — final candidate SHA and evidence identity

After all repository fixes, acceleration, and automation changes are complete,
Cycle 10 freezes one full committed SHA. Evidence must include that SHA, branch,
source repository, build tag/digest where applicable, environment, bundle ID,
provider mode, timestamps, and outcome. Evidence without a SHA, evidence from a
dirty tree, or a stale manifest is not admissible.

Any later repository edit unfreezes the SHA and invalidates all evidence that
could observe changed source. Return to Cycle 10; never relabel an older
artifact.

### G2 — external identities and physical prerequisites

The provider and physical lanes require:

- an approved non-production Gemini credential, the retained TTS-only OpenAI
  credential, and—when live batch recovery is exercised—Modulate credentials;
- a verified deployed development backend identity and safe Firebase test
  principal for mint/direct-provider proof;
- a named non-production bundle with authenticated owner, working microphone,
  required TCC permissions, actual captured audio, and isolated automation port;
- access to sanitized application/backend evidence without exposing bearer
  tokens, provider keys, prompts, transcripts, owner IDs, or raw audio.

Missing any item blocks Cycles 13 and 17, not the earlier hermetic/repository
work. It never downgrades a row to optional.

### G3 — BL-002 operator and live inventory identity

Read-only inventory requires a verified operator, exact environment, project,
region, and ownership authority. Local config names or inherited Omi project
strings are not proof. Unknown classes remain `unknown`.

No deploy, traffic shift, queue drain, service deletion, IAM/secret/image/network
mutation, data cleanup, or release is authorized by inventory. Each mutation
needs exact named targets, before/after evidence, retention/legal/rollback
boundaries, and fresh user authorization.

### G4 — post-Wave-6 S-18/Dodo handoff boundary

S-31 must not create or use Dodo test/live resources. Cycle 15 proves the final
disabled checkpoint and emits a complete handoff to `dodo-integration.md`.
Only after S-31 closes all six waves may a separately authorized S-18 run create
test resources and perform test-mode acceptance; live mode then requires a
second distinct authorization and resource set. Test/live secrets and provider
IDs stay outside git and S-31 evidence.

### G5 — release/signing gate

Cycle 16 requires S-29's owned build-provider configuration, GitHub release
identity, provider token, Developer ID and notarization access, Sparkle private
key/feed/bucket, isolated qualification runner, preview/public domains and TLS,
protected GitHub environments, and explicit approval for any Beta/Stable/public
mutation. Missing credentials keep the release row open.

### G6 — production-app safety

Never use `/Applications/Omi.app`, `/Applications/Omi Beta.app`,
`com.omi.computer-macos`, or `com.omi.computer-macos.beta` as S-31 test targets.
S-28/S-30 may remove those identifiers from the product, but S-31 still treats
the inherited production bundles as untouchable. Use only `omi-wave6-s31`,
isolated harness bundles, signed candidate copies in controlled install roots,
and the post-S-28 product identities proven by their manifests.

### External-input gate table

| Missing input | Affected cycles | Safe work that can proceed | Evidence to reopen | Expected owner | Explicit authorization? |
|---|---|---|---|---|---|
| Integrated S-26 through S-30 | 0–16 | Planning only | Merged commits, owner closeouts, current-tree inventory | Slice owners | Normal landing authority; no external mutation |
| Real provider credentials and dev deployment identity | 13, 16 | Cycles 0–12; offline evidence | Redacted credential-presence check, verified deployment, disposable principal | Provider/platform owner | Yes for credentialed provider activity |
| Working mic/TCC/authenticated named bundle | 13 | All nonphysical lanes | `omi-ctl health`, TCC state, captured-byte and terminal-result evidence | Desktop acceptance owner | No production-app authority; local test only |
| Verified GCP operator/project/environment | 14 | Repository and local acceptance | Operator identity plus authoritative S-27 environment manifest | Platform owner | Read-only identity first; yes for later mutation |
| Post-Wave-6 Dodo test/live resources and authorization | Not an S-31 cycle | All S-31 work and free-MVP release acceptance with billing disabled | Closed S-31/all-six-waves record, then the external inputs and separate authorizations in `dodo-integration.md` | S-18/billing owner | Explicit test authorization after S-31; separate explicit live authorization after test acceptance |
| Signing/notarization/Sparkle/build-provider/runner identities | 16 | Named dev bundle and repository closure | S-29-owned configuration and successful isolated canaries | Release owner | Yes for candidate/channel/public operations |
| Stable/public release approval | Stable portion of 16 | Candidate, qualification, preview, Beta rehearsal where authorized | Exact qualified tag/digest and promotion review | Product/release owner | Separate explicit yes |

## 6. Current production codeflow

This is the exact planning baseline, before S-26 through S-30. Refresh it after
every predecessor integrates.

### 6.1 Retained local product path

```text
macOS UI / onboarding / Home / Memory / Tasks / Insights / Rewind / PTT
  -> AuthService + active owner/generation fences
  -> owner-scoped Application Support and Keychain
  -> TranscriptionStorage / MemoryStorage / ActionItemStorage / GoalStorage
  -> FocusStorage / InsightStorage / local Rewind SQLite/video/OCR/vectors
  -> local Node Chat catalog + kernel journal + app-managed attachments
  -> managed Pi + pi-mono-extension + OMI_BRIDGE_PIPE + ChatToolExecutor
  -> authenticated bounded transient backend requests when required
  -> Mac validates result and commits through the owning local store
```

Concrete owners include
`ConversationRepository.swift`, `TranscriptionStorage+LocalAuthority.swift`,
`MemoryStorage.swift`, `ActionItemStorage.swift`, `GoalStorage.swift`,
`FocusStorage.swift`, `InsightStorage.swift`, `ChatProvider.swift`,
`KernelTurnProjection.swift`, `LocalUserDataExport.swift`,
`PushToTalkManager.swift`, and the `RealtimeHubController+*.swift` state-machine
extensions. S-31 protects their established behavior; it does not consolidate
them for style.

### 6.2 Backend and managed-compute path

The current tree exposes two Python images/entrypoints:

```text
Mac
  -> backend/main.py
       auth, account/subscription/usage/export/deletion
       /v4/listen -> in-process VAD -> managed Modulate -> transient segments
       conversation and Memory proposal compute
       fair-use classification with content-free durable enforcement facts
       update/release/preview authority
       durable account-deletion queue -> OIDC handler on canonical backend
  -> backend/desktop_backend.py
       managed Chat/realtime/TTS/update helpers still selected by desktop routing
```

`backend/runtime_images.json` registers both `backend` and `desktop-backend`.
S-26 must collapse this to the one canonical application/URL and adapt the
offline harness before S-31 begins. S-31 then verifies auth, quota/fair use,
transient STT/models, health, metrics, update/release, and account deletion
through that one assembled app.

Billing is independently disabled. The retained routes exist but must construct
no Dodo client or provider request until the separately authorized post-Wave-6
S-18 test/live procedures.

### 6.3 Current deployment and live-resource boundary

`backend/deploy/runtime_env.yaml`, `gcp_backend.yml`, and
`gcp_backend_auto_dev.yml` still carry inherited `us-central1` and Omi-shaped
network/resource identities. The current OpenTofu tree is a pilot/scaffold, not
S-27's owned final foundation. BL-002 records every live resource class as
`unknown` because no verified operator/project identity was available.

S-27 must first own the canonical `us-west1` Cloud Run, WIF, service accounts,
Redis/TLS/network, Firestore indexes, update/preview GCS, account-deletion queue,
Artifact Registry, logs, alerts, budgets, deploy, rollback, and break-glass
contracts. S-31 verifies those outputs; it does not guess from current names.

### 6.4 Current installation and release path

The baseline still uses Omi bundle IDs, URL schemes, Keychain services,
Application Support paths, update feed/key, domains, telemetry projects, signing
profiles, and visible identity. GitHub controls currently cover candidate
planning/tagging, provider-intake observation, M1 qualification, preview,
Beta/Stable admission, recovery, rollback, and break glass. The tracked external
build/sign/notarize provider definition is absent.

S-28 owns local namespace isolation; S-29 owns artifact production and the
external release system; S-30 owns final visible truth. S-31 consumes a signed
artifact and exact manifest from those owners and proves install/update/release
without reconstructing their systems.

### 6.5 Existing evidence path and known gap

Current evidence is distributed among unit/component suites, backend hermetic
E2E, `.harness/desktop-core/*/manifest.json`,
`.harness/agent-continuity-gauntlet/*/manifest.json`, signed-smoke JSON,
qualification evidence, workflow artifacts, release manifests, PR body, and
owner plans. The Waves 3–4 closeout demonstrated why aggregation alone is
unsafe: a stale Tier-2 SHA and fake-provider continuity could look healthy while
required physical/provider rows remained open.

S-31's final evidence record must link—not replace—each owning slice record and
must reject mixed SHAs, missing rows, fake substitution, and unknown live state.

## 7. Complete caller and dependency inventory

Refresh this table on the integrated S-30 tree. “Expected after predecessor” is
a hard contract to consume, not a statement that the current baseline already
has it.

| Family | Current concrete owners | Expected after predecessor integration | S-31 acceptance / disposition |
|---|---|---|---|
| Requirements and roadmap | `requirements-challenge.md`, validator, deletion map, 31 owner plans, BL-001/002, Dodo handoff | 714 decisions unchanged; S-01–S-30 have implementation evidence | Map every row to owner + final evidence; no open decision fog |
| Mac auth/account | `AuthService`, `AuthSessionCoordinator`, `APIClient+Account`, Firebase/OAuth routes | Owned Firebase/Apple/Google identity, fail-closed session lifecycle, local export, durable deletion | Restore/sign-in/refresh/sign-out/switch/export/delete with disposable identities |
| Local storage identity | `DesktopLocalProfile`, `DesktopKeychainStore`, Rewind/GRDB/Node stores, defaults/login item/cache/log roots | Product-owned clean namespaces, no Omi takeover/import/termination/deletion | Clean install, own upgrade, reset, sign-out, switch, uninstall/reinstall |
| Conversations/transcription | `ConversationRepository`, `TranscriptionStorage`, `/v4/listen`, conversation compute | Mac authority, fixed PCM transient STT, local/manual speakers, no server conversation | Offline and real-provider capture/finalize/list/detail/search/folder/star/merge/delete |
| Memories/search | `MemoryStorage`, local vectors/FTS, three Memory compute routes, embedding proxy | Local lifecycle/search/provenance with bounded transient compute | CRUD/Undo/lifecycle/restart/owner switch/semantic search; no hosted/vector residue |
| Tasks/goals | `ActionItemStorage`, `GoalStorage`, Tasks stores/views/tools | One local task/goal authority, no external export/intelligence/workstreams | UI/Chat/PTT/proactive CRUD, recurrence/order/reminders/Undo/offline/restart |
| Focus/Insights/profile | `FocusStorage`, `InsightStorage`, local profile/proactive assistants | Owner-local state and notifications, no hosted product authority | Capture truth, history, profile, advice, local notifications, owner isolation |
| Rewind | local SQLite/video/OCR/vector/capture/recovery/retention | Exact retained behavior and quirks, no cloud copy | Artifact recovery, search, permissions, retention, local PTT grounding |
| Chat/Home/managed Pi | Node catalog/journal, `ChatProvider`, Pi runtime, bridge/tools | One Home Chat authority, one managed Pi, scoped tools/attachments | Create/switch/restart, typed turns, tools, agents/pills, continuity, faults |
| PTT/realtime | `PushToTalkManager`, `RealtimeHubController`, Gemini Live session, batch recovery | Gemini-only realtime, same-provider reconnect, exact local grounding and lifecycle | Natural physical capture plus Gemini Live/reconnect/tools/blind recall and buffered batch recovery |
| Fair use/quota | Redis meters, Firestore enforcement facts, local evidence request/UI | Content-free backend authority + transient bounded local evidence | Threshold/recovery/restriction/fail-open/support reset/no-content durability |
| Billing | `payment.py`, Dodo utilities/subscription, Mac plan/usage/web flow | Disabled free MVP plus test/live-ready Dodo contract, no Stripe/Omi IDs | Disabled proof and complete post-Wave-6 S-18 handoff; no Dodo test/live operation in S-31 |
| Canonical backend | `main.py`, `desktop_backend.py`, two images today | One app/image/URL, one local/offline harness | Health, metrics auth, routes, STT, models, account deletion, startup/shutdown/faults |
| Firestore/Redis/GCS/Tasks | database modules, runtime env, index registry, task dispatcher, release storage | Only retained account/billing/usage/deletion/release state under owned projects | Repo contract + verified read-only live inventory + authorized dev acceptance |
| Cloud Run/IAM/network | deploy workflows/scripts, OpenTofu pilot, runtime env | Owned S-27 foundation in `us-west1` | Exact SHA/digest deploy, auth, streaming, rollback, break glass, least privilege |
| Images/registries | `runtime_images.json`, Dockerfiles, Artifact/legacy registry paths | One canonical image plus S-29 artifacts, immutable full-SHA/digest identity | Source closure, smoke, serving/rollback reference graph, no `latest` |
| Routes/OpenAPI/generated client | `main.py`, route policy, OpenAPI exporters, generated Swift | Surviving app-client only; deleted routes truly absent | Assembled-app 404/fail-closed plus freshness checks; no hand editing |
| Repository controls/docs | check manifest, workflow contracts, component guides, `PRODUCT.md`, `FORK.md` | Current retained commands, owners, env, service and product truth | Full preflight, residue classification, no orphan checks or false docs |
| Build/sign/notarize | S-29 provider definition, entitlements, profiles, libwebp cache, signed smoke | Owned universal app/dSYM/DMG/Sparkle ZIP with provenance and notarization | Digest/signature/notary/Gatekeeper/architecture/minimum-OS/package smoke |
| Updates/channels | Sparkle policy, backend manifests/pointers, candidate/qualification/promotion/recovery/rollback workflows | Owned feed/key/assets, Beta/Stable authority, activity gates | Own-first-build update, required update, Beta qualification, rollback, manual Stable |
| Previews/public/legal | preview registry/workflow, product site, Terms/Privacy/support/GitHub Releases | Owned signed previews and truthful reachable destinations | Publish/open/replace/delist mutable preview pointer while retaining immutable manifest/artifact evidence; link/status/content inventory; no Omi destination |
| Telemetry/support | PostHog/Sentry/Langfuse, local QueryTracer, diagnostics/export/report | Owned projects, consent, redaction, 30-day platform logs | Opt-out, identity detach, fallback signals, feedback dry run, no sensitive evidence |
| Windows | Outside the macOS roadmap | Outside the macOS roadmap | Do not inspect, edit, test, generate, release, or use as closure evidence |

## 8. Behavior classification

| Category | Concrete S-31 behavior |
|---|---|
| **KEEP AS IS** | Every protected behavior in the deletion map and `PRODUCT.md`: local product authorities, managed Pi, PTT/realtime semantics, `/v4/listen`, fair-use/quota behavior, auth/account deletion, Sparkle activity gates/channels/rollback, previews, privacy-bounded telemetry, and all explicitly retained UI/quirks. S-31 does not redesign them. |
| **ADAPT** | Compose existing owner evidence into one exact-SHA acceptance graph; run the final paths against S-26/S-27/S-28/S-29/S-30-owned identities and topology; prove the disabled billing checkpoint and emit the post-Wave-6 S-18/Dodo handoff without activation; bind release evidence to owned artifact identities. |
| **DELETE** | Only unexplained executable residue whose owning slice already made dead: rejected product/provider/service/route/schema/config/secret-name/workflow/doc/navigation/current-brand references, stale compatibility shells, or stale evidence pointers. If behavior is not already decided and owner-closed, return it to that owner. |
| **SIMPLIFY AFTER** | After full correctness and residue classification, remove duplicate evidence entry points, redundant manual evidence transformations, or obsolete final-owner lists only where one surviving shared primitive can replace them. No product or infrastructure redesign. |
| **ACCELERATE AFTER** | Measure clean setup, focused test, local stack, incremental/full named bundle, backend deploy, candidate intake, qualification, promotion/recovery, and rollback. Improve only the highest avoidable repeated delay proven by the measurements; otherwise `none`. |
| **AUTOMATE LAST** | Extend an existing check/manifest/workflow only for a stable repeated step observed during S-31. Prefer current evidence manifests and lanes. If no repeated bottleneck or correctness gap remains, `none`. |
| **OUT OF SCOPE / DEFERRED** | New product features, UI redesign, speculative refactors, production capacity redesign, Windows, Omi data takeover, bulk cloud teardown, unsupported compatibility, another roadmap slice, and any external mutation lacking its named authorization. Langfuse implementation is integrated; only its live secret binding and provider proof remain in scope for closure evidence. |

## 9. Retained behavioral invariants

1. **One final SHA.** All S-31 source-derived evidence, bundles, images,
   candidates, manifests, provider rows, disabled-billing rows, and release
   records resolve to the same full committed SHA. Any later code/doc/test/control
   edit resets affected evidence. The post-Wave-6 S-18/Dodo run records its own
   later execution SHA and remains outside S-31 closure.
2. **One owner per durable product fact.** Conversations, Memories, Tasks/Goals,
   Focus/Insights/profile, Chat, Rewind, drafts, and attachments remain
   owner-scoped Mac authorities. Backend compute never becomes a shadow store.
3. **Owner-generation fencing.** Sign-out, account switch, same-UID
   reauthentication, auth loss, reset, restart, timeout, and late async results
   cannot leak or commit stale state.
4. **Transient compute stays transient.** STT, model, translation, embedding,
   conversation, Memory, and fair-use proposal inputs/results are bounded,
   authenticated, privacy-sanitized, and committed only by the Mac owner.
5. **Managed access only.** No customer BYOK, hidden provider override, raw
   provider secret, or entitlement bypass reaches Chat, PTT, STT, TTS, embedding,
   or model routes.
6. **PTT is physical and continuous.** Final voice proof uses actual captured
   audio on the named bundle, Gemini Live with same-provider reconnect, and
   typed -> PTT -> blind recall. The buffered batch-recovery UI is proved
   hermetically until the prepared Modulate secret is deployed and exercised.
   Controller, manager, reducer,
   forced-text, and echo runs are supporting evidence only.
7. **Durable account deletion.** Persisted intent, opaque task, exact OIDC
   signer/audience, lock, retry, reconciliation, billing cancellation, auth
   deletion, retained Firestore cleanup, and terminal state remain. No inline
   wipe, fake success, or guessed drain.
8. **Billing starts disabled.** Disabled mode exposes no catalog/checkout/portal,
   constructs no client, performs no provider request, grants no entitlement,
   and leaves quota/fair-use state untouched. Test and live activation are
   separate resources and authorizations.
9. **Failure remains truthful.** Auth, provider, quota, Redis, persistence,
   network, deploy, update, notarization, payment, and release failures surface
   their typed owner behavior and never silently switch authority or fabricate
   success.
10. **Deleted means absent.** No no-op route/service, 410 compatibility shell,
    alias, ignored field, fake-success response, dormant switch, or duplicate
    adapter survives solely to resemble the inherited product.
11. **Release is evidence-bound.** Candidate creation is separate from
    visibility; qualification is digest/SHA-bound; Beta is automatic only after
    qualification; Stable is manual; rollback cannot reach Stable or downgrade
    installed clients.
12. **Installation is isolated.** Clean install, upgrade from this product's
    own first build, reset, sign-out, switch, and reinstall never read, launch,
    terminate, import, migrate, overwrite, or delete an Omi app or store.
13. **Live inventory precedes mutation.** Repository absence is not live
    absence. Unknown identity or shared ownership stops only that resource
    family and remains recorded as `unknown`.
14. **Evidence is privacy bounded.** No secrets, bearer tokens, raw IDs, PII,
    prompts, transcripts, audio, screenshots, provider bodies, payment IDs, or
    customer data enter git, logs, screenshots, manifests, PR text, or closeout.
15. **Automation follows measurement.** S-31 may automate only an observed,
    repeated, stable operation with understood inputs, outputs, failure behavior,
    and an existing blocking audience.
16. **Windows remains nonexistent for this effort.** No Windows path participates
    in implementation, generated output, tests, release, residue cleanup, or
    evidence.

## 10. Target authority, ownership, identity, and topology model

```text
one final committed SHA
  |
  +-- requirements authority
  |     714 indexed rows == 714 detailed decisions
  |     every row -> owning slice -> behavioral/operational evidence
  |
  +-- Mac product authority
  |     owned bundle + app group + Keychain + Application Support
  |     local GRDB/SQLite/FTS/vectors/files + Node Chat catalog/journal
  |     owner/generation-fenced UI, capture, Chat, PTT, tools, export
  |
  +-- one canonical Python backend in owned development/production
  |     Firebase auth, billing/quota/fair use, transient STT/models
  |     health + authenticated metrics + updates/releases
  |     durable account-deletion task handler on the same service
  |
  +-- retained managed dependencies only
  |     owned Firebase / Cloud Run / Redis / Firestore / GCS / Cloud Tasks
  |     Artifact Registry / Secret Manager / Logging / alerts / budgets
  |     approved Gemini / OpenAI TTS / Modulate
  |     Dodo disabled -> authorized test -> separately authorized live
  |     PostHog / Sentry / Langfuse
  |
  +-- owned Mac release system
        build provider -> Developer ID -> notarization
        DMG + Sparkle ZIP + dSYM + signed-smoke digests
        immutable candidate -> M1 T2/fault qualification
        qualified Beta -> manual Stable
        preview / recovery / rollback / break glass
        owned feed, domains, site, Terms, Privacy, support, release notes
```

The evidence graph has four explicit lanes:

1. **repository and local verification** — reversible source/test/build/harness
   work in the assigned worktree and named non-production bundles;
2. **credentialed non-production qualification** — real providers and owned
   development services using disposable principals;
3. **verified read-only live inventory** — no mutation, with authoritative
   operator/environment/project identity; and
4. **separately authorized mutation/release** — deploys, drains, decommissions,
   channel movement, public preview/site, Beta/Stable, or other externally
   visible S-31 changes. Dodo resource creation/activation is a post-S-31 S-18
   lane and cannot substitute for or block this roadmap closure.

No lane can substitute for another.

## 11. Ordered TDD cycles

All REDs below are future execution contracts. Behavioral tests exercise
production seams with fakes or assembled apps; static searches are labelled
tripwires. Evidence-only cycles still fail closed on missing rows. If a cycle
finds predecessor-owned behavior missing, fix it in the authoritative owner
boundary, integrate it, and restart the affected final-SHA evidence rather than
adding an S-31 workaround.

### Cycle 0 — consume S-01 through S-30 and characterize the final candidate tree

- **Intended contract RED:** a slice/evidence ledger rejects any missing S-01
  through S-30 implementation, unintegrated handoff, dirty worktree, changed IR
  decision, unclassified owner, or current surface that still matches the
  pre-S-26/S-30 architecture.
- **Why it fails now:** the pinned planning baseline contains no S-26 through
  S-30 implementation and still has two Python images, inherited region/
  identity, and no tracked build-provider definition.
- **Minimum GREEN:** fetch/rebase on current `origin/main`; record full HEAD,
  merge base, branch, status, commits since this baseline, and each owner
  implementation/closeout; rerun the 714/714 validator; refresh sections 6–7
  from source, tests, manifests, docs, and generated artifacts. Make no product
  change in this characterization cycle.
- **Retained behavior protected:** all predecessor ownership and the entire
  section 9 invariant set.
- **Expected change surfaces:** execution evidence/PR notes only. Any missing
  predecessor change belongs to its owning slice.
- **Exact focused verification:** baseline Git commands from section 2,
  `python3 bootstrap-scaffold/validate-requirements-ledger.py`, `git diff --check`,
  and owner-plan/commit inventory.
- **Deletion/simplification enabled:** identifies only proven post-owner residue
  eligible for Cycle 2.
- **Stop:** any predecessor absent, changed decision, overlapping unrelated
  work, or requirement/map/source conflict.

### Cycle 1 — bind all 714 decisions to owners and admissible evidence

- **Intended contract RED:** every indexed IR must map to its final detailed
  decision, earlier owner(s), current authority/deletion boundary, behavioral
  seam, evidence command/artifact, and final disposition. Missing, duplicate,
  stale, conflicting, `NOT_RUN`, or generic “covered by tests” rows fail.
- **Why it fails now:** the deletion map routes implementation, while current
  evidence is distributed across 31 plans, closeout records, tests, harness
  manifests, workflows, and open backlog items; no final all-waves evidence
  graph exists.
- **Minimum GREEN:** create the manual execution-time acceptance matrix in the
  PR/closeout evidence, using section 4's complete ranges and linking each
  owning record. Record exact retained/deleted/adapted behavior, not only a
  commit hash. Do not create a new repository gate before Cycle 9.
- **Retained behavior protected:** every detailed decision, especially the
  protected-behavior register and retained quirks.
- **Expected change surfaces:** evidence record only; owner defects go back to
  the owning source/test/doc boundary.
- **Exact focused verification:** requirements validator; 714 indexed-row,
  detailed-heading, and `### Decision` counts; owner-plan existence and final
  matrix completeness review.
- **Deletion/simplification enabled:** exposes missing owner tests or final
  residue without reopening decisions.
- **Stop:** a ledger decision conflicts with the deletion map or implemented
  behavior. Record the conflict; do not resolve it silently.

### Cycle 2 — close executable repository residue after every owner is integrated

- **Intended behavioral/static RED:** retained-neighbor behavioral tests pass,
  while static tripwires reject every unexplained current reference to a
  rejected product, route, provider, store, service, identity, workflow,
  compatibility shell, or false claim. All nonzero hits require classification.
- **Why it fails before final owners:** the baseline intentionally still carries
  S-26 through S-30 targets such as duplicate backend shape, inherited region/
  identity, and missing build ownership; these are predecessor work, not S-31
  residue.
- **Minimum GREEN:** after S-30, delete only residue whose named owner has
  already made it dead; update the adjacent behavioral test and owning docs;
  regenerate route/OpenAPI/Swift artifacts from source. Return substantive
  defects to their owner. Preserve historical changelogs and required MIT
  provenance.
- **Retained behavior protected:** local authorities, Gemini Live realtime,
  transient compute, account deletion, update/release, telemetry, and every
  positive-owner search in section 13.
- **Expected change surfaces:** only proven residue in already-owned source,
  tests, contracts, generated output, config, workflows, docs. No live state.
- **Exact focused verification:** section 13 searches; focused owner tests;
  assembled-app negative routes; route-policy/OpenAPI/generated checks;
  runtime-image/env/workflow/index controls.
- **Deletion/simplification enabled:** truthful final repository boundary with no
  compatibility fog.
- **Stop:** any hit has a retained caller, unresolved owner, legal/history role,
  live-only uncertainty, or would require a product decision.

### Cycle 3 — prove focused and full component contracts

- **Intended behavioral RED:** final-tree focused tests, backend suite, desktop
  suite, agent-logic harness, repository checks, and preflight all pass from a
  clean tree; any skipped/failing relevant row remains red and classified.
- **Why it is RED until run:** earlier green results belong to pre-Wave-5 SHAs
  and cannot prove S-26–S-30 integration.
- **Minimum GREEN:** fix only real in-scope regressions through production seams,
  add the regression test that would have caught each bug, update owner docs,
  and rerun affected plus component gates. Delete obsolete/flaky owner tests
  instead of weakening expectations.
- **Retained behavior protected:** all section 9 invariants and per-owner test
  semantics.
- **Expected change surfaces:** defect-owned code/test/docs only; no broad
  refactor or source-string behavioral test.
- **Exact focused verification:** section 14.1–14.5 commands, including official
  `backend/test.sh`, `desktop/macos/test.sh`, agent-logic, requirements, diff,
  `make preflight`, and PR preflight.
- **Deletion/simplification enabled:** removes obsolete tests/check entries only
  when their production owner is already gone.
- **Stop:** unclassified baseline failure, missing toolchain, or a fix requiring
  a changed requirement/large migration.

### Cycle 4 — prove the canonical backend and offline/local harness end to end

- **Intended behavioral RED:** one local command must boot exactly the surviving
  Firebase/Redis/canonical-backend/provider-fake stack in offline mode; health,
  auth, metrics, `/v4/listen`, managed Chat, conversation/Memory compute,
  fair-use, disabled billing, export, and durable account-deletion fake paths
  must work with network denial and controlled faults.
- **Why it is RED until run:** the baseline harness still models two Python app
  factories and predates S-26/S-27's final canonical shape.
- **Minimum GREEN:** consume S-26/S-27 harness outputs, remove only stale final
  scenarios/config, and fix behavior at its production seam. Offline mode must
  use fakes and construct no live provider/payment client.
- **Retained behavior protected:** production-shaped route/auth/failure
  semantics, local ownership, Redis fail-open behavior, account-deletion
  durability, and billing-disabled zero side effects.
- **Expected change surfaces:** canonical app factory, harness profiles/fakes,
  workflow contracts, tests/docs only if the integrated owner left a defect.
- **Exact focused verification:** `PROVIDER_MODE=offline make dev-up`,
  `make dev-check USER=alice`, `backend/testing/e2e/run.sh`, health/metrics/listen
  route tests, account-deletion E2E, and `make dev-down` through the owning
  harness.
- **Deletion/simplification enabled:** stale duplicate-app or rejected-service
  harness residue.
- **Stop:** any test needs network/live credentials, any fake changes product
  semantics, or cleanup would touch a foreign process/port.

### Cycle 5 — prove the retained product matrix on `omi-wave6-s31`

- **Intended behavioral RED:** the named bundle must pass Tier-2 and direct
  semantic/UI flows for onboarding, auth, Home/Chat, capture/transcription,
  Conversations, Memories, Tasks/Goals, Focus/Insights, Rewind, settings,
  notifications/privacy, fair-use/plan usage, export, managed Pi, PTT controller/
  manager support probes, offline/restart/account-switch/late-result faults, and
  removed-surface absence.
- **Why it is RED until run:** earlier Tier-2 and named-bundle evidence predates
  Wave 5 identities, topology, build, and copy.
- **Minimum GREEN:** launch only the assigned named bundle against the isolated
  offline stack, verify its actual post-S-28 bundle ID/backend identity, run the
  typed matrix, and fix only surfaced owner regressions. Do not use seeded auth
  for the auth/onboarding flows themselves.
- **Retained behavior protected:** all Mac product authorities, navigation,
  local persistence, permissions, PTT state, and exact Rewind quirks.
- **Expected change surfaces:** owner source/tests/flows/docs only for a real
  regression; no test-only source mutation or coordinate sleep.
- **Exact focused verification:** desktop core T0/T2, fault suite, relevant
  `omi-harness` flows, `omi-ctl health/state/actions`, and `agent-swift` only for
  native UI not covered semantically.
- **Deletion/simplification enabled:** stale navigation/deep-link/settings/
  restored-state residue after behavioral proof.
- **Stop:** wrong bundle/backend, production-family identifier, mixed auth
  profile, non-offline T2 config, missing owner/TCC prerequisite, or stale SHA.

### Cycle 6 — prove clean installation, storage identity, and account lifecycle

- **Intended behavioral RED:** a matrix must prove clean install, upgrade from
  this product's own first build, DMG/App-Translocation self-install, no
  downgrade, relaunch, reset, sign-out, account switch, same-UID reauth,
  deterministic Export My Data offline, local deletion/isolation behavior, and
  uninstall/reinstall without observing or mutating Omi apps/data.
- **Why it is RED until run:** current baseline still uses Omi namespaces and
  only S-28/S-29 can establish the owned install/upgrade path.
- **Minimum GREEN:** consume S-28's namespace and S-29's install artifact;
  exercise disposable profiles/install roots; compare exported owner-scoped
  content and excluded secrets/diagnostics; prove old Omi paths/processes remain
  untouched. Fix only exact lifecycle regressions.
- **Retained behavior protected:** atomic install, no downgrade, local authority,
  owner fences, authentication, update identity, and user-controlled data.
- **Expected change surfaces:** storage/install/auth/export owner code and tests
  only when a regression is found.
- **Exact focused verification:** focused storage/Auth/export/AppInstaller tests;
  `export-my-data*.yaml`, onboarding/logout/update flows; signed-smoke storage/
  auth-canary later on the release artifact.
- **Deletion/simplification enabled:** inherited takeover migration/path residue
  already rejected by S-28.
- **Stop:** test would touch a production/Omi bundle or store, no disposable
  profile, unknown upgrade source, or export would expose disallowed data.

### Cycle 7 — measure the surviving edit, test, run, deploy, and release loops

- **Intended measurement RED:** no acceleration proposal is admissible until an
  evidence table records elapsed time, repeat count, cache state, failure/rework
  rate, input SHA, machine/runner lane, and phase breakdown for each surviving
  loop.
- **Why it fails now:** historical plans contain timings from different SHAs and
  architectures; S-26–S-30 can materially change setup, bundle, deploy, and
  release paths.
- **Minimum GREEN:** measure clean `make setup`; focused backend and Swift
  feedback; offline stack boot/check; incremental and full named-bundle launch;
  component suites; backend candidate/deploy/rollback; Mac candidate build/
  intake; qualification; preview; promotion/recovery/rollback. Use at least
  three comparable observations for ordinary repeated local loops; for rare
  release operations capture one complete run plus per-phase timestamps.
- **Retained behavior protected:** correctness gates, immutable source identity,
  signing, qualification, rollback, isolation, and safety are never removed to
  improve time.
- **Expected change surfaces:** none; measurement artifacts/evidence only.
- **Exact focused verification:** `/usr/bin/time -p` around local commands,
  `dev-feedback.py` iteration output, harness manifests, GitHub/provider job
  timestamps, and qualification/release evidence timestamps.
- **Deletion/simplification enabled:** identifies avoidable wait, duplicate work,
  cache miss, serial phase, or manual evidence transform; measurement alone
  deletes nothing.
- **Stop:** incomparable cache/machine/config runs, missing phase identity,
  changing source during a sample, or a proposal based only on intuition.

### Cycle 8 — accelerate only the measured dominant repeated bottleneck

- **Intended behavioral/performance RED:** the selected loop has a reproducible
  avoidable bottleneck while all correctness and isolation assertions remain
  fixed.
- **Why it may be RED:** Cycle 7 may identify duplicate setup, unnecessary
  rebuild/sign/copy, overly broad focused selection, safe independent phases
  serialized, or a cache invalidated by unrelated inputs. If it identifies no
  meaningful avoidable repeated cost, this cycle is `none` and makes no change.
- **Minimum GREEN:** make the smallest owner-local change that reduces measured
  median/phase time or removes demonstrated rework; preserve clean/full escape
  hatches and cache integrity; add behavioral/cache-key/failure tests.
- **Retained behavior protected:** full suites and release evidence remain the
  authority; push gate budget is not expanded; no hidden skip or stale cache.
- **Expected change surfaces:** only the measured loop's existing script/cache/
  selector and tests/docs.
- **Exact focused verification:** before/after comparable samples plus the
  loop's unit/contract tests and the full gate it accelerates.
- **Deletion/simplification enabled:** measured waste only.
- **Stop:** improvement requires weakening a check, changing product behavior,
  guessing a cache key, broad architecture work, or moving CI-only cost into
  pre-push.

### Cycle 9 — automate only a stable repeated closure step

- **Intended contract RED:** a repeated manual step observed in Cycles 0–8 can
  produce stale/mixed evidence or unnecessary operator work, and no existing
  shared primitive already enforces it.
- **Why it may be RED:** PR #46's closeout history contained stale-SHA Tier-2
  evidence and open physical/provider rows despite broad green aggregate
  results. This is a real merged-instance candidate for exact-SHA evidence
  composition, but Cycle 7 must still prove that the step repeats and costs or
  fails materially in the final loop.
- **Minimum GREEN:** prefer extending an existing harness manifest,
  `check-gauntlet-evidence-at-head.sh`, signed-smoke result, qualification
  evidence, workflow contract, or `.github/checks-manifest.yaml` lane. The
  automation must validate inputs, outputs, SHA/digest, missing/red rows,
  privacy, and failure behavior. Add no scheduled/orphan script. If the existing
  primitive already suffices or no stable repeated gap exists, record `none`.
- **Retained behavior protected:** manual physical/provider/payment/release
  judgment and explicit authorization cannot be automated away.
- **Expected change surfaces:** one existing evidence/check/workflow primitive,
  its behavioral tests, manifest registration, and component guide if chosen.
- **Exact focused verification:** tool self-tests; manifest/check selection in
  local and CI lanes; injected stale SHA, missing row, red row, malformed input,
  and secret-pattern failure cases; full preflight.
- **Deletion/simplification enabled:** duplicated manual evidence collation only
  after automation is proven.
- **Stop:** no measured repeated instance, no blocking audience, a shared
  primitive can already enforce it, automation would operate external state, or
  the cited incident would not have been caught.

### Cycle 10 — freeze the final committed SHA after all repository changes

- **Intended contract RED:** the final evidence root rejects a dirty tree,
  unpushed/unreviewed required implementation, ambiguous source repository,
  short-only hash, missing owner commit, or artifact not bound to the full SHA.
- **Why it is RED before Cycles 2–9 finish:** residue, regression, acceleration,
  or automation work may still change source and invalidate evidence.
- **Minimum GREEN:** complete code review/landing under repository policy, then
  capture one full SHA, tree state, source repository, merge ancestry, owner
  commit ledger, and intended candidate tag/digests. No further source-derived
  change is allowed without restarting this cycle.
- **Retained behavior protected:** exact-source admission for backend and desktop
  release lanes.
- **Expected change surfaces:** evidence only; no product change.
- **Exact focused verification:** Git full hashes/status/log; release eligibility
  source identity; owner-plan commit comparison; requirements/diff checks.
- **Deletion/simplification enabled:** none.
- **Stop:** dirty tree, unmerged predecessor, stale main, ambiguous artifact
  source, or any subsequent repository edit.

### Cycle 11 — rerun repository, component, offline, and contract evidence on the final SHA

- **Intended behavioral RED:** every Cycle 1–4 row must be green on the frozen
  SHA, and each produced manifest/result must contain that full SHA or a
  cryptographically linked image digest.
- **Why it is RED until rerun:** pre-freeze evidence may precede Cycle 8/9
  changes and is not automatically transferable.
- **Minimum GREEN:** rerun requirements, residue, route/OpenAPI/generated,
  runtime/index/workflow, full backend/desktop, agent-logic, hermetic E2E,
  offline stack, fault, preflight, and PR contracts. Attach unredacted secrets
  nowhere; classify skips and failures explicitly.
- **Retained behavior protected:** all repository/local invariants.
- **Expected change surfaces:** none. Any fix restarts Cycle 10.
- **Exact focused verification:** all section 14 repository/component/backend
  commands and section 13 residue searches.
- **Deletion/simplification enabled:** none; this is final proof.
- **Stop:** any mismatch, skip, failure, stale manifest, or changed tree.

### Cycle 12 — rerun Tier-2 and the complete local user-path matrix on the final SHA

- **Intended behavioral RED:** the final `omi-wave6-s31` bundle must pass the
  complete Cycle 5/6 matrix with Tier-2 `provider_mode=offline`, matching SHA,
  correct bundle/backend identity, and no production-bundle interaction.
- **Why it is RED until rerun:** pre-freeze local evidence may be stale and
  hermetic Tier-2 does not prove physical/provider/release rows.
- **Minimum GREEN:** build/install the exact named bundle, run T0/T2/fault/manual
  local flows and storage/account lifecycle, verify manifests at the frozen SHA,
  and classify every manual-only row. Physical/provider rows remain Cycle 13.
- **Retained behavior protected:** all Mac UI/data/owner/offline/restart/fault
  behavior.
- **Expected change surfaces:** none. Any fix restarts Cycle 10.
- **Exact focused verification:** section 15.1–15.3 commands and flow matrix.
- **Deletion/simplification enabled:** none.
- **Stop:** wrong bundle, stale auth, foreign port, non-offline T2, missing TCC,
  dirty source, or any failed flow.

### Cycle 13 — close BL-001 with physical PTT and real-provider continuity on the final SHA

- **Intended behavioral RED:** the final matrix requires natural authenticated
  physical PTT with actual captured audio; Gemini Live, same-provider reconnect,
  language, and retained tools; typed -> physical PTT -> blind recall; buffered
  batch recovery; and deployed mint/direct-provider proof. Fake, echo,
  forced-text, manager/controller-only, or `NOT_RUN` rows fail.
- **Why it is RED now:** BL-001 records continuity recall failure against the
  offline echo provider and all real-provider/deployed-probe rows as `NOT_RUN`.
- **Minimum GREEN:** with approved non-production credentials and verified dev
  deployment, use `omi-wave6-s31`; capture real audio bytes/duration and typed
  terminal diagnostics; run continuity/agents/owner/prompts/resilience; execute
  the workflow-equivalent `voice-provider-probe.sh` for Gemini using a protected
  token file; prove same-provider reconnect/language/tools and the buffered
  batch-recovery UI. Redact secrets and content.
- **Retained behavior protected:** Gemini session/auth boundaries, PTT
  capture/admission/barge-in/journal/tools, provider failure typing, usage, and
  privacy.
- **Expected change surfaces:** none. Any behavioral fix returns to its owner and
  restarts Cycle 10.
- **Exact focused verification:** physical shortcut observation; gauntlet
  `--suite all`; `check-gauntlet-evidence-at-head.sh`; provider probe against the
  deployed candidate; matching app/backend/manifest SHA evidence.
- **Deletion/simplification enabled:** closes BL-001 only when every row is green.
- **Stop:** missing credential/deployment identity, zero/too-short audio, fake
  provider, failed recall, provider row red, secret exposure, or SHA mismatch.

### Cycle 14 — close BL-002 inventory and prove the owned development backend operationally

- **Intended operational RED:** a verified read-only inventory must classify
  every Cloud Run, Cloud Tasks/scheduler, GKE/network, image, secret/IAM,
  Firestore/index, Redis, GCS, monitoring/alert/budget, provider, and release
  resource as retained/rejected/shared/already absent/unknown; the final dev
  candidate must deploy, authenticate, stream, delete a disposable account,
  recover, and roll back without a retired resource.
- **Why it is RED now:** BL-002's current live classifications are all `unknown`,
  and the baseline has no verified operator/project identity.
- **Minimum GREEN:** first perform read-only inventory under S-27 authority and
  retain `unknown` honestly. Only with separate exact-target authorization,
  deploy the frozen SHA/digest to development, run health/metrics/listen/provider
  probes and disposable account deletion, test restart/traffic rollback and
  break-glass evidence without weakening gates. Operational decommission of
  rejected resources is family-by-family and separately authorized; it is not
  required to falsify an unknown row.
- **Retained behavior protected:** canonical service, exact image/source,
  Firestore index check-only policy, account queue/IAM, data retention, rollback,
  health/alerts, no production mutation.
- **Expected change surfaces:** external read-only evidence; authorized
  development deploy/rollback only. No source edit.
- **Exact focused verification:** S-27 `pre-deploy-check`/runtime env/workflow
  contracts; development deploy with exact admitted SHA; `voice-provider-probe`;
  health/metrics/listen; disposable account deletion; rollback; after-inventory.
- **Deletion/simplification enabled:** separately authorized rejected-resource
  decommission only after zero caller/traffic/retention ambiguity; otherwise
  handoff remains explicit.
- **Stop:** unverified identity, wrong environment, unknown/shared owner,
  retention/legal gap, missing rollback, ordinary user identity, or mutation
  without fresh authorization.

### Cycle 15 — prove the disabled billing checkpoint and emit the post-Wave-6 S-18 handoff

- **Intended behavioral RED:** under the final S-31 build and backend,
  `BILLING_MODE=disabled` must expose no purchasable catalog, checkout or portal
  action; construct no Dodo client; make no Dodo/Stripe request; grant no paid
  entitlement; preserve quota/fair-use state; and keep the visible usage-limit
  action as literal **Skip** with dismissal-only behavior. A handoff validator
  must also reject a packet that omits any post-Wave-6 test/live prerequisite,
  owner, authorization boundary, cleanup duty, or link to `dodo-integration.md`.
- **Why it is RED now:** the final integrated S-31 SHA and its disabled-mode
  evidence do not yet exist; the baseline plan also incorrectly treated later
  Dodo activation as an S-31 cycle.
- **Minimum GREEN:** run the retained disabled-mode backend/Mac/network-recorder
  tests and named-bundle path on the frozen SHA; record zero provider
  construction/network/entitlement mutation; and publish a handoff row naming
  S-18/billing ownership, the all-six-waves prerequisite, test-mode inputs and
  authorization, the separately authorized live gate, evidence/cleanup/rollback
  duties, and the rule that neither activation is S-31 closure evidence.
- **Retained behavior protected:** free MVP, backend-authoritative quota/fair use,
  future fail-closed Dodo architecture, no onboarding paywall, no fabricated
  entitlement, and the complete post-Wave-6 test-then-live acceptance contract.
- **Expected change surfaces:** S-31 evidence/closeout record and, only if stale,
  the existing handoff documentation. No provider resource, credential, product,
  webhook, transaction, subscription, deployment, or live setting is created or
  changed.
- **Exact focused verification:** focused S-18 disabled-mode backend/Mac tests,
  an offline network recorder, named-bundle plan/usage/**Skip** behavior, and a
  read-only validation of every prerequisite/checklist row in
  `dodo-integration.md`; do not run its test/live procedures during S-31.
- **Deletion/simplification enabled:** removes Dodo test/live rows from S-31's
  blocking evidence graph while preserving them in the authoritative post-wave
  S-18 handoff.
- **Stop:** disabled mode constructs a provider, exposes an action/catalog,
  changes entitlement/quota/fair-use state, or the handoff is incomplete or
  falsely claims activation evidence.

### Cycle 16 — prove signed install/update/preview/channel release and compose final closure

- **Intended operational RED:** an exact-SHA signed candidate must pass universal
  packaging, code signature, notarization, Gatekeeper/quarantine, auth-storage
  canary, backend/feed identity, clean install, own-first-build update,
  permissions/storage/network/auth/chat canaries where authorized, M1 T2/fault
  qualification, preview publish/replace/pointer delist with immutable evidence retained, Beta promotion/recovery/rollback, public
  links, and separately approved Stable promotion. The final evidence graph must
  have zero missing/red/stale/unknown-required row.
- **Why it is RED until run:** the baseline has no tracked build-provider
  definition or owned identities, and no final-SHA candidate exists.
- **Minimum GREEN:** use S-29's owned provider to build the frozen SHA; compare
  source/tag/artifact digests and signed-smoke JSON; qualify on the dedicated
  runner; verify update activity gates and own-build upgrade; exercise preview
  lifecycle and authorized channel operations; verify public/legal destinations;
  compose all 714 rows, S-01–S-30 records, BL-001/002, disabled-billing/S-18
  handoff, cycle-time, and automation evidence into the PR/closeout record.
  Stable remains a separately
  confirmed operation. If any source change occurs, discard the candidate and
  restart Cycle 10.
- **Retained behavior protected:** signing/notarization, storage/auth isolation,
  exact candidate identity, qualification, Beta/Stable separation, rollback,
  previews, update blocker/activity gate, public truth, and production-app
  safety.
- **Expected change surfaces:** authorized candidate/preview/channel/public
  external state and evidence only; no repository edit after freeze.
- **Exact focused verification:** signed-smoke script with S-29 identities,
  qualification workflow/script, pre-tag readiness, preview workflow, Beta
  promotion/recovery/rollback workflows, manual Stable workflow with its exact
  confirmation, appcast/download/link verification, and final evidence validator
  if Cycle 9 produced one.
- **Deletion/simplification enabled:** final stale evidence records only; do not
  delete rollback artifacts or legally required history.
- **Stop:** missing signer/notary/feed/provider/runner identity, digest/SHA
  mismatch, failed canary/qualification/update/rollback/link, unauthorized
  public/channel operation, unknown required live state, or any incomplete IR.

## 12. Cross-slice ownership and handoffs

| Owner(s) | S-31 consumes | S-31 final proof | S-31 must not absorb |
|---|---|---|---|
| S-01–S-09 | Removed VM/wearable/alternate agent/apps/connectors/BYOK/zombies; retained identity and telemetry seams | No residue plus managed Pi, scoped tools, auth and owned observability | Recreate alternate runtime, remote access, connector, BYOK, or absent product control |
| S-10–S-18 | Local product authorities, transient listen, onboarding/permissions, Dodo-disabled checkpoint | Complete offline/restart/owner/account/export/billing-disabled matrix | Redesign stores, prompts, UI behavior, or activate billing early |
| S-19–S-25 | Local-grounded PTT/fair-use/shell/model portfolio; hosted product/search/topology deletion; per-slice records | Final physical/provider/continuity, residue, canonical retained topology | Replace slice-specific matrices with generic T2 or infer live absence |
| Waves 3–4 closeout / BL-001 | Open provider/continuity contract and historical evidence | Every required row rerun on final SHA; close only all-green | Treat `NOT_RUN`, echo recall, controller/manager probe, or historical physical run as final |
| S-25 / BL-002 | Sanitized inventory schema with live state `unknown` | Verified read-only classification before any operation | Infer cloud absence from git or bulk-decommission resources |
| S-26 | One canonical app/URL/harness and truthful contracts | Offline/local/route/image/index/harness acceptance | Restore duplicate backend or redesign service API |
| S-27 | Owned retained cloud foundation and operations | Verified inventory, dev deploy/auth/stream/delete/recover/rollback | Change capacity/topology or mutate live state without authority |
| S-28 | Clean Mac namespace/install identity | Clean install/own upgrade/reset/switch/reinstall isolation | Import/take over/terminate/delete Omi state |
| S-29 | Owned build/sign/update/preview/public release system | Exact-SHA signed artifact, qualification, channels, rollback, links | Invent missing external IDs or bypass evidence gates |
| S-30 | Final current identity/copy/privacy/legal truth | Screen/link/source/current-doc inventory | Rewrite history or MIT provenance |
| S-18 Dodo handoff | Full disabled/test/live contract | Final disabled proof plus a complete post-Wave-6 handoff packet; test/live acceptance remains successor work after S-31 closes | Create resources early, run activation inside S-31, copy IDs/secrets into git, or make redirect authoritative |

Shared files remain owned by behavior, not by S-31 convenience. Likely integration
surfaces include `backend/main.py`, runtime env/images, Firestore indexes, route
policy/OpenAPI/generated Swift, deploy/release workflows, `FORK.md`, component
guides, `DesktopLocalProfile`, `AppBuild`, `Info.plist`, `run.sh`, Settings/Home,
and release scripts. Rebase on the integrated owner and make the smallest
owner-correct repair. Do not restore an old shape to satisfy this plan.

## 13. Repository residue-search strategy

These are static tripwires after behavioral GREEN. Run from repository root,
exclude roadmap/evidence/history where stated, exclude Windows entirely, and
classify every hit as retained production, negative test, generated contract,
historical changelog/provenance, external handoff, or defect. Zero counts do not
prove behavior.

### 13.1 Rejected product and compatibility residue

```bash
rg -n --hidden \
  --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  --glob '!desktop/windows/**' --glob '!desktop/macos/changelog/**' \
  'agent[_-]?vm|agent[_-]?cloud|AgentVMService|AgentSyncService|backend-sync|backend-listen|llm[_-]?gateway|HOSTED_PUSHER|HOSTED_VAD|HOSTED_SPEAKER|Pinecone|Typesense' \
  backend desktop/macos .github scripts config infrastructure FORK.md PRODUCT.md

rg -n --hidden \
  --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  --glob '!desktop/windows/**' --glob '!desktop/macos/changelog/**' \
  'BYOK|X-BYOK|OPENROUTER|DEEPGRAM|HOSTED_PARAKEET|ElevenLabs|Twilio|Wrapped|Daily Summary|People|voice.?profile|marketplace|remote MCP|LocalAgentAPIServer|omi-tools-stdio' \
  backend desktop/macos .github scripts config infrastructure FORK.md PRODUCT.md

rg -n --hidden \
  --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  --glob '!desktop/windows/**' --glob '!desktop/macos/changelog/**' \
  '410|deprecated|legacy|compatib|fallback|TODO|FIXME|HACK' \
  backend desktop/macos .github scripts config infrastructure FORK.md PRODUCT.md
```

Every `fallback` hit must have a retained correctness owner and existing
fallback telemetry. Every legacy/compatibility hit needs an explicit released,
drain, schema-migration, or historical owner; otherwise it is a defect.

### 13.2 Current identity, endpoint, storage, and public truth

```bash
rg -n --hidden \
  --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  --glob '!desktop/windows/**' --glob '!desktop/macos/changelog/**' \
  'BasedHardware|api\.omi|omiapi|h\.omi|macos\.omi|com\.omi|Omi Beta|Omi Dev|Application Support/Omi|Omi Dev Bundles|based-hardware|us-central1|gcr\.io' \
  backend desktop/macos .github scripts config infrastructure FORK.md PRODUCT.md

rg -n --hidden \
  --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  --glob '!desktop/windows/**' --glob '!desktop/macos/changelog/**' \
  'Privacy|Terms|support|GitHub Releases|SUFeedURL|SUPublicEDKey|CFBundleIdentifier|URL scheme|Keychain|Application Support|Launch at Login' \
  desktop/macos backend .github FORK.md PRODUCT.md
```

Internal source symbols and development command names may remain when S-30
classifies them as repository-local and non-user-facing. No current shipped
identity, endpoint, storage namespace, telemetry destination, provider account,
or public link may remain inherited.

### 13.3 Routes, persistence, infrastructure, and release owners

```bash
rg -n --hidden --glob '!desktop/windows/**' \
  'include_router|add_api_route|websocket|APIRouter' backend/main.py backend/routers

rg -n --hidden --glob '!desktop/windows/**' \
  'collection\(|collection_group|redis|bucket|Cloud Tasks|artifact|secret|service_account|run.app|workflow_dispatch' \
  backend firestore.indexes.json .github infrastructure config

rg -n --hidden --glob '!desktop/windows/**' \
  'release_tag|source_sha|digest|notari|codesign|Sparkle|appcast|preview|promote|rollback|break.?glass|qualification' \
  desktop/macos backend .github
```

Compare concrete owners against the post-S-26 route policy/OpenAPI,
post-S-27 environment/resource manifests, post-S-28 namespace inventory, and
post-S-29 release manifests. A generic word match is never a deletion order.

### 13.4 Positive retained-owner searches

```bash
rg -n 'TranscriptionStorage|MemoryStorage|ActionItemStorage|GoalStorage|FocusStorage|InsightStorage|KernelTurnProjection|ChatProvider' desktop/macos/Desktop/Sources
rg -n 'PushToTalkManager|RealtimeHubController|Gemini|batch|recordFallback' desktop/macos/Desktop/Sources
rg -n '/v4/listen|VADStreamingGate|Modulate|/v1/health|/metrics|ACCOUNT_DELETION_|BILLING_MODE|record_fallback|log_sanitizer' backend
rg -n 'qualif|candidate|preview|promote|recover|rollback|Sparkle|notari|codesign' desktop/macos .github backend
```

Positive searches must still find the final owners and their tests. If a
retained positive owner disappears, stop even if every rejection search is zero.

## 14. Focused and component-level verification commands

Use the current component guides and refresh test paths after S-30. Commands
below exist at the planning baseline; future S-26–S-30 replacements must update
their component guide in the same change. No result is claimed here.

### 14.1 Baseline, ledger, and repository structure

```bash
git fetch origin
git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD
git rev-parse HEAD
git rev-parse origin/main
git status --short --branch
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
```

### 14.2 Focused backend and billing/account contracts

From `backend/`, construct a temporary selector list from paths that still exist
after predecessor integration, then use the official runner:

```bash
cd backend
s31_backend_tests="$(mktemp)"
printf '%s\n' \
  tests/services/users/test_account_deletion.py \
  tests/services/users/test_data_export.py \
  tests/unit/test_account_deletion_task_identity.py \
  tests/unit/test_billing_mode.py \
  tests/unit/test_dodo_billing.py \
  tests/unit/test_dodo_webhook_behavioral.py \
  tests/unit/test_fair_use_review_runtime.py \
  tests/unit/test_memory_compute.py \
  tests/routers/test_conversation_compute.py \
  tests/unit/test_metrics_route.py \
  tests/unit/test_openapi_contract.py \
  tests/unit/test_route_policy_inventory.py \
  tests/unit/test_backend_runtime_env_validator.py \
  tests/unit/test_runtime_image_contracts.py \
  tests/unit/test_workflow_contracts.py \
  > "$s31_backend_tests"
BACKEND_UNIT_TEST_FILE_LIST="$s31_backend_tests" bash test.sh
.venv/bin/python -m pytest -q testing/e2e/test_account_deletion_cloud_tasks.py
```

Delete obsolete path entries from the execution-time list when their production
owner is gone. Do not keep a dead test merely to preserve this planning command.

### 14.3 Backend contracts, generated artifacts, and infrastructure

From `backend/`:

```bash
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --report-only
scripts/pre-deploy-check.sh
```

From repository root:

```bash
python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows
python3 backend/scripts/validate-backend-runtime-env.py --env prod --check-workflows
python3 backend/scripts/check_workflow_contracts.py
make runtime-image-source-closure
python3 backend/scripts/reconcile_firestore_indexes.py \
  --project <verified-s27-project> --check-only
```

Use S-27's verified execution-time project/region only for a separately
authorized live `pre-deploy-check.sh --live ...`; never paste inherited project
names from this plan.

### 14.4 Backend/local harness and faults

```bash
PROVIDER_MODE=offline make dev-up
make dev-status
make dev-check USER=alice
bash backend/testing/e2e/run.sh
make dev-down
```

The harness must prove its own process/port ownership and must not stop a foreign
service. `BILLING_MODE=disabled` remains independent of provider mode.

### 14.5 Desktop focused and component proof

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'AuthSessionCoordinatorTests|ConversationLocalAuthority|MemoryLocalAuthority|TasksStoreOwnerBoundary|FocusLocalAuthority|ChatTimelineContinuity|RealtimeHub|AppInstaller|DesktopStorageIdentity|LocalUserDataExport'
./scripts/agent-logic-harness.sh
./scripts/desktop-core-harness.sh --self-check
./test.sh
```

Adjust the exact XCTest filter to current class names rather than retaining a
stale empty selection. Source-string tests are not behavioral coverage.

### 14.6 Full repository and PR contracts

```bash
cd backend && bash test.sh
cd ../desktop/macos && ./test.sh
cd ../..
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
scripts/pr-preflight --suggest
make preflight
scripts/pr-preflight --pr-body-file /tmp/s31-pr-body.md
```

The implementation PR records command, duration, result, exact SHA, and any
classified skip/failure. A new guard is registered in the existing check
manifest with local and CI lanes and cites the real merged incident it catches.

## 15. Real named-bundle, backend, infrastructure, and release acceptance

### 15.1 Named-bundle identity and safety

Use only the logical name supplied for this slice. Start the offline harness and keep the local-profile launcher running in shell 1:

```bash
cd <repository-root>
PROVIDER_MODE=offline make dev-up
make desktop-run-local DESKTOP_APP_NAME=omi-wave6-s31 DESKTOP_USER=alice
```

After the launcher reports bundle readiness, use shell 2 for semantic state checks:

```bash
cd <repository-root>/desktop/macos
./scripts/omi-ctl health
./scripts/omi-ctl state
```

Do not place semantic or harness commands after foreground `run.sh`/`make desktop-run-local` in the same shell. Use the reported loopback/emulator profile and never the named-bundle remote-development default.

Read the actual bundle identifier, backend URLs/environment, storage root,
automation port, runtime protocol/capabilities, log path, and final SHA from the
post-S-28/S-30 bundle. Do not hardcode the planning baseline's `com.omi.*`
namespace. Never connect to or operate an inherited production bundle.

### 15.2 Hermetic Tier-2 and fault acceptance

```bash
cd desktop/macos
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave6-s31 --port <reported-port> --keep-stack
./scripts/desktop-core-harness.sh --fault-suite --port <isolated-fault-port>
```

The T2 manifest must record the frozen SHA and `provider_mode=offline`. Run all
current `tier <= 2` flows, not the historical count. The matrix must cover at
least navigation/Home, capture, Rewind recovery, Chat, Memories, Tasks/Goals,
settings, local CRUD, conversation detail/folders/speakers, vocabulary,
fair-use/plan usage, privacy/notifications, export, owner switch, restart, and
fault truthfulness.

### 15.3 Manual local lifecycle acceptance

Run current typed/manual flows for onboarding without auth seeding, sign-in/
refresh, logout, export, clean install, own-build update, reset, account switch,
same-UID reauth, TCC/permissions, audio recording, managed Pi bridge, proactive
writers, and uninstall/reinstall. Use semantic bridge actions first and
`agent-swift` for native UI/TCC only. Record exact bundle/profile and do not
confirm destructive account deletion on an ordinary account.

### 15.4 Final provider and continuity matrix

On `omi-wave6-s31` with approved non-production credentials:

```bash
cd desktop/macos
./scripts/agent-continuity-gauntlet.sh --suite all --bundle-id <reported-bundle-id>
./scripts/check-gauntlet-evidence-at-head.sh
```

Then perform a natural physical shortcut hold/release with actual microphone
capture and run the deployed Gemini provider probe through the protected
token-file interface used by the owned development workflow. Required evidence
includes captured bytes/duration, owner/auth state, Gemini Live identity,
same-provider reconnect/language/tool and buffered-recovery outcomes, terminal
reason, zero stale/invalid transitions, blind recall, deployment URL identity,
and exact SHA. Do not record user speech or assistant content.

### 15.5 Backend development operational acceptance

After verified read-only inventory and separate deploy authority, use S-27's
current exact-SHA workflow inputs—not inherited values from this plan—to:

1. run local/runtime/index/workflow pre-deploy checks;
2. deploy a zero-traffic or candidate revision from the frozen SHA/digest;
3. verify image lineage, readiness, health, authenticated metrics, auth,
   `/v4/listen`, managed provider probes, and no rejected route/resource;
4. shift only authorized development traffic;
5. exercise durable account deletion on a disposable owned development account;
6. force a controlled restart/provider/Redis failure and verify recovery;
7. roll back to the exact retained digest and verify health/user paths; and
8. record post-operation inventory and alerts.

Production deployment, decommission, data cleanup, and traffic remain separate
authorizations.

### 15.6 Disabled billing acceptance and post-Wave-6 Dodo handoff

Keep `BILLING_MODE=disabled` throughout S-31 and prove the Cycle 15 contract
without provider construction or network activity. Validate the completeness of
`dodo-integration.md` and record its S-18/billing owner, but do not create test or
live resources or run either activation procedure. Test mode begins only after
S-31 closes all six waves and receives explicit authorization; live mode remains
a second authorization after successful test acceptance.

### 15.7 Signed candidate and release acceptance

Use S-29's owned provider and current identifiers. The existing verification
surface includes:

```bash
cd desktop/macos
./scripts/pre-tag-readiness.sh --evidence /tmp/s31-readiness.json <final-sha>
./scripts/smoke-signed-desktop-artifact.sh \
  --app <candidate-app> \
  --dmg <candidate-dmg> \
  --zip <candidate-sparkle-zip> \
  --tag <candidate-tag> \
  --source-sha <final-sha> \
  --expected-bundle-id <owned-bundle-id> \
  --expected-url-scheme <owned-scheme> \
  --expected-feed-url <owned-feed> \
  --auth-storage-canary \
  --result-json /tmp/s31-signed-smoke.json
./scripts/qualify-desktop-beta.sh \
  --automatic \
  --signed-smoke-result /tmp/s31-signed-smoke.json \
  --candidate-gate-result <candidate-gate-json> \
  <candidate-tag>
```

Optional launch/network/auth/chat/permissions/storage signed-smoke probes require
the isolated runner and documented explicit environment gates. Do not enable a
production-family launch merely for convenience.

Required release evidence:

- universal app, dSYM, DMG, Sparkle ZIP, libwebp/libsharpyuv provenance and
  architectures, exact version/build/tag/SHA/digests;
- Developer ID chain, entitlements, notarization, Gatekeeper/quarantine,
  package completeness, auth-storage canary, no inherited backend/feed identity;
- candidate intake exactly once, T2/fault qualification, immutable manifest and
  admission generation;
- owned-first-build install/update, automatic/manual update, required blocker,
  active-work deferral, relaunch, and no downgrade;
- signed preview publish/open/replace/pointer delist with isolated identity and truthful links, while immutable manifests and artifacts remain;
- qualified Beta promotion, recovery and rollback; no Stable movement from
  automatic or break-glass Beta paths;
- manual Stable only with the exact qualified current Beta and explicit
  `promote-stable` confirmation; and
- owned website, Terms, Privacy, support, download, feed, and GitHub Releases
  links with no current Omi destination or false claim.

## 16. Repository closure versus separately authorized operational closure

### 16.1 Repository implementation and local verification

Repository closure means S-01 through S-30 are integrated; Cycles 0–12 are
green on one frozen SHA; all 714 decisions map to passing owner/final evidence;
component/harness/named-bundle/residue/contracts/docs are truthful; measured
acceleration/automation is complete or explicitly `none`; and no unexplained
compatibility or rejected-product residue remains.

Repository closure does **not** mean BL-001, BL-002, Dodo, live cloud cleanup,
deployment, signing, candidate, preview, Beta, Stable, or public release passed.

### 16.2 Verified read-only inventory

Read-only inventory is a separate lane using S-27's authoritative identities.
For each environment, record names and metadata—not secret values or customer
content—for:

| Resource class | Retained expectation | Rejected/unknown question |
|---|---|---|
| Cloud Run / routes | One canonical service per environment | Any duplicate/retired service, revision, URL, traffic, IAM or route |
| Cloud Tasks / schedulers | One account-deletion queue | Legacy audience/payload, rejected queue/job/scheduler, oldest/retry work |
| Firestore / indexes | Retained account/billing/usage/deletion/release state and exact indexes | Rejected product collections/indexes, retention/backup obligations |
| Redis / networking | Separate dev/prod TLS+AUTH instances | Old host, shared consumer, insecure binding, retired key namespace |
| GCS | Update/preview publication only | Product-data object path, shared bucket, retention/legal role |
| Images / registry | Canonical full-SHA images and release artifacts | Rejected image/tag/digest still serving or needed for rollback |
| Secret Manager / IAM / WIF | Exact retained version references and least privilege | Retired binding, shared principal, unknown last use; never read values |
| GKE / network | No surviving roadmap owner | Release/workload/ingress/static IP/VPC/shared consumer still present |
| Monitoring / budgets | Sanitized logs, health/5xx alerts, 50/80/100 budgets | Retired dashboards/alerts/export/storage or missing owner |
| Providers / release | Owned approved accounts, feeds, domains, runners | Inherited Omi identity or unknown ownership |

An `unknown` row is an honest open gate. Repository absence cannot convert it to
`already absent`.

### 16.3 Separately authorized mutation and release

Every external operation names exact targets and environment, captures before
state, verifies retention/legal/backup and rollback, performs one family at a
time, and captures after state. The safe sequence is:

1. deploy/accept the retained replacement first;
2. stop new producers for one rejected family;
3. observe/drain or safely terminalize work according to its owner decision;
4. verify zero traffic/caller and retain rollback digest/window;
5. remove the service/job/queue, then exclusive image/secret/IAM/network/alert
   dependencies in that order;
6. rerun inventory, health, alerts, account deletion, and named-bundle paths;
7. stop/roll back that family on any failure.

Post-Wave-6 Dodo test/live activation, candidate publication, preview, Beta,
Stable, public-site publication, deploy, traffic, and decommission each retain
their own explicit authorization. Dodo activation is successor S-18 work rather
than an S-31 label. A terminal request to finish S-31 does not broaden any of
those authorities.

### 16.4 Closure labels

- **Repository/local closed:** Cycles 0–12 green.
- **BL-001 closed:** Cycle 13 green on the same SHA.
- **Inventory verified:** Cycle 14 read-only classification complete; unknowns
  remain named if authority cannot resolve them.
- **Development operationally qualified:** authorized Cycle 14 deploy/delete-
  account/rollback rows green.
- **Disabled billing and successor handoff accepted:** Cycle 15 disabled-mode
  proof is green and the post-Wave-6 S-18/Dodo handoff is complete; no test/live
  activation is claimed.
- **Release accepted:** Cycle 16 signed/candidate/update/preview/channel/public
  rows green under their authorizations.
- **S-31 closed:** every required label above is green, every IR is accounted
  for, and no S-31-required external input remains missing. Dodo test/live remain
  explicit post-S-31 S-18 work and do not keep S-31 open. Otherwise S-31 stays
  open with exact rows and owners.

## 17. Risks, ambiguities, and explicit stop points

| Risk / ambiguity | Affected cycles | Safe work | Evidence needed to reopen / owner |
|---|---|---|---|
| S-26–S-30 not integrated or differ from expected shape | 0–16 | Planning and current-tree characterization only | Integrated owner commits, tests, docs, refreshed inventory |
| Ledger/map/source conflict | 1–16 | Unaffected owner research | Updated authoritative decision/map; product owner |
| A final residue hit has a live caller or historical/legal role | 2 | Classify and keep; run neighbor tests | Caller deletion/decision or explicit retained classification |
| Component/harness failure is pre-existing or unowned | 3–5, 11–12 | Narrow diagnosis without broad fix | Owning regression/failure-class resolution and rerun |
| Evidence manifest has stale/missing SHA | 10–16 | None for that row | Rerun on frozen SHA; never relabel |
| Real provider credentials/deployed identity unavailable | 13, 16 | All hermetic/local rows | Approved credentials, verified dev deployment/principal |
| Mic/TCC/auth failure or zero captured audio | 13 | Controller/manager diagnosis only | Natural captured-byte physical success on named bundle |
| BL-002 operator/project identity unknown | 14 | Repository/local work | Verified operator + S-27 environment manifest |
| Live resource has shared/unknown consumer or retention duty | 14, 16 | Leave it unchanged and `unknown` | Reference graph, traffic/task age, retention/legal/rollback evidence |
| Legacy account-deletion audience/tasks may remain | 14 | Keep bounded legacy acceptance | Verified queue drain, last dispatch, rollback-window expiry |
| Post-Wave-6 Dodo test/live inputs are absent | Successor S-18 handoff, not S-31 | Complete S-31 and release the free MVP with billing disabled | After S-31 closes: explicit test authorization/setup, then separate live approval and monitored rollback plan |
| Signing/notary/Sparkle/provider/runner identity unavailable | 16 | Named dev bundle/local closure | S-29-owned identities and successful canaries |
| Candidate/qualification/public link fails | 16 | Keep candidate non-live | Fixed owner path and new exact-SHA artifact |
| Stable approval absent | Stable portion of 16 | Candidate/Beta evidence where authorized | Exact qualified current Beta plus explicit promotion approval |
| Cycle-time samples are incomparable | 7–9 | Keep current loop | Controlled repeat measurements and phase breakdown |
| Automation has no real repeated failure/bottleneck | 9 | Record `none` | No automation should land |
| A new guard duplicates a shared primitive | 9 | Extend the shared primitive or record none | Evidence existing primitive cannot express the contract |
| Any fix after SHA freeze | 11–16 | Stop external progression | Commit/integrate fix, return to Cycle 10, rerun affected/all lanes |

Global stop conditions:

- no compatibility shell, ignored field, fake success, duplicate adapter, or
  source-string behavioral test may turn a red row green;
- no product, provider, UI, schema, capacity, or topology decision may be made
  in S-31 merely to finish faster;
- no credential, raw identity, content, payment identifier, or secret may be
  copied into evidence;
- no production app may be stopped, restarted, instrumented, or used as a test
  target;
- no external mutation may proceed from repository success alone; and
- no release/closeout claim may omit a missing credential, unknown resource,
  failed row, stale artifact, or unauthorized operation.

## 18. Final completion checklist

### Baseline, decisions, and ownership

- [ ] S-01 through S-30 implementations are integrated before S-31 execution.
- [ ] Current `origin/main`, HEAD, merge base, branch, status, and commits beyond
  `22ad2f16ff8d63fd761c918b92f4c5d961814624` are recorded.
- [ ] Requirements validation passes at 714 indexed rows, 714 detailed sections,
  all reviewed.
- [ ] Every one of the 714 decisions maps to exact owner behavior and admissible
  final evidence; no decision is reopened or silently changed.
- [ ] Every owner plan/closeout remains linked; generic final tests do not erase
  per-slice evidence.

### Repository and retained behavior

- [ ] Every section 13 hit is classified; every positive retained owner still
  exists and passes behavior tests.
- [ ] No unexplained rejected product/provider/route/store/job/service/image/
  workflow/current-brand/current-link/compatibility residue remains.
- [ ] Route policy, app-client OpenAPI, generated non-Windows Swift, runtime
  images/env, Firestore indexes, workflow contracts, docs, and source agree.
- [ ] Focused tests, full backend/desktop suites, agent-logic, hermetic E2E,
  repository checks, `git diff --check`, `make preflight`, and PR preflight pass.
- [ ] One offline/local command boots exactly the surviving stack; fault and
  disabled-billing paths are truthful with zero provider/payment side effects.

### Named bundle, local data, and physical/provider proof

- [ ] `omi-wave6-s31` reports the expected post-S-28/S-30 identity, frozen SHA,
  backend, protocol/capabilities, storage root, and isolated automation/log path.
- [ ] Final-SHA Tier-2 and fault suites pass with `provider_mode=offline`.
- [ ] Onboarding/auth, all retained product surfaces, offline/restart, owner
  switch/reauth, late-result rejection, and removed-surface absence pass.
- [ ] Clean install, own-first-build upgrade, reset, sign-out, account switch,
  export, uninstall/reinstall, and no-Omi-touch behavior pass.
- [ ] Natural authenticated physical PTT captures real audio and reaches terminal
  success with no stale/invalid transitions.
- [ ] Gemini Live, same-provider reconnect, language, tools, typed-to-PTT blind
  recall, deploy-inline mint, direct-provider, and buffered batch-recovery rows
  all pass on the same SHA; BL-001 is closed without fake substitution. The
  Modulate key is configured, but its live recovery row remains explicitly
  unverified until the exact version is deployed and exercised.

### Infrastructure and account lifecycle

- [ ] A verified operator/environment/project identity exists for BL-002.
- [ ] Every live resource class is read-only classified; unknown/shared rows are
  preserved rather than guessed.
- [ ] Any authorized development deploy uses the exact admitted SHA/digest and
  passes health, auth, metrics, streaming, providers, alerts, restart, and rollback.
- [ ] Durable account deletion passes hermetically and, when separately
  authorized, on a disposable development identity with exact queue/OIDC/
  retry/reconciliation/completion evidence.
- [ ] No live deploy, traffic, drain, resource, IAM, secret, image, network, data,
  or production mutation is inferred from repository closure.

### Dodo

- [ ] Entry/final disabled mode exposes no catalog/action, constructs no client,
  performs no Dodo/Stripe request, grants no entitlement, and preserves quota/
  fair-use state.
- [ ] The post-Wave-6 S-18 handoff names every test-mode input, behavior row,
  authorization, evidence, cleanup duty, and the separately authorized live gate
  from `dodo-integration.md` without copying a secret/provider/payment ID.
- [ ] S-31 evidence explicitly records Dodo test/live as successor work not run,
  makes no paid-release claim, and does not block free-MVP release acceptance.

### Release and public truth

- [ ] S-29's owned build provider, signing, notarization, Sparkle, runner,
  preview, GitHub, domain/site, and protected-environment identities are verified.
- [ ] Universal app/dSYM/DMG/Sparkle ZIP and libwebp/libsharpyuv provenance,
  architecture, minimum-OS, signatures, notarization, digests, and final SHA match.
- [ ] Signed-smoke, auth-storage canary, clean install, own-build update, required
  blocker, activity deferral, relaunch, and no-downgrade behavior pass.
- [ ] Candidate intake is singular and exact; M1 T2/fault qualification is
  digest-bound; preview publish/replace/pointer delist and public links pass while immutable manifest/artifact evidence remains.
- [ ] Beta promotion/recovery/rollback pass without reaching Stable; any Stable
  promotion uses the exact qualified current Beta and separate explicit confirm.
- [ ] Current visible/source/link inventory has no Omi identity or false claim;
  historical changelogs and MIT provenance remain truthful.

### Cycle time, automation, and final evidence

- [ ] Clean setup, focused test, offline stack, fast/full named bundle, component,
  backend deploy/rollback, candidate/intake, qualification, preview, promotion/
  recovery, and rollback durations are recorded with comparable context.
- [ ] Any acceleration is justified by before/after measurement and preserves
  full correctness/isolation; otherwise it is `none`.
- [ ] Any automation follows a stable repeated step, extends an existing lane
  where possible, cites the real incident it catches, proves failure/privacy
  behavior, and has a blocking audience; otherwise it is `none`.
- [ ] All source-derived evidence and artifacts resolve to one final full SHA.
- [ ] Any post-freeze edit caused a new freeze and rerun; no evidence was relabelled.
- [ ] Repository, BL-001, BL-002 inventory, development operations, disabled
  billing/post-wave Dodo handoff, and release labels are reported separately.
- [ ] S-31 is marked closed only when every S-31-required row is green and no
  required unknown state, authorization, or code-decision fog remains; later
  Dodo test/live inputs remain owned by the successor S-18 handoff.

## 19. Repository implementation evidence — 2026-09-03

This section supersedes the planning-state description in section 2 without
claiming operational closure. S-01 through S-30 are present on `origin/main` at
`d882065ffa8a526a30259842a727ea467fe13b2e`; S-31 repository repairs are on the
feature branch. Exact final-SHA local manifests and PR checks are recorded only
after this evidence record is committed, so this section deliberately does not
self-reference a commit that cannot contain its own hash.

### 19.1 Complete 714-decision acceptance graph

The inclusive counts below total exactly 714. Every range binds to its named
S-01 through S-30 owner plan/closeout and to a concrete final evidence class;
the requirements ledger remains the authority for the individual decision text.
The graph does not collapse local, credentialed-provider, live-inventory, or
release evidence into one generic pass.

[`s-31-acceptance-matrix.md`](s-31-acceptance-matrix.md) expands these ranges
into all 714 individual decisions. Each row links the exact detailed behavior
and final `### Decision`, copies its ledger disposition, links every earlier
owner record, and resolves the evidence codes below to exact commands or
artifacts. The range table remains only the count/check summary.

Evidence classes used below:

- **REQ:** `validate-requirements-ledger.py`, the detailed decision, section
  4.1's route, and the named owner plan/closeout.
- **REP:** residue classification, generated-contract freshness,
  `git diff --check`, check-manifest selection, `make preflight`, and PR-body
  preflight.
- **BE:** focused/full backend tests, offline `dev-up`/`dev-check`, backend E2E,
  route/OpenAPI/runtime-image/workflow contracts, and fault injection.
- **MAC:** focused/full Swift tests, agent-logic, named `omi-wave6-s31`, semantic
  flows, Tier-2, owner/restart/storage lifecycle, and bundle-source provenance.
- **PROV:** natural physical PTT plus approved non-production Gemini Live,
  reconnect/tool/continuity, mint, and retained Modulate recovery evidence.
- **INV:** verified read-only S-27 resource inventory and separately authorized
  development deploy/account-deletion/rollback evidence.
- **BILL:** disabled-mode backend/Mac/network-recorder proof plus the permanent
  [`dodo-integration.md`](../dodo-integration.md) successor handoff; test/live
  activation is not run by S-31.
- **REL:** exact-SHA signed/notarized artifact, intake, qualification, preview,
  Beta/Stable/recovery/rollback, and public-link evidence under separate
  authorization.

| Ledger family | Count | Earlier owner route | Current authority / exact disposition | Admissible final evidence |
|---|---:|---|---|---|
| IR-001–IR-016 | 16 | S-01, S-04–S-06, S-25, S-26 | Managed Pi/local tools retained; Agent VM, alternate entrance, wearable sync, duplicate backend, and impossible controls deleted. | REQ + REP + BE + MAC |
| IR-017–IR-023 | 7 | S-02, S-03, S-10, S-16 | Mac capture/local commit retained with transient listen, Modulate/Parakeet, language/vocabulary, and generic speakers; no server conversation owner. | REQ + BE + MAC + PROV |
| IR-024–IR-038 | 15 | S-12–S-14 | Owner-local Memories, Tasks/Goals, Focus/Insights/profile/proactive state retained across restart/switch; cloud product authorities deleted. | REQ + REP + MAC |
| IR-039–IR-053 | 15 | S-05–S-07, S-11, S-15, S-17, S-23 | One local Chat/Home/Rewind authority and scoped tools retained; hosted products, connectors, BYOK, and cloud copies deleted. | REQ + REP + MAC |
| IR-054–IR-119 | 66 | S-03, S-05, S-07, S-09–S-16, S-19, S-20, S-22 | Physical PTT/realtime remains Gemini Live with same-provider recovery, local grounding, continuity, privacy, diagnostics, and rejected tools absent. | REQ + MAC + PROV; PROV remains an operational row |
| IR-120–IR-124 | 5 | S-08, S-10, S-17, S-23, S-25 | Durable account deletion, narrowed account metadata, truthful export retained; cloud-product/account residue deleted. | REQ + BE + MAC + INV |
| IR-125–IR-169 | 45 | S-17, S-30 | Narrow onboarding, permissions, literal Skip, completion, restart, and final copy retained; inherited product claims deleted. | REQ + REP + MAC |
| IR-170–IR-211 | 42 | S-08, S-09, S-18, S-30 | Owned auth/telemetry/privacy and disabled free-MVP billing retained; no Dodo/Stripe activation or fabricated entitlement. | REQ + BE + MAC + BILL |
| IR-212–IR-255 | 44 | S-05–S-07, S-09, S-15, S-18, S-21, S-29, S-30 | Settings/shell/notifications/PTT controls retained with owned update/public links; connector/provider/developer residue deleted. | REQ + REP + MAC + BILL + REL |
| IR-256–IR-292 | 37 | S-06, S-10, S-12, S-23, S-24, S-30 | Full local Memory lifecycle/search/provenance retained; hosted Memory, server search, and vector authority deleted. | REQ + BE + MAC |
| IR-293–IR-405 | 113 | S-02, S-03, S-10, S-16, S-23, S-24 | Full local Conversations/transcription behavior retained; server product authority and cloud conversation objects deleted. | REQ + BE + MAC + PROV |
| IR-500–IR-530 | 31 | S-11–S-14, S-21, S-30 | Home/Chat shell and projections retained from one owner-local product mind; duplicate projections removed. | REQ + REP + MAC |
| IR-600–IR-615 | 16 | S-05, S-07, S-09, S-19, S-20, S-22 | Fixed managed portfolio, fair-use split authority, typed workload ownership, and privacy-bounded observability retained; provider selection deleted. | REQ + BE + MAC + PROV |
| IR-616–IR-658 | 43 | S-13, S-21 | Local task/goal CRUD, recurrence, order, Undo, reminders, and assistant integration retained; task-intelligence/productivity products deleted. | REQ + REP + MAC |
| IR-659–IR-699 | 41 | S-14, S-15, S-21 | Exact local Focus/Insights/Rewind behaviors and accepted quirks retained; hosted authorities deleted. | REQ + REP + MAC |
| IR-700–IR-735 | 36 | S-10, S-12, S-14, S-17, S-20, S-22, S-23 | Model-result ownership, fair use, onboarding lifecycle retained; hosted products and stale-result commits deleted. | REQ + BE + MAC |
| IR-800–IR-837 | 38 | S-05, S-06, S-08, S-09, S-11, S-18, S-22–S-26 | Managed Pi, canonical backend, disabled billing, account/export, and retained telemetry remain; rejected product/backend topology deleted. | REQ + REP + BE + MAC + BILL |
| IR-838–IR-891 | 54 | S-03, S-08, S-09, S-18, S-20, S-22, S-25–S-27 | Owned Cloud Run/WIF/IAM/Redis/Firestore/GCS/Tasks/registry contracts retained; inherited service identities and duplicate topology deleted. | REQ + REP + BE + INV |
| IR-892–IR-897 | 6 | S-04, S-29, S-30 | Owned Mac build/sign/notarize/release/preview/public truth retained; impossible absent-tree and inherited release controls deleted. | REQ + REP + MAC + REL |
| IR-898–IR-921 | 24 | S-02, S-15, S-16 | Three-way System Audio and every accepted Rewind behavior/quirk retained. | REQ + MAC |
| IR-922–IR-937 | 16 | S-01, S-04, S-05, S-09, S-11, S-28–S-30 | Managed Pi and clean Intentive storage/update/brand identity retained; local HTTP agent API, orphan runtimes, and Omi takeover paths deleted. | REQ + REP + MAC + REL |
| IR-938 | 1 | S-06 with S-13 protection | External task export deleted; owner-local task candidate acceptance retained. | REQ + REP + MAC |
| IR-939 | 1 | S-29 with S-04 protection | Universal libwebp/libsharpyuv provenance, architecture, signing, minimum OS, and rebuild contract retained. | REQ + MAC + REL |
| IR-940 | 1 | S-04 with S-29 protection | Nested undiscoverable installer workflow stays deleted; owned release qualification remains. | REQ + REP + REL |
| IR-941 | 1 | S-04 | Unreferenced media stays deleted; live Notifications and Rewind remain protected. | REQ + REP + MAC |

The graph has no `NOT_RUN`-as-green path. A row containing PROV, INV, or REL
stays operationally open until that exact evidence exists on the frozen SHA.
BILL means the disabled checkpoint and handoff only; Dodo test/live activation
remains successor S-18 work after all six waves.

### 19.2 Cycle-time measurements and acceleration disposition

All samples used the same Apple-silicon Mac, local runner, and external T9
build/Python cache. The focused-loop set used clean
`a70f42fb26ca16b87008f4e76680de63f2eb11fe`; the complete-suite and PR-gate
set used clean `80a0cef28e1cffa48b075de704b89e23453968b2`. Commands did not change
source during a sample set. Times are `/usr/bin/time -p` wall seconds; every
listed observation passed.

| Surviving loop | Input SHA / runner | Cache state | Three elapsed observations | Failure rate | Phase breakdown | Disposition |
|---|---|---|---:|---:|---|---|
| `make setup` | `a70f42f` / local shell | existing T9 venv | 1.33 / 0.98 / 1.09 | 0/3 | fetch and ancestry -> hook install -> locked dependencies | Already bounded; retain full ownership. |
| formatter ownership behavior test | `a70f42f` / shell test | warm `uvx` | 1.01 / 0.88 / 0.84 | 0/3 | hook fixture -> staged format -> diff/failure assertions | No acceleration; one Black owner now reaches pre-commit, pre-push, and CI. |
| focused backend Redis-seam tests | `a70f42f` / pytest | existing venv | 0.62 / 0.43 / 0.44 | 0/3 | collection -> cache contract -> lock contract | No acceleration needed. |
| focused `AppBuildBetaIdentityTests` | `a70f42f` / SwiftPM | existing Swift build | 29.70 / 1.15 / 26.13 | 0/3 | package plan -> compile/link if invalidated -> XCTest | Planning variance dominates; insufficient stable bottleneck. |
| dev-harness CLI tests | `a70f42f` / pytest | existing venv | 1.25 / 0.96 / 0.98 | 0/3 | fixture roots -> process/config ownership -> command assertions | Correctness repair only. |
| active offline `make dev-check USER=alice` | `a70f42f` / Make | live sentinel-owned stack | 0.25 / 0.19 / 0.18 | 0/3 | ownership -> health -> active provider contract | Retain active-state validation. |
| cold-ish offline `make dev-up` | `a70f42f` / Make | retained cache, stopped services | 7.75 / 6.93 / 6.14 | 0/3 | launch contract -> service start -> health -> evidence publish | No stable speed defect. |
| matching `make dev-down` | `a70f42f` / Make | live sentinel-owned stack | 0.87 / 0.87 / 0.89 | 0/3 | ownership -> targeted stop -> state cleanup | Retain ownership and cleanup evidence. |
| incremental named-bundle launch | `a70f42f` / `run.sh` | reusable package, offline profile | 57.18 / 45.72 / 12.25 | 0/3 | build planning -> compile/sign -> install/launch -> health | Compile/sign variance is not a stable optimization target. |
| backend component suite | `80a0cef` / `run-unit-ci.sh --all` | existing T9 venv | 56.33 / 57.23 / 85.90 | 0/3 | selection -> preflight/deps -> typecheck -> 226 isolated test files | Preserve full component authority. |
| desktop component suite | `80a0cef` / `desktop/macos/test.sh` | existing T9 Swift build | 454.53 / 423.36 / 438.44 | 0/3 | shell contracts -> E2E coverage -> 51 Python tests -> prebuild -> 403 isolated Swift suites | Largest loop, but no stable subphase regression justified weakening or re-keying it. |
| agent-logic suite | `80a0cef` / `agent-logic-harness.sh` | existing T9 package caches | 48.80 / 19.43 / 59.83 | 0/3 | failure self-check -> focused Swift -> agent runtime -> exact pi-mono package | Variance is insufficient for an acceleration change. |
| backend hermetic E2E | `80a0cef` / `run-hermetic-e2e.sh` | existing venv/tokenizer cache | 3.93 / 2.54 / 2.56 | 0/3 | prewarm -> 14 account/network/storage/auth/profile tests | Already bounded. |
| deterministic PR gate | `80a0cef` / `make preflight` | existing T9 caches | 162.33 / 150.51 / 156.84 | 0/3 | manifest load -> changed-path selection -> 91 local-lane checks -> PR/failure-class contracts | Stable enough to retain; the manifest is the required local/CI aggregation owner. |

The acceleration result is therefore **none**. The implementation changes in
this slice repair false/fragmented developer feedback and evidence ownership;
they do not weaken a correctness gate to improve a stopwatch number. Backend
deploy/rollback, candidate intake, qualification, preview, promotion, recovery,
and release timings were not rerun: those are credentialed or mutating lanes
without authorization in this execution. Their absence remains an open Cycle
7/14/16 evidence row, not a local timing estimate.

### 19.3 Stable repeated step automated last

Three material instances were recorded before admitting and then completing
automation. PR #46 (`22ad2f16ff8d63fd761c918b92f4c5d961814624`)
carried stale-SHA Tier-2 evidence while required provider/physical rows remained
open. S-31's first independent review of
`61254178c00caeff083b663fd9f216bdc26e7bfb` found that the checker accepted a
partial suite and had no blocking audience. The final standards review of
`eb34847513f46cb30f567d78621b0fe76d38d282` found that producer provenance used
the wrong authenticated health shape, privacy detection was weaker than the
shared scanner, and the producer self-check lacked a durable CI route. These
are three of three material retrospective correctness escapes; their elapsed
review times were not retained, so they are explicitly excluded from the timed
Cycle 8 acceleration analysis rather than presented as stopwatch data.

The existing `check-gauntlet-evidence-at-head.sh` primitive is extended instead
of adding an orphan checker. On S-31 it now requires the full five-suite/23-row
manifest, full current SHA, clean running source, green outcome, timestamps,
empty failures, and privacy-safe content across every textual evidence
artifact. Its producer provenance and shared privacy paths have dedicated
behavioral tests registered in both manifest lanes. The bounded pre-push lane
is its blocking audience;
`PRE_PUSH_SKIP_GAUNTLET_EVIDENCE=1` is the explicit break-glass hatch only with
a tracking issue and reason. Hermetic tests inject missing directory, partial
suite, missing row, short/stale SHA, red row, malformed JSON, and secret-bearing
manifest and sibling evidence.

Desktop Core evidence separately verifies the running bundle's signed
`IntentiveSourceGitSHA` and `IntentiveSourceTreeDirty=false` health fields before
it may emit a green T1+/fault manifest. It records the fault bundle rather than
the default bundle and records `provider_mode=offline`; it never relabels a
stale binary with repository HEAD.

### 19.4 External and successor handoff status

- **PROV / BL-001:** not closed by repository tests. Natural captured-audio PTT,
  approved Gemini Live/reconnect/tools/continuity, deployed mint, and retained
  Modulate recovery still require the named non-production credentials and
  physical/deployed evidence in Cycle 13.
- **INV / BL-002:** live inventory was not inferred from source. The attempted
  GCP identity check requires operator reauthentication; no cloud mutation,
  deployment, traffic change, account deletion, or cleanup occurred.
- **BILL:** `BILLING_MODE=disabled` remains the free-MVP authority. The complete
  post-Wave-6 S-18 owner, prerequisites, explicit test authorization, distinct
  live authorization, evidence, cleanup, and rollback duties remain in
  [`dodo-integration.md`](../dodo-integration.md). No Dodo resource, credential,
  product, webhook, customer, transaction, or entitlement was created or used.
- **REL:** signing/notarization/candidate/preview/Beta/Stable/public mutation was
  not authorized or run. S-29 controls remain the owner; no push, PR, tag,
  release, channel, feed, or public-site change is implied by this branch.

Accordingly, this record supports repository implementation and final local
verification but does not label S-31 closed. Section 16.4's labels remain
separate and fail closed on every missing operational row.
