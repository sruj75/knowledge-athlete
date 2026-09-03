from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = BACKEND_ROOT / 'scripts' / 'preflight-cloud-run-deploy.py'

_SECRET_VERSION_INPUTS = (
    'DESKTOP_PREVIEW_PUBLISH_KEY_VERSION',
    'BETA_PROMOTION_TOKEN_VERSION',
    'GOOGLE_CLIENT_SECRET_VERSION',
    'POSTHOG_PROJECT_API_KEY_VERSION',
    'LANGFUSE_PUBLIC_KEY_VERSION',
    'LANGFUSE_SECRET_KEY_VERSION',
    'MODULATE_API_KEY_VERSION',
    'GEMINI_API_KEY_VERSION',
    'OPENAI_API_KEY_VERSION',
    'FIREBASE_API_KEY_VERSION',
    'REDIS_DB_PASSWORD_VERSION',
)


@pytest.fixture(autouse=True)
def _exact_secret_version_inputs(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in _SECRET_VERSION_INPUTS:
        monkeypatch.setenv(name, '7')
    monkeypatch.setenv('GCP_PROJECT_ID', 'owned-project')


def load_preflight():
    spec = importlib.util.spec_from_file_location('preflight_cloud_run_deploy', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_check_rendered_secrets_reports_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    preflight = load_preflight()
    monkeypatch.setattr(preflight, '_secret_exists', lambda **kwargs: False)

    missing = preflight.check_rendered_secrets(
        env='prod',
        manifest_path=BACKEND_ROOT / 'deploy/runtime_env.yaml',
        project='intentive-production-test',
    )

    secret_names = {item.secret_name for item in missing}
    assert 'BETA_PROMOTION_TOKEN' in secret_names
    assert 'LANGFUSE_PUBLIC_KEY' in secret_names
    assert 'LANGFUSE_SECRET_KEY' in secret_names
    assert 'GOOGLE_CLIENT_ID' not in secret_names


def test_check_rendered_secrets_passes_when_secrets_exist(monkeypatch: pytest.MonkeyPatch) -> None:
    preflight = load_preflight()
    monkeypatch.setattr(preflight, '_secret_exists', lambda **kwargs: True)

    missing = preflight.check_rendered_secrets(
        env='prod',
        manifest_path=BACKEND_ROOT / 'deploy/runtime_env.yaml',
        project='intentive-production-test',
    )

    assert missing == []


def test_development_manifest_includes_owned_provider_secrets_and_excludes_retired_ones() -> None:
    preflight = load_preflight()
    manifest = preflight.render_backend_runtime_env._load_yaml(BACKEND_ROOT / 'deploy/runtime_env.yaml')
    secrets = manifest['environments']['dev']['cloud_run']['services']['backend']['secrets']

    assert 'GEMINI_API_KEY' in secrets
    assert 'OPENAI_API_KEY' in secrets
    assert 'MODULATE_API_KEY' in secrets
    assert 'LANGFUSE_PUBLIC_KEY' in secrets
    assert 'LANGFUSE_SECRET_KEY' in secrets
    assert {'POSTHOG_PROJECT_API_KEY', 'GOOGLE_CALENDAR_API_KEY'}.isdisjoint(secrets)


def test_parse_revision_targets_rejects_blank_values() -> None:
    preflight = load_preflight()

    with pytest.raises(ValueError, match='non-empty SERVICE and REVISION'):
        preflight._parse_revision_targets(['backend='])


def test_parse_revision_targets_rejects_missing_equals() -> None:
    preflight = load_preflight()

    with pytest.raises(ValueError, match='SERVICE=REVISION'):
        preflight._parse_revision_targets(['backend'])


def test_runtime_binding_check_accepts_manifest_literal_and_secret_bindings_read_only(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    preflight = load_preflight()
    monkeypatch.setenv('BACKEND_CLOUD_RUN_SERVICE', 'knowledge-athlete-dev')
    manifest = tmp_path / 'runtime_env.yaml'
    manifest.write_text(
        '''\
environments:
  dev:
    gcp_project: knowledge-athlete
    cloud_run:
      services:
        backend:
          deployment_name:
            env_var: BACKEND_CLOUD_RUN_SERVICE
          env:
            PUBLIC_SETTING:
              value: public
          secrets:
            PRIVATE_SETTING:
              secret: expected-secret
              version: '7'
''',
        encoding='utf-8',
    )
    commands: list[list[str]] = []
    document = {
        'spec': {
            'template': {
                'spec': {
                    'containers': [
                        {
                            'env': [
                                {'name': 'PUBLIC_SETTING', 'value': 'public'},
                                {
                                    'name': 'PRIVATE_SETTING',
                                    'valueFrom': {'secretKeyRef': {'name': 'expected-secret', 'key': '7'}},
                                },
                            ]
                        }
                    ]
                }
            }
        }
    }

    def runner(command: list[str], **_kwargs):
        commands.append(command)
        return SimpleNamespace(stdout=json.dumps(document))

    drift = preflight.check_runtime_bindings(
        services=('backend',),
        env='dev',
        project='knowledge-athlete',
        region='us-central1',
        manifest_path=manifest,
        runner=runner,
    )

    assert drift == []
    assert commands == [
        [
            'gcloud',
            'run',
            'services',
            'describe',
            'knowledge-athlete-dev',
            '--project=knowledge-athlete',
            '--region=us-central1',
            '--format=json',
        ]
    ]
    assert not any('update' in command or 'remove' in command for command in commands)


def test_runtime_binding_check_reports_manifest_declared_secret_missing_from_live_service(tmp_path: Path) -> None:
    preflight = load_preflight()
    manifest = tmp_path / 'runtime_env.yaml'
    manifest.write_text(
        '''\
environments:
  dev:
    gcp_project: knowledge-athlete
    cloud_run:
      services:
        backend:
          deployment_name:
            value: knowledge-athlete-dev
          secrets:
            PRIVATE_SETTING:
              secret: expected-secret
              version: '7'
''',
        encoding='utf-8',
    )
    document = {'spec': {'template': {'spec': {'containers': [{'env': []}]}}}}

    drift = preflight.check_runtime_bindings(
        services=('backend',),
        env='dev',
        project='knowledge-athlete',
        region='us-central1',
        manifest_path=manifest,
        runner=lambda _command, **_kwargs: SimpleNamespace(stdout=json.dumps(document)),
    )

    assert drift == [
        'runtime-binding/backend/PRIVATE_SETTING: expected Secret Manager reference expected-secret:7, binding is missing'
    ]


def test_runtime_binding_check_rejects_missing_deployment_name_without_querying_cloud_run(tmp_path: Path) -> None:
    preflight = load_preflight()
    manifest = tmp_path / 'runtime_env.yaml'
    manifest.write_text(
        '''\
environments:
  dev:
    gcp_project: knowledge-athlete
    cloud_run:
      services:
        backend:
          env: {}
          secrets: {}
''',
        encoding='utf-8',
    )
    commands: list[list[str]] = []

    with pytest.raises(ValueError, match='Cloud Run service backend deployment_name is missing'):
        preflight.check_runtime_bindings(
            services=('backend',),
            env='dev',
            project='knowledge-athlete',
            region='us-central1',
            manifest_path=manifest,
            runner=lambda command, **_kwargs: commands.append(command),
        )

    assert commands == []


def test_runtime_binding_check_rejects_multi_container_live_service_shape(tmp_path: Path) -> None:
    preflight = load_preflight()
    manifest = tmp_path / 'runtime_env.yaml'
    manifest.write_text(
        '''\
environments:
  dev:
    gcp_project: knowledge-athlete
    cloud_run:
      services:
        backend:
          deployment_name:
            value: knowledge-athlete-dev
          env:
            PUBLIC_SETTING:
              value: public
''',
        encoding='utf-8',
    )
    document = {
        'spec': {
            'template': {
                'spec': {
                    'containers': [
                        {'env': [{'name': 'PUBLIC_SETTING', 'value': 'public'}]},
                        {'env': []},
                    ]
                }
            }
        }
    }

    with pytest.raises(ValueError, match='exactly one container'):
        preflight.check_runtime_bindings(
            services=('backend',),
            env='dev',
            project='knowledge-athlete',
            region='us-central1',
            manifest_path=manifest,
            runner=lambda _command, **_kwargs: SimpleNamespace(stdout=json.dumps(document)),
        )


def test_runtime_binding_check_propagates_gcloud_describe_failure(tmp_path: Path) -> None:
    preflight = load_preflight()
    manifest = tmp_path / 'runtime_env.yaml'
    manifest.write_text(
        '''\
environments:
  dev:
    gcp_project: knowledge-athlete
    cloud_run:
      services:
        backend:
          deployment_name:
            value: knowledge-athlete-dev
          env:
            PUBLIC_SETTING:
              value: public
''',
        encoding='utf-8',
    )
    command = ['gcloud', 'run', 'services', 'describe', 'backend']

    def failing_runner(_command: list[str], **_kwargs):
        raise subprocess.CalledProcessError(returncode=1, cmd=command, stderr='describe failed')

    with pytest.raises(subprocess.CalledProcessError, match='returned non-zero exit status 1'):
        preflight.check_runtime_bindings(
            services=('backend',),
            env='dev',
            project='knowledge-athlete',
            region='us-central1',
            manifest_path=manifest,
            runner=failing_runner,
        )


def test_runtime_binding_check_ignores_undeclared_live_bindings(tmp_path: Path) -> None:
    preflight = load_preflight()
    manifest = tmp_path / 'runtime_env.yaml'
    manifest.write_text(
        '''\
environments:
  dev:
    gcp_project: knowledge-athlete
    cloud_run:
      services:
        backend:
          deployment_name:
            value: knowledge-athlete-dev
          env:
            GLOBAL_PUBLIC:
              value: global
          secrets:
            GLOBAL_SECRET:
              secret: inherited-secret
              version: '3'
        backend-beta:
          deployment_name:
            value: knowledge-athlete-beta
          env:
            RETAINED_PUBLIC:
              value: retained
          secrets:
            RETAINED_SECRET:
              secret: retained-secret
              version: '7'
''',
        encoding='utf-8',
    )
    document = {
        'spec': {
            'template': {
                'spec': {
                    'containers': [
                        {
                            'env': [
                                {
                                    'name': 'GLOBAL_PUBLIC',
                                    'valueFrom': {'configMapKeyRef': {'key': 'retained-live-binding'}},
                                },
                                {
                                    'name': 'GLOBAL_SECRET',
                                    'valueFrom': {'secretKeyRef': {'name': 'retained-live-secret', 'key': '9'}},
                                },
                                {'name': 'RETAINED_PUBLIC', 'value': 'retained'},
                                {
                                    'name': 'RETAINED_SECRET',
                                    'valueFrom': {'secretKeyRef': {'name': 'retained-secret', 'key': '7'}},
                                },
                            ]
                        }
                    ]
                }
            }
        }
    }

    drift = preflight.check_runtime_bindings(
        services=('backend-beta',),
        env='dev',
        project='knowledge-athlete',
        region='us-central1',
        manifest_path=manifest,
        runner=lambda _command, **_kwargs: SimpleNamespace(stdout=json.dumps(document)),
    )

    assert drift == []


def test_runtime_binding_check_reports_declared_type_mismatches_only(tmp_path: Path) -> None:
    preflight = load_preflight()
    manifest = tmp_path / 'runtime_env.yaml'
    manifest.write_text(
        '''\
environments:
  dev:
    gcp_project: knowledge-athlete
    cloud_run:
      services:
        backend:
          deployment_name:
            value: knowledge-athlete-dev
          env:
            PUBLIC_SETTING:
              value: public
            SECOND_PUBLIC_SETTING:
              value: another-public-setting
          secrets:
            PRIVATE_SETTING:
              secret: expected-secret
              version: '7'
''',
        encoding='utf-8',
    )
    document = {
        'spec': {
            'template': {
                'spec': {
                    'containers': [
                        {
                            'env': [
                                {
                                    'name': 'PUBLIC_SETTING',
                                    'valueFrom': {'secretKeyRef': {'name': 'legacy-public', 'key': 'latest'}},
                                },
                                {'name': 'SECOND_PUBLIC_SETTING', 'valueFrom': {'configMapKeyRef': {'key': 'value'}}},
                                {'name': 'PRIVATE_SETTING', 'value': 'not-secret'},
                                {'name': 'UNEXPECTED_SETTING', 'value': 'unexpected'},
                            ]
                        }
                    ]
                }
            }
        }
    }

    drift = preflight.check_runtime_bindings(
        services=('backend',),
        env='dev',
        project='knowledge-athlete',
        region='us-central1',
        manifest_path=manifest,
        runner=lambda _command, **_kwargs: SimpleNamespace(stdout=json.dumps(document)),
    )

    assert drift == [
        'runtime-binding/backend/PUBLIC_SETTING: expected public literal or absent before candidate deploy, observed Secret Manager reference legacy-public:latest',
        'runtime-binding/backend/SECOND_PUBLIC_SETTING: expected public literal or absent before candidate deploy, observed unsupported value source',
        'runtime-binding/backend/PRIVATE_SETTING: expected Secret Manager reference expected-secret:7, observed public literal',
    ]


@pytest.mark.parametrize(
    ('env', 'project'),
    [
        ('prod', 'wrong-prod-project'),
        ('dev', 'wrong-dev-project'),
    ],
)
def test_runtime_binding_check_rejects_cross_environment_project_without_gcloud_calls(env: str, project: str) -> None:
    preflight = load_preflight()
    calls: list[list[str]] = []

    with pytest.raises(ValueError, match='expects project'):
        preflight.check_runtime_bindings(
            services=('backend',),
            env=env,
            project=project,
            region='us-west1',
            runner=lambda command, **_kwargs: calls.append(command),
        )

    assert calls == []


def test_backend_deploy_workflows_do_not_materialize_an_ignored_service_account_key() -> None:
    """Static guard: backend image builds must not materialize an excluded key file."""
    repo_root = BACKEND_ROOT.parent
    assert 'backend/google-credentials.json' in (repo_root / '.dockerignore').read_text(encoding='utf-8')
    workflows = (
        'gcp_backend.yml',
        'gcp_backend_auto_dev.yml',
    )

    for workflow in workflows:
        text = (repo_root / '.github' / 'workflows' / workflow).read_text(encoding='utf-8')
        assert 'GCP_SERVICE_ACCOUNT' not in text
        assert 'backend/google-credentials.json' not in text
