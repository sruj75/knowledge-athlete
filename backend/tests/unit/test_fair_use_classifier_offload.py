"""Structural test: the Free synthetic trigger performs no notification-only event read."""

import ast
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[2]
FAIR_USE = BACKEND_DIR / 'utils' / 'fair_use.py'
TARGET_FN = 'trigger_free_exhaustion_if_needed'
BLOCKING_CALL = 'get_fair_use_events'


def _load_function(name):
    tree = ast.parse(FAIR_USE.read_text(encoding='utf-8'))
    for node in ast.walk(tree):
        if isinstance(node, (ast.AsyncFunctionDef, ast.FunctionDef)) and node.name == name:
            return node
    raise AssertionError(f'{name} not found in {FAIR_USE}')


def _ref_name(node):
    """Name for an ast.Name (.id) or ast.Attribute (.attr); None otherwise."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


def _direct_calls(fn_node, callee):
    return [n for n in ast.walk(fn_node) if isinstance(n, ast.Call) and _ref_name(n.func) == callee]


def test_events_read_is_not_called_directly():
    fn = _load_function(TARGET_FN)
    assert _direct_calls(fn, BLOCKING_CALL) == [], f'{BLOCKING_CALL} must not run in {TARGET_FN}'
