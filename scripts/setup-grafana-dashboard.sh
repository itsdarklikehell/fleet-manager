#!/usr/bin/env bash
# scripts/setup-grafana-dashboard.sh - Grafana dashboard opzetten
# Voegt een Grafana dashboard toe voor real-time fleet visualisatie
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Grafana Dashboard ==="

# Configuratie
GRAFANA_DIR="lib/grafana"
mkdir -p "$GRAFANA_DIR/dashboards" "$GRAFANA_DIR/datasources"

# Functies
create_datasource_config() {
  local datasource_file="$GRAFANA_DIR/datasources/prometheus.yml"
  
  cat > "$datasource_file" << 'DATASOURCE'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
DATASOURCE
  
  echo "  ✅ Datasource config gemaakt"
}

create_dashboard_config() {
  local dashboard_file="$GRAFANA_DIR/dashboards/fleet-dashboard.json"
  
  cat > "$dashboard_file" << 'DASHBOARD'
{
  "dashboard": {
    "id": null,
    "title": "Fleet Manager Dashboard",
    "tags": ["fleet", "github", "automation"],
    "timezone": "browser",
    "schemaVersion": 36,
    "version": 1,
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "title": "Scripts",
        "type": "stat",
        "targets": [
          {
            "expr": "fleet_scripts_total",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Cron Jobs",
        "type": "stat",
        "targets": [
          {
            "expr": "fleet_cron_jobs_total",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0}
      },
      {
        "id": 3,
        "title": "API Rate Limit",
        "type": "gauge",
        "targets": [
          {
            "expr": "fleet_api_rate_limit_remaining / fleet_api_rate_limit_total * 100",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 50},
                {"color": "green", "value": 80}
              ]
            }
          }
        }
      },
      {
        "id": 4,
        "title": "Errors",
        "type": "stat",
        "targets": [
          {
            "expr": "fleet_errors_total",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 4, "w": 6, "x": 18, "y": 0}
      },
      {
        "id": 5,
        "title": "Script Performance",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(fleet_script_duration_seconds_sum[5m])",
            "refId": "A",
            "legendFormat": "Duration"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 4}
      },
      {
        "id": 6,
        "title": "API Calls",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(fleet_api_calls_total[5m])",
            "refId": "A",
            "legendFormat": "API Calls"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 12}
      }
    ]
  }
}
DASHBOARD
  
  echo "  ✅ Dashboard config gemaakt"
}

create_grafana_service() {
  local service_file="$HOME/.config/systemd/user/fleet-grafana.service"
  mkdir -p "$(dirname "$service_file")"
  
  cat > "$service_file" << SERVICE
[Unit]
Description=Fleet Grafana Dashboard
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/docker run --rm -p 3000:3000 \
  -v $(pwd)/lib/grafana/dashboards:/etc/grafana/dashboards \
  -v $(pwd)/lib/grafana/datasources:/etc/grafana/datasources \
  grafana/grafana:latest
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE
  
  echo "  ✅ Grafana service gemaakt"
}

# Hoofdlogica
create_datasource_config
create_dashboard_config
create_grafana_service

echo ""
echo "✅ Grafana dashboard setup klaar"
