# verify/lib/inventory_lib.py
#
# Minimal, dependency-free helpers shared by the inventory-driven checks
# (check 9 duplicate-group consistency, check 11 documentation drift).
#
# The Version Inventory is authored YAML, but this repository's python3 has no
# PyYAML available, so rather than take a network dependency we parse the one
# structure this file is known to use: a top-level `entries:` sequence whose
# members are flat mappings of scalar fields. Block scalars (the `>- notes`)
# and comments are skipped; only the inline scalar fields the checks consume
# (file, locator, current, target, duplicate_group, status, component) matter.
#
# Findings are emitted on stdout in a tiny record protocol the calling bash
# module translates into verify_* helper calls:
#
#     STATUS<US>file<US>resource<US>message\n      (US = 0x1f)
#
# so that harness escaping/aggregation stays the single source of truth.

import os
import re

US = "\x1f"  # field separator matching the harness wire format


def emit(status, file="", resource="", message=""):
    """Print one finding record. Newlines/separators in fields are neutralised
    so each finding is exactly one line; the harness does the real escaping."""
    def clean(s):
        return str(s).replace(US, " ").replace("\n", " ").replace("\r", " ")
    print(US.join([status, clean(file), clean(resource), clean(message)]))


# ---------------------------------------------------------------------------
# Inventory parsing
# ---------------------------------------------------------------------------

_ENTRY_RE = re.compile(r"^  - ([A-Za-z][\w-]*):\s?(.*)$")
_FIELD_RE = re.compile(r"^    ([A-Za-z][\w-]*):\s?(.*)$")


def _scalarize(val):
    """Turn a raw inline YAML scalar into a python string. Strips matching
    surrounding quotes; returns '' for block-scalar indicators, which the
    checks never read."""
    v = val.strip()
    if v in (">-", ">", "|", "|-", "|+", ">+", ""):
        return ""
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        inner = v[1:-1]
        if v[0] == "'":
            inner = inner.replace("''", "'")
        return inner
    return v


def parse_inventory(path):
    """Return the inventory `entries` as a list of dicts of inline scalars.

    Deliberately tolerant: unknown structure is skipped rather than raising, so
    a hand-edit to the inventory degrades to fewer entries instead of crashing
    the check."""
    entries = []
    cur = None
    in_entries = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.rstrip("\n")
            if not in_entries:
                if raw.strip() == "entries:":
                    in_entries = True
                continue
            stripped = raw.strip()
            if stripped == "" or stripped.startswith("#"):
                continue
            m = _ENTRY_RE.match(raw)
            if m:
                if cur is not None:
                    entries.append(cur)
                cur = {m.group(1): _scalarize(m.group(2))}
                continue
            m = _FIELD_RE.match(raw)
            if m and cur is not None:
                cur[m.group(1)] = _scalarize(m.group(2))
                continue
            # Anything more deeply indented (block-scalar body) is ignored.
    if cur is not None:
        entries.append(cur)
    return entries


# ---------------------------------------------------------------------------
# Value / locator helpers
# ---------------------------------------------------------------------------

def is_placeholder(target):
    """True when a `target` is not a concrete version string yet: an unresolved
    task placeholder, an `n/a` (removed component), or an `<unpinned ...>`
    note. Value-at-file comparison is skipped for these."""
    if target is None:
        return True
    t = target.strip().lower()
    if t == "" or t == "n/a":
        return True
    if t.startswith("<"):
        return True
    if "unresolved" in t or "unpinned" in t:
        return True
    return False


def locator_line(locator):
    """Extract the 1-based line number a locator points at, if it states one
    (e.g. '... (line 266)' or 'line 342 — ...'). Returns int or None."""
    if not locator:
        return None
    m = re.search(r"line\s+(\d+)", locator)
    return int(m.group(1)) if m else None


# Characters that are part of a version-ish token; the token match requires a
# non-token character (or string edge) on both sides so '1.35' does not match
# inside '1.352'.
_BOUND = r"A-Za-z0-9._+/:\-"


def token_present(text, token):
    if not token:
        return False
    pat = r"(?<![" + _BOUND + r"])" + re.escape(token) + r"(?![" + _BOUND + r"])"
    return re.search(pat, text) is not None


def version_variants(value):
    """Notation-tolerant forms of a version string. Some duplicate groups mix a
    `v`-prefixed and a bare notation (inventory FINDING 18); accept either."""
    out = {value}
    if value.startswith("v"):
        out.add(value[1:])
    else:
        out.add("v" + value)
    return out


def read_window(path, line, radius=2):
    """Return the text of [line-radius, line+radius] (1-based, inclusive)."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    lo = max(0, line - 1 - radius)
    hi = min(len(lines), line - 1 + radius + 1)
    return "".join(lines[lo:hi])


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def occurrence_verdict(repo_root, entry, expected):
    """Best-effort check of whether the file occurrence an entry names states
    `expected`. Returns (verdict, detail):

      'match'    - the expected version is present at/near the locator
      'drift'    - the entry's `current` is present instead (a real divergence)
      'missing'  - the referenced file does not exist
      'unknown'  - the locator/value could not be resolved (degrade to INFO)
    """
    rel = entry.get("file", "")
    locator = entry.get("locator", "")
    path = os.path.join(repo_root, rel)
    if not rel or not os.path.exists(path):
        return ("missing", "file not found")

    exp_variants = version_variants(expected)
    cur = entry.get("current", "")
    cur_variants = version_variants(cur) if cur and not is_placeholder(cur) else set()

    line = locator_line(locator)
    if line is not None:
        try:
            hay = read_window(path, line, 2)
        except OSError as exc:
            return ("unknown", "could not read file: %s" % exc)
        if any(token_present(hay, t) for t in exp_variants):
            return ("match", "line %d" % line)
        if any(token_present(hay, t) for t in cur_variants):
            return ("drift", "observed '%s' near line %d" % (cur, line))
        return ("unknown", "no matching value near line %d" % line)

    # No line number: fall back to a whole-file token search.
    try:
        hay = read_text(path)
    except OSError as exc:
        return ("unknown", "could not read file: %s" % exc)
    if any(token_present(hay, t) for t in exp_variants):
        return ("match", "found in file")
    if any(token_present(hay, t) for t in cur_variants):
        return ("drift", "observed '%s' in file" % cur)
    return ("unknown", "locator not machine-resolvable")
