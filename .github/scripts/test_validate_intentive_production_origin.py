#!/usr/bin/env python3
"""Behavioral tests for the release API credential boundary."""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

SCRIPT = Path(__file__).with_name("validate-intentive-production-origin.py")
SPEC = importlib.util.spec_from_file_location("validate_intentive_production_origin", SCRIPT)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def test_accepts_only_the_exact_separately_approved_origin():
    VALIDATOR.validate("https://api.heyintentive.com", "https://api.heyintentive.com")

    with pytest.raises(ValueError, match="does not match"):
        VALIDATOR.validate("https://other.heyintentive.com", "https://api.heyintentive.com")


@pytest.mark.parametrize(
    "candidate",
    [
        "",
        "http://api.heyintentive.com",
        "https://api.heyintentive.com/path",
        "https://user@api.heyintentive.com",
        "https://api.omi.me",
        "https://api.omiapi.com",
        "https://api.basedhardware.com",
    ],
)
def test_rejects_missing_malformed_or_inherited_candidates(candidate):
    with pytest.raises(ValueError):
        VALIDATOR.validate(candidate, "https://api.heyintentive.com")


def test_missing_approval_keeps_release_operations_blocked():
    with pytest.raises(ValueError, match="approved"):
        VALIDATOR.validate("https://api.heyintentive.com", "")
