#!/usr/bin/env bash
# scripts/repo-transfer.sh - Transfer repos naar andere owner
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

NEW_OWNER="${1:-}"
if [ -z "$NEW_OWNER" ]; then
  echo "Usage: $0 <new-owner> [repo1 repo2 ...]"
  exit 1
fi
shift
REPOS_TO_TRANSFER=("$@")

log "=== Repo Transfer naar $NEW_OWNER ==="
transferred=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  if [ ${#REPOS_TO_TRANSFER[@]} -gt 0 ]; then
    skip=1
    for r in "${REPOS_TO_TRANSFER[@]}"; do
      [ "$r" = "$repo" ] && skip=0 && break
    done
    [ "$skip" = "1" ] && continue
  fi
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  log "  $repo: transfer naar $NEW_OWNER..."
  maybe_mutate gh repo transfer "${org}/${repo}" --owner "$NEW_OWNER" --yes 2>/dev/null && ((transferred++)) || true
done
log "=== Repo Transfer complete: $transferred repos overgedragen ==="
send_telegram_message "🔄 *Repo Transfer*\n\n*Overgedragen:* $transferred repos naar $NEW_OWNER\n\n📋 Volledig log: $LOG_FILE" || true
