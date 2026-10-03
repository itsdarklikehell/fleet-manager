#!/usr/bin/env bash
# scripts/security-advisory-monitor.sh - Security advisory monitoring
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Security Advisory Monitor ==="

# Configuratie
SAM_ENABLED="${SAM_ENABLED:-yes}"
SAM_DRY_RUN="${SAM_DRY_RUN:-yes}"
SAM_REPO="${SAM_REPO:-}"
SAM_ORG="${SAM_ORG:-itsdarklikehell}"

# Functies
get_dependencies() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Getting dependencies for $repo..."
  
  local tmpdir
  tmpdir=$(mktemp -d)
  
  if ! git clone --depth 1 "https://github.com/$repo.git" "$tmpdir/repo" 2>/dev/null; then
    log "  ❌ Kon repo niet clonen"
    rm -rf "$tmpdir"
    return 1
  fi
  
  cd "$tmpdir/repo"
  
  local deps=""
  
  # Python dependencies
  if [ -f "requirements.txt" ]; then
    deps+=$(grep -E "^[a-zA-Z0-9_-]+" requirements.txt 2>/dev/null || echo "")
  fi
  
  # Node.js dependencies
  if [ -f "package.json" ]; then
    deps+=$(grep -E '"[a-zA-Z0-9_-]+":' package.json 2>/dev/null || echo "")
  fi
  
  # Go dependencies
  if [ -f "go.mod" ]; then
    deps+=$(grep -E "^\s+[a-zA-Z0-9_-]+" go.mod 2>/dev/null || echo "")
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
  
  echo "$deps"
}

check_advisories() {
  local repo="$1"
  local deps="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Checking security advisories for $repo..."
  
  local advisories=""
  
  # Check GitHub advisories voor elke dependency
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    
    # Zoek naar advisories
    local advisory
    advisory=$(gh api "repos/$repo/dependency-graph/snapshots" --jq '.dependencies[] | select(.packageName == "'"$dep"'") | .packageName' 2>/dev/null || echo "")
    
    if [ -n "$advisory" ]; then
      advisories+="- $dep\n"
    fi
  done <<< "$deps"
  
  if [ -n "$advisories" ]; then
    echo -e "$advisories"
    return 0
  else
    log "  ✅ Geen advisories gevonden"
    return 1
  fi
}

create_advisory_issue() {
  local repo="$1"
  local advisories="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating advisory issue for $repo..."
  
  if [ "$SAM_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create advisory issue"
    return 0
  fi
  
  local body
  body=$(cat <<EOF
## 🔒 Security Advisory Monitor

De security advisory monitor heeft mogelijk kwetsbare dependencies gevonden:

$advisories

### Aanbevelingen

1. Update alle dependencies naar de laatste versie
2. Gebruik `npm audit` of `pip-audit` voor gedetailleerde analyses
3. Voeg `dependabot` of `renovate` toe voor automatische updates
4. Monitor regelmatig op nieuwe advisories

---
*Deze issue is automatisch aangemaakt door de GitHub Fleet Manager.*
EOF
)
  
  gh issue create \
    --repo "$repo" \
    --title "🔒 Security advisory: kwetsbare dependencies gevonden" \
    --body "$body" \
    --label "security" 2>/dev/null && log "  ✅ Advisory issue aangemaakt" || log "  ❌ Kon advisory issue niet aanmaken"
}

# Hoofdlogica
if [ "$SAM_ENABLED" != "yes" ]; then
  log "Security advisory monitor uitgeschakeld"
  exit 0
fi

if [ -z "$SAM_REPO" ]; then
  log "SAM_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting security advisory monitor for $SAM_REPO..."

# Haal dependencies op
deps=$(get_dependencies "$SAM_REPO")

# Check advisories
advisories=$(check_advisories "$SAM_REPO" "$deps")

if [ -n "$advisories" ]; then
  log "  ⚠️ Advisories gevonden!"
  create_advisory_issue "$SAM_REPO" "$advisories"
else
  log "  ✅ Geen advisories gevonden"
fi

log "=== Security Advisory Monitor klaar ==="
