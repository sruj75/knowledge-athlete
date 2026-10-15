#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import ast
import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name("backend_candidate_probe.py")
SPEC = importlib.util.spec_from_file_location("backend_candidate_probe", SCRIPT)
assert SPEC and SPEC.loader
PROBE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PROBE
SPEC.loader.exec_module(PROBE)

SHA = "7fd2aac1f5e1d6c12a8c7b641e6fb532e2324e6c"
ROOT = Path(__file__).resolve().parents[2]


def current_conversation_contract():
    """Read actual route/model declarations and execute the real SSE encoder only."""
    source = ROOT / "backend/routers/desktop_conversation.py"
    tree = ast.parse(source.read_text(encoding="utf-8"))
    paths = {}
    for function in tree.body:
        if isinstance(function, ast.AsyncFunctionDef) and function.name in {
            "bootstrap_session",
            "respond",
        }:
            decorator = function.decorator_list[0]
            paths[function.name] = ast.literal_eval(decorator.args[0])
    encoder = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "_sse")
    namespace = {"json": json}
    exec(
        compile(ast.Module(body=[encoder], type_ignores=[]), str(source), "exec"),
        namespace,
    )
    models = ast.parse((ROOT / "backend/models/desktop_conversation.py").read_text(encoding="utf-8"))
    required = {}
    allowed = {}
    for model in models.body:
        if isinstance(model, ast.ClassDef) and model.name in {
            "ConversationSessionRequest",
            "ConversationRespondRequest",
        }:
            fields = [node for node in model.body if isinstance(node, ast.AnnAssign)]
            allowed[model.name] = {node.target.id for node in fields}
            required[model.name] = {node.target.id for node in fields if node.value is None}
    return paths, namespace["_sse"], required, allowed


class CurrentConversationCandidateTests(unittest.TestCase):
    def test_real_probe_uses_current_routes_one_pinned_prompt_and_two_tool_free_turns(
        self,
    ):
        paths, encode, required, allowed = current_conversation_contract()
        prompt = {
            "name": "intentive-live-system",
            "version": "7",
            "source": "langfuse",
            "text": "Hermetic prompt must not enter evidence.",
        }
        prompt["sha256"] = hashlib.sha256(prompt["text"].encode()).hexdigest()
        prompt_ref = {key: value for key, value in prompt.items() if key != "text"}
        calls = []

        class Response:
            headers = {}
            status = 200

            def __init__(self, body):
                self.body = body

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, size=-1):
                return self.body[:size] if size >= 0 else self.body

            def __iter__(self):
                return iter(self.body.splitlines(keepends=True))

        def urlopen(request, *, timeout):
            path = PROBE.urllib.parse.urlsplit(request.full_url).path
            payload = json.loads(request.data) if request.data else None
            calls.append((request.get_method(), path, payload))
            self.assertLessEqual(timeout, PROBE.HTTP_TIMEOUT_SECONDS)
            if path == "/v1/health":
                return Response(b'{"status":"ok"}')
            if path == "/":
                return Response(b'{"status":"healthy","service":"backend","chat_contract_version":"2"}')
            if path == "/updates/latest":
                return Response(b'{}')
            self.assertIn(
                path,
                paths.values(),
                f"probe calls a route absent from the current conversation router: {path}",
            )
            self.assertEqual(
                request.get_header("Authorization"),
                "Bearer fixture-token-must-not-leak",
            )
            model = "ConversationSessionRequest" if path == paths["bootstrap_session"] else "ConversationRespondRequest"
            self.assertTrue(required[model] <= payload.keys())
            self.assertTrue(payload.keys() <= allowed[model])
            if path == paths["bootstrap_session"]:
                return Response(
                    json.dumps(
                        {
                            "conversation_id": payload["conversation_id"],
                            "prompt": prompt,
                        }
                    ).encode()
                )
            self.assertEqual(payload["prompt_ref"], prompt_ref)
            self.assertNotIn("tools", payload)
            self.assertIn("another user turn", payload["message"])
            self.assertIn("do not call end_conversation", payload["message"])
            answer = "first answer" if not payload["history"] else "follow-up answer"
            return Response(
                encode("text_delta", {"text": answer})
                + encode(
                    "done",
                    {
                        "end_conversation": False,
                        "prompt_ref": prompt_ref,
                        "usage": {
                            "input_tokens": 3,
                            "cached_input_tokens": 0,
                            "output_tokens": 2,
                            "thinking_tokens": 0,
                        },
                    },
                )
            )

        with mock.patch.object(PROBE.urllib.request, "urlopen", side_effect=urlopen):
            evidence = PROBE.probe_candidate(
                base_url="https://candidate.example",
                token="fixture-token-must-not-leak",
                expected_contract_version="2",
                source_sha=SHA,
                expected_revision="backend-abc",
                expected_image_digest="sha256:" + "a" * 64,
                candidate_tag="candidate",
                workflow_run_id="123",
            )
        sessions = [body for _, path, body in calls if path == paths["bootstrap_session"]]
        turns = [body for _, path, body in calls if path == paths["respond"]]
        self.assertEqual(len(sessions), 1)
        self.assertEqual(len(turns), 2)
        self.assertEqual(
            [turn["conversation_id"] for turn in turns],
            [sessions[0]["conversation_id"]] * 2,
        )
        self.assertNotEqual(turns[0]["turn_id"], turns[1]["turn_id"])
        self.assertEqual(
            turns[1]["history"],
            [
                {"role": "user", "text": turns[0]["message"]},
                {"role": "assistant", "text": "first answer"},
            ],
        )
        self.assertEqual(evidence["status"], "passed")
        self.assertEqual(evidence["target"]["source_sha"], SHA)
        for private in (
            "fixture-token-must-not-leak",
            prompt["text"],
            "first answer",
            "follow-up answer",
        ):
            self.assertNotIn(private, json.dumps(evidence))


def sse_events(*events) -> list[bytes]:
    _, encode, _, _ = current_conversation_contract()
    return b"".join(encode(name, payload) for name, payload in events).splitlines(keepends=True)


class BackendCandidateProbeTests(unittest.TestCase):
    def test_process_health_stays_shallow_and_compatibility_is_independent(
        self,
    ) -> None:
        self.assertEqual(PROBE.validate_process_health({"status": "ok"}), {"status": "ok"})
        with self.assertRaises(PROBE.ProbeError):
            PROBE.validate_process_health({"status": "healthy"})

        summary = PROBE.validate_compatibility(
            {"status": "healthy", "service": "backend", "chat_contract_version": "2"},
            expected_contract_version="2",
        )
        self.assertEqual(
            summary,
            {"status": "healthy", "service": "backend", "chat_contract_version": "2"},
        )

        for mutation in (
            {"service": "omi-desktop-backend"},
            {"chat_contract_version": "1"},
        ):
            with self.assertRaises(PROBE.ProbeError):
                PROBE.validate_compatibility(
                    {
                        "status": "healthy",
                        "service": "backend",
                        "chat_contract_version": "2",
                        **mutation,
                    },
                    expected_contract_version="2",
                )

    def test_candidate_uses_v1_health_and_never_calls_retired_readiness_routes(
        self,
    ) -> None:
        requests: list[str] = []

        def request_json(url: str) -> object:
            requests.append(url)
            if url.endswith("/v1/health"):
                return {"status": "ok"}
            return {
                "status": "healthy",
                "service": "backend",
                "chat_contract_version": "2",
            }

        chat_results = [
            PROBE.ChatResult("first", 0.1, 0.01, True),
            PROBE.ChatResult("second", 0.1, 0.01, True),
        ]
        with mock.patch.object(PROBE, "_request_json", side_effect=request_json), mock.patch.object(
            PROBE, "_require_firestore_read", return_value={"status": "passed"}
        ), mock.patch.object(PROBE, "_bootstrap_conversation", return_value={}), mock.patch.object(
            PROBE, "_chat_request", side_effect=chat_results
        ):
            evidence = PROBE.probe_candidate(
                base_url="https://candidate.example",
                token="firebase-token",
                expected_contract_version="2",
                source_sha=SHA,
                expected_revision="backend-abc",
                expected_image_digest="sha256:" + "a" * 64,
                candidate_tag="candidate",
                workflow_run_id="123",
            )

        self.assertEqual(
            requests,
            ["https://candidate.example/v1/health", "https://candidate.example/"],
        )
        self.assertEqual(evidence["process_health"], {"status": "ok"})
        self.assertEqual(evidence["target"]["source_sha"], SHA)
        self.assertNotIn("readiness", evidence)

    def test_sse_parser_requires_typed_text_and_terminal_usage(self) -> None:
        answer, terminal, _, saw_usage = PROBE.parse_sse(
            sse_events(
                ("text_delta", {"text": "hello"}),
                (
                    "done",
                    {
                        "end_conversation": False,
                        "usage": {
                            "input_tokens": 2,
                            "cached_input_tokens": 0,
                            "output_tokens": 1,
                            "thinking_tokens": 0,
                        },
                    },
                ),
            ),
            stage="chat",
        )
        self.assertEqual(answer, "hello")
        self.assertTrue(terminal)
        self.assertTrue(saw_usage)

    def test_stream_rejects_missing_completion_changed_prompt_and_nonconversation_events(
        self,
    ):
        cases = [
            [("text_delta", {"text": "hello"})],
            [
                ("text_delta", {"text": "hello"}),
                ("done", {"end_conversation": False, "prompt_ref": {"version": "8"}}),
            ],
            [("tool_call", {"name": "arbitrary_execution"})],
            [("error", {"code": "private-provider-message-must-not-leak"})],
            [("text_delta", {"text": "hello"}), ("done", {"end_conversation": True})],
            [("done", {"end_conversation": False, "prompt_ref": {"version": "7"}})],
        ]
        for events in cases:
            with self.subTest(events=events), self.assertRaises(PROBE.ProbeError) as caught:
                PROBE.parse_sse(
                    sse_events(*events),
                    stage="chat",
                    expected_prompt_ref={"version": "7"},
                )
            self.assertNotIn("private-provider-message", str(caught.exception))

    def test_terminal_usage_must_have_all_nonnegative_exclusive_buckets(self):
        valid = {
            "input_tokens": 2,
            "cached_input_tokens": 0,
            "output_tokens": 1,
            "thinking_tokens": 0,
        }
        for usage in (
            None,
            {},
            {**valid, "thinking_tokens": -1},
            {**valid, "input_tokens": True},
        ):
            with self.subTest(usage=usage):
                _, _, _, saw_usage = PROBE.parse_sse(
                    sse_events(
                        ("text_delta", {"text": "hello"}),
                        ("done", {"end_conversation": False, "usage": usage}),
                    ),
                    stage="chat",
                )
                self.assertFalse(saw_usage)

    def test_stream_bounds_first_event_total_time_bytes_text_and_truncation(self):
        for attribute, limit, events in (
            ("MAX_RESPONSE_BYTES", 8, sse_events(("text_delta", {"text": "hello"}))),
            ("MAX_TEXT_CHARS", 2, sse_events(("text_delta", {"text": "hello"}))),
        ):
            with mock.patch.object(PROBE, attribute, limit), self.assertRaises(PROBE.ProbeError):
                PROBE.parse_sse(events, stage="chat")
        with self.assertRaisesRegex(PROBE.ProbeError, "truncated"):
            PROBE.parse_sse([b'event: text_delta\n', b'data: {"text":"hello"}\n'], stage="chat")
        events = sse_events(("text_delta", {"text": "hello"}))
        with mock.patch.object(PROBE.time, "monotonic", return_value=21), self.assertRaisesRegex(
            PROBE.ProbeError, "first event"
        ):
            PROBE.parse_sse(events, stage="chat", started_at=0, max_elapsed_seconds=70)
        with mock.patch.object(PROBE.time, "monotonic", return_value=71), self.assertRaisesRegex(
            PROBE.ProbeError, "response budget"
        ):
            PROBE.parse_sse(events, stage="chat", started_at=0, max_elapsed_seconds=70)

    def test_stream_rejects_late_events_after_done(self):
        with self.assertRaisesRegex(PROBE.ProbeError, "after terminal"):
            PROBE.parse_sse(
                sse_events(
                    ("text_delta", {"text": "hello"}),
                    ("done", {"end_conversation": False}),
                    ("text_delta", {"text": "late"}),
                ),
                stage="chat",
            )

    def test_bootstrap_validates_conversation_and_prompt_receipt_without_exporting_text(
        self,
    ):
        text = "private-prompt-must-not-leak"
        valid = {
            "name": "intentive-live-system",
            "version": "7",
            "source": "langfuse",
            "text": text,
            "sha256": hashlib.sha256(text.encode()).hexdigest(),
        }

        class Response:
            def __init__(self, payload):
                self.body = json.dumps(payload).encode()

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, size=-1):
                return self.body[:size] if size >= 0 else self.body

        good = {"conversation_id": "probe-1", "prompt": valid}
        with mock.patch.object(PROBE.urllib.request, "urlopen", return_value=Response(good)):
            reference = PROBE._bootstrap_conversation(
                "https://candidate.example", token="fixture", conversation_id="probe-1"
            )
        self.assertNotIn("text", reference)
        mutations = [
            {**good, "conversation_id": "other"},
            {**good, "prompt": {**valid, "sha256": "0" * 64}},
            {**good, "prompt": {**valid, "source": "fallback"}},
            {**good, "prompt": {**valid, "name": "other-agent"}},
            {**good, "prompt": {**valid, "text": "\ud800"}},
        ]
        for payload in mutations:
            with self.subTest(payload=payload), mock.patch.object(
                PROBE.urllib.request, "urlopen", return_value=Response(payload)
            ), self.assertRaises(PROBE.ProbeError) as caught:
                PROBE._bootstrap_conversation(
                    "https://candidate.example",
                    token="fixture",
                    conversation_id="probe-1",
                )
            self.assertNotIn(text, str(caught.exception))

    def test_candidate_rejects_missing_terminal_usage(self):
        with mock.patch.object(
            PROBE,
            "_request_json",
            side_effect=[
                {"status": "ok"},
                {
                    "status": "healthy",
                    "service": "backend",
                    "chat_contract_version": "2",
                },
            ],
        ), mock.patch.object(PROBE, "_require_firestore_read", return_value={"status": "passed"}), mock.patch.object(
            PROBE, "_bootstrap_conversation", return_value={}
        ), mock.patch.object(
            PROBE,
            "_chat_request",
            return_value=PROBE.ChatResult("hello", 0.1, 0.01, False),
        ), self.assertRaisesRegex(
            PROBE.ProbeError, "terminal usage"
        ):
            PROBE.probe_candidate(
                base_url="https://candidate.example",
                token="fixture",
                expected_contract_version="2",
                source_sha=SHA,
                expected_revision="backend-abc",
                expected_image_digest="sha256:" + "a" * 64,
                candidate_tag="candidate",
                workflow_run_id="123",
            )

    def test_token_file_must_be_regular_mode_0600(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            path.write_text("abc.def.ghi", encoding="utf-8")
            path.chmod(0o600)
            if os.name == "nt":
                with self.assertRaisesRegex(PROBE.ProbeError, "mode-0600"):
                    PROBE._valid_token(path)
                return
            self.assertEqual(PROBE._valid_token(path), "abc.def.ghi")
            path.chmod(0o644)
            with self.assertRaisesRegex(PROBE.ProbeError, "mode-0600"):
                PROBE._valid_token(path)

    def test_canonical_workflows_run_chat_and_provider_candidate_probes(self) -> None:
        root = Path(__file__).resolve().parents[2]
        for relative in ("gcp_backend_auto_dev.yml", "gcp_backend.yml"):
            text = (root / ".github/workflows" / relative).read_text(encoding="utf-8")
            self.assertIn("backend_candidate_probe.py", text)
            self.assertIn("voice-provider-probe.sh", text)
            self.assertNotIn("/health", text)
            self.assertNotIn("/ready", text)


if __name__ == "__main__":
    unittest.main()
