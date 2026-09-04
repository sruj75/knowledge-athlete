import importlib.util
import sys
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[2]
SCRIPT_PATH = BACKEND_DIR / 'scripts' / 'runtime_image_contracts.py'


def _load_contract_module():
    spec = importlib.util.spec_from_file_location('runtime_image_contracts_for_test', SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope='module')
def contracts_module():
    return _load_contract_module()


def _contract(contracts_module, name):
    return next(contract for contract in contracts_module.load_contracts() if contract.name == name)


def _dockerfile_without(source: Path, omitted_line: str, destination: Path) -> Path:
    text = source.read_text(encoding='utf-8')
    assert omitted_line in text
    destination.write_text(text.replace(omitted_line, ''), encoding='utf-8')
    return destination


def test_registered_runtime_image_sources_are_closed(contracts_module):
    assert contracts_module.check_source_closures(contracts_module.load_contracts()) == []


def test_registered_runtime_image_build_context_is_fail_closed(contracts_module):
    assert contracts_module.docker_context_contract_errors(contracts_module.load_contracts()) == []


@pytest.mark.parametrize(
    ('mutate', 'expected_error'),
    [
        (
            lambda patterns: [
                pattern for pattern in patterns if pattern != '!.github/scripts/desktop_release_manifest.py'
            ],
            'omits required COPY inputs',
        ),
        (lambda patterns: [*patterns, '!desktop/**'], 'admits paths no registered image copies'),
        (
            lambda patterns: [pattern for pattern in patterns if pattern != 'backend/.env*'],
            'omits cache or credential exclusions',
        ),
        (
            lambda patterns: [pattern for pattern in patterns if pattern != 'backend/.venv'],
            'omits cache or credential exclusions',
        ),
        (
            lambda patterns: [
                patterns[0],
                'backend/.env*',
                *(pattern for pattern in patterns[1:] if pattern != 'backend/.env*'),
            ],
            'cache and credential exclusions must follow every include',
        ),
    ],
)
def test_build_context_contract_rejects_missing_or_broadened_policy(
    contracts_module,
    monkeypatch,
    mutate,
    expected_error,
):
    patterns = contracts_module._dockerignore_patterns(contracts_module.REPOSITORY_ROOT / '.dockerignore')
    monkeypatch.setattr(contracts_module, '_dockerignore_patterns', lambda _: mutate(patterns))

    errors = contracts_module.docker_context_contract_errors(contracts_module.load_contracts())

    assert any(expected_error in error for error in errors)


@pytest.mark.parametrize(
    'excluded_pattern',
    [
        'backend/.harness',
        'backend/*.env',
        'backend/**/*.env',
        'backend/_speech_profiles',
        'backend/_temp',
        'backend/logs',
        'backend/pretrained_models',
        'backend/scripts/data',
        'backend/scripts/rag/*.json',
        'backend/scripts/rag/visualizations',
        'backend/scripts/research',
        'backend/scripts/stt/_temp',
        'backend/scripts/stt/_temp2',
        'backend/scripts/stt/diarization.json',
        'backend/scripts/stt/pretrained_models',
        'backend/scripts/stt/results',
        'backend/syncing',
    ],
)
def test_build_context_contract_rejects_missing_local_artifact_exclusion(
    contracts_module, monkeypatch, excluded_pattern
):
    patterns = contracts_module._dockerignore_patterns(contracts_module.REPOSITORY_ROOT / '.dockerignore')
    monkeypatch.setattr(
        contracts_module,
        '_dockerignore_patterns',
        lambda _: [pattern for pattern in patterns if pattern != excluded_pattern],
    )

    errors = contracts_module.docker_context_contract_errors(contracts_module.load_contracts())

    assert any('omits cache or credential exclusions' in error for error in errors)


def test_build_context_contract_rejects_dockerfile_specific_ignore_override(contracts_module, monkeypatch):
    contracts = contracts_module.load_contracts()
    override = contracts[0].dockerfile.with_name(f'{contracts[0].dockerfile.name}.dockerignore')
    original_is_file = contracts_module.Path.is_file
    monkeypatch.setattr(
        contracts_module.Path,
        'is_file',
        lambda candidate: candidate == override or original_is_file(candidate),
    )

    errors = contracts_module.docker_context_contract_errors(contracts)

    assert any('Dockerfile-specific ignore policy is forbidden' in error for error in errors)


def test_dockerignore_changes_route_to_static_and_image_checks():
    repository_root = BACKEND_DIR.parent
    workflow = (repository_root / '.github' / 'workflows' / 'runtime_image_contracts.yml').read_text(encoding='utf-8')
    pre_push = (repository_root / 'scripts' / 'pre-push').read_text(encoding='utf-8')

    assert "      - '.dockerignore'" in workflow
    assert "    '.dockerignore' \\" in pre_push


def test_source_staging_excludes_generated_virtual_environments(contracts_module):
    names = ['database', '.venv', '.openapi-venv', '.pytest_cache', '__pycache__']

    ignored = contracts_module._ignore_source_directory('/unused', names)

    assert ignored == {'.venv', '.openapi-venv', '.pytest_cache', '__pycache__'}
    assert names == ['database']


def test_registered_runtime_image_workflows_smoke_their_declared_dockerfile(contracts_module):
    assert contracts_module.workflow_contract_errors(contracts_module.load_contracts()) == []


def test_backend_contract_rejects_omitted_runtime_source(contracts_module, tmp_path):
    backend = _contract(contracts_module, 'backend')
    dockerfile = _dockerfile_without(
        backend.dockerfile,
        'COPY backend/ .\n',
        tmp_path / 'Dockerfile',
    )

    errors = contracts_module.source_closure_errors(replace(backend, dockerfile=dockerfile))

    assert any("first-party module 'main' is absent" in error for error in errors)


def test_relative_import_resolution_keeps_the_current_package(contracts_module):
    level_one = contracts_module.ast.parse('from ._client import db')
    level_two = contracts_module.ast.parse('from ..shared import client')
    source_roots = (BACKEND_DIR,)

    assert 'database._client' in contracts_module._imported_modules(
        level_one, 'database.tasks', source_roots, current_is_package=False
    )
    assert 'database.shared' in contracts_module._imported_modules(
        level_two, 'database.sub.tasks', source_roots, current_is_package=False
    )


def test_dependency_probe_checks_dotted_module_when_namespace_exists(contracts_module, monkeypatch, tmp_path):
    contract = replace(
        _contract(contracts_module, 'backend'),
        entrypoints=('entrypoint',),
        entrypoint_source_root=tmp_path,
        source_root=tmp_path,
    )
    (tmp_path / 'entrypoint.py').write_text('from google.cloud import tasks_v2\n', encoding='utf-8')

    dependencies = contracts_module.third_party_dependency_modules(contract)

    assert 'google.cloud.tasks_v2' in dependencies

    monkeypatch.setattr(
        importlib.util,
        'find_spec',
        lambda module: object() if module == 'google' else None,
    )
    monkeypatch.setattr(importlib, 'import_module', lambda _: SimpleNamespace())

    with pytest.raises(AssertionError, match='google.cloud.tasks_v2'):
        exec(contracts_module._dependency_probe_code(('google.cloud.tasks_v2',)), {})


def test_image_smoke_is_network_isolated_and_uses_registered_entrypoint(contracts_module, monkeypatch):
    calls = []

    class Result:
        returncode = 0

    monkeypatch.setattr(contracts_module, 'third_party_dependency_modules', lambda _: ('jsonschema',))
    monkeypatch.setattr(contracts_module.subprocess, 'run', lambda command, check: calls.append(command) or Result())

    assert contracts_module.smoke_image('backend:test', [_contract(contracts_module, 'backend')]) == 0

    assert len(calls) == 1
    for call in calls:
        assert call[:6] == ['docker', 'run', '--rm', '--network=none', '--entrypoint', 'python']
        assert '--network=none' in call
    assert 'jsonschema' in calls[0][-1]
    assert 'importlib.util.find_spec' in calls[0][-1]
    assert 'importlib.import_module(parent)' in calls[0][-1]
    assert 'os.getuid() == 10001' in calls[0][-1]
    assert '/tmp/omi-runtime' in calls[0][-1]
    assert '/tmp/omi-parity-pack' in calls[0][-1]
    assert '/app/main.py' in calls[0][-1]


def test_build_smoke_uses_the_registered_dockerfile_and_context(contracts_module, monkeypatch):
    calls = []

    class Result:
        returncode = 0

    monkeypatch.setattr(contracts_module, 'third_party_dependency_modules', lambda _: ('jsonschema',))
    monkeypatch.setattr(contracts_module.subprocess, 'run', lambda command, check: calls.append(command) or Result())

    assert contracts_module.build_and_smoke_image('backend:test', _contract(contracts_module, 'backend')) == 0

    assert calls[0] == ['docker', 'build', '--file', 'backend/Dockerfile', '--tag', 'backend:test', '.']
    assert calls[1][0:7] == [
        'docker',
        'run',
        '--rm',
        '--network=none',
        '--entrypoint',
        'python',
        'backend:test',
    ]
