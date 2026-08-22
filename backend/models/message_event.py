"""Transient listen events retained after hosted conversation products were removed."""

from typing import Optional

from pydantic import BaseModel

FREEMIUM_ACTION_SETUP_ON_DEVICE_STT = 'setup_on_device_stt'
FREEMIUM_ACTION_NONE = 'none'


class MessageEvent(BaseModel):
    event_type: str

    def to_json(self):
        payload = self.model_dump(mode='json')
        payload['type'] = payload.pop('event_type')
        return payload


class MessageServiceStatusEvent(MessageEvent):
    event_type: str = 'service_status'
    status: str
    status_text: Optional[str] = None
    outcome: Optional[str] = None
    provider: Optional[str] = None
    retryable: Optional[bool] = None
    reason: Optional[str] = None

    def to_json(self):
        payload = self.model_dump(mode='json', exclude_none=True)
        payload['type'] = payload.pop('event_type')
        return payload


class FreemiumThresholdReachedEvent(MessageEvent):
    event_type: str = 'freemium_threshold_reached'
    remaining_seconds: int
    action: str


class FairUseReviewRequestedEvent(MessageEvent):
    event_type: str = 'fair_use_review_requested'
    review_id: str
    trigger: str
    window_speech_ms: dict[str, int]
    thresholds_ms: dict[str, int]
    classifier_contract: str
    requested_at: str
    expires_at: str


class FairUseManagedCloudExhaustedEvent(MessageEvent):
    event_type: str = 'fair_use_managed_cloud_exhausted'
    resets_at: str
    case_ref: str = ''
    support_email: str = 'support@heyintentive.com'
