#!/usr/bin/env bash
# Shared library for the drills: timing, health check, canary reads, result writer.
# Source it; do not run it. The sourcing script owns `set -euo pipefail`.
# Written for bash 3.2 (macOS default): no associative arrays, no mapfile, no ${var,,}.
# shellcheck shell=bash
# shellcheck disable=SC2034  # globals here are read by the scripts that source this file

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRILLS_DIR="$(dirname "$COMMON_DIR")"
REPO_DIR="$(dirname "$DRILLS_DIR")"
SCHEMA_FILE="${DRILLS_DIR}/schema/result.schema.json"
SUMMARY_SCHEMA_FILE="${DRILLS_DIR}/schema/summary.schema.json"

RESULTS_DIR="${RESULTS_DIR:-${DRILLS_DIR}/results}"
KUBECONFIG_FILE="${KUBECONFIG:-${REPO_DIR}/.kubeconfig/respawn.yaml}"
INVENTORY_FILE="${INVENTORY_FILE:-${REPO_DIR}/infra/ansible/inventory/hosts.yml}"
NS_CANARY="${CANARY_NAMESPACE:-canary}"
POLICY_NAME="${BACKUP_POLICY:-canary-db}"
POLL_SECONDS="${POLL_SECONDS:-5}"          # docs/DRILLS.md: poll every 5s
PRECHECK_SECONDS="${PRECHECK_SECONDS:-60}"
# The writer inserts one row per interval, so lost rows * interval = lost seconds (RPO).
WRITE_INTERVAL_SECONDS="${WRITE_INTERVAL_SECONDS:-1}"

# Set by common_arg.
SIMULATE=0
YES_REALLY=0
NO_PROMPT=0
HOST_ARG=""
COUNTDOWN=10
TIMEOUT=""
COMMON_SHIFT=0

# Set by load_inventory.
HOST_ADDR=""
HOST_USER=""
HOST_PROTECTED=""

# Run state, written into the result.
DRILL=""
MODE="real"
T_START=0
T_FAULT=0
T_RECOVERED=0
LAST_SEQ_BEFORE=0
FIRST_SEQ_AFTER=""
RPO_SECONDS=0
ALERTS_FIRED=""
NOTES=""
HC_REASON=""
HC_PREV_SEQ=""
HC_SEQ=""
STEP_NAME=""
STEP_T0=0
CLEANUP_HOOK=""
STEPS_FILE="$(mktemp)"
ENV_FILE="$(mktemp)"

log() { echo "[${DRILL:-drill}] $*" >&2; }
die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found in PATH"; }
now() { date +%s; }
add_note() { NOTES="${NOTES:+${NOTES} }$1"; }
env_set() { printf '%s\t%s\n' "$1" "$2" >>"$ENV_FILE"; }

common_cleanup() {
  # Runs on every exit, including die and Ctrl-C. A drill sets CLEANUP_HOOK to undo its own damage.
  if [ -n "$CLEANUP_HOOK" ]; then "$CLEANUP_HOOK" || true; fi
  rm -f "$STEPS_FILE" "$ENV_FILE"
}
trap common_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

common_usage() {
  cat <<'USAGE'
common options:
  --simulate          fake the fault and the timings; touches nothing; writes a result labelled SIMULATED
  --host NAME         inventory host name of the target (required for a real run)
  --yes-really        confirm a destructive run (needs --host too)
  --inventory FILE    Ansible inventory (default infra/ansible/inventory/hosts.yml)
  --results-dir DIR   where result files go (default drills/results; env RESULTS_DIR)
  --countdown N       seconds to wait before the fault, Ctrl-C aborts (default 10; ignored by --simulate)
  --timeout N         seconds to wait for recovery before giving up
  -h, --help          show this help
Kubeconfig: .kubeconfig/respawn.yaml (env KUBECONFIG). A timed-out run exits non-zero and writes no result file.
USAGE
}

# Consumes one common option from "$@" and sets COMMON_SHIFT to how many words it used.
common_arg() {
  case "$1" in
    --simulate) SIMULATE=1; COMMON_SHIFT=1 ;;
    --yes-really) YES_REALLY=1; COMMON_SHIFT=1 ;;
    --no-prompt) NO_PROMPT=1; COMMON_SHIFT=1 ;;
    --host) [ $# -ge 2 ] || die "--host needs a value"; HOST_ARG="$2"; COMMON_SHIFT=2 ;;
    --inventory) [ $# -ge 2 ] || die "--inventory needs a value"; INVENTORY_FILE="$2"; COMMON_SHIFT=2 ;;
    --results-dir) [ $# -ge 2 ] || die "--results-dir needs a value"; RESULTS_DIR="$2"; COMMON_SHIFT=2 ;;
    --countdown) [ $# -ge 2 ] || die "--countdown needs a value"; COUNTDOWN="$2"; COMMON_SHIFT=2 ;;
    --timeout) [ $# -ge 2 ] || die "--timeout needs a value"; TIMEOUT="$2"; COMMON_SHIFT=2 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
}

require_int() { case "$2" in ''|*[!0-9]*) die "$1 must be a whole number, got '$2'" ;; esac; }

# ---------------------------------------------------------------- safety

load_inventory() {
  [ -f "$INVENTORY_FILE" ] || die "no inventory at ${INVENTORY_FILE} (copy infra/ansible/inventory/hosts.example.yml to hosts.yml)"
  local out
  out="$(python3 - "$INVENTORY_FILE" "$HOST_ARG" <<'PY'
import sys, yaml
inv = yaml.safe_load(open(sys.argv[1])) or {}
want = sys.argv[2]
hosts = {}
def walk(node):
    if not isinstance(node, dict):
        return
    for name, vars_ in (node.get("hosts") or {}).items():
        hosts[name] = vars_ or {}
    for child in (node.get("children") or {}).values():
        walk(child)
walk(inv.get("all") or {})
if want not in hosts:
    sys.exit("error: host %r is not in the inventory (found: %s)" % (want, ", ".join(sorted(hosts)) or "none"))
h = hosts[want]
print(h.get("ansible_host", want))
print(h.get("ansible_user", "ops"))
print(str(h.get("respawn_protected", False)).lower())
PY
)" || exit 1
  HOST_ADDR="$(printf '%s\n' "$out" | sed -n 1p)"
  HOST_USER="$(printf '%s\n' "$out" | sed -n 2p)"
  HOST_PROTECTED="$(printf '%s\n' "$out" | sed -n 3p)"
}

countdown() {
  [ "$COUNTDOWN" -gt 0 ] || return 0
  local i
  echo "Starting in ${COUNTDOWN}s. Press Ctrl-C to abort." >&2
  i="$COUNTDOWN"
  while [ "$i" -gt 0 ]; do printf '\r  %3ds ' "$i" >&2; sleep 1; i=$((i - 1)); done
  printf '\r        \r' >&2
}

# Every destructive drill calls guard_checks first (flags, inventory, protected latch), then checks its
# tools, then guard_plan (prints what will happen and counts down). Refusals therefore come before anything else.
guard_checks() {
  require_int --countdown "$COUNTDOWN"
  [ -n "$HOST_ARG" ] || die "destructive drill: pass --host NAME (an inventory host name)"
  [ "$YES_REALLY" -eq 1 ] || die "destructive drill: pass --yes-really to confirm"
  load_inventory
  [ "$HOST_PROTECTED" = "false" ] || die "refusing: ${HOST_ARG} has respawn_protected: true in ${INVENTORY_FILE}"
}

guard_plan() { # lines describing what will happen
  echo "About to run the '${DRILL}' drill against ${HOST_ARG} (${HOST_USER}@${HOST_ADDR}). It will:" >&2
  local line
  for line in "$@"; do echo "  - ${line}" >&2; done
  countdown
}

simulate_banner() {
  echo "SIMULATED RUN: no server is touched; timings are random but plausible. The result is labelled SIMULATED." >&2
}

# ---------------------------------------------------------------- steps and timing

add_step() { printf '%s\t%s\n' "$1" "$2" >>"$STEPS_FILE"; }
begin_step() { STEP_NAME="$1"; STEP_T0="$(now)"; log "start: $1"; }
end_step() { add_step "$STEP_NAME" "$(( $(now) - STEP_T0 ))"; log "done:  ${STEP_NAME} ($(( $(now) - STEP_T0 ))s)"; }

run_step() { # name command...
  local name="$1"
  shift
  begin_step "$name"
  "$@" >&2 || die "step failed: ${name}"
  end_step
}

# ---------------------------------------------------------------- cluster access

kc() { kubectl --kubeconfig "$KUBECONFIG_FILE" --request-timeout=15s "$@"; }

# GET through the API server's service proxy, so no port-forward is needed.
canary_get() { kc get --raw "/api/v1/namespaces/${NS_CANARY}/services/canary-writer:8080/proxy$1"; }

read_seq() { # prints the highest seq in the database (the writer's /last-seq reads Postgres, not memory)
  local body
  body="$(canary_get /last-seq 2>/dev/null)" || return 1
  printf '%s' "$body" | python3 -c 'import sys, json; print(int(json.load(sys.stdin)["seq"]))' 2>/dev/null
}

# docs/DRILLS.md "Health check". Sets HC_REASON when it fails. The sequence test compares with the
# previous call, so it needs two calls; HC_PREV_SEQ is reset by wait_healthy.
health_check() {
  HC_REASON=""
  kc get --raw /readyz >/dev/null 2>&1 || { HC_REASON="k3s API not answering"; return 1; }

  local apps bad susp seq
  apps="$(kc -n argocd get applications -o 'jsonpath={range .items[*]}{.metadata.name}{"="}{.status.health.status}{"/"}{.status.sync.status}{"\n"}{end}' 2>/dev/null)" \
    || { HC_REASON="cannot list ArgoCD applications"; return 1; }
  [ -n "$apps" ] || { HC_REASON="no ArgoCD applications yet"; return 1; }
  bad="$(printf '%s\n' "$apps" | grep -v -x '.*=Healthy/Synced' | tr '\n' ' ' || true)"
  [ -z "$bad" ] || { HC_REASON="ArgoCD not Healthy/Synced: ${bad}"; return 1; }

  canary_get /healthz >/dev/null 2>&1 || { HC_REASON="canary /healthz not 200"; return 1; }
  if [ -n "${RESPAWN_APP_URL:-}" ]; then
    curl -fsS -o /dev/null --max-time 10 "$RESPAWN_APP_URL" 2>/dev/null || { HC_REASON="app endpoint ${RESPAWN_APP_URL} not 200"; return 1; }
  fi

  # A suspended policy means backups are off: after a rebuild that is not recovered yet.
  susp="$(kc -n "$NS_CANARY" get backuppolicy "$POLICY_NAME" -o 'jsonpath={.spec.suspend}' 2>/dev/null || true)"
  [ "$susp" != "true" ] || { HC_REASON="BackupPolicy ${POLICY_NAME} is suspended (make restore-data, or make resume-backups on a first install)"; return 1; }

  seq="$(read_seq)" || { HC_REASON="canary /last-seq not readable"; return 1; }
  [ -n "$FIRST_SEQ_AFTER" ] || FIRST_SEQ_AFTER="$seq"
  if [ -z "$HC_PREV_SEQ" ] || [ "$seq" -le "$HC_PREV_SEQ" ]; then
    HC_PREV_SEQ="$seq"
    HC_REASON="canary sequence not yet increasing (seq ${seq})"
    return 1
  fi
  HC_PREV_SEQ="$seq"
  HC_SEQ="$seq"
  return 0
}

wait_healthy() { # timeout-seconds; 0 when healthy, 1 on timeout
  local timeout="$1" t0 last=""
  t0="$(now)"
  HC_PREV_SEQ=""
  while :; do
    if health_check; then log "health check passes (seq ${HC_SEQ})"; return 0; fi
    if [ "$HC_REASON" != "$last" ]; then log "not healthy yet: ${HC_REASON}"; last="$HC_REASON"; fi
    [ $(( $(now) - t0 )) -lt "$timeout" ] || return 1
    sleep "$POLL_SECONDS"
  done
}

precheck() { # docs/DRILLS.md step 1: abort unless healthy and the canary is writing
  log "pre-check: the stack must be healthy before a fault is injected"
  wait_healthy "$PRECHECK_SECONDS" || die "pre-check failed (${HC_REASON}); not injecting a fault into an unhealthy stack"
  FIRST_SEQ_AFTER=""
}

# ---------------------------------------------------------------- Prometheus (through the API proxy)

prom_query() {
  local enc
  enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
  kc get --raw "/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query?query=${enc}"
}

alert_firing() { # alert name; 0 when it is firing now
  prom_query "ALERTS{alertname=\"$1\",alertstate=\"firing\"}" 2>/dev/null \
    | python3 -c 'import sys, json; sys.exit(0 if json.load(sys.stdin)["data"]["result"] else 1)' 2>/dev/null
}

# Sets ALERTS_FIRED to the alerts that were firing at any time since the given epoch (Watchdog excluded).
collect_alerts() {
  local window json
  window=$(( $(now) - $1 + 60 ))
  if json="$(prom_query "count by (alertname) (max_over_time(ALERTS{alertstate=\"firing\"}[${window}s]))" 2>/dev/null)"; then
    ALERTS_FIRED="$(printf '%s' "$json" | python3 -c '
import sys, json
d = json.load(sys.stdin)
names = {r["metric"]["alertname"] for r in d["data"]["result"]} - {"Watchdog", "InfoInhibitor"}
print(" ".join(sorted(names)))' 2>/dev/null || true)"
  else
    ALERTS_FIRED=""
    add_note "alerts_fired is empty because Prometheus could not be queried; that is NOT proof that nothing fired."
  fi
}

backup_age_seconds() { # prints the age of the newest verified backup, fails when there is none
  prom_query 'time() - max(backup_last_success_timestamp_seconds)' 2>/dev/null \
    | python3 -c 'import sys, json; r = json.load(sys.stdin)["data"]["result"]; print(int(float(r[0]["value"][1])))' 2>/dev/null
}

# ---------------------------------------------------------------- results

compute_rpo() { # last_seq_before first_seq_after -> whole seconds of lost writes
  awk -v b="$1" -v a="$2" -v i="$WRITE_INTERVAL_SECONDS" 'BEGIN { d = b - a; if (d < 0) d = 0; printf "%d", d * i + 0.5 }'
}

validate_json() { # file schema
  python3 - "$1" "$2" <<'PY'
import sys, json
try:
    import jsonschema
except ImportError:
    sys.exit("error: python module 'jsonschema' is missing (pip install jsonschema)")
doc, schema = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
errors = sorted(jsonschema.Draft7Validator(schema).iter_errors(doc), key=lambda e: list(e.path))
for e in errors:
    print("  %s: %s" % ("/".join(str(p) for p in e.path) or "(root)", e.message), file=sys.stderr)
sys.exit(1 if errors else 0)
PY
}

write_result() { # uses the run-state globals above plus MODE
  local ts out
  ts="$(python3 -c 'import sys, datetime; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))' "$T_START")"
  mkdir -p "$RESULTS_DIR"
  out="${RESULTS_DIR}/${DRILL}-${ts}.json"
  R_DRILL="$DRILL" R_MODE="$MODE" R_START="$T_START" R_FAULT="$T_FAULT" R_REC="$T_RECOVERED" \
  R_BEFORE="$LAST_SEQ_BEFORE" R_AFTER="$FIRST_SEQ_AFTER" R_RPO="$RPO_SECONDS" R_ALERTS="$ALERTS_FIRED" \
  R_NOTES="$NOTES" R_STEPS="$STEPS_FILE" R_ENV="$ENV_FILE" python3 - "${out}.tmp" <<'PY'
import os, sys, json, datetime
E = os.environ
def iso(v):
    return datetime.datetime.fromtimestamp(int(v), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def pairs(path):
    out = []
    for line in open(path):
        line = line.rstrip("\n")
        if line:
            k, v = line.split("\t", 1)
            out.append((k, v))
    return out
doc = {"drill": E["R_DRILL"], "mode": E["R_MODE"]}
if E["R_MODE"] == "simulated":
    doc["label"] = "SIMULATED"
doc.update({
    "started_at": iso(E["R_START"]),
    "fault_injected_at": iso(E["R_FAULT"]),
    "recovered_at": iso(E["R_REC"]),
    "rto_seconds": int(E["R_REC"]) - int(E["R_FAULT"]),
    "last_seq_before": int(E["R_BEFORE"]),
    "first_seq_after": int(E["R_AFTER"]),
    "rpo_seconds": int(E["R_RPO"]),
    "alerts_fired": sorted(set(E["R_ALERTS"].split())),
    "steps": [{"name": k, "seconds": int(v)} for k, v in pairs(E["R_STEPS"])],
    "notes": E["R_NOTES"],
    "environment": dict(pairs(E["R_ENV"])),
})
json.dump(doc, open(sys.argv[1], "w"), indent=2)
open(sys.argv[1], "a").write("\n")
PY
  if ! validate_json "${out}.tmp" "$SCHEMA_FILE"; then
    rm -f "${out}.tmp"
    die "generated result does not match drills/schema/result.schema.json (a bug in the drill)"
  fi
  mv "${out}.tmp" "$out"
  RESULT_FILE="$out"
  log "RTO $(( T_RECOVERED - T_FAULT ))s, RPO ${RPO_SECONDS}s, mode ${MODE}"
  log "result written: ${out}"
  echo "result_file=${out}" # stdout: run-all.sh reads this line
}

# ---------------------------------------------------------------- simulation

rand_between() { # min max (inclusive)
  echo $(( $1 + (RANDOM * 32768 + RANDOM) % ($2 - $1 + 1) ))
}

sim_begin() { SIM_TOTAL=0; : >"$STEPS_FILE"; MODE="simulated"; simulate_banner; }
sim_step() { # name min max: a fake step with a random duration
  local s
  s="$(rand_between "$2" "$3")"
  add_step "$1" "$s"
  SIM_TOTAL=$(( SIM_TOTAL + s ))
}
# Back-dates the timeline so that it ends now: a simulated run never claims a time in the future.
sim_finish() {
  T_RECOVERED="$(now)"
  T_FAULT=$(( T_RECOVERED - SIM_TOTAL ))
  T_START=$(( T_FAULT - $(rand_between 3 9) ))
}

# ---------------------------------------------------------------- summary

write_summary() { # scans RESULTS_DIR; a real run beats a simulated one, then the newest wins
  mkdir -p "$RESULTS_DIR"
  python3 - "$RESULTS_DIR" <<'PY'
import sys, os, json, glob, datetime
d = sys.argv[1]
best = {}
for path in sorted(glob.glob(os.path.join(d, "*.json"))):
    name = os.path.basename(path)
    if name == "summary.json" or name.startswith("sample-"):
        continue
    r = json.load(open(path))
    rank = (r["mode"] == "real", r["started_at"])
    if r["drill"] not in best or rank > best[r["drill"]][0]:
        best[r["drill"]] = (rank, name, r)
drills = {}
for k in ("kill-node", "fill-disk", "delete-server"):
    if k in best:
        _, name, r = best[k]
        e = {"file": name, "mode": r["mode"], "recovered_at": r["recovered_at"],
             "rto_seconds": r["rto_seconds"], "rpo_seconds": r["rpo_seconds"]}
        if r["mode"] == "simulated":
            e["label"] = "SIMULATED"
        drills[k] = e
modes = {e["mode"] for e in drills.values()}
mode = "none" if not modes else (modes.pop() if len(modes) == 1 else "mixed")
doc = {"generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "mode": mode, "drills": drills}
if mode in ("simulated", "mixed"):
    doc["label"] = "SIMULATED"
json.dump(doc, open(os.path.join(d, "summary.json"), "w"), indent=2)
open(os.path.join(d, "summary.json"), "a").write("\n")
PY
  validate_json "${RESULTS_DIR}/summary.json" "$SUMMARY_SCHEMA_FILE" || die "summary.json does not match its schema"
  log "summary written: ${RESULTS_DIR}/summary.json"
}
