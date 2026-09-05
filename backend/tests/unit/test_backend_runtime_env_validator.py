from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/validate-backend-runtime-env.py'
READINESS_PROPOSAL_ARGS = (
    ' --proposal-output "$FIRESTORE_PROPOSAL_PATH"'
    ' --source-commit "$FIRESTORE_SOURCE_COMMIT"'
    ' --proposal-ttl-seconds 3600'
)


def load_validator():
    spec = importlib.util.spec_from_file_location('validate_backend_runtime_env', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_yaml(path: Path, payload: dict) -> None:
    with path.open('w', encoding='utf-8') as handle:
        yaml.safe_dump(payload, handle, sort_keys=False)


def validate_cloud_run_workflows_only(validator, *, env: str, manifest_path: Path, workflow_root: Path | None = None):
    """Exercise a workflow fixture without unrelated full-manifest rollout contracts."""
    manifest = validator._load_yaml(manifest_path)
    return validator._validate_cloud_run_workflows(
        env,
        validator._get_env_config(manifest, env),
        strict_provisional=False,
        manifest_path=manifest_path,
        manifest=manifest,
        workflow_root=workflow_root,
    )


def test_repo_dev_runtime_matches_manifest():
    validator = load_validator()

    errors = validator.validate_runtime_env(env='dev')

    assert errors == []


def test_repo_prod_runtime_matches_manifest():
    validator = load_validator()

    errors = validator.validate_runtime_env(env='prod')

    assert errors == []


def test_manual_workflow_exposes_only_read_only_foundation_maintenance_modes():
    workflow = yaml.safe_load((ROOT.parent / '.github/workflows/gcp_backend.yml').read_text(encoding='utf-8'))
    modes = workflow[True]['workflow_dispatch']['inputs']['mode']['options']
    job = workflow['jobs']['foundation-maintenance']
    readiness_step = next(
        step for step in job['steps'] if step.get('name') == 'Compare sanitized live foundation with the manifest'
    )
    serialized = json.dumps(job, sort_keys=True)
    runs = '\n'.join(str(step.get('run', '')) for step in job['steps'])

    assert modes == ['deploy', 'repair-traffic-only', 'foundation-readiness', 'artifact-cleanup-dry-run']
    assert 'foundation_drift.py --env="$manifest_env" --check-live' in runs
    assert 'artifact_cleanup_policy.py' in serialized
    assert '--include-tags' in serialized
    assert 'artifacts delete' not in serialized
    assert 'run revisions delete' not in serialized
    assert readiness_step['env']['REDIS_DB_HOST'] == '${{ vars.REDIS_DB_HOST }}'
    assert readiness_step['env']['REDIS_DB_PORT'] == '${{ vars.REDIS_DB_PORT }}'
    assert readiness_step['env']['REDIS_DB_CA_CERT_PEM'] == '${{ vars.REDIS_DB_CA_CERT_PEM }}'
    assert {
        'CLOUD_RUN_VPC_NETWORK',
        'CLOUD_RUN_VPC_SUBNET',
        'PRIVATE_SERVICE_ACCESS_RANGE_CIDR',
        'PRIVATE_SERVICE_ACCESS_RANGE_NAME',
        'REDIS_INSTANCE_NAME',
    }.isdisjoint(readiness_step['env'])


@pytest.mark.parametrize('env_name', ['dev', 'prod'])
def test_runtime_manifest_has_one_service_with_the_retained_configuration_union(env_name):
    validator = load_validator()
    manifest = validator._load_yaml(validator.DEFAULT_MANIFEST)
    services = manifest['environments'][env_name]['cloud_run']['services']

    assert set(services) == {'backend'}
    backend = services['backend']
    assert {
        'BILLING_MODE',
        'BASE_API_URL',
        'FIREBASE_PROJECT_ID',
        'ACCOUNT_DELETION_DISPATCH_MODE',
        'DESKTOP_UPDATE_POINTERS_MODE',
        'POSTHOG_HOST',
        'LANGFUSE_BASE_URL',
        'LANGFUSE_TRACING_ENVIRONMENT',
        'LANGFUSE_PROMPT_NAME',
        'LANGFUSE_PROMPT_CACHE_TTL_SECONDS',
        'REDIS_DB_HOST',
        'REDIS_DB_PORT',
        'REDIS_DB_CA_CERT_PEM',
    } <= set(backend['env'])
    assert {
        'GEMINI_API_KEY',
        'OPENAI_API_KEY',
        'FIREBASE_API_KEY',
        'REDIS_DB_PASSWORD',
        'LANGFUSE_PUBLIC_KEY',
        'LANGFUSE_SECRET_KEY',
    } <= set(backend['secrets'])
    if env_name == 'dev':
        assert 'MODULATE_API_KEY' in backend['secrets']
        assert {'POSTHOG_PROJECT_API_KEY', 'GOOGLE_CALENDAR_API_KEY'}.isdisjoint(backend['secrets'])
        workflow = yaml.safe_load((ROOT.parent / '.github/workflows/gcp_backend.yml').read_text(encoding='utf-8'))
        deploy_steps = workflow['jobs']['deploy']['steps']
        transcription_gate = next(
            step for step in deploy_steps if step.get('name') == 'Gate backend candidate on known audio'
        )
        assert transcription_gate['if'] == (
            "${{ github.event.inputs.environment == 'development' && vars.MODULATE_API_KEY_VERSION != '' }}"
        )
    else:
        assert {'MODULATE_API_KEY', 'POSTHOG_PROJECT_API_KEY'} <= set(backend['secrets'])
        assert 'GOOGLE_CALENDAR_API_KEY' not in backend['secrets']
    for binding_group in ('env', 'secrets'):
        assert not {name for name in backend[binding_group] if name.startswith('DODO_')}
    assert backend['env']['BILLING_MODE']['value'] == 'disabled'
    assert backend['env']['POSTHOG_HOST']['value'] == 'https://us.i.posthog.com'
    assert backend['env']['LANGFUSE_BASE_URL']['value'] == 'https://us.cloud.langfuse.com'
    assert backend['env']['LANGFUSE_PROMPT_NAME']['value'] == 'intentive-chat-system'
    assert backend['env']['LANGFUSE_PROMPT_CACHE_TTL_SECONDS']['value'] == '300'
    for binding in backend['secrets'].values():
        assert set(binding) <= {'secret', 'version_env_var'}


@pytest.mark.parametrize('env_name', ['dev', 'prod'])
def test_hosted_runtime_uses_dedicated_identity_adc_and_exact_secret_version_inputs(env_name):
    validator = load_validator()
    manifest = validator._load_yaml(validator.DEFAULT_MANIFEST)
    backend = manifest['environments'][env_name]['cloud_run']['services']['backend']

    assert backend['service_account'] == {'env_var': 'BACKEND_RUNTIME_SERVICE_ACCOUNT'}
    assert 'SERVICE_ACCOUNT_JSON' not in backend['secrets']
    assert 'SERVICE_ACCOUNT_JSON' in backend['forbidden_env']
    assert 'GOOGLE_APPLICATION_CREDENTIALS' in backend['forbidden_env']
    assert all(binding.get('version_env_var') for binding in backend['secrets'].values())
    assert all(binding.get('version') != 'latest' for binding in backend['secrets'].values())


@pytest.mark.parametrize(
    ('env_name', 'network_flags', 'cpu', 'memory', 'minimum', 'maximum', 'cpu_mode'),
    [
        ('dev', {}, '1', '2Gi', '0', '1', '--cpu-throttling'),
        ('prod', {}, '1', '2Gi', '0', '1', '--cpu-throttling'),
    ],
)
def test_canonical_cloud_run_contract_is_explicit_and_owned(
    env_name, network_flags, cpu, memory, minimum, maximum, cpu_mode
):
    validator = load_validator()
    manifest = validator._load_yaml(validator.DEFAULT_MANIFEST)
    env_config = manifest['environments'][env_name]
    cloud_run = env_config['cloud_run']
    backend = cloud_run['services']['backend']

    assert env_config['gcp_project'] == {'env_var': 'GCP_PROJECT_ID'}
    assert env_config['runtime_gcp_project'] == {'env_var': 'RUNTIME_GCP_PROJECT_ID'}
    assert env_config['region'] == 'us-west1'
    assert cloud_run['network']['flags'] == network_flags
    expected_flags = {
        '--cpu': cpu,
        '--memory': memory,
        '--concurrency': '20',
        '--timeout': '3600s',
        '--min-instances': minimum,
        '--max-instances': maximum,
        '--execution-environment': 'gen2',
        '--allow-unauthenticated': True,
        '--no-session-affinity': True,
        cpu_mode: True,
        '--no-cpu-boost': True,
        '--startup-probe': 'httpGet.path=/v1/health,periodSeconds=10,timeoutSeconds=5,failureThreshold=24',
        '--liveness-probe': 'httpGet.path=/v1/health,periodSeconds=10,timeoutSeconds=5,failureThreshold=5',
    }
    assert backend['flags'] == expected_flags


def test_cloud_run_contract_validator_rejects_capacity_and_floating_secret_drift(tmp_path):
    validator = load_validator()
    manifest = copy.deepcopy(validator._load_yaml(validator.DEFAULT_MANIFEST))
    backend = manifest['environments']['prod']['cloud_run']['services']['backend']
    backend['flags']['--cpu'] = '2'
    backend['secrets']['OPENAI_API_KEY'] = {'secret': 'OPENAI_API_KEY', 'version': 'latest'}
    manifest_path = tmp_path / 'runtime_env.yaml'
    write_yaml(manifest_path, manifest)

    errors = validator.validate_runtime_env(env='prod', manifest_path=manifest_path)

    assert any('Cloud Run flag --cpu' in error.message for error in errors)
    assert any('OPENAI_API_KEY must select an exact version input' in error.message for error in errors)


@pytest.mark.parametrize(('env_name', 'alerts'), [('dev', []), ('prod', ['health_unreachable', 'cloud_run_5xx'])])
def test_owned_foundation_contract_covers_retained_dependencies_only(env_name, alerts):
    validator = load_validator()
    foundation = validator._load_yaml(validator.DEFAULT_MANIFEST)['environments'][env_name]['foundation']

    assert foundation['network'] == {'region': 'us-west1', 'connectivity': 'public-egress'}
    assert foundation['redis'] == {
        'provider': 'upstash',
        'database': 'intentive-development',
        'region': 'us-west-2',
        'plan': 'free',
        'endpoint': {
            'host': {'env_var': 'REDIS_DB_HOST'},
            'port': {'env_var': 'REDIS_DB_PORT'},
        },
        'auth': True,
        'transit_encryption': 'TLS',
        'verification': 'runtime-tls-probe',
    }
    assert foundation['tasks']['queue'] == {
        'name': 'account-deletion',
        'location': 'us-west1',
        'max_concurrent_dispatches': 1,
        'max_attempts': 5,
        'dispatch_deadline_seconds': 1500,
        'oidc_signer': {'env_var': 'ACCOUNT_DELETION_TASKS_INVOKER_SA'},
        'handler_audience': {'env_var': 'ACCOUNT_DELETION_HANDLER_URL'},
    }
    assert foundation['gcs']['signing_method'] == 'iamcredentials.signBlob'
    assert foundation['gcs']['signing_service_account'] == {'env_var': 'BACKEND_RUNTIME_SERVICE_ACCOUNT'}
    assert foundation['alerts']['policies'] == alerts
    assert foundation['budget']['thresholds'] == [0.5, 0.8, 1.0]
    assert foundation['budget']['alert_only'] is True
    assert foundation['logging'] == {
        'bucket': '_Default',
        'retention_days': 30,
        'external_archive': False,
    }
    assert foundation['artifact_registry']['cleanup'] == {
        'dry_run_required': True,
        'delete_only_untagged_older_than_days': 30,
        'preserve_exact_release_images': True,
        'delete_cloud_run_revisions': False,
    }


def test_account_deletion_dispatch_contract_requires_canonical_backend_profile():
    validator = load_validator()
    manifest = validator._load_yaml(validator.DEFAULT_MANIFEST)
    prod = copy.deepcopy(manifest['environments']['prod'])

    assert validator._validate_account_deletion_dispatch_contract('prod', prod) == []

    backend_env = prod['cloud_run']['services']['backend']['env']
    missing_entry = backend_env.pop('ACCOUNT_DELETION_DISPATCH_MODE')
    try:
        assert validator.ValidationError(
            'prod/cloud_run/backend',
            'missing required account-deletion env ACCOUNT_DELETION_DISPATCH_MODE',
        ) in validator._validate_account_deletion_dispatch_contract('prod', prod)
    finally:
        backend_env['ACCOUNT_DELETION_DISPATCH_MODE'] = missing_entry

    dispatch_mode = backend_env['ACCOUNT_DELETION_DISPATCH_MODE']
    original_mode = dispatch_mode['value']
    dispatch_mode['value'] = 'inline'
    try:
        assert validator.ValidationError(
            'prod/cloud_run/backend',
            "account-deletion env ACCOUNT_DELETION_DISPATCH_MODE must be literal 'cloud_tasks'",
        ) in validator._validate_account_deletion_dispatch_contract('prod', prod)
    finally:
        dispatch_mode['value'] = original_mode

    prod['cloud_run']['services']['backend-sync'] = copy.deepcopy(prod['cloud_run']['services']['backend'])
    assert validator.ValidationError(
        'prod/cloud_run',
        'canonical backend must be the only Cloud Run service',
    ) in validator._validate_account_deletion_dispatch_contract('prod', prod)


def test_repo_cloud_run_workflows_match_manifest():
    validator = load_validator()

    errors = validator.validate_runtime_env(env='dev', check_workflows=True)

    assert errors == []


def test_repo_prod_cloud_run_workflows_match_manifest(monkeypatch):
    validator = load_validator()
    manifest = validator._load_yaml(validator.DEFAULT_MANIFEST)
    env_config = validator._get_env_config(manifest, 'prod')
    load_yaml = validator._load_yaml

    def load_workflow_only(path):
        if path == validator.DEFAULT_MANIFEST:
            pytest.fail('workflow validation must reuse the already-loaded runtime manifest')
        return load_yaml(path)

    monkeypatch.setattr(
        validator,
        '_load_yaml',
        load_workflow_only,
    )

    errors = validator._validate_cloud_run_workflows(
        'prod',
        env_config,
        strict_provisional=False,
        manifest_path=validator.DEFAULT_MANIFEST,
        manifest=manifest,
    )

    assert errors == []


def test_backend_and_firestore_workflows_use_environment_scoped_wif_without_json_keys():
    workflows = {
        'manual': ROOT.parent / '.github/workflows/gcp_backend.yml',
        'automatic': ROOT.parent / '.github/workflows/gcp_backend_auto_dev.yml',
        'indexes': ROOT.parent / '.github/workflows/gcp_firestore_indexes.yml',
    }
    expected_accounts = {
        'manual': {
            '${{ vars.GCP_DEPLOY_SERVICE_ACCOUNT }}',
            '${{ vars.GCP_FIRESTORE_READONLY_SERVICE_ACCOUNT }}',
        },
        'automatic': {
            '${{ vars.GCP_DEPLOY_SERVICE_ACCOUNT }}',
            '${{ vars.GCP_FIRESTORE_READONLY_SERVICE_ACCOUNT }}',
        },
        'indexes': {'${{ vars.GCP_FIRESTORE_WRITER_SERVICE_ACCOUNT }}'},
    }

    for name, path in workflows.items():
        workflow = yaml.safe_load(path.read_text(encoding='utf-8'))
        auth_steps = [
            step
            for job in workflow['jobs'].values()
            for step in job.get('steps', [])
            if step.get('uses') == 'google-github-actions/auth@v3'
            or step.get('uses') == "google-github-actions/auth@v3"
        ]

        assert auth_steps, f'{name} must authenticate to Google through WIF'
        assert {step['with']['service_account'] for step in auth_steps} == expected_accounts[name]
        assert all(
            step['with']['workload_identity_provider'] == '${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}'
            for step in auth_steps
        )
        assert all('credentials_json' not in step['with'] for step in auth_steps)
        assert all(
            job.get('permissions', {}).get('id-token') == 'write'
            for job in workflow['jobs'].values()
            if any(step in auth_steps for step in job.get('steps', []))
        )


def test_automatic_dev_runtime_contract_steps_receive_every_secret_version_input():
    """Static workflow tripwire for the runtime-manifest renderer and its preflight callers."""
    manifest = yaml.safe_load((ROOT / 'deploy/runtime_env.yaml').read_text(encoding='utf-8'))
    service_secrets = manifest['environments']['dev']['cloud_run']['services']['backend']['secrets']
    required_versions = {
        binding['version_env_var']
        for binding in service_secrets.values()
        if isinstance(binding, dict) and 'version_env_var' in binding
    }
    workflow = yaml.safe_load((ROOT.parent / '.github/workflows/gcp_backend_auto_dev.yml').read_text(encoding='utf-8'))
    contract_steps = {
        'Preflight Cloud Run deploy',
        'Render backend runtime env',
        'Check development Cloud Run runtime bindings',
        'Validate backend runtime env after deploy',
    }

    deploy_steps = {step.get('name'): step for step in workflow['jobs']['deploy']['steps']}
    assert contract_steps <= deploy_steps.keys()
    for step_name in sorted(contract_steps):
        step_env = deploy_steps[step_name].get('env', {})
        missing = sorted(required_versions - step_env.keys())
        assert missing == [], f'{step_name} does not receive secret version inputs: {missing}'


def test_workflow_validation_uses_immutable_workflow_root_with_admitted_runtime_manifest(tmp_path):
    validator = load_validator()
    workflow_path = ROOT.parent / '.github/workflows/gcp_backend.yml'
    admitted_workflow = validator._load_yaml(workflow_path)
    old_admitted_workflow = copy.deepcopy(admitted_workflow)
    old_admitted_workflow['jobs']['deploy']['steps'] = [
        step
        for step in old_admitted_workflow['jobs']['deploy']['steps']
        if step.get('name') != 'Checkout workflow-owned deploy-control source'
    ]
    assert validator.ValidationError(
        f'cloud_run_workflow/{workflow_path}',
        'backend deploy checkout must remain bound to the readiness-approved commit',
    ) in validator._validate_firestore_readiness_workflow_contract(str(workflow_path), old_admitted_workflow)

    workflow_root = tmp_path / 'workflow-source'
    staged_workflow_path = workflow_root / '.github/workflows/deploy.yml'
    staged_workflow_path.parent.mkdir(parents=True)
    write_yaml(staged_workflow_path, {'jobs': {}})
    manifest_path = tmp_path / 'admitted-runtime-env.yaml'
    write_yaml(
        manifest_path,
        {
            'schema_version': 1,
            'environments': {
                'dev': {
                    'gcp_project': 'deployment-project',
                    'runtime_gcp_project': 'serving-project',
                    'region': 'us-central1',
                    'gke': {},
                    'cloud_run': {'workflow_files': ['.github/workflows/deploy.yml'], 'services': {}, 'jobs': {}},
                }
            },
        },
    )

    assert (
        validate_cloud_run_workflows_only(
            validator, env='dev', manifest_path=manifest_path, workflow_root=workflow_root
        )
        == []
    )


def test_local_composite_actions_resolve_from_workflow_root(tmp_path):
    validator = load_validator()
    workflow_root = tmp_path / 'workflow-source'
    action_path = workflow_root / '.github/actions/workflow-root-only/action.yml'
    action_path.parent.mkdir(parents=True)
    write_yaml(
        action_path,
        {
            'runs': {
                'using': 'composite',
                'steps': [
                    {
                        'uses': 'google-github-actions/deploy-cloudrun@v2',
                        'with': {'service': 'backend', 'env_vars': 'RUNTIME_SOURCE=admitted\n'},
                    }
                ],
            }
        },
    )

    assert validator._expand_cloud_run_deploy_steps(
        {'uses': './.github/actions/workflow-root-only'}, workflow_root=workflow_root
    ) == [
        {
            'uses': 'google-github-actions/deploy-cloudrun@v2',
            'with': {'service': 'backend', 'env_vars': 'RUNTIME_SOURCE=admitted\n'},
        }
    ]


@pytest.mark.parametrize(
    ('run', 'message'),
    [
        (
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.GCP_PROJECT_ID }}" --check-only' + READINESS_PROPOSAL_ARGS,
            'Firestore index reconciliation must target vars.RUNTIME_GCP_PROJECT_ID',
        ),
        (
            'python3 backend/scripts/reconcile_firestore_indexes.py ' '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}"',
            'backend deploy Firestore reconciliation must use bounded --check-only proposal mode',
        ),
        (
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}" --check-only',
            'backend deploy Firestore reconciliation must use bounded --check-only proposal mode',
        ),
        (
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}" --check-only'
            + READINESS_PROPOSAL_ARGS.replace('3600', '7200'),
            'backend deploy Firestore reconciliation must use bounded --check-only proposal mode',
        ),
        (
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}" --check-only --provision-missing',
            'backend deploy Firestore reconciliation must use bounded --check-only proposal mode',
        ),
        (
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}" --check-only --dry-run',
            'backend deploy Firestore reconciliation must use bounded --check-only proposal mode',
        ),
        (
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}" --check-only' + READINESS_PROPOSAL_ARGS + '\n'
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}"',
            'backend deploy Firestore reconciliation must use bounded --check-only proposal mode',
        ),
        (
            '# readiness check\n'
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}" --check-only' + READINESS_PROPOSAL_ARGS + '\n'
            '# the writer below must remain visible\n'
            'python3 backend/scripts/reconcile_firestore_indexes.py '
            '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}"',
            'backend deploy Firestore reconciliation must use bounded --check-only proposal mode',
        ),
        (
            'npx firebase deploy --only firestore:indexes',
            'backend deploy Firestore operations must be read-only (--check-only)',
        ),
        (
            'npx firebase deploy',
            'backend deploy Firestore operations must be read-only (--check-only)',
        ),
        (
            'npx firebase deploy --project prod --only=firestore:indexes',
            'backend deploy Firestore operations must be read-only (--check-only)',
        ),
        (
            'gcloud --project=prod firestore indexes composite create --collection-group=memories',
            'backend deploy Firestore operations must be read-only (--check-only)',
        ),
    ],
)
def test_firestore_index_reconciliation_preserves_the_read_only_runtime_boundary(tmp_path, run, message):
    validator = load_validator()
    workflow_path = tmp_path / 'deploy.yml'
    manifest_path = tmp_path / 'runtime_env.yaml'
    workflow = {'jobs': {'deploy': {'steps': [{'run': run}]}}}
    manifest = {
        'schema_version': 1,
        'environments': {
            'dev': {
                'gcp_project': 'deployment-project',
                'runtime_gcp_project': 'serving-project',
                'region': 'us-central1',
                'gke': {},
                'cloud_run': {
                    'workflow_files': [str(workflow_path)],
                    'services': {},
                    'jobs': {},
                },
            }
        },
    }
    write_yaml(workflow_path, workflow)
    write_yaml(manifest_path, manifest)

    errors = validate_cloud_run_workflows_only(validator, env='dev', manifest_path=manifest_path)

    assert errors == [
        validator.ValidationError(
            f'cloud_run_workflow/{workflow_path}',
            message,
        )
    ]

    workflow['jobs']['deploy']['steps'][0]['run'] = (
        'python3 backend/scripts/reconcile_firestore_indexes.py '
        '--project "${{ vars.RUNTIME_GCP_PROJECT_ID }}" --check-only' + READINESS_PROPOSAL_ARGS
    )
    write_yaml(workflow_path, workflow)

    assert validate_cloud_run_workflows_only(validator, env='dev', manifest_path=manifest_path) == []


@pytest.mark.parametrize('workflow_name', ['gcp_backend.yml', 'gcp_backend_auto_dev.yml'])
def test_firestore_readiness_contract_requires_isolated_job_dependency(workflow_name):
    validator = load_validator()
    workflow_path = ROOT.parent / '.github/workflows' / workflow_name
    workflow = validator._load_yaml(workflow_path)
    workflow['jobs']['deploy'].pop('needs')

    errors = validator._validate_firestore_index_reconciliation_boundary(str(workflow_path), workflow)

    assert any('deploy must depend on the isolated Firestore readiness job' in error.message for error in errors)


def test_automatic_firestore_readiness_contract_requires_current_main_then_admitted_sha():
    validator = load_validator()
    workflow_path = ROOT.parent / '.github/workflows/gcp_backend_auto_dev.yml'
    workflow = validator._load_yaml(workflow_path)

    assert validator._validate_firestore_readiness_workflow_contract(str(workflow_path), workflow) == []

    stale_source_workflow = copy.deepcopy(workflow)
    current_main_checkout = next(
        step
        for step in stale_source_workflow['jobs']['firestore_readiness']['steps']
        if step.get('name') == 'Checkout current main for automatic source admission'
    )
    current_main_checkout['with']['ref'] = '${{ github.event.workflow_run.head_sha }}'

    errors = validator._validate_firestore_readiness_workflow_contract(str(workflow_path), stale_source_workflow)

    assert (
        validator.ValidationError(
            f'cloud_run_workflow/{workflow_path}',
            'automatic Firestore readiness must check out current main then the admitted SHA',
        )
        in errors
    )


def test_automatic_firestore_readiness_contract_requires_readiness_admitted_sha_for_deploy():
    validator = load_validator()
    workflow_path = ROOT.parent / '.github/workflows/gcp_backend_auto_dev.yml'
    workflow = validator._load_yaml(workflow_path)
    deploy_checkout = next(
        step for step in workflow['jobs']['deploy']['steps'] if step.get('uses') == 'actions/checkout@v7'
    )
    deploy_checkout['with']['ref'] = '${{ github.event.workflow_run.head_sha }}'

    errors = validator._validate_firestore_readiness_workflow_contract(str(workflow_path), workflow)

    assert (
        validator.ValidationError(
            f'cloud_run_workflow/{workflow_path}',
            'backend deploy checkout must remain bound to the readiness-approved commit',
        )
        in errors
    )


def test_manual_firestore_readiness_contract_allows_one_staged_workflow_control_checkout():
    validator = load_validator()
    workflow_path = ROOT.parent / '.github/workflows/gcp_backend.yml'
    workflow = validator._load_yaml(workflow_path)

    assert validator._validate_firestore_readiness_workflow_contract(str(workflow_path), workflow) == []

    workflow['jobs']['deploy']['steps'] = [
        step
        for step in workflow['jobs']['deploy']['steps']
        if step.get('name') != 'Checkout workflow-owned deploy-control source'
    ]
    errors = validator._validate_firestore_readiness_workflow_contract(str(workflow_path), workflow)

    assert (
        validator.ValidationError(
            f'cloud_run_workflow/{workflow_path}',
            'backend deploy checkout must remain bound to the readiness-approved commit',
        )
        in errors
    )


@pytest.mark.parametrize('workflow_name', ['gcp_backend.yml', 'gcp_backend_auto_dev.yml'])
def test_firestore_readiness_contract_requires_validation_before_artifact_upload(workflow_name):
    validator = load_validator()
    workflow_path = ROOT.parent / '.github/workflows' / workflow_name
    workflow = validator._load_yaml(workflow_path)
    steps = workflow['jobs']['firestore_readiness']['steps']
    upload_index = next(index for index, step in enumerate(steps) if step.get('uses') == 'actions/upload-artifact@v7')
    upload = steps.pop(upload_index)
    validation_index = next(
        index for index, step in enumerate(steps) if step.get('id') == 'validate_firestore_proposal'
    )
    steps.insert(validation_index, upload)

    errors = validator._validate_firestore_index_reconciliation_boundary(str(workflow_path), workflow)

    assert any('only a successfully validated bounded proposal may be uploaded' in error.message for error in errors)


@pytest.mark.parametrize('workflow_name', ['gcp_backend.yml', 'gcp_backend_auto_dev.yml'])
def test_firestore_readiness_contract_rejects_backend_deployment_credentials(workflow_name):
    validator = load_validator()
    workflow_path = ROOT.parent / '.github/workflows' / workflow_name
    workflow = validator._load_yaml(workflow_path)
    auth = next(
        step
        for step in workflow['jobs']['firestore_readiness']['steps']
        if step.get('uses') == 'google-github-actions/auth@v3'
    )
    auth['with']['credentials_json'] = '${{ secrets.GCP_CREDENTIALS }}'

    errors = validator._validate_firestore_index_reconciliation_boundary(str(workflow_path), workflow)

    assert any('must not receive backend deployment credentials' in error.message for error in errors)


def test_repo_prod_rendered_cloud_run_state_matches_manifest():
    validator = load_validator()
    manifest = validator._load_yaml(validator.DEFAULT_MANIFEST)
    env_config = validator._get_env_config(manifest, 'prod')
    rendered_state = validator._build_rendered_cloud_run_state(env_config)

    errors = validator._validate_cloud_run(env_config, rendered_state, strict_provisional=False)

    assert errors == []


def test_cloud_run_workflow_forbidden_env_requires_remove_env_vars(tmp_path):
    validator = load_validator()
    values_file = tmp_path / 'backend_listen.yaml'
    write_yaml(values_file, {'env': []})
    workflow_file = tmp_path / 'deploy.yml'
    workflow = {
        'env': {'SERVICE': 'maintenance-job'},
        'jobs': {
            'deploy': {
                'steps': [
                    {
                        'uses': 'google-github-actions/deploy-cloudrun@v2',
                        'with': {
                            'job': '${{ env.SERVICE }}',
                            'env_vars': 'GOOGLE_CLOUD_PROJECT=knowledge-athlete\n',
                            'secrets': 'SERVICE_ACCOUNT_JSON=SERVICE_ACCOUNT_JSON:latest\n',
                            'flags': '--remove-env-vars=STALE_KEY',
                        },
                    }
                ]
            }
        },
    }
    write_yaml(workflow_file, workflow)
    manifest_path = tmp_path / 'runtime_env.yaml'
    write_yaml(
        manifest_path,
        {
            'schema_version': 1,
            'environments': {
                'dev': {
                    'gcp_project': 'knowledge-athlete',
                    'runtime_gcp_project': 'knowledge-athlete',
                    'region': 'us-central1',
                    'gke': {'backend-listen': {'values_file': str(values_file), 'env': {}}},
                    'cloud_run': {
                        'workflow_files': [str(workflow_file)],
                        'services': {},
                        'jobs': {
                            'maintenance-job': {
                                'env': {'GOOGLE_CLOUD_PROJECT': {'value': 'knowledge-athlete'}},
                                'forbidden_env': ['HOSTED_PUSHER_API_URL'],
                                'secrets': {
                                    'SERVICE_ACCOUNT_JSON': {
                                        'secret': 'SERVICE_ACCOUNT_JSON',
                                        'version': 'latest',
                                    }
                                },
                            }
                        },
                    },
                }
            },
        },
    )

    errors = validate_cloud_run_workflows_only(validator, env='dev', manifest_path=manifest_path)

    assert (
        validator.ValidationError(
            'cloud_run_workflow/maintenance-job',
            'forbidden env HOSTED_PUSHER_API_URL must be listed in --remove-env-vars',
        )
        in errors
    )

    workflow['jobs'] = {
        'deploy': {
            'steps': [
                {
                    'uses': 'google-github-actions/deploy-cloudrun@v2',
                    'with': {
                        'job': '${{ env.SERVICE }}',
                        'env_vars': 'GOOGLE_CLOUD_PROJECT=knowledge-athlete\n',
                        'secrets': 'SERVICE_ACCOUNT_JSON=SERVICE_ACCOUNT_JSON:latest\n',
                        'flags': '--remove-env-vars=STALE_KEY,HOSTED_PUSHER_API_URL',
                    },
                }
            ]
        }
    }
    write_yaml(workflow_file, workflow)

    errors = validate_cloud_run_workflows_only(validator, env='dev', manifest_path=manifest_path)

    assert not any('HOSTED_PUSHER_API_URL must be listed' in error.message for error in errors)


def test_cloud_run_service_forbidden_env_requires_overwrite_without_remove_flag():
    validator = load_validator()
    scope = 'cloud_run_workflow/backend'
    forbidden = ['SERVICE_ACCOUNT_JSON', 'GOOGLE_APPLICATION_CREDENTIALS']

    assert validator._validate_forbidden_workflow_env_update(
        scope=scope,
        forbidden=forbidden,
        update_strategy='merge',
        flags={},
    ) == [
        validator.ValidationError(
            scope,
            'forbidden service env requires env_vars_update_strategy=overwrite',
        )
    ]
    assert validator._validate_forbidden_workflow_env_update(
        scope=scope,
        forbidden=forbidden,
        update_strategy='overwrite',
        flags={'--remove-env-vars': ','.join(forbidden)},
    ) == [
        validator.ValidationError(
            scope,
            'env_vars_update_strategy=overwrite must not be combined with --remove-env-vars',
        )
    ]
    assert (
        validator._validate_forbidden_workflow_env_update(
            scope=scope,
            forbidden=forbidden,
            update_strategy='overwrite',
            flags={},
        )
        == []
    )


@pytest.mark.parametrize('env_name', ['dev', 'prod'])
def test_hosted_managed_stt_surface_requires_modulate_binding(env_name):
    validator = load_validator()
    env_config = {
        'cloud_run': {
            'services': {
                'backend': {'env': {}, 'secrets': {}},
            }
        },
    }

    errors = validator._validate_managed_stt_contract(env_name, env_config)

    assert errors == [
        validator.ValidationError(
            f'{env_name}/cloud_run/backend',
            'managed transcription surface is missing non-empty MODULATE_API_KEY',
        )
    ]


def test_managed_stt_contract_accepts_fixed_modulate_bindings():
    validator = load_validator()
    cloud_secret = {'secret': 'MODULATE_API_KEY', 'version': 'latest'}
    env_config = {
        'cloud_run': {
            'services': {
                'backend': {'env': {}, 'secrets': {'MODULATE_API_KEY': cloud_secret}},
            }
        },
    }

    assert validator._validate_managed_stt_contract('prod', env_config) == []


@pytest.mark.parametrize(
    'retired_name',
    [
        'DEEPGRAM_API_KEY',
        'DEEPGRAM_SELF_HOSTED_ENABLED',
        'DEEPGRAM_SELF_HOSTED_URL',
        'HOSTED_PARAKEET_API_URL',
        'STT_PRERECORDED_MODEL',
        'STT_SERVICE_MODELS',
    ],
)
def test_managed_stt_contract_rejects_retired_provider_controls(retired_name):
    validator = load_validator()
    env_config = {
        'cloud_run': {
            'services': {
                'backend': {
                    'env': {retired_name: {'value': 'retired'}},
                    'secrets': {'MODULATE_API_KEY': {'secret': 'MODULATE_API_KEY', 'version': 'latest'}},
                }
            }
        },
    }

    assert validator._validate_managed_stt_contract('prod', env_config) == [
        validator.ValidationError(
            'prod/cloud_run/backend',
            f'retired managed STT setting is forbidden: {retired_name}',
        )
    ]


def test_repo_manifests_use_only_fixed_modulate_managed_stt_contract():
    validator = load_validator()
    for environment in ('dev', 'prod'):
        manifest = validator._load_yaml(ROOT / 'deploy/runtime_env.yaml')
        env_config = manifest['environments'][environment]
        assert validator._validate_managed_stt_contract(environment, env_config) == []


def test_empty_literal_env_matches_cloud_run_entry_without_value():
    validator = load_validator()
    errors = validator._validate_env_entries(
        scope='cloud_run/backend',
        expected={'OPTIONAL_UIDS': {'value': ''}},
        actual={'OPTIONAL_UIDS': {'name': 'OPTIONAL_UIDS'}},
        strict_provisional=False,
    )

    assert errors == []


def test_non_empty_literal_env_still_rejects_cloud_run_entry_without_value():
    validator = load_validator()
    errors = validator._validate_env_entries(
        scope='cloud_run/backend',
        expected={'BILLING_MODE': {'value': 'off'}},
        actual={'BILLING_MODE': {'name': 'BILLING_MODE'}},
        strict_provisional=False,
    )

    assert len(errors) == 1
    assert errors[0].message == "env BILLING_MODE value mismatch: expected 'off'"


def test_repo_rendered_cloud_run_matches_manifest():
    validator = load_validator()

    assert validator.validate_runtime_env(env='dev', check_rendered_cloud_run=True) == []
    assert validator.validate_runtime_env(env='prod', check_rendered_cloud_run=True) == []


@pytest.mark.parametrize('env_name', ['dev', 'prod'])
def test_missing_modulate_binding_is_rejected_for_rendered_hosted_cloud_run(tmp_path, env_name):
    validator = load_validator()
    manifest = copy.deepcopy(validator._load_yaml(ROOT / 'deploy/runtime_env.yaml'))
    services = manifest['environments'][env_name]['cloud_run']['services']
    required_services = {'backend'}
    for service_name in required_services:
        services[service_name]['secrets'].pop('MODULATE_API_KEY')

    manifest_path = tmp_path / 'runtime_env.yaml'
    write_yaml(manifest_path, manifest)

    errors = validator.validate_runtime_env(env=env_name, manifest_path=manifest_path, check_rendered_cloud_run=True)

    assert {
        (error.scope, error.message)
        for error in errors
        if error.message == 'managed transcription surface is missing non-empty MODULATE_API_KEY'
    } == {
        (
            f'{env_name}/cloud_run/{service_name}',
            'managed transcription surface is missing non-empty MODULATE_API_KEY',
        )
        for service_name in required_services
    }


def test_prod_cloud_run_secret_bindings_exclude_stale_service_account_json():
    validator = load_validator()
    manifest = validator._load_yaml(ROOT / 'deploy/runtime_env.yaml')
    prod_services = manifest['environments']['prod']['cloud_run']['services']
    stale_secrets = {'SERVICE_ACCOUNT_JSON'}

    for service_name, service_config in prod_services.items():
        secret_names = set((service_config.get('secrets') or {}).keys())
        assert stale_secrets.isdisjoint(secret_names), f'{service_name} still binds stale secrets'


# --- live Cloud Run check validates services only (this pipeline deploys no Cloud Run jobs) ---

_LIVE_SERVICE_JSON = '{"spec":{"template":{"metadata":{"annotations":{}},"spec":{"containers":[{"env":[]}]}}}}'


def _live_env_config():
    return {
        'gcp_project': 'knowledge-athlete',
        'region': 'us-central1',
        'cloud_run': {
            'services': {
                'backend': {'deployment_name': {'env_var': 'BACKEND_CLOUD_RUN_SERVICE'}},
            },
            'jobs': {'maintenance-job': {}},
        },
    }


def test_fetch_live_cloud_run_state_validates_services_only(monkeypatch):
    # gcp_backend.yml deploys Cloud Run services, not jobs. The live check must
    # describe services only and never run `gcloud run jobs describe`.
    validator = load_validator()
    described = []
    monkeypatch.setenv('BACKEND_CLOUD_RUN_SERVICE', 'knowledge-athlete-dev')

    def fake_run(command, **kwargs):
        described.append(command)
        assert 'jobs' not in command, f'must not describe Cloud Run jobs: {command}'
        return SimpleNamespace(returncode=0, stdout=_LIVE_SERVICE_JSON, stderr='')

    monkeypatch.setattr(validator.subprocess, 'run', fake_run)
    state = validator._fetch_live_cloud_run_state(_live_env_config())

    assert 'jobs' not in state  # no live job state → consumer skips job env checks
    assert 'backend' in state['services']  # services are still fetched + validated
    assert any('services' in cmd for cmd in described)
    assert all('knowledge-athlete-dev' in cmd for cmd in described)
    assert all('backend' not in cmd for cmd in described)


def test_fetch_live_cloud_run_state_rejects_missing_deployment_binding_before_gcloud(monkeypatch):
    validator = load_validator()
    env_config = _live_env_config()
    env_config['cloud_run']['services']['backend'] = {}
    commands = []

    monkeypatch.setattr(validator.subprocess, 'run', lambda command, **_kwargs: commands.append(command))

    with pytest.raises(ValueError, match='backend deployment_name requires its declared external input'):
        validator._fetch_live_cloud_run_state(env_config)

    assert commands == []


def test_manifest_requires_environment_owned_cloud_run_deployment_name(tmp_path):
    validator = load_validator()
    manifest = copy.deepcopy(validator._load_yaml(ROOT / 'deploy/runtime_env.yaml'))
    manifest['environments']['dev']['cloud_run']['services']['backend'].pop('deployment_name', None)
    manifest_path = tmp_path / 'runtime_env.yaml'
    write_yaml(manifest_path, manifest)

    errors = validator.validate_runtime_env(env='dev', manifest_path=manifest_path)

    assert any(
        error.scope == 'dev/cloud_run/backend'
        and error.message == 'deployment_name must bind $BACKEND_CLOUD_RUN_SERVICE'
        for error in errors
    )


def test_live_cloud_run_describe_normalizes_capacity_identity_and_probe_contract(monkeypatch):
    validator = load_validator()
    env_config = validator._load_yaml(validator.DEFAULT_MANIFEST)['environments']['prod']
    monkeypatch.setenv('GCP_PROJECT_ID', 'owned-prod')
    monkeypatch.setenv('BACKEND_CLOUD_RUN_SERVICE', 'intentive-production')
    document = {
        'spec': {
            'template': {
                'metadata': {
                    'annotations': {
                        'autoscaling.knative.dev/minScale': '1',
                        'autoscaling.knative.dev/maxScale': '10',
                        'run.googleapis.com/execution-environment': 'gen2',
                        'run.googleapis.com/cpu-throttling': 'false',
                        'run.googleapis.com/startup-cpu-boost': 'false',
                        'run.googleapis.com/sessionAffinity': 'false',
                        'run.googleapis.com/network-interfaces': '[{"network":"owned-vpc","subnetwork":"owned-subnet"}]',
                        'run.googleapis.com/vpc-access-egress': 'private-ranges-only',
                    }
                },
                'spec': {
                    'serviceAccountName': 'runtime@owned-prod.iam.gserviceaccount.com',
                    'containerConcurrency': 20,
                    'timeoutSeconds': 3600,
                    'containers': [
                        {
                            'env': [],
                            'resources': {'limits': {'cpu': '2', 'memory': '4Gi'}},
                            'startupProbe': {
                                'httpGet': {'path': '/v1/health'},
                                'periodSeconds': 10,
                                'timeoutSeconds': 5,
                                'failureThreshold': 24,
                            },
                            'livenessProbe': {
                                'httpGet': {'path': '/v1/health'},
                                'periodSeconds': 10,
                                'timeoutSeconds': 5,
                                'failureThreshold': 5,
                            },
                        }
                    ],
                },
            }
        }
    }
    monkeypatch.setattr(
        validator.subprocess,
        'run',
        lambda command, **kwargs: SimpleNamespace(returncode=0, stdout=json.dumps(document), stderr=''),
    )

    flags = validator._fetch_live_cloud_run_state(env_config)['services']['backend']['flags']

    assert flags['--cpu'] == '2'
    assert flags['--memory'] == '4Gi'
    assert flags['--timeout'] == '3600s'
    assert flags['--service-account'] == 'runtime@owned-prod.iam.gserviceaccount.com'
    assert flags['--no-cpu-throttling'] == 'true'
    assert flags['--startup-probe'].startswith('httpGet.path=/v1/health,periodSeconds=10')


def test_live_cloud_run_normalizes_default_scale_affinity_and_public_iam(monkeypatch):
    validator = load_validator()
    monkeypatch.setenv('BACKEND_CLOUD_RUN_SERVICE', 'knowledge-athlete-dev')
    service_document = {
        'spec': {
            'template': {
                'metadata': {'annotations': {}},
                'spec': {'containers': [{'env': []}]},
            }
        }
    }
    iam_policy = {
        'bindings': [
            {
                'role': 'roles/run.invoker',
                'members': ['allUsers', 'serviceAccount:tasks@knowledge-athlete.iam.gserviceaccount.com'],
            }
        ]
    }

    def fake_run(command, **_kwargs):
        document = iam_policy if 'get-iam-policy' in command else service_document
        return SimpleNamespace(returncode=0, stdout=json.dumps(document), stderr='')

    monkeypatch.setattr(validator.subprocess, 'run', fake_run)

    flags = validator._fetch_live_cloud_run_state(_live_env_config())['services']['backend']['flags']
    errors = validator._validate_workflow_flags(
        scope='cloud_run/backend',
        expected={
            '--min-instances': '0',
            '--allow-unauthenticated': True,
            '--no-session-affinity': True,
        },
        actual=flags,
        strict_provisional=False,
    )

    assert errors == []


def test_live_cloud_run_public_flag_requires_unconditional_all_users_invoker():
    validator = load_validator()

    flags = validator._cloud_run_service_flags_from_state(
        annotations={},
        template_spec={},
        container={},
        iam_policy={
            'bindings': [
                {
                    'role': 'roles/run.invoker',
                    'members': ['allUsers'],
                    'condition': {'expression': 'request.time < timestamp("2027-01-01T00:00:00Z")'},
                }
            ]
        },
    )
    errors = validator._validate_workflow_flags(
        scope='cloud_run/backend',
        expected={'--allow-unauthenticated': True},
        actual=flags,
        strict_provisional=False,
    )

    assert [(error.scope, error.message) for error in errors] == [
        ('cloud_run/backend', 'missing Cloud Run flag --allow-unauthenticated')
    ]


def test_live_cloud_run_describe_normalizes_request_based_cpu() -> None:
    validator = load_validator()

    flags = validator._cloud_run_service_flags_from_state(
        annotations={'run.googleapis.com/cpu-throttling': 'true'},
        template_spec={},
        container={},
    )

    assert flags['--cpu-throttling'] == 'true'
    assert '--no-cpu-throttling' not in flags
