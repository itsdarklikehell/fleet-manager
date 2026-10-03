#!/usr/bin/env bash
# scripts/repo-archive.sh - Archive inactieve repos
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Repo Archive ==="
archived=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  is_archived=$(gh repo view --repo "${org}/${repo}" --json isArchived --jq '.isArchived' 2>/dev/null || echo "false")
  if [ "$is_archived" = "true" ]; then
    continue
  fi
  last_push=$(gh api "repos/${org}/${repo}" --jq '.pushed_at' 2>/dev/null || echo "")
  if [ -n "$last_push" ]; then
    days_inactive=$(( ( $(date +%s) - $(date -d "$last_push" +%s) ) / 86400 ))
    if [ "$days_inactive" -ge "$STALE_CLOSE_DAYS" ]; then
      log "  $repo: archiveren (${days_inactive} dagen inactief)..."
      maybe_mutate gh repo archive "${org}/${repo}" --yes 2>/dev/null && ((archived++)) || true
    fi
  fi
done
log "=== Repo Archive complete: $archived repos gearchiveerd ==="
send_telegram_message "📦 *Repo Archive*\n\n*Gearchiveerd:* $archived repos\n\n📋 Volledig log: $LOG_FILE" || true
