#!/usr/bin/env bash

# Logging
LOG_FILE="${LOG_FILE:-/tmp/fleet-manager.log}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
# lib/telegram.sh - Telegram rapportage voor GitHub Fleet Manager
# Uitgebreid met retry logic, rate limiting en betere error handling

set -euo pipefail
TELEGRAM_RATE_LIMIT_FILE="${TELEGRAM_RATE_LIMIT_FILE:-$HOME/.github_fleet_telegram_rate}"
TELEGRAM_MAX_PER_MINUTE="${TELEGRAM_MAX_PER_MINUTE:-20}"
TELEGRAM_RETRY_COUNT="${TELEGRAM_RETRY_COUNT:-3}"
TELEGRAM_RETRY_DELAY="${TELEGRAM_RETRY_DELAY:-2}"

# Rate limiter voor Telegram API
telegram_rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - 60))
  
  local count=0
  local file_time=0
  if [ -f "$TELEGRAM_RATE_LIMIT_FILE" ]; then
    read -r file_time count < "$TELEGRAM_RATE_LIMIT_FILE" 2>/dev/null || true
    if [ -z "$file_time" ] || [ "$file_time" -lt "$window_start" ]; then
      count=0
    fi
  fi
  
  count=$((count + 1))
  echo "$now $count" > "$TELEGRAM_RATE_LIMIT_FILE"
  
  if [ "$count" -ge "$TELEGRAM_MAX_PER_MINUTE" ]; then
    echo "[TELEGRAM] Rate limit bereikt ($count/min)" >&2
    return 1
  fi
  return 0
}

# Stuur bericht met retry logic
send_telegram_message() {
  local text="$1"; local token="$TELEGRAM_TOKEN"
  [ -z "$token" ] && { echo "[TELEGRAM] No token — skipping" >&2; return 1; }
  
  local escaped
  escaped=$(printf '%b' "$text" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$text\"")
  
  local all_ok=1
  for chat_id in $TELEGRAM_CHAT_IDS; do
    [ -z "$chat_id" ] && continue
    
    # Rate limit check
    telegram_rate_limit_check || { echo "[TELEGRAM] Rate limit — skipping chat $chat_id" >&2; continue; }
    
    # Retry logic
    local attempt=0
    local success=false
    while [ $attempt -lt $TELEGRAM_RETRY_COUNT ]; do
      attempt=$((attempt + 1))
      
      local http_code
      http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "https://api.telegram.org/bot${token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"${chat_id}\",\"text\":${escaped},\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}" 2>/dev/null)
      
      if [ "$http_code" = "200" ]; then
        echo "[TELEGRAM] ✓ Verstuurd naar chat $chat_id"
        success=true
        break
      elif [ "$http_code" = "429" ]; then
        # Rate limited — wacht langer
        local wait_time=$((TELEGRAM_RETRY_DELAY * attempt * 2))
        echo "[TELEGRAM] 429 rate limited — wacht ${wait_time}s (poging $attempt)" >&2
        sleep $wait_time
      else
        echo "[TELEGRAM] HTTP $http_code — poging $attempt voor chat $chat_id" >&2
        sleep $TELEGRAM_RETRY_DELAY
      fi
    done
    
    if [ "$success" = false ]; then
      echo "[TELEGRAM] ❌ Gefaald voor chat $chat_id na $TELEGRAM_RETRY_COUNT pogingen" >&2
      all_ok=0
    fi
  done
  
  return $((1 - all_ok))
}

# Stuur samenvatting naar alle chats
send_telegram_summary() {
  local title="$1"
  local body="$2"
  send_telegram_message "**${title}**

${body}"
}
