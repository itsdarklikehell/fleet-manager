#!/usr/bin/env bash
# scripts/auto-release-publishing.sh - Automatische release publishing
# Genereert changelog, maakt GitHub Release aan en upload assets
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Release Publishing ==="

# Configuratie
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"
AUTO_RELEASE_ENABLED="${AUTO_RELEASE_ENABLED:-no}"

if [ "$AUTO_RELEASE_ENABLED" != "yes" ]; then
  echo "Auto release is uitgeschakeld (AUTO_RELEASE_ENABLED=$AUTO_RELEASE_ENABLED)"
  exit 0
fi

# Functies
generate_changelog() {
  local repo="$1"
  local tag="$2"
  
  echo "Changelog genereren voor $repo ($tag)..."
  
  # Haal commits op sinds vorige tag
  local commits
  commits=$(gh api "repos/$repo/commits?sha=$RELEASE_BRANCH&per_page=100" --jq '.[] | "\(.sha[0:7])|\(.commit.message)"' 2>/dev/null || echo "")
  
  if [ -z "$commits" ]; then
    echo "  ⚠️ Geen commits gevonden"
    return 1
  fi
  
  # Categoriseer commits
  local features=()
  local fixes=()
  local docs=()
  local refactors=()
  local others=()
  
  while IFS='|' read -r sha message; do
    if echo "$message" | grep -qiE '^(feat|feature)'; then
      features+=("$message")
    elif echo "$message" | grep -qiE '^(fix|bug)'; then
      fixes+=("$message")
    elif echo "$message" | grep -qiE '^(docs|doc)'; then
      docs+=("$message")
    elif echo "$message" | grep -qiE '^(refactor|cleanup)'; then
      refactors+=("$message")
    else
      others+=("$message")
    fi
  done <<< "$commits"
  
  # Genereer Markdown
  local changelog="# Changelog

"
  
  if [ ${#features[@]} -gt 0 ]; then
    changelog+="## ✨ Nieuwe Features

"
    for feat in "${features[@]}"; do
      changelog+="- $feat
"
    done
    changelog+="
"
  fi
  
  if [ ${#fixes[@]} -gt 0 ]; then
    changelog+="## 🐛 Bugfixes

"
    for fix in "${fixes[@]}"; do
      changelog+="- $fix
"
    done
    changelog+="
"
  fi
  
  if [ ${#docs[@]} -gt 0 ]; then
    changelog+="## 📚 Documentatie

"
    for doc in "${docs[@]}"; do
      changelog+="- $doc
"
    done
    changelog+="
"
  fi
  
  if [ ${#refactors[@]} -gt 0 ]; then
    changelog+="## ♻️ Refactoring

"
    for ref in "${refactors[@]}"; do
      changelog+="- $ref
"
    done
    changelog+="
"
  fi
  
  if [ ${#others[@]} -gt 0 ]; then
    changelog+="## 📦 Overige Wijzigingen

"
    for other in "${others[@]}"; do
      changelog+="- $other
"
    done
    changelog+="
"
  fi
  
  echo "$changelog"
}

publish_release() {
  local repo="$1"
  local tag="$2"
  local changelog="$3"
  
  echo "Release publiceren voor $repo ($tag)..."
  
  # Maak release aan
  gh release create "$tag" \
    --repo "$repo" \
    --title "Release $tag" \
    --notes "$changelog" \
    --target "$RELEASE_BRANCH" \
    2>/dev/null || {
    echo "  ❌ Release publiceren gefaald"
    return 1
  }
  
  echo "  ✅ Release gepubliceerd"
}

# Hoofdlogica
if [ -z "${1:-}" ]; then
  echo "Gebruik: auto-release-publishing.sh <repo> [tag]"
  exit 1
fi

repo="$1"
tag="${2:-}"

if [ -z "$tag" ]; then
  # Genereer tag nummer
  tag="v$(date +%Y.%m.%d)"
fi

echo "Release voor $repo met tag $tag"

# Genereer changelog
changelog=$(generate_changelog "$repo" "$tag")

if [ -z "$changelog" ]; then
  echo "Geen changelog gegenereerd — skipping"
  exit 0
fi

# Publiceer release
publish_release "$repo" "$tag" "$changelog"

echo ""
echo "✅ Auto release publishing klaar"
