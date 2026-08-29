from datetime import datetime, timezone
import hashlib
import json

import pytest

from utils.beta_breakglass_evidence import build_emergency_beta_manifest
from utils.qualified_beta_promotion import QualifiedBetaAdmissionError


TAG = "v0.12.99+12099-macos"
SOURCE_SHA = "a" * 40


class FakeEmergencyBetaReader:
    def __init__(self, *, bundle_id: str):
        self.payloads = {
            "Intentive.zip": b"intentive zip",
            "intentive.dmg": b"intentive dmg",
            "desktop-smoke-result.json": json.dumps(
                {
                    "ok": True,
                    "release_tag": TAG,
                    "expected_channel": "beta",
                    "bundle_id": bundle_id,
                    "checks": ["Signed desktop artifact smoke completed"],
                }
            ).encode(),
        }
        self.release_payload = {
            "tag_name": TAG,
            "draft": False,
            "prerelease": False,
            "published_at": "2026-07-21T12:00:00Z",
            "body": "<!-- KEY_VALUE_START\nedSignature: sparkle-signature\nKEY_VALUE_END -->",
            "assets": [self._asset(name, payload) for name, payload in self.payloads.items()],
        }

    @staticmethod
    def _url(name: str) -> str:
        return f"https://github.com/sruj75/knowledge-athlete/releases/download/{TAG}/{name}"

    @classmethod
    def _asset(cls, name: str, payload: bytes) -> dict[str, str]:
        return {
            "name": name,
            "browser_download_url": cls._url(name),
            "digest": "sha256:" + hashlib.sha256(payload).hexdigest(),
        }

    async def release(self, tag: str):
        assert tag == TAG
        return self.release_payload

    async def tag_sha(self, tag: str):
        assert tag == TAG
        return SOURCE_SHA

    async def is_merged_source(self, source_sha: str):
        assert source_sha == SOURCE_SHA
        return True

    async def download(self, url: str):
        name = url.rsplit("/", 1)[-1]
        return self.payloads[name]


@pytest.mark.asyncio
async def test_emergency_beta_builder_accepts_owned_intentive_smoke_evidence():
    manifest = await build_emergency_beta_manifest(
        TAG,
        reader=FakeEmergencyBetaReader(bundle_id="com.heyintentive.intentive"),
        now=datetime(2026, 7, 21, 12, 2, tzinfo=timezone.utc),
    )

    assert manifest["release_id"] == TAG
    assert manifest["qualification_tier"] == "emergency"
    assert manifest["qualification_passed"] is False


@pytest.mark.asyncio
async def test_emergency_beta_builder_rejects_inherited_omi_smoke_evidence():
    with pytest.raises(QualifiedBetaAdmissionError, match="does not bind the target"):
        await build_emergency_beta_manifest(
            TAG,
            reader=FakeEmergencyBetaReader(bundle_id="com.omi.computer-macos"),
            now=datetime(2026, 7, 21, 12, 2, tzinfo=timezone.utc),
        )
