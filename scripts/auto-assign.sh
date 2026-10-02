#!/usr/bin/env bash
# scripts/auto-assign.sh - Voegt automatisch assignees toe aan nieuwe issues
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Assign ==="
assigned=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  # Zoek open issues zonder assignees
  issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,assignees --jq '.[] | select(.assignees | length == 0) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      # Bepaal assignee op basis van repo
      assignee=""
      case "$repo" in
        hermes-desktop|hermes-pixel-office-enhanced) assignee="hmol33" ;;
        hermes-agent|clawhub) assignee="hmol33" ;;
        mission-control|dnd-utils) assignee="hmol33" ;;
        *) assignee="hmol33" ;;
      esac
      if [ -n "$assignee" ]; then
        log "  Issue #$num: $title → assignee: $assignee"
        gh issue edit "${num}" --repo "${org}/${repo}" --add-assignee "$assignee" 2>/dev/null && ((assigned++)) || true
      fi
    done <<< "$issues"
  fi
done
log "=== Auto Assign complete: $assigned issues toegewezen ==="
send_telegram_message "👤 *Auto Assign*\n\n*Toegewezen:* $assigned issues\n\n📋 Volledig log: $LOG_FILE" || true