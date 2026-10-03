#!/usr/bin/env bash
# scripts/rd-team-coordinator.sh - R&D Team Coordinator
# Coördineert R&D teams voor elke repo
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== R&D Team Coordinator ==="

# Fase 1: Identificeer repos die nog niet zijn aangepakt
log "Fase 1: Repos identificeren..."
local repos_to_process=()
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  # Check of repo al is aangepakt (heeft .github/workflows/gource.yml)
  if [ ! -f "$repo_dir/.github/workflows/gource.yml" ]; then
    repos_to_process+=("$repo")
    log "  → $repo: nog niet aangepakt"
  else
    log "  ✓ $repo: al aangepakt"
  fi
done

log "Totaal repos te verwerken: ${#repos_to_process[@]}"

# Fase 2: Verdeel repos over R&D teams (max 5 repos per team)
log "Fase 2: R&D teams indelen..."
local team_size=5
local team_count=$(( (${#repos_to_process[@]} + team_size - 1) / team_size ))
log "  Teams nodig: $team_count"

# Fase 3: Genereer team configuratie
log "Fase 3: Team configuratie genereren..."
local config_file="$HOME/.hermes/rd-team-config.json"
echo "{" > "$config_file"
echo "  \"teams\": [" >> "$config_file"
for ((i=0; i<team_count; i++)); do
  local start=$((i * team_size))
  local end=$((start + team_size - 1))
  if [ $end -ge ${#repos_to_process[@]} ]; then
    end=$((${#repos_to_process[@]} - 1))
  fi
  echo "    {" >> "$config_file"
  echo "      \"team_id\": $i," >> "$config_file"
  echo "      \"repos\": [" >> "$config_file"
  for ((j=start; j<=end; j++)); do
    if [ $j -gt $start ]; then echo "        ," >> "$config_file"; fi
    echo "        \"${repos_to_process[$j]}\"" >> "$config_file"
  done
  echo "      ]" >> "$config_file"
  echo "    }" >> "$config_file"
  if [ $i -lt $((team_count - 1)) ]; then echo "    ," >> "$config_file"; fi
done
echo "  ]" >> "$config_file"
echo "}" >> "$config_file"

log "  Team configuratie opgeslagen in: $config_file"

# Fase 4: Start R&D teams (via delegate_task)
log "Fase 4: R&D teams starten..."
for ((i=0; i<team_count; i++)); do
  local start=$((i * team_size))
  local end=$((start + team_size - 1))
  if [ $end -ge ${#repos_to_process[@]} ]; then
    end=$((${#repos_to_process[@]} - 1))
  fi
  local repos=""
  for ((j=start; j<=end; j++)); do
    if [ -n "$repos" ]; then repos="$repos, "; fi
    repos="$repos${repos_to_process[$j]}"
  done
  log "  Team $i: $repos"
done

log "=== R&D Team Coordinator complete ==="
send_telegram_message "🤖 *R&D Team Coordinator*\n\n*Repos te verwerken:* ${#repos_to_process[@]}\n*Teams:* $team_count\n\n📋 Volledig log: $LOG_FILE" || true
