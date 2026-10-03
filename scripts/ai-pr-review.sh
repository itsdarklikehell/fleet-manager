#!/usr/bin/env bash
# scripts/ai-pr-review.sh - Automatische PR review met AI
# Integreert met AI models voor betere reviews
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== AI PR Review ==="

# Configuratie
AI_MODEL="${AI_MODEL:-gpt-4o}"
AI_API_KEY="${AI_API_KEY:-}"
AI_REVIEW_ENABLED="${AI_REVIEW_ENABLED:-no}"

if [ "$AI_REVIEW_ENABLED" != "yes" ]; then
  echo "AI review is uitgeschakeld (AI_REVIEW_ENABLED=$AI_REVIEW_ENABLED)"
  exit 0
fi

if [ -z "$AI_API_KEY" ]; then
  echo "AI_API_KEY is niet ingesteld"
  exit 1
fi

# Functies
review_pr() {
  local repo="$1"
  local pr_number="$2"
  
  echo "Reviewing PR #$pr_number in $repo..."
  
  # Haal PR diff op
  local diff
  diff=$(gh pr diff "$pr_number" --repo "$repo" 2>/dev/null || echo "")
  
  if [ -z "$diff" ]; then
    echo "  ❌ Geen diff gevonden"
    return 1
  fi
  
  # Haal PR info op
  local pr_title
  pr_title=$(gh pr view "$pr_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  local pr_body
  pr_body=$(gh pr view "$pr_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  
  # Bouw prompt
  local prompt="Review deze pull request:

Titel: $pr_title
Beschrijving: $pr_body

Diff:
$diff

Geef een review met:
1. Samenvatting van wijzigingen
2. Mogelijke problemen
3. Suggesties voor verbetering
4. Beoordeling (approve/request changes/comment)"
  
  # Call AI API (OpenAI compatible)
  local response
  response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AI_API_KEY" \
    -d "$(jq -n --arg model "$AI_MODEL" --arg prompt "$prompt" '{
      model: $model,
      messages: [{role: "user", content: $prompt}],
      max_tokens: 2000
    }')" 2>/dev/null | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
  
  if [ -n "$response" ]; then
    echo "  ✅ AI review gegenereerd"
    echo "$response"
    
    # Post als PR comment
    gh pr comment "$pr_number" --repo "$repo" --body "$response" 2>/dev/null || true
  else
    echo "  ❌ AI review gefaald"
  fi
}

# Hoofdlogica
if [ -z "${1:-}" ]; then
  echo "Gebruik: ai-pr-review.sh <repo> [pr_number]"
  exit 1
fi

repo="$1"
pr_number="${2:-}"

if [ -n "$pr_number" ]; then
  review_pr "$repo" "$pr_number"
else
  # Alle open PRs
  echo "Alle open PRs reviewen voor $repo..."
  prs=$(gh pr list --repo "$repo" --state open --json number --jq '.[].number' 2>/dev/null || echo "")
  
  if [ -z "$prs" ]; then
    echo "Geen open PRs gevonden"
    exit 0
  fi
  
  for pr in $prs; do
    review_pr "$repo" "$pr"
    echo "---"
  done
fi
