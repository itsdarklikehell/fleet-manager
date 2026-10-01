#!/usr/bin/env bash
# scripts/label-sync.sh - Label synchronisatie
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Label Sync ==="
labels_synced=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  standard_labels=("bug" "enhancement" "documentation" "question" "good first issue" "help wanted" "wontfix" "duplicate" "invalid")
  for label in "${standard_labels[@]}"; do
    gh label create "$label" --repo "${org}/${repo}" --color "ededed" 2>/dev/null && ((labels_synced++)) || true
  done
done
log "=== Label Sync complete: $labels_synced labels gesynchroniseerd ==="
send_telegram_message "🏷️ *Label Sync*\n\n*Gesynchroniseerd:* $labels_synced labels\n\n📋 Volledig log: $LOG_FILE" || true
