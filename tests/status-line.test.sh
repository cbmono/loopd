#!/usr/bin/env bash
#
# status-line.test.sh — `plugin/scripts/status-line.sh`, the bundle's `statusLine`.
#
# THE PROPERTIES:
#   * ONE LINE, FROM THE FILES THAT ACTUALLY CARRY THE FACTS. Task frontmatter for
#     in-flight, AWAITING.md for need-you, `.tick-lock` for the lock, `log.md`'s last
#     `* TICK` for the time — and NOT `SNAPSHOT.json` or `.tick-state`, both of which are
#     wrong or absent exactly when the line matters.
#   * IT DEGRADES INSTEAD OF LYING. Every absent-file path renders `?` and never `0`, and
#     `0` is still printed when zero is what the files say. Outside a bundle: nothing.
#   * AWAITING.md IS THE ONE EXCEPTION, AND IT HAS THREE STATES, NOT TWO. Its absence is
#     the queue's OFF SWITCH (build-awaiting.sh never recreates it), so absent drops the
#     segment, unreadable says so and names the repair, and readable counts. The three
#     cannot all pass on one rendering.
#   * COLOUR SURVIVES A BARE NON-TTY, because a statusLine's stdout is always a pipe into
#     Claude Code. `NO_COLOR` and `--color never` are the only opt-outs; 3/4-bit only.
#   * OFFLINE AND MODEL-FREE, PROVEN: `gh`/`git`/`jq` are PATH stubs that leave a sentinel.
#   * UNDER 100 ms per invocation, measured here rather than asserted.
# Fixtures live under mktemp; no real bundle is touched.
# Exit: 0 all assertions pass, 1 one failed, 2 the fixture could not be built.
# Reasoning: ai-bridge-v3/task-025.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SL="$REPO/plugin/scripts/status-line.sh"
[ -f "$SL" ] || { echo "status-line.test: missing $SL" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/statusline.XXXXXX")" || {
  echo "status-line.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; skip=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# `chmod 000` does not stop ROOT reading a file, and some filesystems ignore the mode
# outright, so every case that needs an unreadable one PROBES its own fixture: untestable
# here is SAID, never passed vacuously and never failed against a correct implementation.
# Same shape as push-state.test.sh.
unreadable() { chmod 000 "$1" 2>/dev/null; [ ! -r "$1" ]; }
no_fixture() { # <what it would have asserted> <how many assertions>
  printf '  SKIP  %-62s (cannot chmod 000 as this user)\n' "$1"; skip=$((skip + $2)); }

# The offline proof: three commands that can only ever be caught. SENTINEL survives the
# call, so "it printed the right line" and "it never asked the network" are two assertions.
BIN="$TMP/bin"; mkdir -p "$BIN"
for t in gh jq git curl; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "$SENTINEL"\nexit 99\n' > "$BIN/$t"
  chmod +x "$BIN/$t"
done
SENTINEL="$TMP/network-was-touched"
# `claude agents --json` is stubbed to an empty list, and the agents cache lives under TMP,
# so this file never reads the machine's real sessions. tests/agent-view.test.sh owns the
# segment itself.
printf '#!/usr/bin/env bash\necho "[]"\n' > "$BIN/claude"; chmod +x "$BIN/claude"
export XDG_CACHE_HOME="$TMP/cache"

run() { SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" "$@" </dev/null 2>/dev/null; }
plain() { run --instance "$1" --color never; }

# ------------------------------------------------------------------- the fixture bundle
mk() { # <dir> — a bundle with 2 in-flight tasks, 3 awaiting items, a closed tick, no lock
  local d="$1"
  mkdir -p "$d/projects/proj-a/tasks" "$d/$AB_DIR" || return 1
  printf '{ "org": "acme" }\n' > "$d/instance.config.json"
  local i
  for i in 1 2; do
    printf -- '---\ntitle: "t%s"\nstatus: in-progress\n---\n\nstatus: done\n' "$i" \
      > "$d/projects/proj-a/tasks/task-00$i.md"
  done
  printf -- '---\nstatus: ready\n---\n'  > "$d/projects/proj-a/tasks/task-003.md"
  printf -- '---\nstatus: done\n---\n'   > "$d/projects/proj-a/tasks/task-004.md"
  cat > "$d/$AB_AWAITING" <<'EOF'
# Awaiting you

*Derived and gitignored.*

## 🔴 Awaiting you (3)
* 🔀 **merge** — [a](/projects/proj-a/tasks/task-001.md)
* ✅ **approve** — [b](/projects/proj-a/tasks/task-003.md)
* ❓ **answer** — [c](/projects/proj-a/tasks/task-004.md)

## Something else
* not an awaiting item
EOF
  cat > "$d/$AB_LEDGER" <<'EOF'
# Log

* TICK 2026-09-12T07:00:00Z by cbmono close: an older tick
* TICK 2026-09-13T16:41:05Z by cbmono open: the one this line reports
EOF
}
INST="$TMP/inst"; mk "$INST" || { echo "status-line.test: could not build the fixture" >&2; exit 2; }

# The expected clock reading, derived the same two ways the script tries, so this file
# asserts a real local time rather than re-implementing the conversion once and agreeing
# with itself about a wrong one.
EP="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' 2026-09-13T16:41:05Z '+%s' 2>/dev/null)" || EP=""
if [ -n "$EP" ]; then HM="$(date -r "$EP" '+%H:%M')"
else                  HM="$(date -d 2026-09-13T16:41:05Z '+%H:%M' 2>/dev/null)"; fi
[ -n "$HM" ] || { echo "status-line.test: no date(1) this file knows how to drive" >&2; exit 2; }

echo
echo "== 1. the whole line, character for character =="
ok "the healthy bundle" "$(plain "$INST")" \
   "loopd · 2 in flight · agents 0 running · 3 need you · lock free · last tick $HM"
: > "$INST/$AB_LOCK"
ok "…and with a tick holding the lock" "$(plain "$INST")" \
   "loopd · 2 in flight · agents 0 running · 3 need you · lock held · last tick $HM"
rm -f "$INST/$AB_LOCK"
ok "exactly one line of output" "$(plain "$INST" | wc -l | tr -d ' ')" 1

echo
echo "== 2. it read the files that carry the facts, and no others =="
ok 'an `open:` TICK is still the last tick (it is the newest)' \
   "$(printf '%s' "$(plain "$INST")" | grep -c "last tick $HM")" 1
printf '{"counts":{"awaiting":99}}\n' > "$INST/$AB_SNAPSHOT"
printf 'recorded: 2001-01-01T00:00:00Z\n'    > "$INST/$AB_STATE_DIR"
ok "SNAPSHOT.json and .tick-state change nothing" "$(plain "$INST")" \
   "loopd · 2 in flight · agents 0 running · 3 need you · lock free · last tick $HM"
ok "…and neither is named in the source" \
   "$(grep -c 'SNAPSHOT\.json\|\.tick-state' "$SL" | tr -d ' ')" 2
ok "…which is twice, in comments saying why not" \
   "$(grep -v '^[[:space:]]*#' "$SL" | grep -c 'SNAPSHOT\.json\|\.tick-state' | tr -d ' ')" 0
rm -f "$INST/$AB_SNAPSHOT" "$INST/$AB_STATE_DIR"

echo
echo "== 3. every absent input renders \`?\`, never \`0\` — except the one that is an OFF SWITCH =="
D="$TMP/d1"; mk "$D"; rm -f "$D/$AB_AWAITING"
ok "no AWAITING.md ⇒ the queue is off, so the segment is GONE" \
   "$(plain "$D" | grep -c 'need you\|AWAITING' | tr -d ' ')" 0
ok "…and the rest of the line is untouched" "$(plain "$D")" \
   "loopd · 2 in flight · agents 0 running · lock free · last tick $HM"
D="$TMP/d2"; mk "$D"; rm -f "$D/$AB_LEDGER"
ok "no log.md ⇒ the time is unknown"       "$(plain "$D" | sed 's/.*· //')" "last tick ?"
D="$TMP/d3"; mk "$D"; printf '# Log\n\nnothing yet\n' > "$D/$AB_LEDGER"
ok "a log with no TICK line ⇒ unknown"     "$(plain "$D" | sed 's/.*· //')" "last tick ?"
D="$TMP/d4"; mk "$D"; rm -rf "$D/projects"
ok "no projects/ ⇒ in-flight is unknown"   "$(plain "$D" | sed 's/.*loopd · \([^·]*in flight\) ·.*/\1/')" "? in flight"

echo
echo "== 4. …and zero is still printed when zero is what the files SAY =="
D="$TMP/d5"; mk "$D"
for f in "$D"/projects/proj-a/tasks/*.md; do printf -- '---\nstatus: ready\n---\n' > "$f"; done
ok "no task in progress ⇒ 0, not ?" "$(plain "$D" | sed 's/.*loopd · \([^·]*in flight\) ·.*/\1/')" "0 in flight"
D="$TMP/d6"; mk "$D"
printf '# Awaiting you\n\n## 🔴 Awaiting you (0)\n\n*nothing waits*\n' > "$D/$AB_AWAITING"
ok "an empty queue ⇒ 0, not ?"      "$(plain "$D" | sed 's/.*· \([^·]*need you\) ·.*/\1/')" "0 need you"
D="$TMP/d7"; mk "$D"; rm -f "$D"/projects/proj-a/tasks/*.md
ok "a project with no tasks ⇒ 0"    "$(plain "$D" | sed 's/.*loopd · \([^·]*in flight\) ·.*/\1/')" "0 in flight"

D="$TMP/d9"; mk "$D"
if unreadable "$D/projects/proj-a/tasks/task-001.md"; then
  ok "an UNREADABLE task doc ⇒ ?, never a quiet undercount" \
     "$(plain "$D" | sed 's/.*loopd · \([^·]*in flight\) ·.*/\1/')" "? in flight"
else
  no_fixture "an UNREADABLE task doc ⇒ ?, never a quiet undercount" 1
fi
chmod 644 "$D/projects/proj-a/tasks/task-001.md"
D="$TMP/d10"; mk "$D"
if unreadable "$D/$AB_AWAITING"; then
  UNREAD="$(plain "$D" | awk -F ' · ' '{ print $4 }')"
  ok "an unreadable AWAITING.md SPEAKS — it is arrived at, not chosen" \
     "$UNREAD" "${AB_AWAITING##*/} unreadable — chmod +r $AB_AWAITING"
  ok "…and the repair is in the LINE, not in a doc the operator must go find" \
     "$(printf '%s' "$UNREAD" | grep -c -- "chmod +r $AB_AWAITING" | tr -d ' ')" 1
  # THE DISCRIMINATOR. Each state asserted on its own is satisfiable by one rendering for
  # all three; this is the assertion a re-collapse of absent onto `? need you` cannot pass.
  ok "absent, unreadable and readable are three renderings, not one" \
     "$(printf '%s\n%s\n%s\n' "$(plain "$TMP/d1")" "$(plain "$D")" "$(plain "$INST")" \
        | sort -u | wc -l | tr -d ' ')" 3
else
  no_fixture "unreadable SPEAKS, and the three states are three renderings" 3
fi
chmod 644 "$D/$AB_AWAITING"

echo
echo "== 5. a \`status:\` in the BODY is not frontmatter =="
D="$TMP/d8"; mk "$D"
printf -- '---\nstatus: done\n---\n\nstatus: in-progress\n' > "$D/projects/proj-a/tasks/task-001.md"
printf -- '---\nstatus: done\n---\n'                        > "$D/projects/proj-a/tasks/task-002.md"
ok "only the first frontmatter block counts" \
   "$(plain "$D" | sed 's/.*loopd · \([^·]*in flight\) ·.*/\1/')" "0 in flight"

echo
echo "== 6. outside a bundle it prints NOTHING, and it is not an error =="
OUT="$(run --instance "$TMP/bin" --color never; echo "rc=$?")"
ok "no instance.config.json anywhere above ⇒ no output" "${OUT%rc=*}" ""
ok "…and exit 0, because a status line never fails a session" "${OUT##*rc=}" 0
mkdir -p "$INST/projects/proj-a/tasks/deep/deeper"
ok "…while a SUBDIRECTORY of a bundle still finds it" \
   "$(plain "$INST/projects/proj-a/tasks/deep/deeper" | cut -d' ' -f1)" "loopd"

echo
echo "== 7. colour: a bare non-TTY keeps it; NO_COLOR and --color never do not =="
esc="$(printf '\033')"
esc_count() { printf '%s' "$1" | tr -cd "$esc" | wc -c | tr -d ' '; }
DEF="$(run --instance "$INST")"
ok "a pipe is still coloured — the whole point"  "$([ "$(esc_count "$DEF")" -gt 0 ] && echo yes || echo no)" yes
ok "--color never strips every escape"           "$(esc_count "$(plain "$INST")")" 0
ok "NO_COLOR strips every escape"                "$(esc_count "$(NO_COLOR=1 run --instance "$INST")")" 0
ok "--color always keeps them"                   "$([ "$(esc_count "$(run --instance "$INST" --color always)")" -gt 0 ] && echo yes || echo no)" yes
ok "…and NO_COLOR= (empty) is NOT set, so colour stays" \
   "$([ "$(esc_count "$(NO_COLOR= run --instance "$INST")")" -gt 0 ] && echo yes || echo no)" yes
ok "the coloured line is the plain one plus SGR" \
   "$(printf '%s' "$DEF" | sed "s/$esc\[[0-9;]*m//g")" "$(plain "$INST")"


# COLOURED BY STATE, which is the half of criterion 1 the plain line cannot show. Read off
# the SGR the segment is wrapped in, not off the words.
sgr_of() { # <output> <segment text> -> the code that opens it
  head -n1 <<<"$(printf '%s' "$1" | tr '\033' '\n' | grep -F "$2" | sed -n 's/^\[\([0-9;]*\)m.*/\1/p')"
}
C="$(run --instance "$INST" --color always)"
ok "work in flight is the machine's blue"  "$(sgr_of "$C" '2 in flight')" 94
ok "a queue that needs you is the human's pink" "$(sgr_of "$C" '3 need you')" 95
ok "a free lock is dim, not shouting"       "$(sgr_of "$C" 'lock free')" 2
: > "$INST/$AB_LOCK"
ok "…and a held one is the machine's blue"  "$(sgr_of "$(run --instance "$INST" --color always)" 'lock held')" 94
rm -f "$INST/$AB_LOCK"
ok "the last tick is a timestamp, so dim italic" "$(sgr_of "$C" 'last tick')" '3;2'
ok "no third hue: every code emitted is blue, pink, bold, dim or dim italic" \
   "$(printf '%s' "$C" | tr '\033' '\n' | grep -oE '^\[[0-9;]+m' | sort -u | grep -vcE '^\[(94|95|1|2|3;2|0)m$' | tr -d ' ')" 0
Z="$(run --instance "$TMP/d5" --color always)"
ok "zero in flight goes dim, not blue"      "$(sgr_of "$Z" '0 in flight')" 2
U="$(run --instance "$TMP/d4" --color always)"
ok "an unknown number is a warning, so pink" "$(sgr_of "$U" '? in flight')" 95
if unreadable "$TMP/d10/$AB_AWAITING"; then
  ok "…and so is an unreadable queue, which is a fault" \
     "$(sgr_of "$(run --instance "$TMP/d10" --color always)" 'unreadable')" 95
else
  no_fixture "…and so is an unreadable queue, which is a fault" 1
fi
chmod 644 "$TMP/d10/$AB_AWAITING"
ok "an off queue paints nothing, because it is not a fault" \
   "$(printf '%s' "$(run --instance "$TMP/d1" --color always)" | grep -c 'need you\|unreadable' | tr -d ' ')" 0

echo
echo "== 8. 3/4-bit ONLY — no 256-colour, no truecolor, no terminfo probe =="
# The codes live in cli-theme.sh; this file asks for its `basic` tier by name, never `auto`.
ok "the theme's basic tier is asked for by name" "$(grep -c 'ab_theme "\$use_color" basic' "$SL" | tr -d ' ')" 1
ok "…and this file builds no escape of its own"  "$(grep -v '^[[:space:]]*#' "$SL" | grep -c '033' | tr -d ' ')" 0
NT="$TMP/no-theme"; mkdir -p "$NT"
cp "$SL" "$REPO/plugin/scripts/bundle-paths.sh" "$NT/"
# Its own cache: this copy has no agent-sessions.sh, so it caches `agents ?` for $INST.
ok "an unsourceable theme means no colour, never no line" \
   "$(XDG_CACHE_HOME="$TMP/nt-cache" SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$NT/status-line.sh" --instance "$INST" --color always </dev/null 2>/dev/null)" \
   "$(plain "$INST" | sed 's/agents 0 running/agents ?/')"
ok "no \`38;5;\` (256-colour) anywhere"  "$(grep -c '38;5;' "$SL" | tr -d ' ')" 0
ok "no \`38;2;\` (truecolor) anywhere"   "$(grep -c '38;2;' "$SL" | tr -d ' ')" 0
ok "COLORTERM is never asked"            "$(grep -v '^[[:space:]]*#' "$SL" | grep -c 'COLORTERM' | tr -d ' ')" 0
ok "tput is never called"                "$(grep -v '^[[:space:]]*#' "$SL" | grep -c 'tput' | tr -d ' ')" 0
ok "…and \`[ -t 1 ]\` is never the colour question" \
   "$(grep -v '^[[:space:]]*#' "$SL" | grep -c -- '-t 1' | tr -d ' ')" 0

echo
echo "== 9. offline, jq-free, model-free =="
ok "nothing reached for gh/jq/git/curl"  "$([ -e "$SENTINEL" ] && cat "$SENTINEL" || echo none)" none
ok "…and none is named in the source"   "$(grep -v '^[[:space:]]*#' "$SL" | grep -cE '(^|[^a-z])(gh|jq|curl) ' | tr -d ' ')" 0

echo
echo "== 10. the session JSON on stdin: drained, and read only for a directory =="
SJ="$(printf '{"session_id":"x","workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":1.5}}' "$INST")"
ok "\`current_dir\` locates the bundle" \
   "$(printf '%s' "$SJ" | SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" --color never 2>/dev/null)" \
   "loopd · 2 in flight · agents 0 running · 3 need you · lock free · last tick $HM"
ok "…and --instance wins over it" \
   "$(printf '%s' "$SJ" | SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" --instance "$TMP/d5" --color never 2>/dev/null \
      | sed 's/.*loopd · \([^·]*in flight\) ·.*/\1/')" "0 in flight"
ok "no dollar figure is ever echoed back" \
   "$(printf '%s' "$SJ" | SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" --color never 2>/dev/null | grep -c '1\.5\|usd' | tr -d ' ')" 0

echo
echo "== 11. it is a SCRIPT, and a fast one =="
ok "ships executable" "$(cd "$REPO" && git ls-files -s plugin/scripts/status-line.sh | awk '{print $1}')" 100755
ok "bash -n clean"    "$(bash -n "$SL" 2>&1 | wc -l | tr -d ' ')" 0
# 100 invocations, wall-clock over the lot — `date +%s` is whole seconds, so a smaller
# sample cannot resolve a 50 ms call at all. Reported whatever it says; only a gross
# regression fails, because a loaded CI box is not the machine the 100 ms budget is about.
T0="$(date +%s)"; i=0
while [ "$i" -lt 100 ]; do plain "$INST" >/dev/null; i=$((i + 1)); done
T1="$(date +%s)"
ELAPSED_MS=$(( (T1 - T0) * 1000 / 100 ))
printf '  INFO  %-62s (%s ms/call over 100)\n' "measured invocation cost" "$ELAPSED_MS"
ok "…and it is nowhere near a second per call" "$([ "$ELAPSED_MS" -lt 1000 ] && echo yes || echo no)" yes

echo
echo "== 12. the mutants — these assertions discriminate =="
D="$TMP/m1"; mk "$D"; printf -- '---\nstatus: in-progress\n---\n' > "$D/projects/proj-a/tasks/task-003.md"
ok "a third in-progress task moves the number" \
   "$(plain "$D" | sed 's/.*loopd · \([^·]*in flight\) ·.*/\1/')" "3 in flight"
D="$TMP/m2"; mk "$D"
printf '%s\n' '* ❓ **answer** — [d](/projects/proj-a/tasks/task-002.md)' >> "$D/$AB_AWAITING"
ok "…and an item outside the block does NOT" \
   "$(plain "$D" | sed 's/.*· \([^·]*need you\) ·.*/\1/')" "3 need you"
D="$TMP/m3"; mk "$D"
printf '* TICK 2026-09-13T18:00:00Z by cbmono open: newer\n' >> "$D/$AB_LEDGER"
ok "a newer TICK line moves the clock" \
   "$([ "$(plain "$D" | sed 's/.*· //')" != "last tick $HM" ] && echo yes || echo no)" yes

printf '\npass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
