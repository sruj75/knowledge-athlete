import ast
import importlib.util
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock

BACKEND_DIR = Path(__file__).resolve().parents[2]


def _load_module(module_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def test_scan_async_blockers_treats_run_blocking_lambda_as_safe():
    scanner = _load_module("scan_async_blockers_for_test", BACKEND_DIR / "scripts" / "scan_async_blockers.py")
    source = """
async def helper():
    await run_blocking(db_executor, lambda: open('x').read())
"""
    tree = ast.parse(source)
    node = next(n for n in tree.body if getattr(n, "name", None) == "helper")

    _db, file_io, _network, _sleeps, _body_call_lines = scanner.scan_async_function(node, set(), set(), set())

    assert file_io == []


def test_scan_async_blockers_keeps_deletion_only_hunks_in_changed_scope(monkeypatch):
    scanner = _load_module(
        "scan_async_blockers_diff_scope_for_test", BACKEND_DIR / "scripts" / "scan_async_blockers.py"
    )
    captured = {}

    def fake_run(*args, **kwargs):
        captured["cmd"] = args[0]
        return types.SimpleNamespace(
            stdout="""
diff --git a/backend/routers/example.py b/backend/routers/example.py
index 1111111..2222222 100644
--- a/backend/routers/example.py
+++ b/backend/routers/example.py
@@ -42 +42,0 @@ async def endpoint():
-    await run_blocking(db_executor, expensive_sync_call)
diff --git a/backend/routers/old_name.py b/backend/routers/new_name.py
similarity index 96%
rename from backend/routers/old_name.py
rename to backend/routers/new_name.py
--- a/backend/routers/old_name.py
+++ b/backend/routers/new_name.py
@@ -10 +10 @@ async def renamed_endpoint():
-    await old_call()
+    await new_call()
"""
        )

    monkeypatch.setattr(scanner.subprocess, "run", fake_run)

    scope = scanner.changed_scope("origin/main", ["backend/routers"])

    assert "--no-renames" in captured["cmd"]
    assert "--diff-filter=ACMRTD" in captured["cmd"]
    assert scope["ranges"]["backend/routers/example.py"] == [(42, 42)]
    assert scope["ranges"]["backend/routers/new_name.py"] == [(10, 10)]
    assert scanner.finding_in_changed_scope(
        {"file": "backend/routers/example.py", "line": 40, "end_line": 45},
        scope,
    )


def test_scan_async_blockers_honors_no_await_fail_on_without_blocking_calls():
    scanner = _load_module("scan_async_blockers_fail_on_for_test", BACKEND_DIR / "scripts" / "scan_async_blockers.py")

    results = {
        "no_await_should_be_def": [
            {
                "file": "backend/routers/example.py",
                "line": 12,
                "end_line": 16,
                "endpoint": "endpoint",
                "method": "GET",
                "path": "/example",
                "has_await": False,
                "db_calls": [],
                "all_blocking": [],
                "all_calls_are_blocking": False,
            }
        ]
    }

    assert scanner.selected_failures(results, ("no_await_should_be_def",)) == [
        ("no_await_should_be_def", results["no_await_should_be_def"][0])
    ]
