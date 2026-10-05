#!/usr/bin/env bash
#
# harness-temp-safety.test.sh — no harness in this directory may `rm -rf` a path it did
# not create.
#
# WHY THIS IS A TEST AND NOT A FIXED LINE IN TWO FILES. On 2026-08-23 two of the 28
# harnesses here DELETED THE CHECKOUT THEY WERE TESTING, twice, on a machine where
# TMPDIR named a directory that did not exist:
#
#   TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")" && pwd)"   <- the destructive form
#   trap 'rm -rf "$TMP"' EXIT
#
#   1. `mktemp -d` fails, so the inner substitution is the EMPTY STRING;
#   2. `cd ""` SUCCEEDS AND DOES NOT MOVE — a documented bash no-op, not an error, so
#      `&& pwd` runs;
#   3. `pwd` therefore prints the harness's own cwd: the repository root;
#   4. TMP is the repo root, and the EXIT trap runs `rm -rf` over it.
#
# No harness here uses `set -e` (a failed assertion must not abort the file), so nothing
# stops it. The other harnesses use the plain `TMP="$(mktemp -d …)"` form: they get an
# empty TMP, `rm -rf ""` is harmless, and they merely fail loudly. ONLY THE FORM THAT
# CD-s INTO A SUBSTITUTION IS DESTRUCTIVE — and the `cd` cannot simply be deleted, since
# it is what normalises the `/var/…` path with a `//` in it that macOS hands back, against
# assertions that compare `pwd` output.
#
# So the fix is a CLASS, not two lines: the substitution that creates the directory must
# be guarded, and the canonicalising `cd` must be handed a variable already known good.
# This file asserts that shape over every harness in the directory, so the next one that
# reaches for `cd "$(mktemp …)"` fails here rather than on somebody's uncommitted work.
#
# The two static classes, per harness, for every path an EXIT trap deletes:
#   NESTED-CD  the path is produced by cd-ing INTO a command substitution.
#   UNGUARDED  the path is canonicalised through `cd`, but the `mktemp` that created it
#              carries no `||` abort, so a failed mktemp reaches the `cd` empty.
#
# PHYSICAL LAYOUT IS NOT A DODGE, AND IT USED TO BE. The first cut of this scanner read
# one PHYSICAL line, so the identical destructive assignment wrapped for readability was
# invisible to it while staying exactly as destructive at runtime. It now normalises each
# harness to LOGICAL lines first (`logical_lines` below: backslash continuations and a
# `$( … )` left open at end of line are joined into one statement) and applies the same
# predicates to whole statements, so every layout of the shape reads the same.
#
# AND NEITHER IS A LITERAL OR A COMMENT. The second cut counted `$(` and `)` wherever they
# stood, which let two lines of ordinary-looking shell placed AROUND the offence disarm the
# scanner completely — the bypass is reproduced in full at `logical_lines` below. The
# delimiters are now read by a small lexer that skips what the shell skips, so no text a
# harness writes about this hazard can stop the scanner from seeing the hazard.
#
# THE LIMITS THAT REMAIN — (b) THROUGH (e) ARE DECIDED PERMANENT (task-027, 2026-08-24), NOT
# TODO. The scanner is a text scan over statements, not a shell parser, and the owner chose
# to stop extending it rather than close a fourth one — see the paragraph after the list:
#   (a) the `||` abort must sit on the same STATEMENT as the `mktemp` — chasing a guard
#       into a following statement would mean deciding which nearby test counts, which is
#       guessing;
#   (b) PERMANENT. the trap must name the path inline (`trap 'rm -rf "$TMP"' EXIT`) — a
#       trap that calls a cleanup function hides the path from a text scan. Reproduced:
#         cleanup() { rm -rf "$FTMP"; }
#         trap cleanup EXIT
#       over an FTMP built by the destructive `cd "$(mktemp …)"` shape on its own, ordinary,
#       unguarded statement. `scan`'s `vars` list is only populated from a statement that
#       contains BOTH `trap` and `rm -rf` together, and here they sit in two different
#       statements, so the destructive assignment is never even looked up. Measured, run for
#       real: in a throwaway checkout with a TMPDIR that does not exist, this shape deleted
#       the checkout and exited 0, while `scan` reported 0 findings against it;
#   (c) PERMANENT. the path must not be laundered through another variable
#       (`A="$(cd "$(mktemp …)" && pwd)"; FTMP="$A"`) — only the trapped name's own
#       assignments are read, and `FTMP="$A"` carries none of the destructive shape itself.
#       Measured the same way: real deletion, real exit 0, 0 findings from `scan`;
#   (d) PERMANENT. joining can over-reach as well as reach: `logical_lines` carries two
#       tripwires for a runaway join (UNCLOSED/WIDE, both asserted non-vacuously below), but
#       a SHORT over-join that closes within MAXSPAN trips neither, and if it swallows a
#       following assignment the joined statement no longer STARTS with that assignment, so
#       the anchored `^FTMP=` selector misses it even though the assignment is real,
#       unguarded, and runs at top level. Reproduced with a `\`-continuation (which joins two
#       physical lines for real bash too, unlike a `$( … )`, which would fork a subshell and
#       the assignment would never reach the trap's scope):
#         A=1 \
#         FTMP="$(cd "$(mktemp …)" && pwd)"
#       joins into one statement beginning `A=1 \ FTMP=…` — the same displacement as (e)
#       below, reached through the JOIN mechanism instead of a bare `;`. Measured: real
#       deletion, real exit 0, 0 findings from `scan`;
#   (e) PERMANENT. the assignment must be at the START of its statement even with no join
#       involved. `A=1 ; TMP="$(cd "$(mktemp …)" && pwd)"` is one physical line of ordinary
#       shell, destructive for real (measured: it emptied a throwaway directory and exited
#       0), and reported by NEITHER this scanner nor the line-wise one it replaced.
#       Splitting statements at `;` wants judgement about `case` arms and `for x; do` that a
#       text scan cannot make. Measured over this directory: no harness assigns a
#       trap-deleted path anywhere but at a statement start, so nothing is hiding behind it
#       today.
#
# task-027 (2026-08-24) answered the question these four raised — keep extending the text
# scan limit by limit, replace it with a real shell parser, or stop and narrow the promise —
# with STOP: task-022's original criterion 2 promised the check fires for `any harness under
# tests/`, and that promise is narrowed here to the class actually covered (stated
# positively in the next paragraph), with (b)–(e) recorded as permanent rather than pending.
# The practical stake was, and remains, ZERO — no harness in this directory hides behind any
# of the four today, which the corpus assertions below fail loudly the moment one does. A
# real shell parser (the option that closes (b), (c) and (e) AS A CLASS, not one at a time)
# is DEFERRED as a possible future iteration and explicitly NOT rejected: three rounds of
# extending this text scan have each closed one class and revealed another, and that
# recurring cost was judged not worth paying again for a promise nothing in this repo
# currently needs.
#
# WHAT THIS SCANNER DOES COVER, stated positively rather than left to be inferred from the
# limits above: a trap that names the deleted path INLINE, built by a `cd` into a command
# substitution, on its OWN statement, at the START of that statement — however that
# statement is laid out across physical lines (one line, backslash-continued, or an open
# `$( … )` spanning lines) and however it is dressed in surrounding quotes or comments
# engineered to look like delimiters. That is the class task-022 shipped a fix for and the
# class this file protects; the promise stops there.
#
# The corpus assertions below fail loudly if the scanner stops finding traps at all, or if
# any harness ends mid-statement — the two failure modes that would let a blind spot pass as
# clean.
#
# Both are asserted NON-VACUOUSLY, over synthetic harnesses that do and do not carry each
# shape: a static check that passes on everything is indistinguishable from no check. The
# fixtures are emitted through `printf` rather than a heredoc on purpose — a heredoc puts
# its body at line start, where this file's own scanner would read the deliberately broken
# fixture lines as this file's own code.
#
# The three once-destructive harnesses are then exercised FOR REAL, in a throwaway copy of
# the checkout: run with a TMPDIR that does not exist, each must abort AND the copy must
# still be there afterwards. That is the actual regression, and it is why the copy is
# entered with `cd` first — an unfixed harness deletes its own cwd, so the blast radius
# has to be the copy.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TESTS="$REPO/tests"

die() { printf 'harness-temp-safety.test: %s\n' "$*" >&2; exit 2; }
[ -d "$TESTS" ] || die "no tests directory at $TESTS"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-temp-safety.XXXXXX")" || die "mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first."
# This file eats its own cooking, and it had to: the real macOS $TMPDIR ends in a slash,
# so the raw mktemp result above is `/var/folders/…/T//harness-temp-safety.xxxxxx`, while a
# path built from it and then normalised downstream comes back with one slash — and the
# "path is under TMPDIR" assertion below compared the two and failed. `pwd`, not `pwd -P`:
# the fixtures normalise logically too, and a physical path here would put /private/var
# against their /var. That is the same class of mismatch the two harnesses' `cd` exists to
# avoid, which is why criterion 3 forbids deleting it.
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# --- logical lines ------------------------------------------------------------
# logical_lines <file> — prints `<first-physical-line>:<statement>`, one per LOGICAL
# line, so a statement spanning several physical lines is joined into one before any
# predicate looks at it: a trailing backslash continues, and so does a `$( … )` still
# open at end of line.
#
# THIS FUNCTION IS THE FIX FOR A REAL HOLE, not a tidy-up. Without it,
#
#   TMP="$(
#     cd "$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")" && pwd
#   )"
#
# reads as three lines none of which carries the whole shape, so an anchored
# `^TMP=` match never reaches the `cd`/`mktemp` tokens on the second — and the
# assignment is exactly as destructive as the one-liner. The `bad-multiline` fixture
# below fails if this function is removed — measured, not assumed — which is the only
# thing that keeps the promise honest.
#
# AND COUNTING DELIMITERS IS ITSELF A BYPASS, WHICH THE FIRST CUT OF THIS FUNCTION SHIPPED.
# It counted every `$(` and every `)` on a line wherever they stood, so four lines of
# ordinary-looking shell disarmed the whole scanner:
#
#   X='$('                                        <- an opener inside a LITERAL
#   FTMP="$(cd "$(mktemp -d …)" && pwd)"          <- the offence, untouched
#   : # )                                         <- the closer inside a COMMENT
#   trap 'rm -rf "$FTMP"' EXIT
#
# The quoted `$(` opened a depth the offending line never closed; the commented `)` closed
# it one line later; all three joined into one statement beginning `X=`, and the `^FTMP=`
# selector never saw the assignment. Measured on that code: 2 findings for the offence
# alone, 0 for the same offence with those two lines around it. A check with a bypass is
# worse than a check with a blind spot, because the bypass is available to precisely the
# code it polices — so the delimiters are now read the way the shell reads them, by `lex`:
#   '…'   single quotes are inert entirely — no expansion, no escape, no comment;
#   "…"   inside double quotes `$(` still opens (bash expands it) but a bare `)` is
#         literal, and the quote it must return to is remembered per depth;
#   #     starts a comment only at word start, so `${X#f}` and `a#b` are not comments; the
#         comment is dropped from the statement text too, so a comment ABOUT this hazard
#         cannot read AS the hazard (that is why the old whole-comment-line skip is gone —
#         `lex` subsumes it and also handles the trailing case it missed);
#   \c    escapes, in code and in double quotes alike, so `\$(` is not an opener.
#
# WHERE IT STOPS, AND WHY THERE — measured, not assumed. Quote state is reset at every
# physical line boundary; only the substitution depth (and its `qs` stack) carries across
# lines. So a single-quoted string that really does span physical lines is read as code from
# its second line on. That happens in this directory: agent-tool-allowlist.test.sh:349 opens
# a four-line quoted fixture, and this normaliser reports it as four statements rather than
# one. It is harmless in the only direction that matters — extra statement boundaries are
# MORE places the predicates look, never fewer, and the whole-tree diff against the counting
# version reports the same offences either way.
#
# Carrying quote state across lines was tried and rejected on evidence. It is only coherent
# if an unterminated quote also CONTINUES the statement — lexing as though quotes span lines
# while splitting statements as though they do not is simply a third behaviour, and measured,
# it changes no finding anywhere. The coherent version does change one: it loses a LIVE
# offence. The `bad-heredoc` fixture below is a real one, an apostrophe in a heredoc body,
# and measured in a throwaway directory with a TMPDIR that does not exist it deleted every
# file there and exited 0. With quotes carried, that apostrophe holds the statement open
# across `EOF`, the assignment and the trap, and the scan reports 0 findings where this lexer
# reports 2. All that variant gets is the runaway alarm — which names neither the offence nor
# the variable — and it trips that same alarm on 2 of the 31 real harnesses here, which this
# lexer trips on none.
#
# The cost of the reset, written down because it is a real one: destructive-LOOKING text
# inside a multi-line single-quoted string is read as code and flagged, though it never
# executes. Nothing in this directory does that today. It is the direction chosen on purpose
# — a false positive is loud and a human clears it in a minute, while a false negative is a
# deleted checkout — but it IS a false positive, so it is stated rather than left to be
# discovered.
#
# Also not tracked, deliberately: heredoc bodies (a body line that looks like an opener
# over-joins — that is what the two tripwires below are for); backtick substitution, which
# is read as ordinary characters (measured: every backtick in this directory outside a
# comment is literal text inside a string, so nothing here turns on it); and `$((…))`, which
# needs no case of its own because its two closers net out against its one opener.
#
# It still does not parse, and its remaining error is over-joining rather than
# under-joining: it errs toward reading MORE text, not less. That direction is the safer one
# but it is not free — an over-join swallows the following statement, and an offending
# assignment that is no longer at the START of its statement is not matched. Both
# diagnostics below exist for exactly that failure mode, because it is the one way this
# function could hand the scanner a clean-looking file:
#   UNCLOSED-STATEMENT-AT-<n>   the file ended mid-statement — a join that never closed.
#   WIDE-STATEMENT-AT-<n>       a statement spanning more than MAXSPAN physical lines.
# MAXSPAN is 12 against a measured maximum of 7 real lines across this whole directory
# (pm-loop-launcher.test.sh:80, a five-stage pipeline of backslash continuations), so it
# is headroom for honest formatting and a tripwire for a runaway.
logical_lines() {
  awk -v maxspan=12 '
    # The single quote cannot appear in this program: the program itself is single-quoted.
    BEGIN { SQ = sprintf("%c", 39) }
    # lex(line) — walk the line as the shell would, maintaining the substitution depth in
    # `depth` and, per depth, the quoting to resume on close in `qs`. Returns the index
    # where a comment starts, or 0. `st`: 0 code, 1 inside SQ…SQ, 2 inside "…".
    function lex(line,   i, n, c, nx, pv, st) {
      st = 0; n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (st == 1) { if (c == SQ) st = 0; continue }
        if (c == "\\") { i++; continue }
        nx = substr(line, i + 1, 1)
        if (st == 2) {
          if (c == "\"") st = 0
          else if (c == "$" && nx == "(") { depth++; qs[depth] = 2; st = 0; i++ }
          continue
        }
        if (c == SQ)   { st = 1; continue }
        if (c == "\"") { st = 2; continue }
        pv = (i > 1) ? substr(line, i - 1, 1) : ""
        if (c == "#" && (i == 1 || pv ~ /[[:space:];&|(]/)) return i
        if (c == "$" && nx == "(") { depth++; qs[depth] = 0; i++; continue }
        # A closer with nothing open is a `case` pattern or an `f()` definition, not a
        # closer: depth stays at zero rather than going negative.
        if (c == ")" && depth > 0) { st = qs[depth]; depth-- }
      }
      return 0
    }
    {
      cut = lex($0)
      eff = (cut > 0) ? substr($0, 1, cut - 1) : $0
      blank = (eff ~ /^[[:space:]]*$/)
      # A blank or comment-only line starts nothing, but inside a statement it still counts
      # toward the span — otherwise a runaway join could hide behind a wall of comments.
      if (blank && buf == "") next
      if (buf == "") { start = FNR; buf = eff; span = 1 }
      else { span++; if (!blank) buf = buf " " eff }
      if (depth == 0 && eff !~ /\\$/) {
        print start ":" buf
        if (span > maxspan) print "0:WIDE-STATEMENT-AT-" start "-SPAN-" span
        buf = ""
      }
    }
    END { if (buf != "") { print start ":" buf; print "0:UNCLOSED-STATEMENT-AT-" start } }
  ' "$1"
}

# --- the scanner --------------------------------------------------------------
# scan <file> — prints one line per offence, class first, and nothing when clean.
# It reads the statements `logical_lines` produces, so the offence is reported at
# the true physical line the statement starts on.
scan() {
  local f="$1" stmts vars v asg
  stmts="$(logical_lines "$f")"
  # Which paths does a trap delete? Names only, both $V and ${V} spellings.
  vars="$(printf '%s\n' "$stmts" | grep 'trap' | grep -F 'rm -rf' \
          | grep -oE '\$\{?[A-Za-z_][A-Za-z_0-9]*\}?' | tr -d '${}' | sort -u)"
  for v in $vars; do
    # `^[0-9]+:` steps over the line number logical_lines prefixes.
    asg="$(printf '%s\n' "$stmts" | grep -E "^[0-9]+:[[:space:]]*$v=")"
    [ -n "$asg" ] || continue
    # (1) the destructive shape. The leading class keeps `cd` a word: without it,
    #     a variable or function ending in "cd" would read as the builtin.
    printf '%s\n' "$asg" | grep -E '(^|[^[:alnum:]_])cd[[:space:]]+"?\$\(' \
      | sed "s|^|NESTED-CD ${f##*/}:\$$v:|"
    # (2) a `cd` canonicalisation is only safe over a guarded mktemp.
    if grep -qE '(^|[^[:alnum:]_])cd[[:space:]]' <<<"$asg"; then
      printf '%s\n' "$asg" | grep -F 'mktemp' | grep -vF '||' \
        | sed "s|^|UNGUARDED ${f##*/}:\$$v:|"
    else
      # (3) task-017: the PLAIN form, no `cd` anywhere in the assignment — the class
      #     (2) check above never looks at, because it is gated on `cd` being present.
      #     `TMP="$(mktemp -d …)"` with no `||` still leaves TMP EMPTY on a failed
      #     mktemp, same as (2)'s failure, just without a `cd` on this exact statement
      #     to make it fatal by itself. That does not make it safe: a later statement
      #     built from the same trapped variable (a bare `cd "$TMP"`, a `-C "$TMP"`, a
      #     path glued onto it) inherits the empty value with nothing here to stop it.
      #     Measured 2026-08-27: 24 of the 36 harnesses surveyed carried exactly this
      #     shape with no accompanying `cd` on the assignment itself, and the fix
      #     shipped for it was the same `mktemp -d … || { …; exit 2; }` guard used by
      #     the ALREADY-CORRECT files this scanner has always accepted — a single `||`
      #     on the creating statement, checked as `grep -vF '||'` here exactly as (2)
      #     already does, is the whole fix. See tests/harness-temp-safety.test.sh
      #     fixtures `bad-plain`/`good-plain-mktemp` below for the non-vacuity proof.
      printf '%s\n' "$asg" | grep -F 'mktemp' | grep -vF '||' \
        | sed "s|^|BARE-MKTEMP ${f##*/}:\$$v:|"
    fi
  done
}

# --- the corpus ---------------------------------------------------------------
HARNESSES="$(find "$TESTS" -maxdepth 1 -type f -name '*.test.sh' | sort)"
n_harness="$(printf '%s\n' "$HARNESSES" | grep -c '.')"
ok "harnesses found to scan" "$([ "$n_harness" -ge 20 ] && echo "yes ($n_harness)" || echo "no ($n_harness)")" "yes ($n_harness)"

offences=""; trapped=0; unclosed=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Non-vacuity of the extractor itself: at least one harness must be seen to trap a
  # path, or every scan below is trivially clean because nothing was ever looked at.
  grep -qF 'rm -rf' <<<"$(grep -v '^[[:space:]]*#' "$f" | grep 'trap')" && trapped=$((trapped+1))
  # And the normaliser must not have run away: a file that ends mid-statement, or that
  # joins an implausible number of lines into one, has had text swallowed into a buffer —
  # which would read as clean for the wrong reason.
  grep -qE '^0:(UNCLOSED|WIDE)-STATEMENT-AT-' <<<"$(logical_lines "$f")" && unclosed=$((unclosed+1))
  out="$(scan "$f")"
  [ -n "$out" ] && offences="${offences}${out}
"
done <<EOF
$HARNESSES
EOF

ok "harnesses seen to trap-delete a path" "$([ "$trapped" -ge 10 ] && echo "yes ($trapped)" || echo "no ($trapped)")" "yes ($trapped)"
ok "harnesses whose statements ran away when joined" "$unclosed" 0

n_off="$(printf '%s' "$offences" | grep -c '.' || true)"
[ -n "$(printf '%s' "$offences" | tr -d '[:space:]')" ] && printf '%s' "$offences" | sed 's/^/        /'
ok "no trap-deleted path built by cd-ing into a substitution" \
   "$(printf '%s' "$offences" | grep -c '^NESTED-CD' || true)" 0
ok "no cd-canonicalised trap path from an unguarded mktemp" \
   "$(printf '%s' "$offences" | grep -c '^UNGUARDED' || true)" 0
ok "no bare unguarded mktemp for a trap-deleted path (task-017)" \
   "$(printf '%s' "$offences" | grep -c '^BARE-MKTEMP' || true)" 0
ok "no offence of any class under tests/" "$n_off" 0

# --- non-vacuity: the scanner must reject what it is for ----------------------
# Every fixture line goes out through printf. `FTMP` rather than `TMP` so a reader can
# tell fixture text from this file's own temp handling at a glance.
FX="$TMP/fx"; mkdir -p "$FX"

fx_head() { printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'; }
fx_trap() { printf 'trap %s EXIT\n' "'rm -rf \"\$FTMP\"'"; }

# (a) the destructive form, exactly as it stood in the two harnesses.
{ fx_head
  printf 'FTMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" && pwd)"\n'
  fx_trap; } > "$FX/bad-nested.test.sh"

# (b) two steps, but the mktemp is unguarded — a failed mktemp still reaches the cd.
{ fx_head
  printf 'FTMP="$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")"\n'
  printf 'FTMP="$(cd "$FTMP" && pwd)"\n'
  fx_trap; } > "$FX/bad-unguarded.test.sh"

# (c) the idiom this repo already uses in prune-worktrees.test.sh and
#     worktree-create-hook.test.sh: guard first, canonicalise second.
{ fx_head
  printf 'FTMP="$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" || { echo "fx: mktemp -d failed" >&2; exit 2; }\n'
  printf 'FTMP="$(cd "$FTMP" && pwd)"\n'
  fx_trap
  printf 'printf %s "$FTMP"\n' "'%s\\n'"; } > "$FX/good-twostep.test.sh"

# (d) task-017: THE PLAIN FORM, UNGUARDED — no `cd` anywhere, so classes (1) and (2)
#     above never look at it, but a failed `mktemp -d` still leaves FTMP EMPTY and
#     nothing here catches that before the trap is set. This used to be fixture
#     `good-plain`, on the theory that "no cd, so nothing to guard against" — refuted
#     by survey on 2026-08-27: 24 of 36 real harnesses in this directory carried exactly
#     this shape, with no cd anywhere in the creating statement, and every one of them
#     was still capable of leaving TMP empty for whatever ran next. Renamed to `bad-plain`
#     and now asserted BARE-MKTEMP, not clean.
{ fx_head
  printf 'FTMP="$(mktemp -d)"\n'
  fx_trap; } > "$FX/bad-plain.test.sh"

# (d') the fix for (d): the same plain form, `||`-guarded on the SAME statement the way
#     classes (1) and (2) already require of a `cd`-bearing assignment. No `cd` to check
#     the success of here, so the guard on the creating statement is the whole promise —
#     matching the idiom this task-017 fix applied to the 24 real harnesses.
{ fx_head
  printf 'FTMP="$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" || { echo "fx: mktemp -d failed" >&2; exit 2; }\n'
  fx_trap; } > "$FX/good-plain-mktemp.test.sh"

# (e) THE SAME DESTRUCTIVE ASSIGNMENT AS (a), WRAPPED ACROSS THREE LINES. Identical at
#     runtime, invisible to an anchored per-line grep: this is the fixture that fails
#     without `logical_lines`. Emitted with one `printf '%s\n' …` per fixture rather than
#     one printf per line, so the unbalanced `$(` stays inside a single physical line of
#     THIS file and cannot make this file's own normaliser join the surrounding code.
{ fx_head
  printf '%s\n' 'FTMP="$(' '  cd "$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" && pwd' ')"'
  fx_trap; } > "$FX/bad-multiline.test.sh"

# (f) and the other layout: one backslash continuation instead of an open substitution.
#     MEASURED, AND WORTH SAYING: the physical-line scanner caught THIS one already, by
#     luck — `cd`, `mktemp` and the assignment all land on its first line, and only the
#     `&& pwd` moved. It is kept as a regression guard that joining does not lose a shape
#     the old read happened to get, not as evidence for the normaliser.
{ fx_head
  printf '%s\n' 'FTMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" \' '  && pwd)"'
  fx_trap; } > "$FX/bad-continued.test.sh"

# (g) the control that keeps (e) and (f) from being "joining flags everything": the SAFE
#     two-step idiom, also wrapped. Joining puts the `||` abort on the same statement as
#     the `mktemp`, which is precisely why this one must come out clean.
{ fx_head
  printf '%s\n' 'FTMP="$(' '  mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX"' ')" || { echo "fx: mktemp -d failed" >&2; exit 2; }' 'FTMP="$(cd "$FTMP" && pwd)"'
  fx_trap; } > "$FX/good-multiline.test.sh"

# (h) THE BYPASS, and the reason `lex` exists. The offence of (a) verbatim, with two lines
#     of perfectly ordinary shell around it: a `$(` inside a single-quoted string and a `)`
#     inside a comment. Against the delimiter-COUNTING normaliser the quoted opener held a
#     depth open past the offending line and the commented closer shut it one line later,
#     joining all three into a single statement beginning `X=` — so the `^FTMP=` selector
#     never saw the assignment and the file scanned CLEAN. Measured on that code, over
#     these exact bytes: 0 findings here against 2 for (a), the same assignment with no
#     scaffolding. Nothing about the runtime differs; only whether the check looks.
{ fx_head
  printf '%s\n' "X='\$('" 'FTMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" && pwd)"' ': # )'
  fx_trap; } > "$FX/bad-bypass.test.sh"

# (i) the other direction, so `lex` is not merely "flag more": a SAFE harness carrying the
#     same delimiters in the same inert places. It must stay clean — and, asserted
#     separately below, its two noisy lines must stay TWO statements, because the counting
#     version joined them, and an over-join is how the statement that FOLLOWS gets hidden.
{ fx_head
  printf 'FTMP="$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" || { echo "fx: mktemp -d failed" >&2; exit 2; }\n'
  printf 'FTMP="$(cd "$FTMP" && pwd)"\n'
  printf '%s\n' "echo 'a \$( inside a literal'" 'echo "a ) inside a string"  # and a ) in a comment'
  fx_trap; } > "$FX/good-noisy.test.sh"

# (j) A LIVE offence standing behind an apostrophe in a heredoc body — and the fixture that
#     pins the line-boundary decision taken at `logical_lines`. Destructive for real, not by
#     analogy: measured in a throwaway directory with a TMPDIR that does not exist, this file
#     deleted every entry there and exited 0. The counting version catches it too, so it is
#     NOT evidence for `lex`; it is a guard against the refactor that looks like an
#     improvement — carrying quote state across physical lines, where `don't` holds the
#     statement open across the assignment and the trap and the scan reports NOTHING
#     (measured: 0 findings against 2). A decision deserves a test, not just a paragraph.
{ fx_head
  printf '%s\n' 'cat <<EOF' "don't" 'EOF' 'FTMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" && pwd)"'
  fx_trap; } > "$FX/bad-heredoc.test.sh"

for k in bad-nested bad-unguarded bad-plain bad-multiline bad-continued bad-bypass bad-heredoc good-twostep good-plain-mktemp good-multiline good-noisy; do
  o="$(scan "$FX/$k.test.sh")"
  case "$k" in
    bad-nested)
      ok "fixture $k is flagged NESTED-CD"  "$(printf '%s' "$o" | grep -c '^NESTED-CD' || true)" 1 ;;
    bad-unguarded)
      ok "fixture $k is flagged UNGUARDED"  "$(printf '%s' "$o" | grep -c '^UNGUARDED' || true)" 1
      ok "fixture $k is not flagged NESTED-CD" "$(printf '%s' "$o" | grep -c '^NESTED-CD' || true)" 0 ;;
    bad-plain)
      # task-017: no `cd` anywhere in the statement — must be caught as BARE-MKTEMP,
      # not as either cd-shaped class, or the fix is a no-op on the shape it targets.
      ok "fixture $k is flagged BARE-MKTEMP" "$(printf '%s' "$o" | grep -c '^BARE-MKTEMP' || true)" 1
      ok "fixture $k is not flagged NESTED-CD" "$(printf '%s' "$o" | grep -c '^NESTED-CD' || true)" 0
      ok "fixture $k is not flagged UNGUARDED" "$(printf '%s' "$o" | grep -c '^UNGUARDED' || true)" 0 ;;
    bad-multiline|bad-continued)
      # The whole point: the same shape, a different physical layout, still caught —
      # and reported at the line the statement STARTS on, which is line 3 in both.
      ok "fixture $k is flagged NESTED-CD"  "$(printf '%s' "$o" | grep -c '^NESTED-CD' || true)" 1
      ok "fixture $k is flagged UNGUARDED"  "$(printf '%s' "$o" | grep -c '^UNGUARDED' || true)" 1
      ok "fixture $k is reported at its first physical line" \
         "$(printf '%s' "$o" | grep -c ':3:' || true)" 2 ;;
    bad-bypass|bad-heredoc)
      # The same two classes as (a) — and reported at the assignment's OWN physical line,
      # not at the line of the literal or the heredoc body that used to swallow it.
      case "$k" in bad-bypass) at=4 ;; bad-heredoc) at=6 ;; esac
      ok "fixture $k is flagged NESTED-CD"  "$(printf '%s' "$o" | grep -c '^NESTED-CD' || true)" 1
      ok "fixture $k is flagged UNGUARDED"  "$(printf '%s' "$o" | grep -c '^UNGUARDED' || true)" 1
      ok "fixture $k is reported at line $at, where the assignment is" \
         "$(printf '%s' "$o" | grep -c ":$at:" || true)" 2
      # And it is caught by SEEING it, not by tripping a diagnostic: a bypass that merely
      # set off the runaway alarm would still leave the offence unnamed.
      ok "fixture $k trips no runaway diagnostic" \
         "$(logical_lines "$FX/$k.test.sh" | grep -cE '^0:(UNCLOSED|WIDE)-STATEMENT-AT-' || true)" 0 ;;
    good-*)
      ok "fixture $k is clean" "$(printf '%s' "$o" | grep -c '.' || true)" 0 ;;
  esac
done

# --- non-vacuity: the normaliser's own two tripwires --------------------------
# The corpus asserts that no harness trips either marker, which is an assertion about
# nothing until the markers are shown to fire. So they are fired: a statement left open
# at end of file, and one joined past MAXSPAN.
# These two fixtures need an opener with NO closer, which no physical line of this file
# may carry — an unbalanced `$(` here would over-join this file exactly as described
# above, and the first draft of this block did: it swallowed 19 lines, and the WIDE
# tripwire caught it. So the `$` is passed as an argument and the line reads `%s(`,
# leaving no `$(` sequence in this file at all.
{ printf '%s\n' '#!/usr/bin/env bash'; printf 'FTMP="%s(mktemp -d\n' '$'; } \
  > "$FX/unclosed.test.sh"
ok "an unclosed statement is reported" \
   "$(logical_lines "$FX/unclosed.test.sh" | grep -c '^0:UNCLOSED-STATEMENT-AT-' || true)" 1

{ printf '%s\n' '#!/usr/bin/env bash'; printf 'FTMP="%s(\n' '$'
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '  echo %s\n' "$i"; done
  printf '%s\n' ')"'; } > "$FX/wide.test.sh"
ok "a statement joined past MAXSPAN is reported" \
   "$(logical_lines "$FX/wide.test.sh" | grep -c '^0:WIDE-STATEMENT-AT-' || true)" 1

# And the converse of the bypass: `lex` must not have bought its accuracy by joining LESS
# than the shell would, nor keep joining on delimiters that are inert. The safe-but-noisy
# fixture's two `echo` lines are two statements; the counting version reported one, because
# the `$(` inside the literal held the first open across the second.
ok "inert delimiters do not join two statements" \
   "$(logical_lines "$FX/good-noisy.test.sh" | grep -c '^[0-9][0-9]*:echo ' || true)" 2

# --- the guarded idiom, at runtime, across the three TMPDIR states ------------
IDIOM="$FX/good-twostep.test.sh"

out="$(env -u TMPDIR bash "$IDIOM" 2>&1)"; rc=$?
ok "TMPDIR unset: exits 0"            "$rc" 0
ok "TMPDIR unset: prints a temp dir"  "$([[ "$out" == /* ]] && echo yes || echo no)" yes

REAL="$TMP/real-tmpdir"; mkdir -p "$REAL"
# Trailing slash on purpose: it is why the `cd`+`pwd` normalisation exists at all, so the
# criterion "the macOS reason the cd exists is preserved" is asserted, not assumed.
out="$(TMPDIR="$REAL/" bash "$IDIOM" 2>&1)"; rc=$?
ok "TMPDIR real (trailing slash): exits 0"        "$rc" 0
ok "TMPDIR real: path is under it"               "$([[ "$out" == "$REAL"/* ]] && echo yes || echo no)" yes
ok "TMPDIR real: path is normalised (no '//')"   "$([[ "$out" != *//* ]] && echo yes || echo no)" yes

ABSENT="$TMP/no-such-tmpdir"
out="$(TMPDIR="$ABSENT" bash "$IDIOM" 2>&1)"; rc=$?
ok "TMPDIR absent: aborts non-zero"   "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
ok "TMPDIR absent: says why"          "$(grep -qi 'mktemp' <<<"$out" && echo yes || echo no)" yes
ok "TMPDIR absent: created nothing"   "$([ -e "$ABSENT" ] && echo no || echo yes)" yes

# --- the real regression, in a throwaway copy of the checkout -----------------
# The three harnesses that carried the destructive form, run the way that destroyed a
# verification tree: cwd inside a checkout, TMPDIR naming a directory that is not there.
# An unfixed harness deletes its cwd, so the cwd is a copy and the copy is rebuilt for
# each one.
#
# `moved-template` is the third because THIS CHECK FOUND IT, not a human: it landed on main
# in parallel, carrying the UNGUARDED shape (`mktemp -d` with no `||`, then
# `cd "$TMP" && pwd -P`), and measured on a throwaway clone of main it deleted every one of
# the 17 top-level entries of its own checkout while reporting `pass=53 fail=0` and exiting
# 0. So the check turned `main` RED the moment it merged, on a file it did not ship.
#
# Credit where it is due, because this file is about not overclaiming: the LINE-WISE version
# caught this one too — the offending assignment sits on a single physical line. Logical
# lines are not what found it. What the join changed here is only the reported location,
# from line 4 (a position in a comment-stripped copy) to line 41, the line a human opens.
#
# NEVER copy `.` wholesale here. TMPDIR may legitimately sit INSIDE the repo — this
# instance tells its agents to isolate their scratch space, which is the very habit that
# found this bug — and a copy of `.` that contains its own destination recurses until the
# disk fills. Measured while writing this file: a `tar cf - .` reached 247 levels of
# `checkout/.scratch/tmp/checkout/…` in ten minutes, and the result was too deep for
# `rm -rf` to remove. So each top-level entry is copied by name, and any entry that is
# the fixture root or contains it is skipped.
fresh_copy() { # <dest>
  local dest="$1" e
  rm -rf "$dest"; mkdir -p "$dest" || return 1
  for e in "$REPO"/*; do
    [ -e "$e" ] || continue
    case "$TMP" in "$e"|"$e"/*) continue ;; esac
    cp -R "$e" "$dest/" || return 1
  done
  [ -f "$REPO/.gitignore" ] && cp "$REPO/.gitignore" "$dest/"
  [ -d "$REPO/.claude-plugin" ] && cp -R "$REPO/.claude-plugin" "$dest/"
  return 0
}

for h in board-renderers snapshot moved-template; do
  COPY="$TMP/checkout-$h"
  fresh_copy "$COPY" || die "could not copy the checkout for $h"
  ok "$h: fixture copy is a checkout" \
     "$([ -f "$COPY/tests/$h.test.sh" ] && [ -f "$COPY/plugin/scripts/init-bundle.sh" ] && echo yes || echo no)" yes
  # Capped, because an UNFIXED harness does not abort: it sets TMP to its own cwd and
  # runs its whole suite before the trap deletes it, which is minutes. A test that HANGS
  # is worse than one that fails, so a breach is reported as rc 124 — and the assertion
  # below demands exactly 2 (this directory's refusal status), so a killed run cannot
  # pass by having had its trap skipped.
  LOG="$TMP/run-$h.log"; : > "$LOG"
  ( cd "$COPY" && TMPDIR="$COPY/no-such-tmpdir" bash "tests/$h.test.sh" >"$LOG" 2>&1 ) &
  pid=$!; waited=0
  # THE BOUND GOES ON THE CHILD: the poll below is OURS, and an unfixed harness in there
  # runs its whole suite for minutes — so if this harness is killed, that run continues
  # reparented to pid 1 (`CONVENTIONS.md` → "Anything you background must be reaped by
  # something that outlives YOU"). The watchdog is a sibling and `sleep` bounds it; 90s is
  # past the 60s poll, so it only ever matters when we are no longer here.
  ( sleep 90; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wd=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rc=124
  else
    wait "$pid"; rc=$?
  fi
  kill "$wd" 2>/dev/null || true
  out="$(cat "$LOG")"
  ok "$h: TMPDIR absent ⇒ exits 2, the refusal status"  "$rc" 2
  ok "$h: TMPDIR absent ⇒ the checkout survives"  "$([ -f "$COPY/tests/$h.test.sh" ] && echo yes || echo no)" yes
  # The harness's OWN refusal line, not mktemp's stderr. A failing `mktemp -d` prints
  # "mktemp: …: No such file or directory" all by itself, so grepping for `mktemp` alone
  # passes just as well on the destructive version — measured, it did.
  ok "$h: TMPDIR absent ⇒ refuses in its own voice" \
     "$(grep -qE "^$h\.test:.*mktemp" <<<"$out" && echo yes || echo no)" yes
  # And the reason the cd exists is still in the file: a "fix" that deleted the
  # canonicalisation would silently break the path assertions these harnesses rest on.
  ok "$h: still canonicalises through cd+pwd" \
     "$(grep -qE 'cd[[:space:]]+"\$TMP"[[:space:]]*&&[[:space:]]*pwd' "$COPY/tests/$h.test.sh" && echo yes || echo no)" yes
  rm -rf "$COPY"
done

# --- task-017: the BARE-MKTEMP class, at runtime ------------------------------
# The three harnesses above all carried a `cd` that made a failed mktemp SELF-DESTRUCTIVE
# on its own. The far more common shape in this directory — surveyed 2026-08-27 at 24 of
# 36 harnesses, none of which cd anywhere in the creating statement — never touches its
# own cwd, so a failed mktemp cannot delete the checkout. It can still leave TMP EMPTY
# with nothing to catch it, and every "$TMP/…" path built afterwards silently resolves to
# a filesystem-root path instead of raising — which is criterion 2's actual target: a
# harness that runs its whole suite to completion and reports a false green rather than
# refusing. `banner-board-line.test.sh` stands in for the class here because it is small,
# offline (no network, no gh, no python3) and fast, so this regression stays cheap.
# (Picked over the plainer `TMP="$(mktemp -d)"` form some harnesses use: on macOS that
# call ignores a nonexistent TMPDIR and falls back to the real system temp directory, so
# a template-less harness cannot be driven to a failing mktemp this way at all — measured
# while writing this. `banner-board-line.test.sh` gives mktemp an explicit
# "${TMPDIR:-/tmp}/…" template, the same shape the three cd-bearing harnesses above use,
# so the bogus-TMPDIR technique actually reaches it.)
for h in banner-board-line; do
  COPY="$TMP/checkout-$h"
  fresh_copy "$COPY" || die "could not copy the checkout for $h"
  ok "$h: fixture copy is a checkout" \
     "$([ -f "$COPY/tests/$h.test.sh" ] && [ -f "$COPY/plugin/scripts/init-bundle.sh" ] && echo yes || echo no)" yes
  LOG="$TMP/run-$h.log"; : > "$LOG"
  ( cd "$COPY" && TMPDIR="$COPY/no-such-tmpdir" bash "tests/$h.test.sh" >"$LOG" 2>&1 ) &
  pid=$!; waited=0
  # THE BOUND GOES ON THE CHILD: the poll below is OURS, and an unfixed harness in there
  # runs its whole suite for minutes — so if this harness is killed, that run continues
  # reparented to pid 1 (`CONVENTIONS.md` → "Anything you background must be reaped by
  # something that outlives YOU"). The watchdog is a sibling and `sleep` bounds it; 90s is
  # past the 60s poll, so it only ever matters when we are no longer here.
  ( sleep 90; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wd=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rc=124
  else
    wait "$pid"; rc=$?
  fi
  kill "$wd" 2>/dev/null || true
  out="$(cat "$LOG")"
  ok "$h: TMPDIR absent ⇒ exits 2, the refusal status"  "$rc" 2
  # The actual regression this criterion names: a killed-early run cannot have reached
  # its own "pass=N fail=0" summary line, which is what an unfixed harness prints while
  # having quietly run in the wrong place.
  ok "$h: TMPDIR absent ⇒ never prints a false-green summary" \
     "$(printf '%s\n' "$out" | grep -c '^pass=[0-9]*[[:space:]]fail=0$' || true)" 0
  ok "$h: TMPDIR absent ⇒ refuses in its own voice" \
     "$(grep -qE "^$h\.test:.*mktemp" <<<"$out" && echo yes || echo no)" yes
  rm -rf "$COPY"
done

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
