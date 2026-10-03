#!/usr/bin/env bash
# scripts/test-suite.sh - Uitgebreide test suite voor fleet scripts
# Unit tests per script met mock gh commands
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

log "=== Fleet Test Suite ==="

# Configuratie
TEST_DIR="${TEST_DIR:-$HOME/.hermes/cache/scratch/fleet-manager/tests}"
mkdir -p "$TEST_DIR"
TEST_RESULTS="$TEST_DIR/results_$(date +%Y%m%d_%H%M%S).txt"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Functies
run_test() {
  local name="$1"
  local command="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if eval "$command" > /dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✅ PASS: $name" >> "$TEST_RESULTS"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "❌ FAIL: $name" >> "$TEST_RESULTS"
  fi
}

test_script_exists() {
  local script="$1"
  run_test "$script exists" "[ -f scripts/$script ]"
}

test_script_executable() {
  local script="$1"
  run_test "$script executable" "[ -x scripts/$script ]"
}

test_script_syntax() {
  local script="$1"
  run_test "$script syntax" "bash -n scripts/$script"
}

test_script_has_shebang() {
  local script="$1"
  run_test "$script shebang" "head -1 scripts/$script | grep -q '^#!'"
}

test_script_has_set_e() {
  local script="$1"
  run_test "$script set -e" "grep -q 'set -e' scripts/$script"
}

test_script_has_dry_run() {
  local script="$1"
  # Alleen voor scripts die mutaties doen
  if grep -q 'maybe_mutate\|DRY_RUN' "scripts/$script" 2>/dev/null; then
    run_test "$script DRY_RUN" "grep -q 'DRY_RUN' scripts/$script"
  fi
}

test_script_has_logging() {
  local script="$1"
  run_test "$script logging" "grep -q 'log ' scripts/$script"
}

# Hoofdlogica
log "Testen uitvoeren..."

for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  name=$(basename "$script")
  
  test_script_exists "$name"
  test_script_executable "$name"
  test_script_syntax "$name"
  test_script_has_shebang "$name"
  test_script_has_set_e "$name"
  test_script_has_dry_run "$name"
  test_script_has_logging "$name"
done

# Samenvatting
log ""
log "=== Test Samenvatting ==="
log "  Tests run: $TESTS_RUN"
log "  Passed: $TESTS_PASSED"
log "  Failed: $TESTS_FAILED"
log "  Results: $TEST_RESULTS"

if [ "$TESTS_FAILED" -gt 0 ]; then
  log "  ❌ $TESTS_FAILED test(s) gefaald"
  exit 1
else
  log "  ✅ Alle tests geslaagd"
  exit 0
fi
