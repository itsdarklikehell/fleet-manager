#!/usr/bin/env bash
# scripts/branch-protection-auto.sh - Branch protection automation
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Branch Protection Auto ==="
protected=0
for repo_dir in "$REPOS_DIR"/*/; do
  [ -d "$repo_dir/.git" ] || continue
  repo=$(basename "$repo_dir")
  org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
  branch=$(gh repo view --repo "${org}/${repo}" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
  # Check of branch protection al is ingesteld
  local current
  current=$(gh api "repos/${org}/${repo}/branches/$branch/protection" --jq '.required_status_checks | length' 2>/dev/null || echo "0")
  if [ "$current" = "0" ]; then
    log "  $repo: branch protection instellen voor $branch..."
    gh api "repos/${org}/${repo}/branches/$branch/protection" \
      --method PUT \
      --input - <<'EOF' 2>/dev/null && ((protected++)) || true
{
  "required_status_checks": {"strict": true, "contexts": ["CI"]},
  "enforce_admins": true,
  "required_pull_request_reviews": {"required_approving_review_count": 1},
  "restrictions": null
}
