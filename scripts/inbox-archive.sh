#!/usr/bin/env bash
# scripts/inbox-archive.sh - Archiveer oude notificaties
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

log "=== Inbox Archive ==="

ARCHIVE_LABEL="archived"
archived_issues=0
archived_prs=0
skipped=0

# Archiveer issues die gesloten zijn en langer dan ARCHIVE_DAYS dagen geleden
archive_days="${ARCHIVE_DAYS:-30}"
archive_date=$(date -d "$archive_days days ago" +%Y-%m-%d)

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Gesloten issues archiveren
  closed_issues=$(gh issue list --repo "${org}/${repo}" --state closed --limit 50 --json number,title,closedAt,labels --jq --arg date "$archive_date" '.[] | select(.closedAt < $date) | select(.labels | map(.name) | index("archived") | not) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$closed_issues" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      log "  Issue #$num: $title → archiveren..."
      if gh issue edit "${org}/${repo}#${num}" --add-label "$ARCHIVE_LABEL" 2>/dev/null; then
        archived_issues=$((archived_issues + 1))
      else
        skipped=$((skipped + 1))
      fi
    done <<< "$closed_issues"
  fi

  # Gesloten/merged PRs archiveren
  closed_prs=$(gh pr list --repo "${org}/${repo}" --state closed --limit 50 --json number,title,closedAt,labels --jq --arg date "$archive_date" '.[] | select(.closedAt < $date) | select(.labels | map(.name) | index("archived") | not) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$closed_prs" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      log "  PR #$num: $title → archiveren..."
      if gh pr edit "${org}/${repo}#${num}" --add-label "$ARCHIVE_LABEL" 2>/dev/null; then
        archived_prs=$((archived_prs + 1))
      else
        skipped=$((skipped + 1))
      fi
    done <<< "$closed_prs"
  fi
done

log "  Gearchiveerde issues: $archived_issues"
log "  Gearchiveerde PRs: $archived_prs"
log "  Overgeslagen: $skipped"
log "=== Inbox Archive complete ==="

send_telegram_message "📦 *Inbox Archive*

*Gearchiveerde issues:* $archived_issues
*Gearchiveerde PRs:* $archived_prs
*Overgeslagen:* $skipped

📋 Volledig log: $LOG_FILE" || true