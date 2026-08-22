# S-25 callerless LLM-gateway handoff

S-22 removed every application import/client/auto-lane call and the unread
`llm_gateway_attempts` writer. The retained Python workloads now resolve one explicit
provider/model in `backend/utils/llm/model_config.py` and construct that provider in
process. `backend/tests/unit/test_managed_model_workloads.py` is the zero-application-
caller guard.

S-25 owns deleting the remaining separately deployable topology. S-22 did not deploy,
change traffic, or mutate cloud resources.

## Repository source and runtime image

- `backend/llm_gateway/**`
- the `llm-gateway` entry in `backend/runtime_images.json`
- `.github/workflows/backend-unit-tests.yml` gateway test lane
- `backend/testing/replay_harness_llm_gateway_fake_upstream/**`
- `backend/testing/replay_harness_llm_streaming_wire_fidelity/**`
- gateway cases in `backend/testing/workflow_contracts.json`
- `backend/tests/unit/test_llm_gateway_*.py`
- `backend/tests/unit/test_gateway_*.py` that remain after S-22 application-client deletion

## Deploy manifests, charts, and credentials

- `backend/charts/llm-gateway/**`
- the `llm_gateway` sections and `OMI_LLM_GATEWAY_*` projections in
  `backend/deploy/runtime_env.yaml`
- the residual `OMI_LLM_GATEWAY_*` entries in
  `backend/charts/backend-listen/dev_omi_backend_listen_values.yaml` and
  `backend/charts/backend-listen/prod_omi_backend_listen_values.yaml`
- the `OMI_LLM_GATEWAY_SERVICE_TOKEN` entries in
  `backend/charts/backend-secrets/dev_omi_backend_secrets_values.yaml` and
  `backend/charts/backend-secrets/prod_omi_backend_secrets_values.yaml`

## Workflows and deploy-control scripts

- `.github/workflows/gcp_llm_gateway.yml`
- gateway jobs/steps in `.github/workflows/gcp_backend.yml`
- gateway jobs/steps in `.github/workflows/gcp_backend_auto_dev.yml`
- gateway mode in `.github/workflows/gcp_backend_pusher.yml`
- `backend/scripts/deploy-llm-gateway.sh`
- `backend/scripts/dev-serve-llm-gateway.sh`
- `backend/scripts/probe-llm-gateway-from-cloud-run.sh`
- `backend/scripts/smoke-llm-gateway.py`
- `backend/scripts/smoke-llm-gateway-openai-schemas.py`
- `backend/scripts/validate-llm-gateway-env.py`
- `backend/scripts/verify-llm-gateway-serving.py`
- gateway branches in `backend/scripts/validate-backend-runtime-env.py`,
  `backend/scripts/validate_rendered_deployment_contract.py`, and
  `backend/scripts/deploy_status_report.py`

## Named live resources requiring S-25 read-only inventory before deletion

The checked-in names are:

- Helm releases `dev-omi-llm-gateway` and `prod-omi-llm-gateway`;
- Kubernetes services/ingresses with those release names in namespaces
  `dev-omi-backend` and `prod-omi-backend`;
- reserved addresses `dev-llm-gateway-ilb-ip-address` and the production address
  resolved by `backend/deploy/runtime_env.yaml`;
- images `gcr.io/<project>/llm-gateway:<sha>`;
- Secret Manager secret `OMI_LLM_GATEWAY_SERVICE_TOKEN` and its mirrored Kubernetes
  secret keys;
- Cloud Run probe jobs/pods and gateway smoke pods created by the workflows above;
- VPC/ILB attachment, traffic, monitoring, and alert resources referenced by the deploy
  control scripts and live cloud configuration.

Repository names are not proof that a live resource exists. S-25 must inventory the
actual dev/prod resources before deleting them and must retarget any surviving consumer
before removal.
