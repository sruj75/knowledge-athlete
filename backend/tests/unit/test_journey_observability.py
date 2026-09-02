from unittest.mock import MagicMock

import pytest

from utils import metrics
from utils.observability import journeys


def test_journey_contract_uses_only_closed_privacy_safe_labels(monkeypatch):
    accepted = MagicMock()
    terminal = MagicMock()
    latency = MagicMock()
    accepted.labels.return_value = MagicMock()
    terminal.labels.return_value = MagicMock()
    latency.labels.return_value = MagicMock()
    monkeypatch.setattr(journeys, 'OMI_JOURNEY_ACCEPTED_TOTAL', accepted)
    monkeypatch.setattr(journeys, 'OMI_JOURNEY_TERMINAL_TOTAL', terminal)
    monkeypatch.setattr(journeys, 'OMI_JOURNEY_LATENCY_SECONDS', latency)

    journeys.record_journey_accepted('chat_response')
    journeys.record_journey_terminal('chat_response', 'cancelled', 1.5)

    accepted.labels.assert_called_once_with(journey='chat_response')
    terminal.labels.assert_called_once_with(journey='chat_response', outcome='cancelled')
    latency.labels.assert_called_once_with(journey='chat_response', outcome='cancelled')
    with pytest.raises(ValueError, match='unknown journey'):
        journeys.record_journey_accepted('removed_journey')  # type: ignore[arg-type]


def test_idle_metrics_export_retained_zero_valued_children_without_user_traffic():
    exported = metrics.generate_latest().decode()
    assert 'intentive_journey_accepted_total{journey="chat_response"}' in exported
    assert 'intentive_live_stt_accepted_total' in exported
    assert 'intentive_live_stt_terminal_total' in exported
    assert 'omi_journey_accepted_total' not in exported
