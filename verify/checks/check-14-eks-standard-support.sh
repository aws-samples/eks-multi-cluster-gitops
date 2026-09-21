#!/usr/bin/env bash
# verify:number: 14
# verify:name: EKS standard support for target and workload Kubernetes versions
# verify:requires-aws: true
# verify:implements: 2.7
#
# Check 14 (Requirement 2.2, 10.8; Correctness Property 10): confirm that
# Target_Kubernetes_Version (management cluster) and Workload_Kubernetes_Version
# (workload clusters) are BOTH in Amazon EKS standard support on the day the
# check runs, and that the workload version is exactly one minor below the
# target. The support-set membership is a fact the account reports, not a fact
# the repository states, so this check needs AWS credentials.
#
#   - workload == target - 1 minor                    -> verify_pass / verify_fail
#   - version present and in STANDARD_SUPPORT          -> verify_pass
#   - version present but EXTENDED_SUPPORT/UNSUPPORTED -> verify_fail (with the
#                                                         observed status and
#                                                         end-of-standard-support date)
#   - version not offered by Amazon EKS at all         -> verify_fail
#
# run.sh SKIPS this module when no credentials are present (Requirement 10.17),
# so the module only implements the credentialed path. It still guards
# internally: if the `aws` CLI is missing, or credentials cannot be resolved,
# or the API call cannot be completed, it degrades with verify_skip/verify_info
# rather than crashing.
#
# Version resolution order (task 2.7 asks us not to hardcode blindly):
#   1. VERIFY_TARGET_K8S_VERSION / VERIFY_WORKLOAD_K8S_VERSION env overrides
#      (also used to exercise this module deterministically in tests).
#   2. The `target` fields of the two k8s-version inventory entries, read from
#      .kiro/specs/component-version-upgrade/version-inventory.yaml where
#      practical.
#   3. The design-fixed defaults: target 1.36, workload 1.35.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

REPO_ROOT="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set}"
INVENTORY_REL=".kiro/specs/component-version-upgrade/version-inventory.yaml"
INVENTORY="$REPO_ROOT/$INVENTORY_REL"

TARGET_DEFAULT="1.36"
WORKLOAD_DEFAULT="1.35"

is_minor() { printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+$'; }

# ---------------------------------------------------------------------------
# 1. Resolve the two versions to check.
# ---------------------------------------------------------------------------
TARGET_VER="${VERIFY_TARGET_K8S_VERSION:-}"
WORKLOAD_VER="${VERIFY_WORKLOAD_K8S_VERSION:-}"

# Where env did not pin them, prefer the inventory targets.
if { [ -z "$TARGET_VER" ] || [ -z "$WORKLOAD_VER" ]; } \
    && [ -f "$INVENTORY" ] && command -v python3 >/dev/null 2>&1; then
    INV_PARSER="$(mktemp)"
    cat >"$INV_PARSER" <<'PY'
import sys, re
path = sys.argv[1]
want = {
    "Management_Cluster Kubernetes version": "TARGET",
    "Workload_Cluster control plane Kubernetes version": "WORKLOAD",
}
current = None
out = {}
with open(path) as fh:
    for line in fh:
        m = re.match(r'^\s*-?\s*component:\s*(.+?)\s*$', line)
        if m:
            current = m.group(1).strip().strip("'\"")
            continue
        m = re.match(r'^\s*target:\s*(.+?)\s*$', line)
        if m and current in want:
            val = m.group(1).strip().strip("'\"")
            if re.match(r'^[0-9]+\.[0-9]+$', val):
                out[want[current]] = val
for k in ("TARGET", "WORKLOAD"):
    if k in out:
        print("%s=%s" % (k, out[k]))
PY
    inv_out="$(python3 "$INV_PARSER" "$INVENTORY" 2>/dev/null)"
    rm -f "$INV_PARSER"
    inv_target="$(printf '%s\n' "$inv_out" | sed -n 's/^TARGET=//p' | head -n1)"
    inv_workload="$(printf '%s\n' "$inv_out" | sed -n 's/^WORKLOAD=//p' | head -n1)"
    [ -z "$TARGET_VER" ] && [ -n "$inv_target" ] && TARGET_VER="$inv_target"
    [ -z "$WORKLOAD_VER" ] && [ -n "$inv_workload" ] && WORKLOAD_VER="$inv_workload"
fi

# Design-fixed fallbacks.
[ -z "$TARGET_VER" ] && TARGET_VER="$TARGET_DEFAULT"
[ -z "$WORKLOAD_VER" ] && WORKLOAD_VER="$WORKLOAD_DEFAULT"

if ! is_minor "$TARGET_VER" || ! is_minor "$WORKLOAD_VER"; then
    verify_info "could not resolve valid Kubernetes minor versions to check (target='${TARGET_VER}', workload='${WORKLOAD_VER}'); skipping EKS standard-support check"
    exit 0
fi

verify_info "checking EKS standard support for target ${TARGET_VER} (management) and workload ${WORKLOAD_VER}"

# ---------------------------------------------------------------------------
# 2. Property 10 relation: workload is exactly one minor below target.
# ---------------------------------------------------------------------------
t_major="${TARGET_VER%%.*}"; t_minor="${TARGET_VER#*.}"
w_major="${WORKLOAD_VER%%.*}"; w_minor="${WORKLOAD_VER#*.}"
if [ "$t_major" = "$w_major" ] && [ "$((t_minor - 1))" -eq "$w_minor" ] 2>/dev/null; then
    verify_pass "workload ${WORKLOAD_VER} is exactly one minor below target ${TARGET_VER}" \
        "Kubernetes version gap" "$INVENTORY_REL"
else
    verify_fail "$INVENTORY_REL" "Kubernetes version gap" \
        "workload ${WORKLOAD_VER} is not exactly one minor below target ${TARGET_VER} (Property 10)"
fi

# ---------------------------------------------------------------------------
# 3. Guard: aws CLI present?
# ---------------------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
    verify_skip "aws CLI not found on PATH; cannot query EKS standard support (target ${TARGET_VER}, workload ${WORKLOAD_VER})"
    exit 0
fi

AWS_REGION_ARG=""
if [ -n "${VERIFY_AWS_REGION:-}" ]; then
    AWS_REGION_ARG="--region ${VERIFY_AWS_REGION}"
elif [ -n "${AWS_REGION:-}" ]; then
    AWS_REGION_ARG="--region ${AWS_REGION}"
elif [ -n "${AWS_DEFAULT_REGION:-}" ]; then
    AWS_REGION_ARG="--region ${AWS_DEFAULT_REGION}"
fi

# ---------------------------------------------------------------------------
# 4. Query Amazon EKS for the versions it currently offers and their status.
# ---------------------------------------------------------------------------
AWS_OUT="$(mktemp)"
AWS_ERR="$(mktemp)"
trap 'rm -f "$AWS_OUT" "$AWS_ERR"' EXIT

# shellcheck disable=SC2086
run_with_timeout 60 aws eks describe-cluster-versions --output json $AWS_REGION_ARG \
    >"$AWS_OUT" 2>"$AWS_ERR"
aws_rc=$?

if [ "$aws_rc" -ne 0 ]; then
    err="$(tr '\n' ' ' <"$AWS_ERR" | cut -c1-400)"
    if [ "$aws_rc" -eq 124 ]; then
        verify_info "aws eks describe-cluster-versions did not complete within 60s; cannot confirm standard support this run"
        exit 0
    fi
    case "$err" in
        *[Cc]redential*|*[Tt]oken*|*ExpiredToken*|*"Unable to locate"*|*AccessDenied*|*"not authorized"*|*Forbidden*|*SSO*|*sso*)
            verify_skip "AWS credentials not usable for eks:DescribeClusterVersions (${err}); cannot confirm standard support"
            ;;
        *"Invalid choice"*|*"argument"*|*"describe-cluster-versions"*)
            # Older aws CLI without describe-cluster-versions.
            verify_info "installed aws CLI does not support 'eks describe-cluster-versions' (${err}); upgrade the CLI to run check 14"
            ;;
        *)
            verify_info "could not query EKS cluster versions (exit ${aws_rc}): ${err}"
            ;;
    esac
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. Evaluate each version against the reported support set.
# ---------------------------------------------------------------------------
EVAL_PARSER="$(mktemp)"
cat >"$EVAL_PARSER" <<'PY'
import sys, json

resp_path = sys.argv[1]
targets = sys.argv[2:]  # list of "role:version"

with open(resp_path) as fh:
    data = json.load(fh)

items = data.get("clusterVersions") or []


def clean(x):
    return str(x).replace("|", "/").replace("\n", " ")


def support_status(entry):
    # Newer CLIs expose `versionStatus` (STANDARD_SUPPORT / EXTENDED_SUPPORT /
    # UNSUPPORTED); older ones expose `status`. Prefer the explicit field.
    for key in ("versionStatus", "status"):
        v = entry.get(key)
        if v:
            return str(v)
    return ""


# Index entries by clusterVersion; prefer an entry that carries a support
# status, and among those an EKS (not local/outpost) clusterType if present.
by_version = {}
for e in items:
    ver = str(e.get("clusterVersion", ""))
    if not ver:
        continue
    prev = by_version.get(ver)
    if prev is None:
        by_version[ver] = e
        continue
    if not support_status(prev) and support_status(e):
        by_version[ver] = e


def is_standard(status):
    s = status.upper().replace("-", "_").replace(" ", "_")
    return s == "STANDARD_SUPPORT" or s == "STANDARD"


for spec in targets:
    role, _, ver = spec.partition(":")
    e = by_version.get(ver)
    if e is None:
        print("FAIL|%s|Kubernetes %s (%s)|not offered by Amazon EKS (absent from describe-cluster-versions output)"
              % (clean(role), clean(ver), clean(role)))
        continue
    status = support_status(e)
    eos = e.get("endOfStandardSupportDate") or e.get("endOfStandardSupport") or ""
    if not status:
        # No status field at all: report the version as present but the
        # support state as undeterminable rather than passing it silently.
        print("FAIL|%s|Kubernetes %s (%s)|present but Amazon EKS reported no support-status field to confirm standard support"
              % (clean(role), clean(ver), clean(role)))
    elif is_standard(status):
        detail = "in standard support (status %s" % clean(status)
        if eos:
            detail += ", end of standard support %s" % clean(str(eos))
        detail += ")"
        print("PASS|%s|Kubernetes %s (%s)|%s" % (clean(role), clean(ver), clean(role), detail))
    else:
        detail = "not in standard support: observed status %s" % clean(status)
        if eos:
            detail += ", end of standard support %s" % clean(str(eos))
        print("FAIL|%s|Kubernetes %s (%s)|%s" % (clean(role), clean(ver), clean(role), detail))
PY

eval_out="$(python3 "$EVAL_PARSER" "$AWS_OUT" \
    "management:${TARGET_VER}" "workload:${WORKLOAD_VER}" 2>&1)"
eval_rc=$?
rm -f "$EVAL_PARSER"

if [ "$eval_rc" -ne 0 ]; then
    verify_info "could not parse eks describe-cluster-versions output: $(printf '%s' "$eval_out" | tr '\n' ' ' | cut -c1-300)"
    exit 0
fi

SRC="aws eks describe-cluster-versions"
while IFS='|' read -r kind role res detail; do
    [ -z "$kind" ] && continue
    case "$kind" in
        PASS) verify_pass "$detail" "$res" "$SRC" ;;
        FAIL) verify_fail "$SRC" "$res" "$detail" ;;
        *)    verify_info "$detail" ;;
    esac
done <<EOF
$eval_out
EOF

exit 0
