#!/usr/bin/env bash
# scripts/cross-repo-dependency-tracker.sh - Track dependencies tussen repos
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

log "=== Cross-Repo Dependency Tracker ==="

# Functies
scan_dependencies() {
  local repo_dir="$1"
  local repo_name=$(basename "$repo_dir")
  
  log "Scanning $repo_name for dependencies..."
  
  # Check for package.json (Node.js)
  if [ -f "$repo_dir/package.json" ]; then
    local deps=$(jq -r '.dependencies // {} | keys[]' "$repo_dir/package.json" 2>/dev/null || true)
    if [ -n "$deps" ]; then
      log "  Node.js dependencies:"
      echo "$deps" | while read -r dep; do
        log "    - $dep"
      done
    fi
  fi
  
  # Check for requirements.txt (Python)
  if [ -f "$repo_dir/requirements.txt" ]; then
    local deps=$(grep -E '^[a-zA-Z]' "$repo_dir/requirements.txt" 2>/dev/null || true)
    if [ -n "$deps" ]; then
      log "  Python dependencies:"
      echo "$deps" | while read -r dep; do
        log "    - $dep"
      done
    fi
  fi
  
  # Check for Cargo.toml (Rust)
  if [ -f "$repo_dir/Cargo.toml" ]; then
    local deps=$(grep -E '^[a-zA-Z].*=' "$repo_dir/Cargo.toml" 2>/dev/null || true)
    if [ -n "$deps" ]; then
      log "  Rust dependencies:"
      echo "$deps" | while read -r dep; do
        log "    - $dep"
      done
    fi
  fi
  
  # Check for go.mod (Go)
  if [ -f "$repo_dir/go.mod" ]; then
    local deps=$(grep -E '^\s+[a-zA-Z]' "$repo_dir/go.mod" 2>/dev/null || true)
    if [ -n "$deps" ]; then
      log "  Go dependencies:"
      echo "$deps" | while read -r dep; do
        log "    - $dep"
      done
    fi
  fi
}

generate_dependency_graph() {
  log "Generating dependency graph..."
  
  local output_file="$REPOS_DIR/dependency-graph.md"
  echo "# Dependency Graph" > "$output_file"
  echo "" >> "$output_file"
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$output_file"
  echo "" >> "$output_file"
  
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    local repo_name=$(basename "$repo_dir")
    
    echo "## $repo_name" >> "$output_file"
    echo "" >> "$output_file"
    
    # Check for package.json
    if [ -f "$repo_dir/package.json" ]; then
      echo "### Node.js" >> "$output_file"
      echo '```json' >> "$output_file"
      jq '.dependencies // {}' "$repo_dir/package.json" 2>/dev/null || echo "{}" >> "$output_file"
      echo '```' >> "$output_file"
      echo "" >> "$output_file"
    fi
    
    # Check for requirements.txt
    if [ -f "$repo_dir/requirements.txt" ]; then
      echo "### Python" >> "$output_file"
      echo '```' >> "$output_file"
      cat "$repo_dir/requirements.txt" >> "$output_file"
      echo '```' >> "$output_file"
      echo "" >> "$output_file"
    fi
    
    echo "---" >> "$output_file"
    echo "" >> "$output_file"
  done
  
  log "✓ Dependency graph saved to: $output_file"
}

# Main
log "Scanning all repos for dependencies..."

for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  scan_dependencies "$repo_dir"
done

generate_dependency_graph

log "=== Done ==="
