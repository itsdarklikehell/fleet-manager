#!/usr/bin/env bash

# Logging
LOG_FILE="${LOG_FILE:-/tmp/fleet-manager.log}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
# scripts/performance-monitor.sh - Performance monitor
# Bijhouden hoe lang elke script duurt en traagste scripts identificeren
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Performance Monitor ==="

# Configuratie
PERF_DIR="${PERF_DIR:-$HOME/.github_fleet_performance}"
mkdir -p "$PERF_DIR"
PERF_FILE="$PERF_DIR/performance.json"

# Functies
record_timing() {
  local script_name="$1"
  local duration="$2"
  local status="$3"
  
  local entry
  entry=$(jq -n --arg script "$script_name" --arg duration "$duration" --arg status "$status" --arg timestamp "$(date -Iseconds)" '{
    script: $script,
    duration: ($duration | tonumber),
    status: $status,
    timestamp: $timestamp
  }')
  
  # Voeg toe aan performance file
  if [ -f "$PERF_FILE" ]; then
    jq --argjson entry "$entry" '. + [$entry]' "$PERF_FILE" > "$PERF_FILE.tmp" && mv "$PERF_FILE.tmp" "$PERF_FILE"
  else
    echo "[$entry]" > "$PERF_FILE"
  fi
}

analyze_performance() {
  echo ""
  echo "=== Performance Analyse ==="
  
  if [ ! -f "$PERF_FILE" ]; then
    echo "  Geen performance data beschikbaar"
    return
  fi
  
  # Traagste scripts
  echo ""
  echo "Traagste scripts (laatste 100 runs):"
  jq -r '.[-100:] | group_by(.script) | map({script: .[0].script, avg_duration: (map(.duration) | add / length)}) | sort_by(-.avg_duration) | .[:10][] | "  \(.script): \(.avg_duration)s gemiddeld"' "$PERF_FILE" 2>/dev/null || echo "  Geen data"
  
  # Meest voorkomende scripts
  echo ""
  echo "Meest voorkomende scripts:"
  jq -r 'group_by(.script) | map({script: .[0].script, count: length}) | sort_by(-.count) | .[:10][] | "  \(.script): \(.count) runs"' "$PERF_FILE" 2>/dev/null || echo "  Geen data"
  
  # Fout ratio
  echo ""
  echo "Fout ratio per script:"
  jq -r 'group_by(.script) | map({script: .[0].script, total: length, failures: map(select(.status == "FAIL")) | length}) | map(. + {failure_rate: (.failures / .total * 100)}) | sort_by(-.failure_rate) | .[:10][] | "  \(.script): \(.failure_rate | round)% fout (\(.failures)/\(.total))"' "$PERF_FILE" 2>/dev/null || echo "  Geen data"
}

# Hoofdlogica
echo "Performance data analyseren..."
analyze_performance

echo ""
echo "✅ Performance monitor klaar"
