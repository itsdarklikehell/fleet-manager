#!/usr/bin/env bash
# scripts/inbox-manager.sh - GitHub Inbox Manager (GEOPTIMALISEERD)
# Werkt zonder notification scope - gebruik gh search en gh issue/pr list
# Classificeert items, voegt labels/assignees toe, antwoordt op nieuwe issues
# OPTIMISATIES: parallelisatie, rate limiting, caching, progress logging

set -euo pipefail

# DRY_RUN guard
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== GitHub Inbox Manager (search-based, geoptimaliseerd) ==="

# Configuratie
AUTO_LABEL_ENABLED="${AUTO_LABEL_ENABLED:-yes}"
AUTO_ASSIGN_ENABLED="${AUTO_ASSIGN_ENABLED:-yes}"
AUTO_REPLY_ENABLED="${AUTO_REPLY_ENABLED:-yes}"
TELEGRAM_REPORT_ENABLED="${TELEGRAM_REPORT_ENABLED:-yes}"
MAX_PARALLEL="${MAX_PARALLEL:-4}"
RATE_LIMIT_DELAY="${RATE_LIMIT_DELAY:-0.5}"

# Rate limiter
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-/tmp/github_fleet_inbox_rate_limit}"
rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - 60))
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
  if [ "$count" -ge 60 ]; then
    log "  Rate limit bereikt ($count requests/min), wacht 5s..."
    sleep 5
    echo "$now 0" > "$RATE_LIMIT_FILE"
  fi
}

# Standaard antwoorden
REPLY_BUG="🐛 Thanks for reporting this bug! I'll investigate and get back to you soon."
REPLY_FEATURE="✨ Thanks for the feature request! I'll review this and add it to the backlog."
REPLY_QUESTION="❓ Thanks for your question! I'll look into this and respond as soon as possible."
REPLY_DEFAULT="👋 Thanks for reaching out! I'll review this and get back to you soon."

# Functies
classify_item() {
  local title="$1"
  local body="${2:-}"
  local combined="$title $body"
  
  if echo "$combined" | grep -qiE "bug|fix|error|crash|broken|regression|not working|fails"; then
    echo "bug"
  elif echo "$combined" | grep -qiE "feature|enhancement|add|request|suggest|would be nice|could you"; then
    echo "feature"
  elif echo "$combined" | grep -qiE "question|how|what|why|when|where|help|wondering"; then
    echo "question"
  elif echo "$combined" | grep -qiE "doc|readme|typo|documentation"; then
    echo "documentation"
  elif echo "$combined" | grep -qiE "security|vuln|cve|exploit|injection"; then
    echo "security"
  elif echo "$combined" | grep -qiE "performance|slow|optimi|speed|memory"; then
    echo "performance"
  elif echo "$combined" | grep -qiE "test|spec|coverage"; then
    echo "testing"
  elif echo "$combined" | grep -qiE "refactor|cleanup|simplify"; then
    echo "refactor"
  elif echo "$combined" | grep -qiE "dependenc|upgrade|update|bump"; then
    echo "dependencies"
  else
    echo "other"
  fi
}

get_label_for_category() {
  local category="$1"
  case "$category" in
    bug) echo "bug" ;;
    feature) echo "enhancement" ;;
    question) echo "question" ;;
    documentation) echo "documentation" ;;
    security) echo "security" ;;
    performance) echo "performance" ;;
    testing) echo "testing" ;;
    refactor) echo "refactor" ;;
    dependencies) echo "dependencies" ;;
    *) echo "triage" ;;
  esac
}

get_assignee_for_repo() {
  local repo="$1"
  case "$repo" in
    *hermes-desktop*|*mission-control*) echo "itsdarklikehell" ;;
    *dnd-utils*) echo "itsdarklikehell" ;;
    *hermes-agent*) echo "itsdarklikehell" ;;
    *clawhub*) echo "itsdarklikehell" ;;
    *ci-templates*) echo "itsdarklikehell" ;;
    *) echo "itsdarklikehell" ;;
  esac
}

get_reply_for_category() {
  local category="$1"
  case "$category" in
    bug) echo "$REPLY_BUG" ;;
    feature) echo "$REPLY_FEATURE" ;;
    question) echo "$REPLY_QUESTION" ;;
    *) echo "$REPLY_DEFAULT" ;;
  esac
}

# Parallelle verwerkingsfunctie
process_item() {
  local item_json="$1"
  local type="$2"  # "issue" of "pr"
  
  local title repo url body number
  title=$(echo "$item_json" | jq -r '.title // "unknown"')
  repo=$(echo "$item_json" | jq -r '.repository.nameWithOwner // "unknown"')
  url=$(echo "$item_json" | jq -r '.url // ""')
  body=$(echo "$item_json" | jq -r '.body // ""')
  number=$(echo "$item_json" | jq -r '.number // ""')
  
  [ -z "$number" ] && return 0
  
  local category label
  category=$(classify_item "$title" "$body")
  label=$(get_label_for_category "$category")
  
  log "  [$type] $repo#$number: $title → $category"
  
  rate_limit_check
  
  # Label toevoegen
  if [ "$AUTO_LABEL_ENABLED" = "yes" ]; then
    if [ "$type" = "issue" ]; then
      maybe_mutate gh issue edit "$repo#$number" --add-label "$label" 2>/dev/null && log "    ✓ Label '$label'" || true
    else
      maybe_mutate gh pr edit "$repo#$number" --add-label "$label" 2>/dev/null && log "    ✓ Label '$label'" || true
    fi
  fi
  
  # Assignee toevoegen
  if [ "$AUTO_ASSIGN_ENABLED" = "yes" ]; then
    local assignee
    assignee=$(get_assignee_for_repo "$repo")
    if [ "$type" = "issue" ]; then
      maybe_mutate gh issue edit "$repo#$number" --add-assignee "$assignee" 2>/dev/null && log "    ✓ Assignee '$assignee'" || true
    else
      maybe_mutate gh pr edit "$repo#$number" --add-assignee "$assignee" 2>/dev/null && log "    ✓ Assignee '$assignee'" || true
    fi
  fi
  
  # Antwoord plaatsen
  if [ "$AUTO_REPLY_ENABLED" = "yes" ] && [ "$type" = "issue" ]; then
    local reply
    reply=$(get_reply_for_category "$category")
    maybe_mutate gh issue comment "$repo#$number" --body "$reply" 2>/dev/null && log "    ✓ Antwoord geplaatst" || true
  fi
}

# Fase 1: Eigen issues en PRs ophalen via gh search
log "Fase 1: Eigen issues en PRs ophalen via gh search..."

total_issues=0
total_prs=0
auto_labeled=0
auto_assigned=0
auto_replied=0
needs_attention=0

# Rate limit check
rate_limit_check

# Eigen issues via gh search
log "  Ophalen eigen issues via gh search..."
my_issues=$(gh search issues --state open --author @me --limit 50 --json title,repository,url,body,number 2>/dev/null || echo "[]")

# Eigen PRs via gh search
log "  Ophalen eigen PRs via gh search..."
my_prs=$(gh search prs --state open --author @me --limit 50 --json title,repository,url,body,number 2>/dev/null || echo "[]")

# Fase 2: Verwerk eigen issues en PRs parallel
log "Fase 2: Verwerk eigen issues en PRs (parallel, max=$MAX_PARALLEL)..."

# Verwerk issues
if [ "$my_issues" != "[]" ] && [ -n "$my_issues" ]; then
  echo "$my_issues" | jq -c '.[]' 2>/dev/null | while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    total_issues=$((total_issues + 1))
    
    # Wacht als te veel parallelle jobs
    while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
      sleep 0.2
    done
    
    process_item "$issue" "issue" &
  done
  wait
fi

# Verwerk PRs
if [ "$my_prs" != "[]" ] && [ -n "$my_prs" ]; then
  echo "$my_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
    [ -z "$pr" ] && continue
    total_prs=$((total_prs + 1))
    
    while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
      sleep 0.2
    done
    
    process_item "$pr" "pr" &
  done
  wait
fi

# Fase 3: Doorloop bekende repos voor open issues en PRs
log "Fase 3: Doorloop bekende repos (parallel)..."

for repo in "${KEY_REPOS[@]}"; do
  log "  Repo: $repo"
  
  rate_limit_check
  
  # Open issues
  repo_issues=$(gh issue list --repo "$repo" --state open --limit 20 --json title,number,body,url 2>/dev/null || echo "[]")
  if [ "$repo_issues" != "[]" ] && [ -n "$repo_issues" ]; then
    echo "$repo_issues" | jq -c '.[]' 2>/dev/null | while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      total_issues=$((total_issues + 1))
      
      while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
        sleep 0.2
      done
      
      process_item "$issue" "issue" &
    done
  fi
  
  rate_limit_check
  
  # Open PRs
  repo_prs=$(gh pr list --repo "$repo" --state open --limit 20 --json title,number,body,url 2>/dev/null || echo "[]")
  if [ "$repo_prs" != "[]" ] && [ -n "$repo_prs" ]; then
    echo "$repo_prs" | jq -c '.[]' 2>/dev/null | while IFS= read -r pr; do
      [ -z "$pr" ] && continue
      total_prs=$((total_prs + 1))
      
      while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
        sleep 0.2
      done
      
      process_item "$pr" "pr" &
    done
  fi
done
wait

# Fase 4: Samenvatting
log "Fase 4: Samenvatting..."
log "  Totaal issues verwerkt: $total_issues"
log "  Totaal PRs verwerkt: $total_prs"
log "  Automatisch labels toegevoegd: $auto_labeled"
log "  Automatisch assignees toegevoegd: $auto_assigned"
log "  Automatisch antwoorden geplaatst: $auto_replied"
log "  Nodig aandacht: $needs_attention"

log "=== GitHub Inbox Manager complete ==="

# Telegram rapportage
if [ "$TELEGRAM_REPORT_ENABLED" = "yes" ]; then
  send_telegram_message "📬 *GitHub Inbox Manager* (search-based, geoptimaliseerd)

*Issues verwerkt:* $total_issues
*PRs verwerkt:* $total_prs
*Labels toegevoegd:* $auto_labeled
*Assignees toegevoegd:* $auto_assigned
*Antwoorden geplaatst:* $auto_replied
*Aandacht nodig:* $needs_attention

📋 Volledig log: $LOG_FILE" || true
fi
