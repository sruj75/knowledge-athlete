#!/usr/bin/env python3
"""Probe one exact no-traffic canonical backend candidate.

The probe is deliberately bounded and content-free in its evidence. It proves:

* the workflow supplies the admitted backend source identity;
* the shallow process health contract stays unchanged;
* the versioned desktop compatibility contract is advertised independently;
* A bootstraps once and completes two tool-free turns with the same pinned prompt.

The Firebase ID token is read from a mode-0600 file and is never printed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

HTTP_TIMEOUT_SECONDS = 75
MAX_CHAT_SECONDS = 70
MAX_FIRST_EVENT_SECONDS = 20
MAX_RESPONSE_BYTES = 1_000_000
MAX_TEXT_CHARS = 32_000
MAX_HISTORY_TEXT_CHARS = 4_000
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
CONTRACT_PATTERN = re.compile(r"^[1-9][0-9]{0,5}$")


class ProbeError(RuntimeError):
    """A bounded release-candidate probe failure."""


@dataclass(frozen=True)
class ChatResult:
    answer: str
    elapsed_seconds: float
    first_event_seconds: float
    saw_usage: bool


def _require_object(value: object, *, stage: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProbeError(f"{stage}: expected a JSON object")
    return value


def validate_process_health(payload: object) -> dict[str, str]:
    health = _require_object(payload, stage="process_health")
    if health != {"status": "ok"}:
        raise ProbeError(
            f"process_health: expected the shallow canonical contract, got {json.dumps(health, sort_keys=True)}"
        )
    return {"status": "ok"}


def validate_compatibility(
    payload: object,
    *,
    expected_contract_version: str,
) -> dict[str, object]:
    health = _require_object(payload, stage="compatibility")
    expected = {
        "status": "healthy",
        "service": "backend",
        "chat_contract_version": expected_contract_version,
    }
    mismatches = {
        key: {"expected": wanted, "actual": health.get(key)}
        for key, wanted in expected.items()
        if health.get(key) != wanted
    }
    if mismatches:
        raise ProbeError(f"compatibility: incompatible service contract {json.dumps(mismatches, sort_keys=True)}")
    return {
        "chat_contract_version": expected_contract_version,
        "service": "backend",
        "status": "healthy",
    }


def parse_sse(
    lines: Iterable[bytes],
    *,
    stage: str,
    started_at: float | None = None,
    max_elapsed_seconds: float | None = None,
    expected_prompt_ref: dict[str, str] | None = None,
) -> tuple[str, bool, float, bool]:
    text: list[str] = []
    saw_terminal = False
    saw_usage = False
    first_event_seconds: float | None = None
    event_name = ""
    data_lines: list[str] = []
    received_bytes = 0
    text_chars = 0
    started_at = time.monotonic() if started_at is None else started_at
    for raw_line in lines:
        received_bytes += len(raw_line)
        if received_bytes > MAX_RESPONSE_BYTES:
            raise ProbeError(f"{stage}: stream exceeded its byte bound")
        elapsed = time.monotonic() - started_at
        if max_elapsed_seconds is not None and elapsed > max_elapsed_seconds:
            raise ProbeError(f"{stage}: exceeded {max_elapsed_seconds:g}s response budget")
        try:
            line = raw_line.decode("utf-8").strip()
        except UnicodeDecodeError as error:
            raise ProbeError(f"{stage}: invalid SSE encoding") from error
        if line.startswith(":"):
            continue
        if line.startswith("event:"):
            event_name = line[6:].strip()
            continue
        if line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
            continue
        if line or not data_lines:
            continue
        data = "\n".join(data_lines)
        data_lines.clear()
        try:
            event = _require_object(json.loads(data), stage=stage)
        except json.JSONDecodeError as error:
            raise ProbeError(f"{stage}: invalid SSE JSON") from error
        if saw_terminal:
            raise ProbeError(f"{stage}: event arrived after terminal completion")
        if event_name == "error":
            raise ProbeError(f"{stage}: upstream stream error")
        if first_event_seconds is None:
            first_event_seconds = time.monotonic() - started_at
            if first_event_seconds > MAX_FIRST_EVENT_SECONDS:
                raise ProbeError(f"{stage}: first event exceeded {MAX_FIRST_EVENT_SECONDS}s budget")
        if event_name == "text_delta":
            delta = event.get("text")
            if not isinstance(delta, str):
                raise ProbeError(f"{stage}: invalid text delta")
            text_chars += len(delta)
            if text_chars > MAX_TEXT_CHARS:
                raise ProbeError(f"{stage}: answer exceeded its text bound")
            text.append(delta)
        elif event_name == "done":
            if event.get("end_conversation") is not False:
                raise ProbeError(f"{stage}: conversation ended before the ordinary follow-up")
            if expected_prompt_ref is not None and event.get("prompt_ref") != expected_prompt_ref:
                raise ProbeError(f"{stage}: terminal prompt reference mismatch")
            usage = event.get("usage")
            required_usage = (
                "input_tokens",
                "cached_input_tokens",
                "output_tokens",
                "thinking_tokens",
            )
            saw_usage = isinstance(usage, dict) and all(
                isinstance(usage.get(key), int) and not isinstance(usage[key], bool) and usage[key] >= 0
                for key in required_usage
            )
            saw_terminal = True
        else:
            raise ProbeError(f"{stage}: unsupported conversation event")
        event_name = ""
    if data_lines:
        raise ProbeError(f"{stage}: truncated SSE event")
    answer = "".join(text).strip()
    if not saw_terminal:
        raise ProbeError(f"{stage}: stream ended without terminal completion")
    if not answer:
        raise ProbeError(f"{stage}: stream completed without answer text")
    if first_event_seconds is None:
        raise ProbeError(f"{stage}: stream completed without events")
    return answer, saw_terminal, first_event_seconds, saw_usage


def _request_json(url: str, *, timeout: int = HTTP_TIMEOUT_SECONDS) -> object:
    request = urllib.request.Request(url, headers={"Accept": "application/json"}, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except (
        urllib.error.HTTPError,
        urllib.error.URLError,
        OSError,
        TimeoutError,
        UnicodeDecodeError,
        json.JSONDecodeError,
    ) as error:
        raise ProbeError(f"GET probe failed: {url.rsplit('/', 1)[-1]}") from error


def _require_firestore_read(base_url: str, *, timeout: int = HTTP_TIMEOUT_SECONDS) -> dict[str, str]:
    url = f"{base_url.rstrip('/')}/updates/latest"
    request = urllib.request.Request(url, headers={"Accept": "application/json"}, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status_code = int(response.status)
    except urllib.error.HTTPError as error:
        status_code = error.code
    except (urllib.error.URLError, OSError, TimeoutError) as error:
        raise ProbeError("firestore_read: request failed") from error
    if status_code not in (200, 404):
        raise ProbeError(f"firestore_read: unexpected HTTP {status_code}")
    return {"status": "passed"}


def _chat_request(
    base_url: str,
    *,
    token: str,
    conversation_id: str,
    turn_id: str,
    prompt_ref: dict[str, str],
    messages: list[dict[str, str]],
    stage: str,
    timeout: int = HTTP_TIMEOUT_SECONDS,
) -> ChatResult:
    payload = {
        "conversation_id": conversation_id,
        "turn_id": turn_id,
        "prompt_ref": prompt_ref,
        "history": [
            {"role": message["role"], "text": message["content"][:MAX_HISTORY_TEXT_CHARS]} for message in messages[:-1]
        ],
        "message": messages[-1]["content"],
    }
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/v1/conversation/respond",
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers={
            "Accept": "text/event-stream",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    started_at = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            answer, _, first_event_seconds, saw_usage = parse_sse(
                response,
                stage=stage,
                started_at=started_at,
                max_elapsed_seconds=MAX_CHAT_SECONDS,
                expected_prompt_ref=prompt_ref,
            )
            elapsed_seconds = time.monotonic() - started_at
            if elapsed_seconds > MAX_CHAT_SECONDS:
                raise ProbeError(f"{stage}: exceeded {MAX_CHAT_SECONDS}s response budget")
            return ChatResult(
                answer=answer,
                elapsed_seconds=elapsed_seconds,
                first_event_seconds=first_event_seconds,
                saw_usage=saw_usage,
            )
    except ProbeError:
        raise
    except urllib.error.HTTPError as error:
        raise ProbeError(f"{stage}: HTTP {error.code}") from error
    except (urllib.error.URLError, OSError, TimeoutError) as error:
        raise ProbeError(f"{stage}: request failed") from error


def _bootstrap_conversation(base_url: str, *, token: str, conversation_id: str) -> dict[str, str]:
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/v1/conversation/session",
        data=json.dumps({"conversation_id": conversation_id}).encode("utf-8"),
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            body = response.read(MAX_RESPONSE_BYTES + 1)
        if len(body) > MAX_RESPONSE_BYTES:
            raise ProbeError("conversation_bootstrap: response exceeded its byte bound")
        payload = _require_object(json.loads(body.decode("utf-8")), stage="conversation_bootstrap")
    except urllib.error.HTTPError as error:
        raise ProbeError(f"conversation_bootstrap: HTTP {error.code}") from error
    except (
        urllib.error.URLError,
        OSError,
        TimeoutError,
        UnicodeDecodeError,
        json.JSONDecodeError,
    ) as error:
        raise ProbeError("conversation_bootstrap: request failed") from error
    if payload.get("conversation_id") != conversation_id:
        raise ProbeError("conversation_bootstrap: conversation identity mismatch")
    prompt = _require_object(payload.get("prompt"), stage="conversation_bootstrap")
    text = prompt.get("text")
    version = prompt.get("version")
    source = prompt.get("source")
    try:
        prompt_hash = hashlib.sha256(text.encode("utf-8")).hexdigest() if isinstance(text, str) else None
    except UnicodeError as error:
        raise ProbeError("conversation_bootstrap: invalid prompt receipt") from error
    if (
        prompt.get("name") != "intentive-live-system"
        or not isinstance(text, str)
        or not 1 <= len(text) <= MAX_TEXT_CHARS
        or not isinstance(version, str)
        or source not in ("langfuse", "fallback")
        or (source == "fallback" and version != "conversation-v1")
        or (source == "langfuse" and re.fullmatch(r"[1-9][0-9]{0,9}", version) is None)
        or prompt.get("sha256") != prompt_hash
    ):
        raise ProbeError("conversation_bootstrap: invalid prompt receipt")
    return {key: prompt[key] for key in ("name", "version", "source", "sha256")}


def probe_candidate(
    *,
    base_url: str,
    token: str,
    expected_contract_version: str,
    source_sha: str,
    expected_revision: str,
    expected_image_digest: str,
    candidate_tag: str,
    workflow_run_id: str,
) -> dict[str, object]:
    process_health = validate_process_health(_request_json(f"{base_url.rstrip('/')}/v1/health"))
    compatibility = validate_compatibility(
        _request_json(f"{base_url.rstrip('/')}/"),
        expected_contract_version=expected_contract_version,
    )
    firestore = _require_firestore_read(base_url)
    conversation_id = f"release-probe-{workflow_run_id}"
    prompt_ref = _bootstrap_conversation(base_url, token=token, conversation_id=conversation_id)

    keep_open = "There will be another user turn; keep this conversation open and do not call end_conversation."
    initial_prompt = (
        f"Reply with one concise sentence confirming that the desktop chat service is available. {keep_open}"
    )
    initial_result = _chat_request(
        base_url,
        token=token,
        conversation_id=conversation_id,
        turn_id=f"{conversation_id}.initial",
        prompt_ref=prompt_ref,
        messages=[{"role": "user", "content": initial_prompt}],
        stage="initial_turn",
    )
    if not initial_result.saw_usage:
        raise ProbeError("initial_turn: provider did not report terminal usage")
    follow_up_result = _chat_request(
        base_url,
        token=token,
        conversation_id=conversation_id,
        turn_id=f"{conversation_id}.follow-up",
        prompt_ref=prompt_ref,
        messages=[
            {"role": "user", "content": initial_prompt},
            {"role": "assistant", "content": initial_result.answer},
            {"role": "user", "content": f"Reply with one short follow-up sentence. {keep_open}"},
        ],
        stage="ordinary_follow_up",
    )
    if not follow_up_result.saw_usage:
        raise ProbeError("ordinary_follow_up: provider did not report terminal usage")

    return {
        "backend": compatibility,
        "chat": {
            "initial_turn": "passed",
            "initial_turn_chars": len(initial_result.answer),
            "initial_turn_first_event_seconds": round(initial_result.first_event_seconds, 3),
            "initial_turn_seconds": round(initial_result.elapsed_seconds, 3),
            "ordinary_follow_up": "passed",
            "ordinary_follow_up_chars": len(follow_up_result.answer),
            "ordinary_follow_up_seconds": round(follow_up_result.elapsed_seconds, 3),
        },
        "firestore_read": firestore,
        "process_health": process_health,
        "target": {
            "candidate_tag": candidate_tag,
            "image_digest": expected_image_digest,
            "revision": expected_revision,
            "source_sha": source_sha,
            "workflow_run_id": workflow_run_id,
        },
        "schema_version": 1,
        "status": "passed",
    }


def probe_health_only(
    *,
    base_url: str,
    expected_contract_version: str,
) -> dict[str, object]:
    return {
        "backend": validate_compatibility(
            _request_json(f"{base_url.rstrip('/')}/"),
            expected_contract_version=expected_contract_version,
        ),
        "process_health": validate_process_health(_request_json(f"{base_url.rstrip('/')}/v1/health")),
        "schema_version": 1,
        "status": "passed",
    }


def _valid_token(path: Path) -> str:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise ProbeError("token: bearer token file must be a regular mode-0600 file")
        with os.fdopen(descriptor, encoding="utf-8") as handle:
            descriptor = -1
            token = handle.read().strip()
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    if not token or len(token) > 8192 or any(char.isspace() for char in token):
        raise ProbeError("token: invalid bearer token file")
    return token


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--bearer-token-file", type=Path)
    parser.add_argument("--health-only", action="store_true")
    parser.add_argument("--source-sha")
    parser.add_argument("--expected-contract-version", required=True)
    parser.add_argument("--expected-revision")
    parser.add_argument("--expected-image-digest")
    parser.add_argument("--candidate-tag")
    parser.add_argument("--workflow-run-id")
    parser.add_argument("--evidence-path", required=True, type=Path)
    args = parser.parse_args()

    if not args.health_only:
        if args.source_sha is None or not SHA_PATTERN.fullmatch(args.source_sha):
            parser.error("--source-sha must be one lowercase full commit SHA")
        for name in (
            "expected_revision",
            "expected_image_digest",
            "candidate_tag",
            "workflow_run_id",
        ):
            if not getattr(args, name):
                parser.error(f"--{name.replace('_', '-')} is required for a full candidate probe")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", args.expected_image_digest):
            parser.error("--expected-image-digest must be one sha256 digest")
        if not re.fullmatch(r"[1-9][0-9]*", args.workflow_run_id):
            parser.error("--workflow-run-id must be a positive integer")
    if not CONTRACT_PATTERN.fullmatch(args.expected_contract_version):
        parser.error("--expected-contract-version must be a positive decimal version")
    if not args.base_url.startswith("https://"):
        parser.error("--base-url must use https")

    try:
        if args.health_only:
            evidence = probe_health_only(
                base_url=args.base_url,
                expected_contract_version=args.expected_contract_version,
            )
        else:
            if args.bearer_token_file is None:
                parser.error("--bearer-token-file is required for a full candidate probe")
            evidence = probe_candidate(
                base_url=args.base_url,
                token=_valid_token(args.bearer_token_file),
                expected_contract_version=args.expected_contract_version,
                source_sha=args.source_sha,
                expected_revision=args.expected_revision,
                expected_image_digest=args.expected_image_digest,
                candidate_tag=args.candidate_tag,
                workflow_run_id=args.workflow_run_id,
            )
    except (OSError, ProbeError) as error:
        print(f"backend candidate probe failed: {error}")
        return 1

    args.evidence_path.parent.mkdir(parents=True, exist_ok=True)
    args.evidence_path.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"backend candidate accepted: contract={args.expected_contract_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
