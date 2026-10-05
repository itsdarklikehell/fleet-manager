#!/usr/bin/env bash
# scripts/auto-labeling.sh - Automatische labeling van issues/PRs (GEOPTIMALISEERD)
# OPTIMISATIES: parallelisatie, rate limiting, sleep verwijderd

set -euo pipefail

DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Automatische Labeling (geoptimaliseerd) ==="

# Configuratie
MAX_PARALLEL="${MAX_PARALLEL:-4}"
RATE_LIMIT_DELAY="${RATE_LIMIT_DELAY:-0.5}"
LABEL_RULES="${LABEL_RULES:-}"

# Rate limiter
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-/tmp/github_fleet_label_rate_limit}"
rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - 60))
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
  if [ "$count" -ge 60 ]; then
    log "  Rate limit bereikt ($count requests/min), wacht 5s..."
    sleep 5
    echo "$now 0" > "$RATE_LIMIT_FILE"
  fi
}

# Label regels
get_labels_for_title() {
  local title="$1"
  local labels=""
  
  echo "$title" | grep -qiE "bug|fix|error|crash|broken|regression" && labels="${labels}bug,"
  echo "$title" | grep -qiE "feature|enhancement|add|request|suggest" && labels="${labels}enhancement,"
  echo "$title" | grep -qiE "doc|readme|typo|documentation" && labels="${labels}documentation,"
  echo "$title" | grep -qiE "security|vuln|cve|exploit" && labels="${labels}security,"
  echo "$title" | grep -qiE "performance|slow|optimi|speed" && labels="${labels}performance,"
  echo "$title" | grep -qiE "test|spec|coverage" && labels="${labels}testing,"
  echo "$title" | grep -qiE "refactor|cleanup|simplify" && labels="${labels}refactor,"
  echo "$title" | grep -qiE "dependenc|upgrade|update|bump" && labels="${labels}dependencies,"
  echo "$title" | grep -qiE "good first issue|beginner|starter" && labels="${labels}good-first-issue,"
  echo "$title" | grep -qiE "help wanted|help-wanted" && labels="${labels}help-wanted,"
  
  # Verwijder trailing comma
  echo "${labels%,}"
}

# Parallelle label functie
apply_labels() {
  local item_json="$1"
  local type="$2"
  
  local title repo number
  title=$(echo "$item_json" | jq -r '.title // "unknown"')
  repo=$(echo "$item_json" | jq -r '.repository.nameWithOwner // "unknown"')
  number=$(echo "$item_json" | jq -r '.number // ""')
  
  [ -z "$number" ] && return 0
  
  local labels
  labels=$(get_labels_for_title "$title")
  
  [ -z "$labels" ] && return 0
  
  log "  [$type] $repo#$number: $title → labels: $labels"
  
  rate_limit_check
  
  IFS=',' read -ra LABEL_ARRAY <<< "$labels"
  for label in "${LABEL_ARRAY[@]}"; do
    [ -z "$label" ] && continue
    if [ "$type" = "issue" ]; then
      maybe_mutate gh issue edit "$repo#$number" --add-label "$label" 2>/dev/null && log "    ✓ Label '$label'" || true
    else
      maybe_mutate gh pr edit "$repo#$number" --add-label "$label" 2>/dev/null && log "    ✓ Label '$label'" || true
    fi
  done
}

# Fase 1: Ophalen
log "Fase 1: Ophalen issues en PRs..."

rate_limit_check

my_issues=$(gh search issues --state open --author @me --limit 50 --json title,repository,url,body,number 2>/dev/null || echo "[]")
my_prs=$(gh search prs --state open --author @me --limit 50 --json title,repository,url,body,number 2>/dev/null || echo "[]")

# Fase 2: Parallel verwerken
log "Fase 2: Parallel labelen (max=$MAX_PARALLEL)..."

labeled_count=0

if [ "$my_issues" != "[]" ] && [ -n "$my_issues" ]; then
  echo "$my_issues" | jq -c '.[]' 2>/dev/null | while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    
    while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
      sleep 0.2
    done
    
    apply_labels "$issue" "issue" &
  done
  wait
fi

if [ "$my_prs" != "[]" ] && [ -n "$my_prs" ]; then
  echo "$my_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
    [ -z "$pr" ] && continue
    
    while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
      sleep 0.2
    done
    
    apply_labels "$pr" "pr" &
  done
  wait
fi

# Fase 3: Bekende repos
log "Fase 3: Bekende repos doorlopen..."

for repo in "${KEY_REPOS[@]}"; do
  log "  Repo: $repo"
  
  rate_limit_check
  
  repo_issues=$(gh issue list --repo "$repo" --state open --limit 20 --json title,number,body,url 2>/dev/null || echo "[]")
  if [ "$repo_issues" != "[]" ] && [ -n "$repo_issues" ]; then
    echo "$repo_issues" | jq -c '.[]' 2>/dev/null | while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      
      while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
        sleep 0.2
      done
      
      apply_labels "$issue" "issue" &
    done
  fi
  
  rate_limit_check
  
  repo_prs=$(gh pr list --repo "$repo" --state open --limit 20 --json title,number,body,url 2>/dev/null || echo "[]")
  if [ "$repo_prs" != "[]" ] && [ -n "$repo_prs" ]; then
    echo "$repo_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
      [ -z "$pr" ] && continue
      
      while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
        sleep 0.2
      done
      
      apply_labels "$pr" "pr" &
    done
  fi
done
wait

log "=== Automatische Labeling complete ==="

if [ "$TELEGRAM_REPORT_ENABLED" = "yes" ]; then
  send_telegram_message "🏷️ *Automatische Labeling* (geoptimaliseerd)

*Items verwerkt:* $labeled_count
*Parallel:* max $MAX_PARALLEL jobs

📋 Volledig log: $LOG_FILE" || true
fi
