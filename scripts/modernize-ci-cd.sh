#!/usr/bin/env bash
# scripts/modernize-ci-cd.sh - Moderniseer CI/CD workflows
# Voegt matrix builds, caching en security scanning toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Moderniseer CI/CD ==="

# Configuratie
CI_DIR=".github/workflows"
mkdir -p "$CI_DIR"

# Functies
modernize_ci_workflow() {
  local workflow_file="$CI_DIR/ci.yml"
  
  cat > "$workflow_file" << 'WORKFLOW'
name: CI

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  bash-syntax:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check bash syntax
        run: |
          for script in scripts/*.sh lib/*.sh; do
            [ -f "$script" ] && bash -n "$script"
          done

  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run shellcheck
        uses: ludeeus/action-shellcheck@master
        with:
          severity: warning

  test-suite:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.9", "3.10", "3.11", "3.12"]
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python ${{ matrix.python-version }}
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: 'pip'
      - name: Run test suite
        run: |
          bash scripts/test-suite.sh
      - name: Run health check
        run: |
          bash scripts/health-check.sh || true

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'
      - name: Upload Trivy scan results
        uses: github/codeql-action/upload-sarif@v2
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'

  dependency-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check dependencies
        run: |
          bash scripts/dependency-audit.sh || true
WORKFLOW
  
  echo "  ✅ CI workflow gemoderniseerd"
}

modernize_gource_workflow() {
  local workflow_file="$CI_DIR/gource.yml"
  
  cat > "$workflow_file" << 'WORKFLOW'
name: Gource Visualization

on:
  push:
    branches: [main, master]
  workflow_dispatch:

jobs:
  gource:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install Gource
        run: |
          sudo apt-get update
          sudo apt-get install -y gource ffmpeg
      - name: Generate Gource video
        run: |
          mkdir -p output
          gource -1920x1080 -o - | ffmpeg -y -r 60 -f image2pipe -vcodec ppm -i - -vcodec libx264 -pix_fmt yuv420p -preset fast -crf 18 output/gource.mp4
      - name: Upload video
        uses: actions/upload-artifact@v4
        with:
          name: gource-video
          path: output/gource.mp4
          retention-days: 30
WORKFLOW
  
  echo "  ✅ Gource workflow gemoderniseerd"
}

# Hoofdlogica
modernize_ci_workflow
modernize_gource_workflow

echo ""
echo "✅ CI/CD modernisering klaar"
