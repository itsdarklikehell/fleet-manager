#!/usr/bin/env bash
# scripts/inbox-auto-assign.sh - Wijs automatisch assignees toe
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Auto Assign ==="

assigned=0
skipped=0

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Zoek open issues zonder assignees
  issues=$(gh issue list --repo "${org}/${repo}" --state open --limit 100 --json number,title,labels,assignees --jq '.[] | select(.assignees | length == 0) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue

      # Bepaal assignee op basis van repo
      assignee=""
      case "$repo" in
        hermes-desktop|hermes-pixel-office-enhanced) assignee="itsdarklikehell" ;;
        hermes-agent|clawhub) assignee="itsdarklikehell" ;;
        mission-control|dnd-utils) assignee="itsdarklikehell" ;;
        *) assignee="itsdarklikehell" ;;
      esac

      if [ -n "$assignee" ]; then
        log "  Issue #$num: $title → assignee: $assignee"
        if gh issue edit "${num}" --repo "${org}/${repo}" --add-assignee "$assignee" 2>/dev/null; then
          assigned=$((assigned + 1))
        else
          skipped=$((skipped + 1))
        fi
      fi
    done <<< "$issues"
  fi

  # Zoek open PRs zonder assignees
  prs=$(gh pr list --repo "${org}/${repo}" --state open --limit 100 --json number,title,assignees --jq '.[] | select(.assignees | length == 0) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue

      assignee=""
      case "$repo" in
        hermes-desktop|hermes-pixel-office-enhanced) assignee="itsdarklikehell" ;;
        hermes-agent|clawhub) assignee="itsdarklikehell" ;;
        mission-control|dnd-utils) assignee="itsdarklikehell" ;;
        *) assignee="itsdarklikehell" ;;
      esac

      if [ -n "$assignee" ]; then
        log "  PR #$num: $title → assignee: $assignee"
        if gh pr edit "${num}" --repo "${org}/${repo}" --add-assignee "$assignee" 2>/dev/null; then
          assigned=$((assigned + 1))
        else
          skipped=$((skipped + 1))
        fi
      fi
    done <<< "$prs"
  fi
done

log "  Toegewezen items: $assigned"
log "  Overgeslagen: $skipped"
log "=== Inbox Auto Assign complete ==="

send_telegram_message "👤 *Inbox Auto Assign*

*Toegewezen:* $assigned items
*Overgeslagen:* $skipped

📋 Volledig log: $LOG_FILE" || true