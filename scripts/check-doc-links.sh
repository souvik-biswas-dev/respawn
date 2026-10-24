#!/usr/bin/env bash
# Fail when README.md, CLAUDE.md or docs/*.md point at a file or directory that does not exist:
# markdown links [text](path) and `backticked/repo/paths`. Anchors and URLs are not checked.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 2; }

python3 - <<'PY'
import glob, os, re, sys

FILES = ["README.md", "CLAUDE.md"] + sorted(glob.glob("docs/*.md"))
# Paths the docs mention that exist only after you create or generate them.
GENERATED = {
    "drills/results/summary.json", "infra/ansible/inventory/hosts.yml",
    "infra/terraform/envs/prod/terraform.tfvars",
    "gitops/secrets/argocd-repo.enc.yaml",  # only if the Git repo is private; you create it
    "site/dist", "site/public/data", "site/node_modules",
}
ROOTS = ("infra/", "gitops/", "docs/", "drills/", "scripts/", "site/", "alerts/", ".github/")
bad = []
for f in FILES:
    text = open(f, encoding="utf-8").read()
    base = os.path.dirname(f)
    for target in re.findall(r"\]\(([^)\s]+)\)", text):
        if re.match(r"^(https?:|mailto:|#)", target):
            continue
        path = os.path.normpath(os.path.join(base, target.split("#")[0]))
        if not os.path.exists(path):
            bad.append((f, target))
    for tok in re.findall(r"`([^`\s]+)`", text):
        tok = tok.rstrip(".,:;")
        if not tok.startswith(ROOTS) or any(c in tok for c in "*<>{}$"):
            continue
        if tok.rstrip("/") in GENERATED or tok in GENERATED:
            continue
        if not os.path.exists(tok):
            bad.append((f, tok))
for f, t in bad:
    print(f"{f}: missing {t}", file=sys.stderr)
print(f"checked {len(FILES)} files, {len(bad)} broken reference(s)")
sys.exit(1 if bad else 0)
PY
