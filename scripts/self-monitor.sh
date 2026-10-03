#!/usr/bin/env bash
# scripts/self-monitor.sh - Self monitoring voor fleet manager
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Self Monitor ==="
script_size=$(wc -c < "$0" 2>/dev/null || echo "0")
script_lines=$(wc -l < "$0" 2>/dev/null || echo "0")
log "  Script grote: $script_size bytes, $script_lines regels"
last_run=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
now=$(date +%s)
last_run_ago=$(( (now - last_run) / 60 ))
log "  Laatste run: $last_run_ago minuten geleden"
cron_count=$(crontab -l 2>/dev/null | grep -c "github_fleet" || echo "0")
log "  Cron jobs: $cron_count"
log_size=$(du -sh "$LOG_FILE" 2>/dev/null | cut -f1 || echo "unknown")
log "  Log bestand: $log_size"
if [ -n "$TELEGRAM_TOKEN" ]; then log "  Telegram: ✓ geconfigureerd"; else log "  Telegram: ✗ niet geconfigureerd"; fi
if gh auth status &>/dev/null; then log "  GitHub: ✓ geauthenticeerd"; else log "  GitHub: ✗ niet geauthenticeerd"; fi
if [ "$last_run_ago" -gt 120 ]; then log "  ⚠️ Laatste run was $last_run_ago minuten geleden"; fi
if [ "$script_size" -gt 1000000 ]; then log "  ⚠️ Script is groot: $script_size bytes"; fi
log "=== Self Monitor complete ==="
send_telegram_message "📊 *Self Monitor*\n\n*Script:* $script_lines regels\n*Cron jobs:* $cron_count\n*Log:* $log_size\n\n📋 Volledig log: $LOG_FILE" || true
