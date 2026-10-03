#!/usr/bin/env bash
# scripts/inbox-stats.sh - Statistieken over inbox items
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Stats ==="

total_issues=0
total_prs=0
open_issues=0
open_prs=0
closed_issues=0
closed_prs=0
labeled_issues=0
unlabeled_issues=0
assigned_issues=0
unassigned_issues=0
stale_issues=0
stale_prs=0
total_repos=0

# Stale datum
stale_date=$(date -d "$STALE_CLOSE_DAYS days ago" +%Y-%m-%d)

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  total_repos=$((total_repos + 1))

  # Issues statistieken
  issues_json=$(gh issue list --repo "${org}/${repo}" --state all --limit 100 --json number,state,labels,assignees,updatedAt 2>/dev/null || echo "[]")
  if [ "$issues_json" != "[]" ] && [ -n "$issues_json" ]; then
    count=$(echo "$issues_json" | jq 'length' 2>/dev/null || echo "0")
    total_issues=$((total_issues + count))

    open=$(echo "$issues_json" | jq '[.[] | select(.state == "OPEN")] | length' 2>/dev/null || echo "0")
    open_issues=$((open_issues + open))

    closed=$(echo "$issues_json" | jq '[.[] | select(.state == "CLOSED")] | length' 2>/dev/null || echo "0")
    closed_issues=$((closed_issues + closed))

    labeled=$(echo "$issues_json" | jq '[.[] | select(.labels | length > 0)] | length' 2>/dev/null || echo "0")
    labeled_issues=$((labeled_issues + labeled))

    unlabeled=$(echo "$issues_json" | jq '[.[] | select(.labels | length == 0)] | length' 2>/dev/null || echo "0")
    unlabeled_issues=$((unlabeled_issues + unlabeled))

    assigned=$(echo "$issues_json" | jq '[.[] | select(.assignees | length > 0)] | length' 2>/dev/null || echo "0")
    assigned_issues=$((assigned_issues + assigned))

    unassigned=$(echo "$issues_json" | jq '[.[] | select(.assignees | length == 0)] | length' 2>/dev/null || echo "0")
    unassigned_issues=$((unassigned_issues + unassigned))

    stale=$(echo "$issues_json" | jq --arg date "$stale_date" '[.[] | select(.state == "OPEN" and .updatedAt < $date)] | length' 2>/dev/null || echo "0")
    stale_issues=$((stale_issues + stale))
  fi

  # PR statistieken
  prs_json=$(gh pr list --repo "${org}/${repo}" --state all --limit 100 --json number,state,updatedAt,mergeable 2>/dev/null || echo "[]")
  if [ "$prs_json" != "[]" ] && [ -n "$prs_json" ]; then
    count=$(echo "$prs_json" | jq 'length' 2>/dev/null || echo "0")
    total_prs=$((total_prs + count))

    open=$(echo "$prs_json" | jq '[.[] | select(.state == "OPEN")] | length' 2>/dev/null || echo "0")
    open_prs=$((open_prs + open))

    closed=$(echo "$prs_json" | jq '[.[] | select(.state == "CLOSED" or .state == "MERGED")] | length' 2>/dev/null || echo "0")
    closed_prs=$((closed_prs + closed))

    stale=$(echo "$prs_json" | jq --arg date "$stale_date" '[.[] | select(.state == "OPEN" and .updatedAt < $date)] | length' 2>/dev/null || echo "0")
    stale_prs=$((stale_prs + stale))
  fi
done

log "  Repos: $total_repos"
log "  Issues: $total_issues (open: $open_issues, gesloten: $closed_issues)"
log "  PRs: $total_prs (open: $open_prs, gesloten/merged: $closed_prs)"
log "  Gelabelde issues: $labeled_issues, ongelabelde: $unlabeled_issues"
log "  Toegewezen issues: $assigned_issues, niet toegewezen: $unassigned_issues"
log "  Stale issues: $stale_issues, stale PRs: $stale_prs"
log "=== Inbox Stats complete ==="

send_telegram_message "📊 *Inbox Stats*

*Repos:* $total_repos
*Issues:* $total_issues (open: $open_issues, gesloten: $closed_issues)
*PRs:* $total_prs (open: $open_prs, gesloten/merged: $closed_prs)

🏷️ Gelabelde issues: $labeled_issues
📭 Ongelabelde issues: $unlabeled_issues
👤 Toegewezen: $assigned_issues
❓ Niet toegewezen: $unassigned_issues

⏰ Stale issues: $stale_issues
⏰ Stale PRs: $stale_prs

📋 Volledig log: $LOG_FILE" || true