#!/usr/bin/env bash
# scripts/quality-upgrade.sh - Batch upgrade alle scripts met set -e, DRY_RUN, logging
# Gebruik Python voor robuuste batch processing
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Quality Upgrade ==="

python3 << 'PYTHON'
import os
import re
import glob

SCRIPTS_DIR = "scripts"
UPGRADED = 0
SKIPPED = 0
FAILED = 0

def upgrade_script(path):
    global UPGRADED, SKIPPED, FAILED
    
    with open(path, 'r') as f:
        content = f.read()
    
    original = content
    modified = False
    
    # 1. set -euo pipefail toevoegen
    if 'set -euo pipefail' not in content:
        lines = content.split('\n')
        for i, line in enumerate(lines):
            if line.strip() and not line.startswith('#'):
                lines.insert(i, 'set -euo pipefail')
                content = '\n'.join(lines)
                modified = True
                break
    
    # 2. DRY_RUN guard toevoegen voor scripts die mutaties doen
    if re.search(r'gh (pr|issue|repo) (create|update|delete|merge|close|reopen|edit)', content):
        if 'DRY_RUN' not in content:
            dry_run_code = '''
# DRY_RUN guard
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
'''
            # Voeg toe na set -euo pipefail
            content = content.replace('set -euo pipefail\n', 'set -euo pipefail\n' + dry_run_code)
            modified = True
    
    # 3. Logging toevoegen
    if 'log()' not in content and 'log ' not in content:
        log_code = '''
# Logging
log() {
  local msg="$*"; local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] $msg" >> "$LOG_FILE" 2>/dev/null || echo "[$ts] $msg" >&2
}
'''
        content = content.replace('set -euo pipefail\n', 'set -euo pipefail\n' + log_code)
        modified = True
    
    if modified:
        with open(path, 'w') as f:
            f.write(content)
        os.chmod(path, 0o755)
        print(f"  ✅ {os.path.basename(path)} geüpgraded")
        UPGRADED += 1
    else:
        print(f"  ⏭️ {os.path.basename(path)} al OK")
        SKIPPED += 1

# Hoofdlogica
scripts = glob.glob(os.path.join(SCRIPTS_DIR, '*.sh'))
print(f"Totaal scripts: {len(scripts)}\n")

for script in sorted(scripts):
    try:
        upgrade_script(script)
    except Exception as e:
        print(f"  ❌ {os.path.basename(path)}: {e}")
        FAILED += 1

print(f"\n=== Quality Upgrade Samenvatting ===")
print(f"  Geüpgraded: {UPGRADED}")
print(f"  Al OK: {SKIPPED}")
print(f"  Gefaald: {FAILED}")
PYTHON

echo ""
echo "✅ Quality upgrade klaar"
