#!/usr/bin/env bash
# scripts/docs-drift-detection.sh - Detecteert docs drift
# Controleert of docs zijn bijgewerkt na code-wijzigingen
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Docs Drift Detection ==="

# Configuratie
DRIFT_REPOS="${DRIFT_REPOS:-${KEY_REPOS[@]}}"
DRIFT_LIMIT="${DRIFT_LIMIT:-30}"
DRIFT_DAYS="${DRIFT_DAYS:-7}"

SINCE=$(date -d "$DRIFT_DAYS days ago" '+%Y-%m-%dT00:00:00Z' 2>/dev/null || date -v-${DRIFT_DAYS}d '+%Y-%m-%dT00:00:00Z' 2>/dev/null || echo "2025-01-01T00:00:00Z")

# Functies
check_docs_drift() {
  local repo="$1"
  local pr_number="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  # Haal PR info op
  local title files
  title=$(gh pr view "$pr_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  files=$(gh pr diff "$pr_number" --repo "$repo" --name-only 2>/dev/null || echo "")
  
  # Controleer of code is gewijzigd
  local code_changed=false
  local docs_changed=false
  local code_files=""
  local docs_files=""
  
  while IFS= read -r file; do
    if [ -z "$file" ]; then continue; fi
    
    # Code bestanden
    if echo "$file" | grep -qE '\.(py|js|ts|go|rs|sh|yaml|yml|toml|json)$'; then
      code_changed=true
      code_files="$code_files $file"
    fi
    
    # Docs bestanden
    if echo "$file" | grep -qE '(README|CHANGELOG|CONTRIBUTING|docs/|\.md$)'; then
      docs_changed=true
      docs_files="$docs_files $file"
    fi
  done <<< "$files"
  
  # Rapporteer drift
  if [ "$code_changed" = true ] && [ "$docs_changed" = false ]; then
    log "  ⚠️ Docs drift gedetecteerd in PR #$pr_number ($repo)"
    log "    Code gewijzigd:$code_files"
    log "    Geen docs bijgewerkt"
    return 1
  elif [ "$code_changed" = true ] && [ "$docs_changed" = true ]; then
    log "  ✅ PR #$pr_number ($repo): code en docs beide bijgewerkt"
    return 0
  else
    log "  ℹ️ PR #$pr_number ($repo): geen code-wijzigingen"
    return 0
  fi
}

# Hoofdlogica
total_prs=0
drift_count=0

for repo in "${DRIFT_REPOS[@]}"; do
  org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Checking docs drift in $repo..."
  
  # Haal recente merged PRs op
  prs=$(gh pr list --repo "$repo" --state merged --limit "$DRIFT_LIMIT" --json number,title,mergedAt --jq ".[] | select(.mergedAt >= \"${SINCE}\") | \"\(.number) \(.title)\"" 2>/dev/null || echo "")
  
  if [ -n "$prs" ]; then
    count=$(echo "$prs" | wc -l)
    total_prs=$((total_prs + count))
    log "  $count merged PRs gevonden"
    
    echo "$prs" | while read -r line; do
      pr_number=$(echo "$line" | awk '{print $1}')
      if ! check_docs_drift "$repo" "$pr_number"; then
        drift_count=$((drift_count + 1))
      fi
    done
  else
    log "  Geen recente merged PRs gevonden"
  fi
done

log "=== Docs Drift Samenvatting ==="
log "Totaal merged PRs gecontroleerd: $total_prs"
log "Docs drift gedetecteerd: $drift_count"
log "=== Docs Drift Detection klaar ==="
