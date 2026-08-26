"""Coverage for the shared dev-only capture adapter used beyond listen."""

import base64
import json
from pathlib import Path
from unittest.mock import patch

import yaml

from testing.parity_pack_v0.live_capture import SurfaceParityCapture


BACKEND_ROOT = Path(__file__).resolve().parents[2]
REPOSITORY_ROOT = BACKEND_ROOT.parent
LOCAL_PARITY_SETTINGS = {
    "OMI_PARITY_PACK_ALLOWED_PRINCIPALS",
    "OMI_PARITY_PACK_CAPTURE",
    "OMI_PARITY_PACK_ROOT",
}


def _env(root):
    return {
        "OMI_ENV_STAGE": "dev",
        "OMI_PARITY_PACK_CAPTURE": "1",
        "OMI_PARITY_PACK_ALLOWED_PRINCIPALS": "allowed-user",
        "OMI_PARITY_PACK_ROOT": str(root),
    }


def _capture(root, *, principal_id="allowed-user"):
    return SurfaceParityCapture.from_environ(
        principal_id=principal_id,
        session_id="surface-session",
        surface="ptt",
        source="desktop_ptt_http",
        provider_lane="deepgram",
        route_or_model="deepgram-nova-3",
        request={"audio_bytes": 20},
        environ=_env(root),
    )


def test_surface_capture_persists_discriminators_and_redacts_text_payloads(tmp_path):
    capture = _capture(tmp_path)

    capture.observe(
        "client",
        {"type": "ptt_audio", "email": "dogfood@example.com", "token": "do-not-keep"},
    )
    capture.persist()

    cassette = json.loads(next((tmp_path / "cassettes").glob("*.json")).read_text())
    assert cassette["surface"] == "ptt"
    assert cassette["source"] == "desktop_ptt_http"
    assert cassette["identity"]["anon_session"] != "allowed-user"
    assert cassette["events"][0]["payload"]["email"] == "[REDACTED_EMAIL]"
    assert cassette["events"][0]["payload"]["token"] == "[REDACTED]"


def test_surface_capture_preserves_binary_audio_encoding_and_denies_non_allowlisted_users(tmp_path):
    allowed = _capture(tmp_path)
    audio = b"12345678901234567890"
    allowed.observe_audio("client", audio)
    allowed.persist()

    cassette = json.loads(next((tmp_path / "cassettes").glob("*.json")).read_text())
    assert cassette["events"][0]["payload"]["audio_b64"] == base64.b64encode(audio).decode("ascii")

    denied = _capture(tmp_path / "denied", principal_id="not-allowlisted")
    denied.observe("client", {"must": "not-persist"})
    denied.persist()
    assert not (tmp_path / "denied" / "cassettes").exists()


def test_surface_capture_stays_local_when_legacy_gcs_settings_are_present(tmp_path, monkeypatch):
    environ = _env(tmp_path)
    environ.update(
        {
            "OMI_PARITY_PACK_GCS_URI": "gs://retired-parity-pack/parity/v0",
            "OMI_PARITY_PACK_GCS_BUCKET": "retired-parity-pack",
            "OMI_PARITY_PACK_GCS_PREFIX": "parity/v0",
            "OMI_PARITY_PACK_EXPORT_INTERVAL_SECONDS": "1",
        }
    )
    for setting, value in environ.items():
        monkeypatch.setenv(setting, value)
    capture = SurfaceParityCapture.from_environ(
        principal_id="allowed-user",
        session_id="surface-session",
        surface="ptt",
        source="desktop_ptt_http",
        provider_lane="deepgram",
        route_or_model="deepgram-nova-3",
        request={"audio_bytes": 20},
        environ=environ,
    )
    capture.observe("client", {"type": "ptt_audio"})

    with patch("google.cloud.storage.Client") as storage_client:
        capture.persist()

    storage_client.assert_not_called()
    assert len(list((tmp_path / "cassettes").glob("*.json"))) == 1


def test_runtime_and_deployment_classification_retain_only_local_parity_settings():
    runtime = yaml.safe_load((BACKEND_ROOT / "deploy/runtime_env.yaml").read_text(encoding="utf-8"))
    runtime_settings = set(runtime["environments"]["dev"]["cloud_run"]["services"]["backend"]["env"])
    classified = json.loads(
        (REPOSITORY_ROOT / "config/deployment-setting-classification.json").read_text(encoding="utf-8")
    )
    classified_settings = set(classified["kinds"]["config"])

    assert {setting for setting in runtime_settings if setting.startswith("OMI_PARITY_PACK_")} == LOCAL_PARITY_SETTINGS
    assert {
        setting for setting in classified_settings if setting.startswith("OMI_PARITY_PACK_")
    } == LOCAL_PARITY_SETTINGS
