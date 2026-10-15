#!/usr/bin/env python3
"""Prove one deployed managed realtime-provider turn without exposing credentials.

The probe resolves pinned conversation instructions and mints a short-lived
provider credential from the deployed desktop backend, opens the provider's
direct WebSocket path with those instructions, commits a fixed harmless text
fixture, and waits for the provider's terminal response event. It accepts
only a mode-0600 Firebase ID-token file so callers never put a bearer token in a
command line, environment dump, or log.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import socket
import ssl
import stat
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence
from uuid import uuid4

MINT_PATH = "/v2/realtime/session"
SESSION_PATH = "/v1/conversation/session"
GEMINI_URL_PREFIX = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained"
GEMINI_TOKEN_PREFIX = "auth_tokens/"
PROBE_INPUT = "Reply with exactly OMI_PROVIDER_PROBE_OK."
MAX_TOKEN_CHARS = 8192
MAX_HTTP_RESPONSE_BYTES = 128 * 1024
MAX_HANDSHAKE_BYTES = 32 * 1024
MAX_WEBSOCKET_MESSAGE_BYTES = 1024 * 1024
DEFAULT_TIMEOUT_SECONDS = 25.0


@dataclass(frozen=True)
class ProbeConfig:
    base_url: str
    bearer_token: str | None
    timeout_seconds: float


@dataclass(frozen=True)
class ProviderSession:
    token: str
    prompt_text: str


class ProbeFailure(RuntimeError):
    def __init__(self, failure_class: str, *, retryable: bool = False):
        super().__init__(failure_class)
        self.failure_class = failure_class
        self.retryable = retryable


def _read_bearer_token(path: Path | None) -> str | None:
    if path is None:
        return None
    descriptor = -1
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        file_stat = os.fstat(descriptor)
        if not stat.S_ISREG(file_stat.st_mode) or file_stat.st_mode & 0o077:
            return None
        with os.fdopen(descriptor, encoding="utf-8") as handle:
            descriptor = -1
            token = handle.read().strip()
    except (OSError, UnicodeDecodeError):
        return None
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    return token if 0 < len(token) <= MAX_TOKEN_CHARS else None


def _normalize_base_url(value: str) -> str | None:
    try:
        parsed = urllib.parse.urlsplit(value.strip())
    except ValueError:
        return None
    if parsed.scheme != "https" or not parsed.netloc or parsed.query or parsed.fragment:
        return None
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, parsed.path.rstrip("/"), "", ""))


def config_from_args(args: argparse.Namespace) -> ProbeConfig:
    return ProbeConfig(
        base_url=_normalize_base_url(args.backend_base_url) or "",
        bearer_token=_read_bearer_token(args.bearer_token_file),
        timeout_seconds=args.timeout_seconds,
    )


def _emit(step: str, status: str, failure_class: str) -> None:
    print(f"provider=gemini step={step} status={status} class={failure_class}", flush=True)


def _classify_http_error(status_code: int) -> ProbeFailure:
    # Match desktop mint (CredentialHealthManager.classifyHTTPFailure): upstream 429 is transient.
    if status_code == 429:
        return ProbeFailure("mint_http_4xx", retryable=True)
    if 400 <= status_code < 500:
        return ProbeFailure("mint_http_4xx")
    if 500 <= status_code < 600:
        return ProbeFailure("upstream_5xx", retryable=True)
    return ProbeFailure("mint_http_unexpected")


def _post_backend_json(config: ProbeConfig, path: str, payload: dict[str, Any], schema_error: str) -> dict[str, Any]:
    if not config.base_url or not config.bearer_token:
        raise ProbeFailure("configuration")
    request = urllib.request.Request(
        f"{config.base_url}{path}",
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {config.bearer_token}",
            "Content-Type": "application/json",
        },
    )
    payload_bytes = b""
    try:
        with urllib.request.urlopen(request, timeout=config.timeout_seconds) as response:
            if int(response.status) < 200 or int(response.status) >= 300:
                raise _classify_http_error(int(response.status))
            payload_bytes = response.read(MAX_HTTP_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as error:
        raise _classify_http_error(error.code) from error
    except (socket.timeout, TimeoutError):
        raise ProbeFailure("timeout", retryable=True)
    except (urllib.error.URLError, OSError, ValueError):
        raise ProbeFailure("mint_transport")

    if len(payload_bytes) > MAX_HTTP_RESPONSE_BYTES:
        raise ProbeFailure(schema_error)
    try:
        payload = json.loads(payload_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ProbeFailure(schema_error)
    finally:
        payload_bytes = b""
    if not isinstance(payload, dict):
        raise ProbeFailure(schema_error)
    return payload


def _prompt_receipt(value: object, schema_error: str) -> dict[str, str]:
    fields = ("name", "version", "source", "sha256", "text")
    if not isinstance(value, dict) or any(not isinstance(value.get(key), str) for key in fields):
        raise ProbeFailure(schema_error)
    receipt = {key: value[key] for key in fields}
    try:
        prompt_hash = hashlib.sha256(receipt["text"].encode("utf-8")).hexdigest()
    except UnicodeError as error:
        raise ProbeFailure(schema_error) from error
    version_valid = (
        receipt["source"] == "langfuse" and re.fullmatch(r"[1-9][0-9]{0,9}", receipt["version"]) is not None
    ) or (receipt["source"] == "fallback" and receipt["version"] == "conversation-v1")
    if (
        receipt["name"] != "intentive-live-system"
        or not version_valid
        or not 1 <= len(receipt["text"]) <= 32000
        or prompt_hash != receipt["sha256"]
    ):
        raise ProbeFailure(schema_error)
    return receipt


def _mint_provider_session(config: ProbeConfig) -> ProviderSession:
    conversation_id = f"provider-probe-{uuid4()}"
    bootstrap = _post_backend_json(config, SESSION_PATH, {"conversation_id": conversation_id}, "session_schema")
    if bootstrap.get("conversation_id") != conversation_id:
        raise ProbeFailure("session_schema")
    receipt = _prompt_receipt(bootstrap.get("prompt"), "session_schema")
    reference = {key: value for key, value in receipt.items() if key != "text"}
    payload = _post_backend_json(
        config, MINT_PATH, {"conversation_id": conversation_id, "prompt_ref": reference}, "mint_schema"
    )
    if _prompt_receipt(payload.get("prompt"), "mint_schema") != receipt:
        raise ProbeFailure("mint_schema")
    token = payload.get("token")
    valid = payload.get("provider") == "gemini" and isinstance(token, str) and token.startswith(GEMINI_TOKEN_PREFIX)
    if not valid or len(token) > MAX_TOKEN_CHARS:
        raise ProbeFailure("mint_schema")
    return ProviderSession(token=token, prompt_text=receipt["text"])


class ProviderWebSocket:
    def __init__(self, url: str, headers: dict[str, str], timeout_seconds: float):
        self.url = url
        self.headers = headers
        self.timeout_seconds = timeout_seconds
        self._socket: socket.socket | ssl.SSLSocket | None = None
        self._closed = False
        self._fragment_opcode: int | None = None
        self._fragments: list[bytes] = []

    def connect(self) -> None:
        parsed = urllib.parse.urlsplit(self.url)
        if parsed.scheme != "wss" or not parsed.hostname:
            raise ProbeFailure("connect_failed")
        try:
            tcp_socket = socket.create_connection((parsed.hostname, parsed.port or 443), self.timeout_seconds)
            tls_socket = ssl.create_default_context().wrap_socket(tcp_socket, server_hostname=parsed.hostname)
            tls_socket.settimeout(self.timeout_seconds)
            self._socket = tls_socket
            self._perform_handshake(parsed)
        except ProbeFailure:
            self.close()
            raise
        except (socket.timeout, TimeoutError) as error:
            self.close()
            raise ProbeFailure("timeout", retryable=True) from error
        except (OSError, ssl.SSLError, ValueError) as error:
            self.close()
            raise ProbeFailure("connect_failed") from error

    def _perform_handshake(self, parsed: urllib.parse.SplitResult) -> None:
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"
        host = parsed.hostname or ""
        if parsed.port and parsed.port != 443:
            host = f"{host}:{parsed.port}"
        websocket_key = base64.b64encode(os.urandom(16)).decode("ascii")
        lines = [
            f"GET {path} HTTP/1.1",
            f"Host: {host}",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Key: {websocket_key}",
            "Sec-WebSocket-Version: 13",
        ]
        for name, value in self.headers.items():
            if "\r" in name or "\n" in name or "\r" in value or "\n" in value:
                raise ProbeFailure("connect_failed")
            lines.append(f"{name}: {value}")
        self._send_raw(("\r\n".join(lines) + "\r\n\r\n").encode("ascii"))
        raw_response = self._read_until_headers_complete()
        try:
            header_text = raw_response.decode("iso-8859-1")
            status_line = header_text.split("\r\n", 1)[0]
            status_code = int(status_line.split()[1])
        except (UnicodeDecodeError, IndexError, ValueError):
            raise ProbeFailure("connect_failed")
        if status_code != 101:
            if 500 <= status_code < 600:
                raise ProbeFailure("upstream_5xx", retryable=True)
            if 400 <= status_code < 500:
                raise ProbeFailure("connect_http_4xx")
            raise ProbeFailure("connect_failed")

    def _read_until_headers_complete(self) -> bytes:
        response = bytearray()
        while b"\r\n\r\n" not in response:
            if len(response) >= MAX_HANDSHAKE_BYTES:
                raise ProbeFailure("connect_failed")
            response.extend(self._recv_exact(1))
        return bytes(response)

    def _send_raw(self, payload: bytes) -> None:
        if self._socket is None:
            raise ProbeFailure("connect_failed")
        self._socket.sendall(payload)

    def _recv_exact(self, size: int) -> bytes:
        if self._socket is None:
            raise ProbeFailure("connect_failed")
        chunks: list[bytes] = []
        remaining = size
        while remaining:
            chunk = self._socket.recv(remaining)
            if not chunk:
                raise ProbeFailure("connect_failed")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def send_json(self, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        if len(encoded) > MAX_WEBSOCKET_MESSAGE_BYTES:
            raise ProbeFailure("commit_failed")
        try:
            self._send_frame(0x1, encoded)
        except (socket.timeout, TimeoutError) as error:
            raise ProbeFailure("timeout", retryable=True) from error
        except (OSError, ssl.SSLError) as error:
            raise ProbeFailure("provider_transport") from error

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        length = len(payload)
        frame = bytearray([0x80 | opcode])
        if length < 126:
            frame.append(0x80 | length)
        elif length < 65536:
            frame.append(0x80 | 126)
            frame.extend(struct.pack("!H", length))
        else:
            frame.append(0x80 | 127)
            frame.extend(struct.pack("!Q", length))
        mask = os.urandom(4)
        frame.extend(mask)
        frame.extend(value ^ mask[index % 4] for index, value in enumerate(payload))
        self._send_raw(bytes(frame))

    def receive_json(self) -> dict[str, Any]:
        while True:
            opcode, finished, payload = self._receive_frame()
            if opcode == 0x8:
                raise ProbeFailure("connect_failed")
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x0:
                if self._fragment_opcode is None:
                    raise ProbeFailure("provider_event_error")
                self._fragments.append(payload)
                if not finished:
                    continue
                opcode = self._fragment_opcode
                payload = b"".join(self._fragments)
                self._fragment_opcode = None
                self._fragments.clear()
            elif not finished:
                if opcode not in (0x1, 0x2):
                    raise ProbeFailure("provider_event_error")
                self._fragment_opcode = opcode
                self._fragments = [payload]
                continue
            if opcode not in (0x1, 0x2):
                continue
            try:
                decoded = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                raise ProbeFailure("provider_event_error")
            if not isinstance(decoded, dict):
                raise ProbeFailure("provider_event_error")
            return decoded

    def _receive_frame(self) -> tuple[int, bool, bytes]:
        first, second = self._recv_exact(2)
        finished = bool(first & 0x80)
        opcode = first & 0x0F
        masked = bool(second & 0x80)
        length = second & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(8))[0]
        if length > MAX_WEBSOCKET_MESSAGE_BYTES:
            raise ProbeFailure("provider_event_error")
        mask = self._recv_exact(4) if masked else b""
        payload = self._recv_exact(length)
        if masked:
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        return opcode, finished, payload

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        try:
            if self._socket is not None:
                self._send_frame(0x8, b"")
        except (OSError, ProbeFailure):
            pass
        finally:
            if self._socket is not None:
                self._socket.close()
                self._socket = None


def _receive_until(websocket: ProviderWebSocket, timeout_seconds: float, matcher: Any) -> None:
    deadline = time.monotonic() + timeout_seconds
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ProbeFailure("timeout", retryable=True)
        if websocket._socket is not None:
            websocket._socket.settimeout(remaining)
        try:
            event = websocket.receive_json()
        except (socket.timeout, TimeoutError) as error:
            raise ProbeFailure("timeout", retryable=True) from error
        except (OSError, ssl.SSLError) as error:
            raise ProbeFailure("provider_transport") from error
        if event.get("type") == "error" or "error" in event:
            raise ProbeFailure("provider_event_error")
        if matcher(event):
            return


def _gemini_websocket(session: ProviderSession, timeout_seconds: float) -> ProviderWebSocket:
    query = urllib.parse.urlencode({"access_token": session.token})
    websocket = ProviderWebSocket(f"{GEMINI_URL_PREFIX}?{query}", {}, timeout_seconds)
    try:
        websocket.connect()
        websocket.send_json(
            {
                "setup": {
                    "model": "models/gemini-3.1-flash-live-preview",
                    "generationConfig": {
                        "responseModalities": ["AUDIO"],
                        "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Charon"}}},
                    },
                    "systemInstruction": {"parts": [{"text": session.prompt_text}]},
                    "inputAudioTranscription": {},
                    "outputAudioTranscription": {},
                    "realtimeInputConfig": {
                        "automaticActivityDetection": {"disabled": False},
                        "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
                    },
                    "tools": [
                        {
                            "functionDeclarations": [
                                {
                                    "name": "end_conversation",
                                    "description": "End this conversation after your final spoken response.",
                                    "parameters": {"type": "OBJECT", "properties": {}},
                                }
                            ]
                        }
                    ],
                    "sessionResumption": {},
                    "contextWindowCompression": {"slidingWindow": {}},
                }
            }
        )
        _receive_until(websocket, timeout_seconds, lambda event: "setupComplete" in event)
        return websocket
    except Exception:
        websocket.close()
        raise


def run_probe(config: ProbeConfig) -> int:
    if not config.base_url or not config.bearer_token:
        _emit("authenticate", "FAIL", "configuration")
        return 1
    _emit("authenticate", "PASS", "none")
    session = None
    current_step = "mint"
    try:
        session = _mint_provider_session(config)
        _emit("mint", "PASS", "none")
        current_step = "connect"
        websocket = _gemini_websocket(session, config.timeout_seconds)
        _emit("connect", "PASS", "none")
        try:
            current_step = "commit"
            # Standalone text commits directly; activity markers are for manual audio.
            websocket.send_json({"realtimeInput": {"text": PROBE_INPUT}})
            _emit("commit", "PASS", "none")
            current_step = "response"
            _receive_until(
                websocket,
                config.timeout_seconds,
                lambda event: isinstance(event.get("serverContent"), dict)
                and event["serverContent"].get("turnComplete") is True,
            )
            _emit("response", "PASS", "none")
        finally:
            websocket.close()
    except ProbeFailure as error:
        _emit(current_step, "FAIL", error.failure_class)
        return 75 if error.retryable else 1
    except (socket.timeout, TimeoutError):
        _emit(current_step, "FAIL", "timeout")
        return 75
    except (OSError, ssl.SSLError):
        _emit(current_step, "FAIL", "provider_transport")
        return 1
    finally:
        session = None
    _emit("close", "PASS", "expected_idle_teardown")
    return 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backend_base_url")
    parser.add_argument("--bearer-token-file", required=True, type=Path)
    parser.add_argument("--timeout-seconds", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    args = parser.parse_args(argv)
    if not 1 <= args.timeout_seconds <= 60:
        parser.error("--timeout-seconds must be between 1 and 60")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    return run_probe(config_from_args(parse_args(argv or sys.argv[1:])))


if __name__ == "__main__":
    raise SystemExit(main())
