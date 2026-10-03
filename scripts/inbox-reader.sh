#!/usr/bin/env bash
# scripts/inbox-reader.sh - Leest GitHub inbox via gh search
# Gebruikt gh search issues/prs om de inbox te lezen zonder notifications scope
set -euo pipefail
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== GitHub Inbox Reader (search-based) ==="

# Configuratie
INBOX_REPOS="${INBOX_REPOS:-${KEY_REPOS[@]}}"
INBOX_LIMIT="${INBOX_LIMIT:-50}"
INBOX_DAYS="${INBOX_DAYS:-7}"

SINCE=$(date -d "$INBOX_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${INBOX_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Functies
read_inbox_issues() {
  log "Fase 1: Inbox issues (laatste $INBOX_DAYS dagen)..."
  
  local total=0
  for kr in "${INBOX_REPOS[@]}"; do
    org="${kr%%/*}"
    set_repo_token "$org"
    
    local issues
    issues=$(gh search issues --repo "$kr" --state open --limit "$INBOX_LIMIT" --json title,createdAt,url,author --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" 2>/dev/null || echo "")
    
    if [ -n "$issues" ]; then
      local count
      count=$(echo "$issues" | wc -l)
      total=$((total + count))
      log "  $kr: $count issues"
      echo "$issues" | while read -r line; do
        log "    $line"
      done
    fi
  done
  log "Totaal: $total issues"
}

read_inbox_prs() {
  log "Fase 2: Inbox PRs (laatste $INBOX_DAYS dagen)..."
  
  local total=0
  for kr in "${INBOX_REPOS[@]}"; do
    org="${kr%%/*}"
    set_repo_token "$org"
    
    local prs
    prs=$(gh search prs --repo "$kr" --state open --limit "$INBOX_LIMIT" --json title,createdAt,url,author --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" 2>/dev/null || echo "")
    
    if [ -n "$prs" ]; then
      local count
      count=$(echo "$prs" | wc -l)
      total=$((total + count))
      log "  $kr: $count PRs"
      echo "$prs" | while read -r line; do
        log "    $line"
      done
    fi
  done
  log "Totaal: $total PRs"
}

read_inbox_mentions() {
  log "Fase 3: Inbox mentions (laatste $INBOX_DAYS dagen)..."
  
  local total=0
  for kr in "${INBOX_REPOS[@]}"; do
    org="${kr%%/*}"
    set_repo_token "$org"
    
    local mentions
    mentions=$(gh search issues --repo "$kr" --state open --limit "$INBOX_LIMIT" --json title,createdAt,url,author --jq ".[] | select(.createdAt >= \"${SINCE}\") | select(.body | test(\"@${GITHUB_USER:-itsdarklikehell}\")) | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" 2>/dev/null || echo "")
    
    if [ -n "$mentions" ]; then
      local count
      count=$(echo "$mentions" | wc -l)
      total=$((total + count))
      log "  $kr: $count mentions"
      echo "$mentions" | while read -r line; do
        log "    $line"
      done
    fi
  done
  log "Totaal: $total mentions"
}

read_inbox_reviews() {
  log "Fase 4: Inbox review requests (laatste $INBOX_DAYS dagen)..."
  
  local total=0
  for kr in "${INBOX_REPOS[@]}"; do
    org="${kr%%/*}"
    set_repo_token "$org"
    
    local reviews
    reviews=$(gh search prs --repo "$kr" --state open --review-requested "@me" --limit "$INBOX_LIMIT" --json title,createdAt,url,author --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" 2>/dev/null || echo "")
    
    if [ -n "$reviews" ]; then
      local count
      count=$(echo "$reviews" | wc -l)
      total=$((total + count))
      log "  $kr: $count review requests"
      echo "$reviews" | while read -r line; do
        log "    $line"
      done
    fi
  done
  log "Totaal: $total review requests"
}

# Hoofdlogica
read_inbox_issues
read_inbox_prs
read_inbox_mentions
read_inbox_reviews

log "=== Inbox Reader klaar ==="
