#!/usr/bin/env bash
# scripts/auto-label.sh - Voegt automatisch labels toe aan nieuwe issues
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Label ==="
labeled=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  # Zoek open issues zonder labels
  issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,labels --jq '.[] | select(.labels | length == 0) | "\(.number)|\(.title)"' 2>/dev/null || true)
  if [ -n "$issues" ]; then
    while IFS='|' read -r num title; do
      [ -z "$num" ] && continue
      labels_to_add=()
      # Detecteer labels op basis van titel
      title_lower=$(echo "$title" | tr '[:upper:]' '[:lower:]')
      if echo "$title_lower" | grep -qiE 'bug|crash|error|broken|fail'; then
        labels_to_add+=("bug")
      fi
      if echo "$title_lower" | grep -qiE 'feature|enhancement|request|add'; then
        labels_to_add+=("enhancement")
      fi
      if echo "$title_lower" | grep -qiE 'doc|readme|wiki|guide'; then
        labels_to_add+=("documentation")
      fi
      if echo "$title_lower" | grep -qiE 'question|help|how'; then
        labels_to_add+=("question")
      fi
      if echo "$title_lower" | grep -qiE 'good first|beginner|starter'; then
        labels_to_add+=("good first issue")
      fi
      if [ ${#labels_to_add[@]} -gt 0 ]; then
        log "  Issue #$num: $title → labels: ${labels_to_add[*]}"
        args=(issue edit "${num}" --repo "${org}/${repo}")
        for lbl in "${labels_to_add[@]}"; do
          args+=(--add-label "$lbl")
        done
        gh "${args[@]}" 2>/dev/null && ((labeled++)) || true
      fi
    done <<< "$issues"
  fi
done
log "=== Auto Label complete: $labeled issues gelabeld ==="
send_telegram_message "🏷️ *Auto Label*\n\n*Gelabeld:* $labeled issues\n\n📋 Volledig log: $LOG_FILE" || true