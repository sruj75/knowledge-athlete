"""Bounded wire contracts for stateless Memory model computation."""

from __future__ import annotations

import json
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

ShortText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=256)]
MemoryText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50_000)]
Rationale = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4_096)]
SegmentToken = Annotated[str, StringConstraints(pattern=r'^s[0-9]+$')]
CandidateToken = Annotated[str, StringConstraints(pattern=r'^c[0-9]+$')]
MemoryToken = Annotated[str, StringConstraints(pattern=r'^m[0-9]+$')]


def _validate_bounded_arguments(value: dict[str, str]) -> dict[str, str]:
    if len(value) > 32 or len(json.dumps(value, ensure_ascii=False)) > 8_192:
        raise ValueError('arguments exceed the bounded contract')
    if any(not key or len(key) > 128 or len(argument) > 1_024 for key, argument in value.items()):
        raise ValueError('argument keys and values must be bounded')
    return value


class MemoryComputeModel(BaseModel):
    model_config = ConfigDict(extra='forbid')


class MemoryTranscriptSegment(MemoryComputeModel):
    token: SegmentToken
    speaker_label: ShortText
    text: MemoryText
    is_user: bool


class MemoryExtractRequest(MemoryComputeModel):
    request_id: UUID
    generation: int = Field(ge=0)
    segments: list[MemoryTranscriptSegment] = Field(min_length=1, max_length=500)
    language: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=32)] = 'en'

    @model_validator(mode='after')
    def validate_packet_size(self) -> 'MemoryExtractRequest':
        if sum(len(segment.text) for segment in self.segments) > 1_000_000:
            raise ValueError('segment text exceeds the packet limit')
        tokens = [segment.token for segment in self.segments]
        if len(tokens) != len(set(tokens)):
            raise ValueError('segment tokens must be unique')
        return self


class MemoryExtractCandidate(MemoryComputeModel):
    content: MemoryText
    category: Literal['system', 'interesting']
    quote: MemoryText
    segment_token: SegmentToken
    speaker_label: ShortText
    subject: Literal['primary_user', 'other_speaker']
    about: ShortText
    archive_class: Literal['general', 'sensitive'] = 'general'
    risk_flags: list[ShortText] = Field(default_factory=list, max_length=16)
    sensitivity_labels: list[ShortText] = Field(default_factory=list, max_length=16)
    confidence: float = Field(ge=0, le=1, allow_inf_nan=False)


class MemoryExtractProposal(MemoryComputeModel):
    candidates: list[MemoryExtractCandidate] = Field(default_factory=list, max_length=32)


class MemoryExtractResponse(MemoryComputeModel):
    request_id: UUID
    generation: int = Field(ge=0)
    candidates: list[MemoryExtractCandidate] = Field(default_factory=list, max_length=32)


class MemoryNormalizeRequest(MemoryComputeModel):
    request_id: UUID
    revision: int = Field(gt=0)
    assertion: MemoryText
    source: Literal['manual', 'correction']
    source_attribution: Literal['primary_user', 'user_owned_project', 'user_relationship', 'third_party', 'unclear']
    provenance_tokens: list[ShortText] = Field(default_factory=list, max_length=16)


class MemoryNormalizeProposal(MemoryComputeModel):
    normalized_content: MemoryText
    subject: Literal['primary_user', 'user_owned_project', 'user_relationship', 'third_party', 'unclear']
    predicate: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128, pattern=r'^[a-z][a-z0-9_]*$')
    ]
    arguments: dict[str, str] = Field(default_factory=dict)
    sensitivity_labels: list[ShortText] = Field(default_factory=list, max_length=16)
    rationale: Rationale

    @field_validator('arguments')
    @classmethod
    def validate_arguments(cls, value: dict[str, str]) -> dict[str, str]:
        return _validate_bounded_arguments(value)


class MemoryNormalizeResponse(MemoryNormalizeProposal):
    request_id: UUID
    revision: int = Field(gt=0)


class MemoryConsolidateCandidate(MemoryComputeModel):
    token: CandidateToken
    content: MemoryText
    evidence_tokens: list[SegmentToken] = Field(default_factory=list, max_length=32)
    sensitivity_labels: list[ShortText] = Field(default_factory=list, max_length=16)
    subject: Literal['primary_user', 'user_owned_project', 'user_relationship', 'third_party', 'unclear']
    predicate: ShortText | None = None
    arguments: dict[str, str] = Field(default_factory=dict)

    @field_validator('arguments')
    @classmethod
    def validate_arguments(cls, value: dict[str, str]) -> dict[str, str]:
        return _validate_bounded_arguments(value)


class MemoryConsolidateActiveMemory(MemoryComputeModel):
    token: MemoryToken
    content: MemoryText
    layer: Literal['short_term', 'long_term']
    revision: int = Field(gt=0)
    subject: Literal['primary_user', 'user_owned_project', 'user_relationship', 'third_party', 'unclear']
    predicate: ShortText | None = None
    arguments: dict[str, str] = Field(default_factory=dict)
    sensitivity_labels: list[ShortText] = Field(default_factory=list, max_length=16)

    @field_validator('arguments')
    @classmethod
    def validate_arguments(cls, value: dict[str, str]) -> dict[str, str]:
        return _validate_bounded_arguments(value)


class MemoryConsolidateRequest(MemoryComputeModel):
    request_id: UUID
    generation: int = Field(ge=0)
    candidates: list[MemoryConsolidateCandidate] = Field(min_length=1, max_length=32)
    active_memories: list[MemoryConsolidateActiveMemory] = Field(default_factory=list, max_length=128)

    @model_validator(mode='after')
    def validate_tokens(self) -> 'MemoryConsolidateRequest':
        candidate_tokens = [candidate.token for candidate in self.candidates]
        memory_tokens = [memory.token for memory in self.active_memories]
        if len(candidate_tokens) != len(set(candidate_tokens)):
            raise ValueError('candidate tokens must be unique')
        if len(memory_tokens) != len(set(memory_tokens)):
            raise ValueError('active memory tokens must be unique')
        return self


class MemoryConsolidateDecision(MemoryComputeModel):
    candidate_token: CandidateToken
    action: Literal['promote', 'archive', 'review', 'reject']
    reconciliation: Literal['create', 'duplicate', 'replace', 'merge', 'keep_both']
    target_memory_tokens: list[MemoryToken] = Field(default_factory=list, max_length=8)
    memory_text: MemoryText | None = None
    evidence_tokens: list[SegmentToken] = Field(default_factory=list, max_length=32)
    subject: Literal['primary_user', 'user_owned_project', 'user_relationship', 'third_party', 'unclear']
    predicate: ShortText | None = None
    arguments: dict[str, str] = Field(default_factory=dict)
    sensitivity_labels: list[ShortText] = Field(default_factory=list, max_length=16)
    relationship_to_user: Literal[
        'self', 'owned_work', 'adopted', 'asking_about', 'encountered', 'other_speaker', 'unclear'
    ]
    aboutness: Literal['primary_user', 'user_owned_project', 'user_relationship', 'third_party', 'unclear']
    basis_for_memory: Literal['explicit', 'recurring', 'inferred_pattern', 'weak_or_none']
    confidence: Literal['high', 'medium', 'low']
    rationale: Rationale

    @field_validator('arguments')
    @classmethod
    def validate_arguments(cls, value: dict[str, str]) -> dict[str, str]:
        return _validate_bounded_arguments(value)

    @model_validator(mode='after')
    def validate_decision_shape(self) -> 'MemoryConsolidateDecision':
        requires_target = self.reconciliation in {'duplicate', 'replace', 'merge'}
        if requires_target and not self.target_memory_tokens:
            raise ValueError('the reconciliation requires a target memory')
        if not requires_target and self.target_memory_tokens:
            raise ValueError('the reconciliation does not allow target memories')
        if self.action == 'promote' and self.memory_text is None:
            raise ValueError('promote requires memory_text')
        if self.action != 'promote' and self.memory_text is not None:
            raise ValueError('only promote may return memory_text')
        if self.action == 'promote' and (not self.evidence_tokens or self.predicate is None):
            raise ValueError('promote requires evidence and a structured predicate')
        if self.action == 'promote' and self.basis_for_memory == 'weak_or_none':
            raise ValueError('promote requires a defensible basis')
        if self.action == 'promote' and self.reconciliation == 'duplicate':
            raise ValueError('duplicate observations must not be promoted')
        if self.action != 'promote' and self.reconciliation in {'replace', 'merge', 'keep_both'}:
            raise ValueError('only promote may replace, merge, or keep both')
        if len(self.target_memory_tokens) != len(set(self.target_memory_tokens)):
            raise ValueError('target memory tokens must be unique')
        if len(self.evidence_tokens) != len(set(self.evidence_tokens)):
            raise ValueError('evidence tokens must be unique')
        return self


class MemoryConsolidateProposal(MemoryComputeModel):
    decisions: list[MemoryConsolidateDecision] = Field(min_length=1, max_length=32)


class MemoryConsolidateResponse(MemoryComputeModel):
    request_id: UUID
    generation: int = Field(ge=0)
    decisions: list[MemoryConsolidateDecision] = Field(min_length=1, max_length=32)
