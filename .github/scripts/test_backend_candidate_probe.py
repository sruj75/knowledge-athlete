#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
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


def sse_event(payload: object) -> bytes:
    return f"data: {json.dumps(payload)}\n".encode()


class BackendCandidateProbeTests(unittest.TestCase):
    def test_process_health_stays_shallow_and_compatibility_is_independent(self) -> None:
        self.assertEqual(PROBE.validate_process_health({"status": "ok"}), {"status": "ok"})
        with self.assertRaises(PROBE.ProbeError):
            PROBE.validate_process_health({"status": "healthy"})

        summary = PROBE.validate_compatibility(
            {"status": "healthy", "service": "omi-backend", "chat_contract_version": "2"},
            expected_contract_version="2",
        )
        self.assertEqual(summary, {"status": "healthy", "service": "omi-backend", "chat_contract_version": "2"})

        for mutation in ({"service": "omi-desktop-backend"}, {"chat_contract_version": "1"}):
            with self.assertRaises(PROBE.ProbeError):
                PROBE.validate_compatibility(
                    {
                        "status": "healthy",
                        "service": "omi-backend",
                        "chat_contract_version": "2",
                        **mutation,
                    },
                    expected_contract_version="2",
                )

    def test_candidate_uses_v1_health_and_never_calls_retired_readiness_routes(self) -> None:
        requests: list[str] = []

        def request_json(url: str) -> object:
            requests.append(url)
            if url.endswith("/v1/health"):
                return {"status": "ok"}
            return {"status": "healthy", "service": "omi-backend", "chat_contract_version": "2"}

        chat_results = [
            PROBE.ChatResult("first", 0.1, 0.01, True),
            PROBE.ChatResult("second", 0.1, 0.01, True),
        ]
        with mock.patch.object(PROBE, "_request_json", side_effect=request_json), mock.patch.object(
            PROBE, "_require_firestore_read", return_value={"status": "passed"}
        ), mock.patch.object(PROBE, "_chat_request", side_effect=chat_results):
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

        self.assertEqual(requests, ["https://candidate.example/v1/health", "https://candidate.example/"])
        self.assertEqual(evidence["process_health"], {"status": "ok"})
        self.assertEqual(evidence["target"]["source_sha"], SHA)
        self.assertNotIn("readiness", evidence)

    def test_sse_parser_requires_native_gemini_text_usage_and_terminal_candidate(self) -> None:
        answer, terminal, _, saw_usage = PROBE.parse_sse(
            [
                sse_event(
                    {
                        "candidates": [
                            {
                                "content": {
                                    "role": "model",
                                    "parts": [{"text": "hello"}, {"thought": True, "text": "hidden"}],
                                },
                                "finishReason": "STOP",
                            }
                        ]
                    }
                ),
                sse_event({"usageMetadata": {"promptTokenCount": 2}}),
            ],
            stage="chat",
        )
        self.assertEqual(answer, "hello")
        self.assertTrue(terminal)
        self.assertTrue(saw_usage)

    def test_chat_request_uses_native_gemini_contract_and_firebase_bearer(self) -> None:
        requests = []

        class Response:
            headers = {"x-omi-chat-contract-version": "2"}

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def __iter__(self):
                return iter(
                    [
                        sse_event(
                            {
                                "candidates": [
                                    {
                                        "content": {"parts": [{"text": "hello"}]},
                                        "finishReason": "STOP",
                                    }
                                ],
                                "usageMetadata": {"promptTokenCount": 2},
                            }
                        )
                    ]
                )

        def urlopen(request, *, timeout):
            requests.append((request, timeout))
            return Response()

        with mock.patch.object(PROBE.urllib.request, "urlopen", side_effect=urlopen):
            result = PROBE._chat_request(
                "https://candidate.example",
                token="firebase-token",
                contract_version="2",
                messages=[
                    {"role": "user", "content": "first"},
                    {"role": "assistant", "content": "second"},
                ],
                stage="chat",
            )

        request, _ = requests[0]
        payload = json.loads(request.data)
        self.assertEqual(
            request.full_url,
            "https://candidate.example/v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse",
        )
        self.assertEqual(request.get_header("Authorization"), "Bearer firebase-token")
        self.assertIsNone(request.get_header("x-goog-api-key"))
        self.assertEqual([content["role"] for content in payload["contents"]], ["user", "model"])
        self.assertEqual(payload["generationConfig"]["thinkingConfig"], {"thinkingLevel": "LOW"})
        self.assertNotIn("messages", payload)
        self.assertEqual(result.answer, "hello")

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
