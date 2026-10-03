#!/usr/bin/env bash
# scripts/repo-branch-protection.sh - Set branch protection
set -euo pipefail
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

BRANCH="${1:-main}"
shift
REPOS_TO_UPDATE=("$@")

log "=== Repo Branch Protection ==="
protected=0
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
  log "  $repo: branch protection instellen voor $BRANCH..."
  maybe_mutate gh api "repos/${org}/${repo}/branches/$BRANCH/protection" \
    --method PUT \
    --input - <<'PROTECTION_EOF' 2>/dev/null && ((protected++)) || true
{
  "required_status_checks": {"strict": true, "contexts": ["CI"]},
  "enforce_admins": true,
  "required_pull_request_reviews": {"required_approving_review_count": 1},
  "restrictions": null
}
PROTECTION_EOF
done
log "=== Repo Branch Protection complete: $protected repos beveiligd ==="
send_telegram_message "🔒 *Repo Branch Protection*\n\n*Beveiligd:* $protected repos (branch: $BRANCH)\n\n📋 Volledig log: $LOG_FILE" || true
