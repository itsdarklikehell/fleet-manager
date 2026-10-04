#!/usr/bin/env bash
# AI-powered PR review helper
set -euo pipefail

AI_MODEL="${AI_MODEL:-gpt-4o}"
AI_API_KEY="${AI_API_KEY:-}"

ai_review_pr() {
  local repo="$1"
  local pr_number="$2"
  
  if [ -z "$AI_API_KEY" ]; then
    echo "  ⚠️ AI_API_KEY niet ingesteld — skipping AI review"
    return 0
  fi
  
  # Haal PR diff op
  local diff
  diff=$(gh pr diff "$pr_number" --repo "$repo" 2>/dev/null || echo "")
  
  if [ -z "$diff" ]; then
    echo "  ⚠️ Geen diff gevonden voor PR #$pr_number"
    return 1
  fi
  
  # Bouw prompt
  local prompt="Review deze pull request:

Diff:
$diff

Geef een review met:
1. Samenvatting van wijzigingen
2. Mogelijke problemen
3. Suggesties voor verbetering
4. Beoordeling (approve/request changes/comment)"
  
  # Call AI API
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
    echo "  ✅ AI review gegenereerd voor PR #$pr_number"
    echo "$response"
  else
    echo "  ❌ AI review gefaald voor PR #$pr_number"
  fi
}
