#!/usr/bin/env bash
# scripts/inbox-auto-merge.sh - Merge automatisch kleine PRs
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Auto Merge ==="

merged=0
skipped=0
merge_threshold="${INBOX_MERGE_THRESHOLD:-$PR_SIZE_THRESHOLD}"

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Zoek open PRs die mergeable zijn en klein
  prs=$(gh pr list --repo "${org}/${repo}" --state open --limit 50 --json number,title,additions,deletions,mergeable,mergeStateStatus,labels --jq --arg threshold "$merge_threshold" '.[] | select(.mergeable == "MERGEABLE" and .mergeStateStatus == "CLEAN" and (.additions + .deletions) < ($threshold | tonumber)) | select(.labels | map(.name) | index("do-not-merge") | not) | "\(.number)|\(.title)|\(.additions + .deletions)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r num title size; do
      [ -z "$num" ] && continue
      log "  PR #$num: $title ($size regels) → mergen..."
      if gh pr merge "${org}/${repo}#${num}" --merge --delete-branch 2>/dev/null; then
        merged=$((merged + 1))
      else
        skipped=$((skipped + 1))
      fi
    done <<< "$prs"
  fi
done

log "  Gemergede PRs: $merged"
log "  Overgeslagen: $skipped"
log "=== Inbox Auto Merge complete ==="

send_telegram_message "🔀 *Inbox Auto Merge*

*Gemerged:* $merged PRs
*Overgeslagen:* $skipped

📏 Threshold: ${merge_threshold} regels

📋 Volledig log: $LOG_FILE" || true