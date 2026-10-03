# GitHub Fleet Manager

Automatische GitHub fleet management met cron jobs, monitoring, en rapportage.

<video src="https://raw.githubusercontent.com/itsdarklikehell/fleet-manager/main/gource.mp4" controls width="100%"></video>

*Gource visualization showing the repository's commit history. See the [Gource workflow](.github/workflows/gource.yml) for details.*

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
- **Release Automation**: Conventional commits → release notes → GitHub release
- **Changelog Generator**: Auto CHANGELOG.md generatie
- **Secret Scanning**: Scan voor hardcoded credentials
- **License Compliance Check**: Dependency license compatibility
- **Repo Health Score**: Health score berekening (issues, activity, CI, tests, docs)
- **Security Advisory Monitor**: Monitor voor kwetsbare dependencies
- **Code Quality Metrics**: LOC, complexity, duplication, coverage, debt ratio
- **Automated Dependency Updates**: Auto PRs voor outdated dependencies
- **Branch Protection Enforcement**: Check en enable branch protection
- **Repo Archiving Suggestions**: Suggesties voor gearchiveerde repos
- **MCP GitHub Bridge**: GitHub MCP server integratie
- **Multi-Tool Chaining**: Combineer meerdere tools voor complexe taken
- **Autonomous PR Workflow**: Autonomous PR creation (branch, commit, push, PR)
- **Delivery Router**: Multi-platform delivery (Telegram, Discord, Slack, Email, Matrix)
- **Webhook Handler**: Auto-review, auto-triage, CI failure alerts
- **Model Router**: Language-based model selection
- **A2A Bridge**: A2A agent queries voor repo-specifieke expertise

## 📦 Scripts

| Script | Doel | Frequency |
|--------|------|-----------|
| `inbox-reader.sh` | GitHub inbox lezen via `gh search` | Elke 4 uur |
| `nightly-backlog-triage.sh` | Nightly triage van open issues/PRs | Elke nacht |
| `docs-drift-detection.sh` | Detecteert documentatie drift | Wekelijks |
| `dependency-audit.sh` | Auditering van dependencies | Dagelijks |
| `pr-review-agent.sh` | Geautomatiseerde PR reviews | Elke 6 uur |
| `ci-failure-summaries.sh` | CI failure samenvattingen | Dagelijks |
| `delivery-router.sh` | Multi-platform delivery | Dagelijks |
| `webhook-handler.sh` | Auto-review, auto-triage, CI alerts | Real-time |
| `model-router.sh` | Language-based model selection | Dagelijks |
| `a2a-bridge.sh` | A2A agent queries | Dagelijks |
| `mcp-github-bridge.sh` | GitHub MCP server integratie | Dagelijks |
| `fleet-automation-suite.sh` | Master orchestrator | Wekelijks |
| `autonomous-pr-workflow.sh` | Autonomous PR creation | On-demand |
| `multi-tool-chaining.sh` | Multi-tool chaining voor complexe taken | Wekelijks |
| `release-automation.sh` | Conventional commits → releases | Wekelijks |
| `changelog-generator.sh` | Auto CHANGELOG.md generatie | Wekelijks |
| `secret-scanning.sh` | Scan voor hardcoded credentials | Dagelijks |
| `license-compliance-check.sh` | License compliance check | Wekelijks |
| `repo-health-score.sh` | Repo health score berekening | Dagelijks |
| `security-advisory-monitor.sh` | Security advisory monitoring | Dagelijks |
| `code-quality-metrics.sh` | Code quality metrics | Wekelijks |
| `automated-dependency-updates.sh` | Auto dependency update PRs | Dagelijks |
| `branch-protection-enforcement.sh` | Branch protection enforcement | Wekelijks |
| `repo-archiving-suggestions.sh` | Repo archiving suggesties | Wekelijks |
| `health-check.sh` | Health check voor alle scripts | On-demand |

## 🚀 Installatie

```bash
# Clone de repository
git clone https://github.com/itsdarklikehell/fleet-manager.git
cd fleet-manager

# Kopieer het environment template
cp .env.example .env

# Vul je GitHub tokens in
# Bewerk .env en voeg je tokens toe:
# - GH_TOKEN_ITSDARKLIKEHELL: GitHub token voor itsdarklikehell
# - GH_TOKEN_HMOL33: GitHub token voor hmol33
# - TELEGRAM_TOKEN: Telegram bot token (optioneel)
# - TELEGRAM_CHAT_ID: Telegram chat ID (optioneel)

# Zorg dat alle scripts executebaar zijn
chmod +x scripts/*.sh

# Voer een health check uit
bash scripts/health-check.sh
```

## ⚙️ Configuratie

Alle configuratie gebeurt via environment variables. Zie `.env.example` voor alle beschikbare opties.

### GitHub Tokens
- `GH_TOKEN_ITSDARKLIKEHELL` - GitHub token voor itsdarklikehell repos
- `GH_TOKEN_HMOL33` - GitHub token voor hmol33 repos

### Telegram (optioneel)
- `TELEGRAM_TOKEN` - Telegram bot token
- `TELEGRAM_CHAT_ID` - Telegram chat ID voor notificaties

### Script-specifieke opties
Elke script heeft zijn eigen configuratie via environment variables:

```bash
# Dry run mode (test zonder echte acties)
export RA_DRY_RUN=yes       # Release automation
export CG_DRY_RUN=yes       # Changelog generator
export SS_DRY_RUN=yes       # Secret scanning
# ... enzovoort
```

## 📊 Health Check

Voer een health check uit om de status van alle scripts te controleren:

```bash
bash scripts/health-check.sh
```

Laat zien of:
- Alle scripts aanwezig en syntax correct zijn
- Alle afhankelijkheden beschikbaar zijn
- Alle environment variables correct zijn ingesteld
- Alle cron jobs actief zijn

## 🔄 Automatisatie

De scripts worden automatisch uitgevoerd via cron. Zie de cron schedule:

```bash
crontab -l
```

Of gebruik de master orchestrator:

```bash
bash scripts/fleet-automation-suite.sh
```

## Gebruik

```bash
# Health check
./scripts/health-check.sh

# Inbox reader
./scripts/inbox-reader.sh

# PR review agent
./scripts/pr-review-agent.sh

# CI failure summaries
./scripts/ci-failure-summaries.sh

# Nightly backlog triage
./scripts/nightly-backlog-triage.sh

# Docs drift detection
./scripts/docs-drift-detection.sh

# Dependency audit
./scripts/dependency-audit.sh

# Delivery router
./scripts/delivery-router.sh

# Webhook handler
./scripts/webhook-handler.sh

# Model router
./scripts/model-router.sh

# A2A bridge
./scripts/a2a-bridge.sh

# MCP GitHub bridge
./scripts/mcp-github-bridge.sh

# Release automation
./scripts/release-automation.sh

# Changelog generator
./scripts/changelog-generator.sh

# Secret scanning
./scripts/secret-scanning.sh

# License compliance check
./scripts/license-compliance-check.sh

# Repo health score
./scripts/repo-health-score.sh

# Security advisory monitor
./scripts/security-advisory-monitor.sh

# Code quality metrics
./scripts/code-quality-metrics.sh

# Automated dependency updates
./scripts/automated-dependency-updates.sh

# Branch protection enforcement
./scripts/branch-protection-enforcement.sh

# Repo archiving suggestions
./scripts/repo-archiving-suggestions.sh

# Fleet automation suite (master orchestrator)
./scripts/fleet-automation-suite.sh

# Autonomous PR workflow
./scripts/autonomous-pr-workflow.sh

# Multi-tool chaining
./scripts/multi-tool-chaining.sh

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

# Inbox manager
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

# Fleet automation scripts
0 */4 * * * ./scripts/inbox-reader.sh
30 */6 * * * ./scripts/pr-review-agent.sh
0 7 * * * ./scripts/ci-failure-summaries.sh
0 2 * * * ./scripts/nightly-backlog-triage.sh
0 3 * * 1 ./scripts/docs-drift-detection.sh
0 5 * * * ./scripts/dependency-audit.sh
0 8 * * * ./scripts/delivery-router.sh
0 9 * * * ./scripts/model-router.sh
30 9 * * * ./scripts/a2a-bridge.sh
0 30 * * * ./scripts/mcp-github-bridge.sh
0 4 * * * ./scripts/fleet-automation-suite.sh
0 7 * * * ./scripts/secret-scanning.sh
30 5 * * * ./scripts/automated-dependency-updates.sh
30 7 * * * ./scripts/repo-health-score.sh
0 6 * * * ./scripts/security-advisory-monitor.sh
0 10 * * 1 ./scripts/release-automation.sh
30 10 * * 1 ./scripts/changelog-generator.sh
0 3 * * 2 ./scripts/license-compliance-check.sh
0 4 * * 3 ./scripts/code-quality-metrics.sh
0 3 * * 4 ./scripts/branch-protection-enforcement.sh
0 3 * * 5 ./scripts/repo-archiving-suggestions.sh
```

## 📝 Licentie

MIT
