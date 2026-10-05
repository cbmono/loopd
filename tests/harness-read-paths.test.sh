#!/usr/bin/env bash
#
# harness-read-paths.test.sh — a harness assertion whose literal path does not resolve is
# a FAILURE, not a datum.
#
# THE CLASS. `grep -q PAT "$HERE/../seed/.claude/settings.json"` exits 2 when the file is
# gone, the `|| echo 0` arm runs, and 0 is exactly what the assertion expects. The read
# failing and the property holding produce the SAME observation, so a path move silently
# converts a test into a certificate. `seed/` moved to `plugin/seed/` in #125 and left two
# such assertions behind (tests/push-state.test.sh, tests/derived-indexes.test.sh); both
# were confirmed by mutation — plant the exact regression the assertion exists for, suite
# stays green. See ai-bridge-v2/task-029 and the control panel's
# knowledge/findings/a-test-that-has-never-failed-is-not-a-test.md.
#
# ============================ WHAT THIS SCANNER REACHES ============================
#
# Stated up front and honestly, because the tempting claim — "it catches the class" — is
# false, and a scanner believed to cover more than it does is the same failure one level up.
#
#   REACHED NATIVELY. Every literal path rooted at a variable this file can prove is bound
#   to the checked-in tree — $TPL, $REPO or $TPLSRC for the repo root, $HERE for this
#   tests/ directory — on a non-comment line. WHICH NAMES, measured over this suite rather
#   than assumed: $REPO binds the root in 36 harnesses, $TPL in 22, $TPLSRC in 5, $HERE the
#   tests/ dir in 20. An earlier draft knew only $TPL and $HERE, so it looked at NONE of the
#   36 — 174 literal paths unexamined while the summary line read as though they were
#   covered, which is this file's own failure mode reproduced inside the guard. Globs count:
#   an empty expansion of `plugin/scripts/*.sh` is the same silent nothing.
#
#   This is a SUPERSET of the `grep`/`cat`/`test -f` read targets task-029 asked for. No
#   command classifier is attempted: those variables address the checked-in tree, harnesses
#   never write to it, and "a literal reference to a tracked path resolves" is a cleaner
#   invariant than any list of read commands.
#
#   TRUST IS PER FILE AND PER VARIABLE, and it fails toward NOT trusting. Every assignment
#   of the name must be the canonical idiom (`export`/`local`/`readonly`/`declare` count as
#   assignments — missing them failed toward trusting), and a root spelled
#   `"$(cd "$HERE/.." && pwd)"` is only as trustworthy as $HERE, which 20 harnesses rely on.
#   A file with any untrusted root is reported PARTIAL; a file binding no root at all is
#   reported NOROOT. Both are printed, and the summary line counts all three buckets,
#   because a file that quietly contributes nothing is exactly what this harness is about.
#
#   OPTED OUT, per call site: `# path-scan: absent — <reason>` exempts the statement, and
#   `# path-scan: absent <path> — <reason>` exempts ONLY that path. The scoped form exists
#   because several tree-wide sweeps here read `grep -r <retired-root> <live> <live>`, and
#   a bare exemption would switch off the live roots to buy the one that is genuinely gone.
#   A marker arms only from the start of its own comment (an unanchored test fired on
#   PROSE — this header spells both markers) and only between statements (a marker set
#   mid-statement would be deferred onto the NEXT one, silencing something unmarked).
#
#   REACHED ONLY BY OPT-IN. `git check-ignore --no-index <path>`. That flag is DESIGNED to
#   answer for a path that does not exist — it is the whole reason `--no-index` exists — so
#   a blanket must-resolve rule over check-ignore targets would be WRONG, and would fail
#   every legitimate probe of a would-be path. The rule is therefore opt-in per call site:
#   `# path-scan: must-resolve` above the statement. tests/derived-indexes.test.sh carries
#   exactly one. Its argument list stops at the first shell operator, because reading the
#   words after `&& echo 0 || echo 1` as paths produced six bogus findings.
#
#   NOT REACHED AT ALL, and this is the important line. An assertion aimed at a file that
#   EXISTS but cannot act. #122 reduced install.sh to a 37-line stub that prints a message
#   and exits 2, and `grep -qF "$KEY" "$TPL/install.sh"` went on certifying that a script
#   writing nothing at all does not write that key. The path resolves, so no
#   path-resolution scanner can ever see it. That class needs the OTHER guard: assert the
#   non-action against a run that provably WAS able to act, and assert that too — see
#   tests/banner-board-line.test.sh's produced-config assertion and the planted-key
#   non-vacuity scan beside it. The fixture below pins this limit as an assertion rather
#   than leaving it as prose, so nobody later reads the scanner as covering it.
#
#   NOT REACHED: a printf FORMAT string that looks like a path. `printf '... "$TPL/%s/x"'`
#   is a template, not a read. Rare enough that it is handled the same way any other
#   deliberate non-path is — `# path-scan: absent` at the call site — and this file is the
#   only harness that does it.
#
#   FOUND ON ITS FIRST EXTENDED RUN, which is the only evidence that any of the above is
#   worth having: tests/blocked-vs-own-tools.test.sh:262 read
#   `grep -rqF 'browser-first' "$REPO/symlink"` — one root, retired in #122 — so `grep -r`
#   exited 2, the `&&` arm never ran, and `yes` was exactly what the line expected. Its own
#   comment called the assertion tree-wide. Repointed at the shipped trees in this change.
#
# ============================ NON-VACUITY ============================
#
# The scanner is proven by removal against a planted fixture tree, in this file, on every
# run: a synthetic harness carrying the item-1 shape, the item-2 shape, an UNMARKED
# check-ignore (must not fire — the opt-in has to be real), a resolving path (must not
# fire), an opted-out absence assertion (must not fire), an install.sh-shaped inert-file
# read (must not fire — the stated limit), and a rebound-TPL file (must be skipped, and
# said so). A scanner asserted only against a clean tree reports "no findings" identically
# whether it works or does nothing at all.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-read-paths.XXXXXX")" || {
  echo "harness-read-paths.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
eq()     { [ "$1" = "$2" ] && echo 0 || echo 1; }
# Sets FDN to this shell's open-descriptor count. A glob rather than `$(ls /dev/fd|wc -l)`:
# no fork, and no pipe of its own to count.
fd_count() { local a; a=(/dev/fd/*); FDN="${#a[@]}"; }

# ---------------------------------------------------------------------------------------
# The scanner.
#
# candidates() emits one `<file>|<line>|<kind>|<relative-path>` record per literal it can
# resolve the ROOT of; the caller does the filesystem test, because awk cannot.
#
# Marker semantics, kept deliberately small so a reader can predict them: a
# `# path-scan: …` comment arms the STATEMENT that begins on the next non-blank,
# non-comment line, where a statement continues while its lines end in a backslash. A
# blank line disarms a pending marker.
# ---------------------------------------------------------------------------------------
CANDIDATES_AWK='
{
  line = $0

  # A MARKER ONLY ARMS FROM ITS OWN COMMENT, AND ONLY BETWEEN STATEMENTS.
  # Anchored: an unanchored test fires on PROSE, and this file spells both markers in its
  # own header — so a documentation paragraph could silently disable the next statement`s
  # check, saved only by a blank line nobody knows is load-bearing.
  # Between statements: pend_* set mid-statement would be deferred and land on the NEXT
  # statement, silencing something the author never marked.
  if (line ~ /^[ \t]*#/) {
    if (!in_stmt) {
      if (line ~ /^[ \t]*#[ \t]*path-scan:[ \t]*absent/) {
        pend_absent = 1
        # OPTIONALLY PATH-SCOPED. A bare marker exempts the whole statement, which is
        # wrong for the several tree-wide `grep -r <rootA> <rootB> <rootC>` sweeps here
        # where exactly ONE root is a retired directory: the bare form would switch off
        # the checks on the roots that still resolve, quietly shrinking the guard to buy
        # one exemption. `# path-scan: absent <path> — <why>` exempts that path alone.
        mp = line; sub(/^[ \t]*#[ \t]*path-scan:[ \t]*absent[ \t]*/, "", mp)
        split(mp, mf, /[ \t]+/)
        if (mf[1] ~ /^[A-Za-z0-9_.\/]/) pend_absent_path = mf[1]; else pend_absent_path = ""
      }
      if (line ~ /^[ \t]*#[ \t]*path-scan:[ \t]*must-resolve/) pend_resolve = 1
    }
    next
  }
  if (line ~ /^[ \t]*$/) { pend_absent = 0; pend_absent_path = ""; pend_resolve = 0; next }

  if (!in_stmt) {
    cur_absent = pend_absent; cur_absent_path = pend_absent_path; cur_resolve = pend_resolve
    pend_absent = 0; pend_absent_path = ""; pend_resolve = 0
  }
  # A statement continues over a trailing backslash AND over the command operators, which
  # is how most multi-line assertions here are actually written. `(` and `{` are
  # deliberately NOT continuations: they open a BLOCK, and treating them as one would let
  # a marker reach past the statement it was written for, which silences more than the
  # author asked for. Under-reaching costs a false positive; over-reaching costs a guard.
  nxt = (line ~ /(\\|&&|\|\||\|)[ \t]*$/) ? 1 : 0

  {
    rest = line
    # The terminator set matters for the UNQUOTED tail form (`"$TPL"/a/b`): shell
    # metacharacters end the word, and leaving `;` out of it once produced a candidate
    # path of `tests/*.test.sh;` from the `for … ; do` loop below. `{}` is in the set for
    # `${cf#"$REPO"/}`, a prefix-strip idiom two harnesses use. The quoted form
    # (`"$TPL/a/b"`) is ended by its own closing quote and never reaches any of them.
    while (match(rest, /"\$(TPL|REPO|TPLSRC|HERE)"?\/[^"$ \t;()&|<>`{}]*/)) {
      tok  = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      vn = tok; sub(/^"\$/, "", vn); sub(/"?\/.*$/, "", vn)
      sub(/^"\$[A-Za-z_][A-Za-z0-9_]*"?\//, "", tok)
      if (tok == "") { continue }
      # The exemption is applied PER TOKEN, so a scoped marker leaves every other literal
      # on the same line live.
      if (cur_absent && (cur_absent_path == "" || tok == cur_absent_path)) { continue }
      if (vn == "HERE") {
        if (!here_ok) { continue }
        print FILENAME "|" FNR "|HERE|" tok
      } else {
        if (index(ok_vars, "," vn ",") == 0) { continue }
        print FILENAME "|" FNR "|ROOT|" tok
      }
    }
  }

  # OPT-IN ONLY. `--no-index` legitimately answers for a path that does not exist, so this
  # never fires without a marker at the call site.
  if (cur_resolve && !cur_absent) {
    i = index(line, "check-ignore")
    if (i > 0) {
      # Which root does `-C` name, and is that root trusted? Without this the branch
      # assumed `-C "$TPL"` and would resolve against the wrong tree.
      ci_root = ""
      if (match(line, /-C[ \t]+"\$[A-Za-z_][A-Za-z0-9_]*"/)) {
        ci_root = substr(line, RSTART, RLENGTH)
        sub(/^-C[ \t]+"\$/, "", ci_root); sub(/"$/, "", ci_root)
      }
      if (ci_root != "" && index(ok_vars, "," ci_root ",") > 0) {
        tail = substr(line, i + 12)
        n = split(tail, a, /[ \t]+/)
        for (k = 1; k <= n; k++) {
          t = a[k]
          # STOP AT THE FIRST OPERATOR. Everything after it is a different command, and
          # reading its words as paths produced six bogus findings on the most ordinary
          # spelling of this probe (`… -q p/i.md && echo 0 || echo 1`).
          if (t == "&&" || t == "||" || t == "|" || t == ";") break
          if (t ~ /^[0-9]*>/) break
          gsub(/[")]+$/, "", t)
          if (t == "")                continue
          if (substr(t, 1, 1) == "-") continue
          if (t ~ /\$/)               continue   # not a literal — out of reach, and silent
          if (t !~ /[\/.]/)           continue   # a bare word is not a path
          print FILENAME "|" FNR "|CHECKIGNORE|" t
        }
      }
    }
  }

  in_stmt = nxt
}
'

# --- per-file trust -------------------------------------------------------------------
# WHICH VARIABLE NAMES. Measured over this suite: REPO binds the checked-in root in 36
# harnesses, TPL in 22, TPLSRC in 5, HERE the tests/ directory in 20. An earlier draft
# knew only TPL and HERE and therefore looked at NONE of the 36 — 174 literal paths
# unexamined, reported as though covered. The names are enumerated rather than inferred
# because a variable holding a runtime fixture path is spelled exactly the same way.
ROOT_VARS="TPL REPO TPLSRC"

# NO PROCESS SUBSTITUTION, AND NO FORK PER ROOT NAME — one awk pass answers for all four.
# bash 3.2 keeps one descriptor per `< <( )` for the life of the enclosing shell, and the
# five this function used to open per harness put `REAL="$(scan …)"` at 255 open fds by the
# 112th file, one short of a cliff where fork() never returns and the child spins in
# _notify_fork_child holding the capture's stdout. Control panel:
# knowledge/findings/bash-3-2-leaks-an-fd-per-process-substitution-and-fork-spins-at-256.
# `export`/`local`/`readonly`/`declare` count as assignments. Missing them failed TOWARD
# trusting the file, which is the wrong direction for every check in here.
CLASSIFY_AWK='
BEGIN { nn = split(names, nm, /[ \t]+/) }
{
  for (i = 1; i <= nn; i++) {
    n = nm[i]
    if ($0 !~ "^[[:space:]]*(export |local |readonly |declare )?" n "=") continue
    seen[n] = 1
    if (n == "HERE") { if (index($0, here_idiom) == 0) bad[n] = 1 }
    else if (index($0, root_idiom) > 0) { }
    else if (index($0, derived_idiom) > 0) { derived[n] = 1 }
    else bad[n] = 1
  }
}
END {
  for (i = 1; i <= nn; i++) {
    n = nm[i]
    if (seen[n]) print n, (bad[n] ? 0 : 1), (derived[n] ? 1 : 0)
  }
}
'

# classify_roots <file> — sets here_ok, ok_vars (",A,B,") and untrusted (a name list).
# HERE is emitted first, so a root derived from it is judged against a settled here_ok.
classify_roots() {
  local f="$1" name ok derived verdicts
  here_ok=0; ok_vars=","; untrusted=""
  verdicts="$(awk -v names="HERE $ROOT_VARS" \
                  -v here_idiom='cd "$(dirname "$0")" && pwd' \
                  -v root_idiom='cd "$(dirname "$0")/.." && pwd' \
                  -v derived_idiom='cd "$HERE/.." && pwd' \
                  "$CLASSIFY_AWK" "$f" 2>/dev/null)"
  while read -r name ok derived; do
    [ -n "${name:-}" ] || continue
    if [ "$name" = HERE ]; then
      here_ok="$ok"
      [ "$ok" = 1 ] || untrusted="$untrusted HERE"
      continue
    fi
    # A ROOT DERIVED FROM $HERE IS ONLY AS TRUSTWORTHY AS $HERE. Twenty harnesses spell
    # TPL="$(cd "$HERE/.." && pwd)", so a fixture-bound HERE would otherwise hand back a
    # fixture-bound root wearing the canonical idiom.
    [ "$derived" = 1 ] && [ "$here_ok" != 1 ] && ok=0
    if [ "$ok" = 1 ]; then ok_vars="$ok_vars$name,"; else untrusted="$untrusted $name"; fi
  done <<< "$verdicts"
}

# resolves <path> — plain existence, or, for a path carrying a glob metacharacter, at
# least one match. `tests/*.test.sh` and `plugin/scripts/*.sh` are read targets like any
# other and an empty expansion is exactly the silent-nothing this file exists to catch.
resolves() {
  local p="$1" m
  [ -e "$p" ] && return 0
  case "$p" in
    *'*'*|*'?'*|*'['*)
      # Unquoted on purpose. No match leaves the pattern itself, which -e then rejects.
      # shellcheck disable=SC2086
      for m in $p; do [ -e "$m" ] && return 0; done ;;
  esac
  return 1
}

# scan <root> <tests-dir> — one human-readable finding per unresolved literal on stdout;
# the per-file coverage report on fd 3 when the caller opens one. EVERY file lands in
# exactly one of three buckets there — checked, partly out of reach, or contributing
# nothing — because a file that quietly contributes nothing is the failure this whole
# harness is about, one level up.
#
# It also reports its own descriptor growth there, as FDGROWTH, and the real-tree run
# asserts on it: this loop is the one that reached the bash-3.2 fd cliff, so the guard
# belongs inside the subshell that leaked, where a count taken by the caller would see
# nothing.
scan() {
  local root="$1" tdir="$2" f base rel kind ln _file cands fd0 fd1
  local here_ok ok_vars untrusted
  fd_count; fd0="$FDN"
  for f in "$tdir"/*.test.sh; do
    [ -e "$f" ] || continue
    base="${f##*/}"
    classify_roots "$f"
    if [ -n "$untrusted" ]; then
      printf 'PARTIAL %s (out of reach:%s — rebound to a runtime path)\n' "$base" "$untrusted" >&3 2>/dev/null || true
    elif [ "$ok_vars" = "," ] && [ "$here_ok" = 0 ]; then
      printf 'NOROOT  %s (binds no checked-in root variable — contributes no candidates)\n' "$base" >&3 2>/dev/null || true
    fi
    cands="$(awk -v here_ok="$here_ok" -v ok_vars="$ok_vars" "$CANDIDATES_AWK" "$f")"
    while IFS='|' read -r _file ln kind rel; do
      [ -n "${rel:-}" ] || continue
      case "$kind" in
        ROOT|CHECKIGNORE) resolves "$root/$rel"  && continue ;;
        HERE)             resolves "$tdir/$rel"  && continue ;;
      esac
      printf '%s:%s  [%s]  %s\n' "$base" "$ln" "$kind" "$rel"
    done <<< "$cands"
  done
  fd_count; fd1="$FDN"
  printf 'FDGROWTH %s (%s open descriptors before the loop, %s after)\n' \
    "$(( fd1 - fd0 ))" "$fd0" "$fd1" >&3 2>/dev/null || true
}

# =======================================================================================
echo "== NON-VACUITY FIRST: the scanner is proven by removal against a planted tree =="
# =======================================================================================
# Built by printf with the stale directory name in a VARIABLE, never spelled literally, so
# this file's own source carries no unresolvable literal and the scanner holds to its own
# rule when it scans itself below.
FX="$TMP/fixture"
GONE=seed          # the pre-#125 directory the item-1 and item-2 probes still named
mkdir -p "$FX/plugin/seed/.claude" "$FX/tests"
printf '{}\n'                   > "$FX/plugin/seed/.claude/settings.json"
printf '# derived\n'            > "$FX/plugin/seed/.gitignore"
printf 'seed index\n'           > "$FX/plugin/seed/index.md"
printf 'exit 2\n'               > "$FX/install.sh"   # exists, and can do nothing — item 3

{
  printf '#!/usr/bin/env bash\n'
  printf 'HERE="$(cd "$(dirname "$0")" && pwd)"\n'
  printf 'TPL="$(cd "$HERE/.." && pwd)"\n'
  printf '\n'
  printf '# A. the item-1 shape: a read of a path the seed move deleted.\n'
  # path-scan: absent — a printf FORMAT, not a path — %s is the fixture's stale dir
  printf 'grep -q hooks "$HERE/../%s/.claude/settings.json"\n' "$GONE"
  printf '\n'
  printf '# B. the item-2 shape, OPTED IN.\n'
  printf '# path-scan: must-resolve\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'git -C "$TPL" check-ignore --no-index -q %s/index.md\n' "$GONE"
  printf '\n'
  printf '# C. the same stale check-ignore with NO marker: the opt-in has to be real.\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'git -C "$TPL" check-ignore --no-index -q %s/other.md\n' "$GONE"
  printf '\n'
  printf '# D. a path that resolves: never a finding.\n'
  printf 'grep -q derived "$TPL/plugin/seed/.gitignore"\n'
  printf '\n'
  printf '# E. a deliberate absence, opted out at the call site.\n'
  printf '# path-scan: absent — this asserts the file is GONE\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'test -e "$TPL/%s/index.md" && echo no || echo yes\n' "$GONE"
  printf '\n'
  printf '# F. the item-3 shape: a real path to a file that cannot act. OUT OF REACH.\n'
  printf 'grep -qF boardArtifactUrl "$TPL/install.sh"\n'
} > "$FX/tests/planted.test.sh"

# G. a harness that rebinds TPL to a fixture: every $TPL literal in it is out of reach,
# and the scanner must SAY so rather than pass over it quietly.
{
  printf '#!/usr/bin/env bash\n'
  printf 'TPL="$TMP/tpl"\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'grep -q x "$TPL/%s/nowhere.md"\n' "$GONE"
} > "$FX/tests/rebound.test.sh"

# H. the $REPO spelling — 36 harnesses use it and an earlier draft of this scanner knew
# only $TPL and $HERE, so it looked at none of them and said nothing about it.
{
  printf '#!/usr/bin/env bash\n'
  printf 'REPO="$(cd "$(dirname "$0")/.." && pwd)"\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'grep -q x "$REPO/%s/repo-rooted.md"\n' "$GONE"
} > "$FX/tests/repo-rooted.test.sh"

# I. PROSE that merely MENTIONS the marker must not arm it. The header of this very file
# spells both markers; unanchored, each one silenced whatever statement came next.
{
  printf '#!/usr/bin/env bash\n'
  printf 'REPO="$(cd "$(dirname "$0")/.." && pwd)"\n'
  printf '# a paragraph explaining that you write `# path-scan: absent` at the call site\n'
  printf '# and that the marker then applies to the next statement\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'grep -q x "$REPO/%s/prose-armed.md"\n' "$GONE"
} > "$FX/tests/prose.test.sh"

# J. an OPTED-IN check-ignore written the ordinary way, with the operators on the same
# line. Reading the words after `&&` as paths produced six bogus findings.
{
  printf '#!/usr/bin/env bash\n'
  printf 'REPO="$(cd "$(dirname "$0")/.." && pwd)"\n'
  printf '# path-scan: must-resolve\n'
  printf 'git -C "$REPO" check-ignore --no-index -q plugin/seed/index.md && echo 0 || echo 1\n'
} > "$FX/tests/operators.test.sh"

# K. a root DERIVED from an untrusted $HERE wears the canonical idiom and must not be
# trusted on the strength of its own spelling. L: `export` counts as an assignment.
{
  printf '#!/usr/bin/env bash\n'
  printf 'HERE="$TMP/fake/tests"\n'
  printf 'TPL="$(cd "$HERE/.." && pwd)"\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'grep -q x "$TPL/%s/derived.md"\n' "$GONE"
  printf 'export REPO="/tmp/elsewhere"\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'grep -q x "$REPO/%s/exported.md"\n' "$GONE"
} > "$FX/tests/derived.test.sh"

# M. a SCOPED absence marker: it exempts the path it names and NOTHING else on the line.
# The tree-wide `grep -r <retired> <live> <live>` sweeps in this suite are the reason —
# a bare marker there would switch off the live roots to buy the one exemption.
{
  printf '#!/usr/bin/env bash\n'
  printf 'REPO="$(cd "$(dirname "$0")/.." && pwd)"\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf '# path-scan: absent %s/retired — the other root on this line resolves\n' "$GONE"
  # path-scan: absent — a printf FORMAT, not a path
  printf 'grep -r x "$REPO/%s/retired" "$REPO/%s/also-gone"\n' "$GONE" "$GONE"
} > "$FX/tests/scoped.test.sh"

FOUND="$(scan "$FX" "$FX/tests" 3>"$TMP/skips.txt")"
printf '%s\n' "$FOUND"          | sed 's/^/    scanner said: /'
sed 's/^/    coverage:     /' "$TMP/skips.txt"

assert "A — flags the stale \$HERE-rooted read (the item-1 shape)" \
  "$(grep -q "planted.test.sh:6  \[HERE\]  ../$GONE/.claude/settings.json" <<<"$FOUND" && echo 0 || echo 1)"
assert "B — flags the MARKED stale check-ignore target (the item-2 shape)" \
  "$(grep -q "\[CHECKIGNORE\]  $GONE/index.md" <<<"$FOUND" && echo 0 || echo 1)"
assert "C — does NOT flag the UNMARKED one: the check-ignore rule is genuinely opt-in" \
  "$(grep -q "$GONE/other.md" <<<"$FOUND" && echo 1 || echo 0)"
assert "D — does NOT flag a path that resolves" \
  "$(grep -q 'plugin/seed/.gitignore' <<<"$FOUND" && echo 1 || echo 0)"
# Narrowed to the [ROOT] kind on purpose: finding B is a [CHECKIGNORE] on the same
# spelling, and an assertion that matched the path alone would have been satisfied by B —
# a vacuity of exactly the kind this file exists to refuse.
assert "E — does NOT flag a deliberate absence carrying 'path-scan: absent'" \
  "$(grep -q "\[ROOT\]  $GONE/index.md" <<<"$FOUND" && echo 1 || echo 0)"
assert "F — does NOT flag install.sh: the stated limit, pinned so nobody assumes otherwise" \
  "$(grep -q 'install.sh' <<<"$FOUND" && echo 1 || echo 0)"
assert "G — reports the rebound-\$TPL harness as out of reach, never silently" \
  "$(grep -q 'PARTIAL rebound.test.sh' "$TMP/skips.txt" && echo 0 || echo 1)"
assert "H — flags a stale \$REPO-rooted read: the 36 harnesses an earlier draft ignored" \
  "$(grep -q "repo-rooted.test.sh:3  \[ROOT\]  $GONE/repo-rooted.md" <<<"$FOUND" && echo 0 || echo 1)"
assert "I — PROSE mentioning the marker does not arm it" \
  "$(grep -q "$GONE/prose-armed.md" <<<"$FOUND" && echo 0 || echo 1)"
assert "J — an opted-in check-ignore with \`&& echo\` yields no bogus word-as-path finding" \
  "$(grep -q 'operators.test.sh' <<<"$FOUND" && echo 1 || echo 0)"
assert "K — a root derived from an untrusted \$HERE is itself untrusted, and reported" \
  "$(grep -q 'PARTIAL derived.test.sh' "$TMP/skips.txt" && grep -qv 'derived.test.sh' <<<"$FOUND" && echo 0 || echo 1)"
assert "L — \`export REPO=\` counts as an assignment, so the file is not trusted on silence" \
  "$(grep -q 'PARTIAL derived.test.sh (out of reach:.*REPO' "$TMP/skips.txt" && echo 0 || echo 1)"
assert "M — a SCOPED marker exempts the path it names…" \
  "$(grep -q "scoped.test.sh:.*$GONE/retired" <<<"$FOUND" && echo 1 || echo 0)"
assert "…and leaves every other literal on the same line live" \
  "$(grep -q "scoped.test.sh:4  \[ROOT\]  $GONE/also-gone" <<<"$FOUND" && echo 0 || echo 1)"
assert "…and finds exactly the five it claims and no sixth thing" \
  "$(eq "$(printf '%s\n' "$FOUND" | grep -c .)" 5)"

# The other half of proof-by-removal: repair the fixture and the same scanner must go
# quiet. A scanner that fires on everything is as useless as one that fires on nothing.
mkdir -p "$FX/$GONE/.claude"
printf '{}\n'     > "$FX/$GONE/.claude/settings.json"
printf 'stale\n'  > "$FX/$GONE/index.md"
printf 'stale\n'  > "$FX/$GONE/repo-rooted.md"
printf 'stale\n'  > "$FX/$GONE/prose-armed.md"
printf 'stale\n'  > "$FX/$GONE/also-gone"
printf 'stale\n'  > "$FX/$GONE/retired"
assert "…and goes SILENT once the planted paths are made to resolve" \
  "$(eq "$(scan "$FX" "$FX/tests" 3>/dev/null | grep -c .)" 0)"

echo
# =======================================================================================
echo "== THE REAL TREE: every literal path a harness reads resolves =="
# =======================================================================================
REAL="$(scan "$TPL" "$TPL/tests" 3>"$TMP/real-skips.txt")"
n_files=0; for _h in "$TPL"/tests/*.test.sh; do [ -e "$_h" ] && n_files=$((n_files+1)); done
n_part="$(grep -c '^PARTIAL' "$TMP/real-skips.txt" 2>/dev/null)"; n_part="${n_part:-0}"
n_none="$(grep -c '^NOROOT'  "$TMP/real-skips.txt" 2>/dev/null)"; n_none="${n_none:-0}"
# grep -c prints 0 AND exits 1 on no match, so `|| echo 0` would append a SECOND zero and
# print the count across two lines. The default-expansion above is the fix.
echo "  scanned $n_files harnesses: $(( n_files - n_part - n_none )) fully in reach, $n_part partly, $n_none binding no checked-in root at all"
sed 's/^/    /' "$TMP/real-skips.txt"
if [ -n "$REAL" ]; then printf '%s\n' "$REAL" | sed 's/^/    UNRESOLVED: /'; fi
assert "no harness reads a literal root-rooted path that does not resolve" \
  "$(eq "$(printf '%s' "$REAL" | grep -c .)" 0)"
# THE GUARD, not a nicety: this scan used to open five `< <( )` per harness and reach 255
# open descriptors here, one below the fork cliff that hung the suite. Growth of anything
# but 0 means a per-item redirection is back.
assert "the scan over every harness leaks no descriptor (bash $BASH_VERSION)" \
  "$(grep -q '^FDGROWTH 0 ' "$TMP/real-skips.txt" && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
