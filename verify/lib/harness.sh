#!/usr/bin/env bash
# verify/lib/harness.sh
#
# Shared library sourced by every check module and by run.sh.
#
# A check module reports its results by calling the verify_* functions below.
# The harness (run.sh) collects those findings, aggregates them across all
# modules, and derives one exit code. A check module never decides the process
# exit code itself; it only emits findings.
#
# ---------------------------------------------------------------------------
# MODULE CONTRACT (read this before writing a check for tasks 2.2-2.7)
# ---------------------------------------------------------------------------
#
# A check module is an executable script placed in verify/checks/. run.sh
# discovers every verify/checks/check-*.sh, reads its metadata, and runs it as
# an independent subprocess. Because each module runs in its own process, a
# module that crashes cannot stop the other modules from running.
#
# 1. Metadata. Declare it with comment lines anywhere near the top of the file:
#
#        # verify:number: 3
#        # verify:name: Helm chart versions resolve in their HelmRepository index
#        # verify:requires-aws: false
#        # verify:implements: 2.3
#
#    - number        ordering / display number (checks 1-15 in the design).
#    - name          human-readable check name (used in reports and the
#                    "exceeded budget" / "skipped" lines).
#    - requires-aws  true if the check needs an AWS account. When no
#                    credentials are present run.sh marks it SKIPPED and it does
#                    not affect the exit code (Requirement 10.17). true|false.
#    - implements    the subtask that fills the stub in (informational).
#
# 2. Bootstrapping. Begin the module with:
#
#        source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"
#
#    run.sh exports these for the module:
#      VERIFY_LIB        path to this file
#      VERIFY_REPO_ROOT  repository root (cd here or build paths from it)
#      VERIFY_FINDINGS   file the verify_* helpers append findings to
#      VERIFY_CHECK_NUM  this check's number
#      VERIFY_CHECK_NAME this check's name
#
# 3. Reporting. Call one helper per observation. Report FILE, RESOURCE, and the
#    observed ERROR on every failure (Requirement 10.10, 10.11, 10.15):
#
#      verify_pass        "<message>" ["<resource>"] ["<file>"]
#      verify_fail        "<file>" "<resource>" "<error>"   # build/schema/lint/etc.
#      verify_unresolved  "<file>" "<reference>" "<registry-or-index>"  # a version ref that does NOT resolve (a not-found result)
#      verify_unverified  "<file>" "<reference>" "<registry-or-index>"  # a registry that could not be REACHED after retries
#      verify_unvalidated "<file>" "<api-version>" "<reason>"           # a manifest whose schema could not be located
#      verify_skip        "<reason>"                                    # rarely needed; run.sh auto-skips AWS checks with no creds
#      verify_info        "<message>"                                   # non-scoring note
#
#    Status -> exit-code effect (Requirement 10.1, 10.11, 10.15, 10.16):
#      PASS        no effect
#      INFO        no effect
#      SKIPPED     no effect (Requirement 10.17)
#      UNVALIDATED reported, does NOT fail the run (Requirement 10.2 asks only
#                  that it be listed with path + declared API version)
#      FAIL        run exits non-zero
#      UNRESOLVED  run exits non-zero, reported DISTINCTLY from UNVERIFIED
#      UNVERIFIED  run exits non-zero, reported DISTINCTLY from UNRESOLVED
#                  (Requirement 10.16)
#
# 4. Exit status of the module. Exit 0 when the module ran to completion, even
#    if it emitted failing findings (the findings, not the exit code, carry the
#    verdict). Exit non-zero only when the module itself could not run; run.sh
#    then records an ERROR finding so the crash is visible and fails the run.
#
# 5. Network access. For checks 3-7, wrap each registry/index call in
#    verify_retry so an unreachable registry becomes UNVERIFIED rather than a
#    false UNRESOLVED (Requirement 10.16):
#
#        if out=$(verify_retry -- crane manifest "$ref" 2>&1); then
#            # resolved: inspect $out
#        elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
#            verify_unverified "$file" "$ref" "$registry"
#        else
#            verify_unresolved "$file" "$ref" "$registry"
#        fi
#
# ---------------------------------------------------------------------------

# Guard against double-sourcing.
if [ -n "${_VERIFY_HARNESS_SOURCED:-}" ]; then
    return 0 2>/dev/null || true
fi
_VERIFY_HARNESS_SOURCED=1

# Status constants.
VERIFY_STATUS_PASS="PASS"
VERIFY_STATUS_INFO="INFO"
VERIFY_STATUS_FAIL="FAIL"
VERIFY_STATUS_UNRESOLVED="UNRESOLVED"
VERIFY_STATUS_UNVERIFIED="UNVERIFIED"
VERIFY_STATUS_UNVALIDATED="UNVALIDATED"
VERIFY_STATUS_SKIPPED="SKIPPED"
VERIFY_STATUS_EXCEEDED="EXCEEDED"   # set by run.sh only, never by a module
VERIFY_STATUS_ERROR="ERROR"         # set by run.sh only, never by a module

# Retry policy for reaching a registry/index (Requirement 10.16).
VERIFY_RETRY_ATTEMPTS="${VERIFY_RETRY_ATTEMPTS:-3}"
VERIFY_RETRY_TIMEOUT="${VERIFY_RETRY_TIMEOUT:-30}"
# Return code verify_retry uses to signal "unreachable after all attempts".
VERIFY_RC_UNREACHABLE=99

# Field separator (US, 0x1f) and newline placeholder (RS, 0x1e). A finding is
# one record line of separator-joined fields. The separator is a NON-whitespace
# control character on purpose: `read` collapses runs of whitespace IFS
# characters and drops empty fields, so a tab separator would lose an empty
# file or resource field. 0x1f is preserved, empty fields and all.
_VF_FS=$'\037'
_VF_NL=$'\036'

# _vf_esc <string> : make a field record-line-safe (no separator, no newline).
_vf_esc() {
    printf '%s' "$1" | tr '\037' ' ' | tr '\n' '\036'
}

# _vf_emit <status> <file> <resource> <message>
_vf_emit() {
    local status="$1" file="$2" resource="$3" message="$4"
    : "${VERIFY_FINDINGS:?VERIFY_FINDINGS not set - run via verify/run.sh}"
    printf '%s%s%s%s%s%s%s\n' \
        "$status" "$_VF_FS" \
        "$(_vf_esc "$file")" "$_VF_FS" \
        "$(_vf_esc "$resource")" "$_VF_FS" \
        "$(_vf_esc "$message")" \
        >>"$VERIFY_FINDINGS"
}

# verify_pass <message> [resource] [file]
verify_pass()        { _vf_emit "$VERIFY_STATUS_PASS"        "${3:-}"   "${2:-}"   "${1:-ok}"; }
# verify_info <message>
verify_info()        { _vf_emit "$VERIFY_STATUS_INFO"        ""         ""         "${1:-}"; }
# verify_fail <file> <resource> <error>
verify_fail()        { _vf_emit "$VERIFY_STATUS_FAIL"        "${1:-}"   "${2:-}"   "${3:-}"; }
# verify_unresolved <file> <reference> <registry/index consulted>
verify_unresolved()  { _vf_emit "$VERIFY_STATUS_UNRESOLVED"  "${1:-}"   "${2:-}"   "${3:-}"; }
# verify_unverified <file> <reference> <registry/index consulted>
verify_unverified()  { _vf_emit "$VERIFY_STATUS_UNVERIFIED"  "${1:-}"   "${2:-}"   "${3:-}"; }
# verify_unvalidated <file> <declared api version> <reason>
verify_unvalidated() { _vf_emit "$VERIFY_STATUS_UNVALIDATED" "${1:-}"   "${2:-}"   "${3:-}"; }
# verify_skip <reason>
verify_skip()        { _vf_emit "$VERIFY_STATUS_SKIPPED"     ""         ""         "${1:-}"; }

# run_with_timeout <seconds> <cmd...> : run cmd, killing it after <seconds>.
# Returns the command's exit code, or 124 if it was killed for timing out.
run_with_timeout() {
    local secs="$1"; shift
    if [ "$secs" -le 0 ] 2>/dev/null; then
        return 124
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout "${secs}s" "$@"; return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "${secs}s" "$@"; return $?
    fi
    # Portable fallback for hosts without coreutils timeout (e.g. stock macOS).
    local marker; marker="$(mktemp)"
    "$@" &
    local pid=$!
    (
        sleep "$secs"
        if kill -0 "$pid" 2>/dev/null; then
            printf 'timeout' >"$marker"
            kill -TERM "$pid" 2>/dev/null
            sleep 2
            kill -KILL "$pid" 2>/dev/null
        fi
    ) &
    local watcher=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    if [ -s "$marker" ]; then rc=124; fi
    rm -f "$marker"
    return $rc
}

# verify_retry [-- ] <cmd...> : run cmd up to VERIFY_RETRY_ATTEMPTS times, each
# attempt bounded by VERIFY_RETRY_TIMEOUT seconds. Returns the command's exit
# code on success. If every attempt timed out (the registry could not be
# reached), returns VERIFY_RC_UNREACHABLE so the caller can report UNVERIFIED,
# distinct from a resolved-but-not-found result (Requirement 10.16).
verify_retry() {
    if [ "${1:-}" = "--" ]; then shift; fi
    local attempt rc all_timed_out=1
    for attempt in $(seq 1 "$VERIFY_RETRY_ATTEMPTS"); do
        run_with_timeout "$VERIFY_RETRY_TIMEOUT" "$@"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            return 0
        fi
        if [ "$rc" -ne 124 ]; then
            # Reached the registry; it returned a definite negative result.
            all_timed_out=0
            return "$rc"
        fi
    done
    if [ "$all_timed_out" -eq 1 ]; then
        return "$VERIFY_RC_UNREACHABLE"
    fi
    return "$rc"
}
