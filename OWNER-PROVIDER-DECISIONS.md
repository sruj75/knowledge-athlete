# Owner provider decisions

Repository-tracked operator handoff. This file records account ownership and
provider boundaries, but must never contain passwords, tokens, private keys,
certificate contents, API keys, recovery codes, or secret values.

Last confirmed: 2026-08-29

## Product identity

- Visible product name: `Intentive`
- macOS application filename: `Intentive.app`
- Shared technical slug: `heyintentive`
- Owned public domain: `heyintentive.com`
- Never use `intentive.life` or `intuitive.life` as an Intentive product domain.
- Current MVP repository: the existing `knowledge-athlete` repository. Do not create or require a GitHub organization for this release.

## Provider accounts and boundaries

- Google Cloud CLI cleanup account: `srujan@intentive.life`
  - This remains the locally authenticated `gcloud` account used only to remove the abandoned Intentive development service from `agentic-accountability`.
  - Do not create new Intentive resources through this account or in `agentic-accountability`.
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

## Google Cloud topology

- Do not create a new Google Cloud project for the MVP.
- Existing Firebase project `knowledge-athlete` is also the Google Cloud project for Intentive Cloud Run and Secret Manager resources. No Artifact Registry repository exists there yet.
- Billing is active on `knowledge-athlete` as of 2026-08-29. The account has a 90-day, $300 trial, but the operating constraint is to stay within the ongoing Google Cloud Free Tier both during and after the trial. Trial credit is not a spending target.
- Budget alerts are warnings, not a hard spending cap. Do not deploy a configuration merely because trial credit is available.
- Created 2026-08-29: dedicated development runtime identity `knowledge-athlete-dev-runtime@knowledge-athlete.iam.gserviceaccount.com` with only project role `roles/datastore.user` and secret-level `roles/secretmanager.secretAccessor` on `REDIS_DB_PASSWORD`. It has no Owner, Editor, deploy, project-wide Secret Manager, Vertex AI, Storage, Tasks, or index-administration role.
- Google Memorystore for Redis is not approved for development because its provisioned capacity is continuously billable and has no ongoing free tier. Do not provision it while the permanent-free constraint applies.
- Deleted 2026-08-29: the abandoned private `knowledge-athlete-dev` Cloud Run service in `agentic-accountability`.
  - Verified afterward that `once-upon-a-time` is the only remaining Cloud Run service in `agentic-accountability/us-west1`.
  - Removed the Intentive runtime account's `roles/aiplatform.user`, `roles/cloudtasks.enqueuer`, self token-creator binding, and conditional cross-project `roles/datastore.user` binding.
  - Disabled `knowledge-athlete-dev-runtime@agentic-accountability.iam.gserviceaccount.com`.
  - Preserved the exact backend container image in the shared `intentive` Artifact Registry for recovery; do not delete the shared repository or unrelated images.
- Created and verified 2026-08-29: public-ingress Cloud Run service `knowledge-athlete-dev` in `knowledge-athlete/us-west1`.
  - Canonical discovered URL: `https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app`.
  - Active revision: `knowledge-athlete-dev-bootstrap-8c870c8`, imported from the immutable backend image for source commit `8c870c83c83131d91e7536ceef73ef7b07f3461e` and serving 100% of traffic.
  - Cloud Run grants `roles/run.invoker` only to `allUsers`, matching the repository's `--allow-unauthenticated` ingress contract. Public `/v1/health` returns `200`; a protected route without a Firebase token reaches FastAPI and returns `401`.
  - Permanent-free bootstrap shape: zero minimum instances, one maximum instance, request-based CPU, 1 vCPU, 2 GiB memory, billing mode disabled, Vertex AI disabled, and no Google Memorystore. This intentionally does **not** claim full S-27 release-manifest conformance or production readiness.
  - Cloud Run imported its own serving copy from the preserved recovery image. Temporary cross-project Artifact Registry reader bindings were removed after deployment, and no Artifact Registry repository/storage was created in `knowledge-athlete`.
  - The Firebase-authenticated release probe verified Firestore write/read through the runtime identity and verified that the same request created its Redis coordination lock. The Firebase probe user, Firestore document, Redis lock, protected token file, and temporary token-signing permission were all removed afterward.
  - Making ingress public changed no revision, traffic, runtime identity, CPU, memory, concurrency, scaling, provider setting, secret permission, Firestore permission, or Redis configuration. Public traffic can still consume Cloud Run's monthly allowance; maximum one instance bounds concurrency but is not a hard monetary cap.
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
- Secret Manager contains exact enabled version 1 of `FIREBASE_API_KEY`, copied from the owned development app configuration for the canonical release-probe tooling. The API key value is not recorded in Git, and the runtime identity has no accessor binding to this secret.
- Enabled 2026-08-29: Google and Apple Firebase Authentication providers. Google uses public-facing
  name `Intentive` and support email `srujan@heyintentive.com`. The refreshed development plist
  contains the generated Google OAuth client. Apple Developer identifier/capability registration is
  still required before native Apple sign-in can work in a signed app.

## Release-readiness checklist

This is the complete handoff, not a request to release now. A checked item is known or
already done. An unchecked item is still required before the corresponding live operation.

### Already decided or completed

- [x] Use GitHub repository `sruj75/knowledge-athlete` for the MVP; do not create a new organization yet.
- [x] Use product name and app filename `Intentive` / `Intentive.app`.
- [x] Use slug `heyintentive`, public domain `heyintentive.com`, and owned bundle namespace `com.heyintentive.intentive`.
- [x] Use Apple Team ID `24D6NXS6H7`; an owned Developer ID Application identity is installed locally.
- [x] Use Codemagic login `srujan24@icloud.com` and Apple Developer login `22btrsn071@gmail.com`.
- [x] Use `srujan@heyintentive.com` as the Google Cloud operator for future Intentive resources.
- [x] Use the existing Firebase/GCP project `knowledge-athlete` for future Intentive development cloud resources; do not create another project.
- [x] Use Firebase project `knowledge-athlete`; its `(default)` Firestore database exists in `us-west1` with deny-all client rules.
- [x] Use Sentry organization `heyintentive` and macOS project `desktop-macos`; the macOS DSN and dSYM upload destination are repository-wired.

### Needed before hosted Firebase sign-in or backend Firestore access

- [x] Register the owned development macOS app in Firebase project `knowledge-athlete` and track its downloaded Google service plist without rewriting an inherited Omi plist.
- [ ] Before Beta/Stable registration, approve the production Firebase project boundary. Register `com.heyintentive.intentive.beta` and `com.heyintentive.intentive` there and download their real Google service plists; do not silently point production-family builds at the development project.
- [x] Enable and configure Google sign-in in Firebase Authentication with public-facing name `Intentive` and support email `srujan@heyintentive.com`; track the refreshed development plist containing its OAuth client.
- [x] Enable Apple sign-in in Firebase Authentication. Native use still requires the Apple Developer identifier/capability under account `22btrsn071@gmail.com`.
- [x] Grant the development runtime identity only application-level Firestore data access (`roles/datastore.user`). The database continues to deny direct third-party client access on purpose.
- [x] Verify one development Firestore read/write path through the runtime identity after the hosted Cloud Run service exists; the fixed release-probe user wrote and read `language=en`, then all probe state was deleted. No service-account key file was created.

### Needed before the hosted development backend is fully usable

- [x] Connect billing to `knowledge-athlete`; confirmed active on 2026-08-29.
- [ ] Review the currently enabled APIs and retain/enable only those required by the development backend. API availability is not authorization to provision a paid service.
- [x] Create and verify the public-ingress `knowledge-athlete-dev` Cloud Run service and dedicated runtime identity inside `knowledge-athlete/us-west1` using the documented permanent-free bootstrap shape.
- [x] Use the one free Upstash database `intentive-development` for development and owner-approved early MVP production. Do not provision Google Memorystore under the current cost constraint; revisit environment isolation before meaningful production traffic.
- [x] Store the current development Redis password and Firebase API key as exact Secret Manager version 1 values. The runtime identity can read only the development Redis secret.
- [ ] Add the remaining managed-provider secrets only when their retained feature is configured. Modulate is deliberately skipped for now; no provider secret may be invented, committed, or copied from Omi.
- [x] Admit public Cloud Run invocation while retaining Firebase authentication on protected routes, and point development desktop defaults at the discovered owned URL.
- [ ] Enable the Cloud Billing Budget API and configure owner-approved alerts if cost notifications are wanted. Alerts are not a hard cap; retain scale-to-zero and maximum one instance regardless.

### Needed before Codemagic can build a signed candidate

- [ ] In Codemagic, connect `sruj75/knowledge-athlete` from the `srujan24@icloud.com` account and record the resulting Codemagic application ID.
- [ ] Create and record the exact release and preview workflow IDs. The inherited Omi workflow IDs are forbidden.
- [ ] Import the supplied Developer ID `.p12` into Codemagic. This requires the `.p12` password; the password must be entered into Codemagic's secret store, never committed or pasted into documentation.
- [ ] Renew/confirm the Apple Developer Program membership for team `24D6NXS6H7` before relying on notarization or creating new identifiers.
- [ ] Create an App Store Connect API key or an accepted notarytool keychain profile for notarization, and store the issuer ID, key ID, and private key only in protected provider secrets.
- [ ] Register the stable, Beta, development, and preview identifiers/schemes with Apple/provider services where registration is required.
- [ ] Generate a new Sparkle EdDSA keypair. Put only the public key in the signed app; put the private key only in Codemagic's protected secret store. Record and approve its public-key fingerprint.
- [ ] Configure a Sentry auth token for dSYM upload to `heyintentive/desktop-macos`; the public DSN already in the app is not an upload credential.
- [ ] Configure the owned production backend URL, appcast/feed URL, manual-download URL, and GitHub release URL as release inputs. Missing values must keep release/update behavior disabled.
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
