#!/usr/bin/env bash
# scripts/auto-issue-labeling-ai.sh - Automatische issue labeling met AI
# Gebruikt AI om labels toe te kennen aan issues
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Issue Labeling AI ==="

# Configuratie
AI_LABELING_ENABLED="${AI_LABELING_ENABLED:-no}"
AI_MODEL="${AI_MODEL:-gpt-4o}"
AI_API_KEY="${AI_API_KEY:-}"

if [ "$AI_LABELING_ENABLED" != "yes" ]; then
  echo "AI labeling is uitgeschakeld (AI_LABELING_ENABLED=$AI_LABELING_ENABLED)"
  exit 0
fi

if [ -z "$AI_API_KEY" ]; then
  echo "AI_API_KEY is niet ingesteld"
  exit 1
fi

# Functies
suggest_labels() {
  local repo="$1"
  local issue_number="$2"
  
  # Haal issue op
  local title
  title=$(gh issue view "$issue_number" --repo "$repo" --json title --jq '.title' 2>/dev/null || echo "")
  local body
  body=$(gh issue view "$issue_number" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  
  # Bouw prompt
  local prompt="Suggesteer labels voor deze GitHub issue:

Titel: $title
Beschrijving: $body

Geef een lijst van max 5 labels in formaat: label1, label2, label3"
  
  # Call AI API
  local response
  response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AI_API_KEY" \
    -d "$(jq -n --arg model "$AI_MODEL" --arg prompt "$prompt" '{
      model: $model,
      messages: [{role: "user", content: $prompt}],
      max_tokens: 200
    }')" 2>/dev/null | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
  
  echo "$response"
}

apply_labels() {
  local repo="$1"
  local issue_number="$2"
  local labels="$3"
  
  echo "  Labels toekennen aan issue #$issue_number: $labels"
  
  # Parse labels
  IFS=',' read -ra label_array <<< "$labels"
  
  for label in "${label_array[@]}"; do
    label=$(echo "$label" | xargs)  # trim whitespace
    [ -z "$label" ] && continue
    
    # Check of label bestaat
    if ! gh label list --repo "$repo" --json name --jq '.[].name' 2>/dev/null | grep -q "^$label$"; then
      # Maak label aan
      gh label create "$label" --repo "$repo" --color "0366d6" > /dev/null 2>&1 || true
    fi
    
    # Voeg label toe
    gh issue edit "$issue_number" --repo "$repo" --add-label "$label" > /dev/null 2>&1 || true
  done
  
  echo "    ✅ Labels toegekend"
}

# Hoofdlogica
echo "Issues labelen met AI..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  issues=$(gh issue list --repo "$repo" --state open --json number --jq '.[].number' 2>/dev/null || echo "")
  
  for issue in $issues; do
    # Check of issue al labels heeft
    label_count
    label_count=$(gh issue view "$issue" --repo "$repo" --json labels --jq '.labels | length' 2>/dev/null || echo "0")
    
    if [ "$label_count" -eq 0 ]; then
      echo "  Issue #$issue in $repo heeft geen labels"
      labels=$(suggest_labels "$repo" "$issue")
      if [ -n "$labels" ]; then
        apply_labels "$repo" "$issue" "$labels"
      fi
    fi
  done
done

echo ""
echo "✅ Auto issue labeling AI klaar"
