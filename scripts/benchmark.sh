#!/usr/bin/env bash
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Performance Benchmark ==="

for script in scripts/*.sh; do
    [ -f "$script" ] || continue
    start=$(date +%s%N)
    timeout 10 bash "$script" --dry-run > /dev/null 2>&1 || true
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))
    echo "  $(basename $script): ${duration}ms"
done
