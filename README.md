# GitHub Fleet Manager

Automatische GitHub fleet management met 156 modulaire scripts, cron jobs, monitoring, en rapportage.

## Functies

- **GitHub Fleet Management**: PRs, issues, releases, branches, CI/CD
- **Netwerk Monitoring**: Device scanning, service checks
- **Systeem Monitoring**: CPU/RAM/Disk, Docker, systemd
- **Security Audits**: SSL certs, port scanning, SSH failures, secret scanning
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
- **AI-Powered Triage**: AI-gestuurde issue triage en PR reviews
- **Cross-Repo Dependency Tracking**: Detecteert dependencies tussen repos
- **Auto Repo Creator**: Automatisch nieuwe repos aanmaken met standaard structuur
- **Auto Release Notes**: Genereer release notes van commits (conventional commits)
- **Fleet Dashboard**: Real-time HTML dashboard met script/cron status
- **Performance Monitoring**: Script execution time tracking
- **Profile Data Generator**: Live JSON data voor GitHub Pages

## 📦 Scripts (156)

### Inbox Management (17)

| Script | Doel | Frequency |
|--------|------|-----------|
| `inbox-reader.sh` | GitHub inbox lezen via `gh search` | Elke 4 uur |
| `mcp-inbox-reader.sh` | MCP-gebaseerde inbox reader | Elke 4 uur |
| `inbox-manager.sh` | Notificaties lezen, classificeren, antwoorden | Elke 2 uur |
| `inbox-stats.sh` | Inbox statistieken | Dagelijks |
| `inbox-health.sh` | Inbox health check | Dagelijks |
| `inbox-alerts.sh` | Alerts voor belangrijke items | Dagelijks |
| `inbox-metrics.sh` | Inbox metrics | Dagelijks |
| `inbox-daily-report.sh` | Dagelijkse inbox rapport | Dagelijks |
| `inbox-weekly-report.sh` | Weekelijkse inbox rapport | Wekelijks |
| `inbox-monthly-report.sh` | Maandelijkse inbox rapport | Maandelijks |
| `inbox-trends.sh` | Inbox trends | Dagelijks |
| `inbox-dashboard.sh` | Inbox dashboard | Dagelijks |
| `inbox-export.sh` | Export inbox data naar JSON/CSV | Dagelijks |
| `inbox-prioriteit.sh` | Prioriteit geven aan notificaties | Ad-hoc |
| `inbox-auto-assign.sh` | Automatisch assignees toewijzen | Ad-hoc |
| `inbox-auto-close.sh` | Automatisch oude issues sluiten | Ad-hoc |
| `inbox-auto-comment.sh` | Automatisch commentaar toevoegen | Ad-hoc |
| `inbox-auto-label.sh` | Automatisch labels toevoegen | Ad-hoc |
| `inbox-auto-merge.sh` | Automatisch kleine PRs mergen | Ad-hoc |
| `inbox-auto-review.sh` | Automatisch PRs reviewen | Ad-hoc |
| `inbox-archive.sh` | Oude notificaties archiveren | Ad-hoc |

### GitHub Actions (10)

| Script | Doel | Frequency |
|--------|------|-----------|
| `actions-audit.sh` | Audit alle Actions workflows | Ad-hoc |
| `actions-cleanup.sh` | Verwijder oude workflow runs | Ad-hoc |
| `actions-disable.sh` | Disable onnodige workflows | Ad-hoc |
| `actions-enable.sh` | Enable disabled workflows | Ad-hoc |
| `actions-environments.sh` | Audit alle environments | Ad-hoc |
| `actions-rerun.sh` | Rerun failed workflows | Ad-hoc |
| `actions-secrets.sh` | Audit alle secrets | Ad-hoc |
| `actions-status.sh` | Toon status van alle workflows | Ad-hoc |
| `actions-update.sh` | Update workflows naar laatste versie | Ad-hoc |
| `actions-variables.sh` | Audit alle variables | Ad-hoc |

### Auto Automation (15)

| Script | Doel | Frequency |
|--------|------|-----------|
| `auto-issue-responder.sh` | Automatische issue responses | Elke 6 uur |
| `auto-labeling.sh` | Automatische labeling | Elke 6 uur |
| `auto-merge.sh` | Auto-merge PRs met CI + reviews | Elke 2 uur |
| `auto-merge-with-ai-review.sh` | Auto-merge met AI review | Ad-hoc |
| `auto-assignment.sh` | Automatische assignment | Ad-hoc |
| `auto-branch-protection.sh` | Automatische branch protection | Ad-hoc |
| `auto-close.sh` | Sluit oude inactieve issues | Ad-hoc |
| `auto-code-quality-checks.sh` | Automatische code quality checks | Ad-hoc |
| `auto-dependency-security-fixes.sh` | Auto security fix PRs | Ad-hoc |
| `auto-issue-duplicate-detection.sh` | Detecteer duplicate issues | Ad-hoc |
| `auto-issue-labeling-ai.sh` | AI-gestuurde issue labeling | Ad-hoc |
| `auto-pr-size-labeling.sh` | PR size labeling (XS-XL) | Ad-hoc |
| `auto-release-asset-uploads.sh` | Automatische release asset uploads | Ad-hoc |
| `auto-release-notes-translation.sh` | Release notes vertaling | Ad-hoc |
| `auto-release-publishing.sh` | Automatische release publishing | Ad-hoc |
| `auto-repo-archiving.sh` | Automatische repo archiving | Ad-hoc |
| `auto-rollback-on-failure.sh` | Automatische rollback bij failures | Ad-hoc |
| `auto-script-dependency-updates.sh` | Automatische script dependency updates | Ad-hoc |
| `auto-secret-scanning-enhanced.sh` | Uitgebreide secret scanning | Ad-hoc |

### Issue Management (8)

| Script | Doel | Frequency |
|--------|------|-----------|
| `issue-create.sh` | Create issues vanuit templates | Ad-hoc |
| `issue-update.sh` | Update issues (labels, assignees, milestones) | Ad-hoc |
| `issue-close.sh` | Close issues met comment | Ad-hoc |
| `issue-reopen.sh` | Reopen issues | Ad-hoc |
| `issue-comment.sh` | Add comments to issues | Ad-hoc |
| `issue-assign.sh` | Assign issues to users | Ad-hoc |
| `issue-label.sh` | Add/remove labels from issues | Ad-hoc |
| `issue-close-auto.sh` | Issue close automation | Ad-hoc |
| `issue-triage-auto.sh` | Issue triage automation | Ad-hoc |

### PR Management (10)

| Script | Doel | Frequency |
|--------|------|-----------|
| `pr-create.sh` | Create PRs vanuit templates | Ad-hoc |
| `pr-update.sh` | Update PRs (title, body, labels, assignees) | Ad-hoc |
| `pr-close.sh` | Close PRs met comment | Ad-hoc |
| `pr-reopen.sh` | Reopen PRs | Ad-hoc |
| `pr-comment.sh` | Add comments to PRs | Ad-hoc |
| `pr-assign.sh` | Assign PRs to reviewers | Ad-hoc |
| `pr-label.sh` | Add/remove labels from PRs | Ad-hoc |
| `pr-merge.sh` | Merge PRs (merge, squash, rebase) | Ad-hoc |
| `pr-review.sh` | Review PRs (approve, request changes, comment) | Ad-hoc |
| `pr-review-agent.sh` | Automatisch PRs reviewen met AGENTS.md | Elke 6 uur |
| `pr-description-generator.sh` | Genereert PR beschrijvingen uit commits | Ad-hoc |

### Release Management (6)

| Script | Doel | Frequency |
|--------|------|-----------|
| `release-automation.sh` | Release automation (conventional commits) | Wekelijks |
| `release-notes-auto.sh` | Release notes automation | Ad-hoc |
| `release-notes-generator.sh` | Genereert release notes uit commits | Ad-hoc |
| `release-publishing.sh` | Automatische release publishing | Dagelijks |
| `changelog-generator.sh` | Automatische CHANGELOG.md generatie | Wekelijks |
| `label-sync.sh` | Label synchronisatie | Ad-hoc |

### Repo Management (12)

| Script | Doel | Frequency |
|--------|------|-----------|
| `repo-archive.sh` | Archive inactieve repos | Ad-hoc |
| `repo-unarchive.sh` | Unarchive gearchiveerde repos | Ad-hoc |
| `repo-transfer.sh` | Transfer repos naar andere owner | Ad-hoc |
| `repo-rename.sh` | Rename repos | Ad-hoc |
| `repo-description.sh` | Update repo descriptions | Ad-hoc |
| `repo-topics.sh` | Update repo topics | Ad-hoc |
| `repo-homepage.sh` | Update repo homepages | Ad-hoc |
| `repo-visibility.sh` | Change repo visibility | Ad-hoc |
| `repo-features.sh` | Enable/disable repo features | Ad-hoc |
| `repo-default-branch.sh` | Change default branch | Ad-hoc |
| `repo-branch-protection.sh` | Set branch protection | Ad-hoc |
| `repo-delete-branch-protection.sh` | Delete branch protection | Ad-hoc |
| `repo-health-score.sh` | Repo health score berekening | Dagelijks |
| `repo-archiving-suggestions.sh` | Repo archiving suggestions | Wekelijks |
| `repo-standardizer.sh` | Standaardiseer repo instellingen | Wekelijks |

### Security & Compliance (8)

| Script | Doel | Frequency |
|--------|------|-----------|
| `secret-scanning.sh` | Secret scanning voor hardcoded credentials | Dagelijks |
| `security-audit.sh` | Security audit (SSL/Ports/SSH) | Wekelijks |
| `security-advisory-monitor.sh` | Security advisory monitoring | Dagelijks |
| `license-compliance-check.sh` | License compliance check | Wekelijks |
| `dependency-audit.sh` | Dagelijkse dependency security audit | Dagelijks |
| `dependency-security-fixes.sh` | Auto-create security fix PRs | Dagelijks |
| `dependency-graph-visualization.sh` | Cross-repo dependency visualisatie | Ad-hoc |
| `cross-repo-dependency-tracker.sh` | Cross-repo dependency tracking | Ad-hoc |

### Monitoring & Health (10)

| Script | Doel | Frequency |
|--------|------|-----------|
| `metrics-collector.sh` | Fleet health metrics | Dagelijks |
| `fleet-doctor.sh` | Incident detectie en diagnose | Dagelijks |
| `health-check.sh` | Health check voor alle scripts | Ad-hoc |
| `performance-monitor.sh` | Performance monitor | Ad-hoc |
| `status.sh` | GitHub Fleet Status | Ad-hoc |
| `activity-report.sh` | Rapporteert activiteit van de dag | Ad-hoc |
| `mention-report.sh` | Rapporteert mentions | Ad-hoc |
| `review-request-report.sh` | Rapporteert review requests | Ad-hoc |
| `notification-digest.sh` | Dagelijkse notificatie digest | Ad-hoc |
| `smart-notification-digest.sh` | Slimme notificatie digest | Ad-hoc |

### Self-Management (3)

| Script | Doel | Frequency |
|--------|------|-----------|
| `self-update.sh` | Git pull van fleet-manager repo | Dagelijks |
| `self-monitor.sh` | Script grootte, laatste run, cron jobs | Dagelijks |
| `self-backup.sh` | Backup van script, crontab, config | Maandelijks |

### System & Network (4)

| Script | Doel | Frequency |
|--------|------|-----------|
| `network-scan.sh` | Netwerk scanning | Dagelijks |
| `system-health.sh` | CPU/RAM/Disk/Docker/systemd | Dagelijks |
| `service-check.sh` | HTTP/DNS/VPN status | Dagelijks |
| `log-monitor.sh` | Hermes/system/Docker errors | Dagelijks |

### Integration & Delivery (8)

| Script | Doel | Frequency |
|--------|------|-----------|
| `delivery-router.sh` | Cross-platform delivery | Dagelijks |
| `mcp-github-bridge.sh` | GitHub MCP server bridge | Dagelijks |
| `a2a-bridge.sh` | A2A agent integration bridge | Dagelijks |
| `webhook-handler.sh` | Webhook event handler | Real-time |
| `webhook-server.sh` | Webhook server voor GitHub events | Real-time |
| `model-router.sh` | Model routing per taal/complexiteit | Dagelijks |
| `multi-tool-chaining.sh` | Multi-tool chaining | Wekelijks |
| `multi-repo-coordination.sh` | Cross-repo coordination | Dagelijks |

### Fleet Operations (10)

| Script | Doel | Frequency |
|--------|------|-----------|
| `fleet-automation-suite.sh` | Master automation suite (28 fases) | Dagelijks |
| `fleet-dashboard.sh` | Fleet dashboard (HTML) | Ad-hoc |
| `fleet-dashboard-deploy.sh` | Fleet dashboard deployen als service | Ad-hoc |
| `rd-team-coordinator.sh` | R&D Team Coordinator | Ad-hoc |
| `autonomous-pr-workflow.sh` | Autonomous PR workflow | Ad-hoc |
| `stale-issue-detection.sh` | Detecteer inactieve issues/PRs | Dagelijks |
| `docs-drift-detection.sh` | Detecteert docs drift | Wekelijks |
| `documentation-generation.sh` | Auto-generate API docs | Wekelijks |
| `test-execution-reporting.sh` | Test resultaten als PR comments | Elke 6 uur |
| `automated-dependency-updates.sh` | Auto PRs voor outdated deps | Dagelijks |

### Utilities (10)

| Script | Doel | Frequency |
|--------|------|-----------|
| `generate-docs.sh` | Genereert script documentatie | Ad-hoc |
| `test-suite.sh` | Test suite voor alle scripts | Ad-hoc |
| `run-all-dry-runs.sh` | Batch test alle scripts (dry-run) | Ad-hoc |
| `quality-upgrade.sh` | Batch upgrade scripts | Ad-hoc |
| `cron-audit.sh` | Audit en fix cron jobs | Ad-hoc |
| `rollback.sh` | Rollback mechanisme voor mutaties | Wekelijks |
| `update-scripts.sh` | Automatische dependency updates | Ad-hoc |
| `backup-verify.sh` | Backup verificatie | Wekelijks |
| `branch-cleanup-auto.sh` | Branch cleanup automation | Ad-hoc |
| `branch-protection-auto.sh` | Branch protection automation | Ad-hoc |
| `branch-protection-enforcement.sh` | Branch protection enforcement | Wekelijks |
| `code-quality-metrics.sh` | Code quality metrics | Wekelijks |

### Profile & Resume (3)

| Script | Doel | Frequency |
|--------|------|-----------|
| `profile-data-generator.sh` | Genereert profile-data.json met live statussen | Elke 6 uur |
| `resume-data-publish.sh` | Publiceer profieldata naar git-repo | Ad-hoc |
| `resume-pdf-generate.sh` | Bouw eigen PDF van CV-pagina | Ad-hoc |

### AI Integration (2)

| Script | Doel | Frequency |
|--------|------|-----------|
| `ai-issue-triage.sh` | Automatische issue triage met AI | Ad-hoc |
| `ai-pr-review.sh` | Automatische PR review met AI | Ad-hoc |

## 🏗️ Architectuur

```
fleet-manager/
├── github_fleet_manager.sh  # Monolithische script (fallback, 281KB)
├── lib/
│   ├── config.sh            # Configuratie + helpers + rate limiter + JSON logging
│   └── telegram.sh          # Telegram rapportage
├── scripts/                 # 156 modulaire scripts
│   ├── inbox-*.sh           # Inbox management (21 scripts)
│   ├── actions-*.sh         # GitHub Actions (10 scripts)
│   ├── auto-*.sh            # Auto automation (19 scripts)
│   ├── issue-*.sh           # Issue management (9 scripts)
│   ├── pr-*.sh              # PR management (11 scripts)
│   ├── release-*.sh         # Release management (6 scripts)
│   ├── repo-*.sh            # Repo management (15 scripts)
│   ├── security-*.sh        # Security & compliance (8 scripts)
│   ├── self-*.sh            # Self-management (3 scripts)
│   ├── fleet-*.sh           # Fleet operations (3 scripts)
│   ├── rd-team-coordinator.sh
│   ├── metrics-collector.sh
│   ├── fleet-doctor.sh
│   ├── health-check.sh
│   ├── rollback.sh
│   ├── delivery-router.sh
│   ├── mcp-github-bridge.sh
│   ├── a2a-bridge.sh
│   ├── webhook-handler.sh
│   ├── webhook-server.sh
│   ├── model-router.sh
│   ├── multi-tool-chaining.sh
│   ├── multi-repo-coordination.sh
│   ├── profile-data-generator.sh
│   ├── resume-*.sh
│   └── ...
├── .github/workflows/       # CI/CD
│   ├── ci.yml
│   ├── gource.yml
│   ├── auto-assign.yml
│   ├── labeler.yml
│   ├── release.yml
│   └── stale.yml
├── .env.example             # Environment variabelen template
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── SECURITY.md
├── SUPPORT.md
└── README.md
```

### Architectuur Patronen

#### Modulaire Structuur
- Wrapper script gebruikt modulaire scripts indien beschikbaar
- Monolithische script als fallback
- Elke module is onafhankelijk testbaar
- `set -euo pipefail` in alle scripts voor robuuste error handling
- `DRY_RUN` guard in mutatie-scripts

#### Rate Limiter + Structured Logging
- `rate_limit_check()` — houdt API requests bij, blokkeert bij limiet
- `rate_limit_info()` — toont remaining/limit
- `log_json()` — schrijft JSON-formatted logs

#### Health Check Uitgebreid
- `record_run()` — houdt laatste run timestamp bij
- `check_stale_scripts()` — detecteert scripts die te lang niet hebben gedraaid
- `check_consecutive_failures()` — detecteert opeenvolgende falen
- `check_rate_limit()` — monitort GitHub API rate limit

#### Fleet Doctor
- Detecteert wanneer meerdere scripts tegelijk falen
- Diagnoseert oorzaak (rate limit, netwerk, token, schijf, cron)
- Stuurt alert naar Telegram

#### Rollback Mechanisme
- Houdt de laatste 100 mutaties bij
- `rollback.sh list [count]` — toon laatste mutaties
- `rollback.sh rollback [count]` — draai mutaties terug
- `rollback.sh stats` — toon statistieken

#### Cross-Platform Delivery
- Telegram (via `lib/telegram.sh`)
- Discord (via webhook URL)
- Slack (via webhook URL)
- Email (via SMTP)
- Matrix (via homeserver API)

## 🔧 Installatie

### Vereisten

```bash
# GitHub CLI
brew install gh          # macOS
sudo apt install gh      # Linux

# Dependencies
brew install jq curl     # macOS
sudo apt install jq curl # Linux

# Telegram (optioneel)
# Maak een bot aan via @BotFather op Telegram
```

### Setup

```bash
# 1. Clone de repo
git clone https://github.com/itsdarklikehell/fleet-manager.git
cd fleet-manager

# 2. Maak .env aan
cp .env.example .env
# Vul je tokens in:
# - GH_TOKEN_ITSDARKLIKEHELL (vereist)
# - GH_TOKEN_HMOL33 (optioneel)
# - TELEGRAM_TOKEN (optioneel)
# - TELEGRAM_CHAT_ID (optioneel)

# 3. Maak scripts executable
chmod +x scripts/*.sh
chmod +x lib/*.sh

# 4. Test de installatie
bash scripts/health-check.sh

# 5. Voeg cron jobs toe (optioneel)
crontab -e
# Zie references/cron-schedule.md voor voorbeelden
```

### Gebruik

```bash
# Een script draaien
bash scripts/inbox-reader.sh

# Dry-run mode (geen mutaties)
DRY_RUN=1 bash scripts/auto-merge.sh

# Health check
bash scripts/health-check.sh

# Cron audit
bash scripts/cron-audit.sh

# Test suite
bash scripts/test-suite.sh

# Fleet dashboard genereren
bash scripts/fleet-dashboard.sh

# Fleet dashboard deployen als service
bash scripts/fleet-dashboard-deploy.sh

# Rollback
bash scripts/rollback.sh list 10
bash scripts/rollback.sh rollback 1
bash scripts/rollback.sh stats
```

### Cron Jobs

227 cron jobs draaien via `github_fleet_wrapper.sh`:

```bash
# Dagelijks
0 4 * * * fleet-doctor
30 4 * * * metrics-collector
0 5 * * * dependency-audit
0 8 * * * delivery-router

# Wekelijks
0 5 * * 1 repo-standardizer
30 5 * * 1 rollback stats
0 3 * * 1 docs-drift-detection

# Self-management
0 6 * * * self-update
15 6 * * * self-monitor
0 5 1 * * self-backup
```

Zie `references/cron-schedule.md` voor de volledige lijst met 227 cron jobs.

## 📊 Monitoring

- **Health Check**: `health-check.sh` controleert alle scripts, dependencies en cron jobs
- **Metrics**: `metrics-collector.sh` verzamelt fleet health metrics
- **Fleet Doctor**: `fleet-doctor.sh` detecteert en diagnoseert incidenten
- **Rate Limiter**: In `lib/config.sh` voorkomt API rate limit overschrijding
- **Performance**: `performance-monitor.sh` houdt script execution times bij
- **Dashboard**: `fleet-dashboard.sh` genereert real-time HTML dashboard

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

# Alle scripts in dry-run mode testen
bash scripts/run-all-dry-runs.sh
```

## 📝 Licentie

MIT
