#!/usr/bin/env bash
# scripts/repo-description.sh - Update repo descriptions
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

NEW_DESCRIPTION="${1:-}"
if [ -z "$NEW_DESCRIPTION" ]; then
  echo "Usage: $0 <description> [repo1 repo2 ...]"
  exit 1
fi
shift
REPOS_TO_UPDATE=("$@")

log "=== Repo Description Update ==="
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
  log "  $repo: description updaten..."
  maybe_mutate gh repo edit --repo "${org}/${repo}" --description "$NEW_DESCRIPTION" 2>/dev/null && ((updated++)) || true
done
log "=== Repo Description complete: $updated repos geüpdatet ==="
send_telegram_message "📝 *Repo Description*\n\n*Geüpdatet:* $updated repos\n\n📋 Volledig log: $LOG_FILE" || true
