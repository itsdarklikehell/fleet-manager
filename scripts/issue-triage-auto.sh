#!/usr/bin/env bash
# scripts/issue-triage-auto.sh - Issue triage automation
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

log "=== Issue Triage Auto ==="
triaged=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,labels --jq '.[] | select(.labels | length == 0) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      log "  Issue #$num: $title"
      labels=""
      if echo "$title" | grep -qiE "bug|fix|error|crash|broken"; then labels="bug"
      elif echo "$title" | grep -qiE "feature|enhancement|add|new"; then labels="enhancement"
      elif echo "$title" | grep -qiE "doc|readme|guide|tutorial"; then labels="documentation"
      elif echo "$title" | grep -qiE "question|help|how"; then labels="question"
      fi
      if [ -n "$labels" ]; then
        gh issue edit "${org}/${repo}#$num" --add-label "$labels" 2>/dev/null && ((triaged++)) || true
      fi
    done <<< "$issues"
  fi
done
log "=== Issue Triage Auto complete: $triaged issues triaged ==="
send_telegram_message "🏷️ *Issue Triage Auto*\n\n*Triaged:* $triaged issues\n\n📋 Volledig log: $LOG_FILE" || true
