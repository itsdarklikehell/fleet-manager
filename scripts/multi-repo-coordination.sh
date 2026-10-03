#!/usr/bin/env bash
# scripts/multi-repo-coordination.sh - Cross-repository dependency tracking
# Detecteer inter-repo dependencies en markeer cascading changes nodig
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Multi-Repo Coordination ==="

# Configuratie
MRC_ENABLED="${MRC_ENABLED:-yes}"
MRC_DRY_RUN="${MRC_DRY_RUN:-no}"

# Function: scan for cross-repo references
scan_cross_references() {
  local repo="$1"
  local repo_dir="$REPOS_DIR/${repo//\//_}"
  
  if [ ! -d "$repo_dir" ]; then
    return
  fi
  
  cd "$repo_dir"
  
  # Scan for GitHub repo references in code
  local refs
  refs=$(grep -rohE 'github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+|npmjs\.com/package/[a-zA-Z0-9_.-@]+|pypi\.org/project/[a-zA-Z0-9_.-]+' . 2>/dev/null | sort -u || echo "")
  
  if [ -n "$refs" ]; then
    log "  Cross-repo references in $repo:"
    echo "$refs" | while read -r ref; do
      log "    - $ref"
      
      # Check if it's a GitHub repo we track
      if echo "$ref" | grep -q "github.com/[a-zA-Z0-9_-]*[a-zA-Z0-9_-]*/[a-zA-Z0-9_.-]*"; then
        local ref_repo
        ref_repo=$(echo "$ref" | sed -E 's|.*github\.com/([a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+).*|\1|')
        
        for kr in "${KEY_REPOS[@]}"; do
          if [ "$ref_repo" = "$kr" ]; then
            log "    ✅ Found dependency on tracked repo: $ref_repo"
          fi
        done
      fi
    done
  fi
}

# Function: detect cascading changes needed
detect_cascading_changes() {
  local repo="$1"
  
  log "Checking for cascading changes in $repo..."
  
  # Get recent commits
  local recent_commits
  recent_commits=$(gh api "repos/$repo/commits?per_page=5" --jq '.[].sha' 2>/dev/null || echo "")
  
  for sha in $recent_commits; do
    # Get changed files
    local changed_files
    changed_files=$(gh api "repos/$repo/commits/$sha" --jq '.files[].filename' 2>/dev/null || echo "")
    
    # Check for API/interface changes that might affect other repos
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      
      # Check file type
      case "$file" in
        *.py|*.js|*.ts|*.go|*.rs)
          log "  Potential API change: $file"
          ;;
      esac
    done <<< "$changed_files"
  done
}

# Function: post coordination alert
post_coordination_alert() {
  local repo="$1"
  local message="$2"
  
  log "Posting coordination alert to $repo..."
  
  if [ "$MRC_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would post: $message"
    return 0
  fi
  
  # Post to repo issues (could create an issue or comment on latest commit)
  gh api "repos/$repo/issues" \
    -X POST \
    -f "title=⚠️ Coordinator Alert: $repo needs attention" \
    -f "body=$message" \
    2>/dev/null || log "  ❌ Post mislukt"
}

# Hoofdlogica
if [ "$MRC_ENABLED" != "yes" ]; then
  log "Multi-repo coordination uitgeschakeld"
  exit 0
fi

for kr in "${KEY_REPOS[@]}"; do
  # Scan for cross-repo references
  scan_cross_references "$kr"
  
  # Detect cascading changes
  detect_cascading_changes "$kr"
done

log "=== Multi-Repo Coordination klaar ==="
