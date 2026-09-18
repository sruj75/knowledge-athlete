#!/usr/bin/env python3
"""Exercise the report publisher against a real, disposable Git remote."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
PUBLISHER = SCRIPTS / "publish_guardrail_pulse.py"
HISTORY = ".github/guardrail-pulse-history.jsonl"
INITIAL = b'{"date":"2026-09-01","metrics":{}}\n'


class PublishGuardrailPulseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="guardrail-publisher-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "remote.git"
        self.checkout = self.root / "publisher"
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        self.env.update(
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_TERMINAL_PROMPT="0",
        )
        self.git(self.root, "init", "--bare", "--initial-branch=main", str(self.remote))
        self.git(self.root, "clone", str(self.remote), str(self.checkout))
        self.git(self.checkout, "config", "user.name", "Pulse fixture")
        self.git(self.checkout, "config", "user.email", "pulse@example.invalid")
        scripts = self.checkout / ".github/scripts"
        scripts.mkdir(parents=True)
        for name in (
            "guardrail_pulse.py",
            "check_brand_ui.py",
            "check_lifecycle_headers.py",
            "check_package_architecture_maps.py",
            "check_version_prefixed_filenames.py",
            "deferred-work-marker-count.py",
        ):
            shutil.copyfile(SCRIPTS / name, scripts / name)
        (scripts / "package_architecture_baseline.json").write_text(
            '{"version":1,"packages":{}}\n'
        )
        (self.checkout / ".github/lifecycle-header-baseline.txt").write_text("")
        (self.checkout / HISTORY).write_bytes(INITIAL)
        (self.checkout / "product.py").write_text("value = 1\n")
        self.git(self.checkout, "add", ".")
        self.git(self.checkout, "commit", "-m", "fixture")
        self.git(self.checkout, "push", "origin", "HEAD:refs/heads/main")
        self.initial_sha = self.git(self.remote, "rev-parse", "main").strip()

    def git(self, root: Path, *args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(root), *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout

    def publish(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(PUBLISHER),
                "--root",
                str(self.checkout),
                "--date",
                "2026-09-18",
            ],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def replace_generator(self, extra: str, payload: object = None) -> None:
        if payload is None:
            payload = {
                "date": "2026-09-18",
                "metrics": {"fixture": {"count": 1, "baseline": 2}},
            }
        generator = self.checkout / ".github/scripts/guardrail_pulse.py"
        generator.write_text(
            "import json\nfrom pathlib import Path\n"
            f"history = Path({HISTORY!r})\n"
            f"payload = {payload!r}\n"
            "with history.open('a') as output:\n    output.write(json.dumps(payload, sort_keys=True) + '\\n')\n"
            f"{extra}\nprint(json.dumps(payload))\n"
        )
        self.git(self.checkout, "add", ".github/scripts/guardrail_pulse.py")
        self.git(self.checkout, "commit", "-m", "generator fixture")
        self.git(self.checkout, "push", "origin", "HEAD:refs/heads/main")
        self.initial_sha = self.git(self.remote, "rev-parse", "main").strip()

    def prepare_rival(self) -> Path:
        rival = self.root / "rival"
        self.git(self.root, "clone", str(self.remote), str(rival))
        self.git(rival, "config", "user.name", "Concurrent fixture")
        self.git(rival, "config", "user.email", "concurrent@example.invalid")
        source = rival / "backend/utils/compat_fixture.py"
        source.parent.mkdir(parents=True)
        source.write_text("value = 1\n")
        self.git(rival, "add", ".")
        self.git(rival, "commit", "-m", "concurrent product change")
        return rival

    def test_publishes_exactly_one_report_append_to_main(self) -> None:
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["date"], "2026-09-18")
        history = self.git(self.remote, "show", f"main:{HISTORY}").encode()
        self.assertTrue(history.startswith(INITIAL))
        self.assertEqual(len(history.splitlines()), 2)
        self.assertEqual(json.loads(history.splitlines()[1]), payload)
        self.assertEqual(
            self.git(
                self.remote, "diff", "--name-status", self.initial_sha, "main"
            ).strip(),
            f"M\t{HISTORY}",
        )
        self.assertEqual(self.git(self.checkout, "status", "--porcelain"), "")

    def test_refuses_preexisting_staged_source_change_without_pushing(self) -> None:
        (self.checkout / "product.py").write_text("value = 999\n")
        self.git(self.checkout, "add", "product.py")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("clean", result.stderr)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )
        self.assertEqual((self.checkout / "product.py").read_text(), "value = 999\n")

    def test_refuses_unstaged_source_change_created_by_generator(self) -> None:
        self.replace_generator("Path('product.py').write_text('value = 999\\n')")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("only", result.stderr)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_refuses_rewriting_existing_history(self) -> None:
        self.replace_generator(
            "history.write_text(json.dumps(payload, sort_keys=True) + '\\n')"
        )
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("append", result.stderr)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_refuses_a_history_file_mode_change(self) -> None:
        self.replace_generator("history.chmod(0o755)")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mode", result.stderr)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_refuses_a_matching_but_invalid_report_row(self) -> None:
        self.replace_generator(
            "",
            {"date": "2026-09-18", "metrics": {"bad": {"count": True, "baseline": 2}}},
        )
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid", result.stderr)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_refuses_a_feature_branch_even_when_clean(self) -> None:
        self.git(self.checkout, "checkout", "-b", "feature")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main", result.stderr)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_retries_a_competing_push_and_regenerates_from_new_main(self) -> None:
        rival = self.prepare_rival()
        marker = self.root / "race-started"
        hook = self.checkout / ".git/hooks/pre-push"
        hook.write_text(
            f"#!{sys.executable}\nfrom pathlib import Path\nimport os, subprocess\n"
            f"marker = Path({str(marker)!r})\n"
            "if not marker.exists():\n"
            "    marker.touch()\n"
            f"    subprocess.run(['git', '-C', {str(rival)!r}, 'push', 'origin', 'HEAD:refs/heads/main'], "
            "env={key: value for key, value in os.environ.items() if not key.startswith('GIT_')}, check=True)\n"
        )
        hook.chmod(0o755)
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            json.loads(result.stdout)["metrics"]["lifecycle_unlabeled_scripts"][
                "count"
            ],
            1,
        )
        self.assertEqual(
            len(self.git(self.remote, "show", f"main:{HISTORY}").splitlines()), 2
        )
        self.assertEqual(
            self.git(self.remote, "show", "main:backend/utils/compat_fixture.py"),
            "value = 1\n",
        )

    def test_rejects_extra_changes_added_by_a_commit_hook(self) -> None:
        hook = self.checkout / ".git/hooks/pre-commit"
        hook.write_text(
            f"#!{sys.executable}\nfrom pathlib import Path\nimport subprocess\n"
            "Path('product.py').write_text('value = 999\\n')\n"
            "subprocess.run(['git', 'add', 'product.py'], check=True)\n"
        )
        hook.chmod(0o755)
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("candidate", result.stderr)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_refuses_untracked_files_created_by_generator(self) -> None:
        self.replace_generator("Path('unapproved.txt').write_text('unexpected')")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_refuses_more_than_one_appended_row(self) -> None:
        self.replace_generator(
            "with history.open('a') as output:\n    output.write(json.dumps(payload) + '\\n')"
        )
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_refuses_an_existing_symlink_without_writing_its_target(self) -> None:
        target = self.root / "outside-history"
        target.write_bytes(INITIAL)
        (self.checkout / HISTORY).unlink()
        (self.checkout / HISTORY).symlink_to(target)
        self.git(self.checkout, "add", HISTORY)
        self.git(self.checkout, "commit", "-m", "unsafe history fixture")
        self.git(self.checkout, "push", "origin", "HEAD:refs/heads/main")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), INITIAL)

    def test_stops_after_three_competing_pushes_without_forcing(self) -> None:
        rival = self.prepare_rival()
        counter = self.root / "push-count"
        hook = self.checkout / ".git/hooks/pre-push"
        hook.write_text(
            f"#!{sys.executable}\nfrom pathlib import Path\nimport os, subprocess\n"
            f"counter = Path({str(counter)!r})\n"
            "count = int(counter.read_text()) + 1 if counter.exists() else 1\n"
            "counter.write_text(str(count))\n"
            f"product = Path({str(rival / 'product.py')!r})\n"
            "product.write_text(f'value = {count + 100}\\n')\n"
            "env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}\n"
            f"base = ['git', '-C', {str(rival)!r}]\n"
            "for args in [['add', 'product.py'], ['commit', '-m', 'concurrent report race'], "
            "['push', 'origin', 'HEAD:refs/heads/main']]:\n"
            "    subprocess.run(base + args, env=env, check=True, capture_output=True)\n"
        )
        hook.chmod(0o755)
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("three attempts", result.stderr)
        self.assertEqual(counter.read_text(), "3")
        self.assertEqual(
            self.git(self.remote, "show", f"main:{HISTORY}").encode(), INITIAL
        )

    def test_preserves_the_row_boundary_of_existing_history(self) -> None:
        (self.checkout / HISTORY).write_bytes(INITIAL.rstrip(b"\n"))
        self.git(self.checkout, "add", HISTORY)
        self.git(self.checkout, "commit", "-m", "unterminated history fixture")
        self.git(self.checkout, "push", "origin", "HEAD:refs/heads/main")
        initial_sha = self.git(self.remote, "rev-parse", "main")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git(self.remote, "rev-parse", "main"), initial_sha)

    def test_refuses_unpublished_local_commits_without_discarding_them(self) -> None:
        (self.checkout / "product.py").write_text("value = 999\n")
        self.git(self.checkout, "add", "product.py")
        self.git(self.checkout, "commit", "-m", "unpublished source work")
        local_sha = self.git(self.checkout, "rev-parse", "HEAD")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD"), local_sha)
        self.assertEqual(
            self.git(self.remote, "rev-parse", "main").strip(), self.initial_sha
        )

    def test_retry_refuses_to_discard_a_new_local_commit(self) -> None:
        rival = self.prepare_rival()
        hook = self.checkout / ".git/hooks/pre-push"
        hook.write_text(
            f"#!{sys.executable}\nfrom pathlib import Path\nimport os, subprocess\n"
            "env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}\n"
            "Path('product.py').write_text('value = 999\\n')\n"
            "subprocess.run(['git', 'add', 'product.py'], env=env, check=True)\n"
            "subprocess.run(['git', 'commit', '-m', 'independent local work'], env=env, check=True)\n"
            f"subprocess.run(['git', '-C', {str(rival)!r}, 'push', 'origin', 'HEAD:refs/heads/main'], env=env, check=True)\n"
        )
        hook.chmod(0o755)
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.checkout / "product.py").read_text(), "value = 999\n")
        self.assertEqual(
            self.git(self.remote, "show", f"main:{HISTORY}").encode(), INITIAL
        )


if __name__ == "__main__":
    unittest.main()
