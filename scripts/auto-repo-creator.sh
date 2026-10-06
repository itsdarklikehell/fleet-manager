#!/usr/bin/env bash
# scripts/auto-repo-creator.sh - Automatisch nieuwe GitHub repos aanmaken
# met standaard structuur (README, LICENSE, .gitignore, CI/CD)
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"

log "=== Auto Repo Creator ==="

# Functies
usage() {
  echo "Usage: $0 <repo-name> [description] [visibility]"
  echo "  repo-name: Naam van de repo"
  echo "  description: Beschrijving van de repo (optioneel)"
  echo "  visibility: public of private (default: public)"
  exit 1
}

create_repo() {
  local repo_name="$1"
  local description="${2:-}"
  local visibility="${3:-public}"
  
  log "Creating repo: $repo_name ($visibility)"
  
  # Create repo via gh
  if [ -n "$description" ]; then
    gh repo create "$repo_name" --"$visibility" --description "$description"
  else
    gh repo create "$repo_name" --"$visibility"
  fi
  
  # Clone repo
  local repo_dir="$REPOS_DIR/$repo_name"
  if [ -d "$repo_dir" ]; then
    log "Repo directory already exists: $repo_dir"
    return 1
  fi
  
  git clone "https://github.com/$GITHUB_OWNER/$repo_name.git" "$repo_dir"
  cd "$repo_dir"
  
  # Create standard structure
  create_standard_structure
  
  # Initial commit
  git add -A
  git commit -m "Initial commit: standard repo structure"
  git push origin HEAD
  
  log "✓ Repo created: $repo_name"
}

create_standard_structure() {
  log "Creating standard structure..."
  
  # README.md
  cat > README.md << EOF
# $repo_name

${description:-"No description provided."}

## Installation

\`\`\`bash
# Add installation instructions here
\`\`\`

## Usage

\`\`\`bash
# Add usage examples here
\`\`\`

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.
EOF

  # LICENSE (MIT)
  cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2026 Hans Molenaar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

  # .gitignore
  cat > .gitignore << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
dist/
*.egg-info/
.eggs/

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Environment
.env
.venv
venv/
EOF

  # CONTRIBUTING.md
  cat > CONTRIBUTING.md << 'EOF'
# Contributing

Thank you for your interest in contributing!

## How to Contribute

1. Fork the repository
2. Create a new branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Code Style

- Follow the existing code style
- Write clear commit messages
- Add tests for new features

## Reporting Issues

Please use the GitHub issue tracker to report bugs or request features.
EOF

  # GitHub Actions CI
  mkdir -p .github/workflows
  cat > .github/workflows/ci.yml << 'EOF'
name: CI

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          echo "Add your tests here"
EOF

  # Create directories
  mkdir -p scripts lib tests docs
  
  log "✓ Standard structure created"
}

# Main
if [ $# -lt 1 ]; then
  usage
fi

REPO_NAME="$1"
DESCRIPTION="${2:-}"
VISIBILITY="${3:-public}"

create_repo "$REPO_NAME" "$DESCRIPTION" "$VISIBILITY"

log "=== Done ==="
