#!/usr/bin/env bash
# scripts/activity-report.sh - Rapporteert alle activiteit van de dag
# Toont issues, PRs, commits en CI status voor alle key repos
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Activity Report ==="

REPORT_DAYS="${REPORT_DAYS:-1}"
# shellcheck disable=SC2206
REPORT_REPOS=( ${REPORT_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')

# Tellers
total_issues_opened=0
total_issues_closed=0
total_prs_opened=0
total_prs_merged=0
total_commits=0
total_ci_failures=0

# Fase 1: Issues activiteit
log "Fase 1: Issues activiteit..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  # Issues geopend vandaag
  opened=$(gh issue list --repo "$kr" --state open --limit 100 --json createdAt --jq "[.[] | select(.createdAt >= \"${TODAY}T00:00:00Z\")] | length" 2>/dev/null || echo "0")
  total_issues_opened=$((total_issues_opened + opened))
  [ "$opened" -gt 0 ] && log "  $kr: $opened issues geopend"
  
  # Issues gesloten vandaag
  closed=$(gh issue list --repo "$kr" --state closed --limit 100 --json closedAt --jq "[.[] | select(.closedAt >= \"${TODAY}T00:00:00Z\")] | length" 2>/dev/null || echo "0")
  total_issues_closed=$((total_issues_closed + closed))
  [ "$closed" -gt 0 ] && log "  $kr: $closed issues gesloten"
done

# Fase 2: PR activiteit
log "Fase 2: PR activiteit..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  # PRs geopend vandaag
  prs_opened=$(gh pr list --repo "$kr" --state open --limit 100 --json createdAt --jq "[.[] | select(.createdAt >= \"${TODAY}T00:00:00Z\")] | length" 2>/dev/null || echo "0")
  total_prs_opened=$((total_prs_opened + prs_opened))
  [ "$prs_opened" -gt 0 ] && log "  $kr: $prs_opened PRs geopend"
  
  # PRs gemerged vandaag
  prs_merged=$(gh pr list --repo "$kr" --state merged --limit 100 --json mergedAt --jq "[.[] | select(.mergedAt >= \"${TODAY}T00:00:00Z\")] | length" 2>/dev/null || echo "0")
  total_prs_merged=$((total_prs_merged + prs_merged))
  [ "$prs_merged" -gt 0 ] && log "  $kr: $prs_merged PRs gemerged"
done

# Fase 3: Commit activiteit
log "Fase 3: Commit activiteit..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  commits=$(gh api "repos/$kr/commits?since=${TODAY}T00:00:00Z&per_page=100" --jq 'length' 2>/dev/null || echo "0")
  total_commits=$((total_commits + commits))
  [ "$commits" -gt 0 ] && log "  $kr: $commits commits"
done

# Fase 4: CI activiteit
log "Fase 4: CI activiteit..."
for kr in "${REPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  failed_runs=$(gh run list --repo "$kr" --limit 20 --json name,conclusion --jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")
  total_ci_failures=$((total_ci_failures + failed_runs))
  [ "$failed_runs" -gt 0 ] && log "  $kr: $failed_runs failed run(s)"
done

# Fase 5: Samenvatting
log "Fase 5: Samenvatting..."
log "  Issues geopend: $total_issues_opened"
log "  Issues gesloten: $total_issues_closed"
log "  PRs geopend: $total_prs_opened"
log "  PRs gemerged: $total_prs_merged"
log "  Commits: $total_commits"
log "  CI failures: $total_ci_failures"

# Fase 6: Verstuur rapport
send_telegram_message "📊 *GitHub Activity Report* — $TODAY

📝 *Issues*
• Geopend: $total_issues_opened
• Gesloten: $total_issues_closed

🔀 *Pull Requests*
• Geopend: $total_prs_opened
• Gemerged: $total_prs_merged

📦 *Commits*
• Totaal: $total_commits

🔴 *CI*
• Failures: $total_ci_failures

📋 Volledig log: $LOG_FILE" || true

log "=== Activity Report complete ==="