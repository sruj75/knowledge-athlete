import utils.observability as observability
from types import SimpleNamespace
from uuid import UUID


def test_tracing_survives_without_product_feedback_export(monkeypatch):
    monkeypatch.delenv("LANGSMITH_API_KEY", raising=False)
    monkeypatch.delenv("LANGCHAIN_API_KEY", raising=False)

    assert observability.get_chat_tracer_callbacks(run_name="chat.agentic.stream") == []
    assert not hasattr(observability, "submit_langsmith_feedback")


def test_agentic_message_binds_to_the_actual_current_langsmith_run():
    expected = UUID("12345678-1234-5678-1234-567812345678")
    callback_data = {}

    run_id = observability.bind_current_langsmith_run(
        callback_data,
        run_tree_getter=lambda: SimpleNamespace(id=expected),
    )

    assert run_id == str(expected)
    assert callback_data == {"langsmith_run_id": str(expected)}


def test_agentic_message_omits_a_fake_run_id_when_no_trace_exists():
    callback_data = {"langsmith_run_id": "stale"}

    run_id = observability.bind_current_langsmith_run(callback_data, run_tree_getter=lambda: None)

    assert run_id is None
    assert "langsmith_run_id" not in callback_data
