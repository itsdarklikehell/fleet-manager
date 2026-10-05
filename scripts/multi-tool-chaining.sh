#!/usr/bin/env bash
# scripts/multi-tool-chaining.sh - Multi-tool chaining voor complexe taken
# Combineert meerdere tools voor complexe GitHub operaties
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

# Caching (5 min TTL)
CACHE_DIR="${CACHE_DIR:-/tmp/github_fleet_cache}"
CACHE_TTL="${CACHE_TTL:-300}"
mkdir -p "$CACHE_DIR"

cache_get() {
  local key="$1"
  local cache_file="$CACHE_DIR/${key//\//_}"
  if [ -f "$cache_file" ]; then
    local age
    age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [ "$age" -lt "$CACHE_TTL" ]; then
      cat "$cache_file"
      return 0
    fi
  fi
  return 1
}

cache_set() {
  local key="$1"
  local value="$2"
  local cache_file="$CACHE_DIR/${key//\//_}"
  echo "$value" > "$cache_file"
}

# Progress tracking
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0

progress_start() {
  PROGRESS_TOTAL=$1
  PROGRESS_CURRENT=0
  log "  Start: $PROGRESS_TOTAL items te verwerken"
}

progress_update() {
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
  if [ $((PROGRESS_CURRENT % 10)) -eq 0 ] || [ "$PROGRESS_CURRENT" -eq "$PROGRESS_TOTAL" ]; then
    log "  Voortgang: $PROGRESS_CURRENT/$PROGRESS_TOTAL"
  fi
}

# Rate limiting (30 req/min voor GitHub API)
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-$HOME/.github_fleet_rate_limit}"
RATE_LIMIT_MAX="${RATE_LIMIT_MAX:-30}"
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-60}"

rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - RATE_LIMIT_WINDOW))
  
  local count=0
  local file_time=0
  if [ -f "$RATE_LIMIT_FILE" ]; then
    read -r file_time count < "$RATE_LIMIT_FILE" 2>/dev/null || true
    if [ -z "$file_time" ] || [ "$file_time" -lt "$window_start" ]; then
      count=0
    fi
  fi
  
  count=$((count + 1))
  echo "$now $count" > "$RATE_LIMIT_FILE"
  
  if [ "$count" -ge "$RATE_LIMIT_MAX" ]; then
    log "  Rate limit bereikt ($count requests in laatste ${RATE_LIMIT_WINDOW}s), wacht..."
    sleep "$RATE_LIMIT_WINDOW"
    echo "$((now + RATE_LIMIT_WINDOW)) 0" > "$RATE_LIMIT_FILE"
    return 1
  fi
  return 0
}

# Wrapper voor timeout 15 gh api met rate limiting
gh_api_rate_limited() {
  rate_limit_check || true
  timeout 15 gh api "$@"
}

# Parallelisatie config
MAX_PARALLEL="${MAX_PARALLEL:-4}"

# Helper: wacht tot er ruimte is voor nieuwe job
wait_for_slot() {
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
    sleep 0.1
  done
}

# Helper: wacht op alle jobs
wait_all_jobs() {
  wait
}

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
  timeout 15 gh api "repos/$repo/contents/$first_file" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | head -50
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
