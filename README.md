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
```

## Licentie

MIT
