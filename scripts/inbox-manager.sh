#!/usr/bin/env bash
# scripts/inbox-manager.sh - GitHub Inbox Manager
# Leest notificaties, classificeert en antwoordt automatisch waar mogelijk
source /home/hans/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"
source "$(dirname "$0")/../lib/telegram.sh"

log "=== GitHub Inbox Manager ==="

# Fase 1: Notificaties ophalen voor beide accounts
log "Fase 1: Notificaties ophalen..."

# itsdarklikehell notificaties
log "  itsdarklikehell notificaties..."
itsdarklikehell_notifs=$(gh api notifications --paginate --jq '.[] | {id, reason, subject: .subject.title, repo: .repository.full_name, type: .subject.type, url}' 2>/dev/null || echo "")

# hmol33 notificaties (als token beschikbaar)
hmol33_notifs=""
if [ -n "$HMOL33_TOKEN" ]; then
  log "  hmol33 notificaties..."
  hmol33_notifs=$(GITHUB_TOKEN="$HMOL33_TOKEN" gh api notifications --paginate --jq '.[] | {id, reason, subject: .subject.title, repo: .repository.full_name, type: .subject.type, url}' 2>/dev/null || echo "")
fi

# Fase 2: Notificaties classificeren
log "Fase 2: Notificaties classificeren..."

total_notifs=0
auto_replied=0
needs_attention=0

# Verwerk itsdarklikehell notificaties
if [ -n "$itsdarklikehell_notifs" ]; then
  while IFS= read -r notif; do
    [ -z "$notif" ] && continue
    total_notifs=$((total_notifs + 1))
    
    reason=$(echo "$notif" | jq -r '.reason // "unknown"')
    subject=$(echo "$notif" | jq -r '.subject // "unknown"')
    repo=$(echo "$notif" | jq -r '.repo // "unknown"')
    type=$(echo "$notif" | jq -r '.type // "unknown"')
    
    log "  [$total_notifs] $repo: $subject (type: $type, reason: $reason)"
    
    # Classificeer en antwoord waar mogelijk
    case "$type" in
      "Issue")
        # Check of issue een bug of feature is
        if echo "$subject" | grep -qiE "bug|fix|error|crash|broken"; then
          log "    → Bug issue, label toevoegen..."
          # Haal issue nummer op uit URL
          issue_url=$(echo "$notif" | jq -r '.url // ""')
          if [ -n "$issue_url" ]; then
            issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$')
            gh issue edit "$repo#$issue_num" --add-label "bug" 2>/dev/null && ((auto_replied++)) || true
          fi
        elif echo "$subject" | grep -qiE "feature|enhancement|add|new"; then
          log "    → Feature issue, label toevoegen..."
          issue_url=$(echo "$notif" | jq -r '.url // ""')
          if [ -n "$issue_url" ]; then
            issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$')
            gh issue edit "$repo#$issue_num" --add-label "enhancement" 2>/dev/null && ((auto_replied++)) || true
          fi
        else
          log "    → Geen automatische actie"
          ((needs_attention++)) || true
        fi
        ;;
      "PullRequest")
        log "    → PR notificatie, review nodig"
        ((needs_attention++)) || true
        ;;
      "Mention")
        log "    → Mention, antwoorden..."
        # Haal comment URL op
        comment_url=$(echo "$notif" | jq -r '.url // ""')
        if [ -n "$comment_url" ]; then
          # Voeg reactie toe
          gh api "$comment_url" --method POST -f body="👋 Thanks for the mention! I'll look into this soon." 2>/dev/null && ((auto_replied++)) || true
        fi
        ;;
      *)
        log "    → Onbekend type: $type"
        ((needs_attention++)) || true
        ;;
    esac
  done <<< "$itsdarklikehell_notifs"
fi

# Verwerk hmol33 notificaties
if [ -n "$hmol33_notifs" ]; then
  while IFS= read -r notif; do
    [ -z "$notif" ] && continue
    total_notifs=$((total_notifs + 1))
    
    reason=$(echo "$notif" | jq -r '.reason // "unknown"')
    subject=$(echo "$notif" | jq -r '.subject // "unknown"')
    repo=$(echo "$notif" | jq -r '.repo // "unknown"')
    type=$(echo "$notif" | jq -r '.type // "unknown"')
    
    log "  [$total_notifs] $repo: $subject (type: $type, reason: $reason)"
    
    # Classificeer en antwoord waar mogelijk
    case "$type" in
      "Issue")
        if echo "$subject" | grep -qiE "bug|fix|error|crash|broken"; then
          log "    → Bug issue, label toevoegen..."
          issue_url=$(echo "$notif" | jq -r '.url // ""')
          if [ -n "$issue_url" ]; then
            issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$')
            GITHUB_TOKEN="$HMOL33_TOKEN" gh issue edit "$repo#$issue_num" --add-label "bug" 2>/dev/null && ((auto_replied++)) || true
          fi
        elif echo "$subject" | grep -qiE "feature|enhancement|add|new"; then
          log "    → Feature issue, label toevoegen..."
          issue_url=$(echo "$notif" | jq -r '.url // ""')
          if [ -n "$issue_url" ]; then
            issue_num=$(echo "$issue_url" | grep -oE '[0-9]+$')
            GITHUB_TOKEN="$HMOL33_TOKEN" gh issue edit "$repo#$issue_num" --add-label "enhancement" 2>/dev/null && ((auto_replied++)) || true
          fi
        else
          log "    → Geen automatische actie"
          ((needs_attention++)) || true
        fi
        ;;
      "PullRequest")
        log "    → PR notificatie, review nodig"
        ((needs_attention++)) || true
        ;;
      "Mention")
        log "    → Mention, antwoorden..."
        comment_url=$(echo "$notif" | jq -r '.url // ""')
        if [ -n "$comment_url" ]; then
          GITHUB_TOKEN="$HMOL33_TOKEN" gh api "$comment_url" --method POST -f body="👋 Thanks for the mention! I'll look into this soon." 2>/dev/null && ((auto_replied++)) || true
        fi
        ;;
      *)
        log "    → Onbekend type: $type"
        ((needs_attention++)) || true
        ;;
    esac
  done <<< "$hmol33_notifs"
fi

# Fase 3: Samenvatting
log "Fase 3: Samenvatting..."
log "  Totaal notificaties: $total_notifs"
log "  Automatisch afgehandeld: $auto_replied"
log "  Nodig aandacht: $needs_attention"

log "=== GitHub Inbox Manager complete ==="
send_telegram_message "📬 *GitHub Inbox Manager*\n\n*Totaal:* $total_notifs\n*Automatisch:* $auto_replied\n*Aandacht nodig:* $needs_attention\n\n📋 Volledig log: $LOG_FILE" || true
