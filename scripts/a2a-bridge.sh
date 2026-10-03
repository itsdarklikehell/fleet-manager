#!/usr/bin/env bash
# scripts/a2a-bridge.sh - A2A integration bridge
# Queryt A2A agents voor repo-gebonden taken
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== A2A Bridge ==="

# Configuratie
A2A_ENABLED="${A2A_ENABLED:-yes}"
A2A_TIMEOUT="${A2A_TIMEOUT:-30}"
A2A_DEFAULT_AGENT="${A2A_DEFAULT_AGENT:-data}"

# Functies
query_a2a_agent() {
  local agent="$1"
  local query="$2"
  local repo="${3:-}"
  
  log "Querying A2A agent '$agent' for repo '$repo'..."
  
  # Check of A2A agent beschikbaar is
  if ! command -v a2a &>/dev/null; then
    log "  ⚠️ A2A CLI niet beschikbaar - skipping"
    return 1
  fi
  
  # Query de agent
  local response
  response=$(a2a call "$agent" "$query" --timeout "$A2A_TIMEOUT" 2>/dev/null || echo "")
  
  if [ -n "$response" ]; then
    log "  ✅ Response ontvangen van $agent"
    echo "$response"
  else
    log "  ❌ Geen response van $agent"
    return 1
  fi
}

query_repo_expert() {
  local repo="$1"
  local task="$2"
  
  # Bepaal welke agent het beste bij de repo past
  local agent="$A2A_DEFAULT_AGENT"
  
  case "$repo" in
    *pwnagotchi*) agent="pwnagotchi-expert" ;;
    *retropie*) agent="retropie-expert" ;;
    *hermes*) agent="hermes-expert" ;;
    *glados*) agent="glados-expert" ;;
  esac
  
  local query="Analyze repository '$repo' for task: $task. Provide recommendations."
  query_a2a_agent "$agent" "$query" "$repo"
}

# Hoofdlogica
if [ "$A2A_ENABLED" != "yes" ]; then
  log "A2A bridge uitgeschakeld"
  exit 0
fi

# Als er een repo en task zijn opgegeven, query dan
if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
  query_repo_expert "$1" "$2"
else
  log "Geen repo/task opgegeven - skipping"
fi

log "=== A2A Bridge klaar ==="
