#!/usr/bin/env bash
# scripts/automated-dependency-updates.sh - Automatische dependency updates
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Automated Dependency Updates ==="

# Configuratie
ADU_ENABLED="${ADU_ENABLED:-yes}"
ADU_DRY_RUN="${ADU_DRY_RUN:-yes}"
ADU_REPO="${ADU_REPO:-}"
ADU_ORG="${ADU_ORG:-itsdarklikehell}"

# Functies
get_outdated_deps() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Checking outdated dependencies for $repo..."
  
  local tmpdir
  tmpdir=$(mktemp -d)
  
  if ! git clone --depth 1 "https://github.com/$repo.git" "$tmpdir/repo" 2>/dev/null; then
    log "  ❌ Kon repo niet clonen"
    rm -rf "$tmpdir"
    return 1
  fi
  
  cd "$tmpdir/repo"
  
  local outdated=""
  
  # Python dependencies
  if [ -f "requirements.txt" ]; then
    outdated+=$(pip list --outdated --format=freeze 2>/dev/null | grep -E "^[a-zA-Z0-9_-]+" || echo "")
  fi
  
  # Node.js dependencies
  if [ -f "package.json" ]; then
    outdated+=$(npm outdated --json 2>/dev/null | jq -r 'to_entries[] | select(.value.current != .value.latest) | "\(.key): \(.value.current) → \(.value.latest)"' 2>/dev/null || echo "")
  fi
  
  # Go dependencies
  if [ -f "go.mod" ]; then
    outdated+=$(go list -u -m all 2>/dev/null | grep -E "^\s+[a-zA-Z0-9_-]+" || echo "")
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
  
  echo "$outdated"
}

create_update_pr() {
  local repo="$1"
  local outdated="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating dependency update PR for $repo..."
  
  if [ "$ADU_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create dependency update PR"
    return 0
  fi
  
  local branch="deps/update-$(date +%Y%m%d)"
  
  # Maak branch
  gh api "repos/$repo/git/refs" \
    -X POST \
    -f "ref=refs/heads/$branch" \
    -f "sha=$(gh api "repos/$repo/commits/main" --jq '.sha' 2>/dev/null)" \
    --jq '.ref' 2>/dev/null || return 1
  
  # Maak PR
  local body
  body=$(cat <<EOF
## 🔄 Automated Dependency Updates

Deze PR bevat automatische dependency updates:

$outdated

### Aanbevelingen

1. Review de updates
2. Voer tests uit
3. Merge als alles werkt

---
*Deze PR is automatisch aangemaakt door de GitHub Fleet Manager.*
EOF
)
  
  gh pr create \
    --repo "$repo" \
    --head "$branch" \
    --base "main" \
    --title "🔄 Automated dependency updates" \
    --body "$body" \
    --label "dependencies" 2>/dev/null && log "  ✅ Dependency update PR aangemaakt" || log "  ❌ Kon PR niet aanmaken"
}

# Hoofdlogica
if [ "$ADU_ENABLED" != "yes" ]; then
  log "Automated dependency updates uitgeschakeld"
  exit 0
fi

if [ -z "$ADU_REPO" ]; then
  log "ADU_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting automated dependency updates for $ADU_REPO..."

# Haal outdated deps op
outdated=$(get_outdated_deps "$ADU_REPO")

if [ -n "$outdated" ]; then
  log "  ⚠️ Outdated dependencies gevonden!"
  create_update_pr "$ADU_REPO" "$outdated"
else
  log "  ✅ Alle dependencies zijn up-to-date"
fi

log "=== Automated Dependency Updates klaar ==="
