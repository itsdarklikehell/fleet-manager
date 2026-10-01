#!/usr/bin/env bash
# scripts/release-auto.sh - Release automation
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Release Auto ==="
releases_created=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  cd "$repo_dir"
  last_release=$(gh release list --repo "${org}/${repo}" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")
  commits_since=0
  if [ -n "$last_release" ]; then
    commits_since=$(git rev-list --count "${last_release}..HEAD" 2>/dev/null || echo "0")
  else
    commits_since=$(git rev-list --count HEAD 2>/dev/null || echo "0")
  fi
  if [ "$commits_since" -gt 10 ]; then
    log "  $repo: $commits_since commits sinds laatste release"
    new_tag="v$(date +%Y.%m.%d)"
    release_notes=$(git log --pretty=format:"%s" -10 2>/dev/null || echo "")
    gh release create "$new_tag" --repo "${org}/${repo}" --title "Release $new_tag" --notes "$release_notes" 2>/dev/null && ((releases_created++)) || true
  fi
  cd - > /dev/null
done
log "=== Release Auto complete: $releases_created releases created ==="
send_telegram_message "🚀 *Release Auto*\n\n*Releases aangemaakt:* $releases_created\n\n📋 Volledig log: $LOG_FILE" || true
