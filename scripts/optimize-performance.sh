#!/usr/bin/env bash
# scripts/optimize-performance.sh - Performance optimalisatie
# Voegt parallelisatie, caching en rate limiting toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

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

echo "=== Performance Optimalisatie ==="

# Configuratie
PERF_DIR="lib/performance"
mkdir -p "$PERF_DIR"

# Functies
setup_parallelization() {
  local parallel="$PERF_DIR/parallel.sh"
  
  cat > "$parallel" << 'PARALLEL'
#!/usr/bin/env bash
# Parallelisatie helper voor fleet-manager scripts

MAX_JOBS="${MAX_JOBS:-4}"

run_parallel() {
  local func="$1"
  shift
  local items=("$@")
  local pids=()
  
  for item in "${items[@]}"; do
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do    done
    "$func" "$item" &
    pids+=($!)
  done
  
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
}

run_parallel_with_timeout() {
  local func="$1"
  local timeout="$2"
  shift 2
  local items=("$@")
  local pids=()
  
  for item in "${items[@]}"; do
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do    done
    (
      timeout "$timeout" "$func" "$item"
    ) &
    pids+=($!)
  done
  
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
}
PARALLEL
  
  chmod +x "$parallel"
  echo "  ✅ Parallelisatie helper ingesteld"
}

setup_caching() {
  local cache="$PERF_DIR/cache.sh"
  
  cat > "$cache" << 'CACHE'
#!/usr/bin/env bash
# Caching helper voor fleet-manager scripts

CACHE_DIR="${CACHE_DIR:-$HOME/.github_fleet_cache}"
CACHE_TTL="${CACHE_TTL:-3600}"  # 1 uur

cache_init() {
  mkdir -p "$CACHE_DIR"
}

cache_get() {
  local key="$1"
  local cache_file="$CACHE_DIR/${key}.cache"
  
  if [ -f "$cache_file" ]; then
    local age
    age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
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
  echo "$value" > "$CACHE_DIR/${key}.cache"
}

cache_clear() {
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
}
CACHE
  
  chmod +x "$cache"
  echo "  ✅ Caching helper ingesteld"
}

setup_rate_limiting() {
  local rate_limit="$PERF_DIR/rate-limit.sh"
  
  cat > "$rate_limit" << 'RATE_LIMIT'
#!/usr/bin/env bash
# Rate limiting helper voor fleet-manager scripts

RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-$HOME/.github_fleet_rate_limit}"
RATE_LIMIT_MAX="${RATE_LIMIT_MAX:-4500}"
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-3600}"

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
    echo "Rate limit bereikt ($count/$RATE_LIMIT_MAX)" >&2
    return 1
  fi
  return 0
}

rate_limit_wait() {
  local remaining
  remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "0")
  
  if [ "$remaining" -lt 100 ]; then
    local reset_time
    reset_time=$(gh api rate_limit --jq '.resources.core.reset' 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local wait_time=$((reset_time - now))
    
    if [ "$wait_time" -gt 0 ]; then
      echo "Rate limit bijna bereikt, wacht ${wait_time}s..." >&2
      sleep "$wait_time"
    fi
  fi
}
RATE_LIMIT
  
  chmod +x "$rate_limit"
  echo "  ✅ Rate limiting helper ingesteld"
}

# Hoofdlogica
setup_parallelization
setup_caching
setup_rate_limiting

echo ""
echo "✅ Performance optimalisatie klaar"
