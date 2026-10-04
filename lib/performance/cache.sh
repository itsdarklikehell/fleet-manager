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
