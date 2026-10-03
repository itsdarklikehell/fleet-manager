#!/usr/bin/env bash
# scripts/auto-assignment.sh - Automatische issue/PR assignment
# Assignment op basis van expertise matrix en round-robin
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Assignment ==="

# Configuratie
AA_ENABLED="${AA_ENABLED:-yes}"
AA_DRY_RUN="${AA_DRY_RUN:-no}"
AA_LIMIT="${AA_LIMIT:-30}"
AA_DAYS="${AA_DAYS:-1}"

SINCE=$(date -d "$AA_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${AA_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Expertise matrix: path pattern -> expert GitHub username
declare -A EXPERTISE_MAP
EXPERTISE_MAP["\.py$"]="python_expert"
EXPERTISE_MAP["\.sh$"]="shell_expert"
EXPERTISE_MAP["\.js$|package.json"]="js_expert"
EXPERTISE_MAP["\.ts$|tsconfig"]="ts_expert"
EXPERTISE_MAP["Dockerfile"]="devops_expert"
EXPERTISE_MAP["\.md$"]="docs_expert"
EXPERTISE_MAP["\.yml$|\.yaml$"]="ops_expert"
EXPERTISE_MAP["Makefile"]="build_expert"
EXPERTISE_MAP["\.rs$"]="rust_expert"
EXPERTISE_MAP["\.go$"]="go_expert"

# Default experts per repo (override expertise map)
declare -A DEFAULT_EXPERTS
DEFAULT_EXPERTS["itssdarklikehell/my-resume"]="itsdarklikehell"
DEFAULT_EXPERTS["hmol33/my-resume"]="hmol33"

# Round-robin state file
RR_STATE_FILE="/tmp/fleet_auto_assign_rr.json"

# Function: get expert for file pattern
get_expert_for_file() {
  local filename="$1"
  local repo="$2"
  
  # Check repo-specific experts first
  if [ -n "${DEFAULT_EXPERTS[$repo]:-}" ]; then
    echo "${DEFAULT_EXPERTS[$repo]}"
    return
  fi
  
  # Check expertise matrix
  for pattern in "${!EXPERTISE_MAP[@]}"; do
    if echo "$filename" | grep -qE "$pattern"; then
      echo "${EXPERTISE_MAP[$pattern]}"
      return
    fi
  done
  
  # Return repo default
  echo ""
}

# Function: round-robin assignee
get_round_robin_assignee() {
  local repo="$1"
  local assignees_str="${ROUND_ROBIN_ASSIGNEES:-}"
  
  if [ -z "$assignees_str" ]; then
    echo ""
    return
  fi
  
  # Convert to array
  IFS=',' read -ra assignees <<< "$assignees_str"
  local count=${#assignees[@]}
  
  if [ "$count" -eq 0 ]; then
    echo ""
    return
  fi
  
  # Read current index
  local idx=0
  if [ -f "$RR_STATE_FILE" ]; then
    idx=$(python3 -c "
import json
try:
  with open('$RR_STATE_FILE') as f:
    data = json.load(f)
  print(data.get('$repo', 0))
except:
  print(0)
" 2>/dev/null || echo "0")
  fi
  
  local assignee="${assignees[$idx]}"
  
  # Write next index
  next_idx=$(( (idx + 1) % count ))
  python3 -c "
import json
data = {}
try:
  with open('$RR_STATE_FILE') as f:
    data = json.load(f)
except:
  pass
data['$repo'] = next_idx
with open('$RR_STATE_FILE', 'w') as f:
  json.dump(data, f)
" 2>/dev/null
  
  echo "$assignee"
}

# Function: assign issue
assign_issue() {
  local repo="$1"
  local issue_number="$2"
  local expert_rule="$3"
  local assignee="$4"
  
  if [ -z "$assignee" ]; then
    return
  fi
  
  log "  Assigning issue #$issue_number to $assignee (rule: $expert_rule)"
  
  if [ "$AA_DRY_RUN" != "yes" ]; then
    gh api "repos/$repo/issues/$issue_number" \
      -X PATCH \
      -f "assignee=$assignee" \
      2>/dev/null
    
    if [ $? -eq 0 ]; then
      log "    ✅ Toegewezen aan $assignee"
    else
      log "    ❌ Assignment mislukt"
    fi
  else
    log "    [DRY RUN] Zou toewijzen aan $assignee"
  fi
}

# Function: assign PR
assign_pr() {
  local repo="$1"
  local pr_number="$2"
  local assignee="$3"
  
  if [ -z "$assignee" ]; then
    return
  fi
  
  log "  Assigning PR #$pr_number to $assignee"
  
  if [ "$AA_DRY_RUN" != "yes" ]; then
    gh api "repos/$repo/pulls/$pr_number" \
      -X PATCH \
      -f "assignee=$assignee" \
      2>/dev/null
    
    if [ $? -eq 0 ]; then
      log "    ✅ Toegewezen aan $assignee"
    else
      log "    ❌ Assignment mislukt"
    fi
  else
    log "    [DRY RUN] Zou toewijzen aan $assignee"
  fi
}

# Function: skip if already assigned
is_assigned() {
  local repo="$1"
  local number="$2"
  local is_pr="${3:-false}"
  
  local endpoint="repos/$repo/issues/$number"
  if [ "$is_pr" = "true" ]; then
    endpoint="repos/$repo/pulls/$number"
  fi
  
  local assignees
  assignees=$(gh api "$endpoint" --jq '.assignees | length' 2>/dev/null || echo "0")
  
  if [ "$assignees" -gt 0 ]; then
    return 0
  fi
  return 1
}

# Hoofdlogica
if [ "$AA_ENABLED" != "yes" ]; then
  log "Auto assignment uitgeschakeld"
  exit 0
fi

for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  log "Assigning issues in $kr..."
  
  # Get recent unassigned issues
  issues=$(gh search issues --repo "$kr" --state open --limit "$AA_LIMIT" \
    --json number,title,assignees,createdAt \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | select(.assignees | length == 0) | \"\(.number)|\(.title)\"" \
    2>/dev/null || echo "")
  
  if [ -n "$issues" ]; then
    echo "$issues" | while IFS='|' read -r number title; do
      [ -z "$number" ] && continue
      
      # Get assignee via round-robin
      assignee=$(get_round_robin_assignee "$kr")
      
      if [ -n "$assignee" ]; then
        assign_issue "$kr" "$number" "round-robin" "$assignee"
      else
        log "  ℹ️ Geen round-robin assignees geconfigureerd voor $kr"
      fi
    done
  fi
  
  log "Assigning PRs in $kr..."
  
  # Get recent unassigned PRs
  prs=$(gh search prs --repo "$kr" --state open --limit "$AA_LIMIT" \
    --json number,title,assignees,createdAt \
    --jq ".[] | select(.createdAt >= \"${SINCE}\") | select(.assignees | length == 0) | \"\(.number)|\(.title)\"" \
    2>/dev/null || echo "")
  
  if [ -n "$prs" ]; then
    echo "$prs" | while IFS='|' read -r number title; do
      [ -z "$number" ] && continue
      
      assignee=$(get_round_robin_assignee "$kr")
      
      if [ -n "$assignee" ]; then
        assign_pr "$kr" "$number" "$assignee"
      fi
    done
  fi
done

log "=== Auto Assignment klaar ==="
