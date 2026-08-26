from __future__ import annotations

from datetime import datetime, timezone

from scripts.artifact_cleanup_policy import normalize_gcloud_inventory, select_cleanup_candidates


NOW = datetime(2026, 8, 26, tzinfo=timezone.utc)


def test_cleanup_selects_only_old_untagged_unprotected_artifact_versions():
    versions = [
        {'name': 'old-untagged', 'kind': 'docker-version', 'created_at': '2026-07-01T00:00:00Z', 'tags': []},
        {'name': 'recent-untagged', 'kind': 'docker-version', 'created_at': '2026-08-20T00:00:00Z', 'tags': []},
        {'name': 'release', 'kind': 'docker-version', 'created_at': '2026-01-01T00:00:00Z', 'tags': ['a' * 40]},
        {'name': 'cache', 'kind': 'docker-version', 'created_at': '2026-01-01T00:00:00Z', 'tags': ['buildcache']},
        {'name': 'rollback', 'kind': 'docker-version', 'created_at': '2026-01-01T00:00:00Z', 'tags': []},
        {'name': 'backend-old', 'kind': 'cloud-run-revision', 'created_at': '2025-01-01T00:00:00Z', 'tags': []},
    ]

    assert select_cleanup_candidates(versions, now=NOW, protected_names={'rollback'}) == ['old-untagged']


def test_cleanup_boundary_is_strictly_older_than_thirty_days():
    versions = [
        {'name': 'boundary', 'kind': 'docker-version', 'created_at': '2026-07-27T00:00:00Z', 'tags': []},
    ]

    assert select_cleanup_candidates(versions, now=NOW, protected_names=set()) == []


def test_gcloud_inventory_normalizes_digest_identity_for_revision_protection():
    values = normalize_gcloud_inventory(
        [
            {
                'package': 'us-west1-docker.pkg.dev/project/backend/backend',
                'version': 'sha256:abc',
                'createTime': '2026-07-01T00:00:00Z',
                'tags': [],
            }
        ]
    )

    assert values == [
        {
            'name': 'us-west1-docker.pkg.dev/project/backend/backend@sha256:abc',
            'kind': 'docker-version',
            'created_at': '2026-07-01T00:00:00Z',
            'tags': [],
        }
    ]
    assert (
        select_cleanup_candidates(
            values,
            now=NOW,
            protected_names={'us-west1-docker.pkg.dev/project/backend/backend@sha256:abc'},
        )
        == []
    )
