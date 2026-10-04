#!/usr/bin/env bash

# Logging
LOG_FILE="${LOG_FILE:-/tmp/fleet-manager.log}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
# scripts/update-scripts.sh - Automatische dependency updates voor scripts
# Controleert op nieuwe gh CLI features en update verouderde API endpoints
set -euo pipefail

# DRY_RUN mode
DRY_RUN="${DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    echo "[DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Update Scripts ==="

# Check gh CLI version (portable met sed)
GH_VERSION=$(gh --version 2>/dev/null | head -1 | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' || echo "unknown")
echo "gh CLI versie: $GH_VERSION"

# Check voor verouderde API endpoints
echo ""
echo "Controleren op verouderde endpoints..."

# Verouderde: gh repo view --json topics
# Nieuwe: gh repo view --json repositoryTopics
for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  if grep -q '\-\-json topics' "$script" 2>/dev/null; then
    echo "  ⚠️ $script: verouderd --json topics"
  fi
done

# Check voor verouderde: gh repo edit --add-topics
# Nieuwe: gh repo edit --add-topic
for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  if grep -q '\-\-add-topics' "$script" 2>/dev/null; then
    echo "  ⚠️ $script: verouderd --add-topics"
  fi
done

# Check voor verouderde: gh run list --json id
# Nieuwe: gh run list --json databaseId
for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  if grep -q '\-\-json id' "$script" 2>/dev/null; then
    echo "  ⚠️ $script: verouderd --json id (gebruik databaseId)"
  fi
done

echo ""
echo "✅ Update scripts klaar"
