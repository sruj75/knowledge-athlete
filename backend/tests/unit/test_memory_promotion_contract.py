"""Validation for server-authored long-term promotion admission receipts."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from models.memory_promotion import (
    PromotionAdmissionReceipt,
    build_promotion_admission_receipt,
    valid_promotion_admission,
)


def _receipt(**overrides):
    values = {
        "memory_id": "memory-1",
        "source_item_revision": 1,
        "output_content_hash": "content-hash",
        "evidence_ids": ["evidence-1"],
        "supersedes": [],
    }
    values.update(overrides)
    return build_promotion_admission_receipt(**values)


def test_promotion_admission_receipt_normalizes_identity_inputs_and_is_stable():
    first = _receipt(evidence_ids=[" evidence-2 ", "evidence-1", "evidence-1"], supersedes=["old-2", "old-1"])
    second = _receipt(evidence_ids=["evidence-1", "evidence-2"], supersedes=["old-1", "old-2"])

    assert first.evidence_ids == ["evidence-1", "evidence-2"]
    assert first.supersedes == ["old-1", "old-2"]
    assert first.receipt_id == second.receipt_id


@pytest.mark.parametrize(
    "overrides",
    [
        {"memory_id": ""},
        {"output_content_hash": " "},
        {"source_item_revision": 0},
        {"evidence_ids": []},
    ],
)
def test_promotion_admission_receipt_rejects_incomplete_identity(overrides):
    with pytest.raises(ValidationError):
        _receipt(**overrides)


def test_promotion_admission_rejects_tampered_receipt_id():
    payload = _receipt().model_dump(mode="json")
    payload["receipt_id"] = "padm_tampered"

    with pytest.raises(ValidationError, match="receipt id mismatch"):
        PromotionAdmissionReceipt(**payload)


def test_valid_promotion_admission_requires_exact_current_inputs():
    receipt = _receipt()
    promotion = {"admission_receipt": receipt.model_dump(mode="json")}

    assert valid_promotion_admission(
        memory_id="memory-1",
        source_item_revision=1,
        output_content_hash="content-hash",
        evidence_ids=["evidence-1"],
        supersedes=[],
        promotion=promotion,
    )
    assert not valid_promotion_admission(
        memory_id="memory-1",
        source_item_revision=2,
        output_content_hash="content-hash",
        evidence_ids=["evidence-1"],
        supersedes=[],
        promotion=promotion,
    )
