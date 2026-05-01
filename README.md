# GitHub Pull & Push Automation

ローカル・Claude Code・GitHub を常に自動同期する仕組みです。

## 動作の概要

| タイミング | 動作 |
|---|---|
| Claude Code セッション開始（最初のプロンプト時） | `git pull --rebase` で最新を取得 |
| Claude Code セッション終了時 | `git add -A` → `git commit` → `git push` を自動実行 |
| 任意のターミナルで `git commit` した後 | `post-commit` フックで自動プッシュ |
| 任意のターミナルで手動同期したいとき | `gsync` コマンド |
| バックグラウンドで定期同期したいとき | `gwatch [秒数]` コマンド |

## インストール

```bash
# 1. このリポジトリをクローン
git clone <repo-url>
cd Github-pull-and-push-automation-

# 2. セットアップスクリプトを実行
bash scripts/setup.sh
```

## ファイル構成

```
scripts/
  setup.sh              — 一括セットアップスクリプト
  git-auto-sync.sh      — コミット＋プッシュ本体（Claude Code Stop hook から呼ばれる）
  git-auto-pull.sh      — プル本体（Claude Code UserPromptSubmit hook から呼ばれる）
  stop-hook-git-check.sh — Claude Code Stop hook エントリポイント
  shell-auto-sync.sh    — シェル統合（gsync / gwatch コマンド定義）
  post-commit           — グローバル git post-commit hook
  post-merge            — グローバル git post-merge hook
```

## 手動コマンド（シェル統合後）

```bash
# 完全同期（pull → commit → push）
gsync
gsync "カスタムコミットメッセージ"

# バックグラウンドで 60 秒ごとに自動同期
gwatch
gwatch 30   # 30 秒ごと

# バックグラウンド同期を停止
gwatch_stop
```

## ログ

`~/.claude/auto-sync.log` にすべての同期操作が記録されます。

```bash
tail -f ~/.claude/auto-sync.log
```

## 競合（コンフリクト）の扱い

- プル前にローカル変更を `git stash` で退避
- `--rebase` でリモートの変更を取り込む
- その後 `git stash pop` でローカル変更を復元
- stash pop でコンフリクトが発生した場合はそのまま保持し、ログに記録（データは失われない）
