"""Allowlisted evaluation export. Provider packets never enter this boundary."""

import hashlib
import logging
from dataclasses import dataclass
from typing import Any

from langfuse import Langfuse, propagate_attributes

from database.redis_connection import get_redis_client
from models.desktop_ai import (
    ScoreObservation,
    ChatTerminalObservation,
    SupervisorDecisionObservation,
    SupervisorRequest,
    SupervisorResponse,
    TerminalTurnObservation,
)
from utils.observability.fallback import record_fallback
from utils.observability.langfuse import get_langfuse_client, create_chat_trace_id
from utils.observability.chat_evaluation import chat_prompt_reference
from utils.observability.evaluation_policy import reviewed_example
from utils.llm.model_config import get_model
from utils.llm.gemini_usage import GeminiUsage
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt

logger = logging.getLogger(__name__)


def trace_id(uid: str, session_id: str, identity: str) -> str:
    return Langfuse.create_trace_id(seed=f'intentive-ai:{uid}:{session_id}:{identity}')


def claim_observation(uid: str, session_id: str, kind: str, identity: str) -> bool:
    """Bound duplicate terminal receipts across workers without retaining content."""
    key = hashlib.sha256(f'{uid}:{session_id}:{kind}:{identity}'.encode()).hexdigest()
    return bool(get_redis_client().set(f'ai-observation:{key}', '1', ex=86400, nx=True))


def _failed_export(error: Exception) -> None:
    logger.warning('AI observation export failed error_type=%s', type(error).__name__)
    record_fallback(
        component='other',
        from_mode='langfuse_tracing',
        to_mode='untraced_ai',
        reason='other',
        outcome='degraded',
        log=logger,
    )


@dataclass
class SupervisorGeneration:
    # Langfuse's external SDK exposes a union of observation handles.
    observation: Any | None

    def cancel(self) -> None:
        if self.observation is None:
            return
        try:
            try:
                self.observation.update(level='WARNING', status_message='cancelled', output={'outcome': 'cancelled'})
            finally:
                self.observation.end()
        except Exception as error:
            _failed_export(error)


def _start_supervisor_observation(
    *,
    uid: str,
    request: SupervisorRequest,
    decision_id: str,
    prompt_name: str,
    prompt_version: str,
    prompt_source: str,
    prompt_client: Any | None,
    inference: bool,
) -> SupervisorGeneration:
    try:
        client = get_langfuse_client()
        if client is None:
            return SupervisorGeneration(None)
        with propagate_attributes(
            user_id=uid,
            session_id=request.session_id,
            tags=['desktop', 'supervisor'],
            metadata={
                'prompt_name': prompt_name,
                'prompt_version': prompt_version,
                'prompt_source': prompt_source,
                'decision_id': decision_id,
                'observation_id': request.observation_id,
            },
        ):
            observation = client.start_observation(
                trace_context={'trace_id': trace_id(uid, request.session_id, decision_id)},
                name='supervisor-evaluation',
                as_type='generation' if inference else 'span',
                model=get_model('supervisor'),
                prompt=prompt_client,
                input={
                    'transcript_count': len(request.transcripts),
                    'conversation_count': len(request.conversation),
                    'has_screen': request.screen is not None,
                    'has_webcam': request.webcam is not None,
                    'memory_count': len(request.memories),
                    'content_revision': request.content_revision,
                    'observed_at': request.observed_at.isoformat() if request.observed_at else None,
                    'input_status': request.input_status.model_dump(mode='json') if request.input_status else None,
                },
            )
        return SupervisorGeneration(observation)
    except Exception as error:
        _failed_export(error)
        return SupervisorGeneration(None)


def start_supervisor_observation(
    *,
    uid: str,
    request: SupervisorRequest,
    decision_id: str,
    prompt: ResolvedRuntimePrompt,
) -> SupervisorGeneration:
    """Open the real generation before provider I/O so its duration is meaningful."""
    return _start_supervisor_observation(
        uid=uid,
        request=request,
        decision_id=decision_id,
        prompt_name=prompt.name,
        prompt_version=prompt.version,
        prompt_source=prompt.source,
        prompt_client=prompt.prompt_client,
        inference=True,
    )


def record_supervisor_observation(
    *,
    uid: str,
    request: SupervisorRequest,
    response: SupervisorResponse,
    prompt_client: Any | None,
    duration_ms: int,
    generation: SupervisorGeneration | None = None,
    usage: GeminiUsage | None = None,
    model_version: str | None = None,
) -> None:
    """Finish metadata only; a missing policy produces a span, never fake model usage."""
    active = generation or _start_supervisor_observation(
        uid=uid,
        request=request,
        decision_id=response.decision_id,
        prompt_name=response.prompt.name,
        prompt_version=response.prompt.version,
        prompt_source=response.prompt.source,
        prompt_client=prompt_client,
        inference=False,
    )
    if active.observation is None:
        return
    try:
        try:
            active.observation.update(
                output={
                    'action': response.action,
                    'outcome': 'unavailable_prompt' if response.prompt.source != 'langfuse' else response.outcome,
                },
                metadata={
                    'duration_ms': duration_ms,
                    'model_version': model_version,
                    'usage_available': usage is not None,
                },
                usage_details=usage.langfuse() if usage else None,
                level='WARNING' if response.outcome == 'degraded' else 'DEFAULT',
            )
        finally:
            active.observation.end()
    except Exception as error:
        _failed_export(error)


def record_client_observation(
    *,
    uid: str,
    event: TerminalTurnObservation | ChatTerminalObservation | ScoreObservation | SupervisorDecisionObservation,
) -> None:
    try:
        client = get_langfuse_client()
        if client is None:
            return
        request_id = event.request_id if isinstance(event, (ChatTerminalObservation, ScoreObservation)) else None
        decision_id = None if isinstance(event, ChatTerminalObservation) else event.decision_id
        identity = (
            event.decision_id if isinstance(event, SupervisorDecisionObservation) else decision_id or event.turn_id
        )
        identifier = create_chat_trace_id(uid, request_id) if request_id else trace_id(uid, event.session_id, identity)
        if isinstance(event, ScoreObservation):
            client.create_score(
                trace_id=identifier,
                score_id=hashlib.sha256(f'{uid}:{event.session_id}:{event.turn_id}:score'.encode()).hexdigest(),
                session_id=event.session_id,
                metadata={
                    'turn_id': event.turn_id,
                    'decision_id': event.decision_id,
                    **({'request_id': request_id} if request_id else {}),
                },
                name='user-feedback',
                value=event.value,
                data_type='BOOLEAN',
            )
            return
        prompt = (
            chat_prompt_reference(uid, event.request_id) if isinstance(event, ChatTerminalObservation) else event.prompt
        )
        # A client never guesses Chat's prompt or borrows Live's receipt. An
        # expired/unavailable metadata receipt drops this optional example.
        if prompt is None:
            return
        event_identity = event.decision_id if isinstance(event, SupervisorDecisionObservation) else event.turn_id
        if not claim_observation(uid, event.session_id, event.kind, event_identity):
            return
        metadata = {
            'prompt_name': prompt.name,
            'prompt_version': prompt.version,
            'prompt_source': prompt.source,
            'evaluation_sharing': str(event.evaluation_sharing).lower(),
        }
        if decision_id is not None:
            metadata['decision_id'] = decision_id
        if request_id is not None:
            metadata['request_id'] = request_id
        if isinstance(event, SupervisorDecisionObservation):
            metadata['observation_id'] = event.observation_id
        else:
            metadata['turn_id'] = event.turn_id
        exported: dict[str, object] = {'conversation_count': len(event.conversation)}
        exported.update(reviewed_example(event))
        if isinstance(event, (TerminalTurnObservation, ChatTerminalObservation)):
            exported.update(outcome=event.outcome, duration_ms=event.duration_ms)
        with propagate_attributes(
            user_id=uid, session_id=event.session_id, tags=['desktop', event.kind], metadata=metadata
        ):
            observation = client.start_observation(
                trace_context={'trace_id': identifier}, name=event.kind, as_type='span', input=exported
            )
            observation.end()
    except Exception as error:
        _failed_export(error)
