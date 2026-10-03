#!/usr/bin/env bash
# scripts/inbox-prioriteit.sh - Prioriteit geven aan notificaties
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

log "=== Inbox Prioriteit ==="

PRIORITY_HIGH="priority-high"
PRIORITY_MEDIUM="priority-medium"
PRIORITY_LOW="priority-low"

prioritized=0

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Haal open issues op
  issues=$(gh issue list --repo "${org}/${repo}" --state open --limit 50 --json number,title,labels,assignees,createdAt,updatedAt 2>/dev/null || echo "[]")
  if [ "$issues" != "[]" ] && [ -n "$issues" ]; then
    echo "$issues" | jq -c '.[]' 2>/dev/null | while IFS= read -r issue; do
      [ -z "$issue" ] && continue

      num=$(echo "$issue" | jq -r '.number // ""')
      title=$(echo "$issue" | jq -r '.title // ""')
      labels=$(echo "$issue" | jq -r '.labels | map(.name) | join(",")' 2>/dev/null || echo "")
      assignees=$(echo "$issue" | jq -r '.assignees | length' 2>/dev/null || echo "0")
      created=$(echo "$issue" | jq -r '.createdAt // ""' 2>/dev/null || echo "")

      # Bepaal prioriteit
      priority=""
      title_lower=$(echo "$title" | tr '[:upper:]' '[:lower:]')

      # Hoge prioriteit: security, crash, bug zonder assignee, of oud
      if echo "$title_lower" | grep -qiE 'security|vuln|cve|exploit|injection|crash|urgent|critical'; then
        priority="$PRIORITY_HIGH"
      elif echo "$labels" | grep -qiE 'security|bug|critical'; then
        priority="$PRIORITY_HIGH"
      elif [ "$assignees" = "0" ] && [ -n "$created" ]; then
        # Issues zonder assignee die ouder zijn dan 7 dagen
        created_date=$(echo "$created" | cut -dT -f1)
        week_ago=$(date -d "7 days ago" +%Y-%m-%d)
        if [ "$created_date" \< "$week_ago" ]; then
          priority="$PRIORITY_HIGH"
        fi
      fi

      # Medium prioriteit: feature requests, documentation
      if [ -z "$priority" ]; then
        if echo "$title_lower" | grep -qiE 'feature|enhancement|request|documentation|docs'; then
          priority="$PRIORITY_MEDIUM"
        elif echo "$labels" | grep -qiE 'enhancement|documentation|question'; then
          priority="$PRIORITY_MEDIUM"
        fi
      fi

      # Low prioriteit: testing, refactor, dependencies
      if [ -z "$priority" ]; then
        if echo "$title_lower" | grep -qiE 'test|refactor|cleanup|dependenc|bump|typo'; then
          priority="$PRIORITY_LOW"
        elif echo "$labels" | grep -qiE 'testing|refactor|dependencies'; then
          priority="$PRIORITY_LOW"
        fi
      fi

      # Voeg prioriteit label toe
      if [ -n "$priority" ]; then
        log "  Issue #$num: $title → prioriteit: $priority"
        gh issue edit "${org}/${repo}#${num}" --add-label "$priority" 2>/dev/null && prioritized=$((prioritized + 1)) || true
      fi
    done
  fi

  # Haal open PRs op
  prs=$(gh pr list --repo "${org}/${repo}" --state open --limit 50 --json number,title,labels,createdAt,additions,deletions 2>/dev/null || echo "[]")
  if [ "$prs" != "[]" ] && [ -n "$prs" ]; then
    echo "$prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
      [ -z "$pr" ] && continue

      num=$(echo "$pr" | jq -r '.number // ""')
      title=$(echo "$pr" | jq -r '.title // ""')
      labels=$(echo "$pr" | jq -r '.labels | map(.name) | join(",")' 2>/dev/null || echo "")
      size=$(( $(echo "$pr" | jq -r '.additions // 0' 2>/dev/null || echo "0") + $(echo "$pr" | jq -r '.deletions // 0' 2>/dev/null || echo "0") ))

      priority=""
      title_lower=$(echo "$title" | tr '[:upper:]' '[:lower:]')

      # Hoge prioriteit voor security of grote PRs
      if echo "$title_lower" | grep -qiE 'security|vuln|cve|fix|bug|hotfix'; then
        priority="$PRIORITY_HIGH"
      elif [ "$size" -gt "$PR_SIZE_THRESHOLD" ]; then
        priority="$PRIORITY_HIGH"
      elif echo "$labels" | grep -qiE 'bug|critical|security'; then
        priority="$PRIORITY_HIGH"
      elif echo "$title_lower" | grep -qiE 'feature|enhancement'; then
        priority="$PRIORITY_MEDIUM"
      elif echo "$labels" | grep -qiE 'enhancement|documentation'; then
        priority="$PRIORITY_MEDIUM"
      else
        priority="$PRIORITY_LOW"
      fi

      if [ -n "$priority" ]; then
        log "  PR #$num: $title → prioriteit: $priority"
        gh pr edit "${org}/${repo}#${num}" --add-label "$priority" 2>/dev/null && prioritized=$((prioritized + 1)) || true
      fi
    done
  fi
done

log "  Geprioriteerde items: $prioritized"
log "=== Inbox Prioriteit complete ==="

send_telegram_message "🎯 *Inbox Prioriteit*

*Geprioriteerde items:* $prioritized

🔴 Hoog: security, bugs zonder assignee, grote PRs
🟡 Medium: features, documentation
🟢 Laag: tests, refactoring, dependencies

📋 Volledig log: $LOG_FILE" || true