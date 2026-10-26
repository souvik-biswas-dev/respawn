# Respawn Makefile. Targets are added step by step; see docs/RUNBOOK.md for the full list.
# TF can be terraform or tofu (OpenTofu is compatible): make plan TF=tofu
TF  ?= terraform
ENV := infra/terraform/envs/prod

.PHONY: help init fmt validate plan apply destroy-confirm ansible-deps bootstrap lint-ansible lint-gitops local-up local-destroy restore-key apply-secrets lint-secrets lint-alerts lint-backup restore-data resume-backups status drill-kill drill-disk drill-delete drill-all drill-simulate drill-validate lint-drills site-build lint-shell lint-terraform lint-leaks lint-docs lint zip

help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

init: ## download providers
	$(TF) -chdir=$(ENV) init

fmt: ## format terraform files
	$(TF) -chdir=infra/terraform fmt -recursive

validate: ## check syntax without touching any cloud
	$(TF) -chdir=infra/terraform fmt -check -recursive
	$(TF) -chdir=$(ENV) init -backend=false -input=false
	$(TF) -chdir=$(ENV) validate

plan: init ## show what would be created (costs nothing)
	$(TF) -chdir=$(ENV) plan -out=tfplan

apply: ## CREATES REAL, BILLED SERVERS from the saved plan
	@test -f $(ENV)/tfplan || { echo "run 'make plan' first"; exit 1; }
	$(TF) -chdir=$(ENV) apply tfplan

destroy-confirm: ## DESTROYS everything; asks you to type the word 'destroy'
	@read -p "Type 'destroy' to delete all Respawn infrastructure: " a; \
	  [ "$$a" = "destroy" ] || { echo "aborted"; exit 1; }
	$(TF) -chdir=$(ENV) destroy

ansible-deps: ## install the Ansible collections the roles need
	cd infra/ansible && ansible-galaxy collection install -r requirements.yml

bootstrap: ## harden the server, install k3s + ArgoCD (needs infra/ansible/inventory/hosts.yml)
	@test -f infra/ansible/inventory/hosts.yml || { echo "copy infra/ansible/inventory/hosts.example.yml to hosts.yml and fill it in"; exit 1; }
	cd infra/ansible && ansible-playbook site.yml

lint-ansible: ## ansible-lint plus a syntax check (uses the example inventory)
	cd infra/ansible && ansible-lint site.yml roles
	cd infra/ansible && ansible-playbook -i inventory/hosts.example.yml site.yml --syntax-check

CRD_SCHEMAS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
KUBECONFORM := kubeconform -strict -summary -schema-location default -schema-location '$(CRD_SCHEMAS)'

lint-gitops: ## build the Kustomize apps and validate every manifest with kubeconform
	kustomize build gitops/apps | $(KUBECONFORM) -
	kustomize build gitops/apps/canary | $(KUBECONFORM) -
	kustomize build gitops/apps/monitoring | $(KUBECONFORM) -
	# BackupPolicy has no published JSON schema: its CRD (and a CEL rule) is checked by the API server.
	kustomize build gitops/apps/backupvouch/config | $(KUBECONFORM) -skip BackupPolicy -
	$(KUBECONFORM) gitops/bootstrap/root-app.yaml

local-up: ## FREE: create a local Ubuntu VM with Multipass instead of a paid cloud server
	bash infra/local/multipass-vm.sh up

local-destroy: ## delete the local VM
	bash infra/local/multipass-vm.sh destroy

restore-key: ## install the age private key (asks for its path) locally and as a cluster Secret
	bash scripts/restore-key.sh $(if $(KEY_FILE),$(KEY_FILE),)

apply-secrets: ## decrypt gitops/secrets/*.enc.yaml with SOPS and apply to the cluster
	bash scripts/apply-secrets.sh

lint-secrets: ## shellcheck the secret scripts; fail if any *.enc.yaml holds a plaintext value
	shellcheck -x scripts/apply-secrets.sh scripts/restore-key.sh scripts/check-secrets.sh
	bash scripts/check-secrets.sh

lint-alerts: ## alert names agree across docs, rules and tests; promtool check + test rules
	shellcheck -x scripts/check-alerts.sh
	bash scripts/check-alerts.sh

lint-backup: ## shellcheck the restore script
	shellcheck -x drills/restore-data.sh

restore-data: ## restore the canary Postgres from the newest BackupVouch backup, then resume backups (asks to confirm)
	bash drills/restore-data.sh $(RESTORE_ARGS)

resume-backups: ## first install only (nothing to restore): un-suspend the BackupVouch policy
	bash drills/restore-data.sh --resume-only

# Drills. Pass options with DRILL_ARGS, e.g. make drill-kill DRILL_ARGS="--host respawn-1 --yes-really".
# Every drill needs --host NAME and --yes-really, or --simulate (touches nothing, result labelled SIMULATED).
status: ## run the health check from docs/DRILLS.md (exit 0 = recovered)
	bash drills/status.sh

drill-kill: ## DRILL: kill k3s on the server and time the recovery (DRILL_ARGS="--host NAME --yes-really")
	bash drills/kill-node.sh $(DRILL_ARGS)

drill-disk: ## DRILL: fill the data disk to 97%, wait for DiskCritical, clean up (DRILL_ARGS="--host NAME --yes-really")
	bash drills/fill-disk.sh $(DRILL_ARGS)

drill-delete: ## DRILL: DESTROYS THE SERVER and rebuilds it (DRILL_ARGS="--host NAME --via local|terraform --age-key FILE --yes-really")
	bash drills/delete-server.sh $(DRILL_ARGS)

drill-all: ## DRILL: run all three in order, then write drills/results/summary.json
	bash drills/run-all.sh $(DRILL_ARGS)

drill-simulate: ## run all three with --simulate into a temp dir: no server, nothing written to drills/results
	RESULTS_DIR="$$(mktemp -d)" bash drills/run-all.sh --simulate

drill-validate: ## validate every drills/results/*.json against drills/schema/*.json
	bash drills/validate-results.sh

lint-drills: ## shellcheck the drill scripts, then schema-validate the committed results
	shellcheck -x drills/*.sh drills/lib/common.sh
	bash drills/validate-results.sh

site-build: ## build the Respawn Console (site/dist) from drills/results; samples + SIMULATED banner if there are none
	cd site && npm ci --no-audit --no-fund && npm run build

lint-shell: ## shellcheck every *.sh in the repo
	find . -name '*.sh' -not -path './site/node_modules/*' -not -path './.git/*' | sort | xargs shellcheck -x

lint-terraform: ## tflint over infra/terraform (bundled ruleset, config in .tflint.hcl)
	cd infra/terraform && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

lint-leaks: ## gitleaks over the working tree (config in .gitleaks.toml)
	gitleaks detect --no-git --source . --config .gitleaks.toml --redact --no-banner

lint-docs: ## every file path the docs mention exists
	bash scripts/check-doc-links.sh

lint: validate lint-terraform lint-ansible lint-gitops lint-alerts lint-shell lint-secrets lint-drills lint-leaks lint-docs ## everything CI runs except the site build

zip: ## make the end-of-step zip: make zip STEP=9
	@test -n "$(STEP)" || { echo "usage: make zip STEP=<number>"; exit 2; }
	bash scripts/make-zip.sh $(STEP)
