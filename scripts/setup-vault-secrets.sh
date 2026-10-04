#!/usr/bin/env bash
# scripts/setup-vault-secrets.sh - HashiCorp Vault secret management
# Vervangt hardcoded secrets door Vault
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Vault Secrets ==="

# Configuratie
VAULT_DIR="lib/vault"
mkdir -p "$VAULT_DIR"

# Functies
create_vault_config() {
  local vault_file="$VAULT_DIR/vault-config.hcl"
  
  cat > "$vault_file" << 'VAULT'
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr = "http://0.0.0.0:8200"
cluster_addr = "https://0.0.0.0:8201"

ui = true
VAULT
  
  echo "  ✅ Vault config gemaakt"
}

create_vault_helper() {
  local vault_helper="$VAULT_DIR/vault-helper.sh"
  
  cat > "$vault_helper" << 'VAULTHELPER'
#!/usr/bin/env bash
# Vault helper voor fleet-manager scripts

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

vault_get_secret() {
  local secret_path="$1"
  local field="${2:-value}"
  
  if [ -z "$VAULT_TOKEN" ]; then
    echo "  ⚠️ VAULT_TOKEN niet ingesteld"
    return 1
  fi
  
  curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/$secret_path" | jq -r ".data.data.$field // empty"
}

vault_put_secret() {
  local secret_path="$1"
  local secret_value="$2"
  
  if [ -z "$VAULT_TOKEN" ]; then
    echo "  ⚠️ VAULT_TOKEN niet ingesteld"
    return 1
  fi
  
  curl -s -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
    -d "{\"data\":{\"value\":\"$secret_value\"}}" \
    "$VAULT_ADDR/v1/$secret_path"
}

vault_list_secrets() {
  local secret_path="$1"
  
  if [ -z "$VAULT_TOKEN" ]; then
    echo "  ⚠️ VAULT_TOKEN niet ingesteld"
    return 1
  fi
  
  curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/$secret_path?list=true" | jq -r ".data.keys[]"
}
VAULTHELPER
  
  chmod +x "$vault_helper"
  echo "  ✅ Vault helper gemaakt"
}

create_vault_service() {
  local service_file="$HOME/.config/systemd/user/fleet-vault.service"
  mkdir -p "$(dirname "$service_file")"
  
  cat > "$service_file" << SERVICE
[Unit]
Description=Fleet HashiCorp Vault
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/docker run --rm -p 8200:8200 \
  -v $(pwd)/lib/vault/vault-config.hcl:/vault/config/vault-config.hcl \
  -v vault-data:/vault/data \
  --cap-add=IPC_LOCK \
  hashicorp/vault:latest server -config=/vault/config/vault-config.hcl
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE
  
  echo "  ✅ Vault service gemaakt"
}

# Hoofdlogica
create_vault_config
create_vault_helper
create_vault_service

echo ""
echo "✅ Vault secrets setup klaar"
