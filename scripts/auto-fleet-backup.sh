#!/usr/bin/env bash
# scripts/auto-fleet-backup.sh - Automatische fleet backup
# Maakt backups van alle fleet configuratie en state
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Backup ==="

# Configuratie
BACKUP_DIR="${BACKUP_DIR:-$HOME/.github_fleet_backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"  # dagen

mkdir -p "$BACKUP_DIR"

# Functies
backup_scripts() {
  local backup_file="$BACKUP_DIR/scripts_$(date +%Y%m%d_%H%M%S).tar.gz"
  tar -czf "$backup_file" -C "$(dirname "$0")" scripts/ 2>/dev/null || true
  echo "  ✅ Scripts gebackupped: $backup_file"
}

backup_config() {
  local backup_file="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).tar.gz"
  tar -czf "$backup_file" -C "$(dirname "$0")" lib/ 2>/dev/null || true
  echo "  ✅ Configuratie gebackupped: $backup_file"
}

backup_cron() {
  local backup_file="$BACKUP_DIR/cron_$(date +%Y%m%d_%H%M%S).txt"
  crontab -l > "$backup_file" 2>/dev/null || true
  echo "  ✅ Cron jobs gebackupped: $backup_file"
}

backup_state() {
  local backup_file="$BACKUP_DIR/state_$(date +%Y%m%d_%H%M%S).tar.gz"
  tar -czf "$backup_file" -C "$HOME" .github_fleet_health/ .github_fleet_metrics/ .github_fleet_performance/ 2>/dev/null || true
  echo "  ✅ State gebackupped: $backup_file"
}

cleanup_old_backups() {
  echo "  Oude backups verwijderen (ouder dan $BACKUP_RETENTION dagen)..."
  find "$BACKUP_DIR" -type f -mtime +$BACKUP_RETENTION -delete 2>/dev/null || true
  echo "  ✅ Oude backups verwijderd"
}

# Hoofdlogica
echo "Backup maken..."
backup_scripts
backup_config
backup_cron
backup_state
cleanup_old_backups

echo ""
echo "✅ Auto fleet backup klaar"
