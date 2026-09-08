#!/usr/bin/env python3
"""Workflow contracts for owner-manual macOS Beta qualification."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RELEASE_TAG = "v0.12.99+12099-macos"
TARGET_SHA = "a" * 40
OWNER_EVIDENCE_ASSET = f"owner-manual-qualification-{TARGET_SHA}-{'b' * 64}.zip"


class DesktopReleaseFlowContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = (ROOT / ".github/workflows/desktop_qualify_beta.yml").read_text(encoding="utf-8")
        self.auto_release = (ROOT / ".github/workflows/desktop_auto_release.yml").read_text(encoding="utf-8")
        self.retry = (ROOT / ".github/workflows/desktop_retry_beta_qualification.yml").read_text(encoding="utf-8")
        self.preview_workflow = (ROOT / ".github/workflows/desktop_publish_preview.yml").read_text(encoding="utf-8")

    @staticmethod
    def _named_step(workflow: str, name: str) -> str:
        marker = f"      - name: {name}\n"
        if workflow.count(marker) != 1:
            raise AssertionError(f"expected exactly one workflow step {name!r}")
        tail = workflow.split(marker, 1)[1].split("\n      - ", 1)[0]
        return re.split(r"\n  [A-Za-z0-9_-]+:\n", tail, maxsplit=1)[0]

    def _workflow_script(self, name: str) -> str:
        step = self._named_step(self.workflow, name)
        script = step.split("        run: |\n", 1)[1]
        return "\n".join(line[10:] if line.startswith("          ") else line for line in script.splitlines())

    def _run_workflow_script(
        self,
        name: str,
        *,
        cwd: Path,
        env: dict[str, str],
    ) -> subprocess.CompletedProcess[str]:
        isolated_env = {key: value for key, value in env.items() if not key.startswith("GIT_")}
        return subprocess.run(
            ["bash", "-c", self._workflow_script(name)],
            cwd=cwd,
            env=isolated_env,
            check=False,
            capture_output=True,
            text=True,
        )

    @staticmethod
    def _release_payload(*, duplicate_owner_evidence: bool = False) -> dict[str, object]:
        names = [
            "Intentive.zip",
            "intentive.dmg",
            "Intentive.Beta.zip",
            "intentive-beta.dmg",
            "desktop-smoke-result.json",
            "desktop-smoke-result-beta.json",
            OWNER_EVIDENCE_ASSET,
        ]
        if duplicate_owner_evidence:
            names.append(OWNER_EVIDENCE_ASSET)
        return {
            "id": 731,
            "tag_name": RELEASE_TAG,
            "body": "immutable candidate",
            "draft": False,
            "prerelease": False,
            "published_at": "2026-09-08T12:00:00Z",
            "assets": [
                {
                    "id": index,
                    "name": name,
                    "created_at": "2026-09-08T12:05:00Z",
                    "digest": f"sha256:{'b' * 64}" if name == OWNER_EVIDENCE_ASSET else f"sha256:{index:064x}",
                    "browser_download_url": f"https://github.com/sruj75/knowledge-athlete/releases/download/{RELEASE_TAG}/{name}",
                    "uploader": {"login": "sruj75", "id": 120443863},
                }
                for index, name in enumerate(names, start=1)
            ],
        }

    @staticmethod
    def _install_fake_gh(root: Path, release: dict[str, object]) -> tuple[Path, dict[str, str]]:
        bin_dir = root / "bin"
        bin_dir.mkdir()
        release_path = root / "release-rest-fixture.json"
        release_path.write_text(json.dumps(release), encoding="utf-8")
        upload_log = root / "release-upload.json"
        gh = bin_dir / "gh"
        gh.write_text(
            """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
if args and args[0] == "api":
    print(Path(os.environ["FAKE_RELEASE_JSON"]).read_text(encoding="utf-8"))
elif args[:2] == ["release", "download"]:
    pattern = args[args.index("--pattern") + 1]
    destination = Path(args[args.index("--dir") + 1])
    destination.mkdir(parents=True, exist_ok=True)
    (destination / pattern).write_bytes(("download:" + pattern).encode())
elif args[:2] == ["release", "view"]:
    print(os.environ.get("FAKE_EXISTING_QUALIFICATION_COUNT", "0"))
elif args[:2] == ["release", "upload"]:
    Path(os.environ["FAKE_UPLOAD_LOG"]).write_text(json.dumps(args), encoding="utf-8")
else:
    raise SystemExit("unexpected fake gh invocation: " + repr(args))
""",
            encoding="utf-8",
        )
        gh.chmod(0o755)
        return bin_dir, {
            "FAKE_RELEASE_JSON": str(release_path),
            "FAKE_UPLOAD_LOG": str(upload_log),
            "FAKE_EXISTING_QUALIFICATION_COUNT": "0",
        }

    def test_static_tripwire_owner_manual_qualification_never_targets_a_mac_runner(self) -> None:
        self.assertIn("runs-on: ubuntu-latest", self.workflow)
        self.assertIn("environment: beta", self.workflow)
        self.assertIn("owner_evidence_asset:", self.workflow)
        for forbidden in ("self-hosted", "intentive-qual-m1-studio", "qualify-m1-studio", "codemagic-lane"):
            self.assertNotIn(forbidden, self.workflow)

    def test_owner_dispatch_executes_with_exact_identity_and_rejects_a_different_actor(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            owner_env = {
                **os.environ,
                "ACTOR": "sruj75",
                "ACTOR_ID": "120443863",
                "REPOSITORY_OWNER": "sruj75",
                "REPOSITORY_OWNER_ID": "120443863",
                "TRIGGERING_ACTOR": "sruj75",
            }
            accepted = self._run_workflow_script(
                "Require exact repository owner dispatch",
                cwd=root,
                env=owner_env,
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            rejected = self._run_workflow_script(
                "Require exact repository owner dispatch",
                cwd=root,
                env={**owner_env, "ACTOR": "invited-friend"},
            )
            self.assertNotEqual(rejected.returncode, 0)

    def test_static_tripwire_owner_dispatch_precedes_candidate_access(self) -> None:
        owner = self._named_step(self.workflow, "Require exact repository owner dispatch")
        for fragment in (
            "ACTOR: ${{ github.actor }}",
            "ACTOR_ID: ${{ github.actor_id }}",
            "REPOSITORY_OWNER_ID: ${{ github.repository_owner_id }}",
            "TRIGGERING_ACTOR: ${{ github.triggering_actor }}",
            'test "$ACTOR" = sruj75',
            'test "$ACTOR_ID" = 120443863',
            'test "$REPOSITORY_OWNER_ID" = 120443863',
            'test "$TRIGGERING_ACTOR" = sruj75',
        ):
            self.assertIn(fragment, owner)
        self.assertLess(
            self.workflow.index("Require exact repository owner dispatch"),
            self.workflow.index("Checkout exact candidate tag"),
        )

    def test_release_download_executes_for_one_exact_owner_asset_and_rejects_ambiguity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir, fake_env = self._install_fake_gh(root, self._release_payload())
            stage = root / "stage"
            env = {
                **os.environ,
                **fake_env,
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "GH_TOKEN": "fixture-token",
                "OWNER_EVIDENCE_ASSET": OWNER_EVIDENCE_ASSET,
                "RELEASE_TAG": RELEASE_TAG,
                "REPO": "sruj75/knowledge-athlete",
                "STAGE": str(stage),
            }
            accepted = self._run_workflow_script(
                "Fetch exact release bytes and owner evidence",
                cwd=root,
                env=env,
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            for name in ("Intentive.zip", "intentive.dmg", "Intentive.Beta.zip", "intentive-beta.dmg"):
                self.assertTrue((stage / "assets" / name).is_file())
            self.assertTrue((stage / OWNER_EVIDENCE_ASSET).is_file())

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir, fake_env = self._install_fake_gh(root, self._release_payload(duplicate_owner_evidence=True))
            rejected = self._run_workflow_script(
                "Fetch exact release bytes and owner evidence",
                cwd=root,
                env={
                    **os.environ,
                    **fake_env,
                    "PATH": f"{bin_dir}:{os.environ['PATH']}",
                    "GH_TOKEN": "fixture-token",
                    "OWNER_EVIDENCE_ASSET": OWNER_EVIDENCE_ASSET,
                    "RELEASE_TAG": RELEASE_TAG,
                    "REPO": "sruj75/knowledge-athlete",
                    "STAGE": str(root / "stage"),
                },
            )
            self.assertNotEqual(rejected.returncode, 0)

    def test_evidence_publication_executes_once_and_rejects_an_existing_asset(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir, fake_env = self._install_fake_gh(root, self._release_payload())
            stage = root / "stage"
            stage.mkdir()
            (stage / "qualification-evidence.json").write_text('{"passed":true}\n', encoding="utf-8")
            output = root / "github-output"
            env = {
                **os.environ,
                **fake_env,
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "GH_TOKEN": "fixture-app-token",
                "GITHUB_OUTPUT": str(output),
                "RELEASE_TAG": RELEASE_TAG,
                "REPO": "sruj75/knowledge-athlete",
                "STAGE": str(stage),
                "TARGET_SHA": TARGET_SHA,
            }
            accepted = self._run_workflow_script("Attach immutable qualification evidence", cwd=root, env=env)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            upload = json.loads(Path(fake_env["FAKE_UPLOAD_LOG"]).read_text(encoding="utf-8"))
            self.assertEqual(upload[:4], ["release", "upload", RELEASE_TAG, "--repo"])
            self.assertIn(f"qualification-evidence-{TARGET_SHA}-", upload[-1])
            self.assertEqual(output.read_text(encoding="utf-8"), "qualified=true\n")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir, fake_env = self._install_fake_gh(root, self._release_payload())
            stage = root / "stage"
            stage.mkdir()
            (stage / "qualification-evidence.json").write_text('{"passed":true}\n', encoding="utf-8")
            rejected = self._run_workflow_script(
                "Attach immutable qualification evidence",
                cwd=root,
                env={
                    **os.environ,
                    **fake_env,
                    "FAKE_EXISTING_QUALIFICATION_COUNT": "1",
                    "PATH": f"{bin_dir}:{os.environ['PATH']}",
                    "GH_TOKEN": "fixture-app-token",
                    "GITHUB_OUTPUT": str(root / "github-output"),
                    "RELEASE_TAG": RELEASE_TAG,
                    "REPO": "sruj75/knowledge-athlete",
                    "STAGE": str(stage),
                    "TARGET_SHA": TARGET_SHA,
                },
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertFalse(Path(fake_env["FAKE_UPLOAD_LOG"]).exists())

    def test_hosted_backend_compatibility_executes_against_the_backend_owned_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            curl = bin_dir / "curl"
            curl.write_text(
                """#!/usr/bin/env python3
import os
import sys

if sys.argv[-1].endswith('/v1/health'):
    print('{"status":"ok"}')
else:
    version = os.environ['FAKE_CHAT_CONTRACT_VERSION']
    print('{"status":"healthy","service":"backend","chat_contract_version":"' + version + '"}')
""",
                encoding="utf-8",
            )
            curl.chmod(0o755)
            base_env = {
                **os.environ,
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "INTENTIVE_PRODUCTION_API_URL": "https://api.example.test",
                "FAKE_CHAT_CONTRACT_VERSION": "2",
            }
            accepted_stage = root / "accepted"
            accepted_stage.mkdir()
            accepted = self._run_workflow_script(
                "Verify live canonical backend chat compatibility",
                cwd=ROOT,
                env={**base_env, "STAGE": str(accepted_stage)},
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            compatibility = json.loads((accepted_stage / "backend-compatibility.json").read_text(encoding="utf-8"))
            self.assertEqual(compatibility["chat_contract_version"], "2")

            rejected_stage = root / "rejected"
            rejected_stage.mkdir()
            rejected = self._run_workflow_script(
                "Verify live canonical backend chat compatibility",
                cwd=ROOT,
                env={**base_env, "FAKE_CHAT_CONTRACT_VERSION": "1", "STAGE": str(rejected_stage)},
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("backend compatibility check failed", rejected.stderr)

    def test_static_tripwire_candidate_and_manual_receipt_bind_exact_tag_and_bytes(self) -> None:
        for fragment in (
            'ref: ${{ inputs.release_tag }}',
            'git rev-parse "$RELEASE_TAG^{commit}"',
            "check-desktop-auto-beta-candidate.py",
            "--qualification-mode owner-manual",
            "Intentive.zip intentive.dmg Intentive.Beta.zip intentive-beta.dmg",
            "desktop-smoke-result.json desktop-smoke-result-beta.json",
            "owner_manual_desktop_qualification.py verify",
            '--bundle "$STAGE/$OWNER_EVIDENCE_ASSET"',
        ):
            self.assertIn(fragment, self.workflow)

    def test_static_tripwire_actions_evidence_name_and_contents_match_backend_admission(self) -> None:
        evidence = self._named_step(self.workflow, "Upload canonical qualification evidence artifact")
        diagnostic = self._named_step(self.workflow, "Upload backend compatibility diagnostic")
        self.assertIn("name: desktop-qualification-evidence-${{ inputs.release_tag }}", evidence)
        self.assertIn("path: ${{ runner.temp }}/desktop-owner-qualification/qualification-evidence.json", evidence)
        self.assertNotIn("backend-compatibility.json", evidence)
        self.assertIn("backend-compatibility.json", diagnostic)
        self.assertNotIn("qualification-evidence.json", diagnostic)

    def test_static_tripwire_release_app_publication_follows_read_only_validation(self) -> None:
        validation = self.workflow.index("Validate exact signed candidate and owner evidence")
        live_backend = self.workflow.index("Verify live canonical backend chat compatibility")
        token = self.workflow.index("Create release app token for final evidence publication")
        publish = self.workflow.index("Attach immutable qualification evidence")
        self.assertLess(validation, live_backend)
        self.assertLess(live_backend, token)
        self.assertLess(token, publish)
        step = self._named_step(self.workflow, "Attach immutable qualification evidence")
        self.assertIn('test "$existing" = 0', step)
        self.assertIn('asset="qualification-evidence-${TARGET_SHA}-${digest}.json"', step)
        self.assertIn("gh release upload", step)
        self.assertNotIn("--clobber", step)
        self.assertNotIn("promote", self.workflow.lower())

    def test_static_tripwire_tagging_is_github_hosted_and_readiness_is_post_candidate_evidence(self) -> None:
        tag_job = self.auto_release.split("  tag-release:", 1)[1]
        self.assertIn("runs-on: ubuntu-latest", tag_job)
        self.assertNotIn("self-hosted", tag_job)
        self.assertNotIn("pre-tag-readiness.sh", tag_job)
        self.assertIn("Publish immutable tag from exact live main source", tag_job)

    def test_static_tripwire_retry_cannot_impersonate_owner_or_dispatch_qualification(self) -> None:
        self.assertIn("Report owner-manual retry requirement", self.retry)
        self.assertNotIn("gh workflow run", self.retry)
        self.assertNotIn("actions/create-github-app-token", self.retry)

    def test_preview_backend_validation_rejects_normalized_production_family_urls(self) -> None:
        step = self._named_step(self.preview_workflow, "Validate the declared backend environment")
        script = step.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] if line.startswith("          ") else line for line in script.splitlines())
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "github-output"
            base_env = {**os.environ, "BACKEND_ENVIRONMENT": "development", "GITHUB_OUTPUT": str(output)}
            accepted = subprocess.run(
                ["bash", "-c", script],
                env={**base_env, "BACKEND_URL": "https://preview.example.test/backend"},
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            for url in ("https://api.omi.me:443/", "https://API.OMI.ME/", "https://api.omi.me./"):
                rejected = subprocess.run(
                    ["bash", "-c", script],
                    env={**base_env, "BACKEND_URL": url},
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("must not target a production-family URL", rejected.stderr)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(DesktopReleaseFlowContractTests)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    owner_contract = subprocess.run(
        [sys.executable, str(ROOT / ".github/scripts/test_owner_manual_desktop_qualification.py"), "-q"],
        check=False,
    )
    raise SystemExit(owner_contract.returncode)
