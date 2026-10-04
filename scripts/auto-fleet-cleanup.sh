#!/usr/bin/env bash
# scripts/auto-fleet-cleanup.sh - Automatische fleet cleanup
# Ruimt oude backups, logs en tijdelijke bestanden op
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Cleanup ==="

# Configuratie
CLEANUP_ENABLED="${CLEANUP_ENABLED:-no}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

if [ "$CLEANUP_ENABLED" != "yes" ]; then
  echo "Fleet cleanup is uitgeschakeld (CLEANUP_ENABLED=$CLEANUP_ENABLED)"
  exit 0
fi

# Functies
cleanup_logs() {
  echo "Logs opruimen (ouder dan $LOG_RETENTION_DAYS dagen)..."
  
  # Oude log bestanden verwijderen
  find "$HOME/.hermes/cron/" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
  find "$HOME/.hermes/cache/scratch/" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
  
  # Log bestanden truncaten als ze te groot zijn
  for logfile in "$HOME/.hermes/cron/github-fleet.log" "$HOME/.github_fleet_manager.log"; do
    if [ -f "$logfile" ]; then
      local size
      size=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo "0")
      if [ "$size" -gt 10485760 ]; then  # 10MB
        tail -1000 "$logfile" > "$logfile.tmp" && mv "$logfile.tmp" "$logfile"
        echo "  ✅ Log getruncat: $logfile"
      fi
    fi
  done
  
  echo "  ✅ Logs opgeruimd"
}

cleanup_backups() {
  echo "Backups opruimen (ouder dan $BACKUP_RETENTION_DAYS dagen)..."
  
  find "$HOME/.github_fleet_backups/" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
  
  echo "  ✅ Backups opgeruimd"
}

cleanup_temp() {
  echo "Tijdelijke bestanden opruim..."
  
  # Oude lock files
  find "$HOME/.hermes/cron/" -name "*.lock" -type f -delete 2>/dev/null || true
  find "$HOME/.hermes/cache/scratch/" -name "*.lock" -type f -delete 2>/dev/null || true
  
  # Oude temp bestanden
  find "$HOME/.hermes/cache/scratch/" -name "*.tmp" -type f -mtime +1 -delete 2>/dev/null || true
  
  echo "  ✅ Tijdelijke bestanden opgeruimd"
}

cleanup_metrics() {
  echo "Metrics opruimen..."
  
  # Oude metrics verwijderen
  find "$HOME/.github_fleet_metrics/" -type f -mtime +30 -delete 2>/dev/null || true
  
  echo "  ✅ Metrics opgeruimd"
}

# Hoofdlogica
cleanup_logs
cleanup_backups
cleanup_temp
cleanup_metrics

echo ""
echo "✅ Auto fleet cleanup klaar"
