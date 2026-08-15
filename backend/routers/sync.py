"""Retained conversation-audio playback and merge routes.

S-02 retired wearable file ingestion from this router. The remaining routes
serve already-authorized conversation audio and execute the shared playback
artifact job; they are not wearable sync compatibility surfaces.
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel

from database import conversations as conversations_db
from database.job_run_locks import release_job_run_lock, try_acquire_job_run_lock
from models.sync_audio import AudioPrecacheResponse, AudioUrlsResponse
from utils.cloud_tasks import get_sync_tasks_max_attempts, verify_cloud_tasks_oidc
from utils.executors import db_executor, run_blocking, storage_executor, sync_executor
from utils.other import endpoints as auth
from utils.other.storage import (
    compute_audio_files_fingerprint,
    get_conversation_playback_signed_url,
    get_playback_artifact_signed_url,
    mark_conversation_playback_unavailable,
    mark_playback_unavailable,
    upload_conversation_playback_artifact,
    upload_playback_artifact,
)
from utils.sync import playback as sync_playback

logger = logging.getLogger(__name__)
router = APIRouter()


class AudioDownloadPendingResponse(BaseModel):
    status: str
    poll_after_ms: int


@router.post("/v1/sync/audio/{conversation_id}/precache", response_model=AudioPrecacheResponse, tags=["v1"])
def precache_conversation_audio_endpoint(
    conversation_id: str,
    uid: str = Depends(auth.get_current_user_uid),
):
    """Warm the playback cache for an existing conversation."""
    conversation = conversations_db.get_conversation(uid, conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if conversation.get("is_locked", False):
        raise HTTPException(status_code=402, detail="A paid plan is required to access this conversation.")
    return sync_playback.precache_audio_files(uid, conversation_id, conversation.get("audio_files", []))


@router.get("/v1/sync/audio/{conversation_id}/urls", response_model=AudioUrlsResponse, tags=["v1"])
def get_audio_signed_urls_endpoint(
    conversation_id: str,
    uid: str = Depends(auth.get_current_user_uid),
):
    """Return playback URLs or pending states for conversation audio."""
    conversation = conversations_db.get_conversation(uid, conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if conversation.get("is_locked", False):
        raise HTTPException(status_code=402, detail="A paid plan is required to access this conversation.")
    return sync_playback.get_audio_signed_urls(
        uid,
        conversation_id,
        conversation.get("audio_files", []),
        conversation=conversation,
    )


@router.get(
    "/v1/sync/audio/{conversation_id}/{audio_file_id}",
    tags=["v1"],
    response_class=StreamingResponse,
    responses={
        200: {
            "description": "Audio stream.",
            "content": {
                "audio/wav": {"schema": {"type": "string", "format": "binary"}},
                "audio/mpeg": {"schema": {"type": "string", "format": "binary"}},
                "application/octet-stream": {"schema": {"type": "string", "format": "binary"}},
            },
        },
        202: {"description": "Audio artifact is being prepared.", "model": AudioDownloadPendingResponse},
        206: {
            "description": "Partial audio stream.",
            "content": {
                "audio/wav": {"schema": {"type": "string", "format": "binary"}},
                "audio/mpeg": {"schema": {"type": "string", "format": "binary"}},
                "application/octet-stream": {"schema": {"type": "string", "format": "binary"}},
            },
        },
    },
)
def download_audio_file_endpoint(
    conversation_id: str,
    audio_file_id: str,
    request: Request,
    format: str = Query(default="wav", pattern="^(wav|pcm)$"),
    uid: str = Depends(auth.get_current_user_uid),
):
    """Download one authorized conversation-audio file."""
    conversation = conversations_db.get_conversation(uid, conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if conversation.get("is_locked", False):
        raise HTTPException(status_code=402, detail="A paid plan is required to access this conversation.")

    audio_file = next(
        (candidate for candidate in conversation.get("audio_files", []) if candidate.get("id") == audio_file_id),
        None,
    )
    if not audio_file:
        raise HTTPException(status_code=404, detail="Audio file not found in conversation")
    return sync_playback.download_audio_file_response(
        uid,
        conversation_id,
        audio_file_id,
        audio_file,
        request,
        format,
    )


@router.post("/v2/audio-merge-jobs/run", include_in_schema=False)
async def run_audio_merge_job(request: Request, task_retry_count: int = Depends(verify_cloud_tasks_oidc)):
    """Build one playback artifact under the shared Cloud Tasks contract."""
    try:
        payload = await request.json()
        schema_version = payload.get("schema_version")
        if schema_version != 2:
            uid = payload["uid"]
            conversation_id = payload["conversation_id"]
            audio_file_id = payload["audio_file_id"]
            timestamps = list(payload["timestamps"])
    except Exception as error:
        logger.error("audio_merge handler: invalid payload, dropping task: %s", error)
        return JSONResponse(status_code=200, content={"status": "dropped", "reason": "invalid_payload"})

    if schema_version == 2:
        return await _run_conversation_merge_job(payload, task_retry_count)

    lock_key = f"audio:{conversation_id}:{audio_file_id}"
    lock_token = await run_blocking(db_executor, try_acquire_job_run_lock, lock_key)
    if not lock_token:
        return JSONResponse(status_code=409, content={"status": "locked"})

    try:
        existing = await run_blocking(
            storage_executor,
            get_playback_artifact_signed_url,
            uid,
            conversation_id,
            audio_file_id,
        )
        if existing:
            return JSONResponse(status_code=200, content={"status": "exists"})

        try:
            mp3_data = await run_blocking(
                sync_executor,
                sync_playback.build_playback_artifact,
                uid,
                conversation_id,
                timestamps,
            )
        except FileNotFoundError:
            logger.warning("audio_merge: chunks missing conv=%s file=%s, dropping", conversation_id, audio_file_id)
            await run_blocking(
                storage_executor,
                mark_playback_unavailable,
                uid,
                conversation_id,
                audio_file_id,
                "chunks_missing",
            )
            return JSONResponse(status_code=200, content={'status': 'dropped', 'reason': 'chunks_missing'})
        except Exception as error:
            if task_retry_count >= get_sync_tasks_max_attempts() - 1:
                logger.error("audio_merge_failed_final conv=%s file=%s: %s", conversation_id, audio_file_id, error)
                await run_blocking(
                    storage_executor,
                    mark_playback_unavailable,
                    uid,
                    conversation_id,
                    audio_file_id,
                    "merge_failed",
                )
                return JSONResponse(status_code=200, content={"status": "failed_final"})
            logger.warning(
                "audio_merge: attempt %s failed conv=%s file=%s, will retry: %s",
                task_retry_count + 1,
                conversation_id,
                audio_file_id,
                error,
            )
            return JSONResponse(status_code=500, content={"status": "retry"})

        if not mp3_data:
            logger.warning("audio_merge: no audio data conv=%s file=%s, dropping", conversation_id, audio_file_id)
            await run_blocking(
                storage_executor,
                mark_playback_unavailable,
                uid,
                conversation_id,
                audio_file_id,
                "empty_audio",
            )
            return JSONResponse(status_code=200, content={"status": "dropped", "reason": "empty_audio"})

        await run_blocking(
            storage_executor,
            upload_playback_artifact,
            uid,
            conversation_id,
            audio_file_id,
            mp3_data,
        )
        logger.info(
            "audio_merge: built artifact conv=%s file=%s size=%s", conversation_id, audio_file_id, len(mp3_data)
        )
        return JSONResponse(status_code=200, content={"status": "done"})
    finally:
        await run_blocking(db_executor, release_job_run_lock, lock_key, lock_token)


async def _run_conversation_merge_job(payload: dict, task_retry_count: int):
    """Build the conversation-level dense MP3 and persist its playback stamp."""
    try:
        uid = payload["uid"]
        conversation_id = payload["conversation_id"]
        payload_fingerprint = payload.get("fingerprint")
    except Exception as error:
        logger.error("audio_merge handler: invalid v2 payload, dropping task: %s", error)
        return JSONResponse(status_code=200, content={"status": "dropped", "reason": "invalid_payload"})

    lock_key = f"audio:{conversation_id}:conversation"
    lock_token = await run_blocking(db_executor, try_acquire_job_run_lock, lock_key)
    if not lock_token:
        return JSONResponse(status_code=409, content={"status": "locked"})

    try:
        conversation = await run_blocking(db_executor, conversations_db.get_conversation, uid, conversation_id)
        if not conversation or not conversation.get("audio_files"):
            return JSONResponse(status_code=200, content={"status": "dropped", "reason": "no_audio_files"})
        audio_files = conversation["audio_files"]
        fingerprint = compute_audio_files_fingerprint(audio_files)
        if payload_fingerprint and payload_fingerprint != fingerprint:
            return JSONResponse(status_code=200, content={"status": "superseded"})

        stamp = conversation.get("conversation_audio") or {}
        if stamp.get("audio_files_fingerprint") == fingerprint:
            existing = await run_blocking(
                storage_executor,
                get_conversation_playback_signed_url,
                uid,
                conversation_id,
            )
            if existing:
                return JSONResponse(status_code=200, content={"status": "exists"})

        started_at = conversation.get("started_at") or conversation.get("created_at")
        started_at_ts = started_at.timestamp()
        try:
            mp3_data, spans = await run_blocking(
                sync_executor,
                sync_playback.build_conversation_playback_artifact,
                uid,
                conversation_id,
                audio_files,
                started_at_ts,
            )
        except FileNotFoundError:
            logger.warning("audio_merge: conversation chunks missing conv=%s, dropping", conversation_id)
            await run_blocking(
                storage_executor,
                mark_conversation_playback_unavailable,
                uid,
                conversation_id,
                fingerprint,
                "chunks_missing",
            )
            return JSONResponse(status_code=200, content={'status': 'dropped', 'reason': 'chunks_missing'})
        except Exception as error:
            if task_retry_count >= get_sync_tasks_max_attempts() - 1:
                logger.error("audio_merge_failed_final conversation artifact conv=%s: %s", conversation_id, error)
                await run_blocking(
                    storage_executor,
                    mark_conversation_playback_unavailable,
                    uid,
                    conversation_id,
                    fingerprint,
                    "merge_failed",
                )
                return JSONResponse(status_code=200, content={"status": "failed_final"})
            logger.warning(
                "audio_merge: conversation attempt %s failed conv=%s, will retry: %s",
                task_retry_count + 1,
                conversation_id,
                error,
            )
            return JSONResponse(status_code=500, content={"status": "retry"})

        await run_blocking(
            storage_executor,
            upload_conversation_playback_artifact,
            uid,
            conversation_id,
            mp3_data,
        )
        mp3_size = len(mp3_data)
        del mp3_data
        captured_duration = round(sum(span["len"] for span in spans), 3)
        wall_duration = round(spans[-1]["wall_offset"] + spans[-1]["len"], 3)
        await run_blocking(
            db_executor,
            conversations_db.update_conversation,
            uid,
            conversation_id,
            {
                "conversation_audio": {
                    "audio_files_fingerprint": fingerprint,
                    "duration": wall_duration,
                    "captured_duration": captured_duration,
                    "spans": spans,
                    "content_type": "audio/mpeg",
                    "built_at": datetime.now(timezone.utc),
                }
            },
        )
        logger.info(
            "audio_merge: built conversation artifact conv=%s size=%s spans=%s",
            conversation_id,
            mp3_size,
            len(spans),
        )
        return JSONResponse(status_code=200, content={"status": "done"})
    finally:
        await run_blocking(db_executor, release_job_run_lock, lock_key, lock_token)
