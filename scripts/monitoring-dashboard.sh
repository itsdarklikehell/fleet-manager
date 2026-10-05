#!/usr/bin/env bash
# scripts/monitoring-dashboard.sh - Centrale monitoring dashboard voor fleet-manager
# Combineert health-check, metrics-collector, fleet-doctor en performance-monitor
# Genereert dagelijkse rapporten en stuurt Telegram alerts bij kritieke problemen
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Monitoring Dashboard ==="

# Configuratie
MONITORING_DIR="${MONITORING_DIR:-$HOME/.github_fleet_monitoring}"
mkdir -p "$MONITORING_DIR"
REPORT_FILE="$MONITORING_DIR/report_$(date +%Y%m%d).md"
ALERT_STATE_FILE="$MONITORING_DIR/.alert_state"

# Functies
send_critical_alert() {
  local message="$1"
  log "  🚨 CRITICAL ALERT: $message"
  
  if [ -n "${TELEGRAM_TOKEN:-}" ]; then
    send_telegram_message "🚨 *Fleet Monitoring Alert* 🚨

$message

Tijd: $(date '+%Y-%m-%d %H:%M:%S')
Host: $(hostname)" || log "  ⚠️ Telegram alert verzenden gefaald"
  fi
}

send_daily_report() {
  local report="$1"
  
  if [ -n "${TELEGRAM_TOKEN:-}" ]; then
    send_telegram_message "📊 *Fleet Monitoring Dagrapport* 📊

$report

Volledig rapport: $REPORT_FILE" || log "  ⚠️ Telegram rapport verzenden gefaald"
  fi
}

check_critical_conditions() {
  local alerts=""
  
  # Check 1: GitHub API rate limit (cache voor 5 minuten)
  local remaining
  local rate_cache="$MONITORING_DIR/.rate_limit_cache"
  local rate_cache_age=0
  if [ -f "$rate_cache" ]; then
    rate_cache_age=$(( $(date +%s) - $(stat -c %Y "$rate_cache" 2>/dev/null || echo 0) ))
  fi
  if [ "$rate_cache_age" -lt 300 ] && [ -f "$rate_cache" ]; then
    remaining=$(cat "$rate_cache" 2>/dev/null || echo "unknown")
  else
    remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "unknown")
    echo "$remaining" > "$rate_cache" 2>/dev/null || true
  fi
  if [ "$remaining" != "unknown" ] && [ "$remaining" -lt 100 ]; then
    alerts+="❌ GitHub API rate limit kritiek: $remaining remaining\n"
  fi
  
  # Check 2: Schijfruimte
  local disk_usage
  disk_usage=$(df -h "$HOME" | tail -1 | awk '{print $5}' | tr -d '%')
  if [ "$disk_usage" -gt 90 ]; then
    alerts+="❌ Schijf bijna vol: ${disk_usage}%\n"
  fi
  
  # Check 3: Cron daemon
  if ! pgrep -x "cron" > /dev/null 2>&1 && ! pgrep -x "crond" > /dev/null 2>&1; then
    alerts+="❌ Cron daemon niet actief\n"
  fi
  
  # Check 4: GitHub authenticatie
  if ! gh auth status &>/dev/null; then
    alerts+="❌ GitHub authenticatie gefaald\n"
  fi
  
  # Check 5: Netwerk
  if ! curl -s --max-time 5 https://api.github.com > /dev/null 2>&1; then
    alerts+="❌ GitHub API onbereikbaar\n"
  fi
  
  # Check 6: Stale scripts (meer dan 48 uur niet gedraaid)
  local now
  now=$(date +%s)
  local stale_count=0
  for state_file in "$HOME/.github_fleet_health"/*.last_run; do
    [ -f "$state_file" ] || continue
    local last_run
    last_run=$(cat "$state_file" 2>/dev/null | cut -d' ' -f1 || echo "0")
    local age=$((now - last_run))
    if [ "$age" -gt 172800 ]; then
      stale_count=$((stale_count + 1))
    fi
  done
  if [ "$stale_count" -gt 5 ]; then
    alerts+="⚠️ $stale_count scripts zijn stale (>48u)\n"
  fi
  
  if [ -n "$alerts" ]; then
    send_critical_alert "$alerts"
    echo "$(date +%s)" > "$ALERT_STATE_FILE"
  fi
}

generate_report() {
  local report=""
  
  report+="# Fleet Monitoring Rapport\n\n"
  report+="**Datum:** $(date '+%Y-%m-%d %H:%M:%S')\n"
  report+="**Host:** $(hostname)\n\n"
  
  # Sectie 1: Script Status
  report+="## Script Status\n\n"
  local total_scripts
  total_scripts=$(ls "$(dirname "$0")"/*.sh 2>/dev/null | wc -l)
  local ok_scripts=0
  local fail_scripts=0
  
  for script in "$(dirname "$0")"/*.sh; do
    [ -f "$script" ] || continue
    if bash -n "$script" 2>/dev/null; then
      ok_scripts=$((ok_scripts + 1))
    else
      fail_scripts=$((fail_scripts + 1))
    fi
  done
  
  report+="- Totaal scripts: $total_scripts\n"
  report+="- OK: $ok_scripts ✅\n"
  report+="- Fout: $fail_scripts ❌\n\n"
  
  # Sectie 2: Cron Jobs
  report+="## Cron Jobs\n\n"
  local cron_count
  cron_count=$(crontab -l 2>/dev/null | grep -c 'github_fleet' || echo "0")
  report+="- Actieve cron jobs: $cron_count\n\n"
  
  # Sectie 3: GitHub API (gebruik cache indien beschikbaar)
  report+="## GitHub API\n\n"
  local rate_limit
  local rate_limit_max
  local rate_cache="$MONITORING_DIR/.rate_limit_cache"
  if [ -f "$rate_cache" ]; then
    rate_limit=$(cat "$rate_cache" 2>/dev/null || echo "unknown")
  else
    rate_limit=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "unknown")
  fi
  rate_limit_max=$(gh api rate_limit --jq '.resources.core.limit' 2>/dev/null || echo "unknown")
  report+="- Rate limit: $rate_limit/$rate_limit_max\n"
  
  local repo_count
  repo_count=$(gh repo list --limit 1000 --json nameWithOwner --jq 'length' 2>/dev/null || echo "0")
  report+="- Repositories: $repo_count\n\n"
  
  # Sectie 4: Systeem
  report+="## Systeem\n\n"
  local disk_usage
  disk_usage=$(df -h "$HOME" | tail -1 | awk '{print $5}')
  local memory_usage
  memory_usage=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
  local uptime_info
  uptime_info=$(uptime -p 2>/dev/null || uptime | awk -F',' '{print $1}')
  
  report+="- Schijf: $disk_usage\n"
  report+="- Geheugen: $memory_usage\n"
  report+="- Uptime: $uptime_info\n\n"
  
  # Sectie 5: Stale Scripts
  report+="## Stale Scripts\n\n"
  local now
  now=$(date +%s)
  local stale_list=""
  for state_file in "$HOME/.github_fleet_health"/*.last_run; do
    [ -f "$state_file" ] || continue
    local script_name
    script_name=$(basename "$state_file" .last_run)
    local last_run
    last_run=$(cat "$state_file" 2>/dev/null | cut -d' ' -f1 || echo "0")
    local age=$((now - last_run))
    if [ "$age" -gt 86400 ]; then
      local age_hours=$((age / 3600))
      stale_list+="- $script_name: ${age_hours}u geleden\n"
    fi
  done
  
  if [ -n "$stale_list" ]; then
    report+="Scripts die >24u niet hebben gedraaid:\n$stale_list\n"
  else
    report+="Alle scripts zijn recent actief ✅\n\n"
  fi
  
  # Sectie 6: Consecutive Failures
  report+="## Fouten\n\n"
  local failures=0
  if [ -f "$HOME/.github_fleet_health/consecutive_failures" ]; then
    failures=$(cat "$HOME/.github_fleet_health/consecutive_failures" 2>/dev/null || echo "0")
  fi
  report+="- Opeenvolgende falen: $failures\n\n"
  
  # Schrijf rapport
  echo -e "$report" > "$REPORT_FILE"
  log "  ✅ Rapport opgeslagen: $REPORT_FILE"
  
  # Stuur naar Telegram
  send_daily_report "$(echo -e "$report" | head -30)"
}

# Hoofdlogica
log "Start monitoring dashboard..."

# Voer checks uit
check_critical_conditions

# Genereer rapport
generate_report

log "=== Monitoring Dashboard voltooid ==="
