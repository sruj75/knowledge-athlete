"""Server-owned canonical long-term promotion admission contracts.

Long-term memory is a state transition, never a create-time option. The
promotion receipt binds the decision to the current short-term item revision,
content, evidence, and superseded items without creating a second graph
projection.
"""

from __future__ import annotations

from typing import List, Literal

from pydantic import BaseModel, field_validator, model_validator

from models.memory_contracts import deterministic_contract_id

PROMOTION_ADMISSION_VERSION = "canonical_memory_promotion_admission.v1"
PROMOTION_PLANNER_ID = "canonical_batched_promotion"
PROMOTION_PLANNER_VERSION = "v2"


class PromotionAdmissionReceipt(BaseModel):
    """Server-authored proof that one exact short-term revision passed admission."""

    receipt_version: Literal["canonical_memory_promotion_admission.v1"] = PROMOTION_ADMISSION_VERSION
    receipt_id: str = ""
    planner_id: Literal["canonical_batched_promotion"] = PROMOTION_PLANNER_ID
    planner_version: Literal["v2"] = PROMOTION_PLANNER_VERSION
    decision: Literal["durable"] = "durable"
    memory_id: str
    source_item_revision: int
    output_content_hash: str
    evidence_ids: List[str]
    supersedes: List[str]

    @field_validator("memory_id", "output_content_hash")
    @classmethod
    def validate_nonblank(cls, value: str) -> str:
        stripped = (value or "").strip()
        if not stripped:
            raise ValueError("promotion admission fields must not be blank")
        return stripped

    @field_validator("source_item_revision")
    @classmethod
    def validate_revision(cls, value: int) -> int:
        if value < 1:
            raise ValueError("source_item_revision must be positive")
        return value

    @field_validator("evidence_ids")
    @classmethod
    def validate_evidence(cls, value: List[str]) -> List[str]:
        normalized = sorted({item.strip() for item in value if item and item.strip()})
        if not normalized:
            raise ValueError("promotion admission requires evidence")
        return normalized

    @field_validator("supersedes")
    @classmethod
    def normalize_supersedes(cls, value: List[str]) -> List[str]:
        return sorted({item.strip() for item in value if item and item.strip()})

    def identity_payload(self):
        return {
            "receipt_version": self.receipt_version,
            "planner_id": self.planner_id,
            "planner_version": self.planner_version,
            "decision": self.decision,
            "memory_id": self.memory_id,
            "source_item_revision": self.source_item_revision,
            "output_content_hash": self.output_content_hash,
            "evidence_ids": self.evidence_ids,
            "supersedes": self.supersedes,
        }

    @model_validator(mode="after")
    def derive_or_validate_id(self):
        expected = "padm_" + deterministic_contract_id("canonical-promotion-admission", self.identity_payload())[:32]
        if self.receipt_id and self.receipt_id != expected:
            raise ValueError("promotion admission receipt id mismatch")
        self.receipt_id = expected
        return self


def build_promotion_admission_receipt(
    *,
    memory_id: str,
    source_item_revision: int,
    output_content_hash: str,
    evidence_ids: List[str],
    supersedes: List[str],
) -> PromotionAdmissionReceipt:
    return PromotionAdmissionReceipt(
        memory_id=memory_id,
        source_item_revision=source_item_revision,
        output_content_hash=output_content_hash,
        evidence_ids=evidence_ids,
        supersedes=supersedes,
    )


def valid_promotion_admission(
    *,
    memory_id: str,
    source_item_revision: int,
    output_content_hash: str,
    evidence_ids: List[str],
    supersedes: List[str],
    promotion: dict,
) -> bool:
    """Validate the complete server-authored admission proof for a short-term item."""
    try:
        receipt = PromotionAdmissionReceipt(**promotion["admission_receipt"])
    except (KeyError, TypeError, ValueError):
        return False
    return (
        receipt.memory_id == memory_id
        and receipt.source_item_revision == source_item_revision
        and receipt.output_content_hash == output_content_hash
        and receipt.evidence_ids == sorted(set(evidence_ids))
        and receipt.supersedes == sorted(set(supersedes))
        and memory_id not in receipt.supersedes
    )


__all__ = [
    "PROMOTION_ADMISSION_VERSION",
    "PROMOTION_PLANNER_ID",
    "PROMOTION_PLANNER_VERSION",
    "PromotionAdmissionReceipt",
    "build_promotion_admission_receipt",
    "valid_promotion_admission",
]
