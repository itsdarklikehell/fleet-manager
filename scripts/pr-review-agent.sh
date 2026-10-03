#!/usr/bin/env bash
# scripts/pr-review-agent.sh - Automatisch PRs reviewen met AGENTS.md conventies
# Leest AGENTS.md uit de repo, reviewt open PRs tegen die regels, en post commentaar
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== PR Review Agent ==="

# Configuratie
REVIEW_REPOS="${REVIEW_REPOS:-${KEY_REPOS[@]}}"
REVIEW_LIMIT="${REVIEW_LIMIT:-10}"
REVIEW_DRY_RUN="${REVIEW_DRY_RUN:-no}"

# Functies
read_agents_md() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  # Probeer AGENTS.md te lezen
  local content
  content=$(gh api "repos/$repo/contents/AGENTS.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  
  if [ -z "$content" ]; then
    # Probeer CLAUDE.md als alternatief
    content=$(gh api "repos/$repo/contents/CLAUDE.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  fi
  
  echo "$content"
}

review_pr() {
  local repo="$1"
  local pr_number="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  # Haal PR info op
  local pr_title pr_body pr_author pr_diff
  pr_title=$(gh pr view "$pr_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  pr_body=$(gh pr view "$pr_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  pr_author=$(gh pr view "$pr_number" --repo "$repo" --json author --jq '.author.login' 2>/dev/null || echo "")
  pr_diff=$(gh pr diff "$pr_number" --repo "$repo" 2>/dev/null || echo "")
  
  # Haal AGENTS.md conventies op
  local agents_md
  agents_md=$(read_agents_md "$repo")
  
  # Genereer review commentaar
  local review_comment
  review_comment=$(cat <<EOF
## 🤖 Automatische PR Review

**PR:** #$pr_number - $pr_title
**Auteur:** @$pr_author

### Review

$(if [ -n "$agents_md" ]; then
  echo "Deze PR is gereviewd tegen de conventies in AGENTS.md:"
  echo ""
  echo "$agents_md" | head -20
else
  echo "Geen AGENTS.md gevonden in deze repo. Algemene review:"
fi)

### Checks

- [ ] Code volgt de project conventies
- [ ] Tests zijn toegevoegd/gewijzigd indien nodig
- [ ] Documentatie is bijgewerkt indien nodig
- [ ] Geen hardcoded credentials of secrets
- [ ] Geen console.log of debug statements

### Suggesties

$(if echo "$pr_diff" | grep -q "console.log"; then
  echo "⚠️ console.log gevonden - overweeg te verwijderen"
fi)
$(if echo "$pr_diff" | grep -q "TODO\|FIXME\|HACK"; then
  echo "⚠️ TODO/FIXME/HACK gevonden - overweeg op te lossen"
fi)
$(if echo "$pr_diff" | grep -q "password\|secret\|token\|api_key"; then
  echo "⚠️ Mogelijke secrets gevonden - controleer of deze veilig zijn"
fi)

---
*Deze review is automatisch gegenereerd door de GitHub Fleet Manager.*
EOF
)
  
  # Post commentaar
  if [ "$REVIEW_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Zou review posten op PR #$pr_number in $repo"
    log "  Review: $review_comment"
  else
    gh pr comment "$pr_number" --repo "$repo" --body "$review_comment" 2>/dev/null
    log "  ✅ Review gepost op PR #$pr_number in $repo"
  fi
}

# Hoofdlogica
for repo in "${REVIEW_REPOS[@]}"; do
  org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Reviewing PRs in $repo..."
  
  # Haal open PRs op
  prs=$(gh pr list --repo "$repo" --state open --limit "$REVIEW_LIMIT" --json number,title,author --jq '.[] | "\(.number) \(.title) by \(.author.login)"' 2>/dev/null || echo "")
  
  if [ -n "$prs" ]; then
    echo "$prs" | while read -r line; do
      pr_number=$(echo "$line" | awk '{print $1}')
      review_pr "$repo" "$pr_number"
    done
  else
    log "  Geen open PRs gevonden"
  fi
done

log "=== PR Review Agent klaar ==="
