import json
from pathlib import Path

from dev_harness import config, desktop_profile, synthetic_profiles


def _config(tmp_path: Path) -> config.HarnessConfig:
    return config.load_config(
        config.repo_root_from(Path.cwd()),
        env={"OMI_LOCAL_STATE_ROOT": str(tmp_path / "state"), "PROVIDER_MODE": "offline"},
        create_layout=True,
    )


def test_profile_manifest_is_neutral_and_contains_only_synthetic_identity(tmp_path: Path) -> None:
    cfg = _config(tmp_path)
    path = synthetic_profiles.initialize_manifest(cfg)
    payload = json.loads(path.read_text(encoding="utf-8"))

    assert payload["schema_version"] == 1
    assert payload["selected_user"] == "alice"
    assert [user["alias"] for user in payload["users"]] == ["local_default_user", "alice", "bob"]
    assert "memory" not in path.name.lower()
    assert "memory" not in json.dumps(payload).lower()


def test_desktop_profile_uses_neutral_manifest_credentials(tmp_path: Path) -> None:
    cfg = _config(tmp_path)
    synthetic_profiles.initialize_manifest(cfg)

    profile = desktop_profile.resolve_profile(
        cfg, user="alice", seeded_users=synthetic_profiles.profile_aliases(cfg), env={}
    )

    assert profile.selected_user == "alice"
    assert profile.selected_user_email == "alice@local.omi.invalid"
    assert profile.selected_user_display_name == "Synthetic Alice"
