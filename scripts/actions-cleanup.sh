#!/usr/bin/env bash
# scripts/actions-cleanup.sh - Verwijder oude workflow runs
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Cleanup ==="
cleaned=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  old_runs=$(gh run list --repo "${org}/${repo}" --limit 50 --json databaseId,createdAt --jq '[.[] | select(.createdAt < "'$(date -d '30 days ago' +%Y-%m-%d)'")] | .[].databaseId' 2>/dev/null || echo "")
  if [ -n "$old_runs" ]; then
    while IFS= read -r run_id; do
      [ -z "$run_id" ] && continue
      log "  $repo: verwijder oude run $run_id..."
      maybe_mutate gh run delete --repo "${org}/${repo}" "$run_id" 2>/dev/null && ((cleaned++)) || true
    done <<< "$old_runs"
  fi
done
log "=== Actions Cleanup complete: $cleaned oude runs verwijderd ==="
send_telegram_message "🧹 *Actions Cleanup*\n\n*Verwijderd:* $cleaned oude runs\n\n📋 Volledig log: $LOG_FILE" || true