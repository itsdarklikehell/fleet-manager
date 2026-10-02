#!/usr/bin/env bash
# scripts/mention-report.sh - Rapporteert alle mentions
# Toont alle mentions van de afgelopen periode
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Mention Report ==="

MENTION_DAYS="${MENTION_DAYS:-7}"
# shellcheck disable=SC2206
MENTION_REPOS=( ${MENTION_REPOS:-${KEY_REPOS[@]}} )

# Teller
total_mentions=0
mention_details=""

# Fase 1: itsdarklikehell mentions
log "Fase 1: itsdarklikehell mentions..."
itsdarklikehell_mentions=$(gh api notifications --paginate --jq '[.[] | select(.reason == "mention") | {id: .id, subject: .subject.title, repo: .repository.full_name, type: .subject.type, url: .subject.url, updated: .updated_at}]' 2>/dev/null || echo "[]")

itsdarklikehell_count=$(echo "$itsdarklikehell_mentions" | jq 'length' 2>/dev/null || echo "0")
total_mentions=$((total_mentions + itsdarklikehell_count))
log "  itsdarklikehell: $itsdarklikehell_count mentions"

if [ "$itsdarklikehell_count" -gt 0 ]; then
  mention_details=$(echo "$itsdarklikehell_mentions" | jq -r '.[] | "• [\(.repo)] \(.subject) (\(.type)) — \(.updated)"' 2>/dev/null || echo "")
fi

# Fase 2: hmol33 mentions
hmol33_count=0
if [ -n "$HMOL33_TOKEN" ]; then
  log "Fase 2: hmol33 mentions..."
  hmol33_mentions=$(GITHUB_TOKEN="$HMOL33_TOKEN" gh api notifications --paginate --jq '[.[] | select(.reason == "mention") | {id: .id, subject: .subject.title, repo: .repository.full_name, type: .subject.type, url: .subject.url, updated: .updated_at}]' 2>/dev/null || echo "[]")
  
  hmol33_count=$(echo "$hmol33_mentions" | jq 'length' 2>/dev/null || echo "0")
  total_mentions=$((total_mentions + hmol33_count))
  log "  hmol33: $hmol33_count mentions"
  
  if [ "$hmol33_count" -gt 0 ]; then
    hmol33_details=$(echo "$hmol33_mentions" | jq -r '.[] | "• [\(.repo)] \(.subject) (\(.type)) — \(.updated)"' 2>/dev/null || echo "")
    if [ -n "$mention_details" ]; then
      mention_details="$mention_details
$hmol33_details"
    else
      mention_details="$hmol33_details"
    fi
  fi
fi

# Fase 3: Samenvatting
log "Fase 3: Samenvatting..."
log "  Totaal mentions: $total_mentions"

# Fase 4: Verstuur rapport
if [ -n "$mention_details" ]; then
  send_telegram_message "📣 *GitHub Mention Report* — laatste $MENTION_DAYS dagen

*Totaal mentions:* $total_mentions

$mention_details

📋 Volledig log: $LOG_FILE" || true
else
  send_telegram_message "📣 *GitHub Mention Report* — laatste $MENTION_DAYS dagen

*Totaal mentions:* $total_mentions

Geen mentions gevonden.

📋 Volledig log: $LOG_FILE" || true
fi

log "=== Mention Report complete ==="