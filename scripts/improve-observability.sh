#!/usr/bin/env bash
# scripts/improve-observability.sh - Observability verbeteren
# Voegt structured logging, distributed tracing en metrics collection toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Improve Observability ==="

# Configuratie
OBS_DIR="lib/observability"
mkdir -p "$OBS_DIR"

# Functies
setup_structured_logging() {
  local logging="$OBS_DIR/structured-logging.sh"
  
  cat > "$logging" << 'LOGGING'
#!/usr/bin/env bash
# Structured logging helper voor fleet-manager scripts

LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FORMAT="${LOG_FORMAT:-json}"  # json, text

log_structured() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date -Iseconds)
  
  case "$LOG_FORMAT" in
    json)
      echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\"}" >> "$LOG_FILE"
      ;;
    text)
      echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
      ;;
  esac
}

log_debug() { [ "$LOG_LEVEL" = "DEBUG" ] && log_structured "DEBUG" "$1" || true; }
log_info() { log_structured "INFO" "$1"; }
log_warn() { log_structured "WARN" "$1"; }
log_error() { log_structured "ERROR" "$1"; }
LOGGING
  
  chmod +x "$logging"
  echo "  ✅ Structured logging ingesteld"
}

setup_distributed_tracing() {
  local tracing="$OBS_DIR/distributed-tracing.sh"
  
  cat > "$tracing" << 'TRACING'
#!/usr/bin/env bash
# Distributed tracing helper voor fleet-manager scripts

TRACE_ID="${TRACE_ID:-$(uuidgen 2>/dev/null || date +%s%N)}"
SPAN_ID="${SPAN_ID:-0}"

trace_start_span() {
  local span_name="$1"
  SPAN_ID=$((SPAN_ID + 1))
  echo "{\"trace_id\":\"$TRACE_ID\",\"span_id\":\"$SPAN_ID\",\"name\":\"$span_name\",\"start\":\"$(date -Iseconds)\"}" >> "$TRACE_FILE"
}

trace_end_span() {
  echo "{\"trace_id\":\"$TRACE_ID\",\"span_id\":\"$SPAN_ID\",\"end\":\"$(date -Iseconds)\"}" >> "$TRACE_FILE"
}

trace_add_event() {
  local event="$1"
  echo "{\"trace_id\":\"$TRACE_ID\",\"span_id\":\"$SPAN_ID\",\"event\":\"$event\",\"timestamp\":\"$(date -Iseconds)\"}" >> "$TRACE_FILE"
}
TRACING
  
  chmod +x "$tracing"
  echo "  ✅ Distributed tracing ingesteld"
}

setup_metrics_collection() {
  local metrics="$OBS_DIR/metrics-collection.sh"
  
  cat > "$metrics" << 'METRICS'
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
METRICS
  
  chmod +x "$metrics"
  echo "  ✅ Metrics collection ingesteld"
}

# Hoofdlogica
setup_structured_logging
setup_distributed_tracing
setup_metrics_collection

echo ""
echo "✅ Observability verbetering klaar"
