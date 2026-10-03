#!/usr/bin/env bash
# scripts/repo-unarchive.sh - Unarchive gearchiveerde repos
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Repo Unarchive ==="
unarchived=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  is_archived=$(gh repo view --repo "${org}/${repo}" --json isArchived --jq '.isArchived' 2>/dev/null || echo "false")
  if [ "$is_archived" = "true" ]; then
    log "  $repo: unarchiveren..."
    maybe_mutate gh api "repos/${org}/${repo}" --method PATCH -f archived=false 2>/dev/null && ((unarchived++)) || true
  fi
done
log "=== Repo Unarchive complete: $unarchived repos ge-unarchiveerd ==="
send_telegram_message "📂 *Repo Unarchive*\n\n*Ge-unarchiveerd:* $unarchived repos\n\n📋 Volledig log: $LOG_FILE" || true
