#!/usr/bin/env bash
# scripts/self-update.sh - Self update voor fleet manager
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Self Update ==="
local fleet_dir="/home/hans/.openclaw/workspace/projects/fleet-manager"
if [ -d "$fleet_dir/.git" ]; then
  cd "$fleet_dir"
  local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  log "  Huidige commit: $current_commit"
  git fetch origin main 2>/dev/null || true
  local remote_commit=$(git rev-parse origin/main 2>/dev/null || echo "unknown")
  log "  Remote commit: $remote_commit"
  if [ "$current_commit" != "$remote_commit" ]; then
    log "  🔄 Update beschikbaar, pullen..."
    git pull origin main 2>/dev/null || true
    log "  ✓ Update voltooid"
  else
    log "  ✓ Al up-to-date"
  fi
else
  log "  ⚠️ Fleet manager repo niet gevonden"
fi
log "=== Self Update complete ==="
send_telegram_message "🔄 *Self Update*\n\n📋 Volledig log: $LOG_FILE" || true
