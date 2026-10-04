#!/usr/bin/env bash
# scripts/setup-dependabot.sh - Dependabot configureren
# Voegt automatische dependency updates toe voor alle package managers
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Dependabot ==="

# Configuratie
DEPENDABOT_DIR=".github"
mkdir -p "$DEPENDABOT_DIR"

# Functies
create_dependabot_config() {
  local config_file="$DEPENDABOT_DIR/dependabot.yml"
  
  cat > "$config_file" << 'CONFIG'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10

  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
CONFIG
  
  echo "  ✅ Dependabot config gemaakt: $config_file"
}

# Hoofdlogica
create_dependabot_config

echo ""
echo "✅ Dependabot setup klaar"
