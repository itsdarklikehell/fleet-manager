#!/usr/bin/env bash
# scripts/delivery-router.sh - Cross-platform delivery router
# Verstuurt rapporten naar Telegram, Discord, Slack, Email, Matrix
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Delivery Router ==="

# Configuratie
DELIVERY_PLATFORMS="${DELIVERY_PLATFORMS:-telegram}"
DELIVERY_MESSAGE="${DELIVERY_MESSAGE:-}"
DELIVERY_TITLE="${DELIVERY_TITLE:-GitHub Fleet Manager Rapport}"

# Functies
deliver_telegram() {
  local message="$1"
  log "Delivering to Telegram..."
  
  if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    log "  ⚠️ Telegram niet geconfigureerd - skipping"
    return 1
  fi
  
  for chat_id in $TELEGRAM_CHAT_IDS; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${chat_id}" \
      -d "text=${message}" \
      -d "parse_mode=Markdown" \
      --max-time 10 >/dev/null 2>&1 && log "  ✅ Verstuurd naar Telegram chat $chat_id" || log "  ❌ Kon niet versturen naar Telegram chat $chat_id"
  done
}

deliver_discord() {
  local message="$1"
  log "Delivering to Discord..."
  
  if [ -z "$DISCORD_WEBHOOK_URL" ]; then
    log "  ⚠️ Discord webhook niet geconfigureerd - skipping"
    return 1
  fi
  
  curl -s -X POST "$DISCORD_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"$message\"}" \
    --max-time 10 >/dev/null 2>&1 && log "  ✅ Verstuurd naar Discord" || log "  ❌ Kon niet versturen naar Discord"
}

deliver_slack() {
  local message="$1"
  log "Delivering to Slack..."
  
  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    log "  ⚠️ Slack webhook niet geconfigureerd - skipping"
    return 1
  fi
  
  curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"$message\"}" \
    --max-time 10 >/dev/null 2>&1 && log "  ✅ Verstuurd naar Slack" || log "  ❌ Kon niet versturen naar Slack"
}

deliver_email() {
  local message="$1"
  log "Delivering to Email..."
  
  if [ -z "$EMAIL_SMTP_HOST" ] || [ -z "$EMAIL_TO" ]; then
    log "  ⚠️ Email niet geconfigureerd - skipping"
    return 1
  fi
  
  echo "$message" | mail -s "$DELIVERY_TITLE" "$EMAIL_TO" 2>/dev/null && log "  ✅ Verstuurd naar Email" || log "  ❌ Kon niet versturen naar Email"
}

deliver_matrix() {
  local message="$1"
  log "Delivering to Matrix..."
  
  if [ -z "$MATRIX_HOMESERVER" ] || [ -z "$MATRIX_ROOM_ID" ] || [ -z "$MATRIX_TOKEN" ]; then
    log "  ⚠️ Matrix niet geconfigureerd - skipping"
    return 1
  fi
  
  curl -s -X POST "${MATRIX_HOMESERVER}/_matrix/client/r0/rooms/${MATRIX_ROOM_ID}/send/m.room.message" \
    -H "Authorization: Bearer ${MATRIX_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"msgtype\": \"m.text\", \"body\": \"$message\"}" \
    --max-time 10 >/dev/null 2>&1 && log "  ✅ Verstuurd naar Matrix" || log "  ❌ Kon niet versturen naar Matrix"
}

# Hoofdlogica
if [ -z "$DELIVERY_MESSAGE" ]; then
  log "Geen delivery message opgegeven - skipping"
  exit 0
fi

for platform in $DELIVERY_PLATFORMS; do
  case "$platform" in
    telegram) deliver_telegram "$DELIVERY_MESSAGE" ;;
    discord) deliver_discord "$DELIVERY_MESSAGE" ;;
    slack) deliver_slack "$DELIVERY_MESSAGE" ;;
    email) deliver_email "$DELIVERY_MESSAGE" ;;
    matrix) deliver_matrix "$DELIVERY_MESSAGE" ;;
    *) log "  ⚠️ Onbekend platform: $platform" ;;
  esac
done

log "=== Delivery Router klaar ==="
