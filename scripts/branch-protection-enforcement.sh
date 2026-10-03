#!/usr/bin/env bash
# scripts/branch-protection-enforcement.sh - Branch protection enforcement
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Branch Protection Enforcement ==="

# Configuratie
BPE_ENABLED="${BPE_ENABLED:-yes}"
BPE_DRY_RUN="${BPE_DRY_RUN:-yes}"
BPE_REPO="${BPE_REPO:-}"
BPE_ORG="${BPE_ORG:-itsdarklikehell}"

# Functies
check_branch_protection() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Checking branch protection for $repo..."
  
  local protection
  protection=$(gh api "repos/$repo/branches/main/protection" --jq '.required_status_checks.strict' 2>/dev/null || echo "")
  
  if [ -z "$protection" ]; then
    log "  ⚠️ Geen branch protection gevonden"
    return 1
  else
    log "  ✅ Branch protection is actief"
    return 0
  fi
}

enable_branch_protection() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Enabling branch protection for $repo..."
  
  if [ "$BPE_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would enable branch protection"
    return 0
  fi
  
  gh api "repos/$repo/branches/main/protection" \
    -X PUT \
    -f "required_status_checks.strict=true" \
    -f "required_status_checks.contexts=[]" \
    -f "enforce_admins=true" \
    -f "required_pull_request_reviews.required_approving_review_count=1" \
    -f "restrictions=null" \
    --jq '.url' 2>/dev/null && log "  ✅ Branch protection ingeschakeld" || log "  ❌ Kon branch protection niet inschakelen"
}

create_protection_issue() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating branch protection issue for $repo..."
  
  if [ "$BPE_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create branch protection issue"
    return 0
  fi
  
  local body
  body=$(cat <<EOF
## 🔒 Branch Protection

Deze repository heeft geen branch protection ingeschakeld voor de `main` branch.

### Aanbevelingen

1. Schakel branch protection in voor de `main` branch
2. Vereis minimaal 1 review voor PRs
3. Schakel status checks in
4. Schakel "Include administrators" in

### Configuratie

```bash
gh api repos/$repo/branches/main/protection \
  -X PUT \
  -f "required_status_checks.strict=true" \
  -f "required_pull_request_reviews.required_approving_review_count=1" \
  -f "enforce_admins=true"
```

---
*Deze issue is automatisch aangemaakt door de GitHub Fleet Manager.*
EOF
)
  
  gh issue create \
    --repo "$repo" \
    --title "🔒 Branch protection niet ingeschakeld" \
    --body "$body" \
    --label "security" 2>/dev/null && log "  ✅ Protection issue aangemaakt" || log "  ❌ Kon protection issue niet aanmaken"
}

# Hoofdlogica
if [ "$BPE_ENABLED" != "yes" ]; then
  log "Branch protection enforcement uitgeschakeld"
  exit 0
fi

if [ -z "$BPE_REPO" ]; then
  log "BPE_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting branch protection enforcement for $BPE_REPO..."

# Check branch protection
if ! check_branch_protection "$BPE_REPO"; then
  log "  ⚠️ Branch protection ontbreekt!"
  enable_branch_protection "$BPE_REPO"
  create_protection_issue "$BPE_REPO"
else
  log "  ✅ Branch protection is al actief"
fi

log "=== Branch Protection Enforcement klaar ==="
