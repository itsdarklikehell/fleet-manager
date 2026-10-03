#!/usr/bin/env bash
# scripts/backup-verify.sh - Backup verificatie
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Backup Verify ==="
local config_backup=$(find ~/.hermes -name "*.bak" -mtime -7 2>/dev/null | wc -l)
log "  Config backups (7d): $config_backup"
local docker_volumes=$(docker volume ls -q 2>/dev/null | wc -l)
log "  Docker volumes: $docker_volumes"
log "=== Backup verify complete ==="
send_telegram_message "💾 *Backup Verify*\n\n📋 Volledig log: $LOG_FILE" || true
