#!/usr/bin/env bash
# scripts/actions-secrets.sh - Audit alle secrets in alle repos
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Secrets Audit ==="
total_secrets=0
total_repos=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  secrets=$(gh secret list --repo "${org}/${repo}" --json name --jq '.[].name' 2>/dev/null || echo "")
  if [ -n "$secrets" ]; then
    count=$(echo "$secrets" | wc -l)
    total_secrets=$((total_secrets + count))
    total_repos=$((total_repos + 1))
    log "  $repo: $count secret(s)"
    while IFS= read -r secret_name; do
      log "    - $secret_name"
    done <<< "$secrets"
  fi
done
log "=== Actions Secrets Audit complete: $total_secrets secrets in $total_repos repos ==="
send_telegram_message "🔑 *Actions Secrets Audit*\n\n*Secrets:* $total_secrets\n*Repos:* $total_repos\n\n📋 Volledig log: $LOG_FILE" || true