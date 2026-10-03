#!/usr/bin/env bash
# scripts/status.sh - GitHub Fleet Status
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== GitHub Fleet Status ==="
rm -f "$REPOS_DIR"/*.status.tmp 2>/dev/null || true
max_jobs="${PARALLEL_JOBS:-4}"
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$max_jobs" ]; do
    sleep 0.2
  done
  {
    echo "--- $repo ---"
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    pr_count=$(gh pr list --repo "${org}/${repo}" --state open --json number --jq 'length' 2>/dev/null || echo "?")
    echo "PRS: $repo has $pr_count open PRs"
    iss_count=$(gh issue list --repo "${org}/${repo}" --state open --json number --jq 'length' 2>/dev/null || echo "0")
    echo "ISS-COUNT: $iss_count"
    echo "DONE: $repo"
  } > "$repo_dir.status.tmp" 2>&1 &
done
wait 2>/dev/null || true
log "=== Status complete ==="
send_telegram_message "🚢 *GitHub Fleet Status*\n\n📋 Volledig log: $LOG_FILE" || true
rm -f "$REPOS_DIR"/*.status.tmp 2>/dev/null || true
