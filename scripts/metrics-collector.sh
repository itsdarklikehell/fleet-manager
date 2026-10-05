#!/usr/bin/env bash
# scripts/metrics-collector.sh - Fleet health metrics (GEOPTIMALISEERD)
# OPTIMISATIES: parallelisatie, rate limiting, KEY_REPOS only, timeout per call

set -euo pipefail

DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Metrics Collector (geoptimaliseerd) ==="

MAX_PARALLEL="${MAX_PARALLEL:-4}"
METRICS_FILE="${METRICS_FILE:-/tmp/fleet_metrics.json}"
GH_TIMEOUT="${GH_TIMEOUT:-10}"

# Rate limiter
RATE_LIMIT_FILE="${RATE_LIMIT_FILE:-/tmp/github_fleet_metrics_rate_limit}"
rate_limit_check() {
  local now
  now=$(date +%s)
  local window_start=$((now - 60))
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
  if [ "$count" -ge 30 ]; then
    log "  Rate limit bereikt, wacht 60s..."
    sleep 60
    echo "$now 0" > "$RATE_LIMIT_FILE"
  fi
}

# Parallelle metrics collectie (alleen KEY_REPOS)
collect_repo_metrics() {
  local repo="$1"
  
  rate_limit_check
  
  local open_issues open_prs ci_failures
  open_issues=$(timeout "$GH_TIMEOUT" gh issue list --repo "$repo" --state open --limit 1 --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  open_prs=$(timeout "$GH_TIMEOUT" gh pr list --repo "$repo" --state open --limit 1 --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  ci_failures=$(timeout "$GH_TIMEOUT" gh run list --repo "$repo" --status failure --limit 1 --json databaseId 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  
  echo "{"repo":"$repo","open_issues":$open_issues,"open_prs":$open_prs,"ci_failures":$ci_failures}"
}

# Fase 1: Repos ophalen
log "Fase 1: Repos ophalen..."

rate_limit_check

# Gebruik KEY_REPOS in plaats van alle 200+ repos
if [ -z "${KEY_REPOS:-}" ]; then
  log "  KEY_REPOS niet gedefinieerd, gebruik standaard set"
  KEY_REPOS=(
    "itsdarklikehell/hermes-desktop"
    "itsdarklikehell/mission-control"
    "itsdarklikehell/hermes-agent"
    "itsdarklikehell/dnd-utils"
    "itsdarklikehell/clawhub"
    "itsdarklikehell/ci-templates"
  )
fi

repo_count=${#KEY_REPOS[@]}
log "  $repo_count repos gevonden (KEY_REPOS)"

# Fase 2: Parallel metrics collectie
log "Fase 2: Parallel metrics collectie (max=$MAX_PARALLEL)..."

metrics_array="[]"

for repo in "${KEY_REPOS[@]}"; do
  log "  Repo: $repo"
  
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$MAX_PARALLEL" ]; do
    sleep 0.2
  done
  
  collect_repo_metrics "$repo" &
done
wait

# Fase 3: Samenvatting
log "Fase 3: Samenvatting..."

total_issues=0
total_prs=0
total_ci_failures=0

# Lees metrics van temp bestanden
for f in /tmp/fleet_metrics_*.json; do
  [ -f "$f" ] || continue
  issues=$(jq -r '.open_issues // 0' "$f" 2>/dev/null || echo "0")
  prs=$(jq -r '.open_prs // 0' "$f" 2>/dev/null || echo "0")
  ci=$(jq -r '.ci_failures // 0' "$f" 2>/dev/null || echo "0")
  total_issues=$((total_issues + issues))
  total_prs=$((total_prs + prs))
  total_ci_failures=$((total_ci_failures + ci))
  rm -f "$f"
done

log "  Totaal open issues: $total_issues"
log "  Totaal open PRs: $total_prs"
log "  Totaal CI failures: $total_ci_failures"

# Sla metrics op
cat > "$METRICS_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_repos": $repo_count,
  "total_open_issues": $total_issues,
  "total_open_prs": $total_prs,
  "total_ci_failures": $total_ci_failures
}
EOF

log "  Metrics opgeslagen: $METRICS_FILE"
log "=== Metrics Collector complete ==="

if [ "$TELEGRAM_REPORT_ENABLED" = "yes" ]; then
  send_telegram_message "📊 *Metrics Collector* (geoptimaliseerd)

*Repos:* $repo_count
*Open issues:* $total_issues
*Open PRs:* $total_prs
*CI failures:* $total_ci_failures

📋 Volledig log: $LOG_FILE" || true
fi
