#!/bin/bash
# Claude Code Stop hook — auto-commit and push all changes.

INPUT=$(cat)

# Prevent recursion when Claude itself is doing git operations
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // "false"' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

# Delegate all logic to the auto-sync script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/git-auto-sync.sh"
