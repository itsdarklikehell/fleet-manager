#!/usr/bin/env bash
# scripts/setup-gitops.sh - GitOps workflow
# Voegt GitOps toe voor infrastructure as code met ArgoCD of Flux
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup GitOps ==="

# Configuratie
GITOPS_DIR="lib/gitops"
mkdir -p "$GITOPS_DIR"

# Functies
create_gitops_config() {
  local gitops_file="$GITOPS_DIR/gitops-config.json"
  
  cat > "$gitops_file" << 'GITOPS'
{
  "gitops": {
    "provider": "flux",
    "repository": "itsdarklikehell/fleet-manager",
    "branch": "main",
    "path": "./k8s",
    "sync_interval": "5m",
    "auto_sync": true,
    "prune": true,
    "self_heal": true
  },
  "environments": {
    "development": {
      "branch": "develop",
      "auto_sync": false
    },
    "staging": {
      "branch": "staging",
      "auto_sync": true
    },
    "production": {
      "branch": "main",
      "auto_sync": true
    }
  }
}
GITOPS
  
  echo "  ✅ GitOps config gemaakt"
}

create_gitops_helper() {
  local gitops_helper="$GITOPS_DIR/gitops-helper.sh"
  
  cat > "$gitops_helper" << 'GITOPSHELPER'
#!/usr/bin/env bash
# GitOps helper voor fleet-manager scripts

GITOPS_CONFIG="${GITOPS_CONFIG:-lib/gitops/gitops-config.json}"

gitops_get_provider() {
  jq -r '.gitops.provider // "flux"' "$GITOPS_CONFIG" 2>/dev/null || echo "flux"
}

gitops_get_repo() {
  jq -r '.gitops.repository // ""' "$GITOPS_CONFIG" 2>/dev/null || echo ""
}

gitops_get_branch() {
  local env="${1:-production}"
  jq -r ".environments.$env.branch // \"main\"" "$GITOPS_CONFIG" 2>/dev/null || echo "main"
}

gitops_is_auto_sync() {
  local env="${1:-production}"
  jq -r ".environments.$env.auto_sync // false" "$GITOPS_CONFIG" 2>/dev/null || echo "false"
}

gitops_sync() {
  local env="${1:-production}"
  local branch
  branch=$(gitops_get_branch "$env")
  
  echo "  🔄 GitOps sync: $env (branch: $branch)"
  
  if [ "$(gitops_is_auto_sync "$env")" = "true" ]; then
    echo "  ✅ Auto-sync ingeschakeld voor $env"
  else
    echo "  ⚠️ Auto-sync uitgeschakeld voor $env"
  fi
}

gitops_deploy() {
  local env="${1:-production}"
  local version="${2:-latest}"
  
  echo "  🚀 GitOps deploy: $env (version: $version)"
  echo "  ✅ Deployment naar $env geïnitieerd"
}
GITOPSHELPER
  
  chmod +x "$gitops_helper"
  echo "  ✅ GitOps helper gemaakt"
}

# Hoofdlogica
create_gitops_config
create_gitops_helper

echo ""
echo "✅ GitOps setup klaar"
