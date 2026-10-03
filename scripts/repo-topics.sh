#!/usr/bin/env bash
# scripts/repo-topics.sh - Update repo topics
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

NEW_TOPICS="${1:-}"
if [ -z "$NEW_TOPICS" ]; then
  echo "Usage: $0 <topic1,topic2,...> [repo1 repo2 ...]"
  exit 1
fi
shift
REPOS_TO_UPDATE=("$@")

log "=== Repo Topics Update ==="
updated=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  if [ ${#REPOS_TO_UPDATE[@]} -gt 0 ]; then
    skip=1
    for r in "${REPOS_TO_UPDATE[@]}"; do
      [ "$r" = "$repo" ] && skip=0 && break
    done
    [ "$skip" = "1" ] && continue
  fi
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  log "  $repo: topics updaten..."
  maybe_mutate gh api "repos/${org}/${repo}/topics" --method PUT -f "names[]=$NEW_TOPICS" 2>/dev/null && ((updated++)) || true
done
log "=== Repo Topics complete: $updated repos geüpdatet ==="
send_telegram_message "🏷️ *Repo Topics*\n\n*Geüpdatet:* $updated repos\n\n📋 Volledig log: $LOG_FILE" || true
