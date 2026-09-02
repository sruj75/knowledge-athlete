"""Renderer for backend Cloud Run runtime env."""

import json
import runpy
from pathlib import Path

import pytest

_SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'render_backend_runtime_env.py'
_MODULE = runpy.run_path(str(_SCRIPT), run_name='render_backend_runtime_env')
_MANIFEST = _MODULE['_load_yaml'](_MODULE['DEFAULT_MANIFEST'])


@pytest.fixture(autouse=True)
def _reuse_parsed_repo_manifest(monkeypatch):
    monkeypatch.setitem(_MODULE, '_load_yaml', lambda _path: _MANIFEST)
    monkeypatch.setenv('BACKEND_RUNTIME_SERVICE_ACCOUNT', 'backend-runtime@example.iam.gserviceaccount.com')
    monkeypatch.setenv('GCP_PROJECT_ID', 'owned-project')
    monkeypatch.setenv('RUNTIME_GCP_PROJECT_ID', 'owned-runtime-project')
    monkeypatch.setenv('FIREBASE_AUTH_PROJECT_ID', 'owned-firebase-project')
    monkeypatch.setenv('REDIS_DB_HOST', 'redis.internal.example')
    monkeypatch.setenv('REDIS_DB_PORT', '6378')
    monkeypatch.setenv('REDIS_DB_CA_CERT_PEM', 'fake-ca')
    monkeypatch.setenv('BUCKET_DESKTOP_UPDATES', 'owned-desktop-artifacts')
    for env_config in _MANIFEST['environments'].values():
        backend = env_config['cloud_run']['services']['backend']
        for binding in backend['secrets'].values():
            version_env_var = binding.get('version_env_var')
            if version_env_var:
                monkeypatch.setenv(version_env_var, '7')


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


def _output_value(out: str, name: str) -> str:
    marker = f'__BACKEND_RUNTIME_ENV_{name}__'
    start = out.index(f'{name}<<{marker}')
    start = out.index('\n', start) + 1
    end = out.index(marker, start)
    return out[start:end].strip()


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


def test_secret_binding_requires_exact_non_latest_version(monkeypatch):
    monkeypatch.delenv('PRIVATE_SETTING_VERSION', raising=False)
    with pytest.raises(ValueError, match='PRIVATE_SETTING_VERSION'):
        _MODULE['_render_secrets'](
            {'PRIVATE_SETTING': {'secret': 'private-setting', 'version_env_var': 'PRIVATE_SETTING_VERSION'}}
        )

    with pytest.raises(ValueError, match='exact version'):
        _MODULE['_render_secrets']({'PRIVATE_SETTING': {'secret': 'private-setting', 'version': 'latest'}})


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
    assert 'LANGFUSE_BASE_URL=https://us.cloud.langfuse.com' in service_env
    assert 'LANGFUSE_TRACING_ENVIRONMENT=production' in service_env
    assert 'LANGFUSE_PROMPT_NAME=intentive-chat-system' in service_env
    assert 'LANGFUSE_PROMPT_CACHE_TTL_SECONDS=300' in service_env
    assert 'LANGFUSE_PUBLIC_KEY=LANGFUSE_PUBLIC_KEY:7' in _job_secret_lines(output, 'backend')
    assert 'LANGFUSE_SECRET_KEY=LANGFUSE_SECRET_KEY:7' in _job_secret_lines(output, 'backend')
    assert 'backend_sync_env_vars' not in output
    assert 'OMI_LLM_GATEWAY' not in output


def test_render_dev_emits_free_tier_cloud_run_without_private_network(capsys, monkeypatch):
    monkeypatch.delenv('CLOUD_RUN_VPC_NETWORK', raising=False)
    monkeypatch.delenv('CLOUD_RUN_VPC_SUBNET', raising=False)
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
        'https://legacy.example.com/v1/users/account-deletion-wipes/run',
    )
    monkeypatch.setenv('ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA', 'legacy@project.iam.gserviceaccount.com')
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'dev'])

    assert _MODULE['main']() == 0
    output = capsys.readouterr().out

    assert _output_value(output, 'cloud_run_flags') == ''
    service_flags = _output_value(output, 'backend_flags')
    assert '--cpu=1' in service_flags
    assert '--memory=2Gi' in service_flags
    assert '--min-instances=0' in service_flags
    assert '--max-instances=1' in service_flags
    assert '--cpu-throttling' in service_flags
    assert '--no-cpu-throttling' not in service_flags


def test_render_foundation_is_deterministic_redacted_and_lists_external_inputs(capsys, monkeypatch):
    monkeypatch.setenv('CLOUD_RUN_VPC_NETWORK', 'owned-prod-vpc')
    monkeypatch.setenv('CLOUD_RUN_VPC_SUBNET', 'owned-prod-subnet')
    monkeypatch.setenv('GOOGLE_CLIENT_ID', 'fake-google-client-id')
    monkeypatch.setenv('ACCOUNT_DELETION_HANDLER_URL', 'https://backend.example.run.app/delete')
    monkeypatch.setenv('ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE', 'https://backend.example.run.app/delete')
    monkeypatch.setenv('ACCOUNT_DELETION_TASKS_INVOKER_SA', 'tasks@example.iam.gserviceaccount.com')
    monkeypatch.setenv('ACCOUNT_DELETION_LEGACY_TASKS_OIDC_AUDIENCE', 'https://legacy.example.run.app/delete')
    monkeypatch.setenv('ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA', 'legacy@example.iam.gserviceaccount.com')
    monkeypatch.setenv('GCP_BUDGET_RECIPIENTS', 'private-owner@example.com')
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'prod'])

    assert _MODULE['main']() == 0
    output = capsys.readouterr().out
    rendered = _output_value(output, 'foundation_contract')
    required_inputs = _output_value(output, 'foundation_required_inputs').split(',')

    contract = json.loads(rendered)
    assert contract['network']['region'] == 'us-west1'
    assert contract['redis']['tier'] == 'STANDARD_HA'
    assert contract['budget']['thresholds'] == [0.5, 0.8, 1.0]
    assert contract['budget']['recipients'] == {'env_var': 'GCP_BUDGET_RECIPIENTS'}
    assert 'private-owner@example.com' not in rendered
    assert required_inputs == sorted(required_inputs)
    assert 'GCP_BUDGET_RECIPIENTS' in required_inputs
    assert 'GCP_WORKLOAD_IDENTITY_PROVIDER' in required_inputs


def test_render_prod_requires_vpc_env_vars_before_job_outputs(monkeypatch):
    """Prod network flags are env_var-backed; missing VPC vars abort rendering."""
    monkeypatch.delenv('CLOUD_RUN_VPC_NETWORK', raising=False)
    monkeypatch.delenv('CLOUD_RUN_VPC_SUBNET', raising=False)
    monkeypatch.setattr('sys.argv', ['render_backend_runtime_env.py', '--env', 'prod'])
    with pytest.raises(ValueError, match='CLOUD_RUN_VPC'):
        _MODULE['main']()
