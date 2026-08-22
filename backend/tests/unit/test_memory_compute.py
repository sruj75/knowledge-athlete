import ast
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from models.memory_compute import (
    MemoryConsolidateActiveMemory,
    MemoryConsolidateCandidate,
    MemoryConsolidateDecision,
    MemoryConsolidateResponse,
    MemoryExtractCandidate,
    MemoryExtractProposal,
    MemoryExtractRequest,
    MemoryExtractResponse,
    MemoryTranscriptSegment,
    MemoryNormalizeResponse,
)
from routers import memory_compute
from utils.llm import memory_compute as compute_service
from utils.llm.memory_compute import validate_consolidation_response
from utils.other import endpoints as auth_endpoints
from utils.other.endpoints import get_current_user_uid


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setattr(auth_endpoints, '_enforce_rate_limit', lambda *_args, **_kwargs: None)
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
                    speaker_label='Srujan',
                    subject='primary_user',
                    about='the user',
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
                    evidence_tokens=['s0'],
                    subject='primary_user',
                    predicate='prefers',
                    arguments={'object': 'tea'},
                    sensitivity_labels=[],
                    relationship_to_user='self',
                    aboutness='primary_user',
                    basis_for_memory='explicit',
                    confidence='high',
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
        json={
            'request_id': str(request_id),
            'revision': 3,
            'assertion': '  I prefer tea.  ',
            'source': 'manual',
            'source_attribution': 'primary_user',
            'provenance_tokens': ['manual-entry'],
        },
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
            'candidates': [
                {
                    'token': 'c0',
                    'content': 'The user prefers tea.',
                    'evidence_tokens': ['s0'],
                    'sensitivity_labels': [],
                    'subject': 'primary_user',
                }
            ],
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
                evidence_tokens=['s0'],
                subject='primary_user',
                predicate='fact',
                sensitivity_labels=[],
                relationship_to_user='self',
                aboutness='primary_user',
                basis_for_memory='explicit',
                confidence='high',
                rationale='one',
            ),
            MemoryConsolidateDecision(
                candidate_token='c0',
                action='reject',
                reconciliation='create',
                evidence_tokens=[],
                subject='primary_user',
                sensitivity_labels=[],
                relationship_to_user='unclear',
                aboutness='unclear',
                basis_for_memory='weak_or_none',
                confidence='low',
                rationale='two',
            ),
        ],
    )
    with pytest.raises(ValueError, match='exactly one decision'):
        validate_consolidation_response(candidate_tokens={'c0'}, active_memory_tokens=set(), response=duplicate)


def test_extract_rejects_a_model_speaker_label_that_does_not_match_the_source(monkeypatch: pytest.MonkeyPatch):
    request = MemoryExtractRequest(
        request_id=uuid4(),
        generation=1,
        segments=[MemoryTranscriptSegment(token='s0', speaker_label='Srujan', text='I prefer tea.', is_user=True)],
    )
    proposal = MemoryExtractProposal(
        candidates=[
            MemoryExtractCandidate(
                content='The user prefers tea.',
                category='system',
                quote='I prefer tea.',
                segment_token='s0',
                speaker_label='Someone else',
                subject='primary_user',
                about='the user',
                confidence=0.9,
            )
        ]
    )
    monkeypatch.setattr(compute_service, 'invoke_model', lambda *_args, **_kwargs: proposal)

    with pytest.raises(ValueError, match='speaker label'):
        compute_service.compute_extract(request, 'owner-1')


def test_consolidation_rejects_restricted_and_relationship_inconsistent_promotions():
    restricted_candidate = MemoryConsolidateCandidate(
        token='c0',
        content='The user shared a health condition.',
        evidence_tokens=['s0'],
        sensitivity_labels=['health'],
        subject='primary_user',
    )
    restricted_decision = MemoryConsolidateDecision(
        candidate_token='c0',
        action='promote',
        reconciliation='create',
        memory_text='The user shared a health condition.',
        evidence_tokens=['s0'],
        subject='primary_user',
        predicate='shared_health_condition',
        sensitivity_labels=['health'],
        relationship_to_user='self',
        aboutness='primary_user',
        basis_for_memory='explicit',
        confidence='high',
        rationale='Explicit but restricted.',
    )
    with pytest.raises(ValueError, match='restricted'):
        validate_consolidation_response(
            candidate_tokens={'c0'},
            active_memory_tokens=set(),
            response=MemoryConsolidateResponse(request_id=uuid4(), generation=1, decisions=[restricted_decision]),
            candidates={'c0': restricted_candidate},
            active_memories={},
        )

    safe_candidate = restricted_candidate.model_copy(update={'sensitivity_labels': []})
    inconsistent = restricted_decision.model_copy(
        update={
            'sensitivity_labels': [],
            'relationship_to_user': 'self',
            'aboutness': 'user_owned_project',
            'rationale': 'Relationship and aboutness conflict.',
        }
    )
    with pytest.raises(ValueError, match='weak relationship'):
        validate_consolidation_response(
            candidate_tokens={'c0'},
            active_memory_tokens=set(),
            response=MemoryConsolidateResponse(request_id=uuid4(), generation=1, decisions=[inconsistent]),
            candidates={'c0': safe_candidate},
            active_memories={},
        )


def test_consolidation_rejects_two_decisions_superseding_the_same_long_term_target():
    candidates = {
        token: MemoryConsolidateCandidate(
            token=token,
            content=f'Candidate {token}',
            evidence_tokens=[f's{index}'],
            sensitivity_labels=[],
            subject='primary_user',
        )
        for index, token in enumerate(('c0', 'c1'))
    }
    active = MemoryConsolidateActiveMemory(
        token='m0',
        content='Old fact',
        layer='long_term',
        revision=2,
        subject='primary_user',
    )
    decisions = [
        MemoryConsolidateDecision(
            candidate_token=token,
            action='promote',
            reconciliation='replace',
            target_memory_tokens=['m0'],
            memory_text=f'Replacement {token}',
            evidence_tokens=[f's{index}'],
            subject='primary_user',
            predicate='fact',
            sensitivity_labels=[],
            relationship_to_user='self',
            aboutness='primary_user',
            basis_for_memory='explicit',
            confidence='high',
            rationale='Replace stale fact.',
        )
        for index, token in enumerate(('c0', 'c1'))
    ]

    with pytest.raises(ValueError, match='same target'):
        validate_consolidation_response(
            candidate_tokens=set(candidates),
            active_memory_tokens={'m0'},
            response=MemoryConsolidateResponse(request_id=uuid4(), generation=1, decisions=decisions),
            candidates=candidates,
            active_memories={'m0': active},
        )


def test_routes_require_authentication(monkeypatch: pytest.MonkeyPatch):
    app = FastAPI()
    app.include_router(memory_compute.router)
    unauthenticated = TestClient(app)
    response = unauthenticated.post(
        '/v1/memory/compute/normalize',
        json={
            'request_id': str(uuid4()),
            'revision': 1,
            'assertion': 'hello',
            'source': 'manual',
            'source_attribution': 'primary_user',
        },
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
        json={
            'request_id': str(uuid4()),
            'revision': 1,
            'assertion': 'private assertion contents',
            'source': 'manual',
            'source_attribution': 'primary_user',
        },
    )

    assert response.status_code == 502
    assert response.json() == {'detail': 'compute_failed'}
    assert 'private assertion contents' not in response.text


def test_model_invocation_uses_the_explicit_memory_l2_workload(monkeypatch: pytest.MonkeyPatch):
    calls = []

    class FakeModel:
        def invoke(self, prompt):
            assert 'Normalize one explicit authoritative assertion' in prompt
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

    def fake_client(feature):
        calls.append(feature)
        return FakeModel()

    monkeypatch.setattr(compute_service, 'get_workload_client', fake_client)
    request_id = uuid4()
    response = compute_service.compute_normalize(
        compute_service.MemoryNormalizeRequest(
            request_id=request_id,
            revision=1,
            assertion='I prefer tea.',
            source='manual',
            source_attribution='primary_user',
        ),
        'owner-1',
    )

    assert response.request_id == request_id
    assert calls == ['memory_l2']


def test_paid_compute_dependency_returns_429_before_model_invocation(monkeypatch: pytest.MonkeyPatch):
    app = FastAPI()
    app.include_router(memory_compute.router)
    app.dependency_overrides[get_current_user_uid] = lambda: 'owner-1'

    def reject(*_args, **_kwargs):
        from fastapi import HTTPException

        raise HTTPException(status_code=429, detail='rate limited')

    monkeypatch.setattr(auth_endpoints, '_enforce_rate_limit', reject)
    response = TestClient(app).post(
        '/v1/memory/compute/normalize',
        json={
            'request_id': str(uuid4()),
            'revision': 1,
            'assertion': 'I prefer tea.',
            'source': 'manual',
            'source_attribution': 'primary_user',
        },
    )
    assert response.status_code == 429


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
