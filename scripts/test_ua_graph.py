#!/usr/bin/env python3
"""Exercise the UA public CLI with committed repositories and the real scanner."""

from __future__ import annotations

import os
import json
from dataclasses import asdict
import shutil
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().with_name("ua-graph")
BASELINE = "a" * 40  # Deliberately absent from every fixture's object database.
CONTENT = "export const value = 1;\n"
CONTENT_HASH = "5d8f65d2774e206bc9f7a7a4ad39ca2dc563b5c31e46ab57ef4874961237ce29"


def environment() -> dict:
    result = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    result.update(
        GIT_CONFIG_NOSYSTEM="1",
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_AUTHOR_NAME="UA fixture",
        GIT_AUTHOR_EMAIL="fixture@example.invalid",
        GIT_COMMITTER_NAME="UA fixture",
        GIT_COMMITTER_EMAIL="fixture@example.invalid",
    )
    return result


class CommittedGraphTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "workspace-a"
        self.repo.mkdir()
        self.git("init", "--quiet")
        self.write("app.ts", CONTENT)
        self.write(".ua/.understandignore", "docs/\ntests/\n")
        self.write_json(".ua/config.json", {"autoUpdate": True, "outputLanguage": "en"})
        self.write_json(
            ".ua/meta.json",
            {
                "version": "1.0.0",
                "gitCommitHash": BASELINE,
                "lastAnalyzedAt": "2026-09-18T00:00:00Z",
                "analyzedFiles": 1,
            },
        )
        self.write_json(
            ".ua/fingerprints.json",
            {
                "version": "1.0.0",
                "gitCommitHash": BASELINE,
                "generatedAt": "2026-09-18T00:00:00Z",
                "files": {
                    "app.ts": {
                        "filePath": "app.ts",
                        "contentHash": CONTENT_HASH,
                        "functions": [],
                        "classes": [],
                        "imports": [],
                        "exports": [],
                        "totalLines": 2,
                        "hasStructuralAnalysis": False,
                    }
                },
            },
        )
        self.write_json(
            ".ua/knowledge-graph.json",
            {
                "version": "1.0.0",
                "kind": "codebase",
                "project": {
                    "name": "Fixture",
                    "languages": ["typescript"],
                    "frameworks": [],
                    "description": "Fixture",
                    "analyzedAt": "2026-09-18T00:00:00Z",
                    "gitCommitHash": BASELINE,
                },
                "nodes": [
                    {
                        "id": "file:app.ts",
                        "type": "file",
                        "name": "app",
                        "filePath": "app.ts",
                        "summary": "Exports a value",
                        "tags": [],
                        "complexity": "simple",
                    }
                ],
                "edges": [],
                "layers": [],
                "tour": [],
            },
        )
        self.commit()

    def git(self, *arguments: str) -> str:
        result = subprocess.run(
            ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", *arguments],
            cwd=self.repo,
            env=environment(),
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def write(self, path: str, content: str) -> None:
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def write_json(self, path: str, value: dict) -> None:
        self.write(path, json.dumps(value) + "\n")

    def commit(self) -> str:
        self.git("add", "-A")
        self.git("commit", "--quiet", "-m", "Fixture candidate")
        return self.git("rev-parse", "HEAD")

    def check(self, ref: str = "HEAD", *, cwd: Path | None = None, env: dict | None = None):
        return subprocess.run(
            [str(CLI), "check", "--ref", ref],
            cwd=cwd or self.repo,
            env=env or environment(),
            capture_output=True,
            text=True,
        )

    def test_committed_content_passes_without_baseline_object(self) -> None:
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 analyzed files", result.stdout)

    def test_changed_commit_fails_even_with_fresh_uncommitted_fingerprints(self) -> None:
        self.write("app.ts", "export const value = 2;\n")
        self.commit()
        data = json.loads((self.repo / ".ua/fingerprints.json").read_text())
        data["files"]["app.ts"]["contentHash"] = "f4918c8ac9858f83b2c0307536179d6bd283bc7c20ba34b53074721f43611f4a"
        self.write_json(".ua/fingerprints.json", data)
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Stale graph", result.stderr)
        self.assertIn("app.ts", result.stderr)

    def test_working_tree_and_index_do_not_change_requested_commit(self) -> None:
        self.write("app.ts", "uncommitted replacement\n")
        self.git("add", "app.ts")
        self.write("new.ts", "untracked source\n")
        self.write(".ua/knowledge-graph.json", "invalid uncommitted JSON")
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_new_deleted_and_renamed_paths_fail_inventory(self) -> None:
        original = self.git("rev-parse", "HEAD")
        for change in ("new", "deleted", "renamed"):
            with self.subTest(change=change):
                self.git("reset", "--hard", original)
                if change == "new":
                    self.write("new.ts", CONTENT)
                elif change == "deleted":
                    (self.repo / "app.ts").unlink()
                else:
                    (self.repo / "app.ts").rename(self.repo / "renamed.ts")
                self.commit()
                result = self.check()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("inventory differs", result.stderr)

    def test_graph_only_ignored_docs_tests_and_generated_files_remain_current(self) -> None:
        graph = json.loads((self.repo / ".ua/knowledge-graph.json").read_text())
        graph["project"]["description"] = "Refined explanation"
        self.write_json(".ua/knowledge-graph.json", graph)
        for path in (
            "docs/guide.md",
            "tests/app.test.ts",
            "app.generated.ts",
            "dist/bundle.js",
            ".ua/intermediate/partial.ts",
        ):
            self.write(path, "excluded content\n")
        self.commit()
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_canonical_negation_can_include_default_excluded_file(self) -> None:
        self.write(".ua/.understandignore", "!app.generated.ts\n")
        self.write("app.generated.ts", CONTENT)
        self.commit()
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("app.generated.ts", result.stderr)

    def test_fresh_second_worktree_inherits_committed_graph(self) -> None:
        workspace_b = Path(self.temporary.name) / "workspace-b"
        self.git("worktree", "add", "--quiet", "--detach", str(workspace_b), "HEAD")
        self.write("app.ts", "unfinished workspace A change\n")
        self.write(".ua/knowledge-graph.json", "unfinished workspace A analysis")
        # Conductor's shared repository may have core.bare=true.
        self.git("config", "core.bare", "true")
        inherited = environment()
        inherited.update(
            GIT_DIR="/does-not-exist",
            GIT_WORK_TREE=str(self.repo),
            GIT_INDEX_FILE="/does-not-exist/index",
            GIT_CONFIG_COUNT="1",
            GIT_CONFIG_KEY_0="core.bare",
            GIT_CONFIG_VALUE_0="true",
        )
        result = self.check(cwd=workspace_b, env=inherited)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_checks_exact_branch_and_merge_candidates(self) -> None:
        original = self.git("rev-parse", "HEAD")
        self.git("checkout", "--quiet", "-b", "feature")
        self.write("docs/feature.md", "Ignored feature documentation\n")
        feature = self.commit()
        self.git("checkout", "--quiet", "-b", "base", original)
        self.write("app.ts", "export const value = 2;\n")
        self.commit()
        self.git("merge", "--quiet", "--no-edit", "--no-ff", "feature")
        passed = self.check(feature)
        failed = self.check("HEAD")
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
        self.assertIn("Stale graph", failed.stderr)

    def test_raw_blobs_ignore_archive_attributes_smudge_and_hooks(self) -> None:
        self.write(".gitattributes", "app.ts export-ignore filter=ua-fixture\n")
        self.write(".ua/.understandignore", "docs/\ntests/\n.gitattributes\n")
        self.commit()
        marker = Path(self.temporary.name) / "must-not-run"
        self.git("config", "filter.ua-fixture.smudge", f"touch '{marker}'")
        self.git("config", "filter.ua-fixture.required", "true")
        hook = self.repo / ".git/hooks/post-checkout"
        hook.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
        hook.chmod(0o755)
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(marker.exists())

    def test_raw_structural_invalidity_is_not_sanitized_into_success(self) -> None:
        original = self.git("rev-parse", "HEAD")
        for issue in ("node", "duplicate", "edge", "layer", "tour", "coverage", "path", "baseline", "count"):
            with self.subTest(issue=issue):
                self.git("reset", "--hard", original)
                graph = json.loads((self.repo / ".ua/knowledge-graph.json").read_text())
                if issue == "node":
                    graph["nodes"].append({"id": "malformed"})
                elif issue == "duplicate":
                    graph["nodes"].append(dict(graph["nodes"][0]))
                elif issue == "edge":
                    graph["edges"] = [
                        {
                            "source": "file:app.ts",
                            "target": "missing",
                            "type": "imports",
                            "direction": "forward",
                            "weight": 1,
                        }
                    ]
                elif issue == "layer":
                    graph["layers"] = [{"id": "layer", "name": "Layer", "description": "", "nodeIds": ["missing"]}]
                elif issue == "tour":
                    graph["tour"] = [{"order": 1, "title": "Tour", "description": "", "nodeIds": ["missing"]}]
                elif issue == "coverage":
                    graph["nodes"][0].update(id="function:app.ts:value", type="function")
                elif issue == "path":
                    graph["nodes"][0]["filePath"] = "../app.ts"
                elif issue == "baseline":
                    graph["project"]["gitCommitHash"] = "b" * 40
                elif issue == "count":
                    meta = json.loads((self.repo / ".ua/meta.json").read_text())
                    meta["analyzedFiles"] = 2
                    self.write_json(".ua/meta.json", meta)
                self.write_json(".ua/knowledge-graph.json", graph)
                self.commit()
                result = self.check()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_malformed_missing_and_symlinked_artifacts_fail_closed(self) -> None:
        original = self.git("rev-parse", "HEAD")
        for issue in ("malformed", "duplicate-key", "missing", "symlink", "scope-symlink"):
            with self.subTest(issue=issue):
                self.git("reset", "--hard", original)
                artifact = self.repo / ".ua/meta.json"
                if issue == "malformed":
                    artifact.write_text("{")
                elif issue == "duplicate-key":
                    artifact.write_text('{"gitCommitHash":"a", "gitCommitHash":"b"}')
                elif issue == "missing":
                    artifact.unlink()
                elif issue == "symlink":
                    artifact.unlink()
                    artifact.symlink_to("/does-not-exist")
                else:
                    (self.repo / ".understandignore").symlink_to("/does-not-exist")
                self.commit()
                result = self.check()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_unresolvable_ref_fails_without_refreshing(self) -> None:
        result = self.check("does-not-exist")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_malformed_fingerprint_structure_is_rejected(self) -> None:
        data = json.loads((self.repo / ".ua/fingerprints.json").read_text())
        data["files"]["app.ts"]["functions"] = "damaged structural analysis"
        self.write_json(".ua/fingerprints.json", data)
        self.commit()
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Invalid fingerprint", result.stderr)

    def test_utf8_decoding_matches_stock_fingerprint_hash(self) -> None:
        # 0xff decodes to U+FFFD. Stock fingerprints hash its UTF-8 encoding, not 0xff.
        (self.repo / "app.ts").write_bytes(b"\xff")
        data = json.loads((self.repo / ".ua/fingerprints.json").read_text())
        data["files"]["app.ts"]["contentHash"] = "83d544ccc223c057d2bf80d3f2a32982c32c3c0db8e2674820da5064783fb097"
        self.write_json(".ua/fingerprints.json", data)
        self.commit()
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_scanner_cannot_silently_fall_back_to_non_git_enumeration(self) -> None:
        binary = Path(self.temporary.name) / "bin/git"
        binary.parent.mkdir()
        binary.write_text(
            '#!/bin/sh\nif [ "$1" = "ls-files" ]; then exit 1; fi\n' + f'exec {shlex.quote(shutil.which("git"))} "$@"\n'
        )
        binary.chmod(0o755)
        env = environment()
        env["PATH"] = str(binary.parent) + os.pathsep + env["PATH"]
        result = self.check(env=env)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("falling back", result.stderr)

    def test_production_manifest_runs_real_checker_in_both_lanes(self) -> None:
        source = CLI.parent.parent
        sys.path.insert(0, str(source / ".github/scripts"))
        try:
            from run_checks import load_manifest

            check = next(
                entry
                for entry in load_manifest(source / ".github/checks-manifest.yaml").checks
                if entry.id == "ua-graph-freshness"
            )
        finally:
            sys.path.pop(0)
        for relative in (
            ".github/scripts/run_checks.py",
            ".github/scripts/git_bash.py",
            "scripts/ua-graph",
            "scripts/ua_graph.py",
            "scripts/ua_graph_validate.mjs",
        ):
            target = self.repo / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / relative, target)
        # Preserve every field of the production entry, including its interpreter.
        fields = list(asdict(check).items())
        self.write(
            ".github/checks-manifest.yaml",
            "checks:\n"
            + "\n".join(
                f'{"  - " if index == 0 else "    "}{key}: {json.dumps(value)}'
                for index, (key, value) in enumerate(fields)
            )
            + "\n",
        )
        self.write(".ua/.understandignore", "docs/\ntests/\nscripts/\n.github/\n")
        oid = self.commit()
        for lane in ("local", "ci"):
            with self.subTest(lane=lane):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(self.repo / ".github/scripts/run_checks.py"),
                        "--lane",
                        lane,
                        "--base",
                        oid,
                        "--head",
                        oid,
                        "--check-id",
                        "ua-graph-freshness",
                    ],
                    cwd=self.repo,
                    env=environment(),
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"UA graph current for {oid}", result.stdout)
                self.assertIn("PASS ua-graph-freshness", result.stdout)


class RuntimeBoundaryTests(unittest.TestCase):
    def test_missing_runtime_fails_without_installing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "not-installed"
            environment = dict(os.environ, UA_GRAPH_CACHE_DIR=str(cache))
            result = subprocess.run([str(CLI), "root"], capture_output=True, text=True, env=environment)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("scripts/ua-graph setup", result.stderr)
            self.assertFalse(cache.exists(), "An offline command must not create its cache")

    def test_setup_is_idempotent_and_resolves_installed_nvm_node(self) -> None:
        ready = subprocess.run([str(CLI), "root"], capture_output=True, text=True)
        self.assertEqual(ready.returncode, 0, ready.stdout + ready.stderr)
        receipt = Path(ready.stdout.strip()).parents[1] / "ready.json"
        before = receipt.stat().st_mtime_ns
        candidates = [shutil.which("node")]
        if os.environ.get("NVM_DIR"):
            candidates.append(str(Path(os.environ["NVM_DIR"]) / "versions/node/v22.22.0/bin/node"))
        node = next(
            (
                Path(path).resolve()
                for path in candidates
                if path
                and Path(path).is_file()
                and subprocess.run([path, "--version"], capture_output=True, text=True).stdout.strip() == "v22.22.0"
            ),
            None,
        )
        self.assertIsNotNone(node, "Run scripts/ua-graph setup with the pinned Node first")
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            wrong = temporary / "bin/node"
            wrong.parent.mkdir()
            wrong.write_text("#!/bin/sh\necho v0.0.0\n")
            wrong.chmod(0o755)
            installed = temporary / "nvm/versions/node/v22.22.0/bin/node"
            installed.parent.mkdir(parents=True)
            installed.symlink_to(node)
            env = dict(
                os.environ, PATH=str(wrong.parent) + os.pathsep + os.environ["PATH"], NVM_DIR=str(temporary / "nvm")
            )
            result = subprocess.run([str(CLI), "setup"], capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Building", result.stdout)
        self.assertEqual(receipt.stat().st_mtime_ns, before)


if __name__ == "__main__":
    unittest.main()
