"""Closed, privacy-safe outcome metrics for retained product journeys."""

from __future__ import annotations

from time import monotonic
from typing import Literal, cast

from utils.metrics import OMI_JOURNEY_ACCEPTED_TOTAL, OMI_JOURNEY_LATENCY_SECONDS, OMI_JOURNEY_TERMINAL_TOTAL

JourneyName = Literal['chat_response']
JourneyOutcome = Literal['success', 'failure', 'cancelled', 'stale']

_JOURNEYS = frozenset({'chat_response'})
_OUTCOMES = frozenset({'success', 'failure', 'cancelled', 'stale'})


def _journey(value: str) -> JourneyName:
    if value not in _JOURNEYS:
        raise ValueError(f'unknown journey: {value}')
    return cast(JourneyName, value)


def _outcome(value: str) -> JourneyOutcome:
    if value not in _OUTCOMES:
        raise ValueError(f'unknown journey outcome: {value}')
    return cast(JourneyOutcome, value)


def record_journey_accepted(journey: JourneyName) -> None:
    OMI_JOURNEY_ACCEPTED_TOTAL.labels(journey=_journey(journey)).inc()


def record_journey_terminal(journey: JourneyName, outcome: JourneyOutcome, elapsed_seconds: float) -> None:
    labels = {'journey': _journey(journey), 'outcome': _outcome(outcome)}
    OMI_JOURNEY_TERMINAL_TOTAL.labels(**labels).inc()
    OMI_JOURNEY_LATENCY_SECONDS.labels(**labels).observe(max(0.0, elapsed_seconds))


class JourneyAttempt:
    def __init__(self, journey: JourneyName) -> None:
        self.journey: JourneyName = _journey(journey)
        self.started_at = monotonic()
        self._finished = False
        record_journey_accepted(self.journey)

    @property
    def finished(self) -> bool:
        return self._finished

    def finish(self, outcome: JourneyOutcome) -> None:
        if self._finished:
            return
        self._finished = True
        record_journey_terminal(self.journey, outcome, monotonic() - self.started_at)
