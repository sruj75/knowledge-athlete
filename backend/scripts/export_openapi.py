#!/usr/bin/env python3
"""Export and check the Firebase-authenticated first-party OpenAPI contract.

The retained app-client contract is generated from the real FastAPI app and
filtered to first-party routes. macOS generation uses this live surface
directly; callers may still supply an explicit output path.

The bootstrap is hermetic: it disables dotenv loading, removes real credential
env vars, installs fake Firestore/Redis/GCS boundaries, patches Firebase app
initialization, and blocks non-local network while importing the app.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os
import socket
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from fastapi.routing import APIRoute
from fastapi.openapi.utils import get_openapi

ROOT_DIR = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT_DIR / 'backend'
E2E_DIR = BACKEND_DIR / 'testing' / 'e2e'
DEFAULT_SPEC_PATH = ROOT_DIR / 'docs' / 'api-reference' / 'app-client-openapi.json'

APP_CLIENT_PREFIXES = (
    '/v1/conversation-compute',
    '/v1/fair-use',
    '/v1/memory/compute',
    '/v1/payment-methods',
    '/v1/payments',
    '/v1/paypal',
    '/v1/sync',
    '/v1/users',
    '/v2/chat/generate-title',
    '/v2/chat/initial-message',
    '/v2/messages',
    '/v2/voice-messages',
    '/v2/voice-message',
    '/v3/upload-audio',
)

HTTP_METHODS = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'}

OPENAPI_TITLE = 'Omi App Client API'
OPENAPI_VERSION = '1.0.0'
OPENAPI_DESCRIPTION = 'First-party Omi app access to transient conversation and Memory compute and product services.'
OPENAPI_CONTACT = {'name': 'Omi', 'url': 'https://omi.me'}
OPENAPI_LICENSE = {'name': 'MIT', 'url': 'https://github.com/BasedHardware/omi/blob/main/LICENSE'}
OPENAPI_SERVERS = [{'url': 'https://api.omi.me', 'description': 'Production'}]
OPENAPI_TAGS = [
    {'name': 'Memory Compute', 'description': 'Compute bounded Memory proposals without backend persistence.'},
    {
        'name': 'Conversations',
        'description': 'Compute bounded conversation candidates without backend persistence.',
    },
]
FIREBASE_BEARER_AUTH_SCHEME = {
    'type': 'http',
    'scheme': 'bearer',
    'bearerFormat': 'Firebase ID token',
    'description': 'Send `Authorization: Bearer <firebase_id_token>`.',
}
ERROR_RESPONSE_SCHEMA = {
    'type': 'object',
    'properties': {
        'detail': {
            'anyOf': [
                {'type': 'string'},
                {'type': 'array'},
                {'type': 'object'},
            ],
            'description': 'Error detail returned by the API.',
        }
    },
    'required': ['detail'],
    'title': 'ErrorResponse',
}
COMMON_RESPONSES = {
    '401': {'description': 'Missing or invalid authentication credentials.'},
    '403': {'description': 'Authenticated, but the token does not grant the required scope.'},
    '404': {'description': 'Requested resource was not found.'},
}
SIDE_EFFECT_PATHS = (BACKEND_DIR / 'google-credentials.json',)
RESTORABLE_SIDE_EFFECT_PATHS: dict[Path, str] = {}


class OpenAPIContractError(RuntimeError):
    """Raised when the generated OpenAPI contract fails a deterministic check."""


def configure_hermetic_environment() -> None:
    os.environ['PYTHON_DOTENV_DISABLED'] = '1'
    os.environ['LOCAL_DEVELOPMENT'] = 'true'
    os.environ['FIREBASE_PROJECT_ID'] = 'test-openapi-project'
    os.environ['GOOGLE_CLOUD_PROJECT'] = 'test-openapi-project'
    os.environ['REDIS_DB_HOST'] = 'localhost'
    os.environ['REDIS_DB_PORT'] = '6379'
    os.environ['REDIS_DB_PASSWORD'] = ''
    os.environ['MODULATE_API_KEY'] = 'fake-modulate-key'
    os.environ['OPENAI_API_KEY'] = 'fake-openai-key'
    os.environ['ANTHROPIC_API_KEY'] = 'fake-anthropic-key'
    os.environ['GOOGLE_API_KEY'] = 'fake-google-key'
    os.environ['BILLING_MODE'] = 'disabled'
    os.environ['ADMIN_KEY'] = ''

    for bucket_var in ('BUCKET_DESKTOP_UPDATES',):
        os.environ[bucket_var] = bucket_var.lower().replace('bucket_', '').replace('_', '-')

    for secret_var in (
        'SERVICE_ACCOUNT_JSON',
        'GOOGLE_APPLICATION_CREDENTIALS',
        'LANGFUSE_PUBLIC_KEY',
        'LANGFUSE_SECRET_KEY',
    ):
        os.environ.pop(secret_var, None)

    for proxy_var in (
        'HTTP_PROXY',
        'HTTPS_PROXY',
        'ALL_PROXY',
        'NO_PROXY',
        'http_proxy',
        'https_proxy',
        'all_proxy',
        'no_proxy',
    ):
        os.environ.pop(proxy_var, None)


def _install_import_paths() -> None:
    for path in (str(BACKEND_DIR), str(E2E_DIR)):
        if path not in sys.path:
            sys.path.insert(0, path)


def is_local_address(host: object) -> bool:
    if host is None:
        return True
    if isinstance(host, bytes):
        host = host.decode('idna')
    if not isinstance(host, str):
        return False
    normalized = host.strip().strip('[]').lower()
    if normalized in {'', 'localhost'}:
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


def _host_from_address(address: object) -> object:
    if isinstance(address, tuple) and address:
        return address[0]
    return None


@contextmanager
def record_and_block_outbound_network() -> Iterator[list[str]]:
    attempts: list[str] = []
    original_connect = socket.socket.connect
    original_connect_ex = socket.socket.connect_ex
    original_create_connection = socket.create_connection
    original_getaddrinfo = socket.getaddrinfo
    original_gethostbyname = socket.gethostbyname
    original_gethostbyname_ex = socket.gethostbyname_ex

    def record(kind: str, target: object) -> None:
        attempts.append(f'{kind}: {target!r}')

    def guarded_connect(sock: socket.socket, address: object):
        if sock.family != socket.AF_UNIX and not is_local_address(_host_from_address(address)):
            record('connect', address)
            raise OpenAPIContractError(f'blocked outbound network connection to {address!r}')
        return original_connect(sock, address)

    def guarded_connect_ex(sock: socket.socket, address: object):
        if sock.family != socket.AF_UNIX and not is_local_address(_host_from_address(address)):
            record('connect_ex', address)
            raise OpenAPIContractError(f'blocked outbound network connection to {address!r}')
        return original_connect_ex(sock, address)

    def guarded_create_connection(address: object, *args, **kwargs):
        if not is_local_address(_host_from_address(address)):
            record('create_connection', address)
            raise OpenAPIContractError(f'blocked outbound network connection to {address!r}')
        return original_create_connection(address, *args, **kwargs)

    def guarded_getaddrinfo(host: object, *args, **kwargs):
        if not is_local_address(host):
            record('getaddrinfo', host)
            raise OpenAPIContractError(f'blocked DNS resolution for {host!r}')
        return original_getaddrinfo(host, *args, **kwargs)

    def guarded_gethostbyname(host: object):
        if not is_local_address(host):
            record('gethostbyname', host)
            raise OpenAPIContractError(f'blocked DNS resolution for {host!r}')
        return original_gethostbyname(host)

    def guarded_gethostbyname_ex(host: object):
        if not is_local_address(host):
            record('gethostbyname_ex', host)
            raise OpenAPIContractError(f'blocked DNS resolution for {host!r}')
        return original_gethostbyname_ex(host)

    socket.socket.connect = guarded_connect
    socket.socket.connect_ex = guarded_connect_ex
    socket.create_connection = guarded_create_connection
    socket.getaddrinfo = guarded_getaddrinfo
    socket.gethostbyname = guarded_gethostbyname
    socket.gethostbyname_ex = guarded_gethostbyname_ex
    try:
        yield attempts
    finally:
        socket.socket.connect = original_connect
        socket.socket.connect_ex = original_connect_ex
        socket.create_connection = original_create_connection
        socket.getaddrinfo = original_getaddrinfo
        socket.gethostbyname = original_gethostbyname
        socket.gethostbyname_ex = original_gethostbyname_ex


def snapshot_side_effect_paths() -> dict[Path, tuple[bool, int | None, int | None]]:
    snapshot: dict[Path, tuple[bool, int | None, int | None]] = {}
    for path in SIDE_EFFECT_PATHS:
        if path.exists():
            stat = path.stat()
            snapshot[path] = (True, stat.st_mtime_ns, stat.st_size if path.is_file() else None)
        else:
            snapshot[path] = (False, None, None)
    return snapshot


def assert_no_side_effect_path_mutations(snapshot: dict[Path, tuple[bool, int | None, int | None]]) -> None:
    mutations = []
    for path, before in snapshot.items():
        if path.exists():
            stat = path.stat()
            after = (True, stat.st_mtime_ns, stat.st_size if path.is_file() else None)
        else:
            after = (False, None, None)
        if before != after:
            try:
                mutations.append(str(path.relative_to(ROOT_DIR)))
            except ValueError:
                mutations.append(str(path))
    if mutations:
        raise OpenAPIContractError('OpenAPI export mutated side-effect paths: ' + ', '.join(mutations))


def restore_restorable_side_effect_paths(snapshot: dict[Path, tuple[bool, int | None, int | None]]) -> None:
    for path, before in snapshot.items():
        existed_before = before[0]
        if existed_before or not path.exists():
            continue
        if path not in RESTORABLE_SIDE_EFFECT_PATHS:
            continue
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()


def assert_env_unchanged(expected_env: dict[str, str]) -> None:
    current_env = dict(os.environ)
    if current_env == expected_env:
        return

    added = sorted(set(current_env) - set(expected_env))
    removed = sorted(set(expected_env) - set(current_env))
    changed = sorted(key for key in set(current_env) & set(expected_env) if current_env[key] != expected_env[key])
    details = []
    if added:
        details.append('added=' + ','.join(added))
    if removed:
        details.append('removed=' + ','.join(removed))
    if changed:
        details.append('changed=' + ','.join(changed))
    raise OpenAPIContractError('OpenAPI export mutated environment: ' + '; '.join(details))


def install_hermetic_dependency_patches():
    import dotenv
    import google.auth
    import google.auth.credentials
    from fakes.firestore import get_mock_firestore, patch_google_firestore, setup_fake_firestore
    from fakes.redis import get_fake_redis, patch_redis_client, setup_fake_redis
    from fakes.storage import patch_google_storage, setup_fake_storage

    dotenv.load_dotenv = lambda *args, **kwargs: False
    # load_backend_env() reads .env files via dotenv_values and writes
    # os.environ directly, so a personal backend/.env would otherwise leak
    # into the export and trip assert_env_unchanged.
    dotenv.dotenv_values = lambda *args, **kwargs: {}
    google.auth.default = lambda *args, **kwargs: (
        google.auth.credentials.AnonymousCredentials(),
        'test-openapi-project',
    )

    fake_firestore = setup_fake_firestore()
    fake_redis = setup_fake_redis()
    setup_fake_storage()

    patch_google_firestore()
    patch_redis_client()
    patch_google_storage()

    import firebase_admin

    firebase_admin.initialize_app = lambda *args, **kwargs: None
    firebase_admin.get_app = lambda *args, **kwargs: object()

    return fake_firestore, fake_redis, get_mock_firestore, get_fake_redis


def relink_imported_service_singletons(fake_firestore, fake_redis, get_mock_firestore, get_fake_redis) -> None:
    import database._client as db_client
    from database.redis_connection import set_redis_client_for_testing

    old_db = db_client.db
    db_client.db = fake_firestore
    set_redis_client_for_testing(fake_redis)
    for module in list(sys.modules.values()):
        if module is None:
            continue
        for attr_name, attr_value in list(vars(module).items()):
            try:
                if attr_value is old_db:
                    setattr(module, attr_name, get_mock_firestore())
            except Exception:
                continue


def generate_app_client_openapi() -> dict[str, Any]:
    original_env = dict(os.environ)
    side_effect_snapshot = snapshot_side_effect_paths()
    configure_hermetic_environment()
    expected_fake_env = dict(os.environ)
    _install_import_paths()

    logging.disable(logging.CRITICAL)
    try:
        fake_firestore, fake_redis, get_mock_firestore, get_fake_redis = install_hermetic_dependency_patches()
        with record_and_block_outbound_network() as network_attempts:
            import main as backend_main

            relink_imported_service_singletons(fake_firestore, fake_redis, get_mock_firestore, get_fake_redis)
            schema = build_app_client_openapi(backend_main.app)

            if network_attempts:
                raise OpenAPIContractError(
                    'OpenAPI export attempted outbound network during import/generation: ' + '; '.join(network_attempts)
                )

            assert_env_unchanged(expected_fake_env)
            return schema
    finally:
        logging.disable(logging.NOTSET)
        restore_restorable_side_effect_paths(side_effect_snapshot)
        os.environ.clear()
        os.environ.update(original_env)
        assert_no_side_effect_path_mutations(side_effect_snapshot)


def is_app_client_contract_path(path: str) -> bool:
    for prefix in APP_CLIENT_PREFIXES:
        if prefix.endswith('/'):
            if path.startswith(prefix):
                return True
        elif path == prefix or path.startswith(f'{prefix}/'):
            return True
    return False


def app_client_contract_routes(app) -> list[APIRoute]:
    return [
        route
        for route in app.routes
        if isinstance(route, APIRoute) and is_app_client_contract_path(route.path) and route.include_in_schema
    ]


def _normalize_app_client_security(schema: dict[str, Any]) -> None:
    components = schema.setdefault('components', {})
    security_schemes = components.setdefault('securitySchemes', {})
    security_schemes.clear()
    security_schemes['firebaseBearer'] = FIREBASE_BEARER_AUTH_SCHEME
    components.setdefault('schemas', {})['ErrorResponse'] = ERROR_RESPONSE_SCHEMA
    responses = components.setdefault('responses', {})
    for status_code, response in COMMON_RESPONSES.items():
        responses[f'Error{status_code}'] = {
            **response,
            'content': {
                'application/json': {
                    'schema': {'$ref': '#/components/schemas/ErrorResponse'},
                }
            },
        }
    schema.pop('security', None)

    for path, operations in schema.get('paths', {}).items():
        for method, operation in operations.items():
            if method.upper() in HTTP_METHODS:
                operation['security'] = [{'firebaseBearer': []}]
                operation.setdefault('responses', {})['401'] = {'$ref': '#/components/responses/Error401'}
                if '{' in path and method.upper() in {'GET', 'PATCH', 'DELETE'}:
                    operation['responses'].setdefault('404', {'$ref': '#/components/responses/Error404'})


def _rewrite_refs(value: Any, ref_map: dict[str, str]) -> None:
    if isinstance(value, dict):
        ref = value.get('$ref')
        if ref in ref_map:
            value['$ref'] = ref_map[ref]
        for child in value.values():
            _rewrite_refs(child, ref_map)
    elif isinstance(value, list):
        for child in value:
            _rewrite_refs(child, ref_map)


def _normalize_component_names(schema: dict[str, Any]) -> None:
    schemas = schema.get('components', {}).get('schemas', {})
    renamed: dict[str, Any] = {}
    ref_map: dict[str, str] = {}

    for name, component_schema in schemas.items():
        title = component_schema.get('title')
        new_name = title if isinstance(title, str) and title and title != name else name
        if (new_name in schemas and new_name != name) or new_name in renamed:
            new_name = name
        renamed[new_name] = component_schema
        if new_name != name:
            ref_map[f'#/components/schemas/{name}'] = f'#/components/schemas/{new_name}'

    if ref_map:
        schemas.clear()
        schemas.update(renamed)
        _rewrite_refs(schema, ref_map)


def build_app_client_openapi(app) -> dict[str, Any]:
    schema = get_openapi(
        title=OPENAPI_TITLE,
        version=OPENAPI_VERSION,
        description=OPENAPI_DESCRIPTION,
        routes=app_client_contract_routes(app),
        tags=OPENAPI_TAGS,
        servers=OPENAPI_SERVERS,
        contact=OPENAPI_CONTACT,
        license_info=OPENAPI_LICENSE,
    )
    _normalize_app_client_security(schema)
    _normalize_component_names(schema)
    validate_contract(schema)
    return schema


def assert_unique_operation_ids(schema: dict[str, Any]) -> None:
    operation_ids: dict[str, tuple[str, str]] = {}
    duplicates: list[str] = []
    missing: list[str] = []
    for path, operations in schema.get('paths', {}).items():
        for method, operation in operations.items():
            if method.upper() not in HTTP_METHODS:
                continue
            operation_id = operation.get('operationId')
            if not operation_id:
                missing.append(f'{method.upper()} {path}')
                continue
            if operation_id in operation_ids:
                previous_method, previous_path = operation_ids[operation_id]
                duplicates.append(f'{operation_id}: {previous_method} {previous_path} and {method.upper()} {path}')
            operation_ids[operation_id] = (method.upper(), path)
    if missing or duplicates:
        details = []
        if missing:
            details.append('missing operationId: ' + ', '.join(missing))
        if duplicates:
            details.append('duplicate operationId: ' + '; '.join(duplicates))
        raise OpenAPIContractError('\n'.join(details))


def validate_contract(schema: dict[str, Any]) -> None:
    if schema.get('openapi') != '3.1.0':
        raise OpenAPIContractError(f"expected OpenAPI 3.1.0, got {schema.get('openapi')!r}")
    assert_unique_operation_ids(schema)
    for path in schema.get('paths', {}):
        if not is_app_client_contract_path(path):
            raise OpenAPIContractError(f'non-app-client route leaked into app-client OpenAPI: {path}')


def stable_json(schema: dict[str, Any]) -> str:
    return json.dumps(schema, indent=2, sort_keys=True, ensure_ascii=False) + '\n'


def write_spec(path: Path, generated: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(generated)


def regenerate_hint(path: Path) -> str:
    """Return the exact command that regenerates the retained contract."""
    return f'backend/scripts/export_openapi.py --surface app-client --write {path}'


def check_spec(path: Path, generated: str) -> None:
    hint = regenerate_hint(path)
    if not path.exists():
        raise OpenAPIContractError(f'{path} does not exist; run {hint}')
    current = path.read_text()
    if current != generated:
        raise OpenAPIContractError(f'{path} is stale; run {hint}')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Export or verify an Omi OpenAPI contract.')
    parser.add_argument(
        '--surface',
        choices=('app-client',),
        default='app-client',
        help='retained first-party contract surface',
    )
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--write', nargs='?', const='', metavar='PATH', help='write generated spec')
    action.add_argument('--check', nargs='?', const='', metavar='PATH', help='check generated spec')
    action.add_argument('--print', action='store_true', help='print generated spec to stdout')
    return parser.parse_args()


def default_spec_path() -> Path:
    return DEFAULT_SPEC_PATH


def resolve_spec_path(raw_path: str) -> Path:
    if raw_path:
        return Path(raw_path)
    return default_spec_path()


def main() -> int:
    args = parse_args()
    try:
        generated = stable_json(generate_app_client_openapi())
        if args.print:
            sys.stdout.write(generated)
        elif args.write is not None:
            path = resolve_spec_path(args.write)
            write_spec(path, generated)
            print(f'wrote {path}')
        elif args.check is not None:
            path = resolve_spec_path(args.check)
            check_spec(path, generated)
            print(f'{path} is up to date')
        return 0
    except OpenAPIContractError as e:
        print(f'OpenAPI contract check failed: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
