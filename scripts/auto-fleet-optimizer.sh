#!/usr/bin/env bash
# scripts/auto-fleet-optimizer.sh - Automatische fleet optimalisatie
# Optimaliseert scripts, cron jobs en configuratie
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Optimizer ==="

# Configuratie
OPTIMIZER_ENABLED="${OPTIMIZER_ENABLED:-no}"

if [ "$OPTIMIZER_ENABLED" != "yes" ]; then
  echo "Fleet optimizer is uitgeschakeld (OPTIMIZER_ENABLED=$OPTIMIZER_ENABLED)"
  exit 0
fi

# Functies
optimize_scripts() {
  echo "Scripts optimaliseren..."
  
  local optimized=0
  for script in scripts/*.sh; do
    [ -f "$script" ] || continue
    
    local modified=false
    
    # Voeg set -euo pipefail toe als het mist
    if ! grep -q 'set -euo pipefail' "$script"; then
      local content
      content=$(cat "$script")
      local lines
      lines=$(echo "$content" | head -1)
      echo "$lines" > "$script.tmp"
      echo "set -euo pipefail" >> "$script.tmp"
      echo "$content" | tail -n +2 >> "$script.tmp"
      mv "$script.tmp" "$script"
      modified=true
    fi
    
    # Voeg logging toe als het mist
    if ! grep -q 'log()' "$script" && ! grep -q 'log ' "$script"; then
      echo "" >> "$script"
      echo "# Logging" >> "$script"
      echo "log() {" >> "$script"
      echo '  local msg="$*"; local ts' >> "$script"
      echo '  ts=$(date "+%Y-%m-%d %H:%M:%S")' >> "$script"
      echo '  echo "[$ts] $msg" >> "$LOG_FILE" 2>/dev/null || echo "[$ts] $msg" >&2' >> "$script"
      echo "}" >> "$script"
      modified=true
    fi
    
    if [ "$modified" = true ]; then
      chmod +x "$script"
      optimized=$((optimized + 1))
    fi
  done
  
  echo "  ✅ $optimized scripts geoptimaliseerd"
}

optimize_cron_jobs() {
  echo "Cron jobs optimaliseren..."
  
  # Verwijder duplicate cron jobs
  local temp_cron
  temp_cron=$(mktemp)
  crontab -l 2>/dev/null | sort -u > "$temp_cron"
  crontab "$temp_cron"
  rm -f "$temp_cron"
  
  echo "  ✅ Cron jobs gedupliceerd verwijderd"
}

optimize_config() {
  echo "Configuratie optimaliseren..."
  
  # Zorg ervoor dat belangrijke environment variables gezet zijn
  if [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ]; then
    echo "  ⚠️ GITHUB_TOKEN/GH_TOKEN niet gezet"
  fi
  
  if [ -z "${TELEGRAM_TOKEN:-}" ]; then
    echo "  ⚠️ TELEGRAM_TOKEN niet gezet"
  fi
  
  echo "  ✅ Configuratie gecontroleerd"
}

# Hoofdlogica
optimize_scripts
optimize_cron_jobs
optimize_config

echo ""
echo "✅ Auto fleet optimizer klaar"
