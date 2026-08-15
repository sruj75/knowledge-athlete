"""Edge-case request validation helpers for calendar dates, sync filenames,
image chunks, and reusable Query parameter aliases.

Body validation convention: JSON request bodies are validated by FastAPI's
native mechanism — declare the body param as a Pydantic model
(``data: YourRequestModel``) and FastAPI + Pydantic handle parsing, type
checking, and 422-on-malformed. Do NOT hand-parse with ``data: dict`` +
``data.get()`` + manual HTTPException; that pattern is being phased out (see
Phase 1.2 of the schema SSOT plan). This module does NOT centralize body
validation; it owns only the retained date, filename, chunk-envelope, and
query-parameter boundaries below.
"""

from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Annotated

from fastapi import HTTPException, Query
from pydantic import BaseModel, Field, model_validator

PositiveLimit = Annotated[int, Query(ge=1, le=1000)]
CalendarMeetingsLimit = Annotated[int, Query(ge=1, le=100)]
NonNegativeOffset = Annotated[int, Query(ge=0)]
HistoryDays = Annotated[int, Query(ge=1, le=365)]


def validate_calendar_date(value: str | None, field_name: str = 'date') -> str | None:
    """Validate YYYY-MM-DD strings as real calendar dates and return the original string."""
    if value is None:
        return None
    try:
        date.fromisoformat(value)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=f'Invalid {field_name}: expected a real YYYY-MM-DD date') from e
    return value


def parse_timezone_aware_datetime(value: str, field_name: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError as e:
        raise ValueError(f'{field_name} must be a valid ISO 8601 datetime') from e
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError(f'{field_name} must include a timezone offset')
    return parsed


MAX_IMAGE_CHUNK_TOTAL = 4096


def parse_sync_filename_timestamp(path: str) -> int | float:
    """Parse and validate the unix timestamp in a sync upload/segment filename.

    Upload filenames are expected to end with _<unix-seconds-or-millis>.bin;
    VAD segment files are named <unix-seconds-or-millis>.wav. The returned
    timestamp is UTC seconds and is safe to pass to fromtimestamp(...,
    tz=timezone.utc).
    """
    filename = path.split('/')[-1]
    timestamp_part = filename.rsplit('_', 1)[1] if '_' in filename else filename
    raw_timestamp_text = timestamp_part.rsplit('.', 1)[0]
    try:
        raw_timestamp = Decimal(raw_timestamp_text)
    except InvalidOperation as e:
        raise ValueError('invalid timestamp') from e
    if not raw_timestamp.is_finite() or raw_timestamp <= 0:
        raise ValueError('invalid timestamp')

    timestamp_decimal = raw_timestamp / Decimal(1000) if raw_timestamp > Decimal(10_000_000_000) else raw_timestamp
    if timestamp_decimal == timestamp_decimal.to_integral_value():
        timestamp = int(timestamp_decimal)
    else:
        timestamp = float(timestamp_decimal)
    try:
        timestamp_dt = datetime.fromtimestamp(timestamp, tz=timezone.utc)
    except (OSError, OverflowError, ValueError) as e:
        raise ValueError('invalid timestamp') from e

    now = datetime.now(timezone.utc)
    if timestamp_dt > now or timestamp_dt < datetime(2024, 1, 1, tzinfo=timezone.utc):
        raise ValueError('invalid timestamp')
    return timestamp


class ImageChunkEnvelope(BaseModel):
    id: str = Field(min_length=1)
    index: int = Field(ge=0)
    total: int = Field(ge=1, le=MAX_IMAGE_CHUNK_TOTAL)
    data: str = Field(min_length=1)

    @model_validator(mode='after')
    def validate_index_within_total(self):
        if self.index >= self.total:
            raise ValueError('index must be smaller than total')
        return self

    def validate_against_cached_total(self, cached_total: int | None) -> None:
        if cached_total is not None and cached_total != self.total:
            raise ValueError('total must be consistent for all chunks in an image upload')
