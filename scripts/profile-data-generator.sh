#!/usr/bin/env bash
# scripts/profile-data-generator.sh - Genereert profile-data.json met live statussen
# Haalt live data op van GitHub, TryHackMe, Hack The Box en CyLab Academy
set -uo pipefail

source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== Profile Data Generator ==="

# Configuratie
PDG_ENABLED="${PDG_ENABLED:-yes}"
PDG_DRY_RUN="${PDG_DRY_RUN:-no}"
PDG_OUTPUT_DIR="${PDG_OUTPUT_DIR:-$REPOS_DIR/itsdarklikehell-my-resume}"
PDG_USERNAME_GITHUB="${PDG_USERNAME_GITHUB:-itsdarklikehell}"
PDG_USERNAME_THM="${PDG_USERNAME_THM:-SgtStroopwafel}"
PDG_USERNAME_HTB="${PDG_USERNAME_HTB:-01a0f22b-f959-73b9-925c-c2e2e350db97}"
PDG_USERNAME_CYLAB="${PDG_USERNAME_CYLAB:-SgtStroopwafel}"

# Function: haal GitHub stats op
get_github_stats() {
  local username="$1"
  log "  Fetching GitHub stats for $username..."
  
  if [ "$PDG_DRY_RUN" = "yes" ]; then
    echo '"total_repos": 50, "total_stars": 100'
    return
  fi
  
  set_repo_token "$username"
  
  local stats
  stats=$(gh api "users/$username" --jq '{
    total_repos: .public_repos,
    followers: .followers,
    following: .following
  }' 2>/dev/null || echo '{}')
  
  echo "$stats"
}

# Function: haal GitHub repository stats op
get_github_repo_stats() {
  local username="$1"
  log "  Fetching GitHub repo stats for $username..."
  
  if [ "$PDG_DRY_RUN" = "yes" ]; then
    echo '{"repos": [{"name": "my-resume", "stars": 10, "description": "CV", "language": "HTML", "url": "https://github.com/itsdarklikehell/my-resume"}], "skills": {"Shell": {"repos": 5, "percentage": 20}, "Python": {"repos": 10, "percentage": 40}}, "stats": {"total_repos": 40, "total_stars": 100, "languages": 4}, "contributions": []}'
    return
  fi
  
  # Get ALL repos with pagination (up to 1000)
  local repos="[]"
  local page=1
  while [ $page -le 10 ]; do
    local page_repos
    page_repos=$(gh api "users/$username/repos?per_page=100&page=$page&sort=updated&direction=desc" --jq '[.[] | {
      name: .name,
      url: .html_url,
      description: (.description // "No description"),
      stars: .stargazers_count,
      forks: .forks_count,
      language: (.language // "Unknown"),
      created: .created_at,
      updated: .updated_at,
      topics: (.topics // [])
    }]' 2>/dev/null || echo "[]")
    
    local count
    count=$(echo "$page_repos" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    
    if [ "$count" -eq 0 ]; then
      break
    fi
    
    repos=$(echo "$repos" "$page_repos" | python3 -c "
import sys, json
parts = sys.stdin.read().split('] [', 1)
if len(parts) == 2:
    a = json.loads(parts[0] + ']')
    b = json.loads('[' + parts[1])
    print(json.dumps(a + b))
else:
    print(parts[0])
" 2>/dev/null || echo "$repos")
    
    if [ "$count" -lt 100 ]; then
      break
    fi
    
    page=$((page + 1))
  done
  
  # Calculate skills based on languages
  local skills
  skills=$(echo "$repos" | python3 -c "
import sys, json
try:
    repos = json.load(sys.stdin)
    lang_counts = {}
    for repo in repos:
        lang = repo.get('language', 'Unknown')
        lang_counts[lang] = lang_counts.get(lang, 0) + 1
    
    total = sum(lang_counts.values())
    skills = {}
    for lang, count in lang_counts.items():
        pct = round((count / total) * 100) if total > 0 else 0
        skills[lang] = {'repos': count, 'percentage': pct}
    
    print(json.dumps(skills))
except Exception as e:
    print('{}')
" 2>/dev/null || echo "{}")
  
  # Get stats
  local total_repos total_stars languages
  total_repos=$(echo "$repos" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  total_stars=$(echo "$repos" | python3 -c "import sys,json; print(sum(r.get('stargazers_count',0) for r in json.load(sys.stdin)))" 2>/dev/null || echo "0")
  languages=$(echo "$repos" | python3 -c "import sys,json; print(len(set(r.get('language','Unknown') for r in json.load(sys.stdin))))" 2>/dev/null || echo "0")
  
  # Get recent contributions
  local contributions
  contributions=$(gh api "users/$username/events/public?per_page=20" --jq '[.[] | select(.type == "PushEvent" or .type == "PullRequestEvent" or .type == "IssuesEvent" or .type == "CreateEvent") | {
    type: .type,
    repo: .repo.name,
    date: .created_at,
    url: ("https://github.com/" + .repo.name)
  }]' 2>/dev/null || echo "[]")
  
  # Build stats object
  echo "{\"repos\": $repos, \"skills\": $skills, \"stats\": {\"total_repos\": $total_repos, \"total_stars\": $total_stars, \"languages\": $languages}, \"contributions\": $contributions}"
}

# Function: check of response JSON is (geen HTML checkpoint)
is_valid_json() {
  local response="$1"
  if echo "$response" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Function: haal TryHackMe stats op
get_thm_stats() {
  local username="$1"
  log "  Fetching TryHackMe stats for $username..."
  
  if [ "$PDG_DRY_RUN" = "yes" ]; then
    echo '{"rank": "N/A", "points": 0}'
    return
  fi
  
  # TryHackMe API - probeer meerdere endpoints
  local stats=""
  
  # Probeer eerst de publieke API
  stats=$(curl -s "https://tryhackme.com/api/users/$username" \
    -H "User-Agent: Mozilla/5.0 (Fleet-Manager)" \
    --max-time 10 2>/dev/null || echo "")
  
  # Check of het geldige JSON is
  if is_valid_json "$stats"; then
    echo "$stats"
    return
  fi
  
  # Probeer alternatief: scrape de profielpagina
  stats=$(curl -s "https://tryhackme.com/p/$username" \
    -H "User-Agent: Mozilla/5.0 (Fleet-Manager)" \
    --max-time 10 2>/dev/null || echo "")
  
  if [ -n "$stats" ]; then
    # Probeer rank en points te parsen uit HTML
    local rank points
    rank=$(echo "$stats" | grep -oP 'rank.*?(\d+)' | grep -oP '\d+' | head -1 || echo "N/A")
    points=$(echo "$stats" | grep -oP 'points.*?(\d+)' | grep -oP '\d+' | head -1 || echo "0")
    
    if [ "$rank" != "N/A" ] || [ "$points" != "0" ]; then
      echo "{\"rank\": \"$rank\", \"points\": $points}"
      return
    fi
  fi
  
  log "    ⚠️ TryHackMe API niet bereikbaar"
  echo '{"rank": "N/A", "points": 0}'
}

# Function: haal Hack The Box stats op
get_htb_stats() {
  local machine_id="$1"
  log "  Fetching Hack The Box stats for $machine_id..."
  
  if [ "$PDG_DRY_RUN" = "yes" ]; then
    echo '{"rank": "N/A", "points": 0}'
    return
  fi
  
  # Hack The Box API
  local stats
  stats=$(curl -s "https://www.hackthebox.com/api/v4/users/$machine_id" \
    -H "User-Agent: Mozilla/5.0 (Fleet-Manager)" \
    --max-time 10 2>/dev/null || echo "")
  
  if is_valid_json "$stats"; then
    echo "$stats"
    return
  fi
  
  log "    ⚠️ Hack The Box API niet bereikbaar"
  echo '{"rank": "N/A", "points": 0}'
}

# Function: haal CyLab Academy stats op
get_cylab_stats() {
  local username="$1"
  log "  Fetching CyLab Academy stats for $username..."
  
  if [ "$PDG_DRY_RUN" = "yes" ]; then
    echo '{"rank": "N/A", "points": 0}'
    return
  fi
  
  # CyLab Academy uses Moodle - try to scrape
  local stats
  stats=$(curl -s "https://learn.cylabacademy.org/user/profile.php?username=$username" \
    -H "User-Agent: Mozilla/5.0 (Fleet-Manager)" \
    --max-time 10 2>/dev/null || echo "")
  
  if [ -n "$stats" ]; then
    # Parse rank/points from profile page
    local rank points
    rank=$(echo "$stats" | grep -oP 'rank.*?(\d+)' | grep -oP '\d+' | head -1 || echo "N/A")
    points=$(echo "$stats" | grep -oP 'points.*?(\d+)' | grep -oP '\d+' | head -1 || echo "0")
    
    if [ "$rank" != "N/A" ] || [ "$points" != "0" ]; then
      echo "{\"rank\": \"$rank\", \"points\": $points}"
      return
    fi
  fi
  
  log "    ⚠️ CyLab Academy API niet bereikbaar"
  echo '{"rank": "N/A", "points": 0}'
}

# Hoofdlogica
if [ "$PDG_ENABLED" != "yes" ]; then
  log "Profile data generator uitgeschakeld"
  exit 0
fi

# Haal data op
github_user_stats=$(get_github_stats "$PDG_USERNAME_GITHUB")
github_repo_data=$(get_github_repo_stats "$PDG_USERNAME_GITHUB")
thm_stats=$(get_thm_stats "$PDG_USERNAME_THM")
htb_stats=$(get_htb_stats "$PDG_USERNAME_HTB")
cylab_stats=$(get_cylab_stats "$PDG_USERNAME_CYLAB")

# Genereer profile-data.json
generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Write temp files for Python to read (avoids shell escaping issues)
echo "$thm_stats" > /tmp/pdg_thm.json
echo "$htb_stats" > /tmp/pdg_htb.json
echo "$cylab_stats" > /tmp/pdg_cylab.json
echo "$github_repo_data" > /tmp/pdg_github.json
echo "$github_user_stats" > /tmp/pdg_github_user.json

# Build JSON with Python for proper formatting
profile_json=$(python3 -c "
import json

with open('/tmp/pdg_thm.json') as f: thm = json.load(f)
with open('/tmp/pdg_htb.json') as f: htb = json.load(f)
with open('/tmp/pdg_cylab.json') as f: cylab = json.load(f)

data = {
    'tryhackme': thm,
    'hackthebox': htb,
    'cylab': cylab,
    'generated_at': '$generated_at'
}
print(json.dumps(data, indent=2, ensure_ascii=False))
" 2>/dev/null)

# Update github-data.json with stats
github_json=$(python3 -c "
import json

with open('/tmp/pdg_github.json') as f: github_data = json.load(f)
with open('/tmp/pdg_github_user.json') as f: github_user = json.load(f)

data = {
    'stats': github_data,
    'generated_at': '$generated_at',
    'github_user': github_user
}
print(json.dumps(data, indent=2, ensure_ascii=False))
" 2>/dev/null)

# Cleanup temp files
rm -f /tmp/pdg_thm.json /tmp/pdg_htb.json /tmp/pdg_cylab.json /tmp/pdg_github.json /tmp/pdg_github_user.json

# Output
output_dir="${PDG_OUTPUT_DIR:-$REPOS_DIR/itsdarklikehell-my-resume}"
if [ ! -d "$output_dir" ] && [ "$PDG_DRY_RUN" != "yes" ]; then
  mkdir -p "$output_dir"
fi

if [ "$PDG_DRY_RUN" = "yes" ]; then
  log "  [DRY RUN] Would write to $output_dir"
  log "  profile-data.json content:"
  echo "$profile_json" | sed 's/^/    /'
  log "  github-data.json content:"
  echo "$github_json" | sed 's/^/    /'
else
  echo "$profile_json" > "$output_dir/profile-data.json"
  echo "$github_json" > "$output_dir/github-data.json"
  log "  ✅ profile-data.json geschreven naar $output_dir"
  log "  ✅ github-data.json bijgewerkt"
fi

log "=== Profile Data Generator klaar ==="
