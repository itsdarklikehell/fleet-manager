#!/usr/bin/env bash
# scripts/smart-notification-digest.sh - Slimme notificatie digest
# Alleen nieuwe issues/PRs, geen duplicates
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Smart Notification Digest ==="

# Configuratie
DIGEST_STATE_DIR="${DIGEST_STATE_DIR:-$HOME/.github_fleet_digest}"
mkdir -p "$DIGEST_STATE_DIR"
DIGEST_FILE="$DIGEST_STATE_DIR/last_digest.json"

# Functies
get_last_digest_time() {
  if [ -f "$DIGEST_FILE" ]; then
    jq -r '.timestamp // ""' "$DIGEST_FILE" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

save_digest_time() {
  jq -n --arg timestamp "$(date -Iseconds)" '{timestamp: $timestamp}' > "$DIGEST_FILE"
}

get_new_items() {
  local since="$1"
  
  # Nieuwe issues
  local issues
  issues=$(gh search issues --state open --limit 50 --json number,title,repository,createdAt --jq '.[] | select(.createdAt > "'"$since"'") | "📝 \(.repository.nameWithOwner)#\(.number): \(.title)"' 2>/dev/null || echo "")
  
  # Nieuwe PRs
  local prs
  prs=$(gh search prs --state open --limit 50 --json number,title,repository,createdAt --jq '.[] | select(.createdAt > "'"$since"'") | "🔀 \(.repository.nameWithOwner)#\(.number): \(.title)"' 2>/dev/null || echo "")
  
  # Nieuwe CI failures
  local ci_failures
  ci_failures=$(gh run list --status failure --limit 20 --json name,conclusion,createdAt,repository --jq '.[] | select(.createdAt > "'"$since"'") | "❌ \(.repository.nameWithOwner): \(.name)"' 2>/dev/null || echo "")
  
  echo "$issues"
  echo "$prs"
  echo "$ci_failures"
}

# Hoofdlogica
last_digest=$(get_last_digest_time)

if [ -z "$last_digest" ]; then
  # Eerste run — laatste 24 uur
  last_digest=$(date -Iseconds -d '24 hours ago' 2>/dev/null || date -Iseconds)
  echo "Eerste run — laatste 24 uur"
else
  echo "Laatste digest: $last_digest"
fi

echo ""
echo "Nieuwe items sinds laatste digest:"
new_items=$(get_new_items "$last_digest")

if [ -z "$new_items" ]; then
  echo "  Geen nieuwe items"
else
  echo "$new_items"
  
  # Stuur digest
  send_telegram_message "📊 **Fleet Digest**

$new_items

---
Laatste update: $(date '+%Y-%m-%d %H:%M:%S')"
fi

# Sla nieuwe timestamp op
save_digest_time

echo ""
echo "✅ Smart notification digest klaar"
