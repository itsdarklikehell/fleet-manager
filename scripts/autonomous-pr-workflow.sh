#!/usr/bin/env bash
# scripts/autonomous-pr-workflow.sh - Autonomous PR workflow
# Maakt branches, schrijft code, commit, pusht, en opent PRs
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Autonomous PR Workflow ==="

# Configuratie
APR_ENABLED="${APR_ENABLED:-no}"
APR_DRY_RUN="${APR_DRY_RUN:-yes}"
APR_REPO="${APR_REPO:-}"
APR_BRANCH="${APR_BRANCH:-}"
APR_TITLE="${APR_TITLE:-}"
APR_BODY="${APR_BODY:-}"
APR_FILES="${APR_FILES:-}"

# Functies
create_branch() {
  local repo="$1"
  local branch="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating branch '$branch' in $repo..."
  
  if [ "$APR_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create branch: $branch"
    return 0
  fi
  
  # Check of branch al bestaat
  if gh api "repos/$repo/branches/$branch" --jq '.name' 2>/dev/null | grep -q "$branch"; then
    log "  ⚠️ Branch '$branch' bestaat al"
    return 1
  fi
  
  # Haal laatste commit SHA op
  local sha
  sha=$(gh api "repos/$repo/commits/main" --jq '.sha' 2>/dev/null || echo "")
  
  if [ -z "$sha" ]; then
    log "  ❌ Kon laatste commit SHA niet ophalen"
    return 1
  fi
  
  # Maak branch
  gh api "repos/$repo/git/refs" \
    -X POST \
    -f "ref=refs/heads/$branch" \
    -f "sha=$sha" \
    --jq '.ref' 2>/dev/null && log "  ✅ Branch '$branch' aangemaakt" || log "  ❌ Kon branch niet aanmaken"
}

commit_and_push() {
  local repo="$1"
  local branch="$2"
  local message="$3"
  local files="$4"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Committing and pushing to '$branch' in $repo..."
  
  if [ "$APR_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would commit and push: $message"
    return 0
  fi
  
  # Push files via API
  for file in $files; do
    local content
    content=$(base64 -w0 "$file" 2>/dev/null || echo "")
    local path
    path=$(basename "$file")
    
    gh api "repos/$repo/contents/$path" \
      -X PUT \
      -f "message=$message" \
      -f "content=$content" \
      -f "branch=$branch" \
      --jq '.content.path' 2>/dev/null && log "  ✅ Pushed: $path" || log "  ❌ Kon niet pushen: $path"
  done
}

create_pull_request() {
  local repo="$1"
  local branch="$2"
  local title="$3"
  local body="$4"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating PR in $repo..."
  
  if [ "$APR_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create PR: $title"
    return 0
  fi
  
  gh pr create \
    --repo "$repo" \
    --head "$branch" \
    --base "main" \
    --title "$title" \
    --body "$body" \
    --json number,url --jq '"PR #\(.number): \(.url)"' 2>/dev/null && log "  ✅ PR aangemaakt" || log "  ❌ Kon PR niet aanmaken"
}

# Hoofdlogica
if [ "$APR_ENABLED" != "yes" ]; then
  log "Autonomous PR workflow uitgeschakeld"
  exit 0
fi

if [ -z "$APR_REPO" ] || [ -z "$APR_BRANCH" ] || [ -z "$APR_TITLE" ]; then
  log "APR_REPO, APR_BRANCH en APR_TITLE zijn vereist"
  exit 1
fi

log "Starting autonomous PR workflow for $APR_REPO..."

# Stap 1: Maak branch
create_branch "$APR_REPO" "$APR_BRANCH"

# Stap 2: Commit en push
commit_and_push "$APR_REPO" "$APR_BRANCH" "feat: $APR_TITLE" "$APR_FILES"

# Stap 3: Maak PR
create_pull_request "$APR_REPO" "$APR_BRANCH" "$APR_TITLE" "$APR_BODY"

log "=== Autonomous PR Workflow klaar ==="
