#!/usr/bin/env bash
# scripts/inbox-dashboard.sh - Dashboard van inbox
# Toont een overzichtelijk dashboard van alle inbox items
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Dashboard ==="

# shellcheck disable=SC2206
DASHBOARD_REPOS=( ${DASHBOARD_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')

# Fase 1: Verzamel data per repo
log "Fase 1: Verzamel data per repo..."

dashboard_data=""

for kr in "${DASHBOARD_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  # Open issues
  open_issues=$(gh issue list --repo "$kr" --state open --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  
  # Open PRs
  open_prs=$(gh pr list --repo "$kr" --state open --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  
  # Review requests
  reviews=$(gh pr list --repo "$kr" --state open --search "review-requested:@me" --limit 100 --json url --jq 'length' 2>/dev/null || echo "0")
  
  # Failing CI
  failing_ci=$(gh run list --repo "$kr" --limit 20 --json conclusion --jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")
  
  # Unassigned issues
  unassigned=$(gh issue list --repo "$kr" --state open --limit 100 --json assignees --jq '[.[] | select(.assignees | length == 0)] | length' 2>/dev/null || echo "0")
  
  dashboard_data="$dashboard_data
📦 *$kr*
  📝 Issues: $open_issues | 🔀 PRs: $open_prs
  👀 Reviews: $reviews | 🔴 CI: $failing_ci
  ⚠️ Unassigned: $unassigned"
  
  log "  $kr: data verzameld"
done

# Fase 2: Verstuur dashboard
log "Fase 2: Verstuur dashboard..."

send_telegram_message "📋 *Inbox Dashboard* — $TODAY
$dashboard_data

📋 Volledig log: $LOG_FILE" || true

log "=== Inbox Dashboard complete ==="
