#!/usr/bin/env bash
# scripts/system-health.sh - Systeem health check
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== System Health Check ==="
local load=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
log "  CPU load: $load"
local mem_total=$(free -m | awk '/^Mem:/{print $2}')
local mem_used=$(free -m | awk '/^Mem:/{print $3}')
local mem_pct=$((mem_used * 100 / mem_total))
log "  Memory: ${mem_used}MB / ${mem_total}MB (${mem_pct}%)"
local disk_usage=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
log "  Disk: ${disk_usage}%"
local docker_running=$(docker ps -q 2>/dev/null | wc -l)
local docker_total=$(docker ps -aq 2>/dev/null | wc -l)
log "  Docker: $docker_running / $docker_total containers running"
local failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
log "  Failed systemd units: $failed"
if [ "$mem_pct" -gt 90 ]; then log "  ⚠️ Hoog memory gebruik: ${mem_pct}%"; fi
if [ "$disk_usage" -gt 90 ]; then log "  ⚠️ Volle disk: ${disk_usage}%"; fi
if [ "$failed" -gt 0 ]; then log "  ⚠️ $failed failed systemd units"; fi
log "=== System health check complete ==="
send_telegram_message "🖥️ *System Health*\n\n📋 Volledig log: $LOG_FILE" || true
