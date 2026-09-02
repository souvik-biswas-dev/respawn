# Architecture

## Repo layout (fixed)
```
respawn/
├── README.md
├── CLAUDE.md
├── Makefile
├── .sops.yaml
├── .github/workflows/ci.yml
├── docs/            PRD, ARCHITECTURE, DESIGN, DRILLS, RUNBOOK, PLAN, PROGRESS
├── infra/
│   ├── terraform/   modules/{server,firewall,dns}  envs/prod
│   └── ansible/     inventory/  roles/{hardening,k3s,argocd_bootstrap}  site.yml
├── gitops/
│   ├── bootstrap/   argocd install + root app
│   ├── apps/        app-of-apps children
│   │   ├── monitoring/   prometheus, alertmanager, grafana, loki
│   │   ├── backupvouch/  backup layer + freshness exporter
│   │   └── canary/       postgres + writer
│   └── secrets/     SOPS-encrypted manifests
├── drills/
│   ├── lib/         common.sh (timing, health check, result writer)
│   ├── kill-node.sh  fill-disk.sh  delete-server.sh  run-all.sh
│   ├── schema/      result.schema.json
│   └── results/     one JSON per run
├── site/            Respawn Console (static)
└── scripts/         make-zip.sh, lint helpers
```

## Flow
```
 git push ──► ArgoCD (in k3s) ──► apps (monitoring, backupvouch, canary)
 terraform apply ──► server ──► ansible (harden + k3s + argocd) ──► ArgoCD pulls Git

 Prometheus ──► Alertmanager ──► (webhook / email, configurable)
 Promtail ──► Loki ──► Grafana
 BackupVouch ──► backup freshness metric ──► Prometheus alert "BackupStale"
 canary writer ──► Postgres (sequence every 1s) ──► metric canary_last_seq
```

## Recovery path (what `delete-server` proves)
1. Server destroyed.
2. `terraform apply` recreates VM, firewall, DNS.
3. Ansible hardens it and installs k3s + ArgoCD.
4. ArgoCD syncs everything from Git; SOPS key restored from the operator's safe store.
5. Postgres data restored from the BackupVouch-managed backup.
6. Health check passes and canary writes resume. The timer stops. RTO recorded.
7. First canary sequence after restore vs last before fault gives RPO.

## Key decisions
| Decision | Why |
|---|---|
| Single node k3s | Matches the real small-team case; honest about the limits |
| ArgoCD app-of-apps | One root, everything else is Git |
| SOPS + age | No external secret store to run or pay for |
| Canary writer | Makes RPO a number, not a feeling |
| Static console | Nothing to host or secure; reads drill JSON |
| Provider variables | Hetzner default, swappable; no lock-in claims |

## Alerts (names are fixed so tests and docs agree)
`DiskFillingSoon`, `DiskCritical`, `CertExpiringSoon`, `BackupStale`, `NodeDown`, `PodCrashLooping`, `CanaryWriteGap`.

## Known limits (state them in the README)
Single node means a node loss is an outage until rebuilt. The drills measure how long, they do not remove it.
