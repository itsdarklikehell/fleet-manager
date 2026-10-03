#!/usr/bin/env bash
# scripts/auto-merge.sh - Merge automatisch PRs met succesvolle CI en reviews
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Auto Merge ==="

# Configuratie
AM_DRY_RUN="${AM_DRY_RUN:-no}"
AM_MIN_APPROVALS="${AM_MIN_APPROVALS:-1}"
AM_MERGE_METHOD="${AM_MERGE_METHOD:-merge}"
# Maximum size for auto-merge (in lines changed) - larger PRs get manual review
AM_MAX_SIZE="${AM_MAX_SIZE:-100}"

# Function: check CI status for PR head commit
check_ci_status() {
  local repo="$1"
  local pr_number="$2"

  local sha
  sha=$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha' 2>/dev/null || echo "")

  if [ -z "$sha" ]; then
    echo "unknown"
    return 1
  fi

  local commit_status
  commit_status=$(gh api "repos/$repo/commits/$sha/status" --jq '.state' 2>/dev/null || echo "unknown")

  echo "$commit_status"
}

# Function: count approvals
check_reviews() {
  local repo="$1"
  local pr_number="$2"

  local approvals
  approvals=$(gh api "repos/$repo/pulls/$pr_number/reviews" --jq "[.[] | select(.state == \"APPROVED\")] | length" 2>/dev/null || echo "0")

  echo "$approvals"
}

# Function: merge PR
merge_pr() {
  local repo="$1"
  local pr_number="$2"
  local title="$3"

  log "  Merging PR #$pr_number: $title"

  if [ "$AM_DRY_RUN" = "yes" ]; then
    log "    [DRY RUN] Would merge with $AM_MERGE_METHOD"
    return 0
  fi

  local result
  result=$(gh pr merge "${repo}#${pr_number}" --${AM_MERGE_METHOD} --delete-branch --admin 2>&1 || echo "")

  if echo "$result" | grep -qi "merged\|success\|complete"; then
    log "    ✅ PR gemerged"
    return 0
  else
    log "    ❌ Merge mislukt: $result"
    return 1
  fi
}

# Function: skip PR based on labels
should_skip_pr() {
  local repo="$1"
  local pr_number="$2"

  local labels
  labels=$(gh api "repos/$repo/issues/$pr_number" --jq '.labels[].name' 2>/dev/null || echo "")

  # Skip PRs with these labels
  for skip_label in "do-not-merge" "wip" "draft" "awaiting-review"; do
    if echo "$labels" | grep -qi "$skip_label"; then
      return 0
    fi
  done

  return 1
}

# Function: check if PR author should be skipped (bot PRs)
is_bot_author() {
  local repo="$1"
  local pr_number="$2"

  local author
  author=$(gh api "repos/$repo/pulls/$pr_number" --jq '.user.type' 2>/dev/null || echo "")

  if [ "$author" = "Bot" ]; then
    return 0
  fi
  return 1
}

merged=0
skipped=0
total_checked=0

for kr in "${KEY_REPOS[@]}"; do
  org="${kr%%/*}"
  repo_name="${kr##*/}"
  set_repo_token "$org"

  log "Checking PRs for merge in $kr..."

  # Get open PRs that are mergeable and small enough
  prs=$(gh pr list --repo "$kr" --state open --json number,title,additions,deletions,mergeable,mergeStateStatus,author --jq ".[] | select(.author.type != \"Bot\") | select(.mergeable == \"MERGEABLE\" and .mergeStateStatus == \"CLEAN\" and (.additions + .deletions) < ${AM_MAX_SIZE}) | \"\(.number)|\(.title)|\(.additions + .deletions)\"" 2>/dev/null || true)

  if [ -n "$prs" ]; then
    while IFS='|' read -r num title size; do
      [ -z "$num" ] && continue
      total_checked=$((total_checked + 1))

      # Check if should skip
      if should_skip_pr "$kr" "$num"; then
        log "  ℹ️ PR #$num: $title wordt overgeslagen (skip label)"
        skipped=$((skipped + 1))
        continue
      fi

      # Check CI status
      ci_status=$(check_ci_status "$kr" "$num")
      if [ "$ci_status" != "success" ]; then
        log "  ⏳ PR #$num: $title - CI niet succesvol ($ci_status)"
        continue
      fi

      # Check reviews (min approvals)
      approvals=$(check_reviews "$kr" "$num")
      if [ "$approvals" -lt "$AM_MIN_APPROVALS" ]; then
        log "  ⏳ PR #$num: $title - Niet genoeg approvals ($approvals/$AM_MIN_APPROVALS)"
        continue
      fi

      log "  ✅ PR #$num: $title ($size reges) klaar voor merge"
      merge_pr "$kr" "$num" "$title" && merged=$((merged + 1)) || true

    done <<< "$prs"
  fi
done

log "=== Auto Merge complete: $merged PRs gemerged, $skipped overgeslagen ($total_checked gecontroleerd) ==="
send_telegram_message "🔀 *Auto Merge*\n\n*Gemerged:* $merged PRs\n*Overgeslagen:* $skipped PRs\n*Gecontroleerd:* $total_checked PRs\n\n📋 Volledig log: $LOG_FILE" || true
