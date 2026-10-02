#!/usr/bin/env bash
# scripts/actions-disable.sh - Disable onnodige workflows
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Disable ==="
disabled=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  workflows=$(gh workflow list --repo "${org}/${repo}" --json name,state --jq '.[] | select(.state == "active") | .name' 2>/dev/null || echo "")
  if [ -n "$workflows" ]; then
    while IFS= read -r wf_name; do
      [ -z "$wf_name" ] && continue
      log "  $repo: disable workflow '$wf_name'..."
      maybe_mutate gh workflow disable --repo "${org}/${repo}" --name "$wf_name" 2>/dev/null && ((disabled++)) || true
    done <<< "$workflows"
  fi
done
log "=== Actions Disable complete: $disabled workflows uitgeschakeld ==="
send_telegram_message "🔴 *Actions Disable*\n\n*Uitgeschakeld:* $disabled workflows\n\n📋 Volledig log: $LOG_FILE" || true