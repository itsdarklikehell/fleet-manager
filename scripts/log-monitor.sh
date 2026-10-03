#!/usr/bin/env bash
# scripts/log-monitor.sh - Log monitoring
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Log Monitor ==="
hermes_errors=$(grep -c "ERROR\|CRITICAL" ~/.hermes/logs/*.log 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
log "  Hermes errors: $hermes_errors"
sys_errors=$(journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | wc -l)
log "  System errors (1h): $sys_errors"
docker_errors=$(docker logs --since 1h $(docker ps -q 2>/dev/null) 2>&1 | grep -ci "error\|fatal" || echo "0")
log "  Docker errors (1h): $docker_errors"
if [ "$hermes_errors" -gt 10 ]; then log "  ⚠️ Veel Hermes errors: $hermes_errors"; fi
if [ "$sys_errors" -gt 50 ]; then log "  ⚠️ Veel system errors: $sys_errors"; fi
log "=== Log monitor complete ==="
send_telegram_message "📋 *Log Monitor*\n\n*Hermes errors:* $hermes_errors\n*System errors:* $sys_errors\n*Docker errors:* $docker_errors\n\n📋 Volledig log: $LOG_FILE" || true
