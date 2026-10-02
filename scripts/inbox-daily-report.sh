#!/usr/bin/env bash
# scripts/inbox-daily-report.sh - Dagelijkse samenvatting van inbox items
# Toont nieuwe issues, PRs en activiteit van de afgelopen 24 uur
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Daily Report ==="

REPORT_DAYS="${REPORT_DAYS:-1}"
# shellcheck disable=SC2206
REPORT_REPOS=( ${REPORT_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')
SINCE=$(date -d "$REPORT_DAYS days ago" '+%Y-%m-%dT00:00:00Z' 2>/dev/null || date -v-${REPORT_DAYS}d '+%Y-%m-%dT00:00:00Z' 2>/dev/null || echo "${TODAY}T00:00:00Z")

# Tellers
total_new_issues=0
total_new_prs=0
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

# Fase 2: Nieuwe PRs
log "Fase 2: Nieuwe PRs..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  new_prs=$(gh pr list --repo "$kr" --state open --limit 100 --json createdAt --jq "[.[] | select(.createdAt >= \"${SINCE}\")] | length" 2>/dev/null || echo "0")
  total_new_prs=$((total_new_prs + new_prs))
  [ "$new_prs" -gt 0 ] && log "  $kr: $new_prs nieuwe PRs"
done

# Fase 3: Mentions
log "Fase 3: Mentions..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  mentions=$(gh api "repos/$kr/issues/comments?since=${SINCE}&per_page=100" --jq 'length' 2>/dev/null || echo "0")
  total_mentions=$((total_mentions + mentions))
  [ "$mentions" -gt 0 ] && log "  $kr: $mentions nieuwe comments"
done

# Fase 4: Review requests
log "Fase 4: Review requests..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  reviews=$(gh pr list --repo "$kr" --state open --search "review-requested:@me" --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  total_reviews=$((total_reviews + reviews))
  [ "$reviews" -gt 0 ] && log "  $kr: $reviews review requests"
done

# Fase 5: Samenvatting
log "Fase 5: Samenvatting..."
log "  Nieuwe issues: $total_new_issues"
log "  Nieuwe PRs: $total_new_prs"
log "  Nieuwe comments: $total_mentions"
log "  Review requests: $total_reviews"

# Fase 6: Verstuur rapport
send_telegram_message "📬 *Inbox Daily Report* — $TODAY

📝 *Nieuwe Issues:* $total_new_issues
🔀 *Nieuwe PRs:* $total_new_prs
💬 *Nieuwe Comments:* $total_mentions
👀 *Review Requests:* $total_reviews

📋 Volledig log: $LOG_FILE" || true

log "=== Inbox Daily Report complete ==="
