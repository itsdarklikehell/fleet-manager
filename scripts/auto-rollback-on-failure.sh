#!/usr/bin/env bash
# scripts/auto-rollback-on-failure.sh - Automatische rollback bij failures
# Monitor scripts en roept rollback aan bij falen
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Rollback On Failure ==="

# Configuratie
ROLLBACK_LOG="${ROLLBACK_LOG:-$HOME/.github_fleet_rollback.log}"
FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-3}"
CHECK_WINDOW="${CHECK_WINDOW:-3600}"  # 1 uur

# Functies
check_recent_failures() {
  local script_name="$1"
  local now
  now=$(date +%s)
  local window_start=$((now - CHECK_WINDOW))
  
  local count=0
  if [ -f "$ROLLBACK_LOG" ]; then
    while IFS='|' read -r timestamp script status; do
      if [ "$script" = "$script_name" ] && [ "$status" = "FAIL" ]; then
        if [ "$timestamp" -ge "$window_start" ]; then
          count=$((count + 1))
        fi
      fi
    done < "$ROLLBACK_LOG"
  fi
  
  echo "$count"
}

auto_rollback() {
  local script_name="$1"
  local failure_count="$2"
  
  echo "  ⚠️ $script_name: $failure_count falen in laatste $CHECK_WINDOW seconden"
  echo "  🔄 Automatische rollback uitvoeren..."
  
  # Laad rollback script
  if [ -f "scripts/rollback.sh" ]; then
    bash scripts/rollback.sh rollback 1
  fi
  
  # Notificatie
  send_telegram_message "🔄 **Auto Rollback**

Script: $script_name
Falen: $failure_count
Actie: Rollback uitgevoerd
Tijd: $(date '+%Y-%m-%d %H:%M:%S')"
}

# Hoofdlogica
echo "Controleren op scripts met falen..."

# Laad health state
HEALTH_STATE_DIR="${HEALTH_STATE_DIR:-$HOME/.github_fleet_health}"
mkdir -p "$HEALTH_STATE_DIR"

for state_file in "$HEALTH_STATE_DIR"/*.fail; do
  [ -f "$state_file" ] || continue
  
  local script_name
  script_name=$(basename "$state_file" .fail)
  local failure_count
  failure_count=$(check_recent_failures "$script_name")
  
  if [ "$failure_count" -ge "$FAILURE_THRESHOLD" ]; then
    auto_rollback "$script_name" "$failure_count"
  fi
done

echo ""
echo "✅ Auto rollback on failure klaar"
