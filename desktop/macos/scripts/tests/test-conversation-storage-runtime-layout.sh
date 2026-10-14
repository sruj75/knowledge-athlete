#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../agent-runtime-cache.sh"
PREPARE="$SCRIPT_DIR/../prepare-agent-runtime.sh"
# Exercise the production validation seam without installing dependencies,
# downloading Node, signing, or launching an application.
for function_name in node_version_at_least validate_runtime_tree validate_packaged_symlinks; do
  eval "$(sed -n "/^${function_name}()/,/^}/p" "$PREPARE")"
done

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/conversation-storage-layout.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
AGENT_DIR="$TEST_ROOT/agent"
AGENT_PACKAGED_NODE_MODULES="$TEST_ROOT/modules"
NODE_RESOURCE="$TEST_ROOT/node"
NODE_MIN_VERSION=v22.19.0
MODE=local
mkdir -p "$AGENT_DIR/dist" "$AGENT_PACKAGED_NODE_MODULES/zod" "$AGENT_PACKAGED_NODE_MODULES/.bin"
printf '#!/bin/bash\nprintf "v22.19.0\\n"\n' > "$NODE_RESOURCE"
chmod +x "$NODE_RESOURCE"
printf 'storage entry\n' > "$AGENT_DIR/dist/index.js"
printf 'conversation storage\n' > "$AGENT_DIR/dist/conversation-storage.js"
printf 'module\n' > "$AGENT_PACKAGED_NODE_MODULES/zod/index.js"

validate_runtime_tree || { echo 'storage-only runtime rejected'; exit 1; }
rm "$AGENT_DIR/dist/conversation-storage.js"
if validate_runtime_tree; then echo 'missing storage implementation accepted'; exit 1; fi
printf 'conversation storage\n' > "$AGENT_DIR/dist/conversation-storage.js"
ln -s "$NODE_RESOURCE" "$AGENT_PACKAGED_NODE_MODULES/.bin/escaping-link"
if validate_runtime_tree; then echo 'escaping dependency symlink accepted'; exit 1; fi
rm "$AGENT_PACKAGED_NODE_MODULES/.bin/escaping-link"
printf '#!/bin/bash\nprintf "v20.0.0\\n"\n' > "$NODE_RESOURCE"
if validate_runtime_tree; then echo 'unsupported Node accepted'; exit 1; fi
printf 'conversation storage runtime validation tests passed\n'
