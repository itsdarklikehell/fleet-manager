#!/usr/bin/env bash
# scripts/ci-failure-check.sh - CI failure check
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== CI Failure Check ==="
failures=0
for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  failed_runs
  failed_runs=$(gh run list --repo "$kr" --limit 5 --json name,conclusion --jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")
  if [ "$failed_runs" -gt 0 ]; then
    log "  ⚠️ $kr: $failed_runs failed run(s)"
    ((failures++)) || true
  fi
done
log "=== CI Failure Check complete: $failures repos met failures ==="
send_telegram_message "🔴 *CI Failure Check*\n\n*Failures:* $failures\n\n📋 Volledig log: $LOG_FILE" || true
