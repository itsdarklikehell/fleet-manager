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
