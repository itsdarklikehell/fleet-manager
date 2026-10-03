#!/usr/bin/env bash
# scripts/code-quality-metrics.sh - Code quality metrics
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Code Quality Metrics ==="

# Configuratie
CQM_ENABLED="${CQM_ENABLED:-yes}"
CQM_DRY_RUN="${CQM_DRY_RUN:-yes}"
CQM_REPO="${CQM_REPO:-}"
CQM_ORG="${CQM_ORG:-itsdarklikehell}"

# Functies
calculate_metrics() {
  local repo="$1"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Calculating code quality metrics for $repo..."
  
  local tmpdir
  tmpdir=$(mktemp -d)
  
  if ! git clone --depth 1 "https://github.com/$repo.git" "$tmpdir/repo" 2>/dev/null; then
    log "  ❌ Kon repo niet clonen"
    rm -rf "$tmpdir"
    return 1
  fi
  
  cd "$tmpdir/repo"
  
  # 1. Lines of Code
  local loc
  loc=$(find . \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
  loc=${loc:-0}
  
  # 2. Cyclomatic complexity (geschat)
  local complexity
  complexity=$(find . \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | xargs grep -c "if\|for\|while\|case\|catch" 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
  complexity=${complexity:-0}
  
  # 3. Code duplication (geschat)
  local duplication
  duplication=$(find . \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | xargs md5sum 2>/dev/null | awk '{print $1}' | sort | uniq -d | wc -l)
  duplication=${duplication:-0}
  
  # 4. Test coverage (geschat)
  local test_files
  test_files=$(find . \( -name "test_*.py" -o -name "*_test.py" -o -name "*.test.js" -o -name "*.spec.ts" \) 2>/dev/null | wc -l)
  test_files=${test_files:-0}
  local source_files
  source_files=$(find . \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | grep -v test | wc -l)
  source_files=${source_files:-0}
  local coverage=0
  if [ "$source_files" -gt 0 ]; then
    coverage=$((test_files * 100 / source_files))
  fi
  
  # 5. Technical debt ratio (geschat)
  local debt_ratio=0
  if [ "$loc" -gt 0 ]; then
    debt_ratio=$((complexity * 100 / loc))
  fi
  
  cd - >/dev/null
  rm -rf "$tmpdir"
  
  echo "LOC: $loc"
  echo "Complexity: $complexity"
  echo "Duplication: $duplication"
  echo "Coverage: $coverage%"
  echo "Debt Ratio: $debt_ratio%"
}

create_metrics_issue() {
  local repo="$1"
  local metrics="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Creating metrics issue for $repo..."
  
  if [ "$CQM_DRY_RUN" = "yes" ]; then
    log "  [DRY RUN] Would create metrics issue"
    return 0
  fi
  
  local body
  body=$(cat <<EOF
## 📊 Code Quality Metrics

De code quality metrics voor deze repository:

$metrics

### Aanbevelingen

1. Voeg meer tests toe voor betere dekking
2. Refactor complexe functies
3. Verwijder duplicate code
4. Gebruik linters en formatters
5. Voeg type hints toe (Python) of TypeScript (JavaScript)

---
*Deze metrics zijn automatisch berekend door de GitHub Fleet Manager.*
EOF
)
  
  gh issue create \
    --repo "$repo" \
    --title "📊 Code quality metrics" \
    --body "$body" \
    --label "quality" 2>/dev/null && log "  ✅ Metrics issue aangemaakt" || log "  ❌ Kon metrics issue niet aanmaken"
}

# Hoofdlogica
if [ "$CQM_ENABLED" != "yes" ]; then
  log "Code quality metrics uitgeschakeld"
  exit 0
fi

if [ -z "$CQM_REPO" ]; then
  log "CQM_REPO niet ingesteld - skipping"
  exit 0
fi

log "Starting code quality metrics for $CQM_REPO..."

# Bereken metrics
metrics=$(calculate_metrics "$CQM_REPO")

# Maak issue
create_metrics_issue "$CQM_REPO" "$metrics"

log "=== Code Quality Metrics klaar ==="
