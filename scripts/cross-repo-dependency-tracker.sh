#!/usr/bin/env bash
# scripts/cross-repo-dependency-tracker.sh - Cross-repo dependency tracking
# Detecteert wanneer repo A afhankelijk is van repo B
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Cross-Repo Dependency Tracker ==="

# Functies
detect_dependencies() {
  local repo="$1"
  local deps=()
  
  # Check package.json voor dependencies
  if gh api "repos/$repo/contents/package.json" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | grep -q '"dependencies"'; then
    deps+=("npm")
  fi
  
  # Check requirements.txt voor Python dependencies
  if gh api "repos/$repo/contents/requirements.txt" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | grep -q .; then
    deps+=("pip")
  fi
  
  # Check Cargo.toml voor Rust dependencies
  if gh api "repos/$repo/contents/Cargo.toml" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | grep -q .; then
    deps+=("cargo")
  fi
  
  # Check go.mod voor Go dependencies
  if gh api "repos/$repo/contents/go.mod" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | grep -q .; then
    deps+=("go")
  fi
  
  echo "${deps[@]}"
}

build_dependency_graph() {
  local graph="{}"
  
  for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
    local deps
    deps=$(detect_dependencies "$repo")
    if [ -n "$deps" ]; then
      graph=$(echo "$graph" | jq --arg repo "$repo" --arg deps "$deps" '. + {($repo): $deps}')
    fi
  done
  
  echo "$graph"
}

# Hoofdlogica
echo "Dependency grafiek opbouwen..."
graph=$(build_dependency_graph)

# Opslaan
DEPENDENCY_GRAPH_FILE="${DEPENDENCY_GRAPH_FILE:-$HOME/.github_fleet_dependencies.json}"
echo "$graph" > "$DEPENDENCY_GRAPH_FILE"

echo "✅ Dependency grafiek opgeslagen in $DEPENDENCY_GRAPH_FILE"
echo ""
echo "Dependencies gevonden:"
echo "$graph" | jq -r 'to_entries[] | "  \(.key): \(.value | join(", "))"'
