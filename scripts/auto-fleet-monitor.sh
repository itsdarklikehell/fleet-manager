#!/usr/bin/env bash
# scripts/auto-fleet-monitor.sh - Automatische fleet monitoring
# Monitort de fleet status en stuurt alerts bij problemen
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Monitor ==="

# Configuratie
MONITOR_ENABLED="${MONITOR_ENABLED:-no}"
ALERT_THRESHOLD="${ALERT_THRESHOLD:-3}"

if [ "$MONITOR_ENABLED" != "yes" ]; then
  echo "Fleet monitor is uitgeschakeld (MONITOR_ENABLED=$MONITOR_ENABLED)"
  exit 0
fi

# Functies
check_rate_limit() {
  local remaining
  remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "0")
  local limit
  limit=$(gh api rate_limit --jq '.resources.core.limit' 2>/dev/null || echo "5000")
  
  if [ "$remaining" -lt 100 ]; then
    send_telegram_message "⚠️ **Fleet Alert: Rate Limit**
  
  Requests remaining: $remaining / $limit
  Tijd: $(date '+%Y-%m-%d %H:%M:%S')"
  fi
}

check_cron_jobs() {
  local failed_jobs=0
  
  for job in $(crontab -l 2>/dev/null | grep 'github_fleet_wrapper' | sed -n 's/.*github_fleet_wrapper\.sh \([^ ]*\).*/\1/p'); do
    if ! crontab -l 2>/dev/null | grep -q "github_fleet_wrapper.sh $job"; then
      failed_jobs=$((failed_jobs + 1))
    fi
  done
  
  if [ "$failed_jobs" -gt 0 ]; then
    send_telegram_message "⚠️ **Fleet Alert: Cron Jobs**
  
  $failed_jobs cron jobs niet gevonden
  Tijd: $(date '+%Y-%m-%d %H:%M:%S')"
  fi
}

check_disk_space() {
  local usage
  usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  
  if [ "$usage" -gt 90 ]; then
    send_telegram_message "⚠️ **Fleet Alert: Disk Space**
  
  Disk usage: $usage%
  Tijd: $(date '+%Y-%m-%d %H:%M:%S')"
  fi
}

check_memory() {
  local usage
  usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
  
  if [ "$usage" -gt 90 ]; then
    send_telegram_message "⚠️ **Fleet Alert: Memory**
  
  Memory usage: $usage%
  Tijd: $(date '+%Y-%m-%d %H:%M:%S')"
  fi
}

# Hoofdlogica
echo "Fleet monitoren..."
check_rate_limit
check_cron_jobs
check_disk_space
check_memory

echo ""
echo "✅ Auto fleet monitor klaar"
