from pathlib import Path
import sys
import os

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dev_harness import desktop_paths

pytestmark = pytest.mark.skipif(os.name == "nt", reason="macOS Applications directories")


def test_user_install_and_existing_system_install(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    assert desktop_paths.configured_app_path("omi-example", {}) == Path("/Applications/omi-example.app")
    assert desktop_paths.configured_app_path("omi-example", {"OMI_DEV_APP_ROOT": str(tmp_path / "Applications")}) == (
        tmp_path / "Applications/omi-example.app"
    )
    assert desktop_paths.dev_app_path("Omi Subagent Test!!").name == "Omi Subagent Test!!.app"


@pytest.mark.parametrize("name", ["Intentive Beta", "Omi", "omi-x/../../Omi", "omi-x\\Omi", "omi-x\nOmi"])
def test_production_and_path_escape_names_are_rejected(name):
    with pytest.raises(ValueError):
        desktop_paths.dev_app_path(name)


def test_foreign_home_and_redirected_app_root_are_rejected(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    with pytest.raises(ValueError):
        desktop_paths.dev_app_path("omi-example", root="/Users/someone-else/Applications")
    (tmp_path / "Applications").symlink_to("/Applications", target_is_directory=True)
    with pytest.raises(ValueError):
        desktop_paths.dev_app_path("omi-example", root=tmp_path / "Applications")
