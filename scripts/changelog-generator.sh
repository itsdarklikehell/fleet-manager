#!/usr/bin/env bash
# scripts/changelog-generator.sh - Automatische CHANGELOG.md generatie
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Changelog Generator ==="

# Configuratie
CG_ENABLED="${CG_ENABLED:-yes}"
CG_DRY_RUN="${CG_DRY_RUN:-yes}"
CG_REPO="${CG_REPO:-}"
CG_ORG="${CG_ORG:-itsdarklikehell}"

# Functies
get_commits_since_last_release() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Fetching commits for $repo..."
  
  # Haal laatste release tag op
  local last_tag
  last_tag=$(gh release view --repo "$repo" --json tagName --jq '.tagName' 2>/dev/null || echo "")
  
  local commits
  if [ -n "$last_tag" ]; then
    commits=$(gh api "repos/$repo/compare/$last_tag...main" --jq '.commits[] | "\(.commit.message)"' 2>/dev/null || echo "")
  else
    commits=$(gh api "repos/$repo/commits?per_page=100" --jq '.[] | "\(.commit.message)"' 2>/dev/null || echo "")
  fi
  
  echo "$commits"
}

parse_conventional_commit() {
  local message="$1"
  
  # Parse conventional commit format: type(scope): description
  local type scope description
  
  if echo "$message" | grep -qiE "^feat(\(.+\))?: "; then
    type="feat"
    scope=$(echo "$message" | sed -n 's/^feat(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^feat(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^feat: \(.*\)/\1/p')
  elif echo "$message" | grep -qiE "^fix(\(.+\))?: "; then
    type="fix"
    scope=$(echo "$message" | sed -n 's/^fix(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^fix(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^fix: \(.*\)/\1/p')
  elif echo "$message" | grep -qiE "^docs(\(.+\))?: "; then
    type="docs"
    scope=$(echo "$message" | sed -n 's/^docs(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^docs(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^docs: \(.*\)/\1/p')
  elif echo "$message" | grep -qiE "^style(\(.+\))?: "; then
    type="style"
    scope=$(echo "$message" | sed -n 's/^style(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^style(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^style: \(.*\)/\1/p')
  elif echo "$message" | grep -qiE "^refactor(\(.+\))?: "; then
    type="refactor"
    scope=$(echo "$message" | sed -n 's/^refactor(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^refactor(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^refactor: \(.*\)/\1/p')
  elif echo "$message" | grep -qiE "^perf(\(.+\))?: "; then
    type="perf"
    scope=$(echo "$message" | sed -n 's/^perf(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^perf(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^perf: \(.*\)/\1/p')
  elif echo "$message" | grep -qiE "^test(\(.+\))?: "; then
    type="test"
    scope=$(echo "$message" | sed -n 's/^test(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^test(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^test: \(.*\)/\1/p')
  elif echo "$message" | grep -qiE "^chore(\(.+\))?: "; then
    type="chore"
    scope=$(echo "$message" | sed -n 's/^chore(\([^)]*\)):.*/\1/p')
    description=$(echo "$message" | sed -n 's/^chore(\([^)]*\)): \(.*\)/\2/p')
    [ -z "$description" ] && description=$(echo "$message" | sed -n 's/^chore: \(.*\)/\1/p')
  else
    type="other"
    scope=""
    description="$message"
  fi
  
  echo "$type|$scope|$description"
}

generate_changelog() {
  local repo="$1"
  local commits="$2"
  
  log "Generating CHANGELOG.md for $repo..."
  
  local changelog="# Changelog\n\n"
  changelog+="All notable changes to this project will be documented in this file.\n\n"
  changelog+="The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).\n\n"
  
  # Categoriseer commits
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
    [ -z "$line" ] && continue
    
    local parsed
    parsed=$(parse_conventional_commit "$line")
    local type scope description
    type=$(echo "$parsed" | cut -d'|' -f1)
    scope=$(echo "$parsed" | cut -d'|' -f2)
    description=$(echo "$parsed" | cut -d'|' -f3)
    
    local entry="- $description"
    [ -n "$scope" ] && entry="$entry ($scope)"
    
    case "$type" in
      feat) features="${features}${entry}\n" ;;
      fix) fixes="${fixes}${entry}\n" ;;
      docs) docs="${docs}${entry}\n" ;;
      style) styles="${styles}${entry}\n" ;;
      refactor) refactors="${refactors}${entry}\n" ;;
      perf) perfs="${perfs}${entry}\n" ;;
      test) tests="${tests}${entry}\n" ;;
      chore) chores="${chores}${entry}\n" ;;
      *) others="${others}${entry}\n" ;;
    esac
  done <<< "$commits"
  
  # Voeg secties toe
  if [ -n "$features" ]; then
    changelog+="## 🚀 Features\n\n"
    changelog+=$(echo -e "$features")
    changelog+="\n"
  fi
  
  if [ -n "$fixes" ]; then
    changelog+="## 🐛 Bug Fixes\n\n"
    changelog+=$(echo -e "$fixes")
    changelog+="\n"
  fi
  
  if [ -n "$docs" ]; then
    changelog+="## 📚 Documentation\n\n"
    changelog+=$(echo -e "$docs")
    changelog+="\n"
  fi
  
  if [ -n "$styles" ]; then
    changelog+="## 💎 Styles\n\n"
    changelog+=$(echo -e "$styles")
    changelog+="\n"
  fi
  
  if [ -n "$refactors" ]; then
    changelog+="## ♻️ Code Refactoring\n\n"
    changelog+=$(echo -e "$refactors")
    changelog+="\n"
  fi
  
  if [ -n "$perfs" ]; then
    changelog+="## ⚡ Performance Improvements\n\n"
    changelog+=$(echo -e "$perfs")
    changelog+="\n"
  fi
  
  if [ -n "$tests" ]; then
    changelog+="## ✅ Tests\n\n"
    changelog+=$(echo -e "$tests")
    changelog+="\n"
  fi
  
  if [ -n "$chores" ]; then
    changelog+="## 🔧 Maintenance\n\n"
    changelog+=$(echo -e "$chores")
    changelog+="\n"
  fi
  
  if [ -n "$others" ]; then
    changelog+="## 📦 Other Changes\n\n"
    changelog+=$(echo -e "$others")
    changelog+="\n"
  fi
  
  echo -e "$changelog"
}

update_changelog_file() {
  local repo="$1"
  local changelog="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Updating CHANGELOG.md for $repo..."
  
  if [ "$CG_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would update CHANGELOG.md"
    return 0
  fi
  
  # Check of CHANGELOG.md bestaat
  local existing
  existing=$(gh api "repos/$repo/contents/CHANGELOG.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  
  if [ -n "$existing" ]; then
    # Update bestaand bestand
    local content
    content=$(echo -e "$changelog" | base64 -w0)
    gh api "repos/$repo/contents/CHANGELOG.md" \
      -X PUT \
      -f "message=docs: update CHANGELOG.md" \
      -f "content=$content" \
      -f "branch=main" \
      --jq '.content.path' 2>/dev/null && log "  ✅ CHANGELOG.md bijgewerkt" || log "  ❌ Kon CHANGELOG.md niet bijwerken"
  else
    # Maak nieuw bestand
    local content
    content=$(echo -e "$changelog" | base64 -w0)
    gh api "repos/$repo/contents/CHANGELOG.md" \
      -X PUT \
      -f "message=docs: add CHANGELOG.md" \
      -f "content=$content" \
      -f "branch=main" \
      --jq '.content.path' 2>/dev/null && log "  ✅ CHANGELOG.md aangemaakt" || log "  ❌ Kon CHANGELOG.md niet aanmaken"
  fi
}

# Hoofdlogica
if [ "$CG_ENABLED" != "yes" ]; then
  log "Changelog generator uitgeschakeld"
  exit 0
fi

if [ -z "$CG_REPO" ]; then
  log "CG_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting changelog generation for $CG_REPO..."

# Haal commits op
commits=$(get_commits_since_last_release "$CG_REPO")

# Genereer changelog
changelog=$(generate_changelog "$CG_REPO" "$commits")

# Update CHANGELOG.md
update_changelog_file "$CG_REPO" "$changelog"

log "=== Changelog Generator klaar ==="
