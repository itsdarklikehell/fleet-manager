#!/usr/bin/env bash
# scripts/review-request-report.sh - Rapporteert alle review requests
# Toont alle open review requests voor beide accounts
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Review Request Report ==="

REVIEW_DAYS="${REVIEW_DAYS:-7}"
# shellcheck disable=SC2206
REVIEW_REPOS=( ${REVIEW_REPOS:-${KEY_REPOS[@]}} )

# Teller
total_review_requests=0
review_details=""

# Fase 1: itsdarklikehell review requests
log "Fase 1: itsdarklikehell review requests..."
itsdarklikehell_reviews=$(gh api notifications --paginate --jq '[.[] | select(.reason == "review_requested") | {id: .id, subject: .subject.title, repo: .repository.full_name, type: .subject.type, url: .subject.url, updated: .updated_at}]' 2>/dev/null || echo "[]")

itsdarklikehell_count=$(echo "$itsdarklikehell_reviews" | jq 'length' 2>/dev/null || echo "0")
total_review_requests=$((total_review_requests + itsdarklikehell_count))
log "  itsdarklikehell: $itsdarklikehell_count review requests"

if [ "$itsdarklikehell_count" -gt 0 ]; then
  review_details=$(echo "$itsdarklikehell_reviews" | jq -r '.[] | "• [\(.repo)] \(.subject) (\(.type)) — \(.updated)"' 2>/dev/null || echo "")
fi

# Fase 2: hmol33 review requests
hmol33_count=0
if [ -n "$HMOL33_TOKEN" ]; then
  log "Fase 2: hmol33 review requests..."
  hmol33_reviews=$(GITHUB_TOKEN="$HMOL33_TOKEN" gh api notifications --paginate --jq '[.[] | select(.reason == "review_requested") | {id: .id, subject: .subject.title, repo: .repository.full_name, type: .subject.type, url: .subject.url, updated: .updated_at}]' 2>/dev/null || echo "[]")
  
  hmol33_count=$(echo "$hmol33_reviews" | jq 'length' 2>/dev/null || echo "0")
  total_review_requests=$((total_review_requests + hmol33_count))
  log "  hmol33: $hmol33_count review requests"
  
  if [ "$hmol33_count" -gt 0 ]; then
    hmol33_details=$(echo "$hmol33_reviews" | jq -r '.[] | "• [\(.repo)] \(.subject) (\(.type)) — \(.updated)"' 2>/dev/null || echo "")
    if [ -n "$review_details" ]; then
      review_details="$review_details
$hmol33_details"
    else
      review_details="$hmol33_details"
    fi
  fi
fi

# Fase 3: Open PRs waarop review nodig is
log "Fase 3: Open PRs waarop review nodig is..."
open_prs_needing_review=0
for kr in "${REVIEW_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  prs=$(gh pr list --repo "$kr" --state open --limit 50 --json number,title,reviewDecision --jq '[.[] | select(.reviewDecision == "REVIEW_REQUIRED" or .reviewDecision == null)] | length' 2>/dev/null || echo "0")
  open_prs_needing_review=$((open_prs_needing_review + prs))
  [ "$prs" -gt 0 ] && log "  $kr: $prs PRs nodig review"
done

# Fase 4: Samenvatting
log "Fase 4: Samenvatting..."
log "  Totaal review requests: $total_review_requests"
log "  Open PRs nodig review: $open_prs_needing_review"

# Fase 5: Verstuur rapport
if [ -n "$review_details" ]; then
  send_telegram_message "👁️ *GitHub Review Request Report*

*Review requests:* $total_review_requests
*Open PRs nodig review:* $open_prs_needing_review

$review_details

📋 Volledig log: $LOG_FILE" || true
else
  send_telegram_message "👁️ *GitHub Review Request Report*

*Review requests:* $total_review_requests
*Open PRs nodig review:* $open_prs_needing_review

Geen review requests gevonden.

📋 Volledig log: $LOG_FILE" || true
fi

log "=== Review Request Report complete ==="