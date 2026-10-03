#!/usr/bin/env bash
# scripts/repo-health-score.sh - Repo health score berekening
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Repo Health Score ==="

# Configuratie
RHS_ENABLED="${RHS_ENABLED:-yes}"
RHS_DRY_RUN="${RHS_DRY_RUN:-yes}"
RHS_REPO="${RHS_REPO:-}"
RHS_ORG="${RHS_ORG:-itsdarklikehell}"

# Functies
calculate_health_score() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Calculating health score for $repo..."
  
  local score=100
  local issues=""
  
  # 1. Open issues (max -20)
  local open_issues
  open_issues=$(gh api "repos/$repo" --jq '.open_issues_count' 2>/dev/null || echo "0")
  if [ "$open_issues" -gt 10 ]; then
    score=$((score - 20))
    issues+="## ⚠️ Open Issues\n\n"
    issues+="- $open_issues open issues (max 10 aanbevolen)\n\n"
  elif [ "$open_issues" -gt 5 ]; then
    score=$((score - 10))
    issues+="## ⚠️ Open Issues\n\n"
    issues+="- $open_issues open issues\n\n"
  fi
  
  # 2. Laatste commit (max -30)
  local last_commit
  last_commit=$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].commit.author.date' 2>/dev/null || echo "")
  if [ -n "$last_commit" ]; then
    local days_since
    days_since=$(( ( $(date +%s) - $(date -d "$last_commit" +%s) ) / 86400 ))
    if [ "$days_since" -gt 365 ]; then
      score=$((score - 30))
      issues+="## ⚠️ Inactive Repository\n\n"
      issues+="- Laatste commit: $days_since dagen geleden\n\n"
    elif [ "$days_since" -gt 180 ]; then
      score=$((score - 15))
      issues+="## ⚠️ Inactive Repository\n\n"
      issues+="- Laatste commit: $days_since dagen geleden\n\n"
    elif [ "$days_since" -gt 90 ]; then
      score=$((score - 5))
      issues+="## ⚠️ Inactive Repository\n\n"
      issues+="- Laatste commit: $days_since dagen geleden\n\n"
    fi
  fi
  
  # 3. CI status (max -20)
  local ci_status
  ci_status=$(gh api "repos/$repo/actions/runs?per_page=1" --jq '.workflow_runs[0].conclusion' 2>/dev/null || echo "")
  if [ "$ci_status" = "failure" ]; then
    score=$((score - 20))
    issues+="## ❌ CI Status\n\n"
    issues+="- Laatste CI run gefaald\n\n"
  elif [ "$ci_status" = "success" ]; then
    score=$((score + 5))
  fi
  
  # 4. Test coverage (max -15)
  local has_tests
  has_tests=$(gh api "repos/$repo/contents/" --jq '.[].name' 2>/dev/null | grep -iE "(test|spec)" || echo "")
  if [ -z "$has_tests" ]; then
    score=$((score - 15))
    issues+="## ⚠️ Test Coverage\n\n"
    issues+="- Geen tests gevonden\n\n"
  fi
  
  # 5. Documentatie (max -10)
  local has_readme
  has_readme=$(gh api "repos/$repo/contents/" --jq '.[].name' 2>/dev/null | grep -i "readme" || echo "")
  if [ -z "$has_readme" ]; then
    score=$((score - 10))
    issues+="## ⚠️ Documentation\n\n"
    issues+="- Geen README gevonden\n\n"
  fi
  
  # 6. License (max -5)
  local has_license
  has_license=$(gh api "repos/$repo" --jq '.license.spdx_id' 2>/dev/null || echo "")
  if [ -z "$has_license" ] || [ "$has_license" = "NOASSERTION" ]; then
    score=$((score - 5))
    issues+="## ⚠️ License\n\n"
    issues+="- Geen licentie gevonden\n\n"
  fi
  
  # Zorg dat score niet onder 0 gaat
  if [ "$score" -lt 0 ]; then
    score=0
  fi
  
  echo "$score|$issues"
}

create_health_issue() {
  local repo="$1"
  local score="$2"
  local issues="$3"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating health issue for $repo (score: $score)..."
  
  if [ "$RHS_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create health issue"
    return 0
  fi
  
  local body
  body=$(cat <<EOF
## 🏥 Repo Health Score: $score/100

De health score voor deze repository is **$score/100**.

### Problemen

$issues

### Aanbevelingen

1. Voeg tests toe voor betere dekking
2. Update de README met duidelijke instructies
3. Voeg een licentiebestand toe
4. Zorg dat CI correct werkt
5. Review en merge open issues

---
*Deze score is automatisch berekend door de GitHub Fleet Manager.*
EOF
)
  
  gh issue create \
    --repo "$repo" \
    --title "🏥 Repo health score: $score/100" \
    --body "$body" \
    --label "health" 2>/dev/null && log "  ✅ Health issue aangemaakt" || log "  ❌ Kon health issue niet aanmaken"
}

# Hoofdlogica
if [ "$RHS_ENABLED" != "yes" ]; then
  log "Repo health score uitgeschakeld"
  exit 0
fi

if [ -z "$RHS_REPO" ]; then
  log "RHS_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting repo health score for $RHS_REPO..."

# Bereken score
result=$(calculate_health_score "$RHS_REPO")
score=$(echo "$result" | cut -d'|' -f1)
issues=$(echo "$result" | cut -d'|' -f2-)

log "  Score: $score/100"

# Maak issue als score laag is
if [ "$score" -lt 70 ]; then
  create_health_issue "$RHS_REPO" "$score" "$issues"
else
  log "  ✅ Score is goed (≥70)"
fi

log "=== Repo Health Score klaar ==="
