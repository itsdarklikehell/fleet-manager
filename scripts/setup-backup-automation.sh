#!/usr/bin/env bash
# scripts/setup-backup-automation.sh - Backup automation
# Voegt automatische backups toe voor disaster recovery
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Backup Automation ==="

# Configuratie
BACKUP_DIR="lib/backup"
mkdir -p "$BACKUP_DIR"

# Functies
create_backup_config() {
  local backup_file="$BACKUP_DIR/backup-config.json"
  
  cat > "$backup_file" << 'BACKUP'
{
  "backup": {
    "enabled": true,
    "schedule": "0 2 * * *",
    "retention_days": 30,
    "targets": [
      "scripts",
      "lib",
      ".github",
      "tests"
    ],
    "storage": {
      "type": "local",
      "path": "/home/hans/.github_fleet_backups"
    },
    "encryption": {
      "enabled": false,
      "key_file": ""
    }
  },
  "restore": {
    "test_schedule": "0 3 1 * *",
    "last_test": null
  }
}
BACKUP
  
  echo "  ✅ Backup config gemaakt"
}

create_backup_helper() {
  local backup_helper="$BACKUP_DIR/backup-helper.sh"
  
  cat > "$backup_helper" << 'BACKUPHELPER'
#!/usr/bin/env bash
# Backup automation helper voor fleet-manager scripts

BACKUP_CONFIG="${BACKUP_CONFIG:-lib/backup/backup-config.json}"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-$HOME/.github_fleet_backups}"

backup_create() {
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_dir="$BACKUP_BASE_DIR/backup_$timestamp"
  
  mkdir -p "$backup_dir"
  
  local targets
  targets=$(jq -r '.backup.targets[]' "$BACKUP_CONFIG")
  
  for target in $targets; do
    if [ -d "$target" ]; then
      cp -r "$target" "$backup_dir/"
    fi
  done
  
  tar -czf "$backup_dir.tar.gz" -C "$BACKUP_BASE_DIR" "backup_$timestamp"
  rm -rf "$backup_dir"
  
  echo "  ✅ Backup gemaakt: $backup_dir.tar.gz"
}

backup_restore() {
  local backup_file="$1"
  local restore_dir="${2:-/tmp/fleet-restore}"
  
  if [ ! -f "$backup_file" ]; then
    echo "  ❌ Backup bestaat niet: $backup_file"
    return 1
  fi
  
  mkdir -p "$restore_dir"
  tar -xzf "$backup_file" -C "$restore_dir"
  
  echo "  ✅ Backup hersteld naar: $restore_dir"
}

backup_list() {
  ls -lh "$BACKUP_BASE_DIR"/backup_*.tar.gz 2>/dev/null || echo "  Geen backups gevonden"
}

backup_cleanup() {
  local retention_days
  retention_days=$(jq -r '.backup.retention_days // 30' "$BACKUP_CONFIG")
  
  find "$BACKUP_BASE_DIR" -name "backup_*.tar.gz" -type f -mtime +$retention_days -delete
  
  echo "  ✅ Oude backups verwijderd (ouder dan $retention_days dagen)"
}

backup_test_restore() {
  local latest_backup
  latest_backup=$(ls -t "$BACKUP_BASE_DIR"/backup_*.tar.gz 2>/dev/null | head -1)
  
  if [ -z "$latest_backup" ]; then
    echo "  ❌ Geen backup beschikbaar voor test"
    return 1
  fi
  
  backup_restore "$latest_backup" /tmp/fleet-restore-test
  
  if [ -f "/tmp/fleet-restore-test/scripts/health-check.sh" ]; then
    echo "  ✅ Restore test geslaagd"
    rm -rf /tmp/fleet-restore-test
    return 0
  else
    echo "  ❌ Restore test gefaald"
    return 1
  fi
}
BACKUPHELPER
  
  chmod +x "$backup_helper"
  echo "  ✅ Backup helper gemaakt"
}

# Hoofdlogica
create_backup_config
create_backup_helper

echo ""
echo "✅ Backup automation setup klaar"
