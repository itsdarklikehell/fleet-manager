#!/usr/bin/env bash
# scripts/auto-close.sh - Sluit automatisch oude inactieve issues
set -euo pipefail

# DRY_RUN guard
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Close ==="
closed=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  # Zoek open issues die langer dan STALE_CLOSE_DAYS dagen inactief zijn
  issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,updatedAt --jq '.[] | select(.updatedAt < "'"$(date -d "$STALE_CLOSE_DAYS days ago" +%Y-%m-%d)"'") | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      log "  Issue #$num: $title → sluiten..."
      gh issue close "${org}/${repo}#${num}" --comment "Automatically closed due to inactivity (>${STALE_CLOSE_DAYS} days)." 2>/dev/null && ((closed++)) || true
    done <<< "$issues"
  fi
done
log "=== Auto Close complete: $closed issues gesloten ==="
send_telegram_message "🔒 *Auto Close*\n\n*Gesloten:* $closed issues\n\n📋 Volledig log: $LOG_FILE" || true