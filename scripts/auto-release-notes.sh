#!/usr/bin/env bash
# scripts/auto-release-notes.sh - Genereer release notes van commits
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

log "=== Auto Release Notes ==="

# Functies
usage() {
  echo "Usage: $0 <repo-name> [tag-name]"
  echo "  repo-name: Naam van de repo"
  echo "  tag-name: Tag naam (optioneel, default: latest)"
  exit 1
}

generate_release_notes() {
  local repo_name="$1"
  local tag_name="${2:-latest}"
  
  log "Generating release notes for $repo_name ($tag_name)..."
  
  local repo_dir="$REPOS_DIR/$repo_name"
  if [ ! -d "$repo_dir" ]; then
    log "ERROR: Repo not found: $repo_dir"
    return 1
  fi
  
  cd "$repo_dir"
  
  # Get commits since last tag
  local last_tag
  last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  local commits
  
  if [ -n "$last_tag" ]; then
    commits=$(git log "$last_tag"..HEAD --pretty=format:"%s" 2>/dev/null || echo "")
  else
    commits=$(git log --pretty=format:"%s" -10 2>/dev/null || echo "")
  fi
  
  if [ -z "$commits" ]; then
    log "No commits found"
    return 1
  fi
  
  # Categorize commits
  local features
  features=$(echo "$commits" | grep -iE "^feat[(:]" || true)
  local fixes
  fixes=$(echo "$commits" | grep -iE "^fix[(:]" || true)
  local docs
  docs=$(echo "$commits" | grep -iE "^docs[(:]" || true)
  local chores
  chores=$(echo "$commits" | grep -iE "^chore[(:]" || true)
  local others
  others=$(echo "$commits" | grep -ivE "^(feat|fix|docs|chore)[(:]" || true)
  
  # Generate release notes
  local release_notes="# Release Notes: $tag_name"
  release_notes+="

"
  release_notes+="Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

"
  
  if [ -n "$features" ]; then
    release_notes+="## ✨ New Features

"
    release_notes+=$(echo "$features" | sed 's/^feat[(:]*\s*/- /' | sed 's/)$//')
    release_notes+="

"
  fi
  
  if [ -n "$fixes" ]; then
    release_notes+="## 🐛 Bug Fixes

"
    release_notes+=$(echo "$fixes" | sed 's/^fix[(:]*\s*/- /' | sed 's/)$//')
    release_notes+="

"
  fi
  
  if [ -n "$docs" ]; then
    release_notes+="## 📚 Documentation

"
    release_notes+=$(echo "$docs" | sed 's/^docs[(:]*\s*/- /' | sed 's/)$//')
    release_notes+="

"
  fi
  
  if [ -n "$chores" ]; then
    release_notes+="## 🔧 Maintenance

"
    release_notes+=$(echo "$chores" | sed 's/^chore[(:]*\s*/- /' | sed 's/)$//')
    release_notes+="

"
  fi
  
  if [ -n "$others" ]; then
    release_notes+="## 📝 Other Changes

"
    release_notes+=$(echo "$others" | sed 's/^- /- /')
    release_notes+="

"
  fi
  
  # Save to file
  local output_file="$repo_dir/RELEASE_NOTES.md"
  echo -e "$release_notes" > "$output_file"
  
  log "✓ Release notes saved to: $output_file"
  
  # Create GitHub release if tag is specified
  if [ "$tag_name" != "latest" ]; then
    log "Creating GitHub release: $tag_name"
    gh release create "$tag_name" --repo "$GITHUB_OWNER/$repo_name" --notes-file "$output_file" --title "Release $tag_name" || true
  fi
}

# Main
if [ $# -lt 1 ]; then
  usage
fi

REPO_NAME="$1"
TAG_NAME="${2:-latest}"

generate_release_notes "$REPO_NAME" "$TAG_NAME"

log "=== Done ==="
