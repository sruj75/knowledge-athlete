import importlib.util
import json
import os
import sys
from pathlib import Path
from subprocess import CompletedProcess


def _load_module():
    root = Path(__file__).resolve().parents[2]
    script_path = root / "scripts" / "product_capability_synthetics.py"
    spec = importlib.util.spec_from_file_location("product_capability_synthetics", script_path)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _config(module, **overrides):
    values = {
        "backend_url": None,
        "run_local_fixtures": False,
        "timeout_seconds": 1.0,
        "e2e_timeout": "1s",
    }
    values.update(overrides)
    return module.SyntheticConfig(**values)


def test_output_uses_required_status_vocabulary_and_json_formatting():
    module = _load_module()
    report = module.build_report(_config(module))

    decoded = json.loads(json.dumps(module.sanitize(report), sort_keys=True))

    assert decoded["suite"] == "intentive_product_capability_synthetics"
    assert decoded["status_vocabulary"] == ["FAIL", "NOT_RUN", "PASS", "SKIP_NO_CREDENTIALS"]
    assert {check["status"] for check in decoded["checks"]} <= set(decoded["status_vocabulary"])
    assert decoded["summary"]["NOT_RUN"] >= 2
    fixture_details = {
        check["name"]: check["details"] for check in decoded["checks"] if check["name"].endswith("_local_fixture")
    }
    assert "pytest_target" in fixture_details["account_deletion_local_fixture"]
    assert decoded["secret_safety"]["uses_production_credentials"] is False
    assert decoded["secret_safety"]["uses_production_user_data"] is False


def test_missing_backend_url_skips_network_only_checks_without_credentials():
    module = _load_module()
    config = _config(module, backend_url=None)

    health_status, health_summary, health_details = module.backend_health_check(config)

    assert health_status == "NOT_RUN"
    assert "/v1/health" in health_details["traced_route"]
    assert "backend" in health_summary.lower()


def test_redaction_masks_tokens_and_secret_fields():
    module = _load_module()
    payload = {
        "authorization": "Bearer intentive_oat_rawsecretvalue",
        "message": "sk-test-not-real and client_secret=super-secret and token:abc123",
        "nested": ["api_key=fake-provider-key"],
    }

    redacted = module.sanitize(payload)

    encoded = json.dumps(redacted)
    assert "rawsecretvalue" not in encoded
    assert "sk-test-not-real" not in encoded
    assert "super-secret" not in encoded
    assert "abc123" not in encoded
    assert "fake-provider-key" not in encoded
    assert "[REDACTED]" in encoded


def test_failing_check_sets_overall_failure(monkeypatch):
    module = _load_module()
    config = _config(module, backend_url="http://synthetic.invalid")

    monkeypatch.setattr(
        module,
        "backend_health_check",
        lambda _config: ("FAIL", "health failed", {"body": "Bearer intentive_mcp_should_not_leak"}),
    )
    monkeypatch.setattr(
        module,
        "account_deletion_fixture_check",
        lambda _config: ("NOT_RUN", "disabled", {}),
    )
    report = module.build_report(config)
    encoded = json.dumps(report)

    assert report["status"] == "FAIL"
    assert report["summary"]["FAIL"] == 1
    assert "should_not_leak" not in encoded
    assert "[REDACTED]" in encoded


def test_local_fixture_check_uses_pytest_selection_supported_by_runner(monkeypatch):
    module = _load_module()
    captured = {}

    def fake_run(command, **kwargs):
        captured["command"] = command
        captured["env"] = kwargs["env"]
        return CompletedProcess(command, 0, stdout="selected fixture passed\n")

    monkeypatch.setattr(module.subprocess, "run", fake_run)

    status, summary, details = module.account_deletion_fixture_check(
        _config(module, run_local_fixtures=True, timeout_seconds=1.0, e2e_timeout="7s")
    )

    assert status == "PASS"
    assert "hermetic e2e harness" in summary
    assert captured["command"][-2:] == [
        "-k",
        "test_account_deletion_cloud_task_completes_once_and_redelivery_is_acked",
    ]
    assert captured["env"]["E2E_PYTEST_TIMEOUT"] == "7s"
    assert details["pytest_target"].endswith(
        "::test_account_deletion_cloud_task_completes_once_and_redelivery_is_acked"
    )
