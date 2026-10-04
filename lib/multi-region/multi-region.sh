#!/usr/bin/env bash
# Multi-region helper voor fleet-manager scripts

REGION_CONFIG="${REGION_CONFIG:-lib/multi-region/regions.json}"

region_get_primary() {
  jq -r '.regions | to_entries | map(select(.value.enabled == true)) | sort_by(.value.priority) | .[0].key' "$REGION_CONFIG" 2>/dev/null || echo "eu-west"
}

region_get_endpoint() {
  local region="$1"
  jq -r ".regions.$region.endpoint // empty" "$REGION_CONFIG" 2>/dev/null || echo "https://api.github.com"
}

region_is_enabled() {
  local region="$1"
  jq -r ".regions.$region.enabled // false" "$REGION_CONFIG" 2>/dev/null || echo "false"
}

region_health_check() {
  local region="$1"
  local endpoint
  endpoint=$(region_get_endpoint "$region")
  
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$endpoint" 2>/dev/null || echo "000")
  
  if [ "$http_code" = "200" ]; then
    echo "  ✅ Region $region: gezond"
    return 0
  else
    echo "  ❌ Region $region: ongezond (HTTP $http_code)"
    return 1
  fi
}

region_failover() {
  local primary
  primary=$(region_get_primary)
  
  if ! region_health_check "$primary"; then
    echo "  ⚠️ Primary region $primary ongezond, failover..."
    
    local new_primary
    new_primary=$(jq -r '.regions | to_entries | map(select(.value.enabled == true)) | sort_by(.value.priority) | .[1].key' "$REGION_CONFIG" 2>/dev/null || echo "")
    
    if [ -n "$new_primary" ]; then
      echo "  ✅ Failover naar region: $new_primary"
      return 0
    else
      echo "  ❌ Geen backup region beschikbaar"
      return 1
    fi
  fi
  
  echo "  ✅ Primary region $primary is gezond"
  return 0
}
