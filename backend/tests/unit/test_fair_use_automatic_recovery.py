from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import database.fair_use as fair_use_db
import utils.fair_use as fair_use


def normalized_state(monkeypatch, state, *, now):
    client = MagicMock()
    transaction = MagicMock()
    client.transaction.return_value = transaction
    reference = client.collection.return_value.document.return_value.collection.return_value.document.return_value
    reference.get.return_value.exists = True
    reference.get.return_value.to_dict.return_value = dict(state)
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    return fair_use_db.get_fair_use_state('owner-a', firestore_client=client, now=now), transaction, reference


def test_expired_automatic_restrict_enters_final_warning_with_fresh_seven_day_timer(monkeypatch):
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    state, transaction, reference = normalized_state(
        monkeypatch,
        {'stage': 'restrict', 'restrict_until': now - timedelta(seconds=1)},
        now=now,
    )

    assert state['stage'] == 'throttle'
    assert state['restrict_until'] is None
    assert state['throttle_until'] == now + timedelta(days=7)
    transaction.set.assert_called_once_with(
        reference,
        {
            'stage': 'throttle',
            'restrict_until': None,
            'throttle_until': now + timedelta(days=7),
            'updated_at': now,
        },
        merge=True,
    )


def test_expired_automatic_final_warning_returns_to_warning_at_exact_boundary(monkeypatch):
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    state, transaction, reference = normalized_state(
        monkeypatch,
        {'stage': 'throttle', 'throttle_until': now},
        now=now,
    )

    assert state['stage'] == 'warning'
    assert state['throttle_until'] is None
    transaction.set.assert_called_once_with(
        reference,
        {'stage': 'warning', 'throttle_until': None, 'updated_at': now},
        merge=True,
    )


def test_timerless_manual_throttle_and_restrict_never_auto_expire(monkeypatch):
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    throttle, throttle_transaction, _ = normalized_state(monkeypatch, {'stage': 'throttle'}, now=now)
    restrict, restrict_transaction, _ = normalized_state(monkeypatch, {'stage': 'restrict'}, now=now)

    assert throttle == {'stage': 'throttle'}
    assert restrict == {'stage': 'restrict'}
    throttle_transaction.set.assert_not_called()
    restrict_transaction.set.assert_not_called()


def test_cached_automatic_restriction_uses_authoritatively_normalized_state(monkeypatch):
    redis = MagicMock()
    redis.get.return_value = b'restrict'
    db = MagicMock()
    db.get_fair_use_state.return_value = {
        'stage': 'throttle',
        'restrict_until': None,
        'throttle_until': datetime.now(timezone.utc) + timedelta(days=7),
    }
    monkeypatch.setattr(fair_use, 'redis_client', redis)
    monkeypatch.setattr(fair_use, 'fair_use_db', db)

    assert fair_use.get_enforcement_stage('owner-a') == 'throttle'
    db.get_fair_use_state.assert_called_once_with('owner-a')
    redis.setex.assert_called_once_with('fair_use:stage:owner-a', 60, 'throttle')


def test_stage_filtered_support_read_filters_after_authoritative_recovery(monkeypatch):
    raw_doc = MagicMock()
    raw_doc.id = 'current'
    raw_doc.reference.path = 'users/owner-a/fair_use_state/current'
    raw_doc.to_dict.return_value = {'stage': 'restrict'}
    query = MagicMock()
    query.where.return_value = query
    query.order_by.return_value = query
    query.limit.return_value = query
    query.stream.return_value = [raw_doc]
    firestore = MagicMock()
    firestore.collection_group.return_value = query
    monkeypatch.setattr(
        fair_use_db,
        'get_fair_use_state',
        lambda uid, **_: {
            'stage': 'throttle',
            'restrict_until': None,
            'throttle_until': datetime(2026, 8, 28, 8, tzinfo=timezone.utc),
        },
    )

    results = fair_use_db.get_flagged_users(stage_filter='throttle', firestore_client=firestore)

    query.where.assert_called_once()
    active_stage_filter = query.where.call_args.kwargs['filter']
    assert active_stage_filter.field_path == 'stage'
    assert active_stage_filter.op_string == 'in'
    assert active_stage_filter.value == ['warning', 'throttle', 'restrict']
    assert results == [
        {
            'stage': 'throttle',
            'restrict_until': None,
            'throttle_until': datetime(2026, 8, 28, 8, tzinfo=timezone.utc),
            'uid': 'owner-a',
            'id': 'current',
        }
    ]


def test_stage_filtered_support_read_pages_past_two_hundred_normalized_nonmatches(monkeypatch):
    def document(uid):
        doc = MagicMock()
        doc.id = 'current'
        doc.reference.path = f'users/{uid}/fair_use_state/current'
        doc.to_dict.return_value = {'stage': 'restrict'}
        return doc

    first_page = [document(f'nonmatch-{index}') for index in range(200)]
    matching = document('matching-owner')
    query = MagicMock()
    query.where.return_value = query
    query.order_by.return_value = query
    query.limit.return_value = query
    query.start_after.return_value = query
    query.stream.side_effect = [first_page, [matching]]
    firestore = MagicMock()
    firestore.collection_group.return_value = query
    monkeypatch.setattr(
        fair_use_db,
        'get_fair_use_state',
        lambda uid, **_: {'stage': 'restrict' if uid == 'matching-owner' else 'warning'},
    )

    results = fair_use_db.get_flagged_users(stage_filter='restrict', limit=1, firestore_client=firestore)

    assert results == [{'stage': 'restrict', 'uid': 'matching-owner', 'id': 'current'}]
    query.start_after.assert_called_once_with(first_page[-1])
