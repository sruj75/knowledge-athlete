# Intentive backend

The backend is Intentive's authenticated transient-compute boundary. It serves
the retained REST and WebSocket APIs without becoming the durable authority for
macOS conversations, Memories, tasks, Chat history, Focus, Insights, or Rewind.
Those product records remain in owner-scoped storage on the Mac.

Read [`AGENTS.md`](AGENTS.md) before changing backend code. It is the current
authority for environment stages, async rules, service boundaries, logging,
providers, and tests.

## Quick start

From the repository root:

```bash
make setup
PROVIDER_MODE=offline make dev-up
```

The offline stage runs the Firebase/Firestore emulators, local Redis, and shared
hermetic provider fakes. It does not require managed-provider credentials.

To serve only this component with an already prepared environment:

```bash
cd backend
./scripts/dev-serve.sh
```

Environment stages are `local`, `offline`, `dev`, and `prod`. Use the matching
untracked environment file; do not commit credentials. Hosted development and
production use the Cloud Run runtime service account through Application Default
Credentials and reject committed or runtime credential files.

## Retained providers

- Google Gemini: managed text, embeddings, and realtime voice
- Modulate: live and prerecorded speech-to-text
- OpenAI: `gpt-4o-mini-tts` text-to-speech only
- Langfuse: fail-open prompt management and model tracing
- Firebase: authentication and minimal retained account data
- Redis: ephemeral coordination
- Dodo Payments: disabled unless an operator explicitly selects and configures a billing mode

Normal Chat must not route through Anthropic, Artificial Analysis, Vertex model
inference, or OpenAI text/realtime APIs.

## Verification

```bash
cd backend
bash test-preflight.sh
./test.sh
```

The canonical hosted shape is one environment-owned Cloud Run backend in
`us-west1`. The tracked runtime manifest and workflows describe that shape; they
do not prove that a production service or its secrets exist, and running tests
does not authorize a deployment.
