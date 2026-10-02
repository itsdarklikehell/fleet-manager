#!/usr/bin/env bash
# scripts/inbox-auto-review.sh - Review automatisch PRs
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Auto Review ==="

reviewed=0
approved=0
commented=0
skipped=0

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"

  # Zoek open PRs
  prs=$(gh pr list --repo "${org}/${repo}" --state open --limit 50 --json number,title,author,additions,deletions,labels 2>/dev/null || echo "[]")
  if [ "$prs" != "[]" ] && [ -n "$prs" ]; then
    echo "$prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
      [ -z "$pr" ] && continue

      num=$(echo "$pr" | jq -r '.number // ""')
      title=$(echo "$pr" | jq -r '.title // ""')
      author=$(echo "$pr" | jq -r '.author.login // ""' 2>/dev/null || echo "")
      size=$(( $(echo "$pr" | jq -r '.additions // 0' 2>/dev/null || echo "0") + $(echo "$pr" | jq -r '.deletions // 0' 2>/dev/null || echo "0") ))
      labels=$(echo "$pr" | jq -r '.labels | map(.name) | join(",")' 2>/dev/null || echo "")

      # Sla PRs van jezelf over
      if [ "$author" = "itsdarklikehell" ] || [ "$author" = "hmol33" ]; then
        continue
      fi

      # Check of er al reviews zijn
      reviews=$(gh api "repos/${org}/${repo}/pulls/$num/reviews" --jq 'length' 2>/dev/null || echo "0")
      if [ "$reviews" != "0" ]; then
        skipped=$((skipped + 1))
        continue
      fi

      log "  PR #$num: $title ($author, $size regels)"

      # Kleine PRs: automatisch goedkeuren
      if [ "$size" -lt 50 ]; then
        log "    → Klein, auto-approve"
        if gh pr review "${org}/${repo}#${num}" --approve --body "✅ Auto-approved by GitHub Fleet Manager (small PR: $size lines)" 2>/dev/null; then
          approved=$((approved + 1))
        fi
      # Middelgrote PRs: commentaar toevoegen
      elif [ "$size" -lt "$PR_SIZE_THRESHOLD" ]; then
        log "    → Middelgroot, commentaar toevoegen"
        comment="🤖 *Auto Review*

**Size:** $size lines
**Status:** Looks reasonable for auto-merge

Please ensure:
- [ ] Tests pass
- [ ] Documentation updated if needed
- [ ] No breaking changes

This PR will be considered for auto-merge once approved."
        if gh pr comment "${org}/${repo}#${num}" --body "$comment" 2>/dev/null; then
          commented=$((commented + 1))
        fi
      else
        log "    → Groot, handmatige review nodig"
        skipped=$((skipped + 1))
      fi

      reviewed=$((reviewed + 1))
    done
  fi
done

log "  Reviewed: $reviewed"
log "  Goedgekeurd: $approved"
log "  Commentaar toegevoegd: $commented"
log "  Overgeslagen: $skipped"
log "=== Inbox Auto Review complete ==="

send_telegram_message "👀 *Inbox Auto Review*

*Reviewed:* $reviewed PRs
✅ *Goedgekeurd:* $approved
💬 *Commentaar:* $commented
⏭️ *Overgeslagen:* $skipped

📋 Volledig log: $LOG_FILE" || true