#!/usr/bin/env bash
# Secret scanner - detecteert hardcoded credentials
set -euo pipefail

echo "=== Secret Scanning ==="

patterns=(
  'AKIA[0-9A-Z]{16}'
  'ghp_[a-zA-Z0-9]{36}'
  'xox[baprs]-[a-zA-Z0-9]{10,}'
  '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
  '(api_key|apikey|secret|password|token|credential)\s*[=:]\s*["\x27][a-zA-Z0-9]{20,}["\x27]'
)

found=0
for pattern in "${patterns[@]}"; do
  matches=$(grep -rE "$pattern" scripts/ lib/ 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "  ⚠️ Mogelijk secret gevonden (pattern: ${pattern:0:30}...)"
    found=$((found + 1))
  fi
done

if [ "$found" -eq 0 ]; then
  echo "  ✅ Geen secrets gevonden"
else
  echo "  ⚠️ $found mogelijke secrets gevonden"
fi
