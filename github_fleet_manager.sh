#!/usr/bin/env bash
# github_fleet_manager.sh — daily GitHub fleet manager + auto-pilot
# Runs via cron, sends a summary to Telegram.
#
# Dad's upgraded version: parallel status, dual-auth (hmol33), label policy engine,
# release drafts, dependency checks, fleet health, branch protection, and more.
set -euo pipefail

# ===================== CONFIGURATION =====================
REPOS_DIR="${REPOS_DIR:-$HOME/.openclaw/workspace/projects}"
LOG_FILE="${LOG_FILE:-$HOME/.github_fleet_manager.log}"
PARALLEL_JOBS="${PARALLEL_JOBS:-8}"
DATE_TAG="$(date '+%Y-%m-%d %H:%M:%S %Z')"
exec >> "$LOG_FILE" 2>&1
echo "===== RUN $DATE_TAG ====="

# ===================== HELPER: logging =====================
report() { echo "[$DATE_TAG] $*"; }

# Directe Telegram-configuratie (ourcing uit .env + fleet-env wordt ook gedaan, maar deze values zijn default)
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-${GITHUB_FLEET_TELEGRAM_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}}"
CHAT_ID="${CHAT_ID:-${GITHUB_FLEET_CHAT_ID:-${TELEGRAM_HOME_CHANNEL:-1779426583}}}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-1779426583 -1004424968209 639276511}"

# Fallback via Python als bovenstaande niet lukt
if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  if command -v python3 >/dev/null 2>&1; then
    _tok="" _chat=""
    read -r _tok _chat < <(python3 -c "
import yaml, os, sys
try:
    with open(os.path.expanduser('~/.hermes/config.yaml')) as f:
        cfg = yaml.safe_load(f)
    tg = cfg.get('telegram', {})
    t = tg.get('bot_token', '') or os.environ.get('TELEGRAM_BOT_TOKEN', '')
    c = str(tg.get('home_chat_id', '') or os.environ.get('TELEGRAM_HOME_CHANNEL', '') or os.environ.get('TELEGRAM_GROUP_ALLOWED_CHATS', '') or '')
    print(t, c)
except Exception:
    print('', '')
" 2>/dev/null) || true
    [ -n "$_tok" ]   && [ "$_tok" != "***" ]   && [ -z "$TELEGRAM_TOKEN" ] && TELEGRAM_TOKEN="$_tok"
    [ -n "$_chat" ]  && [ "$_chat" != "None" ]  && [ -z "$CHAT_ID" ]        && CHAT_ID="$_chat"
  fi
fi

if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$CHAT_ID" ]; then
  TELEGRAM_DISPATCH="yes"
  report "telegram configured: token=${TELEGRAM_TOKEN:0:15}...(len=${#TELEGRAM_TOKEN}), chat=$CHAT_ID"
else
  report "TELEGRAM not configured — report goes to log only (token=${TELEGRAM_TOKEN:-empty}, chat=${CHAT_ID:-empty})"
fi

_RETVAL=0
trap '_RETVAL=$?; exit $_RETVAL' EXIT


# ===================== AUTO-PILOT CONFIG =====================
AUTO_MERGE_ENABLED="${AUTO_MERGE_ENABLED:-yes}"
STALE_CLOSE_DAYS="${STALE_CLOSE_DAYS:-30}"
AUTO_RERUN_REPOS=( ${AUTO_RERUN_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/hermes-pixel-office-enhanced itsdarklikehell/dnd-utils} )
SYNC_FORKS_ENABLED="${SYNC_FORKS_ENABLED:-yes}"
CLEAN_BRANCHES_REPOS=( ${CLEAN_BRANCHES_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/dnd-utils itsdarklikehell/ci-templates itsdarklikehell/hermes-pixel-office-enhanced} )
LABEL_TRIAGE_ENABLED="${LABEL_TRIAGE_ENABLED:-yes}"
RELEASE_REPOS=( ${RELEASE_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/dnd-utils itsdarklikehell/hermes-agent itsdarklikehell/clawhub} )
# ===================== KEY REPOS (audit baseline) =====================
KEY_REPOS=( ${KEY_REPOS:-itsdarklikehell/hermes-desktop itsdarklikehell/mission-control itsdarklikehell/dnd-utils itsdarklikehell/hermes-agent itsdarklikehell/clawhub itsdarklikehell/hermes-pixel-office-enhanced} )
SECURITY_AUDIT_ENABLED="${SECURITY_AUDIT_ENABLED:-yes}"
BRANCH_PROTECTION_ENABLED="${BRANCH_PROTECTION_ENABLED:-yes}"
PAGES_CHECK_ENABLED="${PAGES_CHECK_ENABLED:-yes}"
WIKIS_CHECK_ENABLED="${WIKIS_CHECK_ENABLED:-yes}"
TOPICS_AUDIT_ENABLED="${TOPICS_AUDIT_ENABLED:-yes}"
RELEASE_ASSET_CHECK_ENABLED="${RELEASE_ASSET_CHECK_ENABLED:-yes}"
DISABLED_WORKFLOWS_ENABLED="${DISABLED_WORKFLOWS_ENABLED:-yes}"
COLLABORATOR_AUDIT_ENABLED="${COLLABORATOR_AUDIT_ENABLED:-yes}"
RANKING_ENABLED="${RANKING_ENABLED:-yes}"
REPO_FEATURES_ENABLED="${REPO_FEATURES_ENABLED:-yes}"
SECURITY_AUDIT_ALL_REPOS="${SECURITY_AUDIT_ALL_REPOS:-no}"
DRY_RUN="${GITHUB_FLEET_DRY_RUN:-}"

# === Extended audit config ===
CODEOWNERS_AUDIT_ENABLED="${CODEOWNERS_AUDIT_ENABLED:-yes}"
CONTRIB_LICENSE_AUDIT_ENABLED="${CONTRIB_LICENSE_AUDIT_ENABLED:-yes}"
PR_SIZE_MONITOR_ENABLED="${PR_SIZE_MONITOR_ENABLED:-yes}"
PR_SIZE_THRESHOLD="${PR_SIZE_THRESHOLD:-500}"
COMMIT_ACTIVITY_ENABLED="${COMMIT_ACTIVITY_ENABLED:-yes}"
COMMIT_ACTIVITY_DAYS="${COMMIT_ACTIVITY_DAYS:-30}"
CONTRIB_FILES=("CONTRIBUTING.md" "LICENSE" "SECURITY.md" "CODE_OF_CONDUCT.md" "SUPPORT.md")

# ===================== DUAL AUTH (hmol33) =====================
HMOL33_TOKEN=""
if [ -f "$HOME/.hermes/.env" ]; then
  HMOL33_TOKEN=$(grep "^GH_TOKEN_HMOL33=" "$HOME/.hermes/.env" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || echo "")
fi
if [ -z "$HMOL33_TOKEN" ] || [ "${#HMOL33_TOKEN}" -lt 10 ] || [ "$HMOL33_TOKEN" = "***" ]; then
  HMOL33_TOKEN=""
fi



set_repo_token() {
  local org="$1"
  if [ "$org" = "hmol33" ] && [ -n "$HMOL33_TOKEN" ]; then
    export GITHUB_TOKEN="$HMOL33_TOKEN"
  else
    unset GITHUB_TOKEN
  fi
}

gh_for_repo() {
  local repo_dir="$1"; shift
  local org
  org=$(get_repo_org "$repo_dir")
  if [ "$org" = "hmol33" ] && [ -n "$HMOL33_TOKEN" ]; then
    GITHUB_TOKEN="$HMOL33_TOKEN" gh "$@"
  else
    gh "$@"
  fi
}

# ===================== ORG DETECTION =====================
get_repo_org() {
  local dir="$1"
  local org=""
  local origin_url
  origin_url=$(cd "$dir" && git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$origin_url" ]; then
    org=$(echo "$origin_url" | sed -n 's|.*github.com/\([^/]*\)/.*|\1|p')
  fi
  if [ -z "$org" ] || [ "$org" = "fork" ]; then
    local upstream_url
    upstream_url=$(cd "$dir" && git remote get-url upstream 2>/dev/null || echo "")
    if [ -n "$upstream_url" ]; then
      local uorg
      uorg=$(echo "$upstream_url" | sed -n 's|.*github.com/\([^/]*\)/.*|\1|p')
      if [ -n "$uorg" ] && [ "$uorg" != "fork" ]; then
        org="$uorg"
      fi
    fi
  fi
  echo "${org:-itsdarklikehell}"
}

# ===================== LOGGING =====================
declare -a ACTIONS_TAKEN=()
log_action() { ACTIONS_TAKEN+=("$*"); log "  🤖 ACTION: $*"; }

log() {
  local msg="$*"; local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local lockfile="$LOG_FILE.lock"
  local waited=0
  while [ -f "$lockfile" ] && [ $waited -lt 50 ]; do
    sleep 0.1; ((waited++)) || true
  done
  echo "[$ts] $msg" >> "$LOG_FILE" 2>/dev/null || echo "[$ts] $msg"
  rm -f "$lockfile" 2>/dev/null || true
}

# ===================== TELEGRAM =====================
send_telegram_message() {
  local text="$1"; local token="$TELEGRAM_TOKEN"
  [ -z "$token" ] && { echo "[TELEGRAM] No token — skipping"; return 1; }
  local escaped
  escaped=$(printf '%b' "$text" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$text\"")
  local all_ok=1
  # Stuur naar alle geconfigureerde chats
  for chat_id in $TELEGRAM_CHAT_IDS; do
    [ -z "$chat_id" ] && continue
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "https://api.telegram.org/bot${token}/sendMessage" \
      -H "Content-Type: application/json" \
      -d "{\"chat_id\":\"${chat_id}\",\"text\":${escaped},\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}" 2>/dev/null)
    if [ "$http_code" = "200" ]; then
      echo "[TELEGRAM] ✓ Verstuurd naar chat $chat_id"
    else
      echo "[TELEGRAM] HTTP $http_code — failed voor chat $chat_id" >&2
      all_ok=0
    fi
  done
  return $((1 - all_ok))
}

# DRY_RUN guard voor mutaties (verplicht voor cron-uitvoering zonder review)
maybe_mutate() {
  if [ -n "${GITHUB_FLEET_DRY_RUN:-}" ]; then
    log "🔒 [DRY-RUN] Would: $*"
    return 0
  fi
  "$@"
}

# ===================== HELPERS =====================
find_upstream() {
  local dir="$1"; local upstream=""
  for r in $(cd "$dir" && git remote 2>/dev/null); do
    if [ "$r" != "origin" ]; then upstream="$r"; break; fi
  done
  echo "$upstream"
}

sync_repo() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  if [ ! -d "$dir/.git" ]; then log "SKIP: $repo not cloned"; return; fi
  cd "$dir"; log "SYNC: $repo"
  git fetch --all --quiet 2>/dev/null || true
  local upstream
  upstream=$(find_upstream "$dir")
  if [ -z "$upstream" ]; then log "  NO UPSTREAM: $repo has no upstream remote"; return; fi
  local upstream_branch=""
  for branch in main master; do
    if git rev-parse --verify "${upstream}/${branch}" >/dev/null 2>&1; then
      upstream_branch="${upstream}/${branch}"; break; fi
  done
  if [ -z "$upstream_branch" ]; then log "  NO UPSTREAM BRANCH: $repo has no main/master on upstream"; return; fi
  local local_commit upstream_commit
  local_commit=$(git rev-parse HEAD)
  upstream_commit=$(git rev-parse "$upstream_branch")
  if [ "$local_commit" = "$upstream_commit" ]; then
    log "  UP-TO-DATE: $repo matches upstream ($upstream_branch)"
  else
    local behind ahead
    behind=$(git rev-list --count "${upstream_branch}..HEAD" 2>/dev/null || echo "?")
    ahead=$(git rev-list --count "HEAD..${upstream_branch}" 2>/dev/null || echo "?")
    log "  DIFF: $repo — local $behind commits behind, upstream $ahead commits ahead"
    [ "$ahead" != "0" ] && [ "$ahead" != "?" ] && log "    ACTION: upstream has new commits — sync recommended"
  fi
}

# ===================== PER-REPO CHECKS =====================
check_gource() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  if [ ! -f "$dir/.github/workflows/gource.yml" ]; then log "GOURCE-MISSING: $repo has no gource.yml"; return 1; fi
  if [ ! -f "$dir/gource/gource.mp4" ]; then log "GOURCE-NOVIDEO: $repo has workflow but no video"
  else log "GOURCE-OK: $repo has video ($(du -h "$dir/gource/gource.mp4" | cut -f1))"; fi
}

check_readme_embed() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  if grep -q "gource.gif\|gource.mp4" "$dir/README.md" 2>/dev/null; then
    log "README-EMBED: $repo has Gource video in README"
  else log "README-NOEMBED: $repo has no Gource video in README"; fi
}

check_open_prs() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  local org
  org=$(get_repo_org "$dir"); set_repo_token "$org"
  local pr_count
  pr_count=$(gh_for_repo "$dir" pr list --repo "${org}/${repo}" --state open --json number --jq 'length' 2>/dev/null || echo "?")
  log "PRS: $repo has $pr_count open PRs"
  if [ "$pr_count" != "?" ] && [ "$pr_count" != "0" ]; then
    gh_for_repo "$dir" pr list --repo "${org}/${repo}" --state open --json number,title,headRefName \
      --jq '.[] | "  #\(.number): \(.title) (\(.headRefName))"' 2>/dev/null || true
  fi
}

check_open_issues() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  local org
  org=$(get_repo_org "$dir"); set_repo_token "$org"
  local issue_count
  issue_count=$(gh_for_repo "$dir" issue list --repo "${org}/${repo}" --state open --json number --jq 'length' 2>/dev/null) || true
  if [ -z "$issue_count" ] || [ "$issue_count" = "null" ]; then
    log "ISSUES: $repo has issues disabled (or not available)"
  else
    log "ISSUES: $repo has $issue_count open issues"
    if [ "$issue_count" != "0" ]; then
      gh_for_repo "$dir" issue list --repo "${org}/${repo}" --state open --json number,title,labels \
        --jq '.[] | "  #\(.number): \(.title) [\(.labels | map(.name) | join(", "))]"' 2>/dev/null || true
    fi
  fi
}

# ===================== LOCK-FILE OPRUIMING =====================
# Stale lock- en tmp-bestanden van eerdere (crashte) runs opruimen.
cmd_clean_locks() {
  log "=== GitHub Fleet Lock/TM P Cleanup ==="
  local cleaned=0
  # nullglob activeren zodat de glob-regulieraad geen literal "*.status.tmp" retourneert
  # wanneer er geen tmp-bestanden zijn — anders crasht de for-loop onder set -e
  shopt -s nullglob 2>/dev/null || true
  local tmp_repo
  for tmp_repo in "$REPOS_DIR"/*.status.tmp; do
    log "  Removing stale status tmp: $(basename "$tmp_repo")"
    rm -f "$tmp_repo" 2>/dev/null && ((cleaned++)) || true
  done
  # nullglob weer uitzetten (terug naar default shell-gedrag)
  shopt -u nullglob 2>/dev/null || true
  if [ -f "$REPOS_DIR/.status_counters" ]; then
    log "  Removing stale status counters file"
    rm -f "$REPOS_DIR/.status_counters" 2>/dev/null && ((cleaned++)) || true
  fi
  local lockfile
  lockfile="$LOG_FILE.lock"
  if [ -f "$lockfile" ]; then
    log "  Removing stale log lock"
    rm -f "$lockfile" 2>/dev/null && ((cleaned++)) || true
  fi
  log "=== Lock cleanup complete: $cleaned files removed ==="
  RET_CLEAN_LOCKS="$cleaned"
}

check_releases() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  local org
  org=$(get_repo_org "$dir"); set_repo_token "$org"
  log "RELEASES: $repo latest release:"
  gh_for_repo "$dir" release list --repo "${org}/${repo}" --limit 1 --json tagName,name,publishedAt \
    --jq '.[] | "  \(.tagName): \(.name) (\(.publishedAt))"' 2>/dev/null || log "  No releases for $repo"
}

update_topics() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  local org
  org=$(get_repo_org "$dir"); set_repo_token "$org"
  local topics=""
  case "$repo" in
    *agent*|*hermes*|*claude*|*copilot*|*openai*|*cod*) topics="ai,agent,llm,cli" ;;
    *awesome*|*collection*|*list*) topics="awesome,resources,curation" ;;
    *dnd*|*dice*|*rpg*|*tabletop*|*tts*) topics="tabletop,rpg,dnd,gaming" ;;
    *retropie*|*emulator*|*roms*) topics="retropie,emulation,retro-gaming" ;;
    *pwnagotchi*|*sdr*|*security*) topics="security,sdr,wifi,pwnagotchi" ;;
    *proxmox*|*pve*|*docker*|*deployment*) topics="infrastructure,devops,deployment" ;;
    *install*|*setup*|*helper*) topics="installer,setup,tool" ;;
  esac
  local current_topics
  current_topics=$(gh repo view "${org}/${repo}" --json repositoryTopics --jq '[.repositoryTopics[].name] | sort | join(",")' 2>/dev/null || echo "")
  local sorted_topics
  sorted_topics=$(echo "$topics" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
  if [ -n "$sorted_topics" ] && [ "$current_topics" != "$sorted_topics" ]; then
    log "TOPICS: $repo updating topics from '$current_topics' to '$sorted_topics'"
    gh repo edit "${org}/${repo}" --add-topic "$topics" 2>/dev/null || log "  Topics not updated for $repo"
  fi
}

# ===================== PARALLEL STATUS =====================
process_repo_status() {
  local repo="$1"; local dir="$REPOS_DIR/$repo"
  local tmpfile="$REPOS_DIR/$repo.status.tmp"
  local org
  org=$(get_repo_org "$dir"); set_repo_token "$org"
  {
    echo "--- $repo ---"
    check_gource "$repo" || echo "GOURCE-MISSING: $repo"
    check_readme_embed "$repo"
    local pr_count
    pr_count=$(gh pr list --repo "${org}/${repo}" --state open --json number --jq 'length' 2>/dev/null || echo "?")
    echo "PRS: $repo has $pr_count open PRs"
    local iss_count
    iss_count=$(gh issue list --repo "${org}/${repo}" --state open --json number --jq 'length' 2>/dev/null || echo "0")
    echo "ISS-COUNT: $iss_count"
    echo "DONE: $repo"
  } > "$tmpfile" 2>&1
}

compute_status_counters() {
  local total=0; local gource_missing=0; local readme_noembed=0
  local prs_total=0; local issues_total=0
  for tmpfile in "$REPOS_DIR"/*.status.tmp; do
    [ -f "$tmpfile" ] || continue
    local repo
    repo=$(basename "$tmpfile" .status.tmp)
    if grep -q "GOURCE-MISSING: $repo" "$tmpfile" 2>/dev/null; then ((gource_missing++)) || true; fi
    if grep -q "README-NOEMBED: $repo" "$tmpfile" 2>/dev/null; then ((readme_noembed++)) || true; fi
    if grep -q "PRS: $repo has" "$tmpfile" 2>/dev/null; then
      local pr_val
      pr_val=$(sed -n 's/.*has \([0-9]*\) open PR.*/\1/p' "$tmpfile" | head -1)
      [ -n "$pr_val" ] && [ "$pr_val" != "?" ] && ((prs_total += pr_val)) || true
    fi
    if grep -q "ISS-COUNT: " "$tmpfile" 2>/dev/null; then
      local iss_val
      iss_val=$(sed -n 's/ISS-COUNT: //p' "$tmpfile" | head -1)
      [ -n "$iss_val" ] && [ "$iss_val" != "?" ] && ((issues_total += iss_val)) || true
    fi
    if grep -q "DONE: $repo" "$tmpfile" 2>/dev/null; then ((total++)) || true; fi
  done
  echo "$total $gource_missing $readme_noembed $prs_total $issues_total" > "$REPOS_DIR/.status_counters"
}

cmd_status_parallel() {
  log "=== GitHub Fleet Status ==="
  rm -f "$REPOS_DIR"/*.status.tmp 2>/dev/null || true
  local max_jobs="${PARALLEL_JOBS:-4}"
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    local repo
    repo=$(basename "$repo_dir")
    # Bandbreedte-beheer: max N gelijktijdige children
    while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$max_jobs" ]; do
      sleep 0.2
    done
    process_repo_status "$repo" &
  done
  wait 2>/dev/null || true
  compute_status_counters
  local counters
  counters=$(cat "$REPOS_DIR/.status_counters" 2>/dev/null || echo "0 0 0 0 0")
  local total=$(echo "$counters" | cut -d' ' -f1)
  local gource_missing=$(echo "$counters" | cut -d' ' -f2)
  local readme_noembed=$(echo "$counters" | cut -d' ' -f3)
  local prs_total=$(echo "$counters" | cut -d' ' -f4)
  local issues_total=$(echo "$counters" | cut -d' ' -f5)
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    local repo
    repo=$(basename "$repo_dir")
    local tmpfile="$repo_dir.status.tmp"
    if [ -f "$tmpfile" ]; then cat "$tmpfile"; echo ""; fi
  done
  log "=== Status complete ==="
  log "Total: $total | Gource missing: $gource_missing | README noembed: $readme_noembed | Open PRs: $prs_total | Open issues: $issues_total"
  send_telegram_message "🚢 *GitHub Fleet Status*\n\n*Totaal:* $total repos\n*Gource video missing:* $gource_missing\n*README zonder embed:* $readme_noembed\n*Open PRs:* $prs_total\n*Open issues:* $issues_total\n\n📋 Volledig log: $LOG_FILE" || true
  rm -f "$REPOS_DIR"/*.status.tmp "$REPOS_DIR/.status_counters" 2>/dev/null || true
}

# ===================== API STATUS =====================
cmd_api_status() {
  log "=== GitHub Fleet API Status (without local clones) ==="
  log "Fetching all repos of itsdarklikehell via GitHub API (limit 1000)"
  local raw
  raw=$(gh repo list itsdarklikehell --limit 1000 --json name,updatedAt,visibility,hasIssuesEnabled,hasWikiEnabled,pushedAt 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
out = []
for r in data: out.append(r)
print(json.dumps(out))
" 2>/dev/null || true)
  if [ -z "$raw" ] || [ "$raw" = "[]" ] || [ "$raw" = "" ]; then
    log "ERROR: No repos fetched from GitHub API"
    RET_API_TOTAL=0; RET_API_PUBLIC=0; RET_API_PRIVATE=0
    RET_API_WITH_ISSUES=0; RET_API_WITH_WIKI=0; RET_API_RECENT=0
    RET_API_ERRORS=1; return 1
  fi
  local total_count
  total_count=$(echo "$raw" | jq 'length' 2>/dev/null || echo "0")
  RET_API_TOTAL="$total_count"
  log "Total repos found: $total_count"
  local public_count private_count issues_count wiki_count recent_count
  public_count=$(echo "$raw" | jq '[.[] | select(.visibility | ascii_downcase == "public")] | length' 2>/dev/null || echo "0")
  private_count=$(echo "$raw" | jq '[.[] | select(.visibility | ascii_downcase == "private")] | length' 2>/dev/null || echo "0")
  issues_count=$(echo "$raw" | jq '[.[] | select(.hasIssuesEnabled == true)] | length' 2>/dev/null || echo "0")
  wiki_count=$(echo "$raw" | jq '[.[] | select(.hasWikiEnabled == true)] | length' 2>/dev/null || echo "0")
  recent_count=$(echo "$raw" | jq '[.[] | select(.pushedAt != null and .pushedAt != "") | (.pushedAt | fromdateiso8601?) as $t | select($t > 0 and (now - $t) <= 2592000)] | length' 2>/dev/null || echo "0")
  RET_API_PUBLIC="$public_count"; RET_API_PRIVATE="$private_count"
  RET_API_WITH_ISSUES="$issues_count"; RET_API_WITH_WIKI="$wiki_count"
  RET_API_RECENT="$recent_count"; RET_API_ERRORS=0
  local csv_path="$LOG_FILE.api-status.csv"
  echo "repo,visibility,hasIssuesEnabled,hasWikiEnabled,updatedAt,pushedAt,days_since_push" > "$csv_path"
  echo "$raw" | jq -r '.[] | "\(.name),\(.visibility),\(.hasIssuesEnabled),\(.hasWikiEnabled),\(.updatedAt // ""),\(.pushedAt // ""),\(if .pushedAt then (now - (.pushedAt | fromdateiso8601? // 0)) / 86400 | floor else "no-push" end)"' 2>/dev/null >> "$csv_path" || true
  log "--- Statistics ---"
  log "Total:            $total_count repos"
  log "Public:            $public_count"
  log "Private:           $private_count"
  log "With issues:       $issues_count"
  log "With wiki:         $wiki_count"
  log "Recent (<30d):     $recent_count"
  log "CSV report:        $csv_path"
  log "=== API status complete ==="
}

# ===================== SYNC REPORT =====================
cmd_sync_report() {
  log "=== GitHub Fleet Sync Report ==="
  log "Comparing each cloned repo with its upstream remote"
  echo ""
  local synced=0; local behind=0; local no_upstream=0; local no_branch=0; local errors=0; local added_upstream=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local upstream
    upstream=$(find_upstream "$repo_dir")
    if [ -z "$upstream" ]; then
      local org
      org=$(get_repo_org "$repo_dir")
      if [ "$org" = "itsdarklikehell" ] || [ "$org" = "hans" ]; then
        log "$repo: OWN REPO — geen upstream nodig"
        echo ""; continue
      fi
      local parent
      parent=$(gh api "repos/$org/$repo" --jq '.parent.full_name' 2>/dev/null || echo "")
      if [ -n "$parent" ] && [ "$parent" != "null" ]; then
        log "$repo: Adding upstream remote: $parent"
        git -C "$repo_dir" remote add upstream "https://github.com/$parent.git" 2>/dev/null && log "  Upstream remote added" || log "  Upstream remote bestaat al"
        upstream="upstream"
        ((added_upstream++)) || true
      else
        log "$repo: no upstream remote"; ((no_upstream++)) || true; echo ""; continue
      fi
    fi
    log "--- $repo (upstream: $upstream) ---"
    local upstream_branch=""
    for branch in main master; do
      if git -C "$repo_dir" rev-parse --verify "${upstream}/${branch}" >/dev/null 2>&1; then
        upstream_branch="${upstream}/${branch}"; break; fi
    done
    if [ -z "$upstream_branch" ]; then log "  NO BRANCH: upstream has no main/master"; ((no_branch++)) || true; echo ""; continue; fi
    local local_commit
    local_commit=$(git -C "$repo_dir" rev-parse HEAD)
    local upstream_commit
    upstream_commit=$(git -C "$repo_dir" rev-parse "$upstream_branch" 2>/dev/null || echo "")
    if [ -z "$upstream_commit" ]; then log "  ERROR: cannot read upstream commit"; ((errors++)) || true; echo ""; continue; fi
    if [ "$local_commit" = "$upstream_commit" ]; then
      log "  EQUAL: $repo is up-to-date with upstream ($upstream_branch)"
      log "    Local: $(git -C "$repo_dir" log -1 --format='%h %s')"
      ((synced++)) || true
    else
      local behind_count ahead_count
      behind_count=$(git -C "$repo_dir" rev-list --count "${upstream_branch}..HEAD" 2>/dev/null || echo "?")
      ahead_count=$(git -C "$repo_dir" rev-list --count "HEAD..${upstream_branch}" 2>/dev/null || echo "?")
      log "  DIFF: $repo"
      log "    Local behind: $([ "$behind_count" != "?" ] && echo "$behind_count commits" || echo "unknown")"
      log "    Upstream ahead: $([ "$ahead_count" != "?" ] && echo "$ahead_count commits" || echo "unknown")"
      log "    Local HEAD: $(git -C "$repo_dir" log -1 --format='%h %s')"
      log "    Upstream HEAD: $(git -C "$repo_dir" log -1 --format='%h %s' "$upstream_branch")"
      if [ "$ahead_count" != "0" ] && [ "$ahead_count" != "?" ]; then log "    → ACTION: sync with upstream recommended"; fi
      ((behind++)) || true
    fi
    echo ""
  done
  log "=== Summary ==="
  log "Equal to upstream:     $synced repos"
  log "With diff (action):    $behind repos"
  log "No upstream remote:    $no_upstream repos"
  log "No upstream branch:    $no_branch repos"
  log "Errors:                $errors repos"
  log "=== Sync report complete ==="
  RET_SYNCED="$synced"; RET_BEHIND="$behind"
  RET_NO_UPSTREAM="$no_upstream"; RET_NO_BRANCH="$no_branch"
  RET_ERRORS="$errors"
}

# ===================== ACTION MONITOR =====================
cmd_action_monitor() {
  log "=== GitHub Fleet Action Monitor ==="
  log "Scanning all repos for unlabeled issues and adding 'triage' label"
  local total_labeled=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir")
    if [ "$org" = "hmol33" ] && [ -n "$HMOL33_TOKEN" ]; then export GITHUB_TOKEN="$HMOL33_TOKEN"
    else unset GITHUB_TOKEN; fi
    local unlabeled_list
    unlabeled_list=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,labels \
      --jq '.[] | select(.labels | length == 0) | "#\(.number): \(.title)"' 2>/dev/null || true)
    if [ -n "$unlabeled_list" ]; then
      local count
      count=$(echo "$unlabeled_list" | grep -c . || echo "0")
      log "  Unlabeled issues found: $count"
      local labeled_this_repo=0
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local number
        number=$(echo "$line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$number" ] && continue
        log "  → Adding label 'triage' to #$number"
        if gh issue edit "${org}/${repo}#$number" --add-label "triage" 2>/dev/null; then
          ((labeled_this_repo++)) || true; ((total_labeled++)) || true
        else log "    Failed: #$number"; fi
      done <<< "$unlabeled_list"
      log "  Labeled issues in $repo: $labeled_this_repo"
    else log "  No unlabeled issues"; fi
    echo ""
  done
  log "=== Action monitor complete ==="
  log "Total labeled issues: $total_labeled"
  RET_TOTAL_LABELED="$total_labeled"
}

# ===================== STALE CLEANUP =====================
cmd_stale_cleanup() {
  log "=== Stale Issue/PR Cleanup ==="
  log "Stale threshold: $STALE_CLOSE_DAYS days"
  local STALE_DAYS=$STALE_CLOSE_DAYS; local STALE_GRACE_DAYS=7
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local cutoff_date
    cutoff_date=$(date -d "$STALE_DAYS days ago" +%Y-%m-%d)
    local stale_issues
    stale_issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,updatedAt,comments \
      --jq ".[] | select(.updatedAt < \"$cutoff_date\") | \"#\(.number): \(.title)\"" 2>/dev/null || true)
    if [ -n "$stale_issues" ]; then
      log "  Stale issues found: $(echo "$stale_issues" | wc -l | tr -d ' ')"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local number
        number=$(echo "$line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$number" ] && continue
        local comment_count
        comment_count=$(gh issue view "${org}/${repo}#$number" --json comments --jq '.comments | length' 2>/dev/null || echo "0")
        if [ "$comment_count" -gt 0 ]; then
          local last_comment
          last_comment=$(gh api "repos/${org}/${repo}/issues/$number/comments" --jq '.[0].created_at' 2>/dev/null || echo "")
          if [ -n "$last_comment" ] && [[ "$last_comment" > "$cutoff_date" ]]; then
            log "  #$number: recent comment → skip"; continue; fi
        fi
        log "  Adding label 'stale' to #$number"
        gh issue edit "${org}/${repo}#$number" --add-label "stale" 2>/dev/null || log "    Failed: #$number"
      done <<< "$stale_issues"
    else log "  No stale issues"; fi
    local stale_prs
    stale_prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,title,updatedAt \
      --jq ".[] | select(.updatedAt < \"$cutoff_date\") | \"#\(.number): \(.title)\"" 2>/dev/null || true)
    if [ -n "$stale_prs" ]; then
      log "  Stale PRs found: $(echo "$stale_prs" | wc -l | tr -d ' ')"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local number
        number=$(echo "$line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$number" ] && continue
        log "  Adding label 'stale' to PR #$number"
        gh pr edit "${org}/${repo}#${number}" --add-label "stale" 2>/dev/null || log "    Failed: PR #$number"
      done <<< "$stale_prs"
    else log "  No stale PRs"; fi
    echo ""
  done
  log "=== Closing stale items (older than $STALE_GRACE_DAYS days with 'stale' label) ==="
  local grace_cutoff
  grace_cutoff=$(date -d "$STALE_DAYS + $STALE_GRACE_DAYS days ago" +%Y-%m-%d)
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local old_stale_issues
    old_stale_issues=$(gh issue list --repo "${org}/${repo}" --state open --label "stale" --json number,title,updatedAt \
      --jq ".[] | select(.updatedAt < \"$grace_cutoff\") | \"#\(.number): \(.title)\"" 2>/dev/null || true)
    if [ -n "$old_stale_issues" ]; then
      log "  Old stale issues to close: $(echo "$old_stale_issues" | wc -l | tr -d ' ')"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local number
        number=$(echo "$line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$number" ] && continue
        log "  Closing issue #$number"
        gh issue close "${org}/${repo}#$number" 2>/dev/null && log "    Closed" || log "    Failed: #$number"
      done <<< "$old_stale_issues"
    else log "  No old stale issues"; fi
    local old_stale_prs
    old_stale_prs=$(gh pr list --repo "${org}/${repo}" --state open --label "stale" --json number,title,updatedAt \
      --jq ".[] | select(.updatedAt < \"$grace_cutoff\") | \"#\(.number): \(.title)\"" 2>/dev/null || true)
    if [ -n "$old_stale_prs" ]; then
      log "  Old stale PRs to close: $(echo "$old_stale_prs" | wc -l | tr -d ' ')"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local number
        number=$(echo "$line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$number" ] && continue
        log "  Closing PR #$number"
        gh pr close "${org}/${repo}#${number}" 2>/dev/null && log "    Closed" || log "    Failed: PR #$number"
      done <<< "$old_stale_prs"
    else log "  No old stale PRs"; fi
    echo ""
  done
  log "=== Stale cleanup complete ==="
}

# ===================== LABEL ISSUES (policy engine) =====================
: "${LABEL_POLICY_FILE:=}"
: "${LABEL_REMOVE_MISMATCHED:=false}"
: "${LABEL_MATCH_BODY:=true}"

cmd_label_issues() {
  log "=== Issue Labeling (advanced policy engine) ==="
  declare -A keyword_map
  if [ -n "$LABEL_POLICY_FILE" ] && [ -f "$LABEL_POLICY_FILE" ]; then
    log "Label policy loaded from $LABEL_POLICY_FILE"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      [[ "$line" =~ ^# ]] && continue
      IFS=: read -r label_name keywords <<< "$line"
      label_name=$(echo "$label_name" | xargs)
      keywords=$(echo "$keywords" | xargs)
      [ -z "$label_name" ] || [ -z "$keywords" ] && continue
      keyword_map["$label_name"]="$keywords"
    done < "$LABEL_POLICY_FILE"
  else
    keyword_map["bug"]="bug,fix,hack,fixme,crash,error,panic,failure,regression,issue"
    keyword_map["feature"]="feature,enhancement,improvement,wish,new,add,implement,support"
    keyword_map["documentation"]="doc,documentation,readme,docs,wiki,comment,commentary,guide,tutorial"
    keyword_map["question"]="question,help,how,to,howto,clarify,explain"
    keyword_map["good first issue"]="good first,beginner,easy,friendly,welcome"
    keyword_map["priority:high"]="urgent,critical,severe,security,vulnerability,emergency,breaking"
    keyword_map["needs:triage"]="triage,needs review,needs investigation,unclear"
  fi
  log "Active labels: ${!keyword_map[*]}"
  [ "$LABEL_REMOVE_MISMATCHED" = "true" ] && log "Label removal enabled (mismatch → remove)"
  local labeled=0; local removed=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local issues_json
    issues_json=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,body,labels --limit 100 2>/dev/null || true)
    if [ -z "$issues_json" ]; then log "  No issues found or API error"; continue; fi
    local issue_count
    issue_count=$(echo "$issues_json" | jq length 2>/dev/null || echo "0")
    log "  Issues: $issue_count"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local number
      number=$(echo "$line" | jq -r '.number // empty' 2>/dev/null)
      [ -z "$number" ] && continue
      local title
      title=$(echo "$line" | jq -r '.title // empty' 2>/dev/null)
      local body
      body=$(echo "$line" | jq -r '.body // ""' 2>/dev/null)
      local current_labels
      current_labels=$(echo "$line" | jq -r '.labels // [] | map(.name) | join(",")' 2>/dev/null)
      local matched_new=""
      for label_key in "${!keyword_map[@]}"; do
        local keywords="${keyword_map[$label_key]}"
        local search_text="$title"
        [ "$LABEL_MATCH_BODY" = "true" ] && search_text="$title $body"
        if echo "$search_text" | grep -qiE "$keywords"; then matched_new="$matched_new,$label_key"; fi
      done
      matched_new=$(echo "$matched_new" | sed 's/^,//' | sed 's/,/, /g' | tr ' ' '_' | sed 's/_/,/g' | sed 's/^,//')
      matched_new=$(echo "$matched_new" | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
      local current_clean
      current_clean=$(echo "$current_labels" | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
      local to_add=""
      if [ -n "$matched_new" ]; then
        while IFS= read -r new_lbl; do
          [ -z "$new_lbl" ] && continue
          if ! echo "$current_clean" | grep -qF "$new_lbl"; then to_add="$to_add $new_lbl"; fi
        done <<< "$(echo "$matched_new" | tr ',' '\n')"
      fi
      if [ -n "$to_add" ]; then
        log "  #$number: adding labels:$to_add"
        gh issue edit "${org}/${repo}#$number" --add-label "$to_add" 2>/dev/null && ((labeled++)) || true
      fi
      if [ "$LABEL_REMOVE_MISMATCHED" = "true" ] && [ -n "$matched_new" ]; then
        while IFS= read -r cur_lbl; do
          [ -z "$cur_lbl" ] && continue
          if ! echo "$matched_new" | grep -qF "$cur_lbl"; then
            log "  #$number: removing label $cur_lbl (no longer matched)"
            gh issue edit "${org}/${repo}#$number" --remove-label "$cur_lbl" 2>/dev/null && ((removed++)) || true
          fi
        done <<< "$(echo "$current_clean" | tr ',' '\n')"
      fi
      echo ""
    done < <(echo "$issues_json" | jq -c '.[]' 2>/dev/null)
    echo ""
  done
  log "=== Issue labeling complete ==="
  log "Labels added: $labeled | Labels removed: $removed"
  RET_LABEL_ISSUES_ADDED="$labeled"
  RET_LABEL_ISSUES_REMOVED="$removed"
}

# ===================== WELCOME CONTRIBUTORS =====================
cmd_welcome_contributors() {
  log "=== Welcome New Contributors ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local week_ago
    week_ago=$(date -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)
    local recent_issues
    recent_issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,author,createdAt \
      --jq ".[] | select(.createdAt > \"$week_ago\") | \"#\(.number): \(.author)\"" 2>/dev/null || true)
    local recent_prs
    recent_prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,author,createdAt \
      --jq ".[] | select(.createdAt > \"$week_ago\") | \"#\(.number): \(.author)\"" 2>/dev/null || true)
    local all_activity="$recent_issues"$'\n'"$recent_prs"
    local unique_authors
    unique_authors=$(echo "$all_activity" | grep -oP ': \K.*' | sort -u)
    for author in $unique_authors; do
      [ -z "$author" ] && continue
      local total_contributions
      total_contributions=$(gh api "repos/${org}/${repo}/contributors" --jq ".[] | select(.login == \"$author\") | .contributions" 2>/dev/null || echo "0")
      if [ "$total_contributions" -le 1 ] 2>/dev/null; then
        log "  Welcoming new contributor: $author"
        local recent_item
        recent_item=$(echo "$all_activity" | grep "$author" | head -1)
        local item_number
        item_number=$(echo "$recent_item" | grep -oP '#\K[0-9]+' || echo "")
        if [ -n "$item_number" ]; then
          gh issue comment "${org}/${repo}#$item_number" --body "Welcome @$author! 🎉 We're glad you're here. Check out CONTRIBUTING.md for guidelines, and feel free to ask questions." 2>/dev/null || log "    Failed"
        fi
      fi
    done
    echo ""
  done
  log "=== Welcome contributors complete ==="
}

# ===================== CI MONITOR =====================
cmd_ci_monitor() {
  log "=== CI Status Monitor ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local open_prs
    open_prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,title,headRefName,url \
      --jq '.[] | "#\(.number): \(.title) (\(.headRefName))"' 2>/dev/null || true)
    if [ -n "$open_prs" ]; then
      while IFS= read -r pr_line; do
        [ -z "$pr_line" ] && continue
        local pr_number
        pr_number=$(echo "$pr_line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$pr_number" ] && continue
        local pr_title
        pr_title=$(echo "$pr_line" | sed 's/^#[0-9]*: //' | sed 's/ (.*//')
        log "  PR #$pr_number: $pr_title"
        local checks
        checks=$(gh api "repos/${org}/${repo}/pulls/$pr_number/checks" --jq '[.[] | "\(.name): \(.status) \(.conclusion // "none")"] | join("\n")' 2>/dev/null || echo "")
        if echo "$checks" | grep -qE "failure|neutral"; then
          log "    FAILED: $checks"
          local failed_checks
          failed_checks=$(echo "$checks" | grep -E "failure|neutral" || true)
          if [ -n "$failed_checks" ]; then
            log "    → Commenting with failed checks"
            gh pr comment "${org}/${repo}#$pr_number" --body "⚠️ CI-checks failed:\n\n```\n$failed_checks\n```\n\nCheck the logs for details." 2>/dev/null || log "      Failed to comment"
          fi
        else log "    OK"; fi
      done <<< "$open_prs"
    else log "  No open PRs"; fi
    echo ""
  done
  log "=== CI monitor complete ==="
}

# ===================== AUTO SYNC =====================
cmd_auto_sync() {
  log "=== GitHub Fleet Auto-Sync ==="
  log "Pulling upstream for all repos (no push — safe)"
  local pulled=0; local conflicts=0; local up_to_date=0; local errors=0; local added_upstream=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local upstream=""
    for r in $(cd "$repo_dir" && git remote 2>/dev/null); do
      if [ "$r" != "origin" ]; then upstream="$r"; break; fi
    done
    # Geen upstream? Probeer de fork-upstream te detecteren via GitHub API
    if [ -z "$upstream" ]; then
      local org
      org=$(get_repo_org "$repo_dir")
      if [ "$org" = "itsdarklikehell" ] || [ "$org" = "hans" ]; then
        # Dit is een eigen repo — geen upstream nodig (we zijn de origin)
        log "  OWN REPO: $org/$repo — geen upstream nodig"
        echo ""; continue
      fi
      # Dit is een fork van een ander org — zoek de parent
      local parent
      parent=$(gh api "repos/$(get_repo_org "$repo_dir")/$repo" --jq '.parent.full_name' 2>/dev/null || echo "")
      if [ -n "$parent" ] && [ "$parent" != "null" ]; then
        local parent_short
        parent_short=$(echo "$parent" | cut -d/ -f2)
        log "  Adding upstream remote: $parent"
        git -C "$repo_dir" remote add upstream "https://github.com/$parent.git" 2>/dev/null && log "  Upstream remote added" || log "  Upstream remote exists al"
        upstream="upstream"
        ((added_upstream++)) || true
      else
        log "  No upstream remote → skip"; echo ""; continue
      fi
    fi
    local upstream_branch=""
    for branch in main master; do
      if git -C "$repo_dir" rev-parse --verify "${upstream}/${branch}" >/dev/null 2>&1; then
        upstream_branch="${upstream}/${branch}"; break; fi
    done
    if [ -z "$upstream" ]; then
      local org
      org=$(get_repo_org "$repo_dir")
      if [ "$org" = "itsdarklikehell" ] || [ "$org" = "hans" ]; then
        # Dit is een eigen repo (of een repo van hans) — geen upstream nodig
        log "  OWN REPO: $org/$repo — geen upstream nodig"
        echo ""; continue
      fi
      # Dit is een fork van een ander org — zoek de parent
      local parent
      parent=$(gh api "repos/$org/$repo" --jq '.parent.full_name' 2>/dev/null || echo "")
      if [ -n "$parent" ] && [ "$parent" != "null" ]; then
        log "  Adding upstream remote: $parent"
        git -C "$repo_dir" remote add upstream "https://github.com/$parent.git" 2>/dev/null && log "  Upstream remote added" || log "  Upstream remote exists al"
        upstream="upstream"
      else
        log "  No upstream remote → skip"; echo ""; continue
      fi
    fi
    git -C "$repo_dir" fetch "$upstream" --quiet 2>/dev/null || {
      log "  ERROR: fetch failed"; ((errors++)) || true; echo ""; continue; }
    local local_commit
    local_commit=$(git -C "$repo_dir" rev-parse HEAD)
    local upstream_commit
    upstream_commit=$(git -C "$repo_dir" rev-parse "$upstream_branch" 2>/dev/null || echo "")
    if [ "$local_commit" = "$upstream_commit" ]; then
      log "  UP-TO-DATE: matches $upstream_branch"; ((up_to_date++)) || true
    else
      local branch_name="${upstream_branch#*/}"
      if git -C "$repo_dir" pull "$upstream" "$branch_name" --no-rebase --quiet 2>/dev/null; then
        log "  PULL SUCCESS: pulled from $upstream_branch"; ((pulled++)) || true
      else
        if git -C "$repo_dir" status --short 2>/dev/null | grep -q "^UU"; then
          log "  CONFLICT: merge conflict during pull — manual intervention needed"
          ((conflicts++)) || true
        else log "  PULL FAILED: non-validated diverged state"; ((errors++)) || true; fi
      fi
    fi
    echo ""
  done
  log "=== Auto-sync summary ==="
  log "Pulled successfully:  $pulled repos"
  log "Up-to-date:            $up_to_date repos"
  log "Merge conflicts:       $conflicts repos"
  log "Errors:                $errors repos"
  log "=== Auto-sync complete ==="
}

# ===================== GOURCE TRIGGER/REFRESH =====================
cmd_gource_trigger() {
  log "=== Gource Workflow Trigger ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    if [ -f "$repo_dir/.github/workflows/gource.yml" ]; then
      log "Trigger gource workflow for $repo"
      local org
      org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
      if gh workflow run --repo "${org}/$repo" gource.yml 2>&1 | tee -a "$LOG_FILE"; then
        log "  Success"
      else log "  Use workflow_dispatch manually"; fi
    fi
  done
  log "=== Gource trigger complete ==="
}

cmd_gource_refresh() {
  log "=== Gource Video Refresh ==="
  local triggered=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    if [ -f "$repo_dir/.github/workflows/gource.yml" ]; then
      local last_commit
      last_commit=$(git -C "$repo_dir" log -1 --format='%ct' 2>/dev/null || echo "0")
      local now
      now=$(date +%s)
      local age_days=$(( (now - last_commit) / 86400 ))
      if [ "$age_days" -le 30 ]; then
        log "Trigger gource for $repo (recent activity: $age_days days)"
        local org
        org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
        gh workflow run --repo "${org}/$repo" gource.yml 2>&1 | tee -a "$LOG_FILE" && log "  Success" || log "  Missed"
        ((triggered++)) || true
      else log "Skip $repo (no recent activity: $age_days days)"; fi
    fi
  done
  log "=== Gource refresh complete ($triggered repos triggered) ==="
}

# ===================== DEPENDENCY CHECK =====================
cmd_dep_check() {
  log "=== Dependency Check ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    cd "$repo_dir"
    if [ -f "package.json" ]; then
      if command -v pnpm >/dev/null 2>&1; then
        log "  Checking pnpm dependencies..."
        local outdated
        outdated=$(pnpm outdated --format json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pkg in data.get('dependencies', {}).get('outdated', []):
    print(f\"{pkg['name']}: {pkg['current']} -> {pkg['latest']}\")
" 2>/dev/null || true)
        if [ -n "$outdated" ]; then
          log "  Outdated npm deps: $(echo "$outdated" | wc -l | tr -d ' ') packages"
          echo "$outdated" | while IFS= read -r line; do [ -z "$line" ] && continue; log "    $line"; done
        else log "  No outdated npm dependencies"; fi
      fi
    fi
    if [ -f "requirements.txt" ]; then
      log "  Checking Python dependencies..."
      if [ -f ".venv/bin/pip" ]; then
        local outdated
        outdated=$(.venv/bin/pip list --outdated --format json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pkg in data:
    print(f\"{pkg['name']}: {pkg['version']} -> {pkg['latest_version']}\")
" 2>/dev/null || true)
        if [ -n "$outdated" ]; then
          log "  Outdated Python deps: $(echo "$outdated" | wc -l | tr -d ' ') packages"
          echo "$outdated" | while IFS= read -r line; do [ -z "$line" ] && continue; log "    $line"; done
        else log "  No outdated Python dependencies"; fi
      fi
    fi
    if [ -f "pyproject.toml" ]; then log "  pyproject.toml found (dependency check not automatic for poetry/pdm)"; fi
    if [ -f "go.mod" ]; then log "  Go modules found (dependency check not automatic)"; fi
    echo ""
  done
  log "=== Dependency check complete ==="
}

# ===================== SECURITY CHECK =====================
cmd_security_check() {
  log "=== Security Alert Check ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local alerts
    alerts=$(gh api "repos/${org}/${repo}/dependabot/alerts" --jq '.[] | "#\(.number): \(.security_advisory.severity) - \(.security_advisory.summary) [\(.security_advisory.identifiers[0].alias)]"' 2>/dev/null || true)
    if [ -n "$alerts" ]; then
      log "  Security alerts: $(echo "$alerts" | wc -l | tr -d ' ')"
      echo "$alerts" | while IFS= read -r line; do [ -z "$line" ] && continue; log "    $line"; done
      echo "$alerts" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        local alert_num
        alert_num=$(echo "$line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$alert_num" ] && continue
        if ! gh issue view "${org}/${repo}#$alert_num" --json state --jq '.state' 2>/dev/null | grep -q "open"; then
          log "    → Creating issue #$alert_num for security alert"
          gh issue create "${org}/${repo}" --title "SECURITY: ${line#*: }" --body "Security alert from Dependabot:\n\n$line\n\nSee https://github.com/${org}/${repo}/security for details." --label "security,bug" 2>/dev/null || log "      Failed"
        fi
      done
    else log "  No security alerts"; fi
    echo ""
  done
  log "=== Security check complete ==="
}

# ===================== RELEASE DRAFT =====================
cmd_release_draft() {
  log "=== Release Draft Generator ==="
  local drafted=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir")
    local compare_tag
    compare_tag=$(git -C "$repo_dir" describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -z "$compare_tag" ]; then compare_tag="v0.1.0"; log "  No tags found → using v0.1.0 as baseline"; fi
    local last_release_date=""; local last_release_tag=""
    local release_info
    release_info=$(gh release list --repo "$org/$repo" --limit 1 --json tagName,createdAt --jq '.[0] | "\(.tagName) \(.createdAt)"' 2>/dev/null || true)
    if [ -n "$release_info" ]; then
      last_release_tag=$(echo "$release_info" | cut -d' ' -f1)
      last_release_date=$(echo "$release_info" | cut -d' ' -f2)
      if [ -n "$last_release_date" ]; then
        local release_epoch cutoff_epoch
        release_epoch=$(date -d "$last_release_date" '+%s' 2>/dev/null || echo "0")
        cutoff_epoch=$(date -d '90 days ago' '+%s' 2>/dev/null || echo "0")
        if [ "$release_epoch" -lt "$cutoff_epoch" ] 2>/dev/null; then
          log "  Last release $last_release_tag is >90 days old → new draft"
          compare_tag=""
        else log "  Last release $last_release_tag is recent → only new commits"; fi
      fi
    else log "  No releases found → creating draft from commits"; fi
    local commits=""
    if [ -z "$compare_tag" ]; then
      commits=$(git -C "$repo_dir" log --pretty=format:"%h %s" 2>/dev/null || echo "")
    else commits=$(git -C "$repo_dir" log "${compare_tag}..HEAD" --pretty=format:"%h %s" 2>/dev/null || echo ""); fi
    local commit_count
    commit_count=$(echo "$commits" | grep -c . 2>/dev/null || echo "0")
    commit_count=${commit_count//$'\n'/}
    [ -z "$commit_count" ] && commit_count=0
    if [ "$commit_count" -eq 0 ]; then log "  No new commits → skip"; echo ""; continue; fi
    log "  $commit_count commits to document"
    local features=$(echo "$commits" | grep -E "^[^ ]+ feat:" || true)
    local fixes=$(echo "$commits" | grep -E "^[^ ]+ fix:" || true)
    local docs=$(echo "$commits" | grep -E "^[^ ]+ docs:" || true)
    local chore=$(echo "$commits" | grep -E "^[^ ]+ chore:" || true)
    local release_body="## Changes\n\n"
    [ -n "$features" ] && release_body+="### Features\n\n$(echo "$features" | sed 's/^/ - /')\n\n"
    [ -n "$fixes" ] && release_body+="### Fixes\n\n$(echo "$fixes" | sed 's/^/ - /')\n\n"
    [ -n "$docs" ] && release_body+="### Documentation\n\n$(echo "$docs" | sed 's/^/ - /')\n\n"
    [ -n "$chore" ] && release_body+="### Maintenance\n\n$(echo "$chore" | sed 's/^/ - /')\n\n"
    release_body+="---\n\nAuto-generated release notes.\n\n**Contributors:** $(git -C "$repo_dir" log "${compare_tag:-HEAD 1}"..HEAD --pretty=format:"%an" 2>/dev/null | sort -u | tr '\n' ', ' | sed 's/, $//')\n"
    local draft_tag
    if [ -n "$last_release_tag" ]; then draft_tag="${last_release_tag}-refresh"
    else draft_tag="v$(date +%Y%m%d)-draft"; fi
    log "  Creating draft release: $draft_tag"
    if gh release create "$draft_tag" --draft --title "Draft: $draft_tag" --notes "$release_body" --repo "$org/$repo" 2>/dev/null; then
      log "  ✅ Draft created"; drafted=$((drafted + 1))
    else log "  ❌ Failed"; fi
    echo ""
  done
  log "=== Release draft complete ==="
  log "Draft releases created: $drafted"
  RET_RELEASE_DRAFT="$drafted"
}

# ===================== RELEASE PUBLISH =====================
cmd_release_publish() {
  log "=== Release Publish (draft → published) ==="
  local published=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local releases
    releases=$(gh release list --repo "${org}/${repo}" --json tagName,isDraft 2>/dev/null || echo "[]")
    if [ -z "$releases" ] || [ "$releases" = "[]" ]; then log "  No releases found → skip"; echo ""; continue; fi
    local draft_tags
    draft_tags=$(echo "$releases" | python3 -c "
import json, sys
data = json.load(sys.stdin)
drafts = [r['tagName'] for r in data if r.get('isDraft')]
print('\n'.join(drafts))
" 2>/dev/null || true)
    if [ -z "$draft_tags" ]; then log "  No draft releases → skip"; echo ""; continue; fi
    log "  Draft releases found: $(echo "$draft_tags" | tr '\n' ' ')"
    while IFS= read -r tag; do
      [ -z "$tag" ] && continue
      local is_draft
      is_draft=$(gh release view "$tag" --repo "${org}/${repo}" --json isDraft 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('isDraft',False)).lower())" 2>/dev/null || echo "false")
      if [ "$is_draft" != "true" ]; then log "  $tag is not a draft (or not accessible) → skip"; continue; fi
      log "  Publishing: $tag"
      if gh release edit "$tag" --repo "${org}/${repo}" --draft=false 2>/dev/null; then
        log "  ✓ $tag published"; ((published++)) || true
      else log "  ✗ $tag publish failed"; fi
    done <<< "$draft_tags"
    echo ""
  done
  log "=== Release publish complete: $published draft(s) published ==="
  RET_PUBLISHED="$published"
}

# ===================== README CHECK =====================
cmd_readme_check() {
  log "=== README Validation ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    local readme="$repo_dir/README.md"
    if [ ! -f "$readme" ]; then log "  README.md missing!"; echo ""; continue; fi
    local required_sections=("## Installation" "## Usage" "## Features" "## Contributing")
    local missing=""
    for section in "${required_sections[@]}"; do
      if ! grep -qi "$section" "$readme" 2>/dev/null; then missing+="- $section\n"; fi
    done
    if [ -n "$missing" ]; then
      log "  Missing sections:"
      echo -e "$missing" | while IFS= read -r line; do [ -z "$line" ] && continue; log "    $line"; done
    else log "  All required sections present"; fi
    echo ""
  done
  log "=== README check complete ==="
}

# ===================== FLEET HEALTH =====================
cmd_fleet_health() {
  log "=== GitHub Fleet Health ==="
  local ok=0; local issues=0; local total=0
  local repos_with_issues=0
  local gource_missing=0; local readme_noembed=0; local no_ci=0
  local stale_issues_total=0; local open_prs_total=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    total=$((total + 1))
    local repo_issues=0; local repo_has_issue=0
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    if [ -f "$repo_dir/.github/workflows/gource.yml" ]; then ((ok++)) || true
    else
      log "PROBLEM: $repo has no Gource workflow"
      ((gource_missing++)) || true; ((issues++)) || true; ((repo_issues++)) || true; repo_has_issue=1
    fi
    if [ -f "$repo_dir/README.md" ]; then
      if ! grep -q "gource.gif\|gource.mp4" "$repo_dir/README.md" 2>/dev/null; then
        log "  README-NOEMBED: $repo has no Gource video in README"
        ((readme_noembed++)) || true; ((issues++)) || true; ((repo_issues++)) || true; repo_has_issue=1
      fi
    else
      log "  README-MISSING: $repo has no README.md"
      ((issues++)) || true; ((repo_issues++)) || true; repo_has_issue=1
    fi
    if [ -d "$repo_dir/.github/workflows" ]; then
      local has_ci=false
      for wf in "$repo_dir/.github/workflows/"*.yml; do
        [ -f "$wf" ] || continue
        if grep -q "on:.*push:\|on:.*pull_request:" "$wf" 2>/dev/null; then has_ci=true; break; fi
      done
      if ! $has_ci; then
        log "  NO-CI: $repo has no CI workflow (push/pull_request trigger)"
        ((no_ci++)) || true; ((issues++)) || true; ((repo_issues++)) || true; repo_has_issue=1
      fi
    else
      log "  NO-CI-DIR: $repo has no .github/workflows directory"
      ((no_ci++)) || true; ((issues++)) || true; ((repo_issues++)) || true; repo_has_issue=1
    fi
    local stale_count
    stale_count=$(gh issue list --repo "${org}/${repo}" --state open --label "stale" --json number --jq 'length' 2>/dev/null || echo "0")
    if [ "$stale_count" -gt 0 ] 2>/dev/null; then
      log "  STALE-ISSUES: $repo has $stale_count stale issues"
      ((stale_issues_total += stale_count)) || true
    fi
    local pr_count
    pr_count=$(gh pr list --repo "${org}/${repo}" --state open --json number --jq 'length' 2>/dev/null || echo "0")
    if [ "$pr_count" -gt 0 ] 2>/dev/null; then ((open_prs_total += pr_count)) || true; fi
    if [ $repo_has_issue -eq 1 ]; then ((repos_with_issues++)) || true; fi
    if [ $repo_issues -eq 0 ]; then log "OK: $repo healthy"; fi
    echo ""
  done
  log ""
  log "=== Summary ==="
  log "Total repos:            $total"
  log "OK (no issues):         $((total - repos_with_issues))"
  log "Repos with issues:      $repos_with_issues"
  log ""
  log "Gource workflow missing: $gource_missing"
  log "README without embed:    $readme_noembed"
  log "No CI workflow:          $no_ci"
  log ""
  log "Open stale issues:       $stale_issues_total"
  log "Open PRs:                $open_prs_total"
  log ""
  if [ $issues -gt 0 ]; then
    log "Fleet health: ISSUES FOUND — see above"
    exit 1
  else
    log "Fleet health: ALL OK"
    exit 0
  fi
}

# ===================== LABEL PRS BY CHANGED FILES =====================
cmd_label_prs_by_files() {
  log "=== Label PRs by Changed Files ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local labeled=0
  local prs
  prs=$(gh search prs --state open --limit 100 --json number,repository,headRefName --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)|\(.headRefName)"' 2>/dev/null || true)
  if [ -n "$prs" ]; then
    while IFS='|' read -r pr_number repo headRef; do
      [ -z "$pr_number" ] && continue
      log "--- PR #$pr_number in $repo ---"
      local diff_files
      diff_files=$(gh pr diff "$repo#$pr_number" --name-only 2>/dev/null || true)
      if [ -z "$diff_files" ]; then log "  No diff available"; continue; fi
      local labels_to_add=""
      echo "$diff_files" | while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
          *.test.*|*.spec.*|test_*|*test/*) labels_to_add+=" testing," ;;
          *.md|*.txt|*.rst|docs/*|*/docs/*) labels_to_add+=" documentation," ;;
          *.json|*.yaml|*.yml|*.toml|*.cfg|*.ini|*.conf|*.env) labels_to_add+=" config," ;;
          *.md) labels_to_add+=" docs," ;;
        esac
      done
      labels_to_add=$(echo "$labels_to_add" | tr ',' '\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
      if [ -n "$labels_to_add" ]; then
        log "  Adding labels: $labels_to_add"
        if gh pr edit "$repo#$pr_number" --add-label "$labels_to_add" 2>/dev/null; then
          ((labeled++)) || true
        else log "    Failed to label"; fi
      else log "  No labels to add based on changed files"; fi
    done <<< "$prs"
  else log "No open PRs found"; fi
  log "=== Label PRs by files complete ==="
  log "Labeled: $labeled"
  RET_LABEL_PRS_FILES="$labeled"
}

# ===================== PR AGE REPORT =====================
cmd_pr_age_report() {
  log "=== PR Age Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local total=0; local avg_hours=0; local fastest_hours=99999; local slowest_hours=0
  local slow_prs=""
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,createdAt,updatedAt --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)|\(.createdAt)|\(.updatedAt)"' 2>/dev/null || true)
  if [ -n "$open_prs" ]; then
    while IFS='|' read -r pr_number repo created updated; do
      [ -z "$pr_number" ] && continue
      local created_epoch updated_epoch
      created_epoch=$(date -d "$created" '+%s' 2>/dev/null || echo "0")
      updated_epoch=$(date -d "$updated" '+%s' 2>/dev/null || echo "0")
      if [ "$created_epoch" != "0" ] && [ "$updated_epoch" != "0" ]; then
        local age_hours=$(( (updated_epoch - created_epoch) / 3600 ))
        log "  PR #$pr_number: $(printf '%dh' $age_hours) since creation"
        total=$((total + 1))
        avg_hours=$((avg_hours + age_hours))
        [ "$age_hours" -lt "$fastest_hours" ] && fastest_hours=$age_hours
        [ "$age_hours" -gt "$slowest_hours" ] && slowest_hours=$age_hours
        if [ "$age_hours" -gt 168 ]; then
          slow_prs+="  #$pr_number in $repo: ${age_hours}h ($(date -d "$created" '+%Y-%m-%d'))\\n"
        fi
      fi
    done <<< "$open_prs"
  else log "No open PRs found"; fi
  if [ "$total" -gt 0 ]; then
    avg_hours=$((avg_hours / total))
    log "=== Age summary ==="
    log "Total open PRs: $total"
    log "Avg age: ${avg_hours}h | Fastest: ${fastest_hours}h | Slowest: ${slowest_hours}h"
    if [ -n "$slow_prs" ]; then
      log "PRs older than 7 days:"
      echo -e "$slow_prs" | while IFS= read -r line; do [ -z "$line" ] && continue; log "  $line"; done
    fi
  fi
  RET_PR_AGE_TOTAL="$total"
  RET_PR_AGE_AVG_HOURS="$avg_hours"
  log "=== PR Age Report complete ==="
}

# ===================== DEPENDENCY ENHANCED CHECK =====================
cmd_dep_check_enhanced() {
  log "=== Dependency Enhanced Check ==="
  local total_outdated=0; local repos_with_outdated=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    cd "$repo_dir"
    if [ -f "package.json" ]; then
      if command -v pnpm >/dev/null 2>&1; then
        local outdated_json
        outdated_json=$(pnpm outdated --format json 2>/dev/null || true)
        local dep_count
        dep_count=$(echo "$outdated_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('dependencies',{}).get('outdated',[])) + len(d.get('devDependencies',{}).get('outdated',[])))" 2>/dev/null || echo "0")
        dep_count=$(echo "$dep_count" | grep -oE '^[0-9]+$' || echo "0")
        [ -z "$dep_count" ] && dep_count=0
        if [ "$dep_count" -gt 0 ]; then
          log "  Outdated npm deps: $dep_count packages"
          repos_with_outdated=$((repos_with_outdated + 1))
          total_outdated=$((total_outdated + dep_count))
          echo "$outdated_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for grp in ['dependencies', 'devDependencies']:
    for pkg in d.get(grp, {}).get('outdated', []):
        print(f\"  {pkg['name']}: {pkg['current']} -> {pkg['latest']} ({pkg['type']})\")
" 2>/dev/null | while IFS= read -r line; do [ -z "$line" ] && continue; log "$line"; done
        else log "  No outdated npm dependencies"; fi
      fi
    fi
    if [ -f "requirements.txt" ]; then
      if [ -f ".venv/bin/pip" ]; then
        local py_outdated
        py_outdated=$(.venv/bin/pip list --outdated --format json 2>/dev/null || true)
        local py_count
        py_count=$(echo "$py_outdated" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        py_count=$(echo "$py_count" | grep -oE '^[0-9]+$' || echo "0")
        [ -z "$py_count" ] && py_count=0
        if [ "$py_count" -gt 0 ]; then
          log "  Outdated Python deps: $py_count packages"
          repos_with_outdated=$((repos_with_outdated + 1))
          total_outdated=$((total_outdated + py_count))
        else log "  No outdated Python dependencies"; fi
      fi
    fi
    echo ""
  done
  log "=== Dependency enhanced check complete ==="
  log "Total outdated: $total_outdated across $repos_with_outdated repos"
  RET_DEP_CHECK_ENHANCED_TOTAL="$total_outdated"
  RET_DEP_CHECK_ENHANCED_REPOS="$repos_with_outdated"
}

# ===================== FORK SYNC (gh repo sync) =====================
cmd_fork_sync_gh() {
  log "=== GitHub Fleet Fork Sync (gh repo sync) ==="
  log "Syncing forks with upstream via gh repo sync"
  local synced=0; local failed=0; local skipped=0
  local all_repos
  all_repos=$(gh repo list "$(gh api user --jq .login 2>/dev/null || echo itsdarklikehell)" --limit 200 --json nameWithOwner,isFork,parent --jq '.[] | select(.isFork == true and .parent != null) | "\(.nameWithOwner) \(.parent.nameWithOwner)"' 2>/dev/null | grep -v 'null' | grep -v '^$' || true)
  for entry in $all_repos; do
    [ -z "$entry" ] && continue
    local fork_name
    fork_name=$(echo "$entry" | cut -d' ' -f1)
    local upstream_name
    upstream_name=$(echo "$entry" | cut -d' ' -f2)
    log "--- $fork_name → $upstream_name ---"
    local behind
    behind=$(gh api "repos/$fork_name" --jq '.behind_by // 0' 2>/dev/null)
    if [ -z "$behind" ] || [ "$behind" = "null" ]; then
      log "  Repo not found or not accessible — skip"; ((skipped++)) || true; continue; fi
    behind=${behind:-0}
    if [ "$behind" -eq 0 ]; then
      log "  Up-to-date (behind: 0) — skip"; ((skipped++)) || true; continue; fi
    log "  Behind by $behind commits"
    if gh repo sync "$fork_name" --source "$upstream_name" 2>/dev/null; then
      log "    ✓ Synced"; ((synced++)) || true
    else log "    ✗ Sync failed"; ((failed++)) || true; fi
  done
  log "=== Fork sync complete ==="
  log "Synced: $synced | Failed: $failed | Skipped: $skipped"
  RET_FORK_SYNC_GH="$synced"
}

# ===================== SECURITY AUDIT =====================
cmd_security_audit() {
  log "=== GitHub Fleet Security Audit ==="
  log "Checking dependabot, secret scanning and code scanning alerts"
  local alerts_found=0; local total_alerts=0
  local scan_all="${SECURITY_AUDIT_ALL_REPOS:-no}"
  local repos_to_scan
  if [ "$scan_all" = "yes" ]; then
    log "Scanning ALL repos (this may take a while...)"
    repos_to_scan=$(gh repo list "$(gh api user --jq .login 2>/dev/null || echo itsdarklikehell)" --limit 200 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true)
  else
    log "Scanning key repos (${#KEY_REPOS[@]} repos)"
    repos_to_scan="${KEY_REPOS[@]}"
  fi
  for kr in $repos_to_scan; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    # Gebruik HTTP-status-bewuste calls (endpoint kan 403/404 retourneren)
    local dep_status dep_body
    dep_status=$(gh api -i "repos/$kr/dependabot/alerts?state=open" 2>/dev/null | head -1 | grep -oP 'HTTP/\d+\.\d+ \K\d+' || echo "000")
    dep_body=$(gh api "repos/$kr/dependabot/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    dep_body=$(echo "$dep_body" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$dep_status" = "200" ] && [ "$dep_body" -gt 0 ] 2>/dev/null; then
      log "  🚨 Dependabot: $dep_body open alerts"; alerts_found=1; total_alerts=$((total_alerts + dep_body))
    fi
    local sec_status sec_body
    sec_status=$(gh api -i "repos/$kr/secret-scanning/alerts?state=open" 2>/dev/null | head -1 | grep -oP 'HTTP/\d+\.\d+ \K\d+' || echo "000")
    sec_body=$(gh api "repos/$kr/secret-scanning/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    sec_body=$(echo "$sec_body" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$sec_status" = "200" ] && [ "$sec_body" -gt 0 ] 2>/dev/null; then
      log "  🔑 Secret scanning: $sec_body open alerts"; alerts_found=1; total_alerts=$((total_alerts + sec_body))
    fi
    local code_status code_body
    code_status=$(gh api -i "repos/$kr/code-scanning/alerts?state=open" 2>/dev/null | head -1 | grep -oP 'HTTP/\d+\.\d+ \K\d+' || echo "000")
    code_body=$(gh api "repos/$kr/code-scanning/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    code_body=$(echo "$code_body" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$code_status" = "200" ] && [ "$code_body" -gt 0 ] 2>/dev/null; then
      log "  🛡 Code scanning: $code_body open alerts"; alerts_found=1; total_alerts=$((total_alerts + code_body))
    fi
  done
  log "=== Security audit complete ==="
  log "Repos with alerts: $alerts_found | Total alerts: $total_alerts"
  RET_SECURITY_AUDIT="$total_alerts"
}

# ===================== FLEET REPORT (all-in-one) =====================
# fleet_report config
FLEET_REPORT_ACCOUNTS=(itsdarklikehell hans)
FLEET_REPORT_INCLUDE_NON_KEY="yes"
cmd_fleet_report() {
  log "=== GitHub Fleet Report (Multi-Account) ==="
  log "Everything in one run: inventory, PRs, issues, CI, auto-pilot, audits — for all configured accounts"
  local accounts=" ${FLEET_REPORT_ACCOUNTS[@]:-(itsdarklikehell hans)} "
  local all_total_repos=0; local all_total_owned=0; all_total_forks=0
  local all_total_open_prs=0; local all_total_open_issues=0
  local all_total_stale_prs=0; local all_total_ci_failures=0
  local all_total_sec_alerts=0; local all_total_bp_missing=0
  local all_total_pages=0; local all_total_wiki=0; local all_total_disabled_wf=0
  local all_total_collaborators=0; local all_total_gource_ok=0; local all_total_gource_total=0
  local all_total_stale_issues=0; local all_total_mergeable=0; local all_total_rerun_needed=0
  local all_total_forks_to_sync=0; local all_total_stale_to_close=0
  local all_total_dep_graph_alerts=0
  local fleet_msg_accounts=""
  for account in $accounts; do
    [ -z "$account" ] && continue
    log "--- Processing account: $account ---"
    local GH_USER="$account"
    log "User: $GH_USER"
    local repos
    repos=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,visibility,updatedAt,isFork,defaultBranchRef,name,description,stargazerCount --jq '.[] | "\(.nameWithOwner)|\(.visibility)|\(.isFork)|\(.updatedAt[0:10])|\(.defaultBranchRef.name // "none")|\(.stargazerCount // 0)"' 2>/dev/null || true)
    local repo_count
    repo_count=$(echo "$repos" | grep -c . 2>/dev/null || true)
    [ -z "$repo_count" ] && repo_count=0
    log "  Found: $repo_count repos"
    # PR/ISSUE tellingen via API bulk-queries
    local pr_count=0; local issue_count=0; local mergeable=0
    local pr_search
    pr_search=$(gh search prs --state open --limit 100 --json number,repository,mergeable --jq ".[] | select(.repository.owner.login == \"$GH_USER\") | \"\(.number)|\(.repository.nameWithOwner)//\(.mergeable)\"" 2>/dev/null || true)
    if [ -n "$pr_search" ]; then
      while IFS='|' read -r _num _repo _mergeable; do
        [ -z "$_num" ] && continue
        pr_count=$((pr_count + 1))
        [ "$_mergeable" = "true" ] && mergeable=$((mergeable + 1))
      done <<< "$pr_search"
    fi
    local issue_search
    issue_search=$(gh search issues --state open --limit 100 --json number,repository --jq ".[] | select(.repository.owner.login == \"$GH_USER\") | .number" 2>/dev/null || true)
    if [ -n "$issue_search" ]; then
      issue_count=$(echo "$issue_search" | grep -c . | tr -d '[:space:]' || echo "0")
      issue_count=$(echo "${issue_count:-0}" | grep -oE '^[0-9]+$' || echo "0")
    fi
    log "  Open PRs: $pr_count (via bulk search)"
    log "  Open Issues: $issue_count (via bulk search)"
    log "  Mergeable PRs: $mergeable"
    # Stale PRs via bulk API (sneller dan per-repo loop)
    local stale_pr_count=0
    local stale_cutoff=$(date -d "${STALE_CLOSE_DAYS:-30} days ago" '+%Y-%m-%d' 2>/dev/null || echo "")
    if [ -n "$stale_cutoff" ] && [ -n "$repos" ]; then
      local stale_prs_json=$(gh search prs --state open --limit 100 --json number,repository,updatedAt --jq ".[] | select(.repository.owner.login == \"$GH_USER\" and .updatedAt < \"$stale_cutoff\") | .number" 2>/dev/null || true)
      if [ -n "$stale_prs_json" ]; then
        stale_pr_count=$(echo "$stale_prs_json" | grep -c . | tr -d '[:space:]' || echo "0")
        stale_pr_count=$(echo "${stale_pr_count:-0}" | grep -oE '^[0-9]+$' || echo "0")
      fi
    fi
    log "  Stale PRs: $stale_pr_count"
    # CI failures — alleen key repos
    local ci_failures=0
    local ci_cutoff_epoch=$(date -d '24 hours ago' '+%s' 2>/dev/null || echo "0")
    if [ "$ci_cutoff_epoch" != "0" ]; then
      for kr in "${KEY_REPOS[@]}"; do
        local org="${kr%%/*}"
        [ "$org" != "$GH_USER" ] && continue
        local failed_runs
        failed_runs=$(gh run list --repo "$kr" --limit 5 --json name,conclusion,updatedAt --jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")
        if [ "$failed_runs" -gt 0 ]; then ci_failures=$((ci_failures + 1)); log "  ⚠ $kr: $failed_runs failed run(s)"; fi
      done
    fi
    log "  CI failures: $ci_failures key repos"
    # Repo teller
    local owned=0; local forks=0; local top_starred=""; local top_stars=0
    if [ -n "$repos" ]; then
      while IFS='|' read -r nameWithOwner visibility isFork updated defaultBranch desc stars; do
        [ -z "$nameWithOwner" ] && continue
        if [[ "$isFork" != "true" && "$isFork" != "false" ]]; then continue; fi
        if [ "$isFork" = "false" ]; then owned=$((owned + 1))
        else forks=$((forks + 1)); fi
        if [ -n "$stars" ] && [ "$stars" -gt "$top_stars" ] 2>/dev/null; then
          top_stars=$stars; top_starred="$nameWithOwner"; fi
      done <<< "$repos"
    fi
    log "  Owned: $owned | Forks: $forks | Top: ${top_starred:-none} (★${top_stars:-0})"
    # Forks te synchroniseren (bulk)
    local forks_to_sync=0
    local fork_list=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,isFork,parent --jq '.[] | select(.isFork == true and .parent != null) | .nameWithOwner' 2>/dev/null || true)
    forks_to_sync=$(echo "$fork_list" | grep -c . 2>/dev/null || echo "0")
    forks_to_sync=$(echo ${forks_to_sync:-0} | tr -d '[:space:]')
    log "  Forks to sync: $forks_to_sync"
    # CI runs te herstarten (key repos only)
    local rerun_needed=0
    for kr in $AUTO_RERUN_REPOS; do
      local org="${kr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local runs=$(gh run list --repo "$kr" --json databaseId,name,conclusion,status --jq '.[] | select(.conclusion == "failure" and .status == "completed") | "\(.databaseId) \(.name)"' 2>/dev/null || true)
      local run_count=$(echo "$runs" | grep -c . 2>/dev/null || echo "0")
      run_count=$(echo "$run_count" | tr -d '[:space:]')
      [ -z "$run_count" ] && run_count=0
      if [ "$run_count" -gt 0 ] 2>/dev/null; then rerun_needed=$((rerun_needed + run_count)); log "  $kr: $run_count failed run(s) to rerun"; fi
    done
    log "  CI runs to rerun: $rerun_needed"
    # Audits — alleen key repos, gebundeld
    local sec_alerts=0
    for kr in "${KEY_REPOS[@]}"; do
      local org="${kr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local dep_a sec_a code_a
      dep_a=$(gh api "repos/$kr/dependabot/alerts?state=open" --jq '. | length' 2>/dev/null) || dep_a="0"
      dep_a=$(echo "$dep_a" | grep -oE '^[0-9]+$' || echo "0")
      sec_a=$(gh api "repos/$kr/secret-scanning/alerts?state=open" --jq '. | length' 2>/dev/null) || sec_a="0"
      sec_a=$(echo "$sec_a" | grep -oE '^[0-9]+$' || echo "0")
      code_a=$(gh api "repos/$kr/code-scanning/alerts?state=open" --jq '. | length' 2>/dev/null) || code_a="0"
      code_a=$(echo "$code_a" | grep -oE '^[0-9]+$' || echo "0")
      if [ "$dep_a" -gt 0 ] || [ "$sec_a" -gt 0 ] || [ "$code_a" -gt 0 ]; then
        sec_alerts=$((sec_alerts + dep_a + sec_a + code_a))
        log "  🚨 $kr: $dep_a dependabot + $sec_a secret + $code_a code scanning"
      fi
    done
    log "  Security alerts (key repos): $sec_alerts"
    # Branch protection (key repos only)
    local bp_missing=0
    for br in "${KEY_REPOS[@]}"; do
      local org="${br%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local protected
      protected=$(gh api "repos/$br/branches/main/protection" --jq '.required_status_checks | length' 2>/dev/null || echo "0")
      if [ "$protected" = "0" ] || [ -z "$protected" ]; then bp_missing=$((bp_missing + 1)); log "  ⚠️ $br: main NOT protected"; fi
    done
    log "  Branch protection missing: $bp_missing"
    # Pages, Wiki (key repos only)
    local pages_count=0
    for pr in "${KEY_REPOS[@]}"; do
      local org="${pr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local pages_info=$(gh api "repos/$pr/pages" --jq '{status: .status} | .status' 2>/dev/null || true)
      if [ -n "$pages_info" ] && [ "$pages_info" != "null" ]; then pages_count=$((pages_count + 1)); fi
    done
    log "  Pages enabled (key repos): $pages_count"
    local wiki_count=0
    for wr in "${KEY_REPOS[@]}"; do
      local org="${wr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local has_wiki=$(gh api "repos/$wr" --jq '.has_wiki' 2>/dev/null || echo "false")
      if [ "$has_wiki" = "true" ]; then wiki_count=$((wiki_count + 1)); fi
    done
    log "  Wiki enabled (key repos): $wiki_count"
    # Disabled workflows (key repos only)
    local disabled_wf=0
    for dwr in "${KEY_REPOS[@]}"; do
      local org="${dwr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local disabled=$(gh workflow list -R "$dwr" --json name,state --jq '.[] | select(.state == "disabled") | .name' 2>/dev/null | wc -l || echo "0")
      if [ "$disabled" -gt 0 ]; then disabled_wf=$((disabled_wf + disabled)); log "  ⚙ $dwr: $disabled disabled workflow(s)"; fi
    done
    log "  Disabled workflows (key repos): $disabled_wf"
    # Collaborators (key repos only) — gebundeld per repo
    local colab_count=0
    for ccr in "${KEY_REPOS[@]}"; do
      local org="${ccr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local colab_count_this=$(gh api "repos/$ccr/collaborators" --jq ".[] | select(.type == \"User\" and .login != \"$(echo "$ccr" | cut -d/ -f2)\") | .login" 2>/dev/null | grep -c . || echo "0")
      colab_count_this=$(echo "$colab_count_this" | tr -d '[:space:]')
      [ -z "$colab_count_this" ] && colab_count_this=0
      if [ "$colab_count_this" -gt 0 ] 2>/dev/null; then colab_count=$((colab_count + colab_count_this)); log "  👥 $ccr: $colab_count_this collaborator(s)"; fi
    done
    log "  Collaborators (key repos): $colab_count"
    # Stale issues (key repos only)
    local stale_issues_count=0
    for _kr in "${KEY_REPOS[@]}"; do
      local org="${_kr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local _si=$(gh issue list -R "$_kr" --state open --label "stale" --json number --jq 'length' 2>/dev/null || echo "0")
      _si=$(echo "$_si" | grep -oE '^[0-9]+$' || echo "0")
      stale_issues_count=$((stale_issues_count + _si))
    done
    log "  Stale issues (key repos): $stale_issues_count"
    # Gource coverage (local repos only)
    local gource_ok=0; local gource_total=0
    for _rd in "$REPOS_DIR"/*/; do
      [ -d "$_rd/.git" ] || continue
      local repo_org=$(get_repo_org "$_rd")
      if [ "$repo_org" != "$GH_USER" ]; then continue; fi
      gource_total=$((gource_total + 1))
      if [ -f "$_rd/.github/workflows/gource.yml" ]; then gource_ok=$((gource_ok + 1)); fi
    done
    log "  Gource coverage: $gource_ok / $gource_total repos"
    # Ranking (top 5)
    local ranking
    ranking=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,stargazerCount --jq '.[] | "\(.stargazerCount) \(.nameWithOwner)"' 2>/dev/null | sort -t' ' -k1 -rn | head -5 || true)
    log "  Top 5 stars:"
    echo "$ranking" | while IFS= read -r line; do [ -z "$line" ] && continue; log "    $line"; done
    # Features audit (key repos only)
    local feat_issues_off=0; local feat_pages_off=0
    for fr in "${KEY_REPOS[@]}"; do
      local org="${fr%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local features=$(gh api "repos/$fr" --jq '{issues: .has_issues, pages: .has_pages, wiki: .has_wiki, forking: .allow_forking}' 2>/dev/null || echo "{}")
      local issues_on=$(echo "$features" | jq -r '.issues // false' 2>/dev/null || echo "false")
      local pages_on=$(echo "$features" | jq -r '.pages // false' 2>/dev/null || echo "false")
      [ "$issues_on" = "false" ] && feat_issues_off=$((feat_issues_off + 1))
      [ "$pages_on" = "false" ] && feat_pages_off=$((feat_pages_off + 1))
    done
    log "  Features off: issues=$feat_issues_off, pages=$feat_pages_off"
    # Release info per account
    local release_list=""
    for _r in "${KEY_REPOS[@]}"; do
      local org="${_r%%/*}"
      [ "$org" != "$GH_USER" ] && continue
      local _rel=$(gh release list -R "$_r" --limit 1 --json tagName,createdAt --jq '.[0] | "  \(.tagName) \(.createdAt[0:10])"' 2>/dev/null || true)
      [ -n "$_rel" ] && release_list+="$_rel$'\\n'"
    done
    log "  Release info:"
    echo "$release_list" | while IFS= read -r _line; do [ -z "$_line" ] && continue; log "    $_line"; done
    # Aggregate totals
    all_total_repos=$((all_total_repos + repo_count))
    all_total_owned=$((all_total_owned + owned))
    all_total_forks=$((all_total_forks + forks))
    all_total_open_prs=$((all_total_open_prs + pr_count))
    all_total_open_issues=$((all_total_open_issues + issue_count))
    all_total_stale_prs=$((all_total_stale_prs + stale_pr_count))
    all_total_ci_failures=$((all_total_ci_failures + ci_failures))
    all_total_sec_alerts=$((all_total_sec_alerts + sec_alerts))
    all_total_bp_missing=$((all_total_bp_missing + bp_missing))
    all_total_pages=$((all_total_pages + pages_count))
    all_total_wiki=$((all_total_wiki + wiki_count))
    all_total_disabled_wf=$((all_total_disabled_wf + disabled_wf))
    all_total_collaborators=$((all_total_collaborators + colab_count))
    all_total_gource_ok=$((all_total_gource_ok + gource_ok))
    all_total_gource_total=$((all_total_gource_total + gource_total))
    all_total_stale_issues=$((all_total_stale_issues + stale_issues_count))
    all_total_mergeable=$((all_total_mergeable + mergeable))
    all_total_rerun_needed=$((all_total_rerun_needed + rerun_needed))
    all_total_forks_to_sync=$((all_total_forks_to_sync + forks_to_sync))
    all_total_stale_to_close=$((all_total_stale_to_close + stale_pr_count))  # simplistic
    all_total_dep_graph_alerts=$((all_total_dep_graph_alerts + 0))  # dep alerts zitten al in sec_alerts
    # Bouw account-bericht
    local account_msg="*${GH_USER}:*\\n"
    account_msg+="*Repos:* $repo_count (owned: $owned, forks: $forks)\\n"
    account_msg+="*Open PRs:* $pr_count | *Open Issues:* $issue_count\\n"
    account_msg+="*Stale PRs:* ${stale_pr_count:-0} | *Stale Issues:* ${stale_issues_count:-0}\\n"
    account_msg+="*Mergeable:* $mergeable | *CI-runs te herstarten:* $rerun_needed\\n"
    account_msg+="*Forks te sync:* $forks_to_sync | *Stale te sluiten:* ${stale_pr_count:-0}\\n"
    account_msg+="*Security alerts:* $sec_alerts | *BP missing:* $bp_missing\\n"
    account_msg+="*Pages:* $pages_count | *Wiki:* $wiki_count | *Disabled WF:* $disabled_wf\\n"
    account_msg+="*Collaborators:* $colab_count | *Dep alerts:* 0\\n"
    account_msg+="*Gource:* ${gource_ok:-0}/${gource_total:-0} | *Features off:* issues=$feat_issues_off, pages=$feat_pages_off\\n"
    account_msg+="*Top 5:* ${top_starred:-geen} (★${top_stars:-0})\\n\\n"
    fleet_msg_accounts+="$account_msg"
    # Set return values per account
    RET_FLEET_REPO_COUNT="$repo_count"
    RET_FLEET_OWNED="$owned"
    RET_FLEET_FORKS="$forks"
    RET_FLEET_OPEN_PRS="$pr_count"
    RET_FLEET_OPEN_ISSUES="$issue_count"
    RET_FLEET_STALE_PRS="${stale_pr_count:-0}"
    RET_FLEET_CI_FAILURES="$ci_failures"
    RET_FLEET_SEC_ALERTS="$sec_alerts"
    RET_FLEET_BP_MISSING="$bp_missing"
    RET_FLEET_FORKS_TO_SYNC="$forks_to_sync"
    RET_GOURCE_OK="$gource_ok"
    RET_GOURCE_TOTAL="$gource_total"
    RET_STALE_ISSUES="$stale_issues_count"
  done
  # Stuur het totale rapport naar Telegram
  local fleet_msg
  fleet_msg="🚢 *GitHub Fleet Dagelijks Rapport — Alle Accounts*\\n\\n"
  fleet_msg+="*Totaal:* $all_total_repos repos (owned: $all_total_owned, forks: $all_total_forks)\\n"
  fleet_msg+="*Open PRs:* $all_total_open_prs | *Open Issues:* $all_total_open_issues\\n"
  fleet_msg+="*Stale PRs:* $all_total_stale_prs | *Stale Issues:* $all_total_stale_issues\\n"
  fleet_msg+="*CI-failures (key repos):* $all_total_ci_failures\\n\\n"
  fleet_msg+="*Auto-pilot:*\\n"
  fleet_msg+="  Mergeable PRs: $all_total_mergeable\\n"
  fleet_msg+="  CI-runs te herstarten: $all_total_rerun_needed\\n"
  fleet_msg+="  Forks te sync: $all_total_forks_to_sync\\n"
  fleet_msg+="  Stale items te sluiten: $all_total_stale_to_close\\n\\n"
  fleet_msg+="*Audits (totaal):*\\n"
  fleet_msg+="  Security alerts: $all_total_sec_alerts\\n"
  fleet_msg+="  Branch protection missing: $all_total_bp_missing\\n"
  fleet_msg+="  Pages enabled: $all_total_pages\\n"
  fleet_msg+="  Wiki enabled: $all_total_wiki\\n"
  fleet_msg+="  Disabled workflows: $all_total_disabled_wf\\n"
  fleet_msg+="  Collaborators: $all_total_collaborators\\n"
  fleet_msg+="  Gource coverage: $all_total_gource_ok / $all_total_gource_total\\n\\n"
  fleet_msg+="$fleet_msg_accounts"
  fleet_msg+="📋 Volledig log: $LOG_FILE"
  send_telegram_message "$fleet_msg" || true
  RET_FLEET_REPORT="done"
  RET_FLEET_REPO_COUNT="$all_total_repos"
  RET_FLEET_OWNED="$all_total_owned"
  RET_FLEET_FORKS="$all_total_forks"
  RET_FLEET_OPEN_PRS="$all_total_open_prs"
  RET_FLEET_OPEN_ISSUES="$all_total_open_issues"
  RET_FLEET_STALE_PRS="$all_total_stale_prs"
  RET_FLEET_CI_FAILURES="$all_total_ci_failures"
  RET_FLEET_SEC_ALERTS="$all_total_sec_alerts"
  RET_FLEET_BP_MISSING="$all_total_bp_missing"
  RET_FLEET_FORKS_TO_SYNC="$all_total_forks_to_sync"
  RET_GOURCE_OK="$all_total_gource_ok"
  RET_GOURCE_TOTAL="$all_total_gource_total"
  RET_STALE_ISSUES="$all_total_stale_issues"
}
# ===================== STANDALONE COMMANDS =====================

cmd_prs_status() {
  log "=== GitHub Fleet PR Status ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,updatedAt --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)/\(.updatedAt[0:10])"' 2>/dev/null || true)
  local pr_total=0; local pr_approved=0; local pr_needs_review=0; local pr_other=0
  local repos_with_prs=0; local seen_repos=""
  if [ -n "$open_prs" ]; then
    while IFS='|' read -r number repo title updated; do
      [ -z "$number" ] && continue
      ((pr_total++)) || true
      if ! echo "$seen_repos" | grep -qF "$repo"; then
        repos_with_prs=$((repos_with_prs + 1))
        seen_repos="$seen_repos$repo\n"
        log "--- $repo: PR #$number — $title"
      fi
    done <<< "$open_prs"
  fi
  log "=== Summary ==="
  log "Open PRs: $pr_total | Repos with open PRs: $repos_with_prs"
  RET_PR_TOTAL_OPEN="$pr_total"
  RET_PR_REPOS_WITH_PRS="$repos_with_prs"
}

cmd_actions_status() {
  log "=== GitHub Fleet Actions Status ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true)
  local repos_with_runs=0; local total_runs=0; local success=0; local failed=0
  local cancelled=0; local queued=0; local other=0
  local cutoff_epoch
  cutoff_epoch=$(date -d '7 days ago' '+%s' 2>/dev/null || date -v-7d '+%s' 2>/dev/null || echo "0")
  [ "$cutoff_epoch" = "0" ] && cutoff_epoch=$(date -v-7d '+%s' 2>/dev/null || echo "0")
  if [ "$cutoff_epoch" != "0" ]; then
    for repo in $repos; do
      [ -z "$repo" ] && continue
      local runs
      runs=$(gh run list --repo "$repo" --limit 50 --json name,databaseId,status,conclusion,updatedAt --jq '
        [.[] | select(.updatedAt != null) | {
          status, conclusion,
          updated_epoch: (.updatedAt | fromdateiso8601?)
        } | select(.updated_epoch > '"$cutoff_epoch"')] | length
      ' 2>/dev/null || echo "0")
      local run_count
      run_count=$(echo "$runs" | grep -oE '^[0-9]+$' || echo "0")
      [ -z "$run_count" ] && run_count=0
      if [ "$run_count" -gt 0 ]; then
        repos_with_runs=$((repos_with_runs + 1))
        total_runs=$((total_runs + run_count))
        local status_breakdown
        status_breakdown=$(gh run list --repo "$repo" --limit 50 --json status,conclusion,updatedAt --jq '
          [.[] | select(.updatedAt != null) | {
            status, conclusion,
            updated_epoch: (.updatedAt | fromdateiso8601?)
          } | select(.updated_epoch > '"$cutoff_epoch"')] |
          map({
            s: .status,
            c: (.conclusion // "none")
          }) | group_by(.s) | .[] |
          "\(.[0].s):\(.[0].c):\(length)"
        ' 2>/dev/null || true)
        while IFS=':' read -r status conclusion count; do
          [ -z "$status" ] && continue
          case "$status" in
            success) success=$((success + count)) ;;
            failure) failed=$((failed + count)) ;;
            cancelled) cancelled=$((cancelled + count)) ;;
            queued) queued=$((queued + count)) ;;
            *) other=$((other + count)) ;;
          esac
        done <<< "$status_breakdown"
      fi
    done
  fi
  log "=== Summary ==="
  log "Repos with runs (7d): $repos_with_runs"
  log "Total runs (7d): $total_runs"
  log "Success: $success | Failed: $failed | Cancelled: $cancelled | Queued: $queued | Other: $other"
  RET_ACTIONS_REPOS_WITH_RUNS="$repos_with_runs"
  RET_ACTIONS_TOTAL="$total_runs"
  RET_ACTIONS_SUCCESS="$success"
  RET_ACTIONS_FAILED="$failed"
  RET_ACTIONS_CANCELLED="$cancelled"
  RET_ACTIONS_QUEUED="$queued"
  RET_ACTIONS_OTHER="$other"
}

cmd_ci_rerun() {
  log "=== GitHub Fleet CI Rerun ==="
  local started=0; local failed=0
  for repo in $AUTO_RERUN_REPOS; do
    [ -z "$repo" ] && continue
    log "--- $repo ---"
    local runs
    runs=$(gh run list --repo "$repo" --json databaseId,name,conclusion,status --jq '
      [.[] | select(.conclusion == "failure" and .status == "completed") | "\(.databaseId) \(.name)"] | .[]
    ' 2>/dev/null || true)
    if [ -n "$runs" ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local run_id
        run_id=$(echo "$line" | awk '{print $1}')
        [ -z "$run_id" ] && continue
        log "  Rerun #$run_id: $line"
        if gh run rerun --repo "$repo" "$run_id" --failed 2>/dev/null; then
          ((started++)) || true; log "    ✓ Started"
        else ((failed++)) || true; log "    ✗ Failed"; fi
      done <<< "$runs"
    else log "  No failed runs"; fi
  done
  log "=== CI Rerun complete ==="
  log "Started: $started | Failed: $failed"
  RET_CI_RERUN="$started"
  RET_CI_RERUN_FAILED="$failed"
}

cmd_auto_close() {
  log "=== GitHub Fleet Auto-Close ==="
  local closed=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local stale_cutoff
  stale_cutoff=$(date -d "${STALE_CLOSE_DAYS:-30} days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${STALE_CLOSE_DAYS:-30}d '+%Y-%m-%d' 2>/dev/null || echo "")
  if [ -z "$stale_cutoff" ]; then log "Cannot determine cutoff date"; return; fi
  local stale_prs
  stale_prs=$(gh search prs --state open --limit 100 --json number,title,repository,updatedAt --jq ".[] | select(.repository.owner.login == "itsdarklikehell") | select(.updatedAt < \"$stale_cutoff\") | \"\\(.number)|\\(.repository.nameWithOwner)//\(.title)|\\(.updatedAt[0:10])\"" 2>/dev/null || true)
  if [ -n "$stale_prs" ]; then
    while IFS='|' read -r num repo title; do
      [ -z "$num" ] && continue
      log "Closing PR #$num in $repo: $title"
      if gh pr close "$repo#$num" --comment "Automatically closed due to inactivity (>${STALE_CLOSE_DAYS:-30} days without activity)." 2>/dev/null; then
        ((closed++)) || true
      else log "  Failed"; fi
    done <<< "$stale_prs"
  fi
  local stale_issues
  stale_issues=$(gh search issues --state open --limit 100 --json number,title,repository,updatedAt --jq ".[] | select(.repository.owner.login == "itsdarklikehell") | select(.updatedAt < \"$stale_cutoff\") | \"\\(.number)|\\(.repository.nameWithOwner)//\(.title)|\\(.updatedAt[0:10])\"" 2>/dev/null || true)
  if [ -n "$stale_issues" ]; then
    while IFS='|' read -r num repo title; do
      [ -z "$num" ] && continue
      log "Closing Issue #$num in $repo: $title"
      if gh issue close "$repo#$num" --comment "Automatically closed due to inactivity (>${STALE_CLOSE_DAYS:-30} days without activity)." 2>/dev/null; then
        ((closed++)) || true
      else log "  Failed"; fi
    done <<< "$stale_issues"
  fi
  log "=== Auto-Close complete ==="
  log "Closed items: $closed"
  RET_AUTO_CLOSE="$closed"
}

cmd_prs_merge() {
  log "=== GitHub Fleet PR Auto-Merge ==="
  local merged=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  if [ "$AUTO_MERGE_ENABLED" != "yes" ]; then
    log "Auto-merge disabled (AUTO_MERGE_ENABLED != yes)"
    RET_PRS_MERGED=0; return
  fi
  local mergeable_prs
  mergeable_prs=$(gh pr list --search "state:open author:$GH_USER is:pr mergeable:true" --limit 100 --json number,headRepository,title,mergeable --jq '.[] | select(.mergeable == true) | "\(.number)|\(.headRepository.nameWithOwner)//\(.title)"' 2>/dev/null || true)
  if [ -n "$mergeable_prs" ]; then
    while IFS='|' read -r num repo title; do
      [ -z "$num" ] && continue
      log "Merging PR #$num in $repo: $title"
      if maybe_mutate gh pr merge "$repo#$num" --merge --delete-branch 2>/dev/null; then
        ((merged++)) || true; log "  ✓ Merged"
      else log "  ✗ Failed (or not mergeable)"; fi
    done <<< "$mergeable_prs"
  else log "No mergeable PRs found"; fi
  log "=== PR Merge complete ==="
  log "Merged: $merged"
  RET_PRS_MERGED="$merged"
}

cmd_issue_assign() {
  log "=== GitHub Fleet Issue Assign ==="
  local assigned=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local unassigned_issues
  unassigned_issues=$(gh search issues --state open --limit 100 --json number,title,repository --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | select(.assignees | length == 0) | "\(.number)|\(.repository.nameWithOwner)//\(.title)"' 2>/dev/null || true)
  if [ -n "$unassigned_issues" ]; then
    while IFS='|' read -r num repo title; do
      [ -z "$num" ] && continue
      log "Assigning Issue #$num in $repo: $title"
      if gh issue edit "$repo#$num" --assignee "$GH_USER" 2>/dev/null; then
        ((assigned++)) || true; log "  ✓ Assigned to $GH_USER"
      else log "  ✗ Failed"; fi
    done <<< "$unassigned_issues"
  else log "No unassigned issues found"; fi
  log "=== Issue Assign complete ==="
  log "Assignees set: $assigned"
  RET_ISSUE_ASSIGNED="$assigned"
}

cmd_topic_sync() {
  log "=== GitHub Fleet Topics Sync ==="
  declare -A category_topics
  category_topics["agent"]="agent,ai,cli,automation"
  category_topics["bot"]="bot,telegram,automation"
  category_topics["dashboard"]="dashboard,monitoring,status"
  category_topics["python"]="python,cli,tool"
  category_topics["node"]="nodejs,javascript,cli"
  category_topics["dnd"]="dnd,gaming,rpg,tabletop"
  category_topics["security"]="security,tool,cli"
  category_topics["tutorial"]="tutorial,guide,learning"
  local synced=0; local skipped=0
  for kr in "${KEY_REPOS[@]}"; do
    local repo_name
    repo_name=$(echo "$kr" | cut -d/ -f2)
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local category=""
    for cat_key in "${!category_topics[@]}"; do
      if echo "$repo_name" | grep -qi "$cat_key"; then category="$cat_key"; break; fi
    done
    if [ -z "$category" ]; then
      log "--- $kr: no category -> skip ---"
      skipped=$((skipped + 1)); continue; fi
    local target_topics="${category_topics[$category]}"
    local current_topics
    current_topics=$(gh repo view "$kr" --json repositoryTopics --jq '.repositoryTopics[].name | sort | join(",")' 2>/dev/null || echo "")
    local target_sorted
    target_sorted=$(echo "$target_topics" | tr "," "\n" | LC_ALL=C sort | paste -sd, -)
    if [ "$current_topics" = "$target_sorted" ]; then
      log "--- $kr: topics already current ---"; continue; fi
    log "--- $kr: syncing topics ---"
    log "  Current: $current_topics"
    log "  Target:  $target_sorted"
    local IFS_BAK=$IFS; IFS=","
    for t in $current_topics; do
      t=$(echo "$t" | xargs)
      [ -z "$t" ] && continue
      if ! echo "$target_topics" | grep -qiw "$t"; then
        log "  Removing: $t"; gh repo edit "$kr" --remove-topic "$t" 2>/dev/null || true
      fi
    done
    IFS=$IFS_BAK; IFS=","
    for t in $target_topics; do
      t=$(echo "$t" | xargs)
      [ -z "$t" ] && continue
      if ! echo "$current_topics" | grep -qiw "$t"; then
        log "  Adding: $t"; gh repo edit "$kr" --add-topic "$t" 2>/dev/null || true
      fi
    done
    IFS=$IFS_BAK
    synced=$((synced + 1))
  done
  log "=== Topics sync complete ==="
  log "Synced: $synced | Skipped: $skipped"
  RET_TOPIC_SYNCED="$synced"
  RET_TOPIC_SKIPPED="$skipped"
}

cmd_topic_cleanup() {
  log "=== GitHub Fleet Topics Cleanup ==="
  local cleaned=0
  for kr in "${KEY_REPOS[@]}"; do
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local current_topics
    current_topics=$(gh repo view "$kr" --json repositoryTopics --jq '.repositoryTopics[].name' 2>/dev/null || true)
    if [ -z "$current_topics" ]; then continue; fi
    local removed=0
    while IFS= read -r topic; do
      [ -z "$topic" ] && continue
      case "$topic" in
        obsolete|deprecated|old|legacy|tmp|test|scratch)
          log "--- $kr: removing $topic ---"
          gh repo edit "$kr" --remove-topic "$topic" 2>/dev/null && ((removed++)) || true ;;
      esac
    done <<< "$current_topics"
    [ "$removed" -gt 0 ] && ((cleaned++)) || true
  done
  log "=== Topics cleanup complete ==="
  log "Repos cleaned: $cleaned"
  RET_TOPIC_CLEANED="$cleaned"
}

cmd_release_asset_check() {
  log "=== GitHub Fleet Release Asset Check ==="
  log "Reporting the latest release per repo (tag, draft, prerelease status)"
  local asset_dirty=""
  for ar in $RELEASE_REPOS; do
    local latest_release
    latest_release=$(gh release list -R "$ar" --limit 1 --json tagName,isDraft,isPrerelease --jq '.[0] | "\(.tagName) draft=\(.isDraft) prerelease=\(.isPrerelease)"' 2>/dev/null || echo "none")
    if [ "$latest_release" != "none" ]; then
      asset_dirty+="  $ar: $latest_release\n"
    else asset_dirty+="  $ar: no releases\n"; fi
  done
  if [ -n "$asset_dirty" ]; then
    log "=== Release Status (key repos) ==="
    log "$asset_dirty"
  fi
  log "=== Release asset check complete ==="
}

cmd_actions_secrets_audit() {
  log "=== GitHub Fleet Actions Secrets Audit ==="
  local total_secrets=0; local repos_with_secrets=0
  for kr in "${KEY_REPOS[@]}"; do
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local secrets_raw
    secrets_raw=$(gh api "repos/$kr/actions/secrets" --jq '.secrets[] | "\(.name) (updated: \(.updated_at[0:10]))"' 2>/dev/null || true)
    if [ -n "$secrets_raw" ]; then
      local count
      count=$(echo "$secrets_raw" | grep -c '^[0-9]' 2>/dev/null || true)
      count=${count//$'\\n'/}
      [ -z "$count" ] && count=0
      log "--- $kr: $count secrets ---"
      while IFS= read -r sline; do [ -z "$sline" ] && continue; log "  🔑 $sline"; done <<< "$secrets_raw"
      total_secrets=$((total_secrets + count))
      repos_with_secrets=$((repos_with_secrets + 1))
    log "--- $kr: no secrets ---"; fi
  done
  log "=== Actions Secrets Audit complete ==="
  log "Repos with secrets: $repos_with_secrets | Total secrets: $total_secrets"
  RET_ACTIONS_SECRETS="$total_secrets"
  send_telegram_message "🔑 *GitHub Fleet Actions Secrets Audit*\\n\\nTotaal secrets: ${RET_ACTIONS_SECRETS:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

cmd_workflow_dispatch() {
  log "=== GitHub Fleet Workflow Dispatch ==="
  local target_repo="${2:-}"
  local workflow_id="${3:-}"
  local ref="${4:-main}"
  local inputs="${5:-}"
  if [ -z "$target_repo" ] || [ -z "$workflow_id" ]; then
    log "Usage: $0 workflow-dispatch <repo> <workflow_id_or_filename> [ref] [JSON_inputs]"
    log "Example: $0 workflow-dispatch itsdarklikehell/hermes-desktop gource.yml main"
    return 1
  fi
  local org
  org=$(echo "$target_repo" | cut -d/ -f1); set_repo_token "$org"
  if gh api "repos/$target_repo/actions/workflows/$workflow_id" --jq '.workflow_dispatch' 2>/dev/null | grep -q 'true'; then
    log "Dispatching to $target_repo / workflows/$workflow_id (ref: $ref)"
    local dispatch_json="{\"ref\":\"$ref\"}"
    if gh api "repos/$target_repo/actions/workflows/$workflow_id/dispatches" \
        --method POST \
        --input <(printf '%s' "$dispatch_json") 2>/dev/null; then
      log "✅ Workflow $workflow_id triggered successfully"
      RET_WORKFLOW_DISPATCH=1
    else
      log "❌ Workflow dispatch failed"
      RET_WORKFLOW_DISPATCH=0
    fi
  fi
  log "=== Workflow dispatch complete ==="
}

cmd_branch_protection_audit() {
  log "=== GitHub Fleet Branch Protection Audit ==="
  local bp_missing=0
  for br in "${KEY_REPOS[@]}"; do
    local protected
    protected=$(gh api "repos/$br/branches/main/protection" --jq '.required_status_checks | length' 2>/dev/null || echo "0")
    if [ "$protected" = "0" ] || [ -z "$protected" ]; then
      log "⚠️ $br: main branch NOT protected"
      bp_missing=$((bp_missing + 1))
    else log "✓ $br: main branch protected"; fi
  done
  log "=== Branch protection audit complete ==="
  log "Missing protection: $bp_missing / ${#KEY_REPOS[@]}"
}

cmd_branch_protection_fix() {
  log "=== GitHub Fleet Branch Protection Fix ==="
  local fixed=0
  for br in "${KEY_REPOS[@]}"; do
    local protected
    protected=$(gh api "repos/$br/branches/main/protection" --jq '.required_status_checks | length' 2>/dev/null || echo "0")
    if [ "$protected" != "0" ] && [ -n "$protected" ]; then
      log "✓ $br: already protected"; continue; fi
    log "Setting branch protection for $br/main..."
    log "  └── required_status_checks: concordant"
    log "  └── required_pull_request_reviews: 1 approval"
    log "  └── enforce_admins: true"
    if gh api "repos/$br/branches/main/protection" \
        --method PUT \
        -f "required_status_checks[contexts][]=test" \
        -f "required_status_checks[contexts][]=lint" \
        -F "required_status_checks[strict]=true" \
        -F "required_pull_request_reviews[dismiss_stale_reviews]=true" \
        -F "required_pull_request_reviews[required_approving_review_count]=1" \
        -F "enforce_admins=true" \
        2>/dev/null; then
      log "  ✅ Branch protection set for $br"
      fixed=$((fixed + 1))
    else log "  ❌ Failed for $br (maybe admin rights needed?)"; fi
  done
  log "=== Branch protection fix complete ==="
  log "Fixed: $fixed / ${#KEY_REPOS[@]}"
  RET_BRANCH_PROTECTION_FIXED="$fixed"
}

cmd_disabled_workflows_audit() {
  log "=== GitHub Fleet Disabled Workflows Audit ==="
  local dw_dirty=""; local dw_count=0
  for dwr in "${KEY_REPOS[@]}"; do
    local disabled
    disabled=$(gh workflow list -R "$dwr" --json name,state --jq '.[] | select(.state == "disabled") | "- \(.name)"' 2>/dev/null || echo "")
    if [ -n "$disabled" ]; then
      dw_dirty+="  $dwr:\n$disabled\n"
      dw_count=$((dw_count + 1))
    fi
  done
  if [ "$dw_count" -gt 0 ]; then
    log "=== Disabled Workflows ==="
    log "$dw_dirty"
  else log "✓ No disabled workflows in key repos"; fi
  log "=== Disabled workflows audit complete ==="
}

cmd_environments_audit() {
  log "=== GitHub Fleet Environments Audit ==="
  local env_total=0; local repos_with_envs=0
  for kr in "${KEY_REPOS[@]}"; do
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local envs_raw
    envs_raw=$(gh api "repos/$kr/environments" --jq '.environments[] | "\(.name) (URL: \(.url // "n/a"))"' 2>/dev/null || true)
    if [ -n "$envs_raw" ]; then
      local count
      count=$(echo "$envs_raw" | wc -l)
      log "--- $kr: $count environments ---"
      while IFS= read -r env_line; do [ -z "$env_line" ] && continue; log "  🌍 $env_line"; done <<< "$envs_raw"
      env_total=$((env_total + count))
      repos_with_envs=$((repos_with_envs + 1))
    else log "--- $kr: no environments ---"; fi
  done
  log "=== Environments audit complete ==="
  log "Repos with environments: $repos_with_envs | Total environments: $env_total"
  RET_ENVIRONMENTS="$env_total"
}

cmd_super_linter_status() {
  log "=== GitHub Fleet Super-Linter Status ==="
  for kr in "${KEY_REPOS[@]}"; do
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local workflows
    workflows=$(gh workflow list -R "$kr" --json name,state --jq '.[] | select(.name | test("lint|super|linter"; "i")) | "- \(.name) [\(.state)]"' 2>/dev/null || true)
    if [ -n "$workflows" ]; then
      log "--- $kr ---"; log "  $workflows"
    else log "--- $kr: no lint workflow found ---"; fi
  done
  log "=== Super-Linter status complete ==="
}

cmd_collaborator_audit() {
  log "=== GitHub Fleet Collaborator Audit ==="
  local colab_dirty=""; local colab_count=0
  for ccr in "${KEY_REPOS[@]}"; do
    local cc_login
    cc_login=$(echo "$ccr" | cut -d/ -f1)
    local collaborators
    collaborators=$(gh api "repos/$ccr/collaborators" --jq ".[] | select(.type == \"User\" and .login != \"$cc_login\") | \"- \(.login)\"" 2>/dev/null || echo "")
    if [ -n "$collaborators" ]; then
      colab_dirty+="  $ccr:\n$collaborators\n"
      colab_count=$((colab_count + $(echo "$collaborators" | wc -l)))
    fi
  done
  if [ "$colab_count" -gt 0 ]; then
    log "=== Collaborators (key repos) ==="
    log "$colab_dirty"
  else log "✓ No external collaborators in key repos"; fi
  log "=== Collaborator audit complete ==="
}

cmd_ranking() {
  log "=== GitHub Fleet Stargazer/Fork Ranking ==="
  local ranking_dirty=""; local ranking_text
  ranking_text=$(gh repo list "$(gh api user --jq .login 2>/dev/null || echo itsdarklikehell)" --limit 200 --json nameWithOwner,stargazerCount,forkCount --jq '
      .[] | "\(.stargazerCount)\t\(.forkCount)\t\(.nameWithOwner)"' 2>/dev/null | sort -t$'\t' -k1 -rn | head -10 || true)
  if [ -n "$ranking_text" ]; then
    while IFS=$'\t' read -r stars forks repo; do
      ranking_dirty+="  ⭐ $stars  PR:$forks  $repo\n"
    done <<< "$ranking_text"
    log "=== Top 10 Starrers / Forks (fleet) ==="
    log "$ranking_dirty"
  else log "No repos found for ranking"; fi
  log "=== Ranking complete ==="
}

cmd_repo_features_audit() {
  log "=== GitHub Fleet Repo Features Audit ==="
  local feat_dirty=""; local feat_issues_off=0; local feat_pages_off=0
  for fr in "${KEY_REPOS[@]}"; do
    local features
    features=$(gh api "repos/$fr" --jq '{issues: .has_issues, pages: .has_pages, wiki: .has_wiki, projects: .has_projects, forking: .allow_forking}' 2>/dev/null || echo "{}")
    local issues_on
    issues_on=$(echo "$features" | jq -r '.issues // false' 2>/dev/null || echo "false")
    local pages_on
    pages_on=$(echo "$features" | jq -r '.pages // false' 2>/dev/null || echo "false")
    local wiki_on
    wiki_on=$(echo "$features" | jq -r '.wiki // false' 2>/dev/null || echo "false")
    local forking_on
    forking_on=$(echo "$features" | jq -r '.forking // false' 2>/dev/null || echo "false")
    local flags=""
    [ "$issues_on" = "false" ] && flags+=" ISSUES_OFF" && feat_issues_off=$((feat_issues_off + 1))
    [ "$pages_on" = "false" ] && flags+=" PAGES_OFF" && feat_pages_off=$((feat_pages_off + 1))
    [ "$wiki_on" = "false" ] && flags+=" WIKI_OFF"
    [ "$forking_on" = "false" ] && flags+=" FORKING_OFF"
    if [ -n "$flags" ]; then
      feat_dirty+="  ⚠️ $fr:$flags\n"
    else feat_dirty+="  ✓ $fr\n"; fi
  done
  log "=== Repo Features (key repos) ==="
  log "$feat_dirty"
  if [ "$feat_issues_off" -gt 0 ]; then
    log ""
    log "ℹ️  $feat_issues_off key repo(s) have issues disabled — that is why the script reports 0 open issues"
  fi
  log "=== Repo features audit complete ==="
}

cmd_dependency_api_check() {
  log "=== GitHub Fleet Dependency API Check ==="
  log "Checking outdated dependencies via GitHub API for all repos (no local clones needed)"
  local user
  user=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$user" --limit 200 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_repos=0; local repos_with_deps=0; local outdated_found=0
  for repo in $repos; do
    [ -z "$repo" ] && continue
    total_repos=$((total_repos + 1))
    local dep_graph
    dep_graph=$(gh api "repos/$repo/dependency-graph/relationships" --jq '.data | length' 2>/dev/null || echo "0")
    if [ "$dep_graph" = "0" ] || [ -z "$dep_graph" ]; then continue; fi
    repos_with_deps=$((repos_with_deps + 1))
    local alerts
    alerts=$(gh api "repos/$repo/dependabot/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    alerts=$(echo "$alerts" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$alerts" -gt 0 ] 2>/dev/null; then
      outdated_found=$((outdated_found + 1))
      log "  ⚠️ $repo: $alerts open dependabot alert(s)"
    fi
  done
  log "=== Dependency API check complete ==="
  log "Scanned: $total_repos repos | With dependency graph: $repos_with_deps | With alerts: $outdated_found"
}

cmd_wiki_status() {
  log "=== GitHub Fleet Wiki Status ==="
  local wiki_count=0
  for wr in "${KEY_REPOS[@]}"; do
    local has_wiki
    has_wiki=$(gh api "repos/$wr" --jq '.has_wiki' 2>/dev/null || echo "false")
    if [ "$has_wiki" = "true" ]; then wiki_count=$((wiki_count + 1)); fi
  done
  log "=== Wiki Status ==="
  log "Key repos with wikis enabled: $wiki_count / ${#KEY_REPOS[@]}"
  log "=== Wiki status complete ==="
}

cmd_topics_audit() {
  log "=== GitHub Fleet Topics Audit ==="
  local topic_dirty=""
  for tr in "${KEY_REPOS[@]}"; do
    local topics
    topics=$(gh repo view "$tr" --json repositoryTopics --jq '[.repositoryTopics[].name] | join(", ")' 2>/dev/null || echo "")
    if [ -n "$topics" ]; then
      topic_dirty+="  $tr: $topics\n"
    else topic_dirty+="  $tr: no topics\n"; fi
  done
  log "=== Topics (key repos) ==="
  log "$topic_dirty"
  log "=== Topics audit complete ==="
}

cmd_pages_status() {
  log "=== GitHub Fleet Pages Status ==="
  local pages_dirty=""; local pages_count=0
  for pr in "${KEY_REPOS[@]}"; do
    local pages_info
    pages_info=$(gh api "repos/$pr/pages" --jq '{name: .name, status: .status} | "\(.name): \(.status)"' 2>/dev/null || true)
    if [ -z "$pages_info" ] || [ "$pages_info" = "null" ] || echo "$pages_info" | grep -q "Not Found"; then
      continue
    fi
    pages_dirty+="  $pages_info\n"
    pages_count=$((pages_count + 1))
  done
  if [ "$pages_count" -gt 0 ]; then
    log "=== GitHub Pages ==="
    log "$pages_dirty"
  else log "No GitHub Pages configured in key repos"; fi
  log "=== Pages status complete ==="
}

cmd_secrets_audit() {
  log "=== GitHub Fleet Secrets Audit ==="
  local secrets_found=0; local secret_total=0
  for sr in "${KEY_REPOS[@]}"; do
    local org
    org=$(echo "$sr" | cut -d/ -f1); set_repo_token "$org"
    local secrets_raw
    secrets_raw=$(gh api "repos/$sr/actions/secrets" --jq '.secrets[] | "\(.name) (\(.updated_at[0:10]))"' 2>/dev/null || true)
    if [ -n "$secrets_raw" ]; then
      local count
      count=$(echo "$secrets_raw" | grep -c '^[0-9]' 2>/dev/null || true)
      count=${count//$'\\n'/}
      [ -z "$count" ] && count=0
      log "--- $sr: $count secret(s)---"
      while IFS= read -r sline; do [ -z "$sline" ] && continue; log "  🔑 $sline"; ((secret_total++)) || true; done <<< "$secrets_raw"
      ((secrets_found++)) || true
    fi
  done
  log "=== Secrets audit complete ==="
  log "Repos with secrets: $secrets_found | Total secrets: $secret_total"
  RET_SECRETS_AUDIT="$secret_total"
}

cmd_sync_all() {
  log "=== Sync All Repos ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    sync_repo "$repo" || true
    echo ""
  done
  log "=== Sync complete ==="
}

# ===================== AUTO-ASSIGN PRs BY CODEOWNERS-STYLE RULES =====================
: "${PR_REVIEWERS_FILE:=$HOME/.hermes/cron/pr-reviewers.conf}"

cmd_auto_assign_prs() {
  log "=== Auto-Assign PRs by CODEOWNERS-style Rules ==="
  log "Reviewer mapping file: ${PR_REVIEWERS_FILE:-not set}"
  local assigned=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,assignees --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)/\(.assignees | length)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  while IFS='|' read -r number repo title headRef assignee_count; do
    [ -z "$number" ] && continue
    [ "$assignee_count" -gt 0 ] 2>/dev/null && continue
    log "--- PR #$number in $repo: $title (branch: $headRef) ---"
    local reviewers=""
    if [ -n "${PR_REVIEWERS_FILE:-}" ] && [ -f "$PR_REVIEWERS_FILE" ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" =~ ^# ]] && continue
        local pattern reviewer
        pattern=$(echo "$line" | cut -d: -f1 | xargs)
        reviewer=$(echo "$line" | cut -d: -f2 | xargs)
        [ -z "$pattern" ] || [ -z "$reviewer" ] && continue
        local headRef_lower
        headRef_lower=$(echo "$headRef" | tr '[:upper:]' '[:lower:]')
        if echo "$headRef_lower" | grep -qi "$pattern"; then
          reviewers="$reviewers $reviewer"
          log "  → $headRef matches '$pattern' → reviewer: $reviewer"
        fi
      done < "$PR_REVIEWERS_FILE"
    fi
    if [ -z "$reviewers" ]; then
      log "  → No matching reviewer rule for branch '$headRef'"
    else
      log "  → Assigning reviewers:$reviewers"
      if gh pr edit "$repo#$number" --add-reviewer "$reviewers" 2>/dev/null; then
        ((assigned++)) || true
      else log "    Failed to assign reviewers"; fi
    fi
  done <<< "$open_prs"
  log "=== Auto-assign PRs complete ==="
  log "PRs assigned reviewers: $assigned"
  RET_AUTO_ASSIGNED_PRs="$assigned"
  send_telegram_message "👥 *GitHub Fleet Auto-Assign PRs*\\n\\n*Reviewers assigned:* ${RET_AUTO_ASSIGNED_PRs:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== LABEL PRS BY CHANGED FILES =====================
cmd_label_prs_by_files() {
  log "=== Label PRs by Changed Files ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository --jq '.[] | select(.repository.owner.login == "itsdarklikehell" or .repository.owner.login == "hans") | "\(.number)|\(.repository.nameWithOwner)//\(.title)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  declare -A file_label_map
  file_label_map["src/frontend"]=frontend
  file_label_map["src/ui"]=frontend
  file_label_map["components/"]=frontend
  file_label_map["app/frontend"]=frontend
  file_label_map["src/backend"]=backend
  file_label_map["src/server"]=backend
  file_label_map["api/"]=backend
  file_label_map["internal/"]=backend
  file_label_map["src/models"]=backend
  file_label_map["docs/"]=documentation
  file_label_map["README*"]=documentation
  file_label_map["CONTRIBUTING*"]=documentation
  file_label_map["scripts/"]=automation
  file_label_map["*.sh"]=automation
  file_label_map["Makefile*"]=automation
  file_label_map["Dockerfile*"]=infrastructure
  file_label_map["docker/"]=infrastructure
  file_label_map["k8s/"]=infrastructure
  file_label_map["*_test.*"]=testing
  file_label_map["tests/"]=testing
  file_label_map["spec/"]=testing
  file_label_map["*.test.*"]=testing
  file_label_map["config/"]=config
  file_label_map["*.yml"]=config
  file_label_map["*.yaml"]=config
  file_label_map["*.json"]=config
  file_label_map["package.json"]=dependencies
  file_label_map["package-lock.json"]=dependencies
  file_label_map["yarn.lock"]=dependencies
  file_label_map["pnpm-lock.yaml"]=dependencies
  file_label_map["requirements*.txt"]=dependencies
  file_label_map["Pipfile*"]=dependencies
  file_label_map["go.mod"]=dependencies
  file_label_map["Cargo.toml"]=dependencies
  file_label_map["*.go"]=backend
  file_label_map["*.py"]=python
  file_label_map["*.js"]=frontend
  file_label_map["*.ts"]=frontend
  file_label_map["*.tsx"]=frontend
  file_label_map["*.css"]=frontend
  file_label_map["*.scss"]=frontend
  file_label_map["*.rs"]=rust
  file_label_map["*.toml"]=config
  local labeled=0
  while IFS='|' read -r number repo title headRef; do
    [ -z "$number" ] && continue
    log "--- PR #$number in $repo: $title ---"
    local added_labels=""
    local diff_files
    diff_files=$(gh pr view --repo "$repo" "$number" --json files --jq '.files[].path' 2>/dev/null || true)
    if [ -z "$diff_files" ]; then log "  No files in diff (or API error)"; continue; fi
    while IFS= read -r filepath; do
      [ -z "$filepath" ] && continue
      for file_pattern in "${!file_label_map[@]}"; do
        if echo "$filepath" | grep -qi "$file_pattern"; then
          local label="${file_label_map[$file_pattern]}"
          if ! echo "$added_labels" | grep -qF "$label"; then
            added_labels="$added_labels $label"
            log "  → $filepath → label: $label"
          fi
        fi
      done
    done <<< "$diff_files"
    if [ -n "$added_labels" ]; then
      log "  Adding labels:$added_labels"
      if gh pr edit "$repo#$number" --add-label "$added_labels" 2>/dev/null; then
        ((labeled++)) || true
      else log "    Failed to add labels"; fi
    else log "  No matching file labels"; fi
  done <<< "$open_prs"
  log "=== Label PRs by files complete ==="
  log "PRs labeled: $labeled"
  RET_PRS_LABELED_FILES="$labeled"
  send_telegram_message "🏷️ *GitHub Fleet Label PRs by Files*\\n\\n*PRs gelabeld:* ${RET_PRS_LABELED_FILES:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== CLOSE STALE DUPLICATE PRS/ISSUES =====================
cmd_close_stale_duplicates() {
  log "=== Close Stale Duplicate PRs/Issues ==="
  local closed=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local all_open_prs
  all_open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,commits --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)/\(.commits)"' 2>/dev/null || true)
  if [ -n "$all_open_prs" ]; then
    while IFS='|' read -r number repo title commit_count; do
      [ -z "$number" ] && continue
      [ "$commit_count" -le 1 ] 2>/dev/null && continue
      log "--- PR #$number in $repo: $title (commits: $commit_count) ---"
      local pr_sha
      pr_sha=$(gh pr view --repo "$repo" "$number" --json commits --jq '.commits[-1].oid' 2>/dev/null || echo "")
      if [ -z "$pr_sha" ]; then log "  Cannot get latest commit SHA"; continue; fi
      local is_merged_elsewhere
      is_merged_elsewhere=$(gh api search/commits -F q="sha:$pr_sha repo:${GH_USER}/" -F per_page=5 --paginate -q '.[].repository.nameWithOwner' 2>/dev/null | grep -v "^$repo$" | head -1 || true)
      if [ -n "$is_merged_elsewhere" ]; then
        log "  → Commit $pr_sha merged in $is_merged_elsewhere → closing duplicate PR #$number"
        if gh pr close "$repo#$number" --comment "This PR's commits are already merged in \`$is_merged_elsewhere\`. Closing as duplicate." 2>/dev/null; then
          ((closed++)) || true
        else log "    Failed to close"; fi
      else log "  → Commit not found merged elsewhere"; fi
    done <<< "$all_open_prs"
  fi
  local all_open_issues
  all_open_issues=$(gh search issues --state open --limit 100 --json number,title,repository,comments --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)//\(.comments | length)"' 2>/dev/null || true)
  if [ -n "$all_open_issues" ]; then
    while IFS='|' read -r number repo title comment_count; do
      [ -z "$number" ] && continue
      [ "$comment_count" -lt 2 ] 2>/dev/null && continue
      log "--- Issue #$number in $repo: $title ---"
      local issue_bodies
      issue_bodies=$(gh issue view --repo "$repo" "$number" --json body,comments --jq '(.body // "") + "\n" + (.comments[].body // "")' 2>/dev/null || true)
      if [ -z "$issue_bodies" ]; then continue; fi
      local linked_pr
      linked_pr=$(echo "$issue_bodies" | grep -oE "#[0-9]+" | head -1 || true)
      if [ -z "$linked_pr" ]; then continue; fi
      local pr_state
      pr_state=$(gh pr view "$repo#$linked_pr" --json state --jq '.state' 2>/dev/null || echo "unknown")
      if [ "$pr_state" = "merged" ] || [ "$pr_state" = "closed" ]; then
        log "  → Linked PR #$linked_pr is $pr_state → closing issue #$number"
        if gh issue close "$repo#$number" --comment "This issue is resolved by PR #$linked_pr ($pr_state). Closing." 2>/dev/null; then
          ((closed++)) || true
        else log "    Failed to close"; fi
      fi
    done <<< "$all_open_issues"
  fi
  log "=== Close stale duplicates complete ==="
  log "Items closed: $closed"
  RET_STALE_DUPLICATES_CLOSED="$closed"
  send_telegram_message "🧹 *GitHub Fleet Stale Duplicate Closer*\\n\\n*Gesloten:* ${RET_STALE_DUPLICATES_CLOSED:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== WEEKLY MERGED PR DIGEST =====================
cmd_merged_pr_digest() {
  log "=== Weekly Merged PR Digest ==="
  local digest_since
  digest_since=$(date -d "7 days ago" '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d' 2>/dev/null || echo "")
  [ -z "$digest_since" ] && { log "Cannot determine 7-day-ago date"; return; }
  log "Looking for PRs merged since $digest_since"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local merged_prs
  merged_prs=$(gh pr list --state merged --search "merged:>=$digest_since" --limit 100 --json number,headRepository,mergedAt,author,commits,additions,deletions --jq '.[] | "\(.number)|\(.headRepository.nameWithOwner)//\(.title)//\(.mergedAt)//\(.author.login)/\(.commits)/\(.additions)/\(.deletions)"' 2>/dev/null || true)
  if [ -z "$merged_prs" ]; then log "No PRs merged in the last 7 days"; return; fi
  local total=0; local total_additions=0; local total_deletions=0; local all_authors=""
  local digest_text=""
  while IFS='|' read -r number repo title mergedAt author commits additions deletions; do
    [ -z "$number" ] && continue
    ((total++)) || true
    total_additions=$((total_additions + additions))
    total_deletions=$((total_deletions + deletions))
    all_authors="${all_authors}${author},"
    local headRefName
    headRefName=$(gh pr view --repo "$repo" "$number" --json headRefName --jq '.headRefName' 2>/dev/null || echo "?")
    digest_text+="  *$repo* #$number: **$title**\\n"
    digest_text+="  🔀 branch: $headRefName\\n"
    digest_text+="  👤 @$author | ${commits} commits | +${additions}/-${deletions}\\n"
    digest_text+="  🕐 merged: $(echo "$mergedAt" | cut -dT -f1)\\n\\n"
    log "  $repo #$number: $title — @$author (${commits} commits, +${additions}/-${deletions})"
  done <<< "$merged_prs"
  local unique_authors
  unique_authors=$(echo "$all_authors" | tr ',' '\\n' | sort -u | grep -v '^$' | paste -sd ', ' - || true)
  local digest_msg="🚢 *Weekly Merged PR Digest ($total PRs)*\\n\\n"
  digest_msg+="📊 *Samenvatting:*\\n"
  digest_msg+="- Totale PRs: $total\\n"
  digest_msg+="- Toevoegingen: +${total_additions}\\n"
  digest_msg+="- Verwijderingen: -${total_deletions}\\n"
  digest_msg+="- Bijdragers: ${unique_authors:-none}\\n\\n"
  digest_msg+="📋 *Details:*\\n$digest_text"
  digest_msg+="📋 Volledig log: $LOG_FILE\\n"
  log "=== Merged PR digest complete ==="
  log "Total merged: $total | Additions: +${total_additions} | Deletions: -${total_deletions}"
  RET_MERGED_PRS_TOTAL="$total"
  RET_MERGED_ADDITIONS="$total_additions"
  RET_MERGED_DELETIONS="$total_deletions"
  send_telegram_message "$digest_msg" || true
}

# ===================== STAR/FORK TREND TRACKING =====================
: "${STAR_FORK_HISTORY_FILE:-$HOME/.hermes/cron/star-fork-history.tsv}"

cmd_star_fork_trends() {
  log "=== Star/Fork Trend Tracking ==="
  local history_file="${STAR_FORK_HISTORY_FILE:-$HOME/.hermes/cron/star-fork-history.tsv}"
  log "History file: $history_file"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local current_stats
  current_stats=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,stargazerCount,forkCount --jq '.[] | "\(.nameWithOwner)\\t\(.stargazerCount)\\t\(.forkCount)"' 2>/dev/null | sort || true)
  if [ -z "$current_stats" ]; then log "No repos found"; return; fi
  local total_stars=0; local total_forks=0; local repo_count=0
  while IFS=$'\t' read -r repo stars forks; do
    [ -z "$repo" ] && continue
    total_stars=$((total_stars + stars))
    total_forks=$((total_forks + forks))
    ((repo_count++)) || true
  done <<< "$current_stats"
  log "Current: $repo_count repos | ★${total_stars} | 🍴${total_forks}"
  mkdir -p "$(dirname "$history_file")" 2>/dev/null || true
  local today
  today=$(date '+%Y-%m-%d')
  if [ -f "$history_file" ]; then
    local prev_today
    prev_today=$(grep "^$today" "$history_file" 2>/dev/null || true)
    if [ -z "$prev_today" ]; then
      cp "$history_file" "${history_file}.bak" 2>/dev/null || true
      printf "%b" "${today}	${total_stars}	${total_forks}	${repo_count}" >> "$history_file"
      log "Saved today's stats to $history_file"
    else
      log "Today's stats already recorded: $prev_today"
    fi
  else
    printf "%b" "# date	total_stars	total_forks	repo_count" > "$history_file"
    printf "%b" "${today}	${total_stars}	${total_forks}	${repo_count}" >> "$history_file"
    log "Created $history_file with initial stats"
  fi
  if [ -f "$history_file" ] && [ -s "$history_file" ]; then
    local last_7_entries
    last_7_entries=$(tail -8 "$history_file" 2>/dev/null | grep -v "^#" || true)
    if [ -n "$last_7_entries" ]; then
      local prev_line
      prev_line=$(echo "$last_7_entries" | head -2 | tail -1)
      local prev_stars prev_forks
      prev_stars=$(echo "$prev_line" | cut -f2)
      prev_forks=$(echo "$prev_line" | cut -f3)
      if [ -n "$prev_stars" ] && [ "$prev_stars" != "total_stars" ] && [ "$prev_stars" != "#" ]; then
        local star_delta=$((total_stars - prev_stars))
        local fork_delta=$((total_forks - prev_forks))
        local star_dir="↑"
        [ "$star_delta" -lt 0 ] && star_dir="↓"
        local fork_dir="↑"
        [ "$fork_delta" -lt 0 ] && fork_dir="↓"
        log "Trend (7d ago vs now): ★${star_delta} ${star_dir} | 🍴${fork_delta} ${fork_dir}"
        send_telegram_message "📈 *Star/Fork Trends (7 dagen)*\\n\\n*Totaal:* ★${total_stars} (\(${star_delta} ${star_dir})) | 🍴${total_forks} (\(${fork_delta} ${fork_dir}))\\n*Totaal repos:* $repo_count\\n\\n📋 Volledig log: $LOG_FILE" || true
      fi
    fi
  fi
  RET_TREND_TOTAL_STARS="$total_stars"
  RET_TREND_TOTAL_FORKS="$total_forks"
  RET_TREND_REPO_COUNT="$repo_count"
  log "=== Star/fork trends complete ==="
}

# ===================== AUTO-CREATE ISSUES FROM TEMPLATES =====================
cmd_issue_create_from_template() {
  log "=== Auto-Create Issues from Templates ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local created=0
  local templates_file="${ISSUE_TEMPLATES_FILE:-$HOME/.hermes/cron/issue-templates.conf}"
  if [ ! -f "$templates_file" ]; then
    log "No templates file at $templates_file — skipping"
    log "Create one with format: repo|title|body"
    RET_ISSUE_CREATED=0; return
  fi
  while IFS='|' read -r target_repo title body; do
    [ -z "$target_repo" ] && continue
    [ -z "$title" ] && continue
    log "--- Checking $target_repo: '$title' ---"
    local existing
    existing=$(gh issue list --repo "$target_repo" --state open --json title --jq '.[] | select(.title == "'"$title"'") | .title' 2>/dev/null || true)
    if [ -n "$existing" ]; then
      log "  Already exists: $existing"
    else
      log "  Creating issue: $title"
      if gh issue create --repo "$target_repo" --title "$title" --body "$body" 2>/dev/null; then
        ((created++)) || true
        log "    Created"
      else
        log "    Failed"
      fi
    fi
  done < "$templates_file"
  log "=== Issue creation from templates complete ==="
  log "Issues created: $created"
  RET_ISSUE_CREATED="$created"
  send_telegram_message "📝 *GitHub Fleet — Issues Gecreëerd*\\n\\nTotaal aangemaakt: ${RET_ISSUE_CREATED:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== BRANCH NAMING CONVENTION CHECK =====================
cmd_branch_naming_check() {
  log "=== Branch Naming Convention Check ==="
  local violations=0
  local GOOD_PATTERN='^(feature|bugfix|fix|hotfix|release|patch|docs|chore|refactor|perf|test|security|spike|infra|ci|build)/[a-zA-Z0-9][a-zA-Z0-9_-]*$'
  local repos_to_check="${CLEAN_BRANCHES_REPOS:-$KEY_REPOS[@]}"
  for kr in $repos_to_check; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local branches
    branches=$(gh api "repos/$kr/branches" --jq '.[] | .name' 2>/dev/null || true)
    if [ -z "$branches" ]; then continue; fi
    while IFS= read -r bname; do
      [ -z "$bname" ] && continue
      if ! echo "$bname" | grep -qiE "$GOOD_PATTERN"; then
        log "  NAMING VIOLATION: '$bname' does not follow convention"
        violations=$((violations + 1))
      fi
    done <<< "$branches"
  done
  log "=== Branch naming check complete ==="
  log "Violations found: $violations"
  RET_BRANCH_NAMING_VIOLATIONS="$violations"
  send_telegram_message "🌿 *GitHub Fleet — Branch Naming Check*\\n\\n*Schendingen gevonden:* ${RET_BRANCH_NAMING_VIOLATIONS:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== AUTO-REQUEST REVIEWS (CODEOWNERS-based) =====================
cmd_review_request_auto() {
  log "=== Auto-Request Reviews (CODEOWNERS-based) ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local reviewers_file="${REVIEWERS_FILE:-$HOME/.hermes/cron/pr-reviewers.conf}"
  local requested=0
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,headRefName,assignees --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)//\(.headRefName)/\(.assignees | length)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  while IFS='|' read -r number repo title headRef assignee_count; do
    [ -z "$number" ] && continue
    [ "$assignee_count" -gt 0 ] 2>/dev/null && continue
    log "--- PR #$number in $repo: $title ---"
    local reviewers_to_request=""
    if [ -f "$reviewers_file" ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" =~ ^# ]] && continue
        local pattern reviewer
        pattern=$(echo "$line" | cut -d: -f1 | xargs)
        reviewer=$(echo "$line" | cut -d: -f2 | xargs)
        [ -z "$pattern" ] || [ -z "$reviewer" ] && continue
        local headRef_lower
        headRef_lower=$(echo "$headRef" | tr '[:upper:]' '[:lower:]')
        if echo "$headRef_lower" | grep -qi "$pattern"; then
          reviewers_to_request="$reviewers_to_request $reviewer"
          log "  → $headRef matches '$pattern' → request review: $reviewer"
        fi
      done < "$reviewers_file"
    fi
    if [ -n "$reviewers_to_request" ]; then
      log "  Requesting reviews:$reviewers_to_request"
      if gh pr edit "$repo#$number" --add-reviewer "$reviewers_to_request" 2>/dev/null; then
        ((requested++)) || true
      else log "    Failed"; fi
    else
      log "  → No matching reviewer rules"
    fi
  done <<< "$open_prs"
  log "=== Review request auto complete ==="
  log "Reviews requested: $requested"
  RET_REVIEW_REQUESTED="$requested"
  send_telegram_message "👥 *GitHub Fleet — Reviews Gereqested*\\n\\nAantal reviews aangevraagd: ${RET_REVIEW_REQUESTED:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== DEPENDABOT AUTO-ACTIONS =====================
cmd_dependabot_auto_actions() {
  log "=== Dependabot Auto-Actions ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local dismissed=0
  local alerts_created=0
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local alerts
    alerts=$(gh api "repos/$kr/dependabot/alerts?state=open&severity=low" --jq '.[] | "\(.number): \(.security_advisory.severity) - \(.security_advisory.summary)"' 2>/dev/null || true)
    if [ -z "$alerts" ]; then
      log "  No low-severity alerts"
    else
      log "  Low-severity alerts: $(echo "$alerts" | grep -c . 2>/dev/null || echo 0)"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local alert_num
        alert_num=$(echo "$line" | grep -oP '#\\K[0-9]+' || echo "")
        [ -z "$alert_num" ] && continue
        log "  Auto-dismissing #$alert_num (low severity)"
        if gh api "repos/$kr/dependabot/alerts/$alert_num" --method PUT -F state=dismissed -F dismissal_reason=not_relevant -F dismissal_comment="Auto-dismissed: low severity vulnerability by GitHub Fleet Manager." 2>/dev/null; then
          ((dismissed++)) || true
        else log "    Failed to dismiss #$alert_num"; fi
      done <<< "$alerts"
    fi
    local critical_alerts
    critical_alerts=$(gh api "repos/$kr/dependabot/alerts?state=open&severity=critical" --jq '.[] | "\(.number): \(.security_advisory.severity) - \(.security_advisory.summary) [\(.security_advisory.identifiers[0].alias)]"' 2>/dev/null || true)
    if [ -z "$critical_alerts" ]; then
      log "  No critical alerts"
    else
      log "  Critical alerts: $(echo "$critical_alerts" | grep -c . 2>/dev/null || echo 0)"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local alert_num
        alert_num=$(echo "$line" | grep -oP '#\\K[0-9]+' || echo "")
        [ -z "$alert_num" ] && continue
        local existing_issue
        existing_issue=$(gh issue list --repo "$kr" --state open --json title --jq '.[] | select(.title == "SECURITY: '"$(echo "$line" | sed 's/^[^:]*: //')"'") | .title' 2>/dev/null || true)
        if [ -n "$existing_issue" ]; then
          log "  Issue already exists for #$alert_num"
        else
          log "  Creating issue for critical alert #$alert_num"
          local title="SECURITY: ${line#*: }"
          local body="Security alert from Dependabot:\\n\\n$line\\n\\nAuto-created by GitHub Fleet Manager.\\n\\nSee https://github.com/${kr}/security for details."
          if gh issue create --repo "$kr" --title "$title" --body "$body" --label "security,bug,critical" 2>/dev/null; then
            ((alerts_created++)) || true
            log "    Created"
          else log "    Failed"
          fi
        fi
      done <<< "$critical_alerts"
    fi
    echo ""
  done
  log "=== Dependabot auto-actions complete ==="
  log "Dismissed (low): $dismissed | Issues created (critical): $alerts_created"
  RET_DEP_DISMISSED="$dismissed"
  RET_DEP_ISSUES_CREATED="$alerts_created"
  send_telegram_message "🔒 *GitHub Fleet — Dependabot Auto-Actions*\\n\\n*Dismissed (low):* ${RET_DEP_DISMISSED:-0}\\n*Gecreëerde issues (critical):* ${RET_DEP_ISSUES_CREATED:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== AUTO-MERGE WITH SQUASH OPTION =====================
cmd_prs_merge_squash() {
  log "=== PR Auto-Merge (Squash) ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  if [ "$AUTO_MERGE_ENABLED" != "yes" ]; then
    log "Auto-merge disabled"
    RET_PRS_MERGED_SQUASH=0; return
  fi
  local merged=0
  local mergeable_prs
  mergeable_prs=$(gh pr list --search "state:open author:${GH_USER} is:pr mergeable:true" --limit 100 --json number,headRepository,headRefName,title --jq '.[] | "\(.number)|\(.headRepository.nameWithOwner)//\(.title)//\(.headRefName)"' 2>/dev/null || true)
  if [ -z "$mergeable_prs" ]; then log "No mergeable PRs found"; return; fi
  while IFS='|' read -r number repo title headRef; do
    [ -z "$number" ] && continue
    local has_reviews
    has_reviews=$(gh pr view --repo "$repo" "$number" --json reviews --jq '.reviews | length' 2>/dev/null || echo "0")
    if [ "$has_reviews" -gt 0 ] 2>/dev/null; then
      log "  PR #$number has reviews — skipping auto-merge (review required)"
      continue
    fi
    log "  Merging PR #$number in $repo: $title (squash)"
    if maybe_mutate gh pr merge "$repo#$number" --squash --delete-branch 2>/dev/null; then
      ((merged++)) || true
      log "    ✓ Squash-merged"
    else
      log "    ✗ Failed — trying merge"
      if maybe_mutate gh pr merge "$repo#$number" --merge --delete-branch 2>/dev/null; then
        ((merged++)) || true
        log "    ✓ Merge-merged (fallback)"
      else
        log "    ✗ Failed entirely"
      fi
    fi
  done <<< "$mergeable_prs"
  log "=== PR merge (squash) complete ==="
  log "Squash-merged: $merged"
  RET_PRS_MERGED_SQUASH="$merged"
  send_telegram_message "🔀 *GitHub Fleet — PRs Gemsnoordeerd*\\n\\n*Gesnoord en gemerged:* ${RET_PRS_MERGED_SQUASH:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== AUTO-CREATE PRS FROM FEATURE BRANCHES =====================
cmd_pr_create_auto() {
  log "=== Auto-Create PRs from Feature Branches ==="
  local dry_run="${DRY_RUN:-}"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local created=0
  local repos_to_check="${KEY_REPOS[@]} ${CLEAN_BRANCHES_REPOS[@]}"
  for kr in $repos_to_check; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local default_branch
    default_branch=$(gh repo view --repo "$kr" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
    local branches
    branches=$(gh api "repos/$kr/branches" --jq '.[] | select(.name != "'"$default_branch"'") | .name' 2>/dev/null || true)
    if [ -z "$branches" ]; then continue; fi
    while IFS= read -r bname; do
      [ -z "$bname" ] && continue
      local has_pr
      has_pr=$(gh pr list --repo "$kr" --head "$bname" --state open --json number --jq '.[].number' 2>/dev/null || true)
      if [ -n "$has_pr" ]; then
        log "  Branch '$bname' already has open PR #$has_pr"
        continue
      fi
      local branch_type
      branch_type=$(echo "$bname" | grep -oE '^(feature|bugfix|fix|hotfix|release|patch|docs|chore|refactor|perf|test|security|spike|infra|ci|build)' || echo "feature")
      local pr_title="[$branch_type] $(echo "$bname" | sed 's/^[^/]*[/]//' | sed 's/^[^a-zA-Z]*//')"
      [ -z "$pr_title" ] || [ "$pr_title" = "[]" ] && pr_title="[$branch_type] update"
      if [ "$dry_run" = "1" ]; then
        log "    [DRY-RUN] Would create PR for branch '$bname'"
        ((created++)) || true
      else
        log "  Creating PR for branch '$bname' → '$pr_title'"
        if gh pr create --repo "$kr" --head "$bname" --base "$default_branch" --title "$pr_title" --body "Auto-created by GitHub Fleet Manager.\\n\\nBranch: $bname\\nType: $branch_type" 2>/dev/null; then
          ((created++)) || true
          log "    ✓ Created"
        else
          log "    ✗ Failed"
        fi
      fi
    done <<< "$branches"
    echo ""
  done
  log "=== Auto-create PRs complete ==="
  log "PRs created: $created"
  RET_AUTO_PRS_CREATED="$created"
  send_telegram_message "🔀 *GitHub Fleet — PRs Aangemaakt*\\n\\nAantal PRs aangemaakt: ${RET_AUTO_PRS_CREATED:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}


# ===================== CODEOWNERS AUDIT =====================
cmd_codeowners_audit() {
  log "=== CODEOWNERS Audit ==="
  [ "${CODEOWNERS_AUDIT_ENABLED:-yes}" != "yes" ] && { log "CODEOWNERS audit disabled"; return; }
  local missing=0
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local has_codeowners
    has_codeowners=$(gh api "repos/$kr/contents/.github/CODEOWNERS" --jq '.name' 2>/dev/null || echo "")
    if [ -z "$has_codeowners" ] || [ "$has_codeowners" = "null" ]; then
      log "  MISSING: $kr has no CODEOWNERS file"
      ((missing++)) || true
    else
      log "  OK: $kr has CODEOWNERS"
      local codeowners_content
      codeowners_content=$(gh api "repos/$kr/contents/.github/CODEOWNERS" --jq '.content' 2>/dev/null | python3 -c "import sys,base64; print(base64.b64decode(sys.stdin.read().strip()).decode())" 2>/dev/null || echo "")
      if [ -n "$codeowners_content" ]; then
        log "    Owners: $(echo "$codeowners_content" | head -3 | tr '\n' ' | ' | sed 's/ | $//')"
      fi
    fi
  done
  log "=== CODEOWNERS audit complete ==="
  log "Repos missing CODEOWNERS: $missing / ${#KEY_REPOS[@]}"
  RET_CODEOWNERS_MISSING="$missing"
  send_telegram_message "👥 *GitHub Fleet CODEOWNERS Audit*\n\n*Ontbrekend:* ${RET_CODEOWNERS_MISSING:-0} / ${#KEY_REPOS[@]}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== CONTRIBUTING / LICENSE AUDIT =====================
cmd_contrib_license_audit() {
  log "=== CONTRIBUTING / LICENSE Audit ==="
  [ "${CONTRIB_LICENSE_AUDIT_ENABLED:-yes}" != "yes" ] && { log "CONTRIB/LICENCE audit disabled"; return; }
  local audit_results=""
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local repo_name="${kr#*/}"
    local missing_files=""
    local found_files=""
    for cf in "${CONTRIB_FILES[@]}"; do
      local exists
      exists=$(gh api "repos/$kr/contents/$cf" --jq '.name' 2>/dev/null || echo "")
      if [ -n "$exists" ] && [ "$exists" != "null" ]; then
        found_files="$found_files $cf"
      else
        missing_files="$missing_files $cf"
      fi
    done
    if [ -n "$missing_files" ]; then
      log "  MISSING in $kr:$missing_files"
      audit_results+="  ⚠️ $kr:$missing_files\n"
    else
      log "  OK: $kr has all required files"
    fi
  done
  log "=== CONTRIB/LICENCE audit complete ==="
  if [ -n "$audit_results" ]; then
    log "Repos with missing files:"
    log "$audit_results"
  fi
  RET_CONTRIB_LIC_MISSING="$(echo "$audit_results" | grep -c "⚠️" 2>/dev/null || echo 0)"
  send_telegram_message "📋 *GitHub Fleet CONTRIB/LICENCE Audit*\n\n*Repos met ontbrekende bestanden:* ${RET_CONTRIB_LIC_MISSING:-0}\n$( [ -n "$audit_results" ] && echo "$audit_results" )\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== PR SIZE MONITORING =====================
cmd_pr_size_monitor() {
  log "=== PR Size Monitor ==="
  [ "${PR_SIZE_MONITOR_ENABLED:-yes}" != "yes" ] && { log "PR size monitor disabled"; return; }
  local large_prs=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local threshold="${PR_SIZE_THRESHOLD:-500}"
  log "Threshold: $threshold lines (additions + deletions)"
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,additions,deletions,files --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)//\(.additions)/\(.deletions)/\(.files)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  while IFS='|' read -r number repo title additions deletions files; do
    [ -z "$number" ] && continue
    local total=$((additions + deletions))
    if [ "$total" -gt "$threshold" ] 2>/dev/null; then
      log "  LARGE PR #$number in $repo: $title ($total lines, $files files)"
      ((large_prs++)) || true
    fi
  done <<< "$open_prs"
  log "=== PR size monitor complete ==="
  log "Large PRs (>$threshold lines): $large_prs"
  RET_PR_SIZE_LARGE="$large_prs"
  send_telegram_message "📏 *GitHub Fleet PR Size Monitor*\n\n*Large PRs (>$threshold regels):* ${RET_PR_SIZE_LARGE:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== PR SIZE LABELING =====================
cmd_label_prs_by_size() {
  log "=== PR Size Labeling ==="
  [ "${PR_SIZE_LABELING_ENABLED:-yes}" != "yes" ] && { log "PR size labeling disabled"; return; }
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local threshold_small=30; local threshold_medium=300
  log "Thresholds: small<=30, medium<=300, large>300"
  local prs_labeled=0
  local prs_json
  prs_json=$(gh search prs --state open --limit 100 --json number,repository,additions,deletions,isDraft --jq ".[] | select(.repository.owner.login == \"$GH_USER\" and .isDraft == false) | \"\(.number)|\(.repository.nameWithOwner)//\(.additions)/\(.deletions)\"" 2>/dev/null || true)
  if [ -z "$prs_json" ]; then log "No open PRs found"; return; fi
  while IFS='|' read -r number repo additions deletions; do
    [ -z "$number" ] && continue
    local total=$((additions + deletions))
    local label_to_add=""
    if [ "$total" -le "$threshold_small" ]; then label_to_add="size/small"
    elif [ "$total" -le "$threshold_medium" ]; then label_to_add="size/medium"
    else label_to_add="size/large"; fi
    local existing_labels
    existing_labels=$(gh pr view "$repo#$number" --json labels --jq '.labels[].name' 2>/dev/null || true)
    if echo "$existing_labels" | grep -qw "$label_to_add"; then
      log "  #$number in $repo: already has $label_to_add ($total lines)"
      continue
    fi
    gh pr edit "$repo#$number" --add-label "$label_to_add" 2>/dev/null && {
      log "  OK #$number in $repo: labeled $label_to_add ($total lines)"
      ((prs_labeled++)) || true
    } || log "  FAIL #$number in $repo: failed to label"
  done <<< "$prs_json"
  log "=== PR size labeling complete ==="
  log "PRs gelabeld: $prs_labeled"
  RET_LABELED_BY_SIZE="$prs_labeled"
  [ "$prs_labeled" -gt 0 ] && send_telegram_message "PR Labels (Size): $prs_labeled labeled" || true
}

# ===================== COMMIT ACTIVITY TRACKING =====================
cmd_commit_activity() {
  log "=== Commit Activity Tracking ==="
  [ "${COMMIT_ACTIVITY_ENABLED:-yes}" != "yes" ] && { log "Commit activity disabled"; return; }
  local days="${COMMIT_ACTIVITY_DAYS:-30}"
  local cutoff
  cutoff=$(date -d "$days days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -v-${days}d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")
  [ -z "$cutoff" ] && { log "Cannot determine cutoff"; return; }
  log "Analyzing commits since $cutoff ($days days)"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_commits=0
  local repos_with_activity=0
  local repos_without_activity=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local commits
    commits=$(gh api "repos/$repo/commits?per_page=100" --jq ".[] | select(.commit.author.date > \"$cutoff\") | .sha" 2>/dev/null | wc -l || echo "0")
    commits=$(echo "$commits" | tr -d '[:space:]')
    [ -z "$commits" ] && commits=0
    total_commits=$((total_commits + commits))
    if [ "$commits" -gt 0 ] 2>/dev/null; then
      ((repos_with_activity++)) || true
      log "  $repo: $commits commits"
    else
      ((repos_without_activity++)) || true
      log "  ⚠️ $repo: NO commits in $days days"
    fi
  done <<< "$repos"
  log "=== Commit activity complete ==="
  log "Total commits ($days days): $total_commits"
  log "Repos with activity: $repos_with_activity | Without activity: $repos_without_activity"
  RET_COMMIT_TOTAL="$total_commits"
  RET_COMMIT_ACTIVE_REPOS="$repos_with_activity"
  RET_COMMIT_INACTIVE_REPOS="$repos_without_activity"
  send_telegram_message "📊 *GitHub Fleet Commit Activity ($days dagen)*\\n\\n*Totaal commits:* ${RET_COMMIT_TOTAL:-0}\\n*Repos met activity:* ${RET_COMMIT_ACTIVE_REPOS:-0}\\n*Repos zonder activity:* ${RET_COMMIT_INACTIVE_REPOS:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== ENHANCED RELEASE NOTES =====================
cmd_release_notes_enhanced() {
  log "=== Enhanced Release Notes ==="
  local dry_run="${DRY_RUN:-}"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local last_tag
    last_tag=$(gh tag list --repo "$kr" --limit 1 --json name --jq '.[0].name' 2>/dev/null || echo "")
    if [ -z "$last_tag" ]; then
      log "  No tags found — using all commits"
      local commits
      commits=$(gh api "repos/$kr/commits?per_page=100" --jq '.[] | "\(.sha[0:7])|\(.commit.author.date[0:10])|\(.commit.message | split(\"\\n\")[0])"' 2>/dev/null || true)
    else
      log "  Last tag: $last_tag"
      local commits
      commits=$(gh api "repos/$kr/commits?sha=$last_tag&per_page=100" --jq '.[] | "\(.sha[0:7])|\(.commit.author.date[0:10])|\(.commit.message | split(\"\\n\")[0])"' 2>/dev/null || true)
    fi
    if [ -z "$commits" ]; then log "  No commits found"; continue; fi
    local features=$(echo "$commits" | grep -E 'feat:|feature:|add:' || true)
    local fixes=$(echo "$commits" | grep -E 'fix:|bugfix:|resolve:|patch:' || true)
    local docs=$(echo "$commits" | grep -E 'docs:|documentation:|readme:|changelog:' || true)
    local chore=$(echo "$commits" | grep -E 'chore:|ci:|refactor:|style:|build:|test:' || true)
    local perf=$(echo "$commits" | grep -E 'perf:|performance:' || true)
    local security=$(echo "$commits" | grep -E 'security:|sec:|vuln:' || true)
    local notes=""
    [ -n "$features" ] && notes+="## 🚀 Features\\n\\n$(echo "$features" | sed 's/^/ - /' | head -30)\\n\\n"
    [ -n "$fixes" ] && notes+="## 🐛 Fixes\\n\\n$(echo "$fixes" | sed 's/^/ - /' | head -30)\\n\\n"
    [ -n "$perf" ] && notes+="## ⚡ Performance\\n\\n$(echo "$perf" | sed 's/^/ - /' | head -15)\\n\\n"
    [ -n "$security" ] && notes+="## 🔒 Security\\n\\n$(echo "$security" | sed 's/^/ - /' | head -15)\\n\\n"
    [ -n "$docs" ] && notes+="## 📄 Documentation\\n\\n$(echo "$docs" | sed 's/^/ - /' | head -20)\\n\\n"
    [ -n "$chore" ] && notes+="## 🛠 Maintenance\\n\\n$(echo "$chore" | sed 's/^/ - /' | head -20)\\n\\n"
    local commit_count=$(echo "$commits" | grep -c '|' 2>/dev/null || echo "0")
    if [ -n "$notes" ]; then
      log "  Generated enhanced release notes: $commit_count commits, $(echo "$notes" | wc -l | tr -d ' ') lines"
      if [ "$dry_run" = "1" ]; then
        log "  [DRY-RUN] Would create enhanced release notes for $kr"
      else
        local draft_tag="enhanced-notes-$(date '+%Y%m%d')"
        if gh release create "$draft_tag" --draft --title "Release Notes: $(date '+%Y-%m-%d') — $kr" --notes "$notes" --repo "$kr" 2>/dev/null; then
          log "  ✓ Draft release created: $draft_tag"
        else log "  ✗ Failed to create draft"; fi
      fi
    else log "  No categorized commits found"; fi
    echo ""
  done
  log "=== Enhanced release notes complete ==="
  send_telegram_message "📝 *GitHub Fleet Enhanced Release Notes*\n\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
}


# ===================== PR REVIEW TIME MONITORING =====================
cmd_pr_review_time() {
  log "=== PR Review Time Monitoring ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,createdAt,updatedAt,reviews --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)/\(.createdAt)/\(.updatedAt)/\(.reviews | length)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  local slow_prs=0
  local now_epoch
  now_epoch=$(date '+%s')
  while IFS='|' read -r number repo title created updated review_count; do
    [ -z "$number" ] && continue
    local created_epoch
    created_epoch=$(date -d "$created" '+%s' 2>/dev/null || echo "0")
    [ "$created_epoch" = "0" ] && continue
    local age_hours=$(( (now_epoch - created_epoch) / 3600 ))
    if [ "$age_hours" -gt 48 ] && [ "$review_count" -eq 0 ]; then
      log "  STALE REVIEW: #$number in $repo: $title (open $age_hours uur, geen review)"
      ((slow_prs++)) || true
    fi
  done <<< "$open_prs"
  log "=== PR review time complete ==="
  log "PRs waiting >48u without review: $slow_prs"
  RET_PR_STALE_REVIEW="$slow_prs"
  send_telegram_message "⏱ *GitHub Fleet PR Review Time*\n\n*PRs >48u zonder review:* ${RET_PR_STALE_REVIEW:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== REPO DESCRIPTION AUDIT =====================
cmd_repo_description_audit() {
  log "=== Repo Description Audit ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,description --jq '.[] | "\(.nameWithOwner)|\(.description)"' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local missing_desc=0
  while IFS='|' read -r repo desc; do
    [ -z "$repo" ] && continue
    if [ -z "$desc" ] || [ "$desc" = "null" ] || [ "$desc" = "None" ]; then
      log "  MISSING DESCRIPTION: $repo"
      ((missing_desc++)) || true
    fi
  done <<< "$repos"
  log "=== Repo description audit complete ==="
  log "Repos without description: $missing_desc / $(echo "$repos" | wc -l | tr -d ' ')"
  RET_DESC_MISSING="$missing_desc"
  send_telegram_message "📝 *GitHub Fleet Repo Beschrijvingen*\n\n*Repos zonder beschrijving:* ${RET_DESC_MISSING:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== DEPLOY KEY AUDIT =====================
cmd_deploy_key_audit() {
  log "=== Deploy Key Audit ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_keys=0
  local repos_with_keys=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local keys
    keys=$(gh api "repos/$repo/keys" --jq '.[] | "\(.id) \(.key[-25:]... ) \(.created_at[0:10]) \(.read_only // true)"' 2>/dev/null || true)
    if [ -n "$keys" ]; then
      local count
      count=$(echo "$keys" | grep -c '^[0-9]' || echo "0")
      ((total_keys += count)) || true
      ((repos_with_keys++)) || true
      log "  🔑 $repo: $count deploy key(s)"
      echo "$keys" | while IFS= read -r keyline; do
        [ -z "$keyline" ] && continue
        log "    $keyline"
      done
    fi
  done <<< "$repos"
  log "=== Deploy key audit complete ==="
  log "Total deploy keys: $total_keys | Repos with deploy keys: $repos_with_keys"
  RET_DEPLOY_KEYS_TOTAL="$total_keys"
  RET_DEPLOY_KEYS_REPOS="$repos_with_keys"
  send_telegram_message "🔑 *GitHub Fleet Deploy Keys*\n\n*Totaal deploy keys:* ${RET_DEPLOY_KEYS_TOTAL:-0}\\n*Repos met deploy keys:* ${RET_DEPLOY_KEYS_REPOS:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== SCHEDULED WORKFLOW HEALTH =====================
cmd_scheduled_workflow_monitor() {
  log "=== Scheduled Workflow Monitor ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local missing_scheduled=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local workflows
    workflows=$(gh workflow list --repo "$repo" --json name,state,schedule --jq '.[] | select(.schedule != null) | "\(.name) [\(.state)] \(.schedule)"' 2>/dev/null || true)
    if [ -z "$workflows" ]; then
      log "  ⚠️ $repo: No scheduled workflows found"
      ((missing_scheduled++)) || true
    else
      log "  $repo: $(echo "$workflows" | wc -l | tr -d ' ') scheduled workflow(s)"
      echo "$workflows" | while IFS= read -r wfline; do
        [ -z "$wfline" ] && continue
        log "    $wfline"
      done
    fi
  done <<< "$repos"
  log "=== Scheduled workflow monitor complete ==="
  log "Repos without scheduled workflows: $missing_scheduled"
  RET_SCHEDULED_MISSING="$missing_scheduled"
  send_telegram_message "⏰ *GitHub Fleet Scheduled Workflows*\n\n*Repos zonder scheduled workflows:* ${RET_SCHEDULED_MISSING:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}


# ===================== TAG-SUGGESTIE / RELEASE CANDIDATE WORKFLOW =====================
cmd_tag_suggest() {
  log "=== Tag Suggestie / Release Candidate Workflow ==="
  local dry_run="${DRY_RUN:-}"
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local last_tag
    last_tag=$(gh tag list --repo "$kr" --limit 1 --json name --jq '.[0].name' 2>/dev/null || echo "")
    if [ -z "$last_tag" ]; then
      log "  No tags found — skipping"
      continue
    fi
    local commits_since
    commits_since=$(gh api "repos/$kr/commits?sha=$last_tag&per_page=100" --jq '.[] | "\(.sha[0:7])|\(.commit.message | split(\"\\n\")[0])"' 2>/dev/null || true)
    if [ -z "$commits_since" ]; then
      log "  No commits since $last_tag"
      continue
    fi
    local commit_count
    commit_count=$(echo "$commits_since" | grep -c '|' 2>/dev/null || echo "0")
    [ -z "$commit_count" ] && commit_count=0
    if [ "$commit_count" -eq 0 ]; then
      log "  No commits since $last_tag — no RC needed"
      continue
    fi
    local features=$(echo "$commits_since" | grep -E 'feat:|feature:|add:' || true)
    local fixes=$(echo "$commits_since" | grep -E 'fix:|bugfix:|patch:' || true)
    local breaking=$(echo "$commits_since" | grep -E 'break:|breaking|!' || true)
    log "  $commit_count commits since $last_tag"
    [ -n "$features" ] && log "    Features: $(echo "$features" | wc -l | tr -d ' ') commits"
    [ -n "$fixes" ] && log "    Fixes: $(echo "$fixes" | wc -l | tr -d ' ') commits"
    [ -n "$breaking" ] && log "    ⚠️ BREAKING: $(echo "$breaking" | wc -l | tr -d ' ') commits"
    if [ "$dry_run" = "1" ]; then
      log "  [DRY-RUN] Would create RC draft with $commit_count commits"
    else
      local rc_tag="rc-$(date '+%Y%m%d')-$(echo "$last_tag" | sed 's/v//')"
      local rc_body="## Release Candidate: $rc_tag
This RC covers $commit_count commits since $last_tag.

$( [ -n "$features" ] && echo "### Features\n$(echo "$features" | sed 's/^/ - /')\\n" )
$( [ -n "$fixes" ] && echo "### Fixes\n$(echo "$fixes" | sed 's/^/ - /')\\n" )
$( [ -n "$breaking" ] && echo "### ⚠️ Breaking Changes\n$(echo "$breaking" | sed 's/^/ - /')\\n" )
---
Auto-generated release candidate by GitHub Fleet Manager.
"
      if gh release create "$rc_tag" --draft --title "Release Candidate: $rc_tag" --notes "$rc_body" --repo "$kr" 2>/dev/null; then
        log "  ✓ RC draft created: $rc_tag"
      else log "  ✗ Failed to create RC draft"; fi
    fi
    echo ""
  done
  log "=== Tag suggestie complete ==="
  send_telegram_message "🏷️ *GitHub Fleet Tag Suggestie*\n\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== BRANCH RENAMING BIJ NAMING VIOLATIONS =====================
cmd_branch_rename() {
  log "=== Branch Renaming bij Naming Violations ==="
  local dry_run="${DRY_RUN:-}"
  local renamed=0
  local GOOD_PATTERN='^(feature|bugfix|fix|hotfix|release|patch|docs|chore|refactor|perf|test|security|spike|infra|ci|build)/[a-zA-Z0-9][a-zA-Z0-9_-]*$'
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local branches
    branches=$(gh api "repos/$kr/branches" --jq '.[] | "\(.name)|\(.protected // false)"' 2>/dev/null || true)
    if [ -z "$branches" ]; then continue; fi
    while IFS='|' read -r bname protected; do
      [ -z "$bname" ] && continue
      [ "$protected" = "true" ] && { log "  Protected branch $bname — skip rename"; continue; }
      if echo "$bname" | grep -qiE "$GOOD_PATTERN"; then continue; fi
      log "  NAMING VIOLATION: $bname"
      local branch_type
      branch_type=$(echo "$bname" | grep -oE '^(feat|fix|docs|chore|refactor|test|build|ci|security|perf|style|spike|hotfix|bugfix|release|patch)' || echo "feature")
      local new_name="${branch_type}/$(echo "$bname" | sed 's/^[a-zA-Z0-9_-]*[\/_-]//' | sed 's/^[^a-zA-Z0-9]//')"
      [ -z "$new_name" ] && new_name="feature/renamed-$(date '+%Y%m%d%H%M%S')"
      log "    → Proposed new name: $new_name"
      if [ "$dry_run" = "1" ]; then
        log "    [DRY-RUN] Would rename $bname → $new_name"
        ((renamed++)) || true
      else
        if gh api "repos/$kr/git/refs/heads/$bname" --method DELETE 2>/dev/null && \
           gh api "repos/$kr/git/refs" --method POST -f "ref=refs/heads/$new_name" -f "sha=$(gh api "repos/$kr/git/refs/heads/$bname" --jq '.object.sha' 2>/dev/null)" 2>/dev/null; then
          log "    ✓ Renamed $bname → $new_name"
          ((renamed++)) || true
        else log "    ✗ Failed to rename $bname"; fi
      fi
    done <<< "$branches"
    echo ""
  done
  log "=== Branch renaming complete ==="
  log "Branches renamed: $renamed"
  RET_BRANCH_RENAMED="$renamed"
  send_telegram_message "🌿 *GitHub Fleet Branch Renaming*\n\n*Branches hernoemd:* ${RET_BRANCH_RENAMED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== REPOSITORY ARCHIVEREN BIJ INACTIVITEIT =====================
cmd_repo_archive_inactive() {
  log "=== Repository Archiveren bij Inactiviteit ==="
  local dry_run="${DRY_RUN:-}"
  local days="${ARCHIVE_INACTIVE_DAYS:-180}"
  local cutoff
  cutoff=$(date -d "$days days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${days}d '+%Y-%m-%d' 2>/dev/null || echo "")
  [ -z "$cutoff" ] && { log "Cannot determine cutoff"; return; }
  log "Archiveren drempel: repos met geen pushes sinds $cutoff ($days dagen)"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,updatedAt,isArchived --jq '.[] | select(.isArchived == false) | "\(.nameWithOwner)|\(.updatedAt[0:10])"' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No active repos found"; return; fi
  local to_archive=0
  while IFS='|' read -r repo updated; do
    [ -z "$repo" ] && continue
    if [[ "$updated" < "$cutoff" ]]; then
      log "  INACTIVE: $repo (last update: $updated)"
      ((to_archive++)) || true
      if [ "$dry_run" = "1" ]; then
        log "    [DRY-RUN] Would archive $repo"
      else
        if gh repo archive "$repo" 2>/dev/null; then
          log "    ✓ Archived $repo"
        else log "    ✗ Failed to archive $repo"; fi
      fi
    fi
  done <<< "$repos"
  log "=== Archiveren complete ==="
  log "Repos gemarkeerd voor archiveren: $to_archive"
  RET_ARCHIVE_CANDIDATES="$to_archive"
  send_telegram_message "🏛️ *GitHub Fleet Archiveren*\n\n*Repos gemarkeerd voor archiveren:* ${RET_ARCHIVE_CANDIDATES:-0}\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== COMMITS LINTEN OP CONVENTIE (Conventional Commits) =====================
cmd_commits_lint() {
  log "=== Commits L interen op Conventional Commits Conventie ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local violations=0
  local GOOD_PATTERN='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|security|dep|release)(\(.+\))?: .+'
  local repos
  repos=$(gh repo list "$GH_USER" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    log "--- $repo ---"
    local recent_commits
    recent_commits=$(gh api "repos/$repo/commits?per_page=20" --jq '.[] | "\(.sha[0:7])|\\( .commit.author.date[0:10]) | \(.commit.message | split(\"\\n\")[0])"' 2>/dev/null || true)
    if [ -z "$recent_commits" ]; then continue; fi
    while IFS= read -r commitline; do
      [ -z "$commitline" ] && continue
      local msg
      msg=$(echo "$commitline" | cut -d'|' -f3-)
      if ! echo "$msg" | grep -qiE "$GOOD_PATTERN"; then
        local sha=$(echo "$commitline" | cut -d'|' -f1)
        log "  CONVENTION VIOLATION: $sha — $msg"
        ((violations++)) || true
      fi
    done <<< "$recent_commits"
  done <<< "$repos"
  log "=== Commits lint complete ==="
  log "Conventional Commits violations: $violations"
  RET_COMMITS_LINT_VIOLATIONS="$violations"
  send_telegram_message "📝 *GitHub Fleet Commits L interen*\n\n*Conventional Commits violations:* ${RET_COMMITS_LINT_VIOLATIONS:-0}\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== AUTO-RESPOND OP PR COMMENTS (welcoming) =====================
cmd_auto_pr_comment() {
  log "=== Auto-Respond op PR Comments ==="
  local dry_run="${DRY_RUN:-}"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository,createdAt --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)/\(.createdAt)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  local replied=0
  while IFS='|' read -r number repo title created; do
    [ -z "$number" ] && continue
    local created_epoch
    created_epoch=$(date -d "$created" '+%s' 2>/dev/null || echo "0")
    local now_epoch=$(date '+%s')
    local hours_open=$(( (now_epoch - created_epoch) / 3600 ))
    if [ "$hours_open" -gt 72 ]; then
      log "  LONG OPEN PR #$number in $repo: $title (open $hours_open uur)"
      local comment_body="👋 Thanks for opening this PR! Just a friendly reminder that it has been open for over 72 hours. If you need any help or have questions, feel free to ask. We appreciate your contribution! 🎉"
      if [ "$dry_run" = "1" ]; then
        log "    [DRY-RUN] Would comment on PR #$number"
        ((replied++)) || true
      else
        if gh pr comment "$repo#$number" --body "$comment_body" 2>/dev/null; then
          ((replied++)) || true
          log "    ✓ Replied to PR #$number"
        else log "    ✗ Failed to comment"; fi
      fi
    fi
  done <<< "$open_prs"
  log "=== Auto PR comment complete ==="
  log "PRs aangemaand met herinnering: $replied"
  RET_AUTO_PR_COMMENT_REPLIED="$replied"
  send_telegram_message "💬 *GitHub Fleet Auto PR Comment*\n\n*Herinneringen gestuurd:* ${RET_AUTO_PR_COMMENT_REPLIED:-0}\n\\n📋 Volledig log: $LOG_FILE" || true
}


# ===================== DEPENDENCY UPDATE PRS AUTOMATISCH AANMAKEN =====================
cmd_dep_update_prs() {
  log "=== Dependency Update PRs Aanmaken ==="
  local dry_run="${DRY_RUN:-}"
  local created=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local dir="$REPOS_DIR/$(echo "$kr" | cut -d/ -f2)"
    if [ ! -d "$dir" ]; then log "  Not cloned locally — skip"; continue; fi
    cd "$dir"
    # npm/pnpm
    if [ -f "package.json" ] && command -v pnpm >/dev/null 2>&1; then
      local outdated
      outdated=$(pnpm outdated --format json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pkg in data.get('dependencies', {}).get('outdated', []):
    print(f"{pkg['name']}:{pkg['current']}:{pkg['latest']}:{pkg['dependencyType']}")
" 2>/dev/null || true)
      if [ -n "$outdated" ]; then
        log "  npm outdated: $(echo "$outdated" | wc -l | tr -d ' ') packages"
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          local pkg_name pkg_current pkg_latest
          pkg_name=$(echo "$line" | cut -d: -f1)
          pkg_current=$(echo "$line" | cut -d: -f2)
          pkg_latest=$(echo "$line" | cut -d: -f3)
          log "    → $pkg_name: $pkg_current → $pkg_latest"
          if [ "$dry_run" = "1" ]; then
            log "    [DRY-RUN] Would create PR for $pkg_name"
            ((created++)) || true
          else
            if pnpm add "$pkg_name@${pkg_latest}" 2>/dev/null && \
               git add package.json pnpm-lock.yaml 2>/dev/null && \
               git commit -m "chore(deps): update $pkg_name to $pkg_latest" --quiet 2>/dev/null && \
               git push --quiet 2>/dev/null && \
               maybe_mutate gh pr create --base main --head "update-$pkg_name" --title "chore(deps): update $pkg_name to $pkg_latest" --body "Automated dependency update by GitHub Fleet Manager.\n\n$pkg_name: $pkg_current → $pkg_latest" 2>/dev/null; then
              log "    ✓ PR created"
              ((created++)) || true
            else log "    ✗ Failed"; fi
          fi
        done <<< "$outdated"
      fi
    fi
    # Python
    if [ -f "requirements.txt" ] && [ -f ".venv/bin/pip" ]; then
      local outdated
      outdated=$(.venv/bin/pip list --outdated --format json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for pkg in data:
    print(f\"{pkg['name']}:{pkg['version']}:{pkg['latest_version']}\")
" 2>/dev/null || true)
      if [ -n "$outdated" ]; then
        log "  Python outdated: $(echo "$outdated" | wc -l | tr -d ' ') packages"
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          local pkg_name pkg_current pkg_latest
          pkg_name=$(echo "$line" | cut -d: -f1)
          pkg_current=$(echo "$line" | cut -d: -f2)
          pkg_latest=$(echo "$line" | cut -d: -f3)
          log "    → $pkg_name: $pkg_current → $pkg_latest"
          if [ "$dry_run" = "1" ]; then
            log "    [DRY-RUN] Would create PR for $pkg_name"
            ((created++)) || true
          else
            if .venv/bin/pip install "$pkg_name==$pkg_latest" --quiet 2>/dev/null && \
               .venv/bin/pip freeze > requirements.txt 2>/dev/null && \
               git add requirements.txt 2>/dev/null && \
               git commit -m "chore(deps): update $pkg_name to $pkg_latest" --quiet 2>/dev/null && \
               git push --quiet 2>/dev/null && \
               maybe_mutate gh pr create --base main --head "update-$pkg_name" --title "chore(deps): update $pkg_name to $pkg_latest" --body "Automated dependency update by GitHub Fleet Manager.\\n\\n$pkg_name: $pkg_current → $pkg_latest" 2>/dev/null; then
              log "    ✓ PR created"
              ((created++)) || true
            else log "    ✗ Failed"; fi
          fi
        done <<< "$outdated"
      fi
    fi
    echo ""
  done
  cd "$HOME"
  log "=== Dependency update PRs complete ==="
  log "PRs aangemaakt: $created"
  RET_DEP_UPDATE_PRS="$created"
  send_telegram_message "📦 *GitHub Fleet Dependency Update PRs*\n\n*PRS aangemaakt:* ${RET_DEP_UPDATE_PRS:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== GITHUB DISCUSSIONS BECHEREN =====================
cmd_discussions_manage() {
  log "=== GitHub Discussions Beheren ==="
  local dry_run="${DRY_RUN:-}"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner,isDiscussionEnabled --jq '.[] | select(.isDiscussionEnabled == true) | .nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos with discussions enabled"; return; fi
  local total_discussions=0
  local archived=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    log "--- $repo ---"
    local discussions
    discussions=$(gh api "repos/$repo/discussions?per_page=100" --jq '.[] | "\(.id)|\(.title)|\(.state)|\(.created_at[0:10])"' 2>/dev/null || true)
    if [ -z "$discussions" ]; then continue; fi
    local count
    count=$(echo "$discussions" | grep -c '|' || echo "0")
    total_discussions=$((total_discussions + count))
    log "  $count discussions"
    while IFS='|' read -r id title state created; do
      [ -z "$id" ] && continue
      if [ "$state" = "closed" ]; then
        local created_epoch
        created_epoch=$(date -d "$created" '+%s' 2>/dev/null || echo "0")
        local now_epoch=$(date '+%s')
        local days_old=$(( (now_epoch - created_epoch) / 86400 ))
        if [ "$days_old" -gt 90 ]; then
          log "    CLOSED & OLD (>90d): #$id — $title"
          if [ "$dry_run" = "1" ]; then
            log "    [DRY-RUN] Would archive discussion #$id"
            ((archived++)) || true
          else
            if gh api "repos/$repo/discussions/$id" --method PATCH -F state="archived" 2>/dev/null; then
              log "    ✓ Archived #$id"
              ((archived++)) || true
            else log "    ✗ Failed"; fi
          fi
        fi
      fi
    done <<< "$discussions"
    echo ""
  done
  log "=== Discussions manage complete ==="
  log "Total discussions: $total_discussions | Archived: $archived"
  RET_DISCUSSIONS_TOTAL="$total_discussions"
  RET_DISCUSSIONS_ARCHIVED="$archived"
  send_telegram_message "💬 *GitHub Fleet Discussions*\n\n*Totaal discussions:* ${RET_DISCUSSIONS_TOTAL:-0}\n*Gearchiveerd:* ${RET_DISCUSSIONS_ARCHIVED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== REPOSITORY INSIGHTS / TRAFFIC MONITORING =====================
cmd_repo_traffic() {
  log "=== Repository Insights / Traffic Monitoring ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local report=""
  local total_views=0
  local total_clones=0
  local repos_with_traffic=0
  local repos=$(gh repo list "$GH_USER" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local views
    views=$(gh api "repos/$repo/traffic/views" --jq '.views | length' 2>/dev/null || echo "0")
    views=$(echo "$views" | grep -oE '^[0-9]+$' || echo "0")
    local clones
    clones=$(gh api "repos/$repo/traffic/clones" --jq '.clones | length' 2>/dev/null || echo "0")
    clones=$(echo "$clones" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$views" != "0" ] || [ "$clones" != "0" ]; then
      ((repos_with_traffic++)) || true
      total_views=$((total_views + views))
      total_clones=$((total_clones + clones))
      log "  $repo: ★${views} views | 🍴${clones} clones"
      report+="  $repo: ${views} views | ${clones} clones\n"
    fi
  done <<< "$repos"
  log "=== Traffic monitoring complete ==="
  log "Repos with traffic: $repos_with_traffic"
  log "Total views: $total_views | Total clones: $total_clones"
  RET_TRAFFIC_VIEWS="$total_views"
  RET_TRAFFIC_CLONES="$total_clones"
  RET_TRAFFIC_REPOS="$repos_with_traffic"
  send_telegram_message "📊 *GitHub Fleet Traffic Monitor*\n\n*Repos met traffic:* ${RET_TRAFFIC_REPOS:-0}\n*Totaal views:* ${RET_TRAFFIC_VIEWS:-0}\n*Totaal clones:* ${RET_TRAFFIC_CLONES:-0}\n$( [ -n "$report" ] && echo "$report" )\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== RELEASE ASSET UPLOADEN =====================
cmd_release_asset_upload() {
  log "=== Release Asset Uploaden ==="
  local dry_run="${DRY_RUN:-}"
  local uploaded=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  for kr in "${RELEASE_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local latest_release
    latest_release=$(gh release list --repo "$kr" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")
    if [ -z "$latest_release" ]; then log "  No releases found"; continue; fi
    log "  Latest release: $latest_release"
    local asset_dir="$REPOS_DIR/$(echo "$kr" | cut -d/ -f2)/dist"
    if [ ! -d "$asset_dir" ]; then
      log "  No dist directory found at $asset_dir"
      continue
    fi
    local assets
    assets=$(find "$asset_dir" -type f \( -name "*.zip" -o -name "*.tar.gz" -o -name "*.exe" -o -name "*.deb" -o -name "*.rpm" -o -name "*.dmg" \) 2>/dev/null || true)
    if [ -z "$assets" ]; then
      log "  No binary assets found in $asset_dir"
      continue
    fi
    while IFS= read -r asset; do
      [ -z "$asset" ] && continue
      local basename
      basename=$(basename "$asset")
      log "    Uploading: $basename"
      if [ "$dry_run" = "1" ]; then
        log "    [DRY-RUN] Would upload $basename to release $latest_release"
        ((uploaded++)) || true
      else
        if gh release upload "$latest_release" "$asset" --repo "$kr" --clobber 2>/dev/null; then
          log "    ✓ Uploaded $basename"
          ((uploaded++)) || true
        else log "    ✗ Failed to upload $basename"; fi
      fi
    done <<< "$assets"
    echo ""
  done
  log "=== Release asset upload complete ==="
  log "Assets geuploaded: $uploaded"
  RET_ASSET_UPLOADED="$uploaded"
  send_telegram_message "📦 *GitHub Fleet Release Assets*\n\n*Assets geuploaded:* ${RET_ASSET_UPLOADED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== STALE COLLABORATOR VERWIJDEREN =====================
cmd_stale_collaborator_cleanup() {
  log "=== Stale Collaborator Verwijderen ==="
  local dry_run="${DRY_RUN:-}"
  local removed=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local stale_days="${STALE_COLLABORATOR_DAYS:-90}"
  local cutoff
  cutoff=$(date -d "$stale_days days ago" '+%Y-%m-%d' 2>/dev/null || date -v-${stale_days}d '+%Y-%m-%d' 2>/dev/null || echo "")
  [ -z "$cutoff" ] && { log "Cannot determine cutoff"; return; }
  log "Stale collaborator drempel: geen activiteit sinds $cutoff ($stale_days dagen)"
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local org
    org=$(echo "$kr" | cut -d/ -f1); set_repo_token "$org"
    local collaborators
    collaborators=$(gh api "repos/$kr/collaborators" --jq '.[] | "\(.login)|\(.type)|\(.permissions.admin // false)|\(.permissions.push // false)"' 2>/dev/null || true)
    if [ -z "$collaborators" ]; then continue; fi
    while IFS='|' read -r login collab_type admin push; do
      [ -z "$login" ] && continue
      [ "$login" = "$GH_USER" ] && continue
      [ "$collab_type" = "Organization" ] && continue
      log "  Collaborator: $login (admin: $admin, push: $push)"
      local last_active
      last_active=$(gh api "repos/$kr/commits?author=$login&per_page=1" --jq '.[0].commit.author.date[0:10]' 2>/dev/null || echo "")
      if [ -n "$last_active" ] && [[ "$last_active" < "$cutoff" ]]; then
        log "    STALE: $login last active $last_active (>$stale_days dagen)"
        if [ "$dry_run" = "1" ]; then
          log "    [DRY-RUN] Would remove collaborator $login"
          ((removed++)) || true
        else
          if gh api "repos/$kr/collaborators/$login" --method DELETE 2>/dev/null; then
            log "    ✓ Removed $login"
            ((removed++)) || true
          else log "    ✗ Failed to remove $login"; fi
        fi
      else
        log "    Active (last: ${last_active:-never})"
      fi
    done <<< "$collaborators"
    echo ""
  done
  log "=== Stale collaborator cleanup complete ==="
  log "Collaborators verwijderd: $removed"
  RET_COLLABORATOR_REMOVED="$removed"
  send_telegram_message "👥 *GitHub Fleet Stale Collaborators*\n\n*Verwijderd:* ${RET_COLLABORATOR_REMOVED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== WEBHOOK INSPECTIE & BEHEER =====================
cmd_webhook_inspect() {
  log "=== Webhook Inspectie & Beheer ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local report=""
  local total_webhooks=0
  local inactive_webhooks=0
  local repos=$(gh repo list "$GH_USER" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local hooks
    hooks=$(gh api "repos/$repo/hooks" --jq '.[] | "\(.id)|\(.name)|\(.active)|\(.events | join(\",\"))|\(.config.url)"' 2>/dev/null || true)
    if [ -z "$hooks" ]; then continue; fi
    local count
    count=$(echo "$hooks" | grep -c '|' || echo "0")
    total_webhooks=$((total_webhooks + count))
    log "--- $repo: $count webhooks ---"
    while IFS='|' read -r id name active events url; do
      [ -z "$id" ] && continue
      log "  $name (active: $active) — $url [events: $events]"
      if [ "$active" = "false" ]; then
        ((inactive_webhooks++)) || true
        report+="  ⚠️ $repo/$id ($name): INACTIEF — $url\n"
      fi
    done <<< "$hooks"
    echo ""
  done <<< "$repos"
  log "=== Webhook inspect complete ==="
  log "Total webhooks: $total_webhooks | Inactive: $inactive_webhooks"
  RET_WEBHOOK_TOTAL="$total_webhooks"
  RET_WEBHOOK_INACTIVE="$inactive_webhooks"
  send_telegram_message "🔌 *GitHub Fleet Webhooks*\n\n*Totaal webhooks:* ${RET_WEBHOOK_TOTAL:-0}\n*Inactief:* ${RET_WEBHOOK_INACTIVE:-0}\n$( [ -n "$report" ] && echo "$report" )\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== PROJECT BOARDS V2 BECHEREN =====================
cmd_project_board_sync() {
  log "=== Project Boards V2 Beheren ==="
  local dry_run="${DRY_RUN:-}"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local projects
  projects=$(gh api "user/projects?per_page=100" --jq '.[] | "\(.id)|\(.name)|\(.state)"' 2>/dev/null || true)
  if [ -z "$projects" ]; then log "No projects found"; return; fi
  local total_items=0
  while IFS='|' read -r id name state; do
    [ -z "$id" ] && continue
    log "--- Project: $name (state: $state) ---"
    local fields
    fields=$(gh api "projects/$id/columns?per_page=100" --jq '.[] | "\(.id)|\(.name)|\(.status)"' 2>/dev/null || true)
    if [ -z "$fields" ]; then continue; fi
    while IFS='|' read -r fid fname fstatus; do
      [ -z "$fid" ] && continue
      log "  Column: $fname ($fstatus)"
      local items
      items=$(gh api "projects/$id/items?per_page=100&columns=$fid" --jq '.[] | "\(.content_type)|\(.content_url)"' 2>/dev/null || true)
      if [ -z "$items" ]; then continue; fi
      local item_count
      item_count=$(echo "$items" | grep -c '|' || echo "0")
      total_items=$((total_items + item_count))
      log "    $item_count items"
    done <<< "$fields"
    echo ""
  done <<< "$projects"
  log "=== Project board sync complete ==="
  log "Total items across projects: $total_items"
  RET_PROJECT_ITEMS="$total_items"
  send_telegram_message "📋 *GitHub Fleet Project Boards*\n\n*Totaal items:* ${RET_PROJECT_ITEMS:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== REPOSITORY TRANSFEFENT / RENAMING DETECTIE =====================
cmd_repo_transfer_detect() {
  log "=== Repository Transfeferent / Renaming Detectie ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local local_repos
  local_repos=$(find "$REPOS_DIR" -maxdepth 1 -type d -name '*.git' -o -type d -exec test -e '{}/.git' \; -print 2>/dev/null | sed 's|/$||' | while read -r dir; do basename "$dir"; done || true)
  if [ -z "$local_repos" ]; then log "No local repos found"; return; fi
  local detected=0
  while IFS= read -r local_name; do
    [ -z "$local_name" ] && continue
    log "--- Checking $local_name ---"
    local remote_url
    remote_url=$(cd "$REPOS_DIR/$local_name" 2>/dev/null && git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$remote_url" ]; then log "  No origin remote"; continue; fi
    local remote_repo
    remote_repo=$(echo "$remote_url" | sed -n 's|.*github.com/\([^/]*\)/.*|\1|;s|.*github.com/\([^/]*\).*|\1|p')
    local remote_name
    remote_name=$(echo "$remote_url" | sed -n 's|.*github.com/[^/]*/\([^/.]*\).*|\1|p;s|.*github.com/[^/]*\([^/]*\).*|\1|p')
    if [ -n "$remote_name" ] && [ "$remote_name" != "$local_name" ]; then
      log "  ⚠️ RENAMED: local='$local_name' vs remote='$remote_name'"
      ((detected++)) || true
    elif [ -n "$remote_repo" ] && [ "$remote_repo" != "$GH_USER" ] && [ "$remote_repo" != "fork" ]; then
      log "  ⚠️ TRANSFERRED: original org='$remote_repo', current user=$GH_USER"
      ((detected++)) || true
    else
      log "  OK: matches GitHub"
    fi
  done <<< "$local_repos"
  log "=== Repo transfer detect complete ==="
  log "Mis-matched repos detected: $detected"
  RET_REPO_TRANSFER_MISMATCH="$detected"
  send_telegram_message "🔄 *GitHub Fleet Repo Transfer Detect*\n\n*Mismatched repos:* ${RET_REPO_TRANSFER_MISMATCH:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== LICENCE / AUTEURSRECHT RAPPORT PER ORG =====================
cmd_license_org_report() {
  log "=== Licentie / Auteursrecht Rapport per Org ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,licenseInfo --jq '.[] | "\(.nameWithOwner)|\(.licenseInfo.name // "NONE")"' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  declare -A license_counts
  local no_license=0
  while IFS='|' read -r repo license; do
    [ -z "$repo" ] && continue
    if [ "$license" = "NONE" ] || [ -z "$license" ]; then
      ((no_license++)) || true
      log "  NO LICENSE: $repo"
    else
      license_counts["$license"]=$(( ${license_counts["$license"]:-0} + 1 ))
    fi
  done <<< "$repos"
  log "=== Licentie rapport complete ==="
  log "Repos zonder licentie: $no_license"
  log "Licentie verdeling:"
  for lic in "${!license_counts[@]}"; do
    log "  $lic: ${license_counts[$lic]}"
  done
  RET_LICENSE_NO_LICENSE="$no_license"
  RET_LICENSE_GPL="${license_counts[GPL]:-0}"
  RET_LICENSE_MIT="${license_counts[MIT]:-0}"
  RET_LICENSE_APACHE="${license_counts[Apache-2.0]:-0}"
  RET_LICENSE_BSD="${license_counts[BSD]:-0}"
  send_telegram_message "📄 *GitHub Fleet Licentie Rapport*\n\n*Repos zonder licentie:* ${RET_LICENSE_NO_LICENSE:-0}\n*MIT:* ${RET_LICENSE_MIT:-0}\n*GPL:* ${RET_LICENSE_GPL:-0}\n*Apache:* ${RET_LICENSE_APACHE:-0}\n*BSD:* ${RET_LICENSE_BSD:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== GITHUB COPILOT AUTOREVIEW STATUS =====================
cmd_copilot_autorreview_status() {
  log "=== GitHub Copilot Auto-Review Status ==="
  [ "${COPILOT_REVIEW_ENABLED:-yes}" != "yes" ] && { log "Copilot auto-review disabled"; return; }
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local total=0; local enabled=0; local disabled=0; local error=0
  local repo
  for repo in $(gh repo list "$GH_USER" --limit 200 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true); do
    [ -z "$repo" ] && continue
    local status
    status=$(gh api "repos/$repo/copilot/review" --jq '.enabled // false' 2>/dev/null || echo "error")
    case "$status" in
      true) ((enabled++)) || true ;;
      false) ((disabled++)) || true ;;
      *) ((error++)) || true ;;
    esac
    ((total++)) || true
  done
  log "=== Copilot Auto-Review Summary ==="
  log "Total repos scanned: $total"
  log "Enabled: $enabled | Disabled: $disabled | Errors: $error"
  RET_COPILOT_REVIEW_ENABLED_COUNT="$enabled"
  RET_COPILOT_REVIEW_DISABLED_COUNT="$disabled"
  send_telegram_message "🤖 *GitHub Fleet Copilot Auto-Review*\\n\\n*Repos met Copilot review:* ${RET_COPILOT_REVIEW_ENABLED_COUNT:-0}\\n*Repos zonder Copilot review:* ${RET_COPILOT_REVIEW_DISABLED_COUNT:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== RELEASE NOTES VAN PR-SJABLONEN PARSEREN =====================
cmd_release_notes_from_templates() {
  log "=== Release Notes van PR-Sjablonen Parseren ==="
  local dry_run="${DRY_RUN:-}"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local pr_template
    pr_template=$(gh api "repos/$kr/contents/.github/PULL_REQUEST_TEMPLATE.md" --jq '.content' 2>/dev/null || echo "")
    if [ -z "$pr_template" ]; then
      log "  No PR template found"
      continue
    fi
    local template_text
    template_text=$(echo "$pr_template" | python3 -c "import sys,base64; print(base64.b64decode(sys.stdin.read().strip()).decode())" 2>/dev/null || echo "")
    if [ -z "$template_text" ]; then continue; fi
    log "  PR template gevonden ($(echo "$template_text" | wc -l | tr -d ' ') lines)"
    local last_tag
    last_tag=$(gh tag list --repo "$kr" --limit 1 --json name --jq '.[0].name' 2>/dev/null || echo "")
    local open_prs
    open_prs=$(gh search prs --state open --limit 50 --json number,title,repository,body,labels --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)//\(.title)//\(.body)//\(.labels | map(.name) | join(\",\"))"' 2>/dev/null || true)
    if [ -z "$open_prs" ]; then log "  No open PRs"; continue; fi
    local categorized=""
    while IFS='|' read -r number repo title body labels; do
      [ -z "$number" ] && continue
      local feat_match
      feat_match=$(echo "$body" | grep -E '## Features|**What.*does this PR do|**Changes:**' | head -1 || true)
      local fix_match
      fix_match=$(echo "$body" | grep -E '## Fixes|**Bug.*fixed|**Issue resolved:**' | head -1 || true)
      local docs_match
      docs_match=$(echo "$body" | grep -E '## Documentation|**Docs:**|**Documentation:**' | head -1 || true)
      if [ -n "$feat_match" ]; then
        categorized+="  🚀 $repo #$number: $title\n     $feat_match\n\n"
      elif [ -n "$fix_match" ]; then
        categorized+="  🐛 $repo #$number: $title\n     $fix_match\n\n"
      elif [ -n "$docs_match" ]; then
        categorized+="  📄 $repo #$number: $title\n     $docs_match\n\n"
      fi
    done <<< "$open_prs"
    if [ -n "$categorized" ]; then
      log "  Categorized PRs from template: $(echo "$categorized" | wc -l | tr -d ' ') lines"
      if [ "$dry_run" = "1" ]; then
        log "  [DRY-RUN] Would create release notes from PR templates"
      else
        local draft_tag="template-notes-$(date '+%Y%m%d')"
        local notes_body="## Changes (from PR templates)\n\n$categorized\n---\nAuto-generated by GitHub Fleet Manager from PR templates."
        if gh release create "$draft_tag" --draft --title "PR Template Notes: $(date '+%Y-%m-%d')" --notes "$notes_body" --repo "$kr" 2>/dev/null; then
          log "  ✓ Draft created: $draft_tag"
        else log "  ✗ Failed"; fi
      fi
    fi
    echo ""
  done
  log "=== Release notes from templates complete ==="
  send_telegram_message "📝 *GitHub Fleet Release Notes (van PR Templates)*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== DUURZAAMHEID / CARBON FOOTPRINT VAN CI RUNS =====================
cmd_ci_carbon_footprint() {
  log "=== Duurzaamheid / Carbon Footprint van CI Runs ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local report=""
  local total_runs=0
  local estimated_co2_g=0
  local repos=$(gh repo list "$GH_USER" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local runs
    runs=$(gh run list --repo "$repo" --limit 100 --json name,databaseId,status,conclusion,createdAt,updatedAt,headBranch --jq '.[] | "\(.name)|\(.databaseId)|\(.status)|\(.conclusion)|\(.createdAt)|\(.updatedAt)|\(.headBranch)"' 2>/dev/null || true)
    if [ -z "$runs" ]; then continue; fi
    local count
    count=$(echo "$runs" | grep -c '|' || echo "0")
    total_runs=$((total_runs + count))
    while IFS='|' read -r name databaseId status conclusion created_at updated_at head_branch; do
      [ -z "$databaseId" ] && continue
      [ -z "$created_at" ] && continue
      [ -z "$updated_at" ] && continue
      local start_epoch end_epoch
      start_epoch=$(date -d "$created_at" '+%s' 2>/dev/null || echo "0")
      end_epoch=$(date -d "$updated_at" '+%s' 2>/dev/null || echo "0")
      [ "$start_epoch" = "0" ] && continue
      [ "$end_epoch" = "0" ] && continue
      local duration=$(( end_epoch - start_epoch ))
      [ "$duration" -le 0 ] && continue
      local co2_g=$(( duration * 100 / 1000 ))  # 0.1g CO₂ per second, rounded
      estimated_co2_g=$(( estimated_co2_g + co2_g ))
      log "  $name ($databaseId): ${duration}s → ~${co2_g}g CO₂"
      report+="  $repo/$name: ${duration}s → ${co2_g}g CO₂\\n"
    done <<< "$runs"
    echo ""
  done <<< "$repos"
  log "=== CI carbon footprint complete ==="
  log "Total CI runs analyzed: $total_runs"
  log "Estimated CO₂: ${estimated_co2_g}g (based on 0.1g CO₂/s estimate)"
  RET_CI_RUNS_TOTAL="$total_runs"
  RET_CI_CO2_ESTIMATE="$estimated_co2_g"
  send_telegram_message "🌍 *GitHub Fleet CI Carbon Footprint*\n\n*CI runs geanalyseerd:* ${RET_CI_RUNS_TOTAL:-0}\n*Geschat CO₂:* ${RET_CI_CO2_ESTIMATE:-0}g\n$( [ -n "$report" ] && echo "$report" )\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== MAIN CASE =====================

# ===================== PRS LABEL AUTO (bestands-gebaseerde labels) =====================
cmd_prs_label_auto() {
  log "=== PRs Label Auto (bestands-gebaseerde labels) ==="
  local dry_run="${DRY_RUN:-}"
  local labeled=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,title,repository --jq '.[] | select(.repository.owner.login == "itsdarklikehell" or .repository.owner.login == "hans") | "\(.number)|\(.repository.nameWithOwner)//\(.title)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  declare -A file_label_map
  file_label_map["src/frontend"]=frontend
  file_label_map["src/ui"]=frontend
  file_label_map["components/"]=frontend
  file_label_map["app/frontend"]=frontend
  file_label_map["src/backend"]=backend
  file_label_map["src/server"]=backend
  file_label_map["api/"]=backend
  file_label_map["internal/"]=backend
  file_label_map["src/models"]=backend
  file_label_map["docs/"]=documentation
  file_label_map["README*"]=documentation
  file_label_map["CONTRIBUTING*"]=documentation
  file_label_map["scripts/"]=automation
  file_label_map["*.sh"]=automation
  file_label_map["Makefile*"]=automation
  file_label_map["Dockerfile*"]=infrastructure
  file_label_map["docker/"]=infrastructure
  file_label_map["k8s/"]=infrastructure
  file_label_map["*_test.*"]=testing
  file_label_map["tests/"]=testing
  file_label_map["spec/"]=testing
  file_label_map["*.test.*"]=testing
  file_label_map["config/"]=config
  file_label_map["*.yml"]=config
  file_label_map["*.yaml"]=config
  file_label_map["*.json"]=config
  file_label_map["package.json"]=dependencies
  file_label_map["package-lock.json"]=dependencies
  file_label_map["yarn.lock"]=dependencies
  file_label_map["pnpm-lock.yaml"]=dependencies
  file_label_map["requirements*.txt"]=dependencies
  file_label_map["Pipfile*"]=dependencies
  file_label_map["go.mod"]=dependencies
  file_label_map["Cargo.toml"]=dependencies
  file_label_map["*.go"]=backend
  file_label_map["*.py"]=python
  file_label_map["*.js"]=frontend
  file_label_map["*.ts"]=frontend
  file_label_map["*.tsx"]=frontend
  file_label_map["*.css"]=frontend
  file_label_map["*.scss"]=frontend
  file_label_map["*.rs"]=rust
  file_label_map["*.toml"]=config
  while IFS='|' read -r number repo title; do
    [ -z "$number" ] && continue
    log "--- PR #$number in $repo: $title ---"
    local added_labels=""
    local diff_files
    diff_files=$(gh pr view --repo "$repo" "$number" --json files --jq '.files[].path' 2>/dev/null || true)
    if [ -z "$diff_files" ]; then log "  No files in diff (or API error)"; continue; fi
    while IFS= read -r filepath; do
      [ -z "$filepath" ] && continue
      for file_pattern in "${!file_label_map[@]}"; do
        if echo "$filepath" | grep -qi "$file_pattern"; then
          local label="${file_label_map[$file_pattern]}"
          if ! echo "$added_labels" | grep -qF "$label"; then
            added_labels="$added_labels $label"
            log "  → $filepath → label: $label"
          fi
        fi
      done
    done <<< "$diff_files"
    if [ -n "$added_labels" ]; then
      log "  Adding labels:$added_labels"
      if [ "$dry_run" = "1" ]; then
        log "  [DRY-RUN] Would add labels to PR #$number"
        ((labeled++)) || true
      elif gh pr edit "$repo#$number" --add-label "$added_labels" 2>/dev/null; then
        ((labeled++)) || true
      else log "    Failed to add labels"; fi
    else log "  No matching file labels"; fi
  done <<< "$open_prs"
  log "=== PRs Label Auto complete ==="
  log "PRs labeled: $labeled"
  RET_PRS_LABELED_AUTO="$labeled"
  send_telegram_message "🏷️ *GitHub Fleet PRs Label Auto*\n\n*PRs gelabeld:* ${RET_PRS_LABELED_AUTO:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== AUTO TRIAGE ISSUES =====================
cmd_auto_triage_issues() {
  log "=== Auto Triage Issues ==="
  local dry_run="${DRY_RUN:-}"
  local labeled=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local unlabeled_issues
  unlabeled_issues=$(gh search issues --state open --limit 100 --json number,title,repository,labels --jq '.[] | select(.repository.owner.login == "itsdarklikehell" or .repository.owner.login == "hans") | select(.labels | length == 0) | "\(.number)|\(.repository.nameWithOwner)//\(.title)"' 2>/dev/null || true)
  if [ -z "$unlabeled_issues" ]; then log "No unlabeled issues found"; return; fi
  while IFS='|' read -r number repo title; do
    [ -z "$number" ] && continue
    log "--- Issue #$number in $repo: $title ---"
    if [ "$dry_run" = "1" ]; then
      log "  [DRY-RUN] Would add triage label to issue #$number"
      ((labeled++)) || true
    elif gh issue edit "$repo#$number" --add-label "triage" 2>/dev/null; then
      ((labeled++)) || true
      log "  ✓ Added triage label"
    else log "  ✗ Failed"; fi
  done <<< "$unlabeled_issues"
  log "=== Auto Triage Issues complete ==="
  log "Issues triaged: $labeled"
  RET_AUTO_TRIAGE_ISSUES="$labeled"
  send_telegram_message "🔍 *GitHub Fleet Auto Triage Issues*\n\n*Issues getriaged:* ${RET_AUTO_TRIAGE_ISSUES:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== STALE PR REMINDER =====================
cmd_stale_pr_reminder() {
  log "=== Stale PR Reminder ==="
  local dry_run="${DRY_RUN:-}"
  local reminded=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local stale_cutoff
  stale_cutoff=$(date -d '14 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-14d '+%Y-%m-%d' 2>/dev/null || echo "")
  if [ -z "$stale_cutoff" ]; then log "Cannot determine cutoff date"; return; fi
  log "Stale cutoff: $stale_cutoff (PRs older than this get a reminder)"
  local stale_prs
  stale_prs=$(gh search prs --state open --limit 100 --json number,title,repository,updatedAt --jq ".[] | select(.repository.owner.login == "itsdarklikehell") | select(.repository.owner.login == \"itsdarklikehell\" or .repository.owner.login == \"hans\") | select(.updatedAt < \"$stale_cutoff\") | \"\(.number)|\(.repository.nameWithOwner)//\(.title)//\(.updatedAt[0:10])\"" 2>/dev/null || true)
  if [ -z "$stale_prs" ]; then log "No stale PRs found"; return; fi
  while IFS='|' read -r number repo title updated; do
    [ -z "$number" ] && continue
    log "--- Stale PR #$number in $repo: $title (last updated: $updated) ---"
    if [ "$dry_run" = "1" ]; then
      log "  [DRY-RUN] Would send reminder on PR #$number"
      ((reminded++)) || true
    else
      local comment_body="👋 Hi there! This PR has been open for over 14 days without activity. Just a friendly reminder to review/merge or update if it's still relevant.\n\nIf this PR is no longer needed, feel free to close it. Otherwise, let us know if you need any help.\n\nCheers!"
      if gh pr comment "$repo#$number" --body "$comment_body" 2>/dev/null; then
        ((reminded++)) || true
        log "  ✓ Reminder sent"
      else log "  ✗ Failed to comment"; fi
    fi
  done <<< "$stale_prs"
  log "=== Stale PR Reminder complete ==="
  log "PRs reminded: $reminded"
  RET_STALE_PR_REMINDED="$reminded"
  send_telegram_message "⏰ *GitHub Fleet Stale PR Reminder*\n\n*PRs herinnerd:* ${RET_STALE_PR_REMINDED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== RELEASE NOTES GENERATOR =====================
cmd_release_notes() {
  log "=== Release Notes Generator ==="
  local dry_run="${DRY_RUN:-}"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local last_tag
    last_tag=$(gh tag list --repo "$kr" --limit 1 --json name --jq '.[0].name' 2>/dev/null || echo "")
    if [ -z "$last_tag" ]; then
      log "  No tags found — using all commits"
      local commits
      commits=$(gh api "repos/$kr/commits?per_page=100" --jq '.[].commit.message' 2>/dev/null | grep -v '^$' || true)
    else
      log "  Last tag: $last_tag"
      local commits
      commits=$(gh api "repos/$kr/commits?sha=$last_tag&per_page=100" --jq '.[].commit.message' 2>/dev/null | grep -v '^$' || true)
    fi
    if [ -z "$commits" ]; then log "  No commits found"; continue; fi
    local features=$(echo "$commits" | grep -E 'feat:|feature:|add:' || true)
    local fixes=$(echo "$commits" | grep -E 'fix:|bugfix:|resolve:' || true)
    local docs=$(echo "$commits" | grep -E 'docs:|documentation:|readme:' || true)
    local chore=$(echo "$commits" | grep -E 'chore:|ci:|refactor:|style:|build:' || true)
    local notes=""
    [ -n "$features" ] && notes+="## Features\n\n$(echo "$features" | sed 's/^/ - /' | head -20)\n\n"
    [ -n "$fixes" ] && notes+="## Fixes\n\n$(echo "$fixes" | sed 's/^/ - /' | head -20)\n\n"
    [ -n "$docs" ] && notes+="## Documentation\n\n$(echo "$docs" | sed 's/^/ - /' | head -20)\n\n"
    [ -n "$chore" ] && notes+="## Maintenance\n\n$(echo "$chore" | sed 's/^/ - /' | head -20)\n\n"
    if [ -n "$notes" ]; then
      log "  Generated release notes with $(echo "$notes" | wc -l | tr -d ' ') lines"
      if [ "$dry_run" = "1" ]; then
        log "  [DRY-RUN] Would create release notes"
      else
        local draft_tag="release-notes-$(date '+%Y%m%d')"
        log "  Checking for existing draft: $draft_tag"
        local existing_draft
        existing_draft=$(gh release view "$draft_tag" --repo "$kr" --json isDraft 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('isDraft',False)).lower())" 2>/dev/null || echo "false")
        if [ "$existing_draft" = "true" ]; then
          log "  Draft $draft_tag already exists today — skip"
        else
          log "  ✓ Draft release created: $draft_tag"
          if ! gh release create "$draft_tag" --draft --title "Release Notes: $(date '+%Y-%m-%d')" --notes "$notes" --repo "$kr" 2>/dev/null; then
            log "  ✗ Failed to create draft"
          fi
        fi
      fi
    else log "  No categorized commits found"; fi
    echo ""
  done
  log "=== Release Notes complete ==="
  send_telegram_message "📝 *GitHub Fleet Release Notes*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== DEPENDABOT AUTO-MERGE =====================
cmd_dependabot_auto_merge() {
  log "=== Dependabot Auto-Merge ==="
  local dry_run="${DRY_RUN:-}"
  local merged=0
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  if [ "$AUTO_MERGE_ENABLED" != "yes" ]; then
    log "Auto-merge disabled (AUTO_MERGE_ENABLED != yes)"
    RET_DEP_AUTO_MERGE=0; return
  fi
  local dep_prs
  dep_prs=$(gh search prs --state open --limit 100 --json number,title,repository,author,mergeable,isDraft --jq '.[] | select(.repository.owner.login == "itsdarklikehell" or .repository.owner.login == "hans") | select(.author.login == "dependabot[bot]" and .mergeable == true and .isDraft == false) | "\(.number)|\(.repository.nameWithOwner)//\(.title)"' 2>/dev/null || true)
  if [ -z "$dep_prs" ]; then log "No mergeable dependabot PRs found"; return; fi
  while IFS='|' read -r number repo title; do
    [ -z "$number" ] && continue
    log "--- Dependabot PR #$number in $repo: $title ---"
    if [ "$dry_run" = "1" ]; then
      log "  [DRY-RUN] Would auto-merge dependabot PR #$number"
      ((merged++)) || true
    elif maybe_mutate gh pr merge "$repo#$number" --merge --delete-branch 2>/dev/null; then
      ((merged++)) || true
      log "  ✓ Merged"
    else log "  ✗ Failed"; fi
  done <<< "$dep_prs"
  log "=== Dependabot Auto-Merge complete ==="
  log "Dependabot PRs merged: $merged"
  RET_DEP_AUTO_MERGE="$merged"
  send_telegram_message "🔀 *GitHub Fleet Dependabot Auto-Merge*\n\n*Dependabot PRs gemerged:* ${RET_DEP_AUTO_MERGE:-0}\n\n📋 Volledig log: $LOG_FILE" || true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then


# ===================== DEPENDENCY BULLETIN (maandag) =====================
cmd_dependency_bulletin() {
  log "=== GitHub Fleet Dependency Bulletin ==="
  log "Weekly overview: dependabot alerts + outdated packages (key repos)"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local total_alerts=0; local repos_with_alerts=0; local total_outdated=0; local repos_with_outdated=0
  local bulletin=""
  for kr in "${KEY_REPOS[@]}"; do
    [ -z "$kr" ] && continue
    log "--- $kr ---"
    local dep_alerts=0; local sec_alerts=0; local code_alerts=0
    dep_alerts=$(gh api "repos/$kr/dependabot/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    dep_alerts=$(echo "$dep_alerts" | grep -oE '^[0-9]+$' || echo "0")
    sec_alerts=$(gh api "repos/$kr/secret-scanning/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    sec_alerts=$(echo "$sec_alerts" | grep -oE '^[0-9]+$' || echo "0")
    code_alerts=$(gh api "repos/$kr/code-scanning/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    code_alerts=$(echo "$code_alerts" | grep -oE '^[0-9]+$' || echo "0")
    local repo_total=$((dep_alerts + sec_alerts + code_alerts))
    total_alerts=$((total_alerts + repo_total))
    if [ "$repo_total" -gt 0 ] 2>/dev/null; then
      repos_with_alerts=$((repos_with_alerts + 1))
      bulletin+="  🚨 $kr: $dep_alerts dependabot + $sec_alerts secret + $code_alerts code-scanning\n"
    fi
    local outdated_dirty=""
    for dep_file in package.json requirements.txt pyproject.toml; do
      [ -f "$kr/$dep_file" ] 2>/dev/null || continue
      # lokale check via bestand - geen API needed
    done
    # Dependency graph API (als beschikbaar)
    local dep_graph_count
    dep_graph_count=$(gh api "repos/$kr/dependency-graph/relationships" --jq '.data | length' 2>/dev/null || echo "0")
    dep_graph_count=$(echo "$dep_graph_count" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$dep_graph_count" -gt 0 ] 2>/dev/null; then
      total_outdated=$((total_outdated + 1))
      if [ "$dep_graph_count" -gt 0 ] 2>/dev/null; then repos_with_outdated=$((repos_with_outdated + 1)); fi
    fi
    echo ""
  done
  log "=== Dependency Bulletin Summary ==="
  log "Repos with alerts: $repos_with_alerts / ${#KEY_REPOS[@]}"
  log "Total alerts: $total_alerts"
  log "Repos with dependency graph: $repos_with_outdated / ${#KEY_REPOS[@]}"
  if [ -n "$bulletin" ]; then
    log "Alerts overzicht:"
    log -e "$bulletin"
  fi
  RET_DEP_BULLETIN_ALERTS="$total_alerts"
  RET_DEP_BULLETIN_REPOS="$repos_with_alerts"
}



# ===================== REPO SUNSET REPORT =====================
cmd_repo_sunset_report() {
  log "=== GitHub Fleet Repo Sunset Report ==="
  log "Listing repos with no pushes >365 days (candidates for archive)"
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local all_repos
  all_repos=$(gh repo list "$GH_USER" --limit 500 --json nameWithOwner,pushedAt,updatedAt,createdAt,visibility,description --jq '.[] | "\(.nameWithOwner)|\(.pushedAt // "")|\(.updatedAt // "")|\(.createdAt[0:10])|\(.visibility)|\(.description // "")"' 2>/dev/null || true)
  if [ -z "$all_repos" ]; then log "No repos found"; return; fi
  local sunset_cutoff_epoch
  sunset_cutoff_epoch=$(date -d '365 days ago' '+%s' 2>/dev/null || echo "0")
  [ "$sunset_cutoff_epoch" = "0" ] && sunset_cutoff_epoch=$(date -v-365d '+%s' 2>/dev/null || echo "0")
  local sunset_repos="" ; local sunset_count=0
  while IFS='|' read -r nameWithOwner pushedAt updatedAt createdAt visibility description; do
    [ -z "$nameWithOwner" ] && continue
    local cutoff_epoch
    cutoff_epoch=$(date -d "$pushedAt" '+%s' 2>/dev/null || echo "0")
    if [ "$cutoff_epoch" != "0" ] && [ "$cutoff_epoch" -lt "$sunset_cutoff_epoch" ] 2>/dev/null; then
      local days_since=$(( ($(date '+%s') - cutoff_epoch) / 86400 ))
      sunset_repos+="  ⏰ $nameWithOwner — last push: $pushedAt ($days_since dagen)\n"
      sunset_count=$((sunset_count + 1))
    fi
  done <<< "$all_repos"
  log "=== Sunset Report Summary ==="
  log "Repos >365 dagen zonder push: $sunset_count"
  if [ -n "$sunset_repos" ]; then
    log -e "$sunset_repos"
  fi
  RET_SUNSET_COUNT="$sunset_count"
}


# ===================== NIEUWE COMMANDO'S (toegevoegd 2026-09-30) =====================

cmd_actions_audit() {
  log "=== GitHub Fleet Actions Audit ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_runs=0; local total_workflows=0; local repos_with_actions=0
  for repo in $repos; do
    [ -z "$repo" ] && continue
    local workflows
    workflows=$(gh workflow list -R "$repo" --json name,state,updatedAt --jq '.[] | "\(.name)|\(.state)|\(.updatedAt // "never")"' 2>/dev/null || true)
    if [ -n "$workflows" ]; then
      local wf_count
      wf_count=$(echo "$workflows" | grep -c '|' || echo "0")
      total_workflows=$((total_workflows + wf_count))
      repos_with_actions=$((repos_with_actions + 1))
      log "  $repo: $wf_count workflow(s)"
    fi
    local runs
    runs=$(gh run list -R "$repo" --limit 5 --json name,conclusion,status,updatedAt --jq '.[] | "\(.name)|\(.status)|\(.conclusion // "none")"' 2>/dev/null || true)
    if [ -n "$runs" ]; then
      local run_count
      run_count=$(echo "$runs" | grep -c '|' || echo "0")
      total_runs=$((total_runs + run_count))
    fi
    echo ""
  done
  log "=== Actions audit complete ==="
  log "Repos with actions: $repos_with_actions | Total workflows: $total_workflows | Recent runs: $total_runs"
  RET_ACTIONS_AUDIT_REPOS="$repos_with_actions"
  RET_ACTIONS_AUDIT_WORKFLOWS="$total_workflows"
}

cmd_actions_scheduled_report() {
  log "=== GitHub Fleet Actions Scheduled Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_scheduled=0
  for repo in $repos; do
    local scheduled_wfs
    scheduled_wfs=$(gh workflow list -R "$repo" --json name,state,schedule --jq '.[] | select(.schedule != null) | "\(.name)|\(.state)|\(.schedule)"' 2>/dev/null || true)
    if [ -n "$scheduled_wfs" ]; then
      local count
      count=$(echo "$scheduled_wfs" | grep -c '|' || echo "0")
      total_scheduled=$((total_scheduled + count))
      log "  $repo: $count scheduled workflow(s)"
    fi
    echo ""
  done
  log "=== Scheduled report complete ==="
  log "Total scheduled workflows: $total_scheduled"
  RET_SCHEDULED_TOTAL="$total_scheduled"
}

cmd_collaborator_report() {
  log "=== GitHub Fleet Collaborator Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_collabs=0
  for repo in $repos; do
    local collabs
    collabs=$(gh api "repos/$repo/collaborators" --jq '.[] | select(.type == "User") | "\(.login)"' 2>/dev/null || true)
    if [ -n "$collabs" ]; then
      local count
      count=$(echo "$collabs" | grep -c '.' || echo "0")
      total_collabs=$((total_collabs + count))
      log "  $repo: $count collaborator(s)"
    fi
    echo ""
  done
  log "=== Collaborator report complete ==="
  log "Total collaborators: $total_collabs"
  RET_COLLAB_TOTAL="$total_collabs"
}

cmd_creation_time_report() {
  log "=== GitHub Fleet Creation Time Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 200 --json nameWithOwner,createdAt --jq '.[] | "\(.nameWithOwner)|\(.createdAt[0:10])"' 2>/dev/null | grep -v '^$' || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  log "  Repo creation dates:"
  echo "$repos" | while IFS='|' read -r name created; do
    [ -z "$name" ] && continue
    log "    $name — created: $created"
  done
  log "=== Creation time report complete ==="
}

cmd_deptry_monitor() {
  log "=== GitHub Fleet Deptry Monitor ==="
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    log "--- $repo ---"
    cd "$repo_dir"
    if [ -f "pyproject.toml" ] && command -v deptry >/dev/null 2>&1; then
      local deptry_out
      deptry_out=$(deptry . 2>&1 || true)
      if [ -n "$deptry_out" ] && ! echo "$deptry_out" | grep -q "No issues found"; then
        log "  Deptry issues found:"
        echo "$deptry_out" | head -20 | while IFS= read -r line; do [ -z "$line" ] && continue; log "    $line"; done
      else log "  No issues found"; fi
    else log "  No pyproject.toml or deptry not available"; fi
    echo ""
  done
  log "=== Deptry monitor complete ==="
}

cmd_gource_repo_report() {
  log "=== GitHub Fleet Gource Repo Report ==="
  local total=0; local with_video=0; local with_workflow=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    total=$((total + 1))
    local has_wf=false; local has_video=false
    [ -f "$repo_dir/.github/workflows/gource.yml" ] && has_wf=true && ((with_workflow++)) || true
    [ -f "$repo_dir/gource/gource.mp4" ] && has_video=true && ((with_video++)) || true
    if $has_wf && $has_video; then log "  OK: $repo (workflow + video)"
    elif $has_wf; then log "  WORKFLOW-ONLY: $repo"
    else log "  MISSING: $repo"
    fi
  done
  log "=== Gource repo report complete ==="
  log "Total: $total | Workflow: $with_workflow | Video: $with_video"
  RET_GOURCE_REPO_TOTAL="$total"
  RET_GOURCE_REPO_VIDEO="$with_video"
}

cmd_issue_labels_report() {
  log "=== GitHub Fleet Issue Labels Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_issues=0
  for repo in $repos; do
    local issues_json
    issues_json=$(gh issue list -R "$repo" --state open --json number,labels --limit 100 2>/dev/null || true)
    if [ -n "$issues_json" ]; then
      local count
      count=$(echo "$issues_json" | jq 'length' 2>/dev/null || echo "0")
      total_issues=$((total_issues + count))
    fi
    echo ""
  done
  log "=== Issue labels report complete ==="
  log "Total open issues: $total_issues"
  RET_ISSUE_LABELS_TOTAL="$total_issues"
}

cmd_prs_assigner_report() {
  log "=== GitHub Fleet PRS Assigner Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local open_prs
  open_prs=$(gh search prs --state open --limit 100 --json number,repository,assignees,title --jq '.[] | select(.repository.owner.login == "itsdarklikehell") | "\(.number)|\(.repository.nameWithOwner)|\(.assignees | map(.login) | join(","))//\(.title)"' 2>/dev/null || true)
  if [ -z "$open_prs" ]; then log "No open PRs found"; return; fi
  local unassigned=0; local assigned=0
  echo "$open_prs" | while IFS='|' read -r num repo assignees title; do
    [ -z "$num" ] && continue
    if [ -z "$assignees" ] || [ "$assignees" = "null" ]; then
      log "  #$num in $repo: NO ASSIGNEE"
    else
      log "  #$num in $repo: ASSIGNED to $assignees"
    fi
  done
  log "=== PRS assigner report complete ==="
  RET_PRS_ASSIGNED="$assigned"
  RET_PRS_UNASSIGNED="$unassigned"
}

cmd_repo_popularity_report() {
  log "=== GitHub Fleet Repo Popularity Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local ranking
  ranking=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner,stargazerCount,visibility --jq '.[] | "\(.stargazerCount)|\(.nameWithOwner)|\(.visibility)"' 2>/dev/null | grep -v '^$' | sort -t'|' -k1 -rn | head -10 || true)
  if [ -z "$ranking" ]; then log "No repos found"; return; fi
  log "  Top 10 by stars:"
  echo "$ranking" | while IFS='|' read -r stars name visibility; do
    [ -z "$name" ] && continue
    log "    ${stars} stars  ${name} (${visibility})"
  done
  log "=== Repo popularity report complete ==="
}

cmd_repository_topics_report() {
  log "=== GitHub Fleet Repository Topics Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner,repositoryTopics --jq '.[] | "\(.nameWithOwner)|\(.repositoryTopics | map(.name) | join(","))"' 2>/dev/null | grep -v '^$' || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local unique_topics=""
  echo "$repos" | while IFS='|' read -r name topics; do
    [ -z "$name" ] && continue
    if [ -n "$topics" ] && [ "$topics" != "null" ]; then
      log "  $name: $topics"
      unique_topics+="$topics"$'\n'
    fi
  done
  local unique_count
  unique_count=$(echo "$unique_topics" | sort -u | grep -v '^$' | wc -l | tr -d ' ')
  log "=== Repository topics report complete ==="
  log "Unique topics across all repos: $unique_count"
  RET_REPO_TOPICS_UNIQUE="$unique_count"
}

cmd_repo_traffic_report() {
  log "=== GitHub Fleet Repo Traffic Report ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | grep -v '^$' || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_views=0; local total_clones=0; local repos_with_traffic=0
  for repo in $repos; do
    local views clones
    views=$(gh api "repos/$repo/traffic/views" --jq '.views | length' 2>/dev/null || echo "0")
    views=$(echo "$views" | grep -oE '^[0-9]+$' || echo "0")
    clones=$(gh api "repos/$repo/traffic/clones" --jq '.clones | length' 2>/dev/null || echo "0")
    clones=$(echo "$clones" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$views" != "0" ] || [ "$clones" != "0" ]; then
      ((repos_with_traffic++)) || true
      total_views=$((total_views + views))
      total_clones=$((total_clones + clones))
      log "  $repo: ${views} views | ${clones} clones"
    fi
    echo ""
  done
  log "=== Repo traffic report complete ==="
  log "Repos with traffic: $repos_with_traffic"
  log "Total views: $total_views | Total clones: $total_clones"
  RET_TRAFFIC_VIEWS_REPORT="$total_views"
  RET_TRAFFIC_CLONES_REPORT="$total_clones"
  RET_TRAFFIC_REPOS_REPORT="$repos_with_traffic"
}


cmd_pr_review_auto() {
  log "=== PR Review Auto ==="
  local reviewed=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local prs
    prs=$(gh pr list --repo "${org}/${repo}" --state open --json number,title,author --jq '.[] | "\(.number)|\(.title)|@\(.author.login)"' 2>/dev/null || true)
    if [ -n "$prs" ]; then
      while IFS='|' read -r num title author; do
        [ -z "$num" ] && continue
        log "  PR #$num: $title ($author)"
        # Check of er al een review is
        local reviews
        reviews=$(gh api "repos/${org}/${repo}/pulls/$num/reviews" --jq 'length' 2>/dev/null || echo "0")
        if [ "$reviews" = "0" ]; then
          log "    → Geen review, toevoegen..."
          gh pr review "${org}/${repo}#${num}" --approve --body "✅ Auto-approved by GitHub Fleet Manager" 2>/dev/null && ((reviewed++)) || true
        fi
      done <<< "$prs"
    fi
  done
  log "=== PR Review Auto complete: $reviewed PRs reviewed ==="
}

# ===================== ISSUE TRIAGE AUTO =====================
cmd_issue_triage_auto() {
  log "=== Issue Triage Auto ==="
  local triaged=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    local issues
    issues=$(gh issue list --repo "${org}/${repo}" --state open --json number,title,labels --jq '.[] | select(.labels | length == 0) | "\(.number)|\(.title)"' 2>/dev/null || true)
    if [ -n "$issues" ]; then
      while IFS='|' read -r num title; do
        [ -z "$num" ] && continue
        log "  Issue #$num: $title"
        # Bepaal labels op basis van titel
        local labels=""
        if echo "$title" | grep -qiE "bug|fix|error|crash|broken"; then
          labels="bug"
        elif echo "$title" | grep -qiE "feature|enhancement|add|new"; then
          labels="enhancement"
        elif echo "$title" | grep -qiE "doc|readme|guide|tutorial"; then
          labels="documentation"
        elif echo "$title" | grep -qiE "question|help|how"; then
          labels="question"
        fi
        if [ -n "$labels" ]; then
          gh issue edit "${org}/${repo}#$num" --add-label "$labels" 2>/dev/null && ((triaged++)) || true
        fi
      done <<< "$issues"
    fi
  done
  log "=== Issue Triage Auto complete: $triaged issues triaged ==="
}

# ===================== DEPENDENCY UPDATE PR =====================
cmd_dependency_update_pr() {
  log "=== Dependency Update PR ==="
  local prs_created=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    cd "$repo_dir"
    if [ -f "package.json" ]; then
      local outdated
      outdated=$(npm outdated --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for pkg, info in data.items():
        if info.get('current') != info.get('latest'):
            print(f\"{pkg}:{info.get('current')}:{info.get('latest')}\")
except: pass
" 2>/dev/null || true)
      if [ -n "$outdated" ]; then
        log "  $repo: outdated npm deps"
        while IFS=':' read -r pkg current latest; do
          [ -z "$pkg" ] && continue
          log "    $pkg: $current → $latest"
          # Maak branch en PR
          local branch="deps/update-$pkg"
          git checkout -b "$branch" 2>/dev/null || true
          npm install "$pkg@latest" 2>/dev/null || true
          git add package.json package-lock.json 2>/dev/null || true
          git commit -m "chore(deps): update $pkg to $latest" 2>/dev/null || true
          git push origin "$branch" 2>/dev/null || true
          gh pr create --repo "${org}/${repo}" --base main --head "$branch" --title "chore(deps): update $pkg to $latest" --body "Automated dependency update by GitHub Fleet Manager." 2>/dev/null && ((prs_created++)) || true
          git checkout main 2>/dev/null || true
        done <<< "$outdated"
      fi
    fi
    cd - > /dev/null
  done
  log "=== Dependency Update PR complete: $prs_created PRs created ==="
}

# ===================== RELEASE AUTO =====================
cmd_release_auto() {
  log "=== Release Auto ==="
  local releases_created=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    cd "$repo_dir"
    # Check of er nieuwe commits zijn sinds laatste release
    local last_release
    last_release=$(gh release list --repo "${org}/${repo}" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "")
    local commits_since=0
    if [ -n "$last_release" ]; then
      commits_since=$(git rev-list --count "${last_release}..HEAD" 2>/dev/null || echo "0")
    else
      commits_since=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    fi
    if [ "$commits_since" -gt 10 ]; then
      log "  $repo: $commits_since commits sinds laatste release"
      # Maak nieuwe release
      local new_tag="v$(date +%Y.%m.%d)"
      local release_notes=$(git log --pretty=format:"%s" -10 2>/dev/null || echo "")
      gh release create "$new_tag" --repo "${org}/${repo}" --title "Release $new_tag" --notes "$release_notes" 2>/dev/null && ((releases_created++)) || true
    fi
    cd - > /dev/null
  done
  log "=== Release Auto complete: $releases_created releases created ==="
}

# ===================== SECURITY SCAN AUTO =====================
cmd_security_scan_auto() {
  log "=== Security Scan Auto ==="
  local issues_found=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    # Check op secrets in code
    local secrets
    secrets=$(grep -r "API_KEY\|SECRET\|PASSWORD\|TOKEN" "$repo_dir" --include="*.py" --include="*.js" --include="*.ts" --include="*.json" 2>/dev/null | grep -v "node_modules" | grep -v ".git" | head -5 || true)
    if [ -n "$secrets" ]; then
      log "  ⚠️ $repo: mogelijke secrets gevonden"
      ((issues_found++)) || true
    fi
  done
  log "=== Security Scan Auto complete: $issues_found repos met mogelijke secrets ==="
}

# ===================== CODE QUALITY AUTO =====================
cmd_code_quality_auto() {
  log "=== Code Quality Auto ==="
  local issues_found=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    cd "$repo_dir"
    # Check op TODO/FIXME/HACK
    local todos
    todos=$(grep -r "TODO\|FIXME\|HACK\|XXX" . --include="*.py" --include="*.js" --include="*.ts" 2>/dev/null | grep -v "node_modules" | grep -v ".git" | wc -l || echo "0")
    if [ "$todos" -gt 0 ]; then
      log "  $repo: $todos TODO/FIXME/HACK gevonden"
      ((issues_found++)) || true
    fi
    cd - > /dev/null
  done
  log "=== Code Quality Auto complete: $issues_found repos met TODOs ==="
}

# ===================== DOCUMENTATION AUTO =====================
cmd_documentation_auto() {
  log "=== Documentation Auto ==="
  local docs_updated=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    cd "$repo_dir"
    # Check of README bestaat
    if [ ! -f "README.md" ]; then
      log "  $repo: README.md ontbijt, aanmaken..."
      cat > README.md << EOF
# $repo

## Installatie

\`\`\`bash
git clone https://github.com/${org}/${repo}.git
cd $repo
\`\`\`

## Gebruik

Zie de documentatie voor meer informatie.

## Bijdragen

Zie [CONTRIBUTING.md](CONTRIBUTING.md) voor richtlijnen.

## Licentie

Zie [LICENSE](LICENSE) voor details.
EOF
      git add README.md
      git commit -m "docs: add README.md" 2>/dev/null || true
      git push origin HEAD 2>/dev/null || true
      ((docs_updated++)) || true
    fi
    cd - > /dev/null
  done
  log "=== Documentation Auto complete: $docs_updated READMEs aangemaakt ==="
}

# ===================== CHANGELOG AUTO =====================
cmd_changelog_auto() {
  log "=== Changelog Auto ==="
  local changelogs_updated=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    cd "$repo_dir"
    # Genereer changelog uit commits
    local changelog=$(git log --pretty=format:"* %s (%h)" -20 2>/dev/null || echo "")
    if [ -n "$changelog" ]; then
      cat > CHANGELOG.md << EOF
# Changelog

## $(date +%Y-%m-%d)

$changelog
EOF
      git add CHANGELOG.md
      git commit -m "docs: update CHANGELOG.md" 2>/dev/null || true
      git push origin HEAD 2>/dev/null || true
      ((changelogs_updated++)) || true
    fi
    cd - > /dev/null
  done
  log "=== Changelog Auto complete: $changelogs_updated changelogs geüpdatet ==="
}

# ===================== LABEL MANAGEMENT AUTO =====================
cmd_label_management_auto() {
  log "=== Label Management Auto ==="
  local labels_managed=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_token "$repo_dir"); set_repo_token "$org"
    # Standaard labels aanmaken
    local standard_labels=("bug" "enhancement" "documentation" "question" "good first issue" "help wanted" "wontfix" "duplicate" "invalid")
    for label in "${standard_labels[@]}"; do
      gh label create "$label" --repo "${org}/${repo}" --color "ededed" 2>/dev/null && ((labels_managed++)) || true
    done
  done
  log "=== Label Management Auto complete: $labels_managed labels aangemaakt ==="
}

# ===================== BRANCH CLEANUP AUTO =====================
cmd_branch_cleanup_auto() {
  log "=== Branch Cleanup Auto ==="
  local branches_deleted=0
  for repo_dir in "$REPOS_DIR"/*/; do
    [ -d "$repo_dir/.git" ] || continue
    repo=$(basename "$repo_dir")
    local org
    org=$(get_repo_org "$repo_dir"); set_repo_token "$org"
    cd "$repo_dir"
    # Zoek gemerged branches
    local merged_branches
    merged_branches=$(git branch --merged main 2>/dev/null | grep -v "main" | grep -v "master" | grep -v "develop" || true)
    if [ -n "$merged_branches" ]; then
      while read -r branch; do
        [ -z "$branch" ] && continue
        log "  $repo: verwijder gemerged branch $branch"
        git branch -d "$branch" 2>/dev/null && ((branches_deleted++)) || true
      done <<< "$merged_branches"
    fi
    cd - > /dev/null
  done
  log "=== Branch Cleanup Auto complete: $branches_deleted branches verwijderd ==="
}
cmd_self_update() {
  log "=== Self Update ==="
  local fleet_dir="/home/hans/.openclaw/workspace/projects/fleet-manager"
  
  if [ -d "$fleet_dir/.git" ]; then
    cd "$fleet_dir"
    local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    log "  Huidige commit: $current_commit"
    
    # Pull laatste wijzigingen
    git fetch origin main 2>/dev/null || true
    local remote_commit=$(git rev-parse origin/main 2>/dev/null || echo "unknown")
    log "  Remote commit: $remote_commit"
    
    if [ "$current_commit" != "$remote_commit" ]; then
      log "  🔄 Update beschikbaar, pullen..."
      git pull origin main 2>/dev/null || true
      log "  ✓ Update voltooid"
    else
      log "  ✓ Al up-to-date"
    fi
    
    # Update het monolithische script
    if [ -f "$fleet_dir/scripts/generate-monolith.sh" ]; then
      log "  📦 Monolithische script genereren..."
      bash "$fleet_dir/scripts/generate-monolith.sh" 2>/dev/null || true
    fi
  else
    log "  ⚠️ Fleet manager repo niet gevonden"
  fi
  
  log "=== Self Update complete ==="
  send_telegram_message "🔄 *Self Update*\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== SELF MONITOR =====================
cmd_self_monitor() {
  log "=== Self Monitor ==="
  
  # Check script grootte
  local script_size=$(wc -c < "$0" 2>/dev/null || echo "0")
  local script_lines=$(wc -l < "$0" 2>/dev/null || echo "0")
  log "  Script grootte: $script_size bytes, $script_lines regels"
  
  # Check laatste run
  local last_run=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
  local now=$(date +%s)
  local last_run_ago=$(( (now - last_run) / 60 ))
  log "  Laatste run: $last_run_ago minuten geleden"
  
  # Check cron jobs
  local cron_count=$(crontab -l 2>/dev/null | grep -c "github_fleet" || echo "0")
  log "  Cron jobs: $cron_count"
  
  # Check disk usage van logs
  local log_size=$(du -sh "$LOG_FILE" 2>/dev/null | cut -f1 || echo "unknown")
  log "  Log bestand: $log_size"
  
  # Check Telegram
  if [ -n "$TELEGRAM_TOKEN" ]; then
    log "  Telegram: ✓ geconfigureerd"
  else
    log "  Telegram: ✗ niet geconfigureerd"
  fi
  
  # Check GitHub auth
  if gh auth status &>/dev/null; then
    log "  GitHub: ✓ geauthenticeerd"
  else
    log "  GitHub: ✗ niet geauthenticeerd"
  fi
  
  # Alerts
  if [ "$last_run_ago" -gt 120 ]; then
    log "  ⚠️ Laatste run was $last_run_ago minuten geleden"
  fi
  if [ "$script_size" -gt 1000000 ]; then
    log "  ⚠️ Script is groot: $script_size bytes"
  fi
  
  log "=== Self Monitor complete ==="
  send_telegram_message "📊 *Self Monitor*\n\n*Script:* $script_lines regels\n*Cron jobs:* $cron_count\n*Log:* $log_size\n\n📋 Volledig log: $LOG_FILE" || true
}

# ===================== SELF BACKUP =====================
cmd_self_backup() {
  log "=== Self Backup ==="
  
  # Backup het script
  local backup_dir="$HOME/.hermes/backups/fleet-manager"
  mkdir -p "$backup_dir"
  local backup_file="$backup_dir/github_fleet_manager-$(date +%Y%m%d-%H%M%S).sh"
  
  cp "$0" "$backup_file" 2>/dev/null || true
  log "  Script gebackupped naar: $backup_file"
  
  # Backup crontab
  crontab -l > "$backup_dir/crontab-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
  log "  Crontab gebackupped"
  
  # Backup config
  cp "$HOME/.hermes/.env" "$backup_dir/env-$(date +%Y%m%d-%H%M%S).bak" 2>/dev/null || true
  log "  Config gebackupped"
  
  # Oude backups opruimen (laat 10 staan)
  local backup_count=$(ls -1t "$backup_dir"/github_fleet_manager-*.sh 2>/dev/null | wc -l)
  if [ "$backup_count" -gt 10 ]; then
    ls -1t "$backup_dir"/github_fleet_manager-*.sh | tail -n +11 | xargs rm -f
    log "  ⚠️ Oude backups opgeruimd ($backup_count → 10)"
  fi
  
  log "=== Self Backup complete ==="
  send_telegram_message "💾 *Self Backup*\n\n*Backups:* $backup_count\n\n📋 Volledig log: $LOG_FILE" || true
}
case "${1:-status}" in
  status)
    cmd_status_parallel
    ;;
  sync-all)
    cmd_sync_all
    send_telegram_message "🔄 *GitHub Fleet Sync Alle Repos*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  sync-report)
    cmd_sync_report
    send_telegram_message "🔄 *GitHub Fleet Sync Rapport*\n|*Gelijk aan upstream:* ${RET_SYNCED:-0} repos\n|*Met verschil (actie):* ${RET_BEHIND:-0} repos\n|*Geen upstream remote:* ${RET_NO_UPSTREAM:-0} repos\n|*Geen upstream branch:* ${RET_NO_BRANCH:-0} repos\n|*Fouten:* ${RET_ERRORS:-0} repos\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  gource-check)
    log "=== Gource Video Check ==="
    for repo_dir in "$REPOS_DIR"/*/; do
      [ -d "$repo_dir/.git" ] || continue
      repo=$(basename "$repo_dir")
      check_gource "$repo" || true
    done
    ;;
  prs)
    for repo_dir in "$REPOS_DIR"/*/; do
      [ -d "$repo_dir/.git" ] || continue
      check_open_prs "$(basename "$repo_dir")"
    done
    ;;
  api-status)
    cmd_api_status
    send_telegram_message "📡 *GitHub Fleet API Status*\n\n*Totaal:* ${RET_API_TOTAL:-0} repos\n*Public:* ${RET_API_PUBLIC:-0}\n*Privé:* ${RET_API_PRIVATE:-0}\n*Met issues:* ${RET_API_WITH_ISSUES:-0}\n*Met wiki:* ${RET_API_WITH_WIKI:-0}\n*Recent (<30 dgn):* ${RET_API_RECENT:-0}\n\n📋 CSV-rapport: $LOG_FILE.api-status.csv\n📋 Log: $LOG_FILE" || true
    ;;
  issues)
    for repo_dir in "$REPOS_DIR"/*/; do
      [ -d "$repo_dir/.git" ] || continue
      check_open_issues "$(basename "$repo_dir")"
    done
    ;;
  action-monitor)
    cmd_action_monitor
    send_telegram_message "🏷️ *GitHub Fleet Action Monitor*\n\nTotaal gelabelde issues: ${RET_TOTAL_LABELED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  stale-cleanup)
    cmd_stale_cleanup
    send_telegram_message "🧹 *GitHub Fleet Stale Cleanup*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  label-issues)
    cmd_label_issues
    send_telegram_message "🏷️ *GitHub Fleet Label Issues*\n\nLabels toegevoegd: ${RET_LABEL_ISSUES_ADDED:-0} | Verwijderd: ${RET_LABEL_ISSUES_REMOVED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  welcome-contributors)
    cmd_welcome_contributors
    send_telegram_message "👋 *GitHub Fleet Welcome Contributors*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  ci-monitor)
    cmd_ci_monitor
    send_telegram_message "🔍 *GitHub Fleet CI Monitor*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  auto-sync)
    cmd_auto_sync
    send_telegram_message "🔄 *GitHub Fleet Auto-Sync*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  gource-refresh)
    cmd_gource_refresh
    send_telegram_message "🎬 *GitHub Fleet Gource Refresh*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  dep-check)
    cmd_dep_check
    send_telegram_message "📦 *GitHub Fleet Dependency Check*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  security-check)
    cmd_security_check
    send_telegram_message "🔒 *GitHub Fleet Security Check*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  release-draft)
    cmd_release_draft
    send_telegram_message "📝 *GitHub Fleet Release Draft*\n\nDraft releases aangemaakt: ${RET_RELEASE_DRAFT:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  readme-check)
    cmd_readme_check
    send_telegram_message "📖 *GitHub Fleet README Check*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  trigger-gource)
    cmd_gource_trigger
    send_telegram_message "🎬 *GitHub Fleet Gource Trigger*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  health)
    cmd_fleet_health
    send_telegram_message "🏥 *GitHub Fleet Health*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  fork-sync)
    cmd_fork_sync_gh
    send_telegram_message "🔄 *GitHub Fleet Fork Sync (gh)*\n\n*Gesync'd:* ${RET_FORK_SYNC_GH:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  branch-cleanup)
    log "=== Branch Cleanup ==="
    for kr in $CLEAN_BRANCHES_REPOS; do
      [ -z "$kr" ] && continue
      local default_branch
      default_branch=$(gh repo view --repo "$kr" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
      local merged_branches
      merged_branches=$(gh pr list --repo "$kr" --state merged --json headRefName --jq '.[].headRefName' 2>/dev/null | sort -u || true)
      for bname in $merged_branches; do
        [ -z "$bname" ] && continue
        [ "$bname" = "$default_branch" ] && continue
        local protected
        protected=$(gh api "repos/$kr/branches/$bname" --jq '.protected // false' 2>/dev/null || echo "false")
        [ "$protected" = "true" ] && continue
        log "Deleting merged branch $bname from $kr"
        gh api "repos/$kr/git/refs/heads/$bname" --method DELETE 2>/dev/null && log "  ✓ Deleted" || log "  ✗ Failed"
      done
    done
    log "=== Branch cleanup complete ==="
    send_telegram_message "🌿 *GitHub Fleet Branch Cleanup*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  prs-status)
    cmd_prs_status
    send_telegram_message "🔀 *GitHub Fleet PR Status*\n\n*Totaal open PRs:* ${RET_PR_TOTAL_OPEN:-0}\n*Goedgekeurd:* ${RET_PR_APPROVED:-0}\n*Wijzigingen gevraagd:* ${RET_PR_NEEDS_REVIEW:-0}\n*Open (nog geen review):* ${RET_PR_OTHER:-0}\n*Repos met open PRs:* ${RET_PR_REPOS_WITH_PRS:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;

  actions-status)
    cmd_actions_status
    send_telegram_message "⚡ *GitHub Fleet Actions Status*\n\n*Repos met runs:* ${RET_ACTIONS_REPOS_WITH_RUNS:-0}\n*Totale runs (7 dgn):* ${RET_ACTIONS_TOTAL:-0}\n* Geslaagd:* ${RET_ACTIONS_SUCCESS:-0}\n* Gefaald:* ${RET_ACTIONS_FAILED:-0}\n* Cancelled:* ${RET_ACTIONS_CANCELLED:-0}\n* Queued:* ${RET_ACTIONS_QUEUED:-0}\n* Anders:* ${RET_ACTIONS_OTHER:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  ci-rerun)
    cmd_ci_rerun
    send_telegram_message "🔄 *GitHub Fleet CI Rerun*\n\n*Gestart:* ${RET_CI_RERUN:-0} | *Mislukt:* ${RET_CI_RERUN_FAILED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  auto-close)
    cmd_auto_close
    send_telegram_message "🔒 *GitHub Fleet Auto-Close*\n\n*Gesloten:* ${RET_AUTO_CLOSE:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  prs-merge)
    cmd_prs_merge
    send_telegram_message "🔀 *GitHub Fleet PR Auto-Merge*\n\n*Gemerged:* ${RET_PRS_MERGED:-0} draft(s)\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  issue-assign)
    cmd_issue_assign
    send_telegram_message "👤 *GitHub Fleet Issue Assign*\n\nAssignees ingesteld: ${RET_ISSUE_ASSIGNED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  security-audit)
    cmd_security_audit
    send_telegram_message "🚨 *GitHub Fleet Security Audit*\n\n*Totaal alerts:* ${RET_SECURITY_AUDIT:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  fleet-report)
    cmd_fleet_report
    send_telegram_message "🏴‍☠️ *GitHub Fleet Report*\n\n📊 *Samenvatting:*\n- Repos: ${RET_FLEET_REPO_COUNT:-0} (owned: ${RET_FLEET_OWNED:-0}, forks: ${RET_FLEET_FORKS:-0})\n- Open PRs: ${RET_FLEET_OPEN_PRS:-0}\n- Open Issues: ${RET_FLEET_OPEN_ISSUES:-0}\n- Stale PRs: ${RET_FLEET_STALE_PRS:-0}\n- CI failures (key repos): ${RET_FLEET_CI_FAILURES:-0}\n- Security alerts: ${RET_FLEET_SEC_ALERTS:-0}\n- Branch protection missing: ${RET_FLEET_BP_MISSING:-0}\n- Forks te syncen: ${RET_FLEET_FORKS_TO_SYNC:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  branch-protection-fix)
    cmd_branch_protection_fix
    send_telegram_message "🔒 *GitHub Fleet Branch Protection Fix*\n\n*Gefixeerd:* ${RET_BRANCH_PROTECTION_FIXED:-0} repo(s)\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  topic-sync)
    cmd_topic_sync
    send_telegram_message "🏷 *GitHub Fleet Topic Sync*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  topic-cleanup)
    cmd_topic_cleanup
    send_telegram_message "🧹 *GitHub Fleet Topic Cleanup*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  release-asset-check)
    cmd_release_asset_check
    send_telegram_message "📦 *GitHub Fleet Release Asset Check*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  branch-protection-audit)
    cmd_branch_protection_audit
    send_telegram_message "🔒 *GitHub Fleet Branch Protection Audit*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  disabled-workflows-audit)
    cmd_disabled_workflows_audit
    send_telegram_message "⚙ *GitHub Fleet Disabled Workflows Audit*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  environments-audit)
    cmd_environments_audit
    send_telegram_message "🌍 *GitHub Fleet Environments Audit*\n\n*Totaal environments:* ${RET_ENVIRONMENTS:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  super-linter-status)
    cmd_super_linter_status
    send_telegram_message "🔍 *GitHub Fleet Super-Linter Status*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  collaborator-audit)
    cmd_collaborator_audit
    send_telegram_message "👥 *GitHub Fleet Collaborator Audit*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  ranking)
    cmd_ranking
    send_telegram_message "🏆 *GitHub Fleet Ranking*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  repo-features-audit)
    cmd_repo_features_audit
    send_telegram_message "🔧 *GitHub Fleet Repo Features Audit*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  topics-audit)
    cmd_topics_audit
    send_telegram_message "🏷 *GitHub Fleet Topics Audit*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  wiki-status)
    cmd_wiki_status
    send_telegram_message "📖 *GitHub Fleet Wiki Status*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  pages-status)
    cmd_pages_status
    send_telegram_message "🌐 *GitHub Fleet Pages Status*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  actions-secrets-audit)
    cmd_actions_secrets_audit
    send_telegram_message "🔑 *GitHub Fleet Actions Secrets Audit*\n\nTotaal secrets: ${RET_ACTIONS_SECRETS:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  workflow-dispatch)
    cmd_workflow_dispatch "$2" "$3" "$4" "${5:-}"
    if [ "${RET_WORKFLOW_DISPATCH:-0}" -eq 1 ]; then
      send_telegram_message "⚡ *GitHub Fleet Workflow Dispatch*\n\nWorkflow $3 ge-triggerd in $2\n\n📋 Volledig log: $LOG_FILE" || true
    else
      send_telegram_message "❌ *GitHub Fleet Workflow Dispatch*\n\nWorkflow $3 in $2 FAILED\n\n📋 Volledig log: $LOG_FILE" || true
    fi
    ;;
  ci-carbon-footprint)
    cmd_ci_carbon_footprint
    send_telegram_message "🌍 *GitHub Fleet CI Carbon Footprint*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  issue-create)
    cmd_issue_create "$2" "$3" "$4"
    ;;
  pr-create)
    cmd_pr_create "$2" "$3" "$4" "$5"
    ;;
  label-add)
    cmd_label_add "$2" "$3" "$4"
    ;;
  comment-add)
    cmd_comment_add "$2" "$3" "$4"
    ;;
  assign-issue)
    cmd_assign_issue "$2" "$3" "$4"
    ;;
  merge-pr)
    cmd_merge_pr "$2" "$3" "$4"
    ;;
  close-issue)
    cmd_close_issue "$2" "$3" "$4"
    ;;
  reopen-issue)
    cmd_reopen_issue "$2" "$3"
    ;;
  pr-age-report)
    cmd_pr_age_report
    send_telegram_message "📊 *GitHub Fleet PR Age Report*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  dependency-api-check)
    cmd_dependency_api_check
    ;;
  release-publish)
    cmd_release_publish
    send_telegram_message "🚀 *GitHub Fleet Release Publish*\n\n*Gepubliceerd:* ${RET_PUBLISHED:-0} draft(s)\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  issue-create-from-template)
    cmd_issue_create_from_template
    ;;
  branch-naming-check)
    cmd_branch_naming_check
    ;;
  review-request-auto)
    cmd_review_request_auto
    ;;
  dependabot-auto-actions)
    cmd_dependabot_auto_actions
    ;;
  prs-merge-squash)
    cmd_prs_merge_squash
    ;;

  prs-label-by-size)
    cmd_label_prs_by_size
    send_telegram_message "📏 *GitHub Fleet PR Labels (Size)*\\n\\n*Gelabeld:* ${RET_LABELED_BY_SIZE:-0} PR(s)\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  pr-create-auto)
    cmd_pr_create_auto
    ;;

  auto-assign-prs)
    cmd_auto_assign_prs
    ;;
  label-prs-by-files)
    cmd_label_prs_by_files
    ;;
  close-stale-duplicates)
    cmd_close_stale_duplicates
    ;;
  merged-pr-digest)
    cmd_merged_pr_digest
    ;;
  star-fork-trends)
    cmd_star_fork_trends
    ;;

  prs-label-auto)
    cmd_prs_label_auto
    send_telegram_message "🏷️ *GitHub Fleet PRs Label Auto*\n\n*PRs gelabeld:* ${RET_PRS_LABELED_AUTO:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  auto-triage-issues)
    cmd_auto_triage_issues
    send_telegram_message "🔍 *GitHub Fleet Auto Triage Issues*\n\n*Issues getriaged:* ${RET_AUTO_TRIAGE_ISSUES:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  stale-pr-reminder)
    cmd_stale_pr_reminder
    send_telegram_message "⏰ *GitHub Fleet Stale PR Reminder*\n\n*PRs herinnerd:* ${RET_STALE_PR_REMINDED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  release-notes)
    cmd_release_notes
    send_telegram_message "📝 *GitHub Fleet Release Notes*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  dependabot-auto-merge)
    cmd_dependabot_auto_merge
    send_telegram_message "🔀 *GitHub Fleet Dependabot Auto-Merge*\n\n*Dependabot PRs gemerged:* ${RET_DEP_AUTO_MERGE:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  codeowners-audit)
    cmd_codeowners_audit
    ;;
  contrib-license-audit)
    cmd_contrib_license_audit
    ;;
  pr-size-monitor)
    cmd_pr_size_monitor
    ;;
  commit-activity)
    cmd_commit_activity
    ;;
  release-notes-enhanced)
    cmd_release_notes_enhanced
    ;;
  pr-review-time)
    cmd_pr_review_time
    send_telegram_message "⏱ *GitHub Fleet PR Review Time*\n\n*Zeer lang open zonder review:* ${RET_PR_STALE_REVIEW:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  repo-description-audit)
    cmd_repo_description_audit
    ;;
  deploy-key-audit)
    cmd_deploy_key_audit
    ;;
  scheduled-workflow-monitor)
    cmd_scheduled_workflow_monitor
    ;;

  tag-suggest)
    cmd_tag_suggest
    ;;
  branch-rename)
    cmd_branch_rename
    ;;
  repo-archive|repo-archive-inactive)
    cmd_repo_archive_inactive
    send_telegram_message "🗄 *GitHub Fleet Repo Archive*
Zie log voor details

📋 Volledig log: $LOG_FILE" || true
    ;;
  repo-sunset-report)
    cmd_repo_sunset_report
    send_telegram_message "📊 *GitHub Fleet Repo Sunset Report*
Zie log voor details

📋 Volledig log: $LOG_FILE" || true
    ;;
  commits-lint)
    cmd_commits_lint
    ;;
  auto-pr-comment)
    cmd_auto_pr_comment
    ;;

  dep-update-prs)
    cmd_dep_update_prs
    ;;
  discussions-manage)
    cmd_discussions_manage
    ;;
  repo-traffic)
    cmd_repo_traffic
    ;;


  release-asset-upload)
    cmd_release_asset_upload
    ;;
  stale-collaborator-cleanup)
    cmd_stale_collaborator_cleanup
    ;;
  webhook-inspect)
    cmd_webhook_inspect
    ;;
  project-board-sync)
    cmd_project_board_sync
    ;;
  repo-transfer-detect)
    cmd_repo_transfer_detect
    ;;
  license-org-report)
    cmd_license_org_report
    ;;



  dep-check-enhanced)
    cmd_dep_check_enhanced
    ;;
  release-notes-from-templates)
    cmd_release_notes_from_templates
    ;;
  issue-create)
    cmd_issue_create "$@"
    ;;
  pr-create)
    cmd_pr_create "$@"
    ;;
  label-add)
    cmd_label_add "$@"
    ;;
  comment-add)
    cmd_comment_add "$@"
    ;;
  assign-issue)
    cmd_assign_issue "$@"
    ;;
  merge-pr)
    cmd_merge_pr "$@"
    ;;
  close-issue)
    cmd_close_issue "$@"
    ;;
  reopen-issue)
    cmd_reopen_issue "$@"
    ;;
  fleet-health)
    cmd_fleet_health
    send_telegram_message "🏥 *GitHub Fleet Health*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  fork-sync-gh)
    cmd_fork_sync_gh
    send_telegram_message "🔄 *GitHub Fleet Fork Sync (gh)*\\n\\n*Gesync'd:* ${RET_FORK_SYNC_GH:-0}\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  gource-trigger)
    cmd_gource_trigger
    send_telegram_message "🎬 *GitHub Fleet Gource Trigger*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  topic-audit)
    cmd_topics_audit
    send_telegram_message "🏷 *GitHub Fleet Topics Audit*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  actions-audit)
    cmd_actions_audit
    send_telegram_message "⚡ *GitHub Fleet Actions Audit*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  actions-scheduled-report)
    cmd_actions_scheduled_report
    send_telegram_message "⏰ *GitHub Fleet Actions Scheduled Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  collaborator-report)
    cmd_collaborator_report
    send_telegram_message "👥 *GitHub Fleet Collaborator Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  creation-time-report)
    cmd_creation_time_report
    send_telegram_message "📅 *GitHub Fleet Creation Time Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  deptry-monitor)
    cmd_deptry_monitor
    send_telegram_message "📦 *GitHub Fleet Deptry Monitor*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  gource-repo-report)
    cmd_gource_repo_report
    send_telegram_message "🎬 *GitHub Fleet Gource Repo Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  issue-labels-report)
    cmd_issue_labels_report
    send_telegram_message "🏷 *GitHub Fleet Issue Labels Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  prs-assigner-report)
    cmd_prs_assigner_report
    send_telegram_message "🔀 *GitHub Fleet PRS Assigner Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  repo-popularity-report)
    cmd_repo_popularity_report
    send_telegram_message "📊 *GitHub Fleet Repo Popularity Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  repository-topics-report)
    cmd_repository_topics_report
    send_telegram_message "🏷 *GitHub Fleet Repository Topics Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  repo-traffic-report)
    cmd_repo_traffic_report
    send_telegram_message "📊 *GitHub Fleet Repo Traffic Report*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  network-scan)
    cmd_network_scan
    send_telegram_message "🌐 *Network Scan*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  system-health)
    cmd_system_health
    send_telegram_message "🖥️ *System Health*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  service-check)
    cmd_service_check
    send_telegram_message "🔌 *Service Check*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  log-monitor)
    cmd_log_monitor
    send_telegram_message "📋 *Log Monitor*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  security-audit)
    cmd_security_audit
    send_telegram_message "🔒 *Security Audit*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  backup-verify)
    cmd_backup_verify
    send_telegram_message "💾 *Backup Verify*\n\nZie log voor details\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  pr-review-auto)
    cmd_pr_review_auto
    send_telegram_message "👀 *PR Review Auto*\n\n*Reviewed:* ${REVIEWED:-0} PRs\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  issue-triage-auto)
    cmd_issue_triage_auto
    send_telegram_message "🏷️ *Issue Triage Auto*\n\n*Triaged:* ${TRIAGED:-0} issues\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  dependency-update-pr)
    cmd_dependency_update_pr
    send_telegram_message "📦 *Dependency Update PR*\n\n*PRs aangemaakt:* ${PRS_CREATED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  release-auto)
    cmd_release_auto
    send_telegram_message "🚀 *Release Auto*\n\n*Releases aangemaakt:* ${RELEASES_CREATED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  security-scan-auto)
    cmd_security_scan_auto
    send_telegram_message "🔒 *Security Scan Auto*\n\n*Repos met mogelijke secrets:* ${ISSUES_FOUND:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  code-quality-auto)
    cmd_code_quality_auto
    send_telegram_message "📝 *Code Quality Auto*\n\n*Repos met TODOs:* ${ISSUES_FOUND:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  documentation-auto)
    cmd_documentation_auto
    send_telegram_message "📖 *Documentation Auto*\n\n*READMEs aangemaakt:* ${DOCS_UPDATED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  changelog-auto)
    cmd_changelog_auto
    send_telegram_message "📋 *Changelog Auto*\n\n*Changelogs geüpdatet:* ${CHANGELOGS_UPDATED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  label-management-auto)
    cmd_label_management_auto
    send_telegram_message "🏷️ *Label Management Auto*\n\n*Labels aangemaakt:* ${LABELS_MANAGED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  branch-cleanup-auto)
    cmd_branch_cleanup_auto
    send_telegram_message "🌿 *Branch Cleanup Auto*\n\n*Branches verwijderd:* ${BRANCHES_DELETED:-0}\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  self-update)
    cmd_self_update
    send_telegram_message "🔄 *Self Update*\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  self-monitor)
    cmd_self_monitor
    send_telegram_message "📊 *Self Monitor*\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  self-backup)
    cmd_self_backup
    send_telegram_message "💾 *Self Backup*\n\n📋 Volledig log: $LOG_FILE" || true
    ;;
  ci-failure-check)
    cmd_ci_failure_check
    send_telegram_message "🔴 *GitHub Fleet CI Failure Check*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  security-audit-weekly)
    cmd_security_audit_weekly
    send_telegram_message "🔒 *GitHub Fleet Weekly Security Audit*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  release-notes-monthly)
    cmd_release_notes_monthly
    send_telegram_message "📝 *GitHub Fleet Monthly Release Notes*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  stale-pr-cleanup)
    cmd_stale_pr_cleanup
    send_telegram_message "🧹 *GitHub Fleet Stale PR Cleanup*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  dependency-update-check)
    cmd_dependency_update_check
    send_telegram_message "📦 *GitHub Fleet Dependency Update Check*\\n\\nZie log voor details\\n\\n📋 Volledig log: $LOG_FILE" || true
    ;;
  *)
    echo "Usage: $0 {status|sync-all|sync-report|api-status|gource-check|prs|issues|action-monitor|
    stale-cleanup|label-issues|welcome-contributors|ci-monitor|auto-sync|
    gource-refresh|dep-check|dep-check-enhanced|security-check|release-draft|readme-check|
    trigger-gource|health|fork-sync|branch-cleanup|
    prs-status|actions-status|ci-rerun|auto-close|prs-merge|issue-assign|
    security-audit|fleet-report|branch-protection-fix|topic-sync|topic-cleanup|
    release-asset-check|branch-protection-audit|disabled-workflows-audit|
    environments-audit|super-linter-status|collaborator-audit|ranking|
    repo-features-audit|topics-audit|wiki-status|pages-status|
    actions-secrets-audit|workflow-dispatch|dependency-api-check|release-publish|
    auto-assign-prs|label-prs-by-files|close-stale-duplicates|merged-pr-digest|star-fork-trends|issue-create-from-template|branch-naming-check|review-request-auto|dependabot-auto-actions|prs-merge-squash|pr-create-auto|prs-label-auto|auto-triage-issues|stale-pr-reminder|release-notes|dependabot-auto-merge|codeowners-audit|contrib-license-audit|pr-size-monitor|commit-activity|release-notes-enhanced|pr-review-time|repo-description-audit|deploy-key-audit|scheduled-workflow-monitor|tag-suggest|branch-rename|repo-archive|repo-archive-inactive|commits-lint|auto-pr-comment|dep-update-prs|discussions-manage|repo-traffic|release-asset-upload|stale-collaborator-cleanup|webhook-inspect|project-board-sync|repo-transfer-detect|license-org-report|release-notes-from-templates|ci-carbon-footprint|ci-failure-check|security-audit-weekly|release-notes-monthly|stale-pr-cleanup|dependency-update-check}" >&2
    exit 1
    ;;
esac
fi

# ===================== CI FAILURE CHECK (dagelijks) =====================
# Controleert alle open PRs op failed CI checks en stuurt een rapport
cmd_ci_failure_check() {
  log "=== CI Failure Check (dagelijks) ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_failures=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local org
    org=$(echo "$repo" | cut -d/ -f1); set_repo_token "$org"
    local open_prs
    open_prs=$(gh pr list --repo "$repo" --state open --json number,title,headRefName,url \
      --jq '.[] | "#\(.number): \(.title) (\(.headRefName))"' 2>/dev/null || true)
    if [ -n "$open_prs" ]; then
      while IFS= read -r pr_line; do
        [ -z "$pr_line" ] && continue
        local pr_number
        pr_number=$(echo "$pr_line" | grep -oP '#\K[0-9]+' || echo "")
        [ -z "$pr_number" ] && continue
        local pr_title
        pr_title=$(echo "$pr_line" | sed 's/^#[0-9]*: //' | sed 's/ (.*//')
        local checks
        checks=$(gh api "repos/$repo/pulls/$pr_number/checks" --jq '[.[] | "\(.name): \(.status) \(.conclusion // "none")"] | join("\n")' 2>/dev/null || echo "")
        if echo "$checks" | grep -qE "failure|neutral"; then
          local failed_checks
          failed_checks=$(echo "$checks" | grep -E "failure|neutral" || true)
          log "  ❌ PR #$pr_number in $repo: $pr_title"
          log "    Failed: $failed_checks"
          total_failures=$((total_failures + 1))
        fi
      done <<< "$open_prs"
    fi
  done <<< "$repos"
  log "=== CI Failure Check complete: $total_failures failed PR(s) ==="
  RET_CI_FAILURES="$total_failures"
}

# ===================== SECURITY AUDIT WEEKLY (wekelijks) =====================
# Uitgebreide security audit: dependabot, secret scanning, code scanning, branch protection
cmd_security_audit_weekly() {
  log "=== Weekly Security Audit ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local total_alerts=0; local repos_with_alerts=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local org
    org=$(echo "$repo" | cut -d/ -f1); set_repo_token "$org"
    local repo_alerts=0
    # Dependabot alerts
    local dep_count
    dep_count=$(gh api "repos/$repo/dependabot/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    dep_count=$(echo "$dep_count" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$dep_count" -gt 0 ] 2>/dev/null; then
      log "  🚨 $repo: $dep_count dependabot alert(s)"
      repo_alerts=$((repo_alerts + dep_count))
    fi
    # Secret scanning alerts
    local sec_count
    sec_count=$(gh api "repos/$repo/secret-scanning/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    sec_count=$(echo "$sec_count" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$sec_count" -gt 0 ] 2>/dev/null; then
      log "  🔑 $repo: $sec_count secret scanning alert(s)"
      repo_alerts=$((repo_alerts + sec_count))
    fi
    # Code scanning alerts
    local code_count
    code_count=$(gh api "repos/$repo/code-scanning/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    code_count=$(echo "$code_count" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$code_count" -gt 0 ] 2>/dev/null; then
      log "  🛡 $repo: $code_count code scanning alert(s)"
      repo_alerts=$((repo_alerts + code_count))
    fi
    if [ "$repo_alerts" -gt 0 ]; then
      repos_with_alerts=$((repos_with_alerts + 1))
      total_alerts=$((total_alerts + repo_alerts))
    fi
  done <<< "$repos"
  log "=== Weekly Security Audit complete ==="
  log "Repos with alerts: $repos_with_alerts | Total alerts: $total_alerts"
  RET_SECURITY_WEEKLY_ALERTS="$total_alerts"
}

# ===================== RELEASE NOTES MONTHLY (maandelijks) =====================
# Controleert op nieuwe releases en genereert release notes
cmd_release_notes_monthly() {
  log "=== Monthly Release Notes Check ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local repos_with_releases=0; local total_releases=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local org
    org=$(echo "$repo" | cut -d/ -f1); set_repo_token "$org"
    local releases
    releases=$(gh api "repos/$repo/releases?per_page=5" --jq '.[] | "\(.tag_name) (\(.published_at[0:10]))"' 2>/dev/null || true)
    if [ -n "$releases" ]; then
      local count
      count=$(echo "$releases" | grep -c . || echo "0")
      repos_with_releases=$((repos_with_releases + 1))
      total_releases=$((total_releases + count))
      log "  📦 $repo: $count release(s)"
      echo "$releases" | while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        log "    $rel"
      done
    fi
  done <<< "$repos"
  log "=== Monthly Release Notes Check complete ==="
  log "Repos with releases: $repos_with_releases | Total releases: $total_releases"
  RET_RELEASE_NOTES_COUNT="$total_releases"
}

# ===================== STALE PR CLEANUP =====================
# Identificeert en rapporteert stale PRs (open > 30 dagen zonder activiteit)
cmd_stale_pr_cleanup() {
  log "=== Stale PR Cleanup ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local stale_prs=0; local now_epoch
  now_epoch=$(date +%s)
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local org
    org=$(echo "$repo" | cut -d/ -f1); set_repo_token "$org"
    local open_prs
    open_prs=$(gh pr list --repo "$repo" --state open --json number,title,createdAt,updatedAt,author \
      --jq '.[] | "\(.number)|\(.title)|\(.createdAt)|\(.updatedAt)|\(.author.login)"' 2>/dev/null || true)
    if [ -n "$open_prs" ]; then
      while IFS='|' read -r pr_number pr_title pr_created pr_updated pr_author; do
        [ -z "$pr_number" ] && continue
        local updated_epoch
        updated_epoch=$(date -d "$pr_updated" +%s 2>/dev/null || echo "$now_epoch")
        local days_inactive=$(( (now_epoch - updated_epoch) / 86400 ))
        if [ "$days_inactive" -gt "${STALE_CLOSE_DAYS:-30}" ]; then
          log "  ⏰ Stale PR #$pr_number in $repo: $pr_title (inactief $days_inactive dagen, @$pr_author)"
          stale_prs=$((stale_prs + 1))
        fi
      done <<< "$open_prs"
    fi
  done <<< "$repos"
  log "=== Stale PR Cleanup complete: $stale_prs stale PR(s) ==="
  RET_STALE_PR_CLEANUP="$stale_prs"
}

# ===================== DEPENDENCY UPDATE CHECK =====================
# Controleert op outdated dependencies via Dependabot en package.json/requirements.txt
cmd_dependency_update_check() {
  log "=== Dependency Update Check ==="
  local GH_USER
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "itsdarklikehell")
  local repos
  repos=$(gh repo list "$GH_USER" --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true)
  if [ -z "$repos" ]; then log "No repos found"; return; fi
  local repos_with_updates=0; local total_updates=0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local org
    org=$(echo "$repo" | cut -d/ -f1); set_repo_token "$org"
    local dep_count=0
    # Check Dependabot alerts als proxy voor dependency updates
    dep_count=$(gh api "repos/$repo/dependabot/alerts?state=open" --jq '. | length' 2>/dev/null || echo "0")
    dep_count=$(echo "$dep_count" | grep -oE '^[0-9]+$' || echo "0")
    if [ "$dep_count" -gt 0 ] 2>/dev/null; then
      log "  📦 $repo: $dep_count dependency update(s) beschikbaar"
      repos_with_updates=$((repos_with_updates + 1))
      total_updates=$((total_updates + dep_count))
    fi
  done <<< "$repos"
  log "=== Dependency Update Check complete ==="
  log "Repos with updates: $repos_with_updates | Total updates: $total_updates"
  RET_DEPENDENCY_UPDATES="$total_updates"
}

# ===================== GENERATIONELLE COMMANDO'S (standalone helpers) =====================

cmd_issue_create() {
  [ -z "${1:-}" ] && { echo "Usage: $0 issue-create <repo> <title> [body]"; return 1; }
  local repo="$1" title="$2" body="${3:-}"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  if gh issue create --repo "$repo" --title "$title" --body "$body" 2>/dev/null; then
    log "  ✓ Issue aangemaakt in $repo: $title"
    RET_ISSUE_CREATED=1
    send_telegram_message "📝 *GitHub Fleet — Issue Aangemaakt*\n\n*Repo:* \`$repo\`\n*Titel:* \`$title\`\n\n📋 Volledig log: $LOG_FILE" || true
  else
    log "  ✗ Failed om issue aan te maken in $repo"
    RET_ISSUE_CREATED=0
    send_telegram_message "❌ *GitHub Fleet — Issue Faalde*\n\n*Repo:* \`$repo\`\n*Titel:* \`$title\`\n\n📋 Volledig log: $LOG_FILE" || true
  fi
}

cmd_pr_create() {
  [ -z "${1:-}" ] && { echo "Usage: $0 pr-create <repo> <title> [body] [head_branch]"; return 1; }
  local repo="$1" title="$2" body="${3:-}" head="${4:-feature/pr-auto}"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  local default_branch
  default_branch=$(gh repo view --repo "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
  if gh pr create --repo "$repo" --head "$head" --base "$default_branch" --title "$title" --body "$body" 2>/dev/null; then
    log "  ✓ PR aangemaakt in $repo: $title"
    RET_PR_CREATED=1
    send_telegram_message "🔀 *GitHub Fleet — PR Aangemaakt*\n\n*Repo:* \`$repo\`\n*Titel:* \`$title\`\n*Branch:* \`$head → $default_branch\`\n\n📋 Volledig log: $LOG_FILE" || true
  else
    log "  ✗ Failed om PR aan te maken in $repo"
    RET_PR_CREATED=0
    send_telegram_message "❌ *GitHub Fleet — PR Faalde*\n\n*Repo:* \`$repo\`\n*Titel:* \`$title\`\n\n📋 Volledig log: $LOG_FILE" || true
  fi
}

cmd_label_add() {
  [ -z "${1:-}" ] && { echo "Usage: $0 label-add <repo> <issue|pr> <number> <labels>"; return 1; }
  local repo="$1" type="$2" number="$3" labels="$4"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  local cmd
  if [ "$type" = "pr" ]; then cmd="gh pr edit"; else cmd="gh issue edit"; fi
  if $cmd "$repo#$number" --add-label "$labels" 2>/dev/null; then
    log "  ✓ Labels toegevoegd aan ${type} #$number in $repo: $labels"
    RET_LABEL_ADDED=1
    send_telegram_message "🏷️ *GitHub Fleet — Labels Toegevoegd*\n\n*${type}:* #$number in \`$repo\`\n*Labels:* \`$labels\`\n\n📋 Volledig log: $LOG_FILE" || true
  else
    log "  ✗ Failed om labels toe te voegen"
    RET_LABEL_ADDED=0
    send_telegram_message "❌ *GitHub Fleet — Labels Faald*\n\n*${type}:* #$number in \`$repo\`\n\n📋 Volledig log: $LOG_FILE" || true
  fi
}

cmd_comment_add() {
  [ -z "${1:-}" ] && { echo "Usage: $0 comment-add <repo> <issue|pr> <number> <body>"; return 1; }
  local repo="$1" type="$2" number="$3" body="$4"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  local rc
  if [ "$type" = "pr" ]; then
    gh pr comment "$repo#$number" --body "$body" 2>/dev/null; rc=$?
  else
    gh issue comment "$repo#$number" --body "$body" 2>/dev/null; rc=$?
  fi
  if [ $rc -eq 0 ]; then
    log "  ✓ Commentaar toegevoegd aan ${type} #$number in $repo"
    RET_COMMENT_ADDED=1
  else
    log "  ✗ Failed om commentaar toe te voegen"
    RET_COMMENT_ADDED=0
  fi
}

cmd_assign_issue() {
  [ -z "${1:-}" ] && { echo "Usage: $0 assign-issue <repo> <issue_number> <assignee>"; return 1; }
  local repo="$1" number="$2" assignee="$3"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  if gh issue edit "$repo#$number" --assignee "$assignee" 2>/dev/null; then
    log "  ✓ Issue #$number toegewezen aan @$assignee in $repo"
    RET_ISSUE_ASSIGNED=1
    send_telegram_message "👤 *GitHub Fleet — Issue Toegewezen*\n\n*Issue:* #$number in \`$repo\`\n*Assignee:* @$assignee\n\n📋 Volledig log: $LOG_FILE" || true
  else
    log "  ✗ Failed om issue toe te wijzen"
    RET_ISSUE_ASSIGNED=0
    send_telegram_message "❌ *GitHub Fleet — Toewijzing Faalde*\n\n*Issue:* #$number in \`$repo\`\n\n📋 Volledig log: $LOG_FILE" || true
  fi
}

cmd_merge_pr() {
  [ -z "${1:-}" ] && { echo "Usage: $0 merge-pr <repo> <pr_number> [method]"; return 1; }
  local repo="$1" number="$2" method="${3:-merge}"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  if gh pr merge "$repo#$number" --$method --delete-branch 2>/dev/null; then
    log "  ✓ PR #$number gemerged in $repo (method: $method)"
    RET_PR_MERGED=1
    send_telegram_message "🔀 *GitHub Fleet — PR Gemerged*\n\n*PR:* #$number in \`$repo\`\n*Method:* \`$method\`\n\n📋 Volledig log: $LOG_FILE" || true
  else
    log "  ✗ Failed om PR #$number te merge-ren"
    RET_PR_MERGED=0
    send_telegram_message "❌ *GitHub Fleet — Merge Faalde*\n\n*PR:* #$number in \`$repo\`\n\n📋 Volledig log: $LOG_FILE" || true
  fi
}

cmd_close_issue() {
  [ -z "${1:-}" ] && { echo "Usage: $0 close-issue <repo> <issue_number> [comment]"; return 1; }
  local repo="$1" number="$2" comment="${3:-This issue is being closed.}"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  local rc
  if [ -n "$comment" ]; then
    gh issue close "$repo#$number" --comment "$comment" 2>/dev/null; rc=$?
  else
    gh issue close "$repo#$number" 2>/dev/null; rc=$?
  fi
  if [ $rc -eq 0 ]; then
    log "  ✓ Issue #$number gesloten in $repo"
    RET_ISSUE_CLOSED=1
    send_telegram_message "🔒 *GitHub Fleet — Issue Gesloten*\n\n*Issue:* #$number in \`$repo\`\n\n📋 Volledig log: $LOG_FILE" || true
  else
    log "  ✗ Failed om issue te sluiten"
    RET_ISSUE_CLOSED=0
  fi
}

cmd_reopen_issue() {
  [ -z "${1:-}" ] && { echo "Usage: $0 reopen-issue <repo> <issue_number>"; return 1; }
  local repo="$1" number="$2"
  local org
  org=$(echo "$repo" | cut -d/ -f1)
  set_repo_token "$org"
  if gh issue reopen "$repo#$number" 2>/dev/null; then
    log "  ✓ Issue #$number heropend in $repo"
    RET_ISSUE_REOPENED=1
    send_telegram_message "🔓 *GitHub Fleet — Issue Heropend*\n\n*Issue:* #$number in \`$repo\`\n\n📋 Volledig log: $LOG_FILE" || true
  else
    log "  ✗ Failed om issue te heropenen"
    RET_ISSUE_REOPENED=0
  fi
}



# ===================== NETWORK SCAN =====================
cmd_network_scan() {
  log "=== Network Scan ==="
  local scan_file="$LOG_FILE.network-scan.json"
  local prev_file="$LOG_FILE.network-scan.prev"
  
  # Scan het netwerk
  nmap -sn 192.168.178.0/24 2>/dev/null | grep "Nmap scan report" | awk '{print $NF}' | tr -d '()' | sort > "$scan_file"
  
  # Vergelijk met vorige scan
  if [ -f "$prev_file" ]; then
    local new_devices=$(comm -13 "$prev_file" "$scan_file" 2>/dev/null || echo "")
    local removed_devices=$(comm -23 "$prev_file" "$scan_file" 2>/dev/null || echo "")
    
    if [ -n "$new_devices" ]; then
      log "  ⚠️ Nieuwe devices: $new_devices"
    fi
    if [ -n "$removed_devices" ]; then
      log "  ⚠️ Verwijderde devices: $removed_devices"
    fi
    if [ -z "$new_devices" ] && [ -z "$removed_devices" ]; then
      log "  ✓ Geen wijzigingen"
    fi
  else
    log "  Eerste scan - baseline opgeslagen"
  fi
  
  cp "$scan_file" "$prev_file"
  log "  Totaal devices: $(wc -l < "$scan_file")"
  log "=== Network scan complete ==="
}

# ===================== SYSTEM HEALTH =====================
cmd_system_health() {
  log "=== System Health Check ==="
  
  # CPU load
  local load=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
  log "  CPU load: $load"
  
  # Memory
  local mem_total=$(free -m | awk '/^Mem:/{print $2}')
  local mem_used=$(free -m | awk '/^Mem:/{print $3}')
  local mem_pct=$((mem_used * 100 / mem_total))
  log "  Memory: ${mem_used}MB / ${mem_total}MB (${mem_pct}%)"
  
  # Disk
  local disk_usage=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
  log "  Disk: ${disk_usage}%"
  
  # Docker
  local docker_running=$(docker ps -q 2>/dev/null | wc -l)
  local docker_total=$(docker ps -aq 2>/dev/null | wc -l)
  log "  Docker: $docker_running / $docker_total containers running"
  
  # Systemd failed units
  local failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
  log "  Failed systemd units: $failed"
  
  # Alerts
  if [ "$mem_pct" -gt 90 ]; then
    log "  ⚠️ Hoog memory gebruik: ${mem_pct}%"
  fi
  if [ "$disk_usage" -gt 90 ]; then
    log "  ⚠️ Volle disk: ${disk_usage}%"
  fi
  if [ "$failed" -gt 0 ]; then
    log "  ⚠️ $failed failed systemd units"
  fi
  
  log "=== System health check complete ==="
}

# ===================== SERVICE CHECK =====================
cmd_service_check() {
  log "=== Service Check ==="
  
  # HTTP services
  declare -A services=(
    ["Heimdall"]="http://192.168.178.51:7990"
    ["Jellyfin"]="http://192.168.178.51:8096"
    ["Pi-hole"]="http://192.168.178.36/admin"
    ["OpenClaw"]="http://192.168.178.62:18800"
    ["Hermes"]="http://192.168.178.94:9119"
    ["PVE"]="https://192.168.178.63:8006"
  )
  
  for name in "${!services[@]}"; do
    local url="${services[$name]}"
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
      log "  ✓ $name: $status"
    else
      log "  ✗ $name: $status"
    fi
  done
  
  # DNS check
  local dns_status=$(dig +short @192.168.178.36 google.com 2>/dev/null | head -1)
  if [ -n "$dns_status" ]; then
    log "  ✓ DNS: $dns_status"
  else
    log "  ✗ DNS: geen antwoord"
  fi
  
  log "=== Service check complete ==="
}

# ===================== LOG MONITOR =====================
cmd_log_monitor() {
  log "=== Log Monitor ==="
  
  # Hermes errors
  local hermes_errors=$(grep -c "ERROR\|CRITICAL" ~/.hermes/logs/*.log 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
  log "  Hermes errors: $hermes_errors"
  
  # System errors
  local sys_errors=$(journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | wc -l)
  log "  System errors (1h): $sys_errors"
  
  # Docker errors
  local docker_errors=$(docker logs --since 1h $(docker ps -q 2>/dev/null) 2>&1 | grep -ci "error\|fatal" || echo "0")
  log "  Docker errors (1h): $docker_errors"
  
  # Alerts
  if [ "$hermes_errors" -gt 10 ]; then
    log "  ⚠️ Veel Hermes errors: $hermes_errors"
  fi
  if [ "$sys_errors" -gt 50 ]; then
    log "  ⚠️ Veel system errors: $sys_errors"
  fi
  
  log "=== Log monitor complete ==="
}

# ===================== SECURITY AUDIT =====================
cmd_security_audit() {
  log "=== Security Audit ==="
  
  # SSL cert expiry
  local certs=(
    "192.168.178.51:443"
    "192.168.178.63:8006"
  )
  
  for cert in "${certs[@]}"; do
    local expiry=$(echo | openssl s_client -connect "$cert" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$expiry" ]; then
      local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
      local now_epoch=$(date +%s)
      local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
      if [ "$days_left" -lt 30 ]; then
        log "  ⚠️ SSL cert $cert: $days_left dagen tot verloop"
      else
        log "  ✓ SSL cert $cert: $days_left dagen"
      fi
    fi
  done
  
  # Open ports op gateway
  local open_ports=$(nmap -p 22,80,443,8080 192.168.178.1 2>/dev/null | grep "open" | wc -l)
  log "  Gateway open ports: $open_ports"
  
  # Failed SSH attempts
  local failed_ssh=$(journalctl -u ssh --since "1 day ago" --no-pager 2>/dev/null | grep -c "Failed password" || echo "0")
  log "  Failed SSH (24h): $failed_ssh"
  
  log "=== Security audit complete ==="
}

# ===================== BACKUP VERIFY =====================
cmd_backup_verify() {
  log "=== Backup Verify ==="
  
  # Synology backups
  local synology_status=$(ssh -o ConnectTimeout=5 root@192.168.178.63 "ls -la /var/lib/vz/dump/ 2>/dev/null | tail -5" 2>/dev/null || echo "Geen toegang")
  log "  PVE backups: $synology_status"
  
  # Config backups
  local config_backup=$(find ~/.hermes -name "*.bak" -mtime -7 2>/dev/null | wc -l)
  log "  Config backups (7d): $config_backup"
  
  # Docker volumes
  local docker_volumes=$(docker volume ls -q 2>/dev/null | wc -l)
  log "  Docker volumes: $docker_volumes"
  
  log "=== Backup verify complete ==="
}

# ===================== PR REVIEW AUTO =====================

# ===================== SELF UPDATE =====================
