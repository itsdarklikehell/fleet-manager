#!/usr/bin/env bash
# scripts/mcp-inbox-reader.sh - MCP-gebaseerde inbox reader
# Gebruikt GitHub MCP server voor diepere integratie
set -euo pipefail
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== MCP Inbox Reader ==="

# Configuratie
MCP_INBOX_ENABLED="${MCP_INBOX_ENABLED:-yes}"
MCP_INBOX_LIMIT="${MCP_INBOX_LIMIT:-50}"
MCP_INBOX_DAYS="${MCP_INBOX_DAYS:-7}"

SINCE=$(date -d "$MCP_INBOX_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${MCP_INBOX_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Functie: MCP call helper
mcp_call() {
  local tool="$1"
  shift
  
  if command -v hermes &>/dev/null; then
    hermes mcp call github "$tool" "$@" 2>/dev/null || echo ""
  else
    log "  ⚠️ Geen MCP client beschikbaar - falling back to gh CLI"
    return 1
  fi
}

# MCP-based issue reading met fallback
mcp_read_issues() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  MCP: Reading issues for $repo..."
  
  # Probeer MCP eerst
  if mcp_result=$(mcp_call list_issues --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" 2>/dev/null) && [ -n "$mcp_result" ]; then
    echo "$mcp_result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data:
        created = item.get('createdAt', '')
        if created >= '${SINCE}':
            print(f\"{created[:10]} {item.get('title', 'N/A')} by {item.get('author', {}).get('login', 'N/A')}\")
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  
  # Fallback naar gh CLI
  gh search issues --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# MCP-based PR reading met fallback
mcp_read_prs() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  MCP: Reading PRs for $repo..."
  
  if mcp_result=$(mcp_call list_pull_requests --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" 2>/dev/null) && [ -n "$mcp_result" ]; then
    echo "$mcp_result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data:
        created = item.get('createdAt', '')
        if created >= '${SINCE}':
            print(f\"{created[:10]} {item.get('title', 'N/A')} by {item.get('author', {}).get('login', 'N/A')}\")
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  
  gh search prs --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# MCP-based review requests met fallback
mcp_read_review_requests() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  MCP: Reading review requests for $repo..."
  
  if mcp_result=$(mcp_call list_pull_requests --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" --reviewers "@me" 2>/dev/null) && [ -n "$mcp_result" ]; then
    echo "$mcp_result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data:
        created = item.get('createdAt', '')
        if created >= '${SINCE}':
            reviewers = item.get('reviewRequests', {}).get('nodes', [])
            if reviewers:
                print(f\"{created[:10]} {item.get('title', 'N/A')} by {item.get('author', {}).get('login', 'N/A')}\")
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  
  gh search prs --repo "$repo" --state open --review-requested "@me" --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# MCP-based mentions met fallback
mcp_read_mentions() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "  MCP: Reading mentions for $repo..."
  
  # Probeer MCP code search eerst
  if mcp_result=$(mcp_call search_code --repo "$repo" --query "@${GITHUB_USER:-itsdarklikehell}" --limit "$MCP_INBOX_LIMIT" 2>/dev/null) && [ -n "$mcp_result" ]; then
    echo "$mcp_result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data:
        print(f\"{item.get('name', 'N/A')} - {item.get('path', 'N/A')}\")
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  
  gh search issues --repo "$repo" --state open --limit "$MCP_INBOX_LIMIT" \
    --json title,createdAt,url,author,body \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | select(.body | test(\"@${GITHUB_USER:-itsdarklikehell}\")) | \"\(.createdAt[:10]) \(.title) by \(.author.login)\"" \
    2>/dev/null || echo ""
}

# Hoofdlogica
if [ "$MCP_INBOX_ENABLED" != "yes" ]; then
  log "MCP inbox reader uitgeschakeld"
  exit 0
fi

echo ""
echo "📬 GitHub Inbox (MCP-enhanced) — Laatste $MCP_INBOX_DAYS dagen"
echo "============================================================"
echo ""

for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  echo ""
  echo "📁 $kr"
  echo "---"
  
  # Issues
  issues=$(mcp_read_issues "$kr")
  if [ -n "$issues" ]; then
    issue_count=$(echo "$issues" | wc -l)
    echo "  🐛 Issues ($issue_count):"
    echo "$issues" | sed 's/^/    /'
  else
    echo "  ✅ Geen nieuwe issues"
  fi
  
  # PRs
  prs=$(mcp_read_prs "$kr")
  if [ -n "$prs" ]; then
    pr_count=$(echo "$prs" | wc -l)
    echo "  🔄 PRs ($pr_count):"
    echo "$prs" | sed 's/^/    /'
  else
    echo "  ✅ Geen nieuwe PRs"
  fi
  
  # Review requests
  reviews=$(mcp_read_review_requests "$kr")
  if [ -n "$reviews" ]; then
    review_count=$(echo "$reviews" | wc -l)
    echo "  👀 Review requests ($review_count):"
    echo "$reviews" | sed 's/^/    /'
  else
    echo "  ✅ Geen review requests"
  fi
  
  # Mentions
  mentions=$(mcp_read_mentions "$kr")
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
log "=== MCP Inbox Reader klaar ==="
