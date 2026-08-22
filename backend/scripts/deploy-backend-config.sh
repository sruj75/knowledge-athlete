#!/usr/bin/env bash
# Apply the non-secret backend runtime configuration without exposing values.

set -euo pipefail

: "${ENVIRONMENT:?ENVIRONMENT must be set to dev or prod}"

required_config=(
  GOOGLE_CLIENT_ID
  REDIS_DB_HOST
)

if [[ "$ENVIRONMENT" == "prod" ]]; then
  required_config+=(
    ACCOUNT_DELETION_HANDLER_URL
    SYNC_TASKS_HANDLER_URL
    SYNC_TASKS_INVOKER_SA
  )
fi

missing=()
for name in "${required_config[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
done
if (( ${#missing[@]} > 0 )); then
  printf 'Missing required non-secret deployment variables: %s\n' "${missing[*]}" >&2
  exit 1
fi

namespace="${ENVIRONMENT}-omi-backend"
config_map="${ENVIRONMENT}-omi-backend-config"
env_file="$(mktemp)"
trap 'rm -f "$env_file"' EXIT

for name in "${required_config[@]}"; do
  printf '%s=%s\n' "$name" "${!name}" >> "$env_file"
done

kubectl -n "$namespace" create configmap "$config_map" \
  --from-env-file="$env_file" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Applied non-secret runtime ConfigMap ${namespace}/${config_map} (${#required_config[@]} keys)."
