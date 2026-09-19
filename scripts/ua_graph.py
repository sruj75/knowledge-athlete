"""Manage a pinned scanner and check the graph stored in an immutable Git tree."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

REVISION = "6df3065f1d8ddc2ce3615314d1d493f36d6b1c80"
NODE_VERSION = "22.22.0"
PNPM_VERSION = "10.6.2"
READINESS_VERSION = 2
LOCK_HASH = "20342fbb10c311a3259a4f7acb367cc79b2b2ad565ede2c3e1704a797d32ed96"
SCAN_HASH = "62f075686400959d3fb6634f73798485b82b89c743f9deecc62a601ce398ebb3"
PLATFORM = f"{sys.platform}-{platform.machine().lower()}"
RUNTIME_KEY = f"{REVISION}-lock{LOCK_HASH[:12]}-node{NODE_VERSION}-pnpm{PNPM_VERSION}-{PLATFORM}"
PLUGIN_PATH = Path("source/understand-anything-plugin")
SCAN_PATH = PLUGIN_PATH / "skills/understand/scan-project.mjs"
UPSTREAM = "https://github.com/Egonex-AI/Understand-Anything.git"
ARTIFACTS = ("knowledge-graph.json", "fingerprints.json", "meta.json", "config.json", ".understandignore")
READINESS_MODULES = (
    "packages/core/dist/index.js",
    "skills/understand/compute-batches.mjs",
    "skills/understand/prepare-incremental.mjs",
    "skills/understand/finalize-incremental.mjs",
)


class GraphError(Exception):
    """An actionable error at the public command boundary."""


def cache_directory() -> Path:
    override = os.environ.get("UA_GRAPH_CACHE_DIR")
    if override:
        path = Path(override).expanduser()
        if not path.is_absolute():
            raise GraphError("UA_GRAPH_CACHE_DIR must be an absolute path outside the repository")
        cache = path.resolve()
    elif os.environ.get("XDG_CACHE_HOME"):
        cache = Path(os.environ["XDG_CACHE_HOME"]).expanduser().resolve() / "intentive" / "ua-graph"
    elif sys.platform == "darwin":
        cache = Path.home() / "Library/Caches/intentive/ua-graph"
    else:
        cache = Path.home() / ".cache/intentive/ua-graph"
    for parent in (cache, *cache.parents):
        if (parent / ".git").exists():
            raise GraphError("UA_GRAPH_CACHE_DIR must be outside the repository")
    return cache


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_environment() -> dict[str, str]:
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    for key in ("NODE_OPTIONS", "NODE_PATH"):
        environment.pop(key, None)
    environment.update(
        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_ATTR_NOSYSTEM="1", GIT_NO_REPLACE_OBJECTS="1"
    )
    return environment


def run(
    command: list[str], *, cwd: Path | None = None, environment: dict | None = None, reject_stderr: str | None = None
) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=environment or clean_environment(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        raise GraphError(
            f"{Path(command[0]).name} failed ({result.returncode}):\n{result.stdout.strip()}\n{result.stderr.strip()}".strip()
        )
    if reject_stderr and reject_stderr in result.stderr:
        raise GraphError(result.stderr.strip())
    return result.stdout.strip()


def node_binary() -> Path:
    candidates = [shutil.which("node")]
    if os.environ.get("NVM_DIR"):
        candidates.append(str(Path(os.environ["NVM_DIR"]) / "versions/node" / f"v{NODE_VERSION}/bin/node"))
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            try:
                if run([candidate, "--version"]) == f"v{NODE_VERSION}":
                    return Path(candidate).resolve()
            except GraphError:
                pass
    raise GraphError(f"Node {NODE_VERSION} is required; install the version in .nvmrc and run nvm use.")


def git(arguments: list[str], *, cwd: Path | None = None) -> str:
    return run(["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", *arguments], cwd=cwd)


def verify_runtime_imports(plugin: Path, node: Path) -> None:
    # These stock modules guard their CLI entrypoints. Imports resolve dependencies
    # without preparing a plan, writing graph artifacts, or invoking models.
    modules = [(plugin / relative).as_uri() for relative in READINESS_MODULES]
    run([str(node), "--input-type=module", "-e", f"for (const url of {json.dumps(modules)}) await import(url);"])


def runtime_root() -> Path:
    runtime = cache_directory() / RUNTIME_KEY
    try:
        receipt = json.loads((runtime / "ready.json").read_text())
        if not isinstance(receipt, dict) or receipt.get("readinessVersion") != READINESS_VERSION:
            raise ValueError("runtime readiness contract is outdated")
        if (
            receipt["revision"] != REVISION
            or receipt["nodeVersion"] != NODE_VERSION
            or receipt["pnpmVersion"] != PNPM_VERSION
            or receipt["platform"] != PLATFORM
        ):
            raise ValueError("runtime version mismatch")
        if sha256(runtime / SCAN_PATH) != SCAN_HASH:
            raise ValueError("scanner integrity mismatch")
        if sha256(runtime / "source/pnpm-lock.yaml") != LOCK_HASH:
            raise ValueError("lockfile integrity mismatch")
        if any(str(PLUGIN_PATH / relative) not in receipt["runtimeFiles"] for relative in READINESS_MODULES):
            raise ValueError("incomplete runtime receipt")
        for relative, digest in receipt["runtimeFiles"].items():
            prefixes = (str(PLUGIN_PATH / "packages/core/dist") + "/", str(PLUGIN_PATH / "skills/understand") + "/")
            if not relative.startswith(prefixes) or ".." in Path(relative).parts:
                raise ValueError("invalid runtime receipt path")
            if sha256(runtime / relative) != digest:
                raise ValueError(f"runtime integrity mismatch: {relative}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise GraphError(f"Pinned UA runtime is missing or invalid; run scripts/ua-graph setup. ({error})") from error
    plugin = runtime / PLUGIN_PATH
    try:
        verify_runtime_imports(plugin, node_binary())
    except GraphError as error:
        raise GraphError(f"Pinned UA runtime cannot load; run scripts/ua-graph setup. ({error})") from error
    return plugin


def setup() -> None:
    node = node_binary()
    cache = cache_directory()
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        destination = cache / RUNTIME_KEY
        if destination.exists():
            try:
                root = runtime_root()
            except GraphError:
                # Only setup repairs its disposable cache; offline commands never do.
                shutil.rmtree(destination)
            else:
                print(f"Pinned UA runtime ready: {root}")
                return
        corepack = node.parent / "corepack"
        if not corepack.is_file():
            fallback = shutil.which("corepack")
            if not fallback:
                raise GraphError("Corepack is required for setup; install the official Node 22.22.0 distribution.")
            corepack = Path(fallback)
        environment = clean_environment()
        environment.update(
            PATH=str(node.parent) + os.pathsep + environment.get("PATH", ""),
            COREPACK_HOME=str(cache / "corepack"),
            COREPACK_ENABLE_DOWNLOAD_PROMPT="0",
            CI="1",
        )
        with tempfile.TemporaryDirectory(prefix="build-", dir=cache) as directory:
            staging = Path(directory)
            source = staging / "source"
            source.mkdir()
            git(["init", "--quiet", str(source)])
            git(["-C", str(source), "fetch", "--quiet", "--depth=1", UPSTREAM, REVISION])
            git(["-C", str(source), "checkout", "--quiet", "--detach", REVISION])
            if sha256(source / "pnpm-lock.yaml") != LOCK_HASH or sha256(staging / SCAN_PATH) != SCAN_HASH:
                raise GraphError("Pinned upstream scanner or lockfile failed its SHA-256 check")
            print("Building pinned Understand Anything analysis runtime (network is used only by setup)...", flush=True)
            pnpm = [str(node), str(corepack.resolve()), "pnpm"]
            if run([*pnpm, "--version"], cwd=source, environment=environment) != PNPM_VERSION:
                raise GraphError("Corepack did not resolve the pinned pnpm version")
            run(
                [
                    *pnpm,
                    "--filter",
                    "@understand-anything/skill...",
                    "install",
                    "--frozen-lockfile",
                    "--ignore-scripts",
                ],
                cwd=source,
                environment=environment,
            )
            run([*pnpm, "--filter", "@understand-anything/core", "build"], cwd=source, environment=environment)
            dist = staging / PLUGIN_PATH / "packages/core/dist"
            verify_runtime_imports(staging / PLUGIN_PATH, node)
            helpers = staging / PLUGIN_PATH / "skills/understand"
            files = {
                str(path.relative_to(staging)): sha256(path)
                for path in sorted([*dist.rglob("*.js"), *helpers.glob("*.mjs")])
            }
            receipt = dict(
                readinessVersion=READINESS_VERSION,
                revision=REVISION,
                nodeVersion=NODE_VERSION,
                pnpmVersion=PNPM_VERSION,
                platform=PLATFORM,
                runtimeFiles=files,
            )
            (staging / "ready.json").write_text(json.dumps(receipt, indent=2) + "\n")
            staging.rename(destination)
        print(f"Pinned UA runtime ready: {runtime_root()}")


def repository() -> tuple[Path, Path]:
    current = Path.cwd().resolve()
    for root in (current, *current.parents):
        marker = root / ".git"
        if marker.is_dir():
            return root, marker
        if marker.is_file():
            value = marker.read_text().strip()
            if not value.startswith("gitdir: "):
                raise GraphError("Malformed .git worktree marker")
            return root, (root / value[8:]).resolve()
    raise GraphError("Run this command inside a Git worktree")


def strict_json(path: Path):
    def pairs(items):
        value = {}
        for key, item in items:
            if key in value:
                raise ValueError(f"duplicate JSON key: {key}")
            value[key] = item
        return value

    def constant(value):
        raise ValueError(f"invalid JSON constant: {value}")

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs, parse_constant=constant)
    except (ValueError, UnicodeError) as error:
        raise GraphError(f"Invalid {path.name}: {error}") from error


def export_candidate(root: Path, git_dir: Path, oid: str, candidate: Path) -> None:
    """Use raw committed blobs, never checkout filters or the caller's index."""
    context = ["--git-dir", str(git_dir), "--work-tree", str(root), "-c", "core.bare=false"]
    object_format = git([*context, "rev-parse", "--show-object-format"])
    objects = git([*context, "rev-parse", "--path-format=absolute", "--git-path", "objects"])
    git(["init", "--quiet", f"--object-format={object_format}", str(candidate)])
    (candidate / ".git/objects/info/alternates").write_text(objects + "\n")
    local = ["--git-dir", str(candidate / ".git"), "--work-tree", str(candidate)]
    git([*local, "read-tree", oid])
    git([*local, "update-ref", "HEAD", oid])
    command = ["git", *local, "ls-tree", "-rz", "--full-tree", oid]
    tree = subprocess.run(command, env=clean_environment(), capture_output=True, check=True).stdout
    entries = []
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        header, raw_path = entry.split(b"\t", 1)
        mode, kind, blob = header.decode("ascii").split()
        try:
            relative = raw_path.decode("utf-8")
        except UnicodeError as error:
            raise GraphError("Candidate contains a non-UTF-8 path") from error
        parts = relative.split("/")
        if any(part in ("", ".", "..") or part.lower() == ".git" for part in parts) or "\\" in relative:
            raise GraphError(f"Unsafe candidate path: {relative!r}")
        entries.append((mode, kind, blob, candidate / relative))
    # Batch reads keep large repositories fast without invoking a shell or filters.
    process = subprocess.Popen(
        ["git", *local, "cat-file", "--batch"],
        env=clean_environment(),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        for mode, kind, blob, target in entries:
            if mode == "160000":
                target.mkdir(parents=True, exist_ok=True)
                continue
            if kind != "blob" or mode not in ("100644", "100755", "120000"):
                raise GraphError(f"Unsupported Git tree entry: {target.relative_to(candidate)}")
            process.stdin.write((blob + "\n").encode("ascii"))
            process.stdin.flush()
            response = process.stdout.readline().decode("ascii").split()
            if len(response) != 3 or response[0] != blob or response[1] != "blob":
                raise GraphError("Git could not read a committed blob")
            size = int(response[2])
            content = process.stdout.read(size)
            if len(content) != size or process.stdout.read(1) != b"\n":
                raise GraphError("Git returned an incomplete committed blob")
            target.parent.mkdir(parents=True, exist_ok=True)
            if mode == "120000":
                target.symlink_to(os.fsdecode(content))
            else:
                target.write_bytes(content)
                if mode == "100755":
                    target.chmod(0o755)
        process.stdin.close()
        if process.wait() != 0:
            raise GraphError("Git could not export the committed candidate")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        for stream in (process.stdin, process.stdout, process.stderr):
            if not stream.closed:
                stream.close()


def check(ref: str) -> None:
    plugin = runtime_root()
    node = node_binary()
    root, git_dir = repository()
    context = ["--git-dir", str(git_dir), "--work-tree", str(root), "-c", "core.bare=false"]
    oid = git([*context, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}"])
    with tempfile.TemporaryDirectory(prefix="ua-graph-check-") as directory:
        temporary = Path(directory)
        candidate = temporary / "candidate"
        export_candidate(root, git_dir, oid, candidate)
        if (candidate / ".understand-anything").exists() or (candidate / ".understand-anything").is_symlink():
            raise GraphError("Candidate contains legacy .understand-anything data; use the canonical .ua directory")
        for name in ARTIFACTS:
            path = candidate / ".ua" / name
            if not path.is_file() or path.is_symlink() or path.parent.is_symlink():
                raise GraphError(f"Candidate is missing regular committed .ua/{name}")
            if name.endswith(".json"):
                strict_json(path)
        for name in (".understandignore", ".gitignore"):
            if (candidate / name).is_symlink():
                raise GraphError(f"Scope file {name} must not be a symlink")
        scan = temporary / "scan.json"
        run(
            [
                str(node),
                str(plugin / "skills/understand/scan-project.mjs"),
                str(candidate),
                str(scan),
                "--exclude-analysis-data",
            ],
            cwd=candidate,
            reject_stderr="falling back to recursive walk",
        )
        output = run(
            [str(node), str(Path(__file__).with_name("ua_graph_validate.mjs")), str(plugin), str(candidate), str(scan)],
            cwd=candidate,
        )
        print(f"UA graph current for {oid}: {output}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("setup", "root", "check"))
    parser.add_argument("--ref", default="HEAD", help="committed candidate to check (default: HEAD)")
    arguments = parser.parse_args()
    try:
        if arguments.command == "root":
            print(runtime_root())
        elif arguments.command == "setup":
            setup()
        else:
            check(arguments.ref)
        return 0
    except (GraphError, OSError, subprocess.SubprocessError) as error:
        print(f"ua-graph: {error}", file=sys.stderr)
        return 1
