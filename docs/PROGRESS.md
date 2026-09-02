# PROGRESS

Update this at the end of every step. This file is how a fresh AI session (or a new account) knows where to resume.

**Current step:** 10 done. The build is COMPLETE. Nothing has been run against a real server, and the CI workflow has NEVER run on GitHub. What is left is in "Only you can do this" below.
**Last zip:** respawn-step-10.zip (final release)

## Checklist
- [x] Step 0: docs pack
- [x] Step 1: Terraform
- [x] Step 2: Ansible hardening + k3s
- [x] Step 3: GitOps + canary workload
- [x] Step 4: SOPS secrets
- [x] Step 5: Observability + alerts + alert tests (promtool check+test and kubeconform now PASS locally, see Step 9 validators; helm rendering still not run)
- [x] Step 6: BackupVouch integration (written against BackupVouch's real docs; nothing run against a cluster)
- [x] Step 7: Drills (shellcheck + schema validation PASS; real paths exercised only against stand-in commands, never a real server)
- [x] Step 8: Respawn Console (site) (build + screenshots PASS; only ever shown sample data)
- [x] Step 9: CI + README polish (local lint PASS except terraform validate and ansible-lint; CI itself not yet run)
- [x] Step 10: Final QA + release zip (consistency checks and lint re-run PASS; see Validators run)

## Files added per step
- Step 1: `infra/terraform/modules/server/{main,variables,outputs,versions}.tf` + `cloud-init.yaml.tftpl`;
  `infra/terraform/modules/firewall/{main,variables,outputs,versions}.tf`;
  `infra/terraform/modules/dns/{main,variables,outputs,versions}.tf`;
  `infra/terraform/envs/prod/{main,variables,outputs,versions}.tf` + `terraform.tfvars.example`;
  `Makefile` (help, init, fmt, validate, plan, apply, destroy-confirm); `.gitignore`.
- Step 2: `infra/ansible/{ansible.cfg,site.yml,requirements.yml}`, `inventory/hosts.example.yml`;
  roles `hardening` (ssh, ufw, fail2ban, unattended-upgrades, sysctl, auditd, chrony), `k3s` (pinned install, kubeconfig fetch),
  `argocd_bootstrap` (pinned manifest, root app from a template). Makefile: `ansible-deps`, `bootstrap`, `lint-ansible`.
  `.gitignore` now also ignores `.kubeconfig/` and `infra/ansible/inventory/hosts.yml`.
- Step 3: `gitops/bootstrap/root-app.yaml`; `gitops/apps/{kustomization.yaml,canary-app.yaml}`;
  `gitops/apps/canary/` (kustomization, namespace, postgres service + statefulset, writer service + deployment,
  `pvc-size.patch.yaml`, `secret.example.yaml`, `writer/{app.py,Dockerfile}`).
  Extra, requested by the author (free hosting): `infra/local/multipass-vm.sh` (free local VM). Makefile: `lint-gitops`, `local-up`, `local-destroy`.
- Step 4: `.sops.yaml`; `gitops/secrets/canary-postgres.enc.yaml` (SOPS + age, values only); `scripts/{apply-secrets,restore-key,check-secrets}.sh`;
  Makefile `restore-key`, `apply-secrets`, `lint-secrets`; RUNBOOK section 0 rewritten (key restore, rotation from the demo key, adding secrets), section 2 and make-target list updated;
  comment in `canary/secret.example.yaml` updated. Mechanism: **sops decrypt then kubectl apply** (not ksops: no custom ArgoCD image, one readable command).
- Step 5: `gitops/apps/monitoring-apps.yaml` (4 Applications: `monitoring-stack` = kube-prometheus-stack, `loki`, `promtail`, `monitoring-config`), listed in `gitops/apps/kustomization.yaml`;
  `gitops/apps/monitoring/{kustomization,respawn-rules,canary-servicemonitor}.yaml`, `probe.example.yaml` (not applied), `values/{kube-prometheus-stack,loki,promtail}.yaml`,
  `dashboards/{disk,backups,canary,alerts}.json` (ConfigMaps via configMapGenerator, Grafana sidecar label); `alerts/tests/*.yaml` (7 files, positive and negative cases);
  `scripts/check-alerts.sh`; `gitops/secrets/{alertmanager-webhook,grafana-admin}.example.yaml`; Makefile `lint-alerts` and monitoring added to `lint-gitops`;
  RUNBOOK section 5 (monitoring access) and make-target note. Canary writer comment corrected (scraping is the ServiceMonitor).
  The rules live once, in the PrometheusRule manifest; `check-alerts.sh` extracts them for promtool (no duplicated copy to drift).
- Step 6: built against the real BackupVouch repo (user uploaded `backupvouch-main.zip`: docs/API.md, INSTALL.md, MONITORING.md, ARCHITECTURE.md, RUNBOOK.md, CRD, manifests). Nothing invented.
  `gitops/apps/backupvouch-apps.yaml` (Applications `backupvouch-operator`, `backupvouch-config`), listed in `gitops/apps/kustomization.yaml`;
  `gitops/apps/backupvouch/operator/kustomization.yaml` (BackupVouch's release `install.yaml`, v0.1.0);
  `gitops/apps/backupvouch/config/{kustomization,canary-backuppolicy,servicemonitor,metrics-reader-binding}.yaml`;
  `gitops/secrets/{canary-backup-pg,backupvouch-s3}.example.yaml`; `drills/restore-data.sh`; Makefile `restore-data`, `resume-backups`, `lint-backup` (+ BackupVouch config in `lint-gitops`);
  RUNBOOK section 5 rewritten (BackupVouch, suspended policy, restore) and the make-target note.
  **No separate exporter was built:** BackupVouch already exports `backupvouch_last_verified_timestamp_seconds` etc.
  A recording rule in `respawn-rules.yaml` maps it to `backup_last_success_timestamp_seconds` (max by namespace, policy), so alert, dashboard and drills keep one stable name.
  Step 5 changes: `BackupStale` threshold 26h -> 90 min (1.5 x the hourly schedule); its tests, a new `alerts/tests/backup-metric-mapping.yaml`, and the Backups dashboard (policy legend, new thresholds, Loki query for the Jobs in `canary`) were updated to match.
- Step 7: `drills/lib/common.sh` (timing, health check, canary reads via the API proxy, Prometheus reads, JSON writer, simulate helpers, summary writer),
  `drills/{kill-node,fill-disk,delete-server,run-all,status,validate-results}.sh`, `drills/schema/{result,summary}.schema.json`,
  `drills/results/{.gitkeep,sample-kill-node.json,sample-fill-disk.json,sample-delete-server.json}` (all SIMULATED, generated by the tool's own `--simulate`).
  Makefile: `status`, `drill-kill`, `drill-disk`, `drill-delete`, `drill-all`, `drill-simulate`, `drill-validate`, `lint-drills`. RUNBOOK: "Drills" section, make-target note, section 6 command. `docs/DRILLS.md`: "Implementation notes (step 7)".
  Extras beyond the PLAN list, because RUNBOOK/DRILLS need them: `status.sh` (`make status`), `validate-results.sh`, `summary.schema.json`.
- Step 8: `site/` (Vite 5 + TypeScript, vanilla): `package.json` + `package-lock.json`, `index.html`, `src/{main,data,trace}.ts`, `src/style.css`, `site/scripts/copy-data.mjs`.
  `copy-data.mjs` runs before every build: copies `drills/results/summary.json` entries (or the newest real, else newest simulated per-run files) into `site/public/data/` and writes `index.json`; with no results it uses `sample-*.json` and `index.json` says `"source": "sample"`.
  Fonts self-hosted via Fontsource (Instrument Serif regular+italic, JetBrains Mono 400/700, latin subset); D3 = d3-scale + d3-shape only; GSAP core + ScrollTrigger. Makefile `site-build`. `.gitignore`: `site/node_modules`, `site/dist`, `site/public/data`.
  Page: persistent amber SIMULATED banner, REC header (latest run, mode, source), serif RTO headline, three scroll-replayed traces (each with the canary row strip and the RPO hole), alert tags (dashed + note when simulated), the drill `notes`, rebuild ledger (delete-server, clock times derived from step durations), three copyable commands, footer.
- Step 9: `.github/workflows/ci.yml` (8 parallel jobs: terraform, ansible, gitops, alerts, shell-and-drills, gitleaks, site, docs), `scripts/install-ci-tools.sh` (pinned downloads, SHA-256 verified),
  `scripts/check-doc-links.sh`, `.gitleaks.toml`, `.tflint.hcl`, README rewrite. Makefile: `lint-shell`, `lint-terraform`, `lint-leaks`, `lint-docs`, `lint` (all of CI except the site build), `zip STEP=n`.
  Fixed: `alerts/tests/*.yaml` (9 firing cases) gained `exp_annotations`: promtool failed them without. Docs: PLAN.md rules path, PROGRESS.md copy-data path.

## Only you can do this
1. **Create the GitHub repo**, replace every `YOUR-USER` (gitops Application files, `hosts.example.yml`, `multipass-vm.sh`) and the canary image name (`gitops/apps/canary/kustomization.yaml`), build and push the canary image, then push. Watch the first CI run: its pins are untested on a runner (see Open issues).
2. **Generate your own age key** (`age-keygen`), re-encrypt the secrets, and keep the key somewhere off the server (RUNBOOK section 0). The committed secret cannot be decrypted by anyone, by design.
3. **Create the real secrets** as `*.enc.yaml`: `canary-backup-pg`, `backupvouch-s3`, `alertmanager-webhook`, `grafana-admin` (only `*.example.yaml` exist).
4. **Get an off-server S3 bucket**, put its real endpoint in `canary-backuppolicy.yaml` (now `s3.example.invalid:443`) and confirm BackupVouch v0.1.0's `install.yaml` and images are reachable.
5. **Provide a server**: a free local Multipass VM (`make local-up`) or a paid Hetzner server with a real API token in `terraform.tfvars` (never commit it). Check `server_type`, k3s, ArgoCD and chart version pins against upstream first.
6. **Run the real drills** (`make drill-all` with `--yes-really`), expect to fix the unverified assumptions listed under Open issues, then commit the `mode: real` result files and `make site-build`.
7. **Paste numbers into the README table only from `mode: real` files.** Until then it stays "pending".
8. Run `terraform validate` and a full `ansible-lint` yourself or via CI: neither could run to completion in the sandbox.

## Validators run
- Step 10 (re-run with the pinned tools, all installed fresh and SHA-256 verified): `make lint-alerts` (promtool check + test, 8 test files SUCCESS), `lint-gitops` (kubeconform -strict), `lint-shell`, `lint-secrets`, `lint-drills`, `lint-docs` (9 files, 0 broken), `lint-leaks` (gitleaks, working tree, no leaks): all PASS. Site `npm ci` + `npm run build` PASS (JS 58.0 KB gzip). Every `make X` named in docs/README exists in the Makefile. Alert names agree across ARCHITECTURE.md, the rules (7 alerts + 1 recording rule) and tests. All three result files are `mode: simulated` + `label: SIMULATED`; the README table is still pending. No private key or token in the tree.
  Fixed: README said "eight alert rules"; it is seven alerts plus one recording rule.
  **Still not run:** `terraform validate`/`init`, a full `ansible-lint`, helm rendering, the workflow on GitHub, gitleaks over git history (the zip has no `.git`), and everything against a real server.
- Step 1: `terraform` itself is not installable in the sandbox (releases.hashicorp.com is blocked). Used **OpenTofu 1.8.5**
  (Terraform-compatible, from GitHub releases) with provider zips (hcloud 1.49.1, cloudflare 4.52.1) from a local mirror.
  `fmt -check -recursive`: PASS. `init -backend=false`: PASS. `validate`: PASS.
  Not run: `plan`/`apply` (needs real API tokens; would create billed servers). Keep `terraform validate` in CI (Step 9).
- Step 2: `ansible-lint site.yml roles`: PASS at profile `production` (0 failures, 0 warnings). `ansible-playbook --syntax-check`: PASS.
  Also checked: the `respawn_protected` latch fails without `-e confirm_protected=yes` and passes with it (local test);
  the ssh, fail2ban, k3s config and root-app templates render as expected.
  Collections came from the PyPI `ansible` package (Galaxy is blocked in the sandbox); `requirements.yml` is for real use.
- Step 3: `kustomize build` (apps and canary): PASS. `kubeconform -strict` (with ArgoCD CRD schemas) on all rendered manifests,
  root-app and secret example: PASS, 0 skipped. `pyflakes` on app.py: PASS. `shellcheck -x` on multipass-vm.sh: PASS.
  **Real test of the writer** against PostgreSQL 16 in the sandbox: 1 row/second, `/healthz` 200; with the database killed `/healthz` 503,
  `/livez` 200, `/last-seq` 503, error counter rising; after restart writes resumed and the table had no gaps or duplicates (count = max seq).
  The multipass script was tested against a stand-in `multipass` command only (real Multipass is not installed here). It caught and fixed one bug.
  Not run: building the Docker image (no Docker in the sandbox), and nothing was deployed to a cluster.
  **Never run against a real server.** The roles are untested end to end, in particular `kubernetes.core.k8s` server-side apply of the ArgoCD manifest.
- Step 4: `sops 3.9.4` + `age`: encrypt, decrypt round-trip PASS; decrypt with a wrong key fails (exit 128) as it should.
  `shellcheck -x` on the three new scripts: PASS. `kubeconform -strict` on the decrypted Secret: PASS (schemas from a local clone of yannh/kubernetes-json-schema; raw.githubusercontent.com is blocked in the sandbox).
  `check-secrets.sh`: passes on the encrypted file and fails when a value is replaced by plaintext (tested). `kustomize build` of apps and canary still PASS.
  `restore-key.sh` tested locally (installs at mode 0600, rejects a non-key file). `apply-secrets.sh --dry-run` tested against a **stand-in `kubectl`** that captured what it was fed; real kubectl and a real cluster were not available, so the namespace-create and apply path is untested against a cluster.
- Step 5: **promtool is not installed in the sandbox and there is no network, so `promtool check rules` and `promtool test rules` were NOT run.** Same for `helm template`, `kustomize build` and `kubeconform` on the monitoring files.
  What did run: all new YAML parses; dashboard JSON parses; every file referenced by the kustomization and the Application valueFiles exists;
  `check-alerts.sh --structure-only` passes (the 7 names in ARCHITECTURE.md = rules = tested alert names) and fails when a test file is removed (tested);
  `--help` works; without promtool the script exits 2 with a clear message. `shellcheck` not available, so `check-alerts.sh` is unlinted.
  The PromQL expressions and the expected test outcomes were reasoned by hand only. **Run `make lint-alerts` and `make lint-gitops` first; expect to fix a test or two.**
- Step 6: **Not run: promtool, kustomize, kubeconform, shellcheck, helm (not in the sandbox), and nothing was applied to a cluster.**
  What did run: the BackupPolicy checked against BackupVouch's real CRD schema with a small Python walker (every field exists, required fields present, types and enums, name length 9 <= 45): no errors;
  all YAML parses; `check-alerts.sh --structure-only` passes (7 alert names still agree); `bash -n` on `restore-data.sh`; `restore-data.sh` exercised against **stand-in `kubectl` and `aws` commands**:
  --dry-run changes nothing, picks the newest of several keys by sort, filters non-.dump objects, refuses the placeholder endpoint, streams into `pg_restore`, suspends before and resumes after,
  a failed download exits non-zero and does NOT resume, `--resume-only` only patches. Real `pg_restore`, the AWS CLI against a real bucket, and a real cluster were not available.
- Step 7: `shellcheck -x` on every drill script and `lib/common.sh` (and `restore-data.sh`): PASS, 0 findings. `--help` works on all six scripts.
  `--simulate` of each drill and `run-all.sh --simulate` run end to end, and every file they write (3 results + summary.json) validates against the JSON schemas with python `jsonschema` 4.26 (Draft 7).
  A hand-broken result (missing label, negative RTO) is rejected with exit 1. The 3 committed samples are `mode: simulated` + `label: SIMULATED` and validate.
  Safety refusals tested: no `--host`, no `--yes-really`, unknown host, `respawn_protected: true` host, unknown option, missing `--via`.
  **Real code paths tested only against STAND-IN commands** (fake `kubectl`, `ssh`, `df`, `fallocate`, `terraform`, `ansible-playbook`, `sops`, `aws` in a temp PATH; they live outside the repo): fill-disk happy path (filler created, DiskCritical seen, filler removed, result valid),
  fill-disk when the cluster never recovers (exit 1, filler removed by the EXIT trap, no result file), fill-disk killed with SIGTERM during the alert wait (exit 143, filler removed), kill-node with automatic recovery, with the manual-restart fallback, and with a timeout (exit 1, no result),
  delete-server through every step with stand-ins, using the REAL `restore-key.sh`, `apply-secrets.sh` and `restore-data.sh` against the fake kubectl/aws (RPO taken from `restored_last_seq`; ansible got `-e ansible_host=<new ip>`).
  Those results said "mode: real" because the code cannot tell a stand-in from the real thing: they were deleted and are not in the zip.
  **Not run: any drill against a real cluster, server, Multipass VM or Terraform; the real `terraform destroy -target=module.server` dependency behaviour; real `fallocate`/`df --output` on the server; Prometheus queries through the API proxy; the `kps-prometheus` service name.**
  `make drill-simulate`, `make lint-drills` dry-run as targets; `make status` run against the stand-in only. Still not installed here: promtool, kustomize, kubeconform, helm (Steps 5 and 6 checks still pending).
- Step 8: `tsc --noEmit` and `vite build`: PASS. JS 145.5 KB raw, **57.7 KB gzip** (limit 150 KB); CSS 2.1 KB gzip; fonts are separate woff2/woff files (about 21 KB each, not JS).
  Headless Chromium (Playwright 1.56, bundled browser): desktop 1440 and mobile 360 screenshots reviewed; no console or page errors; no horizontal page overflow at 360 (the traces scroll inside their own box, with a visible hint);
  `prefers-reduced-motion: reduce` emulated: no stroke dashing, all markers visible, REC dot not blinking. Scroll replay checked by scrolling into each trace and re-shooting.
  **Not run:** Lighthouse itself (not installed; only the size budget and the manual checks above), a contrast checker (colours are from DESIGN.md; muted text `#a29f8c` on `#0b0c0a` is about 7:1 by calculation, not measured), any real browser other than Chromium, the site against REAL result files (only samples exist).
- Step 9, run locally for the first time with real tools downloaded from GitHub releases (each SHA-256 matched the publisher's checksum file): promtool 3.15.1, kustomize v5.8.3, kubeconform v0.8.0, gitleaks 8.30.1, tflint 0.65.0, OpenTofu 1.13.2, shellcheck, ansible-lint 26.10.1.
  - `make lint-alerts` PASS: 8 rules, 8 test files all SUCCESS. **It first FAILED**: the 9 tests that expect an alert to fire lacked `exp_annotations` (promtool compares them). Fixed by adding the exact summary/description text each rule produces.
  - `make lint-gitops` PASS: kubeconform -strict with the datree CRD catalogue: apps 7/7, canary 5/5, monitoring 6/6, backupvouch config 2 valid + BackupPolicy skipped (as designed), root-app 1/1. This also means Step 5/6 manifests render with kustomize.
  - `make lint-shell` PASS (every `*.sh` in the repo), `make lint-secrets`, `make lint-drills`, `make lint-docs` (9 files, 0 broken references) PASS. `make lint-terraform` (tflint, recommended preset) PASS. `tofu fmt -check -recursive` PASS.
  - gitleaks: 1 finding, a false positive (the deliberate `dns-disabled-placeholder-token-...` in `envs/prod/main.tf`); allow-listed narrowly in `.gitleaks.toml`. A synthetic GitHub token in a scratch file IS caught. Working tree: no leaks. Git history was not scanned (the zip has no `.git`); CI scans it.
  - README Mermaid diagram rendered with mermaid 11 in headless Chromium: OK. `ci.yml` parses as YAML, all 14 `uses:` pinned to 40-hex SHAs (tags resolved with `git ls-remote`), every `make` target it calls exists.
  **Not run:** the workflow on GitHub Actions; `terraform validate` / `init` (provider registry unreachable here; `tofu fmt` only); `ansible-lint` to completion (Ansible Galaxy unreachable: it stopped at 2 syntax-check errors for the missing collections `kubernetes.core` and `community.general`, which `make ansible-deps` installs in CI, so other findings may be hidden); helm template rendering; `tflint --init` plugins (bundled ruleset only).

## Open issues / decisions
- **Step 9:** CI pins are untested on a runner: `terraform_version: 1.9.8`, tool versions above, `ansible-core 2.21.5` + `ansible-lint 26.10.1` (what pip resolved here), `python 3.12`, `node 22`. If a job fails on first push, check those first. The kubeconform CRD catalogue (`datreeio/CRDs-catalog` on `main`) and Ansible Galaxy are fetched live, so CI needs network and a catalogue change could break `lint-gitops`.
- The `gitleaks` CI job scans git history; any secret ever committed (including in earlier pushes of this project) will fail it even after removal from the tree.
- README says "no real drill has been run" and keeps the results table pending. Update the table only from `"mode": "real"` result files.
- The console footer still has no repo link (`YOUR-USER` placeholders remain in gitops); add when the URL exists.
- **Step 8:** the console has only ever rendered the 3 SIMULATED samples. First real run: `make drill-all ...` then `make site-build`; check the headline, banner (must disappear only when every shown run is real) and `notes`.
- The three traces share one shape (fault, flatline, recovery) and differ only in scale and length; the step detail lives in the ledger and the `notes`, not in the trace. Per-step markers inside the flatline would be a good later improvement. Each trace has its own time scale (T0, +30s ...), so lengths are not comparable between traces by eye; the RTO numbers are.
- The "fault active" red segment is the whole time from fault to recovery. For fill-disk that includes alert latency while Postgres kept writing (the notes say so); it is not an outage of the canary.
- Lenis (optional in DESIGN.md) was not added. The footer has no repo link: add one in Step 9 once the real URL exists (placeholder `YOUR-USER` URLs are still in gitops).
- Package versions pinned from the registry at build time (vite 5.4.11, gsap 3.12.5, d3-scale 4.0.2, d3-shape 3.2.0, fontsource 5.1.1, typescript 5.6.3); `npm audit` was not run.
- The sticky SIMULATED banner is three lines on a 360px phone; kept for visibility.
- **Step 7 assumptions to verify on the first real run:** `kubectl get --raw /api/v1/namespaces/canary/services/canary-writer:8080/proxy/...` and `.../monitoring/services/kps-prometheus:9090/proxy/api/v1/query` work from your machine; `ssh ops@host` works with BatchMode; the data disk is the one holding `/var/lib/rancher/k3s` (k3s local-path); `terraform destroy -target=module.server` also removes the firewall attachment and DNS record (dependents) and does not hit `delete_protection`; after `delete-server --via terraform` the new IP may differ, the drill passes it to Ansible with `-e ansible_host` but the inventory file still holds the old IP afterwards (update it).
- `delete-server` removes the old IP from `~/.ssh/known_hosts` for the NEW address (`ssh-keygen -R`) so Ansible is not blocked by a reused address; it changes your known_hosts.
- `delete-server` refuses to start unless Prometheus reports a verified backup (`backup_last_success_timestamp_seconds`) younger than 2h (`--allow-stale-backup` overrides). So BackupVouch must have run once, and `make resume-backups` must have un-suspended the policy, before the first real run.
- `fill-disk` fills to 97%, not 100%: Postgres usually keeps writing, so its RTO is mostly alert latency (DiskCritical `for: 5m`). `DiskFillingSoon` (`for: 30m`) will normally not be in `alerts_fired`. Both are stated in the result notes.
- `kill-node` uses SIGKILL on the k3s service only; pods keep running, so it normally loses no rows. Whether `NodeDown`/`PodCrashLooping` fire is read back, not assumed.
- Simulated `alerts_fired` are the EXPECTED alerts, not observations; the notes of each simulated file say so.
- A timed-out drill writes no result file (the schema requires `recovered_at`); read the console output. Add a failed-run format later if you want one.
- Simulated runs by default write into `drills/results/` next to real ones (`summary.json` always prefers real). Use `--results-dir` or `make drill-simulate` (temp dir) to keep them out. `summary.json` is not committed; run `make drill-all` or `bash drills/run-all.sh --summarize-only`.
- Drill scripts use bash 3.2-safe syntax (macOS), but `fallocate`/`df --output` run on the Linux server over SSH and `stat`-style GNU tools are not used locally.
- **Step 6 needs from the user before anything works:** (1) an OFF-SERVER S3 bucket and its endpoint in `canary-backuppolicy.yaml` (currently `s3.example.invalid:443`, and `restore-data.sh` refuses it);
  (2) real `canary-backup-pg.enc.yaml` and `backupvouch-s3.enc.yaml` (only `*.example.yaml` exist; no age key available here); (3) BackupVouch release v0.1.0 with `install.yaml` attached and public ghcr images.
  Backups must NOT live on the same server, or the delete-server drill destroys them with the server; this is why no in-cluster S3 was added (BackupVouch's `config/samples/demo/s3.yaml` is for throwaway clusters only).
- **UNVERIFIED in step 6:** the release URL exists and ArgoCD's kustomize can fetch it (hardening: commit the file as `operator/install.yaml`); the ClusterRole name `backupvouch-metrics-reader` and ServiceAccount `kps-prometheus` (comments in `metrics-reader-binding.yaml` give the check commands);
  the runner `limits.memory: 768Mi` is a guess; `pg_restore` reading a custom-format dump from stdin with `--single-transaction`; the AWS CLI against the chosen store (path-style addressing may be needed for some S3-compatible stores).
- **Safety design to keep:** the policy is committed `suspend: true` and ArgoCD ignores `/spec/suspend`. After a rebuild the database is empty; resuming before `make restore-data` would back up the empty database and, after `keepLast` (48) runs, prune the good ones. `restore-data` restores first, then resumes.
- The canary DB's owner role is used for backups (BackupVouch recommends a read-only role; not done). The BackupVouch Jobs have no NetworkPolicy (BackupVouch only recommends one; none added, k3s policy behaviour untested).
- RPO for the drills is bounded by the hourly schedule plus backup time; `delete-server` should report it honestly (not claim seconds).
- The `restore-data` RPO number: canary writes 1 row/s, so `last_seq_before - restored_last_seq` is the loss in seconds (the script prints `restored_last_seq`).
- **Step 5 unverified items:** chart versions pinned from memory (kube-prometheus-stack 67.4.0, loki 6.24.0, promtail 6.16.6; newer exist, confirm these tags exist);
  `defaultRules` keys and the `$values` multi-source Application syntax were not rendered with Helm/ArgoCD; Grafana datasource uid `prometheus` is the chart's default, unconfirmed;
  the Loki single-binary values follow the chart's documented filesystem mode from memory.
- **Promtail is deprecated by Grafana (replaced by Grafana Alloy; end of life was announced for early 2026).** Built as PLAN.md says; consider swapping to Alloy later (touches `values/promtail.yaml` and `monitoring-apps.yaml` only).
- **Alertmanager webhook and Grafana admin Secrets are examples only** (`gitops/secrets/*.example.yaml`): the demo age key is not available, so nothing could be encrypted. Until the user creates `*.enc.yaml` versions and runs `make apply-secrets`, Grafana's admin Secret is missing (pod will not become ready) and alerts have nowhere to go.
- `CertExpiringSoon` needs `probe_ssl_earliest_cert_expiry`, which needs a blackbox probe and a real domain (`probe.example.yaml`). Until then the rule is valid but has no data.
- `BackupStale` fires while the backup metric does not exist (before step 6), on purpose.
- `NodeDown` cannot report a whole-node loss on a single node (Prometheus dies too); documented in the rule and RUNBOOK. Watchdog is kept for an external dead-man's switch.
- `monitoring-config` relies on retry and `SkipDryRunOnMissingResource` while the chart's CRDs install; first sync may show errors for a few minutes.
- **DECIDED (step 3): the author wants to spend nothing, so the default path is a free local VM** (`make local-up`, Multipass).
  Terraform/Hetzner code stays in the repo as the paid, cloud option (Hetzner has no free tier). Oracle Cloud Always Free was NOT built
  (needs a card at signup, free capacity is often unavailable); it would be a new `oci` module if wanted later.
  Local VM limits to state in the README at step 9: no cloud firewall or DNS, and `delete-server` means `make local-destroy` + `make local-up`.
- `server_type` default `cx22` is unverified against Hetzner's current catalogue; check `hcloud server-type list` before applying.
- Provider versions pinned as `~> 1.49` (hcloud) and `~> 4.52` (cloudflare, v4 syntax: `cloudflare_record`). No lock file committed; first `make init` creates it.
- Pinned from memory, unverified against the releases pages: k3s `v1.31.4+k3s1`, ArgoCD `v2.13.2`. Check the tags exist before the first real run.
- The k3s installer script (get.k3s.io) has no published checksum; version is pinned via INSTALL_K3S_VERSION only.
- `argocd_bootstrap` creates the root Application from its own template (`argocd_bootstrap_repo_url` in the inventory, path `gitops/apps`).
  Step 3 should create `gitops/apps` and keep `gitops/bootstrap/root-app.yaml` consistent with that template (or the role can switch to applying that file).
- Canary pods cannot start until step 4 supplies the Secret `canary-postgres` (key `POSTGRES_PASSWORD`); until then they show CreateContainerConfigError.
- Canary image name `ghcr.io/your-user/respawn-canary:0.1.0` and all `repoURL: https://github.com/YOUR-USER/respawn.git` values are placeholders to replace
  (kustomization `images:`; three Application/root files). The Ansible role's root app takes its URL from the inventory.
- Postgres PVC size is 2Gi via `pvc-size.patch.yaml`; volumeClaimTemplates cannot be resized in place later.
- `postgres:16.6-alpine` and `psycopg 3.2.3` pinned from memory; confirm they are the versions you want.
- **The demo age key is throwaway** (generated in the sandbox, not in the zip, so the committed secret CANNOT be decrypted by you). Generate your own key and re-encrypt, see RUNBOOK section 0, before any real use.
- Private Git repos need a repository credential Secret in ArgoCD. Not done in Step 4 (the repo URL is still a placeholder; public repo assumed). Add `gitops/secrets/argocd-repo.enc.yaml` (label `argocd.argoproj.io/secret-type: repository`) when the repo is private; `apply-secrets` already handles it, but its namespace is `argocd`.
- `restore-key` stores `argocd/sops-age` but nothing reads it yet; it only matters if you later move to ksops. `argocd` namespace is created by it if missing (the ArgoCD install adopts it).
- Secrets are applied by hand (`make apply-secrets`), not by Git sync. Drills that rebuild the server must run it after `make bootstrap` (already in RUNBOOK section 2).
- Remote-state (S3-compatible) backend is only a commented example in `envs/prod/versions.tf`.
- BackupVouch API details: needed at step 6 (ask the user to paste the README).

## Notes for next session
Step 10 (final QA): check every Makefile target in `docs/RUNBOOK.md` exists (`lint` and `zip` now do); every path in README exists (`make lint-docs` does this for README/CLAUDE/docs); alert names agree (`make lint-alerts` does this); run gitleaks on history once a `.git` exists; tick PROGRESS; write the "Only you can do this" list (real token, own age key, real BackupVouch wiring + bucket, replace `YOUR-USER` placeholders, run the real drills and paste only `mode: real` numbers, first CI run). Do not claim CI passes until it has run.

(Step 9 notes, kept for reference) `make lint` is the local equivalent of CI minus `site-build`.

Step 9 (CI + README): add `site-build` (`cd site && npm ci && npm run build`) and `make lint-drills` (shellcheck + schema validation of `drills/results/*.json`, includes samples) to CI; add `site/` to the README doc links; the README results table must stay "pending" while only `sample-*` / simulated files exist. Do not start Step 10.

(Step 8 notes, kept for reference) the console reads `site/public/data/index.json`, generated by `site/scripts/copy-data.mjs`.

Step 8 (console): read `drills/results/summary.json` and per-run files; when none exist use `drills/results/sample-*.json` and show the SIMULATED banner. Fields to render are in `drills/schema/result.schema.json` (steps[] for the rebuild ledger, `alerts_fired` for the tags, `rpo_seconds`/`last_seq_before`/`first_seq_after` for the RPO gap strip). Show the banner when `mode` is `simulated` or the summary has `"label": "SIMULATED"`; the `notes` of a real result may explain caveats (e.g. fill-disk RTO includes alert latency) and should be visible. Do not start Step 9.

(Step 7 notes, kept for reference) drills are described in `docs/DRILLS.md` "Implementation notes".

Step 7 (drills): the rebuild path in docs/RUNBOOK.md section 2 now ends with `make restore-key`, `make apply-secrets`, `make restore-data` (needs the `aws` CLI, the cluster, and the S3 bucket reachable). `drills/restore-data.sh` prints `restored_object`, `restored_rows`, `restored_last_seq` on stdout for `common.sh` to read; `--yes` skips its prompt (drills must pass it, after their own `--yes-really` check). The health check must also treat a suspended BackupPolicy as not recovered. Drills must never run against a real BackupVouch bucket without the user knowing: delete-server does not delete backups, but restore REPLACES the canary tables.

(Step 6 notes, kept for reference) Step 6 adds `gitops/apps/backupvouch/` as a fifth child Application in `gitops/apps/kustomization.yaml`; the exporter must expose `backup_last_success_timestamp_seconds` (the name BackupStale and the Backups dashboard use). Ask the user to paste BackupVouch's README first.

(Step 5 notes, kept for reference) Step 5 added `gitops/apps/monitoring/` as another child Application listed in `gitops/apps/kustomization.yaml`. Alertmanager's webhook URL must be a secret: add it as a new `gitops/secrets/*.enc.yaml` (needs the demo key, which only the previous session had; if re-encryption is impossible, add `*.example` and say so, or ask the user to generate their own age key first). Hardening is Ansible-only, not cloud-init. Ansible variable names use the role prefix (ansible-lint rule).
