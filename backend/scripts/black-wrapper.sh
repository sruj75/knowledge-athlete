#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$ROOT/backend/.black-version"

if ! command -v uvx >/dev/null 2>&1; then
  echo "FAIL: uvx is required to run the repository-pinned Black formatter." >&2
  echo "      Run: make setup" >&2
  exit 1
fi

BLACK_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$BLACK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "FAIL: invalid Black version in $VERSION_FILE: $BLACK_VERSION" >&2
  exit 1
fi

exec uvx --from "black==$BLACK_VERSION" black "$@"
