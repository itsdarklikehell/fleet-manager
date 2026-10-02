#!/usr/bin/env bash
# scripts/auto-responder.sh - Auto-responder voor nieuwe issues
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Responder ==="
responded=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  # Zoek open issues die nog geen reactie hebben (gemaakt in de laatste 24u)
  issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,createdAt,author --jq '.[] | select(.createdAt > "'"$(date -d '24 hours ago' +%Y-%m-%d)"'") | "\(.number)|\(.title)|\(.author.login)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title author; do
      [ -z "$num" ] && continue
      log "  Issue #$num: $title → reageren..."
      body="Thanks for opening this issue, @$author! 👋\n\nWe've received your report and will review it shortly. A maintainer will respond as soon as possible.\n\nIf you haven't already, please make sure you've provided:\n- A clear description of the problem\n- Steps to reproduce\n- Your environment details\n\nThis is an automated response."
      gh issue comment "${org}/${repo}#${num}" --body "$body" 2>/dev/null && ((responded++)) || true
    done <<< "$issues"
  fi
done
log "=== Auto Responder complete: $responded issues beantwoord ==="
send_telegram_message "💬 *Auto Responder*\n\n*Beantwoord:* $responded issues\n\n📋 Volledig log: $LOG_FILE" || true