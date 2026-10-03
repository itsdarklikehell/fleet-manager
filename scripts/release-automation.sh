#!/usr/bin/env bash
# scripts/release-automation.sh - Release automation op basis van conventional commits
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Release Automation ==="

# Configuratie
RA_ENABLED="${RA_ENABLED:-yes}"
RA_DRY_RUN="${RA_DRY_RUN:-yes}"
RA_REPO="${RA_REPO:-}"
RA_ORG="${RA_ORG:-itsdarklikehell}"

# Functies
get_conventional_commits() {
  local repo="$1"
  local since_tag="${2:-}"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Fetching conventional commits for $repo..."
  
  local commits
  if [ -n "$since_tag" ]; then
    commits=$(gh api "repos/$repo/compare/$since_tag...main" --jq '.commits[] | "\(.commit.message)"' 2>/dev/null || echo "")
  else
    commits=$(gh api "repos/$repo/commits?per_page=50" --jq '.[] | "\(.commit.message)"' 2>/dev/null || echo "")
  fi
  
  echo "$commits"
}

categorize_commits() {
  local commits="$1"
  
  local features=""
  local fixes=""
  local docs=""
  local styles=""
  local refactors=""
  local perfs=""
  local tests=""
  local chores=""
  local others=""
  
  while IFS= read -r line; do
    if echo "$line" | grep -qiE "^feat(\(.+\))?: "; then
      features="${features}${line}\n"
    elif echo "$line" | grep -qiE "^fix(\(.+\))?: "; then
      fixes="${fixes}${line}\n"
    elif echo "$line" | grep -qiE "^docs(\(.+\))?: "; then
      docs="${docs}${line}\n"
    elif echo "$line" | grep -qiE "^style(\(.+\))?: "; then
      styles="${styles}${line}\n"
    elif echo "$line" | grep -qiE "^refactor(\(.+\))?: "; then
      refactors="${refactors}${line}\n"
    elif echo "$line" | grep -qiE "^perf(\(.+\))?: "; then
      perfs="${perfs}${line}\n"
    elif echo "$line" | grep -qiE "^test(\(.+\))?: "; then
      tests="${tests}${line}\n"
    elif echo "$line" | grep -qiE "^chore(\(.+\))?: "; then
      chores="${chores}${line}\n"
    else
      others="${others}${line}\n"
    fi
  done <<< "$commits"
  
  echo -e "features:$features"
  echo -e "fixes:$fixes"
  echo -e "docs:$docs"
  echo -e "styles:$styles"
  echo -e "refactors:$refactors"
  echo -e "perfs:$perfs"
  echo -e "tests:$tests"
  echo -e "chores:$chores"
  echo -e "others:$others"
}

generate_release_notes() {
  local repo="$1"
  local version="$2"
  local commits="$3"
  
  log "Generating release notes for $repo v$version..."
  
  local notes=""
  notes="# Release v$version\n\n"
  notes+="## 🚀 Features\n\n"
  
  # Categoriseer commits
  local categorized
  categorized=$(categorize_commits "$commits")
  
  # Voeg features toe
  local features
  features=$(echo "$categorized" | grep "^features:" | cut -d: -f2-)
  if [ -n "$features" ]; then
    notes+=$(echo -e "$features" | sed 's/^/- /')
    notes+="\n\n"
  fi
  
  # Voeg fixes toe
  local fixes
  fixes=$(echo "$categorized" | grep "^fixes:" | cut -d: -f2-)
  if [ -n "$fixes" ]; then
    notes+="## 🐛 Bug Fixes\n\n"
    notes+=$(echo -e "$fixes" | sed 's/^/- /')
    notes+="\n\n"
  fi
  
  # Voeg docs toe
  local docs
  docs=$(echo "$categorized" | grep "^docs:" | cut -d: -f2-)
  if [ -n "$docs" ]; then
    notes+="## 📚 Documentation\n\n"
    notes+=$(echo -e "$docs" | sed 's/^/- /')
    notes+="\n\n"
  fi
  
  # Voeg refactors toe
  local refactors
  refactors=$(echo "$categorized" | grep "^refactors:" | cut -d: -f2-)
  if [ -n "$refactors" ]; then
    notes+="## ♻️ Code Refactoring\n\n"
    notes+=$(echo -e "$refactors" | sed 's/^/- /')
    notes+="\n\n"
  fi
  
  # Voeg perfs toe
  local perfs
  perfs=$(echo "$categorized" | grep "^perfs:" | cut -d: -f2-)
  if [ -n "$perfs" ]; then
    notes+="## ⚡ Performance Improvements\n\n"
    notes+=$(echo -e "$perfs" | sed 's/^/- /')
    notes+="\n\n"
  fi
  
  # Voeg tests toe
  local tests
  tests=$(echo "$categorized" | grep "^tests:" | cut -d: -f2-)
  if [ -n "$tests" ]; then
    notes+="## ✅ Tests\n\n"
    notes+=$(echo -e "$tests" | sed 's/^/- /')
    notes+="\n\n"
  fi
  
  # Voeg chores toe
  local chores
  chores=$(echo "$categorized" | grep "^chores:" | cut -d: -f2-)
  if [ -n "$chores" ]; then
    notes+="## 🔧 Maintenance\n\n"
    notes+=$(echo -e "$chores" | sed 's/^/- /')
    notes+="\n\n"
  fi
  
  echo -e "$notes"
}

create_release() {
  local repo="$1"
  local version="$2"
  local notes="$3"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating release v$version for $repo..."
  
  if [ "$RA_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create release: v$version"
    return 0
  fi
  
  gh release create "v$version" \
    --repo "$repo" \
    --title "v$version" \
    --notes "$notes" \
    --latest 2>/dev/null && log "  ✅ Release v$version aangemaakt" || log "  ❌ Kon release niet aanmaken"
}

bump_version() {
  local current_version="$1"
  
  # Semver bump: patch
  local major minor patch
  major=$(echo "$current_version" | cut -d. -f1 | tr -d 'v')
  minor=$(echo "$current_version" | cut -d. -f2)
  patch=$(echo "$current_version" | cut -d. -f3)
  
  patch=$((patch + 1))
  echo "v${major}.${minor}.${patch}"
}

# Hoofdlogica
if [ "$RA_ENABLED" != "yes" ]; then
  log "Release automation uitgeschakeld"
  exit 0
fi

if [ -z "$RA_REPO" ]; then
  log "RA_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting release automation for $RA_REPO..."

# Haal huidige versie op
current_version=$(gh release view --repo "$RA_REPO" --json tagName --jq '.tagName' 2>/dev/null || echo "v0.0.0")
new_version=$(bump_version "$current_version")

log "Current: $current_version → New: $new_version"

# Haal commits op
commits=$(get_conventional_commits "$RA_REPO" "$current_version")

# Genereer release notes
notes=$(generate_release_notes "$RA_REPO" "$new_version" "$commits")

# Maak release
create_release "$RA_REPO" "$new_version" "$notes"

log "=== Release Automation klaar ==="
