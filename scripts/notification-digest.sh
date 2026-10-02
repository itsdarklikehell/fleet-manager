#!/usr/bin/env bash
# scripts/notification-digest.sh - Dagelijkse samenvatting van GitHub activiteit
# Combineert alle rapporten in één digest en stuurt naar Telegram
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Notification Digest ==="

# Configuratie
DIGEST_DAYS="${DIGEST_DAYS:-1}"
DIGEST_REPOS=(${DIGEST_REPOS:-"${KEY_REPOS[@]}"})

# Tellers
total_issues=0
total_prs=0
total_mentions=0
total_review_requests=0
total_ci_failures=0
total_commits=0

# Fase 1: Issues verzamelen
log "Fase 1: Issues verzamelen..."
for kr in "${DIGEST_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  issues=$(gh issue list --repo "$kr" --state open --limit 50 --json number,title,createdAt --jq 'length' 2>/dev/null || echo "0")
  total_issues=$((total_issues + issues))
  [ "$issues" -gt 0 ] && log "  $kr: $issues open issues"
done

# Fase 2: PRs verzamelen
log "Fase 2: PRs verzamelen..."
for kr in "${DIGEST_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  prs=$(gh pr list --repo "$kr" --state open --limit 50 --json number,title,createdAt --jq 'length' 2>/dev/null || echo "0")
  total_prs=$((total_prs + prs))
  [ "$prs" -gt 0 ] && log "  $kr: $prs open PRs"
done

# Fase 3: Mentions verzamelen
log "Fase 3: Mentions verzamelen..."
mentions_data=$(gh api notifications --paginate --jq '[.[] | select(.reason == "mention")] | length' 2>/dev/null || echo "0")
total_mentions=$((total_mentions + mentions_data))
[ "$total_mentions" -gt 0 ] && log "  itsdarklikehell: $total_mentions mentions"

if [ -n "$HMOL33_TOKEN" ]; then
  hmol33_mentions=$(GITHUB_TOKEN="$HMOL33_TOKEN" gh api notifications --paginate --jq '[.[] | select(.reason == "mention")] | length' 2>/dev/null || echo "0")
  total_mentions=$((total_mentions + hmol33_mentions))
  [ "$hmol33_mentions" -gt 0 ] && log "  hmol33: $hmol33_mentions mentions"
fi

# Fase 4: Review requests verzamelen
log "Fase 4: Review requests verzamelen..."
review_requests_data=$(gh api notifications --paginate --jq '[.[] | select(.reason == "review_requested")] | length' 2>/dev/null || echo "0")
total_review_requests=$((total_review_requests + review_requests_data))
[ "$total_review_requests" -gt 0 ] && log "  itsdarklikehell: $total_review_requests review requests"

if [ -n "$HMOL33_TOKEN" ]; then
  hmol33_review=$(GITHUB_TOKEN="$HMOL33_TOKEN" gh api notifications --paginate --jq '[.[] | select(.reason == "review_requested")] | length' 2>/dev/null || echo "0")
  total_review_requests=$((total_review_requests + hmol33_review))
  [ "$hmol33_review" -gt 0 ] && log "  hmol33: $hmol33_review review requests"
fi

# Fase 5: CI failures verzamelen
log "Fase 5: CI failures verzamelen..."
for kr in "${DIGEST_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  failed_runs=$(gh run list --repo "$kr" --limit 10 --json name,conclusion --jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")
  total_ci_failures=$((total_ci_failures + failed_runs))
  [ "$failed_runs" -gt 0 ] && log "  $kr: $failed_runs failed run(s)"
done

# Fase 6: Commits vandaag
log "Fase 6: Commits vandaag verzamelen..."
TODAY=$(date '+%Y-%m-%d')
for kr in "${DIGEST_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  commits=$(gh api "repos/$kr/commits?since=${TODAY}T00:00:00Z&per_page=100" --jq 'length' 2>/dev/null || echo "0")
  total_commits=$((total_commits + commits))
  [ "$commits" -gt 0 ] && log "  $kr: $commits commits vandaag"
done

# Fase 7: Digest samenstellen
log "Fase 7: Digest samenstellen..."
log "  Totaal issues: $total_issues"
log "  Totaal PRs: $total_prs"
log "  Totaal mentions: $total_mentions"
log "  Totaal review requests: $total_review_requests"
log "  Totaal CI failures: $total_ci_failures"
log "  Totaal commits vandaag: $total_commits"

# Fase 8: Verstuur digest
DIGEST_DATE=$(date '+%Y-%m-%d')
send_telegram_message "📬 *GitHub Notification Digest* — $DIGEST_DATE

📊 *Samenvatting*
• Open issues: $total_issues
• Open PRs: $total_prs
• Mentions: $total_mentions
• Review requests: $total_review_requests
• CI failures: $total_ci_failures
• Commits vandaag: $total_commits

📋 Volledig log: $LOG_FILE" || true

log "=== Notification Digest complete ==="