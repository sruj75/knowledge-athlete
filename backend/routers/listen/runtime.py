"""Transient-only runtime coordinator for an accepted ``/v4/listen`` socket."""

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from typing import Any, Awaitable, cast

from fastapi.websockets import WebSocketDisconnect
from starlette.websockets import WebSocketState

import database.redis_db as redis_db
import database.users as user_db
import database.fair_use as fair_use_db
from config.stt_provider_policy import MODULATE_PROVIDER
from models.message_event import (
    FREEMIUM_ACTION_SETUP_ON_DEVICE_STT,
    FreemiumThresholdReachedEvent,
    FairUseReviewRequestedEvent,
    FairUseManagedCloudExhaustedEvent,
    MessageEvent,
    MessageServiceStatusEvent,
)
from utils.analytics import billable_transcription_seconds, record_usage
from utils.async_tasks import WebSocketTaskSupervisor, wait_for_event
from utils.executors import db_executor, run_blocking, start_background_task
from utils.fair_use import (
    FAIR_USE_CHECK_INTERVAL_SECONDS,
    FAIR_USE_ENABLED,
    FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS,
    check_soft_caps,
    get_enforcement_stage,
    get_rolling_speech_ms,
    get_managed_stt_budget_status,
    is_daily_audio_ceiling_exceeded,
    is_managed_stt_budget_exhausted,
    is_free_credits_exhausted,
    record_managed_stt_usage_ms,
    record_speech_ms,
    trigger_free_exhaustion_if_needed,
)
from utils.fair_use_reviews import create_pending_fair_use_review, get_pending_fair_use_review
from utils.listen_session_bootstrap import load_listen_admission
from utils.metrics import BACKEND_LISTEN_ACTIVE_WS_CONNECTIONS
from utils.observability.transcription import LiveSTTAttempt
from utils.subscription import get_remaining_transcription_seconds, is_trial_paywalled

from .contracts import ListenLimits, ListenRequest, ListenSessionState
from .persistence import ListenPersistence
from .receiver import ListenReceiver
from .transcripts import TransientTranscriptProcessor

logger = logging.getLogger(__name__)

FREEMIUM_THRESHOLD_SECONDS = 180


class ListenSessionRuntime:
    """Own one transient transport session and no durable product identity."""

    def __init__(self, request: ListenRequest):
        self.request = request
        self.limits = ListenLimits()
        self.persistence = ListenPersistence()
        self.state = ListenSessionState()
        self.session_id = str(uuid.uuid4())
        self.user_has_credits = True
        self.task_supervisor = WebSocketTaskSupervisor(
            uid=request.uid,
            label="listen",
            gauge=BACKEND_LISTEN_ACTIVE_WS_CONNECTIONS,
        )
        self.state.shutdown_event = self.task_supervisor.shutdown_event
        self.transcripts = TransientTranscriptProcessor(self)
        self.receiver = ListenReceiver(self)
        self._fair_use_managed_cloud_exhausted_in_progress = False

    @staticmethod
    def now() -> float:
        return time.time()

    def spawn(self, coroutine: Awaitable[Any], *, name: str) -> asyncio.Task[Any]:
        return self.task_supervisor.create_task(cast(Any, coroutine), name=name)

    async def wait(self, seconds: float) -> bool:
        return await wait_for_event(self.state.shutdown_event, seconds)

    async def send_json(self, payload: dict[str, Any]) -> bool:
        if not self.state.active:
            return False
        try:
            await self.request.websocket.send_json(payload)
            return True
        except WebSocketDisconnect:
            self.state.active = False
        except RuntimeError as error:
            self.state.active = False
            logger.info("Listen delivery after close type=%s", type(error).__name__)
        except Exception as error:
            logger.warning("Listen delivery failed type=%s", type(error).__name__)
        return False

    async def send_event(self, event: MessageEvent) -> bool:
        return await self.send_json(event.to_json())

    async def _send_fair_use_review(self, review: dict[str, Any] | None) -> None:
        if review is None or review.get('review_id') == self.state.fair_use_review_sent_id:
            return
        sent = await self.send_event(
            FairUseReviewRequestedEvent(
                review_id=str(review['review_id']),
                trigger=str(review['trigger']),
                window_speech_ms=dict(review['window_speech_ms']),
                thresholds_ms=dict(review['thresholds_ms']),
                classifier_contract=str(review['classifier_contract']),
                requested_at=str(review['requested_at']),
                expires_at=str(review['expires_at']),
            )
        )
        if sent:
            self.state.fair_use_review_sent_id = str(review['review_id'])

    async def notify_managed_cloud_exhausted(self) -> None:
        if self.state.fair_use_managed_cloud_exhausted_sent or self._fair_use_managed_cloud_exhausted_in_progress:
            return
        # The check-and-claim is synchronous on this runtime's event loop, so
        # periodic refresh and audio flush cannot both pass it before either
        # reaches persistence or websocket suspension points.
        self._fair_use_managed_cloud_exhausted_in_progress = True
        try:
            budget = await self.persistence.call(get_managed_stt_budget_status, self.request.uid)
            state = await self.persistence.call(fair_use_db.get_fair_use_state, self.request.uid)
            resets_at = budget.get('resets_at')
            if not isinstance(resets_at, str) or not resets_at:
                logger.warning('Listen fair-use allowance reset was unavailable')
                return
            sent = await self.send_event(
                FairUseManagedCloudExhaustedEvent(
                    resets_at=resets_at,
                    case_ref=str(state.get('last_case_ref', '')),
                )
            )
            if sent:
                self.state.fair_use_managed_cloud_exhausted_sent = True
        finally:
            self._fair_use_managed_cloud_exhausted_in_progress = False

    def start_live_transcription(self) -> None:
        if self.state.live_transcription_attempt is None:
            self.state.live_transcription_attempt = LiveSTTAttempt(
                provider=MODULATE_PROVIDER,
                platform=self.request.platform,
            )

    def complete_live_transcription(self) -> None:
        attempt = self.state.live_transcription_attempt
        if attempt is not None:
            attempt.finish("success", phase="transcript_delivery")

    def _finish_live_transcription(self) -> None:
        attempt = self.state.live_transcription_attempt
        if attempt is None:
            return
        outcome = (
            "failure"
            if self.state.live_transcription_failed or self.state.stt_terminal_failure or self.state.close_code == 1011
            else "cancelled"
        )
        attempt.finish(outcome, phase="teardown")

    async def _admit(self) -> bool:
        if not self.request.uid:
            await self.request.websocket.close(code=1008, reason="Bad uid")
            return False
        if await run_blocking(db_executor, is_trial_paywalled, self.request.uid, self.request.platform):
            await self.request.websocket.send_json(
                FreemiumThresholdReachedEvent(
                    remaining_seconds=0,
                    action=FREEMIUM_ACTION_SETUP_ON_DEVICE_STT,
                ).to_json()
            )
            await self.request.websocket.close(code=1008, reason="trial_expired")
            return False

        admission = await load_listen_admission(self.request.uid)
        if not admission.user_exists:
            await self.request.websocket.close(code=1008, reason="Bad user")
            return False
        self.user_has_credits = admission.user_has_credits
        self.state.fair_use_track_managed_stt_usage = admission.fair_use_track_managed_stt_usage
        self.state.fair_use_managed_stt_budget_exhausted = admission.fair_use_managed_stt_budget_exhausted
        self.state.fair_use_allowance_handoff_required = admission.fair_use_managed_stt_budget_exhausted
        if not admission.user_has_credits:
            await self.send_event(
                FreemiumThresholdReachedEvent(
                    remaining_seconds=0,
                    action=FREEMIUM_ACTION_SETUP_ON_DEVICE_STT,
                )
            )
            self.state.freemium_threshold_sent = True
        if FAIR_USE_ENABLED:
            pending_review = await self.persistence.call(get_pending_fair_use_review, self.request.uid)
            await self._send_fair_use_review(pending_review)
            if self.state.fair_use_managed_stt_budget_exhausted:
                await self.notify_managed_cloud_exhausted()
        return True

    async def _send_ping(self) -> bool:
        try:
            await self.request.websocket.send_text("ping")
            return True
        except (WebSocketDisconnect, RuntimeError):
            self.state.active = False
            return False

    async def _heartbeat(self) -> None:
        while self.state.active:
            if self.request.websocket.client_state != WebSocketState.CONNECTED:
                self.state.active = False
                break
            if not await self._send_ping():
                break
            if self.state.last_activity_time and self.now() - self.state.last_activity_time > 90:
                self.state.close_code = 1001
                self.state.active = False
                break
            if await self.wait(10):
                break

    async def _record_usage_periodically(self) -> None:
        while self.state.active:
            if await self.wait(60):
                break
            transcription_seconds = await self._flush_usage(final=False)
            await self._refresh_fair_use()
            await self._refresh_credits(transcription_seconds=transcription_seconds)

    async def _refresh_fair_use(self) -> None:
        if not FAIR_USE_ENABLED or self.now() - self.state.fair_use_last_check_ts < FAIR_USE_CHECK_INTERVAL_SECONDS:
            return
        self.state.fair_use_last_check_ts = self.now()
        try:
            if self.state.fair_use_entitlement_policy is None:
                subscription = await self.persistence.call(user_db.get_user_valid_subscription, self.request.uid)
                self.state.fair_use_entitlement_policy = subscription.entitlement_policy if subscription else None
            totals = await self.persistence.call(get_rolling_speech_ms, self.request.uid)
            caps = await self.persistence.call(
                check_soft_caps,
                self.request.uid,
                speech_totals=totals,
                entitlement_policy=self.state.fair_use_entitlement_policy,
            )
            stage = await self.persistence.call(get_enforcement_stage, self.request.uid)
            if caps and stage != "restrict":
                free_exhausted = await self.persistence.call(is_free_credits_exhausted, self.request.uid)
                if free_exhausted:
                    start_background_task(
                        trigger_free_exhaustion_if_needed(self.request.uid, caps, self.session_id),
                        name=f"fair_use_free_exhausted:{self.request.uid}:{self.session_id}",
                    )
                else:
                    review = await self.persistence.call(
                        create_pending_fair_use_review,
                        self.request.uid,
                        caps,
                        totals,
                        self.state.fair_use_entitlement_policy,
                        self.session_id,
                    )
                    await self._send_fair_use_review(review)
            restricts_managed = stage == "restrict" and FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS > 0
            self.state.fair_use_track_managed_stt_usage = restricts_managed or bool(
                caps and FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS > 0
            )
            restricted_allowance_exhausted = bool(
                restricts_managed and await self.persistence.call(is_managed_stt_budget_exhausted, self.request.uid)
            )
            self.state.fair_use_allowance_handoff_required = restricted_allowance_exhausted
            self.state.fair_use_managed_stt_budget_exhausted = restricted_allowance_exhausted
            if is_daily_audio_ceiling_exceeded(self.request.uid, speech_totals=totals):
                self.state.fair_use_managed_stt_budget_exhausted = True
            if self.state.fair_use_allowance_handoff_required:
                await self.notify_managed_cloud_exhausted()
        except Exception as error:
            logger.warning("Fair-use listen check failed type=%s", type(error).__name__)

    async def _refresh_credits(self, *, transcription_seconds: int = 0) -> None:
        now = self.now()
        invalidated = await self.persistence.call(redis_db.check_credits_invalidation, self.request.uid)
        needs_refresh = (
            not self.state.remaining_seconds_cache_initialized
            or invalidated
            or now - self.state.remaining_seconds_cache_ts >= self.limits.credits_refresh_seconds
        )
        if needs_refresh:
            self.state.remaining_seconds_cache = await self.persistence.call(
                get_remaining_transcription_seconds,
                self.request.uid,
                source=self.request.platform,
            )
            self.state.remaining_seconds_cache_ts = now
            self.state.remaining_seconds_cache_initialized = True
        elif self.state.remaining_seconds_cache is not None and transcription_seconds > 0:
            self.state.remaining_seconds_cache = max(
                0,
                self.state.remaining_seconds_cache - transcription_seconds,
            )
        remaining = self.state.remaining_seconds_cache
        if remaining is not None and remaining <= FREEMIUM_THRESHOLD_SECONDS and not self.state.freemium_threshold_sent:
            await self.send_event(
                FreemiumThresholdReachedEvent(
                    remaining_seconds=remaining,
                    action=FREEMIUM_ACTION_SETUP_ON_DEVICE_STT,
                )
            )
            self.state.freemium_threshold_sent = True
        self.user_has_credits = remaining is None or remaining > 0
        if self.user_has_credits and (remaining is None or remaining > FREEMIUM_THRESHOLD_SECONDS):
            self.state.freemium_threshold_sent = False

    async def _flush_usage(self, *, final: bool) -> int:
        if self.state.fair_use_track_managed_stt_usage and self.state.managed_stt_usage_ms_pending:
            await self.persistence.call(
                record_managed_stt_usage_ms,
                self.request.uid,
                self.state.managed_stt_usage_ms_pending,
            )
            self.state.managed_stt_usage_ms_pending = 0
        if not self.state.last_usage_record_timestamp:
            return 0
        speech_seconds = 0
        if self.receiver.vad_gate is not None:
            speech_ms = self.receiver.vad_gate.consume_speech_ms_delta()
            speech_seconds = speech_ms // 1_000
            if FAIR_USE_ENABLED and speech_ms:
                await self.persistence.call(record_speech_ms, self.request.uid, speech_ms)
        now = self.now()
        seconds = billable_transcription_seconds(
            self.state.last_usage_record_timestamp,
            self.state.last_audio_received_time,
            now,
        )
        words = self.state.words_transcribed_since_last_record
        self.state.words_transcribed_since_last_record = 0
        if seconds or words or speech_seconds:
            await self.persistence.call(
                record_usage,
                self.request.uid,
                transcription_seconds=seconds,
                words_transcribed=words,
                speech_seconds=speech_seconds,
            )
        if not final:
            self.state.last_usage_record_timestamp = now
        return seconds

    async def run(self) -> None:
        if not await self._admit():
            return
        try:
            self.task_supervisor.start_session()
            if not await self.receiver.initialize_stt():
                return
            receive_task = self.task_supervisor.create_task(self.receiver.receive_data(), name="receive")
            self.task_supervisor.create_lifetime_task(self._heartbeat(), name="heartbeat")
            self.task_supervisor.create_lifetime_task(self.transcripts.process_loop(), name="stream_transcript")
            self.task_supervisor.create_lifetime_task(self._record_usage_periodically(), name="record_usage")
            await self.send_event(MessageServiceStatusEvent(status="ready"))
            result = await self.task_supervisor.supervise(receive_task=receive_task)
            logger.info("Listen supervisor exited reason=%s task=%s", result.reason, result.task_name)
            if result.reason in {"crash", "lifetime_done"}:
                self.state.live_transcription_failed = True
            if receive_task.done() and not receive_task.cancelled():
                receive_error = receive_task.exception()
                if receive_error is not None:
                    raise receive_error
        except Exception as error:
            logger.error("Listen WebSocket operation failed type=%s", type(error).__name__)
            self.state.live_transcription_failed = True
            self.state.close_code = 1011
        finally:
            await self._teardown()

    async def _teardown(self) -> None:
        try:
            await self.transcripts.flush()
        except Exception as error:
            logger.warning("Transient transcript flush failed type=%s", type(error).__name__)
        self.state.active = False
        self.state.shutdown_event.set()
        try:
            self.receiver.finish()
        except Exception as error:
            logger.warning("STT finish failed type=%s", type(error).__name__)
        try:
            await self._flush_usage(final=True)
        except Exception as error:
            logger.warning("Final listen usage flush failed type=%s", type(error).__name__)
        if self.request.websocket.client_state == WebSocketState.CONNECTED and not self.state.stt_terminal_failure:
            try:
                await self.request.websocket.close(code=self.state.close_code)
            except Exception:
                pass
        await self.task_supervisor.drain_all(timeout=5.0, cancel=True)
        self.task_supervisor.end_session()
        self._finish_live_transcription()
        self.transcripts.clear()


async def run_listen_session(request: ListenRequest) -> None:
    await ListenSessionRuntime(request).run()
