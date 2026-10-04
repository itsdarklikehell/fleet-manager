#!/usr/bin/env bash
# scripts/auto-release-notes-translation.sh - Automatische release notes vertaling
# Release notes automatisch in meerdere talen
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Release Notes Translation ==="

# Configuratie
TRANSLATION_ENABLED="${TRANSLATION_ENABLED:-no}"
TARGET_LANGUAGES="${TARGET_LANGUAGES:-nl,de,fr,es}"
TRANSLATION_API_KEY="${TRANSLATION_API_KEY:-}"

if [ "$TRANSLATION_ENABLED" != "yes" ]; then
  echo "Vertaling is uitgeschakeld (TRANSLATION_ENABLED=$TRANSLATION_ENABLED)"
  exit 0
fi

# Functies
translate_text() {
  local text="$1"
  local target_lang="$2"
  
  # Gebruik Google Translate API (gratis tier)
  local response
  response=$(curl -s -X POST "https://translation.googleapis.com/language/translate/v2" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg text "$text" --arg lang "$target_lang" '{
      q: $text,
      target: $lang,
      format: "text"
    }')" 2>/dev/null | jq -r '.data.translations[0].translatedText' 2>/dev/null || echo "")
  
  echo "$response"
}

translate_release_notes() {
  local repo="$1"
  local tag="$2"
  
  # Haal release notes op
  local notes
  notes=$(gh release view "$tag" --repo "$repo" --json body --jq '.body' 2>/dev/null || echo "")
  
  if [ -z "$notes" ]; then
    echo "  ⚠️ Geen release notes gevonden voor $tag"
    return 1
  fi
  
  # Vertaal naar elke taal
  IFS=',' read -ra langs <<< "$TARGET_LANGUAGES"
  for lang in "${langs[@]}"; do
    echo "  Vertalen naar $lang..."
    local translated
    translated=$(translate_text "$notes" "$lang")
    
    if [ -n "$translated" ]; then
      # Sla op
      local output_file="$HOME/.github_fleet_translations/${repo}/${tag}.${lang}.md"
      mkdir -p "$(dirname "$output_file")"
      echo "$translated" > "$output_file"
      echo "    ✅ Opgeslagen: $output_file"
    fi
  done
}

# Hoofdlogica
echo "Release notes vertalen..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  # Haal laatste release op
  tag
  tag=$(gh release list --repo "$repo" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")
  
  if [ -n "$tag" ]; then
    translate_release_notes "$repo" "$tag"
  fi
done

echo ""
echo "✅ Auto release notes translation klaar"
