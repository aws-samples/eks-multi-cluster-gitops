# Verification suite

Automated, offline-first checks for the **component-version-upgrade** work.
`verify/run.sh` is the single entry point: it discovers every check module,
runs each as an independent subprocess, aggregates their findings, and returns
one exit code.

```
verify/
  run.sh              entry point: discover -> run -> aggregate -> one exit code
  lib/harness.sh      shared library sourced by run.sh and every check module
  checks/             one file per check; discovered as check-*.sh, run in order
```

## Running

```bash
bash verify/run.sh            # run the whole suite
bash verify/run.sh --list     # list discovered checks without running them
bash verify/run.sh --budget 120   # tighten the credential-free wall-clock budget
```

Exit code is `0` only when every executed check completes without error.
Any build, schema, resolution, lint, duplicate-divergence, Cloud9-residue,
unreachable-registry, budget-exceeded, or module-error result yields `1`.

The 15 checks map to the design's verification table. Checks **14** and **15**
require an AWS account; with no credentials present they are reported as
**SKIPPED** and do not affect the exit code.

## Status vocabulary

| Status | Meaning | Fails the run? |
|---|---|---|
| `PASS` | check completed with nothing to report | no |
| `INFO` | non-scoring note | no |
| `SKIPPED` | AWS check with no credentials present (Req 10.17) | no |
| `UNVALIDATED` | a manifest whose schema could not be located; listed with its path and declared API version (Req 10.2) | no |
| `FAIL` | build / schema / lint / duplicate-divergence / Cloud9 residue | **yes** |
| `UNRESOLVED` | a version reference that does **not** resolve (a not-found result) | **yes** |
| `UNVERIFIED` | a registry that could **not be reached** after 3 attempts at 30s each — kept distinct from `UNRESOLVED` (Req 10.16) | **yes** |
| `EXCEEDED` | a credential-free check that did not complete within the 600s budget, reported by name (Req 10.14) | **yes** |
| `ERROR` | a module that could not run (crashed) | **yes** |

`UNRESOLVED` vs `UNVERIFIED` is the key distinction: a reachable registry that
returns "no such version" is a real upgrade defect (`UNRESOLVED`); a registry
that times out is an environment problem, not a defect in the tree
(`UNVERIFIED`). Both fail the run, but they are reported in separate sections.

## Writing a check (tasks 2.2–2.7)

Each check is an executable script in `verify/checks/` named `check-NN-*.sh`.
The full contract lives at the top of [`lib/harness.sh`](lib/harness.sh). In
short:

1. Declare metadata as comment lines:

   ```bash
   # verify:number: 3
   # verify:name: pinned Helm chart versions present in their HelmRepository index
   # verify:requires-aws: false
   # verify:implements: 2.3
   ```

2. Source the harness and report findings:

   ```bash
   source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

   verify_fail        "<file>" "<resource>" "<observed error>"
   verify_unresolved  "<file>" "<reference>" "<registry/index consulted>"
   verify_unverified  "<file>" "<reference>" "<registry/index consulted>"
   verify_unvalidated "<file>" "<declared apiVersion>" "<reason>"
   verify_pass        "<message>" ["<resource>"] ["<file>"]
   ```

   Every failure must carry the **file path**, the **resource**, and the
   **observed error** (Req 10.10, 10.11, 10.15).

3. For network checks (3–7) wrap each registry/index call in `verify_retry`
   so an unreachable registry becomes `UNVERIFIED`, not a false `UNRESOLVED`:

   ```bash
   if out=$(verify_retry -- crane manifest "$ref" 2>&1); then
       :  # resolved; inspect $out
   elif [ $? -eq "$VERIFY_RC_UNREACHABLE" ]; then
       verify_unverified "$file" "$ref" "$registry"
   else
       verify_unresolved "$file" "$ref" "$registry"
   fi
   ```

4. Exit `0` when the module ran to completion (even if it reported failures —
   the findings carry the verdict). Exit non-zero only if the module itself
   could not run; `run.sh` then records an `ERROR` and fails the run.

Modules run in their own subprocess, so a crash in one cannot stop the others.
The environment `run.sh` provides to each module: `VERIFY_LIB`,
`VERIFY_REPO_ROOT`, `VERIFY_FINDINGS`, `VERIFY_CHECK_NUM`, `VERIFY_CHECK_NAME`.
