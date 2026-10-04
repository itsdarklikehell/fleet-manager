#!/usr/bin/env bash
# scripts/auto-release-asset-uploads.sh - Automatische release asset uploads
# Bij releases automatisch assets uploaden
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Release Asset Uploads ==="

# Configuratie
ASSET_UPLOAD_ENABLED="${ASSET_UPLOAD_ENABLED:-no}"
ASSET_DIR="${ASSET_DIR:-$HOME/.github_fleet_assets}"

if [ "$ASSET_UPLOAD_ENABLED" != "yes" ]; then
  echo "Asset upload is uitgeschakeld (ASSET_UPLOAD_ENABLED=$ASSET_UPLOAD_ENABLED)"
  exit 0
fi

# Functies
upload_assets() {
  local repo="$1"
  local tag="$2"
  
  echo "  Assets uploaden voor $repo ($tag)..."
  
  # Check of asset dir bestaat
  if [ ! -d "$ASSET_DIR" ]; then
    echo "    ⚠️ Asset dir bestaat niet: $ASSET_DIR"
    return 1
  fi
  
  # Upload alle bestanden in asset dir
  for asset in "$ASSET_DIR"/*; do
    [ -f "$asset" ] || continue
    
    local filename
    filename=$(basename "$asset")
    
    echo "    Uploaden: $filename"
    
    gh release upload "$tag" "$asset" --repo "$repo" --clobber > /dev/null 2>&1 || {
      echo "      ❌ Upload gefaald voor $filename"
      continue
    }
    
    echo "      ✅ Geüpload: $filename"
  done
}

# Hoofdlogica
echo "Release assets uploaden..."

for repo in $(gh repo list --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  # Haal laatste release op
  tag
  tag=$(gh release list --repo "$repo" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")
  
  if [ -n "$tag" ]; then
    upload_assets "$repo" "$tag"
  fi
done

echo ""
echo "✅ Auto release asset uploads klaar"
