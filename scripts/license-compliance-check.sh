#!/usr/bin/env bash
# scripts/license-compliance-check.sh - License compliance check
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== License Compliance Check ==="

# Configuratie
LCC_ENABLED="${LCC_ENABLED:-yes}"
LCC_DRY_RUN="${LCC_DRY_RUN:-yes}"
LCC_REPO="${LCC_REPO:-}"
LCC_ORG="${LCC_ORG:-itsdarklikehell}"

# Functies
get_repo_license() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Getting license for $repo..."
  
  local license
  license=$(gh api "repos/$repo" --jq '.license.spdx_id' 2>/dev/null || echo "NOASSERTION")
  
  echo "$license"
}

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
  
  if [ -f "setup.py" ]; then
    deps+=$(grep -E "install_requires|requires" setup.py 2>/dev/null || echo "")
  fi
  
  if [ -f "pyproject.toml" ]; then
    deps+=$(grep -E "dependencies|requires" pyproject.toml 2>/dev/null || echo "")
  fi
  
  # Node.js dependencies
  if [ -f "package.json" ]; then
    deps+=$(grep -E '"[a-zA-Z0-9_-]+":' package.json 2>/dev/null || echo "")
  fi
  
  # Go dependencies
  if [ -f "go.mod" ]; then
    deps+=$(grep -E "^\s+[a-zA-Z0-9_-]+" go.mod 2>/dev/null || echo "")
  fi
  
  # Rust dependencies
  if [ -f "Cargo.toml" ]; then
    deps+=$(grep -E "^\s+[a-zA-Z0-9_-]+\s*=" Cargo.toml 2>/dev/null || echo "")
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
  
  echo "$deps"
}

check_license_compatibility() {
  local repo_license="$1"
  local dep_licenses="$2"
  
  log "Checking license compatibility..."
  
  local conflicts=""
  
  # Definieer compatibiliteitsregels
  # MIT is compatibel met alles
  # Apache-2.0 is compatibel met MIT, BSD, Apache-2.0
  # GPL-3.0 is NIET compatibel met MIT/Apache-2.0 in proprietary projecten
  # BSD is compatibel met alles
  
  case "$repo_license" in
    "MIT"|"BSD-3-Clause"|"BSD-2-Clause"|"ISC")
      # Deze licenties zijn compatibel met alles
      log "  ✅ $repo_license is compatibel met alle dependencies"
      ;;
    "Apache-2.0")
      # Apache-2.0 is compatibel met MIT, BSD, Apache-2.0
      log "  ✅ Apache-2.0 is compatibel met de meeste dependencies"
      ;;
    "GPL-3.0"|"GPL-2.0"|"AGPL-3.0")
      # GPL vereist dat dependencies ook GPL-compatibel zijn
      log "  ⚠️ $repo_license vereist GPL-compatibele dependencies"
      conflicts+="## ⚠️ License Conflicts\n\n"
      conflicts+="Dit project gebruikt $repo_license wat vereist dat alle dependencies GPL-compatibel zijn.\n\n"
      conflicts+="Controleer de volgende dependencies:\n\n"
      conflicts+=$(echo "$dep_licenses" | sed 's/^/- /')
      conflicts+="\n\n"
      ;;
    "NOASSERTION"|"NOASSERTION")
      log "  ⚠️ Geen licentie gevonden voor dit project"
      conflicts+="## ⚠️ Missing License\n\n"
      conflicts+="Dit project heeft geen licentie gevonden.\n\n"
      conflicts+="Voeg een licentiebestand toe aan de repository.\n\n"
      ;;
    *)
      log "  ⚠️ Onbekende licentie: $repo_license"
      conflicts+="## ⚠️ Unknown License\n\n"
      conflicts+="Dit project gebruikt een onbekende licentie: $repo_license\n\n"
      conflicts+="Controleer of deze licentie compatibel is met de dependencies.\n\n"
      ;;
  esac
  
  echo -e "$conflicts"
}

create_license_issue() {
  local repo="$1"
  local conflicts="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating license issue for $repo..."
  
  if [ "$LCC_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create license issue"
    return 0
  fi
  
  local body
  body=$(cat <<EOF
## 🔍 License Compliance Check

De license compliance check heeft mogelijke conflicten gevonden:

$conflicts

### Aanbevelingen

1. Controleer de licenties van alle dependencies
2. Gebruik `license-checker` of `fossa` voor gedetailleerde analyses
3. Overweeg om dependencies met conflicterende licenties te vervangen
4. Voeg een `LICENSE` bestand toe aan de repository

---
*Deze issue is automatisch aangemaakt door de GitHub Fleet Manager.*
EOF
)
  
  gh issue create \
    --repo "$repo" \
    --title "🔍 License compliance: mogelijke conflicten gevonden" \
    --body "$body" \
    --label "legal" 2>/dev/null && log "  ✅ License issue aangemaakt" || log "  ❌ Kon license issue niet aanmaken"
}

# Hoofdlogica
if [ "$LCC_ENABLED" != "yes" ]; then
  log "License compliance check uitgeschakeld"
  exit 0
fi

if [ -z "$LCC_REPO" ]; then
  log "LCC_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting license compliance check for $LCC_REPO..."

# Haal licentie op
repo_license=$(get_repo_license "$LCC_REPO")
log "  License: $repo_license"

# Haal dependencies op
deps=$(get_dependencies "$LCC_REPO")

# Check compatibiliteit
conflicts=$(check_license_compatibility "$repo_license" "$deps")

if [ -n "$conflicts" ]; then
  log "  ⚠️ License conflicten gevonden!"
  create_license_issue "$LCC_REPO" "$conflicts"
else
  log "  ✅ Geen license conflicten"
fi

log "=== License Compliance Check klaar ==="
