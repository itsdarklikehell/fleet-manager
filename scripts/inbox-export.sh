#!/usr/bin/env bash
# scripts/inbox-export.sh - Export inbox data
# Exporteert inbox data naar JSON en CSV
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Export ==="

# shellcheck disable=SC2206
EXPORT_REPOS=( ${EXPORT_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')
EXPORT_DIR="${EXPORT_DIR:-$HOME/.openclaw/workspace/projects/fleet-manager/exports}"
mkdir -p "$EXPORT_DIR"

JSON_FILE="$EXPORT_DIR/inbox-export-$TODAY.json"
CSV_FILE="$EXPORT_DIR/inbox-export-$TODAY.csv"

# Fase 1: Export issues
log "Fase 1: Export issues..."

echo "[" > "$JSON_FILE"
first=true

for kr in "${EXPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  issues=$(gh issue list --repo "$kr" --state open --limit 100 --json title,url,createdAt,labels,assignees 2>/dev/null || echo "[]")
  
  if [ "$first" = true ]; then
    first=false
  else
    echo "," >> "$JSON_FILE"
  fi
  
  echo "{\"repo\": \"$kr\", \"issues\": $issues}" >> "$JSON_FILE"
  
  log "  $kr: issues geëxporteerd"
done

echo "]" >> "$JSON_FILE"

# Fase 2: Export PRs
log "Fase 2: Export PRs..."

for kr in "${EXPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  prs=$(gh pr list --repo "$kr" --state open --limit 100 --json title,url,createdAt,author,reviewRequests 2>/dev/null || echo "[]")
  
  log "  $kr: PRs geëxporteerd"
done

# Fase 3: Export CSV
log "Fase 3: Export CSV..."

echo "repo,type,title,url,created_at,labels,assignees" > "$CSV_FILE"

for kr in "${EXPORT_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  # Issues naar CSV
  gh issue list --repo "$kr" --state open --limit 100 --json title,url,createdAt,labels,assignees --jq '.[] | [.title, .url, .createdAt, (.labels | map(.name) | join(";")), (.assignees | map(.login) | join(";"))] | @csv' 2>/dev/null | while IFS= read -r line; do
    echo "\"$kr\",\"issue\",$line" >> "$CSV_FILE"
  done
  
  # PRs naar CSV
  gh pr list --repo "$kr" --state open --limit 100 --json title,url,createdAt,author --jq '.[] | [.title, .url, .createdAt, .author.login] | @csv' 2>/dev/null | while IFS= read -r line; do
    echo "\"$kr\",\"pr\",$line" >> "$CSV_FILE"
  done
  
  log "  $kr: CSV geëxporteerd"
done

# Fase 4: Verstuur rapport
log "Fase 4: Verstuur rapport..."

issue_count=$(grep -c '"type":"issue"' "$CSV_FILE" 2>/dev/null || echo "0")
pr_count=$(grep -c '"type":"pr"' "$CSV_FILE" 2>/dev/null || echo "0")

send_telegram_message "📤 *Inbox Export* — $TODAY

📁 *Bestanden:*
• JSON: $JSON_FILE
• CSV: $CSV_FILE

📊 *Data:*
• Issues: $issue_count
• PRs: $pr_count

📋 Volledig log: $LOG_FILE" || true

log "=== Inbox Export complete ==="
