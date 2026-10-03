#!/usr/bin/env bash
# scripts/auto-dependency-security-fixes.sh - Automatische security fix PRs
# Maakt automatisch PRs voor kwetsbare dependencies
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Dependency Security Fixes ==="

# Configuratie
AUTO_SECURITY_FIX_ENABLED="${AUTO_SECURITY_FIX_ENABLED:-no}"
SECURITY_FIX_BRANCH_PREFIX="${SECURITY_FIX_BRANCH_PREFIX:-security/fix}"

if [ "$AUTO_SECURITY_FIX_ENABLED" != "yes" ]; then
  echo "Auto security fix is uitgeschakeld (AUTO_SECURITY_FIX_ENABLED=$AUTO_SECURITY_FIX_ENABLED)"
  exit 0
fi

# Functies
check_vulnerabilities() {
  local repo="$1"
  
  # Haal dependabot alerts op
  local alerts
  alerts=$(gh api "repos/$repo/dependabot/alerts?state=open" --jq '.[] | "\(.number)|\(.security_advisory.summary)|\(.dependency.package.name)"' 2>/dev/null || echo "")
  
  echo "$alerts"
}

create_fix_pr() {
  local repo="$1"
  local alert_number="$2"
  local package="$3"
  local summary="$4"
  
  echo "  PR maken voor $package ($summary)..."
  
  # Maak branch
  local branch="$SECURITY_FIX_BRANCH_PREFIX/$package-$(date +%s)"
  
  # Check of branch al bestaat
  if gh api "repos/$repo/branches/$branch" > /dev/null 2>&1; then
    echo "    ⚠️ Branch $branch bestaat al"
    return 1
  fi
  
  # Maak branch aan
  gh api "repos/$repo/git/refs" -X POST \
    -f ref="refs/heads/$branch" \
    -f sha="$(gh api "repos/$repo/branches/main" --jq '.commit.sha' 2>/dev/null || echo "")" \
    > /dev/null 2>&1 || {
    echo "    ❌ Branch aanmaken gefaald"
    return 1
  }
  
  # TODO: Update dependency in package.json/requirements.txt/etc
  # Dit vereist repo-specifieke logica
  
  # Maak PR aan
  gh pr create \
    --repo "$repo" \
    --head "$branch" \
    --base "main" \
    --title "🔒 Security fix: $package" \
    --body "Automatische security fix voor $package

**Alert:** $summary
**Package:** $package
**Alert #:** $alert_number

Deze PR is automatisch gegenereerd door de fleet manager." \
    2>/dev/null || {
    echo "    ❌ PR aanmaken gefaald"
    return 1
  }
  
  echo "    ✅ PR aangemaakt"
}

# Hoofdlogica
echo "Controleren op kwetsbare dependencies..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  echo ""
  echo "--- $repo ---"
  
  alerts=$(check_vulnerabilities "$repo")
  
  if [ -z "$alerts" ]; then
    echo "  Geen kwetsbare dependencies"
    continue
  fi
  
  while IFS='|' read -r alert_number summary package; do
    [ -z "$alert_number" ] && continue
    echo "  ⚠️ $package: $summary"
    create_fix_pr "$repo" "$alert_number" "$package" "$summary"
  done <<< "$alerts"
done

echo ""
echo "✅ Auto dependency security fixes klaar"
