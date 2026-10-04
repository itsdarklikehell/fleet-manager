#!/usr/bin/env bash
# scripts/auto-fleet-scheduler.sh - Automatische fleet scheduler
# Plant cron jobs in op basis van script categorie en frequentie
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Scheduler ==="

# Configuratie
SCHEDULER_ENABLED="${SCHEDULER_ENABLED:-no}"

if [ "$SCHEDULER_ENABLED" != "yes" ]; then
  echo "Fleet scheduler is uitgeschakeld (SCHEDULER_ENABLED=$SCHEDULER_ENABLED)"
  exit 0
fi

# Functies
schedule_script() {
  local script_name="$1"
  local schedule="$2"
  local script_path="scripts/${script_name}.sh"
  
  if [ ! -f "$script_path" ]; then
    echo "  ⚠️ Script niet gevonden: $script_name"
    return 1
  fi
  
  # Check of cron job al bestaat
  if crontab -l 2>/dev/null | grep -q "github_fleet_wrapper.sh $script_name"; then
    echo "  ⏭️ Cron job bestaat al: $script_name"
    return 0
  fi
  
  # Voeg cron job toe
  local cron_entry="$schedule timeout 120 bash /home/hans/.hermes/cron/github_fleet_wrapper.sh $script_name >> /home/hans/.hermes/cron/github-fleet.log 2>&1"
  
  (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
  echo "  ✅ Cron job toegevoegd: $script_name ($schedule)"
}

# Hoofdlogica
echo "Cron jobs inplannen..."

# Dagelijkse jobs
schedule_script "status" "0 0 * * *"
schedule_script "fleet-report" "30 0 * * *"
schedule_script "api-status" "0 1 * * *"
schedule_script "action-monitor" "30 1 * * *"
schedule_script "dependabot-auto-merge" "0 2 * * *"

# Weekelijkse jobs
schedule_script "stale-cleanup" "0 3 * * 1"
schedule_script "label-issues" "30 3 * * 1"
schedule_script "welcome-contributors" "0 4 * * 1"
schedule_script "ci-monitor" "30 4 * * 1"
schedule_script "dep-check" "0 5 * * 1"
schedule_script "dep-check-enhanced" "30 5 * * 1"
schedule_script "prs-merge" "0 6 * * 1"
schedule_script "readme-check" "30 6 * * 1"
schedule_script "gource-refresh" "0 7 * * 1"
schedule_script "release-draft" "30 7 * * 1"
schedule_script "auto-triage-issues" "0 8 * * 1"
schedule_script "prs-status" "30 8 * * 1"
schedule_script "actions-status" "0 9 * * 1"
schedule_script "pr-review-time" "30 9 * * 1"
schedule_script "label-prs-by-files" "0 10 * * 1"
schedule_script "prs-label-auto" "30 10 * * 1"
schedule_script "dependabot-auto-actions" "0 11 * * 1"

# Maandelijkse jobs
schedule_script "release-notes-monthly" "0 12 1 * *"
schedule_script "dependency-update-check" "30 12 1 * *"

echo ""
echo "✅ Auto fleet scheduler klaar"
