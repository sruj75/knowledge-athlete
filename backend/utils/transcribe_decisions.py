"""Pure retained decisions for fixed-format transient STT buffering."""

from dataclasses import dataclass


@dataclass(frozen=True)
class SttBufferFlushDecision:
    should_flush: bool
    socket_dead: bool
    send_to_stt: bool
    managed_stt_usage_ms: int


def stt_buffer_flush_size(sample_rate: int) -> int:
    return int(sample_rate * 2 * 0.03)


def decide_stt_buffer_flush(
    *,
    buffer_len: int,
    flush_size: int,
    force: bool,
    socket_dead: bool,
    socket_available: bool,
    fair_use_managed_stt_budget_exhausted: bool,
    fair_use_track_managed_stt_usage: bool,
    sample_rate: int,
) -> SttBufferFlushDecision:
    if buffer_len == 0:
        return SttBufferFlushDecision(False, False, False, 0)
    if not force and buffer_len < flush_size:
        return SttBufferFlushDecision(False, False, False, 0)

    send_to_stt = socket_available and not socket_dead and not fair_use_managed_stt_budget_exhausted
    managed_stt_usage_ms = 0
    if send_to_stt and fair_use_track_managed_stt_usage:
        managed_stt_usage_ms = buffer_len * 1000 // (sample_rate * 2)
    return SttBufferFlushDecision(True, socket_dead, send_to_stt, managed_stt_usage_ms)
