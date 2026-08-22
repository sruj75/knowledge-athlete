import asyncio
import hashlib
import math
import random
from typing import Any, Dict, List, Optional, Tuple, cast
from firebase_admin import messaging, auth
import database.notifications as notification_db
from utils.executors import db_executor, postprocess_executor, run_blocking
from database.redis_db import set_silent_user_notification_sent, has_silent_user_notification_been_sent
from utils.notification_text import to_plain_text
import logging

logger = logging.getLogger(__name__)


def _get_user(uid: str) -> Any:
    return auth.get_user(uid)  # type: ignore[reportUnknownMemberType]  # firebase_admin auth untyped


# iOS bundle ID for APNs
IOS_BUNDLE_ID = 'com.friend-app-with-wearable.ios12'

# Error codes that indicate a token is permanently invalid
PERMANENT_FAILURE_CODES = frozenset(
    [
        'UNREGISTERED',  # App uninstalled
        'INVALID_REGISTRATION_TOKEN',  # Token format invalid
        'NOT_FOUND',  # FCM/APNs token no longer maps to a valid registration
    ]
)


def _generate_tag(content: str) -> str:
    """Generate a 16-char hash tag for deduplication."""
    return hashlib.md5(content.encode()).hexdigest()[:16]


def _generate_notification_tag(user_id: str, title: str, body: str, data: Optional[Dict[str, Any]] = None) -> str:
    """Generate a tag for notification deduplication based on content."""
    content = f"{user_id}:{title}:{body}"
    if data:
        unique_id: str = str(data.get('type', ''))
        content += f":{unique_id}"
    return _generate_tag(content)


def _build_android_config(tag: str, priority: str = 'normal', is_data_only: bool = False) -> messaging.AndroidConfig:
    """Build Android configuration with deduplication."""
    config_kwargs: Dict[str, Any] = {
        'collapse_key': tag,
        'priority': priority,
    }
    # Only add notification config if not data-only (Android shows empty notification otherwise)
    if not is_data_only:
        config_kwargs['notification'] = messaging.AndroidNotification(tag=tag)
    return messaging.AndroidConfig(**config_kwargs)


def _build_apns_config(tag: str, is_background: bool = False) -> messaging.APNSConfig:
    """Build APNs configuration with deduplication."""
    headers = {'apns-collapse-id': tag}

    if is_background:
        headers.update(
            {
                'apns-push-type': 'background',
                'apns-priority': '5',
                'apns-topic': IOS_BUNDLE_ID,
            }
        )
        return messaging.APNSConfig(
            headers=headers,
            payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True)),
        )

    return messaging.APNSConfig(headers=headers)


def _build_webpush_config(
    tag: str, title: Optional[str] = None, body: Optional[str] = None, link: Optional[str] = None
) -> messaging.WebpushConfig:
    """Build WebPush configuration for browser notifications.

    Note: WebpushNotification must explicitly include title/body because
    browsers use webpush.notification instead of the top-level notification
    when the webpush block is present.

    fcm_options.link must be an absolute HTTPS URL - relative paths will cause
    FCM to reject the entire message batch with 'WebpushFCMOptions.link must be a HTTPS URL'.
    """
    config_kwargs: Dict[str, Any] = {
        'headers': {
            'Topic': tag,  # For deduplication
            'Urgency': 'high',
        },
        'notification': messaging.WebpushNotification(
            title=title,
            body=body,
            icon='/logo.png',
        ),
    }

    # Only include fcm_options if link is a valid HTTPS URL
    if link and link.startswith('https://'):
        config_kwargs['fcm_options'] = messaging.WebpushFCMOptions(link=link)

    return messaging.WebpushConfig(**config_kwargs)


def _build_message(
    token: str,
    tag: str,
    notification: Optional[messaging.Notification] = None,
    data: Optional[Dict[str, Any]] = None,
    is_background: bool = False,
    priority: str = 'normal',
) -> messaging.Message:
    """Build a complete FCM message with proper platform configs."""
    # Extract title/body for webpush config (browsers need explicit values)
    title: Optional[str] = cast(Any, notification).title if notification else None
    body: Optional[str] = cast(Any, notification).body if notification else None
    # Extract navigate_to for webpush click-through link
    link: Optional[str] = data.get('navigate_to') if data else None

    return messaging.Message(
        token=token,
        notification=notification,
        data=data,
        android=_build_android_config(tag, priority, is_data_only=(notification is None)),
        apns=_build_apns_config(tag, is_background),
        webpush=_build_webpush_config(tag, title, body, link),
    )


def _send_messages(messages: List[messaging.Message]) -> Any:
    """Send one FCM batch through the synchronous Firebase Admin SDK."""
    return cast(Any, messaging.send_each(messages))  # type: ignore[reportUnknownMemberType]


def _collect_send_results(response: Any, tokens: List[str]) -> Tuple[int, List[str]]:
    """Return the successful-send count and permanently invalid tokens."""
    invalid_tokens: List[str] = []
    success_count = 0

    for idx, result in enumerate(response.responses):
        if result.success:
            success_count += 1
        elif result.exception:
            error_code = getattr(result.exception, 'code', None)
            if error_code in PERMANENT_FAILURE_CODES:
                invalid_tokens.append(tokens[idx])
                logger.error(f'Invalid token removed - Error: {error_code}')
            else:
                logger.error(f'FCM send failed: {result.exception}({error_code})')

    return success_count, invalid_tokens


def _send_to_user(
    user_id: str,
    tag: str,
    notification: Optional[messaging.Notification] = None,
    data: Optional[Dict[str, Any]] = None,
    is_background: bool = False,
    priority: str = 'normal',
    tokens: Optional[List[str]] = None,
) -> int | None:
    """Return successes, or ``None`` when the user has no registered device."""
    if tokens is None:
        tokens = notification_db.get_all_tokens(user_id)
    if not tokens:
        logger.info(f"No tokens found for user {user_id}")
        return None

    # Build messages for all tokens
    messages = [_build_message(token, tag, notification, data, is_background, priority) for token in tokens]

    try:
        response = _send_messages(messages)
        success_count, invalid_tokens = _collect_send_results(response, tokens)

        # Remove invalid tokens in bulk
        if invalid_tokens:
            notification_db.remove_bulk_tokens(invalid_tokens)

        logger.info(f'FCM batch send: {success_count}/{len(tokens)} successful')
        return success_count

    except Exception as e:
        logger.error(f'FCM batch send error: {e}')
        return 0


async def _send_to_user_async(
    user_id: str,
    tag: str,
    notification: Optional[messaging.Notification] = None,
    data: Optional[Dict[str, Any]] = None,
    is_background: bool = False,
    priority: str = 'normal',
    tokens: Optional[List[str]] = None,
) -> int:
    """Async boundary for the synchronous token store and Firebase Admin SDK."""
    if tokens is None:
        tokens = await run_blocking(db_executor, notification_db.get_all_tokens, user_id)
    if not tokens:
        logger.info(f"No tokens found for user {user_id}")
        return 0

    messages = [_build_message(token, tag, notification, data, is_background, priority) for token in tokens]

    try:
        response = await run_blocking(postprocess_executor, _send_messages, messages)
        success_count, invalid_tokens = _collect_send_results(response, tokens)

        if invalid_tokens:
            await run_blocking(db_executor, notification_db.remove_bulk_tokens, invalid_tokens)

        logger.info(f'FCM batch send: {success_count}/{len(tokens)} successful')
        return success_count
    except Exception as e:
        logger.error(f'FCM batch send error: {e}')
        return 0


def send_notification(
    user_id: str, title: str, body: str, data: Optional[Dict[str, Any]] = None, tokens: Optional[List[str]] = None
) -> int | None:
    """Send notification to all user's devices. Optionally pass pre-fetched tokens to avoid DB lookup."""
    logger.info(f'send_notification to user {user_id}')
    body = to_plain_text(body)
    tag = _generate_notification_tag(user_id, title, body, data)
    notification = messaging.Notification(title=title, body=body)
    return _send_to_user(user_id, tag, notification=notification, data=data, tokens=tokens)


async def send_notification_async(
    user_id: str, title: str, body: str, data: Optional[Dict[str, Any]] = None, tokens: Optional[List[str]] = None
) -> None:
    """Async counterpart used by event-loop callers while preserving the sync public API."""
    logger.info(f'send_notification to user {user_id}')
    body = to_plain_text(body)
    tag = _generate_notification_tag(user_id, title, body, data)
    notification = messaging.Notification(title=title, body=body)
    await _send_to_user_async(user_id, tag, notification=notification, data=data, tokens=tokens)


async def send_silent_user_notification(user_id: str) -> None:
    """Send a notification if a basic-plan user is silent for too long."""
    # Check if notification was sent recently (within 24 hours). Offloaded: the Redis read is sync
    # and blocks the event loop in this async path.
    if await run_blocking(db_executor, has_silent_user_notification_been_sent, user_id):
        logger.info(f"Silent user notification already sent recently for user {user_id}")
        return

    name: str = "there"
    try:
        user = await run_blocking(postprocess_executor, _get_user, user_id)
        name = user.display_name
        if not name and user.email:
            name = user.email.split('@')[0].capitalize()
        if not name:
            name = "there"
    except Exception as e:
        logger.error(f"Error getting user info from Firebase Auth: {e}")
        name = "there"

    messages = [
        f"Hey {name}, just checking in! My ears are open if you've got something to say.",
        f"Is this thing on? Tapping my mic here, {name}. Let me know when you're ready to chat!",
        f"Quiet on the set! {name}, are we rolling? Just waiting for your cue.",
        f"The sound of silence... is nice, but I'm here for the words, {name}! What's on your mind?",
        f"{name}, you've gone quiet! Just a heads up, I'm still here listening and using up your free minutes.",
        f"Psst, {name}... My virtual ears are getting a little lonely. Anything to share?",
        f"Enjoying the quiet time, {name}? Just remember, I'm on the clock, ready to transcribe!",
        f"Hello from the other side... of silence! {name}, ready to talk again?",
        f"I'm all ears, {name}! Just letting you know the recording is still live.",
        f"Silence is golden, but words are what I live for, {name}! Let's chat when you're ready.",
    ]
    title, body = "omi", random.choice(messages)

    # Send notification
    await send_notification_async(user_id, title, body)

    # Cache that notification was sent (24 hours TTL). Offloaded: the Redis write is sync and blocks
    # the event loop in this async path.
    await run_blocking(db_executor, set_silent_user_notification_sent, user_id)
    logger.info(f"Silent user notification sent to user {user_id}")


def send_training_data_submitted_notification(user_id: str) -> None:
    """Send a notification when user submits their training data opt-in request."""
    # Get user name from Firebase Auth
    name: str = "there"
    try:
        user = _get_user(user_id)
        name = user.display_name
        if not name and user.email:
            name = user.email.split('@')[0].capitalize()
        if not name:
            name = "there"
    except Exception as e:
        logger.error(f"Error getting user info from Firebase Auth: {e}")
        name = "there"

    title = "omi"
    body = f"Hey {name}! Thanks for your interest in our training data program. We've received your request and our team will review it shortly. We'll notify you as soon as it's approved!"

    send_notification(user_id, title, body)
    logger.info(f"Training data submitted notification sent to user {user_id}")


async def send_bulk_notification(user_tokens: List[str], title: str, body: str) -> None:
    """Send notification to multiple users in batches."""
    try:
        batch_size = 500
        num_batches = math.ceil(len(user_tokens) / batch_size)
        body = to_plain_text(body)
        tag = _generate_tag(f"bulk:{title}:{body}")
        notification = messaging.Notification(title=title, body=body)

        def send_batch(batch_tokens: List[str]) -> Tuple[Any, List[str]]:
            messages = [_build_message(token, tag, notification=notification) for token in batch_tokens]
            response = _send_messages(messages)

            # Collect permanently invalid tokens
            invalid_tokens: List[str] = []
            for idx, result in enumerate(response.responses):
                if not result.success and result.exception:
                    error_code = getattr(result.exception, 'code', None)
                    if error_code in PERMANENT_FAILURE_CODES:
                        invalid_tokens.append(batch_tokens[idx])
                        logger.error(f"Invalid token found - Error: {error_code}")

            return response, invalid_tokens

        tasks = [
            run_blocking(postprocess_executor, send_batch, user_tokens[i * batch_size : (i + 1) * batch_size])
            for i in range(num_batches)
        ]
        results = await asyncio.gather(*tasks)

        # Remove invalid tokens
        invalid_tokens = [token for _, batch_invalid in results for token in batch_invalid]
        if invalid_tokens:
            logger.error(f"Removing {len(invalid_tokens)} invalid tokens")
            await run_blocking(db_executor, notification_db.remove_bulk_tokens, invalid_tokens)

    except Exception as e:
        logger.error(f"Error sending bulk notification: {e}")


def send_merge_completed_message(
    user_id: str, merged_conversation_id: str, removed_conversation_ids: List[str]
) -> None:
    """
    Sends a data-only FCM message when conversation merge completes.

    The app receives this and:
    - Foreground: Shows toast "Conversations merged successfully"
    - Background: Shows local notification

    Args:
        user_id: The user's Firebase UID
        merged_conversation_id: ID of the primary (merged) conversation
        removed_conversation_ids: List of secondary conversation IDs that were removed
    """
    logger.info(f'send_merge_completed_message to user {user_id}')
    data = {
        'type': 'merge_completed',
        'merged_conversation_id': merged_conversation_id,
        'removed_conversation_ids': ','.join(removed_conversation_ids),
    }
    tag = _generate_tag(f"{user_id}:merge_completed:{merged_conversation_id}")
    _send_to_user(user_id, tag, data=data, is_background=True, priority='high')


def send_important_conversation_message(user_id: str, conversation_id: str):
    """
    Sends a data-only FCM message when a long conversation (>30 min) completes.

    The app receives this and:
    - Shows a local notification: "You just had an important convo, click to share summary"
    - On tap: navigates to conversation detail with share sheet auto-open

    Args:
        user_id: The user's Firebase UID
        conversation_id: ID of the completed conversation
    """
    tokens = notification_db.get_all_tokens(user_id)
    if not tokens:
        logger.info(f"No notification tokens found for user {user_id} for important conversation notification")
        return

    # FCM data values must be strings
    data = {
        'type': 'important_conversation',
        'conversation_id': conversation_id,
        'navigate_to': f'/conversation/{conversation_id}?share=1',
    }

    tag = _generate_tag(f'{user_id}:important_conversation:{conversation_id}')
    _send_to_user(user_id, tag, data=data, is_background=True, priority='high')
