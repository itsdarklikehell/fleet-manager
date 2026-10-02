#!/usr/bin/env bash
# scripts/ci-failure-summaries.sh - Samenvattingen van CI failures
# Haal CI failures op en genereer leesbare samenvattingen
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== CI Failure Summaries ==="

# Configuratie
CI_REPOS="${CI_REPOS:-${KEY_REPOS[@]}}"
CI_LIMIT="${CI_LIMIT:-10}"
CI_DAYS="${CI_DAYS:-7}"

SINCE=$(date -d "$CI_DAYS days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${CI_DAYS}d '+%Y-%m-%d' 2>/dev/null || echo "2025-01-01")

# Functies
summarize_failure() {
  local repo="$1"
  local run_id="$2"
  local org="${repo%%/*}"
  set_repo_token "$org"
  
  # Haal run info op
  local run_name run_status run_conclusion run_url
  run_name=$(gh run view "$run_id" --repo "$repo" --json displayTitle --jq '.displayTitle' 2>/dev/null || echo "Unknown")
  run_status=$(gh run view "$run_id" --repo "$repo" --json status --jq '.status' 2>/dev/null || echo "unknown")
  run_conclusion=$(gh run view "$run_id" --repo "$repo" --json conclusion --jq '.conclusion' 2>/dev/null || echo "unknown")
  run_url=$(gh run view "$run_id" --repo "$repo" --json url --jq '.url' 2>/dev/null || echo "")
  
  # Haal failed jobs op
  local failed_jobs
  failed_jobs=$(gh run view "$run_id" --repo "$repo" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | "\(.name): \(.conclusion)"' 2>/dev/null || echo "")
  
  # Haal logs op voor de eerste failed job
  local error_logs=""
  if [ -n "$failed_jobs" ]; then
    local first_job_id
    first_job_id=$(gh run view "$run_id" --repo "$repo" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | .databaseId' 2>/dev/null | head -1)
    if [ -n "$first_job_id" ]; then
      error_logs=$(gh run view --repo "$repo" --job "$first_job_id" --log-failed 2>/dev/null | tail -20 || echo "")
    fi
  fi
  
  # Genereer samenvatting
  local summary
  summary=$(cat <<EOF
## 🔴 CI Failure Samenvatting

**Repo:** $repo
**Run:** $run_name
**Status:** $run_status
**Conclusie:** $run_conclusion
**URL:** $run_url

### Failed Jobs

$(if [ -n "$failed_jobs" ]; then
  echo "$failed_jobs"
else
  echo "Geen failed jobs gevonden"
fi)

### Error Logs (laatste 20 regels)

\`\`\`
$(if [ -n "$error_logs" ]; then
  echo "$error_logs"
else
  echo "Geen logs beschikbaar"
fi)
\`\`\`

---
*Deze samenvatting is automatisch gegenereerd door de GitHub Fleet Manager.*
EOF
)
  
  echo "$summary"
  log "  Samenvatting gegenereerd voor run $run_id in $repo"
}

# Hoofdlogica
for repo in "${CI_REPOS[@]}"; do
  org="${repo%%/*}"
  set_repo_token "$org"
  
  log "Checking CI failures in $repo..."
  
  # Haal recente failed runs op
  failed_runs=$(gh run list --repo "$repo" --status failure --limit "$CI_LIMIT" --json databaseId,displayTitle,createdAt --jq ".[] | select(.createdAt >= \"${SINCE}\") | \"\(.databaseId) \(.displayTitle)\"" 2>/dev/null || echo "")
  
  if [ -n "$failed_runs" ]; then
    echo "$failed_runs" | while read -r line; do
      run_id=$(echo "$line" | awk '{print $1}')
      summarize_failure "$repo" "$run_id"
    done
  else
    log "  Geen CI failures gevonden in de laatste $CI_DAYS dagen"
  fi
done

log "=== CI Failure Summaries klaar ==="
