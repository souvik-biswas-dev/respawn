# Runbook

> Written for someone at 2 a.m. who did not build this. Short sentences, exact commands.

## 0. Before anything
- You need: the repo, the **age private key** (from the operator's safe store), a cloud API token, and the DNS provider token.
- Without the age key, secrets cannot be decrypted. Escalate to the key holder.

### Secrets and the age key
Secrets live in Git only as SOPS-encrypted files: `gitops/secrets/*.enc.yaml`, rules in `.sops.yaml`.
Only the values are encrypted. The private key is never in Git or in the release zip.

**Restore the key on a new machine or after a rebuild**
```
make restore-key KEY_FILE=/path/to/keys.txt   # omit KEY_FILE to be asked
make apply-secrets                            # decrypt with sops, kubectl apply
```
`restore-key` installs the key at `~/.config/sops/age/keys.txt` (mode 0600) and stores it as Secret `argocd/sops-age`.
Use `scripts/restore-key.sh KEY_FILE --no-cluster` to skip the cluster part.

**The repo ships with a throwaway DEMO key. Replace it before real use**
```
age-keygen -o keys.txt                        # prints the public key (age1...); store keys.txt in your safe store NOW
# 1. put the new public key in .sops.yaml (the "age:" line)
# 2. re-encrypt each secret with the OLD key still available, to the new recipient:
SOPS_AGE_KEY_FILE=old-keys.txt sops updatekeys gitops/secrets/canary-postgres.enc.yaml
# 3. change the password itself: sops gitops/secrets/canary-postgres.enc.yaml  (opens an editor)
# 4. destroy the demo key
make lint-secrets                             # fails if any value is left in plaintext
```
Keep at least two copies of the key in two places. Losing it means re-creating every secret by hand.

**Add or change a secret**: `sops gitops/secrets/<name>.enc.yaml` (new files must match `.sops.yaml`), then `make lint-secrets`, commit, `make apply-secrets`.

## 1. Is it really down?
```
make status        # runs the health check from docs/DRILLS.md
```
If the server answers SSH but the app is down, go to section 3. If the server is gone, section 2.

## 2. Server is gone: full rebuild
```
make plan
make apply         # recreates VM, firewall, DNS
make bootstrap     # ansible: harden, k3s, argocd
make restore-key   # installs the age key locally and as a k3s secret (prompts for the key file path)
make apply-secrets # decrypts gitops/secrets and applies them (canary pods need this)
make restore-data  # restores Postgres from the newest backup in the S3 bucket, then resumes backups
make status
```
Expected time: recorded in `drills/results/summary.json`. Do not trust a number there unless `mode` is `real`.

## 3. Server up, k3s down
```
ssh <host> 'sudo systemctl status k3s'
ssh <host> 'sudo systemctl restart k3s'
```
Then `make status`.

## 4. Disk full
```
ssh <host> 'df -h; sudo du -xh /var --max-depth=2 | sort -h | tail'
```
Remove the largest safe item (old logs, filler). Confirm Postgres accepts writes: `make status`.

## 5. Backups (BackupVouch)
BackupVouch runs hourly in namespace `canary`: dump, upload to the off-server S3 bucket, restore into a scratch Postgres, run the checks, prune old ones. Read the verdict:
```
kubectl -n canary get backuppolicy canary-db     # VERIFIED column; kubectl describe shows events and the failing check
kubectl -n canary get jobs -l app.kubernetes.io/managed-by=backupvouch
```
`BackupStale` means no backup has been **restored and verified** for 90 minutes, or the metric is missing. Look at Grafana "Respawn / Backups", then the job logs, and BackupVouch's own RUNBOOK (reasons such as `SourceUnreachable`, `StorageUnreachable`, `SecretMissing`, `CheckFailed`). Re-run a verification of the newest backup: `kubectl -n canary annotate backuppolicy canary-db backupvouch.pages.dev/reverify="$(date +%s)" --overwrite`.

**The policy is committed suspended.** A rebuilt server has an empty database, and a backup of it would eventually replace the good ones. So after a rebuild, `make restore-data` restores first and resumes backups only after it succeeds (`--keep-suspended` to resume later by hand). On a brand-new install with nothing to restore, run `make resume-backups` once. ArgoCD ignores `spec.suspend` so these commands stick.

Restore needs the `aws` CLI (v2) and reads the bucket address and keys from the cluster, so the Secret `backupvouch-s3` must already be applied (`make apply-secrets`). `make restore-data RESTORE_ARGS="--dry-run"` shows which object it would use without changing anything; `--object KEY` picks another one.

### Look at monitoring
```
kubectl -n monitoring port-forward svc/kps-grafana 3000:80          # http://localhost:3000, login from the grafana-admin Secret
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090     # Alerts tab shows pending/firing
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093
```
Alert notifications go to the webhook in Secret `alertmanager-webhook` (key `url`); until it is created with a real URL nothing is delivered.
Dashboards: Node and disk, Backups, Canary (RPO view), Alert overview. `Watchdog` always fires on purpose; if it ever stops, alerting is broken.
A dead single node cannot alert about itself. Point an external dead-man's switch at the Watchdog alert if you need that.

## 6. After recovery
- Record what happened and how long it took.
- Run `make drill-all DRILL_ARGS="--host respawn-1 --via local --age-key keys.txt --yes-really"` in a quiet window to refresh the numbers (see "Drills" below).
- File a note in `docs/PROGRESS.md` or your incident tracker.

## Drills
Each drill needs `--host NAME` (an inventory host) and `--yes-really`, waits 10 seconds, and refuses an inventory host with `respawn_protected: true`.
```
make status                                                    # the health check, one shot
make drill-simulate                                            # no server; results are labelled SIMULATED
make drill-kill   DRILL_ARGS="--host respawn-1 --yes-really"   # kill k3s
make drill-disk   DRILL_ARGS="--host respawn-1 --yes-really"   # fill the data disk to 97%, always cleans up
make drill-delete DRILL_ARGS="--host respawn-1 --via local --age-key keys.txt --yes-really"   # DESTROYS the server, rebuilds it
make drill-all    DRILL_ARGS="..."                             # all three, then summary.json
make drill-validate                                            # results against the schemas
```
`--via local` uses Multipass, `--via terraform` uses `infra/terraform/envs/prod` (`TF=tofu` works). A drill that times out exits non-zero and writes no result file. If `fill-disk` is interrupted and cannot reach the server, it prints the `ssh ... rm -f` command that removes its filler file.

## Make targets (must exist)
`plan apply bootstrap restore-key apply-secrets restore-data status drill-kill drill-disk drill-delete drill-all lint zip`
Already present: `status`, `drill-kill`, `drill-disk`, `drill-delete`, `drill-all`, `drill-simulate`, `drill-validate`, `lint-drills`, `restore-data`, `resume-backups`, `lint-alerts` (alert rules and their tests), `lint-backup`, `lint-gitops`, `lint-secrets`, `lint-ansible`.
