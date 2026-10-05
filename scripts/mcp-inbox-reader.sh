#!/usr/bin/env bash
# scripts/mcp-inbox-reader.sh - Inbox reader (gh CLI only, geen MCP overhead)
# OPTIMISATIE: MCP calls vervangen door directe gh CLI (10x sneller)
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Reader (gh CLI) ==="

# Configuratie
MCP_INBOX_LIMIT="${MCP_INBOX_LIMIT:-50}"
MCP_INBOX_DAYS="${MCP_INBOX_DAYS:-7}"

SINCE=$(date -d "$MCP_INBOX_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${MCP_INBOX_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Functie: issues lezen via gh CLI
read_issues() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  Reading issues for $repo..."
  
  gh search issues --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# Functie: PRs lezen via gh CLI
read_prs() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  Reading PRs for $repo..."
  
  gh search prs --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# Functie: review requests lezen via gh CLI
read_review_requests() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  Reading review requests for $repo..."
  
  gh search prs --repo "$repo" --state open --review-requested "@me" --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# Functie: mentions lezen via gh CLI
read_mentions() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  Reading mentions for $repo..."
  
  gh search issues --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author,body \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | select(.body | test(\"@${GITHUB_USER:-itsdarklikehell}\")) | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# Hoofdlogica
echo ""
echo "📬 GitHub Inbox — Laatste $MCP_INBOX_DAYS dagen"
echo "============================================================"
echo ""

for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  echo ""
  echo "📁 $kr"
  echo "---"
  
  # Issues
  issues=$(read_issues "$kr")
  if [ -n "$issues" ]; then
    issue_count=$(echo "$issues" | wc -l)
    echo "  🐛 Issues ($issue_count):"
    echo "$issues" | sed 's/^/    /'
  else
    echo "  ✅ Geen nieuwe issues"
  fi
  
  # PRs
  prs=$(read_prs "$kr")
  if [ -n "$prs" ]; then
    pr_count=$(echo "$prs" | wc -l)
    echo "  🔄 PRs ($pr_count):"
    echo "$prs" | sed 's/^/    /'
  else
    echo "  ✅ Geen nieuwe PRs"
  fi
  
  # Review requests
  reviews=$(read_review_requests "$kr")
  if [ -n "$reviews" ]; then
    review_count=$(echo "$reviews" | wc -l)
    echo "  👀 Review requests ($review_count):"
    echo "$reviews" | sed 's/^/    /'
  else
    echo "  ✅ Geen review requests"
  fi
  
  # Mentions
  mentions=$(read_mentions "$kr")
  if [ -n "$mentions" ]; then
    mention_count=$(echo "$mentions" | wc -l)
    echo "  💬 Mentions ($mention_count):"
    echo "$mentions" | sed 's/^/    /'
  else
    echo "  ✅ Geen mentions"
  fi
done

echo ""
echo "============================================================"
echo "📬 Inbox lezen klaar"
log "=== Inbox Reader klaar ==="
