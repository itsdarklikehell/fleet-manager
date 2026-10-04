#!/usr/bin/env bash
# Unit tests voor fleet-manager scripts
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

echo "=== Unit Tests ==="

test_script_syntax() {
  local script="$1"
  if bash -n "$script" 2>/dev/null; then
    echo "  ✅ $script: syntax OK"
    return 0
  else
    echo "  ❌ $script: syntax fout"
    return 1
  fi
}

test_script_executable() {
  local script="$1"
  if [ -x "$script" ]; then
    echo "  ✅ $script: executable"
    return 0
  else
    echo "  ❌ $script: niet executable"
    return 1
  fi
}

test_script_has_set_e() {
  local script="$1"
  if grep -q 'set -e' "$script"; then
    echo "  ✅ $script: heeft set -e"
    return 0
  else
    echo "  ❌ $script: mist set -e"
    return 1
  fi
}

test_script_has_dry_run() {
  local script="$1"
  if grep -q 'DRY_RUN' "$script"; then
    echo "  ✅ $script: heeft DRY_RUN"
    return 0
  else
    echo "  ⚠️ $script: mist DRY_RUN (optioneel)"
    return 0
  fi
}

# Voer tests uit
total=0
passed=0
failed=0

for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  total=$((total + 1))
  
  if test_script_syntax "$script" && test_script_executable "$script" && test_script_has_set_e "$script"; then
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
  exit 1
fi
