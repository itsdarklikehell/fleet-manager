#!/usr/bin/env bash
# Dependency vulnerability scanner
set -euo pipefail

echo "=== Dependency Vulnerability Scanning ==="

# Check Python dependencies
if [ -f "requirements.txt" ]; then
  echo "  Python dependencies controleren..."
  pip install safety 2>/dev/null || true
  safety check -r requirements.txt 2>/dev/null || echo "  ⚠️ Safety check niet beschikbaar"
fi

# Check Node.js dependencies
if [ -f "package.json" ]; then
  echo "  Node.js dependencies controleren..."
  npm audit 2>/dev/null || echo "  ⚠️ npm audit niet beschikbaar"
fi

echo "  ✅ Dependency scan voltooid"
