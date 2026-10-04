#!/usr/bin/env bash
# OpenTelemetry helper voor fleet-manager scripts

OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4317}"
OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-fleet-manager}"

otel_start_span() {
  local span_name="$1"
  local trace_id
  trace_id=$(python3 -c "import uuid; print(uuid.uuid4().hex)")
  local span_id
  span_id=$(python3 -c "import uuid; print(uuid.uuid4().hex[:16])")
  
  echo "{\"trace_id\":\"$trace_id\",\"span_id\":\"$span_id\",\"name\":\"$span_name\",\"start\":\"$(date -Iseconds)\"}" >> "$TRACE_FILE"
  echo "$trace_id $span_id"
}

otel_end_span() {
  local trace_id="$1"
  local span_id="$2"
  echo "{\"trace_id\":\"$trace_id\",\"span_id\":\"$span_id\",\"end\":\"$(date -Iseconds)\"}" >> "$TRACE_FILE"
}

otel_add_event() {
  local trace_id="$1"
  local span_id="$2"
  local event="$3"
  echo "{\"trace_id\":\"$trace_id\",\"span_id\":\"$span_id\",\"event\":\"$event\",\"timestamp\":\"$(date -Iseconds)\"}" >> "$TRACE_FILE"
}

otel_record_metric() {
  local metric_name="$1"
  local metric_value="$2"
  local metric_type="${3:-gauge}"
  echo "{\"name\":\"$metric_name\",\"value\":$metric_value,\"type\":\"$metric_type\",\"timestamp\":\"$(date -Iseconds)\"}" >> "$METRICS_FILE"
}
