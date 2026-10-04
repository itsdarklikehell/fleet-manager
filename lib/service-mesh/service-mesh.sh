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
