#!/usr/bin/env bash
# scripts/inbox-auto-label.sh - Voeg automatisch labels toe
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Auto Label ==="

labeled=0
skipped=0

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Zoek open issues zonder labels
  issues=$(gh issue list --repo "${org}/${repo}" --state open --limit 100 --json number,title,body,labels --jq '.[] | select(.labels | length == 0) | "\(.number)|\(.title)|\(.body // "")"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title body; do
      [ -z "$num" ] && continue

      labels_to_add=()
      combined="$title $body"
      combined_lower=$(echo "$combined" | tr '[:upper:]' '[:lower:]')

      # Detecteer labels op basis van titel en body
      if echo "$combined_lower" | grep -qiE 'bug|crash|error|broken|fail|regression|not working'; then
        labels_to_add+=("bug")
      fi
      if echo "$combined_lower" | grep -qiE 'feature|enhancement|request|add|suggest|would be nice'; then
        labels_to_add+=("enhancement")
      fi
      if echo "$combined_lower" | grep -qiE 'doc|readme|wiki|guide|typo|documentation'; then
        labels_to_add+=("documentation")
      fi
      if echo "$combined_lower" | grep -qiE 'question|help|how|what|why|when|where'; then
        labels_to_add+=("question")
      fi
      if echo "$combined_lower" | grep -qiE 'security|vuln|cve|exploit|injection'; then
        labels_to_add+=("security")
      fi
      if echo "$combined_lower" | grep -qiE 'performance|slow|optimi|speed|memory'; then
        labels_to_add+=("performance")
      fi
      if echo "$combined_lower" | grep -qiE 'test|spec|coverage'; then
        labels_to_add+=("testing")
      fi
      if echo "$combined_lower" | grep -qiE 'refactor|cleanup|simplify'; then
        labels_to_add+=("refactor")
      fi
      if echo "$combined_lower" | grep -qiE 'dependenc|upgrade|update|bump'; then
        labels_to_add+=("dependencies")
      fi
      if echo "$combined_lower" | grep -qiE 'good first|beginner|starter|easy'; then
        labels_to_add+=("good first issue")
      fi

      if [ ${#labels_to_add[@]} -gt 0 ]; then
        log "  Issue #$num: $title → labels: ${labels_to_add[*]}"
        args=(issue edit "${num}" --repo "${org}/${repo}")
        for lbl in "${labels_to_add[@]}"; do
          args+=(--add-label "$lbl")
        done
        if gh "${args[@]}" 2>/dev/null; then
          labeled=$((labeled + 1))
        else
          skipped=$((skipped + 1))
        fi
      fi
    done <<< "$issues"
  fi

  # Zoek open PRs zonder labels
  prs=$(gh pr list --repo "${org}/${repo}" --state open --limit 100 --json number,title,body,labels --jq '.[] | select(.labels | length == 0) | "\(.number)|\(.title)|\(.body // "")"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r num title body; do
      [ -z "$num" ] && continue

      labels_to_add=()
      combined="$title $body"
      combined_lower=$(echo "$combined" | tr '[:upper:]' '[:lower:]')

      if echo "$combined_lower" | grep -qiE 'bug|fix|error|crash|broken|regression'; then
        labels_to_add+=("bug")
      fi
      if echo "$combined_lower" | grep -qiE 'feature|enhancement|add|request'; then
        labels_to_add+=("enhancement")
      fi
      if echo "$combined_lower" | grep -qiE 'doc|readme|documentation'; then
        labels_to_add+=("documentation")
      fi
      if echo "$combined_lower" | grep -qiE 'test|spec|coverage'; then
        labels_to_add+=("testing")
      fi
      if echo "$combined_lower" | grep -qiE 'refactor|cleanup'; then
        labels_to_add+=("refactor")
      fi
      if echo "$combined_lower" | grep -qiE 'dependenc|upgrade|bump'; then
        labels_to_add+=("dependencies")
      fi

      if [ ${#labels_to_add[@]} -gt 0 ]; then
        log "  PR #$num: $title → labels: ${labels_to_add[*]}"
        args=(pr edit "${num}" --repo "${org}/${repo}")
        for lbl in "${labels_to_add[@]}"; do
          args+=(--add-label "$lbl")
        done
        if gh "${args[@]}" 2>/dev/null; then
          labeled=$((labeled + 1))
        else
          skipped=$((skipped + 1))
        fi
      fi
    done <<< "$prs"
  fi
done

log "  Gelabelde items: $labeled"
log "  Overgeslagen: $skipped"
log "=== Inbox Auto Label complete ==="

send_telegram_message "🏷️ *Inbox Auto Label*

*Gelabeld:* $labeled items
*Overgeslagen:* $skipped

📋 Volledig log: $LOG_FILE" || true