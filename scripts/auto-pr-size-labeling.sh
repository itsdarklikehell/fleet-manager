#!/usr/bin/env bash
# scripts/auto-pr-size-labeling.sh - Automatische PR size labeling
# PRs labelen op grootte (XS, S, M, L, XL)
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto PR Size Labeling ==="

# Configuratie
PR_SIZE_LABELING_ENABLED="${PR_SIZE_LABELING_ENABLED:-no}"

if [ "$PR_SIZE_LABELING_ENABLED" != "yes" ]; then
  echo "PR size labeling is uitgeschakeld (PR_SIZE_LABELING_ENABLED=$PR_SIZE_LABELING_ENABLED)"
  exit 0
fi

# Functies
get_size_label() {
  local additions="$1"
  local deletions="$2"
  local total=$((additions + deletions))
  
  if [ "$total" -le 10 ]; then
    echo "size/XS"
  elif [ "$total" -le 50 ]; then
    echo "size/S"
  elif [ "$total" -le 200 ]; then
    echo "size/M"
  elif [ "$total" -le 500 ]; then
    echo "size/L"
  else
    echo "size/XL"
  fi
}

label_pr() {
  local repo="$1"
  local pr_number="$2"
  
  # Haal PR stats op
  local additions
  additions=$(gh pr view "$pr_number" --repo "$repo" --json additions --jq '.additions' 2>/dev/null || echo "0")
  local deletions
  deletions=$(gh pr view "$pr_number" --repo "$repo" --json deletions --jq '.deletions' 2>/dev/null || echo "0")
  
  local size_label
  size_label=$(get_size_label "$additions" "$deletions")
  
  echo "  PR #$pr_number: +$additions/-$deletions → $size_label"
  
  # Verwijder bestaande size labels
  local current_labels
  current_labels=$(gh pr view "$pr_number" --repo "$repo" --json labels --jq '.labels[].name' 2>/dev/null || echo "")
  
  for label in $current_labels; do
    if [[ "$label" == size/* ]]; then
      gh pr edit "$pr_number" --repo "$repo" --remove-label "$label" > /dev/null 2>&1 || true
    fi
  done
  
  # Voeg nieuwe size label toe
  gh pr edit "$pr_number" --repo "$repo" --add-label "$size_label" > /dev/null 2>&1 || true
}

# Hoofdlogica
echo "PRs labelen op grootte..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  prs=$(gh pr list --repo "$repo" --state open --json number --jq '.[].number' 2>/dev/null || echo "")
  
  for pr in $prs; do
    label_pr "$repo" "$pr"
  done
done

echo ""
echo "✅ Auto PR size labeling klaar"
