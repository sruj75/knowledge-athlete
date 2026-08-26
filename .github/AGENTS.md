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
- Backend and Firestore workflows authenticate through environment-scoped Workload Identity Federation with separate deploy, read-only index, and create-only index-writer service accounts. Exact repository/name IDs, owner ID, `main`, GitHub environment, and workflow-ref policies come from `runtime_env.yaml`; do not restore JSON-key inputs.
- Build and push only the full commit-SHA Artifact Registry tag, capture its digest, smoke that published digest, and deploy the resulting `tag@sha256:...` identity. A short SHA is display-only for Cloud Run revision suffixes.
- Development backend acceptance obtains short-lived probe credentials without copying a service-account key into the image or runtime configuration.
- Use `backend/scripts/deploy_status_report.py` as a strict gate on success paths; use it with `|| true` only after a primary rollout/traffic command already failed.
- Full backend deploys must derive one immutable canonical Cloud Run release
  vector and run `backend/scripts/verify_backend_release_vector.py` after
  traffic promotion; a mixed or partially applied serving vector must fail the
  workflow and emit evidence for a retry.
- Keep candidate health, no-traffic acceptance, traffic snapshot, promotion,
  serving verification, production smoke, and conditional restoration in that
  order inside the locked backend deploy job.
- Backend deploy workflows may only run Firestore index readiness with `--check-only` against `RUNTIME_GCP_PROJECT_ID`; run it in an isolated job from the approved commit with `GCP_FIRESTORE_READONLY_SERVICE_ACCOUNT`, and bind manual deploys to the exact checked candidate SHA. A failed gate may upload only a locally revalidated, bounded, redacted schema proposal artifact; Firestore index writes use the separate `GCP_FIRESTORE_WRITER_SERVICE_ACCOUNT` in the manual, main-scoped `gcp_firestore_indexes.yml` workflow and share the backend-stack lock.
- `backend/deploy/runtime_env.yaml` owns Cloud Run shape and the redacted foundation contract. Both deploy workflows must consume its renderer outputs, take the stable `run.app` URL as an explicit environment input for fresh-service bootstrap, verify the discovered URL after deploy, and bind exact Secret Manager versions. The manual `foundation-readiness` mode is read-only describe/drift evidence; `artifact-cleanup-dry-run` never deletes. Resource existence is never inferred from the tracked declaration.
- When editing workflows, keep `actionlint` coverage in CI so YAML and GitHub expression mistakes fail before merge.
