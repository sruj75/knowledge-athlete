from unittest.mock import MagicMock, call

from database import users as users_db


def test_account_deletion_removes_content_free_fair_use_history_even_without_root_document(monkeypatch):
    fake_db = MagicMock()
    user_ref = fake_db.collection.return_value.document.return_value
    user_ref.get.return_value.exists = False
    events = MagicMock(id='fair_use_events')
    processing = MagicMock(id='fair_use_review_processing')
    receipts = MagicMock(id='fair_use_review_receipts')
    state = MagicMock(id='fair_use_state')
    user_ref.collections.return_value = [events, processing, receipts, state]
    delete_recursive = MagicMock()
    monkeypatch.setattr(users_db, 'db', fake_db)
    monkeypatch.setattr(users_db, 'delete_collection_recursive', delete_recursive)

    result = users_db.delete_user_data('owner-a')

    assert result == {'status': 'ok', 'message': 'Account deleted successfully'}
    assert delete_recursive.call_args_list == [
        call(events, client=fake_db),
        call(processing, client=fake_db),
        call(receipts, client=fake_db),
        call(state, client=fake_db),
    ]
    user_ref.delete.assert_not_called()
