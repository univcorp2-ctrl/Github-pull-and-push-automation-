#!/bin/bash
# One-shot setup: installs all auto-sync hooks and shell integration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${HOME}/.git-hooks"

echo "=== GitHub Auto-Sync Setup ==="

# ── 1. Claude config dir ─────────────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR"

for f in git-auto-sync.sh git-auto-pull.sh stop-hook-git-check.sh shell-auto-sync.sh; do
  cp "$SCRIPT_DIR/$f" "$CLAUDE_DIR/$f"
  chmod +x "$CLAUDE_DIR/$f"
  echo "  Installed: ~/.claude/$f"
done

# ── 2. Merge UserPromptSubmit hook into settings.json ────────────────────────
SETTINGS="$CLAUDE_DIR/settings.json"
if [[ ! -f "$SETTINGS" ]]; then
  cat > "$SETTINGS" <<'JSON'
{
    "$schema": "https://json.schemastore.org/claude-code-settings.json",
    "hooks": {},
    "permissions": { "allow": ["Skill"] }
}
JSON
fi

# Add hooks if not already present (requires jq)
if command -v jq >/dev/null 2>&1; then
  TMP=$(mktemp)
  jq '
    .hooks["UserPromptSubmit"] //= [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/git-auto-pull.sh"}]}] |
    .hooks["Stop"] //= [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/stop-hook-git-check.sh"}]}]
  ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
  echo "  Updated: ~/.claude/settings.json"
else
  echo "  WARNING: jq not found — please add UserPromptSubmit and Stop hooks manually to ~/.claude/settings.json"
fi

# ── 3. Global git hooks ───────────────────────────────────────────────────────
mkdir -p "$HOOKS_DIR"
for f in post-commit post-merge; do
  cp "$SCRIPT_DIR/$f" "$HOOKS_DIR/$f"
  chmod +x "$HOOKS_DIR/$f"
  echo "  Installed: ~/.git-hooks/$f"
done
git config --global core.hooksPath "$HOOKS_DIR"
echo "  Set git config --global core.hooksPath ~/.git-hooks"

# ── 4. Shell integration (.bashrc / .zshrc) ───────────────────────────────────
SHELL_LINE='source ~/.claude/shell-auto-sync.sh 2>/dev/null || true'

for rc in ~/.bashrc ~/.zshrc; do
  if [[ -f "$rc" ]] && ! grep -q "shell-auto-sync" "$rc"; then
    echo "" >> "$rc"
    echo "# Git auto-sync (gsync / gwatch)" >> "$rc"
    echo "$SHELL_LINE" >> "$rc"
    echo "  Added to $rc"
  fi
done

echo ""
echo "=== Setup complete ==="
echo "  Reload your shell:  source ~/.bashrc"
echo "  Manual sync:        gsync"
echo "  Background watch:   gwatch [seconds]"
echo "  View logs:          tail -f ~/.claude/auto-sync.log"
