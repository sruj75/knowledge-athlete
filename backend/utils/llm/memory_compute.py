"""Stateless Memory proposal computation; this module owns no durable Memory state."""

from __future__ import annotations

import json
from typing import Any, TypeVar, cast

from langchain_core.output_parsers import PydanticOutputParser
from pydantic import BaseModel

from models.memory_compute import (
    MemoryConsolidateProposal,
    MemoryConsolidateRequest,
    MemoryConsolidateResponse,
    MemoryExtractProposal,
    MemoryExtractRequest,
    MemoryExtractResponse,
    MemoryNormalizeProposal,
    MemoryNormalizeRequest,
    MemoryNormalizeResponse,
)
from utils.llm.providers import get_or_create_openai_compatible_llm

Proposal = TypeVar('Proposal', bound=BaseModel)
PINNED_MEMORY_COMPUTE_MODEL = 'gpt-4.1-mini'

EXTRACT_PROMPT = """
You propose bounded personal Memory candidates from speaker-labelled transcript segments.
Return no more than 32 candidates. Every quote must be an exact substring of the referenced
segment. Use subject=primary_user only for a segment explicitly marked is_user=true; otherwise
use other_speaker. Do not turn ambient media, generic statements, questions, secrets, or
another person's facts into user facts. Do not invent identity, persistence state, or evidence.

Packet:
{packet}

Return JSON matching:
{format_instructions}
""".strip()

NORMALIZE_PROMPT = """
Normalize one explicit assertion without deleting material detail or inventing facts. Return a
concise readable Memory plus subject, one snake_case predicate, bounded string arguments,
sensitivity labels, and a short rationale. This is a proposal only: never emit IDs, timestamps,
revision changes, persistence instructions, or authorization state.

Assertion:
{packet}

Return JSON matching:
{format_instructions}
""".strip()

CONSOLIDATE_PROMPT = """
Return exactly one decision for every supplied candidate token and no other candidate. Compare
only against the supplied active Memory tokens. Promote stable, useful, supported user facts;
archive transient context; review uncertainty; reject unsupported or sensitive claims. Choose
create, duplicate, replace, merge, or keep_both. Targets may reference only supplied active
Memory tokens. This is a proposal only: never invent durable IDs or mutate state.

Packet:
{packet}

Return JSON matching:
{format_instructions}
""".strip()


def _response_text(response: Any) -> str:
    content = getattr(response, 'content', response)
    if isinstance(content, list):
        return '\n'.join(str(part) for part in cast(list[Any], content))
    return str(content)


def invoke_model(feature: str, prompt: str, proposal_type: type[Proposal]) -> Proposal:
    """Invoke the immutable S-12 OpenAI model; ``feature`` remains usage context only."""
    del feature
    parser = PydanticOutputParser(pydantic_object=proposal_type)
    response = get_or_create_openai_compatible_llm('openai', PINNED_MEMORY_COMPUTE_MODEL).invoke(prompt)
    return parser.parse(_response_text(response))


def _prompt(template: str, packet: BaseModel, proposal_type: type[Proposal]) -> str:
    parser = PydanticOutputParser(pydantic_object=proposal_type)
    return template.format(
        packet=json.dumps(packet.model_dump(mode='json'), ensure_ascii=False, sort_keys=True),
        format_instructions=parser.get_format_instructions(),
    )


def compute_extract(request: MemoryExtractRequest, uid: str) -> MemoryExtractResponse:
    del uid
    proposal = invoke_model('memory_l1', _prompt(EXTRACT_PROMPT, request, MemoryExtractProposal), MemoryExtractProposal)
    segments = {segment.token: segment for segment in request.segments}
    for candidate in proposal.candidates:
        segment = segments.get(candidate.segment_token)
        if segment is None or candidate.quote not in segment.text:
            raise ValueError('candidate quote is not grounded in its segment')
        expected_subject = 'primary_user' if segment.is_user else 'other_speaker'
        if candidate.subject != expected_subject:
            raise ValueError('candidate subject conflicts with its segment')
    return MemoryExtractResponse(
        request_id=request.request_id,
        generation=request.generation,
        candidates=proposal.candidates,
    )


def compute_normalize(request: MemoryNormalizeRequest, uid: str) -> MemoryNormalizeResponse:
    del uid
    proposal = invoke_model(
        'memory_l2', _prompt(NORMALIZE_PROMPT, request, MemoryNormalizeProposal), MemoryNormalizeProposal
    )
    return MemoryNormalizeResponse(
        request_id=request.request_id,
        revision=request.revision,
        **proposal.model_dump(),
    )


def validate_consolidation_response(
    *, candidate_tokens: set[str], active_memory_tokens: set[str], response: MemoryConsolidateResponse
) -> MemoryConsolidateResponse:
    returned = [decision.candidate_token for decision in response.decisions]
    if len(returned) != len(set(returned)) or set(returned) != candidate_tokens:
        raise ValueError('consolidation must return exactly one decision per candidate')
    targets = {token for decision in response.decisions for token in decision.target_memory_tokens}
    if not targets.issubset(active_memory_tokens):
        raise ValueError('consolidation referenced an unknown active memory')
    return response


def compute_consolidate(request: MemoryConsolidateRequest, uid: str) -> MemoryConsolidateResponse:
    del uid
    proposal = invoke_model(
        'memory_conflict',
        _prompt(CONSOLIDATE_PROMPT, request, MemoryConsolidateProposal),
        MemoryConsolidateProposal,
    )
    response = MemoryConsolidateResponse(
        request_id=request.request_id,
        generation=request.generation,
        decisions=proposal.decisions,
    )
    return validate_consolidation_response(
        candidate_tokens={candidate.token for candidate in request.candidates},
        active_memory_tokens={memory.token for memory in request.active_memories},
        response=response,
    )
