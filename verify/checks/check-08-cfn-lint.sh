#!/usr/bin/env bash
# verify:number: 8
# verify:name: cfn-lint over initial-setup/auto/cfn.yaml
# verify:requires-aws: false
# verify:implements: 2.4
#
# Check 8 (Requirement 10.12, Property 9): lint the CloudFormation template
# initial-setup/auto/cfn.yaml with cfn-lint and report each error with its
# template location (file:line, rule id, message) via verify_fail.
#
# Graceful degradation: if cfn-lint (or python3, which parses its JSON output)
# is not installed, the module reports an INFO note and exits 0 rather than
# crashing or emitting a false failure -- a missing linter is an environment
# gap, not a defect in the template.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

CFN_REL="initial-setup/auto/cfn.yaml"
CFN="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set}/$CFN_REL"

if [ ! -f "$CFN" ]; then
    verify_fail "$CFN_REL" "template" "CloudFormation template not found at $CFN"
    exit 0
fi

if ! command -v cfn-lint >/dev/null 2>&1; then
    verify_info "cfn-lint not installed; skipped lint of $CFN_REL (install cfn-lint to enable check 8)"
    exit 0
fi

err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT

lint_out="$(cfn-lint --format json "$CFN" 2>"$err_file")"
lint_rc=$?

# Exit 0 from cfn-lint means no findings at all.
if [ "$lint_rc" -eq 0 ]; then
    verify_pass "cfn-lint reported no findings for $CFN_REL" "template" "$CFN_REL"
    exit 0
fi

# cfn-lint produced no JSON on stdout: it failed to run (e.g. exit code 8).
if [ -z "$(printf '%s' "$lint_out" | tr -d '[:space:]')" ]; then
    detail="$(tr '\n' ' ' <"$err_file" | cut -c1-400)"
    verify_fail "$CFN_REL" "cfn-lint" "cfn-lint exited $lint_rc without JSON output: ${detail:-<no stderr>}"
    exit 0
fi

# Parse the JSON findings. Errors -> verify_fail with location; warnings and
# informational findings -> verify_info (non-scoring).
if ! command -v python3 >/dev/null 2>&1; then
    verify_info "cfn-lint reported findings but python3 is unavailable to parse them; raw: $(printf '%s' "$lint_out" | tr '\n' ' ' | cut -c1-400)"
    exit 0
fi

# Write the parser to a temp file rather than feeding it via a here-doc inside
# a $() command substitution: stock macOS bash 3.2 mis-parses that combination.
PY_SCRIPT="$(mktemp)"
trap 'rm -f "$err_file" "$PY_SCRIPT"' EXIT
cat >"$PY_SCRIPT" <<'PY'
import sys, json

rel = sys.argv[1]
raw = sys.stdin.read()

def clean(x):
    return str(x).replace("|", "/").replace("\n", " ")

try:
    items = json.loads(raw) if raw.strip() else []
except Exception as exc:  # noqa: BLE001
    print("PARSEERR|%s" % clean(exc))
    sys.exit(0)

for it in items:
    level = str(it.get("Level", ""))
    rule = it.get("Rule") or {}
    rid = rule.get("Id", "")
    msg = it.get("Message", "")
    start = (it.get("Location") or {}).get("Start") or {}
    line = start.get("LineNumber", "?")
    where = "%s:%s" % (rel, line)
    resource = ("%s %s" % (rid, level)).strip()
    kind = "FAIL" if level.lower() == "error" else "INFO"
    print("%s|%s|%s|%s" % (kind, clean(where), clean(resource), clean(msg)))
PY

parsed="$(printf '%s' "$lint_out" | python3 "$PY_SCRIPT" "$CFN_REL")"

emitted=0
while IFS='|' read -r kind f r m; do
    [ -z "$kind" ] && continue
    emitted=1
    case "$kind" in
        FAIL)     verify_fail "$f" "$r" "$m" ;;
        INFO)     verify_info "$f [$r] $m" ;;
        PARSEERR) verify_fail "$CFN_REL" "cfn-lint" "could not parse cfn-lint JSON output: $f" ;;
        *)        verify_info "$m" ;;
    esac
done <<EOF
$parsed
EOF

# cfn-lint exited non-zero but nothing was extracted: surface it rather than
# silently passing.
if [ "$emitted" -eq 0 ]; then
    verify_fail "$CFN_REL" "cfn-lint" "cfn-lint exited $lint_rc but no findings could be extracted from its output"
fi

exit 0
