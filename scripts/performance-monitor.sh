#!/usr/bin/env bash
# scripts/performance-monitor.sh - Performance monitoring voor fleet scripts
# Meet runtime van alle scripts, genereert rapport, stelt alerts in

set -euo pipefail

source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Performance Monitor ==="

PERF_DIR="${PERF_DIR:-/tmp/fleet_performance}"
PERF_HISTORY="${PERF_DIR}/history.json"
ALERT_THRESHOLD="${ALERT_THRESHOLD:-30}"  # seconden
MAX_PARALLEL="${MAX_PARALLEL:-4}"

mkdir -p "$PERF_DIR"

# Functies
measure_script() {
  local script="$1"
  local script_path="${FLEET_DIR}/scripts/${script}"
  local out_file="${PERF_DIR}/perf_${script}.txt"
  
  [ -f "$script_path" ] || return 0
  
  # Syntax check eerst
  if ! bash -n "$script_path" 2>/dev/null; then
    echo "${script}|0|syntax_error" > "$out_file"
    return 0
  fi
  
  local start end elapsed
  start=$(date +%s%N)
  
  # Voer script uit met timeout
  if timeout 60 bash "$script_path" >/dev/null 2>&1; then
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))  # milliseconden
    echo "${script}|${elapsed}|ok" > "$out_file"
  else
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    echo "${script}|${elapsed}|fail" > "$out_file"
  fi
}

# Fase 1: Meet alle scripts
log "Fase 1: Meet runtime van alle scripts..."

results=()
for script in "${FLEET_DIR}"/scripts/*.sh; do
  [ -f "$script" ] || continue
  script_name=$(basename "$script")
  
  # Sla over het performance-monitor script zelf
  [ "$script_name" = "performance-monitor.sh" ] && continue
  
  log "  Meten: $script_name"
  
  # Parallel met max jobs
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
    sleep 0.2
  done
  
  measure_script "$script_name" &
done
wait

# Fase 2: Verzamel resultaten
log "Fase 2: Verzamel resultaten..."

# Lees resultaten van temp bestanden
perf_data="[]"
for f in "${PERF_DIR}"/perf_*.txt; do
  [ -f "$f" ] || continue
  while IFS='|' read -r script elapsed status; do
    [ -z "$script" ] && continue
    perf_data=$(echo "$perf_data" | jq -c --arg s "$script" --arg e "$elapsed" --arg st "$status" \
      '. + [{"script": $s, "runtime_ms": ($e | tonumber), "status": $st, "timestamp": now}]')
  done < "$f"
  rm -f "$f"
done

# Fase 3: Genereer rapport
log "Fase 3: Genereer rapport..."

# Sla history op
echo "$perf_data" > "$PERF_HISTORY"

# Vind traagste scripts
slowest=$(echo "$perf_data" | jq -r 'sort_by(-.runtime_ms) | .[0:10][] | "\(.script): \(.runtime_ms)ms (\(.status))"')

# Vind scripts boven threshold
alerts=$(echo "$perf_data" | jq -r --arg threshold "$ALERT_THRESHOLD" \
  '[.[] | select(.runtime_ms > ($threshold * 1000))] | length')

log "  Traagste scripts:"
echo "$slowest" | while IFS= read -r line; do
  log "    $line"
done

log "  Scripts boven threshold (${ALERT_THRESHOLD}s): $alerts"

# Fase 4: Telegram alert indien nodig
if [ "$alerts" -gt 0 ]; then
  slow_list=$(echo "$perf_data" | jq -r --arg threshold "$ALERT_THRESHOLD" \
    '[.[] | select(.runtime_ms > ($threshold * 1000))] | .[] | "  \(.script): \(.runtime_ms)ms"')
  
  send_telegram_message "⚠️ *Performance Alert*

${alerts} scripts overschrijden ${ALERT_THRESHOLD}s threshold:

${slow_list}

📋 Volledig log: $LOG_FILE" || true
fi

log "=== Performance Monitor complete ==="
