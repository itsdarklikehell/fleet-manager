#!/usr/bin/env bash
# Self-healing helper voor fleet-manager scripts

HEALING_CONFIG="${HEALING_CONFIG:-lib/self-healing/healing-config.json}"

healing_is_enabled() {
  jq -r '.self_healing.enabled // false' "$HEALING_CONFIG" 2>/dev/null || echo "false"
}

healing_handle_failure() {
  local failure_type="$1"
  local context="$2"
  
  if [ "$(healing_is_enabled)" != "true" ]; then
    return 1
  fi
  
  local strategy
  strategy=$(jq -r ".self_healing.strategies.$failure_type.action // empty" "$HEALING_CONFIG")
  
  if [ -z "$strategy" ]; then
    return 1
  fi
  
  echo "  🔧 Self-healing: $failure_type → $strategy"
  
  case "$strategy" in
    restart)
      healing_restart "$context"
      ;;
    wait)
      healing_wait "$context"
      ;;
    cleanup)
      healing_cleanup "$context"
      ;;
    restart_service)
      healing_restart_service "$context"
      ;;
  esac
}

healing_restart() {
  local script="$1"
  local max_attempts
  max_attempts=$(jq -r ".self_healing.strategies.script_failure.max_attempts // 3" "$HEALING_CONFIG")
  local delay
  delay=$(jq -r ".self_healing.retry_delay_seconds // 60" "$HEALING_CONFIG")
  
  for i in $(seq 1 $max_attempts); do
    echo "  🔧 Poging $i/$max_attempts: $script herstarten..."
    if bash "$script" > /dev/null 2>&1; then
      echo "  ✅ $script succesvol herstart"
      return 0
    fi
    sleep "$delay"
  done
  
  echo "  ❌ $script kon niet worden herstart"
  return 1
}

healing_wait() {
  local wait_time
  wait_time=$(jq -r ".self_healing.strategies.api_rate_limit.wait_time_seconds // 300" "$HEALING_CONFIG")
  
  echo "  🔧 Wacht ${wait_time}s voor rate limit reset..."
  sleep "$wait_time"
}

healing_cleanup() {
  local target_usage
  target_usage=$(jq -r ".self_healing.strategies.disk_full.target_usage_percent // 80" "$HEALING_CONFIG")
  
  echo "  🔧 Disk cleanup uitvoeren (target: ${target_usage}%)..."
  bash scripts/auto-fleet-cleanup.sh
}

healing_restart_service() {
  local service="$1"
  local threshold
  threshold=$(jq -r ".self_healing.strategies.memory_high.threshold_percent // 90" "$HEALING_CONFIG")
  
  echo "  🔧 Service $service herstarten (threshold: ${threshold}%)..."
  systemctl --user restart "$service" 2>/dev/null || true
}
