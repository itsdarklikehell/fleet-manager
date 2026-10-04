#!/usr/bin/env bash
# Cost optimization helper voor fleet-manager scripts

COST_CONFIG="${COST_CONFIG:-lib/cost/cost-config.json}"
COST_FILE="${COST_FILE:-$HOME/.github_fleet_metrics/cost-tracking.jsonl}"

cost_record_api_call() {
  local api_name="$1"
  local cost_per_request
  cost_per_request=$(jq -r ".api_costs.$api_name.cost_per_request // 0.0001" "$COST_CONFIG")
  
  local timestamp
  timestamp=$(date -Iseconds)
  
  echo "{\"timestamp\":\"$timestamp\",\"api\":\"$api_name\",\"cost\":$cost_per_request}" >> "$COST_FILE"
}

cost_get_monthly_total() {
  local api_name="$1"
  local month
  month=$(date +%Y-%m)
  
  local total
  total=$(grep "\"api\":\"$api_name\"" "$COST_FILE" 2>/dev/null | grep "\"timestamp\":\"$month" | jq -s 'map(.cost) | add // 0' 2>/dev/null || echo "0")
  
  echo "$total"
}

cost_check_budget() {
  local api_name="$1"
  local budget
  budget=$(jq -r ".api_costs.$api_name.monthly_budget // 10.00" "$COST_CONFIG")
  local threshold
  threshold=$(jq -r ".api_costs.$api_name.alert_threshold // 0.8" "$COST_CONFIG")
  
  local total
  total=$(cost_get_monthly_total "$api_name")
  
  local limit
  limit=$(echo "$budget * $threshold" | bc)
  
  if (( $(echo "$total > $limit" | bc -l) )); then
    echo "  ⚠️ Cost alert: $api_name heeft $total van $budget budget gebruikt"
    return 1
  fi
  
  echo "  ✅ Cost OK: $api_name heeft $total van $budget budget gebruikt"
  return 0
}

cost_optimize_api_calls() {
  local api_name="$1"
  local remaining
  remaining=$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo "0")
  local limit
  limit=$(gh api rate_limit --jq '.resources.core.limit' 2>/dev/null || echo "5000")
  
  local buffer
  buffer=$(jq -r '.optimization.rate_limit_buffer // 0.9' "$COST_CONFIG")
  
  local safe_limit
  safe_limit=$(echo "$limit * $buffer" | bc | cut -d. -f1)
  
  if [ "$remaining" -lt "$safe_limit" ]; then
    echo "  ⚠️ Rate limit bijna bereikt ($remaining/$limit), optimaliseer API calls"
    return 1
  fi
  
  return 0
}
