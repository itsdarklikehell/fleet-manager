#!/usr/bin/env bash
# scripts/setup-service-mesh.sh - Service mesh
# Voegt een service mesh toe voor betere observability en security
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Service Mesh ==="

# Configuratie
MESH_DIR="lib/service-mesh"
mkdir -p "$MESH_DIR"

# Functies
create_mesh_config() {
  local mesh_file="$MESH_DIR/mesh-config.json"
  
  cat > "$mesh_file" << 'MESH'
{
  "service_mesh": {
    "provider": "istio",
    "enabled": false,
    "namespace": "fleet-system",
    "services": [
      {
        "name": "fleet-manager",
        "port": 8080,
        "protocol": "http"
      },
      {
        "name": "prometheus",
        "port": 9090,
        "protocol": "http"
      },
      {
        "name": "grafana",
        "port": 3000,
        "protocol": "http"
      }
    ],
    "traffic_policy": {
      "mtls": true,
      "circuit_breaker": true,
      "retry_policy": true
    },
    "observability": {
      "metrics": true,
      "tracing": true,
      "access_logs": true
    }
  }
}
MESH
  
  echo "  ✅ Service mesh config gemaakt"
}

create_mesh_helper() {
  local mesh_helper="$MESH_DIR/service-mesh.sh"
  
  cat > "$mesh_helper" << 'MESHHELPER'
#!/usr/bin/env bash
# Service mesh helper voor fleet-manager scripts

MESH_CONFIG="${MESH_CONFIG:-lib/service-mesh/mesh-config.json}"

mesh_is_enabled() {
  jq -r '.service_mesh.enabled // false' "$MESH_CONFIG" 2>/dev/null || echo "false"
}

mesh_get_services() {
  jq -r '.service_mesh.services[].name' "$MESH_CONFIG" 2>/dev/null || echo ""
}

mesh_get_service_port() {
  local service="$1"
  jq -r ".service_mesh.services[] | select(.name == \"$service\") | .port" "$MESH_CONFIG" 2>/dev/null || echo "8080"
}

mesh_is_mtls_enabled() {
  jq -r '.service_mesh.traffic_policy.mtls // false' "$MESH_CONFIG" 2>/dev/null || echo "false"
}

mesh_enable() {
  jq '.service_mesh.enabled = true' "$MESH_CONFIG" > "$MESH_CONFIG.tmp" && mv "$MESH_CONFIG.tmp" "$MESH_CONFIG"
  echo "  ✅ Service mesh ingeschakeld"
}

mesh_disable() {
  jq '.service_mesh.enabled = false' "$MESH_CONFIG" > "$MESH_CONFIG.tmp" && mv "$MESH_CONFIG.tmp" "$MESH_CONFIG"
  echo "  ✅ Service mesh uitgeschakeld"
}
MESHHELPER
  
  chmod +x "$mesh_helper"
  echo "  ✅ Service mesh helper gemaakt"
}

# Hoofdlogica
create_mesh_config
create_mesh_helper

echo ""
echo "✅ Service mesh setup klaar"
