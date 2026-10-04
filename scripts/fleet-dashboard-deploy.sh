#!/usr/bin/env bash

# Logging
LOG_FILE="${LOG_FILE:-/tmp/fleet-manager.log}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
# scripts/fleet-dashboard-deploy.sh - Fleet dashboard deployen als service
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Fleet Dashboard Deploy ==="

DASHBOARD_DIR="${DASHBOARD_DIR:-$HOME/.github_fleet_dashboard}"
DASHBOARD_PORT="${DASHBOARD_PORT:-9120}"
DASHBOARD_SERVICE="fleet-dashboard.service"

# Genereer dashboard
bash "$(dirname "$0")/fleet-dashboard.sh"

# Maak systemd service aan
SERVICE_FILE="$HOME/.config/systemd/user/$DASHBOARD_SERVICE"
mkdir -p "$(dirname "$SERVICE_FILE")"

cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=Fleet Dashboard
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server $DASHBOARD_PORT --directory $DASHBOARD_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE

# Enable en start
systemctl --user daemon-reload
systemctl --user enable "$DASHBOARD_SERVICE" 2>/dev/null || true
systemctl --user restart "$DASHBOARD_SERVICE" 2>/dev/null || true

# Check of het draait
sleep 2
if systemctl --user is-active --quiet "$DASHBOARD_SERVICE" 2>/dev/null; then
  echo "  ✅ Dashboard actief op http://localhost:$DASHBOARD_PORT"
else
  echo "  ⚠️ Dashboard service niet actief — start handmatig:"
  echo "    systemctl --user start $DASHBOARD_SERVICE"
fi

echo ""
echo "✅ Fleet dashboard deploy klaar"
