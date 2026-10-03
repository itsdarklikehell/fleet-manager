#!/usr/bin/env bash
# scripts/auto-branch-protection.sh - Automatische branch protection
# Voor alle repos automatisch branch protection inschakelen
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Branch Protection ==="

# Configuratie
BRANCH_PROTECTION_ENABLED="${BRANCH_PROTECTION_ENABLED:-no}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

if [ "$BRANCH_PROTECTION_ENABLED" != "yes" ]; then
  echo "Branch protection is uitgeschakeld (BRANCH_PROTECTION_ENABLED=$BRANCH_PROTECTION_ENABLED)"
  exit 0
fi

# Functies
enable_branch_protection() {
  local repo="$1"
  
  echo "  Branch protection inschakelen voor $repo ($DEFAULT_BRANCH)..."
  
  # Check of branch protection al actief is
  local existing
  existing=$(gh api "repos/$repo/branches/$DEFAULT_BRANCH/protection" --jq '.url' 2>/dev/null || echo "")
  
  if [ -n "$existing" ]; then
    echo "    ⏭️ Branch protection al actief"
    return 0
  fi
  
  # Schakel branch protection in
  gh api "repos/$repo/branches/$DEFAULT_BRANCH/protection" \
    -X PUT \
    -f required_status_checks.strict=true \
    -f required_status_checks.contexts="ci/ci" \
    -f enforce_admins=false \
    -f required_pull_request_reviews.required_approving_review_count=1 \
    -f restrictions=null \
    > /dev/null 2>&1 || {
    echo "    ❌ Branch protection inschakelen gefaald"
    return 1
  }
  
  echo "    ✅ Branch protection ingeschakeld"
}

# Hoofdlogica
echo "Branch protection controleren voor alle repos..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  enable_branch_protection "$repo"
done

echo ""
echo "✅ Auto branch protection klaar"
