#!/usr/bin/env bash
# scripts/release-publishing.sh - Automatische release publishing
# Maak GitHub releases op basis van versie tags en commit messages
set -euo pipefail
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Release Publishing ==="

# Configuratie
RP_ENABLED="${RP_ENABLED:-yes}"
RP_DRY_RUN="${RP_DRY_RUN:-no}"
RP_REPOS="${RP_REPOS:-}"

# Parse semver tags
parse_version() {
  local tag="$1"
  # Extract version number
  echo "$tag" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | tr -d 'v'
}

# Get latest release tag
get_latest_release() {
  local repo="$1"
  local latest
  latest=$(gh api "repos/$repo/releases/latest" --jq '.tag_name' 2>/dev/null || echo "")
  echo "$latest"
}

# Get latest commit message
get_latest_commit_message() {
  local repo="$1"
  local msg
  msg=$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].commit.message' 2>/dev/null || echo "")
  echo "$msg"
}

# Generate release notes from commits
generate_release_notes() {
  local repo="$1"
  local old_tag="$2"
  local new_tag="$3"
  
  local range="${old_tag}..${new_tag}"
  
  if [ -z "$old_tag" ] || [ "$old_tag" = "null" ]; then
    range="HEAD~10..${new_tag}"
  fi
  
  local commits
  commits=$(gh api "repos/$repo/compare/${range}" --jq '.commits[] | "- \(.commit.message | split("\\n")[0])"' 2>/dev/null || echo "")
  
  local notes
  notes=$(cat << 'EOF'
## 📦 Release Notes

### Features
- Nieuwe functionaliteit toegevoegd

### Bug Fixes
- Bugfixes uitgevoerd

### Commits
EOF
)
  
  if [ -n "$commits" ]; then
    notes="${notes}
${commits}"
  fi
  
  notes="${notes}

---
*Automatisch gegenereerd door Fleet Manager*"
  
  echo "$notes"
}

# Create release
create_release() {
  local repo="$1"
  local tag="$2"
  local notes="$3"
  
  log "  Creating release $tag for $repo..."
  
  if [ "$RP_DRY_RUN" = "yes" ]; then
    log "    [DRY RUN] Would create release $tag"
    return 0
  fi
  
  local result
  result=$(gh api "repos/$repo/releases" \
    -X POST \
    -f "tag_name=$tag" \
    -f "name=$tag" \
    -f "body=$notes" \
    -f "draft=false" \
    -f "prerelease=false" \
    2>&1 || echo "")
  
  if echo "$result" | grep -qi '"html_url"'; then
    local url
    url=$(echo "$result" | grep -oE '"html_url":.*' | cut -d'"' -f4)
    log "    ✅ Release aangemaakt: $url"
  else
    log "    ❌ Release mislukt: $result"
  fi
}

# Check for new version tags
check_new_releases() {
  local repo="$1"
  
  local latest_release
  latest_release=$(get_latest_release "$repo")
  
  # Get tags
  local tags
  tags=$(gh api "repos/$repo/tags" --jq '.[].name' 2>/dev/null || echo "")
  
  if [ -z "$tags" ]; then
    log "  ℹ️ Geen tags gevonden voor $repo"
    return
  fi
  
  for tag in $tags; do
    # Skip if already released
    if [ -n "$latest_release" ] && [ "$tag" = "$latest_release" ]; then
      log "  ℹ️ Release $tag al gemaakt"
      continue
    fi
    
    # Check if it's a version tag
    local version
    version=$(parse_version "$tag")
    if [ -z "$version" ]; then
      continue
    fi
    
    log "  Nieuwe release gevonden: $tag ($version)"
    
    # Check if release exists
    local release_exists
    release_exists=$(gh api "repos/$repo/releases/tags/$tag" --jq '.id' 2>/dev/null || echo "")
    
    if [ -z "$release_exists" ]; then
      # Generate and create release
      local notes
      notes=$(generate_release_notes "$repo" "$latest_release" "$tag")
      create_release "$repo" "$tag" "$notes"
    else
      log "    ℹ️ Release $tag bestaat al"
    fi
  done
}

# Hoofdlogica
if [ "$RP_ENABLED" != "yes" ]; then
  log "Release publishing uitgeschakeld"
  exit 0
fi

# Determine which repos to release
if [ -n "$RP_REPOS" ]; then
  IFS=',' read -ra RELEASE_REPOS <<< "$RP_REPOS"
else
  RELEASE_REPOS=("${KEY_REPOS[@]}")
fi

for kr in "${RELEASE_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  log "Checking releases for $kr..."
  check_new_releases "$kr"
done

log "=== Release Publishing klaar ==="
