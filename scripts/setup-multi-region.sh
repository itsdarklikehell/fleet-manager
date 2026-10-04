#!/usr/bin/env bash
# scripts/setup-multi-region.sh - Multi-region deployment
# Voegt multi-region deployment toe voor redundancy en lagere latency
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Multi-Region Deployment ==="

# Configuratie
REGION_DIR="lib/multi-region"
mkdir -p "$REGION_DIR"

# Functies
create_region_config() {
  local region_file="$REGION_DIR/regions.json"
  
  cat > "$region_file" << 'REGIONS'
{
  "regions": {
    "eu-west": {
      "name": "EU West",
      "location": "Ireland",
      "endpoint": "https://api.github.com",
      "priority": 1,
      "enabled": true
    },
    "us-east": {
      "name": "US East",
      "location": "Virginia",
      "endpoint": "https://api.github.com",
      "priority": 2,
      "enabled": false
    },
    "ap-southeast": {
      "name": "AP Southeast",
      "location": "Singapore",
      "endpoint": "https://api.github.com",
      "priority": 3,
      "enabled": false
    }
  },
  "failover": {
    "enabled": true,
    "health_check_interval": 60,
    "failover_threshold": 3
  }
}
REGIONS
  
  echo "  ✅ Region config gemaakt"
}

create_region_helper() {
  local region_helper="$REGION_DIR/multi-region.sh"
  
  cat > "$region_helper" << 'REGIONHELPER'
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
REGIONHELPER
  
  chmod +x "$region_helper"
  echo "  ✅ Multi-region helper gemaakt"
}

# Hoofdlogica
create_region_config
create_region_helper

echo ""
echo "✅ Multi-region deployment setup klaar"
