#!/usr/bin/env bash
set -euo pipefail

# GPT/ChatGPTで作成したスクリプト群を、指定フォルダーからGitHubリポジトリへ
# 1回のcommit/pushでまとめて反映するmacOS/Linux/Git Bash用スクリプト。
#
# Usage:
#   bash tools/gpt_folder_bulk_push.sh \
#     --source "/path/to/gpt_scripts" \
#     --repo "https://github.com/univcorp2-ctrl/Github-pull-and-push-automation-.git" \
#     --workdir "/path/to/repos/Github-pull-and-push-automation-" \
#     --target "collected_gpt_scripts" \
#     --branch "main" \
#     --message "bulk import GPT developed scripts"

SOURCE=""
REPO=""
WORKDIR=""
TARGET="collected_gpt_scripts"
BRANCH="main"
MESSAGE="bulk import GPT developed scripts"
DRY_RUN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --message) MESSAGE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="1"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SOURCE" || -z "$REPO" || -z "$WORKDIR" ]]; then
  echo "Required: --source, --repo, --workdir" >&2
  exit 1
fi

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo "rsync is required" >&2; exit 1; }

if [[ ! -d "$SOURCE" ]]; then
  echo "Source folder does not exist: $SOURCE" >&2
  exit 1
fi

echo "== Input =="
echo "SOURCE : $SOURCE"
echo "REPO   : $REPO"
echo "WORKDIR: $WORKDIR"
echo "TARGET : $TARGET"
echo "BRANCH : $BRANCH"
echo "DRY_RUN: $DRY_RUN"

echo "== Prepare repository =="
if [[ ! -d "$WORKDIR/.git" ]]; then
  mkdir -p "$(dirname "$WORKDIR")"
  git clone "$REPO" "$WORKDIR"
fi

cd "$WORKDIR"
git fetch origin
git checkout "$BRANCH" 2>/dev/null || git checkout -B "$BRANCH" "origin/$BRANCH"
git pull --ff-only origin "$BRANCH"

mkdir -p "$TARGET"

# 同期先の中身だけ削除
find "$TARGET" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

echo "== Sync with safety excludes =="
rsync -av --delete \
  --exclude='.git/' \
  --exclude='.venv/' \
  --exclude='venv/' \
  --exclude='env/' \
  --exclude='node_modules/' \
  --exclude='__pycache__/' \
  --exclude='.pytest_cache/' \
  --exclude='.mypy_cache/' \
  --exclude='.ruff_cache/' \
  --exclude='dist/' \
  --exclude='build/' \
  --exclude='.next/' \
  --exclude='.turbo/' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='*.pem' \
  --exclude='*.key' \
  --exclude='*.p12' \
  --exclude='*.pfx' \
  --exclude='*secret*' \
  --exclude='*token*' \
  --exclude='*credential*' \
  --exclude='credentials.json' \
  --exclude='token.json' \
  "$SOURCE/" "$TARGET/"

echo "== Git status =="
git status --short

if [[ -z "$(git status --porcelain)" ]]; then
  echo "No changes. Nothing to commit/push."
  exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run. Skip commit/push."
  exit 0
fi

echo "== Commit and push once =="
git add --all
git commit -m "$MESSAGE"
git push origin "$BRANCH"

echo "Done."
