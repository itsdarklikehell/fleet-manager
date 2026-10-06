#!/usr/bin/env bash
# Unit tests voor fleet-manager scripts
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

echo "=== Unit Tests ==="

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
    echo "✅ PASS: $name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "❌ FAIL: $name"
  fi
}

# Test: scripts bestaan
test_scripts_exist() {
  local scripts=(
    "health-check.sh"
    "test-suite.sh"
    "fleet-dashboard.sh"
    "metrics-collector.sh"
    "dependency-audit.sh"
    "security-check.sh"
    "backup-verify.sh"
    "rate-limit-check.sh"
  )
  
  for script in "${scripts[@]}"; do
    run_test "$script exists" "[ -f scripts/$script ]"
  done
}

# Test: scripts zijn executebaar
test_scripts_executable() {
  local scripts=(
    "health-check.sh"
    "test-suite.sh"
    "fleet-dashboard.sh"
  )
  
  for script in "${scripts[@]}"; do
    run_test "$script executable" "[ -x scripts/$script ]"
  done
}

# Test: scripts hebben geldige syntax
test_scripts_syntax() {
  local scripts=(
    "health-check.sh"
    "test-suite.sh"
    "fleet-dashboard.sh"
    "metrics-collector.sh"
  )
  
  for script in "${scripts[@]}"; do
    run_test "$script syntax" "bash -n scripts/$script"
  done
}

# Test: lib files bestaan
test_lib_files() {
  local libs=(
    "config.sh"
    "logging.sh"
    "telegram.sh"
    "github.sh"
    "docker.sh"
  )
  
  for lib in "${libs[@]}"; do
    run_test "lib/$lib exists" "[ -f lib/$lib ]"
  done
}

# Test: CI workflow bestaat
test_ci_workflow() {
  run_test "CI workflow exists" "[ -f .github/workflows/ci.yml ]"
}

# Test: documentatie bestaat
test_documentation() {
  run_test "README exists" "[ -f README.md ]"
  run_test "CONTRIBUTING exists" "[ -f CONTRIBUTING.md ]"
  run_test "LICENSE exists" "[ -f LICENSE ]"
}

# Voer tests uit
test_scripts_exist
test_scripts_executable
test_scripts_syntax
test_lib_files
test_ci_workflow
test_documentation

# Samenvatting
echo ""
echo "=== Test Summary ==="
echo "Total: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
