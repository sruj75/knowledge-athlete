from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys

import pytest
import yaml

from testing.shell import bash_command, bash_executable, bash_path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = ROOT / '.github/workflows/gcp_backend_auto_dev.yml'


def _load_admission_script():
    path = ROOT / '.github/scripts/verify_auto_backend_release_admission.py'
    spec = importlib.util.spec_from_file_location('verify_auto_backend_release_admission', path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _scope_job() -> dict:
    workflow = yaml.safe_load(WORKFLOW_PATH.read_text(encoding='utf-8'))
    return workflow['jobs']['scope']


def _git(repo: Path, *args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()


def _commit(repo: Path, relative_path: str) -> str:
    path = repo / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f'{relative_path}\n', encoding='utf-8')
    _git(repo, 'add', relative_path)
    _git(repo, 'commit', '-m', f'change {relative_path}')
    return _git(repo, 'rev-parse', 'HEAD')


def _run_scope(
    repo: Path,
    sha: str,
    *,
    main_sha: str | None = None,
    comparison: str = 'identical',
    api_fault: str = '',
    deployment_mode: str = 'manual-only',
    expected_returncode: int = 0,
) -> tuple[dict[str, str], str]:
    output = repo / 'github-output.txt'
    summary = repo / 'github-summary.md'
    fake_bin = repo / 'fake-bin'
    fake_bin.mkdir()
    # The scope step intentionally needs two GitHub API proofs before it may
    # no-op a stale run. Model those proofs locally instead of relying on a
    # real token/network in unit tests. GitHub's wire contract has a comparison
    # URL and base_commit, not head_commit (#79):
    # https://docs.github.com/en/rest/commits/commits#compare-two-commits
    curl = fake_bin / 'curl'
    curl.write_text(
        '''#!/usr/bin/env bash
set -euo pipefail
output=''
for ((i = 1; i <= $#; i++)); do
  if [[ "${!i}" == '--output' ]]; then
    j=$((i + 1)); output="${!j}"
  fi
done
url="${!#}"
if [[ "$url" == */git/ref/heads/main ]]; then
  [[ "$MOCK_API_FAULT" == ref-http ]] && { printf '403'; exit 0; }
  printf '{"ref":"refs/heads/main","object":{"type":"commit","sha":"%s"}}' "$MOCK_MAIN_SHA" > "$output"
elif [[ "$url" == */compare/* ]]; then
  [[ "$MOCK_API_FAULT" == compare-http ]] && { printf '503'; exit 0; }
  [[ "$MOCK_API_FAULT" == malformed-json ]] && { printf '{' > "$output"; printf '200'; exit 0; }
  [[ "$MOCK_API_FAULT" == wrong-url ]] && url="$url-invalid"
  base_sha="$RELEASE_SHA"
  [[ "$MOCK_API_FAULT" == wrong-base ]] && base_sha='0000000000000000000000000000000000000000'
  printf '{"url":"%s","base_commit":{"sha":"%s"},"status":"%s"}' "$url" "$base_sha" "$MOCK_COMPARISON" > "$output"
else
  exit 1
fi
printf '200'
''',
        encoding='utf-8',
    )
    curl.chmod(0o755)
    if os.name == 'nt':
        # Git for Windows does not ship jq, so model the two exact API
        # identities while Linux continues to exercise the real jq filters.
        jq = fake_bin / 'jq'
        jq.write_text(
            '''#!/usr/bin/env bash
set -euo pipefail
payload="$(<"${!#}")"
expected_ref='{"ref":"refs/heads/main","object":{"type":"commit","sha":"'"$MOCK_MAIN_SHA"'"}}'
expected_compare='{"url":"https://api.github.com/repos/sruj75/knowledge-athlete/compare/'"$RELEASE_SHA"'...'"$MOCK_MAIN_SHA"'","base_commit":{"sha":"'"$RELEASE_SHA"'"},"status":"'"$MOCK_COMPARISON"'"}'
if [[ "$payload" == "$expected_ref" ]]; then
  printf '%s\\n' "$MOCK_MAIN_SHA"
elif [[ "$payload" == "$expected_compare" ]]; then
  case "$MOCK_COMPARISON" in behind|ahead|identical|diverged) ;; *) exit 1 ;; esac
  printf '%s\\n' "$MOCK_COMPARISON"
else
  exit 1
fi
''',
            encoding='utf-8',
        )
        jq.chmod(0o755)
    scope_step = next(step for step in _scope_job()['steps'] if step.get('id') == 'scope')
    scope_script = f'export PATH="$OMI_TEST_FAKE_BIN:$PATH"\n{scope_step["run"]}'
    result = subprocess.run(
        bash_command('-c', scope_script, cwd=ROOT),
        cwd=repo,
        check=False,
        capture_output=True,
        env={
            **os.environ,
            'OMI_TEST_FAKE_BIN': bash_path(fake_bin, cwd=ROOT),
            'GH_TOKEN': 'test-token',
            'GITHUB_REPOSITORY': 'sruj75/knowledge-athlete',
            'RELEASE_SHA': sha,
            'MOCK_MAIN_SHA': main_sha or sha,
            'MOCK_COMPARISON': comparison,
            'MOCK_API_FAULT': api_fault,
            'AUTO_DEV_DEPLOYMENT_MODE': deployment_mode,
            'GITHUB_OUTPUT': str(output),
            'GITHUB_STEP_SUMMARY': str(summary),
        },
        text=True,
    )
    assert result.returncode == expected_returncode, result.stderr
    values = (
        dict(line.split('=', 1) for line in output.read_text(encoding='utf-8').splitlines()) if output.exists() else {}
    )
    return values, summary.read_text(encoding='utf-8')


@pytest.fixture
def git_repo(tmp_path: Path) -> Path:
    _git(tmp_path, 'init')
    _git(tmp_path, 'config', 'user.email', 'scope-test@example.invalid')
    _git(tmp_path, 'config', 'user.name', 'Scope Test')
    policy = tmp_path / '.github/scripts/backend_auto_deploy_policy.py'
    policy.parent.mkdir(parents=True)
    policy.write_bytes((ROOT / '.github/scripts/backend_auto_deploy_policy.py').read_bytes())
    policy.chmod(0o755)
    (tmp_path / 'README.md').write_text('fixture\n', encoding='utf-8')
    _git(tmp_path, 'add', 'README.md', '.github/scripts/backend_auto_deploy_policy.py')
    _git(tmp_path, 'commit', '-m', 'fixture')
    return tmp_path


def test_windows_bash_resolution_uses_the_active_git_installation(tmp_path: Path) -> None:
    git_root = tmp_path / 'Git'
    git_exec_path = git_root / 'mingw64/libexec/git-core'
    git_exec_path.mkdir(parents=True)
    git_bash = git_root / 'bin/bash.exe'
    git_bash.parent.mkdir()
    git_bash.touch()

    assert bash_executable(cwd=ROOT, platform_name='nt', git_exec_path=git_exec_path) == str(git_bash)


def test_unrelated_desktop_change_exits_as_a_green_no_op(git_repo: Path) -> None:
    desktop_sha = _commit(git_repo, 'desktop/macos/README.md')

    outputs, summary = _run_scope(git_repo, desktop_sha)

    assert outputs == {'applies': 'false', 'reason': 'unrelated'}
    assert 'Green no-op' in summary


@pytest.mark.parametrize(
    'relative_path',
    ('backend/main.py', '.github/actions/release-eligibility/action.yml'),
)
def test_backend_source_or_deploy_input_change_requires_deliberate_dispatch(git_repo: Path, relative_path: str) -> None:
    relevant_sha = _commit(git_repo, relative_path)

    outputs, _summary = _run_scope(git_repo, relevant_sha)

    assert outputs == {'applies': 'false', 'reason': 'manual-required'}


def test_active_policy_preserves_the_existing_backend_scope_decision(git_repo: Path) -> None:
    relevant_sha = _commit(git_repo, 'backend/main.py')

    outputs, _summary = _run_scope(git_repo, relevant_sha, deployment_mode='active')

    assert outputs == {'applies': 'true', 'reason': 'automatic'}


def test_superseded_backend_commit_is_a_green_no_op(git_repo: Path) -> None:
    relevant_sha = _commit(git_repo, 'backend/main.py')
    current_main = _commit(git_repo, 'README-new.md')

    outputs, summary = _run_scope(git_repo, relevant_sha, main_sha=current_main, comparison='ahead')

    assert outputs == {'applies': 'false'}
    assert 'superseded no-op' in summary


@pytest.mark.parametrize('comparison', ('behind', 'diverged'))
def test_non_ancestor_comparison_cannot_bypass_source_admission(git_repo: Path, comparison: str) -> None:
    relevant_sha = _commit(git_repo, 'backend/main.py')

    outputs, summary = _run_scope(
        git_repo, relevant_sha, main_sha='a' * 40, comparison=comparison, deployment_mode='active'
    )

    assert outputs == {'applies': 'true', 'reason': 'automatic'}
    assert 'superseded no-op' not in summary


@pytest.mark.parametrize('api_fault', ('ref-http', 'compare-http', 'malformed-json', 'wrong-url', 'wrong-base'))
def test_ambiguous_api_proof_cannot_authorize_cloud_work(git_repo: Path, api_fault: str) -> None:
    relevant_sha = _commit(git_repo, 'backend/main.py')

    outputs, summary = _run_scope(
        git_repo, relevant_sha, main_sha='a' * 40, comparison='ahead', api_fault=api_fault, expected_returncode=1
    )

    assert outputs == {}
    assert 'proof was unavailable or ambiguous' in summary


def test_unknown_comparison_status_cannot_authorize_cloud_work(git_repo: Path) -> None:
    relevant_sha = _commit(git_repo, 'backend/main.py')

    outputs, summary = _run_scope(git_repo, relevant_sha, comparison='unexpected', expected_returncode=1)

    assert outputs == {}
    assert 'proof was unavailable or ambiguous' in summary


def test_missing_parent_cannot_authorize_cloud_work(git_repo: Path) -> None:
    outputs, summary = _run_scope(git_repo, _git(git_repo, 'rev-parse', 'HEAD'), expected_returncode=1)

    assert outputs == {}
    assert 'could not resolve the triggering commit parent' in summary


def test_stale_relevant_sha_reaches_and_fails_the_existing_admission_guard(git_repo: Path) -> None:
    relevant_sha = _commit(git_repo, 'backend/main.py')
    outputs, _summary = _run_scope(git_repo, relevant_sha, deployment_mode='active')
    admission = _load_admission_script()

    assert outputs == {'applies': 'true', 'reason': 'automatic'}
    with pytest.raises(admission.AutomaticReleaseAdmissionError, match='still equal current main'):
        admission.validate(
            admission.AutomaticReleaseIdentity(
                sha=relevant_sha,
                main_sha='a' * 40,
                checkout_sha='a' * 40,
                run_attempt='1',
            )
        )


def test_scope_job_is_unprivileged_and_gates_admission_before_cloud_steps() -> None:
    workflow = yaml.safe_load(WORKFLOW_PATH.read_text(encoding='utf-8'))
    scope = workflow['jobs']['scope']
    readiness = workflow['jobs']['firestore_readiness']
    checkout = next(step for step in scope['steps'] if step.get('uses') == 'actions/checkout@v7')

    assert scope['permissions'] == {'contents': 'read'}
    assert 'environment' not in scope
    assert checkout['with'] == {'ref': '${{ github.event.workflow_run.head_sha }}', 'fetch-depth': 2}
    assert "needs.scope.outputs.applies == 'true'" in readiness['if']
    assert 'google-github-actions/auth' not in str(scope)
    assert 'gcloud' not in str(scope)
