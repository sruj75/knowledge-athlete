import ast
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from models.memory_compute import (
    MemoryConsolidateDecision,
    MemoryConsolidateResponse,
    MemoryExtractCandidate,
    MemoryExtractResponse,
    MemoryNormalizeResponse,
)
from routers import memory_compute
from utils.llm import memory_compute as compute_service
from utils.llm.memory_compute import validate_consolidation_response
from utils.other.endpoints import get_current_user_uid


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    app = FastAPI()
    app.include_router(memory_compute.router)
    app.dependency_overrides[get_current_user_uid] = lambda: 'owner-1'

    def fake_extract(request, uid):
        assert uid == 'owner-1'
        return MemoryExtractResponse(
            request_id=request.request_id,
            generation=request.generation,
            candidates=[
                MemoryExtractCandidate(
                    content='The user prefers tea.',
                    category='system',
                    quote='I prefer tea',
                    segment_token='s0',
                    subject='primary_user',
                    confidence=0.93,
                )
            ],
        )

    def fake_normalize(request, uid):
        assert uid == 'owner-1'
        return MemoryNormalizeResponse(
            request_id=request.request_id,
            revision=request.revision,
            normalized_content='The user prefers tea.',
            subject='primary_user',
            predicate='prefers',
            arguments={'object': 'tea'},
            sensitivity_labels=[],
            rationale='Direct explicit assertion.',
        )

    def fake_consolidate(request, uid):
        assert uid == 'owner-1'
        return MemoryConsolidateResponse(
            request_id=request.request_id,
            generation=request.generation,
            decisions=[
                MemoryConsolidateDecision(
                    candidate_token='c0',
                    action='promote',
                    reconciliation='create',
                    target_memory_tokens=[],
                    memory_text='The user prefers tea.',
                    rationale='Stable preference.',
                )
            ],
        )

    monkeypatch.setattr(memory_compute, 'compute_extract', fake_extract)
    monkeypatch.setattr(memory_compute, 'compute_normalize', fake_normalize)
    monkeypatch.setattr(memory_compute, 'compute_consolidate', fake_consolidate)
    return TestClient(app)


def test_extract_route_is_authenticated_bounded_and_echoes_local_tokens(client: TestClient):
    request_id = uuid4()
    response = client.post(
        '/v1/memory/compute/extract',
        json={
            'request_id': str(request_id),
            'generation': 7,
            'segments': [{'token': 's0', 'speaker_label': 'Srujan', 'text': 'I prefer tea', 'is_user': True}],
            'language': 'en',
        },
    )
    assert response.status_code == 200
    assert response.json()['request_id'] == str(request_id)
    assert response.json()['candidates'][0]['segment_token'] == 's0'
    assert response.json()['candidates'][0]['quote'] == 'I prefer tea'

    over_limit = client.post(
        '/v1/memory/compute/extract',
        json={
            'request_id': str(uuid4()),
            'generation': 1,
            'segments': [
                {'token': f's{i}', 'speaker_label': 'User', 'text': 'bounded', 'is_user': True} for i in range(501)
            ],
        },
    )
    assert over_limit.status_code == 422


def test_normalize_route_returns_proposal_without_durable_identity(client: TestClient):
    request_id = uuid4()
    response = client.post(
        '/v1/memory/compute/normalize',
        json={'request_id': str(request_id), 'revision': 3, 'assertion': '  I prefer tea.  '},
    )
    assert response.status_code == 200
    assert response.json() == {
        'request_id': str(request_id),
        'revision': 3,
        'normalized_content': 'The user prefers tea.',
        'subject': 'primary_user',
        'predicate': 'prefers',
        'arguments': {'object': 'tea'},
        'sensitivity_labels': [],
        'rationale': 'Direct explicit assertion.',
    }
    assert not {'memory_id', 'owner_id', 'backend_id'} & response.json().keys()


def test_consolidate_route_returns_exactly_one_decision_per_candidate(client: TestClient):
    request_id = uuid4()
    response = client.post(
        '/v1/memory/compute/consolidate',
        json={
            'request_id': str(request_id),
            'generation': 4,
            'candidates': [{'token': 'c0', 'content': 'The user prefers tea.', 'evidence_tokens': ['s0']}],
            'active_memories': [],
        },
    )
    assert response.status_code == 200
    assert response.json()['decisions'][0]['candidate_token'] == 'c0'

    duplicate = MemoryConsolidateResponse(
        request_id=UUID(str(request_id)),
        generation=4,
        decisions=[
            MemoryConsolidateDecision(
                candidate_token='c0',
                action='promote',
                reconciliation='create',
                memory_text='one',
                rationale='one',
            ),
            MemoryConsolidateDecision(
                candidate_token='c0',
                action='reject',
                reconciliation='create',
                rationale='two',
            ),
        ],
    )
    with pytest.raises(ValueError, match='exactly one decision'):
        validate_consolidation_response(candidate_tokens={'c0'}, active_memory_tokens=set(), response=duplicate)


def test_routes_require_authentication(monkeypatch: pytest.MonkeyPatch):
    app = FastAPI()
    app.include_router(memory_compute.router)
    unauthenticated = TestClient(app)
    response = unauthenticated.post(
        '/v1/memory/compute/normalize',
        json={'request_id': str(uuid4()), 'revision': 1, 'assertion': 'hello'},
    )
    assert response.status_code in {401, 403}


def test_compute_failures_do_not_echo_private_input(client: TestClient, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(
        memory_compute,
        'compute_normalize',
        lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError('private assertion contents')),
    )

    response = client.post(
        '/v1/memory/compute/normalize',
        json={'request_id': str(uuid4()), 'revision': 1, 'assertion': 'private assertion contents'},
    )

    assert response.status_code == 502
    assert response.json() == {'detail': 'compute_failed'}
    assert 'private assertion contents' not in response.text


def test_model_invocation_is_pinned_to_gpt_4_1_mini(monkeypatch: pytest.MonkeyPatch):
    calls = []

    class FakeModel:
        def invoke(self, prompt):
            assert 'Normalize one explicit assertion' in prompt
            return type(
                'Response',
                (),
                {
                    'content': (
                        '{"normalized_content":"The user prefers tea.","subject":"primary_user",'
                        '"predicate":"prefers","arguments":{"object":"tea"},'
                        '"sensitivity_labels":[],"rationale":"Explicit assertion."}'
                    )
                },
            )()

    def fake_client(provider, model, streaming=False, options=None):
        calls.append((provider, model, streaming, options))
        return FakeModel()

    monkeypatch.setattr(compute_service, 'get_or_create_openai_compatible_llm', fake_client)
    request_id = uuid4()
    response = compute_service.compute_normalize(
        compute_service.MemoryNormalizeRequest(request_id=request_id, revision=1, assertion='I prefer tea.'),
        'owner-1',
    )

    assert response.request_id == request_id
    assert calls == [('openai', 'gpt-4.1-mini', False, None)]


def test_compute_modules_have_no_durable_storage_dependencies():
    backend = Path(__file__).resolve().parents[2]
    paths = (
        backend / 'models' / 'memory_compute.py',
        backend / 'routers' / 'memory_compute.py',
        backend / 'utils' / 'llm' / 'memory_compute.py',
    )
    forbidden_roots = {'database', 'firebase_admin', 'redis', 'pinecone'}

    for path in paths:
        tree = ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
        imported_roots = {
            alias.name.split('.')[0] for node in ast.walk(tree) if isinstance(node, ast.Import) for alias in node.names
        }
        imported_roots.update(
            (node.module or '').split('.')[0] for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)
        )
        assert imported_roots.isdisjoint(forbidden_roots), f'{path} imports durable storage'


def test_only_the_three_transient_memory_routes_are_mounted():
    route_keys = {
        (method, route.path) for route in memory_compute.router.routes for method in getattr(route, 'methods', set())
    }
    assert route_keys == {
        ('POST', '/v1/memory/compute/extract'),
        ('POST', '/v1/memory/compute/normalize'),
        ('POST', '/v1/memory/compute/consolidate'),
    }
