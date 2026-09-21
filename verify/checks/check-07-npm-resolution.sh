#!/usr/bin/env bash
# verify:number: 7
# verify:name: npm package pins resolve on the npm registry
# verify:requires-aws: false
# verify:implements: 2.3
#
# Check 7 (task 2.3; Requirement 7.4, 7.7, 10.7; Property 12).
#
# For every dependency/devDependency in a package.json under repos/ or
# initial-setup/, confirm it resolves on the npm registry.
#
# Requirement 7.4 mandates that each frontend npm package be pinned to a RANGE
# (e.g. `express ^4.21.2`, `body-parser ^1.20.3`) whose lower bound is a
# published version resolvable by the npm client, and Requirement 7.7 requires
# that a lockfile-validating install resolve every declared range. A pin is
# therefore "resolved" when the npm registry publishes at least one version
# that satisfies it - exactly what the npm client does at install time. This
# check honours that in two shapes:
#
#   - RANGE pin (a caret/tilde range, comparator set, `x`/`*` wildcard,
#     hyphen range, or `||` union): fetch the package document from the npm
#     registry, then resolve the range against the set of PUBLISHED versions
#     using the semver engine bundled with the local npm client (the same
#     resolver npm uses). The pin PASSES when at least one published version
#     satisfies the range, and the concrete resolved version is reported. A
#     range that no published version satisfies (unpublished/unsatisfiable) is
#     UNRESOLVED - resolution is not weakened.
#   - EXACT pin (a bare semver string, optionally a leading `=`): confirmed by
#     GETting https://registry.npmjs.org/<name>/<version> and comparing the
#     registry's `.version` to the pinned string VERBATIM (Property 12 asks for
#     an exact-STRING match, so a normalized mismatch such as a stray `v`
#     prefix is UNRESOLVED).
#
# A git/url/file/link/workspace dependency is not a registry version pin and is
# reported UNRESOLVED with that reason. Registry calls go through verify_retry,
# so an unreachable registry becomes UNVERIFIED rather than a false UNRESOLVED
# (Requirement 10.16); a definite 404 is UNRESOLVED.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

ROOT="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set - run via verify/run.sh}"

if ! command -v curl >/dev/null 2>&1; then
    verify_info "curl not available; npm resolution skipped"
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    verify_info "jq not available; cannot parse package.json - npm resolution skipped"
    exit 0
fi

files="$(
    for d in "$ROOT/repos" "$ROOT/initial-setup"; do
        [ -d "$d" ] || continue
        find "$d" -type f -name 'package.json' -not -path '*/node_modules/*' 2>/dev/null
    done | sort -u
)"

if [ -z "$files" ]; then
    verify_info "no package.json files found under repos/ or initial-setup/"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --------------------------------------------------------------------------
# Range resolver: reads a JSON array of published version strings on stdin and
# takes the range as argv[1]. Prints the highest published version that
# satisfies the range, an empty line when none satisfies it, or the literal
# "INVALID" when the string is not a valid semver range. It uses the semver
# module bundled with the local npm client, so it resolves ranges the same way
# `npm install` does.
# --------------------------------------------------------------------------
SEMVER_OK=0
SEMVER_NODE_PATH=""
if command -v node >/dev/null 2>&1; then
    cat >"$work/semver_max.js" <<'JS'
const semver = require('semver');
const range = process.argv[2];
let buf = '';
process.stdin.on('data', c => (buf += c));
process.stdin.on('end', () => {
    let versions;
    try { versions = JSON.parse(buf); } catch (e) { process.stdout.write('INVALID'); return; }
    if (semver.validRange(range) === null) { process.stdout.write('INVALID'); return; }
    const m = semver.maxSatisfying(versions, range);
    process.stdout.write(m ? String(m) : '');
});
JS
    # Locate a require()-able semver: try the caller's NODE_PATH first, then the
    # module bundled with the globally installed npm client.
    for candidate in "" "$(npm root -g 2>/dev/null)/npm/node_modules"; do
        if NODE_PATH="$candidate" node -e "require('semver')" >/dev/null 2>&1; then
            SEMVER_NODE_PATH="$candidate"
            SEMVER_OK=1
            break
        fi
    done
fi
if [ "$SEMVER_OK" -ne 1 ]; then
    verify_info "node/semver not available; range pins cannot be resolved and will be reported unverified"
fi

# resolve_range <range>  (published versions JSON on stdin) -> prints result
resolve_range() {
    NODE_PATH="$SEMVER_NODE_PATH" node "$work/semver_max.js" "$1"
}

printf '%s\n' "$files" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#$ROOT/}"
    jq -r '((.dependencies // {}) + (.devDependencies // {})) | to_entries[] | "\(.key)\t\(.value)"' "$f" 2>/dev/null \
    | while IFS=$'\t' read -r name spec; do
        [ -n "$name" ] || continue
        enc="$(printf '%s' "$name" | sed 's#/#%2f#')"

        if printf '%s' "$spec" | grep -qE '^=?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
            # ---- EXACT pin: confirm the exact published version verbatim. ----
            ver="${spec#=}"
            url="https://registry.npmjs.org/$enc/$ver"
            body="$work/npm.json"
            rm -f "$body"
            if verify_retry -- curl -fsSL -o "$body" "$url"; then
                got="$(jq -r '.version // empty' "$body" 2>/dev/null)"
                if [ "$got" = "$ver" ]; then
                    verify_pass "resolved on the npm registry as an exact version" "$name@$ver" "$rel"
                else
                    verify_unresolved "$rel" "$name@$ver" "npm registry publishes this as '$got'; pin is not the exact version string"
                fi
            elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
                verify_unverified "$rel" "$name@$spec" "npm registry (unreachable after retries)"
            else
                verify_unresolved "$rel" "$name@$ver" "npm registry ($url) - no such version"
            fi
            rm -f "$body"

        elif printf '%s' "$spec" | grep -qiE '://|^git[+@]|^git:|^github:|^bitbucket:|^gitlab:|^file:|^link:|^workspace:|^npm:|^portal:'; then
            # ---- Not a registry version pin (git/url/file/link/workspace). ----
            verify_unresolved "$rel" "$name@$spec" "npm registry - not a registry version pin (git/url/file/link spec)"

        else
            # ---- RANGE pin: resolve against the published versions. ----
            if [ "$SEMVER_OK" -ne 1 ]; then
                verify_unverified "$rel" "$name@$spec" "npm registry - range not evaluated (node/semver unavailable)"
                continue
            fi
            doc="$work/npm-doc.json"
            rm -f "$doc"
            url="https://registry.npmjs.org/$enc"
            if verify_retry -- curl -fsSL -o "$doc" "$url"; then
                versions_json="$(jq -c '(.versions // {}) | keys' "$doc" 2>/dev/null)"
                if [ -z "$versions_json" ] || [ "$versions_json" = "null" ]; then
                    verify_unresolved "$rel" "$name@$spec" "npm registry ($url) - package publishes no versions"
                else
                    resolved="$(printf '%s' "$versions_json" | resolve_range "$spec")"
                    if [ "$resolved" = "INVALID" ]; then
                        verify_unresolved "$rel" "$name@$spec" "npm registry - not a valid semver range"
                    elif [ -n "$resolved" ]; then
                        verify_pass "range resolves on the npm registry to published version $resolved" "$name@$spec" "$rel"
                    else
                        verify_unresolved "$rel" "$name@$spec" "npm registry ($url) - no published version satisfies this range"
                    fi
                fi
            elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
                verify_unverified "$rel" "$name@$spec" "npm registry (unreachable after retries)"
            else
                verify_unresolved "$rel" "$name@$spec" "npm registry ($url) - no such package"
            fi
            rm -f "$doc"
        fi
    done
done
exit 0
