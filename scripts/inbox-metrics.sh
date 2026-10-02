#!/usr/bin/env bash
# scripts/inbox-metrics.sh - Metrics over inbox
# Toont gedetailleerde metrics voor alle key repos
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Metrics ==="

# shellcheck disable=SC2206
METRIC_REPOS=( ${METRIC_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')

# Tellers
total_open_issues=0
total_open_prs=0
total_labels=0
total_assignees=0
total_comments=0
total_reviews=0
total_ci_runs=0
total_ci_failures=0

# Fase 1: Open issues
log "Fase 1: Open issues..."
for kr in "${METRIC_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  open_issues=$(gh issue list --repo "$kr" --state open --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  total_open_issues=$((total_open_issues + open_issues))
  [ "$open_issues" -gt 0 ] && log "  $kr: $open_issues open issues"
done

# Fase 2: Open PRs
log "Fase 2: Open PRs..."
for kr in "${METRIC_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  open_prs=$(gh pr list --repo "$kr" --state open --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  total_open_prs=$((total_open_prs + open_prs))
  [ "$open_prs" -gt 0 ] && log "  $kr: $open_prs open PRs"
done

# Fase 3: Labels
log "Fase 3: Labels..."
for kr in "${METRIC_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  labels=$(gh label list --repo "$kr" --limit 100 --json name --jq 'length' 2>/dev/null || echo "0")
  total_labels=$((total_labels + labels))
  [ "$labels" -gt 0 ] && log "  $kr: $labels labels"
done

# Fase 4: Comments
log "Fase 4: Comments..."
for kr in "${METRIC_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  comments=$(gh api "repos/$kr/issues/comments?per_page=100" --jq 'length' 2>/dev/null || echo "0")
  total_comments=$((total_comments + comments))
  [ "$comments" -gt 0 ] && log "  $kr: $comments comments"
done

# Fase 5: Reviews
log "Fase 5: Reviews..."
for kr in "${METRIC_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  reviews=$(gh pr list --repo "$kr" --state open --search "review-requested:@me" --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  total_reviews=$((total_reviews + reviews))
  [ "$reviews" -gt 0 ] && log "  $kr: $reviews review requests"
done

# Fase 6: CI runs
log "Fase 6: CI runs..."
for kr in "${METRIC_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  ci_runs=$(gh run list --repo "$kr" --limit 50 --json conclusion --jq 'length' 2>/dev/null || echo "0")
  total_ci_runs=$((total_ci_runs + ci_runs))
  
  ci_failures=$(gh run list --repo "$kr" --limit 50 --json conclusion --jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")
  total_ci_failures=$((total_ci_failures + ci_failures))
  
  [ "$ci_runs" -gt 0 ] && log "  $kr: $ci_runs CI runs ($ci_failures failures)"
done

# Fase 7: Samenvatting
log "Fase 7: Samenvatting..."
log "  Open issues: $total_open_issues"
log "  Open PRs: $total_open_prs"
log "  Labels: $total_labels"
log "  Comments: $total_comments"
log "  Reviews: $total_reviews"
log "  CI runs: $total_ci_runs"
log "  CI failures: $total_ci_failures"

# Fase 8: Verstuur rapport
send_telegram_message "📊 *Inbox Metrics* — $TODAY

📝 *Open Issues:* $total_open_issues
🔀 *Open PRs:* $total_open_prs
🏷️ *Labels:* $total_labels
💬 *Comments:* $total_comments
👀 *Reviews:* $total_reviews
🔄 *CI Runs:* $total_ci_runs
🔴 *CI Failures:* $total_ci_failures

📋 Volledig log: $LOG_FILE" || true

log "=== Inbox Metrics complete ==="
