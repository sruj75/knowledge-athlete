import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[2] / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from readiness_gate_common import (
    GATE_STATUS_BLOCKED,
    GATE_STATUS_GO,
    GATE_STATUS_NOT_RUN,
    collect_gates_from_artifact,
    evaluate_gates,
    exit_code_for_status,
)


def test_evaluate_gates_all_go():
    gates = {
        "gate_a": {"status": GATE_STATUS_GO},
        "gate_b": {"status": GATE_STATUS_GO},
    }
    status, blockers = evaluate_gates(gates)
    assert status == GATE_STATUS_GO
    assert blockers == []


def test_evaluate_gates_blocked_over_not_run():
    gates = {
        "blocked_gate": {"status": GATE_STATUS_BLOCKED},
        "not_run_gate": {"status": GATE_STATUS_NOT_RUN},
    }
    status, blockers = evaluate_gates(gates)
    assert status == GATE_STATUS_BLOCKED
    assert blockers == ["blocked_gate:BLOCKED", "not_run_gate:NOT_RUN"]


def test_evaluate_gates_empty_is_not_run():
    status, blockers = evaluate_gates({})
    assert status == GATE_STATUS_NOT_RUN
    assert blockers == ["no_gates_defined"]


def test_exit_code_for_status_inventory_mode_always_zero():
    assert exit_code_for_status(GATE_STATUS_GO, require_go=False) == 0
    assert exit_code_for_status(GATE_STATUS_BLOCKED, require_go=False) == 0
    assert exit_code_for_status(GATE_STATUS_NOT_RUN, require_go=False) == 0


def test_exit_code_for_status_require_go_only_passes_on_go():
    assert exit_code_for_status(GATE_STATUS_GO, require_go=True) == 0
    assert exit_code_for_status(GATE_STATUS_BLOCKED, require_go=True) == 1
    assert exit_code_for_status(GATE_STATUS_NOT_RUN, require_go=True) == 1
    assert exit_code_for_status("READY_TO_EXECUTE_DEV_CLOUD_PROOF", require_go=True) == 1


def test_collect_gates_from_artifact_includes_proof_cases():
    artifact = {
        "status": GATE_STATUS_NOT_RUN,
        "proof_cases": {
            "case_a": {"status": GATE_STATUS_NOT_RUN},
            "case_b": {"status": GATE_STATUS_BLOCKED},
        },
    }
    gates = collect_gates_from_artifact(artifact)
    assert gates["overall"]["status"] == GATE_STATUS_NOT_RUN
    assert gates["proof_case:case_b"]["status"] == GATE_STATUS_BLOCKED
