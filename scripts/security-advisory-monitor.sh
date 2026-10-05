#!/usr/bin/env bash
# scripts/security-advisory-monitor.sh - Security advisory monitoring
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

# Caching (5 min TTL)
CACHE_DIR="${CACHE_DIR:-/tmp/github_fleet_cache}"
CACHE_TTL="${CACHE_TTL:-300}"
mkdir -p "$CACHE_DIR"

cache_get() {
  local key="$1"
  local cache_file="$CACHE_DIR/${key//\//_}"
  if [ -f "$cache_file" ]; then
    local age
    age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [ "$age" -lt "$CACHE_TTL" ]; then
      cat "$cache_file"
      return 0
    fi
  fi
  return 1
}

cache_set() {
  local key="$1"
  local value="$2"
  local cache_file="$CACHE_DIR/${key//\//_}"
  echo "$value" > "$cache_file"
}

# Cleanup temp files
TEMP_FILES=()
cleanup_temp() {
  for f in "${TEMP_FILES[@]}"; do
    [ -f "$f" ] && rm -f "$f"
  done
}
trap cleanup_temp EXIT

# Progress tracking
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0

progress_start() {
  PROGRESS_TOTAL=$1
  PROGRESS_CURRENT=0
  log "  Start: $PROGRESS_TOTAL items te verwerken"
}

progress_update() {
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
  if [ $((PROGRESS_CURRENT % 10)) -eq 0 ] || [ "$PROGRESS_CURRENT" -eq "$PROGRESS_TOTAL" ]; then
    log "  Voortgang: $PROGRESS_CURRENT/$PROGRESS_TOTAL"
  fi
}

# Rate limiting (30 req/min voor GitHub API)
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-$HOME/.github_fleet_rate_limit}"
RATE_LIMIT_MAX="${RATE_LIMIT_MAX:-30}"
RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-60}"

rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - RATE_LIMIT_WINDOW))
  
  local count=0
  local file_time=0
  if [ -f "$RATE_LIMIT_FILE" ]; then
    read -r file_time count < "$RATE_LIMIT_FILE" 2>/dev/null || true
    if [ -z "$file_time" ] || [ "$file_time" -lt "$window_start" ]; then
      count=0
    fi
  fi
  
  count=$((count + 1))
  echo "$now $count" > "$RATE_LIMIT_FILE"
  
  if [ "$count" -ge "$RATE_LIMIT_MAX" ]; then
    log "  Rate limit bereikt ($count requests in laatste ${RATE_LIMIT_WINDOW}s), wacht..."
    sleep "$RATE_LIMIT_WINDOW"
    echo "$((now + RATE_LIMIT_WINDOW)) 0" > "$RATE_LIMIT_FILE"
    return 1
  fi
  return 0
}

# Wrapper voor timeout 15 gh api met rate limiting
gh_api_rate_limited() {
  rate_limit_check || true
  timeout 15 gh api "$@"
}

# Parallelisatie config
MAX_PARALLEL="${MAX_PARALLEL:-4}"

# Helper: wacht tot er ruimte is voor nieuwe job
wait_for_slot() {
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
    sleep 0.1
  done
}

# Helper: wacht op alle jobs
wait_all_jobs() {
  wait
}

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
  
  local clone_ok=false
  for attempt in 1 2 3; do
    if git clone --depth 1 "https://github.com/$repo.git" "$tmpdir/repo" 2>/dev/null; then
      clone_ok=true
      break
    fi
    log "  ⚠️ Clone poging $attempt gefaald, opnieuw proberen..."
  done
  
  if [ "$clone_ok" != true ]; then
    log "  ❌ Kon repo niet clonen na 3 pogingen"
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
    advisory=$(timeout 15 gh api "repos/$repo/dependency-graph/snapshots" --jq '.dependencies[] | select(.packageName == "'"$dep"'") | .packageName' 2>/dev/null || echo "")
    
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
