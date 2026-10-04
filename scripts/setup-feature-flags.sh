#!/usr/bin/env bash
# scripts/setup-feature-flags.sh - Feature flags
# Voegt feature flags toe voor gradual rollouts en A/B testing
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Feature Flags ==="

# Configuratie
FLAGS_DIR="lib/feature-flags"
mkdir -p "$FLAGS_DIR"

# Functies
create_flags_config() {
  local flags_file="$FLAGS_DIR/flags.json"
  
  cat > "$flags_file" << 'FLAGS'
{
  "flags": {
    "ai_pr_review": {
      "enabled": false,
      "rollout_percentage": 0,
      "description": "AI-powered PR reviews"
    },
    "ai_issue_triage": {
      "enabled": false,
      "rollout_percentage": 0,
      "description": "AI-powered issue triage"
    },
    "auto_merge": {
      "enabled": true,
      "rollout_percentage": 100,
      "description": "Automatische PR merge"
    },
    "webhook_server": {
      "enabled": false,
      "rollout_percentage": 0,
      "description": "Real-time webhook server"
    },
    "prometheus_metrics": {
      "enabled": true,
      "rollout_percentage": 100,
      "description": "Prometheus metrics endpoint"
    },
    "grafana_dashboard": {
      "enabled": false,
      "rollout_percentage": 0,
      "description": "Grafana dashboard"
    },
    "opentelemetry": {
      "enabled": false,
      "rollout_percentage": 0,
      "description": "OpenTelemetry tracing"
    },
    "vault_secrets": {
      "enabled": false,
      "rollout_percentage": 0,
      "description": "HashiCorp Vault secret management"
    }
  }
}
FLAGS
  
  echo "  ✅ Feature flags config gemaakt"
}

create_flags_helper() {
  local flags_helper="$FLAGS_DIR/feature-flags.sh"
  
  cat > "$flags_helper" << 'FLAGHELPER'
#!/usr/bin/env bash
# Feature flags helper voor fleet-manager scripts

FLAGS_FILE="${FLAGS_FILE:-lib/feature-flags/flags.json}"

flag_is_enabled() {
  local flag_name="$1"
  local enabled
  enabled=$(jq -r ".flags.$flag_name.enabled // false" "$FLAGS_FILE" 2>/dev/null || echo "false")
  [ "$enabled" = "true" ]
}

flag_get_rollout() {
  local flag_name="$1"
  jq -r ".flags.$flag_name.rollout_percentage // 0" "$FLAGS_FILE" 2>/dev/null || echo "0"
}

flag_is_in_rollout() {
  local flag_name="$1"
  local user_id="${2:-$USER}"
  
  if ! flag_is_enabled "$flag_name"; then
    return 1
  fi
  
  local rollout
  rollout=$(flag_get_rollout "$flag_name")
  
  if [ "$rollout" -ge 100 ]; then
    return 0
  fi
  
  local hash
  hash=$(echo -n "$user_id$flag_name" | md5sum | cut -d' ' -f1)
  local hash_int
  hash_int=$((16#${hash:0:8}))
  local percentage=$((hash_int % 100))
  
  [ "$percentage" -lt "$rollout" ]
}

flag_enable() {
  local flag_name="$1"
  local rollout="${2:-100}"
  jq ".flags.$flag_name.enabled = true | .flags.$flag_name.rollout_percentage = $rollout" "$FLAGS_FILE" > "$FLAGS_FILE.tmp" && mv "$FLAGS_FILE.tmp" "$FLAGS_FILE"
}

flag_disable() {
  local flag_name="$1"
  jq ".flags.$flag_name.enabled = false" "$FLAGS_FILE" > "$FLAGS_FILE.tmp" && mv "$FLAGS_FILE.tmp" "$FLAGS_FILE"
}
FLAGHELPER
  
  chmod +x "$flags_helper"
  echo "  ✅ Feature flags helper gemaakt"
}

# Hoofdlogica
create_flags_config
create_flags_helper

echo ""
echo "✅ Feature flags setup klaar"
