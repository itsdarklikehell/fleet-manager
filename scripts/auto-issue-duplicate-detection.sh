#!/usr/bin/env bash

# Logging
LOG_FILE="${LOG_FILE:-/tmp/fleet-manager.log}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
# scripts/auto-issue-duplicate-detection.sh - Automatische issue duplicate detection
# Detecteert wanneer een issue een duplicate is van een andere
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

echo "=== Auto Issue Duplicate Detection ==="

# Configuratie
DUPLICATE_DETECTION_ENABLED="${DUPLICATE_DETECTION_ENABLED:-no}"

if [ "$DUPLICATE_DETECTION_ENABLED" != "yes" ]; then
  echo "Duplicate detection is uitgeschakeld (DUPLICATE_DETECTION_ENABLED=$DUPLICATE_DETECTION_ENABLED)"
  exit 0
fi

# Functies
check_duplicate() {
  local repo="$1"
  local issue_number="$2"
  
  # Haal issue op
  local title
  title=$(gh issue view "$issue_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  local body
  body=$(gh issue view "$issue_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  
  # Zoek soortgelijke issues
  local similar
  similar=$(gh search issues --repo "$repo" --state open --match title,body --limit 5 --json number,title --jq '.[] | select(.number != '"$issue_number"') | "\(.number): \(.title)"' 2>/dev/null || echo "")
  
  if [ -n "$similar" ]; then
    echo "    ⚠️ Mogelijke duplicates voor issue #$issue_number:"
    echo "$similar" | while read -r line; do
      echo "      - $line"
    done
    
    # Voeg duplicate label toe
    gh issue edit "$issue_number" --repo "$repo" --add-label "duplicate" > /dev/null 2>&1 || true
  else
    echo "    ✅ Geen duplicates gevonden voor issue #$issue_number"
  fi
}

# Hoofdlogica
echo "Duplicates detecteren..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  issues=$(gh issue list --repo "$repo" --state open --json number --jq '.[].number' 2>/dev/null || echo "")
  
  for issue in $issues; do
    check_duplicate "$repo" "$issue"
  done
done

echo ""
echo "✅ Auto issue duplicate detection klaar"
