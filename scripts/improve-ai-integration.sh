#!/usr/bin/env bash
# scripts/improve-ai-integration.sh - AI-integratie verbeteren
# Voegt AI-powered PR reviews, issue triage en release notes generation toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Improve AI Integration ==="

# Configuratie
AI_DIR="lib/ai"
mkdir -p "$AI_DIR"

# Functies
setup_ai_pr_review() {
  local pr_review="$AI_DIR/ai-pr-review.sh"
  
  cat > "$pr_review" << 'PRREVIEW'
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
PRREVIEW
  
  chmod +x "$pr_review"
  echo "  ✅ AI PR review ingesteld"
}

setup_ai_issue_triage() {
  local triage="$AI_DIR/ai-issue-triage.sh"
  
  cat > "$triage" << 'TRIAGE'
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
TRIAGE
  
  chmod +x "$triage"
  echo "  ✅ AI issue triage ingesteld"
}

setup_ai_release_notes() {
  local release_notes="$AI_DIR/ai-release-notes.sh"
  
  cat > "$release_notes" << 'RELEASE'
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
RELEASE
  
  chmod +x "$release_notes"
  echo "  ✅ AI release notes generation ingesteld"
}

# Hoofdlogica
setup_ai_pr_review
setup_ai_issue_triage
setup_ai_release_notes

echo ""
echo "✅ AI-integratie verbetering klaar"
