#!/bin/bash
# Auto-pull: fetch latest from remote at the start of a Claude Code session.
# Called by Claude Code UserPromptSubmit hook.
# Runs only once per session using a session-scoped lock file.

set -uo pipefail

# Read hook input (UserPromptSubmit passes JSON on stdin)
INPUT=$(cat)

# Only run on the first prompt of a session
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
PULL_MARKER="/tmp/git-auto-pulled-${SESSION_ID}"
if [[ -f "$PULL_MARKER" ]]; then
  exit 0
fi
touch "$PULL_MARKER"

# Must be in a git repo with a remote
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ -z "$(git remote 2>/dev/null)" ]] && exit 0

BRANCH=$(git branch --show-current 2>/dev/null)
[[ -z "$BRANCH" ]] && exit 0

LOG_FILE="${HOME}/.claude/auto-sync.log"
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [pull] $*" >> "$LOG_FILE"
}

log "=== Session start pull (branch: $BRANCH) ==="

# Stash if dirty, pull, unstash
STASHED=false
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  git stash push --include-untracked -m "auto-sync-session-start-$(date +%s)" >/dev/null 2>&1 && STASHED=true
  log "Stashed before pull"
fi

git pull --rebase origin "$BRANCH" 2>&1 >> "$LOG_FILE" || {
  log "Pull/rebase conflict — aborting rebase"
  git rebase --abort 2>/dev/null || true
}

if $STASHED; then
  git stash pop 2>/dev/null && log "Unstashed OK" || log "Stash pop failed — check git stash list"
fi

log "=== Session start pull END ==="
exit 0
