#!/usr/bin/env bash
# scripts/service-check.sh - Service monitoring
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Service Check ==="
declare -A services=(
  ["Heimdall"]="http://192.168.178.51:7990"
  ["Jellyfin"]="http://192.168.178.51:8096"
  ["Pi-hole"]="http://192.168.178.36/admin"
  ["OpenClaw"]="http://192.168.178.62:18800"
  ["Hermes"]="http://192.168.178.94:9119"
  ["PVE"]="https://192.168.178.63:8006"
)
for name in "${!services[@]}"; do
  local url="${services[$name]}"
  local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
    log "  ✓ $name: $status"
  else
    log "  ✗ $name: $status"
  fi
done
local dns_status=$(dig +short @192.168.178.36 google.com 2>/dev/null | head -1)
if [ -n "$dns_status" ]; then log "  ✓ DNS: $dns_status"; else log "  ✗ DNS: geen antwoord"; fi
log "=== Service check complete ==="
send_telegram_message "🔌 *Service Check*\n\n📋 Volledig log: $LOG_FILE" || true
