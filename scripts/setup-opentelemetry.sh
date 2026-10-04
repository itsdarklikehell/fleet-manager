#!/usr/bin/env bash
# scripts/setup-opentelemetry.sh - OpenTelemetry integratie
# Vervangt custom distributed tracing door OpenTelemetry
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup OpenTelemetry ==="

# Configuratie
OTEL_DIR="lib/opentelemetry"
mkdir -p "$OTEL_DIR"

# Functies
create_otel_config() {
  local otel_file="$OTEL_DIR/otel-config.yml"
  
  cat > "$otel_file" << 'OTEL'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024

exporters:
  prometheus:
    endpoint: "0.0.0.0:8888"
  logging:
    loglevel: debug

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, logging]
OTEL
  
  echo "  ✅ OpenTelemetry config gemaakt"
}

create_otel_helper() {
  local otel_helper="$OTEL_DIR/otel-helper.sh"
  
  cat > "$otel_helper" << 'OTELHELPER'
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
OTELHELPER
  
  chmod +x "$otel_helper"
  echo "  ✅ OpenTelemetry helper gemaakt"
}

create_otel_collector_service() {
  local service_file="$HOME/.config/systemuser/fleet-otel-collector.service"
  mkdir -p "$(dirname "$service_file")"
  
  cat > "$service_file" << SERVICE
[Unit]
Description=Fleet OpenTelemetry Collector
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/docker run --rm -p 4317:4317 -p 4318:4318 -p 8888:8888 \
  -v $(pwd)/lib/opentelemetry/otel-config.yml:/etc/otel-collector-config.yml \
  otel/opentelemetry-collector:latest \
  --config=/etc/otel-collector-config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE
  
  echo "  ✅ OpenTelemetry collector service gemaakt"
}

# Hoofdlogica
create_otel_config
create_otel_helper
create_otel_collector_service

echo ""
echo "✅ OpenTelemetry setup klaar"
