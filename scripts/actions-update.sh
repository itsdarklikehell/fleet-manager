#!/usr/bin/env bash
# scripts/actions-update.sh - Update alle GitHub Actions workflows naar laatste versie
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Update ==="
updated=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  workflows=$(gh workflow list --repo "${org}/${repo}" --json name,state --jq '.[] | select(.state == "active") | .name' 2>/dev/null || echo "")
  if [ -n "$workflows" ]; then
    while IFS= read -r wf_name; do
      [ -z "$wf_name" ] && continue
      log "  $repo: update workflow '$wf_name'..."
      maybe_mutate gh workflow update --repo "${org}/${repo}" --name "$wf_name" 2>/dev/null && ((updated++)) || true
    done <<< "$workflows"
  fi
done
log "=== Actions Update complete: $updated workflows geüpdatet ==="
send_telegram_message "🔄 *Actions Update*\n\n*Geüpdatet:* $updated workflows\n\n📋 Volledig log: $LOG_FILE" || true