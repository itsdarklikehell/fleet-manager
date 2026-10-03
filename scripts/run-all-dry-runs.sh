#!/usr/bin/env bash
# scripts/run-all-dry-runs.sh - Run all scripts in dry-run mode
# Test alle scripts in een batch om debugging te vereenvoudigen
set -uo pipefail

SCRATCH="/home/hans/.hermes/cache/scratch"
FLEET_DIR="$SCRATCH/fleet-manager"
source "$FLEET_DIR/.env" 2>/dev/null || true
export GH_TOKEN="${GH_TOKEN_ITSDARKLIKEHELL:-}"
export RA_DRY_RUN=yes CG_DRY_RUN=yes SS_DRY_RUN=yes LCC_DRY_RUN=yes
export RHS_DRY_RUN=yes SAM_DRY_RUN=yes CQM_DRY_RUN=yes ADU_DRY_RUN=yes
export BPE_DRY_RUN=yes RAS_DRY_RUN=yes WH_DRY_RUN=yes MR_DRY_RUN=yes
export A2A_DRY_RUN=yes MCP_DRY_RUN=yes APR_ENABLED=no MTC_ENABLED=no

cd "$FLEET_DIR"

echo "=== Fleet Manager Dry-Run Batch Test ==="
echo ""

# Test alle scripts
scripts=(
  "health-check.sh"
  "repo-health-score.sh"
  "release-automation.sh"
  "changelog-generator.sh"
  "secret-scanning.sh"
  "license-compliance-check.sh"
  "security-advisory-monitor.sh"
  "code-quality-metrics.sh"
  "automated-dependency-updates.sh"
  "branch-protection-enforcement.sh"
  "repo-archiving-suggestions.sh"
)

passed=0
failed=0

for script in "${scripts[@]}"; do
  echo "🧪 Testing: $script"
  export RHS_REPO=itsdarklikehell/fleet-manager
  export RA_REPO=itsdarklikehell/fleet-manager
  export SS_REPO=itsdarklikehell/fleet-manager
  export LCC_REPO=itsdarklikehell/fleet-manager
  export SAM_REPO=itsdarklikehell/fleet-manager
  export CQM_REPO=itsdarklikehell/fleet-manager
  export ADU_REPO=itsdarklikehell/fleet-manager
  export BPE_REPO=itsdarklikehell/fleet-manager
  export RAS_REPO=itsdarklikehell/fleet-manager
  export CG_REPO=itsdarklikehell/fleet-manager
  
  # secret-scanning en security-advisory-monitor retourneren 1 wanneer niets gevonden is
  exit_code=0
  timeout 30 bash "scripts/$script" 2>&1 || exit_code=$?
  
  if [ "$exit_code" -eq 0 ]; then
    echo "  ✅ $script: PASS"
    passed=$((passed + 1))
  elif [ "$exit_code" -eq 1 ] && { [ "$script" = "secret-scanning.sh" ] || [ "$script" = "security-advisory-monitor.sh" ]; }; then
    echo "  ✅ $script: PASS (niets gevonden)"
    passed=$((passed + 1))
  else
    echo "  ❌ $script: FAIL (exit $exit_code)"
    failed=$((failed + 1))
  fi
  echo ""
done

echo "=== Batch Test Summary ==="
echo "Passed: $passed"
echo "Failed: $failed"
echo "Total: $((passed + failed))"

if [ "$failed" -eq 0 ]; then
  echo "✅ All scripts passing"
  exit 0
else
  echo "❌ Some scripts failed"
  exit 1
fi
