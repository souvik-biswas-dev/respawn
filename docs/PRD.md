# PRD: Respawn

## Problem
A small team's single server dies at 2 a.m. Nobody can say: could we rebuild it, how long would it take, would the data survive? Most infra repos show a deploy. They never show a recovery.

## Goal
A reference platform where **recovery is a tested, measured feature**, not a hope. A reader opens the repo and sees real RTO/RPO numbers produced by scripts they can re-run.

## Audience
1. Prospective clients and hiring managers judging the author's DevOps skill from a public repo.
2. Small teams (2-15 people) who want to copy the pattern.

## Non-goals
- Multi-region, multi-cluster, service mesh, or anything needing a big budget.
- A product with accounts or a database of its own. The console is a static site.
- Fake numbers. See hard rule 1 in `CLAUDE.md`.

## Scope (v1)
| Area | Deliverable |
|---|---|
| Provisioning | Terraform for 1 server (provider-agnostic variables, Hetzner default), firewall, DNS, remote-state option |
| Hardening | Ansible: SSH, ufw, fail2ban, unattended upgrades, auditd basics, k3s install |
| GitOps | k3s + ArgoCD app-of-apps; Git is source of truth |
| Secrets | SOPS + age, encrypted files committed |
| Observability | Prometheus, Alertmanager, Grafana (dashboards as code), Loki + Promtail |
| Alerts | Disk filling, certificate expiring, backup stale, node down, pod crashloop, canary write gap |
| Backups | BackupVouch layer + backup freshness metric feeding Alertmanager |
| Canary workload | Postgres + a writer that inserts a sequence number every second, so RPO is measurable |
| Drills | `kill-node`, `fill-disk`, `delete-server`: break, recover, record RTO/RPO as JSON |
| Console | Static site that renders drill results as a flight-recorder timeline |
| CI | Validate Terraform, Ansible, manifests, alert rules, shell, secrets scan |

## Success criteria
- `make drill-all` produces three result JSON files with RTO and RPO.
- Alert rules pass `promtool test rules`.
- All validators pass in CI.
- README table shows measured numbers (once the author has run real drills) and labels anything simulated.
- Console loads in under 2 seconds and reads clearly on mobile.

## Metrics definitions
- **RTO** = seconds from the moment the fault is injected to the moment the health check passes end-to-end (app answers and canary writes resume).
- **RPO** = seconds of data lost = gap between the last canary sequence number present after recovery and the last one written before the fault.

## Risks
| Risk | Handling |
|---|---|
| Cannot run real cloud drills during generation | `--simulate` mode, labelled everywhere; author runs real ones later |
| BackupVouch API unknown to the AI | Adapter + ask user for docs (step 6) |
| Free AI limits cut a session mid-step | Small steps, PROGRESS.md, zip after every step |
