#!/usr/bin/env bash
# scripts/repo-archiving-suggestions.sh - Repo archiving suggestions
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Repo Archiving Suggestions ==="

# Configuratie
RAS_ENABLED="${RAS_ENABLED:-yes}"
RAS_DRY_RUN="${RAS_DRY_RUN:-yes}"
RAS_REPO="${RAS_REPO:-}"
RAS_ORG="${RAS_ORG:-itsdarklikehell}"

# Functies
check_repo_activity() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Checking activity for $repo..."
  
  local should_archive=false
  local reasons=""
  
  # 1. Laatste commit > 1 jaar geleden
  local last_commit
  last_commit=$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].commit.author.date' 2>/dev/null || echo "")
  if [ -n "$last_commit" ]; then
    local days_since
    days_since=$(( ( $(date +%s) - $(date -d "$last_commit" +%s) ) / 86400 ))
    if [ "$days_since" -gt 365 ]; then
      should_archive=true
      reasons+="## ⚠️ Inactive Repository\n\n"
      reasons+="- Laatste commit: $days_since dagen geleden\n\n"
    fi
  fi
  
  # 2. Geen stars
  local stars
  stars=$(gh api "repos/$repo" --jq '.stargazers_count' 2>/dev/null || echo "0")
  if [ "$stars" -eq 0 ]; then
    should_archive=true
    reasons+="## ⚠️ No Stars\n\n"
    reasons+="- Deze repository heeft geen stars\n\n"
  fi
  
  # 3. Geen forks
  local forks
  forks=$(gh api "repos/$repo" --jq '.forks_count' 2>/dev/null || echo "0")
  if [ "$forks" -eq 0 ]; then
    should_archive=true
    reasons+="## ⚠️ No Forks\n\n"
    reasons+="- Deze repository heeft geen forks\n\n"
  fi
  
  # 4. Geen open issues/PRs
  local open_issues
  open_issues=$(gh api "repos/$repo" --jq '.open_issues_count' 2>/dev/null || echo "0")
  if [ "$open_issues" -eq 0 ]; then
    should_archive=true
    reasons+="## ⚠️ No Activity\n\n"
    reasons+="- Geen open issues of PRs\n\n"
  fi
  
  if [ "$should_archive" = true ]; then
    echo "$reasons"
    return 0
  else
    log "  ✅ Repository is actief"
    return 1
  fi
}

create_archive_issue() {
  local repo="$1"
  local reasons="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating archive suggestion issue for $repo..."
  
  if [ "$RAS_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create archive suggestion issue"
    return 0
  fi
  
  local body
  body=$(cat <<EOF
## 📦 Repo Archiving Suggestion

Deze repository kan mogelijk gearchiveerd worden:

$reasons

### Aanbevelingen

1. Controleer of de repository nog nodig is
2. Archiveer indien niet meer nodig
3. Voeg een README toe met uitleg indien gearchiveerd

### Archiveren

```bash
gh api repos/$repo \
  -X PATCH \
  -f "archived=true"
```

---
*Deze suggestie is automatisch gegenereerd door de GitHub Fleet Manager.*
EOF
)
  
  gh issue create \
    --repo "$repo" \
    --title "📦 Repo archiving suggestion" \
    --body "$body" \
    --label "maintenance" 2>/dev/null && log "  ✅ Archive suggestion issue aangemaakt" || log "  ❌ Kon archive suggestion issue niet aanmaken"
}

# Hoofdlogica
if [ "$RAS_ENABLED" != "yes" ]; then
  log "Repo archiving suggestions uitgeschakeld"
  exit 0
fi

if [ -z "$RAS_REPO" ]; then
  log "RAS_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting repo archiving suggestions for $RAS_REPO..."

# Check activity
reasons=$(check_repo_activity "$RAS_REPO")

if [ -n "$reasons" ]; then
  log "  ⚠️ Repository kan gearchiveerd worden!"
  create_archive_issue "$RAS_REPO" "$reasons"
else
  log "  ✅ Repository is actief"
fi

log "=== Repo Archiving Suggestions klaar ==="
