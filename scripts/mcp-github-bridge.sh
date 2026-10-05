#!/usr/bin/env bash
# scripts/mcp-github-bridge.sh - GitHub MCP server bridge (GEOPTIMALISEERD)
# OPTIMISATIES: parallelisatie, rate limiting, caching, KEY_REPOS only

set -euo pipefail

DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== MCP GitHub Bridge (geoptimaliseerd) ==="

MAX_PARALLEL="${MAX_PARALLEL:-4}"
CACHE_DIR="${CACHE_DIR:-/tmp/github_fleet_cache}"
CACHE_TTL="${CACHE_TTL:-300}"  # 5 minuten
GH_TIMEOUT="${GH_TIMEOUT:-10}"

# Cache dir aanmaken
mkdir -p "$CACHE_DIR"

# Rate limiter
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-/tmp/github_fleet_mcp_rate_limit}"
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

# Cache helper
cache_get() {
  local key="$1"
  local cache_file="$CACHE_DIR/${key}.json"
  if [ -f "$cache_file" ]; then
    local age
    age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo "0")))
    if [ "$age" -lt "$CACHE_TTL" ]; then
      cat "$cache_file"
      return 0
    fi
  fi
  return 1
}

cache_set() {
  local key="$1"
  local data="$2"
  echo "$data" > "$CACHE_DIR/${key}.json"
}

# Parallelle repo context ophalen
get_repo_context() {
  local repo="$1"
  
  rate_limit_check
  
  local cache_key
  cache_key=$(echo "$repo" | tr '/' '_')
  
  if cache_data=$(cache_get "$cache_key" 2>/dev/null); then
    echo "$cache_data"
    return 0
  fi
  
  local context
  context=$(timeout "$GH_TIMEOUT" gh repo view "$repo" --json name,description,url,defaultBranchRef 2>/dev/null || echo "{}")
  
  cache_set "$cache_key" "$context"
  echo "$context"
}

# Fase 1: Repos ophalen
log "Fase 1: Repos ophalen..."

rate_limit_check

# Gebruik KEY_REPOS in plaats van alle 200+ repos
if [ -z "${KEY_REPOS:-}" ]; then
  log "  KEY_REPOS niet gedefinieerd, gebruik standaard set"
  KEY_REPOS=(
    "itsdarklikehell/hermes-desktop"
    "itsdarklikehell/mission-control"
    "itsdarklikehell/hermes-agent"
    "itsdarklikehell/dnd-utils"
    "itsdarklikehell/clawhub"
    "itsdarklikehell/ci-templates"
  )
fi

repo_count=${#KEY_REPOS[@]}
log "  $repo_count repos gevonden (KEY_REPOS)"

# Fase 2: Parallel context ophalen
log "Fase 2: Parallel context ophalen (max=$MAX_PARALLEL)..."

for repo in "${KEY_REPOS[@]}"; do
  log "  Repo: $repo"
  
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
    sleep 0.2
  done
  
  get_repo_context "$repo" &
done
wait

# Fase 3: Samenvatting
log "Fase 3: Samenvatting..."
log "  Context opgehaald voor $repo_count repos"
log "  Cache dir: $CACHE_DIR"
log "=== MCP GitHub Bridge complete ==="

if [ "$TELEGRAM_REPORT_ENABLED" = "yes" ]; then
  send_telegram_message "🌉 *MCP GitHub Bridge* (geoptimaliseerd)

*Repos:* $repo_count
*Cache:* $CACHE_DIR (TTL: ${CACHE_TTL}s)
*Parallel:* max $MAX_PARALLEL jobs

📋 Volledig log: $LOG_FILE" || true
fi
