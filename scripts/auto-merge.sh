#!/usr/bin/env bash
# scripts/auto-merge.sh - Merge automatisch kleine PRs
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Merge ==="
merged=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  # Zoek open PRs die mergeable zijn en klein (onder PR_SIZE_THRESHOLD)
  prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,title,additions,deletions,mergeable,mergeStateStatus --jq '.[] | select(.mergeable == "MERGEABLE" and .mergeStateStatus == "CLEAN" and (.additions + .deletions) < '"$PR_SIZE_THRESHOLD"') | "\(.number)|\(.title)|\(.additions + .deletions)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r num title size; do
      [ -z "$num" ] && continue
      log "  PR #$num: $title ($size reges) → mergen..."
      gh pr merge "${org}/${repo}#${num}" --merge --delete-branch 2>/dev/null && ((merged++)) || true
    done <<< "$prs"
  fi
done
log "=== Auto Merge complete: $merged PRs gemerged ==="
send_telegram_message "🔀 *Auto Merge*\n\n*Gemerged:* $merged PRs\n\n📋 Volledig log: $LOG_FILE" || true