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
