#!/usr/bin/env bash
# verify:number: 13
# verify:name: sample application image builds and /ping smoke test
# verify:requires-aws: false
# verify:implements: 2.6
#
# Check 13 (Requirement 7 criteria 10-13): build every Sample_Applications
# container image and smoke-test it.
#
#   7.10  A build reports exit status 0 within 600 seconds       -> verify_pass
#   7.12  A pinned dependency does not resolve during a build:
#         report the package name and requested version, and
#         publish/tag no image                                   -> verify_unresolved
#   7.11  A started container returns HTTP 200 from /ping on its
#         exposed port within 60 seconds (10s per request)       -> verify_pass
#   7.13  No HTTP 200 from /ping within 60 seconds: report the
#         application and the observed status or timeout         -> verify_fail
#
# This check drives a local container engine (docker/podman/nerdctl/finch),
# which is heavy and network-bound. If no engine is available - or the engine
# is installed but its daemon is not responding - the check degrades
# gracefully: it emits a non-scoring INFO note and exits 0 rather than
# crashing or hanging. Container images and containers it creates are labelled
# with a per-run label and removed on exit.
#
# Test / environment seams (all optional):
#   VERIFY_CONTAINER_ENGINE   force a specific engine binary, or "none" to
#                             force the graceful-degradation path.
#   VERIFY_APP_BUILD_TIMEOUT  per-build allowance in seconds (default 600).
#   VERIFY_APP_SMOKE_WINDOW   smoke window in seconds (default 60).
#   VERIFY_APP_REQ_TIMEOUT    per-request timeout in seconds (default 10).
#   VERIFY_APP_HEALTH_PATH    health path to probe (default /ping).

source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

BUILD_TIMEOUT="${VERIFY_APP_BUILD_TIMEOUT:-600}"
SMOKE_WINDOW="${VERIFY_APP_SMOKE_WINDOW:-60}"
REQ_TIMEOUT="${VERIFY_APP_REQ_TIMEOUT:-10}"
HEALTH_PATH="${VERIFY_APP_HEALTH_PATH:-/ping}"

APPS_ROOT="${VERIFY_REPO_ROOT}/repos/apps"
RUN_LABEL_KEY="cvu-verify-check13"
RUN_LABEL_VAL="$$"
RUN_LABEL="${RUN_LABEL_KEY}=${RUN_LABEL_VAL}"

# rel <path> : path relative to the repo root, for reporting.
rel() { printf '%s' "${1#"${VERIFY_REPO_ROOT}"/}"; }

# ---------------------------------------------------------------------------
# 1. Select a container engine, or degrade gracefully.
# ---------------------------------------------------------------------------
ENGINE=""
case "${VERIFY_CONTAINER_ENGINE:-}" in
    none|NONE|off)
        verify_info "container engine forced off (VERIFY_CONTAINER_ENGINE=none); skipping application build and smoke checks"
        exit 0
        ;;
    "")
        for e in docker podman nerdctl finch; do
            if command -v "$e" >/dev/null 2>&1; then ENGINE="$e"; break; fi
        done
        ;;
    *)
        if command -v "${VERIFY_CONTAINER_ENGINE}" >/dev/null 2>&1; then
            ENGINE="${VERIFY_CONTAINER_ENGINE}"
        fi
        ;;
esac

if [ -z "$ENGINE" ]; then
    verify_info "no container engine (docker/podman/nerdctl/finch) on PATH; skipping application build and smoke checks"
    exit 0
fi

# Engine binary present but daemon/VM not responding -> degrade, do not hang.
if ! run_with_timeout 25 "$ENGINE" info >/dev/null 2>&1; then
    verify_info "container engine '${ENGINE}' is present but not responding (daemon/VM unavailable); skipping application build and smoke checks"
    exit 0
fi

# HTTP client for the smoke request.
HTTP_CLIENT=""
if command -v curl >/dev/null 2>&1; then
    HTTP_CLIENT="curl"
elif command -v wget >/dev/null 2>&1; then
    HTTP_CLIENT="wget"
fi

verify_info "using container engine '${ENGINE}' (per-build ${BUILD_TIMEOUT}s, smoke window ${SMOKE_WINDOW}s, per-request ${REQ_TIMEOUT}s)"

# ---------------------------------------------------------------------------
# Cleanup: remove every container/image this run labelled, on any exit.
# ---------------------------------------------------------------------------
cleanup() {
    local ids
    ids="$("$ENGINE" ps -aq --filter "label=${RUN_LABEL}" 2>/dev/null)"
    if [ -n "$ids" ]; then
        # shellcheck disable=SC2086
        "$ENGINE" rm -f $ids >/dev/null 2>&1 || true
    fi
    ids="$("$ENGINE" images -q --filter "label=${RUN_LABEL}" 2>/dev/null)"
    if [ -n "$ids" ]; then
        # shellcheck disable=SC2086
        "$ENGINE" rmi -f $ids >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 2. Discover build files.
# ---------------------------------------------------------------------------
if [ ! -d "$APPS_ROOT" ]; then
    verify_fail "$(rel "$APPS_ROOT")" "repos/apps" "sample applications directory not found"
    exit 0
fi

DOCKERFILES=""
while IFS= read -r df; do
    [ -n "$df" ] && DOCKERFILES="${DOCKERFILES}${df}"$'\n'
done < <(find "$APPS_ROOT" -type f -name Dockerfile 2>/dev/null | LC_ALL=C sort)

if [ -z "$DOCKERFILES" ]; then
    verify_fail "$(rel "$APPS_ROOT")" "repos/apps" "no Dockerfile found under the sample applications tree"
    exit 0
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/cvu-check13.XXXXXX")"
trap 'cleanup; rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# app_label <dockerfile> : short human label like product-catalog-api/v1.
app_label() {
    local ctx; ctx="$(dirname "$1")"
    printf '%s' "${ctx#"${APPS_ROOT}"/}"
}

# exposed_port <dockerfile> : first EXPOSE port, or empty.
exposed_port() {
    grep -iE '^[[:space:]]*EXPOSE[[:space:]]+' "$1" 2>/dev/null \
        | head -n1 | awk '{print $2}' | sed 's#/.*##'
}

# dep_registry <context-dir> : which registry the build's deps come from.
dep_registry() {
    if [ -f "$1/requirements.txt" ]; then printf 'PyPI'
    elif [ -f "$1/package.json" ]; then printf 'npm registry'
    else printf 'package registry'; fi
}

# dep_manifest <context-dir> : the dependency manifest file (for reporting).
dep_manifest() {
    if [ -f "$1/requirements.txt" ]; then printf '%s' "$1/requirements.txt"
    elif [ -f "$1/package.json" ]; then printf '%s' "$1/package.json"
    else printf '%s' "$1"; fi
}

# unresolved_token <build-log> : print the failing "name<sep>version" spec if
# the build failed because a pinned dependency did not resolve, else nothing.
unresolved_token() {
    local log="$1" tok=""
    # pip: "No matching distribution found for <spec>"
    tok="$(sed -n 's/.*No matching distribution found for \([^ ]*\).*/\1/p' "$log" 2>/dev/null | head -n1)"
    # pip: "Could not find a version that satisfies the requirement <spec> (...)"
    if [ -z "$tok" ]; then
        tok="$(sed -n 's/.*satisfies the requirement \([^ ]*\).*/\1/p' "$log" 2>/dev/null | head -n1)"
    fi
    # npm: "No matching version found for <spec>"
    if [ -z "$tok" ]; then
        tok="$(sed -n 's/.*No matching version found for \([^ ]*\).*/\1/p' "$log" 2>/dev/null | head -n1)"
    fi
    # strip a trailing period npm sometimes appends
    tok="${tok%.}"
    printf '%s' "$tok"
}

# split_spec <token> : echo "<name>|<version>" from requests==v2.33.0 or
# express@^4.22.3 or @scope/pkg@^1.0.0.
split_spec() {
    local t="$1" name ver
    case "$t" in
        *==*) name="${t%%==*}"; ver="${t#*==}" ;;
        @*)   local rest="${t#@}"; name="@${rest%@*}"; ver="${rest##*@}" ;;
        *@*)  name="${t%@*}"; ver="${t##*@}" ;;
        *)    name="$t"; ver="" ;;
    esac
    printf '%s|%s' "$name" "$ver"
}

# http_status <url> : print the HTTP status code, honouring REQ_TIMEOUT.
http_status() {
    local url="$1"
    if [ "$HTTP_CLIENT" = "curl" ]; then
        run_with_timeout "$REQ_TIMEOUT" curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null
    else
        # wget: derive the status from the server response header.
        run_with_timeout "$REQ_TIMEOUT" wget -q -S -O /dev/null "$url" 2>&1 \
            | sed -n 's#^[[:space:]]*HTTP/[0-9.]* \([0-9][0-9][0-9]\).*#\1#p' | tail -n1
    fi
}

# build_and_smoke_one : build the current app (globals dockerfile/context/app/
# relfile/img/cname/buildlog) and, on success, smoke-test /ping. Reports via
# the verify_* helpers and returns; the caller removes the container/image.
build_and_smoke_one() {
    # --- build (Requirement 7.10) -----------------------------------------
    run_with_timeout "$BUILD_TIMEOUT" \
        "$ENGINE" build --label "$RUN_LABEL" -t "$img" -f "$dockerfile" "$context" \
        >"$buildlog" 2>&1
    local brc=$?

    if [ "$brc" -eq 124 ]; then
        verify_fail "$relfile" "$app" \
            "image build did not complete within the ${BUILD_TIMEOUT}s per-build allowance"
        return
    fi

    if [ "$brc" -ne 0 ]; then
        # Distinguish an unresolved dependency (7.12) from any other build
        # failure. On an unresolved pin, report the package and requested
        # version; no image was published or tagged.
        local token pair pkg reqver log_tail
        token="$(unresolved_token "$buildlog")"
        if [ -n "$token" ]; then
            pair="$(split_spec "$token")"
            pkg="${pair%%|*}"; reqver="${pair##*|}"
            [ -n "$reqver" ] || reqver="(unspecified)"
            verify_unresolved "$(rel "$(dep_manifest "$context")")" \
                "package '${pkg}' requested version '${reqver}' (no image published)" \
                "$(dep_registry "$context")"
        else
            log_tail="$(tail -n 5 "$buildlog" 2>/dev/null | tr '\n' ' ')"
            verify_fail "$relfile" "$app" \
                "image build failed (exit ${brc}): ${log_tail}"
        fi
        return
    fi

    # --- smoke (Requirement 7.11 / 7.13) ----------------------------------
    if [ -z "$HTTP_CLIENT" ]; then
        verify_info "build succeeded for ${app}, but no HTTP client (curl/wget) is available; smoke test skipped"
        return
    fi

    local cport hostmap hostport url deadline got200 observed code
    cport="$(exposed_port "$dockerfile")"
    [ -n "$cport" ] || cport=8080

    if ! run_with_timeout 40 \
        "$ENGINE" run -d --label "$RUN_LABEL" --name "$cname" \
        -p 127.0.0.1::"$cport" "$img" >/dev/null 2>&1; then
        verify_fail "$relfile" "$app" \
            "container failed to start from the built image on exposed port ${cport}"
        return
    fi

    # Resolve the published host port for the container's exposed port.
    hostmap="$("$ENGINE" port "$cname" "${cport}/tcp" 2>/dev/null | head -n1)"
    hostport="${hostmap##*:}"
    if [ -z "$hostport" ] || [ "$hostport" = "$hostmap" ]; then
        verify_fail "$relfile" "$app" \
            "could not determine the published host port for container port ${cport}"
        return
    fi

    url="http://127.0.0.1:${hostport}${HEALTH_PATH}"
    deadline=$(( $(date +%s) + SMOKE_WINDOW ))
    got200=0
    observed="no response"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        code="$(http_status "$url")"
        if [ "$code" = "200" ]; then
            got200=1
            break
        fi
        if [ -n "$code" ] && [ "$code" != "000" ]; then
            observed="HTTP ${code}"
        fi
        sleep 2
    done

    if [ "$got200" -eq 1 ]; then
        verify_pass "HTTP 200 from ${HEALTH_PATH} within ${SMOKE_WINDOW}s" "$app" "$relfile"
    else
        verify_fail "$relfile" "$app" \
            "no HTTP 200 from ${HEALTH_PATH} on port ${cport} within ${SMOKE_WINDOW}s (last observed: ${observed})"
    fi
}

# ---------------------------------------------------------------------------
# 3. Build + smoke each application.
# ---------------------------------------------------------------------------
idx=0
while IFS= read -r dockerfile; do
    [ -n "$dockerfile" ] || continue
    idx=$((idx + 1))

    context="$(dirname "$dockerfile")"
    app="$(app_label "$dockerfile")"
    relfile="$(rel "$dockerfile")"
    img="localhost/cvu-verify-check13:${RUN_LABEL_VAL}-${idx}"
    cname="cvu-verify-check13-${RUN_LABEL_VAL}-${idx}"
    buildlog="${WORKDIR}/build.${idx}.log"

    build_and_smoke_one
    # Best-effort per-app removal; the EXIT trap is the label-scoped safety net.
    "$ENGINE" rm -f "$cname" >/dev/null 2>&1 || true
    "$ENGINE" rmi -f "$img" >/dev/null 2>&1 || true
done <<EOF
$DOCKERFILES
EOF

exit 0
