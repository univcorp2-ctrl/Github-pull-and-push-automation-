<#
.SYNOPSIS
  GPT/ChatGPTで作成したスクリプト群を、指定フォルダーからGitHubリポジトリへ「1回のcommit/push」でまとめて反映するPowerShellスクリプト。

.DESCRIPTION
  - ChatGPTのプロジェクト/特定フォルダーを直接読むものではありません。
  - GPTで作ったスクリプトをローカルPCの任意フォルダーへ保存しておき、そのフォルダーをこのスクリプトでGitHubへまとめて反映します。
  - 既存リポジトリをclone/pullしてから、指定フォルダーの中身を同期し、1回だけcommitし、1回だけpushします。
  - .env / secrets / token / node_modules / .git などは除外します。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tools\gpt_folder_bulk_push.ps1 `
    -SourceFolder "G:\マイドライブ\AI_Agents\gpt_scripts" `
    -RepoUrl "https://github.com/univcorp2-ctrl/Github-pull-and-push-automation-.git" `
    -WorkFolder "G:\マイドライブ\AI_Agents\github\repos\Github-pull-and-push-automation-" `
    -TargetSubFolder "collected_gpt_scripts" `
    -Branch "main" `
    -CommitMessage "bulk import GPT developed scripts"

.NOTES
  事前条件:
  1. WindowsにGitをインストール済み
  2. GitHub認証済み（GitHub Desktop / gh auth login / Personal Access Token 等）
  3. SourceFolderにGPTで作成したスクリプトを保存済み
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$SourceFolder,

  [Parameter(Mandatory=$true)]
  [string]$RepoUrl,

  [Parameter(Mandatory=$true)]
  [string]$WorkFolder,

  [string]$TargetSubFolder = "collected_gpt_scripts",
  [string]$Branch = "main",
  [string]$CommitMessage = "bulk import GPT developed scripts",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step($message) {
  Write-Host "`n== $message ==" -ForegroundColor Cyan
}

function Assert-Command($commandName) {
  if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
    throw "必要なコマンドが見つかりません: $commandName"
  }
}

function Resolve-FullPath([string]$path) {
  return [System.IO.Path]::GetFullPath($path)
}

Assert-Command git

$SourceFolder = Resolve-FullPath $SourceFolder
$WorkFolder = Resolve-FullPath $WorkFolder

if (-not (Test-Path $SourceFolder)) {
  throw "SourceFolderが存在しません: $SourceFolder"
}

$sourceItem = Get-Item $SourceFolder
if (-not $sourceItem.PSIsContainer) {
  throw "SourceFolderはフォルダーを指定してください: $SourceFolder"
}

Write-Step "入力確認"
Write-Host "SourceFolder   : $SourceFolder"
Write-Host "RepoUrl        : $RepoUrl"
Write-Host "WorkFolder     : $WorkFolder"
Write-Host "TargetSubFolder: $TargetSubFolder"
Write-Host "Branch         : $Branch"
Write-Host "DryRun         : $DryRun"

Write-Step "リポジトリ準備"
if (-not (Test-Path $WorkFolder)) {
  New-Item -ItemType Directory -Path (Split-Path $WorkFolder -Parent) -Force | Out-Null
  git clone $RepoUrl $WorkFolder
}

Set-Location $WorkFolder

git fetch origin
$branchExists = git branch --list $Branch
if (-not $branchExists) {
  git checkout -B $Branch "origin/$Branch"
} else {
  git checkout $Branch
}

git pull --ff-only origin $Branch

$targetPath = Join-Path $WorkFolder $TargetSubFolder
if (-not (Test-Path $targetPath)) {
  New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
}

Write-Step "安全除外ルールつきで同期"
$excludeDirs = @(
  ".git", ".venv", "venv", "env", "node_modules", "__pycache__", ".pytest_cache",
  ".mypy_cache", ".ruff_cache", "dist", "build", ".next", ".turbo"
)

$excludeFilePatterns = @(
  ".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "*secret*", "*token*", "*credential*", "credentials.json", "token.json"
)

# 既存同期先を完全削除してからコピー。ただしリポジトリ直下は消さない。
if (Test-Path $targetPath) {
  Get-ChildItem -LiteralPath $targetPath -Force | Remove-Item -Recurse -Force
}

$copied = 0
$skipped = 0

Get-ChildItem -LiteralPath $SourceFolder -Recurse -Force | ForEach-Object {
  $item = $_
  $relativePath = $item.FullName.Substring($SourceFolder.Length).TrimStart("\", "/")
  if ([string]::IsNullOrWhiteSpace($relativePath)) { return }

  $parts = $relativePath -split "[\\/]"
  foreach ($part in $parts) {
    if ($excludeDirs -contains $part) {
      $script:skipped++
      return
    }
  }

  foreach ($pattern in $excludeFilePatterns) {
    if ($item.Name -like $pattern) {
      $script:skipped++
      return
    }
  }

  $dest = Join-Path $targetPath $relativePath

  if ($item.PSIsContainer) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
  } else {
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
    $script:copied++
  }
}

Write-Host "Copied files : $copied"
Write-Host "Skipped items : $skipped"

Write-Step "差分確認"
git status --short

$changes = git status --porcelain
if (-not $changes) {
  Write-Host "変更なし。commit/pushは不要です。" -ForegroundColor Yellow
  exit 0
}

if ($DryRun) {
  Write-Host "DryRunのためcommit/pushしません。" -ForegroundColor Yellow
  exit 0
}

Write-Step "1回だけcommitして1回だけpush"
git add --all
git commit -m $CommitMessage
git push origin $Branch

Write-Step "完了"
Write-Host "GitHubへまとめてpushしました。" -ForegroundColor Green
