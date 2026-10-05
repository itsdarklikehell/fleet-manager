#!/usr/bin/env bash
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

BACKUP_DIR="${BACKUP_DIR:-$HOME/.github_fleet_backups}"
mkdir -p "$BACKUP_DIR"

timestamp=$(date +%Y%m%d_%H%M%S)
backup_file="$BACKUP_DIR/fleet-manager_$timestamp.tar.gz"

tar -czf "$backup_file" -C "$(dirname "$0")" scripts/ lib/ .github/ 2>/dev/null || true

echo "Backup gemaakt: $backup_file"

# Oude backups verwijderen (ouder dan 7 dagen)
find "$BACKUP_DIR" -name "fleet-manager_*.tar.gz" -type f -mtime +7 -delete 2>/dev/null || true
