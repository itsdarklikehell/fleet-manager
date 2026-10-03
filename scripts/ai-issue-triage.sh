#!/usr/bin/env bash
# scripts/ai-issue-triage.sh - Automatische issue triage met AI
# Integreert met AI models voor betere triage
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== AI Issue Triage ==="

# Configuratie
AI_MODEL="${AI_MODEL:-gpt-4o}"
AI_API_KEY="${AI_API_KEY:-}"
AI_TRIAGE_ENABLED="${AI_TRIAGE_ENABLED:-no}"

if [ "$AI_TRIAGE_ENABLED" != "yes" ]; then
  echo "AI triage is uitgeschakeld (AI_TRIAGE_ENABLED=$AI_TRIAGE_ENABLED)"
  exit 0
fi

if [ -z "$AI_API_KEY" ]; then
  echo "AI_API_KEY is niet ingesteld"
  exit 1
fi

# Functies
triage_issue() {
  local repo="$1"
  local issue_number="$2"
  
  echo "Triaging issue #$issue_number in $repo..."
  
  # Haal issue op
  local title
  title=$(gh issue view "$issue_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  local body
  body=$(gh issue view "$issue_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  local labels
  labels=$(gh issue view "$issue_number" --repo "$repo" --json labels --jq '.labels[].name' 2>/dev/null || echo "")
  
  # Bouw prompt
  local prompt="Classificeer deze GitHub issue:

Titel: $title
Beschrijving: $body
Bestaande labels: $labels

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
    echo "  ✅ AI triage gegenereerd"
    echo "$response"
    
    # Post als issue comment
    gh issue comment "$issue_number" --repo "$repo" --body "$response" 2>/dev/null || true
  else
    echo "  ❌ AI triage gefaald"
  fi
}

# Hoofdlogica
if [ -z "${1:-}" ]; then
  echo "Gebruik: ai-issue-triage.sh <repo> [issue_number]"
  exit 1
fi

repo="$1"
issue_number="${2:-}"

if [ -n "$issue_number" ]; then
  triage_issue "$repo" "$issue_number"
else
  # Alle open issues
  echo "Alle open issues triagen voor $repo..."
  issues=$(gh issue list --repo "$repo" --state open --json number --jq '.[].number' 2>/dev/null || echo "")
  
  if [ -z "$issues" ]; then
    echo "Geen open issues gevonden"
    exit 0
  fi
  
  for issue in $issues; do
    triage_issue "$repo" "$issue"
    echo "---"
  done
fi
