# Fleet Manager Architectuur

## Overzicht

De Fleet Manager is een modulaire bash-applicatie voor het beheren van GitHub repositories, CI/CD, monitoring, en automatisering.

## Architectuur

```
fleet-manager/
├── github_fleet_manager.sh    # Hoofdscript (6166 regels)
├── scripts/                   # 191 modulaire scripts
│   ├── health-check.sh        # Health check
│   ├── test-suite.sh          # Test suite
│   ├── fleet-dashboard.sh     # Dashboard generatie
│   ├── metrics-collector.sh   # Metrics verzamelen
│   └── ...                    # 187 andere scripts
├── lib/                       # 22 library files
│   ├── config.sh              # Configuratie
│   ├── logging.sh             # Logging functies
│   ├── telegram.sh            # Telegram integratie
│   ├── github.sh              # GitHub API helpers
│   └── ...                    # 18 andere libraries
├── tests/                     # Test files
│   ├── test-unit.sh           # Unit tests
│   ├── test-e2e.sh            # E2E tests
│   └── test-integration.sh    # Integration tests
├── docs/                      # Documentatie
├── .github/workflows/         # CI/CD workflows
├── Makefile                   # Build automation
└── Dockerfile                 # Container image
```

## Design Principles

1. **Modulariteit** — Elke functionaliteit is een apart script
2. **Herbruikbaarheid** — Gemeenschappelijke functies in lib/
3. **Testbaarheid** — Unit tests, E2E tests, integration tests
4. **Documentatie** — Elke script heeft een header met beschrijving
5. **Error Handling** — Consistente error handling met set -euo pipefail
6. **Logging** — Gestructureerde logging naar bestanden en Telegram

## Script Categorieën

| Categorie | Aantal | Beschrijving |
|-----------|--------|--------------|
| Inbox Management | 17 | Notificaties lezen, classificeren, antwoorden |
| Fleet Management | 20 | PRs, issues, releases, branches |
| Monitoring | 15 | Systeem, netwerk, Docker, systemd |
| Security | 12 | SSL, port scanning, secret scanning |
| Backup | 8 | Config backups, Docker volumes |
| Telegram | 10 | Berichten, rapportage, alerts |
| Self-Management | 8 | Self-update, self-monitor, self-backup |
| R&D Team | 10 | Repo verdeling, team coordinatie |
| Release | 8 | Release automation, changelog |
| Dependency | 10 | Dependency updates, audits |
| Quality | 8 | Code quality, metrics |
| Other | 73 | Diverse scripts |

## CI/CD Pipeline

1. **Bash Syntax Check** — Alle scripts controleren
2. **Shellcheck** — Static analysis
3. **Test Suite** — Unit tests + E2E tests
4. **Security Scan** — Trivy vulnerability scanner
5. **Dependency Check** — Dependency audit

## Deployment

### Lokale installatie
```bash
make install
```

### Docker
```bash
make docker-build
make docker-run
```

### Cron
```bash
# Elke 4 uur
0 */4 * * * /path/to/github_fleet_manager.sh inbox-reader
```

## Toekomstige Verbeteringen

- [ ] Meer unit tests per script
- [ ] Python rewrite van kritieke scripts
- [ ] Web UI voor dashboard
- [ ] API voor externe integratie
- [ ] Plugin systeem voor custom scripts
