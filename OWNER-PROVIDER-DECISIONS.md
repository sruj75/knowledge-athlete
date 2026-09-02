<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# Owner provider decisions

Repository-tracked operator handoff. This file records account ownership and
provider boundaries, but must never contain passwords, tokens, private keys,
certificate contents, API keys, recovery codes, or secret values.

Last confirmed: 2026-09-02

## Product identity

- Visible product name: `Intentive`
- macOS application filename: `Intentive.app`
- Shared technical slug: `heyintentive`
- Owned public domain: `heyintentive.com`
- Never use `intentive.life` or `intuitive.life` as an Intentive product domain.
- Current MVP repository: the existing `knowledge-athlete` repository. Do not create or require a GitHub organization for this release.

## Provider accounts and boundaries

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
  - Installed signing identity verified 2026-08-27: `Developer ID Application: Srujan Gowda (24D6NXS6H7)`, valid through 2030-11-18.
  - The supplied `.p12` is password-protected and remains under ignored `.context/`; never commit it. Codemagic import still needs its password.
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

## Sparkle update identity

- Generated 2026-08-29 with the repository-pinned Sparkle tooling under the separate macOS Keychain
  account `heyintentive`; no inherited or default Omi update key was reused.
- Public EdDSA key: `APqAXab2u3W8phgwmTmaHu1ztQgpdr+MR2046hUhflM=`.
- SHA-256 fingerprint of the decoded public key:
  `f9007cb82a319a6343cbcddd6707372c30c4e4984350a15e47e9e386a60076ab`.
- The private key remains in the local login Keychain, with an owner-only ignored backup under
  `.context/release-secrets/`, and is stored as protected Codemagic variable `SPARKLE_PRIVATE_KEY`
  in `intentive_macos_release`. It must never be committed.

## Google Cloud topology

- Do not create a new Google Cloud project for the MVP.
- Existing Firebase project `knowledge-athlete` is also the Google Cloud project for Intentive Cloud Run, Secret Manager, Cloud Build, and Artifact Registry resources.
- Billing is active on `knowledge-athlete` as of 2026-08-29. The account has a 90-day, $300 trial, but the operating constraint is to stay within the ongoing Google Cloud Free Tier both during and after the trial. Trial credit is not a spending target.
- Budget alerts are warnings, not a hard spending cap. Do not deploy a configuration merely because trial credit is available.
- Created 2026-08-29: dedicated development runtime identity `knowledge-athlete-dev-runtime@knowledge-athlete.iam.gserviceaccount.com` with only project role `roles/datastore.user` and secret-level `roles/secretmanager.secretAccessor` on `REDIS_DB_PASSWORD`, `FIREBASE_API_KEY`, `GOOGLE_CLIENT_SECRET`, `GEMINI_API_KEY`, and `OPENAI_API_KEY`. It has no Owner, Editor, deploy, project-wide Secret Manager, Vertex AI, Storage, Tasks, or index-administration role.
- Google Memorystore for Redis is not approved for development because its provisioned capacity is continuously billable and has no ongoing free tier. Do not provision it while the permanent-free constraint applies.
- Deleted 2026-08-29: the abandoned private `knowledge-athlete-dev` Cloud Run service in `agentic-accountability`.
  - Verified afterward that `once-upon-a-time` is the only remaining Cloud Run service in `agentic-accountability/us-west1`.
  - Removed the Intentive runtime account's `roles/aiplatform.user`, `roles/cloudtasks.enqueuer`, self token-creator binding, and conditional cross-project `roles/datastore.user` binding.
  - Disabled `knowledge-athlete-dev-runtime@agentic-accountability.iam.gserviceaccount.com`.
  - Preserved the exact backend container image in the shared `intentive` Artifact Registry for recovery; do not delete the shared repository or unrelated images.
- Created and verified 2026-08-29: public-ingress Cloud Run service `knowledge-athlete-dev` in `knowledge-athlete/us-west1`.
  - Stable service URL used by OAuth and development clients: `https://knowledge-athlete-dev-674306938907.us-west1.run.app`; Cloud Run also reports the compatible alias `https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app`.
  - Active revision: `knowledge-athlete-dev-00002-pjn`, serving 100% of development traffic from owned immutable image digest `sha256:3129ea2d5d2a67bb23d4c2db42894b5de33f005660cd733dfc1b443e797379c8`, built from repository commit `98ff1714b125b09b17d3ca741d090232be95901c`.
  - Cloud Run grants `roles/run.invoker` only to `allUsers`, matching the repository's `--allow-unauthenticated` ingress contract. Public `/v1/health` returns `200`; a protected route without a Firebase token reaches FastAPI and returns `401`.
  - Permanent-free bootstrap shape: zero minimum instances, one maximum instance, request-based CPU, 1 vCPU, 2 GiB memory, billing mode disabled, Vertex AI disabled, and no Google Memorystore. This intentionally does **not** claim full S-27 release-manifest conformance or production readiness.
  - The original bootstrap revision used a recovery image from `agentic-accountability`; that dependency is retired. Repository `intentive` now exists in `knowledge-athlete/us-west1`, and the active revision pulls only from `us-west1-docker.pkg.dev/knowledge-athlete/intentive/backend`.
  - Cloud Build completed the owned image in 7 minutes 29 seconds, within its current monthly free allowance. The one-image repository measured 789.033 MB, about 277 MB above Artifact Registry's 0.5 GiB-month free allowance; at the 2026-08-29 published price this is roughly USD 0.03/month until the inherited runtime is slimmed.
  - The Firebase-authenticated release probe verified Firestore write/read through the runtime identity and verified that the same request created its Redis coordination lock. The Firebase probe user, Firestore document, Redis lock, protected token file, and temporary token-signing permission were all removed afterward.
  - Exact Secret Manager version 1 values `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` back the existing Firebase-created Google OAuth web client. Firebase Auth was synchronized to the replacement secret, and the client authorizes the stable Cloud Run callback `/v1/auth/callback/google`.
  - The active owned revision passed public `/v1/health` and a real `/v1/auth/authorize` infrastructure probe: Redis accepted the one-time session and the backend returned a `307` to `accounts.google.com` with the owned client ID. No user completed an interactive sign-in during this setup probe.
  - Public traffic can consume Cloud Run's monthly allowance; zero minimum instances and maximum one instance bound idle and concurrent consumption but are not a hard monetary cap.
- The Cloud Billing Budget API is not enabled in `knowledge-athlete`, so no live budget-alert inventory has been verified. Enabling that API and configuring alerts is a separate cost-observability step; alerts warn but do not cap spend.
- Do not deploy a production service or publish a release until the owner separately authorizes the release stage after all slices and product cleanup are complete.

## Redis topology

- Provider account: `srujan@heyintentive.com` at Upstash.
- Created 2026-08-29: free database `intentive-development`, AWS Oregon (`us-west-2`), TLS endpoint `smart-sunfish-221745.upstash.io:6379`.
- Current free-plan limits observed in the provider console: one free database, 500,000 commands per month, 256 MB storage, and 50 GB monthly bandwidth. Adding a second database currently requires a payment method.
- Owner decision: development and the early MVP production backend may share `intentive-development` until the startup has traction. This is a cost-saving compromise, not production-grade isolation: simultaneous development and production traffic can collide in authentication codes, rate limits, locks, fair-use counters, and caches. Revisit before meaningful production traffic.
- Secret Manager API is enabled in `knowledge-athlete`. Exact enabled version 1 exists for `REDIS_DB_PASSWORD` (development runtime) and `DESKTOP_REDIS_DB_PASSWORD` (future production workflow contract); both currently refer to the owner-approved shared database. Secret values must never be committed to Git or copied into this file.
- Verified 2026-08-29: TLS hostname/certificate validation, ping, temporary set/read/delete, and absence after cleanup all passed.

## Firebase topology

- Firebase Authentication and Firestore are separate Firebase services.
- The desktop sign-in flow requires Google and Apple authentication providers.
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

## Managed-provider classification

An inherited variable in Omi's deployment declaration is not proof that Intentive needs a provider account. Current retained production callers decide the inventory:

- `OPENAI_API_KEY` is retained only for `/v1/tts/synthesize` using `gpt-4o-mini-tts`. It no longer owns text inference, embeddings, realtime voice, or relay traffic. Verified 2026-09-02 under OpenAI account `srujantriples@gmail.com`: the Personal organization's Default project has one service-account key named `Intentive development TTS`, restricted to request permission on `/v1/audio/speech` with every other permission set to none. Its value is stored only as enabled Secret Manager version 1, GitHub environment `development` selects exact version `1`, and only the limited development runtime identity can read it. A direct `gpt-4o-mini-tts` probe returned HTTP 200 with MPEG audio, while a models-list request returned HTTP 403 and proved the denial boundary. The active Cloud Run revision does not bind this secret yet.
- `ANTHROPIC_API_KEY` and `DESKTOP_LEGACY_ANTHROPIC_KEY` are deleted requirements. Normal Chat uses Gemini; neither credential should be created or bound.
- One development `GEMINI_API_KEY` is enough for the MVP. Gemini 3.7 Flash owns normal Chat, greeting, conversation processing, Memory compute, and fair-use classification; existing Flash-Lite title/translation, desktop generation/embeddings, and Gemini Live routes remain. Model inference uses the Gemini Developer API only; `USE_VERTEX_AI` is deleted while Cloud Run ADC remains for Firebase, Firestore, and other GCP infrastructure.
- Verified 2026-09-02: the earlier `GEMINI_API_KEY` version 1 is a standard API key. A replacement authorization key is bound to the limited development runtime service account, restricted only to `generativelanguage.googleapis.com`, and stored without committing its value as enabled Secret Manager version 2. A direct authenticated model-list probe returned HTTP 200. GitHub environment `development` selects exact version `2`. Version 1 remains enabled only as a rollback copy until a development candidate passes. The active Cloud Run revision still has no Gemini binding; that binding belongs to the next complete development deployment, not an isolated live revision mutation. Do not create parallel per-model keys.
- `MODULATE_API_KEY` is genuinely retained for fixed managed live and prerecorded-overflow STT, but the owner explicitly postponed Modulate setup. This leaves managed STT and S-31 real-provider continuity open; it is not evidence that Modulate is unused.
- `POSTHOG_PROJECT_API_KEY` is retained telemetry, but the owned PostHog project identity and truthful disclosure remain S-30 inputs. Do not reuse an inherited Omi token.
- `ARTIFICIALANALYSIS_API_KEY` is deleted with Auto and the provider picker; there is no remaining provider comparison to score.
- Langfuse now owns Chat tracing and prompt management. The repository runtime/configuration migration is complete, but the development Cloud Run service still needs exact Langfuse secret-version bindings and a real fail-open trace before it is live evidence.
- `DESKTOP_GOOGLE_CALENDAR_API_KEY` must not be configured: IR-106, IR-142, IR-144, and IR-375 delete the Calendar creation/import/enrichment/linking surfaces.

## Release-readiness checklist

This is the complete handoff, not a request to release now. A checked item is known or
already done. An unchecked item is still required before the corresponding live operation.

### Already decided or completed

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

### Needed before hosted Firebase sign-in or backend Firestore access

- [x] Register the owned development macOS app in Firebase project `knowledge-athlete` and track its downloaded Google service plist without rewriting an inherited Omi plist.
- [x] Use the same owner-approved MVP Firebase project for Development, Beta, and Stable; register `com.heyintentive.intentive.dev`, `com.heyintentive.intentive.beta`, and `com.heyintentive.intentive`, and preserve each real plist only in its tracked or protected owner.
- [x] Enable and configure Google sign-in in Firebase Authentication with public-facing name `Intentive` and support email `srujan@heyintentive.com`; track the refreshed development plist containing its OAuth client.
- [x] Enable Apple sign-in in Firebase Authentication. Native use still requires the Apple Developer identifier/capability under account `22btrsn071@gmail.com`.
- [x] Grant the development runtime identity only application-level Firestore data access (`roles/datastore.user`). The database continues to deny direct third-party client access on purpose.
- [x] Verify one development Firestore read/write path through the runtime identity after the hosted Cloud Run service exists; the fixed release-probe user wrote and read `language=en`, then all probe state was deleted. No service-account key file was created.

### Needed before the hosted development backend is fully usable

- [x] Connect billing to `knowledge-athlete`; confirmed active on 2026-08-29.
- [ ] Review the currently enabled APIs and retain/enable only those required by the development backend. API availability is not authorization to provision a paid service.
- [x] Create and verify the public-ingress `knowledge-athlete-dev` Cloud Run service and dedicated runtime identity inside `knowledge-athlete/us-west1` using the documented permanent-free bootstrap shape.
- [x] Use the one free Upstash database `intentive-development` for development and owner-approved early MVP production. Do not provision Google Memorystore under the current cost constraint; revisit environment isolation before meaningful production traffic.
- [x] Store the development Redis password, Firebase API key, and Google OAuth client ID/secret as exact Secret Manager version 1 values, plus the Gemini authorization key as exact version 2 and the OpenAI TTS-only key as exact version 1. The runtime identity has secret-level access only to `REDIS_DB_PASSWORD`, `FIREBASE_API_KEY`, `GOOGLE_CLIENT_SECRET`, `GEMINI_API_KEY`, and `OPENAI_API_KEY`; the client ID remains non-secret deployment configuration.
- [x] Retire the active service's cross-project recovery-image dependency by building and serving an immutable backend image from `knowledge-athlete/us-west1/intentive`.
- [ ] OpenAI TTS-only key version 1 and Gemini authorization key version 2 are prepared, provider-verified, and selected by the development GitHub environment. Bind them only as part of the next complete development deployment, then prove the authenticated backend TTS route and a real Gemini turn. Do not create Anthropic or Artificial Analysis credentials. Modulate remains deliberately postponed. Bind exact owned Langfuse secret versions in that same deployment, then prove one real fail-open trace. No provider secret may be invented, committed, or copied from Omi.
- [x] Admit public Cloud Run invocation while retaining Firebase authentication on protected routes, and point development desktop defaults at the discovered owned URL.
- [ ] Enable the Cloud Billing Budget API and configure owner-approved alerts if cost notifications are wanted. Alerts are not a hard cap; retain scale-to-zero and maximum one instance regardless.

### Needed before Codemagic can build a signed candidate

- [x] Connect `sruj75/knowledge-athlete` from the `srujan24@icloud.com` Codemagic account and record the selected application ID `6a8ff0296fc70d39540cb56a`.
- [x] Create and record exact repository workflow IDs `intentive-macos-release` and `intentive-macos-preview`; GitHub dispatch and observation use those owned IDs.
- [x] Delete the empty duplicate Codemagic application `6a8ff02926a0b2fbc893544e`; only the selected application remains.
- [x] Finish YAML setup for the selected Codemagic app and create/update its GitHub webhook after the provider document reached the default branch.
- [x] Store the existing Codemagic API token only as protected GitHub Actions secret `CODEMAGIC_API_TOKEN`.
- [ ] Finish protected Codemagic groups `intentive_macos_signing`, `intentive_macos_release`, and `intentive_macos_preview`. Signing contains the Stable Firebase plist and desktop Firebase environment; release contains the Beta plist, Sparkle pair, and Sentry upload token. Apple signing/notarization values and the preview group remain pending. Populate only names validated by `desktop/macos/scripts/codemagic-release.sh`; never commit their values.
- [ ] Import the supplied Developer ID `.p12` into Codemagic. This requires the `.p12` password; the password must be entered into Codemagic's secret store, never committed or pasted into documentation.
- [ ] Renew/confirm the Apple Developer Program membership for team `24D6NXS6H7` before relying on notarization or creating new identifiers.
- [ ] Create an App Store Connect API key or an accepted notarytool keychain profile for notarization, and store the issuer ID, key ID, and private key only in protected provider secrets.
- [ ] Register the stable, Beta, development, and preview identifiers/schemes with Apple/provider services where registration is required.
- [x] Generate a new Sparkle EdDSA keypair, store it under the separate `heyintentive` Keychain account, configure the public key in Codemagic, and record its public-key fingerprint above.
- [x] Add the Sparkle private key only to Codemagic's protected `intentive_macos_release` group.
- [x] Configure protected Codemagic variable `SENTRY_AUTH_TOKEN` in `intentive_macos_release` for dSYM upload to `heyintentive/desktop-macos`. The Sentry organization token is named `intentive-macos-release-symbols`, has only the `org:ci` scope, and was verified against Sentry's debug-files endpoint before storage. The token value must never be committed.
- [ ] Configure the owned production backend URL, appcast/feed URL, manual-download URL, and GitHub release URL as release inputs. Store the exact production API origin separately as protected `INTENTIVE_APPROVED_PRODUCTION_API_ORIGIN` in every release environment and both Codemagic groups; it must match the production app URL and preview-registry URL before any credential is loaded or sent. No origin is approved yet, so missing values must keep release/update behavior disabled.
- [ ] Configure an owned GitHub App for release automation, install it on `sruj75/knowledge-athlete`, and record its app ID/private key as protected GitHub secrets.
- [ ] Provision the trusted Apple Silicon qualification runner and apply only the Intentive runner labels documented by this repository.

### Needed before Beta or Stable publication

- [ ] Create production Cloud Run/backend resources and public release endpoints only after the owner gives a new explicit release-stage authorization. No current development service should be mistaken for production authority.
- [ ] Configure the release/preview object bucket, public origin, Firestore release documents, service identities, and protected GitHub environments against owned resources.
- [ ] Publish the minimal owned website on `heyintentive.com` with product, download, preview, Terms, Privacy, and support/contact destinations.
- [ ] Decide the exact support and privacy contacts. The valid domain is `heyintentive.com`; earlier spellings such as `heyintuitive.com` or `heintuitive.com` are not owned product identities and must not ship. Likely choices are `support@heyintentive.com` and `privacy@heyintentive.com`, but they are not approved or created yet.
- [ ] Approve the actual Terms and Privacy content. There is no registered company today; the current operator is an individual, so repository agents must not invent a legal company name.
- [ ] Run one signed/notarized candidate, trusted-Mac qualification, clean-install/update exercise, and Beta/Stable recovery drill with evidence tied to the exact source SHA and artifact digests.
- [ ] Give a fresh explicit authorization before publishing any candidate, Beta, Stable, paid artifact, DNS record, legal page, or production resource. The current authorization is repository work and development infrastructure only.
