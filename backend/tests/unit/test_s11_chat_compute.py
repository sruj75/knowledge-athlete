from contextlib import nullcontext
from unittest.mock import MagicMock, patch

import routers.chat_sessions as chat_sessions
import utils.llm.clients as llm_clients
from routers.chat_sessions import (
    GenerateTitleRequest,
    InitialMessageRequest,
    create_initial_message,
    generate_session_title,
)


def _llm_response(text: str) -> MagicMock:
    llm = MagicMock()
    llm.bind.return_value = llm
    llm.invoke.return_value = MagicMock(content=text)
    return llm


def test_initial_message_is_stateless():
    request = InitialMessageRequest(
        profile_text="Srujan builds tools for thought.",
        memories=["Prefers concise plans", "Keeps chat history local"],
    )
    llm = _llm_response("Welcome back — what are we building today?")

    with (
        patch("routers.chat_sessions.get_workload_client", return_value=llm) as get_workload_client,
        patch("routers.chat_sessions.track_usage", return_value=nullcontext()),
    ):
        result = create_initial_message(request, uid="owner-a")

    assert result == {"message": "Welcome back — what are we building today?"}
    get_workload_client.assert_called_once_with("chat_greeting")
    assert not hasattr(chat_sessions, "chat_db")
    prompt = llm.invoke.call_args.args[0]
    assert "Srujan builds tools for thought." in prompt
    assert "Keeps chat history local" in prompt
    assert "session" not in result
    assert "message_id" not in result


def test_generate_title_is_stateless():
    request = GenerateTitleRequest(
        user_text="How should the local chat catalog handle titles?",
        assistant_text="Use compare-and-set so a manual rename always wins.",
    )
    llm = _llm_response("Local Catalog Title Precedence Explained")

    with (
        patch("routers.chat_sessions.get_workload_client", return_value=llm) as get_workload_client,
        patch("routers.chat_sessions.track_usage", return_value=nullcontext()),
    ):
        result = generate_session_title(request, uid="owner-a")

    assert result == {"title": "Local Catalog Title Precedence Explained"}
    get_workload_client.assert_called_once_with("session_titles")
    assert not hasattr(chat_sessions, "chat_db")
    prompt = llm.invoke.call_args.args[0]
    assert request.user_text in prompt
    assert request.assistant_text in prompt
    assert "session_id" not in prompt


def test_chat_compute_inputs_are_bounded():
    too_long = "x" * 12_001

    try:
        GenerateTitleRequest(user_text=too_long, assistant_text="answer")
    except ValueError:
        pass
    else:
        raise AssertionError("unbounded title input was accepted")

    try:
        InitialMessageRequest(profile_text="p", memories=["m"] * 21)
    except ValueError:
        pass
    else:
        raise AssertionError("unbounded greeting memories were accepted")


def test_chat_compute_rejects_provider_output_beyond_response_contract():
    request = InitialMessageRequest(profile_text="", memories=[])
    llm = _llm_response("x" * (chat_sessions._GREETING_MAX_CHARACTERS + 1))

    with (
        patch("routers.chat_sessions.get_workload_client", return_value=llm),
        patch("routers.chat_sessions.track_usage", return_value=nullcontext()),
    ):
        try:
            create_initial_message(request, uid="owner-a")
        except chat_sessions.HTTPException as error:
            assert error.status_code == 502
        else:
            raise AssertionError("unbounded greeting output was accepted")


def test_output_token_limit_uses_native_gemini_parameter():
    direct_gemini = MagicMock()
    direct_gemini.bind.return_value = direct_gemini
    assert llm_clients.bind_llm_output_token_limit("session_titles", direct_gemini, 32) is direct_gemini
    direct_gemini.bind.assert_called_once_with(max_output_tokens=32)
