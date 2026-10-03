#!/usr/bin/env bash
# scripts/network-scan.sh - Netwerk scanning
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Network Scan ==="
local scan_file="$LOG_FILE.network-scan.json"
local prev_file="$LOG_FILE.network-scan.prev"

nmap -sn 192.168.178.0/24 2>/dev/null | grep "Nmap scan report" | awk '{print $NF}' | tr -d '()' | sort > "$scan_file"

if [ -f "$prev_file" ]; then
  local new_devices=$(comm -13 "$prev_file" "$scan_file" 2>/dev/null || echo "")
  local removed_devices=$(comm -23 "$prev_file" "$scan_file" 2>/dev/null || echo "")
  if [ -n "$new_devices" ]; then log "  ⚠️ Nieuwe devices: $new_devices"; fi
  if [ -n "$removed_devices" ]; then log "  ⚠️ Verwijderde devices: $removed_devices"; fi
  if [ -z "$new_devices" ] && [ -z "$removed_devices" ]; then log "  ✓ Geen wijzigingen"; fi
else
  log "  Eerste scan - baseline opgeslagen"
fi

cp "$scan_file" "$prev_file"
log "  Totaal devices: $(wc -l < "$scan_file")"
log "=== Network scan complete ==="
send_telegram_message "🌐 *Network Scan*\n\n📋 Volledig log: $LOG_FILE" || true
