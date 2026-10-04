#!/usr/bin/env bash
# scripts/auto-fleet-tester.sh - Automatische fleet tester
# Test alle scripts en genereert een testrapport
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Auto Fleet Tester ==="

# Configuratie
TESTER_ENABLED="${TESTER_ENABLED:-no}"

if [ "$TESTER_ENABLED" != "yes" ]; then
  echo "Fleet tester is uitgeschakeld (TESTER_ENABLED=$TESTER_ENABLED)"
  exit 0
fi

# Functies
test_script() {
  local script="$1"
  local path="scripts/$script"
  
  if [ ! -f "$path" ]; then
    echo "  ❌ $script: niet gevonden"
    return 1
  fi
  
  # Syntax check
  if ! bash -n "$path" 2>/dev/null; then
    echo "  ❌ $script: syntax fout"
    return 1
  fi
  
  # Executable check
  if [ ! -x "$path" ]; then
    echo "  ⚠️ $script: niet executable"
  fi
  
  # Dry-run test
  local output
  output=$(timeout 10 bash "$path" --dry-run 2>&1 || true)
  
  if echo "$output" | grep -qiE 'error|fatal|command not found'; then
    echo "  ⚠️ $script: mogelijke fout in dry-run"
  else
    echo "  ✅ $script: OK"
  fi
}

# Hoofdlogica
echo "Scripts testen..."

total=0
passed=0
failed=0

for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  total=$((total + 1))
  
  if test_script "$(basename "$script")"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

echo ""
echo "=== Test Resultaten ==="
echo "  Totaal: $total"
echo "  Geslaagd: $passed"
echo "  Gefaald: $failed"

if [ "$failed" -gt 0 ]; then
  echo ""
  echo "❌ $failed testen gefaald"
  exit 1
fi

echo ""
echo "✅ Auto fleet tester klaar"
