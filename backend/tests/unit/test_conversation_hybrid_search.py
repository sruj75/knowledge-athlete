"""Canonical guard after S-23 retired hosted conversation search.

The historical serving-index failure cannot recur when the application has no
conversation query builder or hosted search route. Keep this canonical artifact
as a negative guard until the failure-class registry is retired separately.
"""

from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parents[2]


def test_hosted_conversation_search_query_builder_remains_absent():
    assert not (BACKEND_DIR / 'utils/conversations/search.py').exists()


def test_hosted_conversation_search_routes_remain_unmounted():
    main_source = (BACKEND_DIR / 'main.py').read_text(encoding='utf-8')

    assert 'routers.conversations' not in main_source
    assert 'conversations.router' not in main_source
