#!/usr/bin/env bash
# scripts/setup-cost-optimization.sh - Cost optimalisatie
# Voegt API kosten tracking en optimalisatie toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Cost Optimization ==="

# Configuratie
COST_DIR="lib/cost"
mkdir -p "$COST_DIR"

# Functies
create_cost_config() {
  local cost_file="$COST_DIR/cost-config.json"
  
  cat > "$cost_file" << 'COST'
{
  "api_costs": {
    "github_api": {
      "cost_per_request": 0.0001,
      "monthly_budget": 10.00,
      "alert_threshold": 0.8
    },
    "openai_api": {
      "cost_per_1k_tokens": 0.002,
      "monthly_budget": 50.00,
      "alert_threshold": 0.8
    },
    "telegram_api": {
      "cost_per_message": 0.00001,
      "monthly_budget": 1.00,
      "alert_threshold": 0.8
    }
  },
  "optimization": {
    "cache_ttl_seconds": 3600,
    "batch_size": 100,
    "rate_limit_buffer": 0.9
  }
}
COST
  
  echo "  ✅ Cost config gemaakt"
}

create_cost_helper() {
  local cost_helper="$COST_DIR/cost-helper.sh"
  
  cat > "$cost_helper" << 'COSTHELPER'
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
COSTHELPER
  
  chmod +x "$cost_helper"
  echo "  ✅ Cost helper gemaakt"
}

# Hoofdlogica
create_cost_config
create_cost_helper

echo ""
echo "✅ Cost optimization setup klaar"
