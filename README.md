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
| `metrics-collector.sh` | Fleet health metrics | Dagelijks |
| `fleet-doctor.sh` | Incident detectie en diagnose | Dagelijks |
| `rollback.sh` | Rollback mechanisme voor mutaties | Wekelijks |
| `repo-standardizer.sh` | Standaardiseer repo instellingen | Wekelijks |
| `pr-description-generator.sh` | Genereert PR beschrijvingen | Ad-hoc |
| `release-notes-generator.sh` | Genereert release notes | Ad-hoc |
| `generate-docs.sh` | Genereert script documentatie | Ad-hoc |
| `test-suite.sh` | Test suite voor alle scripts | Ad-hoc |
| `quality-upgrade.sh` | Batch upgrade scripts | Ad-hoc |
| `cron-audit.sh` | Audit en fix cron jobs | Ad-hoc |

## 🏗️ Architectuur

```
fleet-manager/
├── github_fleet_manager.sh  # Monolithische script (fallback)
├── lib/
│   ├── config.sh            # Configuratie + helpers + rate limiter
│   └── telegram.sh          # Telegram rapportage
├── scripts/                 # 129 modulaire scripts
│   ├── inbox-reader.sh
│   ├── pr-review-agent.sh
│   ├── metrics-collector.sh
│   ├── fleet-doctor.sh
│   ├── rollback.sh
│   └── ...
├── docs/                    # Script documentatie
├── tests/                   # Test resultaten
└── .github/workflows/       # CI/CD
```

## 🔧 Configuratie

### Environment Variabelen

| Variable | Beschrijving | Default |
|----------|-------------|---------|
| `GITHUB_TOKEN` | GitHub API token | Vereist |
| `TELEGRAM_TOKEN` | Telegram bot token | Optioneel |
| `TELEGRAM_CHAT_ID` | Telegram chat ID | `1779426583` |
| `TELEGRAM_CHAT_IDS` | Meerdere chat IDs | `1779426583 -1004424968209 639276511` |
| `GITHUB_FLEET_DRY_RUN` | DRY_RUN mode | Leeg |
| `RATE_LIMIT_MAX` | Max API requests per uur | `4500` |
| `STALE_SCRIPT_AGE` | Max tijd zonder run (seconden) | `86400` |

### Cron Jobs

145+ cron jobs draaien via `github_fleet_wrapper.sh`:

```bash
# Dagelijks
0 4 * * * fleet-doctor
30 4 * * * metrics-collector

# Wekelijks
0 5 * * 1 repo-standardizer
30 5 * * 1 rollback stats
```

## 📊 Monitoring

- **Health Check**: `health-check.sh` controleert alle scripts, dependencies en cron jobs
- **Metrics**: `metrics-collector.sh` verzamelt fleet health metrics
- **Fleet Doctor**: `fleet-doctor.sh` detecteert en diagnoseert incidenten
- **Rate Limiter**: In `lib/config.sh` voorkomt API rate limit overschrijding

## 🔄 Rollback

`rollback.sh` houdt de laatste 100 mutaties bij en kan ze ongedaan maken:

```bash
# Laatste 10 mutaties tonen
bash scripts/rollback.sh list 10

# Laatste mutatie terugdraaien
bash scripts/rollback.sh rollback 1

# Statistieken tonen
bash scripts/rollback.sh stats
```

## 🧪 Testen

```bash
# Test suite draaien
bash scripts/test-suite.sh

# Health check
bash scripts/health-check.sh

# Cron audit
bash scripts/cron-audit.sh
```

## 📝 Licentie

MIT
