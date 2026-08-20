"""S-14 contract: desktop notifications no longer depend on hosted LLM drafting."""

from pathlib import Path

from utils.llm import model_config
from utils.llm.usage_tracker import Features

ROOT = Path(__file__).resolve().parents[2]


def test_notification_only_llm_modules_and_routes_are_absent() -> None:
    assert not (ROOT / 'utils/llm/proactive_notification.py').exists()
    assert not (ROOT / 'utils/llm/notifications.py').exists()

    for profile in model_config.MODEL_QOS_PROFILES.values():
        for feature in ('daily_summary', 'proactive_notification', 'notifications'):
            assert feature not in profile

    for feature in ('daily_summary', 'proactive_notification', 'notifications'):
        assert feature not in model_config._AUTO_LANE_FEATURES


def test_notification_only_usage_features_are_absent() -> None:
    assert not hasattr(Features, 'PROACTIVE_NOTIFICATION')
    assert not hasattr(Features, 'NOTIFICATIONS')
    assert not hasattr(Features, 'SUBSCRIPTION_NOTIFICATION')
    assert not hasattr(Features, 'DAILY_SUMMARY')


def test_mentor_notification_frequency_storage_is_absent() -> None:
    source = (ROOT / 'database/notifications.py').read_text(encoding='utf-8')
    assert 'mentor_notification_frequency' not in source
    assert 'mentor_frequency:' not in source


def test_daily_summary_chat_message_type_is_absent() -> None:
    source = (ROOT / 'models/chat.py').read_text(encoding='utf-8')
    assert "day_summary = 'day_summary'" not in source
