#!/usr/bin/env bash
# verify:number: 6
# verify:name: Python distribution pins resolve on the PyPI JSON API
# verify:requires-aws: false
# verify:implements: 2.3
#
# Check 6 (task 2.3; Requirement 10.6; Property 12).
#
# For every pin in a requirements.txt under repos/ or initial-setup/, confirm it
# resolves on the PyPI JSON API as an EXACT version. Only an exact `==` pin is a
# resolution: any other specifier (>=, ~=, <, >, !=, a wildcard, or an unpinned
# name) is a range/wildcard and is reported UNRESOLVED.
#
# Property 12 requires an exact-STRING match. The PyPI JSON endpoint is lenient
# - it normalizes a non-canonical identifier such as a stray `v` prefix
# (`v2.33.0` -> `2.33.0`) and answers 200 - so a 200 alone is not proof the pin
# string is exact. The pin is confirmed only when the published `info.version`
# equals the pinned string verbatim. The fetch runs through verify_retry, so an
# unreachable API becomes UNVERIFIED rather than a false UNRESOLVED; a 404 or a
# normalized mismatch is UNRESOLVED.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

ROOT="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set - run via verify/run.sh}"

if ! command -v curl >/dev/null 2>&1; then
    verify_info "curl not available; PyPI resolution skipped"
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    verify_info "jq not available; cannot confirm exact PyPI version strings - resolution skipped"
    exit 0
fi

files="$(
    for d in "$ROOT/repos" "$ROOT/initial-setup"; do
        [ -d "$d" ] || continue
        find "$d" -type f -name 'requirements.txt' 2>/dev/null
    done | sort -u
)"

if [ -z "$files" ]; then
    verify_info "no requirements.txt files found under repos/ or initial-setup/"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf '%s\n' "$files" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#$ROOT/}"
    while IFS= read -r raw || [ -n "$raw" ]; do
        line="${raw%%#*}"          # strip inline comment
        line="${line%%;*}"         # strip environment marker
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "$line" ] || continue
        case "$line" in
            -*) continue ;;        # -r/-e/--hash and other option lines
        esac

        if printf '%s' "$line" | grep -qE '^[A-Za-z0-9._-]+(\[[^]]*\])?==[^,<>=!~ *]+$'; then
            name="$(printf '%s' "$line" | sed -E 's/(\[[^]]*\])?==.*$//')"
            ver="$(printf '%s' "$line" | sed -E 's/^[^=]*==//')"
            url="https://pypi.org/pypi/$name/$ver/json"
            body="$work/pypi.json"
            rm -f "$body"
            if verify_retry -- curl -fsSL -o "$body" "$url"; then
                got="$(jq -r '.info.version // empty' "$body" 2>/dev/null)"
                if [ "$got" = "$ver" ]; then
                    verify_pass "resolved on PyPI as an exact version" "$name==$ver" "$rel"
                else
                    verify_unresolved "$rel" "$name==$ver" "PyPI publishes this as '$got'; pin is not the exact version string"
                fi
            elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
                verify_unverified "$rel" "$name==$ver" "PyPI JSON API (unreachable after retries)"
            else
                verify_unresolved "$rel" "$name==$ver" "PyPI JSON API ($url) - no such version"
            fi
            rm -f "$body"
        else
            verify_unresolved "$rel" "$line" "PyPI - not an exact '==' pin (range/wildcard/unpinned)"
        fi
    done < "$f"
done
exit 0
