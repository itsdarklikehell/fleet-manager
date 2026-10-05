#!/usr/bin/env bash
# scripts/auto-merge.sh - Auto-merge mergeable PRs (GEOPTIMALISEERD)
# OPTIMISATIES: parallelisatie, rate limiting, batch processing

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

log "=== Auto-Merge (geoptimaliseerd) ==="

MAX_PARALLEL="${MAX_PARALLEL:-4}"
AUTO_MERGE_ENABLED="${AUTO_MERGE_ENABLED:-yes}"

if [ "$AUTO_MERGE_ENABLED" != "yes" ]; then
  log "Auto-merge uitgeschakeld, skip"
  exit 0
fi

# Rate limiter
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-/tmp/github_fleet_merge_rate_limit}"
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
  if [ "$count" -ge 30 ]; then
    log "  Rate limit bereikt, wacht 60s..."
    sleep 60
    echo "$now 0" > "$RATE_LIMIT_FILE"
  fi
}

merge_pr() {
  local pr_json="$1"
  
  local title repo number mergeable
  title=$(echo "$pr_json" | jq -r '.title // "unknown"')
  repo=$(echo "$pr_json" | jq -r '.repository.nameWithOwner // "unknown"')
  number=$(echo "$pr_json" | jq -r '.number // ""')
  mergeable=$(echo "$pr_json" | jq -r '.mergeable // "UNKNOWN"')
  
  [ -z "$number" ] && return 0
  [ "$mergeable" != "MERGEABLE" ] && return 0
  
  log "  Mergen: $repo#$number: $title"
  
  rate_limit_check
  
  if maybe_mutate gh pr merge "$repo#$number" --merge --delete-branch 2>/dev/null; then
    log "    ✓ Gemerged"
  else
    log "    ⚠ Merge gefaald"
  fi
}

# Fase 1: Ophalen
log "Fase 1: Ophalen open PRs..."

rate_limit_check

my_prs=$(gh search prs --state open --author @me --limit 50 --json title,repository,url,number,mergeable 2>/dev/null || echo "[]")

# Fase 2: Parallel mergen
log "Fase 2: Parallel mergen (max=$MAX_PARALLEL)..."

merged_count=0

if [ "$my_prs" != "[]" ] && [ -n "$my_prs" ]; then
  echo "$my_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
    [ -z "$pr" ] && continue
    
    while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
      sleep 0.2
    done
    
    merge_pr "$pr" &
  done
  wait
fi

# Fase 3: Bekende repos
log "Fase 3: Bekende repos doorlopen..."

for repo in "${KEY_REPOS[@]}"; do
  log "  Repo: $repo"
  
  rate_limit_check
  
  repo_prs=$(gh pr list --repo "$repo" --state open --limit 20 --json title,number,mergeable 2>/dev/null || echo "[]")
  if [ "$repo_prs" != "[]" ] && [ -n "$repo_prs" ]; then
    echo "$repo_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
      [ -z "$pr" ] && continue
      
      while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
        sleep 0.2
      done
      
      merge_pr "$pr" &
    done
  fi
done
wait

log "=== Auto-Merge complete ==="

if [ "$TELEGRAM_REPORT_ENABLED" = "yes" ]; then
  send_telegram_message "🔀 *Auto-Merge* (geoptimaliseerd)

*Gemerged:* $merged_count PRs
*Parallel:* max $MAX_PARALLEL jobs

📋 Volledig log: $LOG_FILE" || true
fi
