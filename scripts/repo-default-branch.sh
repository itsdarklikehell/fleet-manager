#!/usr/bin/env bash
# scripts/repo-default-branch.sh - Change default branch
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

NEW_BRANCH="${1:-}"
if [ -z "$NEW_BRANCH" ]; then
  echo "Usage: $0 <new-default-branch> [repo1 repo2 ...]"
  exit 1
fi
shift
REPOS_TO_UPDATE=("$@")

log "=== Repo Default Branch Update ==="
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
  log "  $repo: default branch → $NEW_BRANCH..."
  maybe_mutate gh api "repos/${org}/${repo}" --method PATCH -f default_branch="$NEW_BRANCH" 2>/dev/null && ((updated++)) || true
done
log "=== Repo Default Branch complete: $updated repos geüpdatet ==="
send_telegram_message "🌿 *Repo Default Branch*\n\n*Geüpdatet:* $updated repos → $NEW_BRANCH\n\n📋 Volledig log: $LOG_FILE" || true
