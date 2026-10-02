#!/usr/bin/env bash
# scripts/repo-delete-branch-protection.sh - Delete branch protection
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

BRANCH="${1:-main}"
shift
REPOS_TO_UPDATE=("$@")

log "=== Repo Delete Branch Protection ==="
deleted=0
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
  log "  $repo: branch protection verwijderen voor $BRANCH..."
  maybe_mutate gh api "repos/${org}/${repo}/branches/$BRANCH/protection" --method DELETE 2>/dev/null && ((deleted++)) || true
done
log "=== Repo Delete Branch Protection complete: $deleted repos geüpdatet ==="
send_telegram_message "🔓 *Repo Delete Branch Protection*\n\n*Verwijderd:* $deleted repos (branch: $BRANCH)\n\n📋 Volledig log: $LOG_FILE" || true
