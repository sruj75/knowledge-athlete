import utils.observability as observability


def test_tracing_survives_without_product_feedback_export(monkeypatch):
    monkeypatch.delenv("LANGSMITH_API_KEY", raising=False)
    monkeypatch.delenv("LANGCHAIN_API_KEY", raising=False)

    assert observability.get_chat_tracer_callbacks(run_name="chat.agentic.stream") == []
    assert not hasattr(observability, "submit_langsmith_feedback")
