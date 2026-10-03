#!/usr/bin/env bash
# scripts/generate-docs.sh - Genereert documentatie voor alle fleet scripts
# Maakt README per script en een index pagina
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

log "=== Script Documentatie Generator ==="

DOCS_DIR="${DOCS_DIR:-$HOME/.hermes/cache/scratch/fleet-manager/docs}"
mkdir -p "$DOCS_DIR"

# Functies
generate_script_doc() {
  local script="$1"
  local path="scripts/$script"
  
  if [ ! -f "$path" ]; then
    return
  fi
  
  local name
  name=$(basename "$script" .sh)
  local desc
  desc=$(head -5 "$path" | grep '^# ' | head -1 | sed 's/^# //')
  local usage
  usage=$(grep -A2 'Gebruik:' "$path" 2>/dev/null | head -3 || echo "")
  local size
  size=$(wc -c < "$path")
  local lines
  lines=$(wc -l < "$path")
  
  cat > "$DOCS_DIR/${name}.md" <<EOF
# ${name}.sh

**Beschrijving:** ${desc}

**Grootte:** ${size} bytes, ${lines} regels

**Gebruik:**
\`\`\`bash
${usage}
\`\`\`

**Laatste update:** $(date -Iseconds)
EOF
  
  log "  ✅ ${name}.md"
}

generate_index() {
  local index="# Fleet Manager Script Documentatie

**Totaal scripts:** $(ls scripts/*.sh 2>/dev/null | wc -l)

**Laatste update:** $(date -Iseconds)

## Scripts

"
  
  for script in scripts/*.sh; do
    [ -f "$script" ] || continue
    local name
    name=$(basename "$script" .sh)
    local desc
    desc=$(head -5 "$script" | grep '^# ' | head -1 | sed 's/^# //')
    index+="- [${name}.sh](${name}.md) — ${desc}
"
  done
  
  echo "$index" > "$DOCS_DIR/README.md"
  log "  ✅ README.md"
}

# Hoofdlogica
log "Documentatie genereren..."

for script in scripts/*.sh; do
  [ -f "$script" ] || continue
  generate_script_doc "$(basename "$script")"
done

generate_index

log ""
log "✅ Documentatie gegenereerd in $DOCS_DIR"
