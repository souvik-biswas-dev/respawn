# Drills spec

A drill breaks something on purpose, waits for recovery, and writes a result file. Drills must work against real infra; `--simulate` exists only so the tooling and console can be developed without a server.

## Common contract
Every drill sources `drills/lib/common.sh` and:
1. Runs a **pre-check** (stack healthy, canary writing). Abort if not.
2. Records `fault_injected_at` (UTC, ISO-8601) and `last_seq_before` (canary).
3. Injects the fault.
4. Triggers or waits for recovery, polling the **health check** every 5s up to a timeout.
5. Records `recovered_at`, `first_seq_after`.
6. Computes `rto_seconds` and `rpo_seconds`, writes `drills/results/<drill>-<UTC timestamp>.json`.
7. Exits non-zero if recovery timed out.

## Result schema (`drills/schema/result.schema.json`)
```json
{
  "drill": "delete-server",
  "mode": "real",
  "started_at": "2026-11-02T10:00:00Z",
  "fault_injected_at": "2026-11-02T10:00:05Z",
  "recovered_at": "2026-11-02T10:17:42Z",
  "rto_seconds": 1057,
  "last_seq_before": 88421,
  "first_seq_after": 88377,
  "rpo_seconds": 44,
  "alerts_fired": ["NodeDown", "CanaryWriteGap"],
  "steps": [{"name": "terraform apply", "seconds": 212}],
  "notes": "",
  "environment": {"provider": "hetzner", "server_type": "cx22"}
}
```
`mode` is `real` or `simulated`. Simulated files must also carry `"label": "SIMULATED"`.

## Health check (definition of "recovered")
All must be true: k3s API answers, ArgoCD apps Healthy/Synced, app endpoint returns 200, canary sequence is increasing across two consecutive polls.

## Drills
### kill-node
Stop the k3s service on the server (`systemctl kill k3s`). Recovery: systemd restart or manual start per runbook. Expected alerts: `NodeDown` or `PodCrashLooping`.

### fill-disk
Create a large file until the data disk passes 95%. Recovery: remove the file, confirm Postgres writable. Expected alerts: `DiskFillingSoon`, `DiskCritical`. The drill must delete its own filler file on exit, even on failure (trap).

### delete-server
Destroy the VM via Terraform or the provider API, then run the full rebuild path from `ARCHITECTURE.md`. Requires typing the server name to confirm. This is the headline number.

## Safety
- Every destructive drill needs `--yes-really` plus the target host name.
- Refuse to run against an inventory marked `protected: true`.
- Each drill prints what it will do and waits 10s before starting.

## Aggregation
`drills/run-all.sh` runs the three in order and writes `drills/results/summary.json` with latest RTO/RPO per drill. The console and README table read from there.

## Implementation notes (step 7)
- Options: `--host NAME` + `--yes-really` (destructive), `--simulate`, `--inventory`, `--results-dir`, `--countdown N`, `--timeout N`. `delete-server` also needs `--via terraform|local` and `--age-key FILE`, and asks you to type the server name when stdin is a terminal (`--no-prompt` skips it).
- The scripts reach the cluster through the API server's service proxy using `.kubeconfig/respawn.yaml`; no port-forward. Prometheus is read the same way, so `alerts_fired` is read back after recovery (`ALERTS` firing since the fault, Watchdog excluded). When Prometheus cannot be queried, or is destroyed with the server (`delete-server`), the list is empty and `notes` says so.
- Health check additions: a suspended BackupPolicy counts as not recovered; `RESPAWN_APP_URL` optionally adds a public URL that must return 200.
- RPO = rows lost x `WRITE_INTERVAL_SECONDS` (default 1). For `delete-server`, `first_seq_after` is the highest seq that survived the restore (from `restore-data.sh`), not the first row written afterwards.
- `fill-disk` fills to 97%, not 100%, so Postgres normally keeps writing; its RTO is mostly the time until `DiskCritical` fires (rule `for: 5m`). `DiskFillingSoon` has `for: 30m` and usually does not fire inside the wait.
- `--simulate` writes `"mode": "simulated"` and `"label": "SIMULATED"`; its `alerts_fired` is the expected set, not an observation. Result filenames: `<drill>-<UTC start>.json`; the committed `sample-*.json` are simulated.
- `summary.json` (schema `summary.schema.json`): per drill the newest REAL run, otherwise the newest simulated one; `sample-*` files are ignored.
