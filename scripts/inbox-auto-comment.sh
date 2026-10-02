#!/usr/bin/env bash
# scripts/inbox-auto-comment.sh - Voeg automatisch commentaar toe
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Auto Comment ==="

commented=0
skipped=0

# Standaard antwoorden
REPLY_BUG="🐛 Thanks for reporting this bug! I'll investigate and get back to you soon."
REPLY_FEATURE="✨ Thanks for the feature request! I'll review this and add it to the backlog."
REPLY_QUESTION="❓ Thanks for your question! I'll look into this and respond as soon as possible."
REPLY_DEFAULT="👋 Thanks for reaching out! I'll review this and get back to you soon."

classify_item() {
  local title="$1"
  local body="${2:-}"
  local combined="$title $body"

  if echo "$combined" | grep -qiE "bug|fix|error|crash|broken|regression|not working|fails"; then
    echo "bug"
  elif echo "$combined" | grep -qiE "feature|enhancement|add|request|suggest|would be nice|could you"; then
    echo "feature"
  elif echo "$combined" | grep -qiE "question|how|what|why|when|where|help|wondering"; then
    echo "question"
  elif echo "$combined" | grep -qiE "doc|readme|typo|documentation"; then
    echo "documentation"
  elif echo "$combined" | grep -qiE "security|vuln|cve|exploit|injection"; then
    echo "security"
  elif echo "$combined" | grep -qiE "performance|slow|optimi|speed|memory"; then
    echo "performance"
  elif echo "$combined" | grep -qiE "test|spec|coverage"; then
    echo "testing"
  elif echo "$combined" | grep -qiE "refactor|cleanup|simplify"; then
    echo "refactor"
  elif echo "$combined" | grep -qiE "dependenc|upgrade|update|bump"; then
    echo "dependencies"
  else
    echo "other"
  fi
}

get_reply_for_category() {
  local category="$1"
  case "$category" in
    bug) echo "$REPLY_BUG" ;;
    feature) echo "$REPLY_FEATURE" ;;
    question) echo "$REPLY_QUESTION" ;;
    *) echo "$REPLY_DEFAULT" ;;
  esac
}

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Zoek open issues
  issues=$(gh issue list --repo "${org}/${repo}" --state open --limit 50 --json number,title,body,author,comments --jq '.[] | select(.comments == 0) | "\(.number)|\(.title)|\(.body // "")|@\(.author.login)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title body author; do
      [ -z "$num" ] && continue

      # Sla eigen issues over
      if [ "$author" = "@itsdarklikehell" ] || [ "$author" = "@hmol33" ]; then
        continue
      fi

      category=$(classify_item "$title" "$body")
      reply=$(get_reply_for_category "$category")

      log "  Issue #$num: $title → commentaar ($category)"
      if gh issue comment "${org}/${repo}#${num}" --body "$reply" 2>/dev/null; then
        commented=$((commented + 1))
      else
        skipped=$((skipped + 1))
      fi
    done <<< "$issues"
  fi

  # Zoek open PRs zonder comments
  prs=$(gh pr list --repo "${org}/${repo}" --state open --limit 50 --json number,title,author,comments --jq '.[] | select(.comments == 0) | "\(.number)|\(.title)|@\(.author.login)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r num title author; do
      [ -z "$num" ] && continue

      # Sla eigen PRs over
      if [ "$author" = "@itsdarklikehell" ] || [ "$author" = "@hmol33" ]; then
        continue
      fi

      log "  PR #$num: $title → commentaar"
      if gh pr comment "${org}/${repo}#${num}" --body "👋 Thanks for the PR! I'll review this soon." 2>/dev/null; then
        commented=$((commented + 1))
      else
        skipped=$((skipped + 1))
      fi
    done <<< "$prs"
  fi
done

log "  Commentaar toegevoegd: $commented"
log "  Overgeslagen: $skipped"
log "=== Inbox Auto Comment complete ==="

send_telegram_message "💬 *Inbox Auto Comment*

*Commentaar toegevoegd:* $commented items
*Overgeslagen:* $skipped

📋 Volledig log: $LOG_FILE" || true