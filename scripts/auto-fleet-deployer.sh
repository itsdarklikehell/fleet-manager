#!/usr/bin/env bash
# scripts/auto-fleet-deployer.sh - Automatische fleet deployer
# Deployt de fleet manager naar een server of lokale omgeving
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Deployer ==="

# Configuratie
DEPLOYER_ENABLED="${DEPLOYER_ENABLED:-no}"
DEPLOY_TARGET="${DEPLOY_TARGET:-local}"  # local, remote

if [ "$DEPLOYER_ENABLED" != "yes" ]; then
  echo "Fleet deployer is uitgeschakeld (DEPLOYER_ENABLED=$DEPLOYER_ENABLED)"
  exit 0
fi

# Functies
deploy_local() {
  echo "Lokaal deployen..."
  
  # Installeer scripts
  mkdir -p "$HOME/.hermes/cron"
  cp -r scripts/ "$HOME/.hermes/cron/fleet-manager-scripts/" 2>/dev/null || true
  cp -r lib/ "$HOME/.hermes/cron/fleet-manager-lib/" 2>/dev/null || true
  
  # Installeer cron jobs
  bash scripts/auto-fleet-scheduler.sh
  
  # Start services
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user restart fleet-dashboard.service 2>/dev/null || true
  
  echo "  ✅ Lokaal gedeployed"
}

deploy_remote() {
  echo "Remote deployen naar $DEPLOY_TARGET..."
  
  # TODO: SSH-based deployment
  echo "  ⚠️ Remote deploy nog niet geïmplementeerd"
}

# Hoofdlogica
case "$DEPLOY_TARGET" in
  local)
    deploy_local
    ;;
  remote)
    deploy_remote
    ;;
  *)
    echo "  ⚠️ Onbekend deploy target: $DEPLOY_TARGET"
    ;;
esac

echo ""
echo "✅ Auto fleet deployer klaar"
