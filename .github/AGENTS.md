# GitHub Workflow Agent Guide

These rules apply to GitHub Actions workflows and custom actions under `.github/`.

## CI/CD Deploy Safety

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
- Use immutable image tags for deploys. Build and push the short SHA tag, then deploy that exact tag.
- Development desktop-backend acceptance must stage `GCP_SERVICE_ACCOUNT` only in a mode-0600 runner file for Firebase probe signing, validate that its project matches `FIREBASE_AUTH_PROJECT_ID`, and delete it after the probe; never copy it into the image or deploy it as runtime configuration.
- Do not deploy Cloud Run services from an untagged image path; use `image:...:${SHORT_SHA}` so revisions show the source commit.
- Use `backend/scripts/deploy_status_report.py` as a strict gate on success paths; use it with `|| true` only after a primary rollout/traffic command already failed.
- Full backend deploys must derive one immutable canonical Cloud Run release
  vector and run `backend/scripts/verify_backend_release_vector.py` after
  traffic promotion; a mixed or partially applied serving vector must fail the
  workflow and emit evidence for a retry.
- Keep candidate health, no-traffic acceptance, traffic snapshot, promotion,
  serving verification, production smoke, and conditional restoration in that
  order inside the locked backend deploy job.
- Backend deploy workflows may only run Firestore index readiness with `--check-only` against `RUNTIME_GCP_PROJECT_ID`; run it in an isolated job from the approved commit with `GCP_FIRESTORE_READONLY_CREDENTIALS`, and bind manual deploys to the exact checked candidate SHA. This intentionally read-only credential must be set separately in both `development` and `prod` GitHub Environments. A failed gate may upload only a locally revalidated, bounded, redacted schema proposal artifact; Firestore index writes use the manual, main-scoped `gcp_firestore_indexes.yml` workflow and share the backend-stack lock.
- When editing workflows, keep `actionlint` coverage in CI so YAML and GitHub expression mistakes fail before merge.
