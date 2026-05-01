#!/bin/bash
# Auto-sync: auto-commit all changes and push to remote.
# Called by Claude Code Stop hook.

set -euo pipefail

# Must be in a git repo with a remote
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ -z "$(git remote 2>/dev/null)" ]] && exit 0

BRANCH=$(git branch --show-current 2>/dev/null)
[[ -z "$BRANCH" ]] && exit 0

LOG_FILE="${HOME}/.claude/auto-sync.log"
LOCK_FILE="/tmp/git-auto-sync.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Prevent parallel runs
if [[ -f "$LOCK_FILE" ]]; then
  PID=$(cat "$LOCK_FILE" 2>/dev/null)
  if kill -0 "$PID" 2>/dev/null; then
    log "Another sync in progress (PID=$PID), skipping."
    exit 0
  fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log "=== Auto-sync START (branch: $BRANCH) ==="

# ── Step 1: Pull latest from remote (with stash to protect dirty tree) ──────
STASHED=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push --include-untracked -m "auto-sync-pre-pull-$(date +%s)" >/dev/null 2>&1 && STASHED=true
  log "Stashed local changes before pull"
fi

PULL_OUTPUT=$(git pull --rebase origin "$BRANCH" 2>&1) && {
  log "Pull OK: $PULL_OUTPUT"
} || {
  log "Pull had conflicts, aborting rebase and continuing with local state"
  git rebase --abort 2>/dev/null || true
}

if $STASHED; then
  git stash pop 2>/dev/null && log "Unstashed changes" || {
    log "Stash pop conflict — changes remain in stash (run: git stash pop)"
  }
fi

# ── Step 2: Stage and commit any local changes ───────────────────────────────
DIRTY=false
! git diff --quiet && DIRTY=true
! git diff --cached --quiet && DIRTY=true
[[ -n "$(git ls-files --others --exclude-standard)" ]] && DIRTY=true

if $DIRTY; then
  git add -A
  COMMIT_MSG="auto-sync: $(date '+%Y-%m-%d %H:%M:%S')"
  git commit -m "$COMMIT_MSG" --no-verify 2>&1 | tee -a "$LOG_FILE" || {
    log "Commit failed — possibly nothing to commit"
  }
  log "Committed: $COMMIT_MSG"
fi

# ── Step 3: Push unpushed commits ────────────────────────────────────────────
if git rev-parse "origin/$BRANCH" >/dev/null 2>&1; then
  UNPUSHED=$(git rev-list "origin/$BRANCH..HEAD" --count 2>/dev/null || echo 0)
else
  UNPUSHED=$(git rev-list HEAD --count 2>/dev/null || echo 0)
fi

if [[ "$UNPUSHED" -gt 0 ]]; then
  PUSH_OUTPUT=$(git push -u origin "$BRANCH" 2>&1) && {
    log "Pushed $UNPUSHED commit(s): $PUSH_OUTPUT"
  } || {
    log "Push failed: $PUSH_OUTPUT"
    # Non-fatal: don't block Claude from stopping
  }
fi

log "=== Auto-sync END ==="
exit 0
