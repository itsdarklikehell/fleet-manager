#!/usr/bin/env bash
# scripts/metrics-collector.sh - Verzamelt metrics over de fleet health
# Telt open issues, PRs, CI failures per repo en houdt API usage bij
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Metrics Collector ==="

# Configuratie
METRICS_DIR="${METRICS_DIR:-$HOME/.github_fleet_metrics}"
mkdir -p "$METRICS_DIR"
METRICS_FILE="$METRICS_DIR/metrics_$(date +%Y%m%d).json"

# Functies
collect_repo_metrics() {
  local repo="$1"
  local metrics=""
  
  # Open issues
  local open_issues
  open_issues=$(gh api "repos/$repo/issues?state=open&per_page=1" -i 2>/dev/null | grep -i '^link:' | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p' || echo "0")
  [ -z "$open_issues" ] && open_issues=0
  
  # Open PRs
  local open_prs
  open_prs=$(gh api "repos/$repo/pulls?state=open&per_page=1" -i 2>/dev/null | grep -i '^link:' | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p' || echo "0")
  [ -z "$open_prs" ] && open_prs=0
  
  # CI failures (laatste 7 dagen)
  local ci_failures
  ci_failures=$(gh run list --repo "$repo" --limit 100 --json status,conclusion --jq '[.[] | select(.status == "completed" and .conclusion == "failure")] | length' 2>/dev/null || echo "0")
  
  # Stars
  local stars
  stars=$(gh api "repos/$repo" --jq '.stargazers_count' 2>/dev/null || echo "0")
  
  # Forks
  local forks
  forks=$(gh api "repos/$repo" --jq '.forks_count' 2>/dev/null || echo "0")
  
  # Laatste commit
  local last_commit
  last_commit=$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].commit.committer.date' 2>/dev/null || echo "unknown")
  
  metrics=$(cat <<EOF
{
  "repo": "$repo",
  "open_issues": $open_issues,
  "open_prs": $open_prs,
  "ci_failures_7d": $ci_failures,
  "stars": $stars,
  "forks": $forks,
  "last_commit": "$last_commit",
  "collected_at": "$(date -Iseconds)"
}
EOF
)
  echo "$metrics"
}

collect_api_metrics() {
  local rate_limit
  rate_limit=$(gh api rate_limit --jq '.resources.core' 2>/dev/null || echo '{"remaining":0,"limit":0,"reset":0}')
  
  local search_limit
  search_limit=$(gh api rate_limit --jq '.resources.search' 2>/dev/null || echo '{"remaining":0,"limit":0,"reset":0}')
  
  cat <<EOF
{
  "api": {
    "core": $rate_limit,
    "search": $search_limit,
    "collected_at": "$(date -Iseconds)"
  }
}
EOF
}

# Hoofdlogica
log "Verzamelen van repo metrics..."

# Haal alle repos op
repos=$(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || echo "")

if [ -z "$repos" ]; then
  log "❌ Geen repos gevonden"
  exit 1
fi

# Verzamel metrics per repo
repo_metrics="["
first=true
for repo in $repos; do
  if [ "$first" = true ]; then
    first=false
  else
    repo_metrics+=","
  fi
  repo_metrics+=$(collect_repo_metrics "$repo")
  log "  ✅ $repo"
done
repo_metrics+="]"

# Verzamel API metrics
api_metrics=$(collect_api_metrics)

# Combineer alles
cat > "$METRICS_FILE" <<EOF
{
  "timestamp": "fleet_health",
  "timestamp": "$(date -Iseconds)",
  "repos": $repo_metrics,
  "api": $(echo "$api_metrics" | jq '.api')
}
EOF

log "✅ Metrics opgeslagen in $METRICS_FILE"

# Genereer samenvatting
total_repos=$(echo "$repo_metrics" | jq 'length')
total_issues=$(echo "$repo_metrics" | jq '[.[].open_issues] | add // 0')
total_prs=$(echo "$repo_metrics" | jq '[.[].open_prs] | add // 0')
total_ci_failures=$(echo "$repo_metrics" | jq '[.[].ci_failures_7d] | add // 0')
total_stars=$(echo "$repo_metrics" | jq '[.[].stars] | add // 0')

log ""
log "=== Fleet Health Samenvatting ==="
log "  Repos: $total_repos"
log "  Open issues: $total_issues"
log "  Open PRs: $total_prs"
log "  CI failures (7d): $total_ci_failures"
log "  Totaal stars: $total_stars"

# Stuur naar Telegram
if [ -n "${TELEGRAM_TOKEN:-}" ]; then
  message="📊 Fleet Health Update

Repos: $total_repos
Open issues: $total_issues
Open PRs: $total_prs
CI failures (7d): $total_ci_failures
Total stars: $total_stars

Metrics: $METRICS_FILE"
  
  for chat_id in $TELEGRAM_CHAT_IDS; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=$chat_id" \
      -d "text=$message" > /dev/null 2>&1 || true
  done
fi
