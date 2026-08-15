"""Regeneration hints must name the retained app-client surface."""

import importlib.util
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "export_openapi.py"
_spec = importlib.util.spec_from_file_location("export_openapi_under_test", SCRIPT)
assert _spec is not None and _spec.loader is not None
export_openapi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(export_openapi)


def test_hint_names_app_client_surface_and_path():
    path = export_openapi.default_spec_path()
    hint = export_openapi.regenerate_hint(path)

    assert "--surface app-client" in hint
    assert str(path) in hint


def test_missing_and_stale_errors_carry_app_client_surface(tmp_path):
    path = tmp_path / "contract.json"

    with pytest.raises(export_openapi.OpenAPIContractError) as missing:
        export_openapi.check_spec(path, "{}\n")
    assert "--surface app-client" in str(missing.value)

    path.write_text("{}\n")
    with pytest.raises(export_openapi.OpenAPIContractError) as stale:
        export_openapi.check_spec(path, '{"different": true}\n')
    assert "--surface app-client" in str(stale.value)
