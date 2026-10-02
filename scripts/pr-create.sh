#!/usr/bin/env bash
# scripts/pr-create.sh - Create PRs vanuit templates
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

usage() {
  cat <<EOF
Usage: $0 --repo <org/repo> --head <branch> --base <branch> --title <title> [--body <body>] [--template <template>] [--label <label>]... [--assignee <user>]... [--reviewer <user>]... [--draft]

Create a new pull request.

Options:
  --repo <org/repo>       Repository (required)
  --head <branch>         Head branch (required)
  --base <branch>         Base branch (default: main)
  --title <title>         PR title (required)
  --body <body>           PR body text
  --template <template>   PR template file or name
  --label <label>         Label to add (can be repeated)
  --assignee <user>       Assignee username (can be repeated)
  --reviewer <user>       Reviewer username (can be repeated)
  --draft                 Create as draft PR
  -h, --help              Show this help

Examples:
  $0 --repo itsdarklikehell/hermes-desktop --head feature-branch --title "Add feature" --body "Description"
  $0 --repo itsdarklikehell/hermes-agent --head fix-bug --title "Fix bug" --template pr_template.md --reviewer hmol33
EOF
}

REPO=""
HEAD=""
BASE="main"
TITLE=""
BODY=""
TEMPLATE=""
LABELS=()
ASSIGNEES=""
REVIEWERS=""
DRAFT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --label) LABELS+=("$2"); shift 2 ;;
    --assignee) ASSIGNEES="$ASSIGNEES $2"; shift 2 ;;
    --reviewer) REVIEWERS="$REVIEWERS $2"; shift 2 ;;
    --draft) DRAFT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[ -z "$REPO" ] && { echo "Error: --repo is required" >&2; usage; exit 1; }
[ -z "$HEAD" ] && { echo "Error: --head is required" >&2; usage; exit 1; }
[ -z "$TITLE" ] && { echo "Error: --title is required" >&2; usage; exit 1; }

log "=== PR Create: $REPO ==="

args=(pr create --repo "$REPO" --head "$HEAD" --base "$BASE" --title "$TITLE")

if [ -n "$TEMPLATE" ]; then
  if [ -f "$TEMPLATE" ]; then
    args+=(--body "$(cat "$TEMPLATE")")
  else
    args+=(--body "$(cat "$TEMPLATE" 2>/dev/null || echo "$TEMPLATE")")
  fi
elif [ -n "$BODY" ]; then
  args+=(--body "$BODY")
fi

for label in "${LABELS[@]}"; do
  args+=(--label "$label")
done

for assignee in $ASSIGNEES; do
  args+=(--assignee "$assignee")
done

for reviewer in $REVIEWERS; do
  args+=(--reviewer "$reviewer")
done

[ "$DRAFT" -eq 1 ] && args+=(--draft)

if maybe_mutate gh "${args[@]}"; then
  log "  ✓ PR aangemaakt in $REPO: $TITLE ($HEAD → $BASE)"
  send_telegram_message "🔀 *PR Created*\n\n*Repo:* \`$REPO\`\n*Title:* $TITLE\n*Branch:* \`$HEAD\` → \`$BASE\`" || true
else
  log "  ✗ PR create failed voor $REPO: $TITLE"
  send_telegram_message "❌ *PR Create Failed*\n\n*Repo:* \`$REPO\`\n*Title:* $TITLE" || true
  exit 1
fi
