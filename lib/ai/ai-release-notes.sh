#!/usr/bin/env bash
# AI-powered release notes generation helper
set -euo pipefail

AI_MODEL="${AI_MODEL:-gpt-4o}"
AI_API_KEY="${AI_API_KEY:-}"

ai_generate_release_notes() {
  local repo="$1"
  local tag="$2"
  
  if [ -z "$AI_API_KEY" ]; then
    echo "  ⚠️ AI_API_KEY niet ingesteld — skipping AI release notes"
    return 0
  fi
  
  # Haal commits op sinds vorige tag
  local commits
  commits=$(gh api "repos/$repo/commits?per_page=100" --jq '.[] | "\(.sha[0:7])|\(.commit.message)"' 2>/dev/null || echo "")
  
  if [ -z "$commits" ]; then
    echo "  ⚠️ Geen commits gevonden"
    return 1
  fi
  
  # Bouw prompt
  local prompt="Genereer release notes voor $tag:

Commits:
$commits

Genereer release notes in Markdown met:
1. Nieuwe features
2. Bugfixes
3. Verbeteringen
4. Breaking changes"
  
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
    echo "  ✅ AI release notes gegenereerd voor $tag"
    echo "$response"
  else
    echo "  ❌ AI release notes gefaald voor $tag"
  fi
}
