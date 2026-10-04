#!/usr/bin/env bash
# AI-powered issue triage helper
set -euo pipefail

AI_MODEL="${AI_MODEL:-gpt-4o}"
AI_API_KEY="${AI_API_KEY:-}"

ai_triage_issue() {
  local repo="$1"
  local issue_number="$2"
  
  if [ -z "$AI_API_KEY" ]; then
    echo "  ⚠️ AI_API_KEY niet ingesteld — skipping AI triage"
    return 0
  fi
  
  # Haal issue op
  local title
  title=$(gh issue view "$issue_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  local body
  body=$(gh issue view "$issue_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  
  # Bouw prompt
  local prompt="Classificeer deze GitHub issue:

Titel: $title
Beschrijving: $body

Geef:
1. Categorie (bug, feature request, question, documentation, other)
2. Prioriteit (low, medium, high, critical)
3. Suggesties voor labels
4. Korte samenvatting"
  
  # Call AI API
  local response
  response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AI_API_KEY" \
    -d "$(jq -n --arg model "$AI_MODEL" --arg prompt "$prompt" '{
      model: $model,
      messages: [{role: "user", content: $prompt}],
      max_tokens: 1000
    }')" 2>/dev/null | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
  
  if [ -n "$response" ]; then
    echo "  ✅ AI triage gegenereerd voor issue #$issue_number"
    echo "$response"
  else
    echo "  ❌ AI triage gefaald voor issue #$issue_number"
  fi
}
