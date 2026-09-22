# Owner and provider record

Account ownership, provider roles, operating modes, and configuration for Intentive.
Updated: 2026-09-22. This combines recorded account/console details with
repository-declared settings. Live provider settings were not re-audited during
this cleanup. Secret values belong in the credential stores below.

## Product identity

| Item | Value |
| --- | --- |
| Product / app | Intentive / `Intentive.app` |
| Domain / slug | `heyintentive.com` / `heyintentive` |
| Repository | `sruj75/knowledge-athlete` |
| Bundle IDs | Stable: `com.heyintentive.intentive`; Beta: `.beta`; Dev: `.dev`; named Dev: `.dev.<name>`; Preview: `.preview.<name>` under the same base |
| Product contact | `srujan@heyintentive.com` |

## Accounts and roles

| Provider | Login / owner | Project or account scope | Used for |
| --- | --- | --- | --- |
| Google Cloud / Firebase | `srujan@heyintentive.com`; recorded Firebase backup owner: `srujantriples@gmail.com` | `knowledge-athlete` (project number `674306938907`) | Backend hosting, authentication, Firestore, secrets, build images, storage, and task delivery |
| Google AI Studio / Gemini | Google project `knowledge-athlete`; separate console login not recorded | Gemini Developer API | Managed text, embeddings, and realtime voice |
| Upstash | `srujan@heyintentive.com` | `intentive-development` | Hosted Redis coordination, limits, locks, and caches |
| OpenAI | `srujantriples@gmail.com` | Personal organization / Default project; key name `Intentive development TTS` | Spoken output |
| Modulate | Login email not recorded | Key name `Intentive development` | Managed speech transcription |
| Langfuse | `srujantriples@gmail.com` (signup email; see note below) | `Intentive`, US Cloud | Chat tracing and prompt management |
| PostHog | `srujantriples@gmail.com` | Organization `Intentive`; project `Intentive Desktop` (`397035`) | Product analytics |
| Sentry | Login email not recorded | Organization `heyintentive`; project `desktop-macos` | Crash diagnostics and debug symbols |
| GitHub | `sruj75`; recorded account email `srujan24@icloud.com` | `sruj75/knowledge-athlete` | Source, CI, and release orchestration |
| Codemagic | `srujan24@icloud.com` | App `6a8ff0296fc70d39540cb56a` | macOS builds, signing, and notarization |
| Apple Developer | `22btrsn071@gmail.com` | Team `24D6NXS6H7` | App identifiers, signing, and notarization |
| Vercel | Workspace `srujxx`; login email not recorded | `intentive-tally-landing-page` | Product website and policy/support pages |

Langfuse's April 21, 2026 signup welcome email to `srujantriples@gmail.com` was
checked on September 22. Current membership of the `Intentive` project has not
been confirmed through an authenticated Langfuse session.

## Operating modes

| Mode | Configuration |
| --- | --- |
| Local Dev | Named workspace app, local Firebase Auth/Firestore emulators, local Redis, and synthetic users. Offline providers by default; real AI uses explicit local configuration. |
| Owner Beta | `Intentive Beta.app` uses the shared `knowledge-athlete-dev` backend and configured Firebase participants. |
| Customer billing | `BILLING_MODE=disabled` |
| Cloud authentication | Operator CLI: browser OAuth. Hosted runtime: service-account ADC. GitHub deployment: Workload Identity Federation. |

## Cloud and service settings

| Service / setting | Recorded configuration |
| --- | --- |
| GCP region | `us-west1` |
| Cloud Run service | `knowledge-athlete-dev`; deployment variable `BACKEND_CLOUD_RUN_SERVICE` |
| Backend URL | `https://knowledge-athlete-dev-674306938907.us-west1.run.app` |
| Cloud Run resources | 1 vCPU, 2 GiB RAM, 0–1 instances, concurrency 20, request-based CPU, 3,600-second timeout |
| Firestore | Project `knowledge-athlete`, database `(default)`, `us-west1`; backend access through the runtime identity |
| Firebase sign-in | Google; product/support identity `Intentive` / `srujan@heyintentive.com` |
| Redis | Upstash Free, AWS `us-west-2`, TLS, `smart-sunfish-221745.upstash.io:6379` |
| Artifact Registry | `us-west1-docker.pkg.dev/knowledge-athlete/intentive/backend` |
| Desktop artifact bucket | `knowledge-athlete-desktop-updates-dev`; private, uniform bucket-level access |
| Account-deletion queue | Cloud Tasks `account-deletion`, `us-west1`; 1 concurrent dispatch, 5 attempts |
| Cost settings | Recorded INR 100 monthly alert budget, thresholds 50%/80%/100%, recipient `srujan@heyintentive.com`; Gemini prepaid auto-reload off. Alerts do not cap spending. |
| Langfuse | `https://us.cloud.langfuse.com`; tracing environment `development`; prompt `intentive-chat-system`, label `production`, cache TTL 300 seconds |
| PostHog | US ingestion: `https://us.i.posthog.com` |

### Cloud service identities

All accounts below use the suffix `@knowledge-athlete.iam.gserviceaccount.com`.

| Account | Role |
| --- | --- |
| `knowledge-athlete-dev-runtime` | Hosted backend runtime |
| `intentive-dev-deploy` | Backend deployment and traffic management |
| `intentive-dev-fs-read` | Firestore database/index metadata inspection |
| `intentive-dev-fs-write` | Firestore index creation |
| `intentive-dev-task` | Account-deletion task OIDC signer |

Recorded WIF provider:
`projects/674306938907/locations/global/workloadIdentityPools/intentive-github/providers/github-actions`.

## AI provider configuration

| Provider | Model / setting | Responsibility |
| --- | --- | --- |
| Gemini | `gemini-3.7-flash` | Chat, greeting, conversation processing, Memory compute, and fair-use classification |
| Gemini | `gemini-2.5-flash-lite` | Session titles and segment translation |
| Gemini | `gemini-embedding-001` | Embedding generation |
| Gemini Live | `gemini-3.1-flash-live-preview` | Native realtime voice |
| OpenAI | `gpt-4o-mini-tts` | Text-to-speech; recorded key scope `/v1/audio/speech` |
| Modulate | `velma-2-stt-streaming`, `velma-2-stt-batch` | Live and prerecorded transcription; recorded key limit 500 credits |

## Build, updates, and website

| Item | Recorded configuration |
| --- | --- |
| Signing identity | `Developer ID Application: Srujan Gowda (24D6NXS6H7)` |
| Codemagic workflows | `intentive-macos-release`, `intentive-macos-preview` |
| GitHub Release App | `intentive-release`; app ID `4838294`, installation ID `159216850` |
| Sparkle identity | Keychain account `heyintentive`; public-key SHA-256 `f9007cb82a319a6343cbcddd6707372c30c4e4984350a15e47e9e386a60076ab` |
| Update paths | Backend `/v2/desktop/appcast.xml`; Beta adds `?identity=beta`; manual download `/v2/desktop/download/latest` |
| Website source | `sruj75/intentive-tally-landing-page` |
| Website destinations | `https://heyintentive.com/`, `https://privacy.heyintentive.com/`, `https://terms.heyintentive.com/`, `https://support.heyintentive.com/` |

## Credential locations

| Store | Contents |
| --- | --- |
| GCP Secret Manager | Hosted Redis/Firebase/OAuth credentials and `GEMINI_API_KEY`, `OPENAI_API_KEY`, `MODULATE_API_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`. Deployment variables select exact secret versions. |
| GitHub Actions | Protected deployment variables and release credentials, including `CODEMAGIC_API_TOKEN` and Release App credentials |
| Codemagic `intentive_macos_signing` | Apple signing/notarization credentials, Firebase configuration, and PostHog inputs |
| Codemagic `intentive_macos_release` | Beta Firebase configuration, backend/update URLs, Sparkle keys, Sentry upload token, and Release App private key |
| Local development | Gitignored `backend/.env.local-dev` for explicit provider tests; Sparkle private key in the macOS login Keychain |

Configuration sources: [runtime manifest](backend/deploy/runtime_env.yaml),
[managed workloads](backend/utils/llm/model_config.py),
[desktop generation/embeddings](backend/routers/desktop_proxy.py),
[realtime voice](backend/routers/desktop_realtime.py),
[speech output](backend/routers/desktop_tts_updates.py),
[Langfuse prompts](backend/utils/observability/langfuse_prompts.py),
[Codemagic](codemagic.yaml), and [current repository guidance](openwiki/INSTRUCTIONS.md).
