#!/usr/bin/env bash
# scripts/cron-audit.sh - Audit en fix cron jobs
# Verwijdert dead references en rapporteert scripts die nooit draaien
set -euo pipefail

# Logging
log() {
  local msg="$*"; local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] $msg" >> "$LOG_FILE" 2>/dev/null || echo "[$ts] $msg" >&2
}

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Cron Audit ==="

# Functies
audit_cron_jobs() {
  local dead_refs=()
  local active_scripts=()
  
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    
    # Extract script name from wrapper call (portable, geen -oP)
    local script_name
    script_name=$(echo "$line" | sed -n 's/.*github_fleet_wrapper\.sh \([^ ]*\).*/\1/p')
    
    if [ -n "$script_name" ]; then
      local script_path="scripts/${script_name}.sh"
      if [ -f "$script_path" ]; then
        active_scripts+=("$script_name")
      else
        dead_refs+=("$line")
      fi
    fi
  done < <(crontab -l 2>/dev/null)
  
  echo "Actieve scripts: ${#active_scripts[@]}"
  echo "Dead references: ${#dead_refs[@]}"
  
  if [ ${#dead_refs[@]} -gt 0 ]; then
    echo ""
    echo "Dead references gevonden:"
    for ref in "${dead_refs[@]}"; do
      echo "  ❌ $ref"
    done
    
    # Verwijder dead references
    echo ""
    echo "Dead references verwijderen..."
    local temp_cron
    temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$temp_cron"
    
    for ref in "${dead_refs[@]}"; do
      local script_name
      script_name=$(echo "$ref" | sed -n 's/.*github_fleet_wrapper\.sh \([^ ]*\).*/\1/p')
      sed -i "/github_fleet_wrapper\.sh $script_name/d" "$temp_cron"
    done
    
    crontab "$temp_cron"
    rm -f "$temp_cron"
    echo "  ✅ Dead references verwijderd"
  fi
}

find_never_run_scripts() {
  local active_scripts=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    local script_name
    script_name=$(echo "$line" | sed -n 's/.*github_fleet_wrapper\.sh \([^ ]*\).*/\1/p')
    [ -n "$script_name" ] && active_scripts+=("$script_name")
  done < <(crontab -l 2>/dev/null)
  
  local never_run=()
  for script in scripts/*.sh; do
    [ -f "$script" ] || continue
    local name
    name=$(basename "$script" .sh)
    local found=false
    for active in "${active_scripts[@]}"; do
      if [ "$active" = "$name" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      never_run+=("$name")
    fi
  done
  
  echo ""
  echo "Scripts die nooit draaien: ${#never_run[@]}"
  for script in "${never_run[@]}"; do
    echo "  ⚠️ $script"
  done
}

# Hoofdlogica
audit_cron_jobs
find_never_run_scripts

echo ""
echo "✅ Cron audit klaar"
