#!/usr/bin/env bash
# verify:number: 10
# verify:name: Cloud9 residue scan
# verify:requires-aws: false
# verify:implements: 2.5
#
# Check 10 (Requirement 10.9, Property 16). Scan the solution and bootstrap
# sources for any Cloud9 residue and report each hit as a failure:
#   * `AWS::Cloud9::` resource types
#   * `cloud9:` IAM actions (the cloud9 service namespace in IAM statements)
#   * `CLOUD9_`-prefixed environment variables
#   * references to the removed Cloud9 asset paths
# Uses ripgrep when available and falls back to `grep -r` otherwise.
#
# Scope: the scan deliberately excludes .git, the spec directory (.kiro) and
# the verification suite itself (verify). Those legitimately name Cloud9 — the
# spec plans its removal and this very check embeds the patterns it searches
# for — so scanning them would report the tooling as residue. Property 16 is
# about the deployed GitOps_Solution and Bootstrap_Setup, not the spec or the
# checker.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

REPO="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set}"
cd "$REPO" || { verify_fail "$REPO" "repo-root" "could not cd to repository root"; exit 0; }

# One extended-regex alternation covering every residue class. The asset paths
# are matched by basename so a reference survives being written with or without
# its directory prefix.
PATTERN='AWS::Cloud9::|cloud9:|CLOUD9_|cloud9-role-permission-policy-template\.json|c9-modify-role\.png|c9instancerole\.png|cloud9-role\.png'

hits=0
emit_hit() {
    # <file>:<line>:<matched text>
    local file="$1" line="$2" text="$3"
    verify_fail "$file" "cloud9-residue (line ${line})" "matched: ${text}"
    hits=$((hits + 1))
}

if command -v rg >/dev/null 2>&1; then
    # rg: -n line numbers, -I skip binaries, --no-heading for grep-style output,
    # -e regex, and glob excludes for the out-of-scope trees.
    while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        file="${rec%%:*}"; rest="${rec#*:}"
        line="${rest%%:*}"; text="${rest#*:}"
        emit_hit "$file" "$line" "$text"
    done < <(rg -n -I --no-heading --color never \
                --glob '!.git' --glob '!.kiro' --glob '!verify' \
                -e "$PATTERN" . 2>/dev/null)
else
    verify_info "ripgrep not found; using 'grep -r' fallback for the residue scan"
    while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        file="${rec%%:*}"; rest="${rec#*:}"
        line="${rest%%:*}"; text="${rest#*:}"
        emit_hit "$file" "$line" "$text"
    done < <(grep -rInE \
                --exclude-dir=.git --exclude-dir=.kiro --exclude-dir=verify \
                "$PATTERN" . 2>/dev/null)
fi

if [ "$hits" -eq 0 ]; then
    verify_pass "no Cloud9 residue found (AWS::Cloud9::, cloud9: IAM actions, CLOUD9_ variables, removed asset paths)" "cloud9-residue"
fi

exit 0
