"""Tests that retained auth token exchanges do not block async handlers."""

import ast
import os

import pytest


def _get_async_functions_with_requests(filepath: str) -> list:
    """Parse a Python file and find async functions using requests.*."""
    with open(filepath, encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source)

    violations = []

    class Visitor(ast.NodeVisitor):
        def __init__(self):
            self._in_async = False

        def visit_AsyncFunctionDef(self, node):
            old = self._in_async
            self._in_async = True
            self.generic_visit(node)
            self._in_async = old

        def visit_FunctionDef(self, node):
            old = self._in_async
            self._in_async = False
            self.generic_visit(node)
            self._in_async = old

        def visit_Call(self, node):
            if self._in_async and isinstance(node.func, ast.Attribute):
                if isinstance(node.func.value, ast.Name) and node.func.value.id == 'requests':
                    violations.append((node.lineno, f'requests.{node.func.attr}'))
            self.generic_visit(node)

    Visitor().visit(tree)
    return violations


BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestAuthNoBlockingRequests:
    """Verify auth.py has no blocking requests in async functions."""

    def test_auth_no_blocking_requests(self):
        filepath = os.path.join(BACKEND_DIR, 'routers', 'auth.py')
        violations = _get_async_functions_with_requests(filepath)
        assert violations == [], f"Blocking requests calls in async auth.py: {violations}"
