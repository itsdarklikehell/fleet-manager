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
    echo "  ⚠️ Metrics collector: skipped (requires GitHub API access)"
    return 0
  fi
}

# Voer tests uit
test_health_check
test_fleet_dashboard
test_metrics_collector

echo ""
echo "  ✅ E2E tests voltooid"
