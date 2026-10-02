#!/usr/bin/env bash
# scripts/actions-audit.sh - Audit alle GitHub Actions workflows in alle repos
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Audit ==="
total_workflows=0
total_repos=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  workflows=$(gh workflow list --repo "${org}/${repo}" --json name,state --jq '.[] | "\(.name)|\(.state)"' 2>/dev/null || echo "")
  if [ -n "$workflows" ]; then
    count=$(echo "$workflows" | wc -l)
    total_workflows=$((total_workflows + count))
    total_repos=$((total_repos + 1))
    log "  $repo: $count workflow(s)"
    while IFS='|' read -r name state; do
      log "    - $name ($state)"
    done <<< "$workflows"
  fi
done
log "=== Actions Audit complete: $total_workflows workflows in $total_repos repos ==="
send_telegram_message "🔍 *Actions Audit*\n\n*Workflows:* $total_workflows\n*Repos:* $total_repos\n\n📋 Volledig log: $LOG_FILE" || true