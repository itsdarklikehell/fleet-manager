#!/usr/bin/env bash
# scripts/auto-issue-responder.sh - Automatische issue response system
# Post sjabblonen antwoorden op veelvoorkomende issue patronen
set -euo pipefail
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Issue Responder ==="

# Configuratie
AIR_ENABLED="${AIR_ENABLED:-yes}"
AIR_DRY_RUN="${AIR_DRY_RUN:-no}"
AIR_LIMIT="${AIR_LIMIT:-50}"
AIR_DAYS="${AIR_DAYS:-1}"

SINCE=$(date -d "$AIR_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${AIR_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Responspatronen (regex -> sjabblon bestand)
declare -A RESPONSE_PATTERNS
RESPONSE_PATTERNS["bug"]="responses/bug_report.md"
RESPONSE_PATTERNS["feature request"]="responses/feature_request.md"
RESPONSE_PATTERNS["question"]="responses/question.md"
RESPONSE_PATTERNS["help"]="responses/question.md"
RESPONSE_PATTERNS["error"]="responses/bug_report.md"
RESPONSE_PATTERNS["crash"]="responses/bug_report.md"
RESPONSE_PATTERNS["support"]="responses/question.md"

# Functie: issue categoriseren
categorize_issue() {
  local title="$1"
  local body="$2"
  local combined="${title} ${body}"
  combined_lower=$(echo "$combined" | tr '[:upper:]' '[:lower:]')
  
  for pattern in "${!RESPONSE_PATTERNS[@]}"; do
    if echo "$combined_lower" | grep -qE "$pattern"; then
      echo "$RESPONSE_PATTERNS[$pattern]"
      return
    fi
  done
  
  echo ""
}

# Functie: check of al geresponderd is
has_bot_response() {
  local repo="$1"
  local issue_number="$2"
  
  local comments
  comments=$(gh api "repos/$repo/issues/$issue_number/comments" --jq '.[] | select(.user.type == "Bot" or .user.login | test("bot|auto")) | .id' 2>/dev/null || echo "")
  
  if [ -n "$comments" ]; then
    return 0
  fi
  return 1
}

# Functie: auto-respond op issue
respond_to_issue() {
  local repo="$1"
  local issue_number="$2"
  local template="$3"
  local title="$4"
  
  log "  Reponde op issue #$issue_number: $title"
  
  if [ "$AIR_DRY_RUN" = "yes" ]; then
    log "    [DRY RUN] Zou responden met $template"
    return 0
  fi
  
  # Check if template exists
  local template_path="$(dirname "$0")/../templates/$template"
  if [ ! -f "$template_path" ]; then
    log "    ⚠️ Template niet gevonden: $template"
    return 1
  fi
  
  # Check if already responded
  if has_bot_response "$repo" "$issue_number"; then
    log "    ℹ️ Al eerder gereageerd, overslaan"
    return 0
  fi
  
  # Read template and post comment
  local body
  body=$(cat "$template_path")
  
  gh api "repos/$repo/issues/$issue_number/comments" \
    -X POST \
    -f "body=$body" \
    2>/dev/null
  
  if [ $? -eq 0 ]; then
    log "    ✅ Reactie geplaatst"
  else
    log "    ❌ Reactie mislukt"
  fi
}

# Hoofdlogica
if [ "$AIR_ENABLED" != "yes" ]; then
  log "Auto issue responder uitgeschakeld"
  exit 0
fi

for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  log "Scanning issues in $kr..."
  
  # Get recent issues (created in last N days)
  issues=$(gh search issues --repo "$kr" --state open --limit "$AIR_LIMIT" \
    --json number,title,body,author,createdAt \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.number)|\(.title)|\(.body|tr -d '\\r\\n')|\(.author.login)\"" \
    2>/dev/null || echo "")
  
  if [ -z "$issues" ]; then
    log "  ✅ Geen nieuwe issues"
    continue
  fi
  
  total_responded=0
  echo "$issues" | while IFS='|' read -r number title body author; do
    [ -z "$number" ] && continue
    
    # Skip bot issues
    case "$author" in
      *bot*|*auto*) continue ;;
    esac
    
    template=$(categorize_issue "$title" "$body")
    if [ -n "$template" ]; then
      respond_to_issue "$kr" "$number" "$template" "$title"
      total_responded=$((total_responded + 1))
    fi
  done
  
  log "  📬 $kr: $total_responded issues geautomatiseerd beantwoord"
done

log "=== Auto Issue Responder klaar ==="
