from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi import Response

LIVE_STT_ACTIVE_WS_CONNECTIONS = Gauge(
    'live_stt_active_ws_connections',
    'Number of currently active live transcription WebSocket connections',
)

OMI_JOURNEY_ACCEPTED_TOTAL = Counter(
    'omi_journey_accepted_total',
    'Accepted real-traffic product journeys by closed journey name',
    ['journey'],
)

OMI_JOURNEY_TERMINAL_TOTAL = Counter(
    'omi_journey_terminal_total',
    'Terminal real-traffic product journey outcomes by closed journey and outcome names',
    ['journey', 'outcome'],
)

OMI_JOURNEY_LATENCY_SECONDS = Histogram(
    'omi_journey_latency_seconds',
    'Elapsed time from accepted real-traffic journey to terminal outcome',
    ['journey', 'outcome'],
    buckets=(0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300, 900, 3600, 21600, 86400),
)

# Export zero-valued children from a healthy but idle process so authenticated
# metrics consumers can distinguish no user traffic from an absent target.
for _journey in ('chat_response',):
    OMI_JOURNEY_ACCEPTED_TOTAL.labels(journey=_journey)
    for _outcome in ('success', 'failure', 'cancelled', 'stale'):
        OMI_JOURNEY_TERMINAL_TOTAL.labels(journey=_journey, outcome=_outcome)
        OMI_JOURNEY_LATENCY_SECONDS.labels(journey=_journey, outcome=_outcome)
OMI_FALLBACK_TOTAL = Counter(
    'omi_fallback_total',
    'Fallback / resilience transitions by component, path, reason, and outcome',
    ['component', 'from_mode', 'to_mode', 'reason', 'outcome'],
)

DESKTOP_UPDATE_RESOLUTION_TOTAL = Counter(
    'desktop_update_resolution_total',
    'Desktop update channel resolutions by platform, channel, and source',
    ['platform', 'channel', 'source'],
)

DESKTOP_UPDATE_POINTER_MISMATCH_TOTAL = Counter(
    'desktop_update_pointer_mismatch_total',
    'Desktop update pointer and legacy release mismatches',
    ['platform', 'channel', 'field'],
)

DESKTOP_UPDATE_POINTER_AGE_SECONDS = Gauge(
    'desktop_update_pointer_age_seconds',
    'Age of the selected desktop update pointer',
    ['platform', 'channel'],
)

DESKTOP_UPDATE_LKG_AGE_SECONDS = Gauge(
    'desktop_update_lkg_age_seconds',
    'Age of the selected desktop update last-known-good cache entry',
    ['platform', 'channel'],
)

DESKTOP_UPDATE_FEED_VALID = Gauge(
    'desktop_update_feed_valid',
    'Whether a valid desktop update was resolved for a channel',
    ['platform', 'channel'],
)

OMI_TRANSCRIPTION_ACCEPTED_TOTAL = Counter(
    'omi_voice_transcription_accepted_total',
    'Accepted prerecorded transcription journeys by bounded route and runtime identity',
    ['route', 'provider', 'client_platform', 'deployment_version'],
)

OMI_TRANSCRIPTION_COMPLETED_TOTAL = Counter(
    'omi_voice_transcription_completed_total',
    'Terminal semantic outcomes for accepted prerecorded transcription journeys',
    ['route', 'provider', 'outcome', 'client_platform', 'deployment_version'],
)

OMI_TRANSCRIPTION_LATENCY_SECONDS = Histogram(
    'omi_voice_transcription_latency_seconds',
    'End-to-end latency for accepted prerecorded transcription journeys',
    ['route', 'provider', 'outcome', 'client_platform', 'deployment_version'],
    buckets=(0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300),
)

OMI_LIVE_STT_TERMINAL_FAILURES_TOTAL = Counter(
    'omi_live_stt_terminal_failures_total',
    'Terminal live-STT failures by bounded provider, outcome, client platform, environment, and phase',
    ['provider', 'outcome', 'client_platform', 'deployment_environment', 'phase'],
)

OMI_LIVE_STT_ACCEPTED_TOTAL = Counter(
    'omi_live_stt_accepted_total',
    'Accepted live-STT attempts by bounded provider, client platform, and deployment environment',
    ['provider', 'client_platform', 'deployment_environment'],
)

# Whether misaligned frames actually occur in production is unmeasured; Velma rejects
# them outright, so this counter is what tells a Velma canary if that was the cause.
OMI_LIVE_STT_MISALIGNED_FRAMES_TOTAL = Counter(
    'omi_live_stt_misaligned_frames_total',
    'Live-STT frames that were not a whole number of 16-bit samples, by provider and pipeline stage',
    ['provider', 'stage'],
)

OMI_LIVE_STT_TERMINAL_TOTAL = Counter(
    'omi_live_stt_terminal_total',
    'Terminal live-STT outcomes for accepted attempts by bounded labels',
    ['provider', 'outcome', 'client_platform', 'deployment_environment', 'phase'],
)

AUTH_FLOW_EVENTS = Counter(
    'auth_flow_events_total',
    'Auth flow events by provider, stage, outcome, and sanitized failure class',
    ['provider', 'stage', 'outcome', 'failure_class'],
)

AUTH_FLOW_DURATION_SECONDS = Histogram(
    'auth_flow_duration_seconds',
    'Auth flow duration in seconds by provider and terminal state',
    ['provider', 'terminal_state'],
)


def metrics_response() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
