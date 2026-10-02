# GitHub Fleet Manager

Automatische GitHub fleet management met cron jobs, monitoring, en rapportage.

## Functies

- **GitHub Fleet Management**: PRs, issues, releases, branches, CI/CD
- **Netwerk Monitoring**: Device scanning, service checks
- **Systeem Monitoring**: CPU/RAM/Disk, Docker, systemd
- **Security Audits**: SSL certs, port scanning, SSH failures
- **Backup Verificatie**: Config backups, Docker volumes
- **Telegram Rapportage**: Berichten naar meerdere chats
- **Self-Management**: Self-update, self-monitor, self-backup
- **R&D Team Coordinatie**: Automatische repo verdeling over teams
- **Inbox Management**: Notificaties lezen, classificeren, antwoorden
- **Auto-Responder**: Automatisch antwoorden op issues en PRs
- **Notification Digest**: Dagelijkse samenvatting van activiteit

## Installatie

```bash
git clone https://github.com/itsdarklikehell/fleet-manager.git
cd fleet-manager
chmod +x scripts/*.sh
```

## Configuratie

Kopieer `lib/config.sh` en pas aan:

```bash
export TELEGRAM_TOKEN="your-bot-token"
export TELEGRAM_CHAT_IDS="chat1 chat2 chat3"
export REPOS_DIR="$HOME/.openclaw/workspace/projects"
```

## Gebruik

```bash
# Status check
./scripts/status.sh

# Netwerk scan
./scripts/network-scan.sh

# Systeem health
./scripts/system-health.sh

# Service check
./scripts/service-check.sh

# Log monitor
./scripts/log-monitor.sh

# Security audit
./scripts/security-audit.sh

# Backup verify
./scripts/backup-verify.sh

# CI failure check
./scripts/ci-failure-check.sh

# PR review auto
./scripts/pr-review-auto.sh

# Issue triage auto
./scripts/issue-triage-auto.sh

# Release auto
./scripts/release-auto.sh

# Branch cleanup auto
./scripts/branch-cleanup-auto.sh

# Self management
./scripts/self-update.sh
./scripts/self-monitor.sh
./scripts/self-backup.sh

# R&D Team Coordinator
./scripts/rd-team-coordinator.sh

# Inbox management
./scripts/inbox-manager.sh

# Auto-responder
./scripts/auto-responder.sh
./scripts/auto-label.sh
./scripts/auto-assign.sh
./scripts/auto-close.sh
./scripts/auto-merge.sh

# Notification digest
./scripts/notification-digest.sh
./scripts/activity-report.sh
./scripts/mention-report.sh
./scripts/review-request-report.sh
./scripts/ci-failure-report.sh
```

## Cron jobs

```bash
# Dagelijkse jobs
0 7 * * * ./scripts/network-scan.sh
15 7 * * * ./scripts/system-health.sh
30 7 * * * ./scripts/service-check.sh
45 7 * * * ./scripts/log-monitor.sh

# Weekelijkse jobs
0 8 * * 1 ./scripts/security-audit.sh
30 8 * * 1 ./scripts/backup-verify.sh

# Self-management
0 6 * * * ./scripts/self-update.sh
15 6 * * * ./scripts/self-monitor.sh
0 5 1 * * ./scripts/self-backup.sh

# R&D Team Coordinator (wekelijks)
0 20 * * 0 ./scripts/rd-team-coordinator.sh

# Inbox manager (elke 2 uur)
30 */2 * * * ./scripts/inbox-manager.sh

# Auto-responder (dagelijkse)
0 21 * * * ./scripts/auto-responder.sh
15 21 * * * ./scripts/auto-label.sh
30 21 * * * ./scripts/auto-assign.sh
45 21 * * * ./scripts/auto-close.sh
0 22 * * * ./scripts/auto-merge.sh

# Notification digest (dagelijkse)
0 23 * * * ./scripts/notification-digest.sh
15 23 * * * ./scripts/activity-report.sh
30 23 * * * ./scripts/mention-report.sh
45 23 * * * ./scripts/review-request-report.sh
0 0 * * * ./scripts/ci-failure-report.sh
```

## Licentie

MIT
