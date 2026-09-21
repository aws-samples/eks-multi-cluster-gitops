#!/usr/bin/env bash
# verify:number: 3
# verify:name: pinned Helm chart versions present in their HelmRepository index
# verify:requires-aws: false
# verify:implements: 2.3
#
# Check 3 (task 2.3; Requirement 10.3; Properties 12, 13).
#
# For every HelmRelease under repos/, confirm the pinned chart version exists in
# the live index of the HelmRepository its sourceRef names, as an EXACT string:
#   - HTTP HelmRepository: fetch <url>/index.yaml and match
#     .entries[<chart>][].version exactly.
#   - OCI  HelmRepository: resolve <host>/<chart>:<version> with `crane manifest`
#     (or, absent crane, `helm show chart`).
# Every registry/index call goes through verify_retry, so an unreachable index
# becomes UNVERIFIED rather than a false UNRESOLVED. A range/wildcard pin (never
# an exact resolution) is reported UNRESOLVED.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

ROOT="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set - run via verify/run.sh}"
REPOS="$ROOT/repos"

if ! command -v yq >/dev/null 2>&1; then
    verify_info "yq not available; cannot parse HelmRelease/HelmRepository manifests - Helm chart resolution skipped"
    exit 0
fi
if ! command -v curl >/dev/null 2>&1; then
    verify_info "curl not available; Helm index resolution skipped"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
repomap="$work/repomap"          # name<TAB>type<TAB>url
: > "$repomap"

# Build the HelmRepository map. A real HelmRepository document carries
# `kind: HelmRepository` at column 0; the copies embedded in the
# gotk-components CRDs are indented and are skipped by the anchored match.
while IFS= read -r rf; do
    [ -n "$rf" ] || continue
    while IFS=$'\t' read -r name typ url; do
        [ -n "$name" ] || continue
        printf '%s\t%s\t%s\n' "$name" "$typ" "$url" >> "$repomap"
    done < <(yq eval-all \
        'select(.kind == "HelmRepository") | [.metadata.name, (.spec.type // "default"), .spec.url] | @tsv' \
        "$rf" 2>/dev/null)
done < <(grep -rlE '^kind: HelmRepository' --include='*.yaml' "$REPOS" 2>/dev/null)

lookup_repo() {  # <name>  -> prints "type<TAB>url" (first match) or nothing
    grep -m1 -E "^$(printf '%s' "$1" | sed 's/[].[*^$\/]/\\&/g')"$'\t' "$repomap" 2>/dev/null | cut -f2-
}

# A chart version is exact when it is not a range or wildcard.
is_range() {
    case "$1" in
        ""|*"*"*|*"^"*|*"~"*|*" "*|*x*|*X*|">"*|"<"*|"="*|*"||"*) return 0 ;;
        *) return 1 ;;
    esac
}

found_any=0
while IFS= read -r hr; do
    [ -n "$hr" ] || continue
    while IFS=$'\t' read -r chart ver srcname _srcns; do
        [ -n "$chart" ] || continue
        found_any=1
        rel="${hr#$ROOT/}"
        res="$chart@$ver (HelmRepository/$srcname)"

        if is_range "$ver"; then
            verify_unresolved "$rel" "$res" "pinned version is a range/wildcard, not an exact string"
            continue
        fi

        ti="$(lookup_repo "$srcname")"
        if [ -z "$ti" ]; then
            verify_fail "$rel" "$res" "sourceRef HelmRepository '$srcname' not found under repos/"
            continue
        fi
        typ="${ti%%$'\t'*}"
        url="${ti#*$'\t'}"
        url="${url%/}"

        case "$typ" in
        oci)
            host="${url#oci://}"
            oref="$host/$chart:$ver"
            if command -v crane >/dev/null 2>&1; then
                if verify_retry -- crane manifest "$oref" >/dev/null 2>&1; then
                    verify_pass "chart tag resolved in OCI registry" "$res" "$rel"
                elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
                    verify_unverified "$rel" "$res" "$url (OCI registry unreachable after retries)"
                else
                    verify_unresolved "$rel" "$res" "$url (no such chart tag $chart:$ver)"
                fi
            elif command -v helm >/dev/null 2>&1; then
                if verify_retry -- helm show chart "$url/$chart" --version "$ver" >/dev/null 2>&1; then
                    verify_pass "chart version resolved in OCI registry (via helm)" "$res" "$rel"
                elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
                    verify_unverified "$rel" "$res" "$url (OCI registry unreachable after retries)"
                else
                    verify_unresolved "$rel" "$res" "$url (no such chart version $chart:$ver)"
                fi
            else
                verify_info "neither crane nor helm available; OCI chart not resolved: $res in $rel ($url)"
            fi
            ;;
        *)
            idx="$work/index.yaml"
            rm -f "$idx"
            if verify_retry -- curl -fsSL -o "$idx" "$url/index.yaml" 2>/dev/null; then
                if yq eval '.entries["'"$chart"'"][].version' "$idx" 2>/dev/null | grep -Fxq -- "$ver"; then
                    verify_pass "chart version present in HelmRepository index" "$res" "$rel"
                else
                    verify_unresolved "$rel" "$res" "$url/index.yaml (version $ver not listed for chart '$chart')"
                fi
            elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
                # Every attempt timed out: the index host could not be reached.
                verify_unverified "$rel" "$res" "$url/index.yaml (index unreachable after retries)"
            else
                # The host responded definitively (e.g. HTTP 404): the index is
                # not available at the configured URL, so the pin cannot resolve.
                verify_unresolved "$rel" "$res" "$url/index.yaml (index not available at configured URL)"
            fi
            rm -f "$idx"
            ;;
        esac
    done < <(yq eval-all \
        'select(.kind == "HelmRelease") | .spec.chart.spec | [.chart, .version, .sourceRef.name, (.sourceRef.namespace // "")] | @tsv' \
        "$hr" 2>/dev/null)
done < <(grep -rlE '^kind: HelmRelease' --include='*.yaml' "$REPOS" 2>/dev/null)

if [ "$found_any" -eq 0 ]; then
    verify_info "no HelmRelease manifests found under repos/"
fi
exit 0
