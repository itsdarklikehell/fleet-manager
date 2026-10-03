#!/usr/bin/env bash
# scripts/documentation-generation.sh - Auto-generate API docs
# Genereer documentatie van code comments en upload naar GitHub Pages
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Documentation Generation ==="

# Configuratie
DG_ENABLED="${DG_ENABLED:-yes}"
DG_DRY_RUN="${DG_DRY_RUN:-no}"
DG_OUTPUT_DIR="${DG_OUTPUT_DIR:-docs/api}"
DG_UPLOAD="${DG_UPLOAD:-yes}"

# Supported languages and their doc generators
generate_python_docs() {
  local repo_dir="$1"
  local output_dir="$2"
  
  if [ -f "$repo_dir/requirements.txt" ] || find "$repo_dir" -name "*.py" -type f | head -1; then
    log "  Generating Python docs (pdoc)..."
    
    if command -v pdoc3 &>/dev/null || pip show pdoc3 &>/dev/null; then
      python3 -m pdoc3 --html -o "$output_dir/python" "$repo_dir"/*.py 2>/dev/null || true
      log "    ✅ Python docs gegenereerd"
    elif command -v pydoc &>/dev/null; then
      # Fallback: pydoc
      cd "$repo_dir"
      for f in *.py; do
        [ -f "$f" ] && python3 -m pydoc "$f" > "$output_dir/python/${f%.py}.html" 2>/dev/null || true
      done
      log "    ✅ Python docs gegenereerd (pydoc fallback)"
    else
      log "    ⚠️ Geen Python doc generator beschikbaar"
    fi
  fi
}

generate_js_docs() {
  local repo_dir="$1"
  local output_dir="$2"
  
  if [ -f "$repo_dir/package.json" ] && grep -q '"jsdoc\|"typedoc' "$repo_dir/package.json" 2>/dev/null; then
    log "  Generating JavaScript/TypeScript docs (JSDoc/TypeDoc)..."
    
    if command -v npx &>/dev/null; then
      cd "$repo_dir"
      npx jsdoc -r -d "$output_dir/js" 2>/dev/null || true
      log "    ✅ JS docs gegenereerd"
    else
      log "    ⚠️ npx niet beschikbaar"
    fi
  fi
}

generate_shell_docs() {
  local repo_dir="$1"
  local output_dir="$2"
  
  if find "$repo_dir" -name "*.sh" -type f | head -1; then
    log "  Generating shell script docs (shelldoc)..."
    
    mkdir -p "$output_dir/shell"
    
    for script in "$repo_dir"/*.sh; do
      [ -f "$script" ] || continue
      local name
      name=$(basename "$script" .sh)
      
      cat > "$output_dir/shell/${name}.md" << SHELLEOF
# $(basename "$script")

\`\`\`bash
$(sed '/^#/d; s/^[^:]*:/- /' "$script" | head -30)
\`\`\`

Usage:
\`\`\`bash
$(grep -E '^\s*[a-zA-Z_]+=\$\{|# Usage|# Example|# Functie' "$script" | head -20)
\`\`\`
SHELLEOF
    done
    
    log "    ✅ Shell docs gegenereerd"
  fi
}

generate_readme_index() {
  local output_dir="$1"
  local repo_name="$2"
  
  cat > "$output_dir/index.md" << INDEXEOF
# $repo_name API Documentation

Auto-gegenereerde documentatie voor deze repository.

## Contents

$(find "$output_dir" -name "*.md" -o -name "*.html" | sed "s|$output_dir/||" | sed 's|^|- [link](|' | sed 's|$|)|' | sort)
INDEXEOF
}

# Function: generate docs for a repo
generate_docs() {
  local repo="$1"
  local repo_url
  repo_url=$(echo "$repo" | grep -oE '[a-z]+/[a-z-]+$')
  
  log "Generating docs for $repo..."
  
  local work_dir
  work_dir="$REPOS_DIR/${repo//\//_}"
  
  if [ ! -d "$work_dir" ]; then
    log "  ⚠️ Repo niet gekloond: $work_dir"
    # Try to clone
    if [ "$DG_DRY_RUN" != "yes" ]; then
      org="${repo%%/*}"
      set_repo_token "$org"
      git clone "https://$org:${!GITHUB_TOKEN_VAR:-$GITHUB_TOKEN}@github.com/$repo.git" "$work_dir" 2>/dev/null || {
        log "  ❌ Clone mislukt"
        return 1
      }
    fi
  fi
  
  local output_dir="$work_dir/$DG_OUTPUT_DIR"
  mkdir -p "$output_dir"
  
  # Generate docs for each language
  generate_python_docs "$work_dir" "$output_dir"
  generate_js_docs "$work_dir" "$output_dir"
  generate_shell_docs "$work_dir" "$output_dir"
  
  # Generate index
  local repo_name="${repo##*/}"
  generate_readme_index "$output_dir" "$repo_name"
  
  # Upload to GitHub Pages if enabled
  if [ "$DG_UPLOAD" = "yes" ] && [ "$DG_DRY_RUN" != "yes" ]; then
    # Check if docs branch exists
    if gh api "repos/$repo/branches/gh-pages" --jq '.name' 2>/dev/null; then
      log "  ℹ️ gh-pages branch bestaat al"
    else
      log "  📤 Configureren GitHub Pages..."
      # Initialize gh-pages branch
      git -C "$work_dir" checkout --orphan gh-pages 2>/dev/null || true
      git -C "$work_dir" rm -rf . 2>/dev/null || true
      cp -r "$output_dir"/* "$work_dir/" 2>/dev/null || true
      git -C "$work_dir" add . 2>/dev/null || true
      git -C "$work_dir" commit -m "docs: Auto-generate API documentation" 2>/dev/null || true
      git -C "$work_dir" push origin gh-pages --force 2>/dev/null || true
      git -C "$work_dir" checkout main 2>/dev/null || true
      log "    ✅ GitHub Pages geconfigureerd"
    fi
  fi
}

# Hoofdlogica
if [ "$DG_ENABLED" != "yes" ]; then
  log "Documentation generation uitgeschakeld"
  exit 0
fi

for kr in "${KEY_REPOS[@]}"; do
  generate_docs "$kr"
done

log "=== Documentation Generation klaar ==="
