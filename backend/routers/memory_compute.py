"""Authenticated, stateless Memory proposal computation."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import ValidationError

from models.memory_compute import (
    MemoryConsolidateRequest,
    MemoryConsolidateResponse,
    MemoryExtractRequest,
    MemoryExtractResponse,
    MemoryNormalizeRequest,
    MemoryNormalizeResponse,
)
from utils.llm.memory_compute import (
    compute_consolidate,
    compute_extract,
    compute_normalize,
    validate_consolidation_response,
)
from utils.llm.usage_tracker import Features, track_usage
from utils.other.endpoints import get_current_user_uid

logger = logging.getLogger(__name__)
router = APIRouter(tags=['Memory Compute'])


@router.post('/v1/memory/compute/extract', response_model=MemoryExtractResponse)
def extract_memory_candidates(
    request: MemoryExtractRequest,
    uid: str = Depends(get_current_user_uid),
) -> MemoryExtractResponse:
    try:
        with track_usage(uid, Features.MEMORY_L1):
            return compute_extract(request, uid)
    except (ValidationError, ValueError) as error:
        logger.warning('Memory extract returned an invalid candidate shape')
        raise HTTPException(status_code=502, detail='invalid_candidate_response') from error
    except Exception as error:
        logger.warning('Memory extract compute failed')
        raise HTTPException(status_code=502, detail='compute_failed') from error


@router.post('/v1/memory/compute/normalize', response_model=MemoryNormalizeResponse)
def normalize_memory_assertion(
    request: MemoryNormalizeRequest,
    uid: str = Depends(get_current_user_uid),
) -> MemoryNormalizeResponse:
    try:
        with track_usage(uid, Features.MEMORY_L2):
            return compute_normalize(request, uid)
    except (ValidationError, ValueError) as error:
        logger.warning('Memory normalize returned an invalid candidate shape')
        raise HTTPException(status_code=502, detail='invalid_candidate_response') from error
    except Exception as error:
        logger.warning('Memory normalize compute failed')
        raise HTTPException(status_code=502, detail='compute_failed') from error


@router.post('/v1/memory/compute/consolidate', response_model=MemoryConsolidateResponse)
def consolidate_memory_candidates(
    request: MemoryConsolidateRequest,
    uid: str = Depends(get_current_user_uid),
) -> MemoryConsolidateResponse:
    try:
        with track_usage(uid, Features.MEMORY_CONFLICT):
            response = compute_consolidate(request, uid)
        return validate_consolidation_response(
            candidate_tokens={candidate.token for candidate in request.candidates},
            active_memory_tokens={memory.token for memory in request.active_memories},
            response=response,
        )
    except (ValidationError, ValueError) as error:
        logger.warning('Memory consolidate returned an invalid candidate shape')
        raise HTTPException(status_code=502, detail='invalid_candidate_response') from error
    except Exception as error:
        logger.warning('Memory consolidate compute failed')
        raise HTTPException(status_code=502, detail='compute_failed') from error
