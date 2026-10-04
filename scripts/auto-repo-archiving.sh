#!/usr/bin/env bash

# Logging
LOG_FILE="${LOG_FILE:-/tmp/fleet-manager.log}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
# scripts/auto-repo-archiving.sh - Automatische repo archiving
# Repos die >6 maanden niet actief zijn automatisch archiveren
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Repo Archiving ==="

# Configuratie
ARCHIVE_DAYS="${ARCHIVE_DAYS:-180}"
AUTO_ARCHIVE_ENABLED="${AUTO_ARCHIVE_ENABLED:-no}"

if [ "$AUTO_ARCHIVE_ENABLED" != "yes" ]; then
  echo "Auto archiving is uitgeschakeld (AUTO_ARCHIVE_ENABLED=$AUTO_ARCHIVE_ENABLED)"
  exit 0
fi

# Functies
check_last_activity() {
  local repo="$1"
  local last_push
  last_push=$(gh api "repos/$repo" --jq '.pushed_at' 2>/dev/null || echo "")
  
  if [ -z "$last_push" ]; then
    echo "0"
    return
  fi
  
  local now
  now=$(date +%s)
  local last_push_ts
  last_push_ts=$(date -d "$last_push" +%s 2>/dev/null || echo "0")
  
  local days_inactive=$(( (now - last_push_ts) / 86400 ))
  echo "$days_inactive"
}

archive_repo() {
  local repo="$1"
  local days_inactive="$2"
  
  echo "  Archiveren van $repo ($days_inactive dagen inactief)..."
  
  # Archive repo
  gh api "repos/$repo" -X PATCH -f archived=true > /dev/null 2>&1 || {
    echo "    ❌ Archiveren gefaald"
    return 1
  }
  
  echo "    ✅ Gearchiveerd"
  
  # Notificatie
  send_telegram_message "📦 **Repo Gearchiveerd**

Repo: $repo
Inactief: $days_inactive dagen
Reden: Auto-archiving na $ARCHIVE_DAYS dagen inactiviteit"
}

# Hoofdlogica
echo "Controleren op inactieve repos..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  # Skip al gearchiveerde repos
  archived
  archived=$(gh api "repos/$repo" --jq '.archived' 2>/dev/null || echo "false")
  [ "$archived" = "true" ] && continue
  
  days_inactive
  days_inactive=$(check_last_activity "$repo")
  
  if [ "$days_inactive" -ge "$ARCHIVE_DAYS" ]; then
    archive_repo "$repo" "$days_inactive"
  fi
done

echo ""
echo "✅ Auto repo archiving klaar"
