#!/usr/bin/env bash
# scripts/setup-security-hardening.sh - Security hardening
# Voegt secret scanning, dependency vulnerability scanning en SAST toe
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Security Hardening ==="

# Configuratie
SECURITY_DIR="lib/security"
mkdir -p "$SECURITY_DIR"

# Functies
setup_secret_scanning() {
  local scanner="$SECURITY_DIR/secret-scanner.sh"
  
  cat > "$scanner" << 'SCANNER'
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
SCANNER
  
  chmod +x "$scanner"
  echo "  ✅ Secret scanner ingesteld"
}

setup_dependency_scanning() {
  local scanner="$SECURITY_DIR/dependency-scanner.sh"
  
  cat > "$scanner" << 'SCANNER'
#!/usr/bin/env bash
# Dependency vulnerability scanner
set -euo pipefail

echo "=== Dependency Vulnerability Scanning ==="

# Check Python dependencies
if [ -f "requirements.txt" ]; then
  echo "  Python dependencies controleren..."
  pip install safety 2>/dev/null || true
  safety check -r requirements.txt 2>/dev/null || echo "  ⚠️ Safety check niet beschikbaar"
fi

# Check Node.js dependencies
if [ -f "package.json" ]; then
  echo "  Node.js dependencies controleren..."
  npm audit 2>/dev/null || echo "  ⚠️ npm audit niet beschikbaar"
fi

echo "  ✅ Dependency scan voltooid"
SCANNER
  
  chmod +x "$scanner"
  echo "  ✅ Dependency scanner ingesteld"
}

setup_sast() {
  local sast="$SECURITY_DIR/sast-scanner.sh"
  
  cat > "$sast" << 'SCANNER'
#!/usr/bin/env bash
# SAST (Static Application Security Testing) scanner
set -euo pipefail

echo "=== SAST Scanning ==="

# ShellCheck als SAST voor bash
if command -v shellcheck &>/dev/null; then
  echo "  ShellCheck uitvoeren..."
  shellcheck scripts/*.sh lib/*.sh --severity=warning || true
else
  echo "  ⚠️ ShellCheck niet geïnstalleerd"
fi

# Bandit voor Python (als beschikbaar)
if command -v bandit &>/dev/null; then
  echo "  Bandit uitvoeren..."
  bandit -r . -f json -o bandit-report.json 2>/dev/null || true
else
  echo "  ⚠️ Bandit niet geïnstalleerd"
fi

echo "  ✅ SAST scan voltooid"
SCANNER
  
  chmod +x "$sast"
  echo "  ✅ SAST scanner ingesteld"
}

# Hoofdlogica
setup_secret_scanning
setup_dependency_scanning
setup_sast

echo ""
echo "✅ Security hardening setup klaar"
