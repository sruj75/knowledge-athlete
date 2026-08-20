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
    monkeypatch.delenv('OMI_LLM_GATEWAY_URL', raising=False)
    rendered = _MODULE['_render_env_vars'](
        {
            'OMI_LLM_GATEWAY_URL': {'env_var': 'OMI_LLM_GATEWAY_URL', 'provisional': True},
            'BILLING_MODE': {'value': 'enabled'},
        }
    )
    assert rendered == 'BILLING_MODE=enabled'


def test_provisional_env_var_present_is_rendered(monkeypatch):
    monkeypatch.setenv('OMI_LLM_GATEWAY_URL', 'http://10.0.0.1')
    rendered = _MODULE['_render_env_vars'](
        {'OMI_LLM_GATEWAY_URL': {'env_var': 'OMI_LLM_GATEWAY_URL', 'provisional': True}}
    )
    assert rendered == 'OMI_LLM_GATEWAY_URL=http://10.0.0.1'


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


def test_selected_job_renders_only_shared_network_and_named_job_outputs(capsys, monkeypatch):
    monkeypatch.setenv('CLOUD_RUN_VPC_NETWORK', 'omi-dev-vpc-1')
    monkeypatch.setenv('CLOUD_RUN_VPC_SUBNET', 'omi-dev-subnet-1')
    monkeypatch.setattr(
        'sys.argv',
        ['render_backend_runtime_env.py', '--env', 'dev', '--job', 'notifications-job'],
    )

    assert _MODULE['main']() == 0

    output = capsys.readouterr().out
    assert 'cloud_run_flags<<' in output
    assert 'notifications_job_env_vars<<' in output
    assert 'backend_env_vars<<' not in output


def test_selected_job_rejects_unknown_name_without_emitting_partial_output(capsys, monkeypatch):
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'dev', '--job', 'unknown-job'])

    with pytest.raises(ValueError, match='unknown Cloud Run job'):
        _MODULE['main']()

    assert capsys.readouterr().out == ''


def test_render_prod_gateway_callers_inject_verified_endpoint(capsys, monkeypatch):
    monkeypatch.setenv('CLOUD_RUN_VPC_NETWORK', 'omi-prod-vpc')
    monkeypatch.setenv('CLOUD_RUN_VPC_SUBNET', 'omi-prod-subnet')
    monkeypatch.setenv('GOOGLE_CLIENT_ID', 'fake-google-client-id')
    monkeypatch.setenv(
        'ACCOUNT_DELETION_HANDLER_URL', 'https://backend-sync.example.com/v1/users/account-deletion-wipes/run'
    )
    monkeypatch.setenv(
        'LISTEN_FINALIZATION_TASKS_HANDLER_URL',
        'https://backend-sync.example.com/v1/conversation-finalization-jobs/run',
    )
    monkeypatch.setenv('LISTEN_FINALIZATION_TASKS_INVOKER_SA', 'invoker@project.iam.gserviceaccount.com')
    monkeypatch.setenv('SYNC_TASKS_HANDLER_URL', 'https://backend-sync.example.com/v2/sync-jobs/run')
    monkeypatch.setenv('SYNC_TASKS_INVOKER_SA', 'invoker@project.iam.gserviceaccount.com')
    monkeypatch.setenv('OMI_LLM_GATEWAY_URL', 'http://172.16.160.108')
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'prod'])

    assert _MODULE['main']() == 0
    output = capsys.readouterr().out

    for service in ('backend', 'backend_sync'):
        service_env = _job_env_block(output, service)
        assert 'OMI_LLM_GATEWAY_FEATURE_MODE=gateway' in service_env
        assert 'OMI_LLM_GATEWAY_URL=http://172.16.160.108' in service_env
        assert 'OMI_LLM_GATEWAY_URL=http://127.0.0.1:9' not in service_env


def test_render_prod_requires_vpc_env_vars_before_job_outputs(monkeypatch):
    """Prod network flags are env_var-backed; missing VPC vars abort rendering."""
    monkeypatch.delenv('CLOUD_RUN_VPC_NETWORK', raising=False)
    monkeypatch.delenv('CLOUD_RUN_VPC_SUBNET', raising=False)
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'prod'])
    with pytest.raises(ValueError, match='CLOUD_RUN_VPC'):
        _MODULE['main']()


def test_notifications_job_workflow_passes_vpc_vars_and_checkout_sha():
    workflow = Path(__file__).resolve().parents[3] / '.github/workflows/gcp_notifications_job.yml'
    text = workflow.read_text(encoding='utf-8')
    assert 'CLOUD_RUN_VPC_NETWORK: ${{ vars.CLOUD_RUN_VPC_NETWORK }}' in text
    assert 'CLOUD_RUN_VPC_SUBNET: ${{ vars.CLOUD_RUN_VPC_SUBNET }}' in text
    assert 'git rev-parse --short=7 HEAD' in text
    assert 'short_sha=${GITHUB_SHA::7}' not in text
    assert 'render_backend_runtime_env.py --env ${{ vars.ENV }} --job notifications-job' in text
    assert 'env_vars_update_strategy: overwrite' not in text
    assert 'secrets_update_strategy: overwrite' not in text
