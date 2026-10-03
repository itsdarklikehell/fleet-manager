#!/usr/bin/env bash
# scripts/inbox-auto-close.sh - Sluit automatisch oude issues
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

log "=== Inbox Auto Close ==="

closed=0
skipped=0
close_days="${INBOX_CLOSE_DAYS:-$STALE_CLOSE_DAYS}"
close_date=$(date -d "$close_days days ago" +%Y-%m-%d)

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Zoek open issues die langer dan close_days dagen inactief zijn
  issues=$(gh issue list --repo "${org}/${repo}" --state open --limit 100 --json number,title,updatedAt,labels --jq --arg date "$close_date" '.[] | select(.updatedAt < $date) | select(.labels | map(.name) | index("pinned") | not) | select(.labels | map(.name) | index("keep-open") | not) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      log "  Issue #$num: $title → sluiten (inactief > ${close_days} dagen)..."
      if gh issue close "${org}/${repo}#${num}" --comment "🤖 Automatically closed due to inactivity (> ${close_days} days). Reopen if still relevant." 2>/dev/null; then
        closed=$((closed + 1))
      else
        skipped=$((skipped + 1))
      fi
    done <<< "$issues"
  fi
done

log "  Gesloten issues: $closed"
log "  Overgeslagen: $skipped"
log "=== Inbox Auto Close complete ==="

send_telegram_message "🔒 *Inbox Auto Close*

*Gesloten:* $closed issues
*Overgeslagen:* $skipped

⏰ Inactief > ${close_days} dagen

📋 Volledig log: $LOG_FILE" || true