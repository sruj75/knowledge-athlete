#!/usr/bin/env python3
"""Behavioral contract for the shared Dev backend deployment policy."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPT = Path(__file__).with_name("backend_auto_deploy_policy.py")
SPEC = importlib.util.spec_from_file_location("backend_auto_deploy_policy", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class BackendAutoDeployPolicyTests(unittest.TestCase):
    def test_manual_only_keeps_backend_changes_eligible_but_requires_deliberate_dispatch(self) -> None:
        decision = MODULE.decide("manual-only", backend_changed=True)

        self.assertIs(decision.applies, False)
        self.assertEqual(decision.reason, "manual-required")

    def test_active_mode_preserves_existing_automatic_scope_behavior(self) -> None:
        self.assertIs(MODULE.decide("active", backend_changed=True).applies, True)
        self.assertEqual(MODULE.decide("active", backend_changed=False).reason, "unrelated")

    def test_unknown_mode_fails_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown automatic backend deployment mode"):
            MODULE.decide("typo", backend_changed=True)


if __name__ == "__main__":
    unittest.main()
