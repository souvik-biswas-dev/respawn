# PLAN: build Respawn in small steps (free-limit friendly)

Each step is small enough for one free session. Every step ends with a **zip**. If your limit runs out, switch accounts, upload the latest zip, paste the **Resume prompt**, and continue from the step in `docs/PROGRESS.md`.

## How to use this

**First time (any account):** upload `respawn-step-0.zip` (this pack), then paste the **Start prompt** for Step 1.

**Resuming on a new account:** upload the latest `respawn-step-N.zip`, then paste:

```
Resume prompt:
Unzip the uploaded respawn-step zip. Read CLAUDE.md, docs/PROGRESS.md and docs/PLAN.md.
Find the first unchecked step in PROGRESS.md and do ONLY that step, following CLAUDE.md
(including the end-of-step routine: update PROGRESS.md, run scripts/make-zip.sh, send me the zip).
```

**If a step was cut off halfway:** upload the last good zip and say: "Step N was interrupted. Check what exists against the step's Done-when list, finish only what is missing, then do the end-of-step routine."

## Skills and connectors
- **frontend-design skill**: already available in Claude; needed in Step 8 (tell it to load it).
- **No connectors required.** Everything is generated as files.
- Optional later: GitHub connector to push the repo; not needed for the zips.
- If a step needs something you must provide, it will ask: BackupVouch docs (Step 6), your provider choice (Step 1).

## Shared end-of-step block
Every prompt below ends with this, so you do not forget it. It is already in `CLAUDE.md`, but repeating it saves a step when a session starts cold.

```
When finished: update docs/PROGRESS.md, run `bash scripts/make-zip.sh <N>`, send me the zip
with SendUserFile, state the next step number, and stop.
```

---

## Step 1: Terraform
**Goal:** server, firewall, DNS as code.
**Files:** `infra/terraform/modules/{server,firewall,dns}`, `infra/terraform/envs/prod/{main,variables,outputs,versions}.tf`, `terraform.tfvars.example`, `Makefile` (plan/apply targets).
**Done when:** `terraform fmt -check` and `terraform validate` pass (init with `-backend=false`); variables documented; outputs include server IP and name; no secrets in files.

```
Do Step 1 of docs/PLAN.md: Terraform.
Use Hetzner Cloud as the default provider (hcloud) with variables so another provider could be swapped in.
Create modules for server (with cloud-init that creates an ops user and installs my SSH key),
firewall (allow 22 from a variable CIDR, 80, 443, 6443 from a variable CIDR), and dns (Cloudflare record, optional).
Pin provider versions. Add an optional remote-state example in comments. Add terraform.tfvars.example.
Add Makefile targets: plan, apply, destroy-confirm.
Validate with terraform fmt -check and terraform validate (-backend=false). If terraform is not installable here, say so and note it in PROGRESS.md.
Then do the end-of-step routine from CLAUDE.md with step number 1.
```

## Step 2: Ansible hardening + k3s
**Goal:** a fresh server becomes hardened and runs k3s.
**Files:** `infra/ansible/{ansible.cfg,site.yml}`, `inventory/hosts.example.yml`, roles `hardening`, `k3s`, `argocd_bootstrap`; Makefile `bootstrap`.
**Done when:** `ansible-lint` and `ansible-playbook --syntax-check` pass; roles idempotent by design (modules, not shell); tags on each role.

```
Do Step 2 of docs/PLAN.md: Ansible.
Roles: hardening (SSH key-only, no root login, ufw, fail2ban, unattended-upgrades, sysctl basics, auditd basics, time sync),
k3s (single-node install pinned to a version variable, kubeconfig fetched locally with 0600 perms),
argocd_bootstrap (install ArgoCD from pinned manifest, then apply gitops/bootstrap root app, repo URL as a variable).
Use modules over shell wherever possible. Tag every role. Add inventory/hosts.example.yml with a protected flag variable.
Add Makefile target bootstrap. Validate with ansible-lint and ansible-playbook --syntax-check.
Then do the end-of-step routine with step number 2.
```

## Step 3: GitOps + canary workload
**Goal:** ArgoCD app-of-apps and a workload that makes RPO measurable.
**Files:** `gitops/bootstrap/`, `gitops/apps/` (root + children), `gitops/apps/canary/` (Postgres StatefulSet + writer Deployment + service + a tiny HTTP `/healthz` and `/last-seq`).
**Done when:** `kubeconform` (or `kubectl --dry-run=client`) passes on all manifests; the writer inserts a monotonic sequence number plus timestamp every second and exposes `canary_last_seq` and `canary_write_errors_total` metrics; PVC sizing is a variable/patch.

```
Do Step 3 of docs/PLAN.md: GitOps and canary.
Create an ArgoCD app-of-apps: gitops/bootstrap/root-app.yaml pointing at gitops/apps.
Create the canary app: Postgres StatefulSet with a PVC, and a small writer service (Go or Python, your choice; keep it tiny)
that inserts (seq, ts) every second, exposes /healthz, /last-seq and Prometheus metrics canary_last_seq and canary_write_errors_total.
Include a Dockerfile and a note on where the image is built/pushed (GitHub Container Registry via CI later).
Use Kustomize. No plaintext secrets: reference a Secret that step 4 will provide.
Validate with kubeconform. Then do the end-of-step routine with step number 3.
```

## Step 4: SOPS secrets
**Goal:** encrypted secrets in Git, with a documented key recovery story.
**Files:** `.sops.yaml`, `gitops/secrets/*.enc.yaml` (encrypted with a **throwaway demo age key created in the sandbox**; the key is NOT included in the zip). No new .md file: key instructions go in `docs/RUNBOOK.md` section 0.
**Done when:** `.sops.yaml` creation rules exist; Makefile targets `restore-key`; a helper script to decrypt-apply; no private key in the repo or zip (the make-zip script already excludes `*.agekey` and `keys.txt`).

```
Do Step 4 of docs/PLAN.md: SOPS with age.
Add .sops.yaml with creation rules for gitops/secrets. Create an example Secret for the canary Postgres password,
encrypt it with a demo age key generated in the sandbox. Do NOT put the private key in the repo; tell me in your reply
that the demo key is throwaway and I must generate my own with age-keygen and re-encrypt before real use.
Add a Kubernetes integration approach (ArgoCD with ksops OR a documented 'sops decrypt then apply' step; pick the simpler one and explain why in a comment).
Add Makefile target restore-key and update RUNBOOK section 0 if needed.
Then do the end-of-step routine with step number 4.
```

## Step 5: Observability and alerts
**Goal:** the monitoring stack, with alerts that fire for real conditions, and tests for the rules.
**Files:** `gitops/apps/monitoring/` (Prometheus, Alertmanager, Grafana, Loki, Promtail), `gitops/apps/monitoring/respawn-rules.yaml` (the rules), `alerts/tests/*.yaml`, Grafana dashboards as JSON/ConfigMaps.
**Done when:** `promtool check rules` and `promtool test rules` pass; the seven alert names from ARCHITECTURE.md exist; dashboards: Node/Disk, Backups, Canary (RPO view), Alert overview; Alertmanager receiver configured via a secret placeholder (webhook).

```
Do Step 5 of docs/PLAN.md: observability.
Add monitoring apps under gitops/apps/monitoring: Prometheus, Alertmanager, Grafana, Loki, Promtail (use upstream Helm charts via ArgoCD with pinned versions, values committed).
Write alert rules named exactly: DiskFillingSoon, DiskCritical, CertExpiringSoon, BackupStale, NodeDown, PodCrashLooping, CanaryWriteGap.
Use realistic expressions (predict_linear for disk, x509 expiry for certs, a backup_last_success_timestamp_seconds metric for backups, canary_last_seq not increasing for the gap).
Write promtool unit tests for each rule in alerts/tests and run promtool check rules and promtool test rules.
Add Grafana dashboards as code: Disk, Backups, Canary, Alerts.
Then do the end-of-step routine with step number 5.
```

## Step 6: BackupVouch integration
**Goal:** BackupVouch as the backup layer and the source of the backup-freshness signal.
**Before starting:** have BackupVouch's README or API notes ready to paste. If you do not have them, tell the AI: "Build a generic adapter with a clearly marked TODO block and a restic fallback."
**Files:** `gitops/apps/backupvouch/` (CronJob for Postgres dump + upload, exporter exposing `backup_last_success_timestamp_seconds`), `drills/restore-data.sh`, Makefile `restore-data`, docs note in RUNBOOK section 5.
**Done when:** the CronJob and exporter manifests validate; restore script is shellcheck clean; nothing claims BackupVouch features that were not given in the pasted docs.

```
Do Step 6 of docs/PLAN.md: BackupVouch integration.
Here are BackupVouch's docs / API notes: <PASTE HERE>.
(If the paste above is empty, build a generic adapter with a clearly marked TODO block for BackupVouch calls and use restic as a working fallback. Do NOT invent BackupVouch API calls.)
Create a Postgres backup CronJob, an exporter that exposes backup_last_success_timestamp_seconds, and a restore script drills/restore-data.sh used by `make restore-data`.
Validate manifests with kubeconform and shellcheck the script.
Then do the end-of-step routine with step number 6.
```

## Step 7: Drills
**Goal:** the three drills, the shared library, schema, simulate mode, aggregation.
**Files:** `drills/lib/common.sh`, `kill-node.sh`, `fill-disk.sh`, `delete-server.sh`, `run-all.sh`, `schema/result.schema.json`, `results/sample-*.json` (labelled SIMULATED), `results/.gitkeep`, Makefile `drill-*` targets.
**Done when:** shellcheck clean; every script has `--help`; `--simulate` runs end to end locally and writes valid JSON that passes the schema (validate with `ajv` or python `jsonschema`); result files carry `mode`; destructive drills require `--yes-really` and host name; fill-disk cleans up with a trap.

```
Do Step 7 of docs/PLAN.md: drills. Follow docs/DRILLS.md exactly.
Implement drills/lib/common.sh (timing, health check, canary sequence read, JSON writer) and the three drills plus run-all.sh.
Add --simulate to each drill: it fakes the fault and recovery timings with randomised but plausible durations and writes the result with "mode":"simulated" and "label":"SIMULATED".
Add the JSON schema and validate every generated sample against it. Commit 3 sample result files, all labelled SIMULATED.
Safety: --yes-really plus host name for destructive actions, refuse protected inventories, 10s countdown, trap cleanup in fill-disk.
shellcheck everything. Then do the end-of-step routine with step number 7.
```

## Step 8: Respawn Console (the design step)
**Goal:** the distinctive static site from `docs/DESIGN.md`.
**Before starting:** make sure the **frontend-design** skill is available (it is in Claude by default).
**Files:** `site/` (Vite + TypeScript), `site/public/data/` populated from drills results, fonts via Fontsource, Makefile `site-build`.
**Done when:** `npm run build` passes; the site renders the three traces, RPO gap strip, rebuild ledger, alert tags; SIMULATED banner shows when data is simulated; reduced-motion works; mobile 360px works; screenshots taken and checked; Lighthouse-style sanity (bundle size under 150 KB gzip).

```
Do Step 8 of docs/PLAN.md: the Respawn Console.
First load the frontend-design skill. Then read docs/DESIGN.md fully and follow it exactly: flight-recorder concept,
the banned list, the colour tokens, Instrument Serif + JetBrains Mono self-hosted via Fontsource, D3 for the traces, GSAP ScrollTrigger for the replay.
Build site/ with Vite + TypeScript. Read drills/results/summary.json and per-run JSON (copy into site/public/data at build time via a small script; fall back to the sample data with the SIMULATED banner).
Build: header REC strip, big serif RTO headline, three scroll-replayed traces, RPO gap tick strip, rebuild ledger, alert tags, reproduce-it commands, footer.
Do NOT use purple gradients, card grids with emoji, or centered generic hero.
Build it, open it in a headless browser, take desktop and 360px mobile screenshots, and critique them against DESIGN.md. Fix what looks generic. Report the final bundle size.
Then do the end-of-step routine with step number 8.
```

## Step 9: CI + README polish
**Goal:** CI that proves the repo is valid, and a README that sells it honestly.
**Files:** `.github/workflows/ci.yml`, `.gitleaks.toml` (if needed), README updates, a `docs/` link check.
**Done when:** CI runs terraform fmt/validate, tflint, ansible-lint, kubeconform, promtool, shellcheck, gitleaks, site build, and drill-schema validation; README has the architecture diagram (ASCII or Mermaid), the results table with the real-vs-simulated rule, a "Known limits" section, and a "Try it" path.

```
Do Step 9 of docs/PLAN.md: CI and README.
Write .github/workflows/ci.yml running: terraform fmt -check + validate, tflint, ansible-lint, kubeconform, promtool check+test, shellcheck, gitleaks, site build, and schema validation of drills/results/*.json.
Pin action versions. Update README: Mermaid architecture diagram, the measured-results table (keep numbers pending unless real result files exist), Known limits, Try it, and links to every doc.
Do not claim anything that the repo cannot back up. Then do the end-of-step routine with step number 9.
```

## Step 10: Final QA + release zip
**Goal:** a consistency pass and the final deliverable.
**Done when:** no TODO left unmarked; every Makefile target in RUNBOOK exists; every doc path in README exists; PROGRESS fully ticked; list of "things only the author can do" produced.

```
Do Step 10 of docs/PLAN.md: final QA.
Check: every Makefile target listed in docs/RUNBOOK.md exists; every file referenced in README exists; alert names match across ARCHITECTURE, alerts and tests;
no secrets or private keys anywhere (run gitleaks if available); results labelled correctly; PROGRESS.md fully ticked.
Fix small issues. Then write me a short list called "Only you can do this": real cloud token, own age key, real BackupVouch wiring, running the real drills and pasting the numbers.
Do the end-of-step routine with step number 10 (final release zip).
```

---

## After the build (you, not the AI)
1. Generate your own age key; re-encrypt secrets.
2. Put real tokens in tfvars (never commit).
3. `make apply`, `make bootstrap`, wait for green.
4. Run the real drills: `make drill-all`. Commit the real result files.
5. Rebuild the site so the console shows your measured numbers, then update the README table.
