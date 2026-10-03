#!/usr/bin/env bash
# scripts/actions-variables.sh - Audit alle variables in alle repos
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Variables Audit ==="
total_variables=0
total_repos=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  variables=$(gh variable list --repo "${org}/${repo}" --json name --jq '.[].name' 2>/dev/null || echo "")
  if [ -n "$variables" ]; then
    count=$(echo "$variables" | wc -l)
    total_variables=$((total_variables + count))
    total_repos=$((total_repos + 1))
    log "  $repo: $count variable(s)"
    while IFS= read -r var_name; do
      log "    - $var_name"
    done <<< "$variables"
  fi
done
log "=== Actions Variables Audit complete: $total_variables variables in $total_repos repos ==="
send_telegram_message "📦 *Actions Variables Audit*\n\n*Variables:* $total_variables\n*Repos:* $total_repos\n\n📋 Volledig log: $LOG_FILE" || true