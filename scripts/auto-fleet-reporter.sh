#!/usr/bin/env bash
# scripts/auto-fleet-reporter.sh - Automatische fleet rapportage
# Genereert dagelijkse/weekelijkse rapporten over de fleet status
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Reporter ==="

# Configuratie
REPORTER_ENABLED="${REPORTER_ENABLED:-no}"
REPORT_TYPE="${REPORT_TYPE:-daily}"  # daily, weekly, monthly

if [ "$REPORTER_ENABLED" != "yes" ]; then
  echo "Fleet reporter is uitgeschakeld (REPORTER_ENABLED=$REPORTER_ENABLED)"
  exit 0
fi

# Functies
generate_daily_report() {
  local report="📊 **Fleet Dagrapport** — $(date '+%Y-%m-%d')
  
  **Scripts:** $(ls scripts/*.sh 2>/dev/null | wc -l)
  **Cron jobs:** $(crontab -l 2>/dev/null | grep -c 'github_fleet_wrapper' || echo 0)
  **Repos:** $(gh repo list --limit 1000 --json nameWithOwner --jq 'length' 2>/dev/null || echo 0)
  
  **Laatste health check:**
  $(tail -20 ~/.github_fleet_manager.log 2>/dev/null | grep -E '✅|⚠️|❌' | tail -5)
  
  **Rate limit:** $(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo 'unknown') requests remaining
  "
  
  echo "$report"
}

generate_weekly_report() {
  local report="📊 **Fleet Weekrapport** — Week $(date '+%V') $(date '+%Y')
  
  **Scripts:** $(ls scripts/*.sh 2>/dev/null | wc -l)
  **Cron jobs:** $(crontab -l 2>/dev/null | grep -c 'github_fleet_wrapper' || echo 0)
  **Repos:** $(gh repo list --limit 1000 --json nameWithOwner --jq 'length' 2>/dev/null || echo 0)
  
  **Laatste 7 dagen:**
  - Health checks: $(grep -c 'Health Check' ~/.github_fleet_manager.log 2>/dev/null || echo 0)
  - Fouten: $(grep -c 'ERROR\|FAIL' ~/.github_fleet_manager.log 2>/dev/null || echo 0)
  - Waarschuwingen: $(grep -c '⚠️' ~/.github_fleet_manager.log 2>/dev/null || echo 0)
  
  **Top 5 traagste scripts:**
  $(grep 'duration' ~/.github_fleet_performance/performance.json 2>/dev/null | jq -r 'sort_by(-.duration) | .[:5][] | "  - \(.script): \(.duration)s"' 2>/dev/null || echo '  Geen data')
  "
  
  echo "$report"
}

# Hoofdlogica
case "$REPORT_TYPE" in
  daily)
    report=$(generate_daily_report)
    ;;
  weekly)
    report=$(generate_weekly_report)
    ;;
  monthly)
    report=$(generate_weekly_report)  # TODO: monthly variant
    ;;
  *)
    report=$(generate_daily_report)
    ;;
esac

echo "$report"

# Stuur naar Telegram
send_telegram_message "$report"

echo ""
echo "✅ Auto fleet reporter klaar"
