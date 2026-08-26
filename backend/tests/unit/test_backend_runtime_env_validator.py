from __future__ import annotations

import copy
import importlib.util
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


@pytest.mark.parametrize('env_name', ['dev', 'prod'])
def test_runtime_manifest_has_one_service_with_the_retained_configuration_union(env_name):
    validator = load_validator()
    manifest = validator._load_yaml(validator.DEFAULT_MANIFEST)
    services = manifest['environments'][env_name]['cloud_run']['services']

    assert set(services) == {'backend'}
    backend = services['backend']
    assert {
        'BILLING_MODE',
        'FIREBASE_PROJECT_ID',
        'ACCOUNT_DELETION_DISPATCH_MODE',
        'DESKTOP_UPDATE_POINTERS_MODE',
        'POSTHOG_HOST',
    } <= set(backend['env'])
    assert {
        'MODULATE_API_KEY',
        'GEMINI_API_KEY',
        'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY',
        'FIREBASE_API_KEY',
        'REDIS_DB_HOST',
        'REDIS_DB_PORT',
        'REDIS_DB_PASSWORD',
        'POSTHOG_PROJECT_API_KEY',
    } <= set(backend['secrets'])
    assert backend['env']['BILLING_MODE']['value'] == 'disabled'
    for binding in backend['secrets'].values():
        assert set(binding) <= {'secret', 'version'}


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
                            'env_vars': 'GOOGLE_CLOUD_PROJECT=based-hardware\n',
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
                    'gcp_project': 'based-hardware',
                    'runtime_gcp_project': 'based-hardware',
                    'region': 'us-central1',
                    'gke': {'backend-listen': {'values_file': str(values_file), 'env': {}}},
                    'cloud_run': {
                        'workflow_files': [str(workflow_file)],
                        'services': {},
                        'jobs': {
                            'maintenance-job': {
                                'env': {'GOOGLE_CLOUD_PROJECT': {'value': 'based-hardware'}},
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
                        'env_vars': 'GOOGLE_CLOUD_PROJECT=based-hardware\n',
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


def test_managed_stt_surfaces_require_modulate_binding():
    validator = load_validator()
    env_config = {
        'cloud_run': {
            'services': {
                'backend': {'env': {}, 'secrets': {}},
            }
        },
    }

    errors = validator._validate_managed_stt_contract('dev', env_config)

    assert errors == [
        validator.ValidationError(
            scope,
            'managed transcription surface is missing non-empty MODULATE_API_KEY',
        )
        for scope in ('dev/cloud_run/backend',)
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


def test_missing_modulate_binding_is_rejected_for_rendered_cloud_run(tmp_path):
    validator = load_validator()
    manifest = copy.deepcopy(validator._load_yaml(ROOT / 'deploy/runtime_env.yaml'))
    services = manifest['environments']['dev']['cloud_run']['services']
    required_services = {'backend'}
    for service_name in required_services:
        services[service_name]['secrets'].pop('MODULATE_API_KEY')

    manifest_path = tmp_path / 'runtime_env.yaml'
    write_yaml(manifest_path, manifest)

    errors = validator.validate_runtime_env(env='dev', manifest_path=manifest_path, check_rendered_cloud_run=True)

    assert {
        (error.scope, error.message)
        for error in errors
        if error.message == 'managed transcription surface is missing non-empty MODULATE_API_KEY'
    } == {
        (
            f'dev/cloud_run/{service_name}',
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
        'gcp_project': 'based-hardware',
        'region': 'us-central1',
        'cloud_run': {
            'services': {'backend': {}},
            'jobs': {'maintenance-job': {}},
        },
    }


def test_fetch_live_cloud_run_state_validates_services_only(monkeypatch):
    # gcp_backend.yml deploys Cloud Run services, not jobs. The live check must
    # describe services only and never run `gcloud run jobs describe`.
    validator = load_validator()
    described = []

    def fake_run(command, **kwargs):
        described.append(command)
        assert 'jobs' not in command, f'must not describe Cloud Run jobs: {command}'
        return SimpleNamespace(returncode=0, stdout=_LIVE_SERVICE_JSON, stderr='')

    monkeypatch.setattr(validator.subprocess, 'run', fake_run)
    state = validator._fetch_live_cloud_run_state(_live_env_config())

    assert 'jobs' not in state  # no live job state → consumer skips job env checks
    assert 'backend' in state['services']  # services are still fetched + validated
    assert any('services' in cmd for cmd in described)
