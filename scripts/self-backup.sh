#!/usr/bin/env bash
# scripts/self-backup.sh - Self backup voor fleet manager
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Self Backup ==="
local backup_dir="$HOME/.hermes/backups/fleet-manager"
mkdir -p "$backup_dir"
local backup_file="$backup_dir/github_fleet_manager-$(date +%Y%m%d-%H%M%S).sh"
cp "$HOME/.hermes/cron/github_fleet_manager.sh" "$backup_file" 2>/dev/null || true
log "  Script gebackupped naar: $backup_file"
crontab -l > "$backup_dir/crontab-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
log "  Crontab gebackupped"
cp "$HOME/.hermes/.env" "$backup_dir/env-$(date +%Y%m%d-%H%M%S).bak" 2>/dev/null || true
log "  Config gebackupped"
local backup_count=$(ls -1t "$backup_dir"/github_fleet_manager-*.sh 2>/dev/null | wc -l)
if [ "$backup_count" -gt 10 ]; then
  ls -1t "$backup_dir"/github_fleet_manager-*.sh | tail -n +11 | xargs rm -f
  log "  ⚠️ Oude backups opgeruimd ($backup_count → 10)"
fi
log "=== Self Backup complete ==="
send_telegram_message "💾 *Self Backup*\n\n*Backups:* $backup_count\n\n📋 Volledig log: $LOG_FILE" || true
