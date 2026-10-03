#!/usr/bin/env bash
# scripts/pr-description-generator.sh - Genereert PR beschrijvingen uit commits
# Voegt test resultaten en impact analyse toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== PR Description Generator ==="

# Functies
generate_description() {
  local repo="$1"
  local pr_number="$2"
  
  log "Genereer beschrijving voor PR #$pr_number in $repo..."
  
  # Haal PR info op
  local pr_title
  pr_title=$(gh pr view "$pr_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  
  # Haal commits op
  local commits
  commits=$(gh pr view "$pr_number" --repo "$repo" --json commits --jq '.commits[].commit.message' 2>/dev/null || echo "")
  
  # Haal changed files op
  local changed_files
  changed_files=$(gh pr view "$pr_number" --repo "$repo" --json files --jq '.files[].path' 2>/dev/null || echo "")
  
  # Categoriseer commits
  local feat_count=0
  local fix_count=0
  local docs_count=0
  local refactor_count=0
  local other_count=0
  
  while IFS= read -r commit; do
    if echo "$commit" | grep -qiE '^(feat|feature)'; then
      feat_count=$((feat_count + 1))
    elif echo "$commit" | grep -qiE '^(fix|bug)'; then
      fix_count=$((fix_count + 1))
    elif echo "$commit" | grep -qiE '^(docs|doc)'; then
      docs_count=$((docs_count + 1))
    elif echo "$commit" | grep -qiE '^(refactor|cleanup)'; then
      refactor_count=$((refactor_count + 1))
    else
      other_count=$((other_count + 1))
    fi
  done <<< "$commits"
  
  # Genereer beschrijving
  local description="## 📝 Wijzigingen

"
  
  if [ "$feat_count" -gt 0 ]; then
    description+="### ✨ Nieuwe features ($feat_count)
"
    echo "$commits" | grep -iE '^(feat|feature)' | sed 's/^/ - /' >> /tmp/pr_desc_$$
    description+=$(cat /tmp/pr_desc_$$)
    description+="
"
    rm -f /tmp/pr_desc_$$
  fi
  
  if [ "$fix_count" -gt 0 ]; then
    description+="### 🐛 Bugfixes ($fix_count)
"
    echo "$commits" | grep -iE '^(fix|bug)' | sed 's/^/ - /' >> /tmp/pr_desc_$$
    description+=$(cat /tmp/pr_desc_$$)
    description+="
"
    rm -f /tmp/pr_desc_$$
  fi
  
  if [ "$docs_count" -gt 0 ]; then
    description+="📚 Documentatie ($docs_count)
"
    echo "$commits" | grep -iE '^(docs|doc)' | sed 's/^/ - /' >> /tmp/pr_desc_$$
    description+=$(cat /tmp/pr_desc_$$)
    description+="
"
    rm -f /tmp/pr_desc_$$
  fi
  
  if [ "$refactor_count" -gt 0 ]; then
    description+="♻️ Refactoring ($refactor_count)
"
    echo "$commits" | grep -iE '^(refactor|cleanup)' | sed 's/^/ - /' >> /tmp/pr_desc_$$
    description+=$(cat /tmp/pr_desc_$$)
    description+="
"
    rm -f /tmp/pr_desc_$$
  fi
  
  # Impact analyse
  local file_count
  file_count=$(echo "$changed_files" | grep -c . 2>/dev/null || echo "0")
  
  description+="## 📊 Impact

"
  description+="- Bestanden gewijzigd: $file_count
"
  description+="- Commits: $((feat_count + fix_count + docs_count + refactor_count + other_count))
"
  
  # Test instructies
  description+="
## 🧪 Testen

"
  description+="- [ ] Controleer of alle tests slagen
"
  description+="- [ ] Test handmatig in staging omgeving
"
  description+="- [ ] Controleer documentatie is bijgewerkt
"
  
  echo "$description"
}

# Hoofdlogica
if [ -z "${1:-}" ]; then
  log "Gebruik: pr-description-generator.sh <repo> [pr_number]"
  log "  Als pr_number ontbreekt, worden alle open PRs verwerkt"
  exit 1
fi

repo="$1"
pr_number="${2:-}"

if [ -n "$pr_number" ]; then
  # Specifieke PR
  generate_description "$repo" "$pr_number"
else
  # Alle open PRs
  log "Alle open PRs verwerken voor $repo..."
  prs=$(gh pr list --repo "$repo" --state open --json number --jq '.[].number' 2>/dev/null || echo "")
  
  if [ -z "$prs" ]; then
    log "Geen open PRs gevonden"
    exit 0
  fi
  
  for pr in $prs; do
    generate_description "$repo" "$pr"
    log "---"
  done
fi
