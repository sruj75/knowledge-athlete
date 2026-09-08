from pathlib import Path
import sys
import os

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dev_harness import build_cache

pytestmark = pytest.mark.skipif(os.name == "nt", reason="macOS UID-scoped SwiftPM cache")


def worktree(path):
    package = path / "desktop/macos/Desktop"
    package.mkdir(parents=True)
    (package / "Package.swift").touch()
    return path


def test_each_worktree_has_its_own_cache_and_setup_is_repeatable(tmp_path):
    first, second = (worktree(tmp_path / name) for name in ("one", "two"))
    cache = tmp_path / "cache"
    target = build_cache.prepare(first, cache)
    (target / "built-output").write_text("retained")
    assert build_cache.prepare(first, cache) == target
    assert (first / "desktop/macos/Desktop/.build/built-output").read_text() == "retained"
    assert build_cache.prepare(second, cache) != target


def test_existing_build_and_unmounted_volume_are_preserved(tmp_path):
    repo = worktree(tmp_path / "repo")
    existing = repo / "desktop/macos/Desktop/.build"
    existing.mkdir()
    (existing / "keep").write_text("existing output")
    with pytest.raises(ValueError, match="preserved"):
        build_cache.prepare(repo, tmp_path / "cache")
    assert (existing / "keep").read_text() == "existing output"
    with pytest.raises(ValueError, match="mount"):
        build_cache.prepare(repo, tmp_path / "absent-volume/cache")
