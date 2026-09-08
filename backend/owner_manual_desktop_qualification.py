"""Runtime adapter for the canonical owner-manual qualification bundle contract."""

from __future__ import annotations

import importlib.util
from pathlib import Path

_production_source = Path(__file__).with_name("owner_manual_desktop_qualification_contract.py")
_source = (
    _production_source
    if _production_source.exists()
    else Path(__file__).resolve().parents[1] / ".github/scripts/owner_manual_desktop_qualification.py"
)
_spec = importlib.util.spec_from_file_location("owner_manual_desktop_qualification_contract", _source)
assert _spec is not None and _spec.loader is not None
_contract = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_contract)

MAX_BUNDLE_BYTES = _contract.MAX_BUNDLE_BYTES
REQUIRED_SMOKE_CHECKS = _contract.REQUIRED_SMOKE_CHECKS


def verify_bundle(
    payload: bytes,
    release_tag: str,
    source_sha: str,
    artifact_digests: dict[str, str],
) -> dict[str, object]:
    return _contract.verify_bundle(payload, release_tag, source_sha, artifact_digests)


def build_bundle(receipt_paths: dict[str, Path], output_dir: Path, release_tag: str, source_sha: str) -> Path:
    return _contract.build_bundle(receipt_paths, output_dir, release_tag, source_sha)
