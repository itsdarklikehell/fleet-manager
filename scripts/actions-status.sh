#!/usr/bin/env bash
# scripts/actions-status.sh - Toon status van alle workflows
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Status ==="
total_active=0
total_disabled=0
total_repos=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  workflows=$(gh workflow list --repo "${org}/${repo}" --json name,state --jq '.[] | "\(.name)|\(.state)"' 2>/dev/null || echo "")
  if [ -n "$workflows" ]; then
    total_repos=$((total_repos + 1))
    while IFS='|' read -r name state; do
      if [ "$state" = "active" ]; then
        total_active=$((total_active + 1))
      else
        total_disabled=$((total_disabled + 1))
      fi
      log "  $repo: $name ($state)"
    done <<< "$workflows"
  fi
done
log "=== Actions Status complete: $total_active active, $total_disabled disabled in $total_repos repos ==="
send_telegram_message "📊 *Actions Status*\n\n*Active:* $total_active\n*Disabled:* $total_disabled\n*Repos:* $total_repos\n\n📋 Volledig log: $LOG_FILE" || true