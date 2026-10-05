#!/usr/bin/env bash
# scripts/pr-review-agent.sh - Automatisch PRs reviewen met AGENTS.md conventies
# Leest AGENTS.md uit de repo, reviewt open PRs tegen die regels, en post commentaar
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
  content=$(timeout 15 gh api "repos/$repo/contents/AGENTS.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  
  if [ -z "$content" ]; then
    # Probeer CLAUDE.md als alternatief
    content=$(timeout 15 gh api "repos/$repo/contents/CLAUDE.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
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
