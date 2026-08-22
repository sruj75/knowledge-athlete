from datetime import datetime, timezone, timedelta

import pytest

from utils.conversations.datetime_utils import coerce_utc_datetime


@pytest.mark.parametrize(
    ('value', 'expected'),
    [
        ('2026-06-25T12:00:00Z', datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc)),
        (
            '2026-06-25T08:00:00-04:00',
            datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc),
        ),
        (
            datetime(2026, 6, 25, 8, 0, tzinfo=timezone(timedelta(hours=-4))),
            datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc),
        ),
        (datetime(2026, 6, 25, 12, 0), datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc)),
    ],
)
def test_coerce_utc_datetime_normalizes_supported_timestamps(value, expected):
    assert coerce_utc_datetime(value) == expected


@pytest.mark.parametrize('value', [None, 'not-a-date', object()])
def test_coerce_utc_datetime_returns_none_for_missing_or_malformed_values(value):
    assert coerce_utc_datetime(value) is None
