#!/usr/bin/env bash
# scripts/setup-prometheus-metrics.sh - Prometheus metrics toevoegen
# Voegt Prometheus-compatible metrics toe aan de fleet manager
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Prometheus Metrics ==="

# Configuratie
METRICS_DIR="${METRICS_DIR:-$HOME/.github_fleet_metrics}"
mkdir -p "$METRICS_DIR"

# Functies
generate_metrics() {
  local metrics_file="$METRICS_DIR/fleet-metrics.prom"
  
  cat > "$metrics_file" << 'METRICS'
# Fleet Manager Metrics
# Prometheus-compatible metrics

# HELP fleet_scripts_total Total number of scripts
# TYPE fleet_scripts_total gauge
fleet_scripts_total $(ls scripts/*.sh 2>/dev/null | wc -l)

# HELP fleet_cron_jobs_total Total number of cron jobs
# TYPE fleet_cron_jobs_total gauge
fleet_cron_jobs_total $(crontab -l 2>/dev/null | grep -c 'github_fleet_wrapper' || echo 0)

# HELP fleet_repos_total Total number of repositories
# TYPE fleet_repos_total gauge
fleet_repos_total $(gh repo list --limit 1000 --json nameWithOwner --jq 'length' 2>/dev/null || echo 0)

# HELP fleet_api_rate_limit_remaining GitHub API rate limit remaining
# TYPE fleet_api_rate_limit_remaining gauge
fleet_api_rate_limit_remaining $(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo 0)

# HELP fleet_api_rate_limit_total GitHub API rate limit total
# TYPE fleet_api_rate_limit_total gauge
fleet_api_rate_limit_total $(gh api rate_limit --jq '.resources.core.limit' 2>/dev/null || echo 5000)

# HELP fleet_health_check_last_run Last health check timestamp
# TYPE fleet_health_check_last_run gauge
fleet_health_check_last_run $(date +%s)

# HELP fleet_errors_total Total number of errors
# TYPE fleet_errors_total counter
fleet_errors_total $(grep -c 'ERROR\|FAIL' ~/.github_fleet_manager.log 2>/dev/null || echo 0)

# HELP fleet_warnings_total Total number of warnings
# TYPE fleet_warnings_total counter
fleet_warnings_total $(grep -c '⚠️' ~/.github_fleet_manager.log 2>/dev/null || echo 0)
METRICS
  
  echo "  ✅ Metrics gegenereerd: $metrics_file"
}

setup_metrics_endpoint() {
  local endpoint_dir="$METRICS_DIR/endpoint"
  mkdir -p "$endpoint_dir"
  
  # Maak eenvoudige HTTP server voor metrics
  cat > "$endpoint_dir/server.py" << 'PYTHON'
#!/usr/bin/env python3
import http.server
import os
import subprocess

METRICS_FILE = os.path.expanduser("~/.github_fleet_metrics/fleet-metrics.prom")

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            try:
                with open(METRICS_FILE, 'r') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(content.encode())
            except FileNotFoundError:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', 9122), MetricsHandler)
    print("Metrics endpoint actief op poort 9122")
    server.serve_forever()
PYTHON
  
  chmod +x "$endpoint_dir/server.py"
  echo "  ✅ Metrics endpoint ingesteld"
}

# Hoofdlogica
generate_metrics
setup_metrics_endpoint

echo ""
echo "✅ Prometheus metrics setup klaar"
