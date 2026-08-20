import ast
import json
from pathlib import Path, PurePosixPath, PureWindowsPath

import pytest
from google.cloud.firestore_v1 import FieldFilter

from database.firestore_index_registry import (
    STALE_IN_PROGRESS_CONVERSATIONS_QUERY,
    STARRED_CHAT_SESSIONS_QUERY,
    firebase_index_manifest,
)
from scripts import firestore_query_coverage, generate_firestore_indexes


class _RecordingQuery:
    def __init__(self):
        self.filters = []

    def where(self, *, filter):
        self.filters.append((filter.field_path, filter.op_string, filter.value))
        return self


def test_registered_starred_chat_query_builds_the_real_filter_chain():
    query = _RecordingQuery()

    built = STARRED_CHAT_SESSIONS_QUERY.build(query, {'starred': True}, field_filter_factory=FieldFilter)

    assert built is query
    assert query.filters == [('starred', '==', True)]


def test_generated_firestore_manifest_matches_the_checked_in_contract():
    manifest_path = Path(__file__).resolve().parents[3] / 'firestore.indexes.json'

    assert manifest_path.read_text(encoding='utf-8') == generate_firestore_indexes.render_manifest()
    assert {
        'collectionGroup': 'conversations',
        'queryScope': 'COLLECTION',
        'fields': [
            {'fieldPath': 'status', 'order': 'ASCENDING'},
            {'fieldPath': 'finished_at', 'order': 'ASCENDING'},
            {'fieldPath': '__name__', 'order': 'ASCENDING'},
        ],
    } in firebase_index_manifest()['indexes']


@pytest.mark.slow
def test_query_inventory_registers_the_migrated_query_shapes():
    report = firestore_query_coverage.report_for(firestore_query_coverage.inventory(waiver_ids=set()))

    for spec in (
        STALE_IN_PROGRESS_CONVERSATIONS_QUERY,
        STARRED_CHAT_SESSIONS_QUERY,
    ):
        matching = [query for query in report['queries'] if query['registered_spec'] == spec.identifier]
        assert len(matching) == 1
        assert matching[0]['classification'] == 'registered'
        assert matching[0]['collection_group'] == spec.collection_group
    assert report['counts']['serving']['registered'] >= 2


def test_inventory_finds_a_direct_compound_chain_wrapped_by_list():
    tree = ast.parse(
        "def read(client):\n"
        "    return list(client.collection('items').where('status', '==', 'open').where('expires_at', '>', 0).stream())\n"
    )
    function = tree.body[0]
    analyzer = firestore_query_coverage.FunctionQueryAnalyzer(
        source='backend/database/example.py',
        symbol='read',
        constants={},
        non_serving_scope=None,
        registered_signatures={},
        waiver_ids=set(),
    )

    shapes = analyzer.analyze(function.body)

    assert len(shapes) == 1
    assert shapes[0].classification == 'raw_unregistered'
    assert [(field.field_path, field.operator) for field in shapes[0].components] == [
        ('status', '=='),
        ('expires_at', '>'),
    ]


def test_query_coverage_ratchet_rejects_a_new_raw_serving_shape():
    baseline = {
        'schema_version': 1,
        'eligible_serving': 1,
        'registered_serving': 1,
        'raw_unregistered': [],
        'unsupported': [],
    }
    report = {
        'counts': {
            'serving': {
                'eligible': 2,
                'registered': 1,
                'raw_unregistered': 1,
                'waived': 0,
                'unsupported': 0,
            }
        },
        'queries': [
            {'id': 'registered', 'classification': 'registered'},
            {'id': 'new-raw', 'classification': 'raw_unregistered'},
        ],
    }

    assert firestore_query_coverage.check_ratchet(report, baseline) == [
        'new unregistered serving compound query shape(s): new-raw',
        'registered serving-query coverage percentage decreased',
    ]


@pytest.mark.slow
def test_query_coverage_baseline_tracks_current_raw_and_unsupported_debt():
    baseline_path = Path(__file__).resolve().parents[2] / 'scripts' / 'firestore_query_coverage_baseline.json'
    committed = json.loads(baseline_path.read_text(encoding='utf-8'))
    report = firestore_query_coverage.report_for(firestore_query_coverage.inventory(waiver_ids=set()))

    assert firestore_query_coverage.check_ratchet(report, committed) == []


def test_query_source_paths_are_posix_canonical_on_every_host_platform():
    windows_path = PureWindowsPath('backend\\database\\conversations.py')
    posix_path = PurePosixPath('backend/database/conversations.py')

    assert firestore_query_coverage.canonical_source_path(windows_path) == 'backend/database/conversations.py'
    assert firestore_query_coverage.canonical_source_path(
        windows_path
    ) == firestore_query_coverage.canonical_source_path(posix_path)
