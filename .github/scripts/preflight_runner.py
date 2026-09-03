#!/usr/bin/env python3
"""Run a command single-flight with observable per-worktree state and logs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

POLL_SECONDS = 0.2
STATUS_INTERVAL_SECONDS = 5.0
MAX_PR_BODY_FINGERPRINT_BYTES = 1024 * 1024
IS_WINDOWS = os.name == "nt"
WINDOWS_CHILD_BOOTSTRAP_FLAG = "--windows-child-bootstrap"

# Signals forwarded to the owned child. SIGHUP is POSIX-only and is simply absent
# on Windows, so the set is resolved against the host rather than assumed —
# referencing signal.SIGHUP unconditionally raised AttributeError before any
# pre-push check could run.
FORWARDED_SIGNAL_NAMES = ("SIGINT", "SIGTERM", "SIGHUP")
FINGERPRINT_ENV_NAMES = (
    "GITHUB_HEAD_REF",
    "OMI_PR_BODY_FILE",
    "PATH",
    "PYTHON",
    "PYTHONPATH",
)


def forwardable_signals(signal_module: object = signal) -> tuple[int, ...]:
    """Return the forwardable signals this platform actually defines."""
    names = list(FORWARDED_SIGNAL_NAMES)
    if not hasattr(signal_module, "SIGHUP"):
        names.append("SIGBREAK")
    resolved = (getattr(signal_module, name, None) for name in names)
    return tuple(signum for signum in resolved if signum is not None)


def signal_child(
    child: subprocess.Popen,
    signum: int,
    windows_job: object | None = None,
    *,
    platform_name: str | None = None,
) -> None:
    """Forward a signal to the isolated child process group where supported."""
    platform_name = platform_name or os.name
    killpg = getattr(os, "killpg", None)
    try:
        if windows_job is not None:
            windows_job.terminate()
        elif platform_name == "nt":
            ctrl_break = getattr(signal, "CTRL_BREAK_EVENT", None)
            if ctrl_break is not None and signum in (signal.SIGINT, signal.SIGTERM):
                child.send_signal(ctrl_break)
            else:
                child.send_signal(signum)
        elif killpg is not None:
            killpg(child.pid, signum)
        else:
            child.send_signal(signum)
    except (ProcessLookupError, OSError, ValueError):
        pass


def atomic_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def configure_console_error_handling() -> None:
    """Keep non-console Unicode output from aborting a Windows preflight."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            options = {"errors": "replace"}
            if os.name == "nt":
                options["encoding"] = "utf-8"
            reconfigure(**options)


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def process_exists(pid: int, expected_creation_ticks: int | None = None) -> bool:
    if pid <= 0:
        return False
    if IS_WINDOWS:
        alive, creation_ticks = windows_process_status(pid)
        if expected_creation_ticks is not None:
            return alive and creation_ticks == expected_creation_ticks
        return alive
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def windows_process_status(pid: int) -> tuple[bool, int | None]:
    """Return native liveness and creation time without sending a signal."""
    import ctypes
    from ctypes import wintypes

    synchronize = 0x00100000
    query_limited_information = 0x1000
    wait_timeout = 0x00000102
    access_denied = 5
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.WaitForSingleObject.argtypes = (wintypes.HANDLE, wintypes.DWORD)
    kernel32.WaitForSingleObject.restype = wintypes.DWORD
    kernel32.GetProcessTimes.argtypes = (
        wintypes.HANDLE,
        ctypes.POINTER(wintypes.FILETIME),
        ctypes.POINTER(wintypes.FILETIME),
        ctypes.POINTER(wintypes.FILETIME),
        ctypes.POINTER(wintypes.FILETIME),
    )
    kernel32.GetProcessTimes.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
    kernel32.CloseHandle.restype = wintypes.BOOL

    handle = kernel32.OpenProcess(synchronize | query_limited_information, False, pid)
    if not handle:
        return (ctypes.get_last_error() == access_denied, None)
    try:
        if kernel32.WaitForSingleObject(handle, 0) != wait_timeout:
            return (False, None)
        creation = wintypes.FILETIME()
        exit_time = wintypes.FILETIME()
        kernel_time = wintypes.FILETIME()
        user_time = wintypes.FILETIME()
        if not kernel32.GetProcessTimes(
            handle,
            ctypes.byref(creation),
            ctypes.byref(exit_time),
            ctypes.byref(kernel_time),
            ctypes.byref(user_time),
        ):
            return (True, None)
        ticks = (creation.dwHighDateTime << 32) | creation.dwLowDateTime
        return (True, ticks)
    finally:
        kernel32.CloseHandle(handle)


def windows_process_exists(pid: int) -> bool:
    """Compatibility wrapper for callers that only need Windows liveness."""
    return windows_process_status(pid)[0]


class WindowsJob:
    """Own a Windows process tree and terminate every descendant on exit."""

    def __init__(self) -> None:
        import ctypes
        from ctypes import wintypes

        class IOCounters(ctypes.Structure):
            _fields_ = [
                ("ReadOperationCount", ctypes.c_ulonglong),
                ("WriteOperationCount", ctypes.c_ulonglong),
                ("OtherOperationCount", ctypes.c_ulonglong),
                ("ReadTransferCount", ctypes.c_ulonglong),
                ("WriteTransferCount", ctypes.c_ulonglong),
                ("OtherTransferCount", ctypes.c_ulonglong),
            ]

        class BasicLimitInformation(ctypes.Structure):
            _fields_ = [
                ("PerProcessUserTimeLimit", ctypes.c_longlong),
                ("PerJobUserTimeLimit", ctypes.c_longlong),
                ("LimitFlags", wintypes.DWORD),
                ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t),
                ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.c_size_t),
                ("PriorityClass", wintypes.DWORD),
                ("SchedulingClass", wintypes.DWORD),
            ]

        class ExtendedLimitInformation(ctypes.Structure):
            _fields_ = [
                ("BasicLimitInformation", BasicLimitInformation),
                ("IoInfo", IOCounters),
                ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t),
                ("PeakJobMemoryUsed", ctypes.c_size_t),
            ]

        self._ctypes = ctypes
        self._kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self._kernel32.CreateJobObjectW.argtypes = (ctypes.c_void_p, wintypes.LPCWSTR)
        self._kernel32.CreateJobObjectW.restype = wintypes.HANDLE
        self._kernel32.SetInformationJobObject.argtypes = (
            wintypes.HANDLE,
            ctypes.c_int,
            ctypes.c_void_p,
            wintypes.DWORD,
        )
        self._kernel32.SetInformationJobObject.restype = wintypes.BOOL
        self._kernel32.AssignProcessToJobObject.argtypes = (wintypes.HANDLE, wintypes.HANDLE)
        self._kernel32.AssignProcessToJobObject.restype = wintypes.BOOL
        self._kernel32.TerminateJobObject.argtypes = (wintypes.HANDLE, wintypes.UINT)
        self._kernel32.TerminateJobObject.restype = wintypes.BOOL
        self._kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        self._kernel32.OpenProcess.restype = wintypes.HANDLE
        self._kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
        self._kernel32.CloseHandle.restype = wintypes.BOOL

        self._handle = self._kernel32.CreateJobObjectW(None, None)
        if not self._handle:
            raise OSError(ctypes.get_last_error(), "CreateJobObjectW failed")
        information = ExtendedLimitInformation()
        information.BasicLimitInformation.LimitFlags = 0x00002000
        if not self._kernel32.SetInformationJobObject(
            self._handle,
            9,
            ctypes.byref(information),
            ctypes.sizeof(information),
        ):
            error = ctypes.get_last_error()
            self.close()
            raise OSError(error, "SetInformationJobObject failed")

    def assign(self, pid: int) -> None:
        process_set_quota = 0x0100
        process_terminate = 0x0001
        process = self._kernel32.OpenProcess(process_set_quota | process_terminate, False, pid)
        if not process:
            raise OSError(self._ctypes.get_last_error(), f"OpenProcess failed for PID {pid}")
        try:
            if not self._kernel32.AssignProcessToJobObject(self._handle, process):
                raise OSError(self._ctypes.get_last_error(), f"AssignProcessToJobObject failed for PID {pid}")
        finally:
            self._kernel32.CloseHandle(process)

    def terminate(self, exit_code: int = 1) -> bool:
        return bool(self._handle and self._kernel32.TerminateJobObject(self._handle, exit_code))

    def close(self) -> None:
        if self._handle:
            self._kernel32.CloseHandle(self._handle)
            self._handle = None


def child_launch_command(command: list[str]) -> list[str]:
    """Add a Windows assignment barrier before the real command can spawn."""
    if not IS_WINDOWS:
        return command
    return [sys.executable, str(Path(__file__).resolve()), WINDOWS_CHILD_BOOTSTRAP_FLAG, *command]


def run_windows_child_bootstrap(command: list[str]) -> int:
    """Wait until the parent assigns this process to its Job, then launch."""
    if sys.stdin.buffer.read(1) != b"1":
        print("FAIL: Windows child bootstrap was not assigned to its Job", file=sys.stderr)
        return 2
    return subprocess.run(command, check=False).returncode


def resolve_repo_root() -> Path:
    completed = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=Path.cwd(),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
    )
    return Path(completed.stdout.strip()).resolve() if completed.returncode == 0 else Path.cwd().resolve()


def default_state_dir(root: Path, name: str) -> Path:
    override = os.getenv("OMI_PREFLIGHT_STATE_DIR")
    if override:
        return Path(override).resolve() / name
    git_dir = subprocess.check_output(
        ["git", "rev-parse", "--absolute-git-dir"],
        cwd=root,
        text=True,
        encoding="utf-8",
    ).strip()
    return Path(git_dir) / "omi-preflight" / name


def fingerprint(root: Path, command: list[str], stdin_data: str) -> str:
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
    ).stdout.strip()
    digest = hashlib.sha256()
    for value in (str(root.resolve()), head, "\0".join(command), stdin_data):
        digest.update(value.encode("utf-8"))
        digest.update(b"\0")
    relevant_names = set(FINGERPRINT_ENV_NAMES)
    relevant_names.update(name for name in os.environ if name.startswith("PRE_PUSH_"))
    for name in sorted(relevant_names):
        digest.update(name.encode("utf-8"))
        digest.update(b"=")
        digest.update(os.getenv(name, "").encode("utf-8"))
        digest.update(b"\0")
    body_path = os.getenv("OMI_PR_BODY_FILE", "").strip()
    if body_path:
        try:
            with Path(body_path).open("rb") as body_file:
                body = body_file.read(MAX_PR_BODY_FINGERPRINT_BYTES + 1)
            digest.update(body[:MAX_PR_BODY_FINGERPRINT_BYTES])
            if len(body) > MAX_PR_BODY_FINGERPRINT_BYTES:
                digest.update(b"<truncated-pr-body>")
        except OSError:
            digest.update(b"<unreadable-pr-body>")
        digest.update(b"\0")
    return digest.hexdigest()


def acquire(lock_dir: Path, owner: dict) -> bool:
    try:
        lock_dir.mkdir()
    except FileExistsError:
        return False
    atomic_json(lock_dir / "owner.json", owner)
    return True


def remove_stale_lock(lock_dir: Path, expected_pid: int, expected_creation_ticks: int | None = None) -> bool:
    owner = read_json(lock_dir / "owner.json")
    if int(owner.get("pid") or 0) != expected_pid:
        return False
    if process_exists(expected_pid, expected_creation_ticks):
        return False
    try:
        shutil.rmtree(lock_dir)
        return True
    except FileNotFoundError:
        return True


def join_existing(state_dir: Path, wanted_fingerprint: str) -> int | None:
    lock_dir = state_dir / "lock"
    owner = read_json(lock_dir / "owner.json")
    if not owner:
        try:
            lock_age = time.time() - lock_dir.stat().st_mtime
        except FileNotFoundError:
            return None
        if lock_age > 2:
            shutil.rmtree(lock_dir, ignore_errors=True)
        else:
            time.sleep(POLL_SECONDS)
        return None
    active_pid = int(owner.get("pid") or 0)
    active_creation_ticks = owner.get("creation_ticks")
    if not isinstance(active_creation_ticks, int):
        active_creation_ticks = None
    active_fingerprint = str(owner.get("fingerprint") or "")
    if not process_exists(active_pid, active_creation_ticks):
        if remove_stale_lock(lock_dir, active_pid, active_creation_ticks):
            return None
    log_path = state_dir / "preflight.log"
    status_path = state_dir / "status.json"
    if active_fingerprint != wanted_fingerprint:
        status = read_json(status_path)
        phase = status.get("phase", "starting")
        print(
            f"FAIL: preflight PID {active_pid} is already running different input "
            f"(phase={phase}, log={log_path}). Retry after it finishes.",
            file=sys.stderr,
        )
        return 75

    print(f"Joining identical preflight PID {active_pid}; live log: {log_path}")
    next_status = 0.0
    while lock_dir.exists():
        if not process_exists(active_pid, active_creation_ticks):
            remove_stale_lock(lock_dir, active_pid, active_creation_ticks)
            break
        now = time.monotonic()
        if now >= next_status:
            status = read_json(status_path)
            elapsed = max(0.0, time.time() - float(status.get("started_at_epoch") or time.time()))
            print(
                f"  active phase={status.get('phase', 'starting')} elapsed={elapsed:.1f}s",
                flush=True,
            )
            next_status = now + STATUS_INTERVAL_SECONDS
        time.sleep(POLL_SECONDS)
    result = read_json(state_dir / "result.json")
    if result.get("fingerprint") != wanted_fingerprint:
        print("FAIL: joined preflight ended without a matching result; retry the push.", file=sys.stderr)
        return 1
    return int(result.get("exit_code", 1))


def run_owned(
    state_dir: Path,
    lock_dir: Path,
    wanted_fingerprint: str,
    command: list[str],
    stdin_data: str,
    root: Path,
) -> int:
    log_path = state_dir / "preflight.log"
    status_path = state_dir / "status.json"
    result_path = state_dir / "result.json"
    started = time.monotonic()
    started_wall = time.time()
    phase = "starting"
    child: subprocess.Popen[str] | None = None
    windows_job: WindowsJob | None = None

    def write_status() -> None:
        atomic_json(
            status_path,
            {
                "pid": os.getpid(),
                "fingerprint": wanted_fingerprint,
                "phase": phase,
                "elapsed_seconds": round(time.monotonic() - started, 1),
                "log": str(log_path),
                "started_at_epoch": started_wall,
            },
        )

    def forward_signal(signum: int, _frame: object) -> None:
        if child is not None and (windows_job is not None or child.poll() is None):
            signal_child(child, signum, windows_job)

    previous_handlers = {signum: signal.signal(signum, forward_signal) for signum in forwardable_signals()}
    exit_code = 1
    try:
        print(f"Pre-push single-flight log: {log_path}")
        log_path.write_text("", encoding="utf-8")
        os.chmod(log_path, 0o600)
        write_status()
        child_env = os.environ.copy()
        child_env["PYTHONIOENCODING"] = "utf-8"
        child_env["PYTHONUTF8"] = "1"
        process_group_options = (
            {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {"start_new_session": True}
        )
        launch_command = child_launch_command(command)
        if IS_WINDOWS:
            windows_job = WindowsJob()
        child = subprocess.Popen(
            launch_command,
            cwd=root,
            env=child_env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="backslashreplace",
            bufsize=1,
            **process_group_options,
        )
        if child.stdin:
            if windows_job is not None:
                try:
                    windows_job.assign(child.pid)
                except Exception:
                    child.terminate()
                    child.wait(timeout=10)
                    raise
                child.stdin.write("1")
            child.stdin.write(stdin_data)
            child.stdin.close()
        assert child.stdout is not None
        with log_path.open("a", encoding="utf-8") as log:
            for line in child.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)
                log.flush()
                if line.startswith("==> "):
                    phase = line[4:].strip()
                    write_status()
        exit_code = child.wait()
        phase = "passed" if exit_code == 0 else "failed"
        write_status()
        atomic_json(
            result_path,
            {
                "exit_code": exit_code,
                "fingerprint": wanted_fingerprint,
                "elapsed_seconds": round(time.monotonic() - started, 1),
                "finished_at_epoch": time.time(),
                "log": str(log_path),
            },
        )
        return exit_code
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        if windows_job is not None:
            windows_job.close()
        shutil.rmtree(lock_dir, ignore_errors=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", default="pre-push")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    return parser.parse_args()


def main() -> int:
    configure_console_error_handling()
    if len(sys.argv) > 1 and sys.argv[1] == WINDOWS_CHILD_BOOTSTRAP_FLAG:
        return run_windows_child_bootstrap(sys.argv[2:])
    args = parse_args()
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("FAIL: preflight runner requires a command after --", file=sys.stderr)
        return 2
    root = resolve_repo_root()
    # Git supplies ref updates on a pipe. Manual preflight runs inherit a TTY;
    # treating that as empty input avoids waiting forever for an interactive EOF.
    stdin_data = "" if sys.stdin.isatty() else sys.stdin.read()
    wanted_fingerprint = fingerprint(root, command, stdin_data)
    state_dir = default_state_dir(root, args.name)
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(state_dir, 0o700)
    lock_dir = state_dir / "lock"
    owner = {"pid": os.getpid(), "fingerprint": wanted_fingerprint, "started_at_epoch": time.time()}
    if IS_WINDOWS:
        _, creation_ticks = windows_process_status(os.getpid())
        owner["creation_ticks"] = creation_ticks

    while not acquire(lock_dir, owner):
        joined = join_existing(state_dir, wanted_fingerprint)
        if joined is not None:
            return joined
    return run_owned(state_dir, lock_dir, wanted_fingerprint, command, stdin_data, root)


if __name__ == "__main__":
    raise SystemExit(main())
