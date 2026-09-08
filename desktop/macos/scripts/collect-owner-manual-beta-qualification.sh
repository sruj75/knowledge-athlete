#!/usr/bin/env bash
# Collect exact signed-candidate and source-built evidence without publishing it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONTRACT="$REPO_ROOT/.github/scripts/owner_manual_desktop_qualification.py"
CANDIDATE_GATE="$REPO_ROOT/.github/scripts/check-desktop-auto-beta-candidate.py"
RELEASE_REPOSITORY="sruj75/knowledge-athlete"
OWNER_ID=120443863

usage() {
  cat <<'USAGE'
Usage: collect-owner-manual-beta-qualification.sh [--prepared-stage DIR --source-sha SHA] --output-directory DIR <vX.Y.Z+BUILD-macos>

Normal mode downloads the exact published candidate, runs local signed Stable/Beta
smoke plus post-candidate readiness/T2/fault gates, and emits one content-addressed
ZIP. It never uploads or promotes. --prepared-stage packages an already-produced
fixture stage through the same public evidence verifier.
USAGE
}

PREPARED_STAGE=""
PROVIDED_SOURCE_SHA=""
OUTPUT_DIRECTORY=""
RELEASE_TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepared-stage) PREPARED_STAGE="${2:?}"; shift 2 ;;
    --source-sha) PROVIDED_SOURCE_SHA="${2:?}"; shift 2 ;;
    --output-directory) OUTPUT_DIRECTORY="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) [[ -z "$RELEASE_TAG" ]] || { echo "unexpected extra argument: $1" >&2; exit 2; }; RELEASE_TAG="$1"; shift ;;
  esac
done
[[ -n "$RELEASE_TAG" && -n "$OUTPUT_DIRECTORY" ]] || { usage >&2; exit 2; }

if [[ -n "$PREPARED_STAGE" ]]; then
  [[ "$PROVIDED_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || {
    echo "--prepared-stage requires --source-sha with 40 lowercase hex" >&2
    exit 2
  }
  SOURCE_SHA="$PROVIDED_SOURCE_SHA"
  STAGE="$PREPARED_STAGE"
else
  [[ -z "$PROVIDED_SOURCE_SHA" ]] || { echo "--source-sha is only valid with --prepared-stage" >&2; exit 2; }
  SOURCE_SHA="$(git -C "$REPO_ROOT" rev-parse "$RELEASE_TAG^{commit}")"
  [[ "$SOURCE_SHA" == "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]] || {
    echo "collector requires an exact-tag checkout: $RELEASE_TAG" >&2
    exit 1
  }
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || {
    echo "collector requires a clean exact-tag checkout" >&2
    exit 1
  }
  [[ "$(uname -s)" == Darwin ]] || { echo "owner-manual collection requires macOS" >&2; exit 1; }
  command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }
  for name in OMI_SIGNED_ARTIFACT_SMOKE_TEAM_ID INTENTIVE_STABLE_FEED_URL INTENTIVE_BETA_FEED_URL \
    INTENTIVE_MANUAL_DOWNLOAD_URL INTENTIVE_PRODUCTION_API_URL POSTHOG_PROJECT_API_KEY POSTHOG_HOST \
    INTENTIVE_PRODUCT_URL INTENTIVE_TERMS_URL INTENTIVE_PRIVACY_URL INTENTIVE_SUPPORT_URL; do
    [[ -n "${!name:-}" ]] || { echo "$name is required" >&2; exit 1; }
  done
  STAGE="$(mktemp -d "${TMPDIR:-/tmp}/intentive-owner-manual.XXXXXX")"
  cleanup_stage() {
    local status=$?
    trap - EXIT
    if [[ $status -eq 0 ]]; then
      rm -rf -- "$STAGE"
    else
      echo "Owner-manual qualification failed; retained scoped evidence at $STAGE" >&2
    fi
    exit "$status"
  }
  trap cleanup_stage EXIT
  chmod 700 "$STAGE"
  mkdir "$STAGE/assets"
  gh release view "$RELEASE_TAG" --repo "$RELEASE_REPOSITORY" \
    --json tagName,body,isDraft,isPrerelease,publishedAt,assets > "$STAGE/release.json"
  gh release download "$RELEASE_TAG" --repo "$RELEASE_REPOSITORY" --dir "$STAGE/assets" \
    --pattern Intentive.zip --pattern intentive.dmg --pattern Intentive.Beta.zip --pattern intentive-beta.dmg
  gh release download "$RELEASE_TAG" --repo "$RELEASE_REPOSITORY" --dir "$STAGE" \
    --pattern desktop-smoke-result.json --pattern desktop-smoke-result-beta.json
  cp "$STAGE/desktop-smoke-result.json" "$STAGE/provider-smoke-stable.json"
  cp "$STAGE/desktop-smoke-result-beta.json" "$STAGE/provider-smoke-beta.json"

  record_command() {
    python3 "$CONTRACT" record-command \
      --ledger "$STAGE/command-ledger.json" --release-tag "$RELEASE_TAG" --source-sha "$SOURCE_SHA" "$@"
  }

  LATEST_TAG="$(git -C "$REPO_ROOT" for-each-ref --count=1 --sort=-v:refname --format='%(refname:strip=2)' 'refs/tags/v*-macos')"
  record_command --label candidate-gate --receipt "candidate-gate.json=$STAGE/candidate-gate.json" -- \
    python3 "$CANDIDATE_GATE" \
      --qualification-mode owner-manual \
      --release-json "$STAGE/release.json" \
      --smoke-result "$STAGE/provider-smoke-stable.json" \
      --beta-smoke-result "$STAGE/provider-smoke-beta.json" \
      --release-tag "$RELEASE_TAG" --latest-tag "$LATEST_TAG" \
      --tag-sha "$SOURCE_SHA" --checkout-sha "$SOURCE_SHA" \
      --expected-team-id "$OMI_SIGNED_ARTIFACT_SMOKE_TEAM_ID" \
      --output "$STAGE/candidate-gate.json"

  common_smoke=(
    --tag "$RELEASE_TAG" --source-sha "$SOURCE_SHA" --expected-channel beta
    --expected-manual-download-url "$INTENTIVE_MANUAL_DOWNLOAD_URL"
    --expected-releases-url "https://github.com/$RELEASE_REPOSITORY/releases"
    --expected-python-api-url "$INTENTIVE_PRODUCTION_API_URL"
    --expected-posthog-project-token "$POSTHOG_PROJECT_API_KEY"
    --expected-posthog-host "${POSTHOG_HOST%/}"
    --expected-product-url "$INTENTIVE_PRODUCT_URL" --expected-terms-url "$INTENTIVE_TERMS_URL"
    --expected-privacy-url "$INTENTIVE_PRIVACY_URL" --expected-support-url "$INTENTIVE_SUPPORT_URL"
    --launch --auth-storage-canary --notification-callback-canary --timeout 90
  )
  OMI_SIGNED_ARTIFACT_SMOKE_ALLOW_PRODUCTION_LAUNCH=1 record_command \
    --label stable-signed-smoke --receipt "owner-smoke-stable.json=$STAGE/owner-smoke-stable.json" -- \
    "$SCRIPT_DIR/smoke-signed-desktop-artifact.sh" \
      --zip "$STAGE/assets/Intentive.zip" --dmg "$STAGE/assets/intentive.dmg" \
      --expected-bundle-id com.heyintentive.intentive --expected-url-scheme heyintentive \
      --expected-feed-url "$INTENTIVE_STABLE_FEED_URL" "${common_smoke[@]}" \
      --result-json "$STAGE/owner-smoke-stable.json"
  OMI_SIGNED_ARTIFACT_SMOKE_ALLOW_PRODUCTION_LAUNCH=1 record_command \
    --label beta-signed-smoke --receipt "owner-smoke-beta.json=$STAGE/owner-smoke-beta.json" -- \
    "$SCRIPT_DIR/smoke-signed-desktop-artifact.sh" \
      --zip "$STAGE/assets/Intentive.Beta.zip" --dmg "$STAGE/assets/intentive-beta.dmg" \
      --expected-bundle-id com.heyintentive.intentive.beta --expected-url-scheme heyintentive-beta \
      --expected-feed-url "$INTENTIVE_BETA_FEED_URL" "${common_smoke[@]}" \
      --result-json "$STAGE/owner-smoke-beta.json"

  OMI_READINESS_LANE=local record_command \
    --label pre-tag-readiness --receipt "pre-tag-readiness.json=$STAGE/pre-tag-readiness.json" -- \
    "$SCRIPT_DIR/pre-tag-readiness.sh" --source-repository "$REPO_ROOT" \
      --evidence "$STAGE/pre-tag-readiness.json" "$SOURCE_SHA"
  record_command --label source-qualification \
    --receipt "source-t2-manifest.json=$STAGE/source-t2-manifest.json" \
    --receipt "fault-manifest.json=$STAGE/fault-manifest.json" -- \
    "$SCRIPT_DIR/qualify-desktop-beta.sh" --automatic \
      --signed-smoke-result "$STAGE/provider-smoke-stable.json" \
      --candidate-gate-result "$STAGE/candidate-gate.json" \
      --local-evidence-directory "$STAGE" "$RELEASE_TAG"
  curl -fsS --max-time 15 "${INTENTIVE_PRODUCTION_API_URL%/}/v1/health" > "$STAGE/backend-health.json"
  curl -fsS --max-time 15 "${INTENTIVE_PRODUCTION_API_URL%/}/" > "$STAGE/backend-root.json"
  record_command --label backend-compatibility \
    --receipt "backend-compatibility.json=$STAGE/backend-compatibility.json" -- \
    python3 "$CONTRACT" verify-backend-compatibility \
      --backend-contract-source "$REPO_ROOT/backend/routers/desktop_core.py" \
      --process-health "$STAGE/backend-health.json" --root-health "$STAGE/backend-root.json" \
      --output "$STAGE/backend-compatibility.json"
fi

receipt_args=()
for name in release.json candidate-gate.json provider-smoke-stable.json provider-smoke-beta.json owner-smoke-stable.json \
  owner-smoke-beta.json pre-tag-readiness.json source-t2-manifest.json fault-manifest.json \
  backend-compatibility.json command-ledger.json; do
  receipt_args+=(--receipt "$name=$STAGE/$name")
done
python3 "$CONTRACT" build --release-tag "$RELEASE_TAG" --source-sha "$SOURCE_SHA" \
  --output-directory "$OUTPUT_DIRECTORY" "${receipt_args[@]}"
echo "Owner upload is a separate explicit step; require uploader sruj75/$OWNER_ID and never replace the asset." >&2
