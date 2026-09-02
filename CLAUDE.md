# CLAUDE.md: rules for any AI session working on Respawn

Read this file, `docs/PROGRESS.md` and the current step in `docs/PLAN.md` before doing anything.

## What Respawn is
A small-team platform defined in code (Terraform, Ansible, k3s, ArgoCD, SOPS, Prometheus/Alertmanager/Grafana/Loki, BackupVouch) plus drills that break it and record measured recovery time (RTO) and data loss (RPO). Full detail: `docs/PRD.md`, `docs/ARCHITECTURE.md`.

## Hard rules
1. **Never fabricate measurements.** Every drill result file has `"mode": "real"` or `"mode": "simulated"`. Anything simulated or sample must be labelled SIMULATED / SAMPLE in the file, the console UI and the README. The README results table only gets numbers from `real` runs.
2. **Never invent an API.** BackupVouch's interface is unknown to you. Use the adapter in `gitops/apps/backupvouch/` and ask the user to paste BackupVouch's README or API notes if you need details.
3. **No real secrets, ever.** Use `.sops.yaml` + age. Commit only encrypted files or `*.example`. Never print or commit a private age key.
4. **Everything is validated before it is called done.** Run the validators listed in `docs/PLAN.md` for the step (terraform validate, ansible-lint, kubeconform, promtool, shellcheck). If a tool is not installable in the sandbox, say so in PROGRESS.md and keep the check in CI.
5. **Small steps.** Do only the current step. Do not start the next one.
6. **Honest limits.** You cannot run real cloud drills from a sandbox. Build the drills so they work for real against real infra, with a `--simulate` mode that is clearly labelled.

## Conventions
- Repo layout is fixed (see `docs/ARCHITECTURE.md`). Do not rename top-level folders.
- Terraform: modules under `infra/terraform/modules/`, one `env` under `infra/terraform/envs/prod`. Pin provider versions.
- Ansible: roles under `infra/ansible/roles/`, idempotent, tagged. No `shell` when a module exists.
- Kubernetes: plain YAML or Kustomize. No Helm values with plaintext secrets. ArgoCD app-of-apps in `gitops/`.
- Shell scripts: `set -euo pipefail`, shellcheck clean, small functions, `--help` output.
- Commits and file names: lowercase, kebab-case.
- Comments explain *why*, not *what*.

## Design rules (for `site/`)
Follow `docs/DESIGN.md` exactly. The site must not look like a default AI-generated page: no purple gradients, no generic card grids, no stock hero. Use the "flight recorder" concept.

## End of every step (mandatory)
1. Update `docs/PROGRESS.md`: tick the step, list files added, list open issues, note which validators passed.
2. Run `bash scripts/make-zip.sh <step-number>`; this creates `respawn-step-<n>.zip` one level above the repo.
3. Send the zip to the user (SendUserFile) with a one-line summary and tell them the next step number.
4. Stop. Do not continue into the next step.
