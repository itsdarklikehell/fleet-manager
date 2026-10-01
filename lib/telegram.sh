#!/usr/bin/env bash
# lib/telegram.sh - Telegram rapportage voor GitHub Fleet Manager

send_telegram_message() {
  local text="$1"; local token="$TELEGRAM_TOKEN"
  [ -z "$token" ] && { echo "[TELEGRAM] No token — skipping"; return 1; }
  local escaped
  escaped=$(printf '%b' "$text" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$text\"")
  local all_ok=1
  for chat_id in $TELEGRAM_CHAT_IDS; do
    [ -z "$chat_id" ] && continue
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "https://api.telegram.org/bot${token}/sendMessage" \
      -H "Content-Type: application/json" \
      -d "{\"chat_id\":\"${chat_id}\",\"text\":${escaped},\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}" 2>/dev/null)
    if [ "$http_code" = "200" ]; then
      echo "[TELEGRAM] ✓ Verstuurd naar chat $chat_id"
    else
      echo "[TELEGRAM] HTTP $http_code — failed voor chat $chat_id" >&2
      all_ok=0
    fi
  done
  return $((1 - all_ok))
}
