from __future__ import annotations

import json
import logging
import os
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, TypedDict, cast

from pinecone import Pinecone

from models.conversation_metadata import ConversationMetadataKeys, metadata_list
from utils.llm.clients import embeddings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# TypedDict contracts for Pinecone vector records.
#
# Pinecone SDK types are partially untyped at the SDK boundary, so the module-
# level ``index`` handle below is typed as ``Any`` and every Pinecone call
# funnels through it. These TypedDicts document the document contracts we
# build (``VectorRecordDoc``) and consume (``VectorMatchDoc``) at that
# boundary; ``total=False`` because keys vary by namespace.
# ---------------------------------------------------------------------------


class VectorMetadataDoc(TypedDict, total=False):
    """Metadata sub-document attached to a Pinecone vector record.

    Captures the union of metadata keys written across this module's retained
    conversation, transcript-chunk, and imported-post namespaces.
    """

    uid: str
    memory_id: str
    conversation_id: str
    post_id: str
    chunk_index: int
    created_at: int
    category: str
    subject_entity_id: str
    kind: str


class VectorRecordDoc(TypedDict):
    """Pinecone upsert payload: ``id`` + ``values`` + ``metadata``.

    All three keys are always populated by every upsert site in this module.
    """

    id: str
    values: List[float]
    metadata: Dict[str, Any]


class VectorMatchDoc(TypedDict, total=False):
    """Single match returned by a Pinecone ``query`` response."""

    id: str
    score: float
    values: List[float]
    metadata: Dict[str, Any]


_pinecone_api_key: Optional[str] = os.getenv('PINECONE_API_KEY')
_pinecone_index_name: Optional[str] = os.getenv('PINECONE_INDEX_NAME')

# Pinecone Index methods (upsert/query/update/delete/list) are partially
# untyped at the SDK boundary (e.g. ``**kwargs: Unknown``). Typing the
# handles as ``Any`` isolates that boundary so downstream call sites stay
# warning-clean without per-call ignores.
pc: Any = None
index: Any = None
if _pinecone_api_key and _pinecone_index_name:
    pc = Pinecone(api_key=_pinecone_api_key)
    index = pc.Index(_pinecone_index_name)


def _get_data(uid: str, conversation_id: str, vector: List[float]) -> VectorRecordDoc:
    metadata: VectorMetadataDoc = {
        'uid': uid,
        # Historical ns1 conversation vectors use this provider metadata key.
        'memory_id': conversation_id,
        'created_at': int(datetime.now(timezone.utc).timestamp()),
    }
    return {
        "id": f'{uid}-{conversation_id}',
        "values": vector,
        'metadata': dict(metadata),
    }


def upsert_vector(uid: str, conversation_id: str, vector: List[float]) -> None:
    res = index.upsert(vectors=[_get_data(uid, conversation_id, vector)], namespace="ns1")
    logger.info(f'upsert_vector {res}')


def upsert_vector2(uid: str, conversation_id: str, vector: List[float], metadata: Dict[str, Any]) -> None:
    if index is None:
        return
    data: VectorRecordDoc = _get_data(uid, conversation_id, vector)
    typed_metadata: Dict[str, Any] = data['metadata']
    typed_metadata.update(metadata)
    res = index.upsert(vectors=[data], namespace="ns1")
    logger.info(f'upsert_vector {res}')


def update_vector_metadata(uid: str, conversation_id: str, metadata: Dict[str, Any]) -> Dict[str, Any]:
    if index is None:
        return {}
    metadata['uid'] = uid
    metadata['memory_id'] = conversation_id
    result: Dict[str, Any] = index.update(f'{uid}-{conversation_id}', set_metadata=metadata, namespace="ns1")
    return result


def upsert_vectors(uid: str, vectors: List[List[float]], conversation_ids: List[str]) -> None:
    data: List[VectorRecordDoc] = [_get_data(uid, cid, vector) for cid, vector in zip(conversation_ids, vectors)]
    res = index.upsert(vectors=data, namespace="ns1")
    logger.info(f'upsert_vectors {res}')


def _created_at_filter(starts_at: Optional[int] = None, ends_at: Optional[int] = None) -> Optional[Dict[str, int]]:
    if starts_at is None and ends_at is None:
        return None
    if starts_at is not None and ends_at is not None and starts_at > ends_at:
        return None

    created_at: Dict[str, int] = {}
    if starts_at is not None:
        created_at['$gte'] = starts_at
    if ends_at is not None:
        created_at['$lte'] = ends_at
    return created_at


def query_vectors(
    query: str,
    uid: str,
    starts_at: Optional[int] = None,
    ends_at: Optional[int] = None,
    k: int = 5,
) -> List[str]:
    if index is None:
        return []

    filter_data: Dict[str, Any] = {'uid': uid}
    created_at = _created_at_filter(starts_at, ends_at)
    if (starts_at is not None or ends_at is not None) and created_at is None:
        logger.warning('Skipping conversation vector search with invalid date filter')
        return []
    if created_at is not None:
        filter_data['created_at'] = created_at

    xq = embeddings.embed_query(query)
    xc = index.query(vector=xq, top_k=k, include_metadata=False, filter=filter_data, namespace="ns1")
    matches: List[Any] = xc['matches']
    return [item['id'].replace(f'{uid}-', '') for item in matches]


def query_vectors_by_metadata(
    uid: str,
    vector: List[float],
    dates_filter: List[datetime],
    people: List[str],
    topics: List[str],
    entities: List[str],
    dates: List[str],
    limit: int = 5,
) -> List[str]:
    if index is None:
        return []
    and_clauses: List[Dict[str, Any]] = [{'uid': {'$eq': uid}}]
    filter_data: Dict[str, Any] = {'$and': and_clauses}
    if people or topics or entities or dates:
        and_clauses.append(
            {
                '$or': [
                    {ConversationMetadataKeys.PEOPLE: {'$in': people}},
                    {ConversationMetadataKeys.TOPICS: {'$in': topics}},
                    {ConversationMetadataKeys.ENTITIES: {'$in': entities}},
                    # {'dates': {'$in': dates_mentioned}},
                ]
            }
        )
    if dates_filter and len(dates_filter) == 2 and dates_filter[0] and dates_filter[1]:
        logger.info(f'dates_filter {dates_filter}')
        and_clauses.append(
            {'created_at': {'$gte': int(dates_filter[0].timestamp()), '$lte': int(dates_filter[1].timestamp())}}
        )

    xc = index.query(
        vector=vector, filter=filter_data, namespace="ns1", include_values=False, include_metadata=True, top_k=1000
    )
    if not xc['matches']:
        # Relax-retry when the structured people/topics/entities $or clause produced no hits, dropping
        # it and re-querying uid-only. The $or clause, when present, is always and_clauses[1] (the date
        # range is appended after it). The previous len == 3 guard only relaxed when a date filter was
        # ALSO present, so the common no-date query (uid + $or, len == 2) fell through to return [] and
        # never broadened. Never pop a date-only clause.
        if len(and_clauses) > 1 and '$or' in and_clauses[1]:
            and_clauses.pop(1)
            logger.warning(f'query_vectors_by_metadata retrying without structured filters: {json.dumps(filter_data)}')
            xc = index.query(
                vector=vector,
                filter=filter_data,
                namespace="ns1",
                include_values=False,
                include_metadata=True,
                top_k=20,
            )
        else:
            return []

    conversation_id_to_matches: defaultdict[str, int] = defaultdict(int)
    matches: List[Any] = xc['matches']
    for item in matches:
        metadata: Dict[str, Any] = item['metadata']
        conversation_id: str = metadata['memory_id']
        for topic in topics:
            if topic in metadata_list(metadata, ConversationMetadataKeys.TOPICS):
                conversation_id_to_matches[conversation_id] += 1
        for entity in entities:
            if entity in metadata_list(metadata, ConversationMetadataKeys.ENTITIES):
                conversation_id_to_matches[conversation_id] += 1
        for person in people:
            if person in metadata_list(metadata, ConversationMetadataKeys.PEOPLE):
                conversation_id_to_matches[conversation_id] += 1

    conversations_id: List[str] = [item['id'].replace(f'{uid}-', '') for item in matches]
    conversations_id.sort(key=lambda x: conversation_id_to_matches[x], reverse=True)
    return conversations_id[:limit] if len(conversations_id) > limit else conversations_id


def delete_vector(uid: str, conversation_id: str) -> None:
    """
    Delete a conversation vector from Pinecone.

    Note: Vectors are stored with ID format '{uid}-{conversation_id}'
    """
    if index is None:
        logger.warning('Pinecone index not initialized, skipping conversation vector delete')
        return
    vector_id = f'{uid}-{conversation_id}'
    result = index.delete(ids=[vector_id], namespace="ns1")
    logger.info(f'delete_vector {vector_id} {result}')


# ==========================================
# X (Twitter) Post Vector Functions
# Semantic search over the user's raw imported tweets/bookmarks.
# ==========================================

X_POSTS_NAMESPACE = "ns_x"


def upsert_x_post_vectors_batch(uid: str, items: List[Dict[str, Any]]) -> int:
    """Upsert X post embeddings in one request. Each item: {'post_id', 'content', 'kind'}.
    Returns the number of vectors written (0 if Pinecone is not configured)."""
    if index is None:
        logger.warning('Pinecone index not initialized, skipping x_post vector batch upsert')
        return 0
    filtered: List[Dict[str, Any]] = [it for it in items if (it.get('content') or '').strip()]
    if not filtered:
        return 0

    vectors: List[List[float]] = embeddings.embed_documents([it['content'] for it in filtered])
    now_ts = int(datetime.now(timezone.utc).timestamp())
    payload: List[VectorRecordDoc] = [
        {
            "id": f"{uid}-x-{it['post_id']}",
            "values": vectors[i],
            "metadata": {
                "uid": uid,
                "post_id": str(it['post_id']),
                "kind": it.get('kind', 'tweet'),
                "created_at": now_ts,
            },
        }
        for i, it in enumerate(filtered)
    ]
    res = index.upsert(vectors=payload, namespace=X_POSTS_NAMESPACE)
    logger.info(f'upsert_x_post_vectors_batch count={len(payload)} {res}')
    return len(payload)


def find_similar_x_posts(uid: str, content: str, limit: int = 10) -> List[Dict[str, Any]]:
    """Semantic search over the user's X posts. Returns [{post_id, kind, score}]."""
    if index is None:
        logger.warning('Pinecone index not initialized, skipping x_post similarity search')
        return []
    vector = embeddings.embed_query(content)
    xc = index.query(
        vector=vector, top_k=limit, include_metadata=True, filter={'uid': uid}, namespace=X_POSTS_NAMESPACE
    )
    matches: List[Any] = xc.get('matches', [])
    return [
        {
            'post_id': m['metadata'].get('post_id'),
            'kind': m['metadata'].get('kind'),
            'score': m['score'],
        }
        for m in matches
    ]


def delete_conversation_vectors_batch(uid: str, conversation_ids: List[str]) -> None:
    """Delete a user's conversation vectors (ns1) in one batched, chunked call.

    Chunked so a single failure can't abandon the rest (and to stay under Pinecone's per-delete id
    limit). Used by account deletion to purge all of a user's conversation vectors.
    """
    if index is None:
        logger.warning('Pinecone index not initialized, skipping conversation vector batch delete')
        return
    if not conversation_ids:
        return
    vector_ids = [f'{uid}-{cid}' for cid in conversation_ids]
    for i in range(0, len(vector_ids), 1000):
        index.delete(ids=vector_ids[i : i + 1000], namespace="ns1")
    logger.info(f'delete_conversation_vectors_batch count={len(vector_ids)}')


# ---------------------------------------------------------------------------
# Transcript chunks ("ns_tchunks"): verbatim retrieval over raw conversation
# transcripts. Conversation vectors (ns1) embed only the structured SUMMARY, so
# specific details (exact dates, names, numbers, one-off mentions) are not
# findable semantically. Chunk vectors make the raw transcript searchable.
#
# Privacy: chunk TEXT is embedded but never stored in Pinecone metadata —
# transcripts are encrypted at rest in Firestore, and mirroring them as
# plaintext metadata would bypass that. Readers re-hydrate the text from
# Firestore via (conversation_id, chunk_index).
TRANSCRIPT_CHUNKS_NAMESPACE = "ns_tchunks"


def upsert_transcript_chunk_vectors(uid: str, conversation_id: str, chunks: List[Dict[str, Any]]) -> int:
    """chunks: [{'text': str, 'created_at': int unix ts, 'chunk_index': int}]"""
    if index is None:
        logger.warning('Pinecone index not initialized, skipping transcript chunk upsert')
        return 0
    filtered: List[Dict[str, Any]] = [c for c in chunks if (c.get('text') or '').strip()]
    if not filtered:
        return 0

    vectors: List[List[float]] = embeddings.embed_documents([c['text'] for c in filtered])
    payload: List[VectorRecordDoc] = []
    for c, v in zip(filtered, vectors):
        metadata: VectorMetadataDoc = {
            'uid': uid,
            'conversation_id': conversation_id,
            'chunk_index': c['chunk_index'],
            'created_at': int(c['created_at']),
        }
        payload.append(
            {
                'id': f"{uid}-{conversation_id}-c{c['chunk_index']}",
                'values': v,
                'metadata': dict(metadata),
            }
        )

    upserted = 0
    for i in range(0, len(payload), 100):
        index.upsert(vectors=payload[i : i + 100], namespace=TRANSCRIPT_CHUNKS_NAMESPACE)
        upserted += len(payload[i : i + 100])
    logger.info(f'upsert_transcript_chunk_vectors uid={uid} conversation={conversation_id} count={upserted}')
    return upserted


def search_transcript_chunks(
    uid: str,
    query: str,
    limit: int = 20,
    starts_at: Optional[int] = None,
    ends_at: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Semantic search over transcript chunks. Returns chunk references
    [{conversation_id, chunk_index, created_at, score}] — hydrate text from
    Firestore (utils.conversations.transcript_chunks.hydrate_chunk_texts)."""
    if index is None:
        return []
    vector = embeddings.embed_query(query)
    filter_data: Dict[str, Any] = {'uid': uid}
    if starts_at is not None and ends_at is not None:
        filter_data['created_at'] = {'$gte': int(starts_at), '$lte': int(ends_at)}
    xc = index.query(
        vector=vector,
        top_k=limit,
        include_metadata=True,
        filter=filter_data,
        namespace=TRANSCRIPT_CHUNKS_NAMESPACE,
    )
    results: List[Dict[str, Any]] = []
    matches: List[Any] = xc.get('matches', [])
    for m in matches:
        raw_md: object = m.get('metadata')
        md: Dict[str, Any] = cast(Dict[str, Any], raw_md) if isinstance(raw_md, dict) else {}
        results.append(
            {
                'created_at': int(md['created_at']) if md.get('created_at') is not None else None,
                'conversation_id': md.get('conversation_id'),
                'chunk_index': int(md['chunk_index']) if md.get('chunk_index') is not None else None,
                'score': m.get('score', 0),
            }
        )
    return results


def delete_transcript_chunk_vectors(uid: str, conversation_id: str) -> None:
    """Delete all chunk vectors for one conversation (id-prefix listing on serverless)."""
    if index is None:
        return
    prefix = f'{uid}-{conversation_id}-c'
    try:
        ids: List[str] = []
        for page in index.list(prefix=prefix, namespace=TRANSCRIPT_CHUNKS_NAMESPACE):
            ids.extend(cast(List[str], page if isinstance(page, list) else [page]))
        for i in range(0, len(ids), 1000):
            index.delete(ids=ids[i : i + 1000], namespace=TRANSCRIPT_CHUNKS_NAMESPACE)
        if ids:
            logger.info(f'delete_transcript_chunk_vectors uid={uid} conversation={conversation_id} count={len(ids)}')
    except Exception:
        logger.warning(f'delete_transcript_chunk_vectors failed uid={uid} conversation={conversation_id}')


def delete_transcript_chunk_vectors_batch(
    uid: str, conversation_ids: List[str], *, raise_on_failure: bool = False
) -> int:
    """Account-deletion purge: drop all transcript-chunk vectors for the user's conversations."""
    if index is None:
        if raise_on_failure and conversation_ids:
            raise RuntimeError('Pinecone index not initialized for transcript chunk vector delete')
        return 0
    if not conversation_ids:
        return 0
    deleted = 0
    failures = 0
    for conversation_id in conversation_ids:
        prefix = f'{uid}-{conversation_id}-c'
        try:
            ids: List[str] = []
            for page in index.list(prefix=prefix, namespace=TRANSCRIPT_CHUNKS_NAMESPACE):
                ids.extend(cast(List[str], page if isinstance(page, list) else [page]))
            for i in range(0, len(ids), 1000):
                index.delete(ids=ids[i : i + 1000], namespace=TRANSCRIPT_CHUNKS_NAMESPACE)
            deleted += len(ids)
        except Exception:
            failures += 1
            logger.warning(f'delete_transcript_chunk_vectors_batch failed uid={uid} conversation={conversation_id}')
    if failures and raise_on_failure:
        raise RuntimeError(f'transcript chunk vector delete failed for {failures} conversation(s)')
    logger.info(f'delete_transcript_chunk_vectors_batch uid={uid} total_deleted={deleted}')
    return deleted
