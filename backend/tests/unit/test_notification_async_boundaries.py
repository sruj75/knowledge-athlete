import asyncio
import inspect
import threading
from contextlib import contextmanager
from pathlib import Path
from types import ModuleType, SimpleNamespace
from typing import Any, Iterator

from testing.import_isolation import load_module_fresh, stub_modules

BACKEND_DIR = Path(__file__).resolve().parents[2]


class _MessagingError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _module(name: str, **attributes: Any) -> ModuleType:
    module = ModuleType(name)
    for key, value in attributes.items():
        setattr(module, key, value)
    return module


def _messaging_module() -> ModuleType:
    class Notification:
        def __init__(self, title: str, body: str):
            self.title = title
            self.body = body

    def constructor(**kwargs: Any) -> SimpleNamespace:
        return SimpleNamespace(**kwargs)

    return _module(
        'firebase_admin.messaging',
        Notification=Notification,
        AndroidConfig=constructor,
        AndroidNotification=constructor,
        APNSConfig=constructor,
        APNSPayload=constructor,
        Aps=constructor,
        WebpushConfig=constructor,
        WebpushNotification=constructor,
        WebpushFCMOptions=constructor,
        Message=constructor,
        send_each=lambda _messages: SimpleNamespace(responses=[]),
    )


@contextmanager
def _loaded_notifications() -> Iterator[tuple[ModuleType, ModuleType, ModuleType, dict[str, list[str]]]]:
    messaging = _messaging_module()
    auth = _module(
        'firebase_admin.auth',
        get_user=lambda _uid: SimpleNamespace(display_name='Ada', email='ada@example.com'),
    )
    firebase_admin = _module('firebase_admin', messaging=messaging, auth=auth)
    notification_db = _module(
        'database.notifications',
        get_all_tokens=lambda _uid: ['device-token'],
        remove_bulk_tokens=lambda _tokens: None,
    )
    cache_writes: dict[str, list[str]] = {'silent': []}
    redis_db = _module(
        'database.redis_db',
        has_silent_user_notification_been_sent=lambda _uid: False,
        set_silent_user_notification_sent=lambda uid: cache_writes['silent'].append(uid),
    )
    database_auth = _module('database.auth', get_user_from_uid=lambda _uid: None)

    stubs = {
        'firebase_admin': firebase_admin,
        'firebase_admin.messaging': messaging,
        'firebase_admin.auth': auth,
        'database.notifications': notification_db,
        'database.redis_db': redis_db,
        'database.auth': database_auth,
    }

    with stub_modules(stubs):
        notifications = load_module_fresh(
            'utils.notifications',
            str(BACKEND_DIR / 'utils' / 'notifications.py'),
        )
        yield notifications, notification_db, messaging, cache_writes


async def _assert_loop_responsive_while_worker_waits(
    awaitable: Any,
    entered: asyncio.Event,
    release: threading.Event,
) -> Any:
    task = asyncio.create_task(awaitable)
    try:
        await asyncio.wait_for(entered.wait(), timeout=2)
        loop_tick = asyncio.Event()
        asyncio.get_running_loop().call_soon(loop_tick.set)
        await asyncio.wait_for(loop_tick.wait(), timeout=1)
        assert not task.done()
    finally:
        release.set()
    return await asyncio.wait_for(task, timeout=2)


def _success_response() -> SimpleNamespace:
    return SimpleNamespace(responses=[SimpleNamespace(success=True, exception=None)])


def test_generic_notification_offloads_token_read_and_preserves_sync_api() -> None:
    with _loaded_notifications() as (notifications, notification_db, messaging, _cache_writes):
        assert not inspect.iscoroutinefunction(notifications.send_notification)
        assert inspect.iscoroutinefunction(notifications.send_notification_async)

        async def exercise() -> None:
            entered = asyncio.Event()
            release = threading.Event()
            loop = asyncio.get_running_loop()

            def blocking_token_read(_uid: str) -> list[str]:
                loop.call_soon_threadsafe(entered.set)
                assert release.wait(timeout=2)
                return ['device-token']

            notification_db.get_all_tokens = blocking_token_read
            messaging.send_each = lambda _messages: _success_response()

            await _assert_loop_responsive_while_worker_waits(
                notifications.send_notification_async('user-1', 'omi', 'hello', {'source': 'test'}),
                entered,
                release,
            )

        asyncio.run(exercise())


def test_silent_notification_offloads_invalid_token_removal_and_preserves_fail_soft_send() -> None:
    with _loaded_notifications() as (notifications, notification_db, messaging, cache_writes):

        async def exercise() -> None:
            entered = asyncio.Event()
            release = threading.Event()
            loop = asyncio.get_running_loop()
            removed: list[list[str]] = []

            messaging.send_each = lambda _messages: SimpleNamespace(
                responses=[SimpleNamespace(success=False, exception=_MessagingError('UNREGISTERED'))]
            )

            def blocking_remove(tokens: list[str]) -> None:
                removed.append(tokens)
                loop.call_soon_threadsafe(entered.set)
                assert release.wait(timeout=2)

            notification_db.remove_bulk_tokens = blocking_remove

            await _assert_loop_responsive_while_worker_waits(
                notifications.send_silent_user_notification('user-3'),
                entered,
                release,
            )
            assert removed == [['device-token']]

        asyncio.run(exercise())
        assert cache_writes['silent'] == ['user-3']
