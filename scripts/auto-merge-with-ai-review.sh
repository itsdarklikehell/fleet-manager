#!/usr/bin/env bash
# scripts/auto-merge-with-ai-review.sh - Automatische PR merge met AI review
# Als AI review een PR goedkeurt, automatisch mergen
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Merge With AI Review ==="

# Configuratie
AI_REVIEW_ENABLED="${AI_REVIEW_ENABLED:-no}"
AUTO_MERGE_ENABLED="${AUTO_MERGE_ENABLED:-yes}"
MERGE_STRATEGY="${MERGE_STRATEGY:-merge}"  # merge, squash, rebase

if [ "$AI_REVIEW_ENABLED" != "yes" ]; then
  echo "AI review is uitgeschakeld"
  exit 0
fi

if [ "$AUTO_MERGE_ENABLED" != "yes" ]; then
  echo "Auto merge is uitgeschakeld"
  exit 0
fi

# Functies
check_ai_approval() {
  local repo="$1"
  local pr_number="$2"
  
  # Haal PR comments op
  local comments
  comments=$(gh api "repos/$repo/issues/$pr_number/comments" --jq '.[].body' 2>/dev/null || echo "")
  
  # Check of AI review goedkeurt
  if echo "$comments" | grep -qiE '(approve|looks good|lgtm|✅)'; then
    return 0
  fi
  
  return 1
}

merge_pr() {
  local repo="$1"
  local pr_number="$2"
  
  echo "  PR #$pr_number mergen..."
  
  # Check of PR mergeable is
  local mergeable
  mergeable=$(gh pr view "$pr_number" --repo "$repo" --json mergeable --jq '.mergeable' 2>/dev/null || echo "false")
  
  if [ "$mergeable" != "true" ]; then
    echo "    ⚠️ PR #$pr_number is niet mergeable"
    return 1
  fi
  
  # Merge
  gh pr merge "$pr_number" --repo "$repo" --"$MERGE_STRATEGY" --delete-branch 2>/dev/null || {
    echo "    ❌ Merge gefaald voor PR #$pr_number"
    return 1
  }
  
  echo "    ✅ PR #$pr_number gemerged"
}

# Hoofdlogica
echo "Controleren op PRs met AI goedkeuring..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  prs=$(gh pr list --repo "$repo" --state open --json number --jq '.[].number' 2>/dev/null || echo "")
  
  for pr in $prs; do
    if check_ai_approval "$repo" "$pr"; then
      merge_pr "$repo" "$pr"
    fi
  done
done

echo ""
echo "✅ Auto merge with AI review klaar"
