#!/usr/bin/env bash
# scripts/ci-failure-report.sh - Rapporteert alle CI failures
# Toont alle gefaalde CI runs voor alle key repos
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== CI Failure Report ==="

# shellcheck disable=SC2206
CI_REPOS=( ${CI_REPOS:-${KEY_REPOS[@]}} )
CI_LIMIT="${CI_LIMIT:-10}"

# Teller
total_failures=0
failure_details=""

# Fase 1: CI failures verzamelen
log "Fase 1: CI failures verzamelen..."
for kr in "${CI_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  failed_runs=$(gh run list --repo "$kr" --limit "$CI_LIMIT" --json name,conclusion,status,url,createdAt --jq '[.[] | select(.conclusion == "failure")]' 2>/dev/null || echo "[]")
  failed_count=$(echo "$failed_runs" | jq 'length' 2>/dev/null || echo "0")
  
  if [ "$failed_count" -gt 0 ]; then
    total_failures=$((total_failures + failed_count))
    log "  $kr: $failed_count failed run(s)"
    
    details=$(echo "$failed_runs" | jq -r '.[] | "• \(.name) — \(.createdAt) — \(.url)"' 2>/dev/null || echo "")
    if [ -n "$failure_details" ]; then
      failure_details="$failure_details
$details"
    else
      failure_details="$details"
    fi
  else
    log "  $kr: geen failures"
  fi
done

# Fase 2: Samenvatting
log "Fase 2: Samenvatting..."
log "  Totaal CI failures: $total_failures"

# Fase 3: Verstuur rapport
if [ -n "$failure_details" ]; then
  send_telegram_message "🔴 *GitHub CI Failure Report*

*Totaal failures:* $total_failures

$failure_details

📋 Volledig log: $LOG_FILE" || true
else
  send_telegram_message "🔴 *GitHub CI Failure Report*

*Totaal failures:* $total_failures

Geen CI failures gevonden. ✅

📋 Volledig log: $LOG_FILE" || true
fi

log "=== CI Failure Report complete ==="