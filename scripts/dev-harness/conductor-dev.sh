#!/usr/bin/env bash
# Conductor UI adapter; the existing harness retains process/state ownership.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
export PATH="/opt/homebrew/bin:$PATH"
export OMI_DEV_APP_ROOT="$HOME/Applications"
export OMI_SEED_FROM_CANONICAL_DEV=0
export PROVIDER_MODE="${PROVIDER_MODE:-offline}"

case "${1:-start}" in
  setup)
    if [ -n "${OMI_DEV_CACHE_ROOT:-}" ]; then
      # Reuse the launcher's per-worktree lock, including stale-owner recovery.
      source scripts/dev-instance.sh
      source desktop/macos/scripts/run-sh-build-lock.sh
      omi_run_sh_acquire_build_lock "Dev cache preparation" 30
      trap omi_run_sh_release_build_lock EXIT
      python3 scripts/dev-harness/dev_harness/build_cache.py "$REPO_ROOT" "$OMI_DEV_CACHE_ROOT"
      omi_run_sh_release_build_lock
      trap - EXIT
    fi
    exec make dev-init
    ;;
  status) exec bash scripts/dev-harness/dev-status.sh ;;
  stop|archive) exec bash scripts/dev-harness/dev-down.sh ;;
  start)
    # Firebase discovers emulator hubs through the process temp directory. A
    # cold/failed start must not export another workspace's same-project hub.
    # Keep this private and internal; run.sh also places transient auth here.
    umask 077
    mkdir -p "$HOME/Library/Caches/Intentive Dev Harness"
    RUNTIME_TMP="$(mktemp -d "$HOME/Library/Caches/Intentive Dev Harness/session.XXXXXX")"
    export TMPDIR="$RUNTIME_TMP/"
    # Conductor owns this foreground command. Its Stop action drains only the
    # harness-owned processes; EXIT must not send a second stop on INT/TERM.
    cleanup() {
      trap '' INT TERM
      trap - EXIT
      if bash scripts/dev-harness/dev-down.sh; then
        rm -rf "$RUNTIME_TMP"
      else
        echo "Dev stop is incomplete; preserved its private temporary directory: $RUNTIME_TMP" >&2
        return 1
      fi
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    echo "Starting Dev. Conductor Stop or quitting this named app drains its owned services."
    # desktop-run-local already waits for its recorded app. Keep that existing
    # foreground owner; Conductor signals this command's whole process group.
    make dev-desktop
    ;;
  *) echo "Usage: $0 <setup|start|status|stop|archive>" >&2; exit 2 ;;
esac
