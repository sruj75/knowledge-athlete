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

- Google Cloud: `srujan@intentive.life`
  - This is the account currently verified by `gcloud auth list` and it has access to project `agentic-accountability`.
  - The owner's latest message typed `srujan@intuitive.life`, but the live authenticated account and the owner's earlier instruction both say `srujan@intentive.life`. Treat the live verified address as authoritative unless the owner explicitly changes accounts.
  - This login address is only a Google Cloud operator identity. It is not a product domain or support address.
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
- Existing project/container: `agentic-accountability`.
- Existing reference Cloud Run service: `once-upon-a-time` in `us-west1`.
- New development backend service: `knowledge-athlete-dev` in `us-west1`, beside `once-upon-a-time`.
- Existing Artifact Registry repository to reuse: `intentive` in `us-west1`.
- Created 2026-08-27: private Cloud Run service `knowledge-athlete-dev`.
  - Canonical current URL: `https://knowledge-athlete-dev-pqenui44sa-uw.a.run.app`
  - Runtime service account: `knowledge-athlete-dev-runtime@agentic-accountability.iam.gserviceaccount.com`
  - Image digest: `us-west1-docker.pkg.dev/agentic-accountability/intentive/backend@sha256:684eba6a51c8fbf5cf5a09d510bff4ce0aebeecf515b6496686430a61c41e97d`
  - Revision: `knowledge-athlete-dev-00001-9qb`
  - Verified `/v1/health` returned HTTP 200 with authenticated invocation.
  - No `allUsers` invoker binding exists. The service is not a public beta or release.
  - Redis, Firebase cross-project IAM, provider secrets, public invocation, and full workflow/WIF wiring remain intentionally unconfigured.
- Do not deploy a production service or publish a release until the owner separately authorizes the release stage after all slices and product cleanup are complete.

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
- [x] Use GCP project `agentic-accountability`; the private development Cloud Run service exists in `us-west1`.
- [x] Use Firebase project `knowledge-athlete`; its `(default)` Firestore database exists in `us-west1` with deny-all client rules.
- [x] Use Sentry organization `heyintentive` and macOS project `desktop-macos`; the macOS DSN and dSYM upload destination are repository-wired.

### Needed before hosted Firebase sign-in or backend Firestore access

- [x] Register the owned development macOS app in Firebase project `knowledge-athlete` and track its downloaded Google service plist without rewriting an inherited Omi plist.
- [ ] Before Beta/Stable registration, approve the production Firebase project boundary. Register `com.heyintentive.intentive.beta` and `com.heyintentive.intentive` there and download their real Google service plists; do not silently point production-family builds at the development project.
- [x] Enable and configure Google sign-in in Firebase Authentication with public-facing name `Intentive` and support email `srujan@heyintentive.com`; track the refreshed development plist containing its OAuth client.
- [x] Enable Apple sign-in in Firebase Authentication. Native use still requires the Apple Developer identifier/capability under account `22btrsn071@gmail.com`.
- [ ] Grant the runtime service account only the Firestore permissions the development backend needs, then verify one development read/write path. The database currently denies direct client access on purpose.

### Needed before a private development backend is fully usable

- [ ] Decide and provision an owned Redis service. Redis is a running database service, not only an SDK. The backend will need its TLS URL/password as a secret; no separate Redis login email has been chosen yet.
- [ ] Add the development provider secrets needed by the retained backend and wire them through Secret Manager rather than repository files.
- [ ] Decide how authenticated desktop builds invoke the currently private Cloud Run service, or explicitly authorize a bounded public development endpoint. Do not make it public by accident.

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

- [ ] Create the production Cloud Run/backend resources and public release endpoints only after the owner gives a new explicit release-stage authorization. The current `knowledge-athlete-dev` service is private development infrastructure, not production.
- [ ] Configure the release/preview object bucket, public origin, Firestore release documents, service identities, and protected GitHub environments against owned resources.
- [ ] Publish the minimal owned website on `heyintentive.com` with product, download, preview, Terms, Privacy, and support/contact destinations.
- [ ] Decide the exact support and privacy contacts. The valid domain is `heyintentive.com`; earlier spellings such as `heyintuitive.com` or `heintuitive.com` are not owned product identities and must not ship. Likely choices are `support@heyintentive.com` and `privacy@heyintentive.com`, but they are not approved or created yet.
- [ ] Approve the actual Terms and Privacy content. There is no registered company today; the current operator is an individual, so repository agents must not invent a legal company name.
- [ ] Run one signed/notarized candidate, trusted-Mac qualification, clean-install/update exercise, and Beta/Stable recovery drill with evidence tied to the exact source SHA and artifact digests.
- [ ] Give a fresh explicit authorization before publishing any candidate, Beta, Stable, paid artifact, DNS record, legal page, or production resource. The current authorization is repository work and development infrastructure only.
