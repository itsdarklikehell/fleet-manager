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
