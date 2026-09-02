"""
Fake LLM HTTP server using pytest-httpserver.

Provides deterministic responses for retained Gemini LLM endpoints.
Every request returns the same structured JSON response
so tests are fully reproducible.
"""

import json

# Deterministic LLM responses — these are returned for every LLM call
DEFAULT_STRUCTURED_RESPONSE = {
    "title": "Test Conversation Title",
    "overview": "A test conversation about project planning and action items.",
    "emoji": "🧠",
    "category": "other",
    "action_items": [
        {
            "description": "Review the quarterly report",
            "completed": False,
            "created_at": "2025-01-15T10:00:00Z",
        },
        {
            "description": "Schedule follow-up meeting",
            "completed": False,
            "created_at": "2025-01-15T10:00:00Z",
        },
    ],
    "events": [],
}

DEFAULT_SUMMARY = "Discussion about Q4 planning and deliverables."


def make_gemini_response(content: str = None) -> dict:
    """Build a fake Gemini generateContent response."""
    if content is None:
        content = json.dumps(DEFAULT_STRUCTURED_RESPONSE)
    return {
        "candidates": [
            {
                "content": {"role": "model", "parts": [{"text": content}]},
                "finishReason": "STOP",
            }
        ],
        "usageMetadata": {"promptTokenCount": 100, "candidatesTokenCount": 50, "totalTokenCount": 150},
    }


def configure_llm_fakes(httpserver):
    """
    Register deterministic LLM handlers on a pytest-httpserver instance.

    Retained LLM endpoints return the same structured output so conversation
    processing produces predictable results.
    """

    for model in ("gemini-3.7-flash", "gemini-2.5-flash-lite"):
        httpserver.expect_request(f"/v1beta/models/{model}:generateContent").respond_with_json(
            make_gemini_response(), status=200, content_type="application/json"
        )


def configure_llm_error(httpserver, status_code: int = 500):
    """
    Configure the LLM fake server to return errors.
    Used by failure-mode tests to verify graceful degradation.
    """
    # Clear existing handlers and add error responses
    for endpoint in [
        "/v1beta/models/gemini-3.7-flash:generateContent",
        "/v1beta/models/gemini-2.5-flash-lite:generateContent",
    ]:
        httpserver.expect_request(endpoint).respond_with_json(
            {"error": {"message": "LLM service unavailable", "type": "server_error"}},
            status=status_code,
            content_type="application/json",
        )
