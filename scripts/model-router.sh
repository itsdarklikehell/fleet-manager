#!/usr/bin/env bash
# scripts/model-router.sh - Model routing per repo
# Kiest het juiste model per taaltype en complexiteit
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Model Router ==="

# Configuratie
MODEL_ROUTER_ENABLED="${MODEL_ROUTER_ENABLED:-yes}"
MODEL_DEFAULT="${MODEL_DEFAULT:-meituan/longcat-2.5-preview:free}"
MODEL_SHELL="${MODEL_SHELL:-meituan/longcat-2.5-preview:free}"
MODEL_PYTHON="${MODEL_PYTHON:-meituan/longcat-2.5-preview:free}"
MODEL_SECURITY="${MODEL_SECURITY:-meituan/longcat-2.5-preview:free}"
MODEL_COMPLEX="${MODEL_COMPLEX:-meituan/longcat-2.5-preview:free}"

# Functies
detect_language() {
  local file="$1"
  case "$file" in
    *.sh|*.bash) echo "shell" ;;
    *.py) echo "python" ;;
    *.js|*.ts) echo "javascript" ;;
    *.go) echo "go" ;;
    *.rs) echo "rust" ;;
    *.md) echo "markdown" ;;
    *) echo "other" ;;
  esac
}

detect_complexity() {
  local file="$1"
  local lines
  lines=$(wc -l < "$file" 2>/dev/null || echo "0")
  
  if [ "$lines" -gt 500 ]; then
    echo "high"
  elif [ "$lines" -gt 200 ]; then
    echo "medium"
  else
    echo "low"
  fi
}

route_model() {
  local file="$1"
  local task="${2:-general}"
  
  local language complexity
  language=$(detect_language "$file")
  complexity=$(detect_complexity "$file")
  
  # Security altijd hoog model
  if [ "$task" = "security" ]; then
    echo "$MODEL_SECURITY"
    return
  fi
  
  # Complex code → complex model
  if [ "$complexity" = "high" ]; then
    echo "$MODEL_COMPLEX"
    return
  fi
  
  # Taal-specifiek model
  case "$language" in
    shell) echo "$MODEL_SHELL" ;;
    python) echo "$MODEL_PYTHON" ;;
    *) echo "$MODEL_DEFAULT" ;;
  esac
}

# Hoofdlogica
if [ "$MODEL_ROUTER_ENABLED" != "yes" ]; then
  log "Model router uitgeschakeld - using default: $MODEL_DEFAULT"
  echo "$MODEL_DEFAULT"
  exit 0
fi

# Als er een file is opgegeven, route dan
if [ -n "${1:-}" ]; then
  model=$(route_model "$1" "${2:-general}")
  log "Routed $1 → $model"
  echo "$model"
else
  log "Geen file opgegeven - using default: $MODEL_DEFAULT"
  echo "$MODEL_DEFAULT"
fi

log "=== Model Router klaar ==="
