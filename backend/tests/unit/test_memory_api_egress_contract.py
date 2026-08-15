from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[2]


def _read(path: str) -> str:
    return (BACKEND_DIR / path).read_text(encoding='utf-8')


def test_v3_memories_route_uses_memory_response_builders_for_client_egress():
    source = _read('routers/memories.py')

    assert (
        'from utils.memory.memory_api_response import memory_batch_response, memory_item_response, memory_list_response'
        in source
    )
    assert 'jsonable_encoder(' not in source
    assert (
        'exposure = MemoryApiExposure.CANONICAL if canonical_lifecycle_exposed else MemoryApiExposure.LEGACY' in source
    )
    assert 'memory_list_response(memory_response.body or [], exposure' in source
    assert 'memory_list_response(\n        memories,\n        MemoryApiExposure.LEGACY' in source
    assert 'memory_item_response(memory, MemoryApiExposure.LEGACY)' in source
    assert 'memory_batch_response(memories, MemoryApiExposure.LEGACY' in source
