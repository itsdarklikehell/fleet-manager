#!/usr/bin/env bash
# scripts/nightly-backlog-triage.sh - Nachtelijke backlog triage
# Label, prioriteit en samenvatting van nieuwe issues elke nacht
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Nightly Backlog Triage ==="

# Configuratie
TRIAGE_REPOS="${TRIAGE_REPOS:-${KEY_REPOS[@]}}"
TRIAGE_LIMIT="${TRIAGE_LIMIT:-30}"
TRIAGE_DAYS="${TRIAGE_DAYS:-1}"
TRIAGE_DRY_RUN="${TRIAGE_DRY_RUN:-no}"

SINCE=$(date -d "$TRIAGE_DAYS days ago" '+%Y-%m-%dT00:00:00Z' 2>/dev/null || date -v-${TRIAGE_DAYS}d '+%Y-%m-%dT00:00:00Z' 2>/dev/null || echo "2025-01-01T00:00:00Z")

# Functies
classify_priority() {
  local title="$1"
  local body="${2:-}"
  local combined="$title $body"
  
  if echo "$combined" | grep -qiE "critical|urgent|security|vuln|cve|exploit|breach|crash|data loss"; then
    echo "P0-critical"
  elif echo "$combined" | grep -qiE "bug|fix|error|broken|regression|not working|fails"; then
    echo "P1-high"
  elif echo "$combined" | grep -qiE "feature|enhancement|add|request|suggest"; then
    echo "P2-medium"
  else
    echo "P3-low"
  fi
}

classify_category() {
  local title="$1"
  local body="${2:-}"
  local combined="$title $body"
  
  if echo "$combined" | grep -qiE "bug|fix|error|crash|broken|regression|not working|fails"; then
    echo "bug"
  elif echo "$combined" | grep -qiE "feature|enhancement|add|request|suggest|would be nice"; then
    echo "feature"
  elif echo "$combined" | grep -qiE "doc|readme|typo|documentation"; then
    echo "docs"
  elif echo "$combined" | grep -qiE "security|vuln|cve|exploit|injection"; then
    echo "security"
  elif echo "$combined" | grep -qiE "performance|slow|optimi|speed|memory"; then
    echo "performance"
  elif echo "$combined" | grep -qiE "test|spec|coverage"; then
    echo "testing"
  elif echo "$combined" | grep -qiE "dependenc|upgrade|update|bump"; then
    echo "dependencies"
  else
    echo "other"
  fi
}

triage_issue() {
  local repo="$1"
  local issue_number="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  # Haal issue info op
  local title body author
  title=$(gh issue view "$issue_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  body=$(gh issue view "$issue_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  author=$(gh issue view "$issue_number" --repo "$repo" --json author --jq '.author.login' 2>/dev/null || echo "")
  
  # Classificeer
  local priority category
  priority=$(classify_priority "$title" "$body")
  category=$(classify_category "$title" "$body")
  
  # Genereer triage notitie
  local triage_note
  triage_note=$(cat <<EOF
## 🤖 Automatische Triage

**Issue:** #$issue_number - $title
**Auteur:** @$author

### Classificatie

- **Prioriteit:** $priority
- **Categorie:** $category

### Triage Notitie

$(case "$priority" in
  "P0-critical") echo "🔴 Kritieke issue - vereist onmiddellijke aandacht" ;;
  "P1-high") echo "🟠 Hoge prioriteit - moet snel worden opgelost" ;;
  "P2-medium") echo "🟡 Medium prioriteit - kan worden gepland" ;;
  "P3-low") echo "🟢 Lage prioriteit - kan wachten" ;;
esac)

---
*Deze triage is automatisch gegenereerd door de GitHub Fleet Manager.*
EOF
)
  
  # Voeg labels toe
  if [ "$TRIAGE_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Zou labels toevoegen aan issue #$issue_number in $repo: $priority, $category"
    log "  [DRY RUN] Zou triage notitie posten op issue #$issue_number in $repo"
  else
    gh issue edit "$issue_number" --repo "$repo" --add-label "$priority" --add-label "$category" 2>/dev/null || true
    gh issue comment "$issue_number" --repo "$repo" --body "$triage_note" 2>/dev/null || true
    log "  ✅ Issue #$issue_number in $repo getriageerd: $priority, $category"
  fi
}

# Hoofdlogica
total_issues=0
total_new=0

for repo in "${TRIAGE_REPOS[@]}"; do
  org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Triaging issues in $repo..."
  
  # Haal open issues op
  issues=$(gh issue list --repo "$repo" --state open --limit "$TRIAGE_LIMIT" --json number,title,createdAt --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.number) \(.title)\"" 2>/dev/null || echo "")
  
  if [ -n "$issues" ]; then
    count=$(echo "$issues" | wc -l)
    total_new=$((total_new + count))
    log "  $count nieuwe issues gevonden"
    
    echo "$issues" | while read -r line; do
      issue_number=$(echo "$line" | awk '{print $1}')
      triage_issue "$repo" "$issue_number"
    done
  else
    log "  Geen nieuwe issues gevonden"
  fi
  
  # Totaal open issues
  open_count=$(gh issue list --repo "$repo" --state open --limit 1 --json number --jq 'length' 2>/dev/null || echo "0")
  total_issues=$((total_issues + open_count))
done

log "=== Triage Samenvatting ==="
log "Totaal open issues: $total_issues"
log "Nieuwe issues (laatste $TRIAGE_DAYS dagen): $total_new"
log "=== Nightly Backlog Triage klaar ==="
