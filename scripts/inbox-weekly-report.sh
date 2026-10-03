#!/usr/bin/env bash
# scripts/inbox-weekly-report.sh - Wekelijkse samenvatting van inbox items
# Toont nieuwe issues, PRs en activiteit van de afgelopen 7 dagen
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Weekly Report ==="

REPORT_DAYS="${REPORT_DAYS:-7}"
# shellcheck disable=SC2206
REPORT_REPOS=( ${REPORT_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')
WEEK_START=$(date -d "$REPORT_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${REPORT_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "$TODAY")
SINCE=$(date -d "$REPORT_DAYS days ago" '+%Y-%m-%dT00:00:00Z' 2>/dev/null || date -v-${REPORT_DAYS}d '+%Y-%m-%dT00:00:00Z' 2>/dev/null || echo "${TODAY}T00:00:00Z")

# Tellers
total_new_issues=0
total_closed_issues=0
total_new_prs=0
total_merged_prs=0
total_mentions=0
total_reviews=0

# Fase 1: Nieuwe issues
log "Fase 1: Nieuwe issues..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  new_issues=$(gh issue list --repo "$kr" --state open --limit 100 --json createdAt --jq "[.[] | select(.createdAt >= \"${SINCE}\")] | length" 2>/dev/null || echo "0")
  total_new_issues=$((total_new_issues + new_issues))
  [ "$new_issues" -gt 0 ] && log "  $kr: $new_issues nieuwe issues"
done

# Fase 2: Gesloten issues
log "Fase 2: Gesloten issues..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  closed_issues=$(gh issue list --repo "$kr" --state closed --limit 100 --json closedAt --jq "[.[] | select(.closedAt >= \"${SINCE}\")] | length" 2>/dev/null || echo "0")
  total_closed_issues=$((total_closed_issues + closed_issues))
  [ "$closed_issues" -gt 0 ] && log "  $kr: $closed_issues gesloten issues"
done

# Fase 3: Nieuwe PRs
log "Fase 3: Nieuwe PRs..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  new_prs=$(gh pr list --repo "$kr" --state open --limit 100 --json createdAt --jq "[.[] | select(.createdAt >= \"${SINCE}\")] | length" 2>/dev/null || echo "0")
  total_new_prs=$((total_new_prs + new_prs))
  [ "$new_prs" -gt 0 ] && log "  $kr: $new_prs nieuwe PRs"
done

# Fase 4: Gemergde PRs
log "Fase 4: Gemergde PRs..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  merged_prs=$(gh pr list --repo "$kr" --state merged --limit 100 --json mergedAt --jq "[.[] | select(.mergedAt >= \"${SINCE}\")] | length" 2>/dev/null || echo "0")
  total_merged_prs=$((total_merged_prs + merged_prs))
  [ "$merged_prs" -gt 0 ] && log "  $kr: $merged_prs gemergde PRs"
done

# Fase 5: Mentions
log "Fase 5: Mentions..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  mentions=$(gh api "repos/$kr/issues/comments?since=${SINCE}&per_page=100" --jq 'length' 2>/dev/null || echo "0")
  total_mentions=$((total_mentions + mentions))
  [ "$mentions" -gt 0 ] && log "  $kr: $mentions nieuwe comments"
done

# Fase 6: Review requests
log "Fase 6: Review requests..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  reviews=$(gh pr list --repo "$kr" --state open --search "review-requested:@me" --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  total_reviews=$((total_reviews + reviews))
  [ "$reviews" -gt 0 ] && log "  $kr: $reviews review requests"
done

# Fase 7: Samenvatting
log "Fase 7: Samenvatting..."
log "  Nieuwe issues: $total_new_issues"
log "  Gesloten issues: $total_closed_issues"
log "  Nieuwe PRs: $total_new_prs"
log "  Gemergde PRs: $total_merged_prs"
log "  Nieuwe comments: $total_mentions"
log "  Review requests: $total_reviews"

# Fase 8: Verstuur rapport
send_telegram_message "📬 *Inbox Weekly Report* — $WEEK_START tot $TODAY

📝 *Issues*
• Nieuw: $total_new_issues
• Gesloten: $total_closed_issues

🔀 *Pull Requests*
• Nieuw: $total_new_prs
• Gemerged: $total_merged_prs

💬 *Comments:* $total_mentions
👀 *Review Requests:* $total_reviews

📋 Volledig log: $LOG_FILE" || true

log "=== Inbox Weekly Report complete ==="
