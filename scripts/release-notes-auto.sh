#!/usr/bin/env bash
# scripts/release-notes-auto.sh - Release notes automation
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Release Notes Auto ==="
notes_generated=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  cd "$repo_dir"
  release_notes=$(git log --pretty=format:"* %s (%h)" -20 2>/dev/null || echo "")
  if [ -n "$release_notes" ]; then
    cat > RELEASE_NOTES.md << EOF
# Release Notes

## $(date +%Y-%m-%d)

$release_notes
EOF
    git add RELEASE_NOTES.md
    git commit -m "docs: update RELEASE_NOTES.md" 2>/dev/null || true
    git push origin HEAD 2>/dev/null || true
    ((notes_generated++)) || true
  fi
  cd - > /dev/null
done
log "=== Release Notes Auto complete: $notes_generated release notes gegenereerd ==="
send_telegram_message "📝 *Release Notes Auto*\n\n*Gegenereerd:* $notes_generated release notes\n\n📋 Volledig log: $LOG_FILE" || true
