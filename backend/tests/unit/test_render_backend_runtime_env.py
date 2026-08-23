"""Renderer for backend Cloud Run runtime env."""

import runpy
from pathlib import Path

import pytest

_SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'render_backend_runtime_env.py'
_MODULE = runpy.run_path(str(_SCRIPT), run_name='render_backend_runtime_env')
_MANIFEST = _MODULE['_load_yaml'](_MODULE['DEFAULT_MANIFEST'])


@pytest.fixture(autouse=True)
def _reuse_parsed_repo_manifest(monkeypatch):
    monkeypatch.setitem(_MODULE, '_load_yaml', lambda _path: _MANIFEST)


def _job_env_block(out: str, job_prefix: str) -> str:
    start = out.index(f'{job_prefix}_env_vars<<')
    end = out.index(f'{job_prefix}_secrets<<')
    return out[start:end]


def _job_secret_lines(out: str, job_prefix: str) -> set[str]:
    marker = f'__BACKEND_RUNTIME_ENV_{job_prefix}_secrets__'
    start = out.index(f'{job_prefix}_secrets<<{marker}')
    start = out.index('\n', start) + 1
    end = out.index(marker, start)
    return set(out[start:end].splitlines())


def test_required_env_var_missing_raises(monkeypatch):
    monkeypatch.delenv('SOME_REQUIRED_URL', raising=False)
    with pytest.raises(ValueError, match='requires'):
        _MODULE['_render_env_vars']({'REQUIRED': {'env_var': 'SOME_REQUIRED_URL'}})


def test_provisional_env_var_missing_is_omitted(monkeypatch):
    monkeypatch.delenv('SOME_PROVISIONAL_URL', raising=False)
    rendered = _MODULE['_render_env_vars'](
        {
            'SOME_PROVISIONAL_URL': {'env_var': 'SOME_PROVISIONAL_URL', 'provisional': True},
            'BILLING_MODE': {'value': 'enabled'},
        }
    )
    assert rendered == 'BILLING_MODE=enabled'


def test_provisional_env_var_present_is_rendered(monkeypatch):
    monkeypatch.setenv('SOME_PROVISIONAL_URL', 'http://10.0.0.1')
    rendered = _MODULE['_render_env_vars'](
        {'SOME_PROVISIONAL_URL': {'env_var': 'SOME_PROVISIONAL_URL', 'provisional': True}}
    )
    assert rendered == 'SOME_PROVISIONAL_URL=http://10.0.0.1'


@pytest.mark.parametrize(
    ('value', 'expected'),
    [
        ('first,second', r'first\,second'),
        (r'C:\models', r'C:\\models'),
        ('first\nsecond', 'first\\\nsecond'),
        ('first\rsecond', 'first\\\rsecond'),
        ('first\u2028second', 'first\\\u2028second'),
        ('first\u2029second', 'first\\\u2029second'),
    ],
)
def test_render_env_vars_escapes_deploy_cloudrun_separators(value, expected):
    rendered = _MODULE['_render_env_vars']({'VALUE': {'value': value}})

    assert rendered == f'VALUE={expected}'


def test_network_flags_still_required(monkeypatch):
    monkeypatch.delenv('CLOUD_RUN_VPC_NETWORK', raising=False)
    with pytest.raises(ValueError, match='requires'):
        _MODULE['_render_flags']({'--network': {'env_var': 'CLOUD_RUN_VPC_NETWORK'}})


def test_selected_job_rejects_unknown_name_without_emitting_partial_output(capsys, monkeypatch):
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'dev', '--job', 'unknown-job'])

    with pytest.raises(ValueError, match='unknown Cloud Run job'):
        _MODULE['main']()

    assert capsys.readouterr().out == ''


def test_render_prod_emits_one_canonical_backend_with_account_deletion(capsys, monkeypatch):
    monkeypatch.setenv('CLOUD_RUN_VPC_NETWORK', 'omi-prod-vpc')
    monkeypatch.setenv('CLOUD_RUN_VPC_SUBNET', 'omi-prod-subnet')
    monkeypatch.setenv('GOOGLE_CLIENT_ID', 'fake-google-client-id')
    monkeypatch.setenv(
        'ACCOUNT_DELETION_HANDLER_URL', 'https://backend.example.com/v1/users/account-deletion-wipes/run'
    )
    monkeypatch.setenv(
        'ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE', 'https://backend.example.com/v1/users/account-deletion-wipes/run'
    )
    monkeypatch.setenv('ACCOUNT_DELETION_TASKS_INVOKER_SA', 'invoker@project.iam.gserviceaccount.com')
    monkeypatch.setenv(
        'ACCOUNT_DELETION_LEGACY_TASKS_OIDC_AUDIENCE',
        'https://backend-sync.example.com/v1/users/account-deletion-wipes/run',
    )
    monkeypatch.setenv('ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA', 'legacy-invoker@project.iam.gserviceaccount.com')
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'prod'])

    assert _MODULE['main']() == 0
    output = capsys.readouterr().out

    service_env = _job_env_block(output, 'backend')
    assert 'ACCOUNT_DELETION_TASKS_QUEUE=account-deletion' in service_env
    assert 'ACCOUNT_DELETION_TASKS_MAX_ATTEMPTS=5' in service_env
    assert 'HTTP_ACCOUNT_DELETION_WIPE_RUN_TIMEOUT=1500' in service_env
    assert 'ACCOUNT_DELETION_LEGACY_TASKS_OIDC_AUDIENCE=' in service_env
    assert 'ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA=' in service_env
    assert 'backend_sync_env_vars' not in output
    assert 'OMI_LLM_GATEWAY' not in output


def test_render_prod_requires_vpc_env_vars_before_job_outputs(monkeypatch):
    """Prod network flags are env_var-backed; missing VPC vars abort rendering."""
    monkeypatch.delenv('CLOUD_RUN_VPC_NETWORK', raising=False)
    monkeypatch.delenv('CLOUD_RUN_VPC_SUBNET', raising=False)
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'prod'])
    with pytest.raises(ValueError, match='CLOUD_RUN_VPC'):
        _MODULE['main']()
