#!/usr/bin/env bash
# scripts/repo-visibility.sh - Change repo visibility
set -euo pipefail

# DRY_RUN guard
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

NEW_VISIBILITY="${1:-}"
if [ -z "$NEW_VISIBILITY" ]; then
  echo "Usage: $0 <public|private|internal> [repo1 repo2 ...]"
  exit 1
fi
shift
REPOS_TO_UPDATE=("$@")

log "=== Repo Visibility Update ==="
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
  log "  $repo: visibility → $NEW_VISIBILITY..."
  maybe_mutate gh repo edit --repo "${org}/${repo}" --visibility "$NEW_VISIBILITY" 2>/dev/null && ((updated++)) || true
done
log "=== Repo Visibility complete: $updated repos geüpdatet ==="
send_telegram_message "👁️ *Repo Visibility*\n\n*Geüpdatet:* $updated repos → $NEW_VISIBILITY\n\n📋 Volledig log: $LOG_FILE" || true
