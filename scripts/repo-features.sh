#!/usr/bin/env bash
# scripts/repo-features.sh - Enable/disable repo features (issues, wiki, projects, discussions)
set -euo pipefail

# DRY_RUN guard
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"
maybe_mutate() {
  if [ -n "$DRY_RUN" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

ENABLE_FEATURES="${1:-}"
if [ -z "$ENABLE_FEATURES" ]; then
  echo "Usage: $0 <enable|disable> [issues,wiki,projects,discussions] [repo1 repo2 ...]"
  exit 1
fi
shift
FEATURES="${1:-issues,wiki,projects,discussions}"
shift
REPOS_TO_UPDATE=("$@")

log "=== Repo Features Update ==="
updated=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  if [ ${#REPOS_TO_UPDATE[@]} -gt 0 ]; then
    skip=1
    for r in "${REPOS_TO_UPDATE[@]}"; do
      [ "$r" = "$repo" ] && skip=0 && break
    done
    [ "$skip" = "1" ] && continue
  fi
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  log "  $repo: features $ENABLE_FEATURES ($FEATURES)..."
  args=""
  IFS=',' read -ra feat_arr <<< "$FEATURES"
  for feat in "${feat_arr[@]}"; do
    if [ "$ENABLE_FEATURES" = "enable" ]; then
      args="$args -f has_${feat}=true"
    else
      args="$args -f has_${feat}=false"
    fi
  done
  eval "maybe_mutate gh repo edit --repo ${org}/${repo} $args" 2>/dev/null && ((updated++)) || true
done
log "=== Repo Features complete: $updated repos geüpdatet ==="
send_telegram_message "⚙️ *Repo Features*\n\n*Geüpdatet:* $updated repos ($ENABLE_FEATURES: $FEATURES)\n\n📋 Volledig log: $LOG_FILE" || true
