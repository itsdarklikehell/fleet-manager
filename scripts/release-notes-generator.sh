#!/usr/bin/env bash
# scripts/release-notes-generator.sh - Genereert release notes uit commits
# Categoriseert commits en genereert Markdown release notes
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Release Notes Generator ==="

# Functies
generate_release_notes() {
  local repo="$1"
  local tag="${2:-}"
  
  log "Genereer release notes voor $repo..."
  
  # Bepaal bereik van commits
  local commit_range
  if [ -n "$tag" ]; then
    commit_range="$tag..HEAD"
  else
    # Laatste 50 commits
    commit_range="HEAD~50..HEAD"
  fi
  
  # Haal commits op
  local commits
  commits=$(gh api "repos/$repo/commits?sha=HEAD&per_page=100" --jq '.[] | "\(.sha[0:7])|\(.commit.message)"' 2>/dev/null || echo "")
  
  if [ -z "$commits" ]; then
    log "Geen commits gevonden"
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
  local notes="# Release Notes

"
  
  if [ ${#features[@]} -gt 0 ]; then
    notes+="## ✨ Nieuwe Features

"
    for feat in "${features[@]}"; do
      notes+="- $feat
"
    done
    notes+="
"
  fi
  
  if [ ${#fixes[@]} -gt 0 ]; then
    notes+="## 🐛 Bugfixes

"
    for fix in "${fixes[@]}"; do
      notes+="- $fix
"
    done
    notes+="
"
  fi
  
  if [ ${#docs[@]} -gt 0 ]; then
    notes+="## 📚 Documentatie

"
    for doc in "${docs[@]}"; do
      notes+="- $doc
"
    done
    notes+="
"
  fi
  
  if [ ${#refactors[@]} -gt 0 ]; then
    notes+="## ♻️ Refactoring

"
    for ref in "${refactors[@]}"; do
      notes+="- $ref
"
    done
    notes+="
"
  fi
  
  if [ ${#others[@]} -gt 0 ]; then
    notes+="## 📦 Overige Wijzigingen

"
    for other in "${others[@]}"; do
      notes+="- $other
"
    done
    notes+="
"
  fi
  
  # Statistieken
  local total=$(( ${#features[@]} + ${#fixes[@]} + ${#docs[@]} + ${#refactors[@]} + ${#others[@]} ))
  notes+="---

**Totaal:** $total commits
"
  
  echo "$notes"
}

# Hoofdlogica
if [ -z "${1:-}" ]; then
  log "Gebruik: release-notes-generator.sh <repo> [tag]"
  exit 1
fi

repo="$1"
tag="${2:-}"

generate_release_notes "$repo" "$tag"
