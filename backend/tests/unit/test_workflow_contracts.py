import importlib.util
import json
import re
import sys
from pathlib import Path, PurePosixPath

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[2]
REPO_DIR = BACKEND_DIR.parent


def _load_script(name: str):
    path = BACKEND_DIR / "scripts" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _load_repo_script(name: str):
    path = BACKEND_DIR.parent / "scripts" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    previous = sys.modules.get(name)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    finally:
        if previous is None:
            sys.modules.pop(name, None)
        else:
            sys.modules[name] = previous
    return module


def test_standalone_monitoring_product_is_absent_from_the_deploy_graph():
    """Static deployment contract: the retired all-in-one monitoring product cannot be installed."""
    assert not (BACKEND_DIR / "charts/monitoring").exists()

    exclusive_paths = (
        BACKEND_DIR / "scripts/verify_pusher_dev_observability.py",
        BACKEND_DIR / "tests/unit/test_verify_pusher_dev_observability.py",
        BACKEND_DIR / "tests/unit/test_monitoring_alert_rule_contract.py",
        BACKEND_DIR / "docs/runbooks/resilience-dashboards.md",
    )
    assert all(not path.exists() for path in exclusive_paths)

    current_deploy_contracts = (
        REPO_DIR / ".github/checks-manifest.yaml",
        REPO_DIR / ".github/workflows/gcp_backend.yml",
        REPO_DIR / ".github/workflows/gcp_backend_auto_dev.yml",
        BACKEND_DIR / "testing/workflow_contracts.json",
    )
    for path in current_deploy_contracts:
        contents = path.read_text(encoding="utf-8")
        assert "backend/charts/monitoring" not in contents, path
        assert "verify_pusher_dev_observability" not in contents, path

    current_operator_docs = (BACKEND_DIR / "AGENTS.md",)
    deleted_operator_surfaces = (
        "charts/monitoring",
        "Grafana → Parakeet ASR Monitoring",
        "Grafana pusher dashboard",
        "dev Pusher dashboard",
        "development Prometheus jobs discover",
        "deployed LLM Gateway rules",
    )
    for path in current_operator_docs:
        contents = path.read_text(encoding="utf-8")
        for deleted_surface in deleted_operator_surfaces:
            assert deleted_surface not in contents, (path, deleted_surface)


@pytest.fixture(scope="module")
def selector_and_all_tests():
    selector = _load_script("select_backend_unit_tests")
    return selector, selector.discover_all_tests()


def test_workflow_contract_sources_select_adjacent_tests(selector_and_all_tests):
    selector, all_tests = selector_and_all_tests

    full_run_cases = {}
    selected_cases = {
        "backend/services/users/account_deletion.py": "tests/services/users/test_account_deletion.py",
        "backend/routers/transcribe.py": "tests/unit/test_listen_transient_contract.py",
        "backend/routers/fair_use_reviews.py": "tests/unit/test_fair_use_review_requests.py",
        "backend/routers/listen/runtime.py": "tests/unit/test_fair_use_review_runtime.py",
        "backend/utils/llm/fair_use_classifier.py": "tests/unit/test_fair_use_classifier.py",
        "backend/config/prerecorded_stt.py": "tests/unit/test_prerecorded_stt_config.py",
        "backend/scripts/validate-backend-runtime-env.py": "tests/unit/test_backend_runtime_env_validator.py",
        "backend/scripts/firebase_release_probe_token.py": "tests/unit/test_firebase_release_probe_token.py",
        "scripts/voice-provider-probe.sh": "tests/unit/test_voice_provider_probe.py",
        ".github/workflows/desktop_backend_auto_dev.yml": "tests/unit/test_voice_provider_probe.py",
        ".github/workflows/gcp_backend_auto_dev.yml": "tests/unit/test_backend_runtime_env_validator.py",
        "backend/scripts/preflight-cloud-run-deploy.py": "tests/unit/test_preflight_cloud_run_deploy.py",
    }

    for source_path, expected_test in selected_cases.items():
        selected, reason = selector.tests_for_changed_paths([source_path], all_tests)
        assert expected_test in selected, source_path
        assert reason == "selected backend unit tests from changed paths and workflow contracts"

    for source_path, expected_test in full_run_cases.items():
        selected, reason = selector.tests_for_changed_paths([source_path], all_tests)
        assert expected_test in selected, source_path
        assert reason == f"{source_path} requires the full backend unit suite"
        assert selected == all_tests


def test_workflow_contract_directory_glob_selects_nested_action_test(selector_and_all_tests):
    selector, all_tests = selector_and_all_tests

    selected, reason = selector.tests_for_changed_paths(
        [".github/actions/transcription-release-candidate-probe/action.yml"],
        all_tests,
    )

    assert "tests/unit/test_verify_backend_release_vector.py" in selected
    assert reason == "selected backend unit tests from changed paths and workflow contracts"


def test_selector_docs_and_flat_utils_do_not_force_full_suite_via_globs(selector_and_all_tests):
    """Docs/AGENTS skip selection; metrics is not a FULL_RUN_GLOBS hit."""
    selector, all_tests = selector_and_all_tests

    for path in ("backend/AGENTS.md",):
        selected, reason = selector.tests_for_changed_paths([path], all_tests)
        assert selected == [], path
        assert reason == "no backend files changed", (path, reason)

    selected, reason = selector.tests_for_changed_paths(["backend/utils/metrics.py"], all_tests)
    # Not a FULL_RUN_GLOBS path; unmapped flat utils still use the fallback.
    assert reason == "backend/utils/metrics.py did not match a backend test-selection contract", reason
    assert selected == all_tests

    selected, reason = selector.tests_for_changed_paths(["backend/routers/users.py"], all_tests)
    assert "tests/services/users/test_account_deletion.py" in selected
    assert selected != all_tests
    assert reason == "selected backend unit tests from changed paths and workflow contracts"

    for path in ("backend/main.py", "backend/utils/executors.py"):
        selected, reason = selector.tests_for_changed_paths([path], all_tests)
        assert selected == all_tests, path
        assert reason == f"{path} requires the full backend unit suite"


def test_unmapped_source_forces_full_suite_even_when_direct_test_changed(selector_and_all_tests):
    selector, all_tests = selector_and_all_tests

    selected, reason = selector.tests_for_changed_paths(
        [
            "backend/new_unmapped_runtime.py",
            "backend/tests/unit/test_workflow_contracts.py",
        ],
        all_tests,
    )

    assert selected == all_tests
    assert reason == "backend/new_unmapped_runtime.py did not match a backend test-selection contract"


def test_mapped_source_with_direct_test_remains_narrow(selector_and_all_tests):
    selector, all_tests = selector_and_all_tests

    selected, reason = selector.tests_for_changed_paths(
        [
            "backend/routers/users.py",
            "backend/tests/services/users/test_account_deletion.py",
        ],
        all_tests,
    )

    assert "tests/services/users/test_account_deletion.py" in selected
    assert selected != all_tests
    assert reason == "selected backend unit tests from changed paths and workflow contracts"


def test_removed_test_forces_full_discovered_suite(selector_and_all_tests):
    selector, all_tests = selector_and_all_tests

    selected, reason = selector.tests_for_changed_paths(
        ["backend/tests/unit/test_removed_contract.py"],
        all_tests,
    )

    assert selected == all_tests
    assert reason == "backend/tests/unit/test_removed_contract.py was removed or is outside backend test discovery"


def test_every_external_workflow_contract_source_triggers_backend_unit_workflow():
    contracts = json.loads((BACKEND_DIR / "testing/workflow_contracts.json").read_text(encoding="utf-8"))
    workflow_text = (BACKEND_DIR.parent / ".github/workflows/backend-unit-tests.yml").read_text(encoding="utf-8")

    external_sources = {
        source
        for workflow in contracts["workflows"]
        for source in workflow.get("sources", [])
        if not source.startswith("backend/")
    }
    triggers = re.findall(r"^\s*-\s+['\"]([^'\"]+)['\"]\s*$", workflow_text, flags=re.MULTILINE)
    missing = {
        source
        for source in external_sources
        if not any(
            source == trigger or ("*" not in source and PurePosixPath(source).match(trigger)) for trigger in triggers
        )
    }

    assert missing == set()


def test_backend_unit_ci_runner_stays_in_ci_while_pre_push_keeps_its_budget():
    """#9440: CI is full-suite authority; push latency must remain bounded."""
    repo = BACKEND_DIR.parent
    workflow_text = (repo / ".github/workflows/backend-unit-tests.yml").read_text(encoding="utf-8")
    pre_push = (repo / "scripts/pre-push").read_text(encoding="utf-8")
    runner = (BACKEND_DIR / "scripts/run-unit-ci.sh").read_text(encoding="utf-8")

    assert "scripts/run-unit-ci.sh --changed-files" in workflow_text
    assert "scripts/run-unit-ci.sh --all" in workflow_text
    assert "backend/scripts/run-unit-ci.sh" not in pre_push
    assert "backend/scripts/needs-typecheck.sh" in pre_push
    assert '"$SCRIPT_DIR/needs-typecheck.sh" "$2"' in runner
    assert 'PRE_PUSH_MAX_BACKEND_UNIT_TEST_FILES:-40' in pre_push
    assert "pre-push is intentionally a bounded local-feedback gate" in pre_push
    assert 'BACKEND_FAST_UNIT_WARN_SECONDS="0.1"' in runner
    assert 'BACKEND_FAST_UNIT_FAIL_SECONDS="1.0"' in runner


def test_expensive_pr_contracts_cancel_only_superseded_pull_request_runs():
    repo = BACKEND_DIR.parent
    workflows = {
        "backend-unit-tests.yml": "backend-unit-tests-",
        "openapi-contract.yml": "openapi-contract-",
    }

    for filename, group_prefix in workflows.items():
        workflow = (repo / ".github/workflows" / filename).read_text(encoding="utf-8")
        assert "concurrency:" in workflow
        assert f"group: {group_prefix}${{{{ github.event_name == 'pull_request'" in workflow
        assert "format('pr-{0}', github.event.pull_request.number)" in workflow
        assert "format('run-{0}', github.run_id)" in workflow
        assert "cancel-in-progress: true" in workflow


def test_backend_test_runner_defaults_python_to_utf8():
    runner = (BACKEND_DIR / "test.sh").read_text(encoding="utf-8")
    utf8_export = 'export PYTHONUTF8="${PYTHONUTF8:-1}"'

    assert utf8_export in runner
    assert runner.index(utf8_export) < runner.index('PYTHON_BIN="${PYTHON:-}"')


def test_pre_push_requires_backend_python_lazily():
    pre_push = (BACKEND_DIR.parent / "scripts/pre-push").read_text(encoding="utf-8")
    setup_prefix = pre_push[: pre_push.index("run_step()")]

    assert "require_backend_python()" in setup_prefix
    assert 'if [[ ! -x "$BACKEND_PYTHON" ]]' not in setup_prefix
    for function_name in (
        "check_backend_runtime_env_if_needed",
        "check_backend_typecheck_if_needed",
        "check_backend_unit_tests_if_needed",
    ):
        function_start = pre_push.index(f"{function_name}()")
        function_end = pre_push.find("\n}\n", function_start)
        assert "require_backend_python" in pre_push[function_start:function_end], function_name


def test_pre_push_selects_release_guard_and_focused_test_for_release_contract_changes():
    """The fast lane catches qualification guard drift without cloning the backend suite."""
    pre_push = (BACKEND_DIR.parent / "scripts/pre-push").read_text(encoding="utf-8")
    function_start = pre_push.index("check_release_process_guards_if_needed()")
    function_end = pre_push.index("\n}\n", function_start)
    guard = pre_push[function_start:function_end]

    assert ".github/workflows/desktop_qualify_beta.yml" in guard
    assert ".github/scripts/check-release-process-guards.py" in guard
    assert "scripts/run-release-process-guards.sh" in guard
    assert "tests/unit/test_desktop_release_scripts.py" in guard
    assert "bash scripts/run-release-process-guards.sh" in guard
    assert "BACKEND_UNIT_TEST_FILE_LIST" in guard


def test_pre_push_runs_each_named_check_phase_once():
    pre_push = (BACKEND_DIR.parent / "scripts/pre-push").read_text(encoding="utf-8")
    check_calls = re.findall(r"^run_step (check_[A-Za-z0-9_]+)$", pre_push, flags=re.MULTILINE)
    duplicates = sorted({name for name in check_calls if check_calls.count(name) > 1})

    assert duplicates == []


def test_shared_change_detection_and_backend_isolation_are_ci_wired():
    repo = BACKEND_DIR.parent
    detect_changes = (repo / ".github/actions/detect-changes/action.yml").read_text(encoding="utf-8")
    manifest = (repo / ".github/checks-manifest.yaml").read_text(encoding="utf-8")
    backend_checks = (repo / ".github/workflows/backend-checks.yml").read_text(encoding="utf-8")
    repo_checks = (repo / ".github/workflows/repo-checks.yml").read_text(encoding="utf-8")
    desktop_checks = (repo / ".github/workflows/desktop-checks.yml").read_text(encoding="utf-8")
    retired_agent_proxy_workflows = (
        repo / ".github/workflows/gcp_backend_agent_proxy_auto_deploy.yml",
        repo / ".github/workflows/gcp_backend_agent_proxy.yml",
    )
    swift_test_suites = (repo / "desktop/macos/scripts/swift-test-suites.sh").read_text(encoding="utf-8")
    pre_push = (repo / "scripts/pre-push").read_text(encoding="utf-8")

    assert 'FILES=$(scripts/changed-files "$DIFF_BASE"...HEAD)' in detect_changes
    assert "has_backend_isolation_gate" in detect_changes
    assert "has_desktop_rust" not in desktop_checks
    assert all(not path.exists() for path in retired_agent_proxy_workflows)
    assert "backend/agent-proxy" not in detect_changes
    assert "scan_import_time_side_effects.py" in manifest
    assert "check_module_stub_pollution.py" in manifest
    assert '"--check-allowlist-monotonic", "{base}"' in manifest
    assert "backend/agent-proxy" not in manifest
    assert "backend/dependencies.py" not in manifest
    assert "unmanaged_thread_offload" in manifest
    assert "scan_import_time_side_effects.py" not in backend_checks
    assert "check_module_stub_pollution.py" not in backend_checks
    assert "run_checks.py --lane ci" in repo_checks
    assert 'BASE_REMOTE="${PRE_PUSH_BASE_REMOTE:-origin}"' in pre_push
    assert 'scripts/changed-files "$DIFF_BASE" "$local_oid"' in pre_push
    assert "scripts/pr-preflight --lane local" in pre_push
    assert "backend/scripts/run-unit-ci.sh" not in pre_push
    assert 'PRE_PUSH_MAX_BACKEND_UNIT_TEST_FILES:-40' in pre_push
    assert "scan_import_time_side_effects.py" not in pre_push
    assert "check_module_stub_pollution.py" not in pre_push
    assert "check_desktop_test_quality.py" in manifest
    assert 'python3 "$SCRIPT_DIR/check_desktop_test_quality.py"' in swift_test_suites
    assert 'if [ -z "${OMI_SWIFT_TEST_DISCOVERY_ROOT:-}" ]; then' in swift_test_suites


def test_backend_static_contract_job_uses_the_pinned_backend_environment():
    repo = BACKEND_DIR.parent
    workflow = (repo / '.github/workflows/backend-checks.yml').read_text(encoding='utf-8')
    pre_deploy = (BACKEND_DIR / 'scripts/pre-deploy-check.sh').read_text(encoding='utf-8')

    assert 'uses: actions/setup-python@v6' in workflow
    assert 'uses: astral-sh/setup-uv@ecd24dd710f2fb0dca1693a67af11fc4a5c5ec84' in workflow
    assert 'uv pip sync pylock.toml --system' in workflow
    assert 'backend/scripts/pre-deploy-check.sh' in workflow
    assert 'python3 -m pip install' not in pre_deploy
    assert "python3 -c 'import pytest, yaml'" in pre_deploy


def test_present_repository_ci_routing_has_no_absent_product_outputs():
    resolver = _load_repo_script("pre_push_ci_prediction")

    plan = resolver.resolve_impact([".github/checks-manifest.yaml"])
    assert all(not phase.startswith(("app-", "flutter-")) for phase in plan.phases)
    assert all(not name.startswith(("has_app", "has_flutter")) for name in resolver.github_outputs(plan))


def test_installed_pre_push_hook_falls_back_for_older_worktrees():
    installer = (BACKEND_DIR.parent / "scripts/install-git-hooks.sh").read_text(encoding="utf-8")

    assert 'if [ -x "$ROOT/scripts/pre-push-singleflight" ]' in installer
    assert 'exec "$ROOT/scripts/pre-push" "$@"' in installer


def test_workflow_contracts_static_check_accepts_current_allowlist():
    checker = _load_script("check_workflow_contracts")
    contracts = checker.load_contracts()

    assert checker.check_no_large_tuple_results(contracts) == []


def test_workflow_contracts_static_check_rejects_unlisted_large_tuple_result(tmp_path, monkeypatch):
    checker = _load_script("check_workflow_contracts")
    fake_repo = tmp_path / "repo"
    fake_repo.mkdir()
    fake_source = fake_repo / "backend" / "utils" / "workflow" / "new_workflow.py"
    fake_source.parent.mkdir(parents=True)
    fake_source.write_text("def bad_contract() -> tuple[int, int, int]:\n    return 1, 2, 3\n")

    monkeypatch.setattr(checker, "REPO_DIR", fake_repo)
    contracts = {
        "checks": {"no_large_tuple_results": {"allowlist": []}},
        "workflows": [
            {
                "risk": "high",
                "sources": ["backend/utils/workflow/new_workflow.py"],
                "tests": ["tests/unit/test_new_workflow.py"],
                "checks": ["no_large_tuple_results"],
            }
        ],
    }

    errors = checker.check_no_large_tuple_results(contracts)

    assert len(errors) == 1
    assert "bad_contract returns a positional tuple with 3 fields" in errors[0]


def test_workflow_contracts_static_check_skips_workflows_without_tuple_check(tmp_path, monkeypatch):
    checker = _load_script("check_workflow_contracts")
    fake_repo = tmp_path / "repo"
    fake_repo.mkdir()
    fake_source = fake_repo / "backend" / "routers" / "chat.py"
    fake_source.parent.mkdir(parents=True)
    fake_source.write_text("def bad_contract() -> tuple[int, int, int]:\n    return 1, 2, 3\n")

    monkeypatch.setattr(checker, "REPO_DIR", fake_repo)
    contracts = {
        "checks": {"no_large_tuple_results": {"allowlist": []}},
        "workflows": [
            {
                "risk": "high",
                "sources": ["backend/routers/chat.py"],
                "tests": ["tests/unit/test_voice_message_language.py"],
                "checks": [],
            }
        ],
    }

    assert checker.check_no_large_tuple_results(contracts) == []


def test_workflow_contracts_static_check_ignores_non_python_glob_matches(tmp_path, monkeypatch):
    checker = _load_script("check_workflow_contracts")
    fake_repo = tmp_path / "repo"
    source_dir = fake_repo / "backend" / "utils" / "workflow"
    source_dir.mkdir(parents=True)
    (source_dir / "contract.py").write_text("def safe_contract() -> tuple[int, int, int]:\n    return 1, 2, 3\n")
    (source_dir / "ARCHITECTURE.md").write_text("# architecture\n")
    pycache = source_dir / "__pycache__"
    pycache.mkdir()
    (pycache / "contract.cpython-311.pyc").write_bytes(b"\xa7\r\r\n")

    monkeypatch.setattr(checker, "REPO_DIR", fake_repo)
    contracts = {
        "checks": {
            "no_large_tuple_results": {
                "allowlist": [
                    {
                        "path": "backend/utils/workflow/contract.py",
                        "function": "safe_contract",
                    }
                ]
            }
        },
        "workflows": [
            {
                "risk": "high",
                "sources": ["backend/utils/workflow/**"],
                "tests": ["tests/unit/test_contract.py"],
                "checks": ["no_large_tuple_results"],
            }
        ],
    }

    assert checker.check_no_large_tuple_results(contracts) == []


def test_workflow_contracts_static_check_validates_all_sources_when_manifest_changes(tmp_path, monkeypatch):
    checker = _load_script("check_workflow_contracts")
    fake_repo = tmp_path / "repo"
    fake_repo.mkdir()
    fake_source = fake_repo / "backend" / "utils" / "workflow" / "new_workflow.py"
    fake_source.parent.mkdir(parents=True)
    fake_source.write_text("def bad_contract() -> tuple[int, int, int]:\n    return 1, 2, 3\n")

    monkeypatch.setattr(checker, "REPO_DIR", fake_repo)
    contracts = {
        "checks": {"no_large_tuple_results": {"allowlist": []}},
        "workflows": [
            {
                "risk": "high",
                "sources": ["backend/utils/workflow/new_workflow.py"],
                "tests": ["tests/unit/test_new_workflow.py"],
                "checks": ["no_large_tuple_results"],
            }
        ],
    }

    errors = checker.check_no_large_tuple_results(contracts, [checker.CONTRACTS_REL_PATH])

    assert len(errors) == 1
    assert "bad_contract returns a positional tuple with 3 fields" in errors[0]
