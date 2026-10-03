#!/usr/bin/env bash
# scripts/auto-labeling.sh - Automatische GitHub labeling
# Label issues en PRs op basis van patronen en bestandsstructuur
set -euo pipefail
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Labeling ==="

# Configuratie
AL_ENABLED="${AL_ENABLED:-yes}"
AL_DRY_RUN="${AL_DRY_RUN:-no}"
AL_LIMIT="${AL_LIMIT:-30}"
AL_DAYS="${AL_DAYS:-1}"

SINCE=$(date -d "$AL_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${AL_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Label patronen: keyword -> label
# Issues
declare -A ISSUE_LABELS
ISSUE_LABELS["bug"]="bug"
ISSUE_LABELS["crash"]="bug"
ISSUE_LABELS["error"]="bug"
ISSUE_LABELS["feature"]="enhancement"
ISSUE_LABELS["feature request"]="enhancement"
ISSUE_LABELS["improvement"]="enhancement"
ISSUE_LABELS["enhancement"]="enhancement"
ISSUE_LABELS["question"]="question"
ISSUE_LABELS["help"]="question"
ISSUE_LABELS["support"]="question"
ISSUE_LABELS["documentation"]="documentation"
ISSUE_LABELS["docs"]="documentation"
ISSUE_LABELS["performance"]="performance"
ISSUE_LABELS["slow"]="performance"

# PR labels based on file changes
declare -A PR_FILE_LABELS
PR_FILE_LABELS["Dockerfile"]="infrastructure"
PR_FILE_LABELS["docker-compose"]="infrastructure"
PR_FILE_LABELS["Makefile"]="build"
PR_FILE_LABELS["\.sh"]="shell-script"
PR_FILE_LABELS["\.py"]="python"
PR_FILE_LABELS["\.js"]="javascript"
PR_FILE_LABELS["\.ts"]="typescript"
PR_FILE_LABELS["\.go"]="go"
PR_FILE_LABELS["\.rs"]="rust"
PR_FILE_LABELS["README"]="documentation"
PR_FILE_LABELS["\.md"]="documentation"
PR_FILE_LABELS["requirements"]="dependencies"
PR_FILE_LABELS["package-lock"]="dependencies"

# Function: label issue based on title/body
label_issue() {
  local repo="$1"
  local issue_number="$2"
  local title="$3"
  local body="$4"
  
  local combined="${title} ${body}"
  local combined_lower
  combined_lower=$(echo "$combined" | tr '[:upper:]' '[:lower:]')
  
  # Check existing labels
  local existing_labels
  existing_labels=$(gh api "repos/$repo/issues/$issue_number" --jq '.labels[].name' 2>/dev/null || echo "")
  
  for pattern in "${!ISSUE_LABELS[@]}"; do
    if echo "$combined_lower" | grep -qE "$pattern"; then
      local label="${ISSUE_LABELS[$pattern]}"
      
      # Skip if label already exists
      if echo "$existing_labels" | grep -q "^${label}$"; then
        continue
      fi
      
      log "  Labeling issue #$issue_number with '$label'"
      
      if [ "$AL_DRY_RUN" != "yes" ]; then
        gh api "repos/$repo/issues/$issue_number/labels" \
          -X POST \
          -f "labels=[\"$label\"]" \
          2>/dev/null
        
        if [ $? -eq 0 ]; then
          log "    ✅ Label '$label' toegevoegd"
        else
          log "    ❌ Label mislukt"
        fi
      else
        log "    [DRY RUN] Zou label '$label' toevoegen"
      fi
    fi
  done
}

# Function: label PR based on changed files
label_pr() {
  local repo="$1"
  local pr_number="$2"
  
  # Check existing labels
  local existing_labels
  existing_labels=$(gh api "repos/$repo/issues/$pr_number" --jq '.labels[].name' 2>/dev/null || echo "")
  
  # Get changed files
  local changed_files
  changed_files=$(gh api "repos/$repo/pulls/$pr_number/files" --jq '.[].filename' 2>/dev/null || echo "")
  
  if [ -z "$changed_files" ]; then
    return
  fi
  
  for pattern in "${!PR_FILE_LABELS[@]}"; do
    if echo "$changed_files" | grep -qE "$pattern"; then
      local label="${PR_FILE_LABELS[$pattern]}"
      
      # Skip if label already exists
      if echo "$existing_labels" | grep -q "^${label}$"; then
        continue
      fi
      
      log "  Labeling PR #$pr_number with '$label' (match: $pattern)"
      
      if [ "$AL_DRY_RUN" != "yes" ]; then
        gh api "repos/$repo/issues/$pr_number/labels" \
          -X POST \
          -f "labels=[\"$label\"]" \
          2>/dev/null
        
        if [ $? -eq 0 ]; then
          log "    ✅ Label '$label' toegevoegd"
        else
          log "    ❌ Label mislukt"
        fi
      else
        log "    [DRY RUN] Zou label '$label' toevoegen"
      fi
    fi
  done
}

# Hoofdlogica
if [ "$AL_ENABLED" != "yes" ]; then
  log "Auto labeling uitgeschakeld"
  exit 0
fi

for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  log "Labeling issues in $kr..."
  
  # Get recent issues
  issues=$(gh search issues --repo "$kr" --state open --limit "$AL_LIMIT" \
    --json number,title,body,author,createdAt \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.number)|\(.title)|\(.body // \"\")|\(.author.login)\"" \
    2>/dev/null || echo "")
  
  if [ -n "$issues" ]; then
    echo "$issues" | while IFS='|' read -r number title body author; do
      [ -z "$number" ] && continue
      case "$author" in
        *bot*|*auto*) continue ;;
      esac
      label_issue "$kr" "$number" "$title" "$body"
    done
  fi
  
  log "Labeling PRs in $kr..."
  
  # Get recent PRs
  prs=$(gh search prs --repo "$kr" --state open --limit "$AL_LIMIT" \
    --json number,title,createdAt,author \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.number)|\(.title)|\(.author.login)\"" \
    2>/dev/null || echo "")
  
  if [ -n "$prs" ]; then
    echo "$prs" | while IFS='|' read -r number title author; do
      [ -z "$number" ] && continue
      case "$author" in
        *bot*|*auto*) continue ;;
      esac
      label_pr "$kr" "$number"
    done
  fi
done

log "=== Auto Labeling klaar ==="
