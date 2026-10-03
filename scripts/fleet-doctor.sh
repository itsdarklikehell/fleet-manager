#!/usr/bin/env bash
# scripts/fleet-doctor.sh - Automatische incident detectie en diagnose
# Detecteert wanneer meerdere scripts tegelijk falen en diagnoseert de oorzaak
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Fleet Doctor - Incident Detectie ==="

# Configuratie
DOCTOR_STATE_DIR="${DOCTOR_STATE_DIR:-$HOME/.github_fleet_health}"
DOCTOR_LOG="${DOCTOR_LOG:-$HOME/.github_fleet_doctor.log}"
FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-3}"  # Aantal falen voordat incident wordt gedetecteerd
TIME_WINDOW="${TIME_WINDOW:-3600}"  # 1 uur in seconden

# Functies
detect_incident() {
  local now
  now=$(date +%s)
  local window_start=$((now - TIME_WINDOW))
  local failures=0
  
  # Tel falen in het tijdsvenster
  for state_file in "$DOCTOR_STATE_DIR"/*.last_run; do
    [ -f "$state_file" ] || continue
    local script
    script=$(basename "$state_file" .last_run)
    local last_run
    last_run=$(cat "$state_file" 2>/dev/null | cut -d' ' -f1 || echo "0")
    local status
    status=$(cat "$state_file" 2>/dev/null | cut -d' ' -f2 || echo "unknown")
    
    if [ "$last_run" -gt "$window_start" ] && [ "$status" = "fail" ]; then
      failures=$((failures + 1))
      log "  ❌ $script: gefaald op $(date -d "@$last_run" '+%H:%M:%S')"
    fi
  done
  
  if [ "$failures" -ge "$FAILURE_THRESHOLD" ]; then
    log "  🚨 INCIDENT GEdetecteerd: $failures scripts gefaald in laatste ${TIME_WINDOW}s"
    return 0
  fi
  
  return 1
}

diagnose_cause() {
  log "Diagnose starten..."
  
  # Check 1: GitHub API rate limit
  local remaining
  remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "unknown")
  if [ "$remaining" != "unknown" ] && [ "$remaining" -lt 100 ]; then
    log "  🔍 OORZAAK: GitHub API rate limit bijna bereikt ($remaining remaining)"
    log "  💡 OPLOSSING: Wacht op reset of reduceer cron jobs"
    return 0
  fi
  
  # Check 2: Netwerk connectiviteit
  if ! curl -s --max-time 5 https://api.github.com > /dev/null 2>&1; then
    log "  🔍 OORZAAK: Netwerk connectiviteit probleem (api.github.com onbereikbaar)"
    log "  💡 OPLOSSING: Controleer internet verbinding en DNS"
    return 0
  fi
  
  # Check 3: Token geldigheid
  if ! gh api user > /dev/null 2>&1; then
    log "  🔍 OORZAAK: GitHub token ongeldig of verlopen"
    log "  💡 OPLOSSING: Vernieuw GITHUB_TOKEN in ~/.hermes/.env"
    return 0
  fi
  
  # Check 4: Schijfruimte
  local disk_usage
  disk_usage=$(df -h "$HOME" | tail -1 | awk '{print $5}' | tr -d '%')
  if [ "$disk_usage" -gt 90 ]; then
    log "  🔍 OORZAAK: Schijf bijna vol (${disk_usage}%)"
    log "  💡 OPLOSSING: Ruim op of vergroot schijf"
    return 0
  fi
  
  # Check 5: Cron daemon
  if ! pgrep -x "cron" > /dev/null 2>&1 && ! pgrep -x "crond" > /dev/null 2>&1; then
    log "  🔍 OORZAAK: Cron daemon niet actief"
    log "  💡 OPLOSSING: Start cron service"
    return 0
  fi
  
  log "  🔍 OORZAAK: Onbekend — geen duidelijke oorzaak gevonden"
  log "  💡 OPLOSSING: Controleer logs handmatig"
  return 1
}

suggest_fixes() {
  log "Suggesties:"
  log "  1. Controleer GitHub API rate limit: gh api rate_limit"
  log "  2. Test netwerk: curl -s https://api.github.com"
  log "  3. Verifieer token: gh api user"
  log "  4. Check schijf: df -h"
  log "  5. Check cron: pgrep -x cron"
  log "  6. Bekijk logs: tail -50 ~/.github_fleet_manager.log"
}

# Hoofdlogica
if detect_incident; then
  diagnose_cause
  suggest_fixes
  
  # Stuur alert naar Telegram
  if [ -n "${TELEGRAM_TOKEN:-}" ]; then
    message="🚨 Fleet Doctor: Incident gedetecteerd! $FAILURE_THRESHOLD+ scripts gefaald. Controleer logs."
    for chat_id in $TELEGRAM_CHAT_IDS; do
      curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=$chat_id" \
        -d "text=$message" > /dev/null 2>&1 || true
    done
  fi
  
  exit 1
else
  log "✅ Geen incident gedetecteerd"
  exit 0
fi
