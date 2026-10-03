#!/usr/bin/env bash
# scripts/actions-enable.sh - Enable disabled workflows
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Enable ==="
enabled=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  workflows=$(gh workflow list --repo "${org}/${repo}" --json name,state --jq '.[] | select(.state == "disabled") | .name' 2>/dev/null || echo "")
  if [ -n "$workflows" ]; then
    while IFS= read -r wf_name; do
      [ -z "$wf_name" ] && continue
      log "  $repo: enable workflow '$wf_name'..."
      maybe_mutate gh workflow enable --repo "${org}/${repo}" --name "$wf_name" 2>/dev/null && ((enabled++)) || true
    done <<< "$workflows"
  fi
done
log "=== Actions Enable complete: $enabled workflows ingeschakeld ==="
send_telegram_message "🟢 *Actions Enable*\n\n*Ingeschakeld:* $enabled workflows\n\n📋 Volledig log: $LOG_FILE" || true