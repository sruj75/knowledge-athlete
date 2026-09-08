# shellcheck shell=bash
# Per-worktree dev isolation — source this (don't execute it).
#
# Multiple agents/worktrees building the macOS app used to collide: they all grabbed
# the same ports (backend 8080, automation 47777), the same bundle name
# ("Intentive Dev"), and run.sh killed *every* backend by process name. This derives a
# stable, unique "instance" from the current git worktree so each one gets its own
# ports, its own bundle, and its own pidfile — zero cross-talk, automatically.
# Pair with desktop/macos/scripts/run-sh-build-lock.sh: build serialization is also
# per-worktree (never a machine-wide ./run.sh mutex).
#
# Exports (an explicit override always wins — set any of these to opt out):
#   OMI_INSTANCE      stable id (git worktree basename)
#   PYTHON_PORT       local backend port
#   AUTOMATION_PORT   in-app automation bridge
#   OMI_APP_NAME      named bundle                 (omi-<instance>)
#   OMI_DEV_DIR       per-instance pidfile/scratch dir (<worktree>/.dev)
#   OMI_LOCAL_INSTANCE / OMI_HARNESS_* one matching local-harness identity and
#                       its nine owned ports
#
# The PRIMARY worktree (a normal `git clone`, not a linked `git worktree add`) keeps
# the primary defaults — offset 0, app name "Intentive Dev" — so the main checkout is
# unchanged. Only linked worktrees get isolated values.

_omi_wt="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Linked worktree iff its top-level `.git` is a FILE (a gitdir pointer); the primary
# checkout's `.git` is a directory. Robust regardless of the current subdirectory
# (comparing `git rev-parse --git-dir` vs `--git-common-dir` is NOT — they can return
# different absolute/relative formats from a subdir and give a false positive).
_omi_linked=0
# `if`, not `[ -f ] && …` — the latter returns non-zero when false and would trip a
# caller's `set -e` (run.sh has it) on the primary checkout, aborting it instantly.
if [ -f "$_omi_wt/.git" ]; then _omi_linked=1; fi

: "${OMI_INSTANCE:=$(basename "$_omi_wt")}"

if [ "$_omi_linked" = "1" ]; then
  # Deterministic offset in [1,199] from the instance name (stable across runs/machines).
  # +1 so a linked worktree never lands on the primary's offset-0 ports.
  _omi_off=$(printf '%s' "$OMI_INSTANCE" | cksum | awk '{print ($1 % 199) + 1}')
  : "${OMI_APP_NAME:=omi-$OMI_INSTANCE}"
else
  _omi_off=0
  : "${OMI_APP_NAME:=Intentive Dev}"
fi

_omi_default_env() {
  local name="$1"
  local value="$2"
  if [ -z "${!name+x}" ]; then
    printf -v "$name" '%s' "$value"
  fi
}

_omi_normalize_bounded_integer() {
  local name="$1"
  local minimum="$2"
  local maximum="$3"
  local value="${!name}"
  case "$value" in
    ''|*[!0-9]*)
      echo "ERROR: $name must be an integer, got '$value'" >&2
      return 1
      ;;
  esac
  if [ "${#value}" -gt 5 ]; then
    echo "ERROR: $name resolved outside the valid range $minimum-$maximum: $value" >&2
    return 1
  fi
  value="$((10#$value))"
  if [ "$value" -lt "$minimum" ] || [ "$value" -gt "$maximum" ]; then
    echo "ERROR: $name resolved outside the valid range $minimum-$maximum: $value" >&2
    return 1
  fi
  printf -v "$name" '%s' "$value"
}

_omi_explicit_harness_off=""
if [ -n "${OMI_HARNESS_PORT_OFFSET+x}" ]; then
  _omi_normalize_bounded_integer OMI_HARNESS_PORT_OFFSET 0 50000 || return 1
  _omi_explicit_harness_off="$OMI_HARNESS_PORT_OFFSET"
fi

_omi_conductor_base=""
if [ "${CONDUCTOR_IS_LOCAL:-}" = "1" ] \
  && [ -n "${CONDUCTOR_PORT:-}" ] \
  && [ -z "${OMI_HARNESS_PORT_OFFSET+x}" ]; then
  _omi_normalize_bounded_integer CONDUCTOR_PORT 1 65526 || return 1
  _omi_conductor_base="$CONDUCTOR_PORT"
fi

_omi_default_env OMI_LOCAL_INSTANCE "$OMI_INSTANCE"

if [ -n "$_omi_conductor_base" ]; then
  # Conductor owns exactly ten consecutive ports for this local workspace. Keep
  # one spare at +9 and make every port used by the desktop + emulator stack
  # explicit so Firebase cannot fall back to machine-global auxiliary defaults.
  _omi_default_env OMI_HARNESS_BACKEND_PORT "${PORT:-${PYTHON_PORT:-$_omi_conductor_base}}"
  _omi_default_env OMI_HARNESS_FIRESTORE_PORT "$((_omi_conductor_base + 1))"
  _omi_default_env OMI_HARNESS_AUTH_PORT "$((_omi_conductor_base + 2))"
  _omi_default_env OMI_HARNESS_REDIS_PORT "$((_omi_conductor_base + 3))"
  _omi_default_env OMI_AUTOMATION_PORT "${AUTOMATION_PORT:-$((_omi_conductor_base + 4))}"
  _omi_default_env OMI_HARNESS_FIRESTORE_WEBSOCKET_PORT "$((_omi_conductor_base + 5))"
  _omi_default_env OMI_HARNESS_FIREBASE_HUB_PORT "$((_omi_conductor_base + 6))"
  _omi_default_env OMI_HARNESS_FIREBASE_LOGGING_PORT "$((_omi_conductor_base + 7))"
  _omi_default_env OMI_HARNESS_FIREBASE_UI_PORT "$((_omi_conductor_base + 8))"
else
  # Preserve the existing non-Conductor worktree allocation. An explicit
  # harness offset remains authoritative for qualification/test callers.
  _omi_harness_off="${_omi_explicit_harness_off:-$_omi_off}"
  if [ -n "${OMI_HARNESS_PORT_OFFSET+x}" ]; then
    _omi_backend_default="$((8000 + _omi_harness_off))"
  else
    _omi_backend_default="${PORT:-${PYTHON_PORT:-$((8080 + _omi_off))}}"
  fi
  _omi_default_env OMI_HARNESS_BACKEND_PORT "$_omi_backend_default"
  _omi_default_env OMI_HARNESS_FIRESTORE_PORT "$((8085 + _omi_harness_off))"
  _omi_default_env OMI_HARNESS_AUTH_PORT "$((9099 + _omi_harness_off))"
  _omi_default_env OMI_HARNESS_REDIS_PORT "$((6380 + _omi_harness_off))"
  _omi_default_env OMI_AUTOMATION_PORT "${AUTOMATION_PORT:-$((47777 + _omi_harness_off))}"
  _omi_default_env OMI_HARNESS_FIRESTORE_WEBSOCKET_PORT "$((9150 + _omi_harness_off))"
  _omi_default_env OMI_HARNESS_FIREBASE_HUB_PORT "$((4400 + _omi_harness_off))"
  _omi_default_env OMI_HARNESS_FIREBASE_LOGGING_PORT "$((4500 + _omi_harness_off))"
  _omi_default_env OMI_HARNESS_FIREBASE_UI_PORT "$((4000 + _omi_harness_off))"
fi

_omi_seen_ports=" "
for _omi_port_name in \
  OMI_HARNESS_BACKEND_PORT \
  OMI_HARNESS_FIRESTORE_PORT \
  OMI_HARNESS_AUTH_PORT \
  OMI_HARNESS_REDIS_PORT \
  OMI_AUTOMATION_PORT \
  OMI_HARNESS_FIRESTORE_WEBSOCKET_PORT \
  OMI_HARNESS_FIREBASE_HUB_PORT \
  OMI_HARNESS_FIREBASE_LOGGING_PORT \
  OMI_HARNESS_FIREBASE_UI_PORT; do
  _omi_normalize_bounded_integer "$_omi_port_name" 1 65535 || return 1
  _omi_port_value="${!_omi_port_name}"
  case "$_omi_seen_ports" in
    *" $_omi_port_value "*)
      echo "ERROR: workspace ports must be distinct; $_omi_port_name repeats $_omi_port_value" >&2
      return 1
      ;;
  esac
  _omi_seen_ports="$_omi_seen_ports$_omi_port_value "
done

for _omi_alias_name in PORT PYTHON_PORT AUTOMATION_PORT; do
  if [ -n "${!_omi_alias_name+x}" ]; then
    _omi_normalize_bounded_integer "$_omi_alias_name" 1 65535 || return 1
  fi
done
_omi_default_env PYTHON_PORT "$OMI_HARNESS_BACKEND_PORT"
_omi_default_env AUTOMATION_PORT "$OMI_AUTOMATION_PORT"

if { [ -n "${PORT+x}" ] && [ "$PORT" != "$OMI_HARNESS_BACKEND_PORT" ]; } \
  || [ "$PYTHON_PORT" != "$OMI_HARNESS_BACKEND_PORT" ]; then
  echo "ERROR: conflicting port aliases for backend; PORT, PYTHON_PORT, and OMI_HARNESS_BACKEND_PORT must match" >&2
  return 1
fi
if [ "$AUTOMATION_PORT" != "$OMI_AUTOMATION_PORT" ]; then
  echo "ERROR: conflicting port aliases for automation; AUTOMATION_PORT and OMI_AUTOMATION_PORT must match" >&2
  return 1
fi

OMI_DEV_DIR="$_omi_wt/.dev"
mkdir -p "$OMI_DEV_DIR" 2>/dev/null || true

export OMI_INSTANCE OMI_LOCAL_INSTANCE PYTHON_PORT AUTOMATION_PORT OMI_AUTOMATION_PORT OMI_APP_NAME OMI_DEV_DIR
export OMI_HARNESS_BACKEND_PORT OMI_HARNESS_FIRESTORE_PORT OMI_HARNESS_AUTH_PORT OMI_HARNESS_REDIS_PORT
export OMI_HARNESS_FIRESTORE_WEBSOCKET_PORT OMI_HARNESS_FIREBASE_HUB_PORT
export OMI_HARNESS_FIREBASE_LOGGING_PORT OMI_HARNESS_FIREBASE_UI_PORT
