#!/usr/bin/env bash
# scripts/stale-issue-detection.sh - Detecteer en markeer inactieve issues/PRs
# Issues/PRs die X dagen niet gecommuniceerd, markeren als stale
set -euo pipefail
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

# Caching (5 min TTL)
CACHE_DIR="${CACHE_DIR:-/tmp/github_fleet_cache}"
CACHE_TTL="${CACHE_TTL:-300}"
mkdir -p "$CACHE_DIR"

cache_get() {
  local key="$1"
  local cache_file="$CACHE_DIR/${key//\//_}"
  if [ -f "$cache_file" ]; then
    local age
    age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [ "$age" -lt "$CACHE_TTL" ]; then
      cat "$cache_file"
      return 0
    fi
  fi
  return 1
}

cache_set() {
  local key="$1"
  local value="$2"
  local cache_file="$CACHE_DIR/${key//\//_}"
  echo "$value" > "$cache_file"
}

# Progress tracking
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0

progress_start() {
  PROGRESS_TOTAL=$1
  PROGRESS_CURRENT=0
  log "  Start: $PROGRESS_TOTAL items te verwerken"
}

progress_update() {
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
  if [ $((PROGRESS_CURRENT % 10)) -eq 0 ] || [ "$PROGRESS_CURRENT" -eq "$PROGRESS_TOTAL" ]; then
    log "  Voortgang: $PROGRESS_CURRENT/$PROGRESS_TOTAL"
  fi
}

# Rate limiting (30 req/min voor GitHub API)
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-$HOME/.github_fleet_rate_limit}"
RATE_LIMIT_MAX="${RATE_LIMIT_MAX:-30}"
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-60}"

rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - RATE_LIMIT_WINDOW))
  
  local count=0
  local file_time=0
  if [ -f "$RATE_LIMIT_FILE" ]; then
    read -r file_time count < "$RATE_LIMIT_FILE" 2>/dev/null || true
    if [ -z "$file_time" ] || [ "$file_time" -lt "$window_start" ]; then
      count=0
    fi
  fi
  
  count=$((count + 1))
  echo "$now $count" > "$RATE_LIMIT_FILE"
  
  if [ "$count" -ge "$RATE_LIMIT_MAX" ]; then
    log "  Rate limit bereikt ($count requests in laatste ${RATE_LIMIT_WINDOW}s), wacht..."
    sleep "$RATE_LIMIT_WINDOW"
    echo "$((now + RATE_LIMIT_WINDOW)) 0" > "$RATE_LIMIT_FILE"
    return 1
  fi
  return 0
}

# Wrapper voor timeout 15 gh api met rate limiting
gh_api_rate_limited() {
  rate_limit_check || true
  timeout 15 gh api "$@"
}

# Parallelisatie config
MAX_PARALLEL="${MAX_PARALLEL:-4}"

# Helper: wacht tot er ruimte is voor nieuwe job
wait_for_slot() {
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
    sleep 0.1
  done
}

# Helper: wacht op alle jobs
wait_all_jobs() {
  wait
}

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
  timeout 15 gh api "repos/$repo/issues/$issue_number/labels" \
    -X POST \
    -f "labels=[\"${STALE_LABEL}\"]" \
    2>/dev/null || true
  
  # Post stale comment
  timeout 15 gh api "repos/$repo/issues/$issue_number/comments" \
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
  timeout 15 gh api "repos/$repo/issues/$issue_number/comments" \
    -X POST \
    -f "body=$CLOSE_MESSAGE" \
    2>/dev/null || true
  
  # Close the issue/PR
  timeout 15 gh api "repos/$repo/issues/$issue_number" \
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
  labels=$(timeout 15 gh api "repos/$repo/issues/$issue_number" --jq '.labels[].name' 2>/dev/null || echo "")
  
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
  last_updated=$(timeout 15 gh api "repos/$repo/issues/$issue_number" --jq '.updatedAt' 2>/dev/null || echo "")
  
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
