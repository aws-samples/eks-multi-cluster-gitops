#!/usr/bin/env bash
# verify:number: 12
# verify:name: cfn KubernetesVersion AllowedValues == kubectl Mappings key set
# verify:requires-aws: false
# verify:implements: 2.4
#
# Check 12 (Requirement 2.6, 10.12, Property 9): parse
# initial-setup/auto/cfn.yaml and assert the KubernetesVersion parameter's
# AllowedValues list and the kubectl download map key set are equal.
#
# In this template the "kubectl download map" is not a CloudFormation
# `Mappings:` block: it is the `case {{Version}} in ... esac` shell block in the
# InstallK8sClientToolsDoc SSM document that selects K8S_VERSION and
# RELEASE_DATE for the kubectl download URL. There is exactly one such block
# that sets K8S_VERSION; its case labels are the map key set. A divergent key
# set makes the template invalid (Requirement 2 criterion 6).
#
# Parsing uses python3 with a targeted, CloudFormation-intrinsic-tolerant text
# parse (PyYAML / cfn_tools are not required, and this template embeds !Ref /
# !Sub intrinsics that a plain YAML loader would reject). If python3 is
# unavailable the module reports an INFO note and exits 0 rather than crashing.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

CFN_REL="initial-setup/auto/cfn.yaml"
CFN="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set}/$CFN_REL"

if [ ! -f "$CFN" ]; then
    verify_fail "$CFN_REL" "KubernetesVersion" "CloudFormation template not found at $CFN"
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    verify_info "python3 not available; cannot parse $CFN_REL for AllowedValues/kubectl-map parity (check 12)"
    exit 0
fi

# Write the parser to a temp file rather than feeding it via a here-doc inside
# a $() command substitution: stock macOS bash 3.2 mis-parses that combination.
PY_SCRIPT="$(mktemp)"
trap 'rm -f "$PY_SCRIPT"' EXIT
cat >"$PY_SCRIPT" <<'PY'
import sys, re

path, rel = sys.argv[1], sys.argv[2]

with open(path, "r") as fh:
    lines = fh.read().split("\n")
n = len(lines)


def clean(x):
    return str(x).replace("|", "/").replace("\n", " ")


def emit(kind, f, r, m):
    print("%s|%s|%s|%s" % (kind, clean(f), clean(r), clean(m)))


def indent(line):
    return len(line) - len(line.lstrip(" "))


# --- 1. AllowedValues of the top-level KubernetesVersion parameter ----------
# The parameter uses capitalised `AllowedValues`; the SSM documents use a
# lowercase `allowedValues` key, so anchoring on the parameter name plus the
# capitalised key keeps them distinct.
allowed = None
ki = None
for idx, line in enumerate(lines):
    if re.match(r'^  KubernetesVersion:\s*(#.*)?$', line):
        ki = idx
        break

if ki is not None:
    base = indent(lines[ki])  # 2
    # Gather the parameter's block (lines indented deeper than the key).
    block = []
    for idx in range(ki + 1, n):
        line = lines[idx]
        if line.strip() == "":
            block.append(line)
            continue
        if indent(line) <= base:
            break
        block.append(line)
    for j, line in enumerate(block):
        if re.match(r'^\s*AllowedValues:\s*(#.*)?$', line):
            av_ind = indent(line)
            vals = []
            for line2 in block[j + 1:]:
                if line2.strip() == "":
                    continue
                if indent(line2) <= av_ind:
                    break
                m = re.match(r'^\s*-\s*"?([^"#\s]+)"?\s*(#.*)?$', line2)
                if m:
                    vals.append(m.group(1))
            allowed = vals
            break

# --- 2. kubectl download map: case {{Version}} block keys -------------------
text = "\n".join(lines)
map_keys = None
for m in re.finditer(r'case\s*\{\{Version\}\}\s*in(.*?)\besac\b', text, re.S):
    body = m.group(1)
    if "K8S_VERSION" not in body:
        continue
    keys = []
    for bline in body.split("\n"):
        st = bline.strip()
        if st.startswith("*)"):
            break
        mm = re.match(r'^([0-9][0-9.]*)\)\s*$', st)
        if mm:
            keys.append(mm.group(1))
    map_keys = keys
    break

# --- 3. Report --------------------------------------------------------------
if allowed is None:
    emit("FAIL", rel, "Parameters.KubernetesVersion.AllowedValues",
         "could not locate the AllowedValues list of the KubernetesVersion parameter")
if map_keys is None:
    emit("FAIL", rel, "InstallK8sClientToolsDoc case {{Version}}",
         "could not locate the kubectl download version map (case {{Version}} block setting K8S_VERSION)")

if allowed is not None and map_keys is not None:
    sa, sm = set(allowed), set(map_keys)

    if len(allowed) != len(sa):
        dups = sorted(set(x for x in allowed if allowed.count(x) > 1))
        emit("FAIL", rel, "Parameters.KubernetesVersion.AllowedValues",
             "duplicate version(s) in AllowedValues: %s" % ", ".join(dups))
    if len(map_keys) != len(sm):
        dups = sorted(set(x for x in map_keys if map_keys.count(x) > 1))
        emit("FAIL", rel, "kubectl download map (case {{Version}})",
             "duplicate key(s) in kubectl download map: %s" % ", ".join(dups))

    if sa == sm:
        emit("PASS", rel, "KubernetesVersion AllowedValues == kubectl download map",
             "AllowedValues and kubectl download map key sets are equal: {%s}"
             % ", ".join(sorted(sa)))
    else:
        only_allowed = sorted(sa - sm)
        only_map = sorted(sm - sa)
        if only_allowed:
            emit("FAIL", rel, "kubectl download map (case {{Version}})",
                 "AllowedValues version(s) with no kubectl download entry: %s"
                 % ", ".join(only_allowed))
        if only_map:
            emit("FAIL", rel, "Parameters.KubernetesVersion.AllowedValues",
                 "kubectl download map key(s) not permitted by AllowedValues: %s"
                 % ", ".join(only_map))
PY

py_out="$(python3 "$PY_SCRIPT" "$CFN" "$CFN_REL")"
py_rc=$?

if [ "$py_rc" -ne 0 ]; then
    verify_fail "$CFN_REL" "KubernetesVersion" \
        "parser error while checking AllowedValues/kubectl-map parity: $(printf '%s' "$py_out" | tr '\n' ' ' | cut -c1-400)"
    exit 0
fi

while IFS='|' read -r kind f r m; do
    [ -z "$kind" ] && continue
    case "$kind" in
        PASS) verify_pass "$m" "$r" "$f" ;;
        FAIL) verify_fail "$f" "$r" "$m" ;;
        INFO) verify_info "$m" ;;
        *)    verify_info "$m" ;;
    esac
done <<EOF
$py_out
EOF

exit 0
