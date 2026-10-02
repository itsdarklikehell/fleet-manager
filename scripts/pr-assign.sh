#!/usr/bin/env bash
# scripts/pr-assign.sh - Assign PRs to reviewers
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --pr <number> --reviewer <user>... [--remove]

Assign or unassign reviewers from a pull request.

Options:
  --repo <org/repo>       Repository (required)
  --pr <number>           PR number (required)
  --reviewer <user>      Username to assign as reviewer (can be repeated, required unless --remove)
  --remove                Remove reviewers instead of adding
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --reviewer hmol33
  $0 --repo itsdarklikehell/hermes-agent --pr 10 --reviewer hmol33 --reviewer user2
  $0 --repo itsdarklikehell/hermes-desktop --pr 42 --reviewer hmol33 --remove
EOF
}

REPO=""
PR=""
REVIEWERS=""
REMOVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --reviewer) REVIEWERS="$REVIEWERS $2"; shift 2 ;;
    --remove) REMOVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$PR" ] && { echo "Error: --pr is required" >&2; usage; exit 1; }
[ -z "$REVIEWERS" ] && { echo "Error: --reviewer is required" >&2; usage; exit 1; }

log "=== PR Assign: $REPO#$PR ==="

args=(pr edit "$PR" --repo "$REPO")

if [ "$REMOVE" -eq 1 ]; then
  for reviewer in $REVIEWERS; do
    args+=(--remove-reviewer "$reviewer")
  done
else
  for reviewer in $REVIEWERS; do
    args+=(--add-reviewer "$reviewer")
  done
fi

if maybe_mutate gh "${args[@]}"; then
  if [ "$REMOVE" -eq 1 ]; then
    log "  ✓ Reviewers verwijderd van PR #$PR in $REPO"
    send_telegram_message "👤 *PR Reviewers Removed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  else
    log "  ✓ PR #$PR reviewers toegewezen in $REPO"
    send_telegram_message "👤 *PR Reviewers Assigned*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR\n*Reviewers:*$REVIEWERS" || true
  fi
else
  log "  ✗ PR assign failed voor $REPO#$PR"
  send_telegram_message "❌ *PR Assign Failed*\n\n*Repo:* \`$REPO\`\n*PR:* #$PR" || true
  exit 1
fi
