---
type: Repository guide
title: Intentive authored guidance
description: Human-authored product decisions, engineering rules, ownership and acceptance obligations for the Intentive codebase wiki.
---
# Intentive authored guidance

This is the single authored home for repository rules and accepted product decisions.
Read Scope and Wiki maintenance, then the sections relevant to your task. Use targeted
reads for the decision register rather than loading the entire historical register.
Generated codebase pages describe implementation; they do not override this guidance.

## Scope

- Use stock OpenWiki 0.5.2 and its Codex integration with Node 22.22.0.
- Generate the active macOS product, bundled Node runtime, canonical Python backend,
  development tooling, delivery boundaries and tests under `openwiki/codebase/`.
- Maintain `openwiki/quickstart.md` as the entrypoint and let OpenWiki manage indexes,
  Claims, provenance and run checkpoints. Create the empty `openwiki/company/`
  directory after init begins so native finalization emits its empty index.
- Company is reserved structure only: no company content, connectors or inference.
- Windows is inherited and excluded from research and substantive changes. Do not
  infer that its implementation is part of the active Mac release.
- Do not read credentials, private local state, ignored collaboration files,
  dependencies or build outputs. Tracked placeholder configuration is evidence.

## Wiki maintenance

- Install with Node 22.22.0: `npm install -g openwiki@0.5.2`, then run
  `openwiki integrations install codex --project .` and start a fresh Codex session.
- Use the current authenticated Codex session through the native OpenWiki MCP tools.
  Resolve the current worktree with `git rev-parse --show-toplevel`.
- After code and tests stabilize, run the native update lifecycle before completing
  the task. Include wiki changes with the implementation on the same branch.
- For authored-guidance-only or structural changes, begin an update with `force: true`.
- Complete the native page queue and finish call before claiming success. Resume an
  interrupted run with begin; never edit Claims or completion metadata yourself.
- Init replaces generated pages but preserves this file. Reserve Company again
  after init begins. Remove any init-scaffolded scheduled workflow before committing;
  maintenance is performed during Codex work, with no scheduled generation.
- Update this brief only for explicitly authorized rule or product-decision changes.
  Keep date-bound evidence and unresolved commitments distinct from current proof.
- Every factual generated page cites source and tests outside the wiki. Authored
  policy and archived decisions are not machine-verified repository Claims.
- Source packages above the existing twelve-file threshold need a substantive wiki
  architecture page whose standard `resource` metadata is `repo://<package-path>`.
- Validate documentation links, agent entrypoint budgets, package maps and the
  shared `make preflight` contract. Keep matching tests and manifest triggers current.
- Keep README, CONTRIBUTING, SECURITY, AGENTS and CLAUDE as discoverable entrypoints.
  Detailed guidance belongs here and explanations belong in the generated wiki.

## Reading the migrated record

The following guidance was carried forward from the pre-migration repository.
Source dates, named owners, explicit approvals and unresolved evidence requirements
remain binding. Historical observations are not refreshed live deployment evidence.
The migration changes documentation locations, not product behavior or release approval.
The accepted-requirements register distills each final decision; the complete wording,
investigation and per-decision acceptance records remain available at the pinned archive.
Where a decision has subsequently been implemented, it remains a product constraint,
not an instruction to repeat the old migration. Current Product constraints define
the retained product; historical code descriptions are checked against source and tests.


## Engineering rules

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/AGENTS.md).

#### Definition of Done

Every change must satisfy this checklist before it is committed or put in a PR. When in doubt about any other rule, satisfying this list is the priority.

1. **Behavior changed → a test changed.** Bug fixes include the regression test that would have caught the bug. New features test the core path and the main error path — no more.
2. **The component's test suite passes** (`backend/test.sh`, `desktop/macos/test.sh`, or the component's documented equivalent), run locally before committing.
3. **You exercised the change yourself** — ran the real user-facing path, not just compiled or lint-passed. If you truly could not, say so explicitly instead of implying it works.
4. **Verification evidence is written down** — the commands you ran and what they showed, in the commit message or PR description.
5. **No orphaned deferrals** — new `TODO`/`FIXME`/`HACK` comments reference a tracking issue or are resolved before merge.
6. **Docs moved with the code** — setup, test commands, service boundaries, env vars, or agent-relevant behavior changes update the matching guide (this file or the relevant section of this brief) in the same PR. Product-direction changes update Product constraints in this brief and the owning guard tests in the same PR.
7. **Failure-class declaration** — before drafting a `fix:` PR body, run `scripts/pr-preflight --suggest` for failure-class guidance; every `fix:` commit then declares `Failure-Class: FC-<slug> | new | none` and validates it with `scripts/failure-class`.
8. **PR contracts pass before opening the PR** — run `make preflight`; it executes the same deterministic check manifest CI runs (`.github/checks-manifest.yaml`). Draft the PR body and run `scripts/pr-preflight --pr-body-file /tmp/pr-body.md` (or `scripts/pr-preflight --suggest` for paste-ready failure-class guidance).

A deterministic diff-scoped check failing for the first time in CI is a manifest bug: fix the manifest instead of adding a one-off workflow step. Register new checks in `.github/checks-manifest.yaml` with both `local` and `ci` lanes.

#### Bug Fixes: Repair the Failure-Class Boundary

The unit of work is the violated contract, not only the line where the symptom appeared. The declaration is the PR record for an ordinary instance fix; before fixing, inspect recent fixes in the same subsystem. Registry lifecycle transitions are separate PRs: dormant classes record `dormant_since`, and recurrence reopens them by setting `status: open` and removing it.

- Identify the authoritative owner, identity, state transition, or boundary contract that failed — don't add another observer, fallback boolean, or call-site exception when ownership is the real problem.
- If two or more recent fixes share the cause, add a reusable guard surface in the same PR: a typed state/policy model, behavioral contract test, fault harness, or narrow static checker.
- A regression test must execute production behavior through a controllable seam. Asserting that source strings occur in a certain order is a static tripwire, not behavioral coverage; label static checkers as such.
- Do not broaden a safe bug-fix PR into an unreviewable migration; land the enforceable guard now and track high-blast-radius follow-up explicitly.

#### Leave It Better Than You Found It

- If you touch a file and see a small related defect (dead code, an adjacent bug, a missing test for code you are modifying), fix it **in a separate commit in the same PR**.
- Only make an opportunistic fix you can verify; otherwise open a GitHub issue instead of touching it.
- Never expand beyond files you were already modifying or refactor working code for style alone. Deferring is wrong when the fix is in scope and verifiable; expanding scope is wrong everywhere else.

#### Behavior

- Never ask for permission to access folders, run commands, search the web, or use tools. Just do it.
- Never ask for confirmation. Make decisions autonomously and proceed.
- You have full access to the user's computer — browser, desktop, all apps. Never ask the user to do something you can do yourself.

#### Safety Rules

- Never kill, stop, or restart the production macOS apps (`/Applications/Omi.app` / `Omi Beta.app`, bundle ids `com.omi.computer-macos` and `com.omi.computer-macos.beta`). Dev commands target only dev or `omi-*` named test bundles.
- **Nothing lands on `main` until the user explicitly says so.** Land through PRs only (regular merge, never squash); never push directly to `main`; never push or open PRs unless explicitly asked — commit locally on a feature branch by default. A prior approval never carries over to later changes.
- **Exception — reverts merge right away.** A user request to revert a merged PR/commit is itself the approval to open and merge the revert PR.
- **Exception — verified + peer-approved changes may auto-merge.** If you actually exercised the real user-facing path **and** an independent agent review approved it, you may open and merge without a separate go-ahead — except for risky, wide-blast-radius, or hard-to-reverse changes (migrations, release/CI pipeline, schema, access control, data deletion), which always need explicit user sign-off.
- **Prefer testing locally first.** Default to a local build + run (desktop: named bundle) to verify a change before proposing to land it.

#### Git

- **Setup (required before first commit):** `make setup` — fetches `origin/main`, fast-forwards when safe, installs repo Git hooks (including the auto-formatting pre-commit hook) with linked-worktree-safe paths.
- Before starting work: `git fetch origin && git pull --ff-only` on `main` — don't branch off stale state.
- Always work in a git worktree for code changes (`git worktree add`); commit to the current branch and never switch branches mid-task.
- Make individual commits per feature or testable surface, not per file or unrelated bulk changes.
- If push fails (remote ahead): `git pull --rebase && git push`.
- **PR size is reported, not bounded** (`pr-scope` manifest check — advisory annotations, never blocks): 1,500+ changed production-source lines warns; 3,000+ cites the audited history of missed regressions. Split only when the pieces are independently verifiable; otherwise give the one PR proportional review depth.
- **RELEASE command:** branch from `main`, individual commits, push, open PR, merge without squash, switch back to `main` and pull. **RELEASEWITHBACKEND:** RELEASE + `gh workflow run gcp_backend.yml -f environment=prod -f branch=main`.

#### Issues

- Open issues freely — one paragraph of symptom plus evidence (logs, IDs, links) is a complete issue. Tracking beats polish; iterate in comments.
- Issues state problems; PRs state solutions. Don't write implementation epics, acceptance-criteria matrices, SLOs, or rollout programs into an issue — that content hardens in the PR, where the Definition of Done already demands evidence.
- If an issue does prescribe implementation: scope it to one self-contained PR, verify every code claim against current code first (the fix may already exist), and any proposed check must run in an existing CI or deploy lane.
- Close incident issues on live evidence, not code merge; if live verification is deferred, name its owner in the closing comment.

#### Cross-Component Guidelines

- **Product behavior:** read Product constraints in this brief before changing behavior and update the concrete guard test owned by the changed source.
- **No in-repo compatibility layers:** migrate every in-tree caller in the same change; do not add deprecated aliases, duplicate adapters, or fallback paths to preserve a retired shape.
- **Compiler-first boundaries:** express ownership and mutation invariants with target dependencies, access control, and typed APIs before adding source scrapes or runtime assertions; behavioral tests still prove the permitted paths.
- **Never use purple** anywhere in UI (icons, accents, glows, gradients) — off-brand; use white/neutral. The `INV-UI-1` no-increase checker enforces this directly.
- **Fallback telemetry:** when a branch changes provider, mode, or correctness, or takes a fail-open path, call the existing component-owned `record_fallback`/`recordFallback` helper — never a new one-off counter.
- **Logging:** never log raw sensitive data; sanitize API responses and PII (backend: `utils.log_sanitizer`).
- **Deferred-work markers:** new `TODO`/`FIXME`/`HACK` must reference a tracking issue or be resolved before merge. Packages over 12 source files need a wiki architecture page with package `resource` metadata (`check_arch_guardrails.py` ratchet). Designated rollout scaffolding needs a `LIFECYCLE: permanent|one-time` header; one-time files also need `DELETE-AFTER: <issue URL or invariant ID>` (`check_lifecycle_headers.py`).
- **New guards:** explain in the PR why the guard is not a shared primitive, and cite the real merged PR or incident it would have caught; no real instance means the check does not land.

#### Formatting

The pre-commit hook (installed by `make setup`) auto-formats staged files. Verify: `test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK`. Manual commands:

| Language | Manual command |
|----------|----------------|
| Python (`backend/`) | `backend/scripts/black-wrapper.sh --line-length 120 --skip-string-normalization <files>` |
| Swift (`desktop/macos/Desktop/`) | `desktop/macos/scripts/swift-format-wrapper.sh format -i <files>` |

Swift files under `Desktop/Sources/Generated/` are excluded from the formatter scope.

#### Computer Control

Click at coordinates: `cliclick c:X,Y`. Mac screenshots: `screencapture -x /tmp/screen.png`. Native macOS app testing: `agent-swift` (see desktop guide). Browser automation: `playwright` MCP. Never try 3+ different click tools for the same action — pick one and commit. Prefer `cliclick` over `automac`/`mac-use-mcp` (multi-monitor coordinate bugs).

#### Testing

- **Coverage grows by ratchet, not mandate:** every bug fix adds the regression test that would have caught it; new features test the core path and main error path — no more. A small test that stays meaningful in a year beats ten brittle ones.
- **Push gate budget:** `scripts/pre-push` is a bounded local acceptance gate, intentionally smaller than CI: cap broad backend selection at 40 files and use only the desktop debug compile. Do not add full suites, release compiles, or CI-only toolchain pins to it — push-time bloat breaks normal iteration. Use focused feedback while editing; CI remains the full test authority.
- **CI tests must be hermetic** (no live services, network, sleeps, or ordering dependence) — and hermetic tests must run in CI: put them where the component's runner discovers them. A test needing a live service stays out of CI; note in the PR how you ran it.
- Backend enforces test discovery mechanically: manifest check `backend-test-discovery` fails on any test file no verified runner discovers.
- **New fail-closed gates ship with a legacy-principal test** — an existing/unmigrated principal (no state doc, old API key, already-shipped client) asserting the intended fallback; gates without one have shipped day-one breakage.
- **A test rewritten in the same PR as the code it asserts is suspect** — the PR body must cite an external source (platform doc, wire contract, measurement) for the new expected value, or the rewrite deletes the guard.
- Delete or fix a flaky/obsolete test you encounter — a suite people distrust is worse than a smaller suite.
- Component runners and prerequisites: see [Backend guidance](#backend-guidance) and [Desktop guidance](#desktop-guidance). High-risk backend workflows must be listed in `backend/testing/workflow_contracts.json` with contract tests.

#### Deploys & Release Pipelines

- Desktop (daily candidate → qualified beta → manual stable): [Desktop guidance](#desktop-guidance) → Release Pipeline.
- Backend: `gh workflow run gcp_backend.yml -f environment=prod -f branch=main`. Runtime env contract: [Backend guidance](#backend-guidance) → Service Map.

**Every gated surface has a break-glass hatch. A broken gate is never a reason to be stuck.** Each records a tracking issue; repeated use means the gate is the defect.

| Blocked on | Hatch |
|---|---|
| Desktop candidate won't cut (`Desktop Swift Build & Tests` red/flaky) | `desktop_auto_release.yml` with `release_mode=break_glass` |
| Backend deploy has no Release Eligibility proof | `gcp_backend.yml` with `skip_eligibility_proof=true`, `break_glass_confirm=deploy-without-proof`, `break_glass_reason` |

Hatches relax *evidence* requirements only. They never relax that code is merged to `main` first, and never reach stable/prod pointers without their own explicit confirm.



## Product constraints

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/PRODUCT.md).

### Intentive Product Principles

Short north star for humans and agents. Read this before proposing features or
landing PRs that change product behavior. Engineering standards live in
[`AGENTS.md`](../AGENTS.md). Concrete behavior contracts live beside their owning
source and tests.

#### Principles

1. **Memory-first.** Protect the core loop:
   **Capture → Understand → Remember → Retrieve → Act**.
   If Intentive fails to capture or preserve memory, nothing else matters.

2. **Trust over cleverness.** Prefer reliable capture, sync, and retrieval over
   flashy features. Silent data loss and dual sources of truth are product bugs.

3. **One product mind.** Surfaces are input/output against one shared product
   experience — not separate products with competing authorities. This does
   not make every capture cloud-backed: persisted Rewind OCR history,
   embeddings, and video remain local to the Mac.

4. **Harness over heuristics.** Where we integrate with surfaces we do not own,
   invest in durable harnesses and contracts, not brittle one-off automation.

5. **Taste floor.** Stay on-brand. Prefer deleting dual paths over
   feature-flagging them forever.

6. **Managed desktop access.** Desktop AI, voice, transcription, and agent
   surfaces use account entitlement plus product-owned provider credentials.
   The hosted prototype additionally admits only its configured one-to-five
   Firebase participants and its reserved release probe; local/offline Dev is
   separate. Unlisted accounts retain authenticated account export/deletion.
   Customer billing remains disabled for this Beta.
   They do not solicit, forward, or select customer-supplied provider keys.
   The concrete guards live in the desktop managed-access, request-routing,
   realtime-authentication, and agent-runtime tests and the backend route tests.

#### macOS conversation authority

The Mac owns its conversation archive in its owner-scoped local GRDB database.
Capture creates one stable local conversation ID; list, detail, search, folders,
stars, titles, speaker labels, merge, deletion, and restart recovery read and
write that local authority. The desktop does not project conversations to
Firestore, reconcile server snapshots, or fall back to hosted conversation
data.

The backend remains a transient managed-compute boundary for live speech, the
three candidate-only conversation operations (discard, structure, and
action-item extraction), and fair-use classification. Conversation operations
return candidates that the Mac validates and commits locally. Fair-use compute
accepts only a bounded owner-local metadata projection, runs the pinned fair-use
prompt-v2 contract transiently through Gemini 3.7 Flash, and persists only
content-free enforcement facts. Cloud
conversation playback, reusable People/voice identity, public conversation
sharing, and Store Recordings/Private Cloud Sync settings are not macOS product
surfaces.

Continuous cloud transcription uses one Firebase-authenticated `/v4/listen`
socket. The Mac snapshots language, optional translation target, and ordered
vocabulary for the recording; audio is fixed mono 16 kHz signed PCM. The backend
streams it to managed Modulate and returns only stable UUID segments with
zero-based numeric speakers, truthful transport/account status, and optional
Gemini 2.5 Flash-Lite translations keyed to the segment. It does not create,
persist, identify, roll over, reconcile, or finalize a conversation.

#### macOS Chat and Home authority

Home is the canonical ordinary-Chat host. The owner-scoped Node SQLite catalog
owns Chat identity, titles, title origin, stars, activity metadata, and accepted
turns; Swift owns drafts and app-managed attachment bytes. The desktop does not
project normal Chat sessions, messages, ratings, or attachments to Firestore and
does not reconcile a server catalog.

The persistent primary navigation is Home, Memory, Tasks, and Insights. Memory
owns the Memories and Conversations destinations, while Insights owns Insights
and Focus. Semantic Chat navigation opens the Chat stage inside Home; it is not a
standalone page or raw navigation destination.

The backend is transient compute only for managed assistant completion and the
authenticated, bounded greeting and title routes. Greeting and title results are
identified and committed locally. Home reads tasks, Focus, Insights, and daily
suggestions from their local authorities and must not restore a hosted dashboard
fallback.

Normal Chat uses the bundled native Gemini adapter and the authenticated Gemini
3.7 Flash streaming route. The desktop supplies only its Firebase bearer token;
the backend owns the provider key and preserves native Gemini content, tools,
images, thinking, and thought signatures end to end.

Desktop background notes, screenshot analysis, task extraction, Insights, and
Suggestions use the same account-available Gemini 3.7 Flash model. Their existing
frequency limits and grounding boundaries remain unchanged; they must not fall
back to account-unavailable 2.5 models.

Realtime voice is Gemini Live only. Same-provider reconnect remains the first
recovery step. If Live cannot complete a turn, the Mac retains the bounded PCM
buffer and turn identity until release, then uses the existing silence gate and
batch STT before Gemini Chat and OpenAI TTS. OpenAI remains a spoken-output
provider only, with the existing macOS system-voice fallback.

#### macOS Memory authority

The Mac owns its Memory archive in the same owner-scoped local `omi.db` boundary
as conversations. Add, edit, delete/Undo, bulk deletion, page/search queries,
source provenance, lifecycle transitions, and semantic vectors commit through
`MemoryStorage`; they do not reconcile with or fall back to a hosted Memory
store. Default reads include active Short-term and Long-term rows and hide
Archive, expired, dismissed, and pending-deletion rows.

New local intake begins in Short-term. A restart-safe local lifecycle runner
normalizes assertions, consolidates grounded candidates, expires or archives
rows, and records revision-bound transition receipts. Every delayed result is
committed only while its captured owner and input revision remain current.
Embedding compute is transient; vectors and similarity search remain local.

The backend exposes only three authenticated, bounded proposal operations for
Memory extraction, normalization, and consolidation. They use the pinned
Gemini 3.7 Flash model, return opaque local tokens rather than durable IDs,
and own no Memory persistence, search index, maintenance schedule, or product
mutation authority.

#### macOS task and goal authority

The Mac owns tasks and simple goals in the same owner-scoped local GRDB database.
Tasks expose one stable `local_<rowid>` identity and retain local CRUD, grouped
To Do/Done lists, search, due dates and reminders, priority, recurrence, order,
provenance, source-session linkage, and five-second Undo. One simple goal retains
a stable local identity, title, optional description, and active/completed state.
Dashboard, Chat, voice tools, automation, and Task Assistant all read or commit
through these local stores; their success never waits for a network response.

There is no hosted task/goal authority, task staging or suggestion queue, task
ranking, productivity score, task-attached chat/agent/workstream, numeric or
AI-generated goal system, or task-specific push-notification path. The backend
may return an untrusted action-item candidate from transient conversation compute,
but the Mac alone decides whether and how it becomes a durable task.

#### macOS Focus, Insights, and profile authority

The Mac owns Focus sessions and AI Profile history in its owner-scoped local
GRDB database. Focus retains the current state, truthful capture status, today
totals, and a short recent history. AI Profile generation uses bounded local
inputs, commits only locally, and keeps five prior profiles. Neither product
syncs to or falls back to a hosted data authority.

Insights are owner-local Memory records tagged `tips`; the Insights UI is a
projection of that one authority, not a second store. Home questions use bounded
local context and owner/day caching. Home, Focus, and stored Insights navigate
through one top-level Insights hub, while Live Suggestions remain a distinct
local assistant behavior.

Assistant controls and the master notification switch/frequency are local
preferences. Proactive cards and macOS notifications may enter Chat only through
the accepted local journal continuity path. Daily Summary, server AI Profile,
server Focus, hosted assistant/notification/Mentor settings, personalized
purchase/quota push copy, and the Notifications Cloud Run job are not product
authorities. Cloud FCM delivery is not a product surface. Retained fair-use and
managed-usage facts remain server-authoritative, while the Mac presents fixed
truthful in-app copy and deduplicated local OS notifications under the active
owner boundary.

#### Account data lifecycle

**Export My Data** writes one complete, deterministic JSON file from the active
owner's local Mac authorities: conversations/transcripts, Memories, tasks,
goals, Chat catalog/journal, Focus data, and a privacy-reviewed settings
allowlist. Export is owner-generation fenced, works without product network,
and never dumps raw databases, credentials, prompts, caches, or diagnostics.
The backend export returns retained account/subscription/usage metadata only.

Account deletion remains a durable backend job. Its required boundaries are
billing cancellation, Firebase Authentication deletion, and recursive retained
Firestore deletion. It does not restore cleanup clients for retired recordings,
People/voice identity, phone calling, notifications, hosted search, or hosted
product data.

#### macOS update installation

Published builds automatically check for and download updates. A downloaded
update may relaunch the app immediately only when the Mac's authoritative local
activity snapshot is idle. Ambient capture/finalization, an active voice turn,
realtime capture/provider/playback/tool/token work, and Chat send/streaming work
all keep the update scheduled for quit. The app resamples until idle and never
uses a timeout to interrupt active work; development builds remain
install-on-quit only.

#### Before you build

- Large or ambiguous features start as a GitHub issue.
- Trace product behavior to its owning source, public seam, and concrete guard
  test before changing it.
- A product rule without a guard surface is guidance, not an enforced contract.

#### Maintainer operating rule

When declining a PR for direction or taste, cite the applicable principle here
or the concrete repository guard that protects it. Tribal “no” becomes written
guidance or an enforceable test.


## Backend guidance

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/AGENTS.md).

### Backend (Python) — Developer Guide


#### Setup

Python 3.11 is required (not 3.12+ — Dockerfile pins 3.11). Backend local dev pins the exact interpreter in `backend/.python-version` and uses `uv` for reproducible dependency sync. Also needs FFmpeg, Opus (`opuslib`), Redis (optional).

```bash
cp .env.template .env          # Fill in required values (see .env.template for full list)
./scripts/sync-python-deps.sh  # creates .venv from .python-version + pylock.toml
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8080
```

**Env stages** (`OMI_ENV_STAGE`): `local` (emulator harness, `backend/.env.local-dev`), `offline` (fake-backed providers, `.env.offline`), `dev` (remote dev GCP, `.env.dev`), `prod` (reference only, `.env.prod`). `load_backend_env()` loads the stage file then `backend/.env` overrides. Templates: `backend/.env.*.template`. Harness: `PROVIDER_MODE=offline make dev-up` or `OMI_ENV_STAGE=offline`. Offline harness app factories install the shared hermetic Modulate fake for managed live and prerecorded STT without provider credentials. Hosted compute fails closed unless `INTENTIVE_HOSTED_PARTICIPANT_UIDS` contains exactly 1-5 distinct Firebase UIDs; the hosted Dev manifest binds that list from the environment-owned input rather than checking UIDs into source and sets `ADMIN_KEY_AUTH_ENABLED=false` so the retained admin secret cannot impersonate a Firebase UID. The reserved `intentive-release-probe` system UID is admitted only after that human configuration validates. Explicit dev/prod and Cloud Run's injected `K_SERVICE` always enforce admission, including ADC without credential files. Only non-hosted local/offline or unstaged `LOCAL_DEVELOPMENT=true` without credential files bypass it. Billing is independently selected by `BILLING_MODE=disabled|dodo_test|dodo_live`; disabled is the default, ignores billing credentials, and does not load the Dodo SDK or construct its client. Active modes fail startup unless `DODO_PAYMENTS_API_KEY`, `DODO_PAYMENTS_WEBHOOK_KEY`, the normalized `DODO_BILLING_CATALOG_JSON`, and the owned callback `BASE_URL` are all present.

Parity-pack capture is a dev-only, allowlisted, local persistence path and is explicitly disabled in the hosted Dev/Beta runtime declaration. `OMI_PARITY_PACK_CAPTURE`, `OMI_PARITY_PACK_ALLOWED_PRINCIPALS`, and an absolute external `OMI_PARITY_PACK_ROOT` are its complete local capture configuration; it never exports cassettes or constructs a cloud-storage client.

When intentionally changing backend Python dependencies, edit the relevant `requirements*.txt` input file and refresh the lock:

```bash
./scripts/update-python-lock.sh
```

By default, the lock refresh preserves already-locked package versions so unrelated transitive upgrades do not sneak into infrastructure changes. Set `PYLOCK_UPGRADE=1` only when intentionally refreshing dependency versions.

Key env vars: `OPENAI_API_KEY` (text-to-speech only — not `OPENAI_ADMIN_KEY`, which is billing-only), `MODULATE_API_KEY` (managed live and prerecorded STT), `GEMINI_API_KEY` (managed text, embeddings, and realtime), `LANGFUSE_PUBLIC_KEY` plus `LANGFUSE_SECRET_KEY` (fail-open Chat prompt/tracing; both are required to enable it), optional `POSTHOG_PROJECT_API_KEY` with the owned `POSTHOG_HOST=https://us.i.posthog.com` (fail-open server telemetry), and `REDIS_DB_HOST` / `REDIS_DB_PASSWORD` / `REDIS_DB_CA_CERT_PEM` (the hosted verified-TLS Redis boundary). Hosted Google/Apple OAuth uses `BASE_API_URL`, rendered from the environment's canonical Cloud Run URL, to build provider callback URLs. Langfuse uses `LANGFUSE_BASE_URL`, `LANGFUSE_TRACING_ENVIRONMENT`, `LANGFUSE_PROMPT_NAME`, and `LANGFUSE_PROMPT_CACHE_TTL_SECONDS` as non-secret runtime configuration. Hosted `dev`/`prod` uses the Cloud Run runtime service account through ADC and rejects `SERVICE_ACCOUNT_JSON` and `GOOGLE_APPLICATION_CREDENTIALS`; explicit credential files remain local-tool/test-only. Dodo billing is enabled only by the explicit billing mode above; checkout accepts an opaque server-owned offer ID, and the provider webhook is the only authority that projects paid entitlement state.

Chat SSE deadlines: `AGENT_STREAM_FIRST_EVENT_TIMEOUT_SECONDS` (default `25`), `AGENT_STREAM_PROGRESS_HEARTBEAT_SECONDS` (default `20`), `AGENT_STREAM_MAX_DURATION_SECONDS` (default `150`), and `AGENT_STREAM_CANCEL_GRACE_SECONDS` (default `2`) bound silent setup/producer work and keep valid long tool calls observable. Values must be positive. The direct managed-Gemini stream is re-issued on transport-class failures up to `AGENT_STREAM_PROVIDER_MAX_ATTEMPTS` (default `3`), spaced by `AGENT_STREAM_PROVIDER_RETRY_BACKOFF_SECONDS` (default `1`), and only while at least `AGENT_STREAM_PROVIDER_MIN_RETRY_HEADROOM_SECONDS` (default `45`) of the turn budget remains. Do not route normal Chat through an auto lane or introduce a per-request provider switch.

#### Directory Structure

```
backend/
  main.py                 # FastAPI entry and retained route registration
  models/                 # Pydantic request/response schemas (conversation, transient Memory compute, chat, subscription, etc.)
  database/               # All persistence — 25+ domain modules
    _client.py            #   Firestore singleton + document_id_from_seed utility
    redis_db.py           #   Cache, rate limiting (Lua scripts), pub/sub, locks, geolocation
    users.py              #   Retained account, subscription, deletion, and language state
    fair_use.py           #   Usage limits and soft-cap tracking
    ...                   #   + auth, billing, updates, and operational job state
  routers/                # FastAPI route handlers, one per retained feature domain
    transcribe.py         #   /v4/listen WebSocket — auth + exact transient session contract
    listen/               #   Modulate transport, VAD, metering, canonical segments, direct translation
    chat.py               #   stateless Chat compute and transient voice STT
    chat_sessions.py      #   stateless /v2/chat greeting and title compute
    conversation_compute.py # /v1/conversation-compute — stateless discard/structure/action-item candidates
    memory_compute.py     #   Three authenticated, bounded, stateless Memory proposal routes
    auth.py               #   Google/Apple OAuth callbacks, session management
    users.py              #   Account profile, subscription, usage, export, and deletion routes
    ...                   #   + payment and other retained product routes
  utils/                  # Business logic — 60+ files (never import from routers/)
    llm/                  #   LLM orchestration: stateless Chat/conversation/Memory compute,
                          #   fair-use classification, and usage tracking
      clients.py          #     Explicit direct workload clients with prompt caching and usage callbacks
    stt/                  #   Managed Modulate speech-to-text and provider-neutral VAD gating
    retrieval/            #   Retained explicit-file/web/chart tools; no hosted product search
    other/                #   Auth, timeout middleware, and retained update/preview storage helpers
    log_sanitizer.py      #   sanitize() / sanitize_pii() — required for all logging
    encryption.py         #   AES-256-GCM per-user encryption (HKDF-SHA256 key derivation)
    fair_use.py           #   Rolling speech-hour tracking via Redis minute buckets, soft-cap enforcement
    translation.py        #   Multi-language translation coordination
  tests/unit/            # 50+ unit tests (no external service deps)
  tests/integration/     # Integration tests (need Redis, Firebase, API keys)
  scripts/run-unit-ci.sh # Full CI unit-test contract
  test.sh                # Selected-suite executor used by the shared contract
  test-preflight.sh      # Env validator (Python, pytest, packages, Redis)
```

#### Service Map

```
Shared: Firestore, Redis

backend (main.py, canonical Cloud Run service)
  ├── ──────► modulate (managed STT API; in-process Silero VAD gate)
  ├── ──────► managed model providers through explicit in-process workload clients
  ├── ──────► langfuse (fail-open Chat prompt management and generation evidence)
  └── ──────► Cloud Tasks queue `account-deletion` ──► POST /v1/users/account-deletion-wipes/run (OIDC, same service)

```

Managed STT is fixed to Modulate. `backend/config/stt_provider_policy.py` owns its language/capability policy. Both hosted runtime manifests require an exact `MODULATE_API_KEY` secret version; a revision without that binding cannot count as managed-STT or continuity evidence.

- **backend** (`backend/main.py`) — The one REST/WebSocket Cloud Run service. `/v4/listen` applies in-process `VADStreamingGate`, streams fixed PCM directly to Modulate, and returns transient canonical segments without a side channel, People, or conversation storage. Retained Python model workloads call their declared providers directly through `backend/utils/llm/clients.py`.
- **Deployment identity** — `backend` is the logical service and container-image label. Workflows resolve the real environment-owned Cloud Run name only from `BACKEND_CLOUD_RUN_SERVICE`; development is `knowledge-athlete-dev`, while production stays unset until that service is approved. Never fall back to deploying a Cloud Run service literally named `backend`.
- **Deployment authority** — main Release Eligibility remains automatic, but `gcp_backend_auto_dev.yml` is `manual-only`; apply shared Dev backend changes through the existing protected `gcp_backend.yml` dispatcher. Desktop Beta promotion re-fetches the exact GitHub run, canonical Actions evidence, owner-uploaded content-addressed qualification bundle, signed Stable/Beta bytes, and owner identity before any pointer mutation. Qualification admission binds the rendered Actions run name (`Qualify desktop beta <release_tag>`), not the workflow's display name; tag/SHA, repository, path, success, and owner checks remain mandatory.
- **Fair-use review** — `/v4/listen` owns speech meters, thresholds, cooldown, enforcement, and the restricted managed-cloud budget. It requests one content-free review from the authenticated owner Mac; `POST /v1/fair-use/reviews/{review_id}/classify` accepts only the bounded seven-day local evidence projection, invokes Gemini 3.7 Flash transiently, and persists only content-free classifier/enforcement facts. Conversation evidence never becomes backend authority or durable case data.
- **modulate** — The fixed managed STT adapter for configured languages. Called by transcription-capable services through their `MODULATE_API_KEY` binding.
- **account deletion** — `ACCOUNT_DELETION_DISPATCH_MODE=cloud_tasks` and the complete dedicated `ACCOUNT_DELETION_*` bindings enqueue opaque job IDs to the canonical backend's OIDC handler. Startup rejects inline or incomplete configuration, reconciliation only re-dispatches tasks, and API success follows persisted deletion intent plus durable enqueue. A bounded legacy audience/payload branch remains only because no live queue-drain proof was authorized for S-25.

##### macOS conversation boundary

macOS conversation persistence is owner-scoped GRDB, not this backend. Do not
add `/v1/conversations`, `/v1/folders`, public conversation-audio playback, or
People/settings compatibility routes for the Mac. `/v4/listen` is a transient
speech transport for macOS and `/v1/conversation-compute/{discard,structure,action-items}`
returns candidate data without writing conversation records. Hosted listen and
conversation lifecycle are gone; shared historical datastore internals remain
only for the later-slice owners recorded in [FORK](codebase/architecture/overview.md).

##### macOS Chat and Home boundary

The owner-scoped desktop Node SQLite catalog and journal are the sole durable
authority for normal Chat sessions, titles/stars, turns, and activity metadata;
Swift owns drafts and app-managed attachment bytes. Do not add backend session,
message, rating, attachment, projection, reconcile, import, or count authority
for macOS Chat. `POST /v2/chat/initial-message` and
`POST /v2/chat/generate-title` are authenticated, bounded, stateless compute:
they return only a greeting or title and never read or write Chat product data.
Managed answers continue through the desktop Pi native Gemini
`/v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse` boundary; the
Python hosted persona/RAG route is retired. Real managed calls create one
fail-open Langfuse generation, while the offline stub performs no prompt or
observability network work. The optional `X-Intentive-Session-Id` header is bounded
correlation metadata only and never restores backend session ownership.

##### macOS Memory boundary

The effective owner's `omi.db` is the sole durable Memory authority. The backend exposes only
`POST /v1/memory/compute/{extract,normalize,consolidate}`: authenticated, bounded, stateless
proposal computation pinned to Gemini 3.7 Flash. These modules must not import Firestore,
Redis, hosted vectors, product Memory stores, or log request/response bodies. The retained Gemini
embedding proxy is transient compute; vector storage and similarity remain local on macOS.
The proxy normalizes surrounding whitespace on its server-owned `GEMINI_API_KEY` before
building HTTP headers, matching Chat/realtime; an empty normalized key returns 503.

##### macOS Focus, Insights, profile, and settings boundary

Focus sessions, `tips` Insights, AI Profile history, assistant controls, and the
master notification/frequency controls are Mac-local authorities. Do not add
backend Focus/stat APIs, AI Profile persistence, assistant/notification/Mentor
settings mirrors, Daily Summary, personalized purchase/quota push generation,
or a notifications cron job. Cloud FCM delivery is retired; authoritative
fair-use facts are presented by the Mac through fixed in-app and local OS copy.
Managed Gemini remains transient compute and owns no product records.
The bounded `/v1/proxy/gemini` background route admits Gemini 3.7 Flash and
`gemini-embedding-001`. Exact legacy text model IDs from already-installed Beta
clients map to 3.7 Flash at this wire boundary (#102); current Mac callers use
3.7 directly. Keep `ModelQoS.swift`, proxy admission, and the behavioral legacy-client
tests in `test_desktop_proxy.py` aligned. This routing change does not relax auth,
participant admission, request/token limits, or usage meters.

Backend runtime and foundation contract: `backend/deploy/runtime_env.yaml` is the single redacted declaration for exact WIF claim inputs, ADC/secret bindings, Cloud Run, network/Redis, Firestore, retained GCS, Tasks, Artifact Registry, logging, alerts, and budgets. Development and production use public egress plus the shared `intentive-development` Upstash free database and a 1-vCPU/2-GiB request-throttled, zero-to-one-instance Cloud Run profile; their environment identities, runtime services, and exact secret-version inputs remain separate. Keep the claim-policy evaluator, renderer, validator, preflight, and both deploy workflows aligned. Manual `foundation-readiness` performs read-only sanitized GCP drift checks; its external-Upstash fields are declarations whose connectivity is proved separately by the existing runtime TLS probe. `artifact-cleanup-dry-run` only records candidates; neither declaration nor dry run proves a resource was created or authorizes mutation. Run `backend/scripts/pre-deploy-check.sh` after runtime, foundation, or deploy-workflow changes.

Firestore index boundary: backend deploy workflows run `reconcile_firestore_indexes.py --check-only` against `RUNTIME_GCP_PROJECT_ID` in an isolated approved-source job using the dedicated WIF read-only principal. Auto-dev deploys accept only a first-attempt successful same-repository `Release Eligibility` proof for `main` whose `head_sha` still equals freshly fetched and checked-out `main`, then use that admitted SHA for every source-derived step; manual **deploy** mode accepts only an exact main SHA with the same successful proof. Traffic-only repair leaves that input empty and stays source-independent because it changes no source-derived runtime state. A failed gate writes and locally revalidates a short-lived, redacted create-only proposal before upload; only the separate manual WIF writer may create missing indexes, and no lane deletes indexes.

GitHub environment configuration uses `INTENTIVE_GITHUB_TOKEN_VERSION` because GitHub reserves the `GITHUB_` prefix for configuration-variable names. Both deploy workflows map it to the existing renderer input `GITHUB_TOKEN_VERSION`; the Secret Manager object and backend credential remain `GITHUB_TOKEN`.

Keep this map up to date. When adding, removing, or changing inter-service calls, update this section and the executable workflow-contract tests in the same PR.

#### Import Rules

All static imports stay at module top level — never inside functions. The sole
runtime-loader exception is `backend/utils/billing/factory.py`: it imports the concrete
Dodo adapter module only after the service's active-mode guard; the adapter
keeps a normal top-level SDK import for static checking. Strict hierarchy:

```
database/  →  utils/  →  routers/  →  main.py
```

Higher imports from lower, never reverse. Cross-importing between routers will break. `main.py:app` is the only production application entrypoint; route behavior and generated contracts must be checked through that assembled app.

Runtime-selected providers must keep model-token parsing and required environment bindings in a pure `config/` module. Read mutable env at the call boundary rather than snapshotting it during import, and construct SDK clients lazily. For pre-recorded STT, `backend/config/prerecorded_stt.py` is the single source of truth used by both `backend/utils/stt/pre_recorded.py` and the deploy manifest validator; adding a provider or model token requires updating that contract and its runtime/deploy tests together.

#### Database

**Firestore** (primary store): use `get_firestore_client()` from `database._client` at call time, and add optional keyword-only `firestore_client` parameters on converted database helpers so tests can inject fake clients. `db` remains a legacy lazy compatibility proxy only; do not use it in new code. Never construct Firestore clients at import time. Collection group queries need explicit indexes (will 500 with no useful error). Segments are encrypted at rest — direct Firestore reads return opaque blobs. Feature gating via user fields: e.g., translation requires `users/{uid}.language` non-empty — silently disabled if missing.

**Redis** (cache/rate-limiting/locks): use the process-scoped lazy client from `database.redis_connection`; never construct a second client or perform Redis I/O during import. Hosted profiles require AUTH and verified TLS with the declared CA and have no plaintext fallback; local/offline profiles retain the explicit plaintext fake/local seam. Preserve each caller's existing failure policy—ordinary caches may fail open, while OAuth single-use, listen locks, and other correctness/security boundaries fail closed. Rate limiting uses lazily registered Lua scripts; `try_acquire_listen_lock(uid)` prevents duplicate WS connections.

#### Auth

Ordinary authenticated HTTP endpoints use `uid: str = Depends(get_current_user_uid)` from `utils.other.endpoints`. Account management, export/deletion, entitlement, and usage-reporting surfaces remain available to authenticated legacy principals.

Managed compute/mint HTTP endpoints use `uid: str = Depends(get_current_participant_uid)`. This admits the exact hosted participant UID before client-metadata, Redis, or provider work. Managed compute WebSockets use `get_current_participant_uid_ws_listen`; denial closes with code 1008 before the handler runs.

WebSocket endpoints: use `WebSocketException(code=1008)`, **not** `HTTPException` — HTTPException exits ASGI without handshake, causing LB 5xx.

Rate limiting wraps the route's auth dependency: `get_current_participant_uid` for managed compute, `get_current_user_uid` for account surfaces. Use `Depends(auth.with_rate_limit(dependency, "policy_name"))`; policies live in `backend/utils/rate_limit_config.py`.

Managed provider proxies return provider-owned auth and quota failures as typed JSON with
`reason`, `provider`, `backend_route`, `upstream_status_code`, and `retryable`. Clients must
classify these fields at the backend boundary; never infer provider credential ownership from
human-readable error text.

#### Logging Security

Never log raw sensitive data. Use `sanitize()` and `sanitize_pii()` from `utils.log_sanitizer`.

- `sanitize()` for `response.text`, API responses, error bodies.
- `sanitize_pii()` for names, emails, user text.
- Keep UIDs, IPs, status codes visible for debugging.
- Access logs must omit query strings; OAuth callback codes and state values must never reach Uvicorn or Cloud Run log output.
- Never put raw `response.text` in exception messages.

#### Resource Management

- `del` byte arrays after processing and `.clear()` dicts/lists holding data.

#### Testing

```bash
bash test-preflight.sh   # Verify env
bash test.sh             # Run all tests (CI source of truth)
```

**Tests are selector-driven.** `backend/scripts/run-unit-ci.sh` is the full GitHub Actions contract: it selects changed-file tests on PRs, runs preflight and type-checking, then invokes `backend/test.sh`; main CI uses it with `--all`. Local pre-push intentionally keeps its own 40-file cap and runs changed test files when a broad selector exceeds that budget. Do not make the hook call the CI runner: bounded push latency protects the normal development loop. Local `backend/test.sh` runs the selected set from `backend/tests/unit`, `backend/tests/services`, and `backend/tests/routers` via `backend/scripts/select_backend_unit_tests.py`. Tests that need live services (Redis, Firebase, real API keys) go in `backend/tests/integration`, which is not part of selector auto-discovery; note in the PR how you ran them.

**Runtime image contracts.** `backend/runtime_images.json` registers each deployed Python image, its Dockerfile, build context, entrypoints, and deployment workflows. The root `.dockerignore` is a fail-closed allowlist derived from registered Dockerfile `COPY` inputs; keep local credentials, caches, and unrelated checkout roots outside the backend context. Run `make runtime-image-source-closure` to verify that context boundary, final-stage first-party source closure, every host-side `COPY` input's PR/static-check routing, and that every registered deployment workflow smokes its declared Dockerfile; it is the fast pre-push and CI gate. `make runtime-image-smoke SERVICE=backend` builds one image and checks every reachable third-party module is installed offline. PR CI builds every registry-selected CPU image; deployment workflows build and push the full-SHA tag, capture its digest, smoke the published digest, then deploy that same digest. Do not add a hand-maintained image-layout test or workflow mapping; add the service to the registry instead.

**OpenAPI contract runner** — OpenAPI contract checks use `backend/scripts/openapi_runner.sh`, which syncs the pinned `backend/openapi-requirements.txt` runner env and prewarms `tiktoken`; CI and `scripts/pre-push` must use this same path.

**Desktop app-client generation** — `backend/scripts/generate_swift_openapi_types.py` derives its default schema directly from the live `app-client` FastAPI surface. The pinned `backend/scripts/openapi_runner.sh` environment must validate the committed macOS DTO output; explicit `--spec` remains fixture-only.

The app-client snapshot begins at the S-06 retained-product boundary. The pinned pre-S-06 base had neither this snapshot nor its compatibility checker, so the retired developer, integration, MCP, and app routes were never released through this workflow. Future retained-surface changes keep freshness strict.

**Test isolation / import purity** — never mutate `sys.modules` at module scope in tests; production modules must not construct clients or do IO at import time. Sanctioned seams: `monkeypatch.setattr` on a lazy-held singleton, FastAPI `app.dependency_overrides`. Enforced by `python scripts/check_module_stub_pollution.py` and `python scripts/scan_import_time_side_effects.py`. Full prescription: [Backend import purity and test isolation](#backend-import-purity-and-test-isolation).

**Firestore transaction fakes** — a fake at this service boundary must enforce its ordering and constraint semantics. Use `tests.unit.fixtures.strict_firestore_transaction.StrictFirestore` for transaction tests that need document-reference reads plus `set`/`update`: it rejects reads after the first write, the production rule that #9739's lenient fake missed. If an incident requires queries, deletes, retry, or contention behavior, first cover it with the Firestore emulator; extend the fixture only for a proven hermetic guard.

Pre-mock heavy deps before importing the module under test. Use `patch.object(target_module, "func")` not string-based `patch("module.func")` — the string form silently patches the wrong reference if the function was already imported. When modules construct objects at import time, use lazy getters to avoid triggering heavy init in tests.

#### Self-Testing a Change (run the real path)

A passing unit test is not the same as exercising the endpoint. Before putting a change in a PR:

1. **Serve locally**: `backend/scripts/dev-serve.sh` (per-worktree port) or `uvicorn main:app --port 8080`. No GCP credentials? The offline harness covers fake-backed providers with no external services, including managed live and prerecorded STT through the shared hermetic Modulate fake.
2. **Authenticate without a client**: set `ADMIN_KEY` in `.env`, then call endpoints as any uid with `Authorization: Bearer <ADMIN_KEY><uid>` (the key concatenated with the uid).
3. **Hit the changed endpoints** with curl and read the server logs — verify the behavior changed as intended, not just that the route returns 200.
4. **Record the commands and output** in the PR description (root `AGENTS.md` → Definition of Done).

#### Formatting

```bash
scripts/black-wrapper.sh --line-length 120 --skip-string-normalization <files>
```

`--skip-string-normalization` is critical — without it, black flips all quotes and diffs explode.

#### Async I/O (3-Lane Architecture)

Never block the event loop — it freezes health checks, HPA scaling, and all concurrent connections.

- **Lane 1 — Async HTTP** (`backend/utils/http_client.py`): Shared `httpx.AsyncClient` pools with semaphore-bounded concurrency. Never `requests.*` or sync `httpx.*` in async code.
  - Clients: `get_webhook_client()`, `get_maps_client()`, `get_auth_client()`, `get_stt_client()`
  - Semaphores: always wrap calls — `async with get_webhook_semaphore(): await client.post(...)`
  - Circuit breakers: `get_webhook_circuit_breaker(url)` for external targets — call `cb.record_success()`/`cb.record_failure()`
  - Lifecycle: lazy singletons, closed at shutdown via `close_all_clients()`
- **Lane 2 — Executors** (`backend/utils/executors.py`): 7 purpose-specific thread pools. Never ad-hoc `Thread`/`ThreadPoolExecutor`.
  - **Async dispatch rules** (choose the right primitive):
    - `await run_blocking(executor, fn)` — sync/CPU-bound work where the caller needs the result before continuing.
    - `start_background_task(coro, name=...)` — async fire-and-forget work (pipelines, post-processing). Tracks the task, logs exceptions, cleans up references. Never use bare `asyncio.create_task()` for production background work.
    - `submit_with_context(executor, fn)` — short sync fire-and-forget only (precache, small cleanups). Never for pipelines that hold a slot >10s.
  - **Long-running pipelines must be async coordinators.** Each blocking step uses `await run_blocking(pool, fn)`, borrowing a thread only for that step. Never hold a thread pool slot across await points or for >60s.
  - **Pool assignment** (match work type to pool):
    - `critical_executor` (8w) — auth gates only: `_verify_ws_auth`, `check_rate_limit`, `is_hard_restricted`, session/code Redis ops in `auth.py`
    - `db_executor` (24w) — Firestore/Redis CRUD, vector DB queries
    - `llm_executor` (6w) — retained explicit-workload provider calls and first-party generation/classification work
    - `billing_executor` (4w) — billing-provider API calls
    - `sync_executor` (16w) — retained voice-message and file-VAD compute
    - `cleanup_executor` (4w) — durable account-deletion provider and Firestore cleanup
    - `storage_executor` (128w) — GCS uploads/downloads, audio chunk I/O (fan-out gated by semaphores: 32 global chunks, 8 per-call window, 4 concurrent precache files)
  - **Deadlock prevention — 4 rules:**
    1. **Worker threads are leaf operations only.** Never `.result()` on another pool from inside a worker thread. If pool A thread submits to pool B and calls `.result()`, and vice versa, both pools deadlock.
    2. **Orchestration stays in async code.** The async handler coordinates via `await run_blocking(pool, fn)` — sequentially or with `asyncio.gather`. The event loop never blocks, pools stay independent.
    3. **Coordinators must not share a pool with their children.** If a function fans out work to `storage_executor` and waits on `.result()`, that function must run on a different owning pool, never on `storage_executor` itself — otherwise all threads become coordinators and children can't run.
    4. **Long-running coordinators need async orchestration or sized pools.** If a coordinator holds a thread pool slot for >10s, it must either use async coordination (`asyncio.create_task` + `await run_blocking(...)`) or run on a pool sized for `hold_time × peak_concurrency`. Prefer async coordination for any coordinator with hold time >60s — thread slots occupied by sleeping coordinators waste memory and starve other work.
  - **Audit command:** `grep -rn '\.result()' --include="*.py" | grep -v tests/ | grep -v __pycache__` — every hit must be a leaf operation or a coordinator on a different pool from its children.
  - **Pool observability:** `get_executor_metrics()` returns active count, queue depth, and utilization % for all pools. `log_executor_health()` runs every 60s, warns when any pool exceeds 70% utilization. Wired in `backend/main.py` startup event.
- **Lane 3 — Lint**: `python scripts/scan_async_blockers.py --dirs routers utils` catches blocking calls in async routes and helpers.
  The scanner follows direct calls through module-local sync helpers transitively, so moving blocking I/O behind a wrapper is not an escape; offload the helper at the async boundary with `run_blocking`.
  Run from `backend/` before committing. From the repository root, use `python backend/scripts/scan_async_blockers.py --dirs backend/routers backend/utils`.
- **Shutdown**: `close_all_clients()` + `shutdown_executors()` are wired in `backend/main.py`.

#### WebSocket Concurrency (Long-Lived Connections)

The WS handler in `backend/routers/listen/runtime.py` manages concurrent tasks per connection. Use `backend/utils/async_tasks.py` utilities — never raw `asyncio.gather()` or bare `await receive_task`.

- **Supervision**: `supervise_tasks()` wraps `asyncio.wait(FIRST_COMPLETED)` — detects both client disconnect and bg task crashes immediately. Classify tasks as finite (can complete during session) or lifetime (completion = session ending).
- **Drain**: `drain_tasks()` cancels remaining bg tasks with bounded timeout, force-cancels stragglers via `asyncio.wait` (not `asyncio.gather`, which hangs if a task suppresses CancelledError).
- **Fan-out**: `gather_safe()` replaces `asyncio.gather(return_exceptions=True)` — semaphore-bounded concurrency, per-item exception logging, typed `GatherResult[T]` return.
- **Interruptible sleep**: `wait_for_event(event, seconds)` replaces `asyncio.sleep()` in polling loops — wakes instantly on disconnect via per-connection `asyncio.Event`. Never bare `asyncio.sleep()` in WS task loops.
- **Receive timeouts**: every `websocket.receive()` must be wrapped in `asyncio.wait_for(..., timeout=WS_RECEIVE_TIMEOUT)`.
- **Gauge placement**: `GAUGE.inc()` inside `try` body, `GAUGE.dec()` in `finally`. Init `bg_main_tasks = []` before `try`.
- **Task naming**: `create_named_task()` for WS-scoped tasks (tracked in task_set for supervise/drain). Use `start_background_task()` from `backend/utils/executors.py` for fire-and-forget work that outlives the handler.
- **Prometheus labels**: static low-cardinality only (e.g. "listen", "chat") — never uid/session_id.
- **Module-level dicts**: add TTL-based eviction or cap size — they grow forever otherwise.

#### Common Gotchas

1. **Python 3.11 only** — no 3.12+ syntax (nested same-type quotes in f-strings break the Docker build)
2. **Never `time.sleep()` in async** — use `asyncio.sleep()`. For blocking work: `await run_blocking(executor, fn)` with the appropriate pool
3. **Sync `requests` in async is silent poison** — no error raised, just blocks the entire event loop. All connections freeze, health checks fail, HPA can't scale.
4. **Semaphores are event-loop-bound** — `http_client.py` handles this via `(loop_id, name)` keying. Don't create raw `asyncio.Semaphore` outside that module.
5. **Webhook timeout = 30s** — partner integrations depend on this window. Don't change `httpx.Timeout(30.0, connect=2.0)`.
6. **Firestore collection group queries** need explicit indexes — 500 with no useful error
7. **Mutable WebSocket state races** — snapshot `nonlocal` variables before spawning async work
8. **Silent fire-and-forget drops** — functions gating on connection state must log when dropping work
9. **New fallbacks** — call `utils.observability.fallback.record_fallback`; do not invent a new `*_fallback_total` Counter
10. **`langdetect` unreliable on short text** — don't use on <20 chars or gate paid API calls on interim streaming text



### Backend DB and wire boundary — D4

Decision D4, decided 2026-07-04: use converter-at-router. Database modules return
schema-appropriate domain dictionaries and do not import wire models from models.
Domain response normalizers in `backend/utils/` coerce Firestore-native values;
FastAPI response models validate and serialize the wire shape. Do not return raw
database dictionaries from a handler without its response-model boundary. Keep
coercion in the domain normalizer instead of inline router assignments. A new
normalizer is optional when a simple dictionary already matches the model.
This keeps wire-contract changes from coupling database signatures to API models.

### Backend typing rules

Annotate public function parameters and return values. YAML/JSON runtime config
crosses a typed Pydantic, dataclass or TypedDict boundary. Receive dynamic input
as object, validate its shape, then narrow it. Keep unavoidable Any at the
third-party edge. Every type-ignore names the rule and explains why it is needed.
Use timezone-aware `datetime.now(timezone.utc)`. Preserve callable types in
wrapping decorators. Validate decoded Redis/Firestore values before treating them
as dictionaries. The intended acceptance state remains zero errors and warnings.
The current `backend/scripts/typecheck.sh` runner does not enforce all warnings,
and existing warnings remain an explicit gap. Report its exit status and warning
count accurately; do not claim zero warnings when warnings remain. Strict typing
and narrow ignores remain the engineering target.

### Backend import purity and test isolation

Top-level module imports must not perform network/file IO, construct clients or
downloaded artifacts, mutate process-global state, or subscript environment
variables that can fail without a safe default. Move construction into lazy
getters or explicit app startup; this does not authorize in-function imports as
a general substitute. Prefer pure logic and FastAPI dependency overrides.
Patch lazy-held singleton attributes with pytest monkeypatch. Optional package
stubs belong in conftest. Only when a fake must exist before import, use the
fixture/function-scoped `backend/testing/import_isolation.py` helper. Never
mutate sys.modules at test module scope. Production import-side-effect pragmas
require a reason; the test-mutation gate has no pragma escape.
After migration, shrink the applicable legacy allowlist, enroll the file in the
single-process-safe subset, and run its tests and hermeticity guard. The remaining
import-purity commitment closes only when both legacy allowlists are empty, the
whole backend suite is safe in one pytest invocation, and the obsolete helper
has gone. The current file-isolated runner is not proof of that terminal state.

### Route and cache contracts

Issue #8959: route policy identity is service, route type, HTTP method and parameterized path;
function names and OpenAPI operation IDs are evidence, not identity. New routes
must receive policy entries and must never expand the legacy-missing-route list.
Use legacy_unreviewed only for baseline migration; exempt requires an exempt_reason.
Declared policy remains distinct from observed implementation evidence.

DD-007 / PR #29: the Firestore projection cache accepts allowlisted projections, not full user
documents or security, privacy, entitlement or data-protection fields without
separate review, shadow comparison and mismatch metrics.
Redis is not authority: disabled/cache-read/malformed-envelope failures fetch
Firestore; cache-write failure returns the Firestore result; oversized payloads
are not cached. Keys include global version, namespace, policy version and a
collision-free base64url entity ID. Never put raw names, emails, content or secrets
in keys. Invalidate after successful authoritative writes. Cache metrics use
bounded namespace/result labels, never UID, email, route path or free-form keys.
Begin disabled; rollback disables caching or advances the cache namespace version.

### Support operation limits

Transcription-usage reset is an operator action with a dry-run preview, reason,
before/after totals and audit record. Never run its apply mode against real users
in CI or an automated pipeline without an operator decision. It handles numeric
usage, not transcripts or Memory content. Chat-question quota reset remains
deferred pending integration tests across retained counter shapes; automated
goodwill credits and billing policy are separate product decisions. Fair-use
raw throttle/restrict stages have no timer until support changes/resets them;
setting none clears timers. Use the protected admin case lookup, not a guessed
public customer-status route or support mailbox. Live journey metrics cover the
server boundary only and do not prove the desktop committed or played a result.


## Desktop guidance

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/AGENTS.md).

### Desktop (macOS) — Developer Guide

#### Project Overview
Intentive Desktop App for macOS (Swift)

#### Logs & Debugging

##### Local App Logs
- **App log files**: `/tmp/heyintentive.log` (Stable) and `/tmp/heyintentive-beta.log` (Beta). Each non-production
  launch writes to its own owner-only log; ask the running named bundle for its
  exact path with `./scripts/omi-ctl log-path` rather than reading a shared dev log.

##### Release Health (Sentry)
Check errors in the latest (or specific) release using the **sentry-release skill**:
```bash
./scripts/sentry-release.sh              # new issues in latest version (default)
./scripts/sentry-release.sh --version X  # specific version
./scripts/sentry-release.sh --all        # include carryover issues
./scripts/sentry-release.sh --quota      # billing/quota status
```
Run the script with `--help` for the full option list.

##### User Issue Investigation
When debugging issues for a specific user, check Sentry dashboard for crashes and PostHog for events.

##### Product analytics integrity

- A desktop chat query starts after local concurrency/quota preflight and must
  emit exactly one terminal outcome: `completed`, `failed`, or `cancelled`.
  Intentional Stop and supersession are cancellations, never errors.
- A physical voice shortcut turn emits one start and one terminal outcome from
  the coordinator. Full-answer duration ends at playback drain; a later journal
  failure does not rewrite a delivered response as missing. Intentional and
  too-short endings are excluded from response-failure rates.
- Query latency ends when the final answer is visible. Persistence, title
  generation, and other post-answer work have their own reliability signals and
  must not inflate user-visible query duration.
- Product authority is independent from telemetry. Revoked or timed-out turns
  cannot apply late callbacks/results or persist a late response even if
  analytics is disabled or refactored.
- PostHog receives bounded dimensions and shape metadata only. Never send raw
  prompts, responses, notification/window titles, filesystem paths, or exception
  messages. Keep diagnostic detail in the private local log and Sentry.
- Production `QueryTracer` output is shape-only and stored under a `0700`
  directory in `0600` files. Full prompt/response/tool content is a deliberate
  non-production debugging capability only.

##### Fallback / resilience telemetry
Provider/mode switches and fail-open paths must call `DesktopDiagnosticsManager.recordFallback(area:from:to:reason:outcome:)` (PostHog `desktop_health_event` / `fallback_triggered`) or Rust `fallback::record_fallback`. Never invent health-event cases or product “Recording Error” events for successful heals. See [README.md](codebase/architecture/overview.md) for model, window-query, meter, and idle-voice contracts.

#### Repository
- This is the `desktop/macos/` subfolder of the `sruj75/knowledge-athlete` repository
- macOS Swift app lives here; its canonical Python backend lives under `backend`

#### Release Pipeline

No Intentive candidate exists yet. Owned identities, artifact names, signed smoke, nested libwebp
verification and admission are implemented; publication credentials and endpoint bindings remain incomplete:

1. The MVP release repository is exactly `sruj75/knowledge-athlete`.
2. The owned Apple Team is `24D6NXS6H7`; candidate smoke and qualification must match it.
3. Never register an everyday Mac as a GitHub Actions runner. From an isolated exact-tag checkout run
   `scripts/collect-owner-manual-beta-qualification.sh --output-directory <private-dir> <tag>`. It launches downloaded signed Stable/Beta artifacts and a named source qualification bundle, emits `owner-manual-qualification-<sha>-<digest>.zip`, and never uploads/promotes.
   Verify `gh api user` is `sruj75`/`120443863`, upload once without replacement, then dispatch `desktop_qualify_beta.yml` with the exact tag and asset name. `qualification-desktop-command.py` delegates admission/stop to the exact-tag Dev owner: no second token/signal; require healthy clean exact-SHA ownership before T2, then stop/settle before lease release. Reviewed controller repairs may qualify unchanged candidate source/bytes, never reuse failed T2/fault receipts.
4. Root `codemagic.yaml` owns app `6a8ff0296fc70d39540cb56a` and workflows `intentive-macos-release` / `intentive-macos-preview`. Beta requires signing/notary, publication and backend/feed inputs—not preview readiness.
   Owned Stable/Beta Firebase, PostHog, Sparkle and Sentry inputs are protected; public/legal URLs are stored. The tracked PostHog fingerprint must match the token. Never substitute Omi values or bundle PostHog overrides.
5. Do not dispatch candidate/promotion/rollback workflows until their required owned inputs in [OWNER-PROVIDER-DECISIONS](codebase/operations/releases.md) are configured.

The canonical Python backend must host manifest/pointer endpoints before Beta promotion. Release Eligibility checks main; `gcp_backend_auto_dev.yml` is `manual-only`, so merges never change the shared backend. Protected `gcp_backend.yml` owns Dev/prod candidate delivery, traffic promotion, recovery and repair. Static GCS/CDN feed work is deferred, not the channel source of truth.

Signed artifact smoke scope:
- Always-on release audit covers bundle identity, version/tag alignment, signing/Keychain entitlements, Sparkle metadata, backend URL leakage, exact fingerprint-bound PostHog configuration across the app/ZIP/DMG copies, helper/runtime packaging, artifact readability, and local storage package surface. Stable/Beta analytics resolve only from this signed metadata; environment overrides are for non-production bundles only.
- Before outer-bundle signing, the provider must run `desktop/macos/scripts/prepare-release-libwebp.sh` with the candidate Developer ID identity. It verifies the pinned two-architecture cache and structural Mach-O contract, uses only the checksum-pinned source rebuild as fallback, signs the nested libraries in dependency order, and fails before app signing if either path is invalid. Local `desktop/macos/run.sh` continues using Homebrew.
- S-29's build provider must upload the generated `desktop-smoke-result.json` with artifact digests and completed checks; promotion tooling compares this result to the exact release asset before changing channels.
- Provider smoke must run `--auth-storage-canary` and `--notification-callback-canary` inside both exact signed artifacts before Beta admission; neither uses real credentials. Optional broader live probes (`--network --auth --chat --permissions --storage`) require isolation and explicit canary inputs. Launch remains fail-closed without `OMI_SIGNED_ARTIFACT_SMOKE_ALLOW_PRODUCTION_LAUNCH=1`; `--auth` also needs `OMI_SIGNED_ARTIFACT_SMOKE_AUTH_PROOF_COMMAND` proving app-level persistence, not a bearer-token curl.
- Upload immutable candidates first; advance beta/stable visibility only after digest-matched qualification. Upload qualification JSON with its content-addressed basename; `gh release upload`'s `#suffix` sets a label, not a filename.
- Beta qualification fails closed unless exact Stable/Beta ZIP/DMG bytes, provider/owner signed-smoke receipts, readiness, T2, fault-suite, owner upload identity, admission generation and pointer state agree. Scheduled retry is read-only: the owner must re-dispatch an exact evidence asset; GitHub Apps cannot attest Mac results. Pause/resume authority is ADMIN_KEY-protected backend admission, never workflow variables. For a concretely broken Beta, `desktop_rollback_beta.yml` repoints only macOS Beta to a retained T2-qualified manifest; `desktop_breakglass_rollout_beta.yml` advances only to a higher evidence-bound emergency candidate. Both use protected `prod` and the existing Google identity, atomically audit/pause admission, and cannot reach Stable. Rollback cannot downgrade installed clients; follow with a higher-build repair.

Stable is manual:
- Automatic qualification never promotes Stable. `desktop_promote_prod.yml` remains `workflow_dispatch` only and protected by the `prod` environment.
- Run it with the current qualified Beta `release_tag` and `confirm=promote-stable`. It reads and compare-and-swaps the current Stable pointer itself, advances only that pointer, updates the existing legacy/static bridges, and verifies hashes and feed output.
- Canonical backend deployment remains independent from desktop release promotion. Stable
  promotion must check the configured owned production API; no production API is approved yet.
  Do not manually edit release visibility or pointers outside the promotion workflow.

**Artifact provider:** the Codemagic login is established and the owned application is
`6a8ff0296fc70d39540cb56a`. Root `codemagic.yaml` is the Mac builder; GitHub creates an exact
tag or approves an exact preview SHA, then observes/dispatches the provider workflow. The
protected groups hold owned inputs. Publication mints a one-hour `sruj75/knowledge-athlete` Contents-write
token (implicit Metadata read), bound to 30s and never `CM_ENV`; its App key retains all App permissions.
Unexpected authority/lifetime fails closed. Import PKCS#12 with `security import -f pkcs12`.
SwiftPM resolve/both builds use `--disable-keychain` for public downloads (#98); signing/notary credentials,
checksums, exact-main checks and deliberate dispatch remain required.
Live `notarytool history` authenticated, but no new artifact has been notarized.

#### Firebase Connection
Firebase project `knowledge-athlete` owns the new product's authentication/Firestore boundary.
The `(default)` Firestore database exists in `us-west1` with deny-all rules. Desktop app
registration `com.heyintentive.intentive.dev` and its downloaded development plist are owned;
Google and Apple providers are enabled; Stable and Beta registrations/plists use the same MVP
project. Google is sufficient for the first release; native Apple sign-in awaits its owned
identifier/capability. Never copy or edit inherited `based-hardware` credentials into Intentive.

#### Module Layout (SwiftPM)

`desktop/macos/Desktop/Package.swift` is incrementally splitting the monolithic executable into
library targets with enforced dependency edges:

- `OmiTheme` — shared colors, typography, chrome (`Sources/Theme/`)
- `OmiSupport` — shared desktop runtime helpers (`Sources/OmiSupport/`, e.g.
  `DesktopLocalProfile` and `Dictionary(lastWriteWins:)`)

`Rewind/Core/` remains in the executable target for now — it still references main-app
types (`TaskActionItem`, `PowerMonitor`, etc.) and needs a shared-models carve-out first.

**Do not add new `.swift` files directly under `desktop/macos/Desktop/Sources`.** Place new
code in a feature directory (`Onboarding/`, `MainWindow/`, `Chat/`, etc.). CI
enforces this via `desktop/macos/scripts/check-sources-root-layout.py`.

When carving out additional leaf modules, prefer bottom-up order (models and
storage before UI) and wire `import` + `public` on the extracted target's API.

##### Swift Formatting

Swift formatting uses a pinned `swift-format` binary (release 602.0.0 at commit
`62eaad2`), bootstrapped from source via `desktop/macos/scripts/swift-format-wrapper.sh`. The
config lives at `desktop/macos/Desktop/.swift-format` (2-space indent, 120-column limit).
Generated sources under `desktop/macos/Desktop/Sources/Generated` are excluded from the
formatter scope. Bootstrap once: `./scripts/swift-format-wrapper.sh bootstrap`.
Lint the full scope: `./scripts/swift-format-wrapper.sh lint -r $(./scripts/swift-format-wrapper.sh scope)`.

##### SwiftLint

SwiftLint safety rules run as an explicit macOS manifest check (not a SwiftPM
build-tool plugin) through `desktop/macos/scripts/swiftlint-wrapper.sh`. The wrapper pins the
upstream 0.65.0 universal macOS release artifact by SHA-256 and caches the
verified binary under `~/.cache/omi-swiftlint`; use
`./scripts/swiftlint-wrapper.sh lint` to run the full configured scope.
Generated sources and test fixtures remain excluded and the committed baseline
is down-only. SwiftLint baseline locations are absolute, so the wrapper
materializes a temporary baseline rooted at the current checkout before linting;
do not hand-edit those paths to match a specific machine.

##### Synchronous state-machine callbacks

- A reducer transition is atomic through model assignment, effect delivery, UI
  projection, and snapshot publication. A callback may request another event,
  but it must not recursively reduce against a half-published transition.
- Coordinators with synchronous effect/snapshot callbacks drain nested events
  through a FIFO, non-reentrant queue. Do not fix recursion with one-off boolean
  suppression or by dispatching after an arbitrary delay.
- Tests for callback-driven machines must synchronously enqueue from both an
  effect callback and an observer/snapshot callback, assert callback depth stays
  one, and assert the resulting event order.

##### Collection safety

- Never use `Dictionary(uniqueKeysWithValues:)` for API responses, decoded
  persistence, runtime projections, or any other data whose key uniqueness is
  not enforced by the Swift type system. A duplicate key traps and terminates
  the process.
- Use `Dictionary(lastWriteWins:)` from `OmiSupport` when the newest record in
  input order is authoritative. Use another explicit non-trapping merge policy
  when the domain requires different semantics.
- A raw trapping initializer is allowed only for a statically proven uniqueness
  contract, with a local reason:
  `// omi-collection-safety: static-unique-keys -- <why the type guarantees uniqueness>`.
  Runtime validation, backend expectations, and “should be unique” are not
  static contracts.
- Run `python3 scripts/check_desktop_test_quality.py` after changing Swift
  collection construction.

##### Swift test quality

- Await owner-fixture restoration in async XCTest teardown, never `defer { Task { ... } }`; late cleanup can revoke the next test's owner.
- Behavior fixes require tests that call the production API and assert outcomes.
  Reading a production `.swift` file and asserting that it contains a function
  name or implementation string is not behavioral coverage.
- Source inspection is reserved for narrow forbidden-pattern or static wiring
  tripwires. New tripwires must carry a local reason:
  `// omi-test-quality: source-inspection -- static contract: <what cannot be expressed behaviorally>`.
  The tripwire supplements rather than replaces behavioral coverage.
- Do not add wall-clock sleeps to unit tests. Inject a `Clock`/sleeper, drive a
  callback/continuation, or await a deterministic state signal. An unavoidable
  real-scheduler integration wait needs
  `// omi-test-quality: wall-clock-wait -- <why injection cannot test this boundary>`.
- `python3 scripts/check_desktop_test_quality.py` ratchets both legacy
  source-inspection sites and wall-clock waits; its baselines may only decrease.

#### Key Architecture Notes

##### Authentication
- Desktop first-release auth uses Google through `/v1/auth/authorize` plus a Firebase custom token.
- Native Apple sign-in is deferred, not a first-release requirement. Never reuse `me.omi.web`; keep it fail-closed until the owned Apple identifier/capability exists.
- `AuthSessionCoordinator` owns session death (`INV-AUTH-1`); expired/revoked credentials use `invalidateSession`, never `signOut()`.

###### Session vs provider 401

| Failure class | Owner | Action on 401 after forced refresh |
|---------------|-------|-----------------------------------|
| Firebase session token (default API `Authorization`) | `AuthSessionCoordinator` | `invalidateSession` → Sign-in CTA |
| Managed backend provider | `CredentialHealthManager` | Mark unhealthy/use the product fallback; **never** invalidate Firebase |
| Realtime/voice managed lane | `CredentialHealthManager` + hub UX | `requiresLogin` only when session mint fails after refresh |
| Background poll with `RequestAuthPolicy.sessionPreserving` | Caller | Throw `.unauthorized`; no session invalidation |
| `DesktopLocalProfile` harness | Auth emulator bootstrap | Re-bootstrap emulator session; no prod invalidation side effects |

##### Database Structure
- **GRDB/SQLite**: Mac authority, including Focus, Insight tips, and AI Profile
- **Firestore**: user/later-slice state; no Mac fallback
- **Redis**: Caching

##### User Subcollections (Firestore)
- `users/{uid}/conversations` - callerless S-25 drain residue; never Mac/listen authority
- Capture creates its UUID before ingestion; reads/mutations stay local. Recovery/retries select only rows strictly before the fixed app-launch cutoff, never by age alone.
- `/v4/listen` returns untrusted local candidates; Mac UI/authority stays local. Retired: Daily Summary, hosted assistant/notification/Mentor/Focus/AI Profile routes.
- `MemoryStorage` owns Memory/Insight tips; compute/embeddings leave the Mac, owner/revision-fenced.
- `ActionItemStorage`/`GoalStorage` own task/goal CRUD; reminders and assistant/notification prefs stay local.

##### Platform Detection
- **Conversations**: local capture metadata; no broad hosted `source` taxonomy
- **Action items**: No platform tracking

##### Known Limitations
- Counting users by platform requires iterating all users (slow)
- Apple Sign-In: Only one Services ID per Firebase project

#### API Endpoints
- Production: unconfigured; signed production builds fail closed until
  `IntentiveProductionAPIURL` is supplied by the owned release provider
- Owned public-ingress development service: `https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app`
  (protected routes require the owned Firebase user's bearer token)
- Local: `http://localhost:8080`

#### Credentials
Connection details come from your local agent configuration; they are deliberately not
checked in. Ask the user for anything you are missing rather than guessing an endpoint.

#### Development Workflow

##### Building & Running
- **No Xcode project** — this is a Swift Package Manager project
- **Build command**: `xcrun swift build -c debug --package-path Desktop` (the `xcrun` prefix is required to match the SDK version)
- **Full dev run**: `desktop/macos/run.sh` — builds Swift app, starts Python backend, starts Cloudflare tunnel, launches app
- **Fast dev run**: after a full named launch, Swift-only builds reuse static bundle assets, atomically replace/re-sign the executable, and refresh local-profile `.env` without resetting auth. Package/resources/runtime/entitlement changes force full packaging; `OMI_FORCE_FULL_BUNDLE=1` requests it explicitly. `OMI_SCAN_STALE_BUNDLES=1` is recovery-only, never routine cleanup.
- **Focused feedback loop**: `./scripts/dev-feedback.py --once|--watch swift '<XCTest filter>'` or `... python '<pytest path>'` runs exactly the regression you selected and reports each iteration time. It watches only the matching component inputs, keeps watching after a failure, and never replaces the full component suite. Pre-push deliberately adds only `xcrun swift build -c debug`; never promote it to the full pinned-Xcode suite or release compile, because that push-time budget belongs to CI.
- **Swift tests**: Local suites use four workers; CI uses one for its shared `.build` lock. Use `OMI_SWIFT_TEST_SUITE_WORKERS=1` for diagnosis; increase CI workers only with isolated builds. `./scripts/run-swift-ci.sh --release-notification-regression` sets command-scoped `OMI_NOTIFICATION_RELEASE_TESTS_ONLY=1` to select only the callback test target, with release app flags unchanged; normal testing includes all targets.
- **Local Python backend**: `desktop/macos/run.sh` reuses a healthy worktree-owned backend when Python source/config are unchanged. Before first launch, run `cd ../../backend && ./scripts/sync-python-deps.sh`.
- **Agent runtime preparation cache**: local `desktop/macos/run.sh` reuses `.harness/agent-runtime` only when its inputs and every packaged output still match; CI and `--skip-npm` bypass it. Logs say `HIT`, `MISS`, or `BYPASS`; force a rebuild with `OMI_AGENT_RUNTIME_FORCE_REBUILD=1`. Never copy this worktree-local cache or treat it as a release artifact. Checksum-verified universal Node archives are shared at `~/Library/Caches/heyintentive-desktop/node-archives` (override with `OMI_AGENT_RUNTIME_ARCHIVE_CACHE_DIR`) and revalidated before staging.
- **Managed agent boundary**: Chat/Pills use `pi-mono`, Gemini 3.7 Flash, and the owned Unix socket; realtime voice uses Gemini Live separately. Public inputs cannot select providers, models, or working directories; tests may register an internal fake adapter.
- **Release builds**: root `codemagic.yaml` plus `desktop/macos/scripts/codemagic-release.sh` are the only artifact builder. They remain fail-closed until the remaining protected provider-group fields and exact production/public inputs in [OWNER-PROVIDER-DECISIONS](codebase/operations/releases.md) are configured; GitHub controls tag, observe, qualify, promote, or recover but never build.
- **DO NOT** use bare `swift build` — it will fail with SDK version mismatch
- **DO NOT** use `xcodebuild` — there is no `.xcodeproj`
- **DO NOT** launch the app directly from `build/` — always use `desktop/macos/run.sh`. The canonical build installs to `/Applications/Intentive Dev.app`; named builds install to `/Applications/<OMI_APP_NAME>.app`. This is required for macOS "Quit & Reopen" to find the correct binary.
- **DO NOT** manually copy binaries into app bundles and launch them — this bypasses signing, `/Applications/` installation, and LaunchServices registration

- **DO NOT** kill, delete, or interfere with running "Omi", "omi", or "Omi Beta" app bundles — these are production/release installs the user relies on

##### App Names & Build Artifacts
- `desktop/macos/run.sh` builds **"Intentive Dev"** → installs to `/Applications/Intentive Dev.app` (bundle ID: `com.heyintentive.intentive.dev`)
- **Intentive** Stable (`com.heyintentive.intentive`) and Beta (`com.heyintentive.intentive.beta`) are provider-built only. Never use local `desktop/macos/run.sh` or a GitHub runner to manufacture their release artifacts.
- To check which app is currently running: `ps aux | grep "Omi"`

##### Testing with Named Bundles
When the user asks to test a feature or bug fix, **always create a separate named bundle** so it can run side-by-side with the existing dev/prod apps:
```bash
OMI_APP_NAME="omi-fix-rewind" ./run.sh
```
This creates `/Applications/omi-fix-rewind.app` with bundle ID `com.heyintentive.intentive.dev.omi-fix-rewind`, completely independent of canonical Intentive Dev and production-family bundles.

**Build-lock invariant:** `desktop/macos/run.sh` locks per worktree (repo-root `.dev/run-sh-build.lock.d`), through build→install→seed→`open`, then releases before the long-running wait. Parallel worktrees must not block each other. Two named-bundle builds in the *same* worktree still serialize (shared `desktop/macos/Desktop/.build`). Do not reuse the same explicit `OMI_APP_NAME` across worktrees — `/Applications/$APP_NAME.app` is machine-global and not cross-locked.

**Rules:**
- NEVER use the default `desktop/macos/run.sh` (which overwrites canonical Intentive Dev) when testing a specific feature — always set `OMI_APP_NAME`
- **ALWAYS prefix the name with `omi-`** (e.g., `omi-fix-rewind`, `omi-6512-polling`, `omi-vision-test`) so disposable named bundles are recognizable
- Keep the name short and descriptive (it becomes both the app name and bundle ID suffix)
- The named bundle gets its own permissions and writable database and starts clean by default.
- To connect agent-swift: `agent-swift connect --bundle-id com.heyintentive.intentive.dev.omi-fix-rewind`
- **Optional owned parity seed:** set `OMI_SEED_FROM_CANONICAL_DEV=1` to copy auth, curated settings, and a consistent Rewind snapshot only from `com.heyintentive.intentive.dev`. No Omi source or fallback is allowed.
- **Jump to a screen without clicking:** the automation bridge auto-enables on non-prod bundles — `./scripts/omi-ctl navigate <screen>` (e.g. `rewind`, `memories`, `settings rewind`). See "Fast-Path for Local Iteration" in [Desktop testing guidance](#desktop-testing-guidance).
- Routine Dev uses `make desktop-run-local`; named bundles no longer implicitly select hosted development. `--yolo` explicitly selects the hosted service. Before QA, run
  `./scripts/omi-ctl health`; its unauthenticated identity payload reports the
  resolved backend environment/URL plus the agent-runtime handshake state,
  negotiated protocol version, packaged runtime version, and expected protocol.
  A protocol-compatible runtime that omits a required capability is rejected at
  startup; health never reports the expected protocol as if it were negotiated.
- Run `./scripts/agent-logic-harness.sh --cross-surface-smoke` before building a
  QA bundle. This is the compact Swift/Node/Python contract gate; reserve full
  component suites and the live continuity gauntlet for PR readiness.

##### Run Variants & Parallel Worktrees
- `./run.sh --yolo` — quick start against the dev backend, no local services. `OMI_SKIP_BACKEND=1` — app only, remote backend via `OMI_PYTHON_API_URL`. `OMI_SKIP_TUNNEL=1` — no Cloudflare tunnel.
- **Dev beside Beta.** Use the same desktop login; separate apps, data, services, and updates: [[README](codebase/operations/development.md)](codebase/operations/development.md).
- `Intentive Dev` is the canonical shared development profile and the only allowed opt-in seed source. Do not pass `OMI_APP_NAME="Intentive Dev"` from a linked worktree.
- Local Python backend (per-worktree port): `cd backend && ./scripts/dev-serve.sh`.

##### Self-Testing the App (agents)

**Hard rule: you may not ask the user to verify a feature you have not actually exercised yourself.** Compiling, "looks correct from the code", or "scroll down to see it" are not verification. If the obvious path is blocked (permission, focus, missing tool), try a long sequence of alternatives before involving the user — extend the bridge with a new action, add a temporary in-process hook, search the web for a workaround, grant the missing permission yourself if you can, write a tiny standalone harness. Roughly: spend ten serious attempts across different approaches before you escalate. Asking the user is the last move, not the first.

Fast path (skips web login and sidebar click-through):

1. **Build + launch a clean named bundle** (see Testing with Named Bundles above). For deliberate parity, opt in with `OMI_SEED_FROM_CANONICAL_DEV=1`. Manual seeding:
   ```bash
   ./scripts/omi-auth-dump.sh com.heyintentive.intentive.dev
   ./scripts/omi-auth-seed.sh com.heyintentive.intentive.dev.omi-<feature> \
     tmp/desktop-auth.json "/Applications/omi-<feature>.app"   # clears stale Keychain; UD→KC migrate
   ./scripts/omi-settings-seed.sh com.heyintentive.intentive.dev.omi-<feature> com.heyintentive.intentive.dev
   ```
2. **Prefer the local bridge — it never touches the cursor.** It calls the app's real code in-process (no synthetic mouse events). Use it before reaching for `agent-swift click`/`cliclick`/computer-use. Auto-enables on non-prod bundles; run several at once via distinct `OMI_AUTOMATION_PORT` (default 47777).
   - `./scripts/omi-ctl state` — app-state snapshot (selected tab, auth, onboarding).
   - `./scripts/omi-ctl navigate <screen> [settings-section]` — jump straight to a screen in ~150ms (`omi-ctl screens` lists targets).
   - `./scripts/omi-ctl actions` then `./scripts/omi-ctl action <name> [k=v …]` — semantic actions (e.g. `refresh_all_data`). Add new ones in `DesktopAutomationActionRegistry`. See [Desktop testing guidance](#desktop-testing-guidance) §2b.
   - `agent-swift` only for UI the bridge can't reach yet (`click` moves the cursor).
3. **Read logs to confirm behavior:** app + chat bridge in the exact path from
   `./scripts/omi-ctl log-path` (named dev bundles), `/tmp/heyintentive.log`
   (Stable), or `/tmp/heyintentive-beta.log` (Beta); `desktop/macos/run.sh` prints the isolated local Python backend log path at
   launch; per-user issues in Sentry/PostHog.
4. **Verify the actual behavior**, not just that the app launched — exercise the feature and check the logs/UI reflect the change.

##### Default agent development loop

1. **Edit or diagnose:** run the smallest relevant unit/static harness. For repeated saves, start `./scripts/dev-feedback.py --watch swift '<filter>'` or `... python '<pytest path>'`; do not launch the app only to obtain compile evidence.
2. **Swift/UI behavior:** reuse the workspace bundle with `make desktop-run-local`, then assert behavior through its local bridge (`omi-ctl action`, `state`, or semantic snapshot). Hosted `--yolo` is explicit opt-in only.
3. **Package boundary:** use `./run.sh --full` only for the first named launch, resource/entitlement/package/runtime input changes, or when `--fast-only` reports an expected fingerprint mismatch.
4. **QA, commit, and PR readiness:** run `./scripts/omi-macos-dev doctor`, exercise the real user-facing path, then run the appropriate full component/PR contract.

Every `desktop/macos/run.sh` package stamps its full source Git SHA and tracked-tree dirty
state into the signed bundle. Desktop Core T1+, fault, and continuity evidence
accept green only when public `/health` proves the running named bundle came
from the current clean full SHA. A live local stack is reusable only when its
recorded complete launch contract still matches; otherwise run `make dev-down`.

`omi-macos-dev` defaults to bounded JSON summaries so an agent can safely inspect a busy machine. Pass `--verbose` to the specific command for path-level records (for example, `clean plan --verbose`); cleanup always requires the exact current plan hash. The normal 14-day retention window can be deliberately bypassed with `--older-than 0` only when the operator has explicitly approved immediate cleanup.

Never ask a user to test an unexercised path. A fast named-bundle launch plus a semantic bridge assertion is valid inner-loop evidence; a clean full bundle is release/QA evidence.

##### After Implementing Changes

- `xcrun swift build` is for **compile checks only** — it does NOT start the backend
- Voice-path verification means a natural authenticated PTT turn on a named bundle; `ptt_turn_snapshot` must prove physical origin and nonzero capture shape. Use named-dev-only `ptt_live_transport_fault` for recovery evidence; see [Desktop testing guidance](#desktop-testing-guidance) §2b.1. Provider mint or payload changes must also show the deploy-inline provider probe.
- **When the user says "test it"**, use the `test-local` skill to build, run, and verify via macOS automation

##### macOS Version Compatibility
- The deployment floor is `.macOS("14.0")` in `desktop/macos/Desktop/Package.swift`. Every change must work on every supported macOS version from that floor up.
- Never call an API newer than the floor unguarded: wrap it in `if #available(macOS XX, *)` **and give the `else` branch a working fallback** (degrade the feature, don't blank it). Example: System Audio capture gates on `#available(macOS 14.4, *)` and hides cleanly below it.
- Version-dependent system facts (renamed apps, moved paths, changed defaults) get an explicit mapping with the old value still handled — stored user data may predate the change (example: `AppIconCache.renamedApps` maps "System Preferences" → "System Settings").
- Raising the deployment floor or dropping a fallback is a product decision — never do it as a side effect of another change.

##### Open-Source Merge Hygiene
- Before starting and before committing, `git fetch origin && git rebase origin/main` (or merge) — other contributors land changes continuously; never review your diff against a stale base.
- Keep diffs surgical: touch only lines your change needs. No drive-by reformatting, renames, or import reshuffles in files others may have in-flight PRs against.
- After rebasing onto new upstream work, re-run the test suites for every file you touched **and** every file the rebase brought in that overlaps your change; a clean build alone is not revision.
- If your change modifies shared surfaces (Theme tokens, `SettingsSection`, bridge actions, INV-* contract files), grep for all usages — including tests and e2e flows — and update them in the same commit so concurrent contributors inherit a consistent tree.

##### Agent Logic Harness
For agent runtime, floating pills, realtime/PTT, or `desktop/macos/pi-mono-extension`, run this before broader checks:
```bash
cd desktop/macos && ./scripts/agent-logic-harness.sh
```
It times Swift lifecycle, agent runtime, and exact Pi extension tests. Narrow failures with `--swift-only`, `--node-only`, or `--skip-install`. Synthetic owner probes skip credentials (#77); PTT buffers input until the latest history settles (#76), even on a warm socket.

##### Chat Continuity Write-Path Contract (INV-6)

Invariant: Home and floating/notch Chat present one owner-scoped local timeline
through `historyChatProvider`. Node owns Chat metadata; kernel `main_chat` turns
own durable history. Journal acceptance publishes pending projection; UI never
appends pre-journal turns or maintains a backend shadow catalog.

Rules (fail the PR if any break):
1. **Single provider + floating viewport** — floating presentation is chrome + a
   viewport cursor (`FloatingChatViewport` message ids / `clientTurnId`) over
   `ChatProvider.messages`. It must not own a second durable transcript array
   (`chatHistory` of `ChatMessage` copies is forbidden).
2. **Single `turn_recorded` UI apply gate** — only `KernelTurnProjection` on
   `ChatProvider.mainInstance` (`historyChatProvider`) may attach the runtime
   turn handler (one replaceable slot). Speculative warm and other surfaces must
   reuse `mainInstance`; never construct a second `ChatProvider()` that calls
   `attachClient` / `setTurnRecordedHandler` on the shared runtime.
3. **One idempotency key per logical turn** — call `recordJournalExchange` (or
   the corresponding kernel control RPC) with one opaque continuity key and
   await acceptance before binding a visible row. Direct-control spawn receipts
   already materialize their exchange; refresh that journal instead of issuing a
   second write. Never dedupe by assistant/user text.
4. **Kernel apply is idempotent** — `KernelTurnProjection` upserts only by the
   canonical turn ID published by ordered journal replay. Rejection must leave no
   visible row, and replay/acknowledgement must replace rather than append.
5. **Cross-surface agent identity is structured** — `agentSpawn` / `agentCompletion`
   content blocks (plus tool-block `spawnedAgentID` / sessionId / runId lines) are
   authoritative. Persist them in kernel journal; kernel apply still
   materializes `agentCompletion` from bracket text for legacy rows. Legacy
   `[Background agent id=…]` bracket text is dual-read only. Extend schema + tests
   together. Chat turns and catalog metadata stay local; never restore backend
   projection/reconcile outboxes.
   Proactive notifications use continuity key `notification:<uuid>` (origin
   `proactive_notification`) and enter the notification-to-chat cache only after
   journal acceptance; do not reintroduce local timeline append paths.
6. **Pill cache is derived** — open-by-id hydrates from kernel (`listFloatingAgentPills`
   / `listAgentSessions` / `inspectAgentRun`) when the in-memory pill is missing;
   refresh-on-miss is a fast path only. Success = resolvable agent after hydrate.
   Do not keep a second durable pill store.
7. **Snapshots are aliases** — `automationFloatingChatSnapshot` ==
   `automationChatSnapshot` / `automationMainChatSnapshot` over the same messages;
   no surface-specific transcript filter.
8. **Resources live on the producing message** — artifacts attach to the
   `ChatMessage` that produced them (stage/promote keeps `resources` on that id).
   UI must not invent a standalone artifact-only turn. Floating/notch resource
   strips bind `message.displayResources` on viewport-derived messages only
   (never flatMap the whole provider timeline). Aggregate strips must filter
   with `ChatContinuityInvariants.resourcesBelongingToMessages` /
   `FloatingControlBarState.viewportDisplayResources`.
9. **Agent card/list preview = prompt/objective** — collapsed header / list
   subtitle uses `ChatContinuityInvariants.agentPreviewText(prompt:output:)`
   (prompt wins; output is expanded-body only). Do not put raw completion output
   in the one-line preview.
10. **Forbidden dual-write patterns** — never: construct `ChatProvider()` for
    speculative warm (use `ChatProvider.mainInstance`); add
    `addTurnRecordedHandler` / multi-handler append APIs; introduce
    `suppressNextRecordedTurn`; store `@Published var chatHistory` of
    `ChatMessage` copies on `FloatingControlBarState`.
11. **Tests** — continuity behavior changes require a hermetic behavioral test (call
   projection/provider APIs, assert message counts/IDs). Source-string greps for
   function names are not continuity coverage (forbidden-pattern tripwires are the
   exception). Live gauntlet/stress are gates, not substitutes for hermetic tests.

##### Continuity PR Definition of Done (INV-6)

A PR that touches chat write-path, kernel projection, floating viewport, agent
timeline identity/open, or pill projection is incomplete until:

1. **Contract still true** — INV-6 rules above hold after the change (or are
   updated in the same PR with a matching behavioral test).
2. **Hermetic behavioral test** for the invariant touched (stage/promote,
   snapshot alias, structured identity, open-by-id hydrate, viewport derive /
   restore, resources-on-message, agent preview text). Not a source grep
   (except forbidden-pattern tripwires).
3. **`desktop/macos/scripts/agent-logic-harness.sh` green** (includes
   `KernelTurnRecordedProjectionTests`, `ChatTimelineContinuityTests`,
   `FloatingControlBarStateTests`, `RuntimeOwnerIdentityTests` in the Swift
   focus filter).
4. **Write-path / cross-surface changes:** run a named-bundle continuity
   gauntlet and note evidence in the PR:
   ```bash
   cd desktop/macos && OMI_APP_NAME=omi-gauntlet OMI_SKIP_TUNNEL=1 ./run.sh
   # run.sh seeds auth after install (UD tokens → app Keychain migrate). Manual reseed:
   # ./scripts/omi-auth-seed.sh com.heyintentive.intentive.dev.omi-gauntlet tmp/desktop-auth.json "/Applications/omi-gauntlet.app"
   ./scripts/agent-continuity-gauntlet.sh --suite continuity --bundle-id com.heyintentive.intentive.dev.omi-gauntlet
   ./scripts/check-gauntlet-evidence-at-head.sh
   ```
   CI installs locked agent dependencies and runs gauntlet `--self-check`; live suite is a PR/RC gate, not PR CI.
   Evidence is hash/size-only: never retain prompts, replies, identities, logs, screenshots, audio, or machine paths. Do not assert exact assistant wording.
5. **Hermetic e2e** only if a bridge action/surface contract changed. Do not
   expand flow `covers:` lists as fake continuity coverage.
6. **No second message store** / no new free-text identity format / no
   `suppressNextRecordedTurn`-style dual-write bandage.
7. Changelog fragment only if user-visible.

##### Gauntlet / stress gate policy

- **CI:** `agent-continuity-gauntlet.sh --self-check` only (via desktop-core /
  agent-logic harness). Never require live LLM in PR CI.
- **Prompt / gateway changes:** `--suite prompts` on a named `omi-*` bundle;
  P4 requires a current-fact answer with no synthetic public-web activity,
  browsing claim, or source URL. **Continuity PRs / RC:** `--suite
  continuity` (typed + PTT + blind recall) after auth seed; `--suite all` for
  RC. `--require-live-voice` requires exact-turn transport on each attempt, including failure/timeout; simulated/missing fails. Controller probes are not natural-mic evidence. Evidence has the clean bundle's full SHA; backend reuse requires a matching backend/harness fingerprint.
  The S-31 checker rejects incomplete, failed, malformed, stale, raw, media, or secret-bearing evidence. Its pre-push hatch requires both
  `PRE_PUSH_SKIP_GAUNTLET_EVIDENCE_ISSUE` and `..._REASON`.
- **Anti-flake:** clear owner/kernel state; per-run nonces; hard-fail only blind
  recall/structural snapshots; no model-wrongness retry. Spoken replies may use
  spaces for marker hyphens; fields/case/bounds stay exact. Typed/saved/wire
  markers stay literal.
- **Stress:** offline JSONL + forbidden terminal reasons remain the default
  gate; live bridge probes stay optional until continuity `terminal_reason`s
  exist in the taxonomy.

##### Live gauntlet vs hermetic INV-6 coverage

Do not confuse these gates — a green live suite does **not** prove write-path
contract rules, and hermetic unit tests do **not** prove bridge/LLM continuity.

| Gate | What it covers | What it does **not** cover |
| --- | --- | --- |
| **Hermetic** (`agent-logic-harness.sh` Swift filter: `KernelTurnRecordedProjectionTests`, `ChatTimelineContinuityTests`, `FloatingControlBarStateTests`, `RuntimeOwnerIdentityTests`) | stage/promote same key → one message pair; floating snapshot aliases main; structured agent identity; open-by-id hydrate preference; floating viewport derive / SoT; resources on producing message; agent preview = prompt; owner-swap preserves Firebase tokens; forbidden dual-write tripwires | Live bridge auth, LLM tool use, PTT hub, race/busy policy under a real runtime |
| **Gauntlet `--self-check`** | Bridge action registration (incl. R3 `ask_main_chat_no_wait` / `main_chat_busy_state`), resilience suite wiring, hermetic contract test presence in harness filter | Any live turn |
| **Live `--suite continuity` / `agents` / `owner` / `prompts`** | Typed + PTT + blind recall, spawn/status, owner swap probe, prompt regressions on a named bundle | stage/promote single-writer, snapshot alias, hydrate preference, viewport SoT (those stay hermetic) |
| **Live `--suite resilience` (R1–R4)** | Cold bridge launch, warm reuse, bridge busy/race rejection (R3; requires real `is_sending`/`is_streaming` once, latch only extends the race window), subagent launch+status (R4) | INV-6 write-path unit invariants above |

`--self-check` fails if R3 race actions or the hermetic INV-6 test methods /
harness filter classes drift away.

##### Verifying UI Changes (agent-swift)

After editing Swift UI code, verify the change programmatically using [agent-swift](https://github.com/beastoin/agent-swift) — a CLI that controls any macOS app via the Accessibility API.

**One-time setup:** `brew install beastoin/tap/agent-swift` + grant Accessibility permission to Terminal.app.

```bash
### After ./run.sh launches the app:
agent-swift doctor                                   # verify Accessibility permission
agent-swift connect --bundle-id com.heyintentive.intentive.dev  # connect to running app
agent-swift snapshot -i                              # see interactive elements
agent-swift click @e3                                # CGEvent click (SwiftUI)
agent-swift press @e3                                # AXPress (AppKit buttons)
agent-swift fill @e5 "search text"                   # type into a text field
agent-swift find role button click                   # find + chained action
agent-swift is exists @e3                            # assert element exists (exit 0/1)
agent-swift wait text "Settings"                     # wait for text to appear
agent-swift screenshot /tmp/evidence.png             # capture app window
```

**Key rules:**
- Always use `snapshot -i` (interactive only) — full snapshot of a complex SwiftUI app is extremely verbose.
- Prefer `click` over `press` for SwiftUI — `click` sends CGEvent clicks (triggers NavigationLink), `press` sends AXPress (AppKit only).
- Refs go stale after `click`/`press`/`fill`/`scroll` — re-snapshot before the next interaction.
- Argument order: `get <property> <ref>`, `is <condition> <ref>`, `wait <condition> [<target>]`, `find <locator> <value>`.
- 15 commands: `doctor`, `connect`, `disconnect`, `status`, `snapshot`, `press`, `click`, `fill`, `get`, `find`, `screenshot`, `is`, `wait`, `scroll`, `schema`.
- No app-side instrumentation needed — works via macOS Accessibility API on any Cocoa/SwiftUI app.
- Dev bundle ID: `com.heyintentive.intentive.dev`. Stable/Beta are `com.heyintentive.intentive` and `.beta` — never automate production-family bundles.

##### Changelog Entries

After completing a desktop task with user-visible impact, add one fragment file under `desktop/macos/changelog/unreleased/`:

Example `desktop/macos/changelog/unreleased/20260628-short-description.json`:

```json
{
  "change": "Your user-facing change description"
}
```

Guidelines:
- Write from the user's perspective: "Fixed X", "Added Y", "Improved Z"
- One sentence, no period at the end
- Use a unique kebab-case filename so parallel PRs do not conflict
- Skip internal-only changes (refactors, CI config, code cleanup)
- HTML is allowed for links: `<a href='...'>text</a>`
- Do not edit `desktop/macos/CHANGELOG.json` by hand; release automation regenerates it
- Commit the fragment with your other changes (same commit is fine)

#### User Task Completion Reporting

No owned product-support sender is approved. Do not use `omi-analytics`, inherited sender identities, or user email addresses for completion notices; report results only through the channel that originated the task.


### Runtime and voice ownership contracts

The semantic router owns atomic routing decisions; the kernel owns capability
policy. Session execution profiles are immutable. Context fingerprints and
capability fingerprints are distinct and versioned. Request IDs correlate work;
they are not authorization. SQLite schema DDL stays with the store owner. Each
run uses its managed artifact working directory. Change generated tool surfaces
together, with Swift/Node decode tests and restart/idempotency coverage. Context
packets retain provenance, hash, TTL and audit; action queues remain derived.

One realtime controller owns the voice session. It does not directly reach into
ChatProvider or own semantic routing; provider tools need kernel authorization.
The playback worker owns audio SDK effects. Stop invalidates its generation
immediately. Enqueue acknowledgment means SDK acceptance; terminal text/completion
waits for the required acknowledgments. Notification policy does not own mutable
windows. These are ownership constraints, not permission to restore retired
ACP, task-chat, hosted-agent or alternate-provider proposals.

### Dev and Beta coexistence

Use the same logged-in macOS account for Dev and Beta. Never seed Dev from Beta,
copy Beta credentials, or point routine development at shared Beta services.
Keep credentials and temporary state in private internal storage; do not redirect
global TMPDIR or rely on ownership-disabled external volumes for private state.
Archiving preserves profiles, evidence and reusable caches. Coexistence acceptance
requires the actual signed Beta to remain running with login, history and
settings intact through Dev restarts. Record that acceptance as pending when
an appropriate signed Beta is unavailable; a named development build is not proof.

### Qualification runner and manual cleanup

Artifact/security, behavioral and runner-hygiene failures remain fail-closed.
Before reclaiming resources, prove exact SHA, token, sentinel and process identity.
Never kill unknown listeners or a process selected only by its name. Preserve the
runner capacity floor of 32 GiB and 65,536 inodes and the bounded cache reclaim
limit of 16 entries / 128 GiB. Never skip UX gates to meet the 1,200-second target.
Old per-version qualification-helper cleanup is manual after checking launchd,
cron and Hermes references; CI must not automate that cleanup. The pinned cleanup
record identifies the historical paths; deletion remains dependent on a fresh
local inventory, not the age of the record.

### Release health evidence contract

Schema 4, owner desktop/macos, issue #10425: use terminal-only numerators, retain
expected-event exclusions and correlation rules, and report unknown below the
minimum sample. Compare matching windows and version the schema when semantics
change. PT24H minimums are 50 judgeable PTT attempts, 30 mint users, 40 realtime
users, 50 fallback users, 100 crash sessions and 30 updater attempts. Preserve
the surviving event-specific exclusion and correlation definitions from the
pinned release-health record. Its OpenAI-realtime rotation and hosted-Memory query
examples are explicitly superseded by the accepted Gemini-only/local-Memory
product decisions; they must not be used as current acceptance queries.

### E2E and bundle-size evidence

Select the minimum tier appropriate to the changed surface:

| Change area | Minimum tier |
| --- | --- |
| Transcription / audio capture | T2 |
| Rewind artifact persistence / recovery / privacy admission | T2 |
| ChatProvider / agent runtime | T0 + T3 |
| Top navigation / retained destinations | T1 |
| Redesigned Home stage (hub/chat) | T2 (`home-stage.yaml`) |
| Memories / tasks CRUD surfaces | T2 |
| Secondary surfaces (detail, vocabulary, goals, billing, privacy mutations) | T2 + Live P2 for manual-only |
| Qualified-beta promotion | signed-artifact digest gate + T0 self-check + T2 + Fault |

The inherited Rust chat-completions/API-client row is superseded by retirement
of that runtime. Tier commands remain in Desktop testing guidance. Qualification
uses the current owner-manual release path; this table does not restore retired
automatic promotion. Destructive deletion/onboarding flows remain
manual; deletion checks never confirm the destructive action, and logout uses
the local emulator. Review artifacts before publication. Screenshots need human
visual judgment in addition to machine assertions. Bundle-size acceptance needs
before/after byte counts plus a green runtime smoke. Prune packaged dependencies
through the preparation script, never from the developer's installed environment.

## Delivery guidance

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/.github/AGENTS.md).

### GitHub Workflow Agent Guide

These rules apply to GitHub Actions workflows and custom actions under `.github/`.

#### CI/CD Deploy Safety

- Every workflow that mutates a persistent Cloud Run service/job or
  traffic/promotion state must use a workflow-level concurrency
  group scoped to the exact target and logical environment. Manual and
  automatic entry points for the same target must resolve to the same group.
- Deployment group names are a cross-workflow API. Keep them aligned with
  `.github/scripts/check-deployment-concurrency.py`; use
  `cancel-in-progress: false` so a newer run cannot interrupt a remote mutation
  or a staged validation/traffic promotion.
- `deploy-backend-stack-<environment>` intentionally covers the canonical
  backend Cloud Run service, traffic repair, and Firestore migration. Unrelated
  retained services keep their own groups and may deploy in parallel.
- GitHub concurrency is serialization, not a FIFO queue: only one pending run is
  retained and ordering is not guaranteed. Deploy workflows must not assume
  that every intermediate commit will run.
- WIF identities (deploy, read-only index, create-only index writer), exact repository/owner/`main`/environment/workflow-ref claims, and resource IDs come from `runtime_env.yaml`; never restore JSON keys. Manual deploys must install the whole staged workflow-control tree before deleting it so every `DEPLOY_WORKFLOW_ROOT` path resolves.
- Build and push only the full commit-SHA Artifact Registry tag, capture its digest, smoke that published digest, and deploy the resulting `tag@sha256:...` identity. A short SHA is display-only for Cloud Run revision suffixes.
- Dev acceptance uses short-lived probe credentials, never service-account keys in runtime or images.
- Auto scope proves compare `url`/`base_commit.sha` (not `head_commit`; `ahead` = newer HEAD) before cloud auth; retain behavioral tests and exact-main admission. `AUTO_DEV_DEPLOYMENT_MODE: manual-only` keeps eligibility automatic but requires protected `gcp_backend.yml` deployment; no path exceptions.
- `backend/scripts/deploy_status_report.py` must pass; `|| true` is allowed only after a rollout/traffic failure.
- Full backend deploys must derive one immutable canonical Cloud Run release
  vector and run `backend/scripts/verify_backend_release_vector.py` after
  traffic promotion; a mixed or partially applied serving vector must fail the
  workflow and emit evidence for a retry.
- Locked deploy order: candidate health/no-traffic acceptance, traffic snapshot/promotion, serving verification/smoke, conditional rollback. Service + run/attempt tag must fit 46 characters (boundary fixtures).
- Backend deploy workflows may only run Firestore index readiness with `--check-only` against `RUNTIME_GCP_PROJECT_ID`; run it in an isolated job from the approved commit with `GCP_FIRESTORE_READONLY_SERVICE_ACCOUNT`, and bind manual deploys to the exact checked candidate SHA. A failed gate may upload only a locally revalidated, bounded, redacted schema proposal artifact; Firestore index writes use the separate `GCP_FIRESTORE_WRITER_SERVICE_ACCOUNT` in the manual, main-scoped `gcp_firestore_indexes.yml` workflow and share the backend-stack lock.
- `backend/deploy/runtime_env.yaml` owns Cloud Run shape and the redacted foundation contract. Both deploy workflows must consume its renderer outputs, take the stable `run.app` URL as an explicit environment input for fresh-service bootstrap, verify the discovered URL after deploy, and bind exact Secret Manager versions. The manual `foundation-readiness` mode is read-only describe/drift evidence; `artifact-cleanup-dry-run` never deletes. Resource existence is never inferred from the tracked declaration.
- CI runs `actionlint` and policy/owner checks/tests with `python3 -I -S`. Internal qualifier helpers need changelog CLI coverage; PR labels cannot exempt main.


## Owned identities and release prerequisites

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/OWNER-PROVIDER-DECISIONS.md).

<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
### Owner provider decisions

Repository-tracked operator handoff. This file records account ownership and
provider boundaries, but must never contain passwords, tokens, private keys,
certificate contents, API keys, recovery codes, or secret values.

Last updated: 2026-09-08. Individual verification dates are recorded below.

#### Current Dev and Beta destination (owner decision, 2026-09-08)

These are the target boundaries, not a claim that the transition is complete.

- Target two usable environments: isolated local Development on the owner's Mac,
  and the same persistent `Intentive Beta.app` on the owner and four friends' Macs.
  Keep customer `BILLING_MODE=disabled`; this is not a paid or public Stable launch.
- Routine Dev must use a workspace-owned named app, local Firebase Auth/Firestore
  emulators, and local Redis with synthetic accounts. Offline providers are the
  automated-test default. Real AI tests use explicit local development configuration,
  not the owner's everyday login, allowance, or hosted product data.
- The existing Gemini v2, OpenAI TTS v1, and Modulate v1 inference credentials have
  owner-only copies in ignored `backend/.env.local-dev` for those explicit tests.
  This grants no Firebase/GCP administration to the local stack; never copy cloud
  administration credentials or Beta authentication into workspace launch defaults.
- Reuse of the existing hosted stack for Beta is a transition to prepare, not an
  already-deployed Beta. Main merges must not become automatic updates to the
  group's desktop or backend. Separate Firebase app registrations and Cloud Run
  names do not isolate shared Auth, Firestore, or Redis data.
- Preserve Beta/Omi installations, histories, permissions, and credentials. Dev
  launch/stop/archive must own exact workspace artifacts and processes. No permanent
  runner registration, cloud access/traffic change, purchase, or friend publication
  is implied by local implementation approval.
- Reuse Codemagic/Sparkle; propose manual Mac qualification before changing release
  policy. A real signed/notarized A-to-B update and preserved state remain required.
  Older checklist entries below retain their dated evidence; they are not all
  prerequisites for useful local Dev progress or proof that Beta is ready.

#### Product identity

- Visible product name: `Intentive`
- macOS application filename: `Intentive.app`
- Shared technical slug: `heyintentive`
- Owned public domain: `heyintentive.com`
- Never use `intentive.life` or `intuitive.life` as an Intentive product domain.
- Current MVP repository: the existing `knowledge-athlete` repository. Do not create or require a GitHub organization for this release.

#### Provider accounts and boundaries

- Historical Google Cloud cleanup account: `srujan@intentive.life`
  - It was used only to remove the abandoned Intentive development service from `agentic-accountability`.
  - It is not the active Intentive operator and must not be used to create new Intentive resources.
- Google Cloud operator account: `srujan@heyintentive.com`
  - The owner confirmed this exact address on 2026-08-29, and it is present in the live `knowledge-athlete` project Owner policy.
  - Use browser-based `gcloud` OAuth for the next CLI login; do not create or document a permanent user access token.
- Firebase Console primary owner: `srujan@heyintentive.com`
  - Existing Firebase project: `knowledge-athlete`.
  - Use for owned Firebase Authentication and Firestore configuration.
  - `srujantriples@gmail.com` remains a temporary backup owner; do not use it as the product support identity.
- Apple Developer: `22btrsn071@gmail.com`
  - Use only for Apple Developer membership, certificates, identifiers, notarization, and App Store Connect/Apple integration where applicable.
  - Owned Apple Team ID: `24D6NXS6H7`.
  - Membership confirmed 2026-09-08: the owned Apple account shows renewal on 2027-09-09. The owner accepted the updated Program License Agreement, and its warning cleared on readback; neither renewal nor acceptance is notarization or release proof.
  - Installed signing identity reverified 2026-09-08: `Developer ID Application: Srujan Gowda (24D6NXS6H7)`, valid through 2030-11-18. The current Dev app uses certificate fingerprint `C47A7CD975D1D3B4CC7AEC1DD65D188D0102CDC8`; reuse this specific identity, not an export of every Keychain identity.
  - The supplied `.p12` is password-protected and remains under ignored `.context/`; never commit it. Codemagic still needs its password or a separately approved secure re-export of the existing identity. This verification performed no private-key export or upload.
- GitHub account: `sruj75`; GitHub email: `srujan24@icloud.com`.
- Codemagic account login: `srujan24@icloud.com`, connected to the repository owner account `sruj75`.
  - Codemagic login does not have to match the Apple Developer Apple ID.
  - Connect Apple Developer separately with `22btrsn071@gmail.com` only when configuring signing/notarization.
  - Selected application ID: `6a8ff0296fc70d39540cb56a`. Repository workflow IDs are
    `intentive-macos-release` and `intentive-macos-preview`.
  - The second empty application record `6a8ff02926a0b2fbc893544e` was permanently deleted on
    2026-08-29 after explicit owner confirmation. It had no configuration file or build history.
  - Codemagic detected the root `codemagic.yaml` on `main` on 2026-08-29. The selected application's
    GitHub webhook is active for repository create, pull-request, and push events; the workflow's
    tag filter remains the release admission boundary.
- Langfuse project: the existing Intentive US project owns operator tracing and Prompt Management.
  - `intentive-chat-system` version 1 is deliberately blank because Omi's private LangSmith prompt is unavailable.
  - Preserve `intentive-runtime-bundle` versions 1–5 as history; never copy Omi credentials or prompt content.

#### Existing product website

- Use the existing Vercel project `srujxx/intentive-tally-landing-page` and GitHub
  repository `sruj75/intentive-tally-landing-page`; do not create a second landing page.
- Verified 2026-09-05 at website commit `421735ff66828fb1778001e2e7fac95a7d61a1ff`:
  `privacy.heyintentive.com`, `terms.heyintentive.com`, and `support.heyintentive.com`
  are live over HTTPS under the owner's delegated publication approval. The apex
  and its existing Tally form `ODNJ5A` are unchanged.
- The pages use the existing `srujan@heyintentive.com` contact; no email aliases
  were created. Re-review the development-only policies before a public Mac release.
  Download/preview destinations and the `www` TLS repair remain outstanding.
- Firebase's default `knowledge-athlete.web.app` Hosting site has no releases or
  custom domains. It is not the product website; no Firebase Hosting deployment is needed.

#### Sparkle update identity

- Generated 2026-08-29 with the repository-pinned Sparkle tooling under the separate macOS Keychain
  account `heyintentive`; no inherited or default Omi update key was reused.
- Public EdDSA key: `APqAXab2u3W8phgwmTmaHu1ztQgpdr+MR2046hUhflM=`.
- SHA-256 fingerprint of the decoded public key:
  `f9007cb82a319a6343cbcddd6707372c30c4e4984350a15e47e9e386a60076ab`.
- The private key remains in the local login Keychain, with an owner-only ignored backup under
  `.context/release-secrets/`, and is stored as protected Codemagic variable `SPARKLE_PRIVATE_KEY`
  in `intentive_macos_release`. It must never be committed.

#### Google Cloud topology

- Do not create a new Google Cloud project for the MVP.
- Existing Firebase project `knowledge-athlete` is also the Google Cloud project for Intentive Cloud Run, Secret Manager, Cloud Build, and Artifact Registry resources.
- Billing is active on `knowledge-athlete` as of 2026-08-29. The account has a 90-day, $300 trial, but the operating constraint is to stay within the ongoing Google Cloud Free Tier both during and after the trial. Trial credit is not a spending target.
- Gemini Developer API billing uses the same Google Cloud billing account but requires a positive prepaid balance before it will serve requests. The owner added INR 500 on 2026-09-04; auto-reload remains off, and AI Studio states that eligible Google Cloud trial credits apply to usage first. This is not permission to enable auto-reload or raise the existing budget alerts.
- A Google Payments/AI Studio notice asked for business verification on 2026-09-04. The owner is an unregistered solo developer, so agents must not submit invented organization details or nonexistent business documents. If verification becomes required, use an Individual payments profile and the owner's real personal identity documents; the notice did not block the prepaid Gemini API or the verified development deployment at the time it was observed.
- Budget alerts are warnings, not a hard spending cap. Do not deploy a configuration merely because trial credit is available.
- Created 2026-08-29: dedicated development runtime identity `knowledge-athlete-dev-runtime@knowledge-athlete.iam.gserviceaccount.com` with only project role `roles/datastore.user` and secret-level `roles/secretmanager.secretAccessor` on `REDIS_DB_PASSWORD`, `FIREBASE_API_KEY`, `GOOGLE_CLIENT_SECRET`, `GEMINI_API_KEY`, `OPENAI_API_KEY`, `MODULATE_API_KEY`, `LANGFUSE_PUBLIC_KEY`, and `LANGFUSE_SECRET_KEY`. It has no Owner, Editor, deploy, project-wide Secret Manager, Vertex AI, Storage, Tasks, or index-administration role.
- Google Memorystore for Redis is not approved for development because its provisioned capacity is continuously billable and has no ongoing free tier. Do not provision it while the permanent-free constraint applies.
- Deleted 2026-08-29: the abandoned private `knowledge-athlete-dev` Cloud Run service in `agentic-accountability`.
  - Verified afterward that `once-upon-a-time` is the only remaining Cloud Run service in `agentic-accountability/us-west1`.
  - Removed the Intentive runtime account's `roles/aiplatform.user`, `roles/cloudtasks.enqueuer`, self token-creator binding, and conditional cross-project `roles/datastore.user` binding.
  - Disabled `knowledge-athlete-dev-runtime@agentic-accountability.iam.gserviceaccount.com`.
  - Preserved the exact backend container image in the shared `intentive` Artifact Registry for recovery; do not delete the shared repository or unrelated images.
- Created and verified 2026-08-29: public-ingress Cloud Run service `knowledge-athlete-dev` in `knowledge-athlete/us-west1`.
  - Deployment automation must resolve the environment-scoped GitHub variable `BACKEND_CLOUD_RUN_SERVICE`; development owns the value `knowledge-athlete-dev`. The internal runtime/image label remains `backend` and must never be used as a fallback Cloud Run service name. Production intentionally has no value until its service is separately approved and created.
  - Stable service URL used by OAuth and development clients: `https://knowledge-athlete-dev-674306938907.us-west1.run.app`; Cloud Run also reports the compatible alias `https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app`.
  - Active revision as of 2026-09-04: `knowledge-athlete-dev-0ea29f5-33868830964-1`, serving 100% of development traffic from owned immutable OCI image-index digest `sha256:9aa605d892aa53facad6b5b1f75acbd369f7a3006e42f6cec9e709514302502d`; Cloud Run's verified linux/amd64 runtime-manifest digest is `sha256:acb86f103b780445b5c24802831dc430c97da6efba843eadd8a95895812485cd`. Both were built from exact `main` commit `0ea29f5c30cdf93ae3a76ac70f21d7a8bb148977`.
  - Cloud Run grants `roles/run.invoker` only to `allUsers`, matching the repository's `--allow-unauthenticated` ingress contract. Public `/v1/health` returns `200`; a protected route without a Firebase token reaches FastAPI and returns `401`.
  - Permanent-free bootstrap shape: zero minimum instances, one maximum instance, request-based CPU, 1 vCPU, 2 GiB memory, billing mode disabled, Vertex AI disabled, public egress to the external Upstash free database, and no Google Memorystore. The checked-in development runtime/foundation manifest and the active revision declare this same cost-bounded topology. This is still a development service, not a production release.
  - The original bootstrap revision used a recovery image from `agentic-accountability`; that dependency is retired. Repository `intentive` now exists in `knowledge-athlete/us-west1`, and the active revision pulls only from `us-west1-docker.pkg.dev/knowledge-athlete/intentive/backend`.
  - Cloud Build completed the owned image in 7 minutes 29 seconds, within its current monthly free allowance. The one-image repository measured 789.033 MB, about 277 MB above Artifact Registry's 0.5 GiB-month free allowance; at the 2026-08-29 published price this is roughly USD 0.03/month until the inherited runtime is slimmed.
  - The 2026-08-29 Firebase-authenticated bootstrap probe verified Firestore write/read through the runtime identity and verified that the same request created its Redis coordination lock. Its Firebase user, Firestore document, Redis lock, and protected token file were removed afterward. Future deployments use the narrower persistent release-probe permissions described below instead of restoring that bootstrap identity.
  - Exact Secret Manager version 1 values `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` back the existing Firebase-created Google OAuth web client. Firebase Auth was synchronized to the replacement secret, and the client authorizes the stable Cloud Run callback `/v1/auth/callback/google`.
  - Live probing first caught that the inherited OAuth route's `BASE_API_URL` was missing from the hosted runtime. PR #65 now renders it from the environment-owned canonical Cloud Run URL, and PR #67 normalizes whitespace in the Secret Manager-backed Firebase API key. Against the active revision, a real `srujan@heyintentive.com` browser sign-in completed Google OAuth, the backend callback and token exchange, Firebase custom-token generation, and Firebase ID-token exchange. The protected profile endpoint then accepted that Firebase session. No provider refresh token, Firebase ID token, or OAuth code is recorded in Git.
  - Public traffic can consume Cloud Run's monthly allowance; zero minimum instances and maximum one instance bound idle and concurrent consumption but are not a hard monetary cap.
- Provisioned 2026-09-02: the development deployment foundation for the existing `knowledge-athlete-dev` service.
  - Enabled the Security Token Service, IAM Service Account Credentials, and Cloud Tasks APIs. These services do not add an always-running server.
  - GitHub environment `development` owns `BACKEND_CLOUD_RUN_SERVICE=knowledge-athlete-dev`; the `prod` environment intentionally has no service value and no production resource was created.
  - Workload Identity Federation provider `projects/674306938907/locations/global/workloadIdentityPools/intentive-github/providers/github-actions` accepts only repository `sruj75/knowledge-athlete` (repository ID `1312307218`, owner ID `120443863`), `refs/heads/main`, GitHub environment `development`, and the exact backend deploy or Firestore-index workflow paths declared in `backend/deploy/runtime_env.yaml`.
  - `intentive-dev-deploy@knowledge-athlete.iam.gserviceaccount.com` owns development Cloud Run deploy/traffic, Artifact Registry writes, Cloud Tasks administration, Secret Manager metadata inspection, and act-as permission only on the development runtime identity. For the five-minute Firebase release-probe identity, it additionally has secret-value access only to `FIREBASE_API_KEY` and self-only `roles/iam.serviceAccountTokenCreator`; it has no project-wide secret-value, Firestore document, runtime-impersonation, or production access.
  - `intentive-dev-fs-read@knowledge-athlete.iam.gserviceaccount.com` uses custom role `intentiveDevFirestoreRead`, which can inspect Firestore database/index metadata but cannot read documents or mutate indexes. `intentive-dev-fs-write@knowledge-athlete.iam.gserviceaccount.com` uses custom role `intentiveDevFirestoreWrite`, which adds index creation but not document access or index deletion.
  - `intentive-dev-task@knowledge-athlete.iam.gserviceaccount.com` is the account-deletion OIDC signer. The runtime may act as it, the Cloud Tasks service agent may mint its token, and it may invoke only the existing development Cloud Run service through the declared task route.
  - Private bucket `knowledge-athlete-desktop-updates-dev` is Standard storage in `us-west1`, uses uniform bucket-level access, enforces public-access prevention, and has no lifecycle deletion rules. The runtime has bucket-level object-viewer access and self-signing permission; the future S-29 publisher is not provisioned here.
  - Queue `account-deletion` is running in `us-west1`, with one maximum concurrent dispatch, one dispatch per second, and five attempts. Cloud Tasks remains usage-billed after its free allowance; the queue has no idle compute charge.
  - GitHub `development` has the owned non-secret coordinates, exact Secret Manager version numbers, public Google OAuth client ID, and public Upstash TLS CA chain required by the manifest. Secret values remain only in Secret Manager. No corresponding production variables were configured.
  - Verified 2026-09-04: automatic development deployment run `33868830964` attempt 1 exchanged GitHub OIDC for the restricted deploy identity, built and verified the immutable image from exact `main` commit `0ea29f5c30cdf93ae3a76ac70f21d7a8bb148977`, created a zero-traffic candidate, minted and deleted its short-lived Firebase probe user, passed public health, authenticated two-turn Gemini Chat, Firestore read, managed Gemini realtime, exact composition, serving-vector, OpenAI TTS, Modulate, Langfuse, and Redis checks, then promoted the candidate to 100% traffic. Rollback was not needed. The earlier independent probes also completed Google-to-Firebase sign-in, authenticated OpenAI TTS, Modulate batch transcription, and Modulate live streaming through the development service.
  - Reviewed 2026-09-04: the enabled Google APIs and live billable-resource inventory. The retained runtime surfaces include one development Cloud Run service, one Artifact Registry repository, one Cloud Tasks queue, the Firestore database, the private development update bucket, and the Cloud Build bucket; there is no Google Memorystore, Cloud SQL instance, or Pub/Sub topic/subscription. Firebase and Google Cloud automatically enable several platform APIs, and an enabled API alone is not a provisioned paid resource. No API was disabled during the review because broad disablement can break dependent Firebase/GCP services or delete resources; future removals require a separately scoped dependency-and-usage check.
- Configured 2026-09-02: the Cloud Billing Budget API is enabled and monthly alert-only budget `Intentive development monthly alert` is scoped only to project `knowledge-athlete`. It warns `srujan@heyintentive.com` at 50%, 80%, and 100% of INR 100 through notification channel `projects/knowledge-athlete/notificationChannels/6865909329028813232`; default billing-IAM recipients and automated spend actions are disabled. This is warning coverage, not a hard cap.
- Do not deploy a production service or publish a release until the owner separately authorizes the release stage after all slices and product cleanup are complete.

#### Redis topology

- Provider account: `srujan@heyintentive.com` at Upstash.
- Created 2026-08-29: free database `intentive-development`, AWS Oregon (`us-west-2`), TLS endpoint `smart-sunfish-221745.upstash.io:6379`.
- Current free-plan limits observed in the provider console: one free database, 500,000 commands per month, 256 MB storage, and 50 GB monthly bandwidth. Adding a second database currently requires a payment method.
- Owner decision: development and the early MVP production backend may share `intentive-development` until the startup has traction. This is a cost-saving compromise, not production-grade isolation: simultaneous development and production traffic can collide in authentication codes, rate limits, locks, fair-use counters, and caches. Revisit before meaningful production traffic.
- Secret Manager API is enabled in `knowledge-athlete`. Exact enabled version 1 exists for `REDIS_DB_PASSWORD` (development runtime) and `DESKTOP_REDIS_DB_PASSWORD` (future production workflow contract); both currently refer to the owner-approved shared database. Secret values must never be committed to Git or copied into this file.
- Verified 2026-08-29: TLS hostname/certificate validation, ping, temporary set/read/delete, and absence after cleanup all passed.

#### Firebase topology

- Firebase Authentication and Firestore are separate Firebase services.
- Google sign-in is sufficient for the first desktop release. Apple is enabled
  in Firebase, but native Apple sign-in is owner-deferred and must remain unavailable
  until its Apple identifier/capability is configured.
- This defers only the Apple sign-in method, as the owner explicitly requested.
  Membership is confirmed, but distribution signing and notarization still block
  the first real candidate. Google-only sign-in does not bypass those requirements.
- The retained backend separately requires Firestore.
- Existing project `knowledge-athlete` is the development Firebase/data project; do not create another development Firebase project.
- Created 2026-08-27: the `(default)` Firestore database in `us-west1` (Oregon), Standard edition.
  - It was initialized in production mode.
  - Verified active rules deny all third-party client reads and writes: `allow read, write: if false;`.
  - Do not recreate the database or attempt to change its location; the Firestore location is permanent.
- Registered 2026-08-29: Apple app `Intentive Development macOS` for bundle ID
  `com.heyintentive.intentive.dev` (Firebase App ID
  `1:674306938907:ios:befed665f1aa0cd09b40be`). Its downloaded configuration is tracked
  as `desktop/macos/Desktop/Sources/GoogleService-Info-Dev.plist`.
- Registered 2026-08-29 in the same owner-approved MVP project: Beta app `Intentive Beta macOS` for `com.heyintentive.intentive.beta` (Firebase App ID `1:674306938907:ios:8ac38af4a537b8349b40be`) and Stable app `Intentive macOS` for `com.heyintentive.intentive` (Firebase App ID `1:674306938907:ios:56eb726b7c154b6b9b40be`). Their downloaded plists remain owner-only under ignored `.context/release-secrets/`; protected base64 copies are stored in the matching Codemagic groups.
- Secret Manager contains exact enabled version 1 of `FIREBASE_API_KEY`, copied from the owned development app configuration. The API key value is not recorded in Git; the development runtime can read only this exact secret, the Redis secret, and the Google OAuth secret.
- Enabled 2026-08-29: Google and Apple Firebase Authentication providers. Google uses public-facing
  name `Intentive` and support email `srujan@heyintentive.com`. The refreshed development plist
  contains the generated Google OAuth client. Apple Developer identifier/capability registration is
  still required before native Apple sign-in can work in a signed app.

#### Managed-provider classification

An inherited variable in Omi's deployment declaration is not proof that Intentive needs a provider account. Current retained production callers decide the inventory:

- `OPENAI_API_KEY` is retained only for `/v1/tts/synthesize` using `gpt-4o-mini-tts`. It no longer owns text inference, embeddings, realtime voice, or relay traffic. Verified 2026-09-02 under OpenAI account `srujantriples@gmail.com`: the Personal organization's Default project has one service-account key named `Intentive development TTS`, restricted to request permission on `/v1/audio/speech` with every other permission set to none. Its value is stored only as enabled Secret Manager version 1, GitHub environment `development` selects exact version `1`, and only the limited development runtime identity can read it. A direct `gpt-4o-mini-tts` probe returned HTTP 200 with MPEG audio, while a models-list request returned HTTP 403 and proved the denial boundary. Verified again 2026-09-04 through the active authenticated backend route: `/v1/tts/synthesize` returned HTTP 200 and a non-empty MPEG audio file. The active Cloud Run revision binds version 1.
- `ANTHROPIC_API_KEY` and `DESKTOP_LEGACY_ANTHROPIC_KEY` are deleted requirements. Normal Chat uses Gemini; neither credential should be created or bound.
- One development `GEMINI_API_KEY` is enough for the MVP. Gemini 3.7 Flash owns normal Chat, greeting, conversation processing, Memory compute, and fair-use classification; existing Flash-Lite title/translation, desktop generation/embeddings, and Gemini Live routes remain. Model inference uses the Gemini Developer API only; `USE_VERTEX_AI` is deleted while Cloud Run ADC remains for Firebase, Firestore, and other GCP infrastructure.
- Verified 2026-09-04: the earlier `GEMINI_API_KEY` version 1 is a standard API key. A replacement authorization key is bound to the limited development runtime service account, restricted only to `generativelanguage.googleapis.com`, and stored without committing its value as enabled Secret Manager version 2. GitHub environment `development` selects exact version `2`, and the active Cloud Run revision binds it. After the owner added INR 500 prepaid credit with auto-reload off, a direct Gemini 3.7 Flash request, authenticated two-turn candidate Chat, and managed Gemini realtime probe all passed. Version 1 remains enabled only as an explicit rollback copy and should be retired in a separate credential-cleanup operation. Do not create parallel per-model keys.
- `MODULATE_API_KEY` is retained for fixed managed live and prerecorded-overflow STT. Verified 2026-09-02: the owned Modulate key `Intentive development` is limited to 500 credits and only `velma-2-stt-streaming` plus `velma-2-stt-batch`. Its value is stored only as enabled Secret Manager version 1, GitHub environment `development` selects exact version `1`, and only the limited development runtime identity can read it. The active Cloud Run revision binds version 1. Verified 2026-09-04 through the authenticated hosted backend: the prerecorded `/v2/voice-message/transcribe` route returned the expected known-fixture phrase, and the `/v4/listen` WebSocket produced a matching final segment while the client remained connected and sent microphone-style trailing silence.
- `POSTHOG_PROJECT_API_KEY` is retained telemetry. Verified 2026-09-04 under account `srujantriples@gmail.com`: organization `Intentive`, project `Intentive Desktop` (project ID `397035`), US ingestion host `https://us.i.posthog.com`. The project was empty before setup; a bounded `intentive_configuration_probe` was then accepted and observed in the live Activity view. The public client token and host are stored in Codemagic's shared `intentive_macos_signing` group and the ignored local Mac environment; the token value is not committed. The release contract checks the supplied token against a tracked SHA-256 fingerprint, stamps both values into every built app, and signed-artifact smoke rejects missing or mismatched ownership across app/ZIP/DMG copies. Stable/Beta read only that signed metadata; environment overrides remain non-production-only. Backend defaults and the hosted runtime declaration use the same US ingestion host. Do not reuse an inherited Omi token.
- `ARTIFICIALANALYSIS_API_KEY` is deleted with Auto and the provider picker; there is no remaining provider comparison to score.
- Langfuse now owns Chat tracing and prompt management. Verified 2026-09-04: the existing credentials authenticate to the owned US Cloud project `Intentive`; `intentive-chat-system` resolves to blank version 1 with `production` and `latest`, while `intentive-runtime-bundle` history remains untouched. The public and secret credentials are stored separately as exact Secret Manager version 1 values, GitHub environment `development` selects both version 1 values, and only the limited development runtime identity can read them. The active Cloud Run revision binds both values. The successful two-turn deployment gate produced two private `desktop-chat-completion` generations for `intentive-release-probe`, both linked to prompt version 1 with Gemini usage, cost, latency, and first-token evidence.
- `DESKTOP_GOOGLE_CALENDAR_API_KEY` must not be configured: IR-106, IR-142, IR-144, and IR-375 delete the Calendar creation/import/enrichment/linking surfaces.

#### Release-readiness checklist

This is the complete handoff, not a request to release now. A checked item is known or
already done. An unchecked item is still required before the corresponding live operation.

##### Already decided or completed

- [x] Use GitHub repository `sruj75/knowledge-athlete` for the MVP; do not create a new organization yet.
- [x] Use product name and app filename `Intentive` / `Intentive.app`.
- [x] Use slug `heyintentive`, public domain `heyintentive.com`, and owned bundle namespace `com.heyintentive.intentive`.
- [x] Use Apple Team ID `24D6NXS6H7`; an owned Developer ID Application identity is installed locally.
- [x] Use Codemagic login `srujan24@icloud.com` and Apple Developer login `22btrsn071@gmail.com`.
- [x] Use Codemagic app `6a8ff0296fc70d39540cb56a` with repository-owned workflow IDs
  `intentive-macos-release` and `intentive-macos-preview`; the root `codemagic.yaml` owns both.
- [x] Use `srujan@heyintentive.com` as the Google Cloud operator for future Intentive resources.
- [x] Use the existing Firebase/GCP project `knowledge-athlete` for future Intentive development cloud resources; do not create another project.
- [x] Use Firebase project `knowledge-athlete`; its `(default)` Firestore database exists in `us-west1` with deny-all client rules.
- [x] Use Sentry organization `heyintentive` and macOS project `desktop-macos`; the macOS DSN and dSYM upload destination are repository-wired.
- [x] Use PostHog account `srujantriples@gmail.com`, organization `Intentive`, and US project `Intentive Desktop`; Mac release inputs are stored in the shared Codemagic signing group without committing the project token.

##### Needed before hosted Firebase sign-in or backend Firestore access

- [x] Register the owned development macOS app in Firebase project `knowledge-athlete` and track its downloaded Google service plist without rewriting an inherited Omi plist.
- [x] Use the same owner-approved MVP Firebase project for Development, Beta, and Stable; register `com.heyintentive.intentive.dev`, `com.heyintentive.intentive.beta`, and `com.heyintentive.intentive`, and preserve each real plist only in its tracked or protected owner.
- [x] Enable and configure Google sign-in in Firebase Authentication with public-facing name `Intentive` and support email `srujan@heyintentive.com`; track the refreshed development plist containing its OAuth client.
- [x] Enable Apple sign-in in Firebase Authentication. Native use is deferred and
  still requires the Apple Developer identifier/capability under account
  `22btrsn071@gmail.com`; Google is sufficient for the first release.
- [x] Grant the development runtime identity only application-level Firestore data access (`roles/datastore.user`). The database continues to deny direct third-party client access on purpose.
- [x] Verify one development Firestore read/write path through the runtime identity after the hosted Cloud Run service exists; the fixed release-probe user wrote and read `language=en`, then all probe state was deleted. No service-account key file was created.

##### Needed before the hosted development backend is fully usable

- [x] Connect billing to `knowledge-athlete`; confirmed active on 2026-08-29.
- [x] Review the currently enabled APIs and live project resources. Required development APIs remain enabled; default/Firebase-managed APIs were not blindly disabled, and API availability remains neither a provisioned paid resource nor authorization to create one.
- [x] Create and verify the public-ingress `knowledge-athlete-dev` Cloud Run service and dedicated runtime identity inside `knowledge-athlete/us-west1` using the documented permanent-free bootstrap shape.
- [x] Use the one free Upstash database `intentive-development` for development and owner-approved early MVP production. Do not provision Google Memorystore under the current cost constraint; revisit environment isolation before meaningful production traffic.
- [x] Verify shared Upstash remains on Free Tier. The 2026-09-05 dashboard showed
  $0.00 cost, 99/500,000 monthly commands, 207 B/256 MB storage, and 0 B/50 GB
  bandwidth, with TLS enabled. This is a point-in-time usage check, not a guarantee
  about future traffic or the separate Google Cloud/provider charges.
- [x] Store the development Redis password, Firebase API key, Google OAuth client secret, OpenAI TTS-only key, Modulate key, and both Langfuse credentials as exact Secret Manager version 1 values, plus the Gemini authorization key as exact version 2. The runtime identity has secret-level access only to `REDIS_DB_PASSWORD`, `FIREBASE_API_KEY`, `GOOGLE_CLIENT_SECRET`, `GEMINI_API_KEY`, `OPENAI_API_KEY`, `MODULATE_API_KEY`, `LANGFUSE_PUBLIC_KEY`, and `LANGFUSE_SECRET_KEY`; the Google client ID remains non-secret deployment configuration.
- [x] Retire the active service's cross-project recovery-image dependency by building and serving an immutable backend image from `knowledge-athlete/us-west1/intentive`.
- [x] Bind OpenAI TTS-only key version 1, Gemini authorization key version 2, Modulate key version 1, and both Langfuse version 1 credentials through the complete development deployment. The real authenticated Gemini Chat and Gemini realtime gates passed, and both Chat turns are visible as private Langfuse generations linked to the owned prompt; no Anthropic or Artificial Analysis credential exists.
- [x] Prove the active revision's authenticated OpenAI TTS route and real Modulate batch/streaming continuity. All three live checks passed and the current deployment gate rechecked the provider bindings on revision `knowledge-athlete-dev-0ea29f5-33868830964-1`.
- [x] Admit public Cloud Run invocation while retaining Firebase authentication on protected routes, and point development desktop defaults at the discovered owned URL.
- [x] Enable the Cloud Billing Budget API and configure the owner-approved INR 100 monthly alerts at 50%, 80%, and 100%. Alerts are not a hard cap; retain scale-to-zero and maximum one instance regardless.

##### Needed before Codemagic can build a signed candidate

- [x] Connect `sruj75/knowledge-athlete` from the `srujan24@icloud.com` Codemagic account and record the selected application ID `6a8ff0296fc70d39540cb56a`.
- [x] Create and record exact repository workflow IDs `intentive-macos-release` and `intentive-macos-preview`; GitHub dispatch and observation use those owned IDs.
- [x] Delete the empty duplicate Codemagic application `6a8ff02926a0b2fbc893544e`; only the selected application remains.
- [x] Finish YAML setup for the selected Codemagic app and create/update its GitHub webhook after the provider document reached the default branch.
- [x] Store the existing Codemagic API token only as protected GitHub Actions secret `CODEMAGIC_API_TOKEN`.
- [x] Populate the existing approved Codemagic values. Verified 2026-09-05:
  `intentive_macos_signing` has the Stable Firebase plist, desktop Firebase environment,
  and PostHog key/host; `intentive_macos_release` has the Beta plist, Sparkle pair,
  and Sentry upload token. The release group also stores non-secret
  `INTENTIVE_PRODUCT_URL=https://heyintentive.com/`,
  `INTENTIVE_PRIVACY_URL=https://privacy.heyintentive.com/`,
  `INTENTIVE_TERMS_URL=https://terms.heyintentive.com/`, and
  `INTENTIVE_SUPPORT_URL=https://support.heyintentive.com/`.
  All four were read back; secret rows were unchanged and no build was started.
- [x] Store the existing Intentive Release App private key in Codemagic as protected
  `INTENTIVE_RELEASE_APP_PRIVATE_KEY`. Verified 2026-09-09: exactly one masked value
  persisted in `intentive_macos_release` after a page reload; no token was minted and
  no build or release started.
- [x] Save the five approved candidate backend/feed/download inputs in
  `intentive_macos_release`. Verified after reload on 2026-09-09: API and protected
  approved origin are `https://knowledge-athlete-dev-674306938907.us-west1.run.app`;
  Stable feed is `/v2/desktop/appcast.xml`, Beta adds `?identity=beta`, and the
  manual-download base is `/v2/desktop/download/latest`. The workflow already owns
  the GitHub releases URL. This saved configuration started no build, deployment,
  or publication; hosted Beta activation remains separately approved.
  The preview group remains unconfigured and is not a five-person Beta prerequisite.
  Populate only names validated by `desktop/macos/scripts/codemagic-release.sh`;
  never commit credentials or fill missing destinations with fake working URLs.
- [x] Re-export the exact owned Developer ID identity and save its P12/password as masked Codemagic `intentive_macos_signing` secrets. Verified 2026-09-08: P12 password/MAC, certificate fingerprint/team/expiry, and private-key/public-certificate agreement passed; saved values persisted after a page reload. Only protected local/provider copies hold the secret bytes. A Codemagic import/build has not run yet.
- [x] Confirm Apple Developer Program membership for team `24D6NXS6H7`: verified 2026-09-08, next renewal 2027-09-09. The owner accepted the updated license agreement; the account warning cleared on readback.
- [x] Configure Apple notarization credentials. The owner accepted API access and supplied the replacement `Intentive Codemagic Notary 2` Developer-role key after the first download was unavailable. On 2026-09-08, OpenSSL key validation and live read-only `notarytool history` authentication passed. Key/issuer/ID are masked Codemagic `intentive_macos_signing` values; the local key copy is private and gitignored. Existing keys were not revoked. This proves access, not a newly notarized candidate.
- [ ] Register the stable, Beta, development, and preview identifiers/schemes with Apple/provider services where registration is required.
- [x] Generate a new Sparkle EdDSA keypair, store it under the separate `heyintentive` Keychain account, configure the public key in Codemagic, and record its public-key fingerprint above.
- [x] Add the Sparkle private key only to Codemagic's protected `intentive_macos_release` group.
- [x] Configure protected Codemagic variable `SENTRY_AUTH_TOKEN` in `intentive_macos_release` for dSYM upload to `heyintentive/desktop-macos`. The Sentry organization token is named `intentive-macos-release-symbols`, has only the `org:ci` scope, and was verified against Sentry's debug-files endpoint before storage. The token value must never be committed.
- [ ] Complete the protected GitHub Beta environment's matching API/origin and promotion-token bindings. The Codemagic release group's five candidate addresses above are approved and saved; this does not approve public Stable or configure Preview. Missing environment-specific authority must continue to block that operation.
- [x] Configure the owned `Intentive Release` GitHub App (`intentive-release`,
  app ID `4838294`, installation `159216850`), installed only on
  `sruj75/knowledge-athlete`. Its ID/private key are protected GitHub secrets.
  Verified 2026-09-05: App authentication and scoped check/workflow reads passed;
  Actions/Contents/Pull requests are write-enabled, Checks/Metadata read-only.
  The ephemeral verification token was revoked; no tag or release was created.
  Codemagic's separate protected Release App private-key input was populated and
  read back masked on 2026-09-09; no installation token or release was created.
- [ ] Protect `main` through the existing required CI checks and PR-only merges.
  Verified 2026-09-05: neither branch protection nor a ruleset is configured.
- [ ] Exercise the owner-manual qualification path on an exact signed candidate. Do not register the everyday Mac as a permanent, ephemeral, or JIT Actions runner; GitHub independently validates the owner-uploaded evidence and exact artifacts.

##### Needed before Beta or Stable publication

- [ ] Create production Cloud Run/backend resources and public release endpoints only after the owner gives a new explicit release-stage authorization. No current development service should be mistaken for production authority.
- [ ] Configure the release/preview object bucket, public origin, Firestore release documents, service identities, and protected GitHub environments against owned resources.
- [x] Identify the already-published `heyintentive.com` landing page and its Vercel/GitHub owners above.
- [x] Publish development Privacy, Terms, and Support subdomains under the owner's
  delegated approval, using `srujan@heyintentive.com` and leaving the apex unchanged.
- [ ] Add approved download/preview destinations and repair `www` TLS only after
  separate authorization; no `support@heyintentive.com` or `privacy@heyintentive.com` alias exists.
- [ ] Re-review Terms and Privacy before a public Mac release. The current operator
  is an individual, not a registered company; do not invent a legal company name.
- [ ] Run one signed/notarized candidate, trusted-Mac qualification, clean-install/update exercise, and Beta/Stable recovery drill with evidence tied to the exact source SHA and artifact digests.
- [ ] Give fresh explicit authorization before any candidate, Beta, Stable, paid artifact,
  additional DNS/legal publication, or production resource. The three policy/support
  subdomains were separately authorized; their publication is not app-release approval.


## Unresolved commitments

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/BACKLOG.md).

### Backlog

This file owns work that the product owner has intentionally deferred. An open
entry is not accepted, waived, or silently treated as green. It names the point
at which the work becomes mandatory again and the evidence required to close it.

#### BL-001: Final all-waves provider and continuity qualification

**Status:** OPEN — provider/deployment inputs now exist; final real-provider and
continuity qualification is not yet recorded

**Run when:** every deletion-map wave has been implemented, before the final
all-waves closeout or any release claim

**Next-wave effect:** does not block starting S-26 or S-28, provided they include
the complete Waves 3–4 repair tree

##### Why this was deferred

At the 2026-08-26 deferral, the Waves 3–4 repository repairs and local
acceptance were strong enough to continue sweeping later vertical slices. The
remaining rows required approved non-production provider credentials and a
verified deployed development identity that were not then available. The
offline echo provider could prove lifecycle mechanics, but it could not
truthfully prove that a real provider remembered and recalled earlier context.

This scheduling decision does **not** close the combined Waves 3–4 closeout and
does **not** relax its original acceptance contract. It moves the unavailable
live qualification to one explicit gate at the end of all waves.

##### Current status — 2026-09-04

The original availability blocker is resolved. The approved development
Gemini, OpenAI TTS, Modulate, and Langfuse credentials are bound to the verified
`knowledge-athlete-dev` deployment, whose active revision
`knowledge-athlete-dev-0ea29f5-33868830964-1` serves exact source SHA
`0ea29f5c30cdf93ae3a76ac70f21d7a8bb148977`. Their development checks passed.
BL-001 remains open because the natural physical-PTT, real-provider continuity,
same-provider reconnect/tools, buffered Modulate recovery, deploy-inline mint,
and direct-provider rows have not all been rerun and recorded on one current
final SHA. This update does not relabel the historical baseline below.

##### Proven baseline before deferral

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
[[wave-3-4-closeout tdd](codebase/operations/qualification.md)](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/wave-3-4-closeout%20tdd.md).
Each slice's original acceptance record remains the authority for its own
matrix; one generic Tier-2 run does not replace those records.

##### Required exit evidence

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

#### BL-002: S-25 verified live-resource inventory and operational handoff

**Status:** OPEN — verified operator/project identity and an initial live
inventory now exist; final classification and operational handoff remain

**Run when:** after every deletion-map wave is implemented and before any live
resource decommission or operational-closure claim

**Current effect:** does not block repository work; blocks live-resource or
operational-closure claims

The sanitized historical S-25 inventory is recorded in
[[s-25 tdd](codebase/operations/qualification.md)](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-25%20tdd.md#191-sanitized-live-resource-inventory-handoff--2026-08-26).
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

#### BL-003: S-27 deferred broad verification

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



### Additional retained commitments

- Runtime gap-closure G6: delete SQLite legacy_client_scope and legacy_session_key
  two desktop releases after the release shipping the platonic refactor. The
  columns still exist in the runtime store; no shipping date or completion is
  inferred here. The Desktop runtime owner must establish that release boundary
  before this retirement. Historical task-chat/ACP proposals are superseded by
  the current local Chat product constraints and final IR decisions.
- Backend E2E v2: deterministic retained LLM clients, per-test LLM 500/timeout
  injection, and Redis-unavailable fail-open coverage remain unchecked work from
  the original E2E guide. Preserve its hermetic socket guard, prohibit dynamic
  dependency installation in the runner, and seed retained account fixtures only.
- The backend import-isolation terminal state, actual signed-Beta coexistence,
  and manual stale qualification-helper inventory described above are not
  closed by this documentation migration.

High-risk workflow contracts retain first execution, partial failure/retry,
completed resume, idempotent skip and side-effect-failure accounting. A required
failed step must not yield a successful workflow result. Live journey metrics
exclude synthetic traffic; STT success means the first nonempty payload sent,
not client rendering. Idle counters export zero, and counters never replace the
durable account-deletion state.

### Specialized guidance provenance

These records preserve the original decisions, dates, owners, query definitions,
operating details and historical evidence behind the consolidated rules. Use
current source-grounded wiki pages for implementation; do not reinstate a retired
product from an earlier example.

- [backend/docs/db_pydantic_boundary.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/docs/db_pydantic_boundary.md)
- [backend/docs/type_safety.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/docs/type_safety.md)
- [backend/docs/test_isolation.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/docs/test_isolation.md)
- [backend/docs/firestore-cache-architecture.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/docs/firestore-cache-architecture.md)
- [backend/docs/route_policy_manifest.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/docs/route_policy_manifest.md)
- [backend/docs/runbooks/reset-transcription-usage.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/docs/runbooks/reset-transcription-usage.md)
- [backend/docs/runbooks/real-traffic-journeys.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/docs/runbooks/real-traffic-journeys.md)
- [backend/testing/WORKFLOW_CONTRACTS.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/testing/WORKFLOW_CONTRACTS.md)
- [backend/testing/e2e/README.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/backend/testing/e2e/README.md)
- [scripts/dev-harness/README.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/scripts/dev-harness/README.md)
- [desktop/macos/agent/src/ARCHITECTURE.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/agent/src/ARCHITECTURE.md)
- [desktop/macos/docs/agent-coordinator.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/docs/agent-coordinator.md)
- [desktop/macos/Desktop/Sources/FloatingControlBar/ARCHITECTURE.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/Desktop/Sources/FloatingControlBar/ARCHITECTURE.md)
- [desktop/macos/docs/qualification-environment.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/docs/qualification-environment.md)
- [desktop/macos/docs/qualification-cleanup.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/docs/qualification-cleanup.md)
- [desktop/macos/docs/release-health-metrics.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/docs/release-health-metrics.md)
- [desktop/macos/e2e/CORE_E2E.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/e2e/CORE_E2E.md)
- [desktop/macos/e2e/feature-vector.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/e2e/feature-vector.md)
- [desktop/macos/e2e/harness.md](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/e2e/harness.md)

## Provenance and ownership

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/FORK.md).

### Fork provenance & rebrand checklist

#### Provenance

Snapshot (no history) of a subset of [BasedHardware/omi](https://github.com/BasedHardware/omi).

| | |
|---|---|
| Source commit | `99e0e60be67a4f727ddfab4858184d75da2494a5` |
| Source tag | `v0.12.147+12147-macos` |
| Snapshot date | 2026-07-30 |
| Upstream license | MIT |

This fork has not shipped an application build or public API contract and has
no existing product users. The upstream tag records code provenance only; it
does not create a released-client compatibility population for this product.

Upstream paths were preserved verbatim, so a future `git diff` against upstream at
this SHA is meaningful and cherry-picking upstream commits still applies cleanly.

#### What was included

| Path | Why |
|---|---|
| `desktop/macos/` | Native Swift 6 / SwiftUI app + bundled Node agent runtime |
| `desktop/windows/` | Electron + React + TS app (also builds mac/linux targets) |
| `backend/` | FastAPI + Firestore/Redis + direct managed providers, deployed through canonical Cloud Run workflows |
| `scripts/` | `dev-instance.sh` (sourced by `desktop/macos/run.sh`) and `dev-harness/` (local emulator stack) |
| `.github/` | CI + the desktop release chain |
| `config/`, `contract_tests/` | Build-contract JSON and backend parity fixtures |
| Root `Makefile`, `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `package.json` | Load-bearing: the harness hard-fails without the firebase trio; the Makefile is the only entry point to `dev-harness` |

#### What was excluded

`app/` (Flutter mobile), `web/`, `omi/` (firmware/hardware), `omiGlass/`, `plugins/`,
`sdks/`, `mcp/`, `docs/`, and root `Package.swift` (the iOS SDK).

Roughly 1.24 GB upstream to ~129 MB here.

Repository controls are narrowed to retained backend and desktop sources.
Absent-product workflows, manifest entries, and local routing branches are not
kept as dormant restoration scaffolding.

#### Running it

```bash
make dev-up          # Firebase Auth + Firestore emulators + local Redis
make dev-desktop     # the above, then launch the macOS app against it
```

The emulators replace Google, not the managed providers. For a hermetic local stack,
run `PROVIDER_MODE=offline make dev-up` without provider credentials. Real mode
uses Gemini for model compute, Modulate for speech-to-text, OpenAI for TTS only,
and Langfuse for tracing/prompt management. Their credentials belong in
`backend/.env.local-dev`; `make dev-init` creates that untracked file.

`desktop/macos/run.sh --yolo` skips the local backend and targets the owned
`knowledge-athlete-dev` Cloud Run URL recorded in [OWNER-PROVIDER-DECISIONS](codebase/operations/releases.md). Cloud Run
admits internet traffic so native clients can reach FastAPI; protected routes still require
the owned Firebase user's bearer token. The local emulator path remains the hermetic default.

Prerequisites: Xcode + an Apple signing identity, `brew install webp`, Node 22.x
(`>=22.19 <23`), pnpm, Python 3.11 + `uv`, JDK 21+ (the Firebase emulators need it),
ffmpeg, opus.

#### Rebrand checklist — before shipping your own build

The historical inventory later in this file records Omi identity that was baked into
the source. The build could succeed without changing those values, which is exactly
why each current successor or protected exception needs explicit ownership.

##### Owner-approved successor identity

The MVP stays in the existing `knowledge-athlete` repository. It does not require a
new GitHub organization or a new Google Cloud project. Provider login email addresses
and the current external-resource handoff are recorded in
[[OWNER-PROVIDER-DECISIONS](codebase/operations/releases.md)](codebase/operations/releases.md).

| Surface | Owned value |
|---|---|
| Visible product | `Intentive` |
| macOS application filename | `Intentive.app` |
| Shared technical slug | `heyintentive` |
| Public domain | `heyintentive.com` |
| Stable / Beta / canonical development bundles | `com.heyintentive.intentive`, `com.heyintentive.intentive.beta`, `com.heyintentive.intentive.dev` |
| Named development / preview prefixes | `com.heyintentive.intentive.dev.`, `com.heyintentive.intentive.preview.` |
| Google Cloud project | existing Firebase/GCP project `knowledge-athlete`; billing active, with a permanent-Free-Tier operating constraint |
| Development Cloud Run service | public-ingress `knowledge-athlete-dev` in `knowledge-athlete/us-west1`; protected routes enforce Firebase authentication and development desktop defaults target its discovered URL |
| Container repository | `knowledge-athlete/us-west1/intentive/backend`; the active development revision uses an owned immutable digest and no longer reads a cross-project recovery image |
| Firebase project | existing `knowledge-athlete` for owned development Auth and Firestore |
| Sentry | organization `heyintentive`, macOS project `desktop-macos` |
| PostHog | account `srujantriples@gmail.com`, organization `Intentive`, US project `Intentive Desktop` (`397035`); shared Codemagic Mac configuration is release-stamped and smoke-verified |
| Langfuse | owned US Cloud project `Intentive`; tracing and Prompt Management remain fail-open observability, not product-data authority |

`intentive.life` and `intuitive.life` are not product domains. They must not be
used for product URLs, support/privacy addresses, bundle identity, or public copy.

##### Current macOS safety boundary

- Stable, Beta, development, named-development, and preview bundle/scheme/storage
  identities are now typed under `com.heyintentive.intentive` / `heyintentive`.
- The checked-in Mac app has blank Sparkle feed, Sparkle public key, production API,
  public/legal, and manual-download release metadata. Production-family updates and
  routing fail closed until the signed provider supplies a complete owned configuration.
- The retained Mac backend update resolver and release manifests use
  `sruj75/knowledge-athlete` and Intentive asset names. Windows release ownership is
  intentionally unchanged because S-29 excludes Windows.
- The deny-all Firestore database and owned development Firebase app exist. The public-ingress
  `knowledge-athlete-dev` bootstrap service and free Upstash Redis are verified, including
  per-route Firebase rejection, Firebase-authenticated Firestore write/read, and Redis
  coordination. Development desktop defaults target it; it is not production authority.
- Sentry runtime ingestion and dSYM publication target owned organization
  `heyintentive`, project `desktop-macos`.
- PostHog product analytics targets the owned `Intentive Desktop` US project.
  The public client token and ingestion host are supplied only by ignored local
  configuration or protected Codemagic inputs. The release boundary verifies the
  token against the tracked owned-project fingerprint, and Stable/Beta resolve
  analytics only from signed bundle metadata; the inherited Omi token is neither
  embedded nor used as a fallback.
- The approved Intentive icon, mark, menu-bar art, sign-in backdrop, and DMG
  backgrounds are installed and their source/derivation is recorded in
  [ASSET-PROVENANCE](codebase/integrations/build-signing.md); caller-free inherited Omi brand assets were deleted.

##### Remaining release blockers

- The inherited provisioning profiles are evidence of upstream configuration, not
  shippable Intentive credentials. Owned profiles and Apple capability/provider
  identifiers must replace them; agents must never cosmetically edit inherited
  credentials.
- Apple Team `24D6NXS6H7` has an installed Developer ID Application identity valid
  through 2030-11-18; membership was confirmed on 2026-09-08 with renewal on
  2027-09-09. Codemagic still needs the supplied `.p12` password or an approved
  re-export of that identity, plus notarization credentials. The owner accepted
  the updated Program License Agreement; its account warning cleared on readback.
- Root `codemagic.yaml` owns Codemagic application `6a8ff0296fc70d39540cb56a` and workflows
  `intentive-macos-release` / `intentive-macos-preview`. The owned Firebase plists, PostHog
  client configuration, Sparkle keypair, and Sentry token are protected, and the four public
  website/legal URLs are stored. Apple signing and preview/release publication remain incomplete. The owned
  GitHub Release App is installed and verified, but Codemagic's publication token,
  trusted Intentive M1 runner, and production backend/feed remain unconfigured.
- The existing `heyintentive.com` landing page is hosted by Vercel project
  `intentive-tally-landing-page` from the same-named `sruj75` repository. Do not
  create a replacement site. Privacy, Terms, and Support subdomains are live over HTTPS;
  the apex/Tally page is unchanged. Download/preview destinations and `www` TLS remain outstanding.
- The approved Intentive app icon, mark, menu-bar art, sign-in backdrop, and DMG backgrounds
  are installed; visual-asset ownership is no longer a candidate blocker.
- The complete beginner-facing checklist and account map are tracked in
  [[OWNER-PROVIDER-DECISIONS](codebase/operations/releases.md)](codebase/operations/releases.md).

##### Signing & distribution

- macOS: Developer ID certificate + notarization. `desktop/macos/run.sh` already hard-errors
  without a signing identity; ad-hoc signing makes macOS reset TCC permissions on
  every build.
- Windows: the committed `electron-builder.config.mjs:101` is unsigned, while
  [excluded inherited Windows workflow](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/.github/workflows/desktop_windows_release.yml#L213) conditionally injects Azure
  Trusted Signing when all seven required secrets exist. Its fallback artifact
  is unsigned and triggers the "unknown publisher" warning.

##### Legal

MIT permits rebranding and commercial redistribution, but requires you keep the
copyright notice and license text (`LICENSE`). The license covers the *code* — it
does not grant rights to the "omi" name or logo, so the rename is not optional if
you are shipping this as your own product.

##### Current Firebase packaging boundary

S-30 removed the inherited committed production plist. Development packages the
owned `knowledge-athlete` registration, local harnesses use the synthetic
`demo-heyintentive-local` registration, and release builds inject an owned
protected plist or fail closed. Both local and release bundlers remove any nested
Firebase plist left in SwiftPM output.



## Security policy

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/SECURITY.md).

### Security Policy

Omi handles personal conversations, screen context, integrations, and account data. Please report security issues privately so maintainers can investigate and ship fixes before details are public.

#### Supported Versions

Security fixes are prioritized for:

- The latest `main` branch
- Current production releases of the Omi mobile, desktop, web, backend, firmware, and wearable software

Older releases may not receive separate fixes unless maintainers decide the risk warrants a backport.

#### Reporting a Vulnerability

Please do not open a public GitHub issue, public pull request, or Discord thread for an unpatched vulnerability.

Preferred reporting path:

1. Use GitHub's private vulnerability reporting flow from the repository Security tab, if available: https://github.com/BasedHardware/omi/security/advisories/new
2. If private vulnerability reporting is unavailable, contact the maintainers and ask for a private security channel before sharing exploit details.

Include as much of the following as possible:

- Affected component, endpoint, app, firmware, or commit
- Impact and who can be affected
- Reproduction steps or a minimal proof of concept
- Any relevant logs, request/response examples, screenshots, or traces
- Whether the issue affects production, local development, self-hosted deployments, or all environments
- Suggested fix or mitigation, if you have one

Maintainers aim to acknowledge valid reports within 3 business days and will follow up with triage questions, mitigation status, and disclosure timing when possible.

#### Scope

In scope examples:

- Broken authentication or authorization
- Cross-account data access or modification
- Exposure of conversations, memories, transcripts, recordings, screenshots, credentials, API keys, or integration secrets
- Remote code execution, command injection, SSRF, path traversal, or unsafe file handling
- Vulnerabilities in account OAuth, Firebase auth handling, retained tool execution, or payment webhooks
- Mobile, desktop, backend, firmware, web, and self-hosting security issues

Out of scope examples:

- Social engineering, phishing, or physical attacks
- Vulnerabilities that only affect unsupported versions or modified private forks
- Denial-of-service testing that degrades production service availability
- Spam, rate-limit bypass, or automation abuse without a demonstrated security impact
- Reports that require access to another user's account or data without permission
- Third-party service vulnerabilities that do not affect Omi's implementation

#### Safe Harbor

Good-faith security research is welcome when it follows this policy.

Please:

- Use your own accounts, devices, workspaces, and data whenever possible
- Stop testing and report immediately if you encounter another user's data
- Do not persist, copy, disclose, or modify data that is not yours
- Avoid disrupting Omi services, users, integrations, or infrastructure
- Give maintainers reasonable time to investigate and fix before public disclosure

If you are unsure whether a test is safe, ask maintainers privately before continuing.

#### Coordinated Disclosure

Public disclosure should wait until maintainers have confirmed a fix, mitigation, or disclosure plan. If a report is accepted, maintainers may credit the reporter in release notes, advisories, or pull requests unless the reporter asks to remain anonymous.


## Asset provenance

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/ASSET-PROVENANCE.md).

### Intentive desktop asset provenance

LIFECYCLE: permanent

This is the shipping-source record for current Intentive desktop identity assets. The project owner supplied and explicitly approved the canonical icon and moss-garden inputs plus an experimental Dock-material reference and the DMG composition reference during S-30 on 2026-09-03. This records that product-use approval; it does not assert a separate third-party licence beyond the repository's governing licence and provenance.

#### Owner-supplied sources

| Source | SHA-256 | Approved use |
|---|---|---|
| `intentive-icon.png` (1024 × 1024) | `8cd05bb91370e52aa99359ddda8b715309f63c260e58117a0dca03b3fbf3809a` | Canonical app icon and source geometry for monochrome product marks |
| `Moss garden.jpeg` (736 × 736) | `6748cc8817f39f249d93f66d12d61216460bb57036dbe41f6e06eba05a0546b4` | Sign-in and onboarding backdrop; preserve the complete square image |
| Grass-number reference (500 × 500) | `0ff053f66537d139f73ace51a797e1494e766de5a379d5dead932360e51e3cd8` | Evaluated for the Dock/app icon only; the experiment was rejected because the texture collapsed to flat green at Dock size and does not ship |
| Claude DMG reference screenshot (1304 × 762) | `401e05b7fb85ce3618c49cd9586fdc212d2ce4160179c299db22517718fc7161` | Visual composition reference for the warm drag-to-Applications installer |

The attachment paths are intentionally not committed; `.context/` is workspace-local. The hashes above let a maintainer match future source deliveries without making those paths part of the build.

#### Shipping derivatives

| Shipping asset | Source and transformation |
|---|---|
| `desktop/macos/Desktop/Sources/Resources/intentive_app_icon.png` | Exact owner-supplied black-and-white icon, uniformly scaled to an 824 × 824 tile and centered on a transparent 1024 × 1024 canvas. This preserves the original internal mark geometry while matching the standard macOS Dock footprint |
| `desktop/macos/intentive_icon.icns` | Standard 16, 32, 128, 256, 512 and Retina representations generated from the optically inset canonical icon with `sips` and `iconutil` |
| `desktop/macos/Desktop/Sources/Resources/intentive_mark.png` | Monochrome alpha template extracted from the canonical black head-and-asterisk geometry; no geometry was redrawn |
| `desktop/macos/Desktop/Sources/Resources/intentive_menu_bar_icon.png` | 88 × 88 Retina template derivative of `intentive_mark.png`; rendered by AppKit at 21 × 21 points, matching the owner-provided Intentive menu-bar reference |
| `desktop/macos/Desktop/Sources/Resources/intentive_signin_backdrop.png` | 4096 × 2304 composition. ImageGen extended only the left and right scene. The complete source square was then composited back, centered at full height, so no source content is cropped or repainted; blending occurs outside its bounds |
| `desktop/macos/Desktop/Sources/Resources/intentive_permission_01_privacy.png` through `intentive_permission_04_return.png` | Four 4:3 ImageGen tutorial illustrations. Frames 3 and 4 use the canonical icon pixels composited over generated mockups. Swift renders the exact captions and cycles the frames; the art contains no instructional copy dependency |
| `desktop/macos/Desktop/Sources/Resources/intentive_microphone_settings.png` | ImageGen permission-row illustration with the canonical icon composited over the generated mark |
| `desktop/macos/docs/oauth-callback-success-preview.png` | ImageGen adaptation of the former preview with exact Intentive return copy |
| `desktop/macos/dmg-assets/background.png` and `background@2x.png` | ImageGen-derived warm background and arrow from the approved DMG composition. Finder renders the live Intentive app icon, Applications alias and labels so the mounted installer does not contain doubled bitmap copies |

ImageGen generation record: `01a06210-7810-7000-9fd2-4b3e714ce05c`. Prompts required neutral/white Intentive styling, no purple or magenta, native macOS proportions, exact permission-step intent, and no extra logos or copy. The backdrop prompt additionally locked the square source and requested side-only scene continuation. A grass-material Dock experiment was assessed at real Dock size and deliberately rejected; the shipping app icon is the exact canonical black-and-white source with only a uniform standard-canvas inset. Menu bar, notch, and in-app brand marks likewise remain canonical monochrome assets.

#### Retired inherited assets

S-30 removed the caller-free inherited `OmiIcon.icns`, `AppIcon.icns`, permission GIFs, folder screenshot, Omi wordmark/notch/tray art, onboarding lineup, rope artwork, demo video, and unused DMG design options. Git history remains the recovery and provenance record for those deletions.


## Identity and legal handoff

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30-residue-ledger.md).



The S-30 execution originally recorded PostHog ownership and the next full
development deployment as open inputs. The dated reconciliation below preserves
that historical fact while separating it from current status.

##### Currently open

| Missing input / resource | Current safe repository behavior | Closure owner |
|---|---|---|
| Owned Figma file/page destination for any future onboarding sync | Destination-mutating local LaunchAgent scripts are absent. A manual GitHub workflow can still export and publish the repository onboarding bundle, including Figma's capture helper, but it does not select or mutate an external design file. | Product/design owner |
| Published `heyintentive.com` product/download/preview/Terms/Privacy/support destinations | Website/Terms entries are absent unless an owned HTTPS URL is injected; Privacy & Data remains local; Help Center is absent | Product/legal/release owner |
| Approved support/privacy contacts | No guessed `support@heyintentive.com` or `privacy@heyintentive.com` ships | Product/legal owner |
| Approved Terms/Privacy text and legal operator name | No invented company or affirmative legal promise ships | Legal/product owner |
| Production Cloud Run and public release endpoints | Production remains unconfigured/fail closed; development resource names remain accurate | Infrastructure/release owner with fresh authorization |
| Complete Codemagic Apple signing/notarization/preview secrets and trusted runner | Repository dry-run fixtures only; no signing/publication/promotion performed | Release owner with fresh authorization |

##### Resolved after the historical S-30 execution — 2026-09-04

| Former missing input / resource | Verified current status | Remaining boundary |
|---|---|---|
| Owned PostHog project ID/token | Owned `Intentive Desktop` project ID `397035` exists at `https://us.i.posthog.com`; its project token is stored outside Git in the Codemagic shared signing group and ignored local environment, and an ingestion probe was accepted and observed. | Final-SHA repository integration and telemetry qualification remain separate; no token value belongs in this ledger. |
| Next full development deploy with prepared Gemini/OpenAI/Modulate/Langfuse bindings | `knowledge-athlete-dev-0ea29f5-33868830964-1` serves 100% of development traffic from exact source SHA `0ea29f5c30cdf93ae3a76ac70f21d7a8bb148977`; the prepared Gemini v2, OpenAI TTS v1, Modulate v1, and Langfuse v1 bindings are present and their development checks passed. | S-31/BL-001 still requires its one-final-SHA physical/provider continuity evidence; this does not authorize production or publication. |



## Desktop testing guidance

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/desktop/macos/e2e/SKILL.md).

---
name: desktop-app-flows
description: "Understand and explore the Intentive desktop macOS app's UI flows, navigation patterns, and SwiftUI architecture. Use when developing features, fixing bugs, or verifying changes in desktop/ Swift files. Provides agent-swift commands to explore the live app, understand how screens connect, and verify your work."
allowed-tools: Bash, Read, Glob, Grep
---

### Intentive Desktop App — Flows & Exploration

This skill teaches you the Intentive desktop macOS app's navigation structure, screen architecture, and SwiftUI patterns. Use it when developing features (to understand how the app works), fixing bugs (to navigate to the affected screen), or verifying changes (to confirm your code works in the live app).

#### Fast-Path for Local Iteration (start here)

Two things make iterating on the desktop app slow: signing in (web OAuth) and clicking through the UI to reach a screen. Both are solved — use these before reaching for `agent-swift`.

##### 1. Start clean, or explicitly seed from owned Intentive Dev
Named bundles start clean by default. When feature iteration genuinely needs parity with the
owned canonical development profile, set `OMI_SEED_FROM_CANONICAL_DEV=1`; the app then migrates
the copied tokens into its own bundle-scoped Keychain item. Manual seed:
```bash
cd desktop/macos
./scripts/omi-auth-dump.sh com.heyintentive.intentive.dev   # owned canonical source only
./scripts/omi-auth-seed.sh com.heyintentive.intentive.dev.omi-myfeature \
  tmp/desktop-auth.json \
  "/Applications/omi-myfeature.app"                         # optional: Team ID for clearing stale Keychain
./scripts/omi-settings-seed.sh com.heyintentive.intentive.dev.omi-myfeature \
  com.heyintentive.intentive.dev                            # replay shortcuts/settings
```
The explicitly seeded bundle boots already signed-in and past onboarding with the owned canonical Intentive Dev settings. The captured Firebase idToken expires (~1h); re-run `omi-auth-dump.sh` after signing in again if backend calls start 401ing. **Scope:** this is for dev iteration only — when validating onboarding or auth themselves, use the real flow per Guard Conditions below.

##### 2. Jump straight to any screen (automation bridge)
The app runs a local HTTP control bridge (`DesktopAutomationBridge.swift`) that **auto-enables on every non-production bundle** (off on prod). `desktop/macos/scripts/omi-ctl` drives it — jump to a screen in ~150ms instead of clicking through the top nav bar:
```bash
./scripts/omi-ctl wait-ready                 # block until app reaches "main" state
./scripts/omi-ctl navigate rewind            # jump to the Rewind screen
./scripts/omi-ctl navigate settings rewind   # Settings page, Rewind sub-section
./scripts/omi-ctl state                       # read selected tab / auth / onboarding state as JSON
./scripts/omi-ctl screens                     # list valid targets
```
Disable with `OMI_DISABLE_LOCAL_AUTOMATION=1` to run a dev build "clean". Running several named bundles at once? Give each its own `OMI_AUTOMATION_PORT` (default 47777).

##### 2a. Desktop core E2E harness (tiered)
Primary entry for the desktop confidence ladder: `desktop/macos/scripts/desktop-core-harness.sh` (see [Desktop E2E](codebase/testing/desktop-e2e.md)).
```bash
./scripts/desktop-core-harness.sh --self-check   # Linux-safe T0 (flow lint + gauntlet hooks)
./scripts/desktop-core-harness.sh --tier 1 --bundle omi-core-e2e
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-core-e2e   # hermetic: dev-up offline + core matrix
```
Typed flows live in `desktop/macos/e2e/flows`; run individually with `scripts/omi-harness run <flow.yaml> --lane bridge`.

##### 2b. Run semantic actions (cursor-free, in-process)
Beyond navigation, the bridge exposes named **actions** that invoke the app's real
code paths directly — no synthetic mouse events, so they never grab the cursor (the
deterministic equivalent of the Flutter app's Marionette driver). Prefer these over
`agent-swift click`/coordinate clicking for anything they cover.
```bash
./scripts/omi-ctl actions                          # discover available actions + params
./scripts/omi-ctl action refresh_all_data          # same as Cmd+R
./scripts/omi-ctl action toggle_transcription enabled=false
```
`omi-ctl actions` returns descriptors with `category`, `surfaces`, `safety`,
`sideEffects`, `examples`, and `preferSemantic`. Scan those fields before using
`agent-swift`: prefer actions whose `surfaces` match the screen and whose
`safety` is `read_only`, `local_artifact`, or `local_ui_state` for routine checks.
Add new actions in `DesktopAutomationActionRegistry` (`registerBuiltins()` for global
ones, or `register(name:summary:params:handler:)` from a view model for screen-scoped
ones). `GET /actions` lists them; `POST /action {name, params}` runs one and returns
the resulting state snapshot.

For a background-agent/voice regression, use the read-only cross-surface probe after
the child run reaches a terminal state:
```bash
./scripts/omi-ctl action agent_lifecycle_convergence_snapshot runIds=<canonical-run-id>
```
It reports only run identity and state—not prompts or output—and passes only when the
canonical terminal run, visible pill, and producing journal completion have converged.
The continuity gauntlet uses this before it asserts the exact one-spawn/one-completion
journal receipt, so new PTT work should extend that contract rather than add UI sleeps.

##### 2b.1 Probe a current-screen PTT turn

`ptt_test_turn` is the non-production controller probe. It captures the same one pre-overlay
screen image used by a physical PTT press and drives the real hub turn. Its added screen-protocol
diagnostics expose only safe lifecycle state—never pixels, app names, or evidence IDs. Use it to
reproduce and diagnose a screen-answer stall without coordinate clicking:

```bash
cd desktop/macos
OMI_AUTOMATION_PORT=47920 bash ./scripts/ptt-screen-probe.sh
```

The probe emits only the safe state needed to diagnose its result. For a successful screen report,
expect `screen_evidence_last_completion=completed`, `screen_evidence_protocol_active=false`,
and `pending_tool_count=0`. A non-`completed` completion class identifies the local fail-closed
boundary; `terminal_reason=tool_timeout` is always a regression. This validates the controller
and capture/transport lifecycle.

For a regression in first-press admission, reconnect, or warm buffering, use the separate
manager-level probe. It drives `PushToTalkManager`'s actual route selection and injects a raw
PCM file through its capture callback equivalent; it intentionally does not perform the
controller-only auto-redrive or forced-text behavior:

```bash
cd desktop/macos
./scripts/omi-ctl action ptt_manager_turn pcm=/absolute/path/to/clip.pcm
./scripts/omi-ctl action ptt_turn_snapshot
```

Assert `injected_bytes` equals the clip length, then inspect only the typed diagnostics (admission,
route, pending deadlines, terminal reason). This is the first automated surface for the actual PTT
manager; use a natural authenticated physical PTT press as the final UX validation.

For the final physical Gemini-recovery proof, arm the one-turn transport fault on a **named
development bundle** immediately before pressing the real PTT shortcut:

```bash
cd desktop/macos
./scripts/omi-ctl action ptt_live_transport_fault operation=arm
### Physically hold PTT, speak naturally into the microphone, then release.
./scripts/omi-ctl action ptt_turn_snapshot
```

The action is rejected by Stable, Beta, canonical Intentive Dev, preview, and unknown bundles.
Synthetic `ptt_start` / `ptt_manager_turn` actions do not consume it. A physical press detaches
the active Gemini transport, keeps the real microphone capture alive through the existing bounded
warm wait, and then exercises buffered batch recovery. The fault restores automatically only when
that exact turn terminates. Before a physical press, `operation=clear` safely disarms it.

Accept capture evidence only when the terminal snapshot reports
`capture_origin=physical_microphone`, `captured_audio_bytes > 0`, and
`captured_audio_seconds > 0`. These are content-free capture-shape fields; no audio, transcript,
device name, or provider response is retained by the evidence recorder. Synthetic manager input
reports `capture_origin=automation`; DEBUG capture-driver tests report `capture_origin=test_fixture`.
Neither can close this physical-path row.

##### 2c. Inject backend faults (failure-path testing)
The hermetic E2E harness is backend-only, so desktop failure paths (backend 5xx →
structured `ChatErrorState` and transcription transport truthfulness) can't be driven
end-to-end. Tasks and goals are local-authoritative and are verified with the bridge flows
below instead of a fault server. `desktop/macos/scripts/omi-fault-inject.sh`
stands up a local endpoint that fails on purpose; point a **named test bundle** (never
prod) at it via the documented overrides — `OMI_PYTHON_API_URL` (canonical data plane),
`OMI_AUTH_API_URL` (the explicit OAuth callback seam):
```bash
cd desktop/macos
eval "$(./scripts/omi-fault-inject.sh start error)"      # modes: error | status:CODE | latency | reset | refuse
OMI_SKIP_BACKEND=1 OMI_SKIP_TUNNEL=1 \
  OMI_PYTHON_API_URL="$OMI_FAULT_URL" \
  OMI_APP_NAME="omi-fault" ./run.sh &
./scripts/omi-ctl wait-ready
./scripts/omi-ctl action ask query="hi"                  # exercise the path; assert a surfaced error, not a crash/silent no-op
./scripts/omi-fault-inject.sh stop
```
`status:CODE` returns an HTTP status code in 100-599 (e.g. `status:503`, `status:429`, `status:401`);
`latency` sleeps `--latency-ms` (default 30 000) before replying (watchdog/timeout paths);
`reset` RSTs the connection; `refuse` leaves the port closed (connection refused). Verify a
mode with `curl` before launching the app: `curl -s -o /dev/null -w '%{http_code}\n' "$(./scripts/omi-fault-inject.sh url)"`.

##### 2d. Hardening smoke (runtime regression tripwire)
`desktop/macos/scripts/omi-hardening-smoke.sh` re-runs the proven runtime probes behind hardened
acceptance rows so a behavior that regresses upstream is caught on the next run, not the
next manual audit. One-time setup — build and seed a dedicated named bundle:
```bash
cd desktop/macos
OMI_APP_NAME="omi-smoke" ./run.sh          # build + install /Applications/omi-smoke.app, then quit it
./scripts/omi-auth-dump.sh                 # capture the signed-in Intentive Dev session
./scripts/omi-auth-seed.sh com.heyintentive.intentive.dev.omi-smoke tmp/desktop-auth.json "/Applications/omi-smoke.app"
```
Then re-run any time (launches the installed bundle on an isolated port, ends with it stopped):
```bash
./scripts/omi-hardening-smoke.sh run                          # all probes, defaults: com.heyintentive.intentive.dev.omi-smoke, port 47797
./scripts/omi-hardening-smoke.sh run --only set-01,set-04     # subset
./scripts/omi-hardening-smoke.sh run --attach --port 47795    # against an already-running bundle (skips lifecycle probes)
./scripts/omi-hardening-smoke.sh scan <dir>                   # credential-pattern sweep of any evidence dir
```
Probes in canonical order (destructive last): `auth-06` prod tokens-at-rest (passive read) ·
`set-04` log credential hygiene · `set-01` settings navigation · `mic-06` rapid-PTT orphan
guard · `chat-03` agent-kill recovery · `auth-03` expired-token refresh (**relaunches** the
app) · `lnch-07` shutdown flush (**stops** the app) · `self-hygiene` report-dir scan.
Exit codes: `0` all PASS · `1` any FAIL (a regression — investigate) · `2` usage/prod-refusal ·
`3` BLOCKED only (harness couldn't run: port busy, stale auth seed, app missing). Reports +
`smoke-summary.json` land under `${TMPDIR}/heyintentive-hardening-smoke/<ts>/` unless `--report-dir` is
given. Safety: only exact `com.heyintentive.intentive.dev.omi-*` bundles are accepted; the sole production interaction is
the read-only `defaults read` in `auth-06`.

##### 2e. Stall the agent stream (chat watchdog testing)
The HTTP fault harness (§2c) can't stall the **agent** stream — that's a node/stdio
bridge, not HTTP. Two non-prod bridge actions freeze it so the chat stall path can be
exercised end-to-end (CHAT-02): a slow/stalled annotation at 8s/20s (`StallDetector`),
and ChatProvider's **180s send watchdog** which force-releases `isSending` and surfaces
"Response took too long. Try again." (recoverable — the next send works).

- `suspend_agent_stream` — SIGSTOP the agent process so it emits no events; `durationMs`
  (default `190000`, just past the 180s watchdog; capped at `300000`) auto-resumes it, so
  a forgotten resume can never wedge the agent.
- `resume_agent_stream` — SIGCONT immediately (early clear).

Both are non-production only (`AppBuild.isNonProduction`). Recipe (drive against a named
test bundle's automation port):
```bash
cd desktop/macos
### 1. start a chat turn so a send is in flight
./scripts/omi-ctl action ask query="write a long detailed answer" &
sleep 2
### 2. freeze the agent stream past the 180s watchdog
./scripts/omi-ctl action suspend_agent_stream durationMs=190000
### 3. within <=180s the send watchdog fires: assert the error + that sending is released
sleep 185
./scripts/omi-ctl action main_chat_snapshot | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]; print("error:", d.get("has_error"), d.get("error_message")); print("is_sending:", d.get("is_sending"))'
###   expect has_error=true / "Response took too long…" and is_sending=false (recoverable)
### 4. resume + prove recovery with a fresh turn
./scripts/omi-ctl action resume_agent_stream
./scripts/omi-ctl action ask query="are you back?"   # succeeds — not blocked by the stale send
```
`suspend_agent_stream` returns `{suspended:true, pid, durationMs}` (or an `error` if no
agent process is running / on a prod bundle).

##### 2f. Exercise local task authority through the bridge
The non-production task actions call the same `TasksViewModel`, `TasksStore`, and
`ActionItemStorage` paths as the UI. Their returned `local_<rowid>` identity means the
GRDB transaction committed; no task API or server requery participates:

```bash
cd desktop/macos
./scripts/omi-ctl action create_task description="bridge local task" priority=high
./scripts/omi-ctl action dump_tasks marker="bridge local task"
./scripts/omi-ctl action toggle_task description="bridge local task"
./scripts/omi-ctl action dump_tasks includeCompleted=true marker="bridge local task"
./scripts/omi-ctl action delete_task description="bridge local task"
```
Use `scripts/omi-harness run e2e/flows/tasks-crud.yaml --lane bridge` for the typed
version. `inject_requery_during_drag`, sync waits, and backend task fields are retired.

##### 2g. Inspect the feedback payload without submitting (SET-02)
`FeedbackView.submitFeedback()` always fires a real Sentry event and attaches the app log
plus a `desktop_diagnostics.json`, so there's no way to verify the payload is token-free
without spamming Sentry. `dump_feedback_payload_dryrun` (non-prod only) assembles the
**same** payload — the report title (`feedbackReportTitle`) and the diagnostics JSON
(`writeDiagnosticsAttachment`, the exact builder the real submit uses) — and returns it
**without** calling `SentrySDK`, so the diagnostics JSON can be secret-scanned.

```bash
cd desktop/macos
./scripts/omi-ctl action dump_feedback_payload_dryrun message="mic dropped mid-call" \
  | python3 -c 'import json,sys,re; d=json.load(sys.stdin)["result"]["detail"]; \
assert d["sentry_capture_invoked"]=="false" and d["would_submit_to_sentry"]=="false"; \
dj=d["diagnostics_json"]; \
pats=[r"eyJ[A-Za-z0-9_-]{10,}",r"AIza[0-9A-Za-z_-]{10,}",r"omi_(auto|mcp)_[0-9a-f]{8,}",r"AMf-[A-Za-z0-9_-]{10,}",r"[Bb]earer\s+\S{12,}",r"(?i)_API_KEY\s*[=:]\s*\S+"]; \
hits=[p for p in pats if re.search(p,dj)]; \
print("title:", d["sentry_message"]); print("secret hits:", hits or "NONE")'
```
Assert `sentry_capture_invoked=false`, `would_submit_to_sentry=false`, and **no secret
hits** in `diagnostics_json`. Empty `message` yields the "User Report (logs only)" title.
The action returns the log only as **metadata** (`log_attachment_filename`/`_exists`/`_bytes`) —
never its contents — so the bridge response itself can't leak the raw log. To confirm no
Sentry event fired, check the app log has no "User report submitted to Sentry" line.

##### 2h. Prove /state survives a wedged main thread (bridge responsiveness)
`GET /state` refreshes live UI fields on the MainActor. If the main thread is wedged
(e.g. a sign-in Keychain read blocking on `SecItemCopyMatching`), that hop used to hang
the whole bridge — `curl /state` timed out with 0 bytes. `liveAutomationSnapshot()` now
bounds the hop (`awaitWithTimeout`, 3s) and falls back to the last cached snapshot with
`snapshotStale=true`, so `/state` always answers. `debug_block_main_thread` (non-prod)
wedges the main thread on demand so this is testable:
```bash
cd desktop/macos
### wedge the main thread for 8s, then /state must still answer (stale) within ~3s
./scripts/omi-ctl action debug_block_main_thread durationMs=8000
./scripts/omi-ctl state | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]; print("stale:", d.get("snapshotStale"))'
###   expect snapshotStale=true during the wedge (cached fallback), false again once it clears
```
Typed flow: `scripts/omi-harness run e2e/flows/bridge-state-wedge-fallback.yaml --lane bridge`.
Hermetic ratchet for the timeout itself: `xcrun swift test --package-path Desktop --filter AwaitWithTimeoutTests`.

##### 2i. Prove Quit & Reopen relaunches the same bundle, session intact (PERM-06)
The permission "Quit & Reopen" flow (shown after granting Accessibility / Screen Recording)
calls `AppState.restartApp()` — relaunch the same bundle, keep the auth/onboarding session.
`quit_and_reopen` (non-prod) triggers that exact path (not the onboarding-mutating
`reset_onboarding`), delayed so the action's HTTP response flushes before the process
terminates. The relaunch waits for the old PID to exit before invoking `open <bundle>`;
on non-prod it uses `open -n` only after that handoff and re-passes
`--automation-port=<current port>` as an argv. The reopened app therefore **rebinds the
SAME port** you launched with (argv beats any launchd-inherited
`OMI_AUTOMATION_PORT`). Keep polling the original `OMI_AUTOMATION_PORT`; no rediscovery.

Two traps make a naive `wait-ready` lie, so the recipe below guards against both:
- **Wait for a *new* listener pid.** `quit_and_reopen` returns immediately and only
  schedules the restart ~`delay_ms` later; the pre-quit process is still alive and
  answering for ~1s. Poll until the pid *listening on the port* differs from the one
  you captured before, or you'll assert the OLD process's state (false PASS). Track the
  listener via `lsof -tiTCP:$PORT -sTCP:LISTEN`, not `pgrep` — a `pgrep -f` pattern also
  matches the shell running this recipe.
- **Poll with *fresh* `omi-ctl` calls.** The relaunch is a fresh process, so it mints a
  new bridge auth token and writes it to the same port-keyed token file. A single
  long-lived `omi-ctl` process caches the token from its first read, so it would keep
  presenting the *stale* token and 401 forever (false FAIL). Each `desktop/macos/scripts/omi-ctl`
  invocation is a fresh process that re-reads the token file — so loop over separate
  calls, don't reuse one `wait-ready`.
```bash
cd desktop/macos
export OMI_AUTOMATION_PORT=47894           # whatever port you launched the bundle with
BEFORE_PID=$(lsof -tiTCP:$OMI_AUTOMATION_PORT -sTCP:LISTEN 2>/dev/null | head -1)
./scripts/omi-ctl state | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]; print("before", d["bundleIdentifier"], d["isSignedIn"], d["hasCompletedOnboarding"])'
./scripts/omi-ctl action quit_and_reopen        # detail: {"restarting":"true", "bundle_id":…, "relaunch_path":…, "delay_ms":"400"}
### wait for the OLD listener to be replaced by a NEW one on the SAME port (fresh omi-ctl each try)
for i in $(seq 1 60); do
  PID=$(lsof -tiTCP:$OMI_AUTOMATION_PORT -sTCP:LISTEN 2>/dev/null | head -1)
  if [ -n "$PID" ] && [ "$PID" != "$BEFORE_PID" ] && ./scripts/omi-ctl state >/dev/null 2>&1; then break; fi
  sleep 1
done
./scripts/omi-ctl state | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]; print("after", d["bundleIdentifier"], d["isSignedIn"], d["hasCompletedOnboarding"], d["bridgePort"])'
###   assert: same bundleIdentifier, isSignedIn=true, hasCompletedOnboarding=true, bridgePort=47894 (session intact, SAME port)
### the reopened process's own argv carries the re-passed port (proves the fix):
###   ps -o command= -p "$(lsof -tiTCP:$OMI_AUTOMATION_PORT -sTCP:LISTEN | head -1)"  → …/Omi Computer --automation-port=47894
```
Hermetic ratchets: `xcrun swift test --package-path Desktop --filter QuitAndReopenActionTests`
and `--filter RestartRelaunchCommandTests` (non-prod relaunch re-passes the port as argv).

##### 2j. Prove the chat usage limiter is deterministic + dev-resettable (CHAT-05)
The free-tier monthly chat limiter (`FloatingBarUsageLimiter`, 30 messages/month) is
deterministic and dev-resettable. Driving it to the limit through real chat would burn
LLM calls, so two non-prod bridge actions expose the counter directly: `usage_limiter_snapshot`
(read `is_limit_reached` / `remaining_queries` / `limit_description`) and `reset_usage_limiter`
(reset the counter). No LLM spend. Note: `reset_usage_limiter` is the sign-out-style
`FloatingBarUsageLimiter.reset()` — it clears the cached quota **and** cached-plan state
(and its `UserDefaults` key) on the non-prod bundle; the next subscription poll repopulates
it. Assert on `is_limit_reached` (not `remaining_queries`, which reads `Int.max` when no
quota is loaded).
```bash
cd desktop/macos
./scripts/omi-ctl action usage_limiter_snapshot   # {"is_limit_reached":…, "remaining_queries":…, "limit_description":…}
./scripts/omi-ctl action reset_usage_limiter      # {"reset":"true","is_limit_reached":"false","remaining_queries":…}
./scripts/omi-ctl action usage_limiter_snapshot   # assert is_limit_reached=false after reset (dev-resettable proven)
```
Hermetic ratchets: `xcrun swift test --package-path Desktop --filter FloatingBarUsageLimiterTests`
(deterministic counter + `testResetClearsLimitReachedState`) and `--filter UsageLimiterActionTests`
(the non-prod actions wire to the limiter and the reset is prod-gated).

##### 2k. Prove task order is committed locally (TASK-05)
`reorder_task` commits the due-section mapping and numeric `sortOrder` through one local
GRDB transaction. Read the rows back immediately; there is no network flush or sync log.
```bash
cd desktop/macos
./scripts/omi-ctl action seed_tasks count=5 prefix=T05x      # note the returned ids
./scripts/omi-ctl action reorder_task id=<id1> index=0 category=nodeadline
./scripts/omi-ctl action reorder_task id=<id2> index=1 category=nodeadline
./scripts/omi-ctl action reorder_task id=<id3> index=2 category=nodeadline
./scripts/omi-ctl action dump_tasks limit=5000                 # assert final local order persisted
```
Hermetic ratchets: `--filter Task03ReorderStressTests` and
`--filter TasksSortOrderBandingTests`.

##### 2l. Prove post-wake restart paths without sleeping the machine (CHAT-07)
`simulate_system_wake` (non-prod) posts `NSWorkspace.didWakeNotification` on the
**workspace** notification center — the top of the real wake chain. Every production
consumer then fires exactly as on a physical wake: `RealtimeHubController` re-warms
(or defers) its session, and AppState re-broadcasts the default-center
`.systemDidWake` downstream. (Posting only `.systemDidWake` would silently miss
RealtimeHub, which observes the workspace center directly.) The stray-turn_end half
of CHAT-07 is the CHAT-02 suspend/resume path (a SIGSTOP'd agent across a "sleep" is
the same stale-subprocess class) — already runtime-proven; see §2e.
```bash
cd desktop/macos
OMI_LOG_PATH="$(./scripts/omi-ctl log-path)"
MARK="C07-$(date +%s)"; echo "$MARK" >> "$OMI_LOG_PATH"
./scripts/omi-ctl action simulate_system_wake     # {"posted":"NSWorkspace.didWakeNotification"}
sleep 2
awk "/$MARK/{f=1} f" "$OMI_LOG_PATH" | grep -E 'System woke from sleep|system_wake'
###   assert: "System woke from sleep" (AppState observer ran) AND a RealtimeHub system_wake line —
###   either "re-warming idle session" or "deferring system_wake ..." (defer while mid-turn). With no
###   warm session yet, requestSessionRefresh no-ops by design (guard session != nil); warm one first
###   with a ptt_test_burst if you need the re-warm line specifically.
```
Hermetic ratchet: `--filter HardeningSeamActionTests` (action posts the real top-of-chain
signal on the workspace center, non-prod gated).

##### The full loop
```bash
cd desktop/macos
OMI_APP_NAME="omi-myfeature" ./run.sh &                 # build + launch once
./scripts/omi-auth-seed.sh com.heyintentive.intentive.dev.omi-myfeature tmp/desktop-auth.json "/Applications/omi-myfeature.app"  # after install; relaunch to apply
./scripts/omi-settings-seed.sh com.heyintentive.intentive.dev.omi-myfeature com.heyintentive.intentive.dev
./scripts/omi-ctl wait-ready
./scripts/omi-ctl navigate memories                      # jump to the screen you changed
agent-swift connect --bundle-id com.heyintentive.intentive.dev.omi-myfeature
agent-swift snapshot -i --json
```
After a code change, an incremental `xcrun swift build` + relaunch is fast — the slow parts (login, navigation) are gone. For pure visual checks without launching at all, SwiftUI snapshot tests are an option, but most pages are entangled with `AppState.shared`/Firebase singletons, so the live-app bridge loop above is usually the better path.

#### How to Explore the App

You can interact with the running app via `agent-swift` — a CLI that clicks elements, reads the accessibility tree, and captures screenshots through the macOS Accessibility API. Works with any macOS app, no app-side instrumentation needed.

##### Setup
```bash
### App must be running via ./run.sh from desktop/macos/
agent-swift doctor                                   # check Accessibility permission
agent-swift connect --bundle-id com.heyintentive.intentive.dev  # connect to Intentive Dev
agent-swift snapshot -i --json                       # see what's on screen
```

##### Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `snapshot -i --json` | See all interactive elements with refs, types, labels | `agent-swift snapshot -i --json` |
| `click @ref` | CGEvent click — SwiftUI elements (NavigationLink, gestures) | `agent-swift click @e3` |
| `press @ref` | AXPress — AppKit buttons only | `agent-swift press @e5` |
| `find role/text/key VALUE` | Find element and chain action | `agent-swift find text "Settings" click` |
| `fill @ref "text"` | Type into text field | `agent-swift fill @e7 "search"` |
| `scroll down/up` | Scroll current view | `agent-swift scroll down` |
| `wait text "X"` | Wait for element to appear | `agent-swift wait text "Loading" --timeout 5000` |
| `is exists @ref` | Assert element exists (exit 0/1) | `agent-swift is exists @e3` |
| `get PROP @ref` | Read property value | `agent-swift get value @e5 --json` |
| `screenshot PATH` | Capture app window | `agent-swift screenshot /tmp/screen.png` |

Typed UI flows can use `ax.action` with `locator`, `value`, and
`action: click|press|fill|get`; `fill` and `get` also require `argument`. These
steps execute only in the `ui` lane and require `--bundle-id`.
`ax.expect.text_visible` uses targeted `wait text` queries; set `timeout_ms`
between 1 and 55,000 for a bounded long-running UI operation.

**Key rules:**
- `click` = CGEvent mouse click (SwiftUI). Use for top nav bar buttons, Settings section rows, NavigationLink.
- `press` = AXPress action (AppKit). Use for AppKit-style buttons only.
- Refs go stale after any mutation — always re-snapshot before the next interaction.
- `find` with chained action is more stable than hardcoded `@ref` numbers.
- `--json` flag on any command gives structured output for parsing.

#### App Navigation Architecture

##### Screen Map (v0.12.119+ redesign)
```
Main Window — Top Navigation Bar (use `click` for all nav buttons)
├── Home (DesktopHomeView.swift) — chat + insights + status banners
│   ├── Chat input area (embedded, no separate Chat tab)
│   ├── Insight cards (screen recording, tasks, observations)
│   └── Capture/Listening status (top-right)
├── Memory — 2 destinations
│   ├── Memories — search, lifecycle/category filters, memory list
│   ├── Conversations — Live section, search, category filters (All/Starred/Work/Personal/Social), conversation list
├── Tasks — one To Do/Done list, search, grouped deadlines, inline CRUD, details, and Undo
├── Insights — Insights and Focus segments
├── Rewind — retained View menu / Cmd+Option-R destination
│
├── Capture status button (top-right, red when blocked)
├── Listening status button (top-right, green when active)
└── Settings gear icon (⚙️ top-right) → opens Settings page
    └── Back button returns to previous tab

Settings (SettingsPage.swift) — use `click` for section rows
├── General — app preferences, startup behavior
├── Account & Plan — user info, sign out, delete account, subscription/plan, billing
├── Transcription — Language Mode (Auto-Detect / Single Language), Voice Assistant Languages, Custom Vocabulary
├── Floating Bar — show/hide, background style, draggable, typed questions, screen sharing, voice
├── Notifications & Privacy — local master/frequency, assistant notifications, and privacy controls
├── Rewind — storage info, excluded apps list
├── Shortcuts — Open Intentive shortcut, Push to Talk key, PTT microphone, locked mode, PTT sounds
├── Advanced — AI Setup (Ask Mode)
└── About — version info, Privacy & Data, retained links, software updates, update channel

Rewind overlay (View menu → Rewind or ⌘⌥R)
├── Search bar, date picker, settings gear, toggle
└── Permission gate: "Screen Recording Permission Required" with "Grant Permission" button

System Tray Menu (menu bar icon)
├── Screen Capture (toggle)
├── Audio Recording (toggle)
├── Open Intentive
├── Check for Updates...
├── [signed-in status]
└── Quit
```

##### Interaction Patterns

**Top navigation bar (v0.12.119+):**
- Buttons are `AXButton` type with text labels: `Home`, `Memory`, `Tasks`
- Use `agent-swift find text "Home" click` for reliable navigation
- Use `agent-swift find text "Memory" click` to switch tabs
- Settings: click the gear icon button (label `gearshape`) in top-right area
- Use `click` — these are SwiftUI Button views

**Settings section navigation:**
- Sections are `AXButton` type elements with section name labels
- Use `click` for navigation — these are SwiftUI views that respond to CGEvent clicks
- Section labels: General, Account & Plan, Transcription, Floating Bar, Notifications & Privacy, Rewind, Shortcuts, Advanced, About

**Memory destinations:**
- Two `AXButton` destinations within the Memory page: Memories and Conversations
- Use `click` to switch between sub-tabs

**Rewind access:**
- Not in top nav bar — access via View menu → Rewind (⌘⌥R)
- Or navigate to Settings → Rewind section
- Use `agent-swift press` on the View → Rewind menu item

**Transcription language mode:**
- Two radio-button-style options: "Auto-Detect (Multi-Language)" and "Single Language (Better Accuracy)"
- `click` on the text to switch modes
- Single Language mode shows a language picker (`popupbutton`)
- Click popupbutton → menu items appear as `menuitem` elements

**System tray menu:**
- Menu items accessible via the Intentive menu bar extra (unnamed `AXMenuBarItem`)
- Items: Screen Capture, Audio Recording, Open Intentive, Check for Updates, [auth status], Quit
- Access via `snapshot --json` (includes menu bar items)

#### Known Flows

Reference flows in `desktop/macos/e2e/flows/*.yaml` describe the app's key user journeys. Read these to understand navigation paths, expected elements, and UI state at each step.

| Flow | Covers | Steps | Notes |
|------|--------|-------|-------|
| `desktop/macos/e2e/flows/navigation.yaml` | Top nav bar, Home, Memory, Tasks, Settings | 7 | Core nav smoke — retained top nav buttons + gear icon + Rewind via View menu |
| `desktop/macos/e2e/flows/home.yaml` | Home tab, embedded chat, insights, status banners | 5 | Chat input, insight cards, Capture/Listening status |
| `desktop/macos/e2e/flows/memories.yaml` | Memory tab — Memories and Conversations | 6 | Destination switching, search, conversation list |
| `desktop/macos/e2e/flows/tasks.yaml` | Local Tasks UI — grouped To Do/Done, inline editing, recurrence, Undo | 6 | Manual retained UI and rejected-control absence |
| `desktop/macos/e2e/flows/tasks-crud.yaml` | Local task bridge CRUD | 8 | Hermetic stable local-ID create/read/complete/delete |
| `desktop/macos/e2e/flows/goals-dashboard.yaml` | Simple local goal and Dashboard projection | 5 | Hermetic local goal creation/readback |
| `desktop/macos/e2e/flows/settings-basic.yaml` | Settings — all 9 sections | 11 | General through About, verify each loads |
| `desktop/macos/e2e/flows/rewind.yaml` | Rewind overlay — View menu access, permission gate | 4 | ⌘⌥R shortcut, search, date picker, Grant Permission |
| `desktop/macos/e2e/flows/chat-hermetic.yaml` | Home chat with Rust `OMI_LLM_STUB=1` | 6 | Hermetic chat send/receive in Home tab |
| `desktop/macos/e2e/flows/language.yaml` | Settings → Transcription language config | 5 | Language mode toggle, voice assistant languages |
| `desktop/macos/e2e/flows/screen-recording-permission.yaml` | Rewind permission flow | 7 | Grant Permission button, Capture status |
| `desktop/macos/e2e/flows/audio-recording.yaml` | Audio capture, mic source, transcription | 7 | Start/Stop Recording, BT/mic selection |
| `desktop/macos/e2e/flows/ptt-output-recovery.yaml` | Streaming PTT playback | 3 | Manual output device recovery, responsive UI, Stop/new-turn fencing |
| `desktop/macos/e2e/flows/recording-finalization.yaml` | Recording lifecycle | 7 | Transcription storage, conversation detail |

When you modify a Swift file, check if any flow's `covers:` includes it. That flow describes the user journey your change affects.

##### Adding a New Flow
Create `desktop/macos/e2e/flows/<name>.yaml` in v2 format:
```yaml
version: 2
name: my-flow
description: What this flow covers
app: non-prod
covers:
  - desktop/Desktop/Sources/path/to/YourView.swift
preconditions:
  - auth_ready
steps:
  - id: S1
    name: Step description
    do: "Click the element (identifier: my_element). Verify the page loads."
    expect:
      interactive_count: { min: 5 }
      text_visible:
        - Expected Text
```
**Important:** Always use quoted strings for `do:` fields (not YAML `>` or `|`).

#### Verification & Evidence

After making changes, verify them in the live app:
1. Navigate to the affected screen using the commands above
2. Check that your changes appear (snapshot, screenshot)
3. Test interactions (click buttons, fill fields, scroll)
4. Capture evidence: `agent-swift screenshot /tmp/evidence.png`
5. Generate video: `ffmpeg -framerate 1 -pattern_type glob -i '/tmp/e2e-*.png' -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:-1:-1" -c:v libx264 -pix_fmt yuv420p /tmp/report.mp4`

#### Decision Tree

| Problem | Solution |
|---------|----------|
| Element not found | Re-snapshot, try scrolling, check if on wrong screen |
| Click doesn't navigate | All nav uses `click` in v0.12.119+. For menu items (View → Rewind), use `press` |
| Can't find Rewind | Rewind is not in top nav — use View menu (⌘⌥R) or Settings → Rewind |
| Can't find Chat | Chat is embedded in Home tab, not a separate nav item |
| Picker not responding | SwiftUI Picker `.menu` style may not expose as `popupbutton` — look for `button` with value label |
| App seems frozen | Check `agent-swift status --json`, re-connect, check `./scripts/omi-ctl log-path` |

#### Guard Conditions

**NEVER:**
- Kill or restart the production Omi app
- Enable the automation bridge or seed auth on any production-family bundle — both are gated to non-production builds; keep it that way
- Modify source code to make tests pass — report the failure instead

**When validating auth or onboarding themselves, or running flow-walker E2E:** drive the real flows — do NOT use the seeded-auth / `hasCompletedOnboarding` fast-path, which exists only for iterating on *other* screens. Use an owned named non-production bundle today. The owned Beta identity may be used only after S-29 supplies a signed, isolated candidate; never substitute an inherited Omi bundle.


## Billing activation handoff

Original record: [pinned source](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/dodo-integration.md).

### LIFECYCLE: permanent

### Dodo integration handoff

#### Current product state

The MVP remains free through all six implementation waves. `BILLING_MODE=disabled` is the required runtime state during that period. It returns no purchasable catalog, exposes no checkout or portal action, constructs no Dodo client, and makes no Dodo or Stripe request. The visible usage-limit action is **Skip**; it dismisses the presentation, grants no entitlement, and does not clear trial, quota, or fair-use state.

This disabled checkpoint is sufficient for Wave 3 repository dependencies. It is not final S-18 acceptance and it does not authorize test or live payment activity.

#### Behavior retained for later activation

The repository keeps the provider-neutral behavior needed for a paid release:

- server-owned bounded and unlimited offers and monthly/annual presentation;
- hosted checkout in the retained Mac web sheet;
- signed, idempotent, out-of-order-safe webhook projection;
- bounded post-checkout reconciliation;
- hosted customer portal for plan changes, payment methods, invoices, and cancellation;
- cancellation-at-period-end and access-end presentation;
- backend-authoritative subscription, quota, managed-access, and fair-use mapping;
- retry/failure recovery and account-deletion cancellation safety.

Activation must preserve these behaviors. It must not add a new onboarding paywall or make a redirect URL authoritative for entitlement.

#### Required external resources

Create test resources only after Wave 6 and explicit authorization:

- a Dodo test-mode account and API key supplied through `DODO_PAYMENTS_API_KEY`;
- a test-mode HTTPS webhook targeting `/v1/dodo/webhook` and its signing key supplied through `DODO_PAYMENTS_WEBHOOK_KEY`;
- test-mode subscription products for every approved bounded/unlimited interval;
- one normalized server-owned offer catalog supplied through `DODO_BILLING_CATALOG_JSON`;
- a reachable test backend, Firebase test principal, and disposable test customer;
- access to backend logs, fallback metrics, webhook receipts, subscription projection, quota, fair-use, and account-deletion evidence.

Test and live resources are separate. Dodo documents separate API hosts, products, keys, and webhooks for [test and live modes](https://docs.dodopayments.com/miscellaneous/test-mode-vs-live-mode). Never copy secret values into source, Markdown, logs, screenshots, test fixtures, commit messages, or PR bodies. Never commit real product IDs, customer/subscription IDs, or Stripe/Omi payment identifiers. Repository fixtures must remain obviously synthetic.

#### Post-Wave-6 test-mode acceptance

Use `BILLING_MODE=dodo_test` only in a bounded test environment, then collect evidence for this sequence:

1. Validate startup fails closed when the API key, webhook key, or catalog is missing or malformed.
2. Read `/v1/users/me/subscription` and confirm only the normalized server-owned test offers are presented.
3. Start `/v1/payments/checkout-session` from a selected opaque offer. Confirm the backend resolves the test product and the Mac opens the returned hosted checkout URL.
4. Complete one successful test checkout using Dodo's [test-mode payment process](https://docs.dodopayments.com/miscellaneous/testing-process). Confirm the redirect is presentation only.
5. Receive and verify the exact raw webhook body and Standard Webhooks headers. Confirm duplicate delivery is a no-op, an older event cannot overwrite newer state, and an invalid signature grants nothing. See Dodo's [webhook security guidance](https://docs.dodopayments.com/developer-resources/webhooks).
6. Confirm bounded reconciliation stops after its existing read budget, recognizes only the expected normalized offer, and refreshes subscription, quota, paywall, and fair-use state.
7. Open `/v1/payments/customer-portal`; verify invoices/payment methods and each supported plan change through Dodo's hosted [Customer Portal](https://docs.dodopayments.com/features/customer-portal).
8. Cancel at the next billing date. Confirm **Access ends** is accurate, access remains until that instant, and the terminal webhook removes paid access afterward.
9. Exercise quota denial, fair-use thresholds, renewal/payment failure, delayed/duplicate/out-of-order webhooks, provider timeouts, restart, and reconciliation recovery without creating a second entitlement owner.
10. Exercise account deletion for an active or possibly billable subscription. Irreversible identity deletion must wait until provider cancellation is confirmed and the durable deletion workflow completes.
11. Confirm the Mac's retained plan/usage screens, checkout Close/success/cancel handling, Refresh, portal return, and error states match the free-MVP behavior outside the newly active provider calls.
12. Record commands, timestamps, test resource names, redacted request/event IDs, screenshots, logs, metric queries, final subscription/quota state, and cleanup results. Remove the disposable customer and disable the test webhook when the run ends.

#### Separately authorized live activation

Live activation is a distinct release operation after test-mode acceptance. It requires explicit user authorization, verified business status, separately created live products/API key/webhook/signing key/catalog, a reviewed deployment diff, monitoring ownership, and a rollback window.

The first live proof is deliberately bounded: activate `BILLING_MODE=dodo_live` for the approved environment, perform one low-value transaction with an authorized test customer, verify the signed webhook and normalized entitlement/quota projection, open the portal, cancel, verify access-end behavior, and retain the provider receipt. Do not expand traffic or offers during this proof.

Rollback means restoring `BILLING_MODE=disabled`, removing purchasable catalog exposure, confirming checkout/portal routes return the typed disabled response without provider construction, retaining already-received webhook receipts for idempotency, and reconciling the bounded live test subscription before deleting any provider resource. A rollback never fabricates free or paid entitlement state.

#### Final evidence checklist

- [ ] All six waves are complete and the 714/714 requirements ledger passes.
- [ ] Dodo test credentials, webhook, products, and catalog were created outside the repository.
- [ ] Checkout, signed webhook, duplicate/stale ordering, and reconciliation passed in test mode.
- [ ] Portal, plan change, cancellation/access-end, quota/fair-use, and failure recovery passed.
- [ ] Active-subscription account deletion passed without orphaned billing.
- [ ] No credential, real product/customer/subscription ID, or Stripe/Omi payment identifier appears in git history or artifacts.
- [ ] Test resources and disposable customer data were cleaned up.
- [ ] Live activation received separate explicit authorization.
- [ ] One bounded live transaction and cancellation passed with monitoring and rollback evidence.
- [ ] S-18 was marked complete only after every preceding item passed.


## Accepted requirements

714 final decisions from the [pinned requirements record](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/requirements-challenge.md).
Detailed acceptance requirements and the PROV/INV/REL evidence boundaries are retained in the
[pinned per-decision acceptance matrix](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-31-acceptance-matrix.md).
REQ is now this decision register plus the pinned final Decision; REP uses the migrated wiki checks.
BE/MAC retain their component commands. PROV, INV and REL are not closed by documentation migration.
BILL remains disabled until its separately authorized handoff.


### Acceptance groups

Each decision below names its original owner/evidence group. The pinned owner records preserve dates and exact historical evidence. Current open obligations above supersede older availability observations.

| Group | Original owner records | Required evidence |
| --- | --- | --- |
| A1 | [S-01](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-01%20tdd.md), [S-04](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-04%20tdd.md), [S-05](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-05%20tdd.md), [S-06](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-06%20tdd.md), [S-25](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-25%20tdd.md), [S-26](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-26%20tdd.md) | REQ + REP + BE + MAC |
| A2 | [S-02](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-02%20tdd.md), [S-03](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-03%20tdd.md), [S-10](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-10%20tdd.md), [S-16](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-16%20tdd.md) | REQ + BE + MAC + PROV |
| A3 | [S-12](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-12%20tdd.md), [S-13](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-13%20tdd.md), [S-14](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-14%20tdd.md) | REQ + REP + MAC |
| A4 | [S-05](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-05%20tdd.md), [S-06](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-06%20tdd.md), [S-07](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-07%20tdd.md), [S-11](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-11%20tdd.md), [S-15](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-15%20tdd.md), [S-17](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-17%20tdd.md), [S-23](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-23%20tdd.md) | REQ + REP + MAC |
| A5 | [S-03](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-03%20tdd.md), [S-05](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-05%20tdd.md), [S-07](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-07%20tdd.md), [S-09](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-09%20tdd.md), [S-10](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-10%20tdd.md), [S-11](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-11%20tdd.md), [S-12](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-12%20tdd.md), [S-13](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-13%20tdd.md), [S-14](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-14%20tdd.md), [S-15](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-15%20tdd.md), [S-16](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-16%20tdd.md), [S-19](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-19%20tdd.md), [S-20](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-20%20tdd.md), [S-22](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-22%20tdd.md) | REQ + MAC + PROV |
| A6 | [S-08](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-08%20tdd.md), [S-10](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-10%20tdd.md), [S-17](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-17%20tdd.md), [S-23](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-23%20tdd.md), [S-25](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-25%20tdd.md) | REQ + BE + MAC + INV |
| A7 | [S-17](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-17%20tdd.md), [S-30](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30%20tdd.md) | REQ + REP + MAC |
| A8 | [S-08](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-08%20tdd.md), [S-09](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-09%20tdd.md), [S-18](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-18%20tdd.md), [S-30](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30%20tdd.md) | REQ + BE + MAC + BILL |
| A9 | [S-05](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-05%20tdd.md), [S-06](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-06%20tdd.md), [S-07](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-07%20tdd.md), [S-09](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-09%20tdd.md), [S-15](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-15%20tdd.md), [S-18](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-18%20tdd.md), [S-21](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-21%20tdd.md), [S-29](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-29%20tdd.md), [S-30](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30%20tdd.md) | REQ + REP + MAC + BILL + REL |
| A10 | [S-06](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-06%20tdd.md), [S-10](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-10%20tdd.md), [S-12](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-12%20tdd.md), [S-23](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-23%20tdd.md), [S-24](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-24%20tdd.md), [S-30](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30%20tdd.md) | REQ + BE + MAC |
| A11 | [S-02](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-02%20tdd.md), [S-03](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-03%20tdd.md), [S-10](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-10%20tdd.md), [S-16](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-16%20tdd.md), [S-23](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-23%20tdd.md), [S-24](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-24%20tdd.md) | REQ + BE + MAC + PROV |
| A12 | [S-11](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-11%20tdd.md), [S-12](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-12%20tdd.md), [S-13](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-13%20tdd.md), [S-14](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-14%20tdd.md), [S-21](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-21%20tdd.md), [S-30](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30%20tdd.md) | REQ + REP + MAC |
| A13 | [S-05](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-05%20tdd.md), [S-07](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-07%20tdd.md), [S-09](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-09%20tdd.md), [S-19](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-19%20tdd.md), [S-20](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-20%20tdd.md), [S-22](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-22%20tdd.md) | REQ + BE + MAC + PROV |
| A14 | [S-13](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-13%20tdd.md), [S-21](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-21%20tdd.md) | REQ + REP + MAC |
| A15 | [S-14](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-14%20tdd.md), [S-15](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-15%20tdd.md), [S-21](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-21%20tdd.md) | REQ + REP + MAC |
| A16 | [S-10](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-10%20tdd.md), [S-12](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-12%20tdd.md), [S-14](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-14%20tdd.md), [S-17](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-17%20tdd.md), [S-20](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-20%20tdd.md), [S-22](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-22%20tdd.md), [S-23](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-23%20tdd.md) | REQ + BE + MAC |
| A17 | [S-05](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-05%20tdd.md), [S-06](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-06%20tdd.md), [S-08](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-08%20tdd.md), [S-09](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-09%20tdd.md), [S-11](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-11%20tdd.md), [S-18](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-18%20tdd.md), [S-22](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-22%20tdd.md), [S-23](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-23%20tdd.md), [S-24](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-24%20tdd.md), [S-25](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-25%20tdd.md), [S-26](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-26%20tdd.md) | REQ + REP + BE + MAC + BILL |
| A18 | [S-03](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-03%20tdd.md), [S-08](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-08%20tdd.md), [S-09](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-09%20tdd.md), [S-18](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-18%20tdd.md), [S-20](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-20%20tdd.md), [S-22](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-3/s-22%20tdd.md), [S-25](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-4/s-25%20tdd.md), [S-26](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-26%20tdd.md), [S-27](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-27%20tdd.md) | REQ + REP + BE + INV |
| A19 | [S-04](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-04%20tdd.md), [S-29](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-29%20tdd.md), [S-30](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30%20tdd.md) | REQ + REP + MAC + REL |
| A20 | [S-02](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-02%20tdd.md), [S-15](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-15%20tdd.md), [S-16](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-16%20tdd.md) | REQ + MAC |
| A21 | [S-01](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-01%20tdd.md), [S-04](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-04%20tdd.md), [S-05](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-05%20tdd.md), [S-09](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-09%20tdd.md), [S-11](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-11%20tdd.md), [S-28](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-28%20tdd.md), [S-29](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-29%20tdd.md), [S-30](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-30%20tdd.md) | REQ + REP + MAC + REL |
| A22 | [S-06](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-06%20tdd.md), [S-13](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-2/s-13%20tdd.md) | REQ + REP + MAC |
| A23 | [S-04](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-04%20tdd.md), [S-29](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-29%20tdd.md) | REQ + MAC + REL |
| A24 | [S-04](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-04%20tdd.md), [S-29](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-5/s-29%20tdd.md) | REQ + REP + REL |
| A25 | [S-04](https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-1/s-04%20tdd.md) | REQ + REP + MAC |

### IR-001

Per-user cloud Agent VM and local-database mirroring.

`delete candidate`

Reason: the fork does not require remote/mobile agent execution or a continuously mirrored per-user GCE copy of the Mac's local data. This subsystem adds local polling, database upload, Firebase coupling, Firestore state, GCE lifecycle management, a Python VM runtime, a GKE proxy, deployment workflows, cleanup operations, and a large test/contract surface without serving normal desktop chat.

Acceptance group: A1.


### IR-002

SQL and semantic search boundary.

`keep local; delete VM copies`

Confirmed boundary:

- Delete Python `execute_sql`, `semantic_search`, and `get_daily_recap` with `backend/agent_vm/` and IR-001.
- Retain the normal desktop chat implementations in `ChatToolExecutor.swift`, the local Node bridge, and the generated local tool manifest.
- The retained local tools remain eligible for their own later requirement review; this decision only prevents the cloud-VM deletion from removing them accidentally.

Acceptance group: A1.


### IR-003

Kernel journal backend projection.

`delete backend projection; keep local journal`

Confirmed boundary:

- Keep `omi-agentd.sqlite3`, the local conversation journal, and the local turn projection used to render desktop chat.
- Delete Node's backend outbox, delete outbox, reconciliation state, retry pump, leases, acknowledgements, and `journal_backend_*` protocol messages.
- Delete the matching Swift bridge in `AgentRuntimeProcess`, `KernelJournalBackendSyncDriver`, and `APIClient+KernelJournal`.
- Delete legacy backend-message import into the local journal.
- Review backend-owned chat-session metadata separately before deleting `/v2/chat-sessions`; this confirmation covers turn-history projection, not every adjacent chat feature.

Acceptance group: A1.


### IR-004

Backend promotion of locally transcribed conversations.

`delete backend promotion; keep local GRDB authoritative`

Confirmed: local Parakeet transcripts become complete, visible local conversations without `/v1/conversations/from-segments`, a backend ID, Firestore persistence, or server hydration. The eventual deletion must change completion, query filters, identity, local mutations, and retry recovery atomically; deleting only the HTTP call is explicitly incomplete. Cloud-derived enrichment features are unresolved children, not reasons to retain synchronization.

Acceptance group: A1.


### IR-005

Local authority for retained personal-assistant product data.

`resolved by local-authority child decisions IR-024 through IR-038`

Confirmed: memories, tasks, goals, Focus results, Insights, proactive-assistant outputs, AI Profile state, and their retained settings use the Mac-local authorities selected by IR-024 through IR-038 and their detailed descendants. Delete backend synchronization, duplicate cloud authority, reconciliation, and projections for those personal product records unless a separately retained transient-compute boundary explicitly requires bounded input.

This umbrella adds no new feature and does not override any child's keep, adapt, delete, retention, owner-safety, or presentation decision.

Acceptance group: A1.


### IR-006

Firebase identity, subscriptions, and cloud-compute quota.

`keep account and billing scaffold; migrate Firebase project and payment provider`

Confirmed:

- retain Firebase authentication and `users/{uid}` as the account/entitlement boundary, configured against the new product's Firebase project rather than Omi's;
- retain subscription state, trials/plans as required by the eventual offer, cloud-compute quota/usage enforcement, paywall behavior, checkout/customer management, webhook-driven entitlement updates, and account deletion;
- replace Stripe-specific payment integration with Dodo Payments (`https://dodopayments.com/`) while preserving the existing product flow as the bootstrap scaffold;
- do not redesign identity, billing, or entitlements during the ruthless-deletion phase;
- continue deleting unrelated Omi cloud-data fields and APIs from the shared user document as their own product requirements are rejected;
- review exact plan names, limits, prices, and Dodo API mapping later because they are configuration/provider-migration details, not justification for retaining other Omi products.

Acceptance group: A1.


### IR-007

Managed subscriber access to realtime providers.

`resolved - keep managed PTT access as part of the paid product subscription. A normal subscriber authenticates with the product account, the backend checks entitlement and mints a short-lived OpenAI/Gemini credential, and the Mac connects directly to the provider. Do not require a personal provider account or API key. Usage accounting, audit storage, providers, fallbacks, and the rest of the PTT child graph remain separate decisions.`

Acceptance group: A1.


### IR-008

Retained Python backend and deployed supporting services.

`ADAPT - keep one canonical Python backend and narrow every supporting surface to its retained workloads`

Confirmed: the retained cloud speech portfolio is Mac-local Parakeet plus managed Modulate; IR-888 deletes the separately hosted GPU Parakeet service and IR-889 deletes both Deepgram branches. IR-890 keeps the safe Firestore index pattern only for surviving queries. IR-891 keeps the isolated local/offline development pattern while pruning it to the canonical backend, retained Firebase/Redis behavior, and retained provider fakes.

This closes the reopened parent without restoring any rejected cloud data, VM, worker, synchronization, integration, search, vector, GPU-STT or model path. The authoritative product-data boundary remains the Mac-local stores selected throughout this ledger, with the narrowed Python service handling only the explicitly retained account, billing, quota, managed-model, transient STT, update and operational workloads.

Acceptance group: A1.


### IR-009

Windows excluded from the macOS audit; unused shared Rust crate.

`ignore Windows completely; delete only the verified-unused shared Rust zombie`

Confirmed: do not inspect, question, modify, or delete `desktop/windows/**` or any Windows-only build, test, release, generated-client, documentation, or repository surface. Do not perform Windows cleanup as a consequence of macOS decisions.

Delete `desktop/shared-rust/**`, `desktop/Cargo.toml`, and `desktop/Cargo.lock` when implementation begins because that standalone workspace has no surviving consumer or behavior. This deletion does not touch the macOS Swift app, its local Node/Pi runtime, the Python backend, any retained Rust SDK elsewhere in the repository, or any Windows file.

Acceptance group: A1.


### IR-010

Release, update, telemetry, feedback, and support control planes.

`ADAPT - retain the Mac release, update, telemetry, feedback and support system under our ownership and delete impossible residue`

Confirmed: IR-892 adapts the Codemagic build/sign/notarize definition under our ownership; IR-893 retains deliberate candidate creation and dedicated M1 qualification under our identities; IR-894 retains backend Beta/Stable authority in our Firestore project; IR-895 retains the separately signed branch-preview pattern under our release identities; and IR-896 supplies the retained public links through one small external product/legal site plus GitHub release notes. IR-897 removes workflows, manifests and checks that exclusively require absent source trees while leaving Windows untouched.

This closes the reopened parent without undoing the prior Sparkle, Sentry, PostHog, LangSmith, diagnostics, issue-reporting, announcement, feedback or support decisions. It does not authorize a release, deployment, website publication or product-code deletion.

Acceptance group: A1.


### IR-011

Shared-backend copy of Rewind screen activity.

`delete candidate`

Confirmed: retain local Rewind and reject its Firestore/Pinecone/backend-agent/MCP copy. Deleting only the Swift uploader left the implementation untidy and made the backend contracts look supported despite having no current producer.

Acceptance group: A1.


### IR-012

Wearable BLE audio as a transcription input.

`delete BLE audio input`

Confirmed: retaining transcription capability does not require accepting audio from an Omi BLE wearable. Mac microphone/system-audio transcription is a separate branch and is not removed by this decision.

Acceptance group: A1.


### IR-013

Omi audio WAL and offline device-audio synchronization.

`delete`

Confirmed: the fork does not require raw wearable-frame durability or later device-storage recovery. Because the Omi device is also deleted, no supported producer remains for these WAL files. This removes the reason for the local Omi WAL subsystem, its upload request, and its asynchronous job-status polling while leaving ordinary `omi.db`/GRDB durability untouched.

Acceptance group: A1.


### IR-014

Direct wearable-device integration.

`delete candidate`

Confirmed: the Mac app will not directly connect to or manage wearable hardware. This closes the parent branch containing BLE audio, Omi WAL, device storage recovery, pairing, battery, buttons, and firmware state.

Acceptance group: A1.


### IR-015

Hosted/public MCP product closure audit.

`resolved - delete every hosted/public MCP endpoint, OAuth/API-key access surface, marketplace MCP client, first-party connector MCP configuration, and the unused omi-tools-stdio process/configuration. Preserve the separate private on-Mac managed-Pi path: pi-mono-extension exposes the retained typed manifest, OMI_BRIDGE_PIPE relays authorized calls locally, and Swift ChatToolExecutor executes them. This does not retain remote access, cloud data synchronization, another-device access, or another trusted program entrance. The optional Playwright/browser capability remains a separate requirement to review.`

Acceptance group: A1.


### IR-016

Dedicated `backend-sync` deployment for surviving background work.

`resolved - delete both backend-sync and backend-sync-backfill Cloud Run deployments`

Every workload has now been decided: wearable/offline sync and backfill are deleted under IR-013/014; live-listen conversation finalization is deleted under IR-020; cloud conversation-audio merge is deleted under IR-121; and durable account deletion is retained but its Cloud Task targets the main backend under IR-120. Remove both service deployments, service-specific IAM/configuration, deployment workflow branches, URLs, monitoring, and documentation. Keep only the surviving account-deletion queue and configure it against the main backend.

Acceptance group: A1.


### IR-017

System audio as a continuous-transcription input.

`keep`

Confirmed: audio produced by other Mac applications is a required transcription input. The Core Audio system-output capture path remains. Its meeting-detection, mode-selection, mixing, local/cloud STT, and storage children remain independent requirements to challenge.

Acceptance group: A2.


### IR-018

Automatic meeting-gated listening and conversation boundaries.

`keep`

Confirmed: meeting detection, meeting-gated microphone/system-audio capture, the grace-period transition, and automatic meeting-ended conversation finalization remain product requirements. Their UI, onboarding, task-context event, and tests remain in scope. Shared `ConferencingApps` callers remain separately auditable.

Acceptance group: A2.


### IR-019

Cloud `/v4/listen` as a second continuous-STT engine.

`keep both local and cloud continuous STT`

Confirmed: retain local Parakeet as the Apple Silicon default and retain `/v4/listen` for Intel Macs, local-model failure fallback, generic within-conversation diarization, provider routing, and dual-direction availability fallback. The Mac WebSocket client and live backend STT deployment family remain requirements. IR-020 later removes server conversation ownership from this transport, and IR-021 later removes persistent speech-profile identity. Locally transcribed conversations do not upload under IR-004.

Acceptance group: A2.


### IR-020

Durable server conversation ownership inside `/v4/listen`.

`retain transient cloud STT; delete server conversation ownership`

Confirmed: `/v4/listen` may perform cloud transcription and return live segment/speaker results, but the Mac owns conversation identity, boundaries, persistence, completion, and display in local GRDB. Remove Firestore live-conversation creation and transcript duplication, server lifecycle events, backend-ID binding, cloud reconciliation, and Mac-listen finalization jobs. Speech profiles and any non-Mac callers of shared finalization/playback infrastructure remain separate audits.

Acceptance group: A2.


### IR-021

Persistent cross-conversation voice identity.

`delete persistent voice recognition; keep generic diarization and local manual speaker labels`

Confirmed: remove cloud speech-profile audio, user/person voice embeddings, automatic identity matching, sample migration/recovery, and conversation-derived speaker-training workflows. Retain generic within-conversation speaker IDs from diarization. Users may manually replace those generic labels locally; manual correction must not upload audio, train an embedding, or require a backend conversation.

Acceptance group: A2.


### IR-022

Reusable people identities for manual speaker labels.

`keep conversation-local names; delete reusable people`

Confirmed: manually naming a diarized speaker applies a plain local name inside that conversation only. Do not retain `/v1/users/people`, server person IDs, reusable cross-conversation contacts, or the current create/select-person workflow. The eventual local transcript model must store the displayed name directly (or through a conversation-owned speaker-label mapping), support `You`, and apply a label only to the selected segment or matching speaker within that conversation.

Acceptance group: A2.


### IR-023

Cloud synchronization of transcription preferences.

`keep transcription preferences local; delete their backend synchronization and stored cloud copy`

Confirmed: the Mac owns transcription language, auto-detect mode, and custom vocabulary locally and sends the complete effective configuration with each retained cloud-STT request. Remove the Mac's GET/PATCH synchronization, remove `/v4/listen`'s Firestore dependency for these inputs, and delete the corresponding stored cloud transcription-preference fields after surviving callers are removed or migrated.

This does **not** authorize deleting the entire `users/{uid}` document or every server-side setting. `transcription_preferences` currently also contains `uses_custom_stt` telemetry, and the top-level `language` field is read by server conversation processing, memories, integrations, chat voice messages, and proactive/insight flows. Those are sibling requirements that must be reviewed before their shared cloud fields or APIs can be deleted. The offline wearable-sync readers are already inside the IR-013 deletion boundary.

Acceptance group: A2.


### IR-024

Cloud-authoritative memories.

`keep memories as a local product; delete backend memory synchronization and authority`

Confirmed: the Mac's GRDB `memories` table becomes the sole authority for memory content, identity, lifecycle/category, provenance, edits, deletion, read/dismissal state, search, and pagination. Remove normal Mac use of `/v3/memories`, Firestore memory copies, backend IDs/sync flags, upload/retry/reconciliation/pruning logic, and canonical memory maintenance jobs. Delete the memory-only cases in `backend/testing/contracts/test_desktop_backend_parity.py`, root `contract_tests/fixtures/memories.json`, and the corresponding `contracts` job/path triggers in the mixed `.github/workflows/desktop-backend-contracts.yml`; preserve its independent retained T0 self-check. Because S-12 removes the final file under `backend/testing/contracts/`, it also removes that prefix's `WORKFLOW_COVERED_PREFIXES` registration in `backend/scripts/check_unit_test_discovery.py` and updates the dedicated discovery-check tests in the same change. Local Memory, Insight, Focus, manual-create, chat, and proactive consumers remain, rewritten to finish and read locally. Hosted knowledge graph, MCP/public visibility, persona, imports, and cross-device memory projections lose their cloud source and are deletion candidates unless separately retained later. Account, entitlement, and billing data remain cloud-hosted under IR-006.

Acceptance group: A3.


### IR-025

Cloud-authoritative core tasks/action items.

`keep ordinary tasks locally; delete backend task synchronization and authority`

Confirmed: the Mac's GRDB `action_items` table becomes the sole authority for ordinary task identity, content, completion, deletion, dates, priority, tags, ordering, scores, recurrence, and metadata. Remove normal Mac use of `/v1/action-items`, Firestore action-item copies, backend IDs/sync flags, API paging/merge, server ID census, absent-row reconciliation, upload retries, rollback-on-remote-failure, full-sync flags, and server task migrations. Manual and retained local-agent/proactive producers finish locally. Sharing, staged suggestions/candidates, task intelligence, workstreams, and cross-device task access remain separate audits; IR-938 separately deletes external task integration/export.

Acceptance group: A3.


### IR-026

Cloud candidates, Suggested Tasks, and What Matters Now.

`delete the cloud candidate/task-intelligence/What Matters Now authority; retain the task-candidate review pattern locally under IR-032`

Confirmed: delete candidate and staged-task compatibility APIs, server candidate state and resolution, What Matters Now ranking/evaluation, context and open-loop snapshot uploads, intervention/feedback/outcome persistence, cloud retry outboxes, rollout-control machinery used only by this product, and associated backend/generated contracts. Keep ordinary local tasks and retained local producers. The existing task-candidate review behavior and Suggested UI are ported to local authority under IR-032; workstream candidates and What Matters Now remain deleted.

Acceptance group: A3.


### IR-027

Explicit goal tracking and goal-aware assistance.

`keep one simple local Goals feature; delete both cloud goal systems and synchronization`

Confirmed: retain one local goal model with a stable local identity, title, optional description, and active/completed status. Normal desktop chat may read active goals from the local database. Remove Firestore goal authority and normal Mac goal API calls; `backendId`/`backendSynced` and reconciliation; numeric/scale targets and progress history; AI goal generation, advice, and chat progress extraction; automatic stale-goal retirement; canonical focused/background/achieved/abandoned lifecycle; account-generation/idempotency machinery; and goal relationships to cloud tasks and workstreams. Rewrite onboarding and the surviving goal UI to create and finish locally. Whether onboarding must require a goal can be challenged later as an onboarding-flow question, without changing the retained local goal capability.

Acceptance group: A3.


### IR-028

Backend workstreams and task-attached agent chat.

`delete task-attached agent work and the complete cloud workstream product`

Confirmed: delete “Work on this with Omi,” task sidebar chat, the task-row “Execute”/background-investigation path, task-to-workstream IDs and state, goal-origin threads, work-intent resolution, workstream detail/events/artifacts/checkpoints, continuity preparation/persistence/delivery, workflow-control coupling, their UI/settings/tests/generated contracts, and the backend Firestore workstream stores and routes. Keep normal desktop chat and allow it to read or act on local tasks through separately retained local tools. A future task-specific conversation must be designed as a local feature rather than preserving this architecture.

Acceptance group: A3.


### IR-029

Focus history and statistics page.

`keep a simple local Focus page`

Confirmed: use local GRDB as the sole record authority and retain the current AI status, analysis-delay/cooldown visibility, today's focused time, today's distracted time, and a short recent-judgment list. Delete the 30-day/all-time browsing mode, text search, top-distraction analytics, duplicate UserDefaults record cache, backend-derived IDs/sync behavior, and broader history-management complexity. Retention length and deletion controls can be set during implementation, but must stay small and local.

Acceptance group: A3.


### IR-030

AI screen-activity focus coach.

`keep Gemini focus analysis with local-only results; delete cloud focus persistence`

Confirmed: retain screen-context selection, transient Gemini screenshot/context analysis, focused/distracted classification, delay/cooldown policy, exclusions, live notification/glow behavior, and the minimum recent local state needed by the classifier. Store any durable classification records only in local GRDB. Remove the second write into local memories, backend memory upload, backend IDs/sync flags and retry/delete behavior, and the unused legacy `/v1/focus-sessions` and `/v1/focus-stats` routes/database. The dedicated Focus history/statistics product remains a separate decision under IR-029.

Acceptance group: A3.


### IR-031

Automatic task extraction from screen activity.

`keep automatic Gemini task extraction and adapt accepted task creation to the local task authority`

Confirmed: retain allowed-app/window selection, context-switch and messaging triggers, Gemini extraction, confidence/ownership policy, local task/goal context, local duplicate detection, and source/evidence metadata. Replace hidden cloud-delivery outbox, workflow-control lookup, backend candidate/staged-task creation, promotion, and server-to-local copying with an idempotent local write into `action_items` for policy-approved captures. Do not reduce retained behavior merely because it was previously cloud-backed. The handling of ambiguous captures, proposed updates/completions, and refinements is now the explicit IR-032 child decision.

Acceptance group: A3.


### IR-032

Local review of uncertain automatic task detections.

`port the existing task-candidate review pattern to local authority`

Confirmed: preserve the battle-tested task-candidate domain behavior rather than designing a new queue. Local persistence must retain task proposals for create, update, complete, cancel, and supersede; pending/accepted/rejected/expired lifecycle; evidence and confidence; semantic deduplication; idempotent resolution; account-owner isolation; Later/suppression; Edit; and safe application to local `action_items` in a transaction. Reuse/adapt the existing Suggested UI and policy code where possible. Remove HTTP delivery, Firestore, account-generation/rollout coordination, server feedback/outcome attribution, and cloud retry outboxes. Workstream candidates stay deleted under IR-028, and What Matters Now stays deleted under IR-026.

Acceptance group: A3.


### IR-033

Automatic memory extraction from screen activity.

`keep automatic screenshot-to-Memory extraction; remove only unnecessary synchronization`

Confirmed: preserve the existing Gemini extraction prompt and cadence, exclusions, confidence threshold, conservative one-memory limit, source/screenshot/context provenance, owner isolation, local deduplication, local Memory UI lifecycle, notifications, and tested persistence failure behavior. Make the successful local GRDB transaction the durability terminal. Remove `/v3/memories` creation from this path, backend IDs/sync flags, `markSynced`, remote receipts, remote retry/error classifications, and sync-specific deletion/reconciliation. Rewrite the durability abstraction and its tests around local persistence rather than bypassing it or leaving a fake sync stage.

Acceptance group: A3.


### IR-034

Periodic proactive investigation and advice.

`keep the existing advisor behavior; make generated insights local-authoritative`

Confirmed: preserve the two-phase recent-activity investigation, local SQL tool use, selected-screenshot Gemini verification, conservative prompt, interval, confidence threshold, exclusions, deduplication, owner isolation, notification delivery, and the user-facing Insights lifecycle. Keep the dedicated Insights page and its existing read, dismiss, delete, filter, search, and history behavior, but have it read and mutate the tagged insight records in local GRDB as the sole authority.

Remove `/v3/memories` creation for generated insights, backend IDs/sync flags, `markSynced`, backend refresh/read/dismiss/delete calls, remote retry/reconciliation, and the duplicate `StoredInsight` array encoded into UserDefaults. A successful GRDB transaction is the durability terminal. Sending selected screenshot/context data to Gemini remains transient hosted compute, not cloud data synchronization. Cloud synchronization of the assistant's prompt, cadence, threshold, exclusions, and notification settings remains a separate settings audit.

Acceptance group: A3.


### IR-035

Event-driven grounded Live Suggestions.

`keep the existing Live Suggestions behavior`

Confirmed: retain the context-switch trigger, dwell and cooldown gates, daily evaluation budget, local task/memory/Rewind grounding, current-screen Gemini judgment, confidence and deduplication policy, floating suggestion card, notification throttling/snooze behavior, click-to-chat continuation, owner isolation, local kernel-journal admission, bounded shape-only telemetry, settings, and focused tests. This is retained as its own timely proactive behavior alongside the deeper periodic Insight Assistant.

Do not invent a Firestore suggestion record or backend synchronization lifecycle: none exists in this path. The current screenshot and selected local grounding still travel transiently through the authenticated Gemini proxy for compute. Task-candidate Suggested, Home ask-bar prompts, and generic notification/chat continuity remain separate products and are not collapsed into Live Suggestions.

Acceptance group: A3.


### IR-036

Cloud synchronization of proactive-assistant settings.

`make proactive-assistant settings Mac-local and delete their cloud synchronization`

Confirmed: retain every surviving local assistant setting, its Settings UI, defaults/migrations, runtime change notifications, and UserDefaults persistence. Remove server pull/push behavior for shared, Focus, Task, Insight, Memory, and legacy floating-bar assistant sections; Firestore `assistant_settings` storage and deep-merge ownership; startup/sign-in refreshes that overwrite local values; partial-update calls from the UI; and focused synchronization contracts once released-client compatibility is handled.

Do not delete or implicitly localize the Stable/Beta `update_channel` or the separate global notification enablement/frequency fields under this decision. They remain sibling audits. Live Suggestions is already local-configured and continues unchanged under IR-035.

Acceptance group: A3.


### IR-037

Cloud synchronization of the global proactive-notification controls.

`keep the global notification controls locally and delete their cloud synchronization`

Confirmed: retain the master proactive-notification switch, the exact 0-5 frequency levels and throttling intervals, local migrations/defaults, Settings UI, synchronous UserDefaults delivery gate, snooze behavior, per-assistant switches, owner isolation, card queueing, and notification-to-local-chat continuity. Remove the Mac GET/PATCH calls, Firestore `notifications_enabled` and `notification_frequency` authority, Settings hydration that overwrites local values, the migration's backend push, and focused API/automation contracts once released-client compatibility is handled.

macOS notification authorization, functional notices that bypass proactive throttling, and the separate server mentor-notification product are not deleted by this decision.

Acceptance group: A3.


### IR-038

Daily AI-generated user profile for local personalization.

`keep the existing AI User Profile behavior with local inputs and local authority`

Confirmed: retain the factual profile prompt, daily generation check, two-stage Gemini synthesis and consolidation with prior profiles, local `ai_user_profiles` history, Settings view/edit/regenerate/delete behavior, onboarding and file-exploration additions, owner isolation, and injection into normal chat, Focus, Task extraction/prioritization, and periodic Insights.

Replace backend memory/task/goal/conversation/message fetches with reads from their approved local authorities. Make the successful local GRDB transaction the terminal. Remove `backendSynced`, `/v1/users/ai-profile` upload and retrieval, the Firestore `ai_user_profile` field and cache, remote MCP profile projection, and sync-specific tests/contracts after released-client compatibility is handled. Gemini remains transient hosted synthesis compute.

Acceptance group: A3.


### IR-039

Scheduled cloud Daily Summary product.

`delete Daily Summary for the first Mac release`

Confirmed: remove the Mac Daily Summary Settings card, search entries, view state, GET/PATCH methods/models, generated bindings, and focused settings/routing tests. Remove summary-specific Firestore user settings and collections; hourly selection/generation and Redis idempotency locks; LLM prompts/models/usage tracking; summary CRUD, regeneration, sharing and public lookup; FCM deep-link delivery; webhook payloads; cloud-chat settings tool; route registrations/contracts; and focused backend tests once released-client compatibility is handled.

Do not remove the retained periodic Insight Assistant, simple local Focus page, local AI User Profile, local proactive notification service, or unrelated functional notifications. A future Daily Summary would be a separately approved local Mac feature that may reuse the inherited schema and prompt as a blueprint; it is not part of the first release.

Acceptance group: A4.


### IR-040

Backend-owned multiple-chat session catalog.

`keep the complete multiple-chat behavior with local metadata authority`

Confirmed: retain separate normal-chat threads; new-thread creation; stable owner-scoped identities; sidebar listing and date grouping; selection; recent preview and message count; last-activity ordering; user rename; starring and starred filtering; deletion/clear behavior; drafts per thread; and the existing local turn journals and execution continuity behind each thread.

Adapt the current `ChatSession` semantics and sidebar to the existing local Node kernel rather than inventing an unrelated store. Create/list/update/delete sessions locally, derive preview/count/activity from the authoritative local journal, and persist the remaining sidebar metadata locally. Remove normal Mac GET/POST/PATCH/DELETE use of `/v2/chat-sessions`, Firestore `chat_sessions` authority, cross-device session reconciliation, server IDs, legacy backend-session alias import after its compatibility window, and session-specific backend/generated contracts once released-client compatibility is handled.

The automatic initial greeting, automatic title generation compute, message ratings, cloud attachment uploads, and app/persona-specific session behavior remain explicit child audits. They are not deleted or retained merely by localizing the session catalog.

Acceptance group: A4.


### IR-041

Backend-generated greeting in every new chat thread.

`keep the personalized greeting behavior with local authority`

Confirmed: a newly created ordinary chat still receives the short personalized assistant greeting before the user sends a message. Preserve the existing normal greeting behavior and, for any retained persona chat, the existing persona-specific opener behavior.

Adapt the producer and storage boundary rather than deleting the experience:

```text
create local chat session
  -> read the approved local AI Profile and local memories needed by the prompt
  -> invoke retained model compute transiently
  -> create the assistant message directly in the local kernel journal
  -> derive the local session preview and message count from that journal turn
```

“Local” here means local data authority, not necessarily on-device inference. A retained hosted model may compute the greeting, but it must not require a Firestore session, fetch cloud memories, or leave a backend chat-message copy.

Delete the Mac dependency on `POST /v2/chat/initial-message`, the endpoint's Firestore session verification, backend previous-message lookup, backend prompt-memory lookup, Firestore message/session writes, and the remote-turn import route used only to copy the greeting back into the local journal. Reuse the existing greeting prompts and product behavior in the new local-authoritative path instead of redesigning their personality.

The greeting remains non-fatal: a generation failure leaves the existing welcome state and composer usable. Its accepted local journal turn owns preview/count/continuity. Billing/accounting follows whichever retained transient model lane performs the call.

This decision does not settle whether the separate title-generation call survives.

Acceptance group: A4.


### IR-042

AI-generated title after the first chat exchange.

`keep automatic titles with local authority`

Confirmed: preserve the current behavior that generates a short descriptive title after the first real user/assistant exchange. Read title input from the authoritative local journal, reuse the existing max-six-word prompt and trigger, invoke retained model compute transiently, and persist the returned title in the local session catalog.

Delete the normal Mac dependency on `POST /v2/chat/generate-title`, the backend's Firestore session update, and any assumption that a product-backend session row exists. A failed title generation remains non-fatal and leaves the local default title in place. Manual rename continues to override the local title.

Acceptance group: A4.


### IR-043

Assistant-message thumbs-up/down ratings.

`delete message ratings for the first release`

Confirmed: remove assistant thumbs-up/down controls from normal and floating chat, their in-memory rating state and submission path, `PATCH /v2/desktop/messages/{message_id}/rating`, Firestore message-rating writes, the separate rating analytics document, the dependent PostHog event, and the Chat Lab reader that fetches backend messages to build cloud rating history. Preserve unrelated message actions such as copy and information/details.

Do not add local journal rating metadata merely to preserve unused UI. Feedback can return later only when it has a named consumer and an explicit decision about whether any prompt/answer context may leave the Mac.

Acceptance group: A4.


### IR-044

Chat file attachments and cloud upload.

`keep attachment behavior with an app-managed local store`

Confirmed: retain the existing user-facing ability to select, paste, or drag supported files and screenshots into chat, keep the current attachment chips/cards and four-file limit, pass managed local URIs and relevant image bytes through the retained local agent path, and restore attachment cards from the local journal.

Before journal admission, copy a disk-backed file—or materialize an in-memory pasted screenshot—into an owner/session-scoped app-managed attachment directory. Persist the managed local URI, name, MIME type, and presentation state. Render image previews locally. Chat deletion and storage cleanup must garbage-collect only unreferenced managed attachment files; they must not touch the user's original source file.

Delete the automatic upload wait, `POST /v2/files`, OpenAI Files uploads, Firestore file records, public GCS chat thumbnails, cloud file identifiers and resolution, and their cloud cleanup path. The retained model lane may still receive attachment bytes or extracted content when the user asks it to inspect the file; this decision removes durable cloud file storage, not necessary transient model input.

Acceptance group: A4.


### IR-045

Cloud apps and persona-specific chat.

`delete cloud app/persona selection from first-release Chat`

Confirmed: ship one primary assistant personalized by the retained local AI Profile and local memories. Remove the Chat assistant picker, selected marketplace identity/avatar/name behavior, app-specific normal-chat draft and session partitioning, app IDs from the normal local chat lifecycle, app/persona greeting forks, and the startup fetch performed only to populate chat-capable apps.

Do not copy cloud persona definitions into a local catalog or add persona prompt injection for the first release. This does not delete the local AI Profile, the primary assistant's prompt, or first-party behaviors already retained elsewhere. It also does not yet decide the parent Apps marketplace page and third-party integration platform; those move to IR-046.

Acceptance group: A4.


### IR-046

Cloud Apps marketplace and third-party platform.

`delete the cloud marketplace, developer platform, and marketplace-specific billing`

Confirmed: remove the complete cloud app catalog and installed-app lifecycle; marketplace search/categories/capabilities; app detail, enable/disable, reviews and ratings; app/persona creation and moderation; developer/tester/API-key surfaces; OAuth integrations, webhooks, notification apps, conversation reprocessing and third-party user-data APIs; MCP app manifests; marketplace assets/caches/usage history; and paid-app products, Payment Links, per-app entitlements/subscriptions, Stripe Connect creator onboarding and payouts.

Remove the paid-app branch from the currently shared Stripe webhook and payment utilities without deleting the separate product-account subscription behavior retained in IR-006. That surviving product billing scaffold will be migrated from Stripe to Dodo; marketplace billing must not be ported.

Together with IR-047, no Apps-screen content survives. Delete its page, provider, startup fetching, navigation/menu entries, dashboard popup, loading state, automation targets, and marketplace/connector-specific tests and generated contracts once callers are removed.

Acceptance group: A4.


### IR-047

First-party import and memory-export connectors.

`delete all first-party connectors`

Confirmed by user direction: remove the entire Imports and Exports product rather than audit and retain individual connectors. This includes their cards/sheets, connection status stores, sync/import/export services, OAuth and hosted-MCP setup, local CLI/config writers and detectors used only for connection setup, connector automation commands, telemetry, onboarding requirements, Home shortcuts/status cards, and tests/contracts specific to these flows.

After IR-046 is also confirmed for deletion, the Apps screen, its search/filter/create chrome, sidebar/menu navigation, loading state, and dashboard popup have no surviving role and should be deleted rather than renamed into an empty shell.

Deleting connectors does not delete the locally authoritative Memories feature, local manual memory creation, screen-to-memory extraction, local memory use in Chat, or the local agent runtime itself.

Acceptance group: A4.


### IR-048

Local Playwright browser control.

`resolved - delete Playwright browser control from the first release: the Playwright MCP child/server and package wiring, browser-extension detection and token storage, BrowserExtensionSetup, related settings and Chat failure/setup lifecycle, browser-specific prompts/floating-bar behavior, tests, and the browser-control parts of proactive execution. Preserve the scoped local product tools through managed Pi's separate pi-mono-extension -> OMI_BRIDGE_PIPE -> ChatToolExecutor route; IR-015/S-05 deletes the unused omi-tools-stdio process.`

Acceptance group: A4.


### IR-049

Broad local computer-agent execution.

`resolved - delete general shell commands, arbitrary filesystem read/write/edit access, and agent-controlled native-app clicking/typing from the first release. Remove the broad computer-agent prompts, built-in execution exposure, related Ask/Act claims and controls where they no longer describe a surviving distinction, audit/denylist/approval surfaces that exist only for broad execution, and proactive/task execution hooks already rejected by IR-028. Keep scoped typed local product tools, explicit chat attachments, and read-only Accessibility consumers pending their own audit.`

Acceptance group: A4.


### IR-050

Apple Events Automation permission.

`resolved - delete Apple Events Automation permission from the first release. Remove its onboarding step, startup/status probes and AppState, Chat permission-tool exposure, Settings/sidebar state, System Events request code, NSAppleEventsUsageDescription, prompts/docs/tests, and rejected action callers. Replace the microphone-reset Terminal AppleScript helper with non-Automation recovery guidance or a direct System Settings link. Keep Accessibility observation pending IR-052.`

Acceptance group: A4.


### IR-051

Full Disk Access.

`resolved - delete Full Disk Access and its complete lifecycle: onboarding and polling, protected-directory probes and AppState, Chat/realtime permission exposure, guide/settings/status UI, restart coupling, prompts/docs/tests, local-file indexing and Apple Notes callers already rejected by IR-047. Retain app-owned local persistence and explicit user-selected chat attachments.`

Acceptance group: A4.


### IR-052

Accessibility retained for global PTT and precise Rewind/Focus windows.

`resolved - keep Accessibility for exactly two read-only product areas: reliable system-wide PTT and precise Rewind/Focus focused-window behavior`

Retain the existing Accessibility permission request, trust/status handling, onboarding explanation, stale/broken-TCC detection, and repair behavior needed by those two areas. `PushToTalkManager` uses the grant for system-wide `.flagsChanged`, `.keyDown`, and `.keyUp` observation. `ScreenCaptureService` and `OverlayService` use it to identify the actual focused window, title, ID, and frame when one application owns several visible windows.

The Accessibility-based focused-window path is the normal Rewind/Focus behavior. Keep `CGWindowList` as the existing fail-open path when the grant is missing/broken or a particular app's Accessibility tree fails; do not make the largest-window heuristic the default.

Do not restore Apple Events Automation, clicking/typing, general app control, connector automation, broad computer-agent permissions, or Chat tools that promise those deleted capabilities.

Acceptance group: A4.


### IR-053

Transient Gemini embeddings for local semantic search.

`resolved - keep transient Gemini embedding computation through our authenticated backend for the first release. Keep screenshot OCR/task/query vectors and all cosine similarity/index/search authority on the Mac; do not add Pinecone, Firestore vectors, server vector search, cross-device copies, or Agent VM mirrors. Remove staged-task embeddings with IR-026. Use our Firebase/project/Gemini credentials and entitlement/quota scaffold, do not persist embedding request content server-side, and disclose that app/window/OCR text and search queries are transmitted transiently to Google.`

Acceptance group: A4.


### IR-054

Push-to-talk realtime spoken assistant.

`resolved - keep the PTT spoken-assistant capability with every child governed by its recorded keep, adapt, or delete decision`

Confirmed: the first release lets a user intentionally invoke a voice interaction, ask a question, and receive a spoken response. IR-055 through IR-119 and the later model, fair-use, UI and backend children now separately govern invocation, capture, providers, interruption, current-screen and local-data grounding, tools, continuity, fallbacks, settings, diagnostics and operations. Keeping the parent no longer leaves any inherited child implicitly accepted or unresolved.

PTT remains independent from continuous transcription. The final implementation must follow the child decisions rather than preserve or delete the inherited lifecycle as one indivisible unit.

Acceptance group: A5.


### IR-055

Backend realtime-STT relay as an intermediate PTT fallback.

`reopened and resolved - delete the intermediate backend realtime-STT relay. When Gemini Live is unavailable, retain the bounded complete PCM turn and its identity while the user continues holding; after release, run the existing silence gate and completed-turn batch STT, then Gemini Chat and retained OpenAI TTS. A failed batch transcription remains the terminal transcription error.`

This reopened decision supersedes the earlier relay-retention analysis above. The
Gemini-first provider simplification implements the deletion without a compatibility
endpoint.

Acceptance group: A5.


### IR-056

Per-user managed PTT usage accounting.

`resolved - keep count-only per-user usage, estimated provider cost, and quota-question accounting for managed PTT. Retain the shared monthly allowance/upgrade UI behavior and adapt plan limits and entitlement mapping to our Firebase and Dodo scaffold. Do not store voice audio, transcript text, answer text, screenshots, OCR, or rendered prompt context in this usage ledger. Stronger provider-side reconciliation remains a separate hardening question, not a reason to delete basic accounting.`

Acceptance group: A5.


### IR-057

Firestore record for every temporary PTT credential.

`resolved - delete users/{uid}/realtime_sessions token-hash documents, _record_session/_persist_session, their mint-call hooks, and focused tests that assert this unused write. Keep provider-owned credential expiry, managed token minting under IR-007, and the separate billable usage/cost/quota ledger under IR-056.`

Acceptance group: A5.


### IR-058

PTT BYOK provider access.

`delete PTT BYOK access`

Confirmed: PTT has one commercial access model for the first release. A paying user signs into the product and uses the managed short-lived credential path retained under IR-007. Remove PTT-specific personal-key selection, `.byokKey` authentication branches, direct-key connection eligibility, BYOK-specific provider fallback, BYOK-specific usage-report bypass, PTT setup/error wording that asks for a provider key, and focused tests that exist only for that second PTT access mode.

This decision was originally scoped to PTT so the shared key plumbing was not deleted without review. IR-062 subsequently completed that sibling audit and deletes customer BYOK globally: `APIKeyService` BYOK state, developer-key Settings, account activation, and personal-key use by normal text Chat, transcription, embeddings, TTS, and model proxies are all inside the product-wide deletion boundary.

Acceptance group: A5.


### IR-059

Completed-turn batch STT as final PTT recovery.

`resolved - keep completed-turn batch STT as the final PTT recovery path after the direct realtime hub and retained live relay have failed or become unavailable after release. Preserve the bounded whole-turn audio buffer, authenticated /v2/voice-message/transcribe call, backend provider selection, transcript handoff to the normal local text agent, and existing TTS response. Remove PTT-specific BYOK headers consistently with IR-058 without removing this managed recovery path.`

Acceptance group: A5.


### IR-060

Provider-native realtime speech-to-speech as the primary PTT path.

`resolved - keep the existing provider-native realtime speech-to-speech path as the normal PTT experience. Preserve the direct live provider session in which microphone audio, reasoning, scoped tool calls, and streamed spoken output share one turn. Keep the relay and batch STT -> normal text agent -> TTS routes as fallbacks rather than promoting them to the normal experience. Provider portfolio, barge-in details, screen/local grounding, tools, caching, and continuity remain separate child decisions.`

Acceptance group: A5.


### IR-061

Two realtime providers and cross-provider failover.

`reopened and resolved - keep Gemini Live only; delete OpenAI Realtime, provider switching, and cross-provider failover`

Gemini `gemini-3.1-flash-live-preview` owns the one native speech-to-speech
path. Preserve its same-provider reconnect, barge-in session replacement, tools,
journal, turn claims, and bounded audio buffer. If reconnect cannot recover the
turn, cascade after release through batch STT, Gemini Chat, and retained OpenAI
TTS. OpenAI remains only the separate spoken-text output provider.

This reopened decision supersedes the dual-provider analysis above and does not
restore customer BYOK.

Acceptance group: A5.


### IR-062

Product-wide four-provider BYOK free plan.

`resolved - delete all customer BYOK across the product and use one managed subscription/provider-access model`

Confirmed: remove the complete four-provider "free forever" plan and every personal-provider-key path, including PTT. Delete the customer key fields and status UI; `dev_openai_api_key`, `dev_anthropic_api_key`, `dev_gemini_api_key`, and `dev_deepgram_api_key` storage from the production app; direct key validation; all-four activation rules; raw-key HTTP, WebSocket, TTS, transcription, proxy, and local-runtime propagation; credential-health logic used only by BYOK; backend activation/deactivation endpoints; Firestore fingerprints and BYOK state; peppering, cache, middleware/context, and validation machinery; provider-key overrides; free-plan subscription responses; and trial, paywall, chat-quota, and transcription-quota bypasses.

Every customer signs in and uses our managed provider credentials under the Firebase account, Dodo-backed subscription, entitlement, and usage/quota boundary retained by IR-006. Platform-owned server secrets and short-lived managed credentials are not BYOK and remain wherever a separately retained compute path needs them. This decision does not choose the surviving model vendors; OpenAI versus Gemini versus Anthropic versus Deepgram remains part of the deferred AI-model/Python-backend audit.

Acceptance group: A5.


### IR-063

Accessibility dependency of the global PTT hold shortcut.

`resolved - keep the existing system-wide hold-to-talk activation and retain minimal Accessibility support for its global key observation`

Confirmed: PTT must start when the configured shortcut is held while another application is focused and finalize when the shortcut is released. Preserve the current global/local event-monitor ownership, modifier-down/key-down and release handling, 80 ms modifier-only chord-protection gate, floating-bar reveal, and handoff into the retained PTT turn lifecycle.

Retain Accessibility onboarding, trust/status detection, and recovery UX for two explicit read-only behaviors: global keyboard monitoring for PTT, and exact focused-window/title/frame detection for Rewind capture and Focus-glow placement. The Accessibility path is normal; `CGWindowList` remains the resilience fallback when permission is denied, stale, or an application's Accessibility tree fails. Do not restore deleted clicking, typing, Apple Events Automation, connectors, general computer control, or arbitrary app actuation.

Acceptance group: A5.


### IR-064

Double-tap hands-free locked PTT mode.

`resolved - keep the existing double-tap hands-free locked PTT mode`

Confirmed: retain the local Settings toggle and its current default, first-tap duration gate, 400 ms second-tap window, `pendingLockDecision` and `lockedRecording` phases, hands-free microphone capture, tap-again finalization, locked-mode floating UI, cancellation/owner-change handling, lifecycle diagnostics, and behavioral tests. This does not create a separate backend route, model path, data store, or cloud authority; the completed voice turn continues through the same retained PTT provider/fallback/journal lifecycle.

Acceptance group: A5.


### IR-065

PTT shortcut presets, customization, and disable control.

`resolved - keep PTT shortcut presets, arbitrary custom shortcut recording, local persistence, and the disable control`

Confirmed: retain onboarding selection/testing for Fn, Option, and Control; Settings presets including Right Command; arbitrary single-key and key-combination recording; exact modifier/key-up matching; display labels; local migrations and persistence; later changes; and the ability to disable global PTT without deleting the feature. Preserve the modifier-only and keyed-chord paths in `PushToTalkManager` and their focused tests.

Acceptance group: A5.


### IR-066

PTT-specific microphone selection.

`resolved - keep the PTT-specific microphone selector with Automatic as the default`

Confirmed: retain the Settings picker, available-input enumeration, local stable-UID persistence, Automatic default, explicit USB/studio/display/headset microphone overrides, stale/disconnected selection display, and safe fallback to Automatic when the chosen device is unavailable. Preserve the existing automatic policy that normally follows the system input but prefers the built-in microphone while Bluetooth output is active, so opening a Bluetooth microphone does not degrade or chop assistant playback. Preserve the dedicated/coalesced CoreAudio routing probe and protection against an old lookup overriding a newer selection.

Automatic routing, silent-microphone detection, capture rebuilding, and microphone permission remain reliability behavior; they are not deleted merely because the manual picker survives.

Acceptance group: A5.


### IR-067

Optional PTT recording-state sounds.

`resolved - keep optional start and end PTT sounds and repair the incomplete implementation`

Confirmed: retain the local `Push-to-Talk Sounds` toggle, its current enabled default, and audible confirmation for entering and leaving voice capture in both held and locked modes. During implementation, add the missing end cue and order cue playback coherently with output muting/restoration so an enabled cue is actually audible. Keep cancellation/error behavior deliberate rather than accidentally playing a success-style cue for every teardown, and add behavioral coverage around the retained transitions.

The separate `Mute Audio While Talking` feature is not decided by IR-067; it moves to IR-068.

Acceptance group: A5.


### IR-068

Temporarily mute other Mac playback while PTT is listening.

`resolved - keep Mute Audio While Talking exactly as it is`

Confirmed: retain the local toggle and its enabled default; inspect only the default output device; do nothing when no playback is active or the user already muted the device; prefer the device's master-mute property; fall back to saving and zeroing settable output volumes; leave the media advancing silently; and restore the exact device state on release, finalization, cancellation, errors, owner transitions, terminal cleanup, and before assistant reply audio. Keep its existing idempotent repeated mute/restore behavior and output-readiness integration.

IR-067 may reorder the retained sound cues around muting/restoration so the cues are audible. That repairs the sound feature without changing IR-068's product behavior.

Acceptance group: A5.


### IR-069

Reject accidental taps, silence, and non-speech noise before model commit.

`resolved - keep the existing local speech-admission behavior exactly as it is`

Confirmed: retain the current route-specific duration and voiced/speech-like thresholds, zero-crossing filtering, stricter short-turn coverage, on-device Silero rescue for quiet real speech, amplitude fallback when Silero is unavailable, local rejection before provider/model/tool commit, quiet reset for longer no-speech turns, and the visible “Hold longer to record” state for a too-fast tap. Preserve the bounded raw-audio evidence and focused lifecycle/tests supporting these decisions.

Dead-microphone recovery triggered by near-zero capture, voice-language identification/correction, and audio-buffer bounds remain separate requirements.

Acceptance group: A5.


### IR-070

Recover a microphone that is running but returning zeros.

`resolved - keep the complete existing dead-microphone recovery`

Confirmed: retain the all-transport near-zero watchdog, roughly two-second detection threshold, three-second cooldown, three-recovery cap per capture session, ordinary Bluetooth-input fallback to the built-in Mac microphone, non-Bluetooth CoreAudio stack rebuild, same-turn restart, clearing of zero-valued buffered evidence, capture-generation and turn-identity guards, two-consecutive-dead-turn backstop, neutral handling of unjudgeably short taps, recovery success/failure attribution on the next judgeable turn, diagnostics, and focused tests.

This remains ordinary macOS CoreAudio reliability. It does not restore Omi wearable BLE discovery, pairing, audio decoding, or device management, and it does not overwrite the user's saved PTT microphone selection.

Acceptance group: A5.


### IR-071

Voice-assistant language selection and local misdetection correction.

`resolved - keep the existing PTT voice-language behavior`

Confirmed: retain onboarding and Settings language selection; ordered local `Voice Assistant Languages` storage; explicit-versus-unconfigured gating; voice-language changes rebuilding the idle warm session; language constraints in the realtime system instruction; direct provider hints where supported; the early multi-language Parakeet v3 decode; full-buffer local fallback decode; Apple language recognition biased to the configured set; fail-open behavior for missing/late/uncertain model results; the bounded final transcript-resolution policy; and local journal correction when the provider transcript is empty or in an unrelated language.

Keep this lifecycle separate from ambient meeting-transcription language settings and cloud synchronization. IR-061 keeps both providers, so preserve the explicit OpenAI hint path and Gemini's system-instruction/local-correction path.

Acceptance group: A5.


### IR-072

Hard-coded English retry for empty short batch transcription.

`resolved - preserve a second-chance batch recovery but replace the hard-coded English assumption`

Confirmed: every final PTT batch caller must use one consistent voice-language policy. Choose the first attempt from the approved PTT Voice Assistant Languages authority and per-turn local verdict rather than the ambient meeting-transcription setting. If a language-specific attempt returns empty, allow at most one bounded retry using provider multilingual/auto-detect mode. Remove the special claim that every short failed non-English turn should be retried as English, and remove route-specific differences where only one batch branch receives the second attempt.

Keep the final batch recovery itself under IR-059. This decision adapts its language selection; it does not add another persistent store or provider.

Acceptance group: A5.


### IR-073

Barge in while the assistant is speaking.

`resolved - keep the barge-in capability`

Confirmed: when an admitted PTT press occurs while provider speech or local TTS playback is still active, stop the old spoken reply immediately and begin the new recording turn. Retain the modifier-only activation gate so an ordinary editing shortcut does not accidentally interrupt the assistant, and retain turn/session ownership fences so late callbacks from the interrupted reply cannot leak into the new turn.

This approves only the user-facing interruption capability. What is retained from the cut-off exchange in local history is IR-074. IR-061 subsequently keeps both the OpenAI cancellation and Gemini session-replacement paths.

Acceptance group: A5.


### IR-074

Interrupted exchange in local journal and next-turn context.

`resolved - keep the old question plus only the partial answer actually produced`

Confirmed: preserve the recognized old user question and any assistant text that had already streamed before barge-in. Apply the approved local PTT transcript correction before writing the user text, never synthesize the missing remainder of the answer, use the retained local kernel journal as the only durable authority, keep stable continuity keys and ownership receipts to prevent duplicates, and make the preserved exchange available to the next voice turn.

If interruption happens before any assistant text exists, preserving only the old user question remains valid. This decision creates no cloud copy or synchronization path. How the journal, chat UI, and next model distinguish an intentionally interrupted partial answer from a finished answer is IR-075.

Acceptance group: A5.


### IR-075

Truthful interrupted-state marker.

`resolved - keep one durable local interrupted marker and use it in both UI and context`

Confirmed: keep the journal lifecycle status `completed` when the local write succeeds, and separately store `interrupted: true` as semantic metadata on the partial assistant turn. Project that flag into Swift chat state, show a small neutral “Interrupted” label, and include the fact in the kernel's recent-turn context so the next voice model knows the preceding assistant text is incomplete. Old rows without the field remain non-interrupted by default.

Reuse the existing local journal `metadata_json` path. Do not create a table, a second store, a cloud synchronization field, or misuse journal `failed` status for an intentional user action.

Acceptance group: A5.


### IR-076

Current-screen vision for PTT.

`resolved at parent - keep PTT current-screen vision`

Confirmed: retain the product ability to answer spoken questions about what is currently visible using pixels tied to that exact logical voice turn. Keep this separate from historical Rewind screen search, never treat old OCR as current visual truth, and never persist the temporary PTT image into Rewind, the local journal, kernel context, or logs.

This approves only the parent capability. It does not yet approve capturing on every press, eager OCR/JPEG work, provider-image upload and consent policy, display selection, the two-call report handshake, failure behavior, or `point_click`. Those remain independent children.

Acceptance group: A5.


### IR-077

Freeze one raw screen image at PTT-down.

`resolved - keep one raw in-memory capture at PTT-down`

Confirmed: every admitted PTT turn may freeze one temporary display image before Omi expands its overlay. Keep it bound to the current logical voice turn, clear it when the turn ends or is superseded, fail closed rather than selecting an ambiguous display, and never persist the raw image into Rewind, the journal, kernel context, or logs.

This decision establishes only the temporal source of truth. It does not approve eager OCR, eager JPEG encoding/hashing, provider upload, or the downstream verification protocol.

Acceptance group: A5.


### IR-078

Eager local OCR for PTT transcript correction.

`resolved - keep eager OCR for narrow local correction; delete external screen-word exposure`

Confirmed: continue OCR'ing the already-frozen PTT image locally while the user speaks. Keep it opportunistic and non-blocking, bound results to the current logical turn, cap the material used for keyword extraction, and retain the narrow local transcript corrector for fallback transcripts.

Adapt the flattened vocabulary model so explicit Settings vocabulary remains distinguishable from screen-derived terms. Screen-derived terms must stay on the Mac: do not send them as Python backend batch-STT query keywords and do not print raw keyword samples in logs. This does not decide whether explicitly entered Settings vocabulary may be used as a managed STT hint.

Acceptance group: A5.


### IR-079

Eager JPEG encoding and hashing on every PTT turn.

`resolved - keep eager JPEG encoding and hashing as-is`

Confirmed: continue dispatching JPEG encoding and SHA-256 hashing immediately after the raw PTT-down capture, retain the existing background worker/readiness object, keep the current quality and bounded wait behavior, and discard the prepared bytes with the turn when no screenshot request uses them.

Acceptance group: A5.


### IR-080

Five-second freshness measured from PTT-down.

`resolved - keep the five-second PTT-down freshness limit as-is`

Confirmed: the exact JPEG must enter the matching provider transport less than five seconds after the original PTT-down capture. Keep the existing active turn/session/response/tool/epoch identity checks and the separate eight-second post-transport report deadline. At or after five seconds, reject the image as expired and use the current deterministic screen-verification failure path, even when the user is still in the same logical turn.

Acceptance group: A5.


### IR-081

One provider-image sharing preference for typed Chat and PTT.

`resolved - keep the current PTT provider-image sharing behavior as-is`

Confirmed: continue treating an authorized realtime `screenshot` tool request plus existing macOS Screen Recording access as sufficient for provider delivery. Do not apply the typed Chat `Screen Sharing in Chat` toggle to PTT, do not add a separate PTT sharing preference, and do not add per-turn spoken confirmation. The existing toggle remains scoped only to ordinary Chat's `capture_screen` and `get_screenshot` tools.

Acceptance group: A5.


### IR-082

Multi-display target selection.

`resolved - keep frontmost-window display selection and fail closed when ambiguous`

Confirmed: continue selecting the display containing the frontmost application's foremost useful on-screen window through Core Graphics compositor metadata. Use the sole active display only when that fallback is unambiguous. Do not select by mouse position, capture all displays, add a preferred-display setting, or add an Accessibility lookup to the PTT-down critical path.

Acceptance group: A5.


### IR-083

Whole-display image versus frontmost-window crop.

`resolved - keep the whole selected display as the single current-screen image`

Confirmed: capture and send the complete frame of the one display selected under IR-082. Do not crop to only the frontmost window, do not add question-based scope classification, and do not automatically send a second window crop. Retain menus, dialogs, popovers, side-by-side content, and full desktop spatial context even though unrelated visible material on that display may also be included.

Small-text legibility on Retina displays remains IR-084.

Acceptance group: A5.


### IR-084

Native-resolution detail tiles for realtime PTT.

`resolved again - keep the current one-image behavior and do not add detail/zoom`

Confirmed after reopening: do not add an on-demand crop, native-resolution tile payload, zoom tool, second window image, or any other detail-image branch for the first release. Keep the currently implemented single full-display JPEG behavior unchanged.

Acceptance group: A5.


### IR-085

Hidden `report_screen_observation` verification round.

`resolved - keep report_screen_observation as-is`

Confirmed: retain the generated tool declaration, provider instruction, screenshot/report two-step protocol, `awaitingReport` and receipt states, output suppression, native foreground-application contradiction check, separate eight-second report deadline, deterministic failure/persistence behavior, reducer events, diagnostics, and existing tests. Do not simplify the provider continuation to answer immediately after image transport.

Acceptance group: A5.


### IR-086

Physical `point_click` actuation from realtime voice.

`resolved - delete point_click for the first release`

Confirmed: remove the generated realtime tool declaration, provider guidance, allowlist entry, semantic-policy surface, Swift executor branch, raw `CGEvent` click implementation, diagnostics, harness coverage, and tool-specific tests. Retained PTT screen vision remains read-only: it may understand the current screen and tell the user what to click, but it must not synthesize a physical mouse click.

Acceptance group: A5.


### IR-087

Personal local-data grounding in realtime PTT.

`resolved at the parent - keep personal-data grounding in realtime PTT`

Confirmed: PTT remains able to answer questions about the user's own history, memories, conversations, and tasks. Retained sources must become local-authoritative rather than preserving their current Python product-backend read routes. The individual sources, read/write tools, result bounds, and provider-visible disclosure remain separate child decisions.

Acceptance group: A5.


### IR-088

Rewind semantic-history search from realtime PTT.

`resolved - keep search_screen_history in realtime PTT`

Confirmed: retain the voice tool declaration, local kernel authorization route, alias to the existing local semantic-search implementation, locally stored Rewind vectors/rows, and the provider continuation that speaks the result. This does not restore Firestore, Pinecone, historical screenshot upload, or backend Rewind authority. The result projection was separately retained unchanged under IR-089.

Acceptance group: A5.


### IR-089

Voice-specific bound for Rewind search results.

`resolved - keep the existing Rewind result payload unchanged`

Confirmed: realtime PTT continues using the shared semantic-search formatter with up to fifteen matches, date/time, app name, window title, internal screenshot ID, similarity score, and up to 300 OCR characters per match. Do not add a voice-specific projection or alter typed Chat's result shape.

Acceptance group: A5.


### IR-090

Local daily activity recap in realtime PTT.

`resolved - keep get_daily_recap in realtime PTT`

Confirmed: retain the realtime tool declaration, local kernel authorization route, six-query local GRDB read, combined Markdown formatter, and provider continuation that speaks the result. The recap remains local-authoritative and does not gain a Python backend or separate summarization service. Its period and output bounds were separately retained unchanged under IR-091.

Acceptance group: A5.


### IR-091

Period and row bounds for the PTT daily recap.

`resolved - keep the current unbounded recap behavior unchanged`

Confirmed: retain the generic numeric `days_ago` schema, lower-bound-only clamp, uncapped requested period, existing per-section formatter, and unbounded conversation/task rows. Do not add a seven-day ceiling or voice-specific row limits.

Acceptance group: A5.


### IR-092

Recent and date-filtered conversation listing in realtime PTT.

`resolved - keep get_conversations and move it to local GRDB`

Confirmed: retain recent/date-filtered conversation listing in realtime PTT, but remove its dependency on `APIClient.toolGetConversations` and `GET /v1/tools/conversations`. Reproduce the existing list/filter/format behavior from local `transcription_sessions` and, only when the retained contract needs them, local `transcription_segments`. The semantic topic-search sibling remains separate under IR-093.

Acceptance group: A5.


### IR-093

Semantic topic search across past conversations in realtime PTT.

`resolved - keep semantic conversation search and port the hybrid pattern locally`

Confirmed: retain `search_conversations` in realtime PTT and preserve exact keyword plus semantic recall. Replace Firestore conversation reads, Typesense, and hosted vector storage with local authoritative conversation rows, local FTS5 title/overview indexing, transient embedding compute through the already-retained proxy, locally persisted vectors, local similarity comparison, and the same keyword-first merge/result contract. Do not downgrade to SQL `LIKE`-only search.

Acceptance group: A5.


### IR-094

Broad memory listing in realtime PTT.

`resolved - keep get_memories and move it to local MemoryStorage`

Confirmed: retain broad memory listing in realtime PTT, but remove `APIClient.toolGetMemories`, `GET /v1/tools/memories`, and the canonical/default/legacy Firestore memory-routing dependency from this path. Read the accepted local memory authority through `MemoryStorage`, preserving pagination/date filtering and model-ready formatting. Specific semantic memory search remains separate under IR-095.

Acceptance group: A5.


### IR-095

Semantic search for a specific memory in realtime PTT.

`resolved - keep search_memories and port vector storage/search locally`

Confirmed: retain semantic specific-memory recall in realtime PTT. Replace Firestore memory reads and hosted vector search with embeddings tied to authoritative local memory lifecycle, locally persisted vectors, transient query embedding through the retained proxy, local similarity comparison, and the existing bounded content/category/date/relevance result shape. Do not downgrade to substring-only matching.

Acceptance group: A5.


### IR-096

Local overdue/due-today task fast path in realtime PTT.

`keep unchanged - already resolved by IR-025 and IR-087`

IR-025 retained local tasks, and IR-087 retained personal-data grounding in PTT. This read-only local fast path is the direct intersection of those decisions and introduces no separate cloud authority or hosted service. It therefore does not need a redundant product-choice question.

Acceptance group: A5.


### IR-097

Completed, date-filtered, and full task reads in realtime PTT.

`resolved - keep get_action_items and move it to local ActionItemStorage`

Confirmed: retain completed/date-filtered/full task reads in realtime PTT. Replace `APIClient.toolGetActionItems` and `GET /v1/tools/action-items` with equivalent local filters, surfaced IDs, ordering, timezone formatting, and bounded model-ready output over authoritative `ActionItemStorage`. Do not limit voice to the overdue/today fast path.

Acceptance group: A5.


### IR-098

Creating tasks and reminders from realtime PTT.

`resolved at the parent - keep voice task creation and move it local`

Confirmed: retain `create_action_item` in realtime PTT, replace the backend POST/Firestore/server-refresh path with owner-authorized local `ActionItemStorage` insertion, and keep provider-spoken confirmation. Local reminder behavior and due-date semantics remain separate children.

Acceptance group: A5.


### IR-099

Model-reliant intent for voice task creation.

`resolved - keep the existing model/prompt-reliant pattern`

Confirmed: do not add a deterministic task-intent parser, second confirmation turn, preview/approval UI, or separate dispatch flow for realtime task creation. Continue relying on the model/tool description to call `create_action_item` only when appropriate, while retaining the existing owner, active-turn, allowlist, input-hash, replay, and local mutation-authorization fences.

Acceptance group: A5.


### IR-100

Automatic due-in-24-hours default for voice-created tasks.

`resolved - preserve the due-in-24-hours default and make it local`

Confirmed: when `create_action_item` receives no `due_at`, the local creation path must assign `Date() + 24 hours`, matching the current Python backend behavior. Explicit model-supplied due times remain unchanged after validation.

Acceptance group: A5.


### IR-101

Due-time task reminder delivery on the Mac.

`resolved - keep due-time reminders and make their lifecycle local`

Confirmed: replace backend FCM task-reminder data messages with local `UNUserNotificationCenter` requests keyed by the local surfaced task ID. Create/update must schedule or replace the request; completion, deletion, or clearing the due date must cancel it; launch/owner transitions must reconcile pending requests against authoritative ActionItemStorage. No backend task copy or messaging token is retained for this behavior.

Acceptance group: A5.


### IR-102

Immediate “Task Added” banner after PTT creation.

`resolved - delete the immediate Task Added banner from PTT`

Confirmed: do not replace `send_action_item_created_notification` with an immediate local system notification. Successful PTT creation updates local task state and is confirmed by the provider's spoken tool result; the separately retained due-time reminder remains scheduled for later delivery.

Acceptance group: A5.


### IR-103

Updating tasks from realtime PTT.

`resolved - keep update_action_item and move task updates local`

Confirmed: retain voice-driven complete/pending changes, renaming, and rescheduling. Replace the backend PATCH, Firestore authority, server refresh, FCM reminder-control messages, and server completion banner with owner-authorized `ActionItemStorage` writes, immediate local UI invalidation, and the local reminder reconciliation retained under IR-101.

The model's authorization and ambiguous-match behavior are reviewed separately in IR-104.

Acceptance group: A5.


### IR-104

Model-reliant intent and ambiguous matching for voice task updates.

`resolved - keep the existing model-reliant pattern and make its task data local`

Confirmed: preserve the current model/prompt responsibility for update intent, task matching, and ambiguous requests. Do not add deterministic intent parsing, a mandatory same-turn read receipt, or a second confirmation step. The model reads local task data, passes the selected local task ID to the local `update_action_item` path, and receives the local result. Existing owner/run/attempt/allowlist/replay fences remain.

Acceptance group: A5.


### IR-105

Lookup coverage before a voice task update.

`resolved - keep the existing lookup pattern and make every task lookup local`

Confirmed: retain `get_tasks` as the fast local overdue/due-today read and allow the model to use the broader `get_action_items` read for future, undated, completed, date-filtered, or full-list targets. Port `get_action_items` to authoritative local `ActionItemStorage` under IR-097; do not preserve its Python backend/Firestore read.

The model continues choosing the appropriate read, matching the task, and handling ambiguity under IR-104. Do not add a deterministic lookup router, full-list-only policy, mandatory same-turn read receipt, or second confirmation step. Update the inherited `update_action_item` guidance so it no longer incorrectly claims every target must come only from the overdue/today `get_tasks` slice.

Acceptance group: A5.


### IR-106

Creating Google Calendar events from realtime PTT.

`resolved - delete create_calendar_event with the first-party connectors`

Confirmed: remove the realtime tool declaration and guidance, Swift validation/executor branch, `APIClient.toolCreateCalendarEvent`, `POST /v1/tools/calendar-events`, and calendar-event tool contracts/tests once remaining shared Google-tool callers are audited. Do not retain or rebuild a Google OAuth/Contacts/token-refresh exception, Mac-owned Google authorization flow, or EventKit replacement for the first release.

This does not remove ordinary date fields or due-time reminders from local Tasks. It removes only the external side effect that creates an event in Google Calendar.

Acceptance group: A5.


### IR-107

Checking and requesting macOS permissions from realtime PTT.

`resolved - keep the local permission tools, narrowed to the four surviving permissions`

Confirmed direction:

- preserve the existing local status-check and native request behavior for Screen Recording, Microphone, Notifications, and Accessibility;
- preserve the explicit-user-request/affirmation guard before opening a native permission prompt or Settings pane;
- delete Automation and Full Disk Access from the generated tool enums, descriptions, validation policy, Swift executors, and related tests;
- do not add any backend or cloud permission authority.

Acceptance group: A5.


### IR-108

Saving completed realtime PTT exchanges in local chat history.

`resolved - keep completed PTT exchanges in the selected local Chat`

Confirmed direction:

- preserve the existing user-plus-assistant journal pair for every completed PTT exchange;
- preserve streaming updates, finalization, stable retry-safe IDs, local UI replay, and restart durability;
- keep the selected local Chat as the visible home of the exchange rather than creating a separate hidden voice-history store;
- remove `backend_turn_outbox` creation, delivery, acknowledgement, reconciliation, and Python-backend projection without weakening the local journal behavior.

Acceptance group: A5.


### IR-109

Continuing one conversation across typed Chat and realtime PTT.

`resolved - keep one shared local conversation across typed Chat and PTT`

Confirmed direction:

- preserve the shared canonical conversation mapping for `main_chat`, `floating_chat`, and `realtime_voice` when they carry the same selected chat ID;
- preserve local context snapshots that supply recent canonical turns to both typed and spoken model requests;
- preserve switching behavior: PTT follows the currently selected Chat rather than owning a hidden voice thread;
- preserve the historical-only label on old screen-related voice context so prior screen statements cannot impersonate current visual evidence;
- remove backend delivery/synchronization without weakening this local cross-input continuity.

Acceptance group: A5.


### IR-110

Keeping a realtime model session warm before PTT begins.

`resolved - keep the existing preconnected realtime session for v1`

Confirmed direction:

- preserve launch/post-turn warm-up and reuse of an authenticated realtime-provider WebSocket;
- preserve buffered microphone capture plus the retained transcription fallback when a warm session is unavailable;
- preserve the existing owner, sleep/wake, provider, language, idle-close, maximum-duration, and reconnect-strike safety boundaries;
- accept that the selected Chat's rendered context is delivered to the realtime provider during warm-up rather than waiting for the first PTT press;
- do not confuse this direct provider connection with the rejected agent VM, journal outbox, or backend synchronization.

Acceptance group: A5.


### IR-111

Sending PTT context-plan/cache identity metadata to the backend.

`resolved - delete the unused PTT cache-identity reporting metadata`

Confirmed direction:

- remove `context_plan_id`, `stable_cache_identity`, `dynamic_context_identity`, and `context_cache_replaced` from the realtime PTT usage-report wire path and tests;
- remove PTT-session fields and pass-through state that exist only to deliver those discarded backend values;
- preserve provider-reported input text, input audio, cached input, output text, and output audio token counts because the retained usage/cost ledger consumes them;
- preserve the local context plan and cache identities where the Node runtime actually uses them for binding compatibility and context planning; IR-601 deletes their separate realtime escalation consumer.

Acceptance group: A5.


### IR-112

Reconnecting or replacing a stale warm PTT session.

`reopened and resolved - keep same-provider reconnect and correctness replacement; delete cross-provider failover under IR-061`

Acceptance group: A5.


### IR-113

Managed Gemini inference for the local desktop Chat agent.

`reopened and resolved - keep the existing local Node/Pi loop, replace the Claude proxy with native managed Gemini 3.7 Flash, and expose no provider picker or compatibility alias`

Keep the existing 200k input and 16,384-output caps, transport timeouts,
heartbeat, pre-first-byte-only retry, cancellation, Firebase authentication,
quota enforcement, sanitized errors, and local ownership. Delete the Anthropic
client, translator, SDK and credentials. This does not restore cloud Chat state,
customer BYOK, or the rejected agent VM.

Acceptance group: A5.


### IR-114

Legacy PTT start/end product-analytics events.

`delete both legacy events`

Confirmed: remove `AnalyticsManager.floatingBarPTTStarted`, `AnalyticsManager.floatingBarPTTEnded`, every PTT call site for those helpers, and obsolete comments/spec references that say the deprecated event is retained for backward compatibility. Keep PostHog itself under IR-115. This decision does not delete or retain the newer `ptt_audio_capture_lifecycle` diagnostic; IR-116 audits that separately.

Acceptance group: A5.


### IR-115

Retaining Sentry and PostHog under our ownership.

`keep Sentry and PostHog; migrate them to our projects`

Confirmed behavior:

- retain the existing Sentry and PostHog SDK integrations;
- retain the existing dev-build suppression, release/build/channel tagging, opt-out behavior, and privacy filtering unless a later child audit changes one;
- replace the hardcoded macOS PostHog token/host with our PostHog project configuration;
- replace the hardcoded macOS Sentry DSN with our Sentry project configuration;
- replace the release-symbol upload defaults with our Sentry organization/project and use our auth token in the release environment;
- point retained backend PostHog emission at our environment-provided project key/host;
- audit any other surviving shipped client/backend before implementation so no Omi telemetry endpoint remains.

This decision explicitly rejects deleting Sentry or PostHog as part of the local-authority simplification. Telemetry is operational/product measurement, not authority over the user's local Chat, Rewind, Focus, Goals, memories, tasks, or transcription data.

Acceptance group: A5.


### IR-116

Authoritative PTT lifecycle and incident diagnostics.

`keep the existing authoritative PTT diagnostics`

Confirmed: retain the bounded `ptt_audio_capture_lifecycle` outcome, PTT capture/recovery diagnostics, realtime provider session and close-resolution diagnostics, local redacted diagnostic attachment path, release/build/channel attribution, privacy guards, and their tests. Remote events must use the product-owned projects from IR-115. No transcript, audio, prompt, device identifier, or free-form local error text is authorized for remote telemetry.

Acceptance group: A5.


### IR-117

Local per-query performance tracing for Chat and PTT.

`keep QueryTracer unchanged`

Confirmed: retain the current Chat/PTT/playback/tool instrumentation, rotating owner-only local log, production content redaction, richer development-only content capture, trace-statistics script, continuity-gauntlet trace evidence, and focused tests. During the later fork-identity implementation, only its Omi-named log directory should move to this product's local support/log identity.

Acceptance group: A5.


### IR-118

Short actionable status banner for terminal PTT failures.

`keep the existing two-second terminal status banner unchanged`

Confirmed: retain the typed-reason copy, dedicated floating-bar status row, two-second self-clear deadline, new-turn replacement behavior, silent handling for expected/non-actionable terminal states, and focused reducer/UI tests. Retrying remains a normal new PTT invocation; do not add a retry dialog, retry queue, or separate recovery screen.

Acceptance group: A5.


### IR-119

PTT recording, thinking, and speaking presentation.

`keep the current PTT lifecycle presentation unchanged`

Confirmed: retain the live microphone-level waveform, locked-mode badge, thinking animation, speaking pulse, open-Chat recording overlay, notched-display island behavior, non-notched floating-pill behavior, reducer-owned single state source, accessibility labels, and focused presentation tests. Later rebranding may replace product-name/logo assets without changing this lifecycle behavior.

Acceptance group: A5.


### IR-120

Separate `backend-sync` deployment for account deletion.

`resolved - keep durable queued account deletion, but point its Cloud Task at the main backend`

Preserve the durable deletion-intent/job record, opaque job ID, OIDC-protected handler, run lock, retries, terminal-attempt behavior, reconciliation, long route-specific timeout, privacy-bounded telemetry, and the retained billing-provider cancellation step. Configure the task to call the handler already registered on the main FastAPI app, with bounded queue rate/concurrency. Remove account deletion as a reason to deploy `backend-sync`; final deletion of that service still depends on the playback-audio workload audit.

Acceptance group: A6.


### IR-121

Cloud conversation-audio recording and playback artifacts.

`resolved - delete the complete cloud conversation-audio storage and later-playback slice`

Remove raw conversation-audio uploads to GCS, `audio_files` and `conversation_audio` backend authority, per-part and conversation artifact builders, the `audio-merge` queue and handler, precache/poll/signed-URL/download endpoints, cache and unavailability markers, legacy WAV fallback, conversation-merge audio copying, provider-specific configuration, generated client bindings, cleanup branches, telemetry, tests, and documentation that exist only for this slice. Preserve transient live microphone/system-audio capture for transcription, locally authoritative transcripts, PTT/realtime/TTS playback, and Rewind playback. Do not add a new local raw-audio recorder/player during this simplification pass.

Acceptance group: A6.


### IR-122

Store Recordings and Private Cloud Sync controls.

`resolved by IR-121 - delete both settings instead of localizing meaningless switches`

Remove both Settings rows, UI state/load/update helpers, API methods/models, automation projections, backend routes, Firestore fields/helpers, cloud-listen/pusher/pipeline branches, and focused tests/docs. This does not change microphone/system-audio capture for transient STT, locally stored transcripts, PTT answer playback, or Rewind.

Acceptance group: A6.


### IR-123

Omi training-data opt-in program.

`resolved - delete the complete Omi training-data opt-in and review program`

Remove the GET/POST routes, `training_data_opt_in` Firestore field/helpers, automatic re-enablement of the deleted private-cloud audio sync flag, submission notification, generated client bindings, route-policy entries, tests, and documentation. There is no surviving Mac caller, approval/rejection implementation, or model-training pipeline. This deletion does not affect live transcription, locally stored transcripts, product-model inference, Sentry, PostHog, or privacy-bounded diagnostics.

Acceptance group: A6.


### IR-124

Firestore-backed Mac onboarding state.

`resolved - keep the acquisition-source answer locally and in our PostHog; delete the backend onboarding record`

Preserve the current “How did you hear?” selection in local storage and its bounded PostHog event. Remove the additional `PATCH /v1/users/onboarding` write, unused GET route, Firestore `onboarding.completed`, `onboarding.acquisition_source`, and `onboarding.device_onboarding_completed` fields/helpers, generated bindings, tests, and documentation. The device field also has no surviving direct-wearable setup purpose under IR-014.

This narrow storage decision did not itself decide the complete Mac onboarding experience. IR-125's later screen-by-screen child audit now closes that umbrella without changing this storage boundary.

The backend `/v4/listen` voice-questionnaire mode called `OnboardingHandler` is not the same as this Firestore record and is a separate concrete branch. IR-124 neither keeps nor deletes that branch; IR-395 later resolves it for deletion.

Acceptance group: A6.


### IR-125

First-run Second Brain onboarding product.

`resolved by IR-126 through IR-169 - keep the narrowed, globally skippable conversational onboarding assembled from the confirmed children`

The visible onboarding stages and all three non-stage lifecycle children are reviewed. IR-733 keeps the command-line bypass unchanged, IR-734 keeps the pre-completion window-close quit behavior, and IR-735 keeps the bounded state-authority diagnostics. The parent is closed.

A signed-in first-time user enters the retained conversational setup and may globally Skip it. Keep the truthful rebranded opening, local/Firebase name, local/PostHog acquisition answer, local spoken-language choice, optional retained permission setup, global shortcuts, real skippable screen-aware PTT demo, meeting-only versus continuous-listening choice, local stage restoration/Back behavior, genuine-completion Home opener, and the individually retained presentation, reset and cleanup behavior.

Delete the unused role question; Full Disk Access and Automation stages; external agent/context connector stages; obsolete paged and AI-driven onboarding implementations; Agent VM, goal-generation and rejected cloud-write side effects; and every other child already rejected. Completion may enable only the separately retained local launch-at-login, capture and proactive behaviors. Skip remains a real consent-respecting exit and must not masquerade as completion.

This summary does not add a new onboarding screen, restore deleted Omi behavior, or override any child boundary.

Acceptance group: A7.


### IR-126

Active onboarding opening promise/trust screen.

`resolved - keep the opening promise/trust screen, then rebrand and fact-check its claims against the final architecture`

Retain the opening conversational message, three-row trust card, primary setup action, simple presentation, and normal progression into the next screen. Replace Omi/product/repository identities, including the BasedHardware GitHub link. Rewrite the absolute privacy, memory, pause, and deletion claims only after the retained local/cloud architecture is final so the shipped copy is literally accurate.

This decision does not retain the global Skip behavior or any later onboarding screen by implication. Those remain separate concrete reviews under IR-125.

Acceptance group: A7.


### IR-127

Global Skip action across active onboarding.

`resolved - keep global Skip and distinguish bypass from completion in analytics`

Retain the top-right Skip action on every active onboarding step. It must continue to enter Home without force-enabling any permission, capture, continuous transcription, or screen-analysis behavior that the user bypassed. Keep the local completed flag so the discarded setup does not automatically reopen.

Replace the misleading PostHog **Onboarding Completed** emission in `skip()` with a distinct **Onboarding Skipped** event. Normal completion keeps **Onboarding Completed**. Whether Skip should present the current personalized Home opener remains a separate completion/landing decision.

#### Later lifecycle correction discovered during IR-143

The earlier method-level reading was incomplete. `skip()` does not directly call `startTranscription()` or `startMonitoring()`, but `AssistantSettings` registers both `transcriptionEnabled` and `screenAnalysisEnabled` with default value `true`. After `hasCompletedOnboarding` reveals Home, `DesktopHomeView.restorePersistedCaptureServices()` reads those intents and can start transcription and proactive screen monitoring if the relevant permission/provider checks pass.

Therefore the current surrounding lifecycle can violate the approved Skip contract even though `skip()` itself avoids the start calls. Implementing this decision requires the Skip path to leave both capture intents explicitly off—or otherwise fence Home restoration—before the product UI appears. A user who bypasses setup must not receive a new Microphone prompt or have meeting-gated audio/screen monitoring start merely because the registered defaults are true.

Acceptance group: A7.


### IR-128

Onboarding name question and profile persistence.

`resolved - keep the name screen with local and Firebase Auth ownership; delete the backend profile-name copy`

Retain **What should I call you?**, its editable prefill, blank-input guard, and downstream local personalization. Save the chosen first/family name locally for immediate Mac behavior and update the retained Firebase Auth `displayName` as the durable account-level copy.

Delete the redundant Python-backend `/v1/users/profile` name read/write path and Firestore `users/{uid}.name` authority. On sign-in or reinstall, seed the local name from Firebase Auth rather than reconciling a third profile store. This does not retain other onboarding-profile or AI-profile fields.

Acceptance group: A7.


### IR-129

Onboarding acquisition-source screen.

`resolved - keep the acquisition screen locally plus our PostHog; delete backend persistence`

Retain the simple chip screen, local answer for back/resume behavior, and bounded category event sent to our own PostHog project. Rebrand Omi and any Omi-specific source labels when the product identity is finalized. Delete the `PATCH/GET /v1/users/onboarding` write/read and Firestore `acquisition_source` field already rejected under IR-124.

Acceptance group: A7.


### IR-130

Onboarding spoken-language screen.

`resolved - keep onboarding language selection and make the retained behavior local-authoritative`

Retain Mac-locale detection, one-click confirmation, the searchable supported-language picker, and the local `voiceLanguages` update already approved under IR-071. Delete the onboarding backend write and the Firestore `/v1/users/language` authority for Mac behavior. Any retained local insight or assistant-response consumer that needs the preference must read the local setting rather than fetching it back from our backend.

Rebrand the product name and fact-check the final prompt against the exact retained voice/response scope. Ambient meeting-transcription language remains its separate local setting under IR-023.

Acceptance group: A7.


### IR-131

Onboarding role question with no production consumer.

`resolved - delete the role screen and its unused local storage`

Remove the **What do your days look like?** step, its role chips and free-text input, `SBOnboardingModel.role`/`roleDraft` handling, the local `onboardingRole` key, reset/rehydration code, and tests that exist only for this answer. Advance directly from retained language selection to the first surviving permission screen.

Do not create a new Chat/Goals/Focus/insight personalization path merely to justify the deleted question. Retained local product behavior may learn useful context through its already-approved mechanisms.

Acceptance group: A7.


### IR-132

Onboarding Microphone permission screen.

`resolved - keep the optional Microphone permission screen without starting capture`

Retain the explanation, native local permission request, live grant recheck, already-granted skip, bounded polling, automatic advance after success, and **Skip for now** path. Granting Microphone access during onboarding must continue to update permission state only; it must not start transcription or recording before the later explicit capture choice.

The retained screen has no backend authority or synchronization. Rebrand its product copy later while preserving the concrete explanation that Microphone access captures the user's side of a conversation.

Acceptance group: A7.


### IR-133

Onboarding System Audio permission screen.

`resolved - keep the optional System Audio screen and real-tap verification`

Retain the concrete explanation about hearing remote meeting participants, the local Screen Recording prerequisite check, the short authoritative Core Audio tap test on supported macOS versions, retry/timeout safeguards, already-granted/unsupported bypass, automatic advance after success, and **Skip for now**.

The verification tap must stop immediately and must not begin continuous recording. The later explicit capture selection remains the authority for ongoing listening and the local System Audio mode.

Acceptance group: A7.


### IR-134

Onboarding Screen Recording permission screen.

`resolved - keep the optional Screen Recording permission screen without enabling monitoring`

Retain the local native request, correct-bundle registration, System Settings guidance, live TCC polling, already-granted bypass, **Skip for now**, and best-effort throwaway ScreenCaptureKit consent prime. The prime image remains discarded and must never be saved or uploaded.

Granting Screen Recording access by itself must not enable Rewind capture, proactive monitoring, or screenshot delivery. Those retained behaviors remain controlled by their own local settings, invocations, and the later completion audit. Rebrand and narrow the copy to the final retained visual capabilities without restoring deleted actuation.

Acceptance group: A7.


### IR-135

Onboarding Files / Full Disk Access and profile scan.

`resolved - delete this complete onboarding stage`

Delete the Files/Full Disk Access screen, permission request/polling, drag-to-grant helper entry point, forced scan-after-skip behavior, progress/result/error UI, local broad-folder indexing invoked by onboarding, aggregate file-profile memory formation, resume/back state, and stage-specific tests.

This follows the already-approved deletion of first-party Local Files/Apple Notes connectors and Full Disk Access. It does not remove app-owned local databases or explicit user-selected Chat attachments.

Acceptance group: A7.


### IR-136

Onboarding Accessibility permission screen.

`resolved - keep the optional local Accessibility setup but rewrite its explanation`

Retain the native request, health/stale checks, polling, already-granted bypass, repair behavior, and **Skip for now**. Replace every onboarding click/type/general-control claim with a precise explanation of reliable global hold-to-talk and accurate focused-window detection for Rewind/Focus. Do not restore Apple Events, physical clicking, typing, connectors, or general app control.

Acceptance group: A7.


### IR-137

Onboarding Automation permission screen.

`resolved - delete this complete onboarding stage`

Delete the Automation screen, AppleScript/System Events trigger, permission polling/state, resume/back routing, copy, and stage-specific tests. All action-producing consumers were already rejected; retained screen capture, PTT, local data, explicit attachments, and Rewind/Focus do not require Automation.

Acceptance group: A7.


### IR-138

Onboarding global open-assistant shortcut screen.

`resolved - keep the open-assistant shortcut screen unchanged`

Retain the current ⌘O and ⌘Return choices, default-enabled ⌘O behavior, immediate local persistence/enabling on selection, event-monitor rehearsal, **Perfect, that works** success condition, and existing **Skip for now** semantics. Do not change this stage to explicit opt-in, disable the default on skip, replace the presets, add custom recording here, or gate its success label on the later Carbon registration outcome.

The identified standard-⌘O conflict and possible difference between onboarding event observation and later Carbon registration remain documented context, not authorized changes. Later Settings customization and disable controls remain intact.

Acceptance group: A7.


### IR-139

Onboarding hold-to-talk shortcut selection.

`resolved - keep the current onboarding PTT shortcut selection and rehearsal`

IR-065 explicitly retained onboarding selection/testing for Fn, Option, and Control, local persistence, later presets/customization, and the disable control. IR-063 retained the exact system-wide hold/release behavior and its minimal Accessibility dependency. No additional user decision is needed for this already-covered stage.

Acceptance group: A7.


### IR-140

Live screen-aware PTT onboarding demo.

`resolved - keep the current skippable live screen-aware PTT demo`

Retain the production-path bridge warmup, temporary live-transcription override, real floating bar, configured PTT gesture, screen-aware provider turn, retry/unavailable state, Continue-after-real-answer behavior, always-available pre-answer Skip, isolated onboarding journal/drafts, and lifecycle-fenced teardown. The later provider/model decision changes the production path used by the demo rather than deleting the demo itself.

Acceptance group: A7.


### IR-141

Onboarding external-agent connector screen.

`resolved - delete this complete connector stage`

Remove the stage, install/status probes, connect actions, external-agent config writers, MCP/memory-export connection state, brand rows, restart prompt, onboarding routing, and connector-specific tests. This is the first-party memory-export surface explicitly rejected under IR-047.

Do **not** delete the retained local Node agent/chat runtime, the packaged Pi extension, its `OMI_BRIDGE_PIPE` Unix-socket relay, or Swift `ChatToolExecutor`. Those are internal on-Mac implementation boundaries under IR-002/015/937, not connections to OpenClaw, Hermes, Claude Code, or Codex. The separate callerless `omi-tools-stdio` process is deleted by IR-015/S-05 rather than protected here.

Acceptance group: A7.


### IR-142

Onboarding external-context connector screen.

`resolved - delete this complete connector stage`

Remove the context screen, rows, status refresh/projection, import-sheet presentation, Google/Notes/Files connect actions, Full Disk Access coupling, ChatGPT/Claude import routing, connector-specific onboarding state, and tests. The complete first-party import product and Full Disk Access lifecycle were already rejected.

This does not delete local manual Memories, local screen-derived memory behavior, ordinary meeting detection, or explicit user-selected Chat attachments.

Acceptance group: A7.


### IR-143

Final onboarding listening-mode choice.

`resolved - keep both listening modes, meeting-only primary, with truthful call-detection copy`

Retain the final explicit choice between local `.onlyDuringMeetings` and `.always` modes. Keep meeting-only as the primary/default action and continuous listening as the deliberate alternative. Replace **from my calendar** with copy that truthfully explains supported-call detection through conferencing-app/microphone/browser-title signals.

Meeting-only must arm the retained transcription session while keeping microphone and System Audio capture off outside a detected call. Continuous begins capture immediately. Global Skip remains a separate no-capture outcome under IR-127. This decision does not approve unrelated completion side effects.

Acceptance group: A7.


### IR-144

Personalized post-onboarding Home opener.

`resolved - keep the local Home opener after real completion only; remove Calendar and skipped-flow versions`

After genuine completion, retain the time/name greeting, truthful selected listening-mode status, and up to three starter questions sourced from retained local state. Keep the opener outside durable Chat history and dismiss it on the user's first real message or starter selection.

Delete `CalendarReaderService` enrichment and its meeting-specific starter from this path with the rejected connector. Do not call `presentOnboardingOpener()` after global Skip; skipped users receive the ordinary neutral Home/Chat welcome with no false setup or listening claim.

Acceptance group: A7.


### IR-145

Implicit Launch at Login mutation on onboarding completion.

`resolved - enable Launch at Login after genuine completion; disclose it; leave it off after global Skip; keep the Settings off-switch`

Retain automatic startup for users who genuinely choose meeting-only or continuous listening so those modes keep working after a Mac restart. Remove the stale `launchAtLogin` snapshot and the helper that pretends to replay an onboarding choice. Genuine completion directly requests enablement and reports success; global Skip must not register the login item. The final listening screen must disclose that the app will open at login and that the existing Settings control can turn it off.

Acceptance group: A7.


### IR-146

One-time Launch at Login migration for already-onboarded profiles.

`resolved - delete the one-time legacy Launch at Login migration`

Delete the startup call, `migrateLaunchAtLoginDefault()`, the `didMigrateLaunchAtLoginV1` marker, and migration-source analytics path. Do not alter the retained `LaunchAtLoginManager`, genuine-completion enablement under IR-145, global-Skip exclusion, or the Settings toggle.

Acceptance group: A7.


### IR-147

AppKit reopen-at-login policy beside the retained login item.

`resolved - keep the current AppKit reopen-at-login policy unchanged`

Retain `updateOnboardingLifecyclePolicy()`, its `UserDefaults.didChangeNotification` observer, and `relaunchOnLoginSuppressedForOnboarding`. Production builds continue to suppress AppKit reopening before onboarding and allow it after onboarding; non-production bundles continue to suppress it. Keep this behavior alongside the retained `SMAppService` login item and its Settings control.

Acceptance group: A7.


### IR-148

Proactive screen monitoring enabled by genuine onboarding completion.

`resolved - keep genuine-completion proactive screen monitoring unchanged`

For both retained meeting-only and continuous audio modes, genuine completion continues to record screen-analysis intent as enabled and start monitoring when Screen Recording permission is available. If permission is absent, the plugin may retry without opening the macOS permission prompt and Home may reconcile the stored intent later. Global Skip remains the distinct no-monitoring outcome under IR-127.

Acceptance group: A7.


### IR-149

Resume incomplete onboarding from a local stage marker.

`resolved - keep the lightweight local onboarding stage resume unchanged`

Retain `sbOnboardingResumeStep`, draft rehydration, already-granted-permission skipping, and marker cleanup on genuine completion or global Skip. Do not persist the decorative conversational transcript or add cloud synchronization.

Acceptance group: A7.


### IR-150

One-step Back navigation throughout active onboarding.

`resolved - keep the current one-step Back behavior unchanged`

Retain the Back button, current-step teardown, cancellation of permission polling, draft rehydration, and update of the local resume marker. Going Back may revise editable answers but does not pretend to revoke macOS permissions or reverse already-completed external effects.

Acceptance group: A7.


### IR-151

Simulated typing for fixed local onboarding prompts.

`resolved - keep the current simulated typing behavior unchanged`

Retain the 700-millisecond typing state, word-by-word prompt reveal, delayed widget presentation, cancellable task state, and the same behavior when a stage is revisited. This decision applies only to the fixed onboarding presentation and does not change actual live model streaming.

Acceptance group: A7.


### IR-152

No progress indicator in conversational onboarding.

`resolved - keep the current no-progress presentation unchanged`

Retain the conversational panel without dots, a progress bar, step numbering, or a finish line. Do not add progress calculation for conditional or already-granted-permission skips.

Acceptance group: A7.


### IR-153

In-memory conversation history during onboarding.

`resolved - keep the current in-memory onboarding conversation unchanged`

Retain the scrolling, session-only prompt and answer history, automatic scrolling, and current Back behavior. Do not persist this decorative transcript or add logic that rewrites old bubbles after an answer changes; the active widget and locally saved value remain authoritative.

Acceptance group: A7.


### IR-154

Superseded 18-page onboarding implementation.

`resolved - delete the superseded paged onboarding experience`

Delete `OnboardingView`, page-only views and coordinator branches, old step navigation and migrations, the 18-page screenshot-export registry, and tests that protect only the unreachable experience. Before removal, trace every referenced helper: preserve or extract only code with a current caller in conversational onboarding, Settings, sign-out/reset, post-onboarding UI, or another retained product surface.

Acceptance group: A7.


### IR-155

Local onboarding-state cleanup on sign-out and reset.

`resolved - keep a narrowed shared local onboarding-state cleanup boundary`

Sign-out and Reset Onboarding continue calling one small helper that clears retained account-scoped setup state and setup-owned local conversation state. Remove obsolete paged-flow keys and legacy persistence as their owners are deleted. Do not erase normal app data or claim to revoke macOS permissions.

Acceptance group: A7.


### IR-156

User-facing Reset Onboarding capability.

`resolved - keep the confirmed Reset Onboarding capability in Advanced Settings`

Completed users retain the explicit Settings recovery path. After confirmation it clears only retained setup state, restarts the current app build, and replays conversational onboarding without erasing normal data or claiming to revoke macOS permissions.

Acceptance group: A7.


### IR-157

Duplicate immediate Reset Onboarding in the status menu.

`resolved - keep the immediate status-menu Reset Onboarding command unchanged`

Retain the signed-in **Reset Onboarding…** menu item, its analytics event, and its direct call to the shared reset/restart behavior without adding a confirmation step. The confirmed Advanced Settings entry remains as well.

Acceptance group: A7.


### IR-158

Local-development automated onboarding reset.

`resolved - keep the local-development-only reset_onboarding automation action unchanged`

Retain the loopback, token-protected automation action for local development bundles. It continues invoking the same real reset/restart owner as the UI and remains unavailable in stable, beta, and published preview builds.

Acceptance group: A7.


### IR-159

Ordered asynchronous onboarding answer writes.

`resolved by prior decisions - keep ordering only around the Firebase name update`

Preserve the battle-tested per-field ordering pattern for the remaining asynchronous Firebase display-name mutation. Remove the acquisition and language queue cases with their rejected backend requests; their retained local/PostHog operations do not need an artificial asynchronous write queue.

Acceptance group: A7.


### IR-160

Legacy stored Try-asking suggestions and popup.

`resolved - delete the orphaned legacy suggestion store and Try-asking popup`

Remove `PostOnboardingPromptSuggestions`, its `UserDefaults` flags, popup lifecycle, and inputs that can no longer be populated after IR-154. Keep the IR-144 local completion-only Home opener and its retained local starter actions.

Acceptance group: A7.


### IR-161

Unreachable AI-driven onboarding chat engine.

`resolved - delete the unreachable AI-driven onboarding engine and its exclusive support code`

Remove `OnboardingChatView`, its private persistence, model-controlled completion/follow-up callbacks, onboarding-only prompts and tools, and tests that protect only this unreachable path. Preserve generic executors with retained callers, normal Chat/PTT, the `.onboarding()` journal isolation used by the live demo, and the fixed conversational `SBOnboardingView` lifecycle.

The legacy dependency audit now also has deterministic cleanup outcomes: remove obsolete `OnboardingChatPersistence` clear calls; delete the old local-file and legacy-language automation actions with IR-135/130/154; move the small shared language catalog out of the deleted coordinator without changing Settings behavior; extract the narrowed state cleanup under IR-155; and retain only the Firebase-name branch of the answer ordering gate under IR-159.

Acceptance group: A7.


### IR-162

Return-key default actions throughout retained onboarding.

`resolved - keep the current Return-key behavior unchanged`

Retain each applicable control's existing default-action or text-field submission wiring. Return must continue calling the same validated production handler as clicking the visible primary button; do not replace this with a flow-wide key monitor.

Acceptance group: A7.


### IR-163

Conversational onboarding auto-scroll.

`resolved - keep the current onboarding auto-scroll behavior unchanged`

Retain the existing bottom marker and the current triggers for completed messages, streaming text, widget appearance, and shortcut-rehearsal state. Do not add scroll-position tracking for the first release.

Acceptance group: A7.


### IR-164

Centered conversational-panel sizing.

`resolved - keep the current centered conversational-panel sizing unchanged`

Retain the 540-by-640-point maximum panel, centered placement, and compact available-space fallback. Do not stretch the transcript with the main window or introduce a separate onboarding window.

Acceptance group: A7.


### IR-165

Shared sign-in and onboarding backdrop.

`resolved - keep one shared backdrop across sign-in and onboarding, and require rebranding its bundled image`

Retain the continuous shared-backdrop behavior. Replace `signin_bg.png` with our own branded artwork before shipping; this is a required rebrand task, not an optional future polish item. Keep the asset local and shared rather than introducing separate sign-in and onboarding artwork.

Acceptance group: A7.


### IR-166

Animated fallback when the bundled backdrop is missing.

`resolved - keep the animated SBWallpaper fallback unchanged`

Retain the existing local gradient, animated-hills implementation as the shared fallback for sign-in and onboarding when the required bundled backdrop cannot be loaded.

Acceptance group: A7.


### IR-167

Emergency cleanup after shortcut rehearsal.

`resolved - keep the current on-disappear shortcut cleanup unchanged`

Retain the idempotent view-disappearance restoration of the saved app menu, temporary event monitors, and normal global shortcut registration.

Acceptance group: A7.


### IR-168

Cleanup of all retained temporary work when onboarding unexpectedly disappears.

`resolved - keep the current partial unexpected-disappearance cleanup unchanged`

Do not add a general view-disappearance teardown boundary. Retain only the existing shortcut restoration on `SBOnboardingView.onDisappear`; prompt streaming, permission polling, and live-demo cleanup remain owned by their existing normal navigation, Skip, completion, task, and object-lifetime paths.

Acceptance group: A7.


### IR-169

Vertical fallback for the top-right Back and Skip controls.

`resolved - keep the current horizontal-first and vertical-fallback Back/Skip layout unchanged`

Retain `ViewThatFits`, the normal top-right horizontal row, and the defensive vertically stacked alternative even though no current production window size is known to trigger it.

Acceptance group: A7.


### IR-170

Apple and Google sign-in choices.

`resolved - keep both Apple and Google sign-in choices, with no new account type`

Retain **Continue with Apple** and **Continue with Google**. Do not add email/password, magic-link, guest, or local-only account entry. Repoint both providers and the resulting Firebase identity to our own account project.

Acceptance group: A8.


### IR-171

Hosted browser OAuth plus Firebase custom-token exchange.

`resolved - keep the current hosted OAuth exchange and repoint it to our configuration`

Retain the browser/backend/Redis authorization session, provider callbacks, state and PKCE checks, loopback callback with custom-scheme fallback, single-use custom-token exchange, cancellation/timeout behavior, session fencing, and bounded diagnostics. Replace Omi's Apple, Google, Firebase, backend, and Redis configuration with ours.

Acceptance group: A8.


### IR-172

Unreachable native Apple sign-in alternative.

`resolved - keep the unreachable native Apple sign-in alternative unchanged`

Retain the private native Apple method, delegate, nonce/direct-Firebase path, native-only `FirebaseAuthAvailability` branch, Apple entitlement, local-signing entitlement removal, native-only errors and telemetry, and exclusive test even though the visible Apple button continues to use only the hosted browser flow.

Acceptance group: A8.


### IR-173

Fixed logo-only delay before sign-in controls appear.

`resolved - keep the fixed delayed sign-in reveal unchanged`

Retain the initial large spinning logo and Omi wordmark, the 1.4-second delay, and the subsequent 0.5-second transition that reveals the headline, claims, and Apple/Google buttons on every new `SignInView` presentation. The product name and logo still require normal rebranding.

Acceptance group: A8.


### IR-174

Sign-in marketing and architecture claims.

`resolved - keep the sign-in copy structure and require rebranded, fact-checked wording`

Retain the headline, supporting sentence, and compact footer positions. Replace the Omi name/logo and rewrite all visible promise, capture, follow-up, open-source, on-Mac, and pause wording against the final shipped architecture before release.

Acceptance group: A8.


### IR-175

Loading lock and user cancellation during browser sign-in.

`resolved - keep the current sign-in loading lock and callback-wait Cancel behavior unchanged`

Retain disabled Apple/Google buttons during `isLoading`, the progress indicator, the user-driven callback-wait cancellation, the five-minute abandoned-flow timeout, and the existing brief non-cancellable token-commit interval.

Acceptance group: A8.


### IR-176

Inline sanitized sign-in errors.

`resolved - keep the current inline sanitized sign-in failure behavior unchanged`

Retain silent user cancellation, the specific connection-recovery message, the generic safe sign-in fallback, display-time re-sanitization, inline placement, and immediate Apple/Google retry. Rebrand shared product-named error copy wherever it survives on other screens.

Acceptance group: A8.


### IR-177

Blocking validation of a saved account session at launch.

`resolved - keep the current launch-time saved-session validation gate unchanged`

Retain `.restoring` as a non-authenticated phase, the logo/spinner gate for accounts with a saved restore hint, credential validation before mounting authenticated or owner-scoped local UI, and direct Sign In presentation when no saved hint exists.

Acceptance group: A8.


### IR-178

Session recovery instead of destructive sign-out on transient validation failure.

`resolved - keep the current recoverable-session screen and light invalidation boundary unchanged`

Retain the fail-closed recovery screen, Retry with its in-button progress state, Sign In Again through light invalidation, definitive-death classification, per-owner directory routing, and preservation of onboarding/setup and owner-local data during credential recovery.

Acceptance group: A8.


### IR-179

Forced credential refresh when the app returns to the foreground.

`resolved - keep the current fail-closed foreground credential validation unchanged for the first release`

Retain the activation observer, 30-second debounce, shared single-flight refresh, authenticated transition on success, recovery routing on temporary failure, and light invalidation on definitive account death. Do not introduce offline-authorized local UI for the first release.

Acceptance group: A8.


### IR-180

Explicit Sign Out entry points and one-click presentation.

`resolved - keep both one-click Sign Out entry points unchanged`

Retain Sign Out in Account Settings and the signed-in status menu without adding a confirmation dialog. This does not decide the cleanup effects triggered by sign-out or the separate destructive Delete Account & Data flow.

Acceptance group: A8.


### IR-181

Stop active capture during explicit Sign Out.

`resolved - keep the current capture-shutdown behavior exactly as it is`

Retain the existing implementation without adding a later normalization requirement. Account Settings continues stopping transcription and proactive monitoring before sign-out begins. The status-menu action continues stopping proactive monitoring immediately and transcription after successful sign-out notification.

Acceptance group: A8.


### IR-182

Delete unsent local chat drafts during explicit Sign Out.

`resolved - keep clearing unsent local chat drafts on explicit Sign Out`

Retain `ChatDraftStore.clearAll(ownerID:)` in the explicit sign-out path. Temporary authentication recovery continues preserving drafts, and sent conversation/transcription/Rewind data remains outside this cleanup.

Acceptance group: A8.


### IR-183

Detach PostHog and Sentry identity during explicit Sign Out.

`resolved - keep the current PostHog and Sentry sign-out identity cleanup unchanged`

Retain the account-attributed `Signed Out` event followed by PostHog reset and Sentry user clearing. Repoint both SDKs to our own projects as already decided.

Acceptance group: A8.


### IR-184

User-facing Delete Account & Data control and confirmation.

`resolved - keep the user-facing Delete Account & Data control and confirmation`

Retain the destructive Account Settings row, Cancel/Delete Permanently confirmation, loading lock, inline error presentation, and successful transition into the explicit Sign Out lifecycle. Review the actual server and local deletion boundaries separately.

Acceptance group: A8.


### IR-185

Delete owner-scoped local data with the account.

`resolved - keep the current no-local-wipe behavior exactly as implemented`

After the server accepts deletion, retain the existing stop-capture plus ordinary Sign Out path. Do not add deletion of `users/<uid>`, local-agent history, or other normal owner-local product data. Keep the current Account Settings copy and confirmation text unchanged as part of this as-is decision.

Acceptance group: A8.


### IR-186

Remove rejected Omi product cleanup from the durable server-account worker.

`resolved - remove rejected Omi product cleanup from the retained durable worker`

Delete Twilio caller-ID deletion, Pinecone vector purges, GCS conversation-recording deletion, canonical cloud-memory cleanup, and their deletion-only dependencies/tests. Replace Stripe-specific cancellation with Dodo. Retain Firebase Auth deletion, recursive deletion of our retained Firestore account/billing/entitlement/usage data, the durable queue/retry/reconciliation lifecycle from IR-120, and privacy-bounded completion/failure telemetry.

Acceptance group: A8.


### IR-187

Account-deletion reason and free-text details with no Mac producer.

`resolved - delete the unused deletion-reason feedback surface`

Remove `reason` and `reason_details` from the account-deletion request/service contract and delete their feedback write. Retain `account_deletions/<uid>` as the durable operational job record with its job ID, status, timestamps, billing-failure state, retry/reconciliation queries, and completed/failed lifecycle.

Acceptance group: A8.


### IR-188

Minimal Firestore account control plane versus a fully local-only product.

`resolved - keep Firestore only as the minimal account control plane`

Retain Firestore for our Firebase account mapping, Dodo entitlement/subscription projection, centrally funded compute quota/usage, and durable account-deletion job state. Delete rejected Omi product-content collections and their sync/read/write paths. Transcripts, recordings, screen/OCR/embeddings, memories, goals, Focus, tasks, insights, settings, and local-agent history remain Mac-local authoritative.

Acceptance group: A8.


### IR-189

Sign out after deletion is durably accepted, before the worker finishes.

`resolved - keep immediate Sign Out after durable deletion acceptance`

Retain the current accepted-job response, immediate capture shutdown, ordinary Sign Out, and no polling/completion screen. The durable Cloud Tasks worker and reconciliation remain responsible for finishing Dodo cancellation, Firebase Auth deletion, and retained Firestore cleanup independently of the Mac.

Acceptance group: A8.


### IR-190

Indefinite completed account-deletion job records.

`resolved - keep completed account-deletion tombstones indefinitely as implemented`

Retain the completed status, opaque job ID, Firebase uid document identity, and lifecycle timestamps without adding `expires_at`, Firestore TTL configuration, or a cleanup job.

Acceptance group: A8.


### IR-191

Disabled-by-default three-day desktop trial system.

`resolved - keep the three-day trial system exactly as implemented and default it off`

Retain the Firebase-account-age clock, `GET /v1/users/me/trial`, 60-second Mac refresh, active/expired cards, countdown/progress, 24-hour/one-hour/expired nudges, paywall gates, debug modes, and tests. Keep `TRIAL_PAYWALL_ENABLED=false` as the default. Enabling it creates the existing three-day trial/expiry behavior; the separate ongoing free/basic tier remains governed by plan and monthly quota rules.

Acceptance group: A8.


### IR-192

Always-visible current-plan summary and billing management.

`resolved - keep the existing card behavior and adapt its provider/product data to Dodo`

Retain the loading state, fetched plan and status, price and billing interval, renewal/access-end date, hosted **Manage** action, **Refresh** action, and bounded inline errors. Replace Omi plan names, Stripe fields and portal wiring, Operator-to-Unlimited compatibility, and the already-rejected BYOK presentation with our Dodo subscription catalog and hosted portal. The server remains authoritative for the paid managed-compute entitlement.

Acceptance group: A8.


### IR-193

Omi legacy Plan Retiring migration card.

`resolved - delete the Omi-specific legacy migration card and contract`

Delete the Mac **Plan Retiring** card, its hard-coded Unlimited-to-Operator fallback copy and **Try Operator** action, the `deprecated` and `deprecation_message` subscription response fields in Swift and Python, and the dedicated contract test. This does not delete the ordinary Dodo current-plan card, paid-plan catalog, purchases, plan changes, or hosted billing management.

Acceptance group: A8.


### IR-194

In-app paid-plan catalog cards.

`resolved - keep the catalog-card interaction and adapt its data to Dodo`

Retain the side-by-side comparison cards, exclusion of the current plan, single selected card, and expansion to billing-interval choices. Replace Omi plan IDs, titles, copy, feature lists, ordering, platform/version filters, and Stripe prices with our server-provided Dodo offer. This decision does not yet settle exact plans/prices, promo codes, checkout presentation, or upgrade/downgrade rules.

Acceptance group: A8.


### IR-195

In-app promotion-code entry and validation.

`resolved - delete the product-owned promotion-code path`

Delete the Mac **Promo code** control and state, the `promotion_code` properties in checkout and plan-change requests, Stripe promotion lookup/application branches, and promotion-specific Mac/backend tests. Ordinary Dodo pricing, checkout, subscription changes, and the retained trial remain. A future discount requirement should use Dodo's hosted/provider-owned mechanism where possible instead of rebuilding this product-owned path by default.

Acceptance group: A8.


### IR-196

Hosted checkout inside a Mac WebKit sheet.

`resolved - keep the embedded provider-hosted checkout sheet and adapt it to Dodo`

Retain the `WKWebView` sheet, provider-owned payment page, **Close** behavior, same-view handling for new-window links, and exact success/cancel interception. Replace Stripe checkout URLs, redirect URLs, and provider-specific copy with Dodo. The Mac still does not collect or store payment-card details.

Acceptance group: A8.


### IR-197

Post-checkout subscription reconciliation poll.

`resolved - keep the bounded reconciliation poll and adapt its plan match to Dodo`

Retain up to eight server-authoritative subscription reads, spaced one second apart, the expected-plan match, successful plan/quota/paywall refresh, one reload on cancellation/dismissal, and bounded catch-up/failure messages. Replace the Stripe price comparison with the corresponding Dodo product or price identity. This is checkout-scoped verification, not persistent synchronization.

Acceptance group: A8.


### IR-198

Orphaned local checkout-completion simulator.

`resolved - delete the orphaned helper and both ineffective completion requests`

Delete `completeLocalTestSubscriptionIfNeeded()`, its call after checkout success, its extra localhost request to the static `/v1/payments/success` page, its request to the nonexistent desktop `/test/complete-subscription` route, and the helper-only `isLocalURL` if no other caller remains. Retain the actual success/cancel redirect routes, Dodo webhook-driven subscription update, and IR-197's verified subscription poll.

Acceptance group: A8.


### IR-199

Product-owned existing-subscription plan changes.

`resolved - delete the product-owned existing-subscription change path and use Dodo's hosted portal`

Delete the Mac `upgradeSubscription` request, its request/response types and routing tests, `/v1/payments/upgrade-subscription`, Stripe schedule-release and plan-change logic that becomes unreferenced, hard-coded downgrade policy, and Omi cloud-content unlock side effects. Keep the in-app catalog and hosted checkout for a free user's first paid subscription. Existing paid users use the retained Dodo **Manage** portal for plan, interval, payment-method, cancellation, and invoice management.

Acceptance group: A8.


### IR-200

Unreachable same-plan scheduled-cancellation reactivation.

`resolved - delete the unreachable same-plan cancellation reactivation branch`

Delete `_try_reactivate_subscription()`, its invocation inside first-purchase checkout, the special `reactivated` response validation and Mac handling, and dedicated reactivation tests. Keep `cancelAtPeriodEnd`/Dodo's corresponding cancellation state in the entitlement projection so the current-plan card still displays **Access ends on <date>**. Existing subscription changes remain under the retained Dodo **Manage** path.

Acceptance group: A8.


### IR-201

Duplicate plan-catalog fetch, local fallback reconstruction, and merge.

`resolved - keep only the rich Dodo-backed catalog in the subscription response`

Delete the Mac `getAvailablePlans()` request and response types, `fallbackPlanCatalog`, title-based plan normalization, hard-coded Omi fallback features/names/descriptions, `SubscriptionPlanCatalogMerger`, the separate `/v1/payments/available-plans` endpoint when no retained caller remains, and their dedicated tests. Retain the rich `available_plans` catalog returned by `/v1/users/me/subscription`, its partial-price resilience, and the IR-194 free-to-paid plan cards and checkout.

Acceptance group: A8.


### IR-202

Monthly managed-chat usage card and local preflight limiter.

`resolved - keep the usage card and shared local preflight; backend remains authoritative`

Retain the Account & Plan **Usage this month** card, loading/progress/reset/warning states, and the shared `FloatingBarUsageLimiter` used by Chat and PTT. Retain optimistic local increments for question-based limits, server-snapshot behavior for cost-based limits, and fail-open local behavior when no snapshot is available. Keep the backend usage ledger and quota enforcement authoritative. Delete BYOK exceptions under IR-062, and adapt plan names, caps, metered units, and final limit/overage messages when the commercial offer is decided.

Acceptance group: A8.


### IR-203

Paid-plan usage-based overage billing.

`resolved - delete unfinished paid-plan overage and hard-cap managed Chat at the included allowance`

Delete the Account & Plan overage card and explainer, `/v1/payments/overage-info`, `utils.overage`, the paid-plan quota bypass, provider-reference/markup copy, response models, and overage-only tests. Apply the server-authoritative quota rejection to paid plans as well as free users when their included managed-compute allowance is exhausted. Retain IR-202's usage card, near-limit warnings, reset date, shared local preflight, and backend usage ledger/enforcement. The exact included allowances remain a separate commercial-model decision.

Acceptance group: A8.


### IR-204

Static Privacy server-encryption card.

`resolved - keep the information surface, remove the fake Active state, and rewrite it for the final architecture`

Retain a simple data-location/security information card in Privacy. Remove the hard-coded green **Server-side encryption — Active** status and Omi's broad Google Cloud storage claim. Before shipping, rewrite the content to accurately distinguish local-authoritative product data, minimal Firebase/Dodo account and billing data, transient managed AI/STT compute, and any protection that is actually implemented and verifiable. Keep the Settings search entry only after its name/subtitle match that final content.

Acceptance group: A8.


### IR-205

Expandable What We Track disclosure.

`resolved - keep the disclosure and rewrite it from the retained PostHog/Sentry inventory`

Retain the simple expandable **What We Track** panel and its Settings search entry. After deletion, replace Omi's ten-item hard-coded list with an accurate plain-English summary of the analytics and diagnostic categories our PostHog and Sentry projects actually receive. Remove categories whose producers are deleted, include meaningful retained categories, and keep raw-content/privacy boundaries consistent with the real event payloads. Do not build a dynamic event browser.

Acceptance group: A8.


### IR-206

Static Privacy Guarantees card.

`resolved - delete the duplicate Privacy Guarantees card`

Delete the separate **Privacy Guarantees** card and its four absolute bullets. Do not move those claims elsewhere. The retained IR-204 data/security card and IR-205 telemetry disclosure must contain only facts supported by the final implementation and policy. Decide a real analytics/diagnostics opt-out independently under IR-207.

Acceptance group: A8.


### IR-207

User-facing analytics and diagnostics opt-out.

`resolved - add a local PostHog analytics toggle and keep Sentry diagnostics separate`

Add a Privacy-page **Share product analytics** toggle, enabled by default and persisted locally. Apply the saved choice before PostHog identification or event capture at startup, use the existing SDK opt-in/out seam, and correct or remove the inverted `hasOptedOut` helper and its automation projection. Turning the toggle off must stop PostHog product-analytics capture and detach analytics identity as supported by the retained SDK contract. It does not disable the separately retained privacy-bounded Sentry crash/error diagnostics. Explain that distinction in the IR-205 disclosure and keep beta-only enhanced diagnostics as a separate control.

Acceptance group: A8.


### IR-208

Beta-only Enhanced Diagnostics toggle.

`resolved - keep it as it is`

Keep the beta-production-only **Enhanced Diagnostics** toggle exactly as implemented: visible only in the beta bundle, enabled by default, persisted locally, and controlling inclusion of the bounded 50-entry typed beta trail. Preserve the current incident-attachment behavior in which disabling the toggle excludes that typed trail and substitutes the strictly filtered/redacted local-log tail. Keep baseline Sentry reporting, copy, privacy filters, and focused tests unchanged.

Acceptance group: A8.


### IR-209

In-app Report an Issue submission.

`resolved - keep it as it is`

Keep the current **Report an Issue** form and submission semantics unchanged. Preserve the description editor, optional name, prefilled email, explanatory copy, PostHog opened/submitted events and description-length property, generic Sentry **User Report** event, bounded/redacted diagnostics attachment, deliberate exclusion of the typed description/name/email from the upload, success state, and focused tests.

Acceptance group: A8.


### IR-210

Duplicate Report Issue entry points.

`resolved - keep it as it is`

Keep all three current entry points unchanged: the About card, the Advanced Troubleshooting card, and the signed-in status-menu command. Preserve both Settings search results, their current copy/styling, the shared singleton `FeedbackWindow`, opened-event behavior, and focused routing tests.

Acceptance group: A8.


### IR-211

Offline Save Diagnostics export.

`resolved - keep it as it is`

Keep **Save Diagnostics…** exactly as implemented: the standard save panel, user-chosen local destination, bounded metadata and health snapshots, final-512-KB/500-line recent-log limit, current common-secret/identifier redaction, rich remaining operational context, background file construction, offline/no-upload boundary, Finder reveal, copy, and focused tests. Rebrand the Omi filename/header identity later without changing behavior.

Acceptance group: A8.


### IR-212

Advanced Rescan Files troubleshooting card.

`resolved by dependency - delete with the rejected broad file-indexing lifecycle`

Delete the **Rescan Files** card, confirmation alert and view state, `.triggerFileIndexing` notification, `DesktopHomeView` observer, three-hour periodic rescan, delayed existing-user backfill, `hasCompletedFileIndexing` state/migration when no remaining caller needs it, Settings search entry, `FileIndexerService` and index storage after all IR-047/051 callers are removed, and focused tests/docs. Do not remove explicit Chat attachments, app-owned local persistence, or local AI Profile generation from its retained approved sources.

Acceptance group: A9.


### IR-213

Advanced Browser Extension card.

`resolved by dependency - delete with IR-048`

Delete the Advanced Browser Extension card, its view state/sheet, token display/reset/reconfigure actions, and Settings search result with the rejected Playwright lifecycle. Preserve the retained managed-Pi extension, `OMI_BRIDGE_PIPE` Unix-socket relay, Swift `ChatToolExecutor`, and scoped local product tools. The separate callerless `omi-tools-stdio` process is deleted by IR-015/S-05.

Acceptance group: A9.


### IR-214

Advanced Dev Mode card.

`resolved by dependency - delete with IR-049`

Delete the Dev Mode card, toggle and analytics event, injected `dev-mode` instructions, project/global dev-mode fallback handling, Settings search result, and exclusive tests/docs with the broad computer-agent execution slice. This does not decide whether ordinary non-development skills remain; that is a separate branch.

Acceptance group: A9.


### IR-215

AI Chat project Workspace selector.

`resolved - delete the project Workspace selector and project-level config discovery`

Delete both duplicate Workspace cards, their Settings search routing, `aiChatWorkingDirectory` preference/UI state, user-selected execution-profile working-directory reconfiguration, project CLAUDE.md reading/display, project skill discovery/catalog precedence, and project dev-mode fallback already rejected by IR-214. Future local agent sessions use the private app-managed artifacts directory. Keep explicit Chat attachments and their separate app-managed copies. Do not delete global skills under this decision.

Acceptance group: A9.


### IR-216

Global `~/.claude/CLAUDE.md` reference card.

`resolved - delete the global CLAUDE.md reference card and reader`

Delete the AI Chat Settings CLAUDE.md card, `~/.claude/CLAUDE.md` startup/settings disk reads, published and local content/path state, this file's read-only viewer route, and focused tests that exist only for the reference. Do not inject the file into Chat as a replacement. Do not delete global skills under this decision.

Acceptance group: A9.


### IR-217

Global `~/.claude/skills` extension system.

`resolved - delete the Claude Code skills compatibility layer`

Delete automatic `~/.claude/skills` scanning from Swift and Node, the AI Chat Skills card and full-file viewer route, local disabled-skill-name state, compact skill-catalog context projection and guidance, `search_skills`/`load_skill` tool declarations/executors/policies, pi-mono compatibility implementation, generated manifests/capabilities, and exclusive tests/fixtures/docs. Keep the local Node/pi agent runtime and every separately retained typed task, goal, memory, conversation, Rewind, and search tool.

Acceptance group: A9.


### IR-218

Optional AI Chat Ask/Act mode.

`resolved - keep it exactly as it is with no repair`

Keep the optional Settings card, default-off `askModeEnabled` preference, conditional composer Ask/Act switch, default Act state, per-turn mode plumbing, current SQL-only Ask check, all retained write tools that are not mode-gated, existing read-only user-facing claim, and focused tests exactly as implemented. Do not expand enforcement to other tools and do not present this decision elsewhere as a verified global safety boundary.

Acceptance group: A9.


### IR-219

Persistent Show floating bar preference.

`resolved - keep it exactly as implemented`

Keep the default-enabled local `askOmiBarEnabled` preference, Settings toggle, bar-owned Hide action, normal signed-in launch presentation, hidden-state PTT reveal/re-enable, temporary proactive-notification reveal/re-hide, independent Snooze state, and existing tests exactly as implemented.

Acceptance group: A9.


### IR-220

Floating bar transparent/solid background choice.

`resolved - keep it exactly as implemented`

Keep the transparent default, Solid Dark option, local `shortcut_solidBackground` persistence, immediate shared-modifier update, HUD blur/overlay implementation, opaque dark implementation, and common clipping/border behavior exactly as implemented.

Acceptance group: A9.


### IR-221

Optional draggable floating-bar mode.

`resolved - keep it as it is`

Keep the default-off `draggableBarEnabled` preference, Settings toggle, draggable-area events, saved local coordinates, draggable pill presentation on notched displays, exact pre-expansion restoration, canonical compact positioning, multi-display proportional translation/clamping, monitor/Space validation, off-screen recovery, and focused geometry/lifecycle tests exactly as implemented.

Acceptance group: A9.


### IR-222

Spoken answers for typed floating-bar questions.

`resolved - keep it exactly as implemented`

Keep the default-off local `floatingBarTypedQuestionVoiceAnswersEnabled` preference, complete visible response when off, filler and streaming answer playback through the existing voice pipeline when on, shared selected voice/speed, interruption and stale-owner lifecycle, system-speech fallback, focused tests, and the invariant that PTT replies remain spoken independently.

Acceptance group: A9.


### IR-223

Screen Sharing in ordinary typed Chat.

`resolved - keep it as it is with no repair`

Keep the default-on local `chatScreenshotSharingEnabled` preference, Settings card/copy, `capture_screen` and `get_screenshot` precondition checks, the automatic typed floating-bar relevance heuristic and direct screenshot attachment that does not read the preference, and the separately exempt PTT screenshot path exactly as implemented. Do not repair or broaden enforcement.

Acceptance group: A9.


### IR-224

Floating-bar spoken-answer voice selector.

`resolved - keep it exactly as it is with no deferral`

Keep Onyx, Shimmer, Coral, and Nova as the complete visible catalog; Shimmer as default and invalid-value fallback; the local selected ID; immediate “Hey, how is it going?” sample; background-agent phrase prewarm; authenticated managed `POST /v1/tts/synthesize` OpenAI route; voice-specific instructions; and macOS system-speech failure fallback exactly as implemented. Do not defer or adapt this requirement in the later provider audit.

Acceptance group: A9.


### IR-225

Floating-bar voice playback-speed control.

`resolved - keep it exactly as implemented`

Keep the six steps (`0.8×`, `1.0×`, `1.2×`, `1.4×`, `1.6×`, `2.0×`), 1.4× default, Faster/Slow/Max labels, stepped slider, haptics, local persistence, `AVAudioPlayer` rate application for generated audio, and fixed `AVSpeechUtterance` fallback rate exactly as implemented.

Acceptance group: A9.


### IR-226

Main-window font-scale control.

`resolved - keep it exactly as implemented`

Keep the 50–200% range, 5% steps, 100% default, local `fontScale` persistence, percentage and preview UI, haptics, conditional Reset, `⌘+`/`⌘-`/`⌘0` commands, shared environment injection, and current scaled-text/main-window boundary exactly as implemented.

Acceptance group: A9.


### IR-227

Reset Window Size action.

`resolved - keep it exactly as implemented`

Keep both Settings and app-menu entry points, `NSApp.keyWindow`-first target selection, fallback title search, fixed 1200 × 800 frame, current-center preservation, animation, normal/Rewind mismatch, lack of visible-screen clamping, and current tests exactly as implemented.

Acceptance group: A9.


### IR-228

Local VAD Gate transcription setting.

`keep Local VAD Gate behavior exactly as implemented with no repair; replace only a retired provider noun`

Retain the **Local VAD Gate** card, Settings search entry, `vadGateEnabled` preference/state, transcription-restart side effect, `VADGateService`, model/resource, diagnostics, focused tests, and the meaning of the existing explanatory copy. Do not delete the feature and do not wire or repair it under this decision. Because IR-889 retires Deepgram completely, replace only “Deepgram API usage” with “managed cloud transcription usage”; this wording adaptation does not change Local VAD Gate behavior. The Python `/v4/listen` receiver's independently configured VAD and the PTT silence/noise admission gate remain separate.

Acceptance group: A9.


### IR-229

Notifications master switch and delivery-frequency slider.

`keep the Notifications master/frequency behavior locally and delete synchronization`

Remove Settings hydration/PATCH calls, Firestore `notifications_enabled` and `notification_frequency` ownership, and the migration's backend push. Preserve the concrete UI and local delivery behavior. This is a code-level closure of IR-037, not a new product choice.

Acceptance group: A9.


### IR-230

Per-assistant switches inside the Notifications card.

`keep the per-assistant notification switches locally and delete synchronization`

Preserve the current switches, labels, defaults, local persistence, immediate runtime effects, and retained notification generation. Remove the assistant-settings push calls from this card and cloud hydration that can overwrite these values. This closes the concrete Notifications UI under IR-035/036 without reopening the assistants.

Acceptance group: A9.


### IR-231

Daily Summary Settings card.

`delete the Daily Summary Settings card`

Remove the card, toggle, time picker, view state/defaults, GET/PATCH settings methods and models, and the **Daily Summary**/**Summary Time** Settings search entries with the IR-039 slice. Retain ordinary local notifications and the separately approved Insight, Focus, Profile, Memory, Task, and Live Suggestions behaviors.

Acceptance group: A9.


### IR-232

Rewind local Storage information card.

`keep the local Rewind Storage card unchanged`

Retain the read-only local frame count, screenshot/video disk-usage calculation, **Loading...** state, formatting, card, and Settings search entry exactly as implemented. Do not expand this decision into new reveal, deletion, or storage-breakdown controls.

Acceptance group: A9.


### IR-233

Rewind global Excluded Apps privacy control.

`keep Rewind Excluded Apps exactly as implemented`

Retain the default Omi/password-manager exclusions, exact-name checks, user additions from text or running apps, removal of defaults, explicit-removed-default persistence, future-default merging, Reset to Defaults, local `UserDefaults` authority, pre-indexer capture rejection, downstream proactive-assistant inheritance, Settings card/search entry, and focused privacy tests exactly as implemented.

Acceptance group: A9.


### IR-234

Automatic Rewind battery optimization and information card.

`keep the automatic battery optimization and its information card exactly as implemented`

Retain the automatic three-times-slower battery capture cadence, power-source monitoring, active-chunk flush and timer restart, encoder-rate adaptation, accurate OCR behavior, static **Battery Optimization — Automatic** card, explanatory copy, Settings search entry, diagnostics, and focused tests exactly as implemented.

Acceptance group: A9.


### IR-235

Rewind local Data Retention setting and cleanup.

`keep the main local Rewind Data Retention behavior exactly as implemented`

Retain the main 3/7/14/30-day picker, seven-day default, `rewindRetentionDays` local persistence, frame-triggered maximum-once-per-six-hours cleanup, GRDB row deletion, legacy-JPEG deletion, orphaned-video-chunk deletion, empty-directory cleanup, asynchronous failure behavior, card, search entry, and focused tests exactly as implemented. Do not add immediate/scheduled cleanup or broaden this window to other local data under this decision. The separate Rewind-only Settings entry remains part of IR-236.

Acceptance group: A9.


### IR-236

Separate command-line Rewind-only launch mode.

`keep the command-line Rewind-only mode and legacy view exactly as implemented`

Treat this slice as retained agent/dev/testing infrastructure. Preserve `--mode=rewind`, the launch-mode parser and enum, Rewind initial selection, mode-specific title/size/menu-bar icon and tooltip, mode-scoped single-instance lock and concurrent full/rewind allowance, tests, and the currently unmounted `RewindOnlyView` with its duplicate Settings UI exactly as implemented. Do not delete or repair this branch under the requirements challenge.

Acceptance group: A9.


### IR-237

Phantom Rewind Settings search results.

`delete the three phantom Rewind Settings search results`

Remove only the **Rewind**, **Screen Capture**, and **Audio Recording** entries from the Settings search catalog. Retain the normal Rewind history page, Rewind Settings category and its four real searchable cards, menu-bar/top-level screen-capture and audio-listening controls, their local state, and every retained capture/transcription lifecycle.

Acceptance group: A9.


### IR-238

Phantom generic Transcription Settings search result.

`delete only the phantom generic Transcription Settings search result`

Remove only the **Transcription Settings — Configure speech-to-text options** catalog entry targeting `transcription.settings`. Retain the Language Mode, Voice Assistant Languages, Custom Vocabulary, and Local VAD Gate cards, their valid search entries/targets, and every behavior previously retained under IR-023/071/228.

Acceptance group: A9.


### IR-239

Phantom General Settings search results.

`delete the three phantom General Settings search results`

Remove only the General catalog entries **Rewind — Screen capture and audio recording**, **Ask omi — Show or hide the floating chat bar**, and **Reset Window Size — Restore the default window dimensions**. Retain the real General Screen Capture and Audio Recording cards, the Floating Bar **Show floating bar** card and valid search entry, the Font Size card, the working Reset Window Size button/menu command, and all previously retained behavior.

Acceptance group: A9.


### IR-240

Privacy search entries for rejected cloud recording controls.

`delete both search entries with IR-122`

Remove **Store Recordings** and **Private Cloud Sync** from the Settings search catalog when their card is removed. This does not affect transient microphone/system-audio capture for STT, local transcripts, PTT, or Rewind.

Acceptance group: A9.


### IR-241

Sign Out Settings search result.

`delete only the broken Sign Out Settings search result`

Remove only the **Sign Out — Sign out of your omi account** Settings search catalog entry targeting `account.signout`. Retain the Account card and its valid search entry, the one-click Account Sign Out button, the signed-in status-menu Sign Out item, and their exact retained lifecycle under IR-180/181.

Acceptance group: A9.


### IR-242

Phantom generic Plan and Usage search result.

`delete only the phantom generic Plan and Usage search result`

Remove only the **Plan and Usage — Subscription status and usage limits** search catalog entry targeting `planusage.overview`. Retain **Current Plan** and **Upgrade Plan** search results/targets and every approved account, Dodo entitlement, usage, checkout, portal, and billing behavior. Rewrite surviving plan names/keywords during the Dodo/product rebrand rather than preserving Omi's Stripe/Architect/Operator vocabulary.

Acceptance group: A9.


### IR-243

Manual Sparkle update check and recovery UI.

`keep the manual update and recovery behavior; repoint it to our release infrastructure`

Retain **Check Now** in About Settings and the status menu, shared Sparkle execution, duplicate-session gating, last-check display, classified failure diagnostics, **Open Applications**, **Download Latest**, **Dismiss**, named-development/preview isolation, and focused tests. Replace Omi's appcast, `api.omi.me/v2/desktop/download/latest` fallback, release links, signing/update keys as required, and visible product branding with our controlled release infrastructure before shipping.

Acceptance group: A9.


### IR-244

Forced automatic Sparkle check/download policy.

`keep the automatic check/download policy exactly as implemented`

Retain the forced-on production automatic-check/download values, forced-off development behavior, disabled explanatory switches, immediate launch check, Stable ten-minute interval, Beta two-minute interval, named-preview isolation, PostHog setting telemetry, copy, and focused tests exactly as implemented. Point the feed/artifacts to our retained release infrastructure under IR-243. Installation timing remains separate under IR-245.

Acceptance group: A9.


### IR-245

Immediate silent update installation/relaunch and conversation gate.

`keep immediate installation/relaunch, but repair the gate using authoritative retained activity state`

Retain the published-build immediate installation block, development-build install-on-quit behavior, background-versus-window restoration, intended-build verification, bounded update telemetry, and relevant focused tests. Before invoking the release installer, use one local installation-admission seam driven by the existing authoritative lifecycle state for retained meeting transcription, PTT, and active Chat/model or tool work; wait until those activities are idle, then install and relaunch. Remove `VADGateService.lastSpeechAt` as the sole authority for this decision and remove or adapt the now-obsolete exclusive coupling in `DeferredUpdateInstall`. Do not wire up or repair the disconnected Local VAD feature: IR-228 still keeps it exactly as it is.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-246

Stable/Beta user choice and per-user Firestore authority.

`keep the existing Stable/Beta behavior, but make the user's preference local-authoritative`

Retain the normal production app's Stable/Beta picker, local `UserDefaults` persistence, first-launch inference, legacy-value normalization and justified migration, Beta label, immediate check after selection, Stable/Beta polling behavior, bounded PostHog/Sentry channel dimensions, Beta-production-bundle pinning, downgrade warning, and focused release-safety tests. Repoint the Omi stable-download URL under IR-243.

Delete the per-user `users/{uid}.update_channel` Firestore field and its special assistant-settings GET/PATCH injection, Swift response-model field, server-authoritative hydration, incidental full-settings upload, and focused synchronization tests. This also closes the update-channel exception left by IR-036. Do not delete or localize the separate backend `desktop_update_channels` release documents, channel manifests/pointers, promotion controls, or Sparkle feed resolution: those publish which signed build is Stable or Beta and remain required release infrastructure.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-247

About app-identity and version card.

`keep the card and rebrand its identity`

Retain the About identity/version card's layout, locally derived Beta label, selectable `CFBundleShortVersionString` and `CFBundleVersion`, graceful behavior if the artwork resource is unavailable, and valid **Version Info** Settings search result. Replace `herologo.png` and the hard-coded **omi** name with our product identity before shipping. The adjacent release, website, support, privacy, and terms links remain independent requirements.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-248

About manual What's New release-notes link.

`keep the version-aware link and repoint it to our release repository`

Retain the About **What's New** row, default-browser opening, `v<version>+<build>-macos` tag construction, correct `+` path encoding, exact running-build deep link for published production bundles, and general releases-list fallback for development/named builds. Replace `https://github.com/BasedHardware/omi/releases` with our release repository and preserve release/tag compatibility with the retained packaging pipeline. The automatic post-update toast remains independently undecided.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-249

Automatic post-update What's New toast.

`keep the automatic post-update toast and rebrand it`

Retain the main-window overlay, signed-in gate, local `whatsNewLastShownBuild` baseline, fresh-install suppression, larger-build detection, one-time presentation, hidden-window update-relaunch suppression, 2.5-second launch delay, installed-version copy, exact IR-248 release link, whole-card open action, close action, 12-second auto-dismiss, fallback artwork behavior, animation, and relevant focused tests. Replace **omi updated**, Omi artwork, and inherited release ownership with our product identity.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-250

About Visit Website link.

`keep the Visit Website row and repoint it to our website`

Retain the About **Visit Website** row, its placement, shared `linkRow` presentation, URL validation, and default-browser opening. Replace the inherited `https://omi.me` destination with our public product website before shipping. Do not infer a retained Help Center, Privacy Policy, or Terms surface from this decision.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-251

About external Help Center link.

`delete the external Help Center row for the first ship`

Delete the About card's **Help Center** `linkRow`, hard-coded `https://help.omi.me` destination, and any focused UI assertion that requires this row. Do not create a replacement external help-center platform or placeholder link merely to preserve the inherited layout. Do not delete or modify the separate in-app Crisp Help webview, unread polling/badge, operator-reply notifications, backend route, already-retained Report an Issue flow, or Save Diagnostics behavior under this decision; those survive or fall through their own audits.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-252

About internal Privacy navigation mislabeled as Privacy Policy.

`keep the local shortcut, but rename it Privacy & Data`

Retain the About card's local button, arrow presentation, and direct `selectedSection = .privacy` navigation to the retained Privacy settings/disclosure page. Rename **Privacy Policy** to **Privacy & Data** or final equivalent wording that accurately describes the destination. Do not convert this shortcut into a browser link or treat the in-app page as the company's legal privacy policy. Audit the separately hosted legal policy on its own.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-253

About Terms of Service link and acceptance boundary.

`keep the simple Terms of Service link and repoint it to our document`

Retain the About **Terms of Service** row, shared `linkRow` presentation, URL validation, and default-browser behavior. Replace `https://omi.me/terms` with our hosted legal terms before shipping. Do not add an acceptance checkbox, version/timestamp state, sign-in/checkout gating, re-consent policy, Firestore field, or backend ledger under this decision. Delete the unrelated Omi legal footer with the rejected hosted public MCP/OAuth template under IR-015 rather than adapting it for a product that no longer survives.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-254

In-app Crisp founder-support chat and reply polling.

`delete the entire Crisp support slice for the first ship`

Delete `HelpPage`/`CrispWebView`, the unreachable Help navigation enum/route and automation target, hard-coded Omi Crisp website ID, name/email webview query projection, `CrispManager`, signed-in startup/activation/Cmd+R polling and sign-out cleanup, local Crisp timestamps/deduplication/unread state, unused sidebar observation, Crisp reply floating notifications/copy, authenticated Python `GET /v1/crisp/unread` route, email-to-session cache and Crisp API helpers, `CRISP_PLUGIN_IDENTIFIER`/`CRISP_PLUGIN_KEY`/`CRISP_WEBSITE_ID` configuration, and exclusive Swift/Python tests and startup-delay expectations. Remove only the Crisp portion from the mixed `desktop_screen_crisp.py` module while deleting the rejected screen-activity slice under its own earlier decision. Retain Report an Issue, Save Diagnostics, Sentry/PostHog, website/legal links, and generic notification infrastructure.

No product-code change is authorized yet.

Acceptance group: A9.


### IR-255

User-selectable old Home design compatibility mode.

`delete the old Home compatibility mode and audit the surviving current shell item by item`

Confirmed: remove the **Use old Home design** toggle, `useLegacyHomeDesign` preference and branches, old chat-first `legacyHome`, old expandable `SidebarView`, and code/state/tests used only by that presentation. Keep the current redesigned Home and top-bar shell as the single supported UI.

This decision does not automatically keep every item currently shown in the surviving top bar or Home. Audit those current surfaces separately against earlier product decisions. In particular, IR-046 and IR-047 already leave the current **Apps** page with no surviving marketplace, import, or export role, so the **Apps** top-bar item, page, provider/startup work, Home connection shortcuts, sheets, and exclusive state are already marked for deletion. Focus, Insights, Rewind, Memory, Tasks, capture/listening, Settings, and their discoverability remain governed by their own requirements and must not be deleted merely because the old sidebar is removed.

The traversal after this decision covers the **entire surviving customer UI**, not only the new top bar or one destination page. Use the active code as the map and walk every reachable branch: `DesktopTopBar`; the complete redesigned `DashboardPage`; Memory/Memories/Conversations/Brain Map; Tasks; Focus/Insights; Rewind; every Settings section; status-menu controls; floating Chat/PTT and proactive overlays; notifications and update announcements; plus their sheets, popovers, context menus, empty/loading/error states, shortcuts, and background side effects. Auth and onboarding remain part of the same full UI graph but reuse their many already-recorded decisions. When a parent feature is already deleted, close every UI entry point and exclusive child by dependency instead of questioning each orphan as though its parent survived.

Acceptance group: A9.


### IR-256

Current Memory top-bar hub and Brain Map.

`delete Brain Map and the complete knowledge-graph slice by dependency`

Confirmed: retain the locally authoritative Memories and Conversations products, but remove **Brain Map** from the current Memory menu and persisted destinations; delete both the canonical Memory Atlas and legacy SceneKit graph presentations; server capability/cohort routing and fallback telemetry; `/v1/knowledge-graph` read/rebuild/delete APIs and backend generation/jobs/storage; local `local_kg_nodes`/`local_kg_edges`, `KnowledgeGraphStorage`, `save_knowledge_graph`, callbacks and generated tool exposure after the deleted file/onboarding callers are removed; graph-specific prompts, analytics, automation, caches, models, assets, tests, and documentation.

This closes the same knowledge-graph product across its two old data paths: broad file/onboarding exploration was already deleted under IR-135/051/161/212, and the hosted memory-derived graph loses its source under IR-024. Do not design a replacement local memory-to-graph generator merely to preserve the visualization.

Acceptance group: A10.


### IR-257

Current top-bar switching between Memories and Conversations.

`keep the existing Memory grouping and behavior after removing Brain Map`

Confirmed: retain the single **Memory** top-bar item, direct click into locally authoritative Memories, the existing delayed hover menu with Conversations as its sole child, the nested compact-navigation equivalent, local destination persistence, Cmd+2/automation routing to Conversations, pointer-transit protection, accessibility behavior, and focused tests. Remove only Brain Map and its routing under IR-256; do not redesign this into two top-bar buttons or an in-page segmented control.

Acceptance group: A10.


### IR-258

Memories-page This device filter.

`delete the This device filter by dependency`

Confirmed: remove the Memories-header **This device** pill; `filterThisDeviceOnly` state and reload branches; `/v3/memories` `device_scope=current` parameter; `X-Omi-Memory-Device-Scope-Supported` capability parsing/cache; unsupported-account 400 retry and fallback telemetry; list-time current-device matching used only by this filter; and exclusive tests/copy. Retain capture/source provenance fields only where another approved local behavior uses them. Do not replace this control with a differently defined source filter.

Acceptance group: A10.


### IR-259

Memory Public/Private visibility and shareable persona controls.

`delete memory Public/Private visibility and shareable-persona controls by dependency`

Confirmed: remove per-memory **Public** chips, **Make public…** confirmation and shareable-persona copy, **Make private**, bulk public/private menu commands, visibility toggle/loading state, `/v3/memories/{id}/visibility` and bulk visibility APIs, backend-ID-based local mirror helpers, `toggle_memory_visibility` automation, visibility-specific errors/prompts/generated contracts, and exclusive tests. Remove the local visibility field once remaining compatibility/decoding callers are migrated; retained memories are local/private by architecture rather than by a user-toggleable string. Keep per-memory deletion and leave bulk deletion for its own requirement.

Acceptance group: A10.


### IR-260

Memory Short-term, Long-term, and Archive lifecycle.

`keep the same Short-term, Long-term, and Archive behavior but make it local-authoritative`

Confirmed: retain the canonical **Default / Short-term / Long-term / Archive** filter; Default exclusion of Archive; row badges and explanations; Short-term expiry metadata; corroboration/model-based promotion semantics; expiration and archive transitions; tier-scoped reads/search/bulk safeguards; explicit Archive access/acknowledgement; deterministic transition records, idempotency, owner isolation, cancellation, and recovery behavior that protect the current cloud lifecycle.

Move authority and execution to this Mac: local GRDB owns tier, expiry, promotion/archive state, transition/audit records, and mutation results. Port the existing behavioral policy and safety pattern into a local lifecycle runner using retained managed model compute where judgment is required. Remove `/v3/memories` authority/sync, Firestore lifecycle state, server cohort capability/header and canonical-versus-legacy split, hosted schedulers/workers, and cloud reconciliation. The retained canonical local experience applies to this product's users without an Omi rollout cohort. IR-710 pins explicit Add/Edit normalization to OpenAI GPT-4.1-mini `memory_l2`, while IR-730 pins evidence-backed consolidation to OpenAI GPT-4.1-mini `memory_conflict`; the Mac remains lifecycle authority.

Acceptance group: A10.


### IR-261

Workflow memory category.

`delete the Workflow memory category by dependency`

Confirmed: remove `MemoryCategory.workflow`, the matching `MemoryTag.workflow`, **Workflow** filter/count/icon/label rendering, local query branches, generated/wire compatibility after old-schema migration is no longer needed, and exclusive tests/copy. Retain **About You**, **Insights**, and **Manual** with their existing local producers and category semantics. Do not expand local extraction merely to recreate a fourth inherited category.

Acceptance group: A10.


### IR-262

Search field inside the Memories category popover.

`delete the category-name search field only`

Confirmed: remove **Search categories…**, its icon and inline clear button, `categorySearchText`, category-name filtering, and exclusive assertions. Keep the main **Search memories** field unchanged. Keep the category rows, counts, staged multi-selection, **All**, **Clear**, and **Apply** pending IR-263 rather than deciding them implicitly.

Acceptance group: A10.


### IR-263

Memories category staged multi-selection and counts.

`keep the existing category multi-select behavior unchanged`

Confirmed: retain **All**, total/per-category local counts, simultaneous About You/Insights/Manual selection, checkmarks, staged `pendingSelectedTags`, **Clear**, **Apply**, popover dismissal behavior, combined category-plus-text filtering, bounded local pagination, and focused tests. No cloud synchronization or hosted category authority is introduced.

Acceptance group: A10.


### IR-264

Main Search memories field.

`keep the main Search memories behavior unchanged`

Confirmed: retain the **Search memories** field; 250-millisecond non-empty debounce and immediate clear; superseded-task cancellation; trimmed-query and scope-generation fencing; case-insensitive local GRDB content matching; deleted/dismissed exclusion; locally authoritative tier and selected-category composition; progress indicator; newest-first ordering; in-memory fallback on database failure; batches of 100 and **Load more memories**; empty-result UI; and focused tests. Do not replace this visible-list search with model/vector search; IR-095's semantic recall remains separate.

Acceptance group: A10.


### IR-265

Add Memory sheet and manual-memory creation lifecycle.

`keep Add Memory and adapt the existing lifecycle locally`

Confirmed: retain the header **+** button, empty-state **Add Your First Memory** action, current `AddMemorySheet`, Manual/user-asserted classification, readable Short-term submission, required local processing, durable Long-term outcome, idempotent transition records, retry/recovery safety, and focused tests. Make GRDB and the retained local lifecycle runner authoritative. Remove the hosted `POST /v3/memories`, legacy Firestore/vector write, backend acceptance/reload, cache synchronization, and sync-shaped ownership from this path. Provider selection remains deferred to the reserved Gemini/OpenAI model branch.

Acceptance group: A10.


### IR-266

Add Memory acceptance timing and failure presentation.

`keep the current interaction and adapt only the local acceptance boundary`

Confirmed: close the sheet, clear the draft, and refresh the locally authoritative list immediately after the atomic local Short-term submission/lifecycle transaction commits. Do not wait for model normalization or durable Long-term admission; run that work in the retained background local lifecycle with its retry/recovery rules. If initial local acceptance fails, retain the open sheet and exact draft, log the failure through the retained privacy-bounded diagnostics, and add no new saving, success, or visible error state. Preserve idempotent submission handling if Save is invoked more than once.

Acceptance group: A10.


### IR-267

Memories ellipsis menu and bulk Delete Default Memories.

`keep bulk Delete Default Memories and make it local`

Confirmed: remove the Visibility heading, both Make Default Memories Private/Public actions, their view-model functions, server visibility API calls, and related tests under IR-259. Retain the ellipsis control and a single **Delete Default Memories** action. Enable it whenever applicable against local authority; preserve destructive confirmation, Short-term+Long-term scope, Archive exclusion, explicit Archive safeguards in lower layers, cancellation of any pending single-memory Undo lifecycle, one local GRDB soft-delete transaction, in-progress/error handling, local reload/count invalidation, and focused tests. Remove `bulkServerMutationsAvailable`, its disabled-state help copy, the hosted `DELETE /v3/memories`, server-first sequencing, and synchronization from this path.

Acceptance group: A10.


### IR-268

Memories initial loading and failed-load Retry states.

`keep Loading and Retry, but adapt the failure state to local authority`

Confirmed: retain the blocking initial circular progress state and **Loading memories...** copy; retain the warning icon, **Failed to Load Memories**, and **Retry** recovery action. Replace **Check your connection and try again.** with neutral local-accurate copy such as **Unable to load memories. Try again.** Retry only the locally authoritative GRDB open/query/projection lifecycle—no API fetch, cache fallback, capability check, or synchronization. Continue hiding raw technical errors from the product UI while recording privacy-bounded local diagnostics in the retained PostHog/Sentry/logging setup.

Acceptance group: A10.


### IR-269

Memories true-empty state and source explanation.

`keep the empty state but rewrite its source explanation`

Confirmed: retain the generic brain SF Symbol, **No Memories Yet**, centered empty-state layout, and **Add Your First Memory** entry into the existing sheet. Remove the legacy “memories and tips” and conversations-only explanation. Replace it with concise architecture-accurate copy such as **Memories you add and insights learned from your conversations and activity will appear here.** Revalidate the final wording against the retained local writers and final product brand; do not add a new category or source merely to satisfy the copy.

Acceptance group: A10.


### IR-270

Memories No Results state and scoped clearing.

`keep the No Results state unchanged`

Confirmed: retain the magnifying-glass icon, **No Results**, **Try a different search or filter**, and the conditional **Clear Filters** action. Continue showing this state only when the authoritative local scope contains memories but the composed local projection is empty. Clear Filters removes selected About You/Insights/Manual categories only; preserve the text query and Short-term/Long-term/Archive choice, whose existing visible controls remain responsible for their own reset. Keep the state and tests entirely local with no API dependency.

Acceptance group: A10.


### IR-271

Memories list pagination, prefetch, and hosted exhaustion fallback.

`keep the pagination experience and make it local-only`

Confirmed: retain newest-first 100-row paging for the normal Default/Short-term/Long-term/Archive views; final-ten `onAppear` prefetch; explicit **Load more memories** fallback; **Loading more...** feedback; stale-scope/cursor fencing; and IR-264's 100-row bounded reveal of local search/category results. Query only authoritative GRDB, and end a scope when the local page contains fewer than 100 rows. Remove hosted page fetches, `rawBackendOffset`, device/lifecycle capability commits, server-page synchronization, cloud fallback logs/errors, `performFullSyncIfNeeded`, `reconcileCacheIfNeeded`, per-user completion keys, and exclusive API/cache-source-of-truth tests.

Acceptance group: A10.


### IR-272

Memory-card info-circle hover metadata preview.

`keep the info-circle hover preview exactly as it is`

Confirmed: retain the inline info icon; pointer-entry behavior; popover-hover protection; 250-millisecond delayed dismissal; Layer/Expires/Category/Subcategory/Tags/App/Source/Window/Context/Activity/Confidence/Reasoning/Created rows; and its independent rendering/state/tests. Keep the current duplicate `Text(value)` rendering in `tooltipRow` unchanged. Do not delete, reduce, or repair this surface merely because the persistent detail panel contains overlapping information.

Acceptance group: A10.


### IR-273

Memory-content `[Protected…]` / `[Encrypted…]` placeholder compatibility.

`delete the memory placeholder-string compatibility branch`

Confirmed: remove the literal prefix checks and **Protected memory** substitution from `MemoryCardView` and `MemoryDetailPanel`, plus memory-specific compatibility assertions/tests. Render and edit the actual content stored in authoritative local GRDB. This decision neither adds nor removes encryption, changes local file protection, nor claims that the database is encrypted; the deleted branch performed no cryptography. Do not carry this decision into Chat's separately implemented session-preview compatibility until that branch is audited.

Acceptance group: A10.


### IR-274

Memory capture-device provenance labels and stored device-ID arrays.

`delete memory-specific capture-device provenance by dependency`

Confirmed: remove the memory-card and detail-panel **This Mac/Mac/iPhone/Android** labels; `primaryCaptureDevice`/`captureDeviceIds` from memory models, local schema after migration, API decoding, and cache conversion; device matching/filter residue; and exclusive tests. Retain app/source/window/manual/microphone/confidence/conversation provenance and its local presentation. Do not delete shared `ClientDeviceService` through this decision; audit its remaining non-memory callers separately.

Acceptance group: A10.


### IR-275

One-minute New badge and highlight on memory cards.

`keep the one-minute New treatment exactly as implemented`

Confirmed: retain the 60-second computed condition, shared **New** badge, subtle highlighted card background, natural SwiftUI-refresh expiry, and focused tests. Add no per-row timer or repair work.

Acceptance group: A10.


### IR-276

Whole-card click opening the persistent right-hand memory inspector.

`keep the card-to-inspector shell unchanged`

Confirmed: retain the full-row button target, raised hover surface, pointing cursor, diagonal-arrow affordance, 360-point right-hand `MemoryDetailPanel`, side-by-side list visibility, slide/fade transition, close behavior, `.id(memory.id)` state isolation, responsive `ViewThatFits` header wrapping, accessibility identifier, and focused tests. Do not infer retention of the panel's metadata or actions; challenge those children separately.

Acceptance group: A10.


### IR-277

Insight memories' special Tips/subcategory/reasoning presentation.

`keep the Tips presentation and apply its final Insights category locally`

Confirmed: retain `tips` classification; Productivity/Health/Communication/Learning/Other subcategory tags and icons; Tips and subcategory chips in the detail header; Category/Subcategory rows in the retained hover tooltip; duplicate raw-tag suppression; and **Why this tip** for reasoning. Change the first authoritative local InsightAssistant record to category `interesting`/Insights while retaining those structured tags. Remove its temporary `system`/About You classification, hosted `POST /v3/memories`, response-based category correction, mark-synced step, and synchronization tests. Preserve local owner fencing, deduplication, lifecycle processing, and focused presentation tests.

Acceptance group: A10.


### IR-278

Memory inspector Edit text action and correction lifecycle.

`keep the active inline editor and adapt canonical correction behavior locally`

Confirmed: retain the inspector's **Edit text** action, click-to-edit behavior, tall inline `TextEditor`, Cancel/Save controls, local list reload, and selected-value refresh. On Save, resolve the retained local/surfaced identity and atomically store the trimmed user correction as the authoritative GRDB revision; preserve Omi's existing Short-term/pending-processing, retry/idempotency/audit, and durable-admission semantics locally so derived content cannot remain tied to the old text. Delete the hosted `PATCH /v3/memories/{memory_id}` dependency from this path, backend-ID-only cache mutation, hosted vector/synchronization consequences, `editingMemory` state, and unreachable duplicate `EditMemorySheet`. Failure/dismissal presentation remains a separate inspector child to challenge next.

Acceptance group: A10.


### IR-279

Memory inline-edit Save/Cancel and local failure behavior.

`keep the simple UI and close only after local acceptance`

Confirmed: retain the current inline Cancel/Save presentation with no new banner, progress indicator, or recovery screen. Cancel immediately discards the draft. Save trims the correction, refuses an empty result, and exits edit mode only after the authoritative local transaction commits. If that commit fails, keep the editor and exact draft visible for another Save attempt and record the existing privacy-bounded diagnostic; do not silently replace it with the old stored text.

Acceptance group: A10.


### IR-280

Individual memory Delete action and four-second Undo lifecycle.

`keep the four-second Undo experience with local finalization`

Confirmed: retain the inspector **Delete memory** action, panel dismissal, immediate animated list/search/filter removal, four-second countdown toast, Undo, × finalization, and the rule that a newer deletion finalizes the previous one. The initial soft-delete transaction must succeed before presenting deletion as accepted. Undo restores and requeries the active local scope. On ×, expiry, or displacement, permanently remove the authoritative local row, cancel any pending lifecycle processing for its identity, and emit the retained privacy-bounded deletion analytic. Keep explicit deletion of an individually selected Archive memory. Delete the hosted DELETE request, backend-only identity branch, raw server paging adjustment, restore-after-remote-failure path, and indefinite sync tombstone.

Acceptance group: A10.


### IR-281

Legacy external-device/integration source labels in memory provenance.

`delete external-source compatibility while retaining local provenance`

Confirmed: retain the existing provenance-chip presentation and timestamp with locally produced **Desktop**, **Screenshot**, and **Added by you** identities plus app name, microphone, and confidence when present. Remove named mapping/icon cases and exclusive tests for OMI, Phone, Frame, Friend, Apple Watch, Bee, Plaud, Limitless, Screenpipe, Workflow/Integration, and OpenGlass. Do not remove the underlying local source field or the retained provenance section through this decision.

Acceptance group: A10.


### IR-282

Generic Tags section in the memory inspector.

`keep the generic Tags section exactly as implemented`

Confirmed: retain the conditional section, wrapping tag chips, color treatment, and current suppression of the primary category, `tips`, Tips subcategory, `has-message`, and `app:<name>`. Continue showing meaningful remaining tags such as **focus** and **focused**/**distracted** from the retained local Focus writer. Do not infer a generic memory-tag editor or new tagging system from this read-only presentation.

Acceptance group: A10.


### IR-283

Generic non-Tips Reasoning section in the memory inspector.

`delete the generic non-Tips Reasoning inspector branch`

Confirmed: render the inspector explanation only for retained Tips/Insight rows under **Why this tip**. Remove the ordinary-memory **Reasoning** title/branch and exclusive compatibility tests. Keep the local `reasoning` field because InsightAssistant still writes it; do not change task, goal, notification, Focus-alert, consolidation, or other internal reasoning; and do not repair or reduce IR-272's separately retained hover tooltip through this decision.

Acceptance group: A10.


### IR-284

Memory inspector Context section.

`keep the Context section exactly as implemented`

Confirmed: retain `currentActivity`, `windowTitle`, and `contextSummary` in authoritative local memory rows; the conditional `hasContext` check; activity/window lines; selectable wrapping summary; and current visual treatment/tests. Do not show an empty section for manual or other context-free memories, and do not infer new context fields or editing controls.

Acceptance group: A10.


### IR-285

View Source Conversation from a linked memory.

`keep View Source Conversation with a local session relationship`

Confirmed: conversation-derived memories retain a stable local transcription-session reference; unrelated screen/Focus/Insight/manual rows continue omitting the action. Keep the existing inspector action, dismissal, loading overlay, in-place conversation detail, and Back return. Resolve the local session and its segments from authoritative `TranscriptionStorage` and construct the existing detail projection locally. Remove the backend-ID requirement, `GET /v1/conversations/{id}`, hosted fallback, and exclusive network tests from this path. Source-conversation deletion semantics remain a separate requirement.

Acceptance group: A10.


### IR-286

Conversation-deletion cascade into source-linked memories.

`keep the conversation-to-memory privacy cascade locally`

Confirmed: when local conversation deletion is accepted, atomically delete every authoritative memory whose stable source-session reference matches that conversation and cancel any pending lifecycle work for those identities. Only after the transaction succeeds should the UI report deletion and remove those memories from visible/search/filter state. Continue cascading an edited but still linked memory, and leave unrelated memories untouched. Remove hosted `cascade=true` memory retraction from this path, vector/projection cleanup, `.conversationDeleted` cloud-cache repair, server refetch, and orphan pruning; task/action-item cascade remains a separate conversation/task requirement.

Acceptance group: A10.


### IR-287

Memories-page title and Omi-learning subtitle.

`keep the heading layout with exact local-accurate subtitle copy`

Confirmed: retain the title/subtitle hierarchy, typography, spacing, and **Memories** title. Replace the subtitle exactly with **Memories and insights saved on this Mac**. Remove the Omi brand and assistant-authority claim without making a false local-compute claim.

Acceptance group: A10.


### IR-288

Basic memory-card content preview and creation timestamp.

`keep the two-line preview and dual timestamp exactly as implemented`

Confirmed: retain the current font, two-line limit, tail truncation, leading alignment, and `formatDate` output combining abbreviated relative time with `MMM d, h:mm a` absolute time from the authoritative local `createdAt`. Add no timer or alternative card expansion behavior.

Acceptance group: A10.


### IR-289

Unused memory human-review, thumb-rating, and scoring metadata.

`delete the unused memory review/scoring slice`

Confirmed: remove `reviewed`, `userReview`, and `scoring` from `MemoryRecord`, `ServerMemory`, GRDB after migration, API/generated projection, cache conversion, Chat SQL field descriptions, fixtures, and exclusive tests. Delete the unused memory review mutation/review-queue hosted slice and generated client calls. Retain locally produced/displayed `confidence`; IR-034's `isRead`/`isDismissed`; manual/user-asserted identity; and IR-260/278's typed processing, correction, retry, idempotency, and audit records.

Acceptance group: A10.


### IR-290

Persisted Insight notification headline in memory records.

`keep the short notification headline transient; delete its durable memory field`

Confirmed: retain `InsightExtractionResult.headline`, the model's short-headline instruction, immediate local notification use, and the existing `headline ?? full advice` fallback. Do not save the headline in a durable memory or reconstruct it later. Remove only the memory-persistence and hosted-compatibility field from `MemoryRecord`, `ServerMemory`, the GRDB schema after migration, memory create/decode/cache/conversion projections, generated memory API models, fixtures, and exclusive tests. Retain the full advice as the authoritative durable content. Do not touch unrelated task, onboarding, Focus, or other headline fields.

Acceptance group: A10.


### IR-291

Exact local Rewind screenshot relationship on automatic memories.

`keep the exact local screenshot relationship unchanged`

Confirmed: retain `MemoryRecord.screenshotId`, the local `Screenshot` relationship, the memories-table foreign key and lookup index, population by retained local screen-derived producers, and `memories.screenshotId -> screenshots.id` discoverability for normal desktop Chat. Preserve `ON DELETE SET NULL`: removing an expired Rewind frame must clear only the reference while the memory and its copied provenance remain. Do not add a new Memories navigation control. Do not introduce any screenshot copy or remote synchronization.

Acceptance group: A10.


### IR-292

Dead MemoryTier-to-MemoryLayer rename aliases.

`delete all five unused rename aliases`

Confirmed: remove `MemoryTierFilter`, `MemoryTierBadge`, `MemoryTier`, `MemoryTierScope`, and `MemoryTierFilterTests`, together with comments that exist only for those declarations. Retain canonical `MemoryLayer`, `MemoryLayerFilter`, `MemoryLayerBadge`, `MemoryLayerScope`, tests, stored-field decoding, schema migrations, Short-term/Long-term/Archive behavior, and every decision under IR-260. This is compile-time cleanup only.

Acceptance group: A10.


### IR-293

Conversations-page fixed title and subtitle header.

`keep the Conversations header exactly as implemented`

Confirmed: retain both visible strings, typography, colors, spacing, background, and pinned placement while the complete page body scrolls below it. Do not infer any decision for Select/Merge, Quick Note, Start Recording, live transcript, search, filters, folders, rows, or detail views; audit those concrete children separately.

Acceptance group: A11.


### IR-294

Conversations Select/Merge workflow.

`keep Select/Merge and make the essential transcript merge local-authoritative`

Confirmed: retain the current entry condition, Select/Done transition, row selection in normal/search lists, displayed-list-scoped Select All/Deselect All, selected count, two-item minimum, confirmation and irreversible wording, progress/failure presentation, chronological ordering, gap-preserving segment offsets, completed/unlocked/nondeleted validation, and replace-originals behavior.

Make local GRDB authoritative. A new local replacement and its transcript segments must become durably accepted before source deletion; failures or crashes must leave/recover the source conversations rather than lose them. Reprocess only derived conversation behavior that separately survives this audit. Remove `APIClient.mergeConversations`, `/v1/conversations/merge`, Firestore lifecycle/status authority, GCS audio/photo copying, vector rebuilding, FCM completion delivery, cloud background execution, generated contracts, configuration, and exclusive tests. Do not restore cloud recording playback or synchronization.

Acceptance group: A11.


### IR-295

Conversations Quick Note and Rewind live transcript/notes workspace.

`keep it exactly as implemented with no repair`

Confirmed: retain the always-visible Quick Note button, notification-based navigation to Rewind, fixed 0.3-second mount delay, automatic expansion, transcript-left/notes-right layout, back behavior, current panel sizing, manual note creation/edit/delete, enabled-by-default Gemini note generation, local `live_notes` persistence, active-session relationship, crash-recovery reload, and local Chat/SQL visibility exactly as they work now.

Do not hide or disable Quick Note while idle. Do not prevent the current clear-after-unsaved idle submission. Do not rename the button, start a recording, create standalone notes, focus the field automatically, add error UI, or add stored notes to Conversation Detail. Provider choice remains part of the already-reserved model/backend audit; this decision preserves the behavior rather than resolving Gemini-versus-other-model selection.

Acceptance group: A11.


### IR-296

Conversations Start Recording header action.

`keep Start Recording exactly as implemented`

Confirmed: retain its microphone icon, label, styling, location, `!isTranscribing && mode == .always` gate, direct `startTranscription()` call, and all existing permission/paywall/error behavior inherited from that shared lifecycle. Do not expose it in Meetings Only or Mic Only, make it a one-off recording mode, or create another recording authority. Retained local/cloud STT provider selection and final model/backend work remain governed by their existing decisions.

Acceptance group: A11.


### IR-297

Conversations compact and full-screen live transcript.

`keep the compact card and full-screen expansion exactly as implemented`

Confirmed: retain the Live/Listening states, red indicator, 220-point compact transcript, speaker alignment/labels/avatars, timestamps, translations, automatic bottom following, complete-card click target, hover/help/cursor behavior, expand transition, full-page overlay, shared live monitor, collapse button, Escape shortcut, and automatic collapse when transcription stops. Do not combine it with Quick Note/Notes or create another transcript store.

Acceptance group: A11.


### IR-298

Conversations title/overview search.

`keep the exact title/overview search experience and execute it locally`

Confirmed: retain **Search conversations**, shared search chrome, whitespace normalization, 250 ms nonempty debounce, immediate clear, loading indicator, stale-query cancellation, owner fencing, title-plus-overview matching only, non-discarded/unlocked scope, newest-first ordering, 50-result cap, normal rows, detail selection, multi-select/Merge compatibility, folder actions, and query-length-only PostHog telemetry.

Execute against locally authoritative conversation fields and remove the page's `ConversationRemoteDataSource.search`, `APIClient.searchConversations`, `POST /v1/conversations/search`, Typesense conversation-query dependency, Firestore hit hydration, search-result cache writes/reconciliation, generated contracts, and exclusive backend/client tests. Do not silently expand this page field into transcript or semantic search; retained voice/Chat conversation retrieval remains separately governed.

Acceptance group: A11.


### IR-299

Conversations search loading and failure states.

`keep the states and replace only the connection-specific sentence`

Confirmed: retain the search-field spinner, centered spinner, **Searching...**, warning icon, query preservation, cleared result area on true failure, stale-query cancellation without an error, and retry through another field submission. Replace only **Couldn't search conversations. Check your connection and try again.** with exact local-authority copy **Couldn't search conversations. Try again.** Do not add a Retry button, database-repair control, or synchronous search assumption.

Acceptance group: A11.


### IR-300

Conversations search No Results state.

`keep the No Results state exactly as implemented`

Confirmed: retain the muted magnifying-glass icon, both exact strings, typography, spacing, centered layout, preserved query, clear control, and ability to type a replacement query. Do not add a Retry button, transcript/semantic-search escalation, or automatic filter mutation.

Acceptance group: A11.


### IR-301

Conversation starring and Starred filter.

`keep conversation starring and make GRDB authoritative`

Confirmed: retain outline/filled stars in compact and expanded rows, amber state, `isStarring` repeat suppression, immediate optimistic appearance, field-scoped rollback on local commit failure, latest-intent/overlapping-mutation safety, Starred filter icon/text/loading/active presentation, local starred-only list/count, combinations with date/folder, and owner isolation.

Make the local session ID and indexed `transcription_sessions.starred` field authoritative. Remove the conversation-star remote protocol method, `APIClient.setConversationStarred`, PATCH route use from Mac, backend-ID dependence, response hydration, pending remote acknowledgement/reconciliation, count-cache invalidation for this mutation, generated contracts, and exclusive API/client tests. Chat-thread starring is untouched.

Acceptance group: A11.


### IR-302

Conversations Date filter.

`keep the complete Date filter and make the local session store authoritative`

Confirmed: retain the Date label, graphical 300-point calendar, prohibition on future dates, automatic popover close on selection, local-calendar day semantics, `MMM d` active label, loading indicator, active styling, inline date-only clear, Clear-all behavior, and combinations with Starred and folder filters. Query and count authoritative local sessions using `[calendar.startOfDay(for: selectedDate), nextDayStart)`. Remove the backend conversation-list/count dependency and hosted `created_at` filtering for this Mac feature.

Acceptance group: A11.


### IR-303

Conversation folder tabs and manual assignment.

`keep manual folder organization and make it local-authoritative`

Confirmed: retain the horizontal All/Starred/folder strip, selection and toggle behavior, temporary interaction disabling during a filter transition, combinations with Date and Starred, and folder movement from compact rows, expanded rows, and Conversation Detail, including **No folder**. Preserve immediate optimistic presentation, field-isolated rollback on local commit failure, and latest-intent safety.

Store folder definitions locally and make the stable local session ID plus `transcription_sessions.folderId` authoritative. Remove the Mac's folder-list and conversation-move API dependence, backend conversation IDs and acknowledgements for this behavior, Firestore folder/session assignment ownership, and hosted reconciliation. Folder creation, editing, deletion, description semantics, Omi system folders, and automatic AI assignment remain separate open requirements.

Acceptance group: A11.


### IR-304

New Folder creation workflow.

`keep New Folder creation and make the insert local`

Confirmed: retain the plus button, 380-point sheet, title and dismiss action, required trimmed name, disabled/muted whitespace-only Create state, current color palette and gray default, Cancel, progress indicator, close-after-attempt behavior, and append/order behavior. Replace `POST /v1/folders`, the returned hosted model, and Firestore creation with a local folder transaction that generates the stable local folder ID, timestamps, order, and initial zero count. The optional Description field and its AI semantics remain the immediately following open requirement.

Acceptance group: A11.


### IR-305

Automatic AI conversation-folder assignment and folder Description.

`delete automatic AI folder assignment and its Description field`

Confirmed: remove the Description input/state from New/Edit Folder, Description fields from folder models and requests, the `conv_folder` model route and prompt, folder-context construction, folder-assignment result/confidence/reasoning validation, category/default fallback selection, processing invocation and usage tracking, automatic hosted `folder_id` write, automatic-versus-manual `folder_user_set` reconciliation, generated contracts, and exclusive tests. Retain the already-approved manual folder creation, selection, filtering, assignment, and **No folder** behavior locally. Preinstalled Work/Personal/Social folders remain a separate open requirement.

Acceptance group: A11.


### IR-306

Preinstalled Work/Personal/Social conversation folders.

`delete Work/Personal/Social seeding and system/category protection`

Confirmed: remove `SYSTEM_FOLDERS`, category mappings and resolution, deterministic system-folder document IDs, empty-collection initialization, `isSystem`/`isDefault`/`categoryMapping` folder state, protected-delete branches, system/custom counting, associated icons/descriptions, initialization calls, generated contracts, and exclusive tests. A user with no folders sees only **All**, **Starred**, and **+**; every retained folder is an ordinary user-created local folder.

Acceptance group: A11.


### IR-307

Edit Folder workflow.

`keep the existing Edit Folder workflow locally`

Confirmed: retain the tab's right-click **Edit** action, 380-point Edit Folder sheet, prefilled name and color, required trimmed-name rule, whitespace-disabled Save styling, Cancel/dismiss actions, progress indicator, close-after-attempt behavior, and the existing folder order and conversation assignments. Remove the already-rejected Description control and replace `PATCH /v1/folders/{id}`, response hydration, and Firestore update ownership with an authoritative local folder-row update.

Acceptance group: A11.


### IR-308

Delete Folder and assigned-conversation destination.

`keep Delete Folder and make the whole mutation one local transaction`

Confirmed: retain the right-click destructive action, 380-point named confirmation sheet, authoritative local conversation count and pluralized explanation, default **No folder (unfiled)** choice, every other local folder as a colored destination, Cancel/dismiss, red Delete styling, progress indicator, and reset to All when deleting the selected filter. In one local transaction, set every assigned session's `folderId` to the chosen destination or `nil`, then delete the folder and update affected counts. Remove hosted validation, Firestore batching/deletion, cached-count reconciliation, endpoint/generated contracts, and exclusive tests.

Acceptance group: A11.


### IR-309

Unused folder-reordering protocol.

`delete manual folder-reordering infrastructure and retain creation order`

Confirmed: remove `POST /v1/folders/reorder`, `ReorderFoldersRequest`, duplicate/unknown-ID validation, Firestore batch reordering, mutable-order fields accepted by hosted update contracts, generated endpoint methods/types, route policy entries, and exclusive tests. Retain deterministic local folder ordering and the IR-304 rule that each newly created folder is appended. No drag-and-drop or replacement ordering UI is added.

Acceptance group: A11.


### IR-310

Public conversation Copy Link and hosted sharing.

`delete conversation Copy Link and the complete hosted sharing slice`

Confirmed: remove the row hover icon, row context-menu item, Conversation Detail link action, loading state and analytics, Mac share/visibility helpers, conversation-only `private/shared/public` protocol state, visibility PATCH route and Firestore mutation, Redis publication/revocation mappings, unauthenticated shared-conversation read and field-redaction contract, `h.omi.me` link construction and hosted shared-conversation page dependencies, public shared-conversation Chat resolver/route/rate limits, its dedicated model-gateway lane/configuration, generated contracts, and exclusive tests. Do not replace it with a new export or peer-sharing design here. Local **Copy Transcript** remains open.

Acceptance group: A11.


### IR-311

Conversation-row Copy Transcript.

`keep row Copy Transcript and resolve local detail on demand`

Confirmed: retain the context-menu label/icon, no-navigation behavior, `You: …` / `Speaker <id>: …` format, two-newline separation, general pasteboard destination, and current silent presentation. When invoked from a lightweight row, load that stable local session's complete ordered segments from GRDB before formatting; do not restore server detail hydration, preload all list transcripts, or merge this formatter with Conversation Detail's distinct person-aware output.

Acceptance group: A11.


### IR-312

Edit Conversation Title.

`keep Edit Conversation Title with a local durable user override`

Confirmed: retain row-hover pencil, row context-menu action, detail-header pencil, exact native alert title/message/field/buttons, prefilled text, exactly-empty-only validation, whitespace acceptance, close-on-Save presentation, immediate optimistic update, serialized same-conversation mutations, latest-intent safety, and title-only rollback on local failure. Commit the title plus a durable local user-authored-override marker using stable local session identity so later processing preserves it. Remove backend-ID-only mutation, `PATCH /v1/conversations/{id}/title`, Firestore `user_title` authority, canonical response hydration, generated contracts, and exclusive network tests.

Acceptance group: A11.


### IR-313

Delete Conversation UI and local transcript lifecycle.

`keep Delete Conversation and make it permanently local`

Confirmed: retain the row-hover trash button, row context-menu destructive action, Conversation Detail trash button, exact native alert title/message/buttons, row retention until acceptance, count update after success, and detail Back/refresh only after success. In the authoritative local transaction, permanently delete the transcription session and its cascade-owned transcript segments/live notes together with the IR-286 linked-memory deletion/cancellation. Remove the local soft-delete-only acceptance path, backend ID, server-first DELETE, Firestore document/subcollection purge, hosted audio/vector cleanup, response contract, generated bindings, and exclusive network tests. Task/action-item cascade remains immediately open.

Acceptance group: A11.


### IR-314

Conversation-deletion cascade into source-linked tasks.

`keep the exact-source task cascade locally`

Confirmed: replace task `conversationId` backend identity with a stable local source-session relationship. During the IR-313 accepted deletion transaction, permanently delete every authoritative local task whose source-session reference matches, including edited, completed, reprioritized, or rescheduled rows that remain linked. Leave every unrelated task untouched and do not follow recurrence/goal/other relationships unless those rows independently carry the same exact source. Remove hosted `delete_action_items_for_conversation`, Firestore batch deletion, cache repair, generated contracts, and exclusive server-cascade tests.

Acceptance group: A11.


### IR-315

Conversation row-to-detail navigation and detail loading.

`keep row-to-detail navigation with local-authoritative detail loading`

Confirmed: retain whole-row normal-mode click, Select/Merge click interception, search-result parity, selected-conversation replacement, Detail's 0.5-second gated fade/rise, Back return, and automation/memory-source entry into the same surface. Resolve the stable local session plus its complete ordered segments and retained metadata from `TranscriptionStorage`; remove backend identity, `GET /v1/conversations/{id}`, server revalidation/response hydration, hosted fallback, and exclusive network tests from ordinary detail loading. No detail child is implicitly retained by this shell decision.

Acceptance group: A11.


### IR-316

Hidden Expanded conversation-row mode.

`delete Expanded mode and keep Compact as the sole row`

Confirmed: retain the current Compact row's exact emoji/title/metadata/action/star sizing, spacing, padding, background, corners, selection behavior, and every separately decided child. Remove `expandedRowContent`, `isCompactView` propagation from page/list/row callers, the `conversationsCompactView` `AppStorage` declarations and stale preference contract, comments/previews/tests that exist only for dual mode, and any external automation field exclusive to it. Do not add a new density selector.

Acceptance group: A11.


### IR-317

One-minute New badge/highlight on conversation rows.

`keep the one-minute New treatment exactly as implemented`

Confirmed: retain the `createdAt`-based less-than-60-second computation, shared New badge, subtle background, selection/hover precedence, and natural disappearance on a later SwiftUI recomputation. Do not add a timer, read/unread persistence, click-to-clear behavior, count, settings, or cloud state.

Acceptance group: A11.


### IR-318

Compact conversation-row identity block.

`keep the Compact row identity block exactly as implemented`

Confirmed: retain the 36-point rounded emoji tile and `💬` fallback, one-line medium title and **Untitled Conversation** fallback, `startedAt`-then-`createdAt` selection, exact Today/Yesterday/same-year/older-year formats, dot separator, start/end duration with transcript-timing fallback, and exact minute/second formatting. Do not add source/folder/overview text here. Title/emoji generation remains part of the later model-processing audit.

Acceptance group: A11.


### IR-319

Conversation-list date sections and flat rendering.

`keep date-section grouping and the flat-list structure exactly as implemented`

Confirmed: retain `createdAt` local-day grouping, exact Today/Yesterday/`MMM d, yyyy` labels, header ordering, repository-provided row order within groups, first-versus-later header spacing, and one flat identifiable header/row `ForEach`. Do not switch grouping to `startedAt`, add an inner sort, or restore nested list rendering.

Acceptance group: A11.


### IR-320

Dead conversation-row folder/source label helpers.

`delete the two dead row helpers only`

Confirmed: remove only `ConversationRowView.folderName` and `.sourceLabel` plus comments/tests exclusive to them if any are found during implementation. Do not remove the row's folder inputs/actions, persisted `folderId`, `ConversationSource`, source serialization, source displays elsewhere, or historical compatibility under this decision.

Acceptance group: A11.


### IR-321

Initial Conversations loading state.

`keep the initial loading state exactly, driven locally`

Confirmed: retain the empty-list-only blocking condition, centered layout, accent spinner at 1.2 scale, exact **Loading conversations...** copy, and preservation of already-visible rows during later work. Drive the state only from local GRDB open/recovery/query/projection; remove server-fetch/cache-revalidation lifecycle ownership without adding skeletons, refresh banners, or timing changes.

Acceptance group: A11.


### IR-322

Conversations failed-load and retry state.

`keep the failure state with neutral local copy and GRDB retry`

Confirmed: retain the empty-list-only condition, warning icon, exact **Failed to load conversations** title, centered styling, hidden raw error, and **Try Again** control. Replace the explanatory sentence with exact **Unable to load conversations. Try again.** and make Try Again rerun only local GRDB open/recovery/query/projection. Preserve already-visible rows on a later failure and record technical evidence only through retained privacy-bounded diagnostics. Do not add reset, repair, or network instructions.

Acceptance group: A11.


### IR-323

True-empty Conversations state.

`keep the exact state for genuinely empty history only`

Confirmed: retain the 48-point bubbles icon, exact **No Conversations** title, exact **Start recording to capture your first conversation** instruction, typography, spacing, centered full-page layout, and no additional button. Show it only when local history is genuinely empty with no active Date/Starred/folder scope; do not use it for a zero-match active filter.

Acceptance group: A11.


### IR-324

Zero-match active conversation filters.

`add one minimal zero-match filter state`

Confirmed: when any Date, Starred, or folder filter is active and its successful local query returns no rows, retain the centered empty-state presentation but use exact title **No matching conversations** and exact explanation **Try changing or clearing your filters.** Preserve the selected controls, existing clear-all `x`, search independence, and true-empty state from IR-323. Do not auto-clear, add another button, or treat zero matches as an error.

Acceptance group: A11.


### IR-325

Conversations 50-row pagination and Load older.

`keep the complete 50-row manual paging experience locally`

Confirmed: retain page size 50, total-count-aware has-more calculation, exact **Load older conversations** label/style/accessibility identifier, bottom pinning, search/embedded/exhaustion exclusions, Merge-bar precedence, in-flight repeat suppression, stable current rows, duplicate-ID replacement, ordered append, silent failed-page behavior, and retry opportunity. Add authoritative local offset/limit/count queries for the active Date/Starred/folder scope; remove hosted page/count calls, response reconciliation, backend IDs, and exclusive network tests.

Acceptance group: A11.


### IR-326

Conversation refresh triggers and activation cooldown.

`keep all current refresh triggers against local authority only`

Confirmed: retain native pull-to-refresh, global Cmd+R/`.refreshAllData`, `refresh_all_data` automation parity, at-most-once-per-60-seconds activation refresh, internal post-mutation/lookup callers, existing-row preservation, and `.conversationsPageDidLoad` notification behavior. Redefine `refreshConversations()` as a fresh local list/count query for the active scope. Remove server-only semantics, hosted list/count calls, response reconciliation, and cloud revalidation; add no periodic timer or polling.

Acceptance group: A11.


### IR-327

Conversation Detail static identity header.

`keep the static identity header exactly as it is`

Confirmed: preserve the generated emoji with chat-bubble fallback, one-line title, `startedAt`-then-`createdAt` selection, optional `finishedAt` range, exact subtitle formatting, typography, colors, and spacing. Keep all values backed by the locally authoritative conversation record.

Acceptance group: A11.


### IR-328

Conversation Detail non-completed status badge.

`keep the status badge exactly and drive it from local state`

Confirmed: preserve completed-state suppression; the exact In Progress, Processing, Merging, and Failed labels; warning/information/error color mapping; capsule styling; and layout. Read the status from the locally authoritative conversation lifecycle rather than hosted conversation state.

Acceptance group: A11.


### IR-329

Plan-based lazy conversation enrichment on first open.

`delete Omi's plan-based lazy-on-first-open enrichment mode`

Confirmed: remove the `deferred` conversation product field and its Basic/Neo/Operator/Architect/BYOK eligibility policy, first-detail-read enrichment trigger, atomic deferred reacquisition, failure re-arming, stale-sweeper exclusions, Mac deferred branch, and focused contracts. Every finalized conversation enters the normal locally authoritative enrichment lifecycle immediately. Keep the ordinary Processing state and separately audit its UI/update behavior. IR-727 subsequently selects the separate Gemini 3.7 Flash structure and action-item workloads.

Acceptance group: A11.


### IR-330

Conversation Detail processing overlay.

`keep the exact processing overlay against local state`

Confirmed: retain the spinner, exact **Processing conversation…** and **Generating summary and action items** copy, typography, colors, spacing, translucent panel, placement over the detail card, preservation of already-available content, and disabled hit testing. Show it from the locally authoritative ordinary Processing lifecycle; remove dependency on the deleted `deferred` mode. Audit completion observation separately.

Acceptance group: A11.


### IR-331

Conversation Detail processing completion refresh.

`keep the exact bounded refresh loop locally`

Confirmed: retain the immediate first read, two-second delay, maximum fifteen attempts, early exit when status leaves Processing, incremental replacement of displayed detail, silent timeout, and no unbounded background timer. Read authoritative local GRDB detail only; remove API/server revalidation and the deleted deferred-mode trigger semantics.

Acceptance group: A11.


### IR-332

Conversation Detail View/Hide Transcript pill.

`keep the View/Hide Transcript pill exactly as it is`

Confirmed: retain the quote icon; exact **View Transcript** and **Hide Transcript** labels; neutral and selected capsule treatments; and motion-gated 0.25-second transition. Opening sets local drawer presentation on. Hiding follows IR-337's shared close transition and clears expanded mode as well as drawer presentation. No cloud read or synchronization is introduced by the control.

Acceptance group: A11.


### IR-333

Conversation Detail transcript drawer presentation.

`keep the side drawer and full-window expansion exactly`

Confirmed: retain the right-side same-page drawer, maximum 450-point normal width, one-point divider, trailing transition, greedy summary pane, full-window transcript expansion, summary-pane zero-width/opacity/clipping behavior, divider suppression while expanded, and restoration on collapse.

Acceptance group: A11.


### IR-334

Conversation Detail transcript drawer identity header.

`keep the drawer identity and segment-count badge exactly`

Confirmed: retain the quote icon, exact **Transcript** label, typography, accent capsule styling, spacing, and direct count of the locally loaded transcript segment array. Do not replace it with a word, speaker, or duration metric.

Acceptance group: A11.


### IR-335

Conversation Detail transcript Expand/Collapse button.

`keep the Expand/Collapse button exactly as it is`

Confirmed: retain the 28-point circular treatment, outward/inward directional symbol swap, exact **Expand transcript** and **Collapse transcript** help text, local `isTranscriptExpanded` state, and motion-gated 0.25-second animation.

Acceptance group: A11.


### IR-336

Conversation Detail Copy Transcript entry points.

`keep both Conversation Detail Copy Transcript buttons`

Confirmed: retain the main detail-header and transcript drawer-header `doc.on.doc` buttons, their circular styling and **Copy transcript** help text, and their shared call into IR-311's exact local formatter and pasteboard behavior. Do not revive Copy Link or duplicate formatting logic.

Acceptance group: A11.


### IR-337

Conversation Detail transcript close/reset contract.

`keep the X and use its close/reset transition for both controls`

Confirmed: retain the 28-point circular X, `xmark` symbol, **Close transcript** help text, styling, and motion-gated 0.25-second transition. Route both the X and **Hide Transcript** through one local close action that sets drawer presentation and full-window expansion to false, restores the summary pane, and makes the next open use the side drawer. IR-332's labels and visual treatments remain unchanged.

Acceptance group: A11.


### IR-338

Per-conversation billing lock and Transcript locked UI.

`delete per-conversation billing locks and Transcript locked`

Confirmed: remove the conversation `isLocked` product field, `lockedOrRedacted` transcript-presence state, drawer lock icon/copy, copy suppression, hosted 402 detail/mutation/audio guards, list/search/retrieval redaction or exclusion, integration/share filters where not already deleted, propagation into conversation-derived records, credit-exhaustion `should_lock` writes, mass-unlock payment effects, repair scripts, generated contracts, and lock-specific tests. The authoritative local transcript remains readable once written. Retain account and Dodo-backed entitlement enforcement at app access and before initiating managed paid compute. Audit any independently created memory/task billing lock separately rather than assuming it survives through this conversation dependency.

Acceptance group: A11.


### IR-339

Conversation Detail genuine empty-transcript state.

`keep the genuine empty-transcript state exactly as it is`

Confirmed: retain the zero-local-segment condition after loading finishes, faded quote icon, exact **No transcript available** copy, typography, colors, spacing, and centered layout. Do not substitute the deleted billing lock or assume every empty result is still loading.

Acceptance group: A11.


### IR-340

Conversation Detail transcript local-loading state.

`keep the exact Loading transcript state for local detail reads`

Confirmed: retain `isLoadingConversation` precedence over the empty state, small spinner, exact **Loading transcript...** copy, typography, color, spacing, and centered layout. Drive it only around the on-demand local GRDB conversation/segment read retained under IR-315; remove server/cache-revalidation meaning and add no new failure child in this decision.

Acceptance group: A11.


### IR-341

Conversation Detail base transcript bubbles.

`keep the base transcript bubbles exactly as implemented`

Confirmed: retain direct `ScrollView`/`LazyVStack` composition; user/right and other-speaker/left alignment; You/Speaker N labels; Y/numbered avatars; stable user/speaker bubble-color rules; rounded text bubbles; local start-time `m:ss` formatting; spacing; and the deliberate absence of per-bubble text selection. Whole-transcript copying remains the supported copy path.

Acceptance group: A11.


### IR-342

Conversation Detail translated bubble variants.

`keep translated bubble rows and persist received results locally`

Confirmed: retain conditional per-language iteration; italic secondary text; matching padding/corner radius; lighter speaker-color bubble; live in-memory update; local `translationsJson` encoding/decoding; and later detail reconstruction. Return retained cloud-translation events transiently to the Mac and remove the Firestore conversation load/update dependency. Do not add translation generation to local Parakeet in this decision, and defer the exact Gemini/NLLB/provider choice to the reserved model/backend audit.

Acceptance group: A11.


### IR-343

Conversation Detail local speaker-naming entry point.

`keep the speaker-label interaction exactly and point it to local naming`

Confirmed: retain non-user-only clickability; unnamed **Speaker N** plus pencil; named accent label without pencil; plain-button treatment; vertical hit padding; pointer cursor; segment-derived accessibility identifier; current-label accessibility text; and callback into naming. Replace the destination's reusable People/backend contract with IR-022's local conversation-owned label flow. Keep **You** rows non-clickable through this entry point.

Acceptance group: A11.


### IR-344

Conversation Detail Name Speaker sheet shell and preview.

`keep the Name Speaker sheet shell and preview exactly`

Confirmed: retain fixed 400-by-450 size; primary background; **Name Speaker** heading; dismiss X; header/footer dividers; scrollable middle; Cancel/Save footer placement; 28-point numbered avatar; **Speaker N** label; quoted italic sample; 120-character truncation with `...`; three-line limit; card styling; and spacing.

Acceptance group: A11.


### IR-345

Conversation Detail local Who is this selector.

`keep the chip/inline pattern narrowed to You or a local name`

Confirmed: retain the **Who is this?** heading, FlowLayout, selectable **You** chip, selected/unselected chip presentation, and inline-entry pattern. Replace **+ Add Person** with **+ Add Name** and **Person name** with **Speaker name**. Hold the trimmed plain-text draft locally until footer Save. Remove the People array/chips, server person IDs, `onCreatePerson`, asynchronous Add button/spinner, pre-Save creation call, and global directory duplicate warning. Do not add a local cross-conversation contacts table.

Acceptance group: A11.


### IR-346

Conversation Detail speaker-label apply scope.

`keep the apply-scope checkbox exactly as it is`

Confirmed: retain matching by the current conversation's diarization speaker value; non-user filtering; conditional display only for more than one match; default-on state; exact **Also tag N other segment(s) from this speaker** copy with singular/plural selection; checked all-matching indices; unchecked tapped-segment index; checkbox style; and layout.

Acceptance group: A11.


### IR-347

Conversation Detail local speaker-label Save/Cancel boundary.

`keep the footer but make one GRDB transaction the Save boundary`

Confirmed: retain Cancel, Save capsule, disabled/active treatments, and Save spinner. Enable Save for **You** or a non-empty trimmed local name. Atomically update the selected local transcript segments or their conversation-owned speaker-label mapping; after commit, update displayed bubbles and close. On failure, stop saving and keep the sheet plus draft open without adding new error UI. Cancel and X close without writing. Remove backend assignment calls, backend segment-ID/fallback-token construction for this mutation, server person IDs, `onAssignSpeaker`, and backend-success dependency.

Acceptance group: A11.


### IR-348

Conversation Detail card shell.

`keep the Conversation Details card shell exactly as it is`

Confirmed: retain the main-pane ScrollView; `doc.text` icon; exact **Conversation Details** label; header-bar typography, colors, padding, and background; child-stack spacing/padding; rounded secondary card; clipping; one-point outline; shadow; and outer spacing. Audit every child separately.

Acceptance group: A11.


### IR-349

Conversation Detail generated Summary.

`keep generated summaries and make their output local-authoritative`

Confirmed: retain transcript/context-based overview generation; conditional omission when empty; gold star; exact **Summary** label; typography, spacing, and colors; `OmiMarkdown`; dark rendering; text selection; and leading full-width layout. Write the generated overview through the locally authoritative enrichment transaction and let retained local search/retrieval read it. Remove Firestore conversation storage/hydration/synchronization for this field. This decision does not retain every sibling of `process_conversation`; IR-727 subsequently selects the exact model boundary.

Acceptance group: A11.


### IR-350

Conversation Detail Source metadata chip.

`delete the Source chip and unsupported device-label mapping`

Confirmed: remove `sourceChip`, the detail `sourceLabel` switch, its radio-waves icon/capsule, and displayed compatibility for Omi, phone, watch, workflow, Screenpipe, partner devices, and Unknown. Do not add a replacement capture/provider chip. Retain only narrow internal provenance fields proven necessary by separately accepted recording, diagnostics, or migration behavior; remove the broad local conversation source enum/data after its remaining callers are audited rather than by blind field deletion.

Acceptance group: A11.


### IR-351

Conversation Detail Duration metadata chip.

`keep the Duration chip exactly as it is`

Confirmed: retain the hourglass symbol, metadata capsule treatment, `finishedAt - startedAt` preference, final-segment-end fallback, zero fallback, exact `Xm Ys`/`Xs` formatting, typography, colors, padding, and spacing. Read only authoritative local conversation/segment timestamps.

Acceptance group: A11.


### IR-352

Conversation Detail generated category and chip.

`delete generated conversation category and its chip`

Confirmed: remove category from conversation structured-generation output, backend/domain/generated contracts, local conversation storage/hydration, and Conversation Detail's tag capsule. Remove category-exclusive prompts/tests and compatibility once callers are gone. This does not delete task, memory, or Insight categories, which are separate domains.

Acceptance group: A11.


### IR-353

Conversation Detail Action Items section.

`keep the exact section against authoritative local tasks`

Confirmed: retain conditional omission when no active linked task exists; checklist icon; exact **Action Items** label; local active count badge; read-only rows; incomplete/completed symbols and colors; selectable description; completed strikethrough; row card styling; and spacing. Query authoritative local `action_items` linked to the stable local conversation/session ID. Delete `Structured.actionItems`/`actionItemsJson` as a duplicate display authority and the compatibility write/hydration paths. Task mutation stays on retained task surfaces.

Acceptance group: A11.


### IR-354

Conversation Detail Opened analytics.

`keep the event but remove conversation_id`

Confirmed: retain one **Conversation Detail Opened** PostHog event on real detail opening, route it to our project under IR-115, and honor IR-207's analytics opt-out. Remove the per-conversation UUID property and do not replace it with transcript, title, summary, folder, or speaker content.

Acceptance group: A11.


### IR-355

Conversation Detail non-production automation.

`keep the automation behavior and make its reads local`

Confirmed: retain request/state ownership; open-specific and open-latest actions; optional transcript presentation; tab navigation; bounded wait; detail/drawer state synchronization; view lifecycle clearing; and snapshot fields. Replace API refresh/detail reads with authoritative local list/detail queries and stable local IDs. Keep test-only boundaries and focused automation contracts.

Acceptance group: A11.


### IR-356

Local conversation language.

`keep conversation language locally`

Confirmed: retain the effective language on the authoritative local session; use it for capture recovery, finalization, and retained title/summary/memory/task processing; and send it as an explicit parameter to any retained transient STT/model call. Remove hosted preference synchronization and server-conversation ownership for the field.

Acceptance group: A11.


### IR-357

Locally detected calendar commitments.

`keep automatic commitment detection as local conversation data without Calendar creation`

Confirmed: retain the strict event-extraction criteria and the title, description, start, and duration result in the same retained structured-processing pass. Store the result with the authoritative local conversation and let local Chat read it. Do not restore Google Calendar, EventKit, OAuth, attendee invitations, or any other external calendar-write path.

Remove the hosted events-state patch route and the calendar-creation meaning of `created`; no retained behavior marks a real calendar entry as created. Do not silently reinterpret that boolean as completed, dismissed, or acknowledged without a separately challenged local UI requirement.

Acceptance group: A11.


### IR-358

Opt-in local conversation location.

`keep real opt-in Mac location capture and make the conversation location local-authoritative`

Confirmed: use macOS Location Services behind explicit user permission; attach the captured coordinates and any optional human-readable place label to the authoritative local transcription session/conversation; and preserve that local value for conversation recall and retained processing. Remove the periodic hosted user-location endpoint, Redis location cache, server-finalizer ownership, Firestore propagation, and Google Maps dependency for this path.

Do not infer continuous location collection outside the retained capture lifecycle, background location history, a location timeline, or automatic current-city injection into every Chat request. Audit the separate Chat-location-context child before retaining it.

Acceptance group: A11.


### IR-359

Wearable-camera photos inside conversations.

`delete the inherited wearable-camera conversation-photo pipeline`

Confirmed: remove live-listen image chunk assembly, image-description processing, photo buffers/events, `ConversationPhoto`, hosted photo subcollection storage/encryption/readback, photo-derived processing inputs, Mac photo-event no-ops, `photosJson`, generated contracts, and focused tests that exist only for this wearable-camera path.

Preserve Rewind screenshots, PTT screenshot grounding, and ordinary Chat attachments. Do not treat those independent retained surfaces as conversation photos. If manual photo or screenshot attachment to a recorded conversation is later required, challenge it as a separate Mac product flow with its own UI, local storage, lifetime, and privacy boundary rather than retaining this dead wearable protocol.

Acceptance group: A11.


### IR-360

Recording-time timezone.

`keep the recording-time timezone locally and wire it into retained processing`

Confirmed: snapshot the Mac's IANA timezone when the authoritative local session starts; preserve it with that conversation; and explicitly pass it to retained title/summary, task, memory, and calendar-commitment processing where date interpretation is relevant. Do not reconstruct it from Firestore, a hosted user preference, the server's timezone, or the Mac's possibly different current timezone during later reprocessing.

Acceptance group: A11.


### IR-361

Recording input-device name.

`keep the input-device name locally`

Confirmed: preserve the recording input's display name on the authoritative local session and allow local diagnostic/Chat use. Do not synchronize the raw device name to Firestore or include it in PostHog/Sentry payloads; retain the current count/boolean-style diagnostic boundary unless a separately reviewed support flow requires more.

Acceptance group: A11.


### IR-362

Automatic low-value conversation filtering.

`keep the existing discard policy and make its result local-authoritative`

Confirmed: retain the empty-content fast path, over-100-word automatic keep, duration-aware short-content prompt, and existing meaningful-content criteria. Run any required model classification as transient compute, persist the resulting discarded state only in the authoritative local conversation, and apply it consistently to local list/search/Chat/summary/task/memory eligibility. Do not preserve hosted conversation discard state or synchronization.

This decision does not silently define permanent deletion or retention duration for hidden discarded transcript rows; local storage cleanup and privacy retention remain separate requirements.

Acceptance group: A11.


### IR-363

Local conversation-finalization cause and timing.

`keep minimal local finalization cause/timing and delete cloud-sync finalization state`

Confirmed: retain the finalization reason, started-at timestamp, completed-at timestamp, and the minimum local recording/finalizing/completed/failed state required for idempotent local completion, crash recovery, and the already-retained privacy-bounded PostHog/Sentry diagnostics. Preserve the accepted meeting-ended, Finish and Continue, maximum-duration rotation, user-stop, crash-recovery, and retry distinctions.

Delete `.cloudReconcile`, local-segment upload as a promotion strategy, `pending_upload`/`uploading` semantics, backend/client reconciliation IDs, `backendSynced`, `serverUpdatedAt`, server cache completeness, hosted hydration, and retry/error bookkeeping whose only job is server promotion or reconciliation. A separately justified retry for retained transient enrichment must be modeled around that local work rather than preserving upload terminology.

Acceptance group: A11.


### IR-364

Generated conversation title.

`keep generated conversation titles and make them local-authoritative`

Confirmed: retain the existing concise-title behavior in the structured-processing pass; use retained language, recording-time timezone, meeting context, and local speaker labels when available; and commit the result to the authoritative local conversation. Preserve the current **Untitled Conversation** presentation fallback. Remove hosted title ownership, Firestore synchronization/hydration, and server mutation requirements.

Acceptance group: A11.


### IR-365

Generated conversation emoji.

`keep generated conversation emojis locally`

Confirmed: retain one generated emoji in the existing structured-processing response, store it with the authoritative local conversation, and preserve the current chat-bubble fallback and retained row/detail presentation. Remove hosted ownership and synchronization for the field.

Acceptance group: A11.


### IR-366

Mobile-only current-city context in Chat.

`delete the mobile-only current-city Chat context`

Confirmed: remove the 30-day Firestore location-context consent model/field/routes, mobile-platform prompt injection, Redis location read/delete behavior used by this feature, Google Maps city lookup for Chat, provider disclosure copy, and focused contracts/tests. Do not add automatic current-city context to Mac Chat.

Preserve only the separately retained, explicit, conversation-scoped local Mac location from IR-358. Chat may use a recorded conversation's stored location when the user asks about that conversation, but every ordinary Chat request must not silently receive the Mac's current city.

Acceptance group: A11.


### IR-367

Final disposal of automatically discarded recordings.

`permanently delete a locally discarded session after classification succeeds`

Confirmed: retain the crash-safe session and segments only while capture/finalization/classification are unfinished. After the IR-362 discard decision commits, atomically remove the local transcription session, its segments, live notes, and any classification-only work for that identity. Do not create summaries, tasks, memories, calendar commitments, or other derived records from it.

Remove permanent `discarded` rows, list/search/Chat filters whose only role is hiding those tombstones, hosted restore/merge/reprocess support for discarded conversations, and cloud discard synchronization. Migration/cleanup must remove legacy discarded rows safely. This does not alter explicit user-driven Conversation deletion, which remains the separately retained permanent local cascade under IR-286/313.

Acceptance group: A11.


### IR-368

Generic conversation `external_data`.

`delete the generic external_data bag and keep only typed local merge provenance`

Confirmed: remove `external_data` from conversation models, generated contracts, storage, public sanitization, connector/import/calendar/workflow paths, cloud-promotion claims, processing/rendering, and exclusive tests. Do not replace it with another arbitrary JSON dictionary.

For the separately retained local Merge feature, preserve only the exact stable local source-session relationships its deduplication, deletion, and provenance behavior requires, expressed as a typed field or relation owned by that feature. Do not retain imported connector payloads or server claim timestamps inside that local shape.

Acceptance group: A11.


### IR-369

Omi hosted data-protection levels.

`delete the complete hosted data-protection-level system`

Confirmed: remove the user protection-level field and endpoints; Redis cache; `standard`/`enhanced`/`e2ee` product-data branching; per-document `data_protection_level`; master-secret key derivation and product-content encryption/decryption helpers; storage decorators; migration state/jobs/scripts; audio/photo/conversation/message/memory compatibility; and exclusive tests/configuration after every retained cloud control-plane caller is verified not to depend on it.

This decision does not claim that local GRDB is application-encrypted and must not be used to make that privacy promise. Firebase/Dodo protection for the separately retained account, billing, entitlement, and usage data follows those providers' actual configuration. App-specific local database encryption, beyond normal macOS user-account/FileVault protection, is a separate Mac security requirement rather than a reason to retain this Python cloud system.

Acceptance group: A11.


### IR-370

Conversation and memory capture-device provenance.

`delete conversation and memory client-device provenance`

Confirmed: remove `client_device_id`/`client_platform` from conversation and memory/evidence product models, hosted persistence, merge propagation, generated contracts, device-scoped retrieval, labels, and exclusive tests. Local merge provenance must use stable local source-session relationships rather than a device identity.

Do not delete `ClientDeviceService` or shared request headers blindly. Audit remaining authentication, abuse/rate-limit, notification, update, analytics, and diagnostic callers and retain only independently justified narrow device identity. Do not let those operational uses reintroduce device-scoped product history.

Acceptance group: A11.


### IR-371

Hidden model-extracted conversation search metadata.

`delete hidden model-extracted conversation search metadata`

Confirmed: remove conversation/message/text metadata-extraction calls; `ConversationMetadata`; people/topics/entities/dates vector metadata; per-user filter-category catalogs; model-selected structured-filter prompts; Pinecone metadata filtering/reranking; related hosted retrieval branches; configuration; and exclusive tests.

Preserve IR-093's local authoritative semantic conversation search: FTS5 exact title/overview matches, locally persisted embeddings, local similarity comparison, explicit capture-date constraints, and the established keyword-first result merge. This does not delete generated titles/summaries, local tasks/memories, transcript text, or ordinary user-visible/local date filtering.

Acceptance group: A11.


### IR-372

Whole-recording transcript replacement and provider-comparison pipeline.

`delete the whole-recording transcript replacement and comparison pipeline`

Confirmed: remove `postprocess_conversation`; post-processing audio upload/cleanup; FAL/WhisperX conversation status and model enum; whole-file VAD/retranscription and replacement; speech-profile/emotion branches; per-provider transcript and emotion subcollections; `/v1/conversations/{id}/transcripts`; post-processing bucket/configuration; orphaned callers/helpers; and exclusive tests/scripts after shared prerecorded-STT helpers are audited for separately retained callers.

Preserve normal live transcription, the transient `/v4/listen` fallback, generic speaker diarization, local manual speaker labels, PTT transcription fallbacks, and any separately retained voice-message/audio-file transcription caller. No retained path should upload a completed Mac conversation merely to run this deleted comparison experiment.

Acceptance group: A11.


### IR-373

Firestore transcript-segment compression format.

`delete the Firestore transcript compression format`

Confirmed: remove `transcript_segments_compressed` from models and generated contracts; hosted zlib packing/unpacking; encrypted/uncompressed legacy branches; protection migration handling; public-share decoding; backend compatibility/parity tests; and exclusive migration code when hosted conversation documents are removed. This explicitly includes the conversation-only cases in `backend/testing/contracts/test_desktop_backend_parity.py`, root `contract_tests/fixtures/conversations.json`, and the `contracts` job/path triggers in `.github/workflows/desktop-backend-contracts.yml`. Preserve that mixed workflow's independent `desktop-core-e2e-t0` self-check unless its own retained owner moves it.

Keep local GRDB segment rows and their ordinary ordered reads/writes unchanged. This decision removes a rejected cloud storage format; it does not prohibit an independently justified database-level optimization later and does not remove transcript text, timing, speakers, translations, or local indexes.

Acceptance group: A11.


### IR-374

Legacy hosted conversation-processing identity aliases.

`delete both hosted processing-ID names and their memory compatibility events`

Confirmed: remove `processing_conversation_id`, `processing_memory_id`, the constructor alias assignment, obsolete processing-memory event models/fields, generated contracts, migration-safety assertions, factory comments, and exclusive compatibility tests. Do not introduce a replacement cloud processing identifier.

Preserve the stable local session identity and separately retained local lifecycle/finalization status used for crash recovery and UI behavior. This is deletion of dead hosted naming compatibility, not deletion of local processing state.

Acceptance group: A11.


### IR-375

Google Calendar event links attached to conversations.

`delete Google Calendar event linking from conversations`

Confirmed: remove `CalendarEventLink` and `calendar_event`; manual link, auto-link, and unlink routes; overlap lookup; attendee extraction/storage; Google event fetch and token refresh used by this slice; conversation-link writes into event descriptions; generated contracts; compatibility/migration handling; and exclusive tests.

Preserve the locally generated title/description/start/duration commitment from IR-357 with the authoritative local conversation. Do not add Google Calendar, EventKit, OAuth, attendee invitations, external calendar writes, or hosted/public conversation links through this retained local result.

Acceptance group: A11.


### IR-376

Backend-only manual conversation-summary mutation.

`delete the backend-only manual summary mutation`

Confirmed: remove `UpdateSummaryRequest`, the summary PATCH route, default-overview Firestore mutation, Apps-result lookup/mutation, generated bindings, and exclusive endpoint/database tests. Keep generated summaries local-authoritative under IR-349, keep their existing display, and keep the separately retained local manual title override unchanged.

Do not infer a new summary editor from this deletion. If a user-facing Mac summary-editing feature is wanted later, it must be designed as an explicit local behavior with durable user-override precedence rather than preserved accidentally through this unused cloud endpoint.

Acceptance group: A11.


### IR-377

Backend-only transcript-segment text correction.

`delete the backend-only transcript-text correction endpoint`

Confirmed: remove `UpdateSegmentTextRequest`, the segment-text PATCH route, Firestore embedded-array rewrite, locked/backend-ID error branches used only here, generated bindings, and exclusive tests. Do not add a local transcript text editor during this simplification pass.

Preserve transcript capture/display, stable local segment rows, Copy Transcript, retained translations, generic diarization, and local manual speaker labels. Speaker correction remains a distinct retained behavior and must not depend on this deleted text-mutation API.

Acceptance group: A11.


### IR-378

Per-speaker conversation analytics API.

`delete the unused per-speaker conversation analytics API`

Confirmed: remove the analytics GET route; `ConversationAnalytics`/`SpeakerAnalytics` models; calculation helper; hosted People lookup; generated bindings; issue-specific contracts; and exclusive tests. This deletion does not remove transcript timing, generic diarization, manual local labels, generated summaries, or retained privacy-bounded PostHog/Sentry diagnostics.

Acceptance group: A11.


### IR-379

Backend-only arbitrary transcript prompt.

`delete the backend-only arbitrary transcript-prompt path`

Confirmed: remove the test-prompt route; its request/response models; the custom-prompt summary helper when no retained caller remains; its route-specific rate-limit/configuration surface; generated bindings; and exclusive tests. Preserve normal local Chat, the generated local summary retained under IR-349, title generation, and the transcript itself.

Acceptance group: A11.


### IR-380

Hosted speaker-identity conversation search.

`delete the hosted speaker-identity search filter`

Confirmed: remove `speaker_id` from the search request; People-registry validation; Firestore transcript hydration and segment scanning used for this filter; related helpers/contracts; generated bindings; and exclusive tests. Preserve local keyword, semantic, and date search under IR-093, plus retained local manual speaker labels.

Do not infer a new local speaker-label search control from this deletion. Such a filter can be designed later only if it becomes a real Mac requirement.

Acceptance group: A11.


### IR-381

Broad durable conversation-source protocol.

`delete the broad durable conversation-source protocol`

Confirmed: remove the durable source field and broad enum; source-only count/filter behavior; processing branches for rejected producers; source labels; generated contracts; compatibility/migration handling; and exclusive tests. Existing retained local conversations become ordinary Mac sessions without preserving a product-facing source taxonomy.

Preserve the separately retained input-device name under IR-361, transient STT provider diagnostics, local location under IR-358, typed local Merge provenance under IR-368, and the Mac transcription lifecycle itself. This deletion does not collapse those distinct pieces of information into a new generic source field.

Acceptance group: A11.


### IR-382

Dead speech-profile processing state on transcript segments.

`delete transcript speech-profile processing state`

Confirmed: remove `speech_profile_processed` from the segment model and wire contracts; the forced `True` assignment; the unread `current_session_segments` map; merge guards based on the flag; generated bindings; and exclusive tests. Preserve generic within-conversation diarization, normal segment combination, `is_user` when known from retained audio routing, and conversation-local manual speaker labels.

Acceptance group: A11.


### IR-383

Unused improved-transcript result schemas.

`delete the unused improved-transcript schemas`

Confirmed: remove `ImprovedTranscript` and `ImprovedTranscriptSegment` plus any exclusive dead imports or tests discovered during deletion. Preserve live and local transcription, PTT's separately retained contextual transcript cleanup, generic diarization, conversation-local manual labels, and ordinary model-generated summaries. This does not reintroduce the whole-recording replacement pipeline deleted under IR-372.

Acceptance group: A11.


### IR-384

Client-supplied custom-STT listen protocol.

`delete custom-STT listen passthrough and durable per-segment provider identity`

Confirmed: remove custom-STT query/request state; `suggested_transcript` handling; the `uses_custom_stt` user/cloud setting and usage stamp; custom-mode STT, quota, and speaker-identification branches; durable segment `stt_provider`; provider-based segment merge separation; generated contracts; synthetic fixtures; and exclusive tests when no independent retained caller is found.

Preserve ordinary backend-selected `/v4/listen` cloud transcription and fallback under IR-019, local Parakeet, retained provider-selection/failover logic, and privacy-bounded provider/model diagnostics for PTT and operational failures. This decision removes a second transcript-producer protocol, not the retained cloud STT engine.

Acceptance group: A11.


### IR-385

Duplicate machine speaker-number representations.

`keep one canonical numeric speaker ID`

Confirmed: use one numeric `speakerId` in the retained transcript domain and local segment record. Convert provider strings such as `SPEAKER_01` into that integer at the STT adapter boundary, then discard the transport formatting. Remove the duplicate durable `speaker`/`speakerLabel` representation, parser-derived overwrite behavior, generated duplicate field, compatibility code, and exclusive tests.

Preserve generic within-conversation diarization and every UI behavior keyed by the numeric speaker ID. Human labels such as `You` or `Alice` remain a separate conversation-local mapping and must never be conflated with the provider's machine label.

Acceptance group: A11.


### IR-386

Stable local transcript-segment identity.

`keep one required stable segment UUID alongside the internal GRDB row ID`

Confirmed: generate a stable UUID for every local or cloud-STT segment at ingestion and call it `segmentId` across the retained domain. Use it for live upserts, translation attachment, segment deletion, and local speaker-label mutation. Keep GRDB's integer row ID as an internal database key only.

Remove duplicate `backendId`/`backendSegmentId` aliases for segments, optional UUID semantics, speaker-and-start UI identity, and order-based mutation fallback after existing retained local rows receive stable IDs through a bounded local migration. This does not preserve backend conversation ownership or synchronization.

Acceptance group: A11.


### IR-387

Live Name Speaker behavior in Rewind.

`keep live speaker naming and make the promised behavior local`

Confirmed: retain the live clickable speaker, preview sheet, Save/Cancel interaction, and immediate display update. Replace the People directory with the same local choices established for completed conversations: `You` or `+ Add Name`. Apply the choice to existing and future segments carrying that numeric speaker ID in the current recording, and persist the conversation-local label with the authoritative local session so it survives finalization.

Delete People fetching/creation, reusable person chips and IDs, automatic cloud speaker suggestions, and the temporary person-ID map. Do not create a cross-conversation contacts directory or train a voice profile.

Acceptance group: A11.


### IR-388

Same-speaker transcript-fragment joining.

`keep same-speaker joining and make it provider-independent locally`

Confirmed: preserve the deterministic gap, speaker, sentence-completeness, and length behavior, adapted to the canonical numeric speaker ID from IR-385. Apply one authoritative normalization before local persistence for both local Parakeet and transient cloud-STT segments. Preserve one stable segment UUID, extend its end time, and publish the corresponding local update consistently.

Acceptance group: A11.


### IR-389

Cross-speaker transcript-boundary reassignment.

`keep the cross-speaker boundary repair and adapt it locally`

Confirmed: retain the existing deterministic reassignment behavior rather than deleting it. Run the same rule in the local-authoritative normalization path for both Parakeet and transient cloud-STT results, preserve all input words, update the surviving stable segment UUIDs, and apply any resulting local segment update/deletion atomically before downstream enrichment reads the transcript.

This is retention of the existing heuristic, not permission to add an LLM rewrite, re-transcribe whole recordings, train voice profiles, or restore cloud conversation persistence. Manual local speaker correction remains available when the heuristic is wrong.

Acceptance group: A11.


### IR-390

Basic transcript punctuation-spacing normalization.

`keep punctuation-spacing cleanup and make it local-authoritative`

Confirmed: retain the current deterministic cleanup and execute it once in the shared local ingestion/normalization path for both retained STT engines before durable persistence. Do not use an LLM, broaden it into semantic rewriting, or repeatedly mutate already-persisted transcript text.

Acceptance group: A11.


### IR-391

Shared local transcript formatter for retained models.

`keep one local-authoritative transcript formatter for retained models`

Confirmed: preserve the readable `Speaker: text` representation, but build it from authoritative local segment rows and conversation-local speaker labels. Use that same representation for retained summary, memory, task, insight, follow-up, and Chat inputs so provider choice does not change the transcript meaning. Delete hosted People queries, `person_id` resolution, and parallel cloud-authoritative formatting branches.

Acceptance group: A11.


### IR-392

User name inside model transcript context.

`keep the authenticated first-name behavior without a Firestore profile fallback`

Confirmed: source the first name from retained Firebase Auth/local auth state and pass it into the local transcript formatter. Fall back to `User` when no name exists. Delete the duplicate Firestore-name fallback and any synchronization used only to support it. Keep the user-facing Mac and clipboard label `You` unchanged.

Acceptance group: A11.


### IR-393

Optional timestamps in model-formatted transcript text.

`keep the optional timestamp formatter and overlap guard unchanged`

Confirmed: retain `get_timestamp_string`, the optional `include_timestamps` behavior, and `can_display_seconds` overlap/order check exactly as implemented. Keeping this harmless helper does not retain hosted RAG, Firestore conversations, cloud vectors, or any backend conversation authority. Exact segment start/end values remain authoritative local data regardless of whether a formatted consumer requests these labels.

Acceptance group: A11.


### IR-394

Server-controlled `/v4/listen` conversation timeout and rollover.

`delete server conversation timeout, polling, rollover, and finalization ownership`

Confirmed: remove `conversation_timeout`, cloud in-progress-conversation reuse, the five-second lifecycle poll, server-created rollover conversations, stale hosted-conversation recovery, and listen-triggered cloud finalization. The retained `/v4/listen` connection emits transient transcript results only.

Keep the Mac's existing local meeting detector, explicit Stop and Finish-and-Continue actions, four-hour maximum rotation, WebSocket watchdog, and reconnection behavior. Those local boundaries—not Python silence polling—decide when a local recording starts and ends.

Acceptance group: A11.


### IR-395

Python `/v4/listen` spoken-question onboarding mode.

`delete the Python spoken-question onboarding mode`

Confirmed: delete the `/v4/listen` onboarding parameter, `OnboardingHandler`, its question catalog and LLM answer check, the synthetic speaker-99 segments, `skip_question` input, onboarding WebSocket events, and onboarding-only transcript/STT branches.

Keep the separately audited native Mac onboarding unchanged. This deletion does not remove its screens, fixed conversational presentation, local answers, permissions, PTT demonstration, or completion lifecycle.

Acceptance group: A11.


### IR-396

Phone-call identity on `/v4/listen`.

`delete listen call identity`

Confirmed: remove the `/v4/listen` and `/v4/web/listen` `call_id` parameter, request field, and durable conversation assignment. This decision does not by itself delete generic channel-count handling; that audio concern remains separate and must be challenged on its own evidence.

Acceptance group: A11.


### IR-397

Client-to-cloud conversation identity and reconciliation handshake.

`delete the client-to-cloud conversation identity handshake`

Confirmed: stop sending `client_conversation_id`; remove its Python recording-session and Firestore identity behavior; delete `conversation_session` lifecycle events; and delete the Mac's backend-conversation binding, rotated-ID tracking, and cloud-reconciliation state used for this handshake. The authoritative recording identity remains local to the Mac.

Keep the existing WebSocket watchdog and reconnect behavior for transient cloud STT, together with local generation/session fencing needed to prevent late results from crossing local recording boundaries. Reconnection resumes delivery into the same local recording; it does not recreate a cloud conversation.

Acceptance group: A11.


### IR-398

Duplicate browser-style `/v4/web/listen` admission route.

`delete the duplicate browser listen route`

Confirmed: remove `/v4/web/listen`, its five-second first-message authentication exchange, `auth_response` protocol, and device-context parser used only by that route. Keep `/v4/listen` and its normal Firebase-authenticated WebSocket admission unchanged.

Acceptance group: A11.


### IR-399

Special multi-channel `/v4/listen` audio protocol.

`delete the special multi-channel listen protocol`

Confirmed: remove tagged-channel frame routing, channel-role configuration, per-channel STT sockets/decoders/buffers, special mixing/tail flush, and multi-channel-only lifecycle branches. Retain the ordinary mono `/v4/listen` audio path.

This deletion does not remove Mac microphone capture, system-audio capture, its existing downmix/mixing behavior, or normal STT diarization. It also does not decide whether generic audio helpers shared by another proven path survive; delete only code exclusive to the rejected listen protocol.

Acceptance group: A11.


### IR-400

Client-supplied listen STT-provider preference.

`delete the client STT-provider hint`

Confirmed: remove the public `stt_service` request field and preferred-service reordering driven by it. Keep internal server-owned provider selection, capability checks, configuration gates, fallback, and diagnostics until the deferred provider/model audit decides the actual managed lineup.

Acceptance group: A11.


### IR-401

Functional backend VAD gate and unused client override.

`keep the server-configured VAD gate; delete only the client override`

Confirmed: retain the functional Python VAD gate, its deployment-controlled default, managed-stream integration, diagnostics, and fail-open behavior. Remove the unused `vad_gate` query parameter, request field, and per-socket enable/disable override.

Leave the Mac Local VAD Gate UI, local preference, restart side effect, and current disconnected behavior exactly as already decided under IR-228; do not wire it to Python as part of this cleanup.

Acceptance group: A11.


### IR-402

Live translation of cloud-STT transcript segments.

`keep cloud-STT live translation as transient compute with local result authority`

Confirmed: preserve the existing multilingual cloud-STT translation behavior, target-selection rules, visible italic secondary line, and local SQLite persistence. Send the Mac-local preferred language as session input rather than reading or synchronizing a Firestore transcription preference. Return translations directly to the Mac without first requiring a durable cloud conversation write.

IR-726 subsequently narrows the provider chain to the existing Gemini 2.5 Flash-Lite path and deletes the separately deployed NLLB GPU service without changing this retained user behavior.

Do not add local Parakeet translation for v1, upload local Parakeet transcript text for translation, or introduce a new local translation model. The current provider difference remains explicit: retained transient cloud STT can translate; private local Parakeet remains local and untranslated.

Acceptance group: A11.


### IR-403

Legacy codec and audio-format compatibility on `/v4/listen`.

`narrow retained listen audio to mono 16 kHz linear PCM`

Confirmed: make `/v4/listen` accept the Mac's fixed mono 16 kHz linear-PCM contract and remove listen-only PCM8, Opus, AAC, LC3, frame-duration, variable-sample-rate, and decoder-native-library compatibility.

Do not delete a codec implementation proven necessary by another retained endpoint such as PTT. This decision removes only its `/v4/listen` negotiation and decoding surface. Mac microphone capture, system-audio capture, downmixing, and delivery of the resulting linear PCM remain unchanged.

Acceptance group: A11.


### IR-404

Stable per-install device identity on the listen socket.

`delete stable listen-device identity; keep coarse platform diagnostics`

Confirmed: stop sending and processing `X-Device-Id-Hash` on `/v4/listen` and remove listen-specific client-device identity construction and durable conversation provenance. Retain coarse `macos` platform context where the existing privacy-bounded STT failure diagnostics use it. Remove the currently unused app-version field from this listen session unless a separately verified diagnostic consumer owns it.

This is a decision about the retained STT socket only. It does not automatically remove common headers from unrelated retained API calls whose requirements have not been audited.

Acceptance group: A11.


### IR-405

Listen service-status and last-cloud-conversation events.

`keep ready/failure truth; delete logged-only and cloud-lifecycle statuses`

Confirmed: retain the `ready` and `stt_failed` status behavior that truthfully drives the Mac's transcription availability state. Delete `initiating`, `stt_initiating`, `in_progress_conversations_processing`, and `last_memory` emission and handling.

Keep direct transcript delivery and separately retained subscription-limit signaling. Conversation-session, cloud-memory lifecycle, photo, and speaker-identity events follow their already confirmed deletion decisions; translation remains under IR-402.

Acceptance group: A11.


### IR-500

Home as the default landing surface and history-aware Chat host.

`keep Home as the default destination and keep the current history-aware hub-versus-Chat resting policy`

Confirmed: retain Home as the normal post-authentication and post-onboarding landing route. While the canonical Chat journal is still restoring or has no messages, Home may rest on the orientation hub. Once restoration completes with durable history, the shared main Chat timeline becomes Home's resting surface and must not collapse back to the hub on Escape or an outside click.

Keep the existing single-`ChatProvider` ownership, atomic-history reveal, **Continue in Omi**/Ask navigation into that same Chat, and deferred-focus fence. Do not infer that this retains the current hub contents, Connect mode, separate `ChatPage` route, or any child surface; audit each independently.

Acceptance group: A12.


### IR-501

Personalized readiness greeting on the empty-history Home hub.

`keep the current local greeting unchanged`

Confirmed: retain the local/account given-name greeting **Hey [first name]. I'm ready.** and the anonymous **I'm ready.** fallback. Keep it immediate, outside Chat history, and independent from runtime/backend/quota health aggregation. Rebranding may replace product identity assets later without changing this greeting behavior.

Acceptance group: A12.


### IR-502

Focus-state claim at the start of the Home daily brief.

`keep the Focus-state claim exactly as it is`

Confirmed: preserve the existing **Deep in [app] today / Heads-down today / A scattered stretch just now** behavior without adding a freshness boundary. Home may continue to use the newest restored `FocusStorage.currentStatus` and `currentApp`, including a persisted result from an earlier day or monitoring run, and may describe that result as **today** or **just now**. Keep the existing fallback to `detectedAppName` and the current suppression of empty or **unknown** app names.

Acceptance group: A12.


### IR-503

Open-task count at the end of the Home daily brief.

`keep the Home task count exactly as it is`

Confirmed: preserve the current recent-overdue/today/recent-undated task window, the per-query limits, and the exact **nothing's waiting on you / one thing needs you / N things need you** copy. Continue excluding future tasks, tasks outside the seven-day windows, and rows beyond the query caps. A task hidden from the Home knows-list may continue to reduce this headline count even though the underlying local task remains incomplete and undeleted. Under IR-025, the surviving count will use local `ActionItemStorage` after backend task synchronization is removed.

Acceptance group: A12.


### IR-504

Diverse, automatically rotating knows-list on Home.

`keep the diverse typed list, but stop automatic rotation`

Confirmed: retain the compact mixed task/insight-or-tip/task/question composition, its blank filtering and question deduplication, and its reuse as a smaller suggestion set above an empty Home Chat. Remove the seven-second hub and empty-Chat rotation behavior. Displayed rows remain stable until their underlying retained data changes or the user acts on them; do not add a manual rotation control unless later evidence establishes a need.

Acceptance group: A12.


### IR-505

Retained local Insight rows on Home must actually open and dismiss.

`keep retained local Insights on Home and make their local actions functional`

Confirmed: after the cloud recommendation source is removed under IR-026, continue surfacing retained locally generated Insights in Home's mixed list. Clicking a local Insight opens the same real detail lifecycle used by the retained Insights page and marks it read according to that lifecycle. Its **x** updates the authoritative local dismissed state so the row genuinely disappears. Remove recommendation-only **Later**, feedback-reason, intervention, and attribution behavior rather than attaching it to ordinary local Insights. Under IR-034, these actions operate on tagged local GRDB Insight records, not the duplicate `StoredInsight` UserDefaults cache slated for removal.

Acceptance group: A12.


### IR-506

Home task rows open the real task; hiding is presentation-only.

`keep the current task-row navigation and temporary presentation-only hide`

Confirmed: clicking a Home task row continues to navigate to Tasks, reveal the exact authoritative local `TaskActionItem`, clear incompatible list filters, scroll to it, and select its normal detail. The hollow circle remains a type icon rather than an inline completion control. The **x** continues to hide the row only in the current Home view state; it must not complete, delete, permanently suppress, or create a persisted snooze for the task. The row may return when the Home view is reconstructed or the app relaunches.

Acceptance group: A12.


### IR-507

Contextual fallback Chat tip in the Home mixed list.

`keep the current contextual fallback and editable prefill exactly`

Confirmed: when no retained Insight occupies the mixed list's tip slot, keep the existing priority order and exact prompt text: restored/current distracted Focus state produces **Help me get back on track**; otherwise five or more currently counted Home tasks produces **Sort my open tasks — which 3 actually matter today?**; otherwise use **Recap what I got done today**. Continue reusing the Focus and task semantics retained by IR-502/503. Clicking the row only prefills and focuses the canonical Home Ask bar for review; it must not send automatically or create a separate feedback/persistence lifecycle.

Acceptance group: A12.


### IR-508

Once-daily personalized questions generated for Home.

`keep once-daily personalized questions from bounded local-authoritative context`

Confirmed: retain up to two owner-scoped personalized Home questions per local calendar day, the immediate owner-keyed local cache, sanitization/deduplication/length limits, account-switch authorization fence, successful-empty daily hold, transport-failure retry, universal first question, static fallbacks, and editable Ask-bar prefill. Replace all server memory/conversation/action-item/goal reads with bounded recent/relevant reads from their authoritative local stores and send only that selected context for transient Gemini generation. Do not restore backend product-data copies for this surface. Remove the orphaned `PostOnboardingPromptSuggestions` input under IR-160.

Acceptance group: A12.


### IR-509

Focused-goals strip above the Home Ask bar.

`remove the goals strip and goal-management sheets from Home`

Confirmed: delete `FocusedGoalsSection`, its **Focused goals / No focused goals / All goals / Add goal / Choose focus** Home presentation, and the Home-owned canonical goal management/detail/create/focus/replacement sheets and error wiring. Do not rebuild an **Active goals** strip against the simple local model. This removes the more complex Home branch while preserving the one simple local Goals feature, its surviving dedicated management surface, and its retained use as context for normal Chat and Focus under IR-027. IR-028's deletion of goal-origin workstreams and **Work on this with Omi** remains unchanged.

Acceptance group: A12.


### IR-510

Home Ask bar as the canonical main-Chat composer.

`keep the current shared Home Ask composer and send/stop behavior`

Confirmed: retain the direct binding to the canonical `ChatProvider.draftText`, focus/keyboard entry into Home's shared inline Chat, one-to-six-line field growth, Return-to-send, Shift+Return newline, whitespace-only rejection, `sendMainDraft` acceptance/clearing ownership, and Send-to-Stop replacement while the main assistant is responding. Do not introduce a separate Home quick-question draft or session. Preserve the existing deferred-focus generation fence and canonical main-Chat continuity retained by IR-500.

Acceptance group: A12.


### IR-511

File attachments staged from the Home Ask bar.

`keep the current Home attachment UX with a required text instruction`

Confirmed: retain Home paperclip selection, file-URL drag and drop, shared `ChatProvider.pendingAttachments`, local previews, individual removal, four-file cap, and continuity from hub into inline Chat. Continue requiring nonblank text before Send appears or Return submits; do not invent an attachment-only implicit prompt. Implement the already-decided IR-044 lifecycle beneath this UI: copy/materialize attachments into the owner/session-scoped app-managed local store before journal admission, pass managed local URIs and relevant image bytes to the agent, and remove `/v2/files`, upload waiting, cloud identifiers, Firestore/OpenAI Files/GCS persistence, and public thumbnails.

Acceptance group: A12.


### IR-512

Connect button and connector/export tray inside Home.

`delete the complete Home Connect branch by dependency`

Confirmed: remove the Ask-bar **Connect** action and empty-state action mode; `HomeStageMode.connect`; the source/destination tray and cards; connector/export/device/Apps status and selection state; import/export/catalog sheets and popup entry points; device website shortcut; Connect-specific focus, collapse, Escape, modal, animation, responsive-layout, telemetry, and automation behavior; and exclusive tests/contracts. Home simplifies to the retained hub and canonical inline Chat modes. Do not preserve an empty placeholder or invent a replacement integration surface without a new requirement.

Acceptance group: A12.


### IR-513

Obsolete cloud Dashboard Intelligence coordinator on Home.

`delete DashboardIntelligenceStore and preserve only local task navigation separately`

Confirmed: remove the cloud dashboard coordinator, its client/projection/recommendation/goal/action/outbox models, load and foreground-refresh lifecycle, What Matters Now notification listeners, recommendation and canonical-goal actions, generation/idempotency state, error/retry card, attribution/telemetry, desktop automation registration, rich UI, and exclusive tests. Do not repurpose it as an umbrella over retained local owners. Extract `TaskNavigationRequestStore` into a narrow local task-navigation source so IR-506's Home-to-Tasks shortcut survives without the rejected control plane.

Acceptance group: A12.


### IR-514

Static welcome inside an explicitly opened empty Home Chat.

`keep the static empty-Chat welcome, rebranded and truthfully scoped`

Confirmed: preserve the transparent local logo/title/subtitle welcome whenever inline Home Chat is explicitly open with no messages and no pending onboarding opener. Replace `herologo.png` and **omi** with the new product identity, and phrase the subtitle as the ability to use authoritative local memories and conversations when available rather than claiming an empty account is already known through them. Keep IR-144's genuine completion opener as the higher-priority branch. Do not generate or journal a greeting for the ordinary empty state.

Acceptance group: A12.


### IR-515

Home Capture status and start/stop control.

`keep the Home Capture control unchanged`

Confirmed: retain Home's **Capture** capsule as the live On/Off/Blocked control for the proactive screen-monitoring runtime. Keep immediate start/stop, native Screen Recording permission repair, failed-start rollback, in-flight feedback, runtime-state reconciliation, and the Home context-menu shortcut to Rewind. The indicator must continue following the actual monitor rather than merely the saved preference.

Acceptance group: A12.


### IR-516

Home Listening status and start/stop control.

`keep the Home Listening status exactly as it is`

Confirmed: retain the current collapsed status semantics and copy. Whenever the broader transcription session is armed, Home may show the green **Listening** state even while Meetings-only mode is waiting with both microphone and System Audio capture stopped. Continue revealing **Meetings only** versus **In meeting** only on hover. Keep the neutral off state, red **Transcription unavailable** override, immediate main-area start/stop, Microphone permission request, shared local owner, and current transition feedback unchanged.

Acceptance group: A12.


### IR-517

Home's hover-only Meetings-only / Always listening-mode switch.

`keep live Home mode switching, presented as an explicit named choice`

Confirmed: retain the ability to change an armed transcription session between **Meetings only** and **Always** directly from Home without stopping or restarting listening. Replace the hover-only one-click person icon with a clear selector that names both choices before applying one. A deliberate selection may reconfigure the active session immediately; no additional confirmation step is required. Keep the setting local and continue using the shared `AssistantSettings` notification/reconciliation path.

Acceptance group: A12.


### IR-518

Responsive single-column Home stage and readable width caps.

`keep the responsive single-column Home stage and current readable width caps`

Confirmed: retain one continuously responsive centered Home layout. Keep the proportional side inset clamped to 30...96 points, the 1,360-point maximum general stage width, the 900-point maximum Chat/message-column width, and shrink-to-fit behavior for narrow windows. Do not add separate compact and regular Home implementations. Remove Connect-only geometry by dependency on IR-512, while preserving the surviving hub and Chat layout behavior.

Acceptance group: A12.


### IR-519

Compact hub Ask bar and draft-measured width expansion.

`keep the Home Ask-bar width behavior exactly as it is`

Confirmed: retain the compact 560-point/clamped empty hub width, the draft-measured hub expansion up to 980 points using the current text measurement plus chrome allowance, and the stable 900-point/clamped Chat width. Preserve responsive shrink-to-fit behavior and allow preserved or programmatically supplied hub drafts to resize the resting composer according to their measured character width.

Acceptance group: A12.


### IR-520

Reduced-motion-aware Hub / Chat stage transitions.

`keep the current reduced-motion-aware Hub / Chat transition`

Confirmed: retain the existing gated spring and paired vertical/fade/scale movement between the empty-history hub and canonical Chat. Continue honoring macOS **Reduce motion** by performing the same stage change immediately with no animation. Remove only Connect-specific movement by dependency on IR-512; do not make motion part of Chat restoration, focus, sending, or persistence.

Acceptance group: A12.


### IR-521

Home's neutral dark canvas and private color palette.

`keep Home's neutral dark appearance and consolidate its colors into the shared desktop theme`

Confirmed: preserve the current calm, neutral dark Home canvas, subtle gradient, contrast hierarchy, and no-purple boundary. Do not add a Home-only Light Mode. Treat the private hard-coded `HomePalette` as implementation duplication rather than a product requirement: map surviving Home components to shared theme tokens or promote genuinely distinct accepted values into that shared authority, then remove the parallel palette without intentionally changing the approved visual result.

Acceptance group: A12.


### IR-522

Local desktop-automation controls for the surviving Home workflow.

`keep local Home automation narrowed to the retained Chat workflow`

Confirmed: retain local-build, token-protected automation for opening Home Chat, collapsing an empty-history Chat to its resting hub, sending through the canonical Home Ask path, staging an attachment through canonical admission, and observing `hub`/`chat` mode. Delete the Connect command/event/mode and legacy-Home state/guards by dependency on IR-512 and IR-255. Keep the bridge routed through the same production functions as the UI; do not replace it with direct provider-state mutation or expose it in published builds.

Acceptance group: A12.


### IR-523

Home startup and foreground refresh after rejected dashboard features are removed.

`narrow Home startup and foreground work to surviving data owners`

Confirmed: Home and startup should load/refresh only retained Tasks through `TasksStore`, owner-scoped once-daily questions through `HomeSuggestionsStore`, canonical Chat restoration/navigation through `ChatProvider`, and capture/permission truth through `AppState` and the capture owner. Remove Home score, goal, cloud-intelligence, connector/export/count/device-history loads and their foreground observers. Remove the broad `DashboardViewModel` once only task observation/refresh has moved to `TasksStore`. Preserve the underlying import-connector status owner for Onboarding and Apps through direct ownership/injection rather than retaining unused Home projections.

IR-160 independently closes the obsolete **Try asking** popup and stored onboarding-suggestion readers still present in Home lifecycle code; they are deleted by that settled decision and are not a new Home requirement.

Acceptance group: A12.


### IR-524

Unreachable standalone Chat page beside Home's canonical Chat.

`delete the hidden standalone ChatPage and route semantic Chat navigation to Home`

Confirmed: remove `ChatPage`, the hidden page-index-2 branch/destination, exclusive presentation state/views/tests/previews, and accidental raw-index entry. Route developer automation target **chat** through the same `.navigateToChat` Home path used by customer shortcuts. Preserve explicit raw values for later navigation items rather than renumbering them accidentally. Keep `ChatProvider`, the canonical Home/floating timeline, Home composer/attachments, and shared components with other proven live callers.

IR-045 already deletes the standalone page's cloud Chat-app/persona picker and app-specific normal-Chat behavior. That settled child is not relocated into Home.

Acceptance group: A12.


### IR-525

Multiple local Chat threads inside canonical Home Chat.

`integrate a compact complete Chats catalog into Home Chat`

Confirmed: when **Multiple Chat Sessions** is enabled, canonical Home Chat will expose one compact **Chats**/current-title control that opens the complete locally authoritative thread catalog: New Chat, selection, search, starred filtering, rename, star/unstar, and confirmed deletion. Selecting or creating a thread keeps the customer inside the same Home Chat timeline and composer; creating or selecting an empty thread keeps Home on the Chat stage for that explicit interaction. When multiple sessions are disabled, the control remains absent and the existing one-default-Chat experience remains unchanged.

This does not restore the hidden standalone Chat page or introduce another message authority. The existing orphaned catalog presentations should be consolidated into the one reachable Home control rather than retained as parallel implementations.

Acceptance group: A12.


### IR-526

Generic Chat failures are invisible in canonical Home.

`preserve the existing failure behavior and render its missing fallback in Home`

Confirmed: canonical Home Chat will keep the current three-way failure presentation. Restoration/catalog failures remain inside the timeline with **Try Again**; recognized recoverable failures retain `ChatErrorCard` and its tailored Retry, Sign In, Install Runtime, or Dismiss action; remaining user-actionable `errorMessage` failures gain the same dismissible, user-safe warning currently rendered only by the hidden standalone page.

This is not an error-model redesign. Preserve the existing clearing lifecycle so a new send or active-Chat transition does not leave stale per-turn warnings visible, and keep the floating bar's compact combined failure presentation unchanged.

Acceptance group: A12.


### IR-527

ChatPage-only Claude-auth sheet and lifetime-cost upgrade nudge.

`delete both obsolete page-exclusive modals and keep the shared quota popup`

Confirmed: delete the unreachable `ClaudeAuthSheet` presentation, `isClaudeAuthRequired`, the uncalled sheet-launch path and state that have no independent live consumer, plus the hidden `$50` lifetime Omi-AI spend nudge. Remove the Mac lifetime-cost startup fetch/accumulator/checks, `showOmiThresholdAlert`, hardcoded Omi pricing/URL alert, and exclusive tests after confirming released-client/backend compatibility.

Preserve the authoritative count-only usage/cost accounting, entitlement and monthly quota checks, globally mounted `UsageLimitPopupView`, and its Upgrade navigation into Account & Plan. Rebrand that retained shared flow for our product and Dodo plan catalog, and remove its **Bring your own keys** action under IR-062. This page-exclusive modal decision did not itself resolve the broader Advanced Settings agent-provider/harness picker; the later IR-800 decision deletes that picker, its connection/disconnect state, and all non-Pi adapters and overrides.

Acceptance group: A12.


### IR-528

Top-bar “new since you were last here” counters.

`delete the top-bar aggregate new-item counters`

Confirmed: remove `topBarNewSince` persistence and active/background timestamp mutation; aggregate conversation/memory/task count calculations; `+N` capsules; badge-driven pill-width expansion; and exclusive tests/comments. Keep the **Memory** and **Tasks** top-bar destinations, their retained local data, and the compact navigation unchanged apart from removal of the nonexistent badge concept.

This does not remove the separate one-minute row-level **New** treatments already retained for Memories and Conversations under IR-275/317, and it does not create a replacement unread/read authority.

Acceptance group: A12.


### IR-529

Global Escape navigation back to Home.

`keep the current shell-level Escape-to-Home behavior exactly`

Confirmed: retain the shell `.onExitCommand` and its current precedence and destination set. Child-owned Escape behavior remains first: local sheets, panels, details, Memory Atlas, and Home's guarded empty-Chat collapse continue handling their own dismissal. When no child consumes Escape, Conversations, Memories, Tasks, and Rewind navigate to Home with the existing reduced-motion-aware page transition. Keep Home, Settings, permissions, help, and other excluded destinations unchanged.

Acceptance group: A12.


### IR-530

Compact top navigation on narrow windows.

`keep the current responsive top-navigation substitution`

Confirmed: retain direct **Home / Memory / Tasks** pills whenever the complete row fits and substitute the complete named **Navigate** menu when it does not. Preserve the nested Memories/Conversations destination behavior in the compact menu, the custom no-overlap layout, enlarged-font handling, accessibility labels, and focused layout tests. Keep Capture, Listening, and Settings persistently visible. Remove only Apps and badge-specific width behavior under IR-046/047 and IR-528.

Acceptance group: A12.


### IR-600

Daily Artificial Analysis-backed Auto realtime-provider selection.

`reopened and resolved - delete Auto, the Voice Model picker, and Artificial Analysis; server-pin realtime voice to Gemini Live`

There is no remaining provider portfolio to rank. Delete the saved selection,
daily refresh and caches, `/v1/auto/model-pick`, Artificial Analysis client and
credential, provider-status UI, and provider-change rewarm branch. Keep the
separate OpenAI TTS voice picker unchanged.

Acceptance group: A13.


### IR-601

Realtime voice escalation to the managed Claude model.

`delete the realtime ask_higher_model tool entirely`

Reopened and confirmed after the live-web mismatch was explained: remove `ask_higher_model` from the source tool manifest and regenerated Gemini schema, realtime capability lists, authorization surface, provider instructions, dispatch switch, synthetic harnesses, and tests. Delete its unique Mac execution path: `escalateToHigherModel`, escalation prompt/body construction, `omi_web_search` flag, owner-bound higher-model transport, response parsing, failure text, logging, and comments. Remove files or context/cache plumbing only when no surviving caller remains after regeneration and reference tracing.

Gemini Live now owns every ordinary voice answer itself. It must answer, decline,
or state that it cannot verify live information; voice no longer calls a second
model for another opinion. Normal typed Chat remains under IR-113's native
managed-Gemini boundary. IR-603 separately deletes the Agent Pill title/ack
caller, while IR-061/600 delete provider choice and cross-provider failover.

Acceptance group: A13.


### IR-602

Truthful live web lookup for voice escalations.

`delete by dependency with the entire ask_higher_model tool under IR-601`

Confirmed: do not build a voice-specific web-search continuation. Deleting `ask_higher_model` removes its current-facts tool description, escalation prompt, `omi_web_search` request field, unsupported freshness claim, and all prospective source/citation projection for this path. Normal typed Chat's separate public-web behavior is outside this deletion and remains unchanged.

Acceptance group: A13.


### IR-603

Claude-generated Agent Pill title and acknowledgement.

`delete the Claude Haiku title/ack call and keep Agent Pill metadata local for v1`

Confirmed for v1 simplicity and ease of mind: remove `generateTitleAndAck`, its extra authenticated `/v2/chat/completions` request, Haiku model selection, prompt, eight-second timeout, response/JSON parsing, late title/status mutation, logs, comments, and tests that exist only for this cosmetic call. Remove the unused generated acknowledgement and instant-ack helpers only where reference tracing proves no surviving caller.

Preserve the immediate deterministic title derived from the request, the normal `Starting…` -> `Working…` -> terminal status lifecycle, any authoritative title or acknowledgement already supplied by the router, account-owner fencing around surviving pill updates, and all background-agent execution, results, journal, and UI behavior unrelated to cosmetic generation. Native managed Gemini remains for normal typed Chat under IR-113.

Acceptance group: A13.


### IR-604

Shipped Chat Prompt Lab and direct Anthropic BYOK.

`delete Chat Prompt Lab entirely from the v1 desktop app`

Confirmed: remove the unconditional Advanced Settings Dev Tools card, `ChatLabView` and its window manager/view model/data models, the `chatlab_anthropic_api_key` preference and direct Anthropic requests, prompt generation and AI grading, real-context lab questions and isolated `chat_lab` runtime surface, repository/git prompt-history reader, production-ratings attribution, prompt-version comparison/editor state, ChatProvider lab-only helpers, ChatLab-only model constants, and exclusive tests and documentation. Reference-trace shared Chat/runtime helpers before removal and retain anything with an independent production caller.

This does not change normal Chat, its production prompt, the local Node/Pi loop, managed Gemini inference retained under IR-113, production message rating behavior outside the lab, or repository-level testing. If prompt evaluation is needed later, build it as an explicitly internal harness or developer script that is not shipped to customers and does not recreate customer BYOK.

Acceptance group: A13.


### IR-605

Dormant Opus and model-selection scaffolding in Sonnet-only Chat.

`reopened and resolved - pin normal Chat to the actual gemini-3.7-flash ID and delete all Claude identities and selection scaffolding`

Confirmed: make `gemini-3.7-flash` authoritative for retained normal Chat and
background-agent launches. Remove the selected-model preference, dead menu,
Opus registration/mappings, `omi-sonnet` runtime alias, and Claude-only tests and
comments. Migrate the current development SQLite profile once by appending a new
canonical execution-profile generation; historical audit rows may retain their
original value but no runtime alias survives.

Preserve the local Node/Pi loop, tools, context, journal, and managed Python
inference boundary. Realtime voice is separately pinned to Gemini Live under
IR-061. Flash-Lite workloads remain separately retained.

Acceptance group: A13.


### IR-606

Orphaned desktop Haiku and ChatLab model identities.

`delete by dependency`

When those product callers are removed, also delete `ModelQoS.Claude.synthesis`, `chatLabQuery`, and `chatLabGrade`, their exclusive tests/comments, and any desktop-Chat gateway Haiku or dated alias with no surviving in-tree or released-client contract. This does not delete Haiku from unrelated backend workloads merely because they use the same provider model name; each independent Python workload remains separately auditable.

Acceptance group: A13.


### IR-607

Per-attempt LLM-gateway Firestore accounting ledger.

`resolved - delete the unread per-attempt Firestore accounting ledger`

Confirmed: remove the `llm_gateway_attempts` writer, detached persistence queue, accounting-delivery configuration, Firestore/IAM bindings used only by this ledger, cost-rate-card machinery used only to price these documents, and exclusive documentation/tests. Retain authoritative subscription, entitlement, usage, and quota counters; retained request/failure/latency/fallback metrics; and any billing record that a separately retained payment or quota flow actually reads.

This decision deletes only the unread persistent receipt for each provider attempt. It does not yet decide whether the separately deployed LLM gateway itself survives; that operational boundary is IR-608.

Acceptance group: A13.


### IR-608

Separately deployed internal LLM gateway.

`resolved - delete the separately deployed LLM gateway and collapse retained routing into the owning Python backends`

Confirmed: normal typed Chat will call managed Anthropic Sonnet directly from the Python desktop backend. Each separately retained product/background model workload will call its chosen managed provider through the shared in-process Python client layer. Remove the standalone `backend/llm_gateway` service; GKE/Helm release; internal ingress/static-address and VPC connectivity boundary; service-token/caller-auth plumbing; gateway mode, auto lanes, route artifacts, shadow/promotion scaffolding, circuit and transport wrappers exclusive to the extra hop; independent deployment/probe/validation workflows; gateway-only metrics/docs/tests; and IR-607's already rejected attempt ledger.

Retain the Mac's local Node/Pi agent loop and tool controls, normal Chat, selected Python AI workloads, managed provider credentials, authoritative quota/usage accounting, sanitized workload metrics, and workload-owned timeout/retry/fallback behavior. The OpenAI Realtime/Gemini Live switching and failover retained under IR-061 is a separate native voice path and is unchanged.

Removing the gateway does not silently preserve every provider/model route currently named by its generated configuration. IR-609 and later workload audits must choose one explicit direct route for each surviving Python feature and delete routes whose product workload was already rejected.

Acceptance group: A13.


### IR-609

Global premium, max, and BYOK model-QoS profiles.

`resolved - delete the global model-QoS profile system and keep one explicit route per surviving workload`

Confirmed: remove the duplicated `premium`, `max`, and `byok` maps; the global startup `MODEL_QOS` selector; customer-BYOK route upgrades; profile-name/accessor/logging machinery; and profile-only tests/docs/config. Replace them with one typed managed provider/model route for each workload that survives its own audit. Delete a workload's route when that workload is rejected rather than keeping dead feature vocabulary in a generic map.

This decision does not choose every remaining provider/model in bulk. The
reopened provider decisions now pin normal Chat and retained managed text to
Gemini 3.7 Flash, and pin realtime voice to Gemini Live under IR-061/600.
Remaining workload decisions still resolve their own behavior once.

Acceptance group: A13.


### IR-610

GPT-based fair-use classifier and graduated transcription restriction.

`reopened and resolved - keep fair-use protection and route its bounded transient classification through Gemini 3.7 Flash`

Confirmed: preserve rolling usage awareness, a conservative abuse-review step after soft triggers, graduated warning/throttle/restrict states, a user-visible explanation/appeal path, support controls, and the deterministic impossible-volume ceiling. Do not collapse all protection into the ordinary monthly quota.

This is not approval to keep the current implementation verbatim. Its hosted-conversation evidence is no longer authoritative, the `throttle` stage currently claims a quality reduction that no production reader performs, and Omi/Deepgram/on-device wording and legacy plan types must become our own Dodo-backed contract. IR-611 through IR-709 now resolve the evidence, inference, thresholds, enforcement effects, recovery, user/support surfaces, retention, and operational-override boundaries.

The fair-use branch is now closed. Its children preserve the existing product
pattern while moving durable evidence authority to local GRDB, routing bounded
transient classification through the canonical Gemini 3.7 Flash workload,
retaining content-free backend enforcement/support state, and recording the
user's explicit choices where current behavior remains intentionally imperfect.
The Gemini-first implementation preserves the existing classifier schema,
parser, and fail-open behavior; it does not restore hosted conversations or
make model output durable product authority.

Acceptance group: A13.


### IR-611

Local-conversation evidence admitted to fair-use classification.

`resolved at the evidence-source boundary - adapt the existing recent-conversation pattern to local authority`

Confirmed flow:

```text
backend rolling speech meter crosses a soft trigger
  -> Mac receives a fair-use review request
  -> Mac reads up to thirty recent conversations from local GRDB
  -> assemble the current bounded evidence shape locally
     (generated title, first 200 overview characters, category,
      duration, source, and time)
  -> classifier returns the conservative misuse score/type/evidence result
  -> backend remains authoritative for warning/throttle/restrict state
```

Do not recreate durable hosted conversation documents, upload raw transcripts/audio, or let an empty/stale server conversation query stand in for the Mac's real local history. The evidence is assembled only after a soft trigger and exists only for that review.

This decision establishes where the evidence comes from, not yet where model inference runs. The repository has no existing general-purpose on-device language model for this task. `AgentBridge` is a local runtime/orchestrator, but its normal model inference is managed Gemini through the Python desktop backend, so using it would still send the bounded title/overview evidence off the Mac. IR-612 resolves that boundary explicitly.

Acceptance group: A13.


### IR-612

Local-authoritative evidence with the existing cloud GPT-5.1 classifier.

`reopened and resolved - keep local-authoritative evidence and replace GPT-5.1 with Gemini 3.7 Flash as bounded transient compute`

Confirmed flow:

```text
backend detects a rolling soft-cap trigger
  -> authenticated Mac reads up to thirty local evidence records
  -> send one bounded, owner-authorized evidence request
  -> backend Gemini 3.7 Flash classifier uses the retained prompt/recipes/schema
  -> transient result contains misuse_score, type, confidence,
     evidence, and reasoning
  -> discard request content and detailed result after deriving bounded facts
  -> backend applies the retained graduated enforcement policy
```

Preserve the recent seven-day/up-to-thirty-conversation window,
title/overview/category/duration/source/time evidence, prompt, recipes,
conservative legitimate-use rules, misuse score, coarse usage type, confidence,
evidence selection, parser behavior, warning/throttle/restrict decision contract,
and fail-open policy. Gemini 3.7 Flash replaces GPT-5.1 only at the bounded
transient inference boundary; local GRDB remains the evidence authority.

No raw audio, full transcript, screenshot, person/name, or unbounded conversation payload leaves the Mac. The exact bounded title/overview/category/duration/source/time evidence may cross only in the authenticated transient classification request. It must not enter Firestore, Redis, logs, metrics, crash reports, notifications, support responses, or a hosted conversation store. The backend remains authoritative for metered cloud usage, strikes, enforcement state, and the deterministic 30-hour ceiling.

IR-613 is resolved by this transient-compute boundary: Gemini may observe
bounded evidence for the live request, while the backend durably stores only
content-free verdict, usage, and enforcement facts.

Acceptance group: A13.


### IR-613

Durable storage of classifier conversation evidence.

`resolved by IR-612 - allow transient classifier content and persist only content-free case facts`

Confirmed: the authenticated classification request may contain only the existing title, first 200 overview characters, category, duration, source, time, and an opaque request-local evidence token for at most thirty conversations. The backend fair-use event retains account UID, rolling usage and thresholds, provider/model/prompt version, score, the existing coarse usage type, confidence, prior/new stage, action, timestamps, and case reference. No title, overview, transcript, raw audio, name, local conversation ID, prompt payload, selected evidence, content-specific reasoning text, or newly invented reason-code taxonomy is durably stored or logged.

Acceptance group: A13.


### IR-614

Meaning of the seven-day fair-use throttle stage.

`resolved - keep the notify-only final-warning stage and make its seven-day reset real`

Retain the existing three-strike progression. The second qualifying violation remains a notify-only grace stage before real restriction; it must not silently introduce a lower-quality STT provider, model, transcript, or allowance.

Replace customer-facing claims that transcription quality was reduced with truthful final-warning language. If no further qualifying violation occurs during the seven-day window, normalize the stage back to `warning`. A further qualifying violation inside that window may advance to the retained real restriction stage.

Acceptance group: A13.


### IR-615

Free allowance exhaustion treated as a fair-use violation.

`resolved - keep the current combined Free-quota and fair-use behavior`

Retain the existing `free_exhausted` shortcut. When a non-paid user has no transcription credits and crosses a fair-use soft cap, the backend may continue skipping semantic classification, recording the synthetic `misuse_score: 1.0` / `usage_type: free_exhausted` result, and advancing through the retained warning/final-warning/restrict stages.

Keep the ordinary quota/paywall response as well as the fair-use case history, notifications, restriction state, and payment-webhook cleanup that clears `free_exhausted` enforcement after a paid upgrade. This decision preserves the current product pattern; it does not claim that a semantic model inspected the Free user's content.

Acceptance group: A13.


### IR-616

One canonical Tasks list versus the unreachable Board view.

`keep the current grouped Tasks list and delete the unreachable Board implementation`

Confirmed: retain the visible grouped-list Tasks experience as the single canonical presentation. Delete `tasksViewIsBoard`, the hidden Board/List segmented control, `tasksBoardView`, Board columns and placeholders, `TaskBoardCard`, and tests or stored-preference handling used only by that unreachable layout. Do not redesign the visible list or silently remove any of its workflows; each surviving list behavior remains subject to its own child decision.

Acceptance group: A14.


### IR-617

Truthful label for the combined today-and-overdue task section.

`keep the combined urgent section and rename it Today & Overdue`

Confirmed: tasks with deadlines before tomorrow continue to share one first section and retain their current due-date ordering. Change only the user-facing heading from **Today** to **Today & Overdue**; do not add a fifth category or rewrite stored order keys. Individual due dates and overdue styling remain unchanged. Review the section's bulk “Clean today's tasks” action separately because it mutates those deadlines.

Acceptance group: A14.


### IR-618

Bulk deadline removal behind the Today-section × button.

`delete the bulk deadline-removal shortcut`

Confirmed: remove the first-section ×, its tooltip and confirmation alert, `clearTodayDeadlinesForIncompleteTasks`, the associated callback plumbing, and tests or copy used only by that bulk action. Keep individual due-date add/change/removal, due-date grouping, reminders, task completion, and task deletion unchanged. Do not replace the shortcut with another bulk planning workflow in this pass.

Acceptance group: A14.


### IR-619

Task search spanning both unfinished and completed work.

`keep the current global status search unchanged`

Confirmed: retain the current local, case-insensitive task-description search across both unfinished and completed non-deleted records. The To Do/Done toggle continues to control the normal list but does not narrow an active search query. Do not add a search-scope selector, backend search, semantic search, or model dependency. Preserve the existing completed styling so mixed-status matches remain distinguishable.

Acceptance group: A14.


### IR-620

Visible To Do/Done switch versus unreachable advanced task filters.

`keep the visible To Do/Done switch and delete the unreachable advanced-filter system`

Confirmed: retain the circled-check switch between unfinished and completed task views. Delete the inaccessible advanced-filter groups/tags, dynamic-filter types, matching/query branches, and legacy filtered-mode state used only by the removed popover. Preserve task tags, categories, priorities, sources, origins, deletion provenance, and any visible/detail or retained local-agent use of that metadata. Preserve drag/reorder safety with a direct internal seam rather than keeping dead product filters as its test trigger. Keep global local search unchanged under IR-619.

Acceptance group: A14.


### IR-621

Inline task creation versus the unreachable full creation sheet.

`keep inline task creation and delete the unreachable full creation sheet`

Confirmed: retain +, Command-N, Return-to-create, Escape-to-cancel, and inline creation after a keyboard-selected task. Delete `showingCreateTask`, `TaskCreateSheet`, its form-only state and controls, and tests or helpers used only by that unreachable modal. Keep task descriptions, due dates, priorities, tags, and their normal post-creation row editors. The silent context/deadline assigned by inline creation remains a separate child audit.

Acceptance group: A14.


### IR-622

Automatic section-derived deadline on inline-created tasks.

`keep Omi's current inline deadline behavior exactly as it is`

Confirmed: retain the current selected-row context lookup, section-derived deadlines, flat-view exact-date inheritance, +/Command-N selection influence, same-section **New below** placement, and absence of a due-date preview in the inline row. Keep the exact Today 11:59 PM, Tomorrow start-of-day, Later plus-seven-days, and No Deadline mappings. Do not add a confirmation, visible due-date chip, or separate global quick-add rule. These dates continue to participate in the retained local due-time reminder lifecycle.

Acceptance group: A14.


### IR-623

One-second autosave while editing task text.

`keep the current task-text editing behavior unchanged and make its writes local-authoritative`

Confirmed: retain click/double-Return entry, one-second debounced autosave, Return-to-save, click-away save, Escape **Save & exit**, trimming, and restoration of the prior text when the field is empty or unchanged. Preserve the manual-edit marker. Remove only backend mutation/rollback coupling when implementing IR-025; a successful local transaction becomes the completed edit.

Acceptance group: A14.


### IR-624

Completing and reopening an ordinary task.

`keep ordinary task completion and reopening unchanged, with local authority`

Confirmed: retain checkbox and Space-key completion, the current animation, immediate To Do/Done movement, completed history, and reopening of the same task record with its retained metadata. Integrate completion/reopening with the local reminder schedule/cancel/reconcile behavior from IR-101. Delete backend mutation, remote echo, and rollback-on-cloud-failure when implementing IR-025; a successful owner-scoped local transaction is final. Recurring next-occurrence behavior remains separate.

Acceptance group: A14.


### IR-625

Local next-occurrence lifecycle for repeating tasks.

`keep repeating tasks and localize next-occurrence creation`

Confirmed: retain Daily, Weekdays, Weekly, Every 2 Weeks, Monthly, and Never; the current completed occurrence remains in Done; and exactly one next future occurrence is created in To Do, skipping missed dates rather than generating a backlog. Perform completion plus next-occurrence creation as one owner-scoped local-authoritative transaction. Preserve description, priority, tags/category, recurrence rule, series identity/provenance, and other user-visible recurrence-safe metadata, then schedule the new local reminder under IR-101. Remove backend completion/create/echo dependence. Do not include automatic AI execution, which remains a separate child audit.

Acceptance group: A14.


### IR-626

Dormant automatic AI execution for due recurring tasks.

`delete the dormant recurring-task automatic-AI scheduler`

Confirmed: delete `RecurringTaskScheduler`, its coordinator configuration and shutdown call, its one-minute timer, four-hour agent retry gate, due-recurring-task query used only by it, and tests/guards specific to that dormant automatic-execution branch. Do not start a task agent merely because a recurring deadline arrives. Keep recurrence generation under IR-625, local notifications under IR-101, and explicit user-initiated assistance outside this deletion.

Acceptance group: A14.


### IR-627

Individual due-date editing and deadline removal.

`keep the existing date editor and add per-task deadline removal`

Confirmed: retain the current calendar-plus entry point, date-and-time picker, Save/Cancel behavior, relative date labels, and recurrence indicator. Add an explicit **Remove deadline** action inside the individual task's date popover. It clears only that task's due date, moves the task to **No Deadline**, persists through the owner-scoped local-authoritative task transaction, and cancels its pending due-time notification under IR-101. Do not restore the deleted bulk-clear action from IR-618.

Acceptance group: A14.


### IR-628

Per-task priority editor.

`keep the priority editor exactly as it is`

Confirmed: retain the hover-only **+ Priority** entry point for unfinished tasks, the High/Medium/Low choices, immediate selection and popover dismissal, selected checkmark, and visible priority badge. Do not add **No priority**, **None**, or another clearing action. Once assigned through the visible UI, a priority can be changed among the three retained levels but cannot be removed. Persist priority changes through the owner-scoped local-authoritative task transaction when implementing IR-025.

Acceptance group: A14.


### IR-629

Disconnected task tags and automatic tag metadata.

`delete task tags completely and add no replacement tag feature`

Confirmed: delete `TagBadgeInteractive`, its unused row/callback/update wiring, tag selection from the unreachable `TaskCreateSheet`, and task-tag editing tests. Stop asking Gemini task extraction for a multi-value tag list and remove task-tag generation, metadata serialization/accessors, detail/tooltip display, advanced-filter matching already rejected by IR-620, task-agent tag references already rejected by IR-028, and copying tags into recurring occurrences under IR-625. Do not add a visible tag editor or preserve a compatibility/migration path for nonexistent legacy users. Do not silently delete the distinct single task category or source/provenance fields; audit those separately and amend earlier broad tag-preservation wording in IR-025, IR-620, and IR-625 during implementation.

Acceptance group: A14.


### IR-630

Semantic Personal/Work/Bug task category.

`delete the semantic task category`

Confirmed: remove `TaskActionItem.category` and equivalent ordinary-task record/wire/storage fields where they exist only for this semantic category; stop deriving it from Gemini tags; remove its hover/detail and local-Chat prompt display; remove its recurrence/restore/copy propagation; and delete compatibility, hidden-filter, superseded-onboarding, task-agent, test, and generated-contract references exclusive to it. Do not add a replacement single-category model output or editor. Do not alter `TaskCategory` due-date grouping (Today/Tomorrow/Later/No Deadline) or `source_category`/`source_subcategory`; those are different concepts.

Acceptance group: A14.


### IR-631

Hidden two-level task source classification.

`delete the hidden two-level source classification`

Confirmed: remove `source_category` and `source_subcategory` from Gemini extraction prompts, tool schemas, parsed models, task metadata, local records/accessors, validation enums/helpers, dictionary/event payloads, hidden filter/query/count branches already rejected by IR-620, generated contracts where exclusive, and focused tests. Do not add replacement fields or UI. Preserve ordinary task source, source app, window title, context/current activity, confidence, capture-policy facts, and evidence/provenance required by retained automatic extraction under IR-031/032.

Acceptance group: A14.


### IR-632

Task information hover preview and full detail window.

`keep both task-detail surfaces and trim them to retained fields`

Confirmed: retain the information-circle button, hover-to-open preview, pointer-transfer delay, click-to-open full **Task Details** sheet, scrolling, fixed full-sheet presentation, and close behavior. Keep ordinary task state and the useful source/evidence fields required by IR-031/032. Remove category/tags under IR-629/630 and task-agent fields under IR-028; do not retain any other conditional or catch-all child merely because the shell survives. Audit remaining integration-specific and generic metadata sections separately.

Acceptance group: A14.


### IR-633

Generic rendering of arbitrary task metadata.

`delete generic unknown-metadata rendering`

Confirmed: delete the hover preview's `allMetadataEntries` catch-all and the full sheet's `remainingMetadata`/**Other Info** catch-all, including automatic snake-case-to-label conversion. Render only fields with an explicit retained user-facing requirement. Do not infer from this presentation deletion that internally required capture-policy, candidate-review, idempotency, or provenance metadata must also be deleted; audit storage ownership separately. Do not add an Advanced/raw-metadata replacement.

Acceptance group: A14.


### IR-634

Orphaned omi-analytics task type and Analysis details.

`delete the omi-analytics task type and Analysis detail UI`

Confirmed: remove `source = omi-analytics` compatibility from task models, display labels, inaccessible filters already rejected by IR-620, Task Details' **Analysis** section and `original_message`/`creation_reason`/`key_findings`/`search_summary`/`relevant_files` handling, and exclusive tests/docs. Do not alter PostHog/diagnostic analytics or retained Gemini task extraction. Do not add a replacement producer or legacy-row migration.

Acceptance group: A14.


### IR-635

Persisted raw inferred deadline beside the editable due date.

`keep only the canonical editable due date`

Confirmed: retain Gemini's `inferred_deadline` tool output and validation only as transient extraction input, parse an accepted value into canonical `dueAt`, and then discard the raw string. Remove `inferred_deadline` from task metadata, staged/local/backend compatibility shapes being retired, Task Details' Source section, catch-all exclusions, and focused tests/docs. User edits and IR-627 removal operate on the one authoritative due date. Do not add an original-AI-date label or general deadline-history feature.

Acceptance group: A14.


### IR-636

Raw source-conversation identifier in Task Details.

`hide the raw source-conversation ID and keep the relationship internally`

Confirmed: remove the full Task Details **Conversation** row and do not expose the stable local source-session ID elsewhere in the retained hover/detail surfaces. Preserve the owner-scoped local relationship, Conversation Detail lookup under IR-353, and deletion cascade under IR-314. Do not add title resolution or a task-to-conversation navigation feature in this requirement. Remove the raw Goal row through the already-decided IR-027 task-goal relationship deletion rather than treating it as a new retained field.

Acceptance group: A14.


### IR-637

Public task-sharing links and recipient import.

`delete Task sharing completely`

Confirmed: remove the task-row Share button, loading/copied-toast/error state, clipboard and analytics path, Mac `shareTasks` client and automation probe, share/preview/accept endpoints, generated models/contracts, Redis `task_share` token and per-recipient acceptance keys, thirty-day TTL behavior, public `h.omi.me/tasks` dependencies, sender-name lookup unique to this flow, recipient cloud-task copying and `shared_from` metadata, shared-task completion notifications, route policy, and exclusive tests/docs. Do not replace it with local export, peer sharing, or another cloud-publication design. Do not infer deletion of separately audited Chat or Conversation clipboard/export behavior.

Acceptance group: A14.


### IR-638

Individual task deletion, Undo, and local finalization.

`keep individual deletion and five-second Undo, fully local`

Confirmed: retain hover-trash, Command-D, unindented left-swipe deletion, no confirmation, deletion animation, five-second **Task deleted** Undo toast, up-to-ten pending entries, newest-first Undo, count presentation, and timer reset while entries remain. First commit an owner-scoped local soft-delete; only after success remove the row and report acceptance. Cancel its pending notification under IR-101 and purge deleted task-agent state under IR-028's removal. Undo clears the deletion state on the same stable local row and restores all retained fields/order without backend recreation. Timeout permanently deletes every remaining pending row; owner/app shutdown makes them nonrecoverable and launch reconciliation permanently purges any stranded user-deletion tombstones. Remove backend DELETE/re-create, backend-ID branching, remote failure behavior, cloud full-sync purge ownership, and exclusive synchronization tests. Conversation-cascade deletion under IR-314 and bulk deletion remain separate.

Acceptance group: A14.


### IR-639

Unreachable task multi-select and bulk deletion.

`delete task multi-select and bulk deletion`

Confirmed: remove `isMultiSelectMode`, `selectedTaskIds`, selection toggle/select-all/deselect-all/delete functions, unreachable header controls, row selection checkboxes and selection-only styling/gesture gates, task-section callback plumbing, navigation/sort branches used only by this mode, `TasksStore.deleteMultipleTasks`, backend bulk-delete loops, and exclusive tests/comments/automation. Do not add an entry button, bulk confirmation, or batch Undo. Preserve ordinary completion circles, search/status behavior, drag/reorder and indentation outside the removed gates, and individual deletion/Undo under IR-638.

Acceptance group: A14.


### IR-640

Visual-only task indentation.

`delete visual task indentation`

Confirmed: remove `indentLevel` from retained task/local/wire shapes; owner-scoped `TasksIndentLevels` fallback and migration; indent lookup/mutation state; Tab/Shift-Tab handling; hover indent/outdent buttons; swipe-right indent and indented left-swipe outdent behavior; guide lines/padding; sort-sync payload coupling; automation/generated contracts; and exclusive tests/docs. Do not add parent IDs or a subtask replacement. After removal, ordinary rows remain flat and left swipe consistently enters the individual deletion/Undo lifecycle from IR-638. Preserve drag-and-drop ordering as a separate open requirement.

Acceptance group: A14.


### IR-641

Task drag ordering and deadline-section rescheduling.

`keep and repair task drag ordering and deadline-section rescheduling`

Confirmed: retain the hover drag handle in the ordinary grouped To Do list, top/row drop targets, drag preview/feedback, same-section manual ordering without changing the deadline, cross-section rescheduling, and the exact IR-622 mappings of Today 11:59 PM, Tomorrow start-of-day, and Later plus seven days. Dropping into No Deadline must explicitly clear `dueAt`. Any cross-section move must update or cancel the retained local due-time notification under IR-101 and be accepted visually only after the authoritative local deadline transaction succeeds. Persist stable numeric `sortOrder` locally with rapid reorders coalesced; remove backend sort-order/deadline coupling, owner-scoped UserDefaults order fallback/migration, remote retry/failure presentation, and exclusive cloud-sync contracts. Disable drag handles and drop targets while search results are displayed so a partial result set cannot redefine hidden full-list order; the Done view remains non-draggable. Preserve automatic fallback sorting for tasks that have not been manually ordered. Do not add subtasks, Board behavior, or another ordering UI.

Acceptance group: A14.


### IR-642

Task keyboard navigation and shortcut hints.

`keep and repair task keyboard navigation`

Confirmed: retain Up/Down row selection and scrolling, single-Return **New below**, double-Return edit, Space completion/reopening, Command-D individual deletion with IR-638 Undo, Command-N inline creation with IR-622's current deadline context, Escape cancellation/deselection, editing Escape **Save & exit**, selection styling, and the context-sensitive hint capsule. Capture the selected task ID when the first Return is received; moving selection must not retarget the delayed action, and Escape, view/search/status changes, page disappearance, editing, or inline-creation entry must cancel any pending single-Return action. Preserve the current 0.4-second single-versus-double timing and search/Chat Return guards. Remove Tab/Shift-Tab handling and Indent/Outdent hints under IR-640. Hide or replace Return hints whenever those actions are not available in the current search, Chat, editing, or creation context. Do not add new shortcuts or globalize this page-scoped monitor.

Acceptance group: A14.


### IR-643

Delete Suggested and reverse the local candidate-review queue.

`delete Suggested and supersede IR-032`

Confirmed: delete the visible **Suggested** section and **Checking Suggested** indicator; `SuggestedTasksStore`, candidate/card/action/presentation models, cloud client adapter, Do now/Later/Dismiss/edit behavior, optional dismissal reasons, 24-hour and 30-day suppressions, owner/account-generation coordination, intervention/feedback/outcome attribution and outboxes, candidate navigation/hydration, automation actions, and exclusive tests. Complete the candidate, staged-task compatibility, workflow-control, backend persistence/API, generated-contract, and What Matters Now deletions already required by IR-026/031 instead of replacing them with a local candidate table or another review inbox. Remove candidate-specific empty-state, refresh, and Dashboard-to-Suggested coupling while retaining ordinary task navigation.

Under IR-031, explicit reminders/commands and policy-approved high-confidence user commitments continue to create ordinary authoritative local tasks idempotently with retained source/evidence provenance. Unconfirmed requests, inferred next steps, likely duplicates/refinements, and proposed update/complete/cancel/supersede outcomes are discarded without creating or mutating a task. Do not silently promote an uncertain case, retain a hidden pending queue, or add a replacement approval surface. The ordinary Tasks list, manual creation, explicit local-Chat task creation, completion, editing, reminders, recurrence, and local task-agent behavior are unchanged. The provenance **Why Omi added this** affordance on directly auto-created tasks is not deleted by this decision and remains a separate child audit.

Acceptance group: A14.


### IR-644

Provenance explanation for automatically created tasks.

`keep the task provenance Why button as implemented`

Confirmed: retain the conditional non-manual-plus-provenance visibility rule, **Why** row label, **Why Omi added this** popover, current Mac/conversation/authorized-source plain-language classification, linked-source count, read-only behavior, and accessibility identifier. Continue reading retained ordinary-task `source` and evidence/provenance fields locally. Move the component out of the deleted Suggested implementation during IR-643 cleanup, but do not add evidence navigation, raw IDs, screenshot/transcript disclosure, editing, network loading, or another candidate-review surface. Manual tasks and tasks without provenance continue showing no button.

Acceptance group: A14.


### IR-645

One-minute New treatment on task rows.

`keep the task New treatment exactly as implemented`

Confirmed: retain the local `createdAt`-based less-than-sixty-second computation, shared **New** capsule, subtle row background, keyboard-selection and hover/drag precedence, applicability to manual and retained automatically created tasks, and natural disappearance on a later SwiftUI recomputation. Do not add a timer, persisted read/unread state, click-to-clear behavior, count, setting, migration, analytics event, or cloud dependency.

Acceptance group: A14.


### IR-646

Staged-task Gemini prioritization and misleading Re-score control.

`delete staged-task prioritization and Re-score`

Confirmed: remove `TaskPrioritizationService`, both production startup calls, its ninety-second startup delay/five-minute poll/hourly run, Gemini ranking prompt/schema/parsing/application, profile-refresh side effect, UserDefaults last-run timestamp, legacy ranking gate branch, staged score read/re-rank/sync operations, backend batch-score endpoint/contracts, **Task Prioritization / Re-score** settings row, and exclusive tests/docs. Do not replace it with AI ordering of ordinary tasks. Preserve the Tasks gear and its retained automatic-extraction settings, ordinary High/Medium/Low priority, due-date grouping, IR-641 manual drag `sortOrder`, and AI-profile storage/UI/consumers; any ongoing automatic profile-refresh owner is a separate audit. Ordinary-task `relevanceScore` fields and consumers are not decided by this deletion and remain a separate child audit.

Acceptance group: A14.


### IR-647

Hidden ordinary-task relevance ranking.

`delete ordinary task relevanceScore and scoredAt`

Confirmed: remove `relevanceScore` and `scoredAt` from ordinary task models, local records/schema creation, migrations/backfills, insert assignment, removal compaction, completion/deletion/bulk paths, backend score synchronization/endpoints/contracts, search/context tuples, Chat schema descriptions, task-extraction models/prompts, generated shapes, and exclusive tests/docs. Do not add a replacement AI score or relevance sort. Retain explicit High/Medium/Low priority, `dueAt`, IR-641 local manual `sortOrder`, creation/update timestamps, and source/evidence provenance. When Chat or retained automatic extraction needs bounded ordinary-task context, select deterministically from those retained visible facts—priority and due urgency first, then manual order/recency as appropriate—without exposing or depending on hidden rank state. Remove score-only staged/task-promotion coupling already rejected by IR-643/646. No compatibility migration is required for a nonexistent shipped user population.

Acceptance group: A14.


### IR-648

Tasks loading, local pagination, refresh, and state screens.

`keep Tasks state presentation and 100-row pagination, fully local`

Confirmed: retain the 100-row first page, separate To Do and Done local offsets, bottom loading feedback, **Load more tasks**, existing near-bottom loading where currently reachable, pull-to-refresh, **Try Again**, initial loading presentation, and the distinct true-empty/completed-empty/search-empty states. Every initial load, next-page request, refresh, retry, and `hasMore` calculation must query the owner-scoped authoritative SQLite task store only; use a deterministic local extra-row/count boundary so an exact 100-row final page does not falsely promise another page. Preserve IR-619's global local search with its bounded result reveal.

Remove backend page fetching, cache/API merge, remote cursors, ID census, absent-row reconciliation/deletion, dashboard cloud-refresh coupling, connection-dependent fallbacks, and exclusive synchronization tests. Pull-to-refresh must requery local task state and no longer load Suggested under IR-643. Replace **Check your connection and try again** with local-accurate copy such as **Couldn't load tasks from this Mac**, and make **Try Again** retry only that local query. Do not turn pagination into cloud synchronization or load the complete task history eagerly.

Acceptance group: A14.


### IR-649

Tasks-header shortcut to Task Assistant settings.

`keep the Tasks gear shortcut as implemented`

Confirmed: retain the gear icon, **Task Settings** help text, `.navigateToTaskSettings` notification, main-window switch to Settings, Advanced-section selection, and Task Assistant card highlighting. Point it at the surviving IR-031 extraction settings after removing Task Agent children under IR-028 and staged Re-score under IR-646. Do not add a Tasks-page popover, duplicate controls, or hide the shortcut merely because adjacent settings are deleted. Exact behavior and persistence of each destination control remain separate child audits.

Acceptance group: A14.


### IR-650

Task Assistant master enablement switch.

`keep the default-on Task Assistant switch locally and make disablement authoritative before task creation`

Confirmed: retain the existing Task Assistant card, switch, default-on behavior, `UserDefaults` persistence, runtime enablement checks, and independence from the shared screen-analysis/Rewind controls. Apply IR-036 by removing this switch's `SettingsSyncManager` push and all server hydration rather than changing its visible behavior.

Turning the switch off must prevent any new Task Assistant analysis from starting and must discard an extraction result that was already in flight before it can write an observation, candidate, or authoritative local task. It cannot retract a screenshot already sent in an existing model request, but that response must produce no local mutation or task. Do not stop shared capture, Rewind, or other assistants when only Task Assistant is disabled.

Acceptance group: A14.


### IR-651

Task Assistant extraction-interval slider.

`delete the extraction-interval slider and keep a fixed ten-minute fallback`

Confirmed: remove the visible slider, label/help copy, slider-index/formatting coupling where no longer shared, Task Assistant interval preference/default/reset state, Task settings request/response field, `SettingsSyncManager` wiring, and exclusive tests/search entries. Keep the existing ten-minute value as the internal fallback interval. Retain IR-031's context-switch extraction, messaging fast path, dedupe behavior, eligible-app/window filtering, and automatic extraction enablement; do not reinterpret the fixed fallback as a global rate limit or slow timely event-driven detection.

Do not redesign the scheduler to make a user-selected interval govern every trigger. User-facing control remains the Task Assistant master switch and the separately audited app/window filters.

Acceptance group: A14.


### IR-652

Retain the current Task Assistant extraction interval.

`keep the extraction-interval control exactly as implemented`

Confirmed: retain the **Extraction Interval** slider, **How often to scan for new tasks** subtitle, 10-second/10-minute/1-hour choices, ten-minute default, `taskExtractionInterval` local preference, existing formatting and slider behavior, and current fallback-timer application. Context-switch extraction and the approximately fifteen-second messaging fast path may continue to trigger earlier than the selected fallback interval. Changing the preference is not required to restart a fallback timer that is already sleeping.

Apply IR-036 by removing only the interval's `SettingsSyncManager` push, server hydration, and backend request/response field. Do not reinterpret this setting as a global rate limit, redesign the scheduler, change its copy/options/default, or remove it merely because event-driven paths can run earlier.

Acceptance group: A14.


### IR-653

Task Assistant minimum-confidence control.

`keep the minimum-confidence control exactly as implemented`

Confirmed: retain the existing label/subtitle, 30%-90% range, ten-point step, 75% default, displayed percentage, local `taskMinConfidence` persistence, post-analysis threshold check, observation-before-threshold behavior, and interaction with the separate fixed capture-safety policy. Values below the 80% final policy floor must not weaken IR-031/643's explicit-or-clear-high-confidence automatic task-creation boundary; ambiguous detections remain discarded rather than becoming visible Suggested items.

Apply IR-036 by removing only this control's `SettingsSyncManager` push, server hydration, and backend request/response field. Do not delete, relabel, rerange, redefault, or otherwise redesign the control because its lower values overlap the safety floor or its initial 75% value is off the slider's later ten-point steps.

Acceptance group: A14.


### IR-654

Task Extraction Prompt editor.

`keep the Task Extraction Prompt editor as implemented and make it local-only`

Confirmed: retain the **Task Extraction Prompt** row, **Edit** button, separate reusable/resizable window, immediate per-keystroke persistence, character count, **Reset to Default**, **Done**, Command-Return shortcut, current no-Cancel/no-explicit-Save behavior, and use of the locally stored prompt by later Task Assistant analysis. Apply IR-036 by removing the prompt from cloud request/response models, server hydration, full-settings pushes, and Firestore ownership; this Mac's `UserDefaults` value is sole authority.

Update only the compiled default prompt and extraction tool schema where earlier decisions require it: remove tags and semantic category/subcategory, remove Suggested/candidate/update/completion/refinement branches rejected by IR-643, and describe the retained explicit-command/clear-high-confidence direct local task policy, local duplicate prevention, deadlines, priority, and ordinary provenance. Custom text may influence model interpretation but must never override code-level privacy exclusions, ownership/concrete-deliverable validation, confidence gates, deduplication/idempotency, IR-650 disablement, or IR-643 admission rules. Do not redesign or delete the editor because its default text must follow the accepted task model.

Acceptance group: A14.


### IR-655

Task Extraction Test Run historical replay.

`keep the Task Extraction Test Run exactly as implemented`

Confirmed: retain the **Test Run** button, separate reusable/resizable window, previous-24-hour default, editable date range, up-to-100,000 screenshot query, allowed-app/browser/Rewind-privacy filtering, context-switch replay of every departing frame, sequential real Gemini tool-loop calls, local searches, progress/results/summary UI, between-frame Stop behavior, errors, and no-task-mutation contract. Do not add a preflight count, warning/confirmation, request cap, sampling, one-frame mode, stronger cancellation, or developer-only gate merely because a run can send many historical screenshots and consume substantial managed-model usage.

Adapt only fields already removed by other decisions: remove tag and semantic category/subcategory presentation under IR-629/631 and display the surviving task title, priority, deadline/provenance where available, confidence, searches, decision, error, and timing facts. Continue to use Rewind's privacy exclusions and current Task Assistant filters. A test run must remain side-effect-free for authoritative tasks and observations even though it performs real transient model computation.

Acceptance group: A14.


### IR-656

Task Assistant Allowed Apps whitelist.

`keep the Allowed Apps whitelist exactly as implemented`

Confirmed: retain the **Allowed Apps** heading/help copy, full default app-name set, sorted rows, icons, browser badges, X removal, manual display-name entry, Add/Return behavior, currently running app chips and refresh, exact display-name matching, frame/context-switch/Test Run enforcement, and stronger Rewind-exclusion precedence. Retain the current empty-array fallback: removing the last entry restores the defaults rather than representing a persistent empty whitelist. Do not repair, relabel, redesign, or replace it with bundle-identifier selection.

Apply IR-036 by removing only allowed-app cloud hydration, full-settings upload, backend request/response fields, and Firestore ownership. Preserve the local `UserDefaults` behavior and runtime setting notification.

Acceptance group: A14.


### IR-657

Task Assistant Browser Window Keywords.

`keep Browser Window Keywords exactly as implemented`

Confirmed: retain the heading/help copy, full default keyword list, chips, UI-only filter/clear behavior, add/remove controls, count, case-insensitive duplicate prevention, fixed browser-name classification, localized title-substring matching, missing-title rejection, non-browser bypass, production/context-switch/Test Run enforcement, and current empty-array fallback to defaults. Do not remove, repair, relabel, reduce, or redesign the control.

Apply IR-036 by removing only browser-keyword cloud hydration, full-settings upload, backend request/response fields, and Firestore ownership. Preserve the local `UserDefaults` value and runtime setting notification.

Acceptance group: A14.


### IR-658

Local-development Tasks automation actions.

`keep local-development Tasks automation and make it SQLite-only`

Confirmed: retain local-automation-only registration and the real-path `create_task`, bounded `seed_tasks`, `toggle_task`, `delete_task`, `reorder_task`, and `dump_tasks` actions, including ambiguity checks, headless local loading, deterministic reorder flushing, local read-back, marker verification, and no exposure to published bundles. Use stable owner-scoped local task IDs immediately. Make every action finish against the authoritative local store without backend polling, `synced` fields/counts, remote IDs, backend flushes, or network-dependent timeouts. Update summaries/results and focused automation tests accordingly.

Delete `inject_requery_during_drag`, its forced hidden-filter state/counters/waits, and server-push-specific test contract because IR-025/620 remove the event and query branch it exists to simulate. Preserve drag/reorder correctness through IR-641's ordinary local behavioral tests rather than inventing a fake server refresh. Do not broaden these actions into a production, remote, MCP, or customer task API.

Acceptance group: A14.


### IR-659

Retained Insights and Focus hub reachability.

`expose the existing combined Insights / Focus hub through one visible Insights navigation item`

Confirmed: replace the Apps position being removed under IR-046/047/255 with one visible **Insights** primary-navigation item. The surviving expanded row becomes **Home / Memory / Tasks / Insights**. The compact **Navigate** menu must expose the same complete destination set. Selecting **Insights** opens the existing combined hub on its current **Insights** segment, with the existing **Focus** segment providing normal access to the retained simple local Focus page.

This amends IR-530's post-Apps surviving-navigation list without changing its responsive substitution, no-overlap, Capture/Listening, Settings, Memory-destination, motion, or accessibility decisions. Preserve the retained Insight and Focus assistants, their local-authoritative records, notifications, settings, and page behavior. Do not create a new page, split them into two primary-navigation items, restore the legacy sidebar, or delete either retained history product. The separate hidden Insight route, development-automation aliases, Command-number mapping, and exact Home-to-Insight-detail routing remain implementation/audit details rather than being silently decided here.

Acceptance group: A15.


### IR-660

Durable local deletion of Focus history.

`keep individual Delete and Clear All History, and make both authoritative local deletions`

Confirmed: retain both visible controls and their existing confirmations. Individual **Delete** must permanently delete the exact owner-scoped Focus row from local GRDB before removing it from the displayed list. **Clear All History** must permanently delete all Focus rows owned by the current local owner in one authoritative local operation before clearing the page. Recompute current status/app from the newest surviving row after an individual deletion, and clear them when no row remains.

On local deletion failure, keep or restore the affected records on screen and present an actionable error rather than silently claiming success. Remove UserDefaults-cache mutation, synchronized/backend-ID branching, duplicate-memory deletion, backend DELETE, and swallowed-error behavior under IR-029/030. Do not change Focus analysis, notifications, settings, the retained summary/history presentation, or the Insights/Focus hub merely to repair deletion durability.

Acceptance group: A15.


### IR-661

Truthful Focus monitoring status.

`make the Focus monitoring label follow the real capture runtime`

Confirmed: show green **Monitoring** only when Focus Assistant is enabled and the shared proactive screen-capture runtime is actually healthy and running. Show distinct truthful non-running states for **Focus disabled**, **Capture off**, and **Capture blocked** rather than deriving all status from the saved Focus toggle. Reuse the canonical live Capture/permission/health state retained by IR-515 and react to its runtime changes; do not create a second monitoring authority.

This changes only the Focus-page status presentation. Do not automatically enable Focus, start or stop Capture, request permission, alter assistant settings, change stored Focus results, or modify analysis/cooldown behavior merely because the page observes the real state.

Acceptance group: A15.


### IR-662

Focus result-card wording for restored history.

`keep the Focus result card exactly as it is`

Confirmed: preserve the current unqualified **Focused / Distracted** headline, app subtitle, focus-rate leading value, colors, and status-banner precedence. Continue restoring `currentStatus` and `currentApp` from the newest locally loaded Focus row and showing that row without a timestamp, **Latest result** label, freshness threshold, current-run requirement, stale treatment, or automatic hiding when capture is off.

Keep IR-661's separate truthful **Monitoring / Focus disabled / Capture off / Capture blocked** header state. Do not infer that the monitoring label changes the retained result-card wording or stored Focus history.

Acceptance group: A15.


### IR-663

Open-ended Focus-duration calculation.

`keep the current Focus-duration calculation exactly as it is`

Confirmed: continue ending older classification periods at the next newer transition and extending the newest locally loaded row to the current time. Do not persist or honor an explicit end time, use `durationSeconds`, add monitoring-run identity, close the period when Focus/Capture stops or permission is lost, cap it at the last captured frame, or distinguish active from restored sessions for duration accounting.

Today's focused minutes, distracted minutes, focus rate, session count, top-distraction durations, and the result-card focus-rate value may continue using this inferred open-ended duration behavior even while IR-661 reports **Focus disabled**, **Capture off**, or **Capture blocked**. Do not change IR-662's retained result-card wording.

Acceptance group: A15.


### IR-664

Focus totals while the page remains open.

`keep the current snapshot refresh behavior exactly as it is`

Confirmed: do not add a per-minute or other normal-state display timer for focused minutes, distracted minutes, focus rate, session count, or the result-card value. Keep the existing one-second updates only for active analysis-delay and cooldown countdown presentation. Allow the normal totals to remain unchanged until another existing observed state change, page reconstruction, or explicit refresh causes recomputation.

This does not change IR-663's open-ended duration arithmetic; it preserves only when that arithmetic is visibly recomputed while the page is open. Do not add background model calls, database writes, or a new refresh control.

Acceptance group: A15.


### IR-665

Owner-safe Focus state during account changes.

`finish the local adaptation with owner-safe Focus state transitions`

Confirmed: on every effective-owner change or sign-out, synchronously clear all visible/in-memory Focus sessions, current status/app, detected-app state, delay/cooldown state, loading ownership, and other owner-derived projections before any next-owner authenticated surface can render. Then load only the newly authorized owner's local Focus rows from that owner's retargeted GRDB database. Capture an owner/authorization generation around every asynchronous load, insert projection, refresh, delete, and clear operation, and reject a completion that returns after the owner changes.

Remove the process-wide Focus UserDefaults record cache under IR-029 rather than replacing it with another duplicate authority. Do not add an `ownerId` column merely to duplicate the existing per-owner database-directory boundary. Signing out or switching accounts must not delete the prior owner's database; their data remains in their own directory for a later authorized return. Preserve the same Focus analysis, page, status, history, and settings product behavior after the correct owner's state loads.

Acceptance group: A15.


### IR-666

Small local retention boundary for Focus history.

`preserve the existing 30-day / 500-row Focus-history window and enforce it locally`

Confirmed: retain at most the newest 500 owner-scoped Focus rows and permanently remove any Focus row older than 30 days from the current owner's local GRDB database. Apply both limits as local maintenance after a successful Focus-row insert and when the current owner's Focus storage starts or refreshes, so long-running and returning installations converge on the same small boundary. Perform cleanup and the related insert/load work against the currently authorized owner's database, and fence asynchronous completion through the owner-generation rule in IR-665.

Keep the retained page's recent-history presentation, today's statistics, analysis behavior, and the individual **Delete** and **Clear All History** controls from IR-660. Do not add cloud retention, backend IDs, synchronization, a second cache, an archive, all-time browsing, or a user-configurable retention setting. This is the existing recent-history pattern made authoritative in local storage.

Acceptance group: A15.


### IR-667

Empty Focus-history presentation.

`keep the empty Focus-history screen exactly as it is`

Confirmed: preserve the existing empty-state title, explanatory wording, line break, Refresh button, layout, styling, and behavior exactly as they are. Do not make the wording conditional on the truthful monitoring states introduced by IR-661, add a Capture or permission action, redirect the user to Settings, or otherwise redesign this empty state.

IR-661 continues to govern the separate monitoring label in the page header. That truthful header state does not alter the retained empty-history message.

Acceptance group: A15.


### IR-668

Local Focus-history Refresh naming.

`keep Refresh exactly as it behaves and rename only the misleading internal method`

Confirmed: preserve both existing visible **Refresh** controls, their labels, placement, styling, and force-reload behavior. Refresh must continue re-reading only the currently authorized owner's local GRDB Focus rows, subject to the owner-generation fence in IR-665 and the local retention boundary in IR-666. It must not contact a cloud backend, restore synchronization, or trigger new Focus analysis.

Rename the internal `refreshFromBackend` API and its in-tree callers to an accurate local-storage name. This is an internal cloud-to-local naming cleanup only; do not change the customer-visible Refresh workflow or add a second refresh implementation.

Acceptance group: A15.


### IR-669

Local Insight-history loading boundary.

`keep all Insights locally and continue loading the newest 100 on the page`

Confirmed: preserve the current newest-100 page-loading boundary, but read those records only from the currently authorized owner's local GRDB database. Keep older tagged Insight records stored locally even when they fall outside the page's loaded window. Do not automatically delete overflow records, impose a 100-record retention cap, or treat the page limit as a data-retention rule.

Keep the existing Insight page, search, category filters, read/unread state, dismiss/show-dismissed behavior, detail presentation, individual deletion, and clear-history controls retained by IR-034. Their authoritative local mutation and owner-transition behavior remain separate implementation details. Do not restore cloud reads, synchronization, backend IDs, or the duplicate UserDefaults array merely to preserve the newest-100 presentation pattern.

Acceptance group: A15.


### IR-670

Owner-safe Insight state during account changes.

`clear the old in-memory Insight projection and load only the newly authorized owner's local history`

Confirmed: on every effective-owner change or sign-out, synchronously clear the displayed/in-memory Insight history, unread projection, loading ownership, error state, selection-derived state, and any other owner-derived page projection before a next-owner authenticated surface can render. Then load at most the newest 100 tagged Insight records from the newly authorized owner's local GRDB database under IR-669.

Capture the current owner/authorization generation around every asynchronous Insight load, refresh, insert projection, read, mark-all-read, dismiss, delete, and clear operation, and reject a completion that returns after the owner changes. Remove the global UserDefaults Insight array under IR-034 rather than partitioning that duplicate cache. Do not delete the prior owner's local database during sign-out or switching; their complete Insight history remains in their own database for a later authorized return.

Keep the same Insight page, filters, search, detail, read/dismiss/delete lifecycle, notification behavior, and newest-100 presentation after the correct owner's state loads. This is account isolation for the local adaptation, not a redesigned Insight workflow.

Acceptance group: A15.


### IR-671

Authoritative local Clear All Insights.

`keep Clear All History and make it delete every current-owner Insight locally`

Confirmed: retain the existing **Clear All History** control, wording, confirmation dialog, styling, and user workflow. After confirmation, delete every tagged Insight record in the currently authorized owner's local GRDB database in one authoritative local operation, including records older than the newest-100 page window in IR-669. Do not limit the operation to the currently loaded or filtered items.

Scope the deletion to Insight-tagged records only. Do not delete ordinary Memories, other locally stored product data, or another owner's database. On database failure, keep or restore the Insight list and present an actionable error rather than claiming that history was cleared. Remove the per-ID backend loop, UserDefaults mutation, cloud deletion, and swallowed-error behavior under IR-034.

This repairs the existing control's stated behavior while preserving its product pattern; it does not add a new Insight workflow.

Acceptance group: A15.


### IR-672

Authoritative local deletion of one Insight.

`keep individual Insight Delete and make the selected local record authoritative`

Confirmed: preserve the existing hover action, **Delete** label, **Delete Insight** confirmation dialog, Cancel action, styling, and user workflow. After confirmation, permanently delete exactly the selected tagged Insight record from the currently authorized owner's local GRDB database. Do not delete other Insights, ordinary Memories, or another owner's data.

Complete the authoritative local deletion before finalizing removal from the displayed projection, or restore the row if an optimistic presentation is used and the transaction fails. Present an actionable error on failure rather than silently claiming success. Remove duplicate UserDefaults mutation, backend-memory deletion, backend-ID routing, cloud refresh resurrection, and swallowed-error behavior under IR-034.

Keep search, filters, read/dismiss state, detail presentation, Clear All History from IR-671, and all other retained Insight behavior unchanged.

Acceptance group: A15.


### IR-673

Authoritative local Insight dismissal.

`keep Dismiss and Show Dismissed exactly as they behave, backed by local GRDB`

Confirmed: preserve the existing eye-slash hover action, no-confirmation dismissal workflow, normal-list hiding, **Show Dismissed** toggle, dismissed-row presentation, filtering, labels, styling, and behavior. Persist the selected tagged Insight record's dismissed flag only in the currently authorized owner's local GRDB database.

Complete the authoritative local update before finalizing the displayed projection, or restore the previous dismissed state if an optimistic presentation is used and the transaction fails. Present an actionable error rather than silently claiming success. Remove duplicate UserDefaults mutation, backend read-status updates, backend IDs, cloud refresh reversal, and swallowed-error behavior under IR-034.

Do not turn Dismiss into deletion, add a confirmation, automatically delete dismissed records, alter Show Dismissed, or affect ordinary Memories or another owner's data.

Acceptance group: A15.


### IR-674

Authoritative local read state when opening an Insight.

`keep open-and-mark-read exactly as it behaves, backed by local GRDB`

Confirmed: preserve the existing row selection, detail sheet, content, styling, unread emphasis, and automatic mark-read behavior. Opening one Insight must update only that selected tagged Insight record's read flag in the currently authorized owner's local GRDB database. It must not mark other Insights read, dismiss or delete anything, or affect ordinary Memories or another owner's data.

The detail sheet must still open if the local read-state transaction fails. In that case, keep or restore the Insight's unread presentation and show an actionable error rather than pretending the read state was saved. Remove duplicate UserDefaults mutation, backend read-status updates, backend IDs, cloud refresh reversal, and swallowed-error behavior under IR-034.

Acceptance group: A15.


### IR-675

Authoritative local Mark all read.

`keep Mark all read as it is presented and persist its complete result locally`

Confirmed: preserve the existing **Mark all read** button, conditional visibility, label, placement, styling, and immediate user-facing meaning. When selected, mark every tagged Insight record belonging to the currently authorized owner as read in local GRDB, including dismissed Insights and older records outside the newest-100 page window. Active search, category, and dismissed filters must not narrow this all-history operation.

Do not dismiss, delete, rewrite, or otherwise alter Insight content. If the authoritative local transaction fails, keep or restore the previous unread states and present an actionable error rather than claiming success. Remove duplicate UserDefaults mutation, per-ID backend updates, the broken post-mutation unread-ID lookup, backend IDs, cloud refresh reversal, and swallowed-error behavior under IR-034.

This keeps the existing customer-visible pattern and makes its stated all-read result durable under local authority.

Acceptance group: A15.


### IR-676

Empty Insights presentation.

`keep the empty Insights screen exactly as it is`

Confirmed: preserve the existing empty-state icon, title, explanatory wording, line break, Settings hint, layout, styling, and behavior exactly as they are. Do not make the wording conditional on assistant or Capture runtime state, add a direct Settings/Capture/permission action, or otherwise redesign this empty state.

This matches IR-667's decision for the equivalent Focus-history empty state. Truthful status behavior elsewhere does not alter the retained Insights empty-state copy.

Acceptance group: A15.


### IR-677

Plain combined Insights top-navigation item.

`keep the combined Insights navigation item plain`

Confirmed: render the new combined **Insights** primary-navigation item as the same plain destination pattern used by Home, Memory, and Tasks. Do not add an unread-Insight number, new-item badge, Focused/Distracted color, monitoring dot, Capture state, or a combined status calculation to the expanded top-navigation item or compact **Navigate** entry.

Keep unread counts and **Mark all read** inside the Insights page. Keep Focus result and truthful monitoring presentation inside the Focus page under IR-661/662. Selecting the plain navigation item must still open the combined hub on its Insights segment under IR-659; this decision removes no underlying state or behavior.

Acceptance group: A15.


### IR-678

Home Insight preview opens the canonical local detail.

`route a Home Insight preview through the combined hub to that exact local Insight detail`

Confirmed: clicking a retained local Insight preview on Home must select the combined **Insights / Focus** hub, keep its **Insights** segment active, resolve the exact tagged Insight record from the currently authorized owner's local GRDB database, and automatically open the existing Insight detail sheet for that record. Opening it applies the normal local mark-read behavior from IR-674. Closing the detail leaves the user on the Insights page.

Reuse one owner-scoped navigation request and the existing Insight detail presentation rather than creating a second Home-specific detail UI or copying record content into navigation state. Reject a pending request if its owner generation changes or the record is no longer available, and present a truthful unavailable result rather than opening another owner's or a different Insight.

Keep IR-505's local dismissal behavior for the Home row. Do not restore cloud recommendations, route ordinary local Insights into Tasks/threads/Chat, open the hidden standalone Insight route, or change the combined hub's default segment and plain-navigation decisions from IR-659/677.

Acceptance group: A15.


### IR-679

Canonical local-development route for Insights.

`preserve the navigate-insight automation pattern through the canonical combined hub`

Confirmed: keep the local-development `navigate insight` command and its ability to open the retained Insights product. Resolve that command to the same combined **Insights / Focus** hub customers use, with the **Insights** segment selected. Delete the duplicate standalone `.insight` navigation route and its exclusive page-switch, legacy-sidebar loading, and route-state wiring.

Do not delete or redesign `InsightPage`; it remains the Insights segment's content and retains all accepted behavior. Direct component previews and view-export fixtures may still instantiate `InsightPage` when they are testing/rendering the component itself, because those are not competing product-navigation routes.

This is the existing local-development pattern adapted to the canonical local product route, not removal of Insights or its automation coverage.

Acceptance group: A15.


### IR-680

Canonical local-development route for Focus.

`keep navigate-focus and select Focus inside the canonical combined hub`

Confirmed: preserve the local-development `navigate focus` command and its ability to inspect the retained Focus product. Resolve the command to the same combined **Insights / Focus** hub customers use, while explicitly selecting its **Focus** segment. Do not create or restore a separate Focus navigation route merely for automation.

Use the same hub-segment routing authority needed by IR-678/679 rather than a second automation-only flag. Keep ordinary selection of the visible **Insights** navigation item opening the hub on **Insights** under IR-659. Preserve every retained Focus page, analysis, local history, monitoring, and control decision.

This fixes the command's destination while preserving its development workflow and the canonical customer shell.

Acceptance group: A15.


### IR-681

Numbered shortcuts follow the surviving primary navigation.

`adapt Command-number navigation to Home, Memory, Tasks, and Insights`

Confirmed: preserve the familiar numbered-navigation pattern, but map it to the complete surviving primary-navigation order: `⌘1` **Home**, `⌘2` **Memory**, `⌘3` **Tasks**, and `⌘4` **Insights**. `⌘2` must open the Memory hub's normal **Memories** destination rather than a stale previously selected child. `⌘4` must open the combined Insights / Focus hub with **Insights** selected under IR-659/679.

Remove the obsolete numbered `⌘5` Rewind and `⌘6` Apps commands and their menu entries. This does not delete Rewind: keep its retained Capture-hover entry, `⌘⌥R` global navigation, normal internal routing, and local-development automation. Keep `⌘,` for Settings and unrelated shortcuts unchanged.

Use typed surviving destinations rather than continuing to expose raw deleted-sidebar positions as the shortcut contract. Update command titles, accessibility/menu presentation, and focused shortcut-routing tests with the mapping.

Acceptance group: A15.


### IR-682

Insight notification click continues into local Chat.

`keep Insight notification click-to-local-Chat exactly as it behaves`

Confirmed: preserve the existing floating-bar Insight card, whole-card click target, automatic presentation timeout, hidden provenance, and click-to-follow-up behavior. Clicking must continue into the currently authorized owner's canonical local Chat journal with the Insight context rather than navigating to the Insights page or automatically opening Insight detail.

Preserve the card **X** as presentation-only dismissal. Closing or timing out the card must not dismiss, mark read, delete, or otherwise mutate the authoritative local Insight record. The record remains available through Home and the combined Insights hub until the user uses those surfaces' accepted lifecycle controls.

Keep owner authorization fencing and local journal continuity. Do not restore cloud Chat/history persistence, duplicate the Insight record into another authority, or add an Insight-specific conversation renderer merely to retain this workflow.

Acceptance group: A15.


### IR-683

Customer-facing local Rewind screen-history workflow.

`keep the current customer-facing Rewind screen-history workflow with local authority`

Confirmed: preserve the existing Rewind overlay, `Command-Option-R` entrance, date-based history, search entry, grouped-results and timeline presentations, frame inspection, Settings entrance, and truthful Capture control as one customer-visible local product. Keep the current screen-history records, OCR, video, indexes, and retrieval authority local to the currently authorized Mac profile under IR-011/053.

Do not delete Rewind merely because its former shared-backend copy is removed, hide the history while retained assistants continue consuming capture, or redesign the overall workflow. Audit the date boundary, search behavior, result grouping, timeline/frame controls, empty/error/recovery presentation, and local-development route as separate children before declaring the Rewind page complete. Conversation transcript and speaker controls remain with their parallel workflow audit rather than being re-decided here.

Acceptance group: A15.


### IR-684

Rewind selected-day timeline and search boundary.

`keep Rewind scoped to one selected calendar day at a time`

Confirmed: preserve today as the initial selection, the existing graphical date picker, and the rule that both ordinary timeline browsing and search operate only within the selected calendar day. Changing the date must reload or re-run the current query for that day; clearing search must return to that same day's ordinary timeline.

Do not add all-history, week/month, or arbitrary date-range search for the first release. Keep the selected date visible beside search so the scope remains understandable. This decision governs the date boundary only; frame sampling, search implementation, result presentation, and empty states remain separate children.

Acceptance group: A15.


### IR-685

Rewind daily timeline sampling boundary.

`keep the 500-frame evenly sampled daily timeline projection`

Confirmed: preserve every retained local Rewind record while limiting the ordinary selected-day timeline to at most 500 evenly distributed frames. Return all frames when the day contains no more than 500. Keep chronological navigation across the resulting projection and continue refreshing today's projection as finalized captures arrive.

Do not load every captured second into the visible timeline, delete records merely because they were not selected for the projection, or make ordinary timeline sampling limit search eligibility. Search result limits and presentation remain separate children.

Acceptance group: A15.


### IR-686

Rewind combined text and semantic search.

`keep combined local text and local-vector semantic Rewind search`

Confirmed: preserve the debounced parallel search, 100-result full-text bound, 50-result semantic bound, 0.5 semantic inclusion threshold, text-first merge order, stable-ID duplicate removal, and selected-day boundary from IR-684. Continue using transient managed query embedding with local vector comparison and authority under IR-053.

Semantic-service failure must continue failing open to available local text results rather than blocking the complete Rewind search. Do not replace the combined search with semantic-only retrieval, upload authoritative Rewind history to create a cloud search product, or make the ordinary 500-frame timeline projection from IR-685 constrain search eligibility. Search result grouping and error presentation remain separate children.

Acceptance group: A15.


### IR-687

Rewind nearby search-result grouping.

`keep the current same-context 30-second search-result grouping`

Confirmed: preserve grouping by exact application and window-title context within the existing 30-second window, multiple separated sessions for a repeated context, one representative result row, count/time-range presentation, and access to every screenshot in the selected group through its timeline.

Do not flatten nearby near-duplicate frames into independent top-level rows, permanently collapse them into one stored record, or merge unrelated apps/windows merely because their text is similar. List/timeline presentation and navigation remain separate children.

Acceptance group: A15.


### IR-688

Rewind search list and timeline presentations.

`keep the grouped-results-first search workflow and both presentations`

Confirmed: preserve grouped List as the initial active-search presentation, row selection into that group's Timeline, the existing List/Timeline toggle, back and Escape return from a search timeline to the results list, and query clearing back to the ordinary selected-day timeline.

Do not delete either presentation, default every search directly into a frame viewer, create a separate search window, or make closing a selected group clear the query. Individual result selection, frame navigation, and frame-load failure behavior remain separate children.

Acceptance group: A15.


### IR-689

Reachable Rewind manual frame navigation.

`keep the reachable manual Rewind frame-navigation pattern`

Confirmed: preserve timeline click and drag, page scroll, left/right arrow navigation, bounded first/last behavior, current-position and timestamp presentation, and newest-request-only image application. Keep the same controls for the ordinary selected-day timeline and the timeline inside a selected search-result group.

Do not add autoplay, playback-speed controls, or a second full-screen player to the reachable page merely because dormant player code exists elsewhere. That unreachable code and selected-frame load failures remain separate children.

Acceptance group: A15.


### IR-690

Rewind selected-frame load failure presentation.

`keep the current selected-frame failure behavior exactly as implemented`

Confirmed: when a newly selected Rewind frame cannot be loaded, preserve the selected index, current loading-state completion, last successfully displayed image, existing logging, active-chunk protection, and corrupted-old-chunk cleanup/refresh behavior exactly as they are. Do not add a **Frame unavailable** or still-saving presentation, clear the old image, automatically skip to another frame, realign the visible timestamp to the prior image, or otherwise repair this mismatch.

This is an explicit decision to retain the current presentation despite the possible image/index/timestamp mismatch. It does not change the normal successful frame-load or latest-request protection accepted under IR-689.

Acceptance group: A15.


### IR-691

Unreachable Rewind autoplay player.

`keep the unreachable Rewind autoplay player exactly as it is`

Confirmed: preserve `RewindTimelinePlayerView.swift`, `RewindTimelinePlayerView`, `TimelinePlayerViewModel`, their private playback/timer/image-loading behavior, and the self-contained preview exactly as implemented. Do not delete, connect, redesign, test, document, or otherwise change this dormant player as part of the first-release Rewind adaptation.

This does not add autoplay or a second reachable frame-navigation pattern. The customer-visible manual Rewind timeline remains governed by IR-689.

Acceptance group: A15.


### IR-692

Unreachable alternate Rewind timeline and screenshot preview.

`keep the unreachable alternate Rewind timeline and screenshot preview exactly as they are`

Confirmed: preserve `RewindTimelineView`, its private scroll/app-marker/hover-preview support, `ScreenshotPreviewView`, its OCR text and Copy presentation, navigation controls, image-loading behavior, shared `SearchHighlightOverlay`, and all other declarations in the file exactly as implemented. Do not delete, connect, split, redesign, test, document, or otherwise change this dormant alternate UI during the first-release adaptation.

This does not make its app-icon timeline, hover preview, separate screenshot viewer, or OCR Copy action customer-reachable. The current page continues using only its existing live declarations, including the search-highlight helper.

Acceptance group: A15.


### IR-693

Unreachable Rewind search and app-filter bar.

`keep the unreachable Rewind search and app-filter bar exactly as it is`

Confirmed: preserve `RewindSearchBar.swift`, both previews, its search/app/date/quick-date/Clear/Command-F presentation, callback contract, single-date **This Week** behavior, and the corresponding `availableApps`, `selectedApp`, unique-app loading, filter application, and `filterByApp` view-model wiring exactly as implemented. Do not delete, expose, rename, correct, test, document, or otherwise change this dormant UI or its still-executed support path.

This does not add an app filter or quick-date row to the reachable Rewind page. The live search field and date picker remain governed by IR-684/686.

Acceptance group: A15.


### IR-694

Unreachable Rewind search-results filmstrip.

`keep the unreachable Rewind search-results filmstrip exactly as it is`

Confirmed: preserve `SearchResultsFilmstrip.swift`, `SearchResultsFilmstrip`, `FilmstripThumbnail`, the private thumbnail-loading/cache behavior, the screenshot text-match-count extension, hover/selection/position presentation, and self-contained preview exactly as implemented. Do not delete, connect, redesign, test, document, or otherwise change this dormant search-results presentation.

This does not add the filmstrip to the customer-visible Rewind workflow or replace either retained reachable search presentation.

Acceptance group: A15.


### IR-695

Unreachable Rewind screenshot grid and individual-delete UI.

`keep the unreachable Rewind screenshot grid and individual-delete UI exactly as they are`

Confirmed: preserve `ScreenshotThumbnailView.swift`, `ScreenshotThumbnailView`, `SearchContextSnippet`, `ScreenshotGridView`, grouping, thumbnails, selection, hover delete presentation, preview, and `RewindViewModel.deleteScreenshot` exactly as implemented. Do not delete, connect, redesign, test, document, or otherwise change this dormant grid or its unused view-model deletion path.

This does not expose individual screenshot deletion in the reachable Rewind page and does not change lower-level retention, corruption cleanup, or storage-safety behavior.

Acceptance group: A15.


### IR-696

Reachable Rewind no-screenshots presentation.

`keep the Rewind No Screenshots Yet screen exactly as it is`

Confirmed: preserve the current icon, title, sentence text and line break, **Rewind captures your screen every second.** claim, search tip, layout, styling, and unconditional reuse across eligible empty dates and runtime states exactly as implemented. Do not make the wording conditional on the selected date or Capture health, replace the one-second claim, add an action, or otherwise redesign this empty state.

Acceptance group: A15.


### IR-697

Rewind missing Screen Recording permission state.

`keep the current Rewind Screen Recording permission flow exactly as implemented`

Confirmed: preserve the lock icon, title, explanation, **Grant Permission** label/action, styling, desired-Capture enablement, frontmost permission registration, and System Settings handoff exactly as they are. Do not replace this with an in-app permission claim, omit the local enablement, add another setup screen, or redesign the recovery path.

Acceptance group: A15.


### IR-698

Rewind stuck ScreenCaptureKit reset and restart.

`keep the current stuck-ScreenCaptureKit reset and restart exactly as implemented`

Confirmed: preserve the red recovery presentation, wording, **Reset & Restart** action, desired-Capture enablement, Launch Services registration, bundle-scoped hard Screen Recording reset, update-in-progress guard, success restart, logged-failure behavior, and all retained local Rewind data exactly as they are. Do not replace this Rewind action with the separate soft-recovery helper, broaden the permission reset, wipe history, or add another recovery state.

Acceptance group: A15.


### IR-699

Rewind initial loading-error presentation and Retry.

`keep the current initial Rewind loading-error screen exactly as implemented`

Confirmed: preserve the generic icon, title, copy, **Retry** action, safe suppression of the raw error, full reinitialization attempt, styling, and diagnostic logging exactly as they are. Do not expose database/provider details, add separate startup error classes, change Retry into partial refresh, or redesign the state.

Later selected-date and active-search failures remain a separate child because their current paths do not enter this initial error presentation.

Acceptance group: A15.


### IR-700

Bounded-plan versus unlimited-plan review thresholds.

`resolved - keep the exact two-band threshold behavior and adapt only its plan mapping`

Retain review triggers of 2 speech hours in 24 hours, 8 in 3 days, or 10 in 7 days for bounded-transcription entitlements. Retain doubled triggers of 4, 16, and 20 speech hours for unlimited-transcription entitlements. Crossing any one remains a request for classification, not automatic proof of misuse, subject to IR-615's separately retained `free_exhausted` shortcut.

Replace the hard-coded Omi plan-name membership with the equivalent bounded/unlimited property from the authoritative Dodo entitlement. Retain the separate thirty-audio-hour daily impossible-volume ceiling for every plan.

Acceptance group: A16.


### IR-701

Restrict-stage cloud allowance and local handoff.

`resolved - keep the thirty-minute daily cloud allowance and add an explicit Mac handoff`

Retain the thirty-day `restrict` stage and its 1,800,000-millisecond managed-cloud STT allowance per UTC day. Exhaustion continues stopping additional provider-funded cloud transcription without closing and reconnecting the live socket.

Replace silent audio disposal with a typed live event. When local Parakeet is available, the Mac must continue or switch to that local engine while preserving the current local recording. When no local engine is usable, the Mac must show that managed cloud transcription is unavailable until the stated daily reset/support resolution; it must not claim that on-device transcription continues. Local Parakeet itself remains outside the restriction.

Acceptance group: A16.


### IR-702

Automatic recovery after a thirty-day restriction.

`resolved - keep and make authoritative the thirty-day restriction recovery ladder`

Every enforcement consumer must read one normalized state. After thirty days, automatically move `restrict -> throttle/final warning` and start a real seven-day `throttle_until` window. After seven clean days, automatically move `throttle/final warning -> warning` under IR-614. A new qualifying violation during the final-warning window may advance the account back to restriction.

Do not make expiry depend on the user opening a status endpoint, using an old upload route, reconnecting in a particular order, or receiving manual support intervention. Retain support's explicit reset authority as a separate override.

Acceptance group: A16.


### IR-703

Public unauthenticated fair-use case lookup.

`resolved - delete only the unauthenticated public case-status lookup`

Remove `/v1/fair-use/case/{case_ref}/status`, its public response contract, rate-limit registration, generated-client methods, route-policy entry, and tests that exist only for anonymous case tracking. Do not build a replacement public tracking page.

Retain random case references in enforcement events/notifications and protected operator list/detail/case lookup/reset/stage/resolve actions. Retain the case-reference Firestore query/index wherever the protected support lookup still requires it. The surviving support destination is `support@heyintentive.com`. IR-704 subsequently resolves the separate authenticated own-status route as unused and deletes it with the false Settings direction.

Acceptance group: A16.


### IR-704

Signed-in fair-use status inside Account and Plan.

`resolved - keep the simpler notification -> case code -> support pattern`

Do not add a Fair Use card to Account and Plan. Keep stage-change push notifications with truthful stage wording, applicable timer/cloud-allowance information, a random case reference, and `support@heyintentive.com`. Remove the false instruction to check Settings for details.

Because no retained Mac or other handwritten client will consume `/v1/fair-use/status`, delete that signed-in own-status endpoint, response models, generated-client methods, route-policy entry, and exclusive tests. This supersedes IR-703's provisional retention of the authenticated route; protected operator lookup and actions remain. Keep content-specific classifier request/result data transient and out of durable backend state under IR-613.

Acceptance group: A16.


### IR-705

Protected API-only support toolkit.

`resolved - keep and adapt the protected API-only support toolkit without a dashboard`

Retain protected operations to list flagged accounts, inspect one account/events, look up a quoted case reference, resolve an event with notes, reset enforcement, and manually set the enforcement stage. Keep the deployment-secret `X-Admin-Key` pattern for v1; do not ship that key to the Mac or build staff accounts, RBAC, or a graphical support dashboard in this scope.

Use `support@heyintentive.com` in retained support addresses/copy and update the operator runbook. Preserve bounded validation and mutation audit metadata. Every retained manual mutation must comply with the authoritative timer/state transitions resolved in IR-614/702; IR-706 owns that child consistency rule.

Acceptance group: A16.


### IR-706

Manual support stage-transition consistency.

`resolved - keep the raw manual stage override exactly as it is`

Retain the protected `set-stage` command as a direct write of `none`, `warning`, `throttle`, or `restrict`. Do not route it through the automatic transition helper, require a reason, or add operator-specific transition metadata. Preserve the existing behavior where only manual `none` clears `throttle_until` and `restrict_until`.

This makes manual support overrides an explicit exception to IR-614/702's automatic timer contract: a manually selected `throttle` or `restrict` without an existing timestamp does not expire automatically and remains until support manually changes the stage or invokes reset. Automatic classifier-created stages continue using the approved seven-day/thirty-day timers.

Acceptance group: A16.


### IR-707

What counts as a repeated fair-use violation.

`resolved - count only threshold-passing verdicts created after the latest support reset`

Retain every bounded, content-free classifier event as operational history, but count an event toward graduated enforcement only when its stored `misuse_score` is at least `0.7`. IR-615's synthetic `free_exhausted = 1.0` result remains a qualifying strike.

Use the most recent support `reset_at` as the counting boundary so older events cannot silently repopulate the seven-day/thirty-day strike totals after reset. Do not delete those older audit records merely to exclude them from escalation. Keep event resolution semantics separate from reset.

Acceptance group: A16.


### IR-708

Fair-use event-history retention.

`resolved - keep account-lifetime content-free history exactly as it is`

Retain fair-use event and support history without a TTL, cap, scheduled cleanup service, or shorter retention window. Old events remain queryable for protected support/audit purposes while IR-707 prevents them from acting as current strikes outside the recent post-reset qualifying window.

The retained account-deletion worker remains the deletion boundary for the entire user Firestore subtree, including fair-use state/events. Keep IR-613's transient-compute boundary: account-lifetime backend history must not regain titles, overviews, transcripts, audio, screenshots, local conversation IDs, prompt payloads, selected evidence, or detailed classifier reasoning.

Acceptance group: A16.


### IR-709

Complete kill-switch and exempt-user bypass.

`resolved after reversal - keep the current partial kill-switch and exemption behavior exactly as implemented`

Keep fair use explicitly enabled in production, `FAIR_USE_KILL_SWITCH=false` during normal operation, and the exempt UID list empty by default. Do not add a shared complete-enforcement bypass or change existing live cloud-budget checks.

Preserve the current split behavior: the kill switch/exempt UID bypasses new soft-cap escalation, the deterministic daily ceiling, and hard restriction lookup where those guards already exist, while an account already stored at `restrict` may still be metered against the thirty-minute managed-cloud allowance and have its live cloud audio gated after exhaustion. Metering and stored case history continue unchanged.

Acceptance group: A16.


### IR-710

Managed model for explicit-memory normalization.

`reopened and resolved - keep the bounded memory_l2 normalization pattern and route transient inference to Gemini 3.7 Flash`

Preserve the existing instruction to retain every material user-authored detail;
bounded text/provenance/source packet; structured content, subject, predicate,
argument, sensitivity and rationale output; subject and schema validation;
auditable receipt; retryable provider/parse/validation failures; and
no-mutation-on-failure behavior.

Pending-item selection, current-revision validation, retries, receipt storage,
and the normalized write remain in the Mac lifecycle runner and authoritative
GRDB store. Send only the bounded explicit assertion packet through the
authenticated canonical Python backend. Its `memory_l2` workload calls Gemini
3.7 Flash using the server-held Gemini credential, returns the proposal, stores
no cloud Memory copy, and keeps raw Memory content out of logs and durable
backend state. The separate evidence-backed lifecycle decision remains under
IR-730. Do not place a provider key on the Mac, add an on-device replacement,
or restore premium/max/BYOK switching.

Acceptance group: A16.


### IR-711

Hidden Premium/Max tier for retained Mac Gemini workloads.

`delete only the verified-dead Mac Premium/Max selector; keep every live model caller and separately reachable proxy capability`

Confirmed with the user's dead-code condition: remove `ModelTier`, the private `modelQoS_activeTier` UserDefaults getter/setter and change notification, tier-dependent `switch` branches, `tierDescription`, and tests that exist only to activate or describe the unreachable Max state. Replace the surviving `ModelQoS.Gemini` accessors with fixed current-default values: Flash for proactive/Task/Insight workloads, Flash-Lite plus the existing Flash fallback for Live Suggestions, and the unchanged embedding model.

Do not delete the live `ModelQoS` namespace or its retained callers. Do not change prompts, cadence, proxy transport, local persistence, fallback behavior, realtime PTT provider selection, or embeddings. The unused shared-Rust tier disappears separately with the already-approved unused crate deletion under IR-009. Preserve the Python proxy's authenticated `gemini-2.5-pro` allowlist and Pro-to-Flash downgrade behavior for a separate reachability/compatibility decision because a crafted authenticated request can still invoke it.

Acceptance group: A16.


### IR-712

Vertex AI and Gemini AI Studio paths behind the retained proxy.

`reopened and resolved - use the Gemini Developer API only and delete Vertex model selection and fallback`

Retain one authenticated Mac-facing Gemini proxy contract backed only by the
Gemini Developer API and the server-held `GEMINI_API_KEY`. Preserve the bounded
generation, native streaming, and embedding actions, request/response
adaptation, authentication, rate limits, and local result ownership.

Delete `USE_VERTEX_AI`, Vertex model/client selection, project/location model
inference, and the credential-acquisition fallback, together with customer BYOK
routing already rejected under IR-062. Cloud Run ADC remains required for
Firebase, Firestore, Cloud Tasks, and other non-model Google Cloud
infrastructure. Customers do not choose the Google access route or provide a
Gemini key. Prompts and results remain transient with no durable backend content
copy.

Acceptance group: A16.


### IR-713

Managed Gemini proxy authentication, limits, and payload guardrails.

`keep the current shared Gemini proxy guardrails exactly; adapt only entitlement ownership and stale BYOK copy`

Confirmed: retain Firebase authentication; the retained desktop entitlement/trial gate; shared per-UID Redis counters covering generation, streaming, and embeddings; the exact 30-request/60-second burst ceiling and 1,500-request/24-hour hard ceiling; fail-closed `503` behavior when the limiter is unavailable; model/action allowlists; the 5 MiB request cap; one-candidate rule; 8,192-token output clamp; bounded thinking configuration; and the existing request-control sanitization.

Keep these as universal managed-compute safety ceilings rather than a new customer-visible plan matrix. Adapt only Omi/BYOK entitlement wording and configuration to the retained Dodo-backed account contract under IR-006/062/191. Preserve transient proxy handling and sanitized errors; do not add durable prompt, screenshot, or embedding-text storage.

Acceptance group: A16.


### IR-714

Callerless ElevenLabs TTS route beside retained Mac OpenAI TTS.

`delete the callerless ElevenLabs /v2 TTS slice; preserve the live OpenAI /v1 route exactly`

Confirmed: remove the canonical backend's `/v2/tts/synthesize` registration and handler; `backend/models/tts.py`; ElevenLabs-only arbitrary voice/model/output/voice-settings validation and streaming adapter; the route-exclusive upstream HTTP client/semaphore; product-backend ElevenLabs secret/template/harness requirements proven exclusive to this route; the unused `elevenlabs_voice_id` settings response field and Mac decoder/test; route-specific OpenAPI inventory; and exclusive backend tests/docs.

Preserve the complete authenticated `/v1/tts/synthesize` OpenAI `gpt-4o-mini-tts` route, Onyx/Shimmer/Coral/Nova catalog, Shimmer default, voice instructions, preview/prewarm behavior, playback speed, macOS system-speech fallback, entitlement checks, OpenAI route limits, and the shared Redis `check_tts_rate_limit` primitive. Do not edit excluded Windows files under IR-009 or remove an ElevenLabs credential/config occurrence owned by another independently retained deployment without a separate caller audit.

Acceptance group: A16.


### IR-715

Callerless Perplexity/Sonar web-search path.

`delete the verified callerless Perplexity/Sonar web-search slice`

Confirmed: remove `perplexity_tools.py`; the exclusive `web_search -> sonar-pro/perplexity` model lane and Perplexity-only feature helpers; the product-backend `PERPLEXITY_API_KEY` requirement; Perplexity gateway-provider registration and branches proven to have no other surviving caller; route inventory; and tests/docs that exist only for this implementation. Preserve generic gateway abstractions shared by retained providers.

Do not interpret this deletion as approval either to preserve or to remove Claude web search. It does not change private local retrieval, normal Chat, PTT, or any retained model route by itself. Claude web-search reachability is audited separately against the selected local Pi plus `/v2/chat/completions` architecture.

Acceptance group: A16.


### IR-716

Public-web search in normal typed Chat.

`delete public-web search completely`

Confirmed: remove normal typed Chat's public/current-fact routing rules; the Node public-web classifier and prompt injection; synthetic web-search progress and denial-stripping behavior; Claude/Anthropic server-side `web_search` declarations and event handling in hosted-agent residue; the rejected voice `omi_web_search` flag and claims already covered by IR-601/602; the Perplexity slice covered by IR-715; public-web onboarding lookups; and tests, fixtures, diagnostics, copy, and documentation that promise or simulate live search. The exact support boundary includes `backend/desktop_fixtures/public-web-routing-contract.fixture.json`, its Pi-adapter test and architecture-doc references. After the behavior-removal PR is merged, a separate registry-lifecycle PR transitions `.github/failure-classes/FC-public-web-routing-parity.json` from `open` to dormant with `dormant_since`; do not combine that lifecycle transition with the implementation deletion or erase the historical registry entry.

After this deletion, Chat and PTT must not claim that they searched, browsed, verified, or used live information. They may answer from model knowledge while being honest about its limits, or state that current information cannot be verified. Do not replace web search with a different search vendor or local search proxy.

This does not delete private local retrieval over the user's own conversations, memories, tasks, goals, files, or screen history. It also does not automatically delete a separately retained explicit URL-reading or connector capability merely because it accesses a user-supplied resource; those are not general public-web search and remain governed by their own decisions.

Acceptance group: A16.


### IR-717

Product-dead Gemini Pro proxy admission.

`delete Gemini Pro admission and its exclusive downgrade/tier policy`

Confirmed: remove `gemini-2.5-pro` from the desktop proxy's model allowlist; the Pro-only post-soft-limit rewrite to Flash; the `OMI_MODEL_TIER` 30-versus-300 soft-limit branch used only by that rewrite; Pro-only proxy tests, fixtures, comments, and documentation; and any remaining Pro model helper proven to have no surviving caller after IR-711 and the unused shared-Rust deletion under IR-009.

Preserve the live allowlisted Gemini generation and embedding models and actions; the sole Gemini Developer API route under IR-712; Firebase authentication and retained entitlement checks; 30 requests per minute and 1,500 per day with fail-closed Redis; request sanitization; payload/output/thinking bounds; and all live Mac workloads. A hand-crafted Pro request must now receive the same `403` as any unsupported model rather than being accepted or silently downgraded.

Acceptance group: A16.


### IR-718

Callerless Gemini streaming proxy.

`reopened and resolved - keep one authenticated native Gemini streaming action exclusively for normal Chat`

Normal Chat now calls
`POST /v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse` through the
packaged Pi adapter. Keep that one authenticated native-streaming action,
server-held Gemini credential, raw Gemini SSE transport, bounded request and
duration policy, usage accounting, cancellation, typed provider failures, and
opaque thought-signature round trips required by tool continuation.

Keep non-stream generation and embedding actions unchanged. Do not restore the
old `/v1/proxy/gemini-stream/{path}` compatibility route, a generic streaming
action for unrelated callers, Claude Chat, Vertex routing, or provider
selection. Realtime Gemini Live and managed transcription remain separate
protocol owners.

Acceptance group: A16.


### IR-719

Legacy Gemini preview-name compatibility rewrite.

`keep the preview-to-Flash rewrite unchanged`

Confirmed after reversing the initial deletion recommendation: preserve the battle-tested `gemini-3-flash-preview` to `gemini-2.5-flash` path normalization and its focused compatibility test. It is a low-cost safety net for an unexpected older caller and does not keep Gemini Pro, the rejected streaming proxy, Wrapped, OpenRouter routing, the unused shared-Rust crate, or any independent model surface.

Acceptance group: A16.


### IR-720

OpenRouter provider integration after Wrapped deletion.

`delete OpenRouter completely after Wrapped`

Reversed after clarifying that OpenRouter is not carrying normal Chat, PTT, retained Mac Gemini workloads, memory promotion, or another surviving product path. Its only current named workload is Wrapped, which IR-820 deletes. Do not invent a new OpenRouter fallback or provider-switching role merely to keep otherwise-stale plumbing.

After removing Wrapped, delete the product-backend OpenRouter provider registration and client factory; `OPENROUTER_API_KEY` templates, secret wiring, validation, development-harness setup, and deployment configuration; OpenRouter model-name/vendor-prefix and temperature branches; OpenRouter-specific streaming, BYOK rerouting, observability dimensions, fixtures, tests, documentation, and direct-provider guard vocabulary proven exclusive to it; and all standalone-gateway OpenRouter support already leaving under IR-608.

Preserve the direct Gemini Developer API workloads, Gemini Live PTT, retained OpenAI TTS, their credentials, their focused tests, and shared provider abstractions still used by them. Do not connect OpenRouter alongside Gemini and do not replace it with another aggregation provider.

Acceptance group: A16.


### IR-721

Managed model for automatic local Chat titles.

`keep Gemini 2.5 Flash-Lite for automatic titles with local-only title authority`

Confirmed: preserve the first-real-exchange trigger; existing maximum-six-word prompt; title-only response handling; managed Gemini 2.5 Flash-Lite computation; authentication, rate limiting, count-only usage accounting, timeout/error handling, and focused title tests; non-fatal failure that leaves `New Chat`; and manual rename precedence.

Read the title input from the authoritative local journal and bound it to the existing small first-exchange context. Return the candidate transiently from Python without reading or writing a backend Chat session. Validate and persist the accepted title only in the owner-scoped local session catalog, then update the current/sidebar presentation from that local commit.

Delete the Firestore session lookup/update and backend session ID requirement from the compute boundary; server-side title persistence; global premium/max/BYOK title switching; OpenRouter involvement; and tests/contracts that require a cloud session record. This does not change normal Chat's separate native Gemini stream, public-web deletion, local journal authority, or manual rename.

Acceptance group: A16.


### IR-722

Managed model for the automatic local Chat greeting.

`reopened and resolved - preserve the bounded greeting contract and route transient inference to Gemini 3.7 Flash`

Preserve the ordinary primary-assistant greeting prompt's friendly, short,
personalized behavior; one generation attempt when a new ordinary Chat is
created; authentication, rate limiting, count-only usage accounting, bounded
timeout/error handling, and focused greeting tests; and the non-fatal failure
behavior that leaves the existing welcome state and composer usable. The
canonical `chat_greeting` workload uses Gemini 3.7 Flash.

Build the prompt from an explicitly bounded local AI Profile/memory packet supplied for transient computation. Python returns greeting text only and stores no prompt context, output, session, or message. The Mac assigns the local turn identity, commits it directly to the owner-scoped journal, and derives preview/count from that accepted local turn.

Delete Firestore Chat-session lookup/creation; previous backend-message lookup;
backend prompt-memory lookup; app/persona greeting forks; server
message/session writes and server message ID; remote-turn import used only to
copy the greeting back; global premium/max/BYOK route switching; and old
generic `chat_responses` vocabulary or hosted-Chat helpers left with no other
surviving caller. This does not change normal Chat's separate native Gemini
stream, automatic title generation, manual rename, or the local post-onboarding
Home opener.

Acceptance group: A16.


### IR-723

Cloud Mentor/App proactive-notification model workload.

`delete the cloud Mentor/App proactive-notification model workload`

Confirmed: remove the backend Mentor relevance, draft, critic, and combined-evaluation prompts/models/functions; the `proactive_notification` explicit model route and usage feature after all callers leave; Mentor conversation/fact/goal/Pinecone context assembly; Mentor/App notification rate-limit and recent-history state with no other caller; FCM Mentor/App delivery and stored cloud messages; transcript/App trigger branches; rejected capability/schema vocabulary; and exclusive tests, fixtures, configuration, telemetry, and documentation.

Preserve the retained Mac Focus, Task, Memory, Insight, and Live Suggestions assistants; their local settings, gates, cadence, confidence/dedup policies, local GRDB/journal authority, cards and macOS notifications; and their direct managed Gemini Flash/Flash-Lite compute through the guarded proxy. Do not replace the deleted cloud Mentor pipeline with a second local implementation.

Acceptance group: A16.


### IR-724

GPT-personalized subscription and usage-limit notifications.

`delete GPT-personalized push copy; keep the authoritative state and present it locally`

Confirmed: remove the `notifications` model route; subscription-notification usage feature; GPT prompts and generation helpers for purchase welcomes and credit-limit warnings; Firestore memory lookup used by those prompts; Redis recently-sent state used only for the generated credit-limit push; purchase-webhook welcome-push caller; live-listen generated credit-warning push caller; and exclusive tests, fixtures, configuration, telemetry, and documentation.

For a retained usage-limit event, return or expose the authoritative structured state through the authenticated backend boundary and have the Mac show fixed, truthful in-app copy and, where an operating-system notification is required, a local `UNUserNotificationCenter` notification as already required by IR-826. Keep quota enforcement, plan and usage details, the paywall/upgrade action, billing reconciliation and purchase status UI, Dodo subscription work, and relevant error/case/support information.

Do not replace these two deleted messages with a different LLM or with local-memory personalization. This decision does not alter the retained automatic Chat greeting, automatic Chat title, direct OpenAI/Anthropic/Gemini integrations, local Mac proactive assistants, or the separately static silent-user nudge; that static nudge has no `notifications` model call and remains governed by the FCM/product-lifecycle decisions that own it.

Acceptance group: A16.


### IR-725

OpenGlass and smart-glasses image-description models.

`delete the smart-glasses image-description workload`

Confirmed: remove the `openglass` and callerless `smart_glasses` model routes; OpenGlass usage feature; image-description prompt/helper; live-listener `image_chunk` ingestion, validation, chunk buffering, cleanup and limits; photo-processing/photo-described events; newly produced smart-glasses photo buffering/persistence; and exclusive tests, fixtures, configuration, telemetry, dependencies, and documentation.

Preserve Mac screenshot capture and OCR, screen embeddings, images attached to local Chat, ordinary retained Gemini vision use, and all non-camera Mac transcription. Do not infer deletion of historical/imported conversation-photo models, readers, or presentation from this decision; those remain owned by the separate Conversation Detail and transcript/history audit. Do not build a replacement Mac-camera feature.

Acceptance group: A16.


### IR-726

Provider for retained live transcript translation.

`delete self-hosted NLLB and use Gemini 2.5 Flash-Lite alone`

Confirmed: keep retained cloud-STT live translation, but make the existing managed Gemini 2.5 Flash-Lite structured-output route its single provider. Preserve target-language rules, language detection, sentence splitting and batching, cardinality/empty-response validation, deduplication, positive and negative caching, bounded failure behavior, useful metrics, local Mac result authority, live italic presentation, and later local display.

Remove the NLLB provider adapter and language-token compatibility unique to it; NLLB model service and Docker image; CUDA/CTranslate2/model-download runtime; health and translation endpoints; GPU/GKE deployment, chart, autoscaling, monitoring, release workflow, image contracts, runtime URL/secrets/settings, benchmarks/tuning scripts, fallback-to/from-NLLB branches, and exclusive tests/documentation. Collapse provider-selection configuration to the one explicit translation route instead of retaining a one-item provider list.

If Gemini translation fails, preserve the original transcript and the existing bounded missing/retryable-translation behavior; do not block or discard transcription. Do not add translation to local Parakeet, upload locally produced Parakeet text, change the visible translation UI, or alter unrelated direct Gemini workloads.

Acceptance group: A16.


### IR-727

Managed models for retained conversation enrichment.

`reopened and resolved - keep both conversation-enrichment jobs and route transient inference to Gemini 3.7 Flash`

Retain separate `conv_structure` and `conv_action_items` computations using
their established prompt patterns, structured response validation, language
and deterministic local-time handling, due-date normalization, conservative
task-quality rules, related-task deduplication semantics, bounded errors, usage
accounting, and focused behavioral tests. Both canonical workloads use Gemini
3.7 Flash.

Adapt the ownership boundary: the Mac owns the accepted finalized transcript and supplies only the bounded transcript plus independently retained local language, time-zone, conversation-local speaker/context and related-task facts needed for transient computation. Python returns candidate structure and action items without creating or loading a hosted conversation, task, session or processing record. The Mac validates the response against the local enrichment generation, assigns local identities, and commits accepted title, overview, emoji, calendar commitments and linked tasks through the authoritative local transaction.

Remove the global quality-profile and BYOK switching already rejected by IR-609; standalone-gateway/auto-lane/shadow/promotion machinery already rejected by IR-608; Firestore conversation/task reads and writes; server-owned processing state and IDs; rejected category, wearable-photo, App/integration and automatic-folder inputs/outputs; and exclusive compatibility, synchronization and cloud-authority tests. Manual title edits and ordinary local task edit/completion behavior continue to override or mutate their authoritative local records.

This does not alter normal Chat's separate native Gemini stream, automatic Chat
greeting/title jobs, Gemini translation or proactive-assistant workloads,
realtime PTT, or local Parakeet transcription.

Acceptance group: A16.


### IR-728

Managed model for conversation-derived Memory extraction.

`reopened and resolved - keep the memory_l1 extraction and local-admission pattern and route transient inference to Gemini 3.7 Flash`

Retain the source-aware conversation prompt; structured candidate schema;
32-item maximum; source-local speaker and subject-attribution rules;
evidence-quote requirement and exact grounding; candidate
deduplication/bounding; confidence and sensitivity/risk hints; strict
parse/failure behavior; usage accounting; and focused behavioral tests. The
canonical `memory_l1` workload uses Gemini 3.7 Flash.

Adapt the ownership boundary: the Mac supplies a bounded readable transcript built from authoritative local segment rows and conversation-local speaker labels for transient computation. Python returns candidates and stores no transcript, candidate, source, route outcome or memory record. The Mac verifies every evidence quote against exactly one local source segment, resolves subject attribution from authoritative local segment facts, assigns local identities, and admits accepted candidates into the locally authoritative Short-term lifecycle and audit transaction selected under IR-260.

Remove hosted People and user-language/profile lookups by supplying the
independently retained local name/language/context explicitly; Firestore
conversation and Memory reads/writes; canonical cohort/capability selection;
hosted evidence associations, route outcomes, analytics dedup state and
source-replacement transactions; global quality profiles/BYOK and
standalone-gateway machinery already rejected under IR-609/608; rejected
external-integration extraction callers; and exclusive synchronization/cloud-
authority tests. Keep later local promotion/archive behavior and its separately
retained `memory_conflict` consolidation judgment unchanged.

Do not route screenshot/OCR Memories through this conversation endpoint,
replace manual Memory creation, weaken source-conversation deletion cascades,
or make Python authoritative for Memory identity, tier, expiry, correction,
conflict resolution, deletion, or search.

Acceptance group: A16.


### IR-729

Obsolete memory-extraction and category model routes.

`delete the obsolete memories, learnings, and memory_category model routes and keep memory_l1 as the only conversation-memory extractor`

Confirmed: remove the legacy `memories` conversation/text prompt and schemas, the callerless `learnings` prompt/schema/route, the `memory_category` classifier, their model-profile entries and usage branches, and exclusive scripts/tests. Remove `_extract_memories_legacy`, legacy Firestore/vector writes and invalidation logic, parity/canonical-versus-legacy switching, `memory_system_request_scope`, cohort/capability selection, and old-route compatibility code once every in-tree caller has been removed.

Delete the `memory_category` callers with the previously rejected MCP, developer, external-integration, and X/import surfaces rather than recreating the classifier locally. Retained local/manual producers already know which accepted category they create.

Keep `memory_l1` exactly as selected in IR-728 for conversation-derived candidates, `memory_l2` explicit-memory normalization under IR-710, the `memory_conflict` consolidation pattern selected under IR-730, Short-term/Long-term/Archive lifecycle behavior, manual and screenshot-derived memories, local authority, search, correction, deletion, and source-deletion cascades.

Acceptance group: A16.


### IR-730

Managed consolidation and conflict judgment for Short-term memories.

`reopened and resolved - keep the memory_conflict consolidation pattern with local authority and route transient inference to Gemini 3.7 Flash`

Retain the canonical batch prompt; promote/archive/review/reject and
create/duplicate/replace/merge/keep-both vocabulary; total
one-decision-per-input contract; bounded similarity context; subject, evidence,
sensitivity, aboutness, relationship and recurrence rules; supersession/merge
semantics; structured output; deterministic allowlist and conservation
validation; no-mutation-on-invalid-output behavior; retry/review escalation;
usage accounting; and focused behavioral tests. The canonical
`memory_conflict` workload uses Gemini 3.7 Flash.

The Mac's local lifecycle runner selects a bounded due Short-term batch and
relevant active local Memories, assigns an input-generation identity, and sends
only that packet through the authenticated canonical Python backend for
transient inference. Python calls Gemini, returns a proposed batch, and stores
no Memory, evidence, retry, cursor, watermark, or decision record. The Mac
validates every returned candidate, target, supersession, and evidence reference
against the same current local generation, then atomically commits accepted
lifecycle and audit transitions to GRDB. Provider, parse, stale-generation, or
validation failure changes nothing and is retried locally under the retained
bounded policy.

Remove the Cloud Run scheduler/job, Firestore candidate hydration and writes,
hosted retry leases/cursors/watermarks/outbox, cohort gating, cloud
graph/recurrence handoffs already rejected elsewhere, global quality/BYOK and
gateway switching, the legacy per-Memory resolver deleted under IR-729, and
exclusive cloud-authority tests. Do not combine this prompt with `memory_l1`,
make Python authoritative, put a provider key on the Mac, or alter manual
Add/Edit normalization under IR-710.

Acceptance group: A16.


### IR-731

Obsolete hosted Chat extraction/RAG and persona-answer routes.

`delete the old chat_extraction and chat_graph model routes completely`

Confirmed: remove both model-profile entries; `chat_extraction` classifiers, date/filter selection, chunk extraction/summarization, hosted-product-question and cloud RAG helpers; `chat_graph` persona streaming; old hosted agentic retrieval orchestration and exclusive prompt/schema/usage/test/script surfaces; and the old `/v2/messages` processing branches that have no independently retained caller. Remove shared files only after reference-tracing and moving any small provider-neutral helper still used by a retained route.

Preserve the local Node/Pi agent loop; authenticated native managed-Gemini stream; local owner-scoped journal and multiple-thread catalog; typed local conversation/memory/task/goal retrieval; local semantic and exact search; locally managed attachments; automatic greeting/title computations retained under IR-722/721; realtime PTT; and independently retained voice-message STT or reporting endpoints that happen to share a Python router file. Do not replace Pi's tool choice with another classifier layer or route normal Chat through the deleted hosted RAG stack.

Acceptance group: A16.


### IR-732

Managed discard judgment for short ambient conversations.

`reopened and resolved - keep the conv_discard pattern with local conversation authority and route transient inference to Gemini 3.7 Flash`

Retain the empty-content discard fast path; over-100-word automatic keep;
duration-aware higher bar for recordings under two minutes; existing
meaningful-content versus filler criteria; prompt; boolean schema/parser;
bounded provider failure; keep-on-model/parse-failure safety; usage accounting;
and focused behavioral tests. The canonical `conv_discard` workload uses Gemini
3.7 Flash.

Adapt the ownership boundary: the Mac supplies only the bounded authoritative local transcript, duration and word count through the authenticated canonical Python backend. Python performs transient inference, returns the proposed boolean, and stores no transcript, conversation, discard state or processing record. The Mac verifies the response against the current local finalization/enrichment generation and applies the retained local discard/cleanup policy atomically; stale results do nothing.

Remove wearable-photo input and visual criteria under IR-359; hosted
conversation reads/writes and discard synchronization; premium/max/BYOK and
gateway routing under IR-609/608; and exclusive cloud-authority tests. Do not
route long or empty transcripts through the model, weaken keep-on-failure,
apply this classifier to typed Chat/PTT, or change the downstream rule that
discarded ambient captures do not produce visible conversation history,
summaries, tasks, or Memories.

Acceptance group: A16.


### IR-733

Command-line onboarding-completion bypass.

`keep --skip-onboarding exactly as implemented`

Confirmed: retain the global process-argument check and `DesktopHomeView` branch that directly sets `appState.hasCompletedOnboarding = true`. Keep the argument available to local development, agents, automated launches, and published builds launched with that flag. Preserve its current behavior of bypassing `SBOnboardingModel.skip()` rather than adding analytics, capture-intent correction, resume/journal/draft cleanup, landing-policy work, an `AppBuild.isNonProduction` guard, or a separately defined test lifecycle.

This is an explicit acceptance of the narrow direct-flag shortcut, not a claim that it behaves like the visible consent-respecting Skip action retained by IR-127. Do not delete, guard, repair, document, or otherwise redesign it merely because no in-repository caller was found.

Acceptance group: A16.


### IR-734

Terminate the process when the last onboarding window closes.

`keep the current pre-completion terminate-on-last-window-close behavior`

Confirmed: before onboarding completion, closing the final onboarding window continues terminating the complete app process. Preserve the locally saved resume step so a later launch returns to the incomplete flow without marking it complete or erasing its state. After onboarding completion, closing the normal main window continues leaving the menu-bar app, retained capture behavior, and global shortcuts running.

Do not keep an invisible pre-consent background process, reinterpret window close as Skip or completion, delete resume state, or change the post-onboarding menu-bar lifecycle.

Acceptance group: A16.


### IR-735

Diagnostics for disagreement between onboarding state authorities.

`keep the bounded state-authority diagnostics and the completion flag as the UI winner`

Confirmed: retain both disagreement read sites, their bounded state labels/directions, the existing behavioral coverage, and `hasCompletedOnboarding` as the sole Home-versus-onboarding gate. When the completion flag says complete but a valid resume marker or active setup journal remains, continue opening Home and emitting the diagnostic without exposing onboarding answers, Chat content, permission values, or other sensitive data.

Do not automatically repair, clear, resume, or block the UI from this diagnostic. Remove a comparison only if a separately accepted implementation decision deletes the underlying retained resume marker or setup journal.

Acceptance group: A16.


### IR-800

Managed Pi as the only desktop agent adapter.

`delete every non-Pi agent adapter and keep managed Pi as the only desktop agent runtime`

Confirmed: normal Chat and all retained background Agent Pills use the managed Pi adapter. Delete the Claude ACP, Hermes, and OpenClaw adapter implementations and activation/registry branches; the global provider picker in both Settings locations; non-Pi `BridgeMode`/`AgentHarnessMode`/adapter identities and stored-preference compatibility that have no surviving caller; customer-Claude OAuth events/state/URL launch, config-file and Keychain inspection/deletion, connection status and Disconnect UI; local Hermes/OpenClaw executable discovery and environment injection; directed-provider `spawn_agent` input/schema/admission/routing; realtime dynamic provider advertisement; provider-specific pill identity, logos, setup messages, failure formatting, telemetry dimensions, generated contracts, fixtures, tests, and documentation.

Keep the bundled Pi adapter and whatever generic runtime interface it genuinely requires, the local Node kernel and Pi model/tool/model loop, local tool authorization/execution, local journal and restart durability, ordinary managed and background agents, and the authenticated native Gemini inference boundary retained by IR-113. This does not delete Gemini Live PTT, cloud-STT providers, retained OpenAI TTS, or other non-agent model workloads merely because they are also called providers.

No product-code deletion is authorized yet.

Acceptance group: A17.


### IR-801

Separate AI Chat Settings destination after rejected cards leave.

`move Ask Mode into Advanced AI Setup and delete the separate AI Chat Settings destination`

Confirmed: move the existing Ask Mode card without changing its label, default-off preference, conditional composer switch, per-turn plumbing, current SQL-only check, or tests required by IR-218. Place it beside the surviving Voice Model control in **Advanced > AI Setup**. Delete the top-level **AI Chat** sidebar destination, empty section renderer, exclusive search/navigation/deep-link/automation routing, and section-only tests after all rejected cards are removed.

This does not delete normal Chat, Ask Mode, the floating Chat composer, managed Pi, managed Gemini inference, or the separate Floating Bar Settings page.

No product-code deletion is authorized yet.

Acceptance group: A17.


### IR-802

Proposed static provider-disclosure card.

`do not add the static provider-disclosure card`

Confirmed: do not replace the deleted provider picker with a read-only Chat Model/provider information card in Advanced or AI Chat Settings. Remove the picker's taglines and external-provider attribution with the picker under IR-800.

This decision is scoped to the proposed Settings card. It does not authorize inaccurate onboarding, Privacy, Terms, or network-processing claims; those already require truthful rebranding against the final retained architecture. No separate provider-selection or connection UI survives.

No product-code deletion is authorized yet.

Acceptance group: A17.


### IR-803

One canonical Python backend service and URL.

`consolidate retained Mac cloud behavior into one Python backend and remove the stale Rust identity`

Confirmed: deploy one canonical Python FastAPI service for the surviving Mac account/billing, auth, cloud-STT, managed Chat, realtime credential/usage/relay, Gemini proxy/embedding, TTS, account-deletion worker, payment callback, and other separately retained server behavior. Reuse the existing route implementations already mounted by the main application; do not redesign those behaviors merely to consolidate deployment.

Use one canonical Python backend URL and environment binding. Replace `rustBackendURL`, `DesktopBackendEnvironment.rustBackendURL`, `developmentRustBackendURL`, `OMI_DESKTOP_API_URL`, automation/diagnostic payload fields, comments, logs, tests, scripts, and documentation with truthful Python naming, consolidating with the existing Python-base resolver rather than creating two differently named aliases for the same service. Delete the separate desktop-backend entry point, Docker image, Cloud Run service, deployment/recovery/promotion plumbing, service-specific health identity, and duplicate operational configuration after every retained caller is routed through the canonical service.

This does not move Python onto the customer Mac and does not delete any retained hosted behavior. It also does not decide IR-804's release-compatibility policy.

Acceptance group: A17.


### IR-804

Optional exact-source backend identity versus live compatibility.

`keep independent backend deployment plus live compatibility; delete dormant exact-SHA mode`

Confirmed after correcting the original description: preserve Omi's actual release pattern against the one canonical Python backend from IR-803. Backend deployment remains independent from Mac artifact promotion. Beta and Stable continue to fail closed on a real live backend health/readiness check and an explicit versioned compatibility contract, and a Mac change that requires a newer contract must wait for that compatible backend deployment. Mac-only changes do not rebuild Python merely to share a source commit.

Delete the unproduced `backend_required` manifest mode, exact desktop-backend source/image/digest fields, conditional schema branches, fixtures, lineage binding, and exclusive tests after a final implementation-time caller check. Preserve the app artifact's own exact source identity, qualification evidence, signing, notarization, Sparkle publication, Beta/Stable pointers, and all other retained release safeguards.

Acceptance group: A17.


### IR-805

Sentry feedback copied into administrator cloud Tasks.

`delete the Sentry-to-cloud-Task bridge`

Confirmed: remove the Sentry feedback webhook and polling routes, hardcoded organization URLs, Sentry admin UID/token polling configuration unique to this bridge, issue-to-action-item transformation, duplicate detection/ranking, `sentry_feedback` Task source and exclusive rich-metadata presentation, route-policy entries, tests, and documentation.

Keep the Mac Sentry SDK, crash and error reporting, privacy-bounded diagnostics, debug-symbol publication, the separately retained in-app Report an Issue behavior, and PostHog. Feedback remains available in this product's own Sentry project rather than being copied into backend-owned product Tasks.

Acceptance group: A17.


### IR-806

Separately hosted Typesense search.

`delete Typesense completely`

Confirmed: remove Typesense deployment/configuration/secrets; Python client and lazy compatibility shim; conversation and memory collection schemas; indexing, deletion, synchronization, Firestore hydration, retry/fail-soft, readiness and repair behavior; migrations/scripts; generated-only compatibility; and exclusive tests/docs. Preserve the agreed local GRDB/FTS5 search fields, debouncing/cancellation/result limits, local semantic vectors, and keyword-plus-vector result behavior.

Acceptance group: A17.


### IR-807

Pinecone hosted vector authority.

`delete Pinecone completely`

Confirmed: remove Pinecone credentials, dependency/client initialization, indexes/namespaces, all hosted vector upsert/query/delete and metadata-filter branches, projection/synchronization, repair outboxes/workers, backfills/migrations/readiness scripts, account-deletion cleanup, deployment configuration, and exclusive contracts/tests/docs. Preserve transient embedding computation, locally persisted vectors, local cosine-similarity/search logic, and every retained user-facing semantic-retrieval behavior.

Acceptance group: A17.


### IR-808

Redis for surviving temporary server coordination.

`keep one Redis service narrowly for retained ephemeral coordination`

Confirmed: retain one Redis dependency and readiness contract for explicitly surviving OAuth sessions/single-use codes, rate limits, fair-use and restricted-allowance counters, short locks, and bounded caches. Remove every key family, helper, configuration branch, test, and operational assumption belonging only to deleted public sharing, hosted product data, connectors, Apps, Daily Summary, cloud synchronization, protection migrations, Agent VM, or other rejected products. Do not store Mac-authoritative product content in Redis and do not introduce Redis synchronization for local data.

Acceptance group: A17.


### IR-809

GCS product-data storage versus Mac update distribution.

`delete GCS product-data storage; keep one rebranded Mac update-distribution bucket`

Confirmed: remove rejected product-data buckets/paths, uploads/downloads/signed URLs, lifecycle and cleanup jobs, service-account/IAM permissions, environment variables, deployment branches, account-deletion cleanup, tests, and documentation unique to those stores. Retain one product-owned GCS bucket and the minimum publication/read permissions needed for signed Sparkle ZIPs, update feeds, Stable repair metadata, and retained preview builds. Replace Omi bucket names, URLs, project identities, and release configuration with ours.

This does not authorize private Mac data upload to the release bucket and does not remove signing, notarization, Sparkle, Beta/Stable channels, or the live-compatibility checks retained under IR-804.

Acceptance group: A17.


### IR-810

Separate Pusher WebSocket side-effect service.

`delete the entire Pusher service and protocol`

Confirmed: remove the Pusher FastAPI entry point and router, `/v1/trigger/listen`, the binary frame protocol, `ListenPusherSession`, duplicate audio/transcript/control dispatch, reconnect and circuit-breaker state, buffering and bounded queues, readiness/drain behavior, Pusher Helm chart and GKE service, deploy/auto-deploy workflows, monitoring/alerts/dashboards, rollout and degraded-service scripts/runbooks, exclusive test harnesses, environment bindings such as `HOSTED_PUSHER_API_URL`, and code/configuration used only by those rejected consumers.

Preserve direct `/v4/listen` audio-to-STT-provider streaming, transcript events returned to the Mac, generic within-conversation speaker labels, the Mac WebSocket watchdog/reconnect path, and separately retained privacy-bounded diagnostics. No replacement queue or side-effect worker is required.

Acceptance group: A17.


### IR-811

Separate GKE `backend-listen` deployment.

`serve /v4/listen from the canonical Python backend and delete the separate GKE listener control plane`

Confirmed: keep the authenticated `/v4/listen` route and transient managed cloud-STT behavior, but expose it from the canonical Python backend selected by IR-803. Remove the `backend-listen` Helm chart, GKE Deployment/Service/NEG, HPA and active-connection scaling adapter, scheduled scale-up/down resources, listener-specific service account/configuration, deployment and rollback workflows, separate release identity, dashboards/alerts/runbooks, and exclusive infrastructure contract tests.

Do not delete cloud continuous transcription, Intel-Mac support, local-model failure fallback, server-configured VAD, generic diarization, live translation, fair-use accounting, or the Mac reconnection path. A separately scaled listener service is not retained speculatively; it may be reconsidered only from measured production need.

Acceptance group: A17.


### IR-812

Separately hosted VAD service.

`delete the separately hosted VAD service; keep the in-process live gate`

Confirmed: remove the hosted VAD deployment/chart, service URLs, external request/fallback branches that have no surviving caller, model-deployment workflow, secrets/configuration, monitoring, tests, scripts, and documentation exclusive to completed-recording VAD or speech-profile matching. Retain `VADStreamingGate`, its local Silero ONNX model/runtime, server-controlled `VAD_GATE_MODE`, live metrics/fail-open behavior, timestamp mapping, provider keepalives, and fair-use speech accounting.

This does not alter the Mac **Local VAD Gate** card retained exactly as implemented under IR-228 and does not wire that disconnected preference to Python.

Acceptance group: A17.


### IR-813

Separate GPU diarizer service.

`delete the standalone GPU diarizer and make generic diarization part of the cloud-STT provider contract`

Confirmed: remove the diarizer FastAPI service, Pyannote/WeSpeaker standalone image, Helm chart/GPU deployment, service URL and external fallback, deployment workflow, monitoring, benchmarks, exclusive tests, and speaker-vector helpers whose only surviving purpose would be cross-conversation identity. During the reserved provider/model audit, any selected cloud-STT route must itself return stable generic speaker labels within the current connection; a candidate that cannot satisfy that contract is not eligible unless this requirement is explicitly reopened.

Preserve generic within-conversation speaker numbering, the deterministic local segment-normalization behavior, local manual speaker labels, and the rejection of persistent voice samples/identity. This decision does not choose between the deferred cloud STT providers.

Acceptance group: A17.


### IR-814

Hourly Notifications Cloud Run job.

`delete the complete Notifications Cloud Run job`

Confirmed: remove the `notifications-job` entry point and Docker image, hourly scheduler/job resource, deployment workflow, runtime image and environment manifest entries, notification/X cron dispatcher, wearable reminder, cloud Daily Summary generation/deduplication/storage/webhook/push path, X synchronization invocation, job-specific secrets/configuration, validation rules, and exclusive tests/docs. Remove push-token and scheduled-notification helpers only where no separately retained caller remains.

Preserve local task reminders, proactive overlay delivery, retained billing/account notifications that execute in their own request path, in-app error/status messages, Sentry, PostHog, and any generic notification primitive with a proven surviving caller.

Acceptance group: A17.


### IR-815

Canonical cloud memory-maintenance job.

`delete the complete cloud memory-maintenance job and control plane`

Confirmed: remove the job entry point and Dockerfile, Cloud Run Job and scheduler, manual/auto-development deployment workflows, runtime-image manifest entry, `memory-maintenance-job` environment/secrets, `MEMORY_MODE` maintenance coupling, allowlists and rollout gates, normalization/TTL/promotion/consolidation cron orchestration, projection/workstream recurrence hooks, job-only validation rules, monitoring, tests, and documentation. Delete shared canonical-memory helpers only when no separately surviving caller remains.

Preserve local memory extraction, local memory CRUD/search/vector behavior, local lifecycle/category decisions already retained, the private local AI Profile, Chat/Focus/Insight personalization, and transient model compute used by those Mac-owned features.

Acceptance group: A17.


### IR-816

Public AI Persona/clone product.

`delete the complete public Persona/AI-clone product`

Confirmed: remove the remaining Mac Persona page and API client/models/navigation or Apps entry points, backend persona routes/database/helpers, public username and prompt/image generation, public-memory coupling, persona-specific Chat/greeting branches not already removed by IR-045/046, `web/personas-open-source`, its public-build target/configuration, Cloud Run deployment workflow, assets, telemetry, tests, and documentation exclusive to the clone product. Remove shared public-build machinery only if it has no separately retained target.

Preserve the owner's private local AI Profile, local memories, the one primary assistant, ordinary local personalization, and the public product/legal website independently retained elsewhere.

Acceptance group: A17.


### IR-817

Duplicate `backend-integration` Cloud Run service.

`delete backend-integration and its external App API control plane`

Confirmed: remove the `backend-integration` Cloud Run service, duplicate deployment and traffic-promotion steps, runtime environment/secrets, revision/release-vector/readiness/repair entries, service-specific monitoring, public integration OpenAPI export and contract, external integration routes/models/API-key and enabled-App checks, hosted data transformations, webhook/notification dispatch, exclusive tests, and documentation. Delete shared integration helpers only after proving no retained caller remains.

Preserve the canonical Python backend, Firebase account authentication, browser OAuth used for product sign-in, Dodo webhook handling, retained model/STT/TTS routes, and local managed-Pi tool behavior.

Acceptance group: A17.


### IR-818

Source-less Plugins Cloud Run workflow.

`delete the zombie Plugins deployment and service-only residue`

Confirmed: remove `gcp_plugins.yml`, its deployment-concurrency registration, runtime-image/check-manifest references to the nonexistent Dockerfile, Plugins Cloud Run dashboards/alerts/service catalogs, scripts/docs/tests exclusive to that missing service, and any dead release-notification entries. Do not create replacement plugin source or preserve a compatibility deployment.

Preserve managed Pi, the local Node runtime and retained typed tools, local proactive assistants, and any unrelated reusable deployment primitive with another live target.

Acceptance group: A17.


### IR-819

Twilio outbound-phone-call product.

`delete the complete Twilio phone-call product`

Confirmed: remove phone verification/list/check/delete/token/TwiML routes and models, Firestore verified-number/pending-verification/usage/config collections, caller-ID encryption/hash and primary-selection logic, quotas and country restrictions, Twilio SDK/service/signature/token/dialing helpers, credentials and webhook configuration, user-plan phone-quota fields, conversation `call_id` remnants, account-deletion cleanup, generated contracts, dependencies, tests, and documentation unique to outbound calling.

Preserve Mac Zoom/Meet/Teams detection, microphone and system-audio capture, continuous meeting transcription, ordinary `/v4/listen`, PTT/realtime voice, and generic conversation-local speaker labels. Those features do not place telephone calls through Twilio.

Acceptance group: A17.


### IR-820

Annual cloud Wrapped recap.

`delete the complete Wrapped product`

Confirmed: remove the Wrapped routes, Firestore status/result store, generation and progress/restart machinery, yearly conversation/task analytics, Wrapped-specific Gemini prompts/model purpose, completion notification, generated Mac API methods, rate-limit/configuration entries, tests, and documentation. Remove shared helpers only when no retained caller remains.

Preserve local conversations, local Tasks and productivity behavior, local AI Profile/insights, ordinary retained model compute, and unrelated notifications.

Acceptance group: A17.


### IR-821

Firestore-controlled announcements.

`delete the cloud announcement product while preserving local Mac update communication`

Confirmed: remove the announcement routes, models, Firestore queries and collections, admin secret-key CRUD, version/device/platform targeting, per-user dismissal and CTA tracking, generated Mac API methods, route-policy/OpenAPI residue, tests, and documentation exclusive to this product.

Preserve and rebrand the local Mac post-update toast, its local suppression state, the About **What's New** link, Sparkle update behavior, release notes, and unrelated in-app notices.

Acceptance group: A17.


### IR-822

Public Firestore memory-topic Trends feed.

`delete the complete Trends product`

Confirmed: remove the Trends route, Firestore database helper and collections, trend classifiers/models/prompts with no other caller, route-policy/OpenAPI entries, tests, and documentation exclusive to the feed. Remove shared primitives only when no retained caller remains.

Preserve Rewind, local memories and their search, local Tasks/productivity scores, Focus/Insights, and unrelated current-information lookup behavior.

Acceptance group: A17.


### IR-823

Omi hardware firmware and OTA metadata API.

`delete the complete wearable firmware API`

Confirmed: remove the firmware router, hardware-model mapping, Omi firmware-tag and release-body parsing, OTA asset selection and compatibility rules, generated API methods, release-cache entries used only by firmware, tests, and documentation exclusive to wearable updates. Remove shared GitHub-release helpers only when no retained caller remains.

Preserve the Mac Sparkle updater, signed Mac artifacts, Stable/Beta channels and feeds, update policy/recovery, About checks, release notes, and local **What's New** experience.

Acceptance group: A17.


### IR-824

Hosted Limitless ZIP-import product.

`delete the complete Limitless cloud-import product`

Confirmed: remove the upload/status/list/cancel/delete routes, temporary ZIP lifecycle, Limitless Markdown parser and conversation converter, Firestore import-job storage, hosted conversation persistence, push completion/failure notifications, no-op imported-conversation deletion route, generated Mac methods, models, multipart configuration, tests, and documentation exclusive to this importer.

Preserve local conversations and ordinary user-added content. This decision does not require building or prohibit later proposing a genuinely local file importer against local GRDB; such an importer would need its own concrete requirement and audit.

Acceptance group: A17.


### IR-825

Cloud task productivity-score APIs.

`delete the orphaned cloud score product instead of localizing unused presentation`

Confirmed: remove both score routes, Firestore score calculations, response models, Mac `getScores` client and score state/loading, obsolete score widgets and exporter entry, generated contracts, route-policy entries, tests, and documentation exclusive to the score product. Remove shared Task models or calculations only when no retained caller remains.

Preserve local Tasks, their completed/pending state and dates, all retained Task UI and mutations, and the ability to propose a local score later if a concrete retained screen requires it. Do not keep an invisible background calculation solely for possible future use.

Acceptance group: A17.


### IR-826

Mobile Firebase Cloud Messaging platform.

`delete mobile FCM and adapt surviving server warnings to the Mac`

Confirmed: remove the FCM token endpoint and Firestore token collection/migrations, Firebase Admin message builders and batching, Android/iOS/WebPush compatibility, mobile background-data contracts, invalid-token cleanup, arbitrary admin push, Apps/integration notification route, generated Mac token method, exclusive configuration/dependencies/tests/docs, and rejected-product notification callers.

For surviving fair-use or managed-usage transitions, expose the authoritative state and truthful message through a retained authenticated Mac/backend interaction and have the Mac present the warning in-app and, where the retained requirement calls for an operating-system notification, through local `UNUserNotificationCenter`. Preserve case references, restriction timers/allowances, support direction, ordinary local task reminders, proactive overlay notifications, billing reconciliation UI, and unrelated Sentry/PostHog diagnostics.

Acceptance group: A17.


### IR-827

Langfuse LLM tracing and observability.

`preserve Omi's observability lifecycle while replacing only the vendor with Langfuse`

Confirmed: use the existing owned US Langfuse project and the current v4 SDK for lazy client initialization, deterministic trace correlation, prompt-linked generations, sanitized status/error reporting, and bounded shutdown flushing. Require both public and secret keys before enabling delivery, and keep every failure outside the Chat behavior boundary. The implementation deliberately does not restore backend Chat persistence, server-side tool spans, in-app ratings, or Omi's deleted agent architecture.

Keep Sentry and PostHog as separate retained systems with their own responsibilities. Remove all Intentive runtime LangSmith imports and configuration; a transitive package required by LangChain is not an active provider path. Do not add dual delivery or a generic observability-provider abstraction.

Acceptance group: A17.


### IR-828

Langfuse Prompt Management.

`keep Langfuse Prompt Management plus an identical repository fallback`

Confirmed: retain remote prompt fetching/linking, the configured prompt name, version metadata, Langfuse SDK cache and stale-while-revalidate behavior, source metadata, identical blank local fallback, environment configuration, and focused tests. Resolve it through the bounded LLM executor only after request validation and skip all prompt and tracing work for the offline stub.

Accept the current two-level authority: the Langfuse prompt is authoritative when successfully fetched, and the identical repository text is the availability fallback. Prompt history is append-only operator state in Langfuse and is not deleted by repository automation.

Acceptance group: A17.


### IR-829

Server Mentor notification-frequency setting.

`delete the orphaned server Mentor setting`

Confirmed: remove both routes, request/response models, Firestore field/helpers, memory-cache key, generated bindings, route-policy entries, exclusive tests/docs, and Mentor-frequency reads with no separate surviving caller.

Preserve the retained local proactive assistants, proactive overlay, local macOS notifications, and their already-approved local settings and persistence. Do not add a second cloud mirror for those local controls.

Acceptance group: A17.


### IR-830

Local-authoritative user product-data export.

`keep user data export, but make product content local-authoritative`

Confirmed: add one simple Mac **Export My Data** action that writes a user-chosen JSON file containing the retained local conversations/transcripts, memories, Tasks, Goals, Chat history, Focus data, and relevant local settings from their authoritative stores. Reuse existing local serialization/storage boundaries where possible; do not upload local product data merely to export it.

Replace or narrow the backend exporter so it returns only genuine retained server-side account, entitlement, subscription/billing, and other user metadata we actually hold and are permitted to expose. Delete the old cloud conversation/memory/people/task/chat export readers, generated assumptions, and exclusive tests/docs. The local export may incorporate the authenticated server metadata response, but the server must not masquerade as the authority for Mac-local content.

Acceptance group: A17.


### IR-831

Detailed and client-self-reported LLM usage APIs.

`delete unused detailed usage readers and personal-adapter self-reporting`

Confirmed: remove the two unused detailed-reader routes and models, the personal-adapter POST route/model, Mac `recordLlmUsage` client and rejected-harness caller, generated bindings, route-policy entries, and exclusive tests/docs. Remove aggregation helpers only if no retained operator or billing caller remains.

Preserve authoritative server-recorded managed Chat usage, managed PTT count/cost reporting, quota-question idempotency, `/usage-quota`, the total managed-cost value used by the existing limiter, Dodo entitlement mapping, fair-use accounting, billing controls, and Langfuse traces. Do not let arbitrary customer-supplied cost values influence retained billing or quota state.

Acceptance group: A17.


### IR-832

Langfuse operator evaluation without restoring the in-app rating product.

`keep Langfuse website-side annotation and evaluation; do not restore in-app ratings`

Confirmed: retain trace collection and Langfuse's operator-side annotation, dataset, and evaluation lifecycle for v1. Keep the in-app thumbs-up/down controls, Firestore message/rating analytics, and coupled rating event deleted under IR-043. If explicit end-user feedback is justified later, it requires its own local-authoritative requirement rather than silently reviving Omi's cloud rating pipeline.

Acceptance group: A17.


### IR-833

Cloud conversation-summary rating product.

`delete the cloud conversation-summary rating product`

Confirmed: remove both routes, request/response models, Firestore rating helpers and fields, generated bindings, route-policy entries, and exclusive tests/docs. Preserve Langfuse operator-side evaluation under IR-827/832 and the retained local conversation/transcript experience.

Acceptance group: A17.


### IR-834

Joan cloud-conversation follow-up-question endpoint.

`delete the Joan follow-up-question endpoint`

Confirmed: remove the route, its cloud-conversation lookup and prompt helper when unreferenced, generated bindings, route-policy entry, and exclusive tests/docs. Preserve the independent retained local Chat, onboarding, suggestion, and proactive-assistant behaviors.

Acceptance group: A17.


### IR-835

Unused detailed general usage-history API.

`delete the unused detailed usage-history API`

Confirmed: remove `GET /v1/users/me/usage`, its exclusive response/period models, generated bindings, route-policy entry, and endpoint-only tests/docs. Remove aggregation helpers only when no retained subscription, billing, fair-use, support, or administrative caller remains.

Preserve authoritative usage recording, monthly subscription usage, managed Chat quota, total managed cost, fair-use state, reset/support tooling, and the retained Account usage card.

Acceptance group: A17.


### IR-836

Omi self-hosted GKE monitoring platform.

`delete the complete Omi self-hosted monitoring platform`

Confirmed: remove the monitoring Helm charts, Omi-specific Prometheus scrape deployment, Grafana/Loki/Alloy/Alertmanager infrastructure, exporters/adapters used only by that stack, Omi dashboards and alert rules, monitoring-domain/bucket/secrets configuration, deploy workflows, and exclusive tests/docs. Remove monitoring references from deleted service charts as their owning services disappear.

Preserve Sentry, PostHog, Langfuse, ordinary sanitized backend logs, provider-native infrastructure monitoring, and the separately retained lightweight metrics surface under IR-837. A future managed metrics integration may consume that surface without recreating Omi's GKE monitoring platform.

Acceptance group: A17.


### IR-837

Lightweight authenticated backend metrics surface.

`keep the lightweight authenticated metrics endpoint and useful counters for v1`

Confirmed: preserve the authenticated route, secret requirement, low-cardinality/privacy boundary, and useful counters in retained backend paths. It remains optional and creates no requirement to deploy Prometheus, Grafana, or another collector for v1. Remove counters and dashboards owned exclusively by rejected products when those products are deleted; do not preserve deleted services merely to keep their metrics.

Acceptance group: A17.


### IR-838

Backend process-health endpoint.

`keep the backend health endpoint unchanged`

Confirmed: retain `/v1/health`, its small response model, route-policy entry, and deployment/smoke-test callers. Keep its purpose narrow: basic process reachability, not a public product-status page or an expensive downstream dependency check.

Acceptance group: A18.


### IR-839

Canonical Python backend host.

`keep one canonical Python backend on Cloud Run for v1`

Confirmed: retain one Cloud Run service hosting the surviving `backend/main.py` routes, with our project identity, domain/URL, service account, runtime secrets, scaling/timeouts, and deployment contract. Delete rejected duplicate and supporting service deployments rather than carrying their topology into our project.

Acceptance group: A18.


### IR-840

Development and production backend environments.

`keep separate development and production Cloud Run backends`

Confirmed: retain one development service and one production service with our own environment-specific Firebase/GCP identities, Dodo configuration, provider credentials, Redis and other genuinely retained bindings. Development changes must not share production customer data or production secrets. Delete namespaces, variables, secrets, and release identities that exist only for rejected services.

Acceptance group: A18.


### IR-841

Automatic development backend deployment.

`keep automatic development deployment, simplified to one service`

Confirmed: retain backend-change scope detection, successful-check gating, immutable source/image identity, automatic deployment to the canonical development Cloud Run service, health/readiness validation, and clear failure evidence. Remove synchronization, integration, GKE listener/gateway/secrets, multi-service release-vector, and rejected-product readiness branches. Do not deploy for Mac-only or documentation-only changes that cannot affect the backend.

Acceptance group: A18.


### IR-842

Safe production rollout for the single backend.

`keep candidate validation, controlled traffic promotion, and rollback for one service`

Confirmed: preserve exact reviewed-commit deployment, immutable image identity, a no-customer-traffic candidate, backend health/readiness and Mac compatibility checks, controlled traffic promotion, post-promotion verification, previous-revision restoration, and useful deployment evidence for the canonical production service. Remove rejected-service targets, GKE gates, multi-service release vectors, and service-specific rollback state. This keeps release safety without carrying Omi's infrastructure topology.

Acceptance group: A18.


### IR-843

GitHub-to-Google deployment authentication.

`replace permanent JSON deployment keys with short-lived Workload Identity Federation`

Confirmed: create narrow development and production GitHub OIDC/WIF providers and dedicated service accounts in our Google project; bind the exact repository/workflow/environment identities; grant only permissions required by the retained single-service deployment, read checks, Artifact Registry, Cloud Run promotion/recovery, and other separately retained operations; and update GitHub authentication steps to use provider/service-account inputs rather than credential JSON.

Remove permanent deployment/read-only JSON secrets after the federated paths are proven. Do not reuse Omi project IDs, repository IDs, service accounts, or broad roles.

Acceptance group: A18.


### IR-844

Omi OpenTofu pilot and empty foundation scaffold.

`delete the Omi-specific OpenTofu pilot and empty future scaffold`

Confirmed: remove the foundation placeholder, development WIF pilot, read-only probe, Omi-specific backend examples, validation/plan workflows, guard scripts, fixtures/tests, issue references, and exclusive documentation. Configure the narrow WIF identities selected by IR-843 directly for v1. Do not introduce a replacement infrastructure-as-code platform until a concrete retained infrastructure requirement justifies it.

Acceptance group: A18.


### IR-845

Exact-main Release Eligibility proof.

`keep Release Eligibility, simplified to retained checks`

Confirmed: preserve exact main SHA checkout and identity proof, deterministic retained preflight, immutable proof consumption, stale/superseded-run handling, and clear evidence. Remove checks, manifests, release-vector fields, and admission conditions owned exclusively by deleted products or services. The proof does not authorize deployment of an arbitrary branch or unmerged source.

Acceptance group: A18.


### IR-846

Emergency backend deployment recovery.

`keep audited break-glass deployment and traffic repair for the single backend`

Confirmed: preserve exact-main ancestry for break glass, explicit typed confirmation, reason/evidence recording, narrow environment authorization, and the source-independent traffic-repair path. Restrict both to the canonical Cloud Run backend and its retained development/production environments; remove sync, integration, GKE, gateway, listener, and multi-service recovery state. Neither path may bypass the rule that production source is merged to main.

Acceptance group: A18.


### IR-847

Backend Python base-image ownership.

`replace the Omi base image with a pinned Python 3.11 slim base under our control`

Confirmed: use a specific immutable digest from an official source or a controlled copy in our registry, preserve the retained two-stage dependency build and locked Python environment, and update image-contract tests/configuration. Remove Omi registry identity and LC3-only build packages/libraries after IR-403 is implemented. Do not remove `ffmpeg` or another native package without tracing a separately retained audio caller.

Acceptance group: A18.


### IR-848

Retained production secrets.

`keep Google Secret Manager for genuine retained runtime secrets`

Confirmed: create environment-separated secret containers and least-privilege Cloud Run access in our Google project, bind values by reference, and keep payloads out of source, logs, deployment evidence, and ordinary environment configuration. Delete every binding/container/validation rule whose only caller is rejected; do not port Omi secret values or project identities.

Acceptance group: A18.


### IR-849

Validated runtime-environment manifest.

`keep the manifest pattern, collapsed to the retained deployment`

Confirmed: retain one declarative, validated source for the canonical development and production backend's public values, secret references, service flags, and required environment differences. Remove GKE, duplicate services/jobs, rejected product variables, provisional rollouts, service-discovery URLs, renderer branches, validation rules, workflow inputs, fixtures, and docs that have no retained owner.

Acceptance group: A18.


### IR-850

Non-root container and writable filesystem scope.

`keep the non-root user and narrow writable locations`

Confirmed: retain an unprivileged runtime identity and ensure application source/dependency paths are not writable merely for deleted sync behavior. Give the process only the temporary/cache directories proven necessary by retained endpoints, using Cloud Run's ephemeral storage without treating it as durable product storage. Preserve successful startup, audio processing, and other retained temporary-file behavior through focused container tests.

Acceptance group: A18.


### IR-851

Cloud Run private networking for retained Redis.

`keep one private-ranges-only Cloud Run-to-Redis network path`

Confirmed: create our own environment-specific VPC/subnet or equivalent narrow private connection required by the retained Redis service and send only private-address traffic through it. Delete Omi network/subnet names, GKE/gateway ingress and static-address paths, service-discovery routes, connectivity probes, firewall/IAM rules, and validation owned only by rejected services. Do not broaden the private network into a replacement compute platform.

Acceptance group: A18.


### IR-852

Public backend entrance with per-route authentication.

`keep internet-reachable Cloud Run ingress and authenticate inside each route boundary`

Confirmed: retain public network reachability for the canonical service while preserving or tightening authentication, authorization, signatures, rate limits, payload bounds, and route-policy tests for every non-public endpoint. Do not treat infrastructure-level unauthenticated invocation as application-level anonymous access, and do not make internal worker or metrics routes public merely because they share the service.

Acceptance group: A18.


### IR-853

Browser CORS boundary for a Mac-only v1.

`keep default-deny CORS with no allowed browser origins for v1`

Confirmed: preserve the canonical exact-origin/no-wildcard guard and leave `CORS_ALLOWED_ORIGINS` empty in development and production unless a separately retained browser caller is proven. Delete the duplicate desktop backend's permissive policy with that service. Direct browser navigation to public redirects/health does not require a cross-origin JavaScript allowance.

Acceptance group: A18.


### IR-854

Mutable `backend:latest` image alias.

`delete the unused mutable alias and preserve the exact-image release pattern`

Confirmed: stop tagging and pushing `backend:latest` in development and production. Continue building once from the exact admitted commit, smoke-testing that commit image, publishing its immutable identity, deploying the same candidate, promoting after acceptance, and restoring an exact prior revision on failure. Preserve the separate build-cache identity. Remove alias-only documentation/tests; do not replace it with another moving production tag.

Acceptance group: A18.


### IR-855

Explicit Cloud Run capacity configuration.

`declare all important Cloud Run capacity settings in the validated runtime manifest`

Confirmed: make development and production CPU, memory, request timeout, per-instance concurrency, minimum instances, and maximum instances explicit, rendered, validated, deployed, and included in candidate/serving evidence for the one canonical service. Remove reliance on Omi console state and rejected-service capacity fields. Exact CPU/memory/concurrency/max values remain child capacity questions rather than being guessed inside this parent decision.

Acceptance group: A18.


### IR-856

Cloud Run timeout for retained meeting transcription.

`set the canonical backend request timeout to 60 minutes`

Confirmed: declare and validate a 3,600-second timeout for development and production. Retain the Mac watchdog, token refresh, generation/session fencing, bounded reconnect, error presentation, and same-local-recording continuation because network, rollout, instance, and maximum-duration closures still occur. Do not restore cloud conversation identity or server finalization to support reconnection.

Acceptance group: A18.


### IR-857

Development and production warm-instance floors.

`development minimum zero; production minimum one`

Confirmed: allow the development service to scale fully to zero, keep one production instance warm, and let both autoscale above their floor within the separately selected maximum. Declare the settings at service scope in the runtime manifest and deployment evidence so tagged candidate revisions do not accidentally create additional hidden warm-instance cost.

Acceptance group: A18.


### IR-858

Single v1 backend region.

`use one us-west1 region for v1`

Confirmed: define `us-west1` once per retained environment source and propagate it to the canonical Cloud Run service, Artifact/container registry placement where applicable, VPC/subnet and private Redis, retained Cloud Tasks queues/handler identity, Secret Manager access policy where region-sensitive, provider/runtime location fields, deployment probes, release evidence, domains/URLs, and documentation. Remove Omi's repeated `us-central1` assumptions rather than retaining conflicting aliases. Do not introduce multi-region replication or failover in v1.

Acceptance group: A18.


### IR-859

Cloud Run CPU and memory per instance.

`set each canonical backend instance to 2 vCPU and 4 GiB`

Confirmed: declare, validate, and deploy the same per-instance resource envelope in development and production. Preserve runtime-image smoke tests and relevant memory/concurrency diagnostics; remove executor pools only with their rejected callers rather than changing retained async boundaries merely to fit a smaller container.

Acceptance group: A18.


### IR-860

Cloud Run per-instance request concurrency.

`set per-instance request concurrency to 20`

Confirmed: declare and validate concurrency 20 for development and production. This conservatively adapts Omi's 22-socket target and applies to the combined HTTP/WebSocket service. Keep per-user listen admission, endpoint rate limits, bounded executors/semaphores, and load/connection tests; do not claim this number eliminates the separately retained product quotas.

Acceptance group: A18.


### IR-861

Cloud Run maximum instance counts.

`development maximum three; production maximum ten`

Confirmed: declare, validate, and deploy max instances 3 in development and 10 in production, alongside IR-857's minimums of zero and one. Keep ordinary rate limits, quota/fair-use controls, alerting through retained managed observability, and truthful overload behavior. Do not copy Omi's scheduled 10/30 minimum or 60-pod maximum controls.

Acceptance group: A18.


### IR-862

Cloud Run session affinity.

`leave Cloud Run session affinity disabled`

Confirmed: do not add sticky-session configuration or a server-session synchronization layer. Every healthy instance must accept a reconnect independently. Retain the Mac watchdog/backoff/error lifecycle and stateless backend admission, and test reconnection across distinct process instances rather than only same-instance recovery.

Acceptance group: A18.


### IR-863

Dedicated Cloud Run runtime service identity.

`attach a dedicated least-privilege runtime service account per environment`

Confirmed: create or select one user-managed runtime identity for the development backend and one for production, attach it explicitly in the validated Cloud Run deployment contract, and grant only the permissions required by retained Google API calls. Keep the GitHub WIF deployment identity from IR-843 separate and grant it only the ability required to deploy and attach the runtime account. Do not use the broad default Compute Engine service account or share one runtime principal across development and production.

Acceptance group: A18.


### IR-864

Hosted Firebase and Google API credentials.

`keep Firebase, Firestore, and Storage behavior through Cloud Run ADC; remove the hosted JSON key`

Confirmed: preserve the same retained reads, writes, authentication, storage, and task behavior while removing `SERVICE_ACCOUNT_JSON` from the development and production Cloud Run secret contract and adapting every retained hosted Google client to the attached runtime identity through Application Default Credentials. Remove the hosted JSON-to-`/tmp` materialization path and its exclusive deployment tests/configuration. Keep Firebase Auth and Firestore emulator behavior, and keep an appropriate explicit local-development credential path for workstations that are not running on Google Cloud. Do not remove provider API keys or the GitHub deployment identity.

Acceptance group: A18.


### IR-865

Cloud Run startup and liveness probes.

`reuse /v1/health for explicit Cloud Run startup and liveness probes`

Confirmed: preserve the existing shallow health endpoint and configure explicit HTTP startup and liveness probes for the one canonical development and production service. Startup must prevent premature failure while the Python process initializes; liveness may replace an instance that can no longer answer. Keep candidate transcription, health, authentication, and compatibility acceptance checks as separate deployment gates. Do not turn liveness into a deep Firestore/provider dependency test that restarts healthy processes during an external outage, and do not adopt preview readiness behavior merely to recreate Kubernetes configuration.

Acceptance group: A18.


### IR-866

Cloud Run CPU allocation and billing mode.

`use instance-based billing to keep retained account-deletion recovery running`

Confirmed: explicitly configure and validate instance-based billing for the canonical development and production Cloud Run service. This preserves the five-minute account-deletion recovery behavior without introducing another scheduler. Development may still scale to zero under IR-857; production's one minimum 2-vCPU/4-GiB instance will remain allocated and billed throughout its lifetime. Keep durable Cloud Tasks for the actual account-deletion worker request and keep the in-process loop as recovery/requeue supervision, not as the sole durability boundary. Delete the conversation-finalization and stale hosted-conversation loops under IR-020/394/397 rather than using this billing decision to retain them.

Acceptance group: A18.


### IR-867

Canonical backend image registry.

`store the canonical backend image in regional us-west1 Artifact Registry`

Confirmed: create one narrowly permissioned Docker repository in `us-west1`, publish the retained backend under its `us-west1-docker.pkg.dev` address, and propagate that authoritative repository through build cache, immutable commit tag/digest, candidate deployment, validation evidence, promotion, traffic repair, rollback, and documentation. Preserve exact-image release identity and delete `gcr.io`, Container Registry command, compatibility redirect, and rejected-service image references from the retained deployment path.

Acceptance group: A18.


### IR-868

Retained account-deletion Cloud Tasks OIDC caller identity.

`keep one dedicated account-deletion task caller per environment and remove stale naming`

Confirmed: retain one least-privilege Cloud Tasks OIDC signer in development and one in production for the account-deletion handler. Preserve exact signer-email and audience verification, HTTPS, queue retry/deduplication behavior, and fail-closed configuration. Rename retained variables/helpers/contracts to truthful account-deletion or generic backend-task terminology; remove `SYNC_TASKS_*` ownership and branches that exist only for rejected sync/audio-merge jobs. Delete the conversation-finalization queue, handler, signer/audience configuration, reconciliation loops, and exclusive tests. Do not reuse the Cloud Run runtime identity or GitHub deployment identity as the task signer.

Acceptance group: A18.


### IR-869

Cloud Run secret-version binding.

`pin exact retained secret versions to each deployed revision`

Confirmed: preserve Secret Manager and secret-as-environment-variable consumption, but resolve and deploy explicit enabled version numbers for every retained secret. Record only secret resource/version identity, never secret values, in validated deployment evidence. A rotation must select the new version, deploy a new candidate revision, exercise the relevant health/authentication behavior, and promote or roll back through the existing release path. Delete rejected-product secrets rather than pinning them, and do not silently refresh credentials inside an already-running revision.

Acceptance group: A18.


### IR-870

Cloud Run startup CPU boost.

`keep startup CPU boost disabled`

Confirmed: explicitly declare and validate no startup CPU boost for development and production, retaining the ordinary 2-vCPU allocation from IR-859. Do not add paid temporary capacity as an unmeasured optimization. Candidate/startup evidence should continue exposing real initialization failures; a future change requires measured cold-start or scale-out evidence and remains a separate capacity decision.

Acceptance group: A18.


### IR-871

Stable v1 backend public addresses.

`use stable development and production Cloud Run service URLs for v1`

Confirmed: preserve the environment separation and production-family pinning behavior, but replace every retained `api.omi.me`, `api.omiapi.com`, and rejected desktop-backend address with the exact stable `run.app` URL of our development or production canonical service as appropriate. Use those same environment URLs for retained OAuth callbacks, Dodo webhooks, desktop release/update endpoints, Cloud Tasks audiences, probes, generated API metadata, and tests. Do not add a custom-domain load balancer, preview domain mapping, CDN, or redirect layer for v1. A future branded hostname is a separate migration and must either update shipped clients or preserve compatibility with the original service URL.

Acceptance group: A18.


### IR-872

Cloud Run execution environment.

`explicitly use the second-generation Cloud Run execution environment`

Confirmed: declare, validate, deploy, and record second generation for the development and production service. Keep the same 2-vCPU/4-GiB allocation, WebSocket protocol, container image, and Direct VPC route. Accept potentially slower scale-from-zero startup in development; production retains its warm minimum. Do not allow an inherited provider choice to change this runtime boundary between revisions.

Acceptance group: A18.


### IR-873

Cloud Run startup and liveness timing.

`adapt startup to 240 seconds and keep the existing liveness tolerance`

Confirmed: configure the HTTP startup probe on `/v1/health` with a ten-second period, five-second timeout, and 24-failure threshold. Configure liveness on the same shallow endpoint with a ten-second period, five-second timeout, and five-failure threshold. Let successful startup enable liveness. Keep deeper release/candidate tests separate and fail the candidate rather than continually expanding startup time when initialization is broken.

Acceptance group: A18.


### IR-874

Cloud Run graceful shutdown window.

`bound application cleanup to about eight seconds inside Cloud Run's shutdown window`

Confirmed: retain Uvicorn/FastAPI SIGTERM handling, stop accepting new application work, cancel or drain tracked background tasks for at most about eight seconds, close shared HTTP/database clients, flush ordinary logs where supported, and exit before Cloud Run's forced kill. Preserve durable task retry and Mac WebSocket reconnection. Delete Kubernetes-only `terminationGracePeriodSeconds`, `preStop`, and rollout assumptions from the retained service rather than copying them into ineffective configuration.

Acceptance group: A18.


### IR-875

Redis hosting and environment availability.

`use separate us-west1 Memorystore instances: Basic development and Standard production`

Confirmed: provision one 1-GiB Basic-tier Memorystore for Redis instance for development and one separate 1-GiB Standard-tier highly available instance for production, both in `us-west1` and reachable only through their environment's retained private VPC path. Do not share keys, hosts, passwords, databases, or network access between environments. Keep Redis strictly ephemeral: no authoritative conversations, tasks, goals, Rewind data, or synchronization state. Do not add read replicas, Redis Cluster, or capacity beyond the selected minimum without measured need.

Acceptance group: A18.


### IR-876

Redis authentication and transport encryption.

`keep private Redis and enable AUTH plus verified TLS`

Confirmed: enable Memorystore AUTH and in-transit encryption when creating both environment instances; store each generated AUTH value in its own Secret Manager secret/version; supply the environment-specific CA through a non-secret validated runtime file/configuration; and adapt the shared Python Redis client to require TLS, verify the server certificate, authenticate, retain pooling/health checks, and fail according to each existing caller's explicit policy. Do not add a public Redis endpoint, disable certificate verification, or silently fall back to plaintext.

Acceptance group: A18.


### IR-877

Retained account-deletion Cloud Tasks queue shape.

`provision one explicitly bounded account-deletion queue per environment`

Confirmed: create and update an `account-deletion` queue in each environment's `us-west1` project/location with maximum concurrent dispatches 1, maximum attempts 5, and a 1,500-second/25-minute task dispatch deadline matched by the handler timeout. Bind the exact stable environment handler URL and OIDC signer/audience from IR-868, validate live queue shape during deployment, and keep deterministic opaque task names, retry-count interpretation, Firestore claims, and lock fencing. Delete sync, audio-merge, and conversation-finalization queues rather than adapting their capacity.

Acceptance group: A18.


### IR-878

Exhausted account-deletion recovery.

`keep Firestore failure state and the five-minute reconciler; do not add a dead-letter queue`

Confirmed: preserve terminal-attempt marking, sanitized Sentry/PostHog diagnostics, owner-safe Firestore state, transactional claim fencing, and periodic re-enqueue. Do not add another queue, service, scheduler, or payload copy. A repeatedly failing wipe remains visible and retryable through its durable state until the underlying provider/configuration problem is fixed; it must never be silently acknowledged as successful.

Acceptance group: A18.


### IR-879

Built-in logging for the canonical backend.

`keep Cloud Run's built-in Cloud Logging and the existing privacy-sanitized Python logging path`

Confirmed: preserve retained application logs to standard output/error, Cloud Run request and system logs, severity and useful correlation metadata already shared by surviving code, and the existing rules against raw sensitive payloads. Remove logs, labels, filters, sinks, dashboards, and configuration owned exclusively by rejected services. Do not deploy a logging agent, Loki replacement, custom collector, cross-cloud export pipeline, or another hosted logging product for v1.

This decision does not merge Cloud Logging with Sentry, PostHog, or Langfuse and does not authorize transcript, audio, prompt, secret, token, or other raw sensitive content in logs. Log-retention duration and exclusions are separate operational configuration details rather than silently expanded here.

Acceptance group: A18.


### IR-880

Minimal managed production outage alerts.

`delete rejected-service alerts and keep only production health-unreachable and Cloud Run 5xx alerts for v1`

Confirmed: remove sync-backfill allowance metrics/policies and every dashboard, policy, notification route, label, test, and configuration exclusive to deleted services. For the canonical production service, keep one managed external availability policy against the retained `/v1/health` route and one managed Cloud Run server-error-rate policy covering HTTP 5xx responses. Route both through our production notification channel and keep their configuration reproducible and validated.

Do not port Omi's GKE dashboards or add separate Redis, Cloud Tasks, per-route, latency, capacity, business-event, or development paging policies for v1. Retained Sentry diagnostics provide exception detail, while IR-878's durable state/reconciler protects account-deletion correctness. Exact warning thresholds and notification recipients may be environment configuration; they must not require another monitoring service.

Acceptance group: A18.


### IR-881

Google Cloud billing warnings.

`create monthly alerts-only budgets for development and production; do not enforce a hard cap`

Confirmed: delete the sync-backfill allowance metrics and policies. Create one monthly alerts-only billing budget scoped to the development Google project and one scoped to production, using an environment-configured monetary amount and warning notifications at 50%, 80%, and 100%. Notify the owned billing/operator recipients through Google Cloud's supported budget channel and keep project identity and budget presence verifiable.

Do not use a billing-disable function, Pub/Sub shutdown automation, preview enforced spend cap, or another action that automatically pauses production resources. A budget warning is cost visibility, not customer entitlement, Dodo billing, provider quota, or application fair-use enforcement; those retained boundaries remain unchanged.

Acceptance group: A18.


### IR-882

Cloud Run revision retention.

`keep zero-traffic revisions for rollback and do not add a custom revision-deletion job`

Confirmed: preserve previous production and development revisions, immutable revision identity, traffic restoration, release evidence, and the current removal of temporary candidate tags. Attach IR-857's production minimum instance at service level rather than separately to old revisions so inactive revisions have no warm-instance allocation. Rely on Cloud Run's platform retention limit instead of scheduling revision deletion.

Do not preserve traffic, permanent candidate tags, or revision-level minimum instances on obsolete revisions. Artifact Registry image and build-cache cleanup is a separate storage-retention requirement and is not decided by keeping Cloud Run revisions.

Acceptance group: A18.


### IR-883

Immutable backend image identity.

`record the full source commit and deploy the accepted immutable image digest`

Confirmed: publish the canonical backend with a tag derived from the full admitted Git commit; capture and validate the resulting `sha256` image digest; smoke-test, deploy, candidate-check, promote, record, and recover using that exact digest; and carry both the full source commit and image digest in release evidence. Keep a short hash plus run/attempt only where Cloud Run's revision-name length and human readability require it.

Do not use the seven-character tag as authoritative image identity, re-resolve a tag between acceptance and promotion, or rebuild the same source independently for a later release step. IR-854's deletion of `latest` and IR-867's regional Artifact Registry remain unchanged.

Acceptance group: A18.


### IR-884

Artifact Registry BuildKit cache.

`keep one environment-owned backend registry build cache`

Confirmed: retain registry `cache-from` and `cache-to` for the canonical backend in development and production, scoped to each environment's regional Artifact Registry and deploy identity. Preserve cache misses as safe full rebuilds, and never make cache availability a runtime dependency or release-identity authority. Delete caches belonging to rejected images/services rather than copying them into the canonical repository.

Do not store secrets or customer data in build layers, share a writable production cache with an unrelated project, or restore the mutable `latest` release alias. Cache retention is bounded separately by IR-885.

Acceptance group: A18.


### IR-885

Artifact Registry cleanup policy.

`delete only untagged versions older than 30 days and keep exact release images`

Confirmed: define an environment-owned Artifact Registry cleanup policy that matches only untagged backend image/cache versions older than 30 days. Apply it in dry-run mode first, inspect the matched inventory, and enable periodic deletion only after proving that no full-commit-tagged release image matches. Keep every exact commit-tagged backend release image automatically in v1.

Do not add a custom cleanup service or scheduled script, delete by broad package age regardless of tag state, remove a release tag to make its image eligible, or clean images from rejected repositories instead of deleting those repositories outright. Cloud Run revision retention remains governed by IR-882.

Acceptance group: A18.


### IR-886

Cloud Logging retention.

`keep the default 30-day backend-log retention with no external archive`

Confirmed: retain the development and production projects' ordinary 30-day `_Default` log retention and query recent backend evidence in Cloud Logging. Do not add a custom long-retention bucket, GCS/BigQuery export, cross-cloud sink, or third-party log archive for v1. Remove sinks or buckets exclusive to Omi's deleted Loki/GKE stack.

The privacy boundary remains stronger than the retention period: raw audio, transcripts, screenshots, prompts, files, authorization tokens, secrets, payment payloads, and other sensitive customer content must not be logged merely because entries expire after 30 days. Sentry, PostHog, and Langfuse keep their separately accepted scopes and are not log archives.

Acceptance group: A18.


### IR-887

Managed Modulate Velma-2 cloud STT.

`KEEP AS IS - retain Modulate in its current managed primary/overflow role`

Confirmed: keep Modulate Velma-2 exactly in its current server-provider role: first choice for live `/v4/listen` and completed-turn PTT fallback, and overflow choice for prerecorded transcription. Re-own the provider account, `MODULATE_API_KEY`, billing, usage metering, operational configuration, and truthful privacy disclosure under this product rather than Omi.

Preserve the current provider policy, supported-language routing, transient audio processing, generic provider diarization, connection/error handling, and existing failover relationship while IR-888 decides the hosted Parakeet half separately. Do not make Modulate the authority for local conversations, store its transcript in a provider-owned product database, expose customer BYOK, or change Mac-local Parakeet merely because this managed cloud path is retained.

Acceptance group: A18.


### IR-888

Hosted GPU Parakeet cloud STT service.

`DELETE - remove the complete hosted GPU Parakeet service while preserving Mac-local Parakeet`

Confirmed: delete the separately deployed Python Parakeet HTTP/WebSocket service; its batch and streaming models; GPU worker, model downloads, VAD and diarization service code; stream-capacity admission and allocation policy; Helm chart, GPU image, deployment workflow, health/metrics/alerting, secrets, runtime manifests and service-specific tests; and the canonical backend's remote-Parakeet client, provider order, `HOSTED_PARAKEET_API_URL`, capacity fallback and other code left exclusive to that service.

Keep the Parakeet engine embedded in the Mac app exactly as the retained private local transcription path. Managed Modulate remains the cloud `/v4/listen`, PTT fallback and prerecorded provider under IR-887, including generic within-conversation speaker labels where the retained cloud path supports them. Do not replace the deleted hosted service with another self-operated GPU engine or delete local Parakeet merely because both use the Parakeet name.

Acceptance group: A18.


### IR-889

Managed and self-hosted Deepgram cloud STT branches.

`DELETE - remove both managed and self-hosted Deepgram branches completely`

Confirmed: delete public Deepgram API client and compatibility code; Deepgram SDK dependencies, model aliases, provider-selection tokens, BYOK/key lookup residue, `DEEPGRAM_API_KEY` and managed-endpoint configuration; self-hosted-only WebSocket routing and `DEEPGRAM_SELF_HOSTED_*` configuration; the complete `deepgram-self-hosted` GKE chart, model/API credentials, deployment and monitoring surfaces; and Deepgram-specific tests, fixtures, diagnostics and documentation.

This changes no ordinary serving route because the authoritative defaults did not select Deepgram. Preserve managed Modulate under IR-887, Mac-local Parakeet under IR-019, provider-neutral speech boundaries still used by the retained path, and generic within-conversation speaker labels. Do not retain an inactive emergency chart or compatibility alias and do not replace Deepgram with a third cloud provider in v1.

Acceptance group: A18.


### IR-890

Firestore composite-index control plane.

`ADAPT - keep the create-only reconciliation pattern for surviving queries only`

Confirmed: retain the repository-owned query/index registry, generated manifest, backend deploy's read-only readiness check, human-selected environment, explicit `APPLY_FIRESTORE_INDEXES` confirmation, dry-run plan, create-only application and wait-for-readiness behavior. Authenticate the manual writer through the environment's WIF identity selected under IR-843 rather than an inherited permanent JSON credential.

Prune every registry entry, query specification, manifest index, test and document that exists only for rejected cloud conversations, memories, screen activity, candidates, Tasks, synchronization or other deleted collections. Retain or add an index only when a surviving account, entitlement, fair-use, account-deletion, release-channel or other accepted Firestore query proves it is required. Do not keep the old registry unchanged, let ordinary backend deployment mutate serving schema, or wait for a production missing-index error as the discovery mechanism.

Acceptance group: A18.


### IR-891

Local and offline backend development harness.

`ADAPT - keep the isolated local/offline harness and prune it to the retained stack`

Confirmed: retain the safe local lifecycle commands, run-isolated state, Firebase Auth and Firestore emulators, local Redis, canonical Python backend, required local desktop backend/profile, synthetic users, provider-offline mode, hermetic retained-provider fakes, optional real-provider mode, health/status/log commands, and reset safeguards that refuse shared or production targets.

Delete Typesense and its Docker/native runtime; cloud-memory and synchronization scenarios; deleted service processes; hosted Parakeet and Deepgram fakes/configuration; rejected provider adapters; stale Omi identities and sample data; and tests, fixtures, ports, reports and documentation exclusive to those branches. Adapt surviving scenarios to the Mac-local authority and retained backend instead of preserving cloud product-data behavior. Do not require ordinary development or coding-agent verification to touch shared cloud accounts, production data, or paid providers.

Acceptance group: A18.


### IR-892

Owned Mac build, signing, notarization, and publication lane.

`ADAPT - recreate and re-own the Codemagic build, signing, notarization and publication pattern`

Confirmed: add a complete auditable root `codemagic.yaml` for this product and retain the current immutable candidate-tag intake shape plus IR-895's separately signed preview workflow. The owned release workflow must build the exact source, use our bundle/application identity, Developer ID certificate, hardened runtime and entitlements, submit and staple Apple notarization, sign the Sparkle archive with our EdDSA key, publish the exact ZIP/DMG and metadata to our artifact destination, and provide the evidence expected by downstream qualification. The preview workflow must preserve its separate branch-derived identity and artifact contract.

Replace the absent Omi workflow, Codemagic app/workflow IDs, Apple team and signing material, Sparkle key, domains, buckets and credentials with ours. Preserve fail-closed exact-tag/source binding and do not introduce a manual local release artifact as a second authority or redesign the trusted build onto GitHub merely because the inherited definition was omitted from this checkout.

Acceptance group: A19.


### IR-893

Mac candidate publication and dedicated M1 qualification.

`ADAPT - keep deliberate candidate publication and dedicated M1 qualification under our identities`

Confirmed: retain manual `workflow_dispatch` candidate planning, immutable version/tag binding, one-candidate serialization, provider-intake verification, dedicated trusted Apple-Silicon qualification, runner-capacity and hygiene enforcement, exact-candidate rebuild/tests, immutable evidence, live-backend compatibility validation, Beta admission gate, recovery/retry behavior, and manual-only Stable promotion.

Replace Omi Bot, GitHub App, runner labels, cache/lease names, protected environments, secrets, artifact names and qualification identities with ours. Correct the component guide to describe the actual manual candidate trigger rather than the deleted automatic push/schedule behavior. Do not restore a candidate for every accepted merge or treat ordinary compile/CI evidence as a substitute for the retained real-machine qualification gate.

Acceptance group: A19.


### IR-894

Server-owned release manifests and Beta/Stable channel control.

`ADAPT - retain the complete Beta/Stable release authority in our canonical backend`

Confirmed: retain immutable signed release manifests, exact-candidate reservation and admission, qualification evidence binding, Beta pointer advancement, promotion of the same accepted build to Stable, Sparkle appcast and download resolution, live-backend compatibility checks, Beta pause/recovery, qualified rollback, audited emergency rollout, idempotent retries and conflict-safe Firestore transactions.

Move the operational collections, keys, service URLs, artifact domains and authorized deployment identities to our Firebase/Google Cloud projects and product namespace. Preserve IR-895's preview manifests and pointers as a separately namespaced preview product rather than merging them into Beta/Stable state. Remove Omi-specific identities and duplicate backend ownership; leave Windows untouched under IR-009. Do not infer release channels only from GitHub release labels, replace the state machine with hand-edited static appcasts, or mix customer conversations and other rejected personal product data into this operational release ledger.

Acceptance group: A19.


### IR-895

Signed branch-preview publication.

`ADAPT - retain the complete signed branch-preview pattern under our ownership`

Confirmed: retain manual publication from a canonical `preview/<slug>` branch; immutable full-commit resolution; protected-environment approval; branch-derived preview identity that can coexist with the ordinary app; a separately signed and notarized Codemagic preview DMG; production-compatible versus explicit preview-backend configuration; immutable per-commit manifests; one compare-and-set mutable pointer per slug; public current and immutable landing pages; tester notes; authorized replacement and delisting; and preview artifacts in the retained Mac update bucket.

Replace `BasedHardware/omi`, Omi Codemagic app/workflow IDs, `com.omi.preview.*`, URL schemes, Omi API URLs, bucket/path names, public domains, Firestore collection namespace, secrets and authorization identities with ours. Preserve preview state separately from Beta/Stable release authority and do not make a preview eligible for Stable promotion merely because it is signed. Do not reduce this to unsigned CI artifacts or delete it in favor of Beta.

Acceptance group: A19.


### IR-896

Public website and legal-document hosting boundary.

`ADAPT - use one small externally hosted product and legal site, with exact release notes on GitHub`

Confirmed: keep the Mac's visible **Visit Website**, Terms and real Privacy Policy destinations, but point them to pages we own on one small externally hosted static site. The Privacy Policy must truthfully describe the final retained architecture and processors, including local product-data authority plus Firebase account state, Dodo billing, PostHog, Sentry, Langfuse, managed AI and Modulate where applicable. Keep exact version release notes on our GitHub Releases pages and point the retained release-note behavior there.

Do not restore the absent Omi `web/` monorepo, admin/personas applications, public-build deployment system or another application backend merely to host these pages. Do not leave Omi URLs or absolute privacy claims in the Mac, remove the retained public links, or treat the in-app local data/settings page as the legal Privacy Policy.

Acceptance group: A19.


### IR-897

Orphaned workflows, manifests, and checks for absent source trees.

`DELETE - remove every control surface exclusive to a source tree absent from this checkout`

Confirmed: delete mobile, absent-web, firmware, SDK/CLI, plugin, MCP and docs-application workflows whose required trees are missing; runtime-image and public-build manifest entries for missing Dockerfiles/canaries; preflight commands and triggers that can only address those absent components; exclusive scripts, fixtures, settings, secrets, documentation claims and release checks; and cross-component contracts that cannot be satisfied by any present source.

Preserve and repair every control required by the present Mac and canonical Python backend, including the adapted local harness, backend deployment, Mac tests, IR-892's newly supplied `codemagic.yaml`, release build/qualification/promotion, IR-895 previews and surviving repository guardrails. Do not restore missing product trees merely to satisfy zombie automation. Do not inspect, edit, remove or make a decision about the present Windows tree or any Windows-only workflow under this cleanup; IR-009 keeps it completely outside this macOS audit.

Acceptance group: A19.


### IR-898

Three-way System Audio capture mode.

`KEEP AS IS - retain Always, Only during meetings, and Never/Mic only with meeting-only as the default`

Confirmed: preserve all three labels, values, local `UserDefaults` persistence, default, Settings picker, live reconciliation notification, Home/header status wording, meeting-detector ownership, whole-capture meeting gate, meeting-end local finalization, continuous microphone behavior in Always and Never, system-audio suppression in Never, and the current shortcut/onboarding relationship. **Never** must continue to mean continuous microphone-only transcription while Listening is enabled, not disabling all recording.

Do not collapse the picker to the two onboarding choices, remove Mic only, make the header shortcut cycle into Mic only, capture application audio in Never, or reinterpret this local privacy control as a cloud synchronization setting. Existing hidden development overrides and actual System Audio permission/setup remain governed by their previously recorded requirements.

Acceptance group: A20.


### IR-899

Rewind selected-date and active-search load failures.

`keep later Rewind date and search failure behavior exactly as implemented`

Confirmed: preserve immediate selected-date/query changes, retention of the prior screenshot projection after a failed date or primary text-search query, diagnostic-only failure reporting, loading/searching completion, and absence of a customer-visible error or Retry action exactly as they are. Do not revert the visible date/query, clear the old projection, distinguish stale results, add failure copy, or add a retry control.

This decision does not change the initial loading-error screen under IR-699 or the semantic-search fail-open behavior under IR-686.

Acceptance group: A20.


### IR-900

Rewind successful zero-results search presentation.

`keep the current Rewind zero-results search presentation exactly as implemented`

Confirmed: preserve the icon, **Searching...**, **No results found**, **Try a different search term**, layout, styling, absence of an inline action, persistent top search/date controls, and query-field clearing behavior exactly as they are. Do not merge this state with **No Screenshots Yet**, add suggestions or a Clear button inside the content area, or redesign it.

Acceptance group: A20.


### IR-901

Rewind database-recovery banner and index rebuild.

`keep the current Rewind database-recovery banner and Rebuild Index workflow exactly as implemented`

Confirmed: preserve banner priority and placement, icon, title, recovered-count and zero-record copy, the rule that **Rebuild Index** appears only after zero-row recovery, local video-backed reconstruction, disabled in-flight action, success reload/dismissal, X dismissal, styling, and retained data exactly as they are. Do not offer rebuilding after partial salvage, automatically start a rebuild, delete surviving video, or redesign this workflow.

Visible rebuild progress and failure feedback remain a separate child.

Acceptance group: A20.


### IR-902

Rewind index-rebuild progress and failure feedback.

`keep Rewind index-rebuild feedback exactly as implemented`

Confirmed: preserve internal progress tracking without visible progress, the unchanged disabled **Rebuild Index** label during work, absence of cancellation, diagnostic-only failure reporting, persistent banner, and re-enabled same-button retry opportunity exactly as they are. Do not add a spinner, percentage, progress wording, failure message, or separate Retry action.

Acceptance group: A20.


### IR-903

Rewind shared Capture toggle and health presentation.

`keep the current Rewind shared Capture control exactly as implemented`

Confirmed: preserve the same shared-runtime ownership, colors, knob, health badge/copy, tooltip, transition spinner, permission handoff, saved setting updates, start/stop behavior, failed-start rollback, notification reconciliation, timing, styling, and analytics exactly as they are. Do not create a Rewind-only recorder or preference, split assistants from this switch, change health meanings, or redesign the control.

Acceptance group: A20.


### IR-904

Rewind Settings gear navigation.

`keep the Rewind Settings gear and direct route exactly as implemented`

Confirmed: preserve the gear icon, placement, help text, notification request, main-window Settings navigation, direct `.rewind` section selection, and reuse of the retained canonical Settings surface exactly as they are. Do not duplicate settings inside Rewind, open another window, remove the shortcut, or redirect it elsewhere.

Acceptance group: A20.


### IR-905

Rewind advertised and actual global shortcut mismatch.

`keep the Rewind global-shortcut mismatch exactly as implemented`

Confirmed: preserve the visible Command-Option-R badge and help, walkthrough claim, IR-681 wording, actual Control-Option-R key monitor, comments, logs, and resulting mismatch exactly as they are. Do not change the listener to Command-Option-R, change the displayed/help shortcut to Control-Option-R, or otherwise reconcile these surfaces during the first-release adaptation.

This does not reverse IR-681's separate deletion of the obsolete numbered Command-5 Rewind command.

Acceptance group: A20.


### IR-906

Rewind full-page behavior and stale overlay descriptions.

`keep the Rewind page behavior and stale overlay descriptions exactly as they are`

Confirmed: preserve Rewind as an ordinary full-page selected destination, Escape-to-Home, normal navigation away, absence of outside-click dismissal, and the conflicting overlay/previous-page descriptions in the walkthroughs and IR-683 exactly as they stand. Do not redesign Rewind into a real overlay and do not correct, rename, or reconcile the stale requirements/E2E wording during the first-release adaptation.

Acceptance group: A20.


### IR-907

Rewind local-development automation navigation.

`keep Rewind local-development automation navigation exactly as implemented`

Confirmed: preserve the developer-only `navigate rewind` target, its authenticated local automation route, ordinary sidebar-destination selection, and reuse of the real Rewind page exactly as they are. Do not remove the testing route, create a parallel Rewind screen, or expose this command as a customer feature.

Acceptance group: A20.


### IR-908

Rewind quiet refresh of today's timeline.

`keep the quiet refresh of today's Rewind timeline exactly as implemented`

Confirmed: preserve the three-second interval, today-only and search/loading skip conditions, silent fetch, active-chunk exclusion, ID-change comparison, absence of loading feedback, retained visible data on failure, and diagnostic-only failure report exactly as they are. Do not add a manual-refresh requirement, visible background-loading state, or customer-facing refresh error. Leave the separately owned transcript/notes condition untouched for its parallel workflow.

Acceptance group: A20.


### IR-909

Rewind selected-day midnight boundary.

`keep the inclusive next-midnight boundary exactly as implemented`

Confirmed: preserve the greater-than-or-equal start and less-than-or-equal following-midnight comparisons, including the possibility that an exact-midnight screenshot appears in both adjacent selected days. Do not change the end comparison to an exclusive boundary or otherwise normalize the daily range during the first-release adaptation.

Acceptance group: A20.


### IR-910

Rewind position after newly captured screenshots arrive.

`keep Rewind's current-position preservation exactly as implemented`

Confirmed: preserve initial selection of the newest frame, continued display of the same identified screenshot when later captures arrive, absence of automatic live-edge following, manual navigation to newer captures, and fallback to the newest available frame when the previous frame disappears exactly as they are.

Acceptance group: A20.


### IR-911

Rewind statistics state with no reachable presentation.

`keep the undisplayed Rewind statistics wiring exactly as implemented`

Confirmed: preserve the published statistics state, initial asynchronous calculation, throttled new-frame listener, repeated database and storage-size calculations, unused public refresh helper, and absence of a visible statistics presentation exactly as they are. Do not remove this wiring or add a new statistics UI during the first-release adaptation.

Acceptance group: A20.


### IR-912

Rewind continuous evenly spaced timeline presentation.

`keep the continuous evenly spaced Rewind timeline exactly as implemented`

Confirmed: preserve index-based full-width spacing, hidden elapsed-time gaps, per-app colored blocks, launch-variable app colors, actual app/time hover details, and all dormant gap-rendering machinery exactly as they are. Do not introduce time-proportional placement, stabilize colors, expose gaps, or remove the unused gap path.

Acceptance group: A20.


### IR-913

Rewind search-group timeline direction and match legend.

`keep the search-group timeline direction and match presentation exactly as implemented`

Confirmed: preserve the opposite temporal direction between ordinary and selected-search timelines, the shared controls, the visible yellow **match** legend, absence of yellow timeline markers, and retained marker-rendering code exactly as they are. Do not normalize ordering or reconcile the legend with the bar.

Acceptance group: A20.


### IR-914

Rewind search-result keyboard activation and thumbnail failure.

`keep Rewind search-result activation and thumbnail failure exactly as implemented`

Confirmed: preserve Up/Down highlighting, pointer-only row activation, absence of Enter activation, one-shot thumbnail loading, indefinite spinner placeholder after failure, silent failure, and absence of Retry exactly as they are.

Acceptance group: A20.


### IR-915

Rewind in-flight projection and rapid-date request ordering.

`keep Rewind in-flight projections and date-request ordering exactly as implemented`

Confirmed: preserve old screenshots during replacement search/date work, immediate visible query/date changes, lack of date-load cancellation or latest-request protection, and possible older-request overwrite exactly as they are. Do not add a blocking loading projection, request generation, cancellation, or result-date validation.

Acceptance group: A20.


### IR-916

Rewind whitespace-only search state.

`keep whitespace-only Rewind search behavior exactly as implemented`

Confirmed: preserve trimmed-empty search execution, raw nonempty search-mode detection, their disagreement, resulting controls or no-results state, and clearing through the existing X action exactly as they are. Do not normalize the UI check to the trimmed query.

Acceptance group: A20.


### IR-917

Rewind active video-chunk search visibility and first-frame failure.

`keep active-chunk search visibility and first-frame fallback exactly as implemented`

Confirmed: preserve ordinary-timeline active-chunk exclusion, search visibility of those same rows, possible unreadable result selection, diagnostic behavior, and the initial **No frame** fallback exactly as they are. Do not filter active chunks from search or introduce a still-saving state.

Acceptance group: A20.


### IR-918

Rewind unrestricted graphical date picker.

`keep the unrestricted Rewind date picker exactly as implemented`

Confirmed: preserve unlimited past and future selection, same-day no-op behavior, absence of previous/next controls, future-date querying, and reuse of the existing empty state exactly as they are. Do not cap the picker at today or add navigation controls.

Acceptance group: A20.


### IR-919

Rewind application-wide scroll-wheel monitoring.

`keep Rewind scroll-wheel monitoring exactly as implemented`

Confirmed: preserve the application-local monitor, combined horizontal/vertical delta, results-list guard, lack of pointer or window scoping, simultaneous event pass-through, and possible timeline movement from scrolling elsewhere in Omi exactly as they are.

Acceptance group: A20.


### IR-920

Additional dormant Rewind components, helpers, and state.

`keep the additional dormant Rewind code exactly as implemented`

Confirmed: preserve every listed unreachable component, model, helper, parameter, and state value exactly as it stands, without exposing, deleting, consolidating, documenting, or testing it. Preserve the active analytics call and all visible Rewind behavior unchanged.

Acceptance group: A20.


### IR-921

Rewind developer visual-export registrations.

`keep Rewind developer visual exports exactly as implemented`

Confirmed: preserve both export names, indices, sizes and surrounding exporter behavior, direct construction of the real Rewind page, and developer-only availability exactly as they are. Do not remove the registrations or expose the exporter as a customer feature.

Acceptance group: A20.


### IR-922

Production Local Agent HTTP API for other programs on the same Mac.

`delete external Local Agent HTTP access while preserving the managed Pi tool path`

Confirmed: remove `LocalAgentAPIServer`, `LocalAgentAPISettings`, the production `127.0.0.1:47778` listener, `/health`, `/v1/local/tools`, `/v1/local/tool`, persisted enablement and port state, scoped Keychain bearer-token lifecycle, app-launch startup, Memory Export connection setup/testing coupling, generated `local-agent-api` adapter projection, API-only wrappers, and tests/fixtures that exist only for this external HTTP surface.

Do not delete or replace the managed Pi harness, retained local Node runtime, packaged Pi extension, `OMI_BRIDGE_PIPE`, `AgentRuntimeProcess` authorization/relay path, `ChatToolExecutor`, or any tool capability retained by Pi merely because the deleted API also exposed or executed it. Delete the separate callerless `omi-tools-stdio` process under IR-015/S-05 without routing Pi through it. Do not convert the API-only wrappers into new Pi tools as part of this deletion. Keep shared loopback HTTP parsing needed by the separately retained test-only `DesktopAutomationBridge` on port 47777, relocating or renaming it if necessary rather than deleting that test safety boundary.

Acceptance group: A21.


### IR-923

Managed Pi background agents and visible Agent Pill lifecycle.

`keep the complete local managed-Pi background-agent and Agent Pill lifecycle`

Confirmed: preserve managed-Pi spawn and bounded batch spawn, canonical local session/run ownership, visible Agent Pills and all current statuses, progress and conversation projection, artifacts, Stop/cancellation, same-session follow-ups and their active-run interruption/queueing behavior, restart/runtime restoration, reconciliation, owner fencing, local terminal-journal materialization, manual dismissal, viewed-finished ten-minute expiry, and soft eight-pill trimming exactly as the retained architecture provides.

Delete provider-specific residue through IR-800 and the cosmetic title model call through IR-603. Do not restore cloud Agent VMs, remote workstreams, backend run authority, or alternate agent harnesses. Do not replace the retained Pill lifecycle with a new background-work system for v1.

Acceptance group: A21.


### IR-924

Delivery of completed background-agent results into a live voice session.

`keep bounded managed-Pi completion context in live voice and remove the rejected workstream trigger`

Confirmed: preserve terminal-transition observation for retained background surfaces, canonical local completion-delta reads, the previous-hour window, five-run bound, untrusted-context marking, no immediate synthetic response, delivery only into a live session, retry on provider readiness, and exactly-once checkpoint advancement only after successful injection. Keep the behavior compatible with the retained Gemini Live session.

Remove `workstream` from the trigger set and delete any coupling that exists only for the rejected workstream product. Keep `service` only for genuinely retained local managed-Pi service runs. Do not add another model call, cloud completion store, immediate spoken interruption, or second completion authority.

Acceptance group: A21.


### IR-925

Notch task-save receipts and conversation-end follow-up cards.

`keep both Notch Moments and adapt their save proof and actions to local task authority`

Confirmed: preserve the transcription-only live receipt, unseen-ID detection, two-minute freshness bound, one in-flight verification per task, suppression when durable confirmation fails, silent presentation, most-recent receipt tracking, Undo, Review, conversation-start baseline, creation-time floor, positive-only singular/plural follow-up card, and Tasks navigation.

Replace `APIClient.getActionItem` with a read-back from the canonical local task store after its durable transaction. Make Undo an authoritative local deletion through the retained Tasks boundary. Remove backend/cross-device identity and synchronization assumptions without weakening the requirement that **Saved** is shown only after a durable authoritative read confirms the same active task. Keep card-to-live-voice delivery separate under its own requirement.

Acceptance group: A21.


### IR-926

Injection of displayed notch-notification context into live voice.

`keep the bridge, deliver the complete visible card, and add account-owner fencing`

Confirmed: preserve available provenance, untrusted-reference framing, no synthetic response, no second classifier, newest-only pending replacement, retry on connect/input-window readiness, process-local fifty-ID delivered history, and nondurable state. Continue using the existing live-session context seam for both retained realtime providers.

Change the handoff to include the exact visible notification title and message together, so title-only task receipts and the complete singular/plural follow-up card reach voice as reference context. Add the current owner identity to pending delivery state and clear or reject that state when authorization changes, so one account's card cannot enter another account's later session. Do not add a persistent queue, another model call, automatic spoken announcement, or cloud storage.

Acceptance group: A21.


### IR-927

Server-controlled desktop update warning and required-update blocker.

`keep the complete update-policy behavior and adapt its ownership to our infrastructure`

Confirmed: preserve the separate Sparkle and update-policy roles, public policy read, current-policy document pattern, inactive default, platform and maximum-build targeting, `none`/`banner`/`required` severities, server/fallback copy behavior, dismissible banner and policy-ID persistence, non-dismissible required overlay, download validation and stable fallback, launch/activation refresh, five-minute minimum interval, and fail-open clearing on Mac or backend failure.

Move the Firestore document, backend endpoint ownership, stable/manual download destination, product wording, tests, operator controls, credentials, and deployment documentation onto the retained product-owned release infrastructure established by IR-010 and IR-894. Do not create a second policy system or merge the emergency control into Sparkle.

Acceptance group: A21.


### IR-928

Automatic RAM-pressure remediation and extreme-memory app relaunch.

`keep automatic RAM remediation and extreme-memory relaunch while removing the rejected AgentSync step`

Confirmed: preserve launch/termination monitoring, thirty-second sampling, twenty-sample trend window, 500/800/3,000 MB thresholds, 450/720 MB hysteresis, warning/report/remediation cooldowns, growth diagnostics, component diagnostics, assistant pending-work clearing, persisted-transcript trimming, Rewind chunk flush, Focus pending-work clearing, before/after logging, bounded Sentry behavior, production-only one-shot extreme response, three-second reporting flush, relaunch of the exact bundle, termination only after successful relaunch start, and retry eligibility after relaunch failure.

Remove only the `AgentSyncService` pause, delayed resume, and related diagnostics/tests because the synchronized cloud Agent VM product is rejected. Do not add a replacement synchronization service, user confirmation prompt, different thresholds, or another restart mechanism during the first-release adaptation.

Acceptance group: A21.


### IR-929

Runtime self-install from a DMG or App Translocation into `/Applications`.

`keep and rebrand the guarded runtime self-install behavior`

Confirmed: preserve detection limited to mounted-volume and translocated paths, the harness escape hatch, `/Applications` destination, numeric no-downgrade comparison, launch of an installed same/newer build, copy-to-staging before atomic replacement, preservation of an existing install on failure, post-first-open quarantine clearing, delayed relaunch, termination only after relaunch scheduling succeeds, two-attempt loop guard, manual-install fallback, and fail-open running-in-place behavior.

Adapt the app names, user-facing guidance, logs where product identity appears, bundle filename expectations, skip-environment-variable identity, and focused tests to our product. Keep this runtime gate separate from IR-892's artifact construction/signing/notarization/publication responsibilities and do not introduce another installer framework.

Acceptance group: A21.


### IR-930

Advanced Settings “Your Stats” presentation and count authority.

`keep Your Stats, move every retained count to local authority, and delete Apps Installed`

Confirmed: preserve the hidden-until-requested **Profile & Stats** wrapper, the separately retained AI Profile, the **Your Stats** card, Conversations, AI Chat Messages, Screenshots, Focus Sessions, To Do/Done/Removed Tasks, Goals, Memories, formatted integer presentation, per-row loading placeholders, chat-count loading state, and the existing card-level failure presentation.

Replace backend conversation, Chat-message, and goal counts with queries against their approved owner-scoped local stores. Preserve already-local Rewind, Focus, Task, and Memory reads. Delete **Apps Installed**, its rejected marketplace fetch, loading row, state contribution, and tests. Do not add replacement cloud counts, synchronized totals, duplicate counter state, or another statistics backend.

Acceptance group: A21.


### IR-931

Fork-local storage identity and inherited Omi takeover migrations.

`create clean product namespaces and delete every automatic Omi takeover migration`

Confirmed: assign our own stable, Beta, development, named-bundle, and preview bundle identities; Application Support, Cache, Log, UserDefaults, database, runtime, and related filesystem roots; Keychain base services while retaining Team ID plus bundle-ID scoping; login-item/updater/TCC identities; and user-facing path descriptions. Preserve owner-scoped per-account local database isolation inside the new product root.

Delete automatic migration from the shared Omi root and Omi anonymous directory, including Omi-specific WAL checkpoint/move/merge cleanup used only by that import. Leave all Omi files, databases, media, backups, defaults, caches, logs, permissions, login items, and Keychain entries untouched. Do not offer or silently attempt an Omi import because this product is not Omi and has no authority to access that data.

Delete the `Omi Computer.app` search, Omi bundle-process enumeration, force termination, delayed deletion, Trash fallback, and related compatibility tests. Do not replace them with a generic legacy-app killer: no previously shipped app exists under our identity in v1. Keep IR-929's same-product DMG-to-Applications installation. A future real rename may deliberately reintroduce a narrowly targeted migration for our own signed old identity.

Acceptance group: A21.


### IR-932

Upgrade-only import from the retired realtime voice UserDefaults outbox.

`delete the retired voice-outbox importer while preserving current voice persistence`

Confirmed: remove `LegacyVoiceJournalImporter.swift`, its compatibility metadata and removal marker, decode-only entry model, `realtimeVoiceTurnOutbox.v1` reader/acknowledgement store, 200-entry batch import, owner imported/task state, session invocation, importer-only tests, and compatibility assertions.

Preserve current realtime turn persistence directly into the kernel journal, journal acceptance fencing, stable idempotency keys, owner checks, barge-in and interrupted-turn continuity, local restoration, and next-turn context. Do not create a renamed legacy queue or another compatibility path for a version of this product that never shipped.

Acceptance group: A21.


### IR-933

Disabled engagement-based Feature Tiers and dormant navigation gating.

`delete the complete disabled Feature Tiers system`

Confirmed: remove `TierManager`, eligibility computation and thresholds, backend/local stats reads performed only for tiers, V2/V3/V4 tier migrations, once-daily check calls, `currentTierLevel` and related defaults, last-seen/show-all/old migration keys where exclusive, the unreachable Feature Tiers card, tier picker and progress rows, sidebar locks/tooltips/manual unlock behavior, tier-driven navigation redirects and visible-item helpers, tier-change analytics, required-tier metadata where exclusive, and focused tests/docs.

Keep every retained first-release product feature visible. Preserve IR-930's independent **Your Stats** card and preserve paid plans, Dodo entitlements, managed-usage quotas, and fair-use enforcement because none is this engagement gate. Do not replace Feature Tiers with another progressive-unlock system.

Acceptance group: A21.


### IR-934

Orphaned `desktop/macos/agent-cloud/` cloud Agent VM snapshot.

`delete the complete agent-cloud snapshot as an explicit IR-001 child`

Confirmed: remove every module, script, experiment, research snapshot, fixture, and test beneath `desktop/macos/agent-cloud/`. Remove or rewrite live comments/contracts whose only authority is parity with that deleted snapshot. Preserve historical changelog entries as historical records.

Do not port these duplicate helpers into the retained runtime merely because individual patterns are generally useful. Preserve `desktop/macos/agent/`, the local Node kernel, managed Pi model/tool/model loop, private local tool transport, Swift authorization/execution, local journal, and all accepted background-agent behavior. This closes a forgotten child of IR-001 rather than making a new product decision.

Acceptance group: A21.


### IR-935

Standalone Remotion marketing-video project under `desktop/macos/demo/`.

`delete the complete standalone Remotion marketing-video project`

Confirmed: remove both compositions, every scene/component/style, public logo, README, Remotion/PostCSS/TypeScript/ESLint/Prettier configuration, package manifest, package lock, and project-specific ignore file beneath `desktop/macos/demo/`. Remove any newly discovered live reference that exists only to invoke this project.

Do not port or rebrand the stale videos for v1. Preserve their historical source through Git history. Future marketing material must be created from the finalized product and fact-checked disclosures under an explicitly owned website/marketing workflow rather than treated as a Mac runtime dependency.

Acceptance group: A21.


### IR-936

Orphaned compiled Claude ACP bridge under `desktop/macos/acp-bridge/`.

`delete the orphaned compiled ACP bridge as an explicit IR-800 child`

Confirmed: remove `desktop/macos/acp-bridge/` completely together with the live Claude ACP adapter, activation and registry branches, Claude authentication, external-adapter policy, focused tests, configuration, packaging residue, and documentation already rejected by IR-800.

Preserve `desktop/macos/agent/` as the retained local Node runtime, its managed Pi adapter, packaged extension, `OMI_BRIDGE_PIPE` bridge, Swift `ChatToolExecutor`, tool authorization, local journal, and accepted normal-chat and background-agent behavior. Delete the callerless `omi-tools-stdio` process with the alternate-adapter plumbing under IR-015/S-05; do not delete or weaken Pi merely because the obsolete ACP bridge also relayed Omi tools.

Acceptance group: A21.


### IR-937

Live packaged managed-Pi provider and tool extension under `desktop/macos/pi-mono-extension/`.

`retain and narrow the packaged managed-Pi extension according to prior decisions`

Confirmed: preserve the package, managed provider registration, one retained Sonnet-class route, authenticated request, safe request-correlation and reasoning-lane headers, scoped typed-tool registration and Unix-socket relay, packaging/signing wiring, focused package tests, and generic code genuinely required by those paths.

Delete four-provider BYOK environment/header propagation; Opus registration, aliases, and tests; rejected skill discovery/search/load registration; general shell/file built-in exposure; the broad-command and arbitrary-write denylist classifiers; the unconsumed broad-execution audit log and its `~/.omi` path; and exclusive fixtures/tests/docs. Replace Omi provider/model/endpoint/protocol-visible identity with the fork's owned identity while keeping internal transport compatibility only where a surviving caller requires it.

Do not delete the extension or replace managed Pi with ACP, Hermes, OpenClaw, direct customer keys, or a new harness. This is the source-level reconciliation of already-approved behavior, not a new agent architecture.

Acceptance group: A21.


### IR-938

External task integrations and automatic export.

`delete the complete external task-integration and export product`

Confirmed: remove `task_integrations.router` and registration; provider OAuth URL, callback, token-exchange/refresh, discovery and task-write endpoints; Todoist, Asana, Google Tasks, and ClickUp clients, credentials, settings, stored tokens/defaults/list/project metadata, generated non-Windows bindings, tests, docs, metrics, and deployment configuration; `task_integrations_ops.py`; automatic single/batch export hooks from action-item, task-intelligence, and conversation processing; and the integration-only candidate dispatch machinery. The latter includes `candidate_integration_outbox` writes from task/workstream acceptance, its claim/complete/list lease helpers and exports, `candidate_service` dispatch/drain code, `/v1/candidates/integrations/drain`, its Firestore index plus registry entry, generated binding, focused candidate/workstream/router tests, and the integration-dispatch clause in the `task_candidate_lifecycle` workflow invariant. Preserve candidate creation/acceptance itself after removing that side effect.

Also remove the complete Apple Reminders export path. That path includes its mobile-push builder/sender, `batch_set_sync_requested`, `get_pending_apple_reminders_sync`, `batch_sync_update_action_items`, `/v1/action-items/pending-sync`, `/v1/action-items/sync-batch`, `SyncBatch*`/`PendingSyncResponse` models, the five export/sync fields where no other retained caller remains, route-policy/generated-client entries, mobile-lifecycle and focused unit tests, and current docs.

Preserve ordinary local tasks, local Task Assistant extraction, local recurrence/edit/complete/delete behavior, and retained Chat/PTT/proactive producers writing the authoritative GRDB store. Do not replace the deleted providers with a generic integration framework or silently add a native Apple Reminders integration. A future local/native export is a new product decision with its own authority and consent boundary.

Acceptance group: A22.


### IR-939

Vendored universal libwebp release libraries.

`retain and re-own the universal libwebp cache with the Mac release system`

Confirmed: keep the two universal dylibs and the reproducible build instructions as an S-29 release input. The owned Codemagic/release definition must verify the expected version/checksums, both architectures, `@rpath` install names, minimum supported macOS version, signing, and the from-source fallback before copying them into a universal candidate. Update Omi names and missing-file claims when that owned consumer lands; do not treat a README as sufficient release wiring.

Preserve `CWebP`, ordinary typed WebP screen capture, local Homebrew/pkg-config development behavior, artifact MIME handling, and signed-bundle library rewriting. Do not convert typed capture to PTT's separate JPEG path or delete live screen understanding to remove two release artifacts.

Acceptance group: A23.


### IR-940

Nested undiscoverable Mac install workflow.

`delete the nested install workflow and its exclusive exact-file contract`

Confirmed: remove `desktop/macos/.github/workflows/test-install.yml`, `desktop/macos/tests/test-test-install-workflow-contract.sh`, `test-install-job-contract.yml`, `test-install-workflow-prefix-contract.yml`, and live manifest/runner/docs references whose only purpose is to preserve that nested artifact. Do not move it to the root or recreate an Omi release lane as part of cleanup.

Preserve the actual root candidate, signing, notarization, qualification, Beta/Stable, preview, install/update, and rollback controls selected under IR-892 through IR-895 and assigned to S-29. The owned release system may implement a new discoverable signed-install test against this product's exact candidate; it must not inherit `BasedHardware/omi`, Omi bundle/process names, or destructive production-app cleanup.

Acceptance group: A24.


### IR-941

Unreferenced packaged notification and Rewind media.

`delete both unreferenced packaged media files`

Confirmed: remove `enable_notifications.gif` and `rewind-demo.mp4` plus any newly discovered metadata or tests whose only owner is those exact files. Re-run the Mac resource/package and named-bundle checks to prove no dynamic lookup depended on them and record the bundle-size change.

Preserve all live Notifications and Rewind source, reachable assets, settings, tests, local databases/media, and reviewed behavior. Do not interpret the no-caller resource deletion as authority to delete or redesign those product families.

Acceptance group: A25.
