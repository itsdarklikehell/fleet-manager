#!/usr/bin/env bash
# scripts/inbox-trends.sh - Trends in inbox items
# Toont trends in issues, PRs en activiteit over tijd
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Inbox Trends ==="

TREND_DAYS="${TREND_DAYS:-30}"
# shellcheck disable=SC2206
TREND_REPOS=( ${TREND_REPOS:-${KEY_REPOS[@]}} )
TODAY=$(date '+%Y-%m-%d')
SINCE=$(date -d "$TREND_DAYS days ago" '+%Y-%m-%dT00:00:00Z' 2>/dev/null || date -v-${TREND_DAYS}d '+%Y-%m-%dT00:00:00Z' 2>/dev/null || echo "${TODAY}T00:00:00Z")

# Fase 1: Verzamel trend data
log "Fase 1: Verzamel trend data..."

# Dagelijkse issue counts
declare -A daily_issues
declare -A daily_prs
declare -A daily_comments

for kr in "${TREND_REPOS[@]}"; do
  org="${kr%%/*}"
  set_repo_token "$org"
  
  # Issues per dag
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    day=$(echo "$line" | cut -d'|' -f1)
    count=$(echo "$line" | cut -d'|' -f2)
    daily_issues[$day]=$(( ${daily_issues[$day]:-0} + count ))
  done < <(gh issue list --repo "$kr" --state open --limit 100 --json createdAt --jq '.[] | .createdAt[:10]' 2>/dev/null | sort | uniq -c | awk '{print $2"|"$1}')
  
  # PRs per dag
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    day=$(echo "$line" | cut -d'|' -f1)
    count=$(echo "$line" | cut -d'|' -f2)
    daily_prs[$day]=$(( ${daily_prs[$day]:-0} + count ))
  done < <(gh pr list --repo "$kr" --state open --limit 100 --json createdAt --jq '.[] | .createdAt[:10]' 2>/dev/null | sort | uniq -c | awk '{print $2"|"$1}')
done

# Fase 2: Bereken trends
log "Fase 2: Bereken trends..."

# Gemiddelde per dag
total_issues=0
total_prs=0
days_with_data=0

for day in "${!daily_issues[@]}"; do
  total_issues=$((total_issues + ${daily_issues[$day]}))
  days_with_data=$((days_with_data + 1))
done

for day in "${!daily_prs[@]}"; do
  total_prs=$((total_prs + ${daily_prs[$day]}))
done

avg_issues=0
avg_prs=0
if [ "$days_with_data" -gt 0 ]; then
  avg_issues=$((total_issues / days_with_data))
  avg_prs=$((total_prs / days_with_data))
fi

# Fase 3: Top dagen
log "Fase 3: Top dagen..."

top_issue_day=""
top_issue_count=0
for day in "${!daily_issues[@]}"; do
  if [ "${daily_issues[$day]}" -gt "$top_issue_count" ]; then
    top_issue_count=${daily_issues[$day]}
    top_issue_day=$day
  fi
done

top_pr_day=""
top_pr_count=0
for day in "${!daily_prs[@]}"; do
  if [ "${daily_prs[$day]}" -gt "$top_pr_count" ]; then
    top_pr_count=${daily_prs[$day]}
    top_pr_day=$day
  fi
done

# Fase 4: Verstuur rapport
log "Fase 4: Verstuur rapport..."

trend_report="📈 *Inbox Trends* — Laatste $TREND_DAYS dagen

📊 *Gemiddelden per dag*
• Issues: $avg_issues
• PRs: $avg_prs

🔥 *Top dagen*
• Meeste issues: $top_issue_day ($top_issue_count)
• Meeste PRs: $top_pr_day ($top_pr_count)

📋 Volledig log: $LOG_FILE"

send_telegram_message "$trend_report" || true

log "=== Inbox Trends complete ==="
