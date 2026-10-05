#!/usr/bin/env bash
#
# background-teardown.test.sh — the reader for `CONVENTIONS.md` → "Anything you background
# must be reaped by something that outlives YOU", and the reader for the `/loopd:welcome check`
# row that reports orphaned processes under `worktreeRoot`.
#
# WHY THERE IS A TEST AT ALL. The rule this file guards REPLACED a rule that was already in
# `CONVENTIONS.md` and did not stop the failure: the dev-server teardown bullet named
# servers, so it had nothing to say about the ten `(while :; do :; done) &` spinners an agent
# started on 2026-08-31 to reproduce a flaky suite. Its shell died before the `kill` line ran
# and 34 children survived across three batches, every one with `ppid 1`, at ~24% of a core
# each — load average 310, 0% idle, found in Activity Monitor by a human. Prose did not stop
# it and a second, wider piece of prose would not either.
#
# THE THREE THINGS ASSERTED HERE, and none of them is the rule's wording for its own sake:
#
#   1. THE SCANNER (§2-§4). A background spawn in this repo's own machinery must carry a
#      bound, or be allowlisted with a stated reason and a PINNED COUNT. Both directions are
#      asserted against fixtures — an unbounded spawn is flagged and a bounded one is not —
#      because a one-direction assertion passes on an empty repo.
#   2. THE MEASURED CASE ITSELF (§6). A fixture parent spawns a child, is SIGKILLed before
#      its own kill line, and the child is verified to be reparented to `ppid 1` — that is
#      the incident, reproduced. The bounded form from `CONVENTIONS.md` is then run through
#      exactly the same SIGKILL and its child is verified to die anyway, on its own, with
#      no parent left to help it. The unbounded run is what makes the bounded one non-vacuous.
#   3. THE CHECK ROW (§7). `/loopd:welcome check` reports an orphan whose cwd is under
#      `worktreeRoot` — asserted against a REAL synthetic orphan, not only against a clean
#      machine — and, on every path where it cannot answer, says so instead of reporting
#      zero. A false zero here would be worse than no row at all.
#
# WHAT THE SCANNER PROMISES, AND WHAT IT DOES NOT. It cannot decide whether an arbitrary
# backgrounded command terminates — that is the halting problem with a `&` in front of it —
# so it asks for the shape instead: a bound ON the spawn (`timeout`, a `sleep` that IS the
# child, a deadline computed from `date +%s`), or a detached watchdog beside it. Everything
# else is reported, and a legitimate one-shot is answered with an allowlist entry that has to
# say why. Known blind spots, stated rather than discovered later: a `&` at the end of a
# QUOTED STRING reads as a spawn (there is none in this repo today); `cmd &# c` with no space
# before the comment is missed; and a bound more than three executable lines away from its
# spawn is not seen, which is deliberate — a bound a reader cannot see beside the spawn is
# not much of a bound.
#
# ONE SCANNER, USED TWICE. The repo scan and every fixture go through the same awk program
# written to $TMP once, so this file cannot certify the repo with logic the fixtures never
# exercised (`knowledge/findings/a-widened-check-is-vacuous-until-you-pin-what-the-old-one-missed`).
#
# EVERYTHING THIS HARNESS STARTS IS ITSELF BOUNDED — it would be a poor advertisement
# otherwise. Every child it spawns is a `sleep` with a fixed argument or carries a watchdog,
# so an interrupted run leaves nothing behind that outlives its own bound; the EXIT trap that
# also kills them is the ADDITION the rule permits, never the whole answer.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
AIB="$REPO/plugin/scripts/welcome.sh"
for f in "$CONV" "$AIB"; do
  [ -f "$f" ] || { echo "background-teardown.test: missing $f" >&2; exit 2; }
done

# Guarded first, canonicalised second — the two-step form `tests/harness-temp-safety.test.sh`
# requires, because a failed `mktemp` leaves the variable EMPTY and every "$TMP/…" path built
# from it silently resolves to a filesystem-root path.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/background-teardown.XXXXXX")" || {
  echo "background-teardown.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
case "$TMP" in /*) ;; *) echo "background-teardown.test: mktemp returned a relative path" >&2; exit 2 ;; esac
# `lsof` reports a RESOLVED cwd and macOS symlinks /var and /tmp, so an unresolved prefix
# would make §7's orphan invisible to the very check under test — a pass for the wrong reason.
TMP="$(cd "$TMP" && pwd -P)"

REAP=""
reap() { local p; for p in $REAP; do kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; REAP=""; }
trap 'reap; rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
# Assertions run only on SOME hosts or only while a mutation anchor still matches. Each such
# block adds its own count here, so the pin at the end of the file measures the UNCONDITIONAL
# body and does not move with the platform.
EXTRA=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# SKIPPED is printed, never counted as caught: a mutation whose anchor has moved must not
# look like a mutation that was detected
# (knowledge/findings/inspection-is-not-verification-on-a-resumed-run).
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
# `grep -c`, never `printf … | grep -q`: under `set -o pipefail` a `-q` exits at the first
# match and the writer's EPIPE becomes the pipeline's status, so the assertion inverts
# exactly when it is true (knowledge/findings/grep-q-under-pipefail-reports-a-match-as-a-failure).
saw() { # <haystack> <fixed string> -> yes|no
  [ "$(printf '%s\n' "$1" | grep -cF -- "$2")" -gt 0 ] && echo yes || echo no
}
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }

# =======================================================================================
# THE SCANNER — one implementation, used for the repo and for every fixture
# =======================================================================================
SCANNER="$TMP/scan.awk"
cat > "$SCANNER" <<'AWK'
# Prints "<file>:<line>: <text>" for every background spawn that carries no bound.
function stripped(l) { sub(/^[ \t]+/, "", l); return l }
function is_comment(l) { l = stripped(l); return (substr(l, 1, 1) == "#") }
# A SPAWN: a logical line ending in a single `&` (with or without a trailing comment), or one
# that detaches explicitly. `[^&|>]` before it keeps `&&`, `|&` and `>&2` out; requiring
# WHITESPACE before a trailing comment keeps HTML character references (`&#8203;`) out, which
# is not hypothetical — four lines in this repo carry one.
function is_spawn(l) {
  if (l ~ /(^|[^&|>])&[ \t]*$/)        return 1
  if (l ~ /(^|[^&|>])&[ \t]+#/)        return 1
  if (l ~ /(^|[ \t;(&|])nohup[ \t]/)   return 1
  if (l ~ /(^|[ \t;(&|])setsid[ \t]/)  return 1
  return 0
}
# A loop with no exit condition DISQUALIFIES a `sleep` from counting as a bound: in
# `while :; do sleep 1; done` the sleep is a pause inside something that never ends. Failing
# in this direction over-reports, which is the safe one — an allowlist entry answers it.
function endless_loop(l) {
  if (l ~ /while[ \t]*:/)                 return 1
  if (l ~ /while[ \t]+true/)              return 1
  if (l ~ /until[ \t]+false/)             return 1
  if (l ~ /while[ \t]*\[[ \t]*1[ \t]*\]/) return 1
  if (l ~ /for[ \t]*\(\([ \t]*;[ \t]*;/)  return 1
  return 0
}
function has_timeout(l) { return (l ~ /(^|[^A-Za-z0-9_])g?timeout[ \t]+[0-9$"]/) }
function has_sleep(l)   { return (l ~ /(^|[^A-Za-z0-9_])sleep[ \t]+[0-9$"]/) }
function has_deadline(l) {
  if (l ~ /date[ \t]+\+%s/)                            return 1
  if (l ~ /(^|[^A-Za-z0-9_])SECONDS([^A-Za-z0-9_]|$)/) return 1
  return 0
}
function bound_here(l) {
  if (has_timeout(l))                   return 1
  if (has_deadline(l))                  return 1
  if (has_sleep(l) && !endless_loop(l)) return 1
  return 0
}
# A DETACHED WATCHDOG: itself backgrounded, waits out a fixed bound, then kills. It has to be
# backgrounded — a `sleep` in a poll loop the PARENT runs is the parent-dependent teardown
# this whole rule exists to reject, and it would otherwise read as a bound.
function watchdog(l) { return (is_spawn(l) && (has_sleep(l) || has_timeout(l)) && l ~ /kill/) }
# A watchdog must not inherit the caller's stdout. Killing `( sleep N; … ) &` kills the
# SUBSHELL and leaves the `sleep`, which then holds any pipe it inherited open for the rest of
# the bound — and this repo's CI reads every harness through `out="$(bash "$f" 2>&1)"`, so a
# finished harness reads as a hang. Measured: 15 seconds of work, 99 seconds of pipe.
function stdout_closed(l) { return (l ~ /\)[ \t]*>[ \t]*\/dev\/null/) }
{
  logical = $0; first = FNR
  while (logical ~ /\\$/) {
    sub(/\\$/, "", logical)
    if ((getline nxt) <= 0) break
    logical = logical " " stripped(nxt)
  }
  n++; L[n] = logical; LN[n] = first; C[n] = is_comment(logical)
}
END {
  # MODE `loud`: the watchdogs themselves, and whether they let go of the caller's stdout.
  if (mode == "loud") {
    for (i = 1; i <= n; i++) {
      if (C[i]) continue
      if (!watchdog(L[i])) continue
      if (stdout_closed(L[i])) continue
      printf "%s:%d: %s\n", FILENAME, LN[i], stripped(L[i])
    }
    exit
  }
  for (i = 1; i <= n; i++) {
    if (C[i]) continue
    if (!is_spawn(L[i])) continue
    if (bound_here(L[i])) continue
    seen = 0; bounded = 0
    for (j = i + 1; j <= n && seen < 3; j++) {
      if (C[j]) continue
      if (stripped(L[j]) == "") continue
      seen++
      if (watchdog(L[j])) { bounded = 1; break }
    }
    if (bounded) continue
    printf "%s:%d: %s\n", FILENAME, LN[i], stripped(L[i])
  }
}
AWK

scan() { # <file>... -> one "<file>:<line>: <text>" line per unbounded spawn
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    awk -f "$SCANNER" "$f"
  done
}
scan_loud() { # <file>... -> one line per watchdog that keeps the caller's stdout
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    awk -v mode=loud -f "$SCANNER" "$f"
  done
}
count_lines() { printf '%s' "$1" | grep -c . || true; }

# =======================================================================================
# THE SCOPE — this repo's own scripts and harnesses, and it must not be empty
# =======================================================================================
# A directory-wide claim on zero files is the vacuous pass this whole file exists to avoid,
# so each glob is counted and asserted non-empty before anything is concluded from it.
IN_SCOPE=()
while IFS= read -r f; do [ -n "$f" ] && IN_SCOPE+=("$f"); done <<SCOPE
$(cd "$REPO" && {
   find plugin/scripts -name '*.sh' -type f
   find plugin/hooks -name '*.sh' -type f 2>/dev/null
   find scripts -name '*.sh' -type f 2>/dev/null
   find tests -name '*.sh' -type f
   ls install.sh upgrade.sh 2>/dev/null
 } | sort)
SCOPE

echo "== 1. the scope is real =="
N_SCOPE="$(printf '%s\n' ${IN_SCOPE+"${IN_SCOPE[@]}"} | grep -c . || true)"
ok "the scan covers files at all"                        "$([ "$N_SCOPE" -ge 60 ] && echo yes || echo no)" yes
n_mach=0; n_harness=0
for f in ${IN_SCOPE+"${IN_SCOPE[@]}"}; do
  case "$f" in plugin/*) n_mach=$((n_mach+1)) ;; tests/*) n_harness=$((n_harness+1)) ;; esac
done
ok "…including this repo's machinery"                    "$([ "$n_mach" -ge 20 ] && echo yes || echo no)" yes
ok "…and its harnesses"                                  "$([ "$n_harness" -ge 40 ] && echo yes || echo no)" yes
ok "…and the harness under test is in scope (it spawns)" "$(yn grep -qx "tests/background-teardown.test.sh" <<<"$(printf '%s\n' ${IN_SCOPE+"${IN_SCOPE[@]}"})")" yes

# =======================================================================================
echo
echo "== 2. the scanner flags an unbounded spawn — every shape of one =="
# =======================================================================================
# EVERY FIXTURE LINE GOES OUT THROUGH printf, the idiom this directory already uses: a
# literal `foo &` in this file would be scanned as this repo's own machinery in §4 and would
# have to be allowlisted, which is a fixture changing the thing it is a fixture for.
FX="$TMP/fx"; mkdir -p "$FX"
fx_head() { printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'; }

{ fx_head; printf '( while :; do :; done ) %s\n' '&'; } > "$FX/bad-spinner.sh"
{ fx_head; printf 'nohup ./server >/dev/null 2>%s1 %s\n' '&' '&'; } > "$FX/bad-nohup.sh"
{ fx_head; printf 'setsid ./thing %s\n' '&'; } > "$FX/bad-setsid.sh"
{ fx_head; printf 'bash ./one-shot.sh %s   # started, and then hoped for\n' '&'; } > "$FX/bad-comment.sh"
# The parent-dependent poll: a `sleep` this shell runs is not a bound on the child, and this
# is the shape most of the real spawns in this repo have.
{ fx_head; printf './thing %s\np=$!\n' '&'
  printf 'while kill -0 "$p" 2>/dev/null && [ "$w" -lt 60 ]; do sleep 1; w=$((w+1)); done\n'
  printf 'kill "$p" 2>/dev/null\n'; } > "$FX/bad-poll.sh"
# A watchdog four executable lines away: out of the window, on purpose — a bound a reader
# cannot see beside the spawn is not much of a bound.
{ fx_head; printf './thing %s\np=$!\n' '&'; printf 'a=1\nb=2\nc=3\n'
  printf '( sleep 30; kill "$p" 2>/dev/null ) >/dev/null 2>%s1 %s\n' '&' '&'; } > "$FX/bad-far-watchdog.sh"
{ fx_head; printf '( while :; do sleep 1; done ) %s\n' '&'; } > "$FX/bad-sleep-in-loop.sh"
# The same unbounded spawn wrapped over two physical lines: identical at runtime, invisible
# to a scan that does not join continuations.
{ fx_head; printf 'bash ./thing \\\n  --flag %s\n' '&'; } > "$FX/bad-continuation.sh"

for b in bad-spinner bad-nohup bad-setsid bad-comment bad-poll bad-far-watchdog \
         bad-sleep-in-loop bad-continuation; do
  ok "flagged: $b"  "$(count_lines "$(scan "$FX/$b.sh")")" 1
done

# =======================================================================================
echo
echo "== 3. …and does NOT flag a bounded one, nor anything that is not a spawn =="
# =======================================================================================
# The other direction, which is the half that stops this being a ban on backgrounding. A
# one-direction assertion passes on an empty repo; this pair is what makes the scan a claim.
{ fx_head; printf 'timeout 30 ./thing %s\n' '&'; } > "$FX/good-timeout.sh"
{ fx_head; printf '( exec sleep 300 ) %s\n' '&'; } > "$FX/good-sleep-child.sh"
{ fx_head; printf './thing %s\np=$!\n' '&'
  printf '( sleep 120; kill "$p" 2>/dev/null ) >/dev/null 2>%s1 %s\n' '&' '&'; } > "$FX/good-watchdog.sh"
# The far edge of the window: third executable line after the spawn, still visible.
{ fx_head; printf './thing %s\np=$!\nlog=x\n' '&'
  printf '( sleep 120; kill "$p" 2>/dev/null ) >/dev/null 2>%s1 %s\n' '&' '&'; } > "$FX/good-watchdog-edge.sh"
{ fx_head; printf '( end=$(( $(date +%%s) + 5 )); while [ "$(date +%%s)" -lt "$end" ]; do :; done ) %s\n' '&'
  } > "$FX/good-deadline.sh"
# Not spawns at all. Each of these ends in an `&` or contains one, and a needle that cannot
# tell them apart reports the whole repo and gets switched off within a week.
{ fx_head; printf 'a %s%s b\n' '&' '&'; printf 'echo x >%s2\n' '&'; printf 'cmd 2>%s1\n' '&'
  printf '# a comment that ends in an %s\n' '&'
  printf 'case "$x" in *%s) : ;; esac\n' '&'
  printf "printf '%%s' '%s#8203;'\\n" '&'; } > "$FX/good-not-spawns.sh"

for g in good-timeout good-sleep-child good-watchdog good-watchdog-edge good-deadline \
         good-not-spawns; do
  ok "not flagged: $g"  "$(count_lines "$(scan "$FX/$g.sh")")" 0
done

# THE SECOND CLASS, and it is not cosmetic: a watchdog that keeps the caller's stdout turns a
# finished job into a hang, because the `sleep` survives the subshell being killed and holds
# the pipe. This repo's CI reads every harness through a command substitution, so the bound
# becomes the runtime. Measured at 99 seconds for 15 seconds of work while writing this.
{ fx_head; printf './thing %s\np=$!\n' '&'
  printf '( sleep 120; kill "$p" 2>/dev/null ) %s\n' '&'; } > "$FX/loud-watchdog.sh"
ok "a watchdog holding the caller's stdout is flagged" \
  "$(count_lines "$(scan_loud "$FX/loud-watchdog.sh")")" 1
ok "…and the same one redirected is not"              \
  "$(count_lines "$(scan_loud "$FX/good-watchdog.sh")")" 0
ok "…while the loud one still counts as BOUNDED"      \
  "$(count_lines "$(scan "$FX/loud-watchdog.sh")")" 0

# THE SHIPPED SNIPPET PASSES ITS OWN SCANNER. `CONVENTIONS.md` tells every agent to write
# this shape; a repo whose own reader would flag it is telling them two different things.
SNIP="$TMP/bg-bounded.sh"
awk '
  /^[ \t]*```/ { if (inb) { if (buf ~ /bg_bounded\(\)/) printf "%s", buf; inb = 0; buf = ""; next } else { inb = 1; next } }
  inb { line = $0; sub(/^  /, "", line); buf = buf line "\n" }
' "$CONV" > "$SNIP"
ok "CONVENTIONS.md ships an extractable bg_bounded"      "$(yn grep -q '^bg_bounded()' "$SNIP")" yes
ok "…it is valid shell"                                  "$(yn bash -n "$SNIP")" yes
ok "…it handles timeout being absent on macOS"           "$(yn grep -q 'command -v timeout' "$SNIP")" yes
ok "…and the scanner does not flag the shape it teaches" "$(count_lines "$(scan "$SNIP")")" 0

# =======================================================================================
echo
echo "== 4. this repo's own machinery is clean, or allowlisted with a reason =="
# =======================================================================================
# `<path>|<count>|<reason>`. THE COUNT IS PINNED IN BOTH DIRECTIONS: one more unbounded spawn
# in an allowlisted file is red (the hole this would otherwise leave), and one fewer is red
# too (a stale pin nobody lowered). The reason is not decoration — it is the whole difference
# between an allowlist and a switch-off, so an empty or one-word one fails below.
#
# EVERY ENTRY HERE IS A ONE-SHOT: the backgrounded command exits on its own and the `&` is
# there to keep the PARENT responsive (a trap that fires at once, several acquires racing),
# not to detach anything long-lived. The spawns whose child never ends on its own —
# `watch-board.sh` driven by board-renderers, an installer blocked on a fifo, a whole harness
# run in a fixture copy — were FIXED in this change rather than listed here.
ALLOW=(
  "plugin/scripts/watch-board.sh|1|run_wait backgrounds a one-shot render (write-snapshot, build-board) and waits on it immediately, so its own INT/TERM trap fires at once instead of after the child returns; the child exits on its own and nothing is detached."
  "tests/artifact-board.test.sh|1|a one-shot page render of a 900-million-question fixture, backgrounded only so the harness can cap the hang it is asserting about; the generator exits on its own."
  "tests/tick-lock.test.sh|3|N concurrent one-shot tick-lock.sh acquire calls, racing on purpose; each exits in milliseconds and the harness waits for all of them."
)
allow_count() { # <path> -> the pinned count, or empty
  local e
  for e in "${ALLOW[@]}"; do
    case "$e" in "$1|"*) e="${e#*|}"; printf '%s' "${e%%|*}"; return 0 ;; esac
  done
  printf ''
}
REPO_HITS="$(cd "$REPO" && scan ${IN_SCOPE+"${IN_SCOPE[@]}"})"
N_HITS="$(count_lines "$REPO_HITS")"
echo "  (the scan reports $N_HITS unbounded spawn(s) across $N_SCOPE files)"

# Every hit is in an allowlisted file, and every allowlisted file has exactly its pinned
# number of hits. Reported as two numbers so a failure says WHICH way it broke.
unlisted=""; miscounted=""
for f in $(printf '%s\n' "$REPO_HITS" | sed -n 's/^\([^:]*\):.*/\1/p' | sort -u); do
  [ -n "$f" ] || continue
  want="$(allow_count "$f")"
  got="$(printf '%s\n' "$REPO_HITS" | grep -c "^$f:" || true)"
  if [ -z "$want" ]; then unlisted="${unlisted:+$unlisted }$f($got)"
  elif [ "$want" != "$got" ]; then miscounted="${miscounted:+$miscounted }$f(want $want, got $got)"
  fi
done
[ -n "$unlisted" ] && printf '%s\n' "$REPO_HITS" | sed 's/^/      /'
ok "no unbounded spawn outside the allowlist"            "$unlisted"   ""
ok "…and every allowlisted file has exactly its pin"     "$miscounted" ""
# A pin for a file that no longer exists, or that has been fixed, is a pin that stops
# meaning anything. Both directions of a stale allowlist.
stale=""
for e in "${ALLOW[@]}"; do
  p="${e%%|*}"; rest="${e#*|}"; n="${rest%%|*}"; why="${rest#*|}"
  [ -f "$REPO/$p" ] || { stale="${stale:+$stale }$p(missing)"; continue; }
  got="$(printf '%s\n' "$REPO_HITS" | grep -c "^$p:" || true)"
  [ "$got" = "$n" ] || stale="${stale:+$stale }$p(pinned $n, scans $got)"
  [ "${#why}" -ge 40 ] || stale="${stale:+$stale }$p(reason too thin)"
done
ok "every allowlist entry names a real file, a real count and a real reason" "$stale" ""
ok "…and the allowlist is not empty (it would pass vacuously)" \
  "$([ "${#ALLOW[@]}" -ge 1 ] && echo yes || echo no)" yes

# And no watchdog in this repo holds the stdout its caller reads through a command
# substitution. There is no allowlist for this one: the redirect costs nothing.
LOUD="$(cd "$REPO" && scan_loud ${IN_SCOPE+"${IN_SCOPE[@]}"})"
[ -n "$LOUD" ] && printf '%s\n' "$LOUD" | sed 's/^/      /'
ok "no watchdog keeps its caller's stdout"           "$(count_lines "$LOUD")" 0

# NON-VACUITY OF THE REPO SCAN ITSELF. The assertions above pass on a scanner that never
# reports anything, so the same scan is run over a MUTANT of a real machinery file with its
# bound deleted, and it must go from clean to flagged.
MUTSRC="$REPO/tests/board-renderers.test.sh"
MUTANT="$TMP/mutant-board-renderers.sh"
ANCHOR='( sleep 120; kill -TERM "$p" 2>/dev/null ) >/dev/null 2>&1 &'
if [ "$(grep -cF -- "$ANCHOR" "$MUTSRC")" -eq 0 ]; then
  skipped "MUTATION A: the watchdog anchor is gone from board-renderers.test.sh — not asserted"
else
  ok "CONTROL: the real file is clean under the scanner" "$(count_lines "$(scan "$MUTSRC")")" 0
  grep -vF -- "$ANCHOR" "$MUTSRC" > "$MUTANT"
  ok "the mutant really lost the bound" \
    "$([ "$(wc -c < "$MUTANT")" -lt "$(wc -c < "$MUTSRC")" ] && echo yes || echo no)" yes
  ok "MUTATION A: removing a watchdog turns the scan RED" \
    "$([ "$(count_lines "$(scan "$MUTANT")")" -ge 1 ] && echo yes || echo no)" yes
  EXTRA=$((EXTRA + 3))

  # MUTATION A2, the other class on the same real line: keep the bound, drop the redirect.
  # `index`-based replacement rather than `sub`, because the anchor is full of regex
  # metacharacters and a half-applied pattern is a mutant that proves nothing.
  LOUDER="$TMP/mutant-loud-watchdog.sh"
  ANCHOR_LOUD='( sleep 120; kill -TERM "$p" 2>/dev/null ) &'
  awk -v a="$ANCHOR" -v b="$ANCHOR_LOUD" \
    '{ i = index($0, a); if (i > 0) { print substr($0, 1, i - 1) b substr($0, i + length(a)); next } print }' \
    "$MUTSRC" > "$LOUDER"
  ok "the loud mutant really lost its redirect"      "$(grep -cF -- "$ANCHOR" "$LOUDER" | tr -d ' ')" 0
  ok "…while keeping the bound"                      "$(count_lines "$(scan "$LOUDER")")" 0
  ok "MUTATION A2: a watchdog that keeps stdout turns the loud scan RED" \
    "$([ "$(count_lines "$(scan_loud "$LOUDER")")" -ge 1 ] && echo yes || echo no)" yes
  EXTRA=$((EXTRA + 3))
fi

# MUTATION G — the allowlist PIN, which is the whole reason an entry carries a count. A new
# unbounded spawn in an already-allowlisted file must move the number the pin is compared
# against, or an entry is a permanent exemption for the file rather than for what was audited.
MUTALLOW="$TMP/mutant-allowlisted.sh"
cp "$REPO/tests/tick-lock.test.sh" "$MUTALLOW"
ok "CONTROL: the allowlisted file scans at its pin" "$(count_lines "$(scan "$MUTALLOW")")" 3
printf './something-new %s\n' '&' >> "$MUTALLOW"
ok "MUTATION G: one more unbounded spawn moves the count off the pin" \
  "$(count_lines "$(scan "$MUTALLOW")")" 4

# =======================================================================================
echo
echo "== 5. the rule in CONVENTIONS.md is about the CLASS, and there is only one of it =="
# =======================================================================================
# The wording is asserted because the wording is what failed: the bullet that stood here
# named servers, and the next kind of child was not a server. Each phrase below gets a
# mutation in §6 so none of these is a text assertion nobody can break.
CLASS='**Anything you background must be reaped by something that outlives YOU.**'
NOENUM='**A rule that enumerates kinds of process is a rule that misses the next kind**'
ONLYRULE="It is this repo's ONLY rule about backgrounded children"
NOTBAN='**It does not ban backgrounding.**'
REAPER='what is required is a REAPER, not abstinence'
CHILD='**The bound goes on the CHILD ITSELF, and that part is not optional.**'
DEFEATED='**both were already defeated**'
ADDITION='neither may ship as the whole answer'
READERS='**Two readers, because what stood here was prose and prose did not stop this:**'
OLDRULE='**Kill everything you started before you report.**'
CONV_FLAT="$(flatten "$CONV")"

ok "the rule states the CLASS"                      "$(saw "$CONV_FLAT" "$CLASS")" yes
ok "…and says why an enumeration is the defect"     "$(saw "$CONV_FLAT" "$NOENUM")" yes
ok "…and claims to be the only one of its kind"     "$(saw "$CONV_FLAT" "$ONLYRULE")" yes
ok "…and folds in the dev-server measurement"       "$(saw "$CONV_FLAT" '2 days 16 hours')" yes
ok "the bound is required ON THE CHILD"             "$(saw "$CONV_FLAT" "$CHILD")" yes
ok "…with the measured reparenting as the reason"   "$(saw "$CONV_FLAT" 'reparented to `ppid 1`')" yes
ok "…naming the trap and the process-group kill"    "$(saw "$CONV_FLAT" 'a process-group kill needs someone left')" yes
ok "…as defeated in the measured case"              "$(saw "$CONV_FLAT" "$DEFEATED")" yes
ok "…and permitted only as additions"               "$(saw "$CONV_FLAT" "$ADDITION")" yes
ok "backgrounding is NOT banned"                    "$(saw "$CONV_FLAT" "$NOTBAN")" yes
ok "…a reaper is what is asked for, not abstinence" "$(saw "$CONV_FLAT" "$REAPER")" yes
ok "…and deleting the & is called out as no fix"    "$(saw "$CONV_FLAT" 'satisfies nothing here')" yes
ok "both readers are named where the rule is"       "$(saw "$CONV_FLAT" "$READERS")" yes
ok "…this harness by name"                          "$(saw "$CONV_FLAT" 'tests/background-teardown.test.sh')" yes
ok "…and the check row"                             "$(saw "$CONV_FLAT" 'row naming every orphaned process whose cwd is')" yes

# ONE RULE, NOT TWO THAT DISAGREE ON SCOPE. Counted over BULLET TITLES — the bolded phrase a
# `- **…**` bullet opens with — because the word "background" also appears inside the
# check-dispatch bullet, which is a rule about something else and must not be counted.
bullet_titles() { sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p' "$1"; }
teardown_titles() { bullet_titles "$1" | grep -icE 'backgroun|teardown|kill everything' || true; }
ok "exactly ONE bullet TITLE is about backgrounded children" "$(teardown_titles "$CONV")" 1
ok "…and the superseded dev-server title is gone"            "$(saw "$CONV_FLAT" "$OLDRULE")" no

# =======================================================================================
echo
echo "== 6. MUTATIONS on the rule — every clause is individually breakable =="
# =======================================================================================
# Delete the whole `- ` bullet whose text contains <marker>, up to the next top-level bullet.
strip_bullet() { # <file> <marker>
  awk -v m="$2" 'index($0, m) && /^- / { skip = 1; next } skip && /^- / { skip = 0 } !skip { print }' "$1"
}
# Delete from the line containing <from> up to (not including) the line containing <to>.
strip_range() { # <file> <from> <to>
  awk -v a="$2" -v b="$3" 'index($0, a) && !skip { skip = 1 } skip && index($0, b) { skip = 0 } !skip { print }' "$1"
}
mut_smaller() { # <mutant> — a mutation that changed nothing proves nothing
  [ "$(wc -c < "$1")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no
}

if [ "$(grep -cF -- "$CLASS" "$CONV")" -eq 0 ]; then
  skipped "MUTATION B: the rule's opening phrase has moved — the bullet cut is not asserted"
else
  strip_bullet "$CONV" "$CLASS" > "$TMP/conv-no-rule.md"
  B_FLAT="$(flatten "$TMP/conv-no-rule.md")"
  ok "MUTATION B removed something"                  "$(mut_smaller "$TMP/conv-no-rule.md")" yes
  ok "CONTROL: the harness-growth bullet survives"   "$(saw "$B_FLAT" "Don't grow the harness without a reason")" yes
  ok "CONTROL: the check-dispatch bullet survives"   "$(saw "$B_FLAT" 'A dispatch is not finished until its artifact exists')" yes
  ok "mutant: the class statement is gone"           "$(saw "$B_FLAT" "$CLASS")" no
  ok "mutant: the bound-on-the-child is gone"        "$(saw "$B_FLAT" "$CHILD")" no
  ok "mutant: not-a-ban is gone"                     "$(saw "$B_FLAT" "$NOTBAN")" no
  ok "mutant: the readers are gone"                  "$(saw "$B_FLAT" "$READERS")" no
  ok "mutant: NO bullet title is about this any more" "$(teardown_titles "$TMP/conv-no-rule.md")" 0
  EXTRA=$((EXTRA + 8))
fi

if [ "$(grep -cF -- "$NOTBAN" "$CONV")" -eq 0 ]; then
  skipped "MUTATION C: the not-a-ban phrase has moved — its own cut is not asserted"
else
  strip_range "$CONV" "$NOTBAN" "$CHILD" > "$TMP/conv-ban.md"
  C_FLAT="$(flatten "$TMP/conv-ban.md")"
  ok "MUTATION C removed something"                  "$(mut_smaller "$TMP/conv-ban.md")" yes
  ok "CONTROL: the class statement remains"          "$(saw "$C_FLAT" "$CLASS")" yes
  ok "CONTROL: the bound-on-the-child remains"       "$(saw "$C_FLAT" "$CHILD")" yes
  ok "mutant: not-a-ban is gone"                     "$(saw "$C_FLAT" "$NOTBAN")" no
  ok "mutant: reaper-not-abstinence is gone"         "$(saw "$C_FLAT" "$REAPER")" no
  EXTRA=$((EXTRA + 5))
fi

if [ "$(grep -cF -- "$CHILD" "$CONV")" -eq 0 ]; then
  skipped "MUTATION D: the bound-on-the-child phrase has moved — its own cut is not asserted"
else
  strip_range "$CONV" "$CHILD" '```sh' > "$TMP/conv-no-bound.md"
  D_FLAT="$(flatten "$TMP/conv-no-bound.md")"
  ok "MUTATION D removed something"                  "$(mut_smaller "$TMP/conv-no-bound.md")" yes
  ok "CONTROL: the class statement remains"          "$(saw "$D_FLAT" "$CLASS")" yes
  ok "CONTROL: not-a-ban remains"                    "$(saw "$D_FLAT" "$NOTBAN")" yes
  ok "mutant: the bound requirement is gone"         "$(saw "$D_FLAT" "$CHILD")" no
  ok "mutant: the measured ppid 1 is gone"           "$(saw "$D_FLAT" 'reparented to `ppid 1`')" no
  ok "mutant: trap-and-pgroup-defeated is gone"      "$(saw "$D_FLAT" "$DEFEATED")" no
  EXTRA=$((EXTRA + 6))
fi

# MUTATION E — the absence assertion, proved non-vacuous. Paste the superseded dev-server
# bullet back and the "exactly one" count must break: that is what "one rule, not two that
# disagree on scope" means, and an absence check passes against any document by default.
{ cat "$CONV"
  printf -- '- %s Any dev server, watcher or other background process you launch must be\n' "$OLDRULE"
  printf -- '  **stopped before you report back**.\n'; } > "$TMP/conv-two-rules.md"
E_FLAT="$(flatten "$TMP/conv-two-rules.md")"
ok "MUTATION E: the old bullet really is back"      "$(saw "$E_FLAT" "$OLDRULE")" yes
ok "…and TWO titles now claim the subject"          "$(teardown_titles "$TMP/conv-two-rules.md")" 2
ok "CONTROL: the new rule is still there too"       "$(saw "$E_FLAT" "$CLASS")" yes

# =======================================================================================
echo
echo "== 7. the measured case, reproduced: the parent dies before its kill line =="
# =======================================================================================
# THIS IS THE INCIDENT, not an analogy: a parent spawns a child, records its pid, and is
# SIGKILLed before the `kill` at the end of the script runs. The child is then verified to be
# alive and reparented to pid 1 — which is what all 34 orphans looked like — and only then is
# the bounded form put through the same SIGKILL. The unbounded run is what makes the bounded
# one mean anything: without it, "the child is gone" could just be a child that never ran.
WTROOT="$TMP/wtroot"; WT="$WTROOT/ai-bridge-fixture-wt"
mkdir -p "$WT" "$TMP/repos"
INST="$TMP/inst"; mkdir -p "$INST/scripts"
printf '{\n  "worktreeRoot": "%s",\n  "reposRoot": "%s"\n}\n' "$WTROOT" "$TMP/repos" \
  > "$INST/instance.config.json"

# A child that records its own pid and does not end on any timescale in this file. Reading
# the pid from a file rather than from `ps | grep` keeps the harness's own grep out of its own
# process listing; `exec` makes the recorded pid the surviving process rather than a wrapper.
# A single `sleep` rather than a `while :; do sleep 1; done` loop deliberately: that loop
# spawns a fresh `sleep` every second, so killing it leaves a one-second orphan of its own
# behind and the exact counts asserted below would be a race instead of a fact. Four minutes
# is unbounded relative to every timescale in this file and still obeys the rule being tested
# — if this harness is itself killed mid-run, nothing it started outlives its own bound by
# more than that.
CHILD_BODY='echo $$ > "$1"; exec sleep 240'
{ printf '#!/usr/bin/env bash\n'
  printf 'cd "$1" || exit 1\n'
  printf 'sh -c %s _ "$1/child.pid" %s\n' "'$CHILD_BODY'" '&'
  printf 'LOAD=$!\n'
  # `wait`, not `sleep 600`: a builtin, so the fixture parent has exactly ONE child and the
  # orphan count below is exact. It blocks until the child ends, which it never does.
  printf 'wait "$LOAD"\n'
  printf 'kill "$LOAD" 2>/dev/null   # NEVER REACHED — the defect, in one line\n'
} > "$TMP/parent-unbounded.sh"

alive() { kill -0 "$1" 2>/dev/null && echo yes || echo no; }
ppid_of() { ps -p "$1" -o ppid= 2>/dev/null | tr -d ' '; }
wait_file() { # <file> <tries> — 0.2s apart
  local i=0
  while [ "$i" -lt "$2" ]; do [ -s "$1" ] && return 0; sleep 0.2; i=$((i+1)); done
  return 1
}
wait_gone() { # <pid> <tries> — 0.5s apart
  local i=0
  while [ "$i" -lt "$2" ]; do kill -0 "$1" 2>/dev/null || return 0; sleep 0.5; i=$((i+1)); done
  return 1
}

bash "$TMP/parent-unbounded.sh" "$WT" >/dev/null 2>&1 &
UPID=$!
# This harness obeys the rule it is testing: the fixture parent blocks in `wait` forever, so
# it gets a bound of its own that fires whether or not this harness lives to reach the kill
# below. `>/dev/null` because killing this watchdog leaves its `sleep` behind, and a `sleep`
# holding this harness's stdout blocks the `out=$(bash …)` the CI loop reads it through —
# measured at 99 seconds for a 15-second harness before the redirect was added.
( sleep 45; kill -9 "$UPID" 2>/dev/null ) >/dev/null 2>&1 &
REAP="$REAP $UPID $!"
ok "the unbounded fixture parent is running"        "$(alive "$UPID")" yes
wait_file "$WT/child.pid" 150 || true
KID="$(cat "$WT/child.pid" 2>/dev/null || true)"
REAP="$REAP $KID"
ok "…and its child recorded a pid"                  "$([ -n "$KID" ] && echo yes || echo no)" yes
ok "…which is a child of the fixture parent"        "$(ppid_of "$KID")" "$UPID"
kill -9 "$UPID" 2>/dev/null
wait "$UPID" 2>/dev/null
wait_gone "$UPID" 20 || true
ok "the parent is dead, its kill line never ran"    "$(alive "$UPID")" no
sleep 1
ok "…and the child SURVIVED it (this is the defect)" "$(alive "$KID")" yes
KID_PPID="$(ppid_of "$KID")"
if [ "$KID_PPID" = 1 ]; then
  ok "…reparented to pid 1, exactly as measured"    "$KID_PPID" 1
  EXTRA=$((EXTRA + 1))
else
  # A user-level subreaper (some Linux session managers) adopts orphans instead of pid 1.
  # That is an environment fact, not a defect, and it is printed rather than counted:
  # macOS — the platform this repo is measured on — reparents to launchd, pid 1.
  skipped "reparenting: this host adopted the orphan at ppid $KID_PPID, not 1 — not asserted"
fi

# =======================================================================================
echo
echo "== 8. /loopd:welcome check reports THAT orphan — and never a false zero =="
# =======================================================================================
# Asserted against the real orphan from §7, not against a clean machine: a row that reports
# zero because it can never report anything else is the failure mode this row is written
# against, and only a live orphan can tell the two apart.
LIST="$(bash "$AIB" check --list 2>/dev/null)"
ok "the row is in the ONE list"                     "$(printf '%s\n' "$LIST" | grep -c '^orphan-processes' | tr -d ' ')" 1
ok "…at the human tier (killing is never automatic)" \
  "$(printf '%s\n' "$LIST" | awk -F'\t' '$1=="orphan-processes" {print $2}')" human
ok "…and it may speak on the SessionStart path"    \
  "$(printf '%s\n' "$LIST" | awk -F'\t' '$1=="orphan-processes" {print $3}')" yes
ok "…with no fix_ function anywhere in the script"  "$(grep -c '^fix_orphan_processes()' "$AIB" | tr -d ' ')" 0

CHK="$(bash "$AIB" check --instance "$INST" --template "$REPO" 2>&1)"
ORPH="$(printf '%s\n' "$CHK" | grep -e 'orphan' -e 'ppid 1' || true)"
printf '%s\n' "$ORPH" | sed 's/^/      /'
ok "the orphan is reported at all"                  "$(saw "$ORPH" 'run out of a worktree')" yes
ok "…exactly one of them, which is how many there are" "$(saw "$ORPH" '1 orphaned process(es)')" yes
ok "…as a warning, not a pleasantry"                "$(printf '%s\n' "$ORPH" | grep -c '^⚠' | tr -d ' ')" 1
ok "…naming the pid"                                "$(saw "$CHK" "pid $KID")" yes
ok "…and the worktree it is running out of"         "$(saw "$CHK" "$WT")" yes
ok "…and how long it has been up"                   "$(saw "$CHK" 'up ')" yes
ok "…with the human's own command, never a repair"  "$(saw "$CHK" "yours, not fix's:")" yes
ok "…and NOT the clean verdict"                     "$(saw "$CHK" 'no orphan runs out of a worktree root')" no
# The SessionStart budget: two lines per failing check, whatever the number of orphans.
BAN="$(bash "$AIB" check --only-problems --banner --instance "$INST" --template "$REPO" 2>&1)"
ok "the banner path carries it too"                 "$(saw "$BAN" 'run out of a worktree')" yes
ok "…in at most 2 lines for this row"               \
  "$(printf '%s\n' "$BAN" | grep -cE '(orphan|not fix.s: ps)' | tr -d ' ')" 2
# No command line, ever: this output lands in session context and an argv can carry a token.
ok "…and never the child's own argv"                "$(saw "$CHK" 'sleep 240')" no

# NON-VACUITY: the same instance, the same live orphan, with the ROW deleted from the script.
# THE MUTANT LIVES IN A PLUGIN-SHAPED DIRECTORY, because welcome.sh resolves its sibling
# helpers from its own location — <root>/plugin/scripts/ — and a copy dropped anywhere else
# would find none of them, so the CONTROL assertion below ("it still reports the other
# rows") would fail for a reason that has nothing to do with the mutation.
mkdir -p "$TMP/mutplugin/plugin"
ln -sfn "$REPO/plugin/scripts" "$TMP/mutplugin/plugin/scripts-real" 2>/dev/null || true
cp -R "$REPO/plugin/scripts" "$TMP/mutplugin/plugin/scripts"
cp "$REPO/VERSION" "$TMP/mutplugin/VERSION"
MUTAIB="$TMP/mutplugin/plugin/scripts/welcome.sh"
# The row is the last line of the CHECKS string, so a plain line delete takes the closing
# quote with it and the "mutant" only proves that a syntax error reports nothing. Keep
# whatever terminated the string on that line.
awk -v q="'" '$0 ~ /^orphan-processes\|/ { if (index($0, q)) print q; next } { print }' \
  "$AIB" > "$MUTAIB"
if [ "$(grep -c '^orphan-processes|' "$MUTAIB" | tr -d ' ')" -ne 0 ]; then
  skipped "MUTATION F: the row is not on a line of its own any more — not asserted"
else
  ok "MUTATION F: the mutant is still valid shell" "$(yn bash -n "$MUTAIB")" yes
  MCHK="$(bash "$MUTAIB" check --instance "$INST" --template "$REPO" 2>&1)"
  ok "…and still runs"                             "$([ -n "$MCHK" ] && echo yes || echo no)" yes
  ok "…and says NOTHING about the live orphan"      "$(saw "$MCHK" 'run out of a worktree')" no
  ok "CONTROL: it still reports the other rows"     "$(saw "$MCHK" 'config resolves')" yes
  EXTRA=$((EXTRA + 4))
fi

# CANNOT-ANSWER, THREE WAYS, AND NONE OF THEM PRINTS ZERO. Each stub narrows PATH rather than
# editing the script, so what is asserted is the shipped code on a machine missing a tool.
mkstub() { # <dir> <tool>... — symlink each tool that exists here, so PATH can be narrowed
  local d="$1"; shift; mkdir -p "$d"
  local t p
  for t in "$@"; do p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$d/$t"; done
  return 0
}
# `dirname` is in the list because welcome.sh locates its own sibling scripts with it
# (the plugin ships them beside itself since task-013). Narrowing PATH is meant to simulate
# a machine with no `ps`, not one with no coreutils.
TOOLS="bash sh python3 git find sed awk tr wc sort comm grep id date basename dirname cat readlink"
# (a) no `ps`: nothing can be enumerated, so nothing may be concluded.
STUB_NOPS="$TMP/stub-nops"; mkstub "$STUB_NOPS" $TOOLS lsof
NOPS="$(PATH="$STUB_NOPS" bash "$AIB" check --instance "$INST" --template "$REPO" 2>/dev/null)"
ok "no ps: says so"                                 "$(saw "$NOPS" 'no ps on PATH')" yes
ok "…and does not claim a clean scan"               "$(saw "$NOPS" 'no orphan runs out of a worktree root')" no
ok "…and does not claim the orphan is gone"         "$(saw "$NOPS" 'UNKNOWN, not zero')" yes
# (b) an `lsof` that answers nothing — a restricted one, or one that cannot see these pids.
# The live orphan of §7 is still there, so a zero here would be a measured false zero.
STUB_BLINDLSOF="$TMP/stub-blind"; mkstub "$STUB_BLINDLSOF" $TOOLS ps
printf '#!/bin/sh\nexit 0\n' > "$STUB_BLINDLSOF/lsof"; chmod +x "$STUB_BLINDLSOF/lsof"
BLIND="$(PATH="$STUB_BLINDLSOF" bash "$AIB" check --instance "$INST" --template "$REPO" 2>/dev/null)"
ok "a blind lsof: reports the question as UNKNOWN"   "$(saw "$BLIND" 'where they run is UNKNOWN')" yes
ok "…and NOT as none found"                         "$(saw "$BLIND" 'no orphan runs out of a worktree root')" no
ok "…while the orphan it could not see is still alive" "$(alive "$KID")" yes
# (c) an instance that names no worktree root at all: nothing was scanned, and it says so
# rather than reporting a clean machine.
NOWT="$TMP/inst-no-wt"; mkdir -p "$NOWT"; printf '{\n  "org": "example"\n}\n' > "$NOWT/instance.config.json"
NONE="$(bash "$AIB" check --instance "$NOWT" --template "$REPO" 2>&1)"
ok "no worktree root: says there is nowhere to scan" "$(saw "$NONE" 'nowhere to scan')" yes
ok "…and explicitly claims nothing"                  "$(saw "$NONE" 'nothing is claimed')" yes

# The clean verdict is a REPORTED answer, not silence — with the counts that make it checkable.
kill -9 "$KID" 2>/dev/null; wait_gone "$KID" 20 || true
ok "the fixture orphan is gone now"                 "$(alive "$KID")" no
CLEAN="$(bash "$AIB" check --instance "$INST" --template "$REPO" 2>&1)"
ok "a clean root is reported, not passed over"       "$(saw "$CLEAN" 'no orphan runs out of a worktree root')" yes
ok "…carrying the counts behind the claim"           "$(saw "$CLEAN" 'cwds read')" yes
ok "…and no warning"                                 "$(printf '%s\n' "$CLEAN" | grep -c '^⚠.*worktree' | tr -d ' ')" 0

# =======================================================================================
echo
echo "== 9. the shipped bound ends the child with no parent left to help =="
# =======================================================================================
# THE SAME SIGKILL AS §7, the same child, the same reparenting — and this time the child dies
# on its own. That is the whole claim of the rule, and §7 is what makes it non-vacuous: there,
# an identical child was still running until this harness shot it by hand.
#
# THE SNIPPET UNDER TEST IS THE ONE `CONVENTIONS.md` SHIPS, extracted from the document in
# §3 and pasted into the fixture. Nothing here re-types it, so the rule cannot come to
# recommend one thing while the harness proves another.
BWT="$WTROOT/bounded-wt"; mkdir -p "$BWT"
{ printf '#!/usr/bin/env bash\n'
  cat "$SNIP"
  printf 'cd "$1" || exit 1\n'
  printf 'bg_bounded "$2" sh -c %s _ "$1/child.pid"\n' "'$CHILD_BODY'"
  printf 'wait\n'
  printf 'kill 0 2>/dev/null   # NEVER REACHED, and never the mechanism\n'
} > "$TMP/parent-bounded.sh"
ok "the bounded fixture parent is valid shell"      "$(yn bash -n "$TMP/parent-bounded.sh")" yes

# run_bounded_case <label> <PATH to run under> <bound seconds> — returns 0 if the child was
# reparented to pid 1 and then died on its own inside the bound.
BOUND=4
bounded_case() { # <label> <path>
  local label="$1" runpath="$2" kid
  rm -f "$BWT/child.pid"
  PATH="$runpath" bash "$TMP/parent-bounded.sh" "$BWT" "$BOUND" >/dev/null 2>&1 &
  local bp=$!
  ( sleep 45; kill -9 "$bp" 2>/dev/null ) >/dev/null 2>&1 &
  REAP="$REAP $bp $!"
  wait_file "$BWT/child.pid" 150 || true
  kid="$(cat "$BWT/child.pid" 2>/dev/null || true)"
  REAP="$REAP $kid"
  ok "$label: the child is running"                 "$([ -n "$kid" ] && echo "$(alive "$kid")" || echo missing)" yes
  kill -9 "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
  ok "$label: the parent is SIGKILLed, kill line unreached" "$(alive "$bp")" no
  # It must genuinely become an orphan first — otherwise this is a test of a live parent's
  # cleanup, which is the thing the rule says is not enough.
  ok "$label: the child outlived its parent as an orphan" "$(alive "$kid")" yes
  # And then die, with nothing left anywhere that could be doing it for us.
  wait_gone "$kid" 40 || true
  ok "$label: …and then ended on its own, inside the bound" "$(alive "$kid")" no
  return 0
}

# (a) NO `timeout` ON PATH — a stock macOS, which is the machine the incident happened on and
# the platform CI runs. The fallback branch of the snippet is what carries the bound here.
STUB_MIN="$TMP/stub-min"; mkstub "$STUB_MIN" bash sh sleep
ok "the minimal PATH really has no timeout"         "$(yn test -e "$STUB_MIN/timeout")" no
bounded_case "no timeout" "$STUB_MIN"

# (b) WITH `timeout`, where the host has it (a Linux runner, or a brewed coreutils). SKIPPED
# rather than faked when it is absent: a stub `timeout` would assert this harness's stub.
if command -v timeout >/dev/null 2>&1; then
  bounded_case "timeout branch" "$PATH"
  EXTRA=$((EXTRA + 4))
else
  skipped "the timeout branch: no timeout on this host (stock macOS) — the fallback above is what ships here"
fi

# THE READER AGREES WITH THE MECHANISM. Both fixture worktrees are empty of orphans now, and
# the row that reported one in §8 says so — including the watchdog, which ended itself.
FINAL="$(bash "$AIB" check --instance "$INST" --template "$REPO" 2>&1)"
ok "and /loopd:welcome check now reports the roots clean" "$(saw "$FINAL" 'no orphan runs out of a worktree root')" yes
ok "…with no warning left about either worktree"      "$(printf '%s\n' "$FINAL" | grep -c '^⚠.*worktree' | tr -d ' ')" 0

# =======================================================================================
echo
echo "== 10. this harness ships like the others here =="
# =======================================================================================
ok "it parses"                                      "$(yn bash -n "$0")" yes
ok "…and is executable in the index"                "$(cd "$REPO" && git ls-files -s tests/background-teardown.test.sh | awk '{print $1}')" 100755
ok "…with the shebang this directory declares"      "$(head -1 "$0")" '#!/usr/bin/env bash'
# No GNU-only regex escape anywhere in the scanner or in this file: the same portability rule
# tests/snapshot.test.sh holds the shipped scripts to, and a `\s` that a BSD grep does not
# implement is a silently wrong ANSWER rather than an error. THE NEEDLE IS ASSEMBLED rather
# than typed — spelling it out here would make this assertion match its own source line, which
# is how a scanner comes to report the check that looks for the thing
# (knowledge/findings/inspection-is-not-verification-on-a-resumed-run).
BS="$(printf '%s' '\')"
no_gnu_escape() { # <file> <escape letter> -> count of hits outside whole-line comments
  # `-F`, not a regex: this machine's BSD grep DOES implement `\s`, so an unescaped needle
  # would match every line with a space in it (measured: 414 of them).
  sed 's/^[[:space:]]*#.*$//' "$1" | grep -cF -- "$BS$2" || true
}
ok "no GNU-only whitespace escape outside comments"  "$(no_gnu_escape "$0" s | tr -d ' ')" 0
ok "no GNU-only word-boundary escape outside comments" "$(no_gnu_escape "$0" b | tr -d ' ')" 0
ok "…and that check is not vacuous (a plant is seen)" \
  "$([ "$(printf 'x=%ss\n' "$BS" > "$TMP/plant.sh"; no_gnu_escape "$TMP/plant.sh" s | tr -d ' ')" -ge 1 ] && echo yes || echo no)" yes

# --- the assertion-count pin ----------------------------------------------------------
# A skipped block is as red as a failed one: an ambient variable, an early `return`, or an
# unterminated string can make whole sections vanish while `fail=0` still prints. This counts
# every assertion before itself, minus the ones a CONDITIONAL block declared it added, so a
# platform difference (a host with `timeout`) moves the arithmetic and not the pin. The
# conditional blocks announce themselves through SKIP lines, which is the other half.
EXPECTED_ASSERTIONS=98
TOTAL=$(( pass + fail - EXTRA ))
: "${EXPECTED_ASSERTIONS:?EXPECTED_ASSERTIONS not set — a merge likely dropped it}"
ok "exactly $EXPECTED_ASSERTIONS unconditional assertions ran (got $TOTAL)" \
  "$([ "$TOTAL" -eq "$EXPECTED_ASSERTIONS" ] && echo yes || echo no)" yes

echo
printf 'pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
