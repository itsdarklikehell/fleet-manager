#!/usr/bin/env bash
# Metrics collection helper voor fleet-manager scripts

METRICS_FILE="${METRICS_FILE:-$HOME/.github_fleet_metrics/execution-metrics.jsonl}"

metrics_record() {
  local script="$1"
  local status="$2"
  local duration="$3"
  local timestamp
  timestamp=$(date -Iseconds)
  
  echo "{\"timestamp\":\"$timestamp\",\"script\":\"$script\",\"status\":\"$status\",\"duration\":$duration}" >> "$METRICS_FILE"
}

metrics_summary() {
  if [ -f "$METRICS_FILE" ]; then
    local total
    total=$(wc -l < "$METRICS_FILE")
    local success
    success=$(grep -c '"status":"success"' "$METRICS_FILE" 2>/dev/null || echo 0)
    local failed
    failed=$(grep -c '"status":"failed"' "$METRICS_FILE" 2>/dev/null || echo 0)
    
    echo "  Totaal: $total"
    echo "  Succes: $success"
    echo "  Gefaald: $failed"
  fi
}
