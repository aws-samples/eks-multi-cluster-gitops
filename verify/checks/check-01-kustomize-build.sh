#!/usr/bin/env bash
# verify:number: 1
# verify:name: kustomize build over every kustomization under repos/
# verify:requires-aws: false
# verify:implements: 2.2
#
# Check 1 (design Testing Strategy, Property 7): run `kustomize build` over
# every Kustomize base and overlay directory under repos/. A directory is a
# build root when it holds a kustomization.yaml / kustomization.yml /
# Kustomization file. Each build failure is reported with the file path, the
# resource (the build target), and the observed kustomize error via
# verify_fail. Requirements 10.1, 10.15.
#
# Degrades cleanly: if kustomize is not installed in this environment the
# module reports the situation with verify_info (non-scoring) and exits 0
# rather than crashing or emitting false failures.

source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

repo_root="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set}"
repos_dir="$repo_root/repos"

if [ ! -d "$repos_dir" ]; then
    verify_info "no repos/ directory at $repo_root; nothing to build"
    exit 0
fi

if ! command -v kustomize >/dev/null 2>&1; then
    verify_info "kustomize is not installed in this environment; kustomize build (check 1) skipped. Install kustomize to run this check."
    exit 0
fi

# Per-build wall-clock cap so a pathological build cannot consume the whole
# credential-free budget on its own. The harness still bounds the module as a
# whole.
BUILD_TIMEOUT="${VERIFY_KUSTOMIZE_TIMEOUT:-120}"

# ---------------------------------------------------------------------------
# Expected-condition rule 1(a): intentional empty aggregation placeholders.
#
# `repos/gitops-system/clusters-config/kustomization.yaml` and
# `repos/gitops-workloads/template/kustomization.yaml` declare `resources:`
# with a null/empty list on purpose. They are AGGREGATION points that are
# populated at bootstrap / onboarding time - the `bin/*.sh` scripts append a
# resource entry when a workload cluster is created or a workload is onboarded.
# Until then they are legitimately empty, and `kustomize build` rejects an
# empty kustomization with "kustomization.yaml is empty".
#
# Treat a kustomization as an intentional placeholder ONLY when it has a
# `resources:` key that is present-but-empty/null AND carries no other
# output-producing field (no bases, components, generators, patches,
# patchesStrategicMerge, patchesJson6902, resources entries, configMapGenerator,
# secretGenerator). Such a file emits nothing by design, so it is reported
# non-failing (verify_info) with an explanation rather than FAIL.
#
# This is deliberately narrow: a kustomization that references resources (or
# any other producing field) does NOT qualify, so a genuinely broken build
# still fails. Uses yq for a precise structural read when available and falls
# back to a conservative line scan otherwise.
is_empty_aggregation_placeholder() {
    local f="$1"
    # Output-producing fields other than `resources` that would make the file
    # more than a bare placeholder.
    local producing_fields="bases components generators patches patchesStrategicMerge patchesJson6902 configMapGenerator secretGenerator"

    if command -v yq >/dev/null 2>&1; then
        # `resources:` must be present...
        [ "$(yq e 'has("resources")' "$f" 2>/dev/null)" = "true" ] || return 1
        # ...and empty or null.
        [ "$(yq e '(.resources // []) | length' "$f" 2>/dev/null)" = "0" ] || return 1
        # No other producing field may carry content.
        local field len
        for field in $producing_fields; do
            len="$(yq e "(.${field} // []) | length" "$f" 2>/dev/null)"
            [ "${len:-0}" = "0" ] || return 1
        done
        return 0
    fi

    # Fallback (no yq): a bare placeholder has a `resources:` line with no
    # following list item, and none of the other producing fields present.
    grep -qE '^[[:space:]]*resources:[[:space:]]*$' "$f" || return 1
    # A YAML list entry under any key would appear as a line starting with '-'.
    grep -qE '^[[:space:]]*-[[:space:]]' "$f" && return 1
    local field
    for field in $producing_fields; do
        grep -qE "^[[:space:]]*${field}:" "$f" && return 1
    done
    return 0
}

# ---------------------------------------------------------------------------
# Expected-condition rule 1(b): the product-catalog-api v2-staging overlay
# layers onto the v1 base of a single-version repo.
#
# `product-catalog-api-manifests` is a SINGLE-VERSION repo. It initially holds
# the v1 content (including `v1/kubernetes/base`). Later the v2-staging content
# overwrites the repo while the v1 `base/` stays in place, so the v2-staging
# overlay's `resources: [../../base]` resolves against the base already present
# in the deployed repo. In this sample layout the two live side by side (v1 and
# v2-staging), so `../../base` has no sibling `base/` next to the overlay and a
# naive standalone `kustomize build` fails with "no such file or directory".
#
# We validate it GENUINELY by materializing the overlay over the v1 base in a
# throwaway tree (mirroring the deployed single-version layout) and building
# that. This is targeted strictly by path, so any OTHER overlay with a
# genuinely-missing base still FAILs normally.
#
# Path is relative to repo root; matched exactly.
V2_STAGING_OVERLAY_REL="repos/apps-manifests/product-catalog-api-manifests/v2-staging/kubernetes/overlays/staging"
V1_BASE_REL="repos/apps-manifests/product-catalog-api-manifests/v1/kubernetes/base"

# build_v2_staging_over_v1_base <overlay-abs-dir> <rel-for-reporting>
# Returns 0 and reports verify_pass on a clean build; returns 1 and reports
# verify_fail otherwise. Falls back to a non-failing verify_info only when the
# v1 base needed for the substitution is itself absent (nothing to validate
# against), documenting why.
build_v2_staging_over_v1_base() {
    local overlay_dir="$1" rel="$2"
    local base_src="$repo_root/$V1_BASE_REL"
    if [ ! -d "$base_src" ]; then
        verify_info "expected-condition: $rel layers onto the shared v1 base of the single-version product-catalog-api-manifests repo; v1 base ($V1_BASE_REL) not present in this tree, so the standalone build is reported non-failing (it resolves ../../base against the base carried in the deployed repo)."
        return 0
    fi
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/kubernetes/base" "$tmp/kubernetes/overlays/staging"
    cp "$base_src"/* "$tmp/kubernetes/base"/ 2>/dev/null
    cp "$overlay_dir"/* "$tmp/kubernetes/overlays/staging"/ 2>/dev/null
    local out rc
    out="$(run_with_timeout "$BUILD_TIMEOUT" kustomize build "$tmp/kubernetes/overlays/staging" 2>&1)"
    rc=$?
    rm -rf "$tmp"
    if [ "$rc" -eq 0 ]; then
        verify_pass "kustomize build succeeded (v2-staging overlay validated over the shared v1 base)" "kustomize build" "$rel"
        return 0
    elif [ "$rc" -eq 124 ]; then
        verify_fail "$rel/kustomization.yaml" "kustomize build" \
            "build (over substituted v1 base) did not complete within ${BUILD_TIMEOUT}s"
        return 1
    else
        verify_fail "$rel/kustomization.yaml" "kustomize build" \
            "$(printf '%s' "$out" | tr -s ' ')"
        return 1
    fi
}

# Enumerate every directory that carries a kustomization file. Sort for stable,
# reproducible reporting order. NUL-delimited to tolerate unusual paths.
build_dirs=()
while IFS= read -r -d '' f; do
    build_dirs+=("$(dirname "$f")")
done < <(
    find "$repos_dir" -type f \
        \( -name 'kustomization.yaml' -o -name 'kustomization.yml' -o -name 'Kustomization' \) \
        -print0 | sort -z
)

if [ "${#build_dirs[@]}" -eq 0 ]; then
    verify_info "no kustomization.yaml found under repos/; nothing to build"
    exit 0
fi

built=0
placeholders=0
for dir in "${build_dirs[@]}"; do
    rel="${dir#"$repo_root"/}"

    # Rule 1(b): the v2-staging overlay is validated over the shared v1 base.
    if [ "$rel" = "$V2_STAGING_OVERLAY_REL" ]; then
        if build_v2_staging_over_v1_base "$dir" "$rel"; then
            built=$((built + 1))
        fi
        continue
    fi

    # Determine the kustomization file for this build root (for the
    # placeholder structural read and for failure reporting).
    kfile="$dir/kustomization.yaml"
    [ -f "$kfile" ] || kfile="$dir/kustomization.yml"
    [ -f "$kfile" ] || kfile="$dir/Kustomization"

    # Rule 1(a): intentional empty aggregation placeholder -> non-failing.
    if [ -f "$kfile" ] && is_empty_aggregation_placeholder "$kfile"; then
        verify_info "expected-condition: ${kfile#"$repo_root"/} is an intentional empty aggregation placeholder (resources: is present but empty and no other output-producing field is set); it is populated at bootstrap/onboarding time by the bin/*.sh scripts. kustomize build's \"kustomization.yaml is empty\" here is by design, so it is reported non-failing."
        placeholders=$((placeholders + 1))
        continue
    fi

    out="$(run_with_timeout "$BUILD_TIMEOUT" kustomize build "$dir" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        verify_pass "kustomize build succeeded" "kustomize build" "$rel"
        built=$((built + 1))
    elif [ "$rc" -eq 124 ]; then
        verify_fail "$rel/kustomization.yaml" "kustomize build" \
            "build did not complete within ${BUILD_TIMEOUT}s"
    else
        verify_fail "$rel/kustomization.yaml" "kustomize build" \
            "$(printf '%s' "$out" | tr -s ' ')"
    fi
done

verify_info "kustomize build ran over ${#build_dirs[@]} kustomization director(ies); ${built} built cleanly; ${placeholders} intentional empty aggregation placeholder(s) reported non-failing"
exit 0
