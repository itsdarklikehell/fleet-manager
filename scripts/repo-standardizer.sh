#!/usr/bin/env bash
# scripts/repo-standardizer.sh - Standaardiseer repo instellingen
# Zorgt voor consistente issue templates, labels en bestanden
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Repo Standardizer ==="

# Configuratie
STANDARD_LABELS=("bug" "enhancement" "documentation" "good first issue" "help wanted" "question" "wontfix")
STANDARD_FILES=("LICENSE" "CONTRIBUTING.md" "SECURITY.md" "CODE_OF_CONDUCT.md")

# Functies
ensure_labels() {
  local repo="$1"
  log "  Labels controleren voor $repo..."
  
  for label in "${STANDARD_LABELS[@]}"; do
    # Check of label bestaat
    if ! gh api "repos/$repo/labels/$label" > /dev/null 2>&1; then
      # Maak label aan
      local color
      case "$label" in
        "bug") color="d73a4a" ;;
        "enhancement") color="a2eeef" ;;
        "documentation") color="0075ca" ;;
        "good first issue") color="7057ff" ;;
        "help wanted") color="008672" ;;
        "question") color="d876e3" ;;
        "wontfix") color="ffffff" ;;
        *) color="cccccc" ;;
      esac
      
      gh api "repos/$repo/labels" -X POST -f name="$label" -f color="$color" > /dev/null 2>&1 || true
      log "    ✅ Label '$label' toegevoegd"
    fi
  done
}

ensure_files() {
  local repo="$1"
  log "  Bestanden controleren voor $repo..."
  
  for file in "${STANDARD_FILES[@]}"; do
    if ! gh api "repos/$repo/contents/$file" > /dev/null 2>&1; then
      log "    ⚠️ $file ontbreekt in $repo"
      # TODO: Automatisch toevoegen (vereist sjabloon)
    fi
  done
}

ensure_issue_template() {
  local repo="$1"
  log "  Issue template controleren voor $repo..."
  
  if ! gh api "repos/$repo/contents/.github/ISSUE_TEMPLATE" > /dev/null 2>&1; then
    log "    ⚠️ Geen issue template in $repo"
  fi
}

# Hoofdlogica
log "Repos standaardiseren..."

repos=$(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || echo "")

if [ -z "$repos" ]; then
  log "❌ Geen repos gevonden"
  exit 1
fi

for repo in $repos; do
  log ""
  log "--- $repo ---"
  ensure_labels "$repo"
  ensure_files "$repo"
  ensure_issue_template "$repo"
done

log ""
log "✅ Repo standardizer klaar"
