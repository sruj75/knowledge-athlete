from types import SimpleNamespace
from unittest.mock import MagicMock

from database import auth as auth_db


class _FailOnFirestoreAccess:
    def __getattr__(self, name):
        raise AssertionError(f'Firestore must not participate in Firebase name resolution: {name}')


def test_user_name_uses_firebase_display_name_without_firestore(monkeypatch):
    firebase_user = SimpleNamespace(
        uid='user-123',
        email='user@example.com',
        email_verified=True,
        phone_number=None,
        display_name='Firebase Person',
        photo_url=None,
        disabled=False,
    )
    cache = MagicMock()
    monkeypatch.setattr(auth_db, '_firebase_get_user', lambda uid: firebase_user)
    monkeypatch.setattr(auth_db, 'cache_user_name', cache)
    monkeypatch.setattr(auth_db, 'db', _FailOnFirestoreAccess(), raising=False)
    monkeypatch.setattr(
        auth_db,
        '_get_firestore_user_name',
        MagicMock(side_effect=AssertionError('Firestore fallback called')),
        raising=False,
    )

    assert auth_db.get_user_name('user-123', use_default=False) == 'Firebase'
    cache.assert_called_once_with('user-123', 'Firebase', ttl=60 * 60)


def test_missing_firebase_name_does_not_read_firestore(monkeypatch):
    firebase_user = SimpleNamespace(
        uid='user-123',
        email='user@example.com',
        email_verified=True,
        phone_number=None,
        display_name=None,
        photo_url=None,
        disabled=False,
    )
    monkeypatch.setattr(auth_db, '_firebase_get_user', lambda uid: firebase_user)
    monkeypatch.setattr(auth_db, 'db', _FailOnFirestoreAccess(), raising=False)
    monkeypatch.setattr(
        auth_db,
        '_get_firestore_user_name',
        MagicMock(side_effect=AssertionError('Firestore fallback called')),
        raising=False,
    )

    assert auth_db.get_user_name('user-123', use_default=False) is None
    assert auth_db.get_user_name('user-123') == 'The User'
