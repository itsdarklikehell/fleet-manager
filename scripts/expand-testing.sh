#!/usr/bin/env bash
# scripts/expand-testing.sh - Testing uitbreiden
# Voegt unit tests, integration tests en E2E tests toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Expand Testing ==="

# Configuratie
TESTS_DIR="tests"
mkdir -p "$TESTS_DIR"

# Functies
create_unit_tests() {
  local test_file="$TESTS_DIR/test-scripts.sh"
  
  cat > "$test_file" << 'TEST'
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
TEST
  
  chmod +x "$test_file"
  echo "  ✅ Unit tests gemaakt"
}

create_integration_tests() {
  local test_file="$TESTS_DIR/test-integration.sh"
  
  cat > "$test_file" << 'TEST'
#!/usr/bin/env bash
# Integration tests voor fleet-manager
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

echo "=== Integration Tests ==="

test_git_repo() {
  if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "  ✅ Git repo: OK"
    return 0
  else
    echo "  ❌ Git repo: fout"
    return 1
  fi
}

test_gh_cli() {
  if command -v gh &>/dev/null; then
    echo "  ✅ gh CLI: beschikbaar"
    return 0
  else
    echo "  ❌ gh CLI: niet beschikbaar"
    return 1
  fi
}

test_telegram() {
  if [ -n "${TELEGRAM_TOKEN:-}" ]; then
    echo "  ✅ Telegram token: gezet"
    return 0
  else
    echo "  ⚠️ Telegram token: niet gezet (optioneel)"
    return 0
  fi
}

test_cron() {
  if crontab -l > /dev/null 2>&1; then
    echo "  ✅ Crontab: OK"
    return 0
  else
    echo "  ❌ Crontab: fout"
    return 1
  fi
}

# Voer tests uit
test_git_repo
test_gh_cli
test_telegram
test_cron

echo ""
echo "  ✅ Integration tests voltooid"
TEST
  
  chmod +x "$test_file"
  echo "  ✅ Integration tests gemaakt"
}

create_e2e_tests() {
  local test_file="$TESTS_DIR/test-e2e.sh"
  
  cat > "$test_file" << 'TEST'
#!/usr/bin/env bash
# E2E tests voor fleet-manager
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

echo "=== E2E Tests ==="

test_health_check() {
  if bash scripts/health-check.sh > /dev/null 2>&1; then
    echo "  ✅ Health check: OK"
    return 0
  else
    echo "  ❌ Health check: fout"
    return 1
  fi
}

test_fleet_dashboard() {
  if bash scripts/fleet-dashboard.sh > /dev/null 2>&1; then
    echo "  ✅ Fleet dashboard: OK"
    return 0
  else
    echo "  ❌ Fleet dashboard: fout"
    return 1
  fi
}

test_metrics_collector() {
  if bash scripts/metrics-collector.sh > /dev/null 2>&1; then
    echo "  ✅ Metrics collector: OK"
    return 0
  else
    echo "  ❌ Metrics collector: fout"
    return 1
  fi
}

# Voer tests uit
test_health_check
test_fleet_dashboard
test_metrics_collector

echo ""
echo "  ✅ E2E tests voltooid"
TEST
  
  chmod +x "$test_file"
  echo "  ✅ E2E tests gemaakt"
}

# Hoofdlogica
create_unit_tests
create_integration_tests
create_e2e_tests

echo ""
echo "✅ Testing uitbreiding klaar"
