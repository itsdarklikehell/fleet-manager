#!/usr/bin/env bash
# Rate limiting helper voor fleet-manager scripts

RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-$HOME/.github_fleet_rate_limit}"
RATE_LIMIT_MAX="${RATE_LIMIT_MAX:-4500}"
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-3600}"

rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - RATE_LIMIT_WINDOW))
  
  local count=0
  local file_time=0
  if [ -f "$RATE_LIMIT_FILE" ]; then
    read -r file_time count < "$RATE_LIMIT_FILE" 2>/dev/null || true
    if [ -z "$file_time" ] || [ "$file_time" -lt "$window_start" ]; then
      count=0
    fi
  fi
  
  count=$((count + 1))
  echo "$now $count" > "$RATE_LIMIT_FILE"
  
  if [ "$count" -ge "$RATE_LIMIT_MAX" ]; then
    echo "Rate limit bereikt ($count/$RATE_LIMIT_MAX)" >&2
    return 1
  fi
  return 0
}

rate_limit_wait() {
  local remaining
  remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "0")
  
  if [ "$remaining" -lt 100 ]; then
    local reset_time
    reset_time=$(gh api rate_limit --jq '.resources.core.reset' 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local wait_time=$((reset_time - now))
    
    if [ "$wait_time" -gt 0 ]; then
      echo "Rate limit bijna bereikt, wacht ${wait_time}s..." >&2
      sleep "$wait_time"
    fi
  fi
}
