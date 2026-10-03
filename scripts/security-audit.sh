#!/usr/bin/env bash
# scripts/security-audit.sh - Security audit
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Security Audit ==="
local certs=("192.168.178.51:443" "192.168.178.63:8006")
for cert in "${certs[@]}"; do
  local expiry=$(echo | openssl s_client -connect "$cert" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [ -n "$expiry" ]; then
    local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
    local now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    if [ "$days_left" -lt 30 ]; then
      log "  ⚠️ SSL cert $cert: $days_left dagen tot verloop"
    else
      log "  ✓ SSL cert $cert: $days_left dagen"
    fi
  fi
done
local open_ports=$(nmap -p 22,80,443,8080 192.168.178.1 2>/dev/null | grep "open" | wc -l)
log "  Gateway open ports: $open_ports"
local failed_ssh=$(journalctl -u ssh --since "1 day ago" --no-pager 2>/dev/null | grep -c "Failed password" || echo "0")
log "  Failed SSH (24h): $failed_ssh"
log "=== Security audit complete ==="
send_telegram_message "🔒 *Security Audit*\n\n📋 Volledig log: $LOG_FILE" || true
