#!/usr/bin/env bash
# scripts/inbox-health.sh - Health check van inbox
# Controleert de gezondheid van de inbox voor alle key repos
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Health Check ==="

# shellcheck disable=SC2206
HEALTH_REPOS=( ${HEALTH_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')

# Tellers
total_stale_issues=0
total_stale_prs=0
total_unassigned_issues=0
total_unlabeled_issues=0
total_failing_ci=0
total_stale_reviews=0

# Fase 1: Stale issues (open > 30 dagen)
log "Fase 1: Stale issues..."
for kr in "${HEALTH_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  stale=$(gh issue list --repo "$kr" --state open --limit 100 --json createdAt --jq "[.[] | select(.createdAt < \"$(date -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-30d '+%Y-%m-%d' 2>/dev/null || echo '2025-01-01')T00:00:00Z\")] | length" 2>/dev/null || echo "0")
  total_stale_issues=$((total_stale_issues + stale))
  [ "$stale" -gt 0 ] && log "  $kr: $stale stale issues"
done

# Fase 2: Stale PRs (open > 14 dagen)
log "Fase 2: Stale PRs..."
for kr in "${HEALTH_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  stale_prs=$(gh pr list --repo "$kr" --state open --limit 100 --json createdAt --jq "[.[] | select(.createdAt < \"$(date -d '14 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-14d '+%Y-%m-%d' 2>/dev/null || echo '2025-01-01')T00:00:00Z\")] | length" 2>/dev/null || echo "0")
  total_stale_prs=$((total_stale_prs + stale_prs))
  [ "$stale_prs" -gt 0 ] && log "  $kr: $stale_prs stale PRs"
done

# Fase 3: Unassigned issues
log "Fase 3: Unassigned issues..."
for kr in "${HEALTH_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  unassigned=$(gh issue list --repo "$kr" --state open --limit 100 --json assignees --jq '[.[] | select(.assignees | length == 0)] | length' 2>/dev/null || echo "0")
  total_unassigned_issues=$((total_unassigned_issues + unassigned))
  [ "$unassigned" -gt 0 ] && log "  $kr: $unassigned unassigned issues"
done

# Fase 4: Unlabeled issues
log "Fase 4: Unlabeled issues..."
for kr in "${HEALTH_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  unlabeled=$(gh issue list --repo "$kr" --state open --limit 100 --json labels --jq '[.[] | select(.labels | length == 0)] | length' 2>/dev/null || echo "0")
  total_unlabeled_issues=$((total_unlabeled_issues + unlabeled))
  [ "$unlabeled" -gt 0 ] && log "  $kr: $unlabeled unlabeled issues"
done

# Fase 5: Failing CI
log "Fase 5: Failing CI..."
for kr in "${HEALTH_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  failing=$(gh run list --repo "$kr" --limit 20 --json conclusion --jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")
  total_failing_ci=$((total_failing_ci + failing))
  [ "$failing" -gt 0 ] && log "  $kr: $failing failing CI runs"
done

# Fase 6: Stale reviews
log "Fase 6: Stale reviews..."
for kr in "${HEALTH_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  stale_reviews=$(gh pr list --repo "$kr" --state open --search "review-requested:@me" --limit 100 --json createdAt --jq "[.[] | select(.createdAt < \"$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d' 2>/dev/null || echo '2025-01-01')T00:00:00Z\")] | length" 2>/dev/null || echo "0")
  total_stale_reviews=$((total_stale_reviews + stale_reviews))
  [ "$stale_reviews" -gt 0 ] && log "  $kr: $stale_reviews stale reviews"
done

# Fase 7: Samenvatting
log "Fase 7: Samenvatting..."
log "  Stale issues: $total_stale_issues"
log "  Stale PRs: $total_stale_prs"
log "  Unassigned issues: $total_unassigned_issues"
log "  Unlabeled issues: $total_unlabeled_issues"
log "  Failing CI: $total_failing_ci"
log "  Stale reviews: $total_stale_reviews"

# Fase 8: Verstuur rapport
send_telegram_message "🏥 *Inbox Health Check* — $TODAY

⚠️ *Stale Issues:* $total_stale_issues
⚠️ *Stale PRs:* $total_stale_prs
📝 *Unassigned Issues:* $total_unassigned_issues
🏷️ *Unlabeled Issues:* $total_unlabeled_issues
🔴 *Failing CI:* $total_failing_ci
👀 *Stale Reviews:* $total_stale_reviews

📋 Volledig log: $LOG_FILE" || true

log "=== Inbox Health Check complete ==="
