#!/usr/bin/env bash
# scripts/stale-issue-detection.sh - Detecteer en markeer inactieve issues/PRs
# Issues/PRs die X dagen niet gecommuniceerd, markeren als stale
set -euo pipefail
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Stale Issue Detection ==="

# Configuratie
SID_ENABLED="${SID_ENABLED:-yes}"
SID_DRY_RUN="${SID_DRY_RUN:-no}"
SID_STALE_DAYS="${SID_STALE_DAYS:-30}"
SID_CLOSE_DAYS="${SID_CLOSE_DAYS:-14}"
SID_LIMIT="${SID_LIMIT:-100}"

SINCE_STALE=$(date -d "$SID_STALE_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")
SINCE_CLOSE=$(date -d "$SID_CLOSE_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Stale label en bericht
STALE_LABEL="stale"
STALE_MESSAGE="Dit item is inactief geweest gedurende meer dan ${SID_STALE_DAYS} dagen. Het zal automatisch worden gesloten in ${SID_CLOSE_DAYS} dagen als er geen activiteit is. Reageer gerust als dit nog relevant is."
CLOSE_MESSAGE="Gesloten vanwege inactiviteit. Mocht dit nog relevant zijn, dan kunt u een nieuw issue openen."

# Functie: label en comment toevoegen
mark_stale() {
  local repo="$1"
  local issue_number="$2"
  local title="$3"
  local is_pr="${4:-false}"
  
  log "  Marking issue/PR #$issue_number ($title) as stale"
  
  if [ "$SID_DRY_RUN" = "yes" ]; then
    log "    [DRY RUN] Would mark as stale"
    return 0
  fi
  
  # Add stale label
  gh api "repos/$repo/issues/$issue_number/labels" \
    -X POST \
    -f "labels=[\"${STALE_LABEL}\"]" \
    2>/dev/null || true
  
  # Post stale comment
  gh api "repos/$repo/issues/$issue_number/comments" \
    -X POST \
    -f "body=$STALE_MESSAGE" \
    2>/dev/null || true
  
  log "    ✅ Gemarkeerd als stale"
}

# Functie: issue/PR sluiten
close_stale() {
  local repo="$1"
  local issue_number="$2"
  local title="$3"
  local is_pr="${4:-false}"
  
  log "  Closing issue/PR #$issue_number ($title)"
  
  if [ "$SID_DRY_RUN" = "yes" ]; then
    log "    [DRY RUN] Would close"
    return 0
  fi
  
  # Post close message
  gh api "repos/$repo/issues/$issue_number/comments" \
    -X POST \
    -f "body=$CLOSE_MESSAGE" \
    2>/dev/null || true
  
  # Close the issue/PR
  gh api "repos/$repo/issues/$issue_number" \
    -X PATCH \
    -f "state=closed" \
    2>/dev/null || true
  
  log "    ✅ Gesloten"
}

# Functie: check of item al stale is gemarkeerd
is_already_stale() {
  local repo="$1"
  local issue_number="$2"
  
  local labels
  labels=$(gh api "repos/$repo/issues/$issue_number" --jq '.labels[].name' 2>/dev/null || echo "")
  
  if echo "$labels" | grep -q "^${STALE_LABEL}$"; then
    return 0
  fi
  return 1
}

# Functie: check laatste activiteit
get_last_activity() {
  local repo="$1"
  local issue_number="$2"
  local is_pr="${3:-false}"
  
  local endpoint="repos/$repo/issues/$issue_number"
  if [ "$is_pr" = "true" ]; then
    endpoint="repos/$repo/issues/$issue_number/timeline"
  fi
  
  local last_updated
  last_updated=$(gh api "repos/$repo/issues/$issue_number" --jq '.updatedAt' 2>/dev/null || echo "")
  
  echo "$last_updated"
}

# Hoofdlogica
if [ "$SID_ENABLED" != "yes" ]; then
  log "Stale issue detection uitgeschakeld"
  exit 0
fi

for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  log "Scanning for stale issues in $kr..."
  
  # Get open issues older than SINCE_STALE
  issues=$(gh search issues --repo "$kr" --state open --limit "$SID_LIMIT" \
    --json number,title,updatedAt,author,labels,createdAt \
    --jq ".[] | select(.updatedAt <= \"${SINCE_STALE}\") | select(.author.type != \"Bot\") | \"\(.number)|\(.title)|\(.updatedAt)\"" \
    2>/dev/null || echo "")
  
  if [ -n "$issues" ]; then
    marked=0
    closed=0
    
    echo "$issues" | while IFS='|' read -r number title updated; do
      [ -z "$number" ] && continue
      
      # Skip if already stale
      if is_already_stale "$kr" "$number"; then
        # Check if it should be closed (stale for close_days)
        last_activity=$(get_last_activity "$kr" "$number")
        if [ -n "$last_activity" ] && [ "$last_activity" \< "$SINCE_CLOSE" ]; then
          close_stale "$kr" "$number" "$title"
          closed=$((closed + 1))
        fi
      else
        mark_stale "$kr" "$number" "$title"
        marked=$((marked + 1))
      fi
    done
    
    log "  📊 $kr: $marked gemarkeerd als stale, $closed gesloten"
  else
    log "  ✅ Geen inactieve issues gevonden"
  fi
  
  log "Scanning for stale PRs in $kr..."
  
  # Get open PRs older than SINCE_STALE
  prs=$(gh search prs --repo "$kr" --state open --limit "$SID_LIMIT" \
    --json number,title,updatedAt,author,labels \
    --jq ".[] | select(.updatedAt <= \"${SINCE_STALE}\") | select(.author.type != \"Bot\") | \"\(.number)|\(.title)|\(.updatedAt)\"" \
    2>/dev/null || echo "")
  
  if [ -n "$prs" ]; then
    marked=0
    closed=0
    
    echo "$prs" | while IFS='|' read -r number title updated; do
      [ -z "$number" ] && continue
      
      if is_already_stale "$kr" "$number"; then
        last_activity=$(get_last_activity "$kr" "$number" "true")
        if [ -n "$last_activity" ] && [ "$last_activity" \< "$SINCE_CLOSE" ]; then
          close_stale "$kr" "$number" "$title" "true"
          closed=$((closed + 1))
        fi
      else
        mark_stale "$kr" "$number" "$title" "true"
        marked=$((marked + 1))
      fi
    done
    
    log "  📊 $kr: $marked PRs gemarkeerd als stale, $closed PRs gesloten"
  else
    log "  ✅ Geen inactieve PRs gevonden"
  fi
done

log "=== Stale Issue Detection klaar ==="
