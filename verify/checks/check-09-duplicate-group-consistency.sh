#!/usr/bin/env bash
# verify:number: 9
# verify:name: duplicate-group consistency (inventory-driven)
# verify:requires-aws: false
# verify:implements: 2.5
#
# Check 9 (Requirement 10.13, Property 8). Two assertions, both driven by the
# Version Inventory:
#   1. every inventory entry sharing a `duplicate_group` states the same
#      `target`; and
#   2. the value actually present at each entry's stated file+locator matches
#      that target.
# Each divergence is reported via verify_fail carrying the file, the resource
# (locator / group), and observed-vs-expected. Group-equality is a pure
# inventory comparison and always decidable; the value-at-file assertion is
# best-effort against the locator and degrades to an INFO note where a locator
# is not machine-resolvable, rather than guessing.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

REPO="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set}"
LIB_DIR="$(dirname -- "$VERIFY_LIB")"
INV="$REPO/.kiro/specs/component-version-upgrade/version-inventory.yaml"

if ! command -v python3 >/dev/null 2>&1; then
    verify_info "python3 not available; duplicate-group consistency not evaluated (a YAML parser is required)"
    exit 0
fi
if [ ! -f "$INV" ]; then
    verify_fail "$INV" "version-inventory" "inventory file not found; cannot evaluate duplicate-group consistency"
    exit 0
fi

run_py() {
    PYTHONPATH="$LIB_DIR" python3 - "$INV" "$REPO" <<'PY'
import os
import sys
from collections import defaultdict, OrderedDict

import inventory_lib as inv

inv_path, repo_root = sys.argv[1], sys.argv[2]

try:
    entries = inv.parse_inventory(inv_path)
except Exception as exc:  # noqa: BLE001 - report, never crash the suite
    inv.emit("INFO", inv_path, "version-inventory",
             "could not parse inventory: %s" % exc)
    sys.exit(0)

groups = OrderedDict()
for e in entries:
    g = e.get("duplicate_group")
    if g:
        groups.setdefault(g, []).append(e)

if not groups:
    inv.emit("INFO", inv_path, "version-inventory",
             "no duplicate_group entries found in inventory")
    sys.exit(0)

for g, members in groups.items():
    targets = OrderedDict((m.get("target", ""), None) for m in members)

    # Assertion 1: group-target equality (Property 8, first clause).
    if len(targets) > 1:
        tlist = sorted(targets.keys())
        for m in members:
            inv.emit(
                "FAIL", m.get("file", ""), "%s (%s)" % (m.get("locator", ""), g),
                "duplicate_group '%s' target mismatch: this entry states '%s'; "
                "group states %s" % (g, m.get("target", ""), tlist),
            )
        continue  # a divergent group has no single target to compare files to

    group_target = next(iter(targets))
    inv.emit("PASS", "", g,
             "duplicate_group '%s': all %d entries state target '%s'"
             % (g, len(members), group_target))

    # Assertion 2: the value at each occurrence matches the group target
    # (Property 8, second clause). Skipped for not-yet-resolved targets.
    if inv.is_placeholder(group_target):
        inv.emit("INFO", "", g,
                 "duplicate_group '%s' target '%s' is not a concrete version "
                 "yet; per-file value comparison skipped"
                 % (g, group_target))
        continue

    for m in members:
        verdict, detail = inv.occurrence_verdict(repo_root, m, group_target)
        res = "%s (%s)" % (m.get("locator", ""), g)
        if verdict == "match":
            inv.emit("PASS", m.get("file", ""), res,
                     "states target '%s' (%s)" % (group_target, detail))
        elif verdict == "drift":
            inv.emit("FAIL", m.get("file", ""), res,
                     "expected '%s' but %s" % (group_target, detail))
        elif verdict == "missing":
            inv.emit("FAIL", m.get("file", ""), res,
                     "file not found; cannot confirm it states '%s'" % group_target)
        else:  # unknown
            inv.emit("INFO", m.get("file", ""), res,
                     "could not confirm value against target '%s' (%s)"
                     % (group_target, detail))
PY
}

# Capture to a file (not a pipe) so a python failure is not masked by the
# exit status of the reading loop.
PYOUT="$(mktemp)"; PYERR="$(mktemp)"
run_py >"$PYOUT" 2>"$PYERR"
rc=$?
if [ "$rc" -ne 0 ]; then
    verify_fail "$INV" "check-09" "inventory evaluation failed (python exit $rc): $(tr '\n' ' ' <"$PYERR" | tail -c 300)"
fi
while IFS=$'\037' read -r st f r m; do
    case "$st" in
        PASS)       verify_pass "$m" "$r" "$f" ;;
        FAIL)       verify_fail "$f" "$r" "$m" ;;
        INFO)       verify_info "$m" ;;
        UNVERIFIED) verify_unverified "$f" "$r" "$m" ;;
        *)          verify_info "check-09 unexpected status '$st': $m" ;;
    esac
done <"$PYOUT"
rm -f "$PYOUT" "$PYERR"

exit 0
