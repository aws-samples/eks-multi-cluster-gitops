#!/usr/bin/env bash
# verify:number: 11
# verify:name: documentation drift (inventory-driven) and referenced-path existence
# verify:requires-aws: false
# verify:implements: 2.5
#
# Check 11 (Requirements 9.3, 9.17, Property 15). Over the Solution_Documentation
# file set:
#   1. every version string equals its inventory `target` (inventory-driven:
#      each inventory entry located in a doc file must state its target); and
#   2. every repository path the documentation references exists.
# Drift and missing referenced paths are reported via verify_fail with the file
# and observed-vs-expected / the missing path.
#
# Solution_Documentation (requirements glossary): README.md, scenarios.md,
# initial-setup/README.md, the files under initial-setup/doc,
# repos/gitops-system/README.md, bin/README.md, clean-up/README.md.
source "${VERIFY_LIB:?VERIFY_LIB not set - run via verify/run.sh}"

REPO="${VERIFY_REPO_ROOT:?VERIFY_REPO_ROOT not set}"
LIB_DIR="$(dirname -- "$VERIFY_LIB")"
INV="$REPO/.kiro/specs/component-version-upgrade/version-inventory.yaml"

if ! command -v python3 >/dev/null 2>&1; then
    verify_info "python3 not available; documentation drift not evaluated (a YAML parser is required)"
    exit 0
fi

run_py() {
    PYTHONPATH="$LIB_DIR" python3 - "$INV" "$REPO" <<'PY'
import os
import re
import sys

import inventory_lib as inv

inv_path, repo_root = sys.argv[1], sys.argv[2]

# --- Solution_Documentation file set -------------------------------------
DOC_FILES = [
    "README.md",
    "scenarios.md",
    "initial-setup/README.md",
    "repos/gitops-system/README.md",
    "bin/README.md",
    "clean-up/README.md",
]
doc_dir = os.path.join(repo_root, "initial-setup", "doc")
if os.path.isdir(doc_dir):
    for root, _dirs, files in os.walk(doc_dir):
        for fn in files:
            rel = os.path.relpath(os.path.join(root, fn), repo_root)
            DOC_FILES.append(rel)
DOC_SET = set(DOC_FILES)

# --- Clause 1: version drift, inventory-driven ---------------------------
try:
    entries = inv.parse_inventory(inv_path) if os.path.exists(inv_path) else []
except Exception as exc:  # noqa: BLE001
    entries = []
    inv.emit("INFO", inv_path, "version-inventory",
             "could not parse inventory: %s" % exc)

if not os.path.exists(inv_path):
    inv.emit("INFO", inv_path, "version-inventory",
             "inventory file not found; version-drift clause skipped")

doc_entries = [e for e in entries if e.get("file", "") in DOC_SET]
for e in doc_entries:
    target = e.get("target", "")
    res = "%s (%s)" % (e.get("locator", ""), e.get("component", ""))
    if inv.is_placeholder(target):
        inv.emit("INFO", e.get("file", ""), res,
                 "inventory target '%s' not resolved yet; drift not evaluated"
                 % target)
        continue
    verdict, detail = inv.occurrence_verdict(repo_root, e, target)
    if verdict == "match":
        inv.emit("PASS", e.get("file", ""), res,
                 "documentation states inventory target '%s'" % target)
    elif verdict == "drift":
        inv.emit("FAIL", e.get("file", ""), res,
                 "documentation drift: expected inventory target '%s' but %s"
                 % (target, detail))
    elif verdict == "missing":
        inv.emit("FAIL", e.get("file", ""), res,
                 "documentation file not found; cannot confirm target '%s'" % target)
    else:
        inv.emit("INFO", e.get("file", ""), res,
                 "could not confirm documented version against target '%s' (%s)"
                 % (target, detail))

# --- Clause 2: referenced repository paths exist -------------------------
# Two reference kinds are resolved with different, deliberate semantics:
#   * Markdown links / images  `](target)` : a relative target resolves
#     against the DOCUMENT's own directory (standard Markdown), an absolute
#     `/target` against the repo root. Any relative link is a repository path.
#   * Inline code spans `like/this`        : prose, so treated as a reference
#     only when it is unambiguously a repo-root path (its head is a known
#     top-level directory). This keeps illustrative snippets such as a
#     kustomization entry `./flux-system` from being mistaken for a file.
TOP = ("initial-setup", "repos", "bin", "clean-up", "doc", "apps",
       "apps-manifests", ".kiro", "verify")
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)\)")
CODE_RE = re.compile(r"`([^`\n]+)`")
PATH_TOKEN_RE = re.compile(r"^[\w./-]+$")


def norm_target(tok):
    return tok.split("#", 1)[0].split("?", 1)[0].strip()


def is_external(tok):
    return (not tok or "://" in tok
            or tok.startswith(("#", "mailto:", "http", "<")))


for doc_rel in sorted(DOC_SET):
    doc_abs = os.path.join(repo_root, doc_rel)
    if not os.path.isfile(doc_abs):
        continue
    if doc_rel.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".pdf")):
        continue
    try:
        text = inv.read_text(doc_abs)
    except OSError:
        continue

    refs = {}  # resolved-repo-relative -> original token (deduped per doc)

    # Markdown links / images: relative to the document's directory.
    for raw in LINK_RE.findall(text):
        t = norm_target(raw)
        if is_external(t) or " " in t:
            continue
        if t.startswith("/"):
            resolved = os.path.normpath(t.lstrip("/"))
        else:
            resolved = os.path.normpath(os.path.join(os.path.dirname(doc_rel), t))
        if resolved.startswith(".."):
            continue  # escapes the repository tree; not ours to assert
        refs.setdefault(resolved, raw)

    # Inline code spans: only unambiguous repo-root paths.
    for raw in CODE_RE.findall(text):
        t = raw.strip()
        if is_external(t) or " " in t or not PATH_TOKEN_RE.match(t):
            continue
        head = t.split("/", 1)[0]
        if "/" not in t or head not in TOP:
            continue
        resolved = os.path.normpath(norm_target(t))
        if resolved.startswith(".."):
            continue
        refs.setdefault(resolved, raw)

    for resolved, raw in sorted(refs.items()):
        if os.path.exists(os.path.join(repo_root, resolved)):
            inv.emit("PASS", doc_rel, "referenced-path",
                     "references '%s' which exists" % raw)
        else:
            inv.emit("FAIL", doc_rel, "referenced-path",
                     "references '%s' -> '%s' which does not exist"
                     % (raw, resolved))
PY
}

# Capture to a file (not a pipe) so a python failure is not masked by the
# exit status of the reading loop.
PYOUT="$(mktemp)"; PYERR="$(mktemp)"
run_py >"$PYOUT" 2>"$PYERR"
rc=$?
if [ "$rc" -ne 0 ]; then
    verify_fail "$INV" "check-11" "documentation evaluation failed (python exit $rc): $(tr '\n' ' ' <"$PYERR" | tail -c 300)"
fi
while IFS=$'\037' read -r st f r m; do
    case "$st" in
        PASS)       verify_pass "$m" "$r" "$f" ;;
        FAIL)       verify_fail "$f" "$r" "$m" ;;
        INFO)       verify_info "$m" ;;
        UNVERIFIED) verify_unverified "$f" "$r" "$m" ;;
        *)          verify_info "check-11 unexpected status '$st': $m" ;;
    esac
done <"$PYOUT"
rm -f "$PYOUT" "$PYERR"

exit 0
