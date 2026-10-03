#!/usr/bin/env bash
# scripts/auto-script-dependency-updates.sh - Automatische dependency updates voor scripts
# De scripts gebruiken soms oude gh CLI syntax. Automatisch bijwerken.
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Script Dependency Updates ==="

# Configuratie
SCRIPT_UPDATE_ENABLED="${SCRIPT_UPDATE_ENABLED:-no}"

if [ "$SCRIPT_UPDATE_ENABLED" != "yes" ]; then
  echo "Script updates is uitgeschakeld (SCRIPT_UPDATE_ENABLED=$SCRIPT_UPDATE_ENABLED)"
  exit 0
fi

# Functies
update_deprecated_syntax() {
  local script="$1"
  local modified=false
  
  # Verouderde: gh repo view --json topics
  # Nieuwe: gh repo view --json repositoryTopics
  if grep -q '\-\-json topics' "$script" 2>/dev/null; then
    sed -i 's/\-\-json topics/--json repositoryTopics/g' "$script"
    modified=true
  fi
  
  # Verouderde: gh repo edit --add-topics
  # Nieuwe: gh repo edit --add-topic
  if grep -q '\-\-add-topics' "$script" 2>/dev/null; then
    sed -i 's/\-\-add-topics/--add-topic/g' "$script"
    modified=true
  fi
  
  # Verouderde: gh run list --json id
  # Nieuwe: gh run list --json databaseId
  if grep -q '\-\-json id' "$script" 2>/dev/null; then
    sed -i 's/\-\-json id/--json databaseId/g' "$script"
    modified=true
  fi
  
  if [ "$modified" = true ]; then
    echo "  ✅ $script bijgewerken"
  fi
}

# Hoofdlogica
echo "Scripts controleren op verouderde syntax..."

for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  update_deprecated_syntax "$script"
done

echo ""
echo "✅ Auto script dependency updates klaar"
