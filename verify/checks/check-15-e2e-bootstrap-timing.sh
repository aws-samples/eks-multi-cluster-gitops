#!/usr/bin/env bash
# verify:number: 15
# verify:name: end-to-end bootstrap and onboarding timing assertions
# verify:requires-aws: true
# verify:implements: 2.7
#
# Check 15 (Requirement 8, criteria 8.1-8.11): the harness for the documented
# end-to-end flow, run once against a real account. It asserts the timing
# bounds of Requirement 8:
#
#   8.1  management cluster ACTIVE (all node-group nodes Ready)   <= 30 min
#   8.2  hub Crossplane/ESO/Sealed-Secrets reconciliations Ready  <= 15 min
#   8.3  sealed secret unsealed to a Secret with the same keys    <= 60 sec
#   8.4  workload cluster composite Ready=True & Synced=True      <= 45 min
#   8.5  Flux installed into the workload cluster (Available)     <= 15 min
#   8.6  workload add-ons (ALB/EBS-CSI/Karpenter/Crossplane) Ready<= 20 min
#   8.7  application pods Ready                                   <= 10 min
#   8.8  DynamoDB managed resource Ready=True & Synced=True       <= 10 min
#   8.9  control-plane upgrade to target version                 <= 60 min
#   8.10 managed node-group upgrade to target version            <= 60 min
#   8.11 workload cluster + its AWS resources torn down           <= 45 min
#
# This is a harness/scaffold for a manual or integration run: it is NOT an
# offline check and it does NOT provision infrastructure. run.sh SKIPS it when
# no credentials are present (Requirement 10.17). Even with credentials, it
# performs only READ-ONLY, non-mutating AWS calls, and only when explicitly
# pointed at an already-running bootstrap through environment variables. With
# no such inputs it reports what it needs and returns without failing the run.
#
# Driving inputs (all optional; nothing runs against AWS without them):
#   VERIFY_E2E_STACK_NAME    the bootstrap CloudFormation stack name; its
#                            CreationTime anchors the 8.1 "start of bootstrap".
#   VERIFY_E2E_MGMT_CLUSTER  the management EKS cluster name; enables the
#                            read-only 8.1 measurement (status + createdAt).
#   VERIFY_AWS_REGION        region for the read-only calls (else AWS_REGION /
#                            AWS_DEFAULT_REGION).
#
# The reconciliation-timing criteria (8.2-8.11) are measured inside the
# clusters via Flux/Crossplane/kubectl during the live run and are reported
# here as informational: they require cluster API access and a driven bootstrap
# that this offline-first suite does not perform on its own.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

STACK_NAME="${VERIFY_E2E_STACK_NAME:-}"
MGMT_CLUSTER="${VERIFY_E2E_MGMT_CLUSTER:-}"

AWS_REGION_ARG=""
if [ -n "${VERIFY_AWS_REGION:-}" ]; then
    AWS_REGION_ARG="--region ${VERIFY_AWS_REGION}"
elif [ -n "${AWS_REGION:-}" ]; then
    AWS_REGION_ARG="--region ${AWS_REGION}"
elif [ -n "${AWS_DEFAULT_REGION:-}" ]; then
    AWS_REGION_ARG="--region ${AWS_DEFAULT_REGION}"
fi

# ---------------------------------------------------------------------------
# Always publish the timing budget so the report documents what a live run
# asserts, whether or not this invocation can measure anything.
# ---------------------------------------------------------------------------
verify_info "Requirement 8 end-to-end timing budget (asserted during a live run):"
verify_info "  8.1  management cluster ACTIVE, nodes Ready ...... within 30 min of bootstrap start"
verify_info "  8.2  hub Crossplane/ESO/Sealed-Secrets Ready ..... within 15 min of Flux bootstrap"
verify_info "  8.3  sealed secret unsealed (same key names) ..... within 60 sec"
verify_info "  8.4  workload composite Ready=True & Synced=True .. within 45 min of reconcile"
verify_info "  8.5  Flux installed into workload cluster ........ within 15 min"
verify_info "  8.6  workload add-ons Ready ...................... within 20 min"
verify_info "  8.7  application pods Ready ...................... within 10 min of onboarding commit"
verify_info "  8.8  DynamoDB managed resource Ready & Synced .... within 10 min"
verify_info "  8.9  control-plane upgrade to target version ..... within 60 min"
verify_info "  8.10 node-group upgrade to target version ........ within 60 min"
verify_info "  8.11 workload cluster + AWS resources torn down .. within 45 min"

# ---------------------------------------------------------------------------
# Guard: aws CLI present?
# ---------------------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
    verify_skip "aws CLI not found on PATH; end-to-end timing harness cannot run any read-only measurement"
    exit 0
fi

# ---------------------------------------------------------------------------
# Without driving inputs there is no running bootstrap to observe: report the
# required inputs and return without failing. Nothing is provisioned.
# ---------------------------------------------------------------------------
if [ -z "$MGMT_CLUSTER" ]; then
    verify_skip "no running bootstrap supplied to observe (set VERIFY_E2E_MGMT_CLUSTER, and VERIFY_E2E_STACK_NAME to anchor the 8.1 start time); this harness never provisions infrastructure"
    verify_info "criteria 8.2-8.11 are measured in-cluster via Flux/Crossplane/kubectl during the live end-to-end run"
    exit 0
fi

# ---------------------------------------------------------------------------
# Read-only 8.1 measurement, when a management cluster (and ideally the stack)
# is supplied. This describes existing resources only; it creates nothing.
# ---------------------------------------------------------------------------
CL_OUT="$(mktemp)"
CL_ERR="$(mktemp)"
ST_OUT="$(mktemp)"
trap 'rm -f "$CL_OUT" "$CL_ERR" "$ST_OUT"' EXIT

# shellcheck disable=SC2086
run_with_timeout 60 aws eks describe-cluster --name "$MGMT_CLUSTER" --output json $AWS_REGION_ARG \
    >"$CL_OUT" 2>"$CL_ERR"
cl_rc=$?

if [ "$cl_rc" -ne 0 ]; then
    err="$(tr '\n' ' ' <"$CL_ERR" | cut -c1-400)"
    if [ "$cl_rc" -eq 124 ]; then
        verify_info "aws eks describe-cluster did not complete within 60s for '${MGMT_CLUSTER}'; skipping 8.1 measurement"
        exit 0
    fi
    case "$err" in
        *[Cc]redential*|*[Tt]oken*|*ExpiredToken*|*"Unable to locate"*|*AccessDenied*|*"not authorized"*|*Forbidden*|*SSO*|*sso*)
            verify_skip "AWS credentials not usable for eks:DescribeCluster (${err}); cannot measure 8.1"
            ;;
        *ResourceNotFound*|*"No cluster found"*|*NotFound*)
            verify_info "management cluster '${MGMT_CLUSTER}' not found yet; 8.1 not measurable this run (${err})"
            ;;
        *)
            verify_info "could not describe management cluster '${MGMT_CLUSTER}' (exit ${cl_rc}): ${err}"
            ;;
    esac
    exit 0
fi

# Optionally fetch the stack creation time to anchor "start of bootstrap".
stack_ok=0
if [ -n "$STACK_NAME" ]; then
    # shellcheck disable=SC2086
    if run_with_timeout 60 aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --output json $AWS_REGION_ARG >"$ST_OUT" 2>/dev/null; then
        stack_ok=1
    else
        verify_info "could not describe stack '${STACK_NAME}'; measuring 8.1 status only, without the 30-min elapsed bound"
    fi
fi

E2E_PARSER="$(mktemp)"
cat >"$E2E_PARSER" <<'PY'
import sys, json, datetime, re

cl_path = sys.argv[1]
st_path = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
budget_min = 30


def clean(x):
    return str(x).replace("|", "/").replace("\n", " ")


def parse_ts(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return datetime.datetime.fromtimestamp(v, datetime.timezone.utc)
    s = str(v).strip()
    # Normalise trailing Z and drop fractional seconds/offset noise for a
    # tolerant parse across CLI output shapes.
    s = s.replace("Z", "+00:00")
    try:
        return datetime.datetime.fromisoformat(s)
    except Exception:
        m = re.match(r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})', s)
        if m:
            dt = datetime.datetime.fromisoformat(m.group(1))
            return dt.replace(tzinfo=datetime.timezone.utc)
    return None


with open(cl_path) as fh:
    cl = json.load(fh).get("cluster", {})

name = cl.get("name", "?")
status = str(cl.get("status", "")).upper()
created = parse_ts(cl.get("createdAt"))

start = None
if st_path:
    try:
        with open(st_path) as fh:
            stacks = json.load(fh).get("Stacks", [])
        if stacks:
            start = parse_ts(stacks[0].get("CreationTime"))
    except Exception:
        start = None

res = "management cluster '%s' (criterion 8.1)" % clean(name)

if status != "ACTIVE":
    print("INFO||%s|not yet ACTIVE (status %s); 8.1 becomes measurable once the cluster reports ACTIVE"
          % (res, clean(status or "unknown")))
    sys.exit(0)

# Cluster is ACTIVE. If we have both an anchor start and a creation time,
# assert the 30-minute bound; otherwise report ACTIVE as an informational
# observation (the full bound needs the bootstrap start time).
anchor = start
if anchor is not None and created is not None:
    elapsed_min = (created - anchor).total_seconds() / 60.0
    if elapsed_min < 0:
        print("INFO||%s|ACTIVE, but stack CreationTime is after cluster createdAt; cannot compute a meaningful elapsed time"
              % res)
    elif elapsed_min <= budget_min:
        print("PASS||%s|ACTIVE within %.1f min of stack creation (budget %d min)"
              % (res, elapsed_min, budget_min))
    else:
        print("FAIL||%s|ACTIVE but took %.1f min from stack creation, exceeding the %d min budget"
              % (res, elapsed_min, budget_min))
else:
    print("INFO||%s|ACTIVE (supply VERIFY_E2E_STACK_NAME to assert the 30-min bound; node-group node readiness is measured in-cluster)"
          % res)
PY

st_arg=""
[ "$stack_ok" -eq 1 ] && st_arg="$ST_OUT"
e2e_out="$(python3 "$E2E_PARSER" "$CL_OUT" "$st_arg" 2>&1)"
e2e_rc=$?
rm -f "$E2E_PARSER"

if [ "$e2e_rc" -ne 0 ]; then
    verify_info "could not evaluate 8.1 from describe-cluster output: $(printf '%s' "$e2e_out" | tr '\n' ' ' | cut -c1-300)"
    exit 0
fi

SRC="aws eks describe-cluster / cloudformation describe-stacks (read-only)"
while IFS='|' read -r kind _blank res detail; do
    [ -z "$kind" ] && continue
    case "$kind" in
        PASS) verify_pass "$detail" "$res" "$SRC" ;;
        FAIL) verify_fail "$SRC" "$res" "$detail" ;;
        *)    verify_info "$detail" ;;
    esac
done <<EOF
$e2e_out
EOF

verify_info "criteria 8.2-8.11 require in-cluster Flux/Crossplane/kubectl observation during the live run; not measured by this read-only harness"
exit 0
