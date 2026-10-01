#!/usr/bin/env bash
# scripts/pr-review-auto.sh - PR review automation
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== PR Review Auto ==="
reviewed=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,title,author --jq '.[] | "\(.number)|\(.title)|@\(.author.login)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r num title author; do
      [ -z "$num" ] && continue
      log "  PR #$num: $title ($author)"
      reviews=$(gh api "repos/${org}/${repo}/pulls/$num/reviews" --jq 'length' 2>/dev/null || echo "0")
      if [ "$reviews" = "0" ]; then
        log "    → Geen review, toevoegen..."
        gh pr review "${org}/${repo}#${num}" --approve --body "✅ Auto-approved by GitHub Fleet Manager" 2>/dev/null && ((reviewed++)) || true
      fi
    done <<< "$prs"
  fi
done
log "=== PR Review Auto complete: $reviewed PRs reviewed ==="
send_telegram_message "👀 *PR Review Auto*\n\n*Reviewed:* $reviewed PRs\n\n📋 Volledig log: $LOG_FILE" || true
