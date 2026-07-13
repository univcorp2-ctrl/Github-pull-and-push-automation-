#!/bin/bash
# Shell integration for git auto-sync.
# Source this file from ~/.bashrc or ~/.zshrc.
#
# Usage: source ~/.claude/shell-auto-sync.sh
#
# Provides:
#   gsync       — pull + add + commit + push in one command
#   gwatch      — background file watcher that auto-commits every N seconds

# ── gsync: one-shot full sync ────────────────────────────────────────────────
gsync() {
  local MSG="${1:-auto-sync: $(date '+%Y-%m-%d %H:%M:%S')}"
  local BRANCH
  BRANCH=$(git branch --show-current 2>/dev/null) || { echo "Not in a git repo."; return 1; }

  echo "[gsync] Pulling latest from origin/$BRANCH..."
  if ! git diff --quiet || ! git diff --cached --quiet; then
    git stash push --include-untracked -m "gsync-pre-pull-$(date +%s)" >/dev/null
    git pull --rebase origin "$BRANCH" || { git rebase --abort 2>/dev/null; git stash pop 2>/dev/null; }
    git stash pop 2>/dev/null || true
  else
    git pull --rebase origin "$BRANCH" || git rebase --abort 2>/dev/null
  fi

  if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "[gsync] Committing changes..."
    git add -A
    git commit -m "$MSG" --no-verify
  else
    echo "[gsync] Nothing to commit."
  fi

  local UNPUSHED
  UNPUSHED=$(git rev-list "origin/$BRANCH..HEAD" --count 2>/dev/null || echo 0)
  if [[ "$UNPUSHED" -gt 0 ]]; then
    echo "[gsync] Pushing $UNPUSHED commit(s) to origin/$BRANCH..."
    git push -u origin "$BRANCH"
  else
    echo "[gsync] Already up to date."
  fi
}

# ── gwatch: background auto-commit every N seconds ──────────────────────────
_GWATCH_PID=""

gwatch() {
  local INTERVAL="${1:-60}"  # default: every 60 seconds
  local REPO_ROOT
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo."; return 1; }

  if [[ -n "$_GWATCH_PID" ]] && kill -0 "$_GWATCH_PID" 2>/dev/null; then
    echo "[gwatch] Already watching (PID=$_GWATCH_PID). Stop it with: gwatch_stop"
    return 0
  fi

  echo "[gwatch] Watching $REPO_ROOT every ${INTERVAL}s... (stop with: gwatch_stop)"
  (
    cd "$REPO_ROOT" || exit
    LOG_FILE="${HOME}/.claude/auto-sync.log"
    while true; do
      sleep "$INTERVAL"
      if ! git diff --quiet 2>/dev/null || \
         ! git diff --cached --quiet 2>/dev/null || \
         [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        BRANCH=$(git branch --show-current 2>/dev/null)
        if [[ -n "$BRANCH" && -n "$(git remote 2>/dev/null)" ]]; then
          git add -A >/dev/null 2>&1
          git commit -m "auto-sync: $(date '+%Y-%m-%d %H:%M:%S')" --no-verify \
            >> "$LOG_FILE" 2>&1
          git push -u origin "$BRANCH" >> "$LOG_FILE" 2>&1
        fi
      fi
    done
  ) &
  _GWATCH_PID=$!
  echo "[gwatch] Started PID=$_GWATCH_PID"
}

gwatch_stop() {
  if [[ -n "$_GWATCH_PID" ]] && kill -0 "$_GWATCH_PID" 2>/dev/null; then
    kill "$_GWATCH_PID"
    echo "[gwatch] Stopped PID=$_GWATCH_PID"
    _GWATCH_PID=""
  else
    echo "[gwatch] No watcher running."
  fi
}
