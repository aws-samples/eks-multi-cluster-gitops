#!/usr/bin/env bash
#
# verify/run.sh - single entry point for the component-version-upgrade
# verification suite.
#
# Discovers every check module under verify/checks/, runs each as an
# independent subprocess, aggregates their findings, and returns one exit code.
#
#   - Exit 0 only when every executed check completes without error.
#   - Any resolution, build, schema, lint, duplicate-divergence, residue,
#     unreachable-registry, budget-exceeded, or module-error result -> exit 1.
#     (Requirement 10.1, 10.11, 10.15, 10.16)
#   - A failing module never prevents the remaining modules from running; each
#     failure is reported with its file path, resource, and observed error.
#     (Requirement 10.11, 10.15)
#   - Registries that cannot be reached after retries are reported as
#     UNVERIFIED, kept distinct from UNRESOLVED. (Requirement 10.16)
#   - The credential-free checks share a 600s wall-clock budget; any that do
#     not complete within it are reported by name. (Requirement 10.14)
#   - Checks that require AWS are SKIPPED with a reason when no credentials are
#     present, and skipped checks do not affect the exit code. (Requirement 10.17)
#
# Usage:
#   verify/run.sh [options]
#     --budget <seconds>     credential-free wall-clock budget (default 600)
#     --checks-dir <dir>     directory of check modules (default verify/checks)
#     --list                 list discovered checks and exit
#     -h | --help            show this help
#
# Environment overrides:
#   VERIFY_BUDGET_SECONDS   same as --budget
#   VERIFY_NO_AWS=1         force "no AWS credentials" (skip AWS checks)
#   VERIFY_FORCE_AWS=1      force "AWS credentials present" (run AWS checks)
#   VERIFY_RETRY_ATTEMPTS   registry reach attempts (default 3)
#   VERIFY_RETRY_TIMEOUT    per-attempt timeout seconds (default 30)

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)"
VERIFY_LIB="$SCRIPT_DIR/lib/harness.sh"
CHECKS_DIR="$SCRIPT_DIR/checks"
BUDGET_SECONDS="${VERIFY_BUDGET_SECONDS:-600}"
LIST_ONLY=0

# shellcheck source=lib/harness.sh
. "$VERIFY_LIB"

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --budget)      BUDGET_SECONDS="$2"; shift 2 ;;
        --budget=*)    BUDGET_SECONDS="${1#*=}"; shift ;;
        --checks-dir)  CHECKS_DIR="$2"; shift 2 ;;
        --checks-dir=*) CHECKS_DIR="${1#*=}"; shift ;;
        --list)        LIST_ONLY=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) printf 'run.sh: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

now_s() { date +%s; }

# emit_global <num> <name> <status> <file> <resource> <message>
# Append one aggregated finding line (separator-joined) to GLOBAL_FINDINGS.
emit_global() {
    printf '%s%s%s%s%s%s%s%s%s%s%s\n' \
        "$1" "$_VF_FS" "$(_vf_esc "$2")" "$_VF_FS" "$3" "$_VF_FS" "$4" "$_VF_FS" "$5" "$_VF_FS" "$6" \
        >>"$GLOBAL_FINDINGS"
}

# meta_get <file> <key> <default>
meta_get() {
    local f="$1" key="$2" def="$3" val
    val="$(grep -m1 -E "^#[[:space:]]*verify:${key}:" "$f" 2>/dev/null \
        | sed -E "s/^#[[:space:]]*verify:${key}:[[:space:]]*//")"
    if [ -n "$val" ]; then printf '%s' "$val"; else printf '%s' "$def"; fi
}

is_true() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|y) return 0 ;;
        *) return 1 ;;
    esac
}

have_aws_creds() {
    [ "${VERIFY_NO_AWS:-0}" = "1" ] && return 1
    [ "${VERIFY_FORCE_AWS:-0}" = "1" ] && return 0
    [ -n "${AWS_ACCESS_KEY_ID:-}" ] && return 0
    [ -n "${AWS_PROFILE:-}" ] && return 0
    [ -n "${AWS_SESSION_TOKEN:-}" ] && return 0
    return 1
}

# Severity rank for rolling per-check findings up into one status.
severity_rank() {
    case "$1" in
        "$VERIFY_STATUS_ERROR")      echo 70 ;;
        "$VERIFY_STATUS_EXCEEDED")   echo 60 ;;
        "$VERIFY_STATUS_FAIL")       echo 50 ;;
        "$VERIFY_STATUS_UNRESOLVED") echo 45 ;;
        "$VERIFY_STATUS_UNVERIFIED") echo 40 ;;
        "$VERIFY_STATUS_UNVALIDATED") echo 20 ;;
        "$VERIFY_STATUS_SKIPPED")    echo 10 ;;
        "$VERIFY_STATUS_INFO")       echo 5 ;;
        "$VERIFY_STATUS_PASS")       echo 1 ;;
        *) echo 0 ;;
    esac
}

is_failing_status() {
    case "$1" in
        "$VERIFY_STATUS_FAIL"|"$VERIFY_STATUS_UNRESOLVED"|"$VERIFY_STATUS_UNVERIFIED"|"$VERIFY_STATUS_EXCEEDED"|"$VERIFY_STATUS_ERROR")
            return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Discover check modules
# ---------------------------------------------------------------------------

if [ ! -d "$CHECKS_DIR" ]; then
    printf 'run.sh: checks directory not found: %s\n' "$CHECKS_DIR" >&2
    exit 2
fi

CHECK_FILES=()
while IFS= read -r f; do
    [ -n "$f" ] && CHECK_FILES+=("$f")
done < <(find "$CHECKS_DIR" -maxdepth 1 -type f -name 'check-*.sh' | sort)

if [ "${#CHECK_FILES[@]}" -eq 0 ]; then
    printf 'run.sh: no check modules found in %s\n' "$CHECKS_DIR" >&2
    exit 2
fi

if [ "$LIST_ONLY" -eq 1 ]; then
    printf 'Discovered %d check module(s) in %s:\n\n' "${#CHECK_FILES[@]}" "$CHECKS_DIR"
    for f in "${CHECK_FILES[@]}"; do
        num="$(meta_get "$f" number '?')"
        name="$(meta_get "$f" name "$(basename "$f")")"
        raws="$(meta_get "$f" 'requires-aws' false)"
        impl="$(meta_get "$f" implements '-')"
        if is_true "$raws"; then cred="AWS"; else cred="no-cred"; fi
        printf '  [%2s] %-7s (task %s) %s\n' "$num" "$cred" "$impl" "$name"
    done
    exit 0
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

WORKDIR="$(mktemp -d)"
GLOBAL_FINDINGS="$WORKDIR/findings.all"
: >"$GLOBAL_FINDINGS"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

AWS_AVAILABLE=0
if have_aws_creds; then AWS_AVAILABLE=1; fi

RUN_START="$(now_s)"
cf_elapsed=0   # accumulated credential-free wall-clock seconds

# Parallel arrays keyed by check index.
declare -a C_NUM C_NAME C_STATUS C_DUR C_RAWS

printf '=== Verification suite: component-version-upgrade ===\n'
printf 'repo:   %s\n' "$REPO_ROOT"
printf 'checks: %d discovered in %s\n' "${#CHECK_FILES[@]}" "$CHECKS_DIR"
printf 'budget: %ss over credential-free checks\n' "$BUDGET_SECONDS"
if [ "$AWS_AVAILABLE" -eq 1 ]; then
    printf 'aws:    credentials present (AWS checks will run)\n\n'
else
    printf 'aws:    no credentials (AWS checks will be skipped)\n\n'
fi

idx=0
for f in "${CHECK_FILES[@]}"; do
    num="$(meta_get "$f" number "$((idx + 1))")"
    name="$(meta_get "$f" name "$(basename "$f")")"
    raws="$(meta_get "$f" 'requires-aws' false)"

    C_NUM[$idx]="$num"
    C_NAME[$idx]="$name"
    C_RAWS[$idx]="$raws"
    C_DUR[$idx]=0

    per_check_findings="$WORKDIR/findings.$idx"
    : >"$per_check_findings"
    per_check_log="$WORKDIR/log.$idx"

    # Point the harness helpers (and _vf_emit, used below for synthetic
    # findings) at this check's findings file.
    export VERIFY_FINDINGS="$per_check_findings"

    # AWS check with no credentials -> skip, no exit-code effect.
    if is_true "$raws" && [ "$AWS_AVAILABLE" -eq 0 ]; then
        _vf_emit "$VERIFY_STATUS_SKIPPED" "" "" "requires an AWS account; no credentials present"
        C_STATUS[$idx]="$VERIFY_STATUS_SKIPPED"
        printf '  [%2s] %-11s %s\n' "$num" "SKIPPED" "$name"
        while IFS="$_VF_FS" read -r st fi re ms; do
            emit_global "$num" "$name" "$st" "$fi" "$re" "$ms"
        done <"$per_check_findings"
        idx=$((idx + 1))
        continue
    fi

    # Export the rest of the module contract environment.
    export VERIFY_LIB VERIFY_REPO_ROOT="$REPO_ROOT"
    export VERIFY_CHECK_NUM="$num" VERIFY_CHECK_NAME="$name"

    status_override=""
    if is_true "$raws"; then
        # AWS check with credentials: not bound by the credential-free budget.
        t0="$(now_s)"
        bash "$f" >"$per_check_log" 2>&1
        rc=$?
        t1="$(now_s)"
        C_DUR[$idx]=$((t1 - t0))
    else
        # Credential-free check: bound by the remaining shared budget.
        remaining=$((BUDGET_SECONDS - cf_elapsed))
        if [ "$remaining" -le 0 ]; then
            _vf_emit "$VERIFY_STATUS_EXCEEDED" "" "" \
                "credential-free budget (${BUDGET_SECONDS}s) exhausted before this check started"
            status_override="$VERIFY_STATUS_EXCEEDED"
            rc=0
        else
            t0="$(now_s)"
            run_with_timeout "$remaining" bash "$f" >"$per_check_log" 2>&1
            rc=$?
            t1="$(now_s)"
            C_DUR[$idx]=$((t1 - t0))
            cf_elapsed=$((cf_elapsed + ${C_DUR[$idx]}))
            if [ "$rc" -eq 124 ]; then
                _vf_emit "$VERIFY_STATUS_EXCEEDED" "" "" \
                    "did not complete within the ${BUDGET_SECONDS}s credential-free budget"
                status_override="$VERIFY_STATUS_EXCEEDED"
            fi
        fi
    fi

    # A module that exited non-zero without a timeout and without emitting any
    # failing finding has crashed: record it so the run fails visibly.
    if [ -z "$status_override" ] && [ "$rc" -ne 0 ]; then
        emitted_failing=0
        while IFS="$_VF_FS" read -r st _; do
            if is_failing_status "$st"; then emitted_failing=1; break; fi
        done <"$per_check_findings"
        if [ "$emitted_failing" -eq 0 ]; then
            log_tail="$(tail -n 3 "$per_check_log" 2>/dev/null | tr '\n' ' ')"
            _vf_emit "$VERIFY_STATUS_ERROR" "$f" "" \
                "module exited $rc without reporting a result: ${log_tail}"
        fi
    fi

    # Roll the module's findings into one status and fold into global findings.
    worst="$VERIFY_STATUS_PASS"
    worst_rank="$(severity_rank "$worst")"
    had_any=0
    while IFS="$_VF_FS" read -r st fi re ms; do
        [ -z "$st" ] && continue
        had_any=1
        r="$(severity_rank "$st")"
        if [ "$r" -gt "$worst_rank" ]; then worst="$st"; worst_rank="$r"; fi
        emit_global "$num" "$name" "$st" "$fi" "$re" "$ms"
    done <"$per_check_findings"
    if [ "$had_any" -eq 0 ]; then
        # No findings emitted at all: treat completion as a pass.
        emit_global "$num" "$name" "$VERIFY_STATUS_PASS" "" "" "completed with no findings"
    fi
    C_STATUS[$idx]="$worst"

    printf '  [%2s] %-11s %s (%ss)\n' "$num" "$worst" "$name" "${C_DUR[$idx]}"
    idx=$((idx + 1))
done

TOTAL_WALL=$(( $(now_s) - RUN_START ))

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

print_findings_of_status() {
    local want="$1" heading="$2" any=0
    while IFS="$_VF_FS" read -r num name st fi re ms; do
        [ "$st" = "$want" ] || continue
        if [ "$any" -eq 0 ]; then printf '\n%s\n' "$heading"; any=1; fi
        printf '  - [check %s] %s\n' "$num" "$(printf '%s' "$name" | tr "$_VF_NL" ' ')"
        [ -n "$fi" ] && printf '      file:     %s\n' "$(printf '%s' "$fi" | tr "$_VF_NL" ' ')"
        [ -n "$re" ] && printf '      resource: %s\n' "$(printf '%s' "$re" | tr "$_VF_NL" ' ')"
        if [ -n "$ms" ]; then
            printf '      detail:   '
            printf '%s' "$ms" | tr "$_VF_NL" '\n' | sed '1!s/^/                /'
            printf '\n'
        fi
    done <"$GLOBAL_FINDINGS"
}

# Count findings whose (3rd) status field equals $1. grep -c prints 0 and
# exits 1 when there is no match, so capture the number and never chain `||`.
count_status() {
    local n
    n="$(grep -c -e "^[^$_VF_FS]*$_VF_FS[^$_VF_FS]*$_VF_FS$1$_VF_FS" "$GLOBAL_FINDINGS" 2>/dev/null)"
    printf '%s' "${n:-0}"
}

n_fail=$(count_status "$VERIFY_STATUS_FAIL")
n_unres=$(count_status "$VERIFY_STATUS_UNRESOLVED")
n_unver=$(count_status "$VERIFY_STATUS_UNVERIFIED")
n_unval=$(count_status "$VERIFY_STATUS_UNVALIDATED")
n_exc=$(count_status "$VERIFY_STATUS_EXCEEDED")
n_err=$(count_status "$VERIFY_STATUS_ERROR")
n_skip=$(count_status "$VERIFY_STATUS_SKIPPED")

print_findings_of_status "$VERIFY_STATUS_ERROR"      "MODULE ERRORS (module could not run):"
print_findings_of_status "$VERIFY_STATUS_FAIL"       "FAILURES (build / schema / lint / duplicate / residue):"
print_findings_of_status "$VERIFY_STATUS_UNRESOLVED" "UNRESOLVED (reference not found in its registry/index):"
print_findings_of_status "$VERIFY_STATUS_UNVERIFIED" "UNVERIFIED (registry unreachable after retries - distinct from unresolved):"
print_findings_of_status "$VERIFY_STATUS_UNVALIDATED" "UNVALIDATED (schema could not be located; reported, non-failing):"

# Budget report (Requirement 10.14): name every credential-free check that did
# not complete within the budget.
if [ "$n_exc" -gt 0 ]; then
    printf '\nEXCEEDED BUDGET (credential-free budget %ss; these did not complete in time):\n' "$BUDGET_SECONDS"
    i=0
    while [ "$i" -lt "$idx" ]; do
        if [ "${C_STATUS[$i]}" = "$VERIFY_STATUS_EXCEEDED" ]; then
            printf '  - [check %s] %s\n' "${C_NUM[$i]}" "${C_NAME[$i]}"
        fi
        i=$((i + 1))
    done
fi

# Skipped report.
if [ "$n_skip" -gt 0 ]; then
    printf '\nSKIPPED (no effect on exit code):\n'
    while IFS="$_VF_FS" read -r num name st fi re ms; do
        [ "$st" = "$VERIFY_STATUS_SKIPPED" ] || continue
        printf '  - [check %s] %s - %s\n' "$num" "$(printf '%s' "$name" | tr "$_VF_NL" ' ')" "$(printf '%s' "$ms" | tr "$_VF_NL" ' ')"
    done <"$GLOBAL_FINDINGS"
fi

printf '\n=== Summary ===\n'
printf 'credential-free wall-clock: %ss (budget %ss) | total wall-clock: %ss\n' "$cf_elapsed" "$BUDGET_SECONDS" "$TOTAL_WALL"
printf 'fail=%s unresolved=%s unverified=%s exceeded=%s module-errors=%s | unvalidated=%s skipped=%s\n' \
    "$n_fail" "$n_unres" "$n_unver" "$n_exc" "$n_err" "$n_unval" "$n_skip"

failing_total=$((n_fail + n_unres + n_unver + n_exc + n_err))
if [ "$failing_total" -gt 0 ]; then
    printf 'RESULT: FAIL (%d failing finding(s))\n' "$failing_total"
    exit 1
fi
printf 'RESULT: PASS\n'
exit 0
