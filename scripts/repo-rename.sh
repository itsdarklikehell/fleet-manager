#!/usr/bin/env bash
# scripts/repo-rename.sh - Rename repos
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

OLD_NAME="${1:-}"
NEW_NAME="${2:-}"
if [ -z "$OLD_NAME" ] || [ -z "$NEW_NAME" ]; then
  echo "Usage: $0 <old-name> <new-name>"
  exit 1
fi

log "=== Repo Rename ==="
renamed=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  if [ "$repo" = "$OLD_NAME" ]; then
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    log "  $repo: rename naar $NEW_NAME..."
    maybe_mutate gh repo rename "$NEW_NAME" --repo "${org}/${repo}" --yes 2>/dev/null && ((renamed++)) || true
  fi
done
log "=== Repo Rename complete: $renamed repos hernoemd ==="
send_telegram_message "✏️ *Repo Rename*\n\n*Hernoemd:* $renamed repos ($OLD_NAME → $NEW_NAME)\n\n📋 Volledig log: $LOG_FILE" || true
