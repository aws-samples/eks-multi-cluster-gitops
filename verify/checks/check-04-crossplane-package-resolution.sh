#!/usr/bin/env bash
# verify:number: 4
# verify:name: Crossplane package references resolve via crane manifest
# verify:requires-aws: false
# verify:implements: 2.3
#
# Check 4 (task 2.3; Requirement 10.4; Property 12).
#
# For every Crossplane package reference (a Provider/Configuration `.spec.package`)
# under repos/ and initial-setup/, confirm the reference including its tag (or
# digest) resolves via `crane manifest`. The call goes through verify_retry, so
# an unreachable registry becomes UNVERIFIED rather than a false UNRESOLVED. A
# reference without a tag/digest, or with a range/wildcard tag, is UNRESOLVED
# (not an exact, immutable reference). If crane is unavailable the references are
# reported via verify_info and the module degrades gracefully.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

ROOT="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set - run via verify/run.sh}"

if ! command -v yq >/dev/null 2>&1; then
    verify_info "yq not available; cannot parse Crossplane package references - resolution skipped"
    exit 0
fi

have_crane=0
command -v crane >/dev/null 2>&1 && have_crane=1

# A tag is exact when the last path segment carries a ':' tag or the reference
# carries an '@sha256:' digest, and the tag is not a range/wildcard.
ref_is_exact() {
    local ref="$1" last tag
    case "$ref" in *"@sha256:"*) return 0 ;; esac
    last="${ref##*/}"
    case "$last" in
        *:*) tag="${last##*:}" ;;
        *)   return 1 ;;   # no tag at all
    esac
    case "$tag" in
        ""|"latest"|*"*"*|*"^"*|*"~"*|*x*|*X*) return 1 ;;
        *) return 0 ;;
    esac
}

registry_of() { printf '%s' "${1%%/*}"; }   # host portion of an OCI reference

found_any=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS=$'\t' read -r kind name pkg; do
        [ -n "$pkg" ] || continue
        found_any=1
        rel="${f#$ROOT/}"
        res="${kind}/${name} package=$pkg"

        if ! ref_is_exact "$pkg"; then
            verify_unresolved "$rel" "$res" "package reference lacks an exact immutable tag/digest"
            continue
        fi

        reg="$(registry_of "$pkg")"
        if [ "$have_crane" -eq 0 ]; then
            verify_info "crane unavailable; package not resolved: $pkg ($rel, registry $reg)"
            continue
        fi

        if verify_retry -- crane manifest "$pkg" >/dev/null 2>&1; then
            verify_pass "package reference resolved via crane" "$res" "$rel"
        elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
            verify_unverified "$rel" "$res" "$reg (registry unreachable after retries)"
        else
            verify_unresolved "$rel" "$res" "$reg (crane manifest: no such package/tag)"
        fi
    done < <(yq eval-all \
        'select(.spec.package != null) | [.kind, (.metadata.name // "?"), .spec.package] | @tsv' \
        "$f" 2>/dev/null)
done < <(
    for d in "$ROOT/repos" "$ROOT/initial-setup"; do
        [ -d "$d" ] || continue
        grep -rlE '[[:space:]]package:[[:space:]]' --include='*.yaml' "$d" 2>/dev/null
    done | sort -u
)

if [ "$found_any" -eq 0 ]; then
    verify_info "no Crossplane package references (.spec.package) found under repos/ or initial-setup/"
fi
exit 0
