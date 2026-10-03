#!/usr/bin/env bash
# scripts/actions-rerun.sh - Rerun failed workflows
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Rerun ==="
rerun=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  failed_runs=$(gh run list --repo "${org}/${repo}" --status failure --json databaseId --jq '.[].databaseId' 2>/dev/null || echo "")
  if [ -n "$failed_runs" ]; then
    while IFS= read -r run_id; do
      [ -z "$run_id" ] && continue
      log "  $repo: rerun failed run $run_id..."
      maybe_mutate gh run rerun --repo "${org}/${repo}" "$run_id" 2>/dev/null && ((rerun++)) || true
    done <<< "$failed_runs"
  fi
done
log "=== Actions Rerun complete: $rerun runs opnieuw gestart ==="
send_telegram_message "🔄 *Actions Rerun*\n\n*Opnieuw gestart:* $rerun runs\n\n📋 Volledig log: $LOG_FILE" || true