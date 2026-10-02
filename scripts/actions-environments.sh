#!/usr/bin/env bash
# scripts/actions-environments.sh - Audit alle environments in alle repos
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Actions Environments Audit ==="
total_envs=0
total_repos=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  envs=$(gh environment list --repo "${org}/${repo}" --json name --jq '.[].name' 2>/dev/null || echo "")
  if [ -n "$envs" ]; then
    count=$(echo "$envs" | wc -l)
    total_envs=$((total_envs + count))
    total_repos=$((total_repos + 1))
    log "  $repo: $count environment(s)"
    while IFS= read -r env_name; do
      log "    - $env_name"
    done <<< "$envs"
  fi
done
log "=== Actions Environments Audit complete: $total_envs environments in $total_repos repos ==="
send_telegram_message "🌍 *Actions Environments Audit*\n\n*Environments:* $total_envs\n*Repos:* $total_repos\n\n📋 Volledig log: $LOG_FILE" || true