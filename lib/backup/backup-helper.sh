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
