#!/usr/bin/env bash
# scripts/multi-tool-chaining.sh - Multi-tool chaining voor complexe taken
# Combineert meerdere tools voor complexe GitHub operaties
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Multi-Tool Chaining ==="

# Configuratie
MTC_ENABLED="${MTC_ENABLED:-yes}"
MTC_DRY_RUN="${MTC_DRY_RUN:-yes}"

# Functies
chain_search_and_read() {
  local repo="$1"
  local query="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Chaining: search code → read file for $repo..."
  
  # Stap 1: Zoek code
  local files
  files=$(gh search code --repo "$repo" --query "$query" --json path --jq '.[].path' 2>/dev/null || echo "")
  
  if [ -z "$files" ]; then
    log "  ⚠️ Geen resultaten voor: $query"
    return 1
  fi
  
  # Stap 2: Lees eerste resultaat
  local first_file
  first_file=$(echo "$files" | head -1)
  
  log "  Gevonden: $first_file"
  
  if [ "$MTC_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would read: $first_file"
    return 0
  fi
  
  # Lees file inhoud
  gh api "repos/$repo/contents/$first_file" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | head -50
}

chain_issue_with_code() {
  local repo="$1"
  local issue_number="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Chaining: get issue → search related code → create comment for $repo..."
  
  # Stap 1: Haal issue op
  local issue_title issue_body
  issue_title=$(gh issue view "$issue_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  issue_body=$(gh issue view "$issue_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  
  log "  Issue #$issue_number: $issue_title"
  
  # Stap 2: Zoek gerelateerde code
  local search_query
  search_query=$(echo "$issue_title" | tr ' ' '\n' | head -3 | tr '\n' ' ')
  
  local related_files
  related_files=$(gh search code --repo "$repo" --query "$search_query" --json path --jq '.[].path' 2>/dev/null | head -5 || echo "")
  
  # Stap 3: Genereer comment
  local comment
  comment=$(cat <<EOF
## 🤖 Multi-Tool Analysis

**Issue:** #$issue_number - $issue_title

### Gerelateerde bestanden

$(if [ -n "$related_files" ]; then
  echo "$related_files" | while read -r f; do
    echo "- \`$f\`"
  done
else
  echo "Geen gerelateerde bestanden gevonden"
fi)

### Aanbevelingen

1. Controleer de gerelateerde bestanden
2. Voeg tests toe voor nieuwe functionaliteit
3. Update documentatie indien nodig

---
*Deze analyse is automatisch gegenereerd door de GitHub Fleet Manager.*
EOF
)
  
  if [ "$MTC_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would post comment on issue #$issue_number"
    return 0
  fi
  
  # Post comment
  gh issue comment "$issue_number" --repo "$repo" --body "$comment" 2>/dev/null && log "  ✅ Comment gepost" || log "  ❌ Kon comment niet posten"
}

chain_pr_with_tests() {
  local repo="$1"
  local pr_number="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Chaining: get PR → check tests → post review for $repo..."
  
  # Stap 1: Haal PR op
  local pr_title pr_files
  pr_title=$(gh pr view "$pr_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  pr_files=$(gh pr diff "$pr_number" --repo "$repo" --name-only 2>/dev/null || echo "")
  
  log "  PR #$pr_number: $pr_title"
  
  # Stap 2: Check of tests zijn toegevoegd
  local has_tests=false
  if echo "$pr_files" | grep -qE '(test|spec)'; then
    has_tests=true
  fi
  
  # Stap 3: Genereer review
  local review
  review=$(cat <<EOF
## 🤖 Multi-Tool PR Review

**PR:** #$pr_number - $pr_title

### Test Coverage

$(if [ "$has_tests" = true ]; then
  echo "✅ Tests zijn toegevoegd in deze PR"
else
  echo "⚠️ Geen tests gevonden in deze PR - overweeg om tests toe te voegen"
fi)

### Files Changed

$(echo "$pr_files" | while read -r f; do
  echo "- \`$f\`"
done)

---
*Deze review is automatisch gegenereerd door de GitHub Fleet Manager.*
EOF
)
  
  if [ "$MTC_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would post review on PR #$pr_number"
    return 0
  fi
  
  # Post review
  gh pr comment "$pr_number" --repo "$repo" --body "$review" 2>/dev/null && log "  ✅ Review gepost" || log "  ❌ Kon review niet posten"
}

# Hoofdlogica
if [ "$MTC_ENABLED" != "yes" ]; then
  log "Multi-tool chaining uitgeschakeld"
  exit 0
fi

# Als er een repo en taak zijn opgegeven
if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
  case "${2:-}" in
    search-read) chain_search_and_read "$1" "${3:-}" ;;
    issue-code) chain_issue_with_code "$1" "${3:-}" ;;
    pr-tests) chain_pr_with_tests "$1" "${3:-}" ;;
    *) log "Onbekende taak: $2" ;;
  esac
else
  log "Geen repo/taak opgegeven - skipping"
fi

log "=== Multi-Tool Chaining klaar ==="
