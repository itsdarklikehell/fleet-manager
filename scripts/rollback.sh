#!/usr/bin/env bash
# scripts/rollback.sh - Rollback mechanisme voor fleet mutaties
# Houdt de laatste N mutaties bij en kan ze ongedaan maken
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Fleet Rollback ==="

# Configuratie
ROLLBACK_LOG="${ROLLBACK_LOG:-$HOME/.github_fleet_rollback.log}"
ROLLBACK_MAX_ENTRIES="${ROLLBACK_MAX_ENTRIES:-100}"

# Functies
record_mutation() {
  local action="$1"
  local target="$2"
  local details="${3:-}"
  local timestamp
  timestamp=$(date -Iseconds)
  
  echo "$timestamp|$action|$target|$details" >> "$ROLLBACK_LOG"
  
  # Houd log beperkt
  if [ "$(wc -l < "$ROLLBACK_LOG")" -gt "$ROLLBACK_MAX_ENTRIES" ]; then
    tail -n "$ROLLBACK_MAX_ENTRIES" "$ROLLBACK_LOG" > "$ROLLBACK_LOG.tmp"
    mv "$ROLLBACK_LOG.tmp" "$ROLLBACK_LOG"
  fi
}

list_mutations() {
  local count="${1:-10}"
  log "Laatste $count mutaties:"
  tail -n "$count" "$ROLLBACK_LOG" 2>/dev/null || log "  (geen mutaties gevonden)"
}

rollback_last() {
  local count="${1:-1}"
  
  if [ ! -f "$ROLLBACK_LOG" ] || [ ! -s "$ROLLBACK_LOG" ]; then
    log "Geen mutaties om terug te draaien"
    return 1
  fi
  
  log "Draai laatste $count mutaties terug..."
  
  for i in $(seq 1 "$count"); do
    local line
    line=$(tail -n 1 "$ROLLBACK_LOG")
    [ -z "$line" ] && break
    
    local timestamp
    timestamp=$(echo "$line" | cut -d'|' -f1)
    local action
    action=$(echo "$line" | cut -d'|' -f2)
    local target
    target=$(echo "$line" | cut -d'|' -f3)
    local details
    details=$(echo "$line" | cut -d'|' -f4)
    
    log "  Terugdraaien: $action op $target ($timestamp)"
    
    case "$action" in
      "pr-merge")
        # PR terugdraaien naar open
        gh pr close "$target" --comment "🔄 Rolled back by fleet manager" 2>/dev/null || true
        ;;
      "pr-close")
        # PR heropenen
        gh pr reopen "$target" 2>/dev/null || true
        ;;
      "issue-close")
        # Issue heropenen
        gh issue reopen "$target" 2>/dev/null || true
        ;;
      "issue-comment")
        # Comment verwijderen (lastig, log alleen)
        log "    ⚠️ Comment verwijderen niet automatisch mogelijk: $target"
        ;;
      "label-add")
        # Label verwijderen
        label=$(echo "$details" | cut -d' ' -f1)
        gh issue edit "$target" --remove-label "$label" 2>/dev/null || true
        ;;
      "label-remove")
        # Label terug toevoegen
        label=$(echo "$details" | cut -d' ' -f1)
        gh issue edit "$target" --add-label "$label" 2>/dev/null || true
        ;;
      "assign")
        # Assignee verwijderen
        gh issue edit "$target" --remove-assignee "$details" 2>/dev/null || true
        ;;
      *)
        log "    ⚠️ Onbekende actie: $action — handmatig nodig"
        ;;
    esac
    
    # Verwijder de mutatie uit het log
    head -n -1 "$ROLLBACK_LOG" > "$ROLLBACK_LOG.tmp" 2>/dev/null || true
    mv "$ROLLBACK_LOG.tmp" "$ROLLBACK_LOG" 2>/dev/null || true
  done
  
  log "✅ Rollback voltooid"
}

show_stats() {
  if [ ! -f "$ROLLBACK_LOG" ]; then
    log "Geen rollback data"
    return
  fi
  
  local total
  total=$(wc -l < "$ROLLBACK_LOG")
  local pr_merges
  pr_merges=$(grep -c "pr-merge" "$ROLLBACK_LOG" 2>/dev/null || echo "0")
  local pr_closes
  pr_closes=$(grep -c "pr-close" "$ROLLBACK_LOG" 2>/dev/null || echo "0")
  local issue_closes
  issue_closes=$(grep -c "issue-close" "$ROLLBACK_LOG" 2>/dev/null || echo "0")
  local labels
  labels=$(grep -c "label-" "$ROLLBACK_LOG" 2>/dev/null || echo "0")
  
  log "Rollback statistieken:"
  log "  Totaal mutaties: $total"
  log "  PR merges: $pr_merges"
  log "  PR closes: $pr_closes"
  log "  Issue closes: $issue_closes"
  log "  Label wijzigingen: $labels"
}

# Hoofdlogica
case "${1:-list}" in
  "list")
    list_mutations "${2:-10}"
    ;;
  "rollback")
    rollback_last "${2:-1}"
    ;;
  "stats")
    show_stats
    ;;
  "record")
    # Handmatig mutatie registreren
    record_mutation "$2" "$3" "$4"
    log "Mutatie geregistreerd"
    ;;
  *)
    log "Gebruik: rollback.sh [list|rollback|stats|record]"
    exit 1
    ;;
esac
