# Intentive

Intentive is a macOS second brain for conversations and activity you choose to
capture. The Mac owns durable product data such as conversations, Memories,
tasks, Chat history, Focus, Insights, and Rewind. Features that need managed AI
or transcription send selected inputs to the configured providers for transient
processing; they do not make the backend a second product-data authority.

This repository is under active development. Intentive for macOS is not
published. The existing [landing page](https://heyintentive.com) is live, but legal,
support, production backend, and update destinations still await owner approval
and configuration. The owned Intentive icon, mark, menu-bar art, sign-in backdrop,
and installer artwork are installed; provenance is recorded under `desktop/macos/`.

## Repository scope

| Component | Path | Current role |
|---|---|---|
| macOS app | [`desktop/macos/`](desktop/macos/) | SwiftUI app, local product stores, bundled TypeScript agent runtime |
| Backend | [`backend/`](backend/) | FastAPI authentication and transient managed-compute boundary |
| Windows snapshot | [`desktop/windows/`](desktop/windows/) | Retained upstream code; outside the Intentive macOS rebrand and release scope |

The retained managed-provider map is Gemini for text, embeddings, and realtime
voice; Modulate for live and prerecorded speech-to-text; OpenAI for text-to-speech
only; Langfuse for prompt management and model tracing; PostHog for optional
product analytics; and Sentry for diagnostics. Billing is disabled, so the app
makes no Dodo checkout or portal calls.

## Local development

Requirements include macOS 14+, Xcode, Python 3.11 with `uv`, Node 22, JDK 21,
ffmpeg, opus, and webp.

```bash
make setup
PROVIDER_MODE=offline make dev-up
make desktop-run-local DESKTOP_APP_NAME=omi-local
```

The offline lane uses hermetic provider fakes and an isolated named development
bundle. Managed development is an explicit alternative:

```bash
cd desktop/macos
OMI_APP_NAME=omi-local ./run.sh --yolo
```

`--yolo` targets the owned development backend; protected routes still require
the owned development Firebase identity. It is not an offline data sandbox and
must never be treated as production.

## Verification

```bash
desktop/macos/test.sh
backend/test.sh
make preflight
```

Use focused commands from the component guides while editing. The complete
component suites and repository preflight remain the acceptance boundary.

## Documentation

- [`PRODUCT.md`](PRODUCT.md) — current product and data-authority boundaries
- [`FORK.md`](FORK.md) — upstream provenance and current rebrand/release state
- [`OWNER-PROVIDER-DECISIONS.md`](OWNER-PROVIDER-DECISIONS.md) — approved owned identities and external blockers
- [`AGENTS.md`](AGENTS.md) — repository engineering rules
- [`desktop/macos/AGENTS.md`](desktop/macos/AGENTS.md) — macOS build, test, and named-bundle workflow
- [`backend/AGENTS.md`](backend/AGENTS.md) — backend setup, provider, and service contracts

## License

MIT. See [`LICENSE`](LICENSE) and retain the attribution recorded in
[`FORK.md`](FORK.md).
