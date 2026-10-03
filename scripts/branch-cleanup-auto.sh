#!/usr/bin/env bash
# scripts/branch-cleanup-auto.sh - Branch cleanup automation
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Branch Cleanup Auto ==="
branches_deleted=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  cd "$repo_dir"
  merged_branches=$(git branch --merged main 2>/dev/null | grep -v "main" | grep -v "master" | grep -v "develop" || true)
  if [ -n "$merged_branches" ]; then
    while read -r branch; do
      [ -z "$branch" ] && continue
      log "  $repo: verwijder gemerged branch $branch"
      git branch -d "$branch" 2>/dev/null && ((branches_deleted++)) || true
    done <<< "$merged_branches"
  fi
  cd - > /dev/null
done
log "=== Branch Cleanup Auto complete: $branches_deleted branches verwijderd ==="
send_telegram_message "🌿 *Branch Cleanup Auto*\n\n*Branches verwijderd:* $branches_deleted\n\n📋 Volledig log: $LOG_FILE" || true
