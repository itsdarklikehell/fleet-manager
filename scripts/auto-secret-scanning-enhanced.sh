#!/usr/bin/env bash
# scripts/auto-secret-scanning-enhanced.sh - Uitgebreide secret scanning
# Meer patterns en betere detectie
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Secret Scanning Enhanced ==="

# Configuratie
SECRET_SCAN_ENABLED="${SECRET_SCAN_ENABLED:-no}"

if [ "$SECRET_SCAN_ENABLED" != "yes" ]; then
  echo "Secret scanning is uitgeschakeld (SECRET_SCAN_ENABLED=$SECRET_SCAN_ENABLED)"
  exit 0
fi

# Functies
scan_for_secrets() {
  local repo="$1"
  
  echo "  Scannen van $repo voor secrets..."
  
  # Haal alle bestanden op
  local files
  files=$(gh api "repos/$repo/git/trees/HEAD?recursive=1" --jq '.tree[].path' 2>/dev/null || echo "")
  
  local secrets_found=0
  
  for file in $files; do
    # Skip binaire bestanden en node_modules
    [[ "$file" == *node_modules* ]] && continue
    [[ "$file" == *.lock ]] && continue
    [[ "$file" == *.min.js ]] && continue
    
    # Haal bestand op
    local content
    content=$(gh api "repos/$repo/contents/$file" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    # Check voor secrets
    if echo "$content" | grep -qiE '(api_key|apikey|secret|password|token|credential)\s*[=:]\s*["\x27][a-zA-Z0-9]{20,}["\x27]'; then
      echo "    ⚠️ Mogelijk secret gevonden in $file"
      secrets_found=$((secrets_found + 1))
    fi
    
    # Check voor AWS keys
    if echo "$content" | grep -qE 'AKIA[0-9A-Z]{16}'; then
      echo "    ⚠️ AWS access key gevonden in $file"
      secrets_found=$((secrets_found + 1))
    fi
    
    # Check voor GitHub tokens
    if echo "$content" | grep -qE 'ghp_[a-zA-Z0-9]{36}'; then
      echo "    ⚠️ GitHub token gevonden in $file"
      secrets_found=$((secrets_found + 1))
    fi
    
    # Check voor Slack tokens
    if echo "$content" | grep -qE 'xox[baprs]-[a-zA-Z0-9]{10,}'; then
      echo "    ⚠️ Slack token gevonden in $file"
      secrets_found=$((secrets_found + 1))
    fi
  done
  
  if [ "$secrets_found" -gt 0 ]; then
    echo "    ❌ $secrets_found secrets gevonden"
  else
    echo "    ✅ Geen secrets gevonden"
  fi
}

# Hoofdlogica
echo "Secret scanning uitvoeren..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  scan_for_secrets "$repo"
done

echo ""
echo "✅ Auto secret scanning enhanced klaar"
