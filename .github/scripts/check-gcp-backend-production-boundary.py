#!/usr/bin/env python3
"""Keep canonical production deploys rollback-first and single-service."""

from __future__ import annotations

from pathlib import Path

WORKFLOW = Path(".github/workflows/gcp_backend.yml")
CANDIDATE_PROBE = "Prove canonical candidate chat compatibility"
PROVIDER_PROBE = "Prove canonical candidate managed realtime provider paths"
TRAFFIC_SHIFT = "Shift Cloud Run traffic to validated revisions"
PROD_SMOKE = "Smoke promoted production serving API"
SERVING_VERIFY = "Verify serving backend release vector"
ROLLBACK_CONDITION = "steps.smoke-promoted-production-serving-api.outcome == 'failure'"
PROD_FORBIDDEN = (
    "probe-transcription-candidate-from-cloud-run.sh",
    "FIREBASE_PROBE_TOKEN",
    "identity_audience=",
    "deploy_targets:",
    "deploy_gateway:",
    "backend-sync",
    "helm upgrade",
    "kubectl ",
)


def validate(root: Path) -> list[str]:
    path = root / WORKFLOW
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    errors: list[str] = []
    if text.count('uses: google-github-actions/deploy-cloudrun@') != 1:
        errors.append('gcp_backend.yml must deploy exactly one canonical Cloud Run service')
    if text.count("resolve_cloud_run_tagged_url.py") != 1:
        errors.append("gcp_backend.yml must resolve exactly one canonical no-traffic candidate URL")
    for forbidden in PROD_FORBIDDEN:
        if forbidden in text:
            errors.append(f"gcp_backend.yml must not retain production candidate dependency {forbidden!r}")
    try:
        candidate_probe = text.index(CANDIDATE_PROBE)
        provider_probe = text.index(PROVIDER_PROBE)
        traffic_shift = text.index(TRAFFIC_SHIFT)
        serving_verify = text.index(SERVING_VERIFY)
        prod_smoke = text.index(PROD_SMOKE)
    except ValueError:
        errors.append("gcp_backend.yml must retain candidate probes, traffic promotion, and production serving smoke")
    else:
        if not candidate_probe < provider_probe < traffic_shift:
            errors.append("chat and provider candidate probes must pass before backend traffic promotion")
        if prod_smoke <= serving_verify:
            errors.append("production serving smoke must follow exact serving release-vector verification")
    for required in (
        "--tag=${{ env.CANDIDATE_TAG }}",
        "backend_candidate_probe.py",
        "voice-provider-probe.sh",
        "https://api.omi.me/v2/desktop/beta/candidates/reserve",
        '--data \'{"tag":"v0.0.0+1-macos"}\'',
        "schema-valid inert tag reaches the authorization wall",
        "--candidate-api-url https://api.omi.me",
        "umask 077",
        "firebase-production-serving-token",
        "trap 'rm -f \"$token_file\"' EXIT",
        ROLLBACK_CONDITION,
    ):
        if required not in text:
            errors.append(f"gcp_backend.yml is missing production serving-smoke guard {required!r}")
    if "--data '{}')" in text:
        errors.append("gcp_backend.yml must not use an invalid empty reservation body for the 401 smoke")
    smoke_text = text[text.find(PROD_SMOKE) :] if PROD_SMOKE in text else ""
    if "$GITHUB_OUTPUT" in smoke_text and "firebase-production-serving-token" in smoke_text:
        errors.append("production smoke token must not be written to GITHUB_OUTPUT")
    return errors


if __name__ == "__main__":
    raise SystemExit(1 if validate(Path(".")) else 0)
