#!/usr/bin/env bash
# Chaos engineering helper voor fleet-manager scripts

CHAOS_CONFIG="${CHAOS_CONFIG:-lib/chaos/chaos-config.json}"

chaos_is_enabled() {
  local experiment="$1"
  jq -r ".experiments.$experiment.enabled // false" "$CHAOS_CONFIG" 2>/dev/null || echo "false"
}

chaos_should_run() {
  local experiment="$1"
  local frequency="$2"
  
  if [ "$(chaos_is_enabled "$experiment")" != "true" ]; then
    return 1
  fi
  
  local last_run_file="$CHAOS_DIR/last-run-$experiment"
  if [ -f "$last_run_file" ]; then
    local last_run
    last_run=$(cat "$last_run_file")
    local now
    now=$(date +%s)
    local elapsed=$((now - last_run))
    
    case "$frequency" in
      weekly) [ $elapsed -lt 604800 ] && return 1 ;;
      monthly) [ $elapsed -lt 2592000 ] && return 1 ;;
      quarterly) [ $elapsed -lt 7776000 ] && return 1 ;;
    esac
  fi
  
  date +%s > "$last_run_file"
  return 0
}

chaos_simulate_script_failure() {
  local script="$1"
  local failure_rate
  failure_rate=$(jq -r '.experiments.script_failure.failure_rate // 0.1' "$CHAOS_CONFIG")
  
  local hash
  hash=$(echo -n "$script$(date +%s)" | md5sum | cut -d' ' -f1)
  local hash_int
  hash_int=$((16#${hash:0:8}))
  local percentage=$((hash_int % 100))
  local threshold=$(echo "$failure_rate * 100" | bc | cut -d. -f1)
  
  if [ "$percentage" -lt "$threshold" ]; then
    echo "  🧪 Chaos: simuleer failure voor $script"
    return 1
  fi
  return 0
}

chaos_simulate_latency() {
  local latency
  latency=$(jq -r '.experiments.network_latency.latency_ms // 500' "$CHAOS_CONFIG")
  local jitter
  jitter=$(jq -r '.experiments.network_latency.jitter_ms // 100' "$CHAOS_CONFIG")
  
  local actual_latency=$((latency + (RANDOM % (jitter * 2)) - jitter))
  echo "  🧪 Chaos: simuleer ${actual_latency}ms latency"
  sleep "$(echo "scale=3; $actual_latency / 1000" | bc)"
}
