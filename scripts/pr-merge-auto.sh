#!/usr/bin/env bash
# scripts/pr-merge-auto.sh - PR merge automation
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== PR Merge Auto ==="
merged=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,title,mergeable,mergeStateStatus --jq '.[] | select(.mergeable == "MERGEABLE" and .mergeStateStatus == "CLEAN") | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      log "  PR #$num: $title → mergen..."
      gh pr merge "${org}/${repo}#${num}" --merge --delete-branch 2>/dev/null && ((merged++)) || true
    done <<< "$prs"
  fi
done
log "=== PR Merge Auto complete: $merged PRs gemerged ==="
send_telegram_message "🔀 *PR Merge Auto*\n\n*Gemerged:* $merged PRs\n\n📋 Volledig log: $LOG_FILE" || true
