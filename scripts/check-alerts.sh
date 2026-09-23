#!/usr/bin/env bash
# Validate the alert rules: structure (names agree across docs, rules and tests), then promtool.
# The PrometheusRule manifest is the source of truth; its spec.groups are extracted to a
# temporary rules file because promtool reads the plain Prometheus format, not the CRD.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_CRD="${REPO_DIR}/gitops/apps/monitoring/respawn-rules.yaml"
TESTS_DIR="${REPO_DIR}/alerts/tests"
ARCH_DOC="${REPO_DIR}/docs/ARCHITECTURE.md"

usage() {
  cat <<'USAGE'
usage: bash scripts/check-alerts.sh [--structure-only]

Checks, in order:
  1. the seven alert names in docs/ARCHITECTURE.md exist in the rules and each has a test file
  2. promtool check rules, then promtool test rules (skipped with --structure-only)
USAGE
}

extract_rules() {
  # Writes {groups: ...} from the PrometheusRule spec to $1.
  python3 - "$RULES_CRD" "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
yaml.safe_dump({"groups": doc["spec"]["groups"]}, open(sys.argv[2], "w"), sort_keys=False)
PY
}

check_structure() {
  python3 - "$1" "$ARCH_DOC" "$TESTS_DIR" <<'PY'
import glob, re, sys, yaml
rules_file, arch, tests_dir = sys.argv[1:4]
in_rules = {r["alert"] for g in yaml.safe_load(open(rules_file))["groups"] for r in g["rules"] if "alert" in r}
m = re.search(r"## Alerts.*?\n(.*?)\n\n", open(arch).read(), re.S)
in_doc = set(re.findall(r"`(\w+)`", m.group(1))) if m else set()
tested = set()
for f in glob.glob(tests_dir + "/*.yaml"):
    for t in yaml.safe_load(open(f))["tests"]:
        tested |= {a["alertname"] for a in t.get("alert_rule_test", [])}
bad = False
for label, a, b in (("in docs but not in rules", in_doc, in_rules),
                    ("in rules but not in docs", in_rules, in_doc),
                    ("in rules but without a test", in_rules, tested)):
    missing = sorted(a - b)
    if missing:
        print(f"{label}: {', '.join(missing)}"); bad = True
if len(in_doc) != 7:
    print(f"expected 7 alerts in docs/ARCHITECTURE.md, found {len(in_doc)}"); bad = True
sys.exit(1 if bad else 0)
PY
  echo "structure ok: alert names agree across ARCHITECTURE.md, rules and tests"
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    ""|--structure-only) ;;
    *) usage; exit 1 ;;
  esac

  # Global (not local) so the EXIT trap can still see it under set -u.
  work="$(mktemp -d)"
  trap 'rm -rf "${work}"' EXIT
  extract_rules "${work}/rules.yaml"
  check_structure "${work}/rules.yaml"
  [ "${1:-}" = "--structure-only" ] && exit 0

  command -v promtool >/dev/null || { echo "promtool not found (install Prometheus' promtool); it is required in CI" >&2; exit 2; }
  promtool check rules "${work}/rules.yaml"
  # Tests refer to ../rules.yaml, so mirror the layout in the temp dir.
  mkdir -p "${work}/tests"
  cp "${TESTS_DIR}"/*.yaml "${work}/tests/"
  promtool test rules "${work}"/tests/*.yaml
}

main "$@"
