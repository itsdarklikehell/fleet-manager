#!/usr/bin/env bash
# scripts/mcp-github-bridge.sh - GitHub MCP server bridge
# Integreert met de GitHub MCP server voor diepere integratie
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== GitHub MCP Bridge ==="

# Configuratie
MCP_ENABLED="${MCP_ENABLED:-yes}"
MCP_SERVER_NAME="${MCP_SERVER_NAME:-github}"
MCP_TIMEOUT="${MCP_TIMEOUT:-30}"

# Functies
test_mcp_connection() {
  log "Testing GitHub MCP connection..."
  
  if ! command -v hermes &>/dev/null; then
    log "  ⚠️ Hermes CLI niet beschikbaar - skipping MCP test"
    return 1
  fi
  
  local result
  result=$(hermes mcp test "$MCP_SERVER_NAME" 2>&1 || echo "")
  
  if echo "$result" | grep -qi "success\|ok\|connected"; then
    log "  ✅ GitHub MCP server verbonden"
    return 0
  else
    log "  ❌ GitHub MCP server niet verbonden: $result"
    return 1
  fi
}

load_repo_context() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Loading repository context for $repo..."
  
  # Probeer AGENTS.md te lezen
  local context
  context=$(gh api "repos/$repo/contents/AGENTS.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  
  if [ -z "$context" ]; then
    # Probeer PROJECT_INSTRUCTIONS.md
    context=$(gh api "repos/$repo/contents/PROJECT_INSTRUCTIONS.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  fi
  
  if [ -z "$context" ]; then
    # Probeer CONTRIBUTING.md
    context=$(gh api "repos/$repo/contents/CONTRIBUTING.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  fi
  
  if [ -n "$context" ]; then
    log "  ✅ Repository context geladen (${#context} chars)"
    echo "$context"
  else
    log "  ⚠️ Geen repository context gevonden"
    return 1
  fi
}

mcp_list_issues() {
  local repo="$1"
  local limit="${2:-10}"
  
  log "Listing issues via MCP for $repo..."
  
  if ! command -v hermes &>/dev/null; then
    log "  ⚠️ Hermes CLI niet beschikbaar - falling back to gh CLI"
    gh issue list --repo "$repo" --state open --limit "$limit" --json number,title,author --jq '.[] | "\(.number) \(.title) by \(.author.login)"' 2>/dev/null || echo ""
    return
  fi
  
  # Gebruik MCP server
  hermes mcp call "$MCP_SERVER_NAME" list-issues --repo "$repo" --limit "$limit" 2>/dev/null || echo ""
}

mcp_list_prs() {
  local repo="$1"
  local limit="${2:-10}"
  
  log "Listing PRs via MCP for $repo..."
  
  if ! command -v hermes &>/dev/null; then
    log "  ⚠️ Hermes CLI niet beschikbaar - falling back to gh CLI"
    gh pr list --repo "$repo" --state open --limit "$limit" --json number,title,author --jq '.[] | "\(.number) \(.title) by \(.author.login)"' 2>/dev/null || echo ""
    return
  fi
  
  # Gebruik MCP server
  hermes mcp call "$MCP_SERVER_NAME" list-pull-requests --repo "$repo" --limit "$limit" 2>/dev/null || echo ""
}

mcp_get_issue() {
  local repo="$1"
  local issue_number="$2"
  
  log "Getting issue #$issue_number via MCP for $repo..."
  
  if ! command -v hermes &>/dev/null; then
    log "  ⚠️ Hermes CLI niet beschikbaar - falling back to gh CLI"
    gh issue view "$issue_number" --repo "$repo" --json title,body,author --jq '"\(.title) by \(.author.login)\n\n\(.body)"' 2>/dev/null || echo ""
    return
  fi
  
  # Gebruik MCP server
  hermes mcp call "$MCP_SERVER_NAME" get-issue --repo "$repo" --issue "$issue_number" 2>/dev/null || echo ""
}

mcp_get_pr() {
  local repo="$1"
  local pr_number="$2"
  
  log "Getting PR #$pr_number via MCP for $repo..."
  
  if ! command -v hermes &>/dev/null; then
    log "  ⚠️ Hermes CLI niet beschikbaar - falling back to gh CLI"
    gh pr view "$pr_number" --repo "$repo" --json title,body,author --jq '"\(.title) by \(.author.login)\n\n\(.body)"' 2>/dev/null || echo ""
    return
  fi
  
  # Gebruik MCP server
  hermes mcp call "$MCP_SERVER_NAME" get-pull-request --repo "$repo" --pr "$pr_number" 2>/dev/null || echo ""
}

mcp_search_code() {
  local repo="$1"
  local query="$2"
  
  log "Searching code via MCP for $repo: $query..."
  
  if ! command -v hermes &>/dev/null; then
    log "  ⚠️ Hermes CLI niet beschikbaar - falling back to gh CLI"
    gh search code --repo "$repo" --query "$query" --json path,repository --jq '.[] | "\(.repository.name): \(.path)"' 2>/dev/null || echo ""
    return
  fi
  
  # Gebruik MCP server
  hermes mcp call "$MCP_SERVER_NAME" search-code --repo "$repo" --query "$query" 2>/dev/null || echo ""
}

# Hoofdlogica
if [ "$MCP_ENABLED" != "yes" ]; then
  log "MCP bridge uitgeschakeld"
  exit 0
fi

# Test verbinding
test_mcp_connection

# Als er een repo is opgegeven, laad dan context
if [ -n "${1:-}" ]; then
  load_repo_context "$1"
fi

log "=== GitHub MCP Bridge klaar ==="
