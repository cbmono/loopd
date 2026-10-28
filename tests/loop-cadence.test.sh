#!/usr/bin/env bash
#
# loop-cadence.test.sh — the tick cadence runs on a first-party session cron (the same
# job `/loop` creates), the dispatch skill owns that job itself, and a firing that lands
# mid-tick is a clean skip rather than a fault.
#
# WHY THIS EXISTS. `/loop [interval] <prompt>` and `/schedule` (remote routines) both ship
# with Claude Code, and until now loopd documented neither: the cadence was the owner
# re-running `/<plugin>:dispatch` by hand, or a session babysitting it. Then it was
# `/loop 10m /<plugin>:dispatch`, which worked and which nobody remembered to type — so
# since 2026-10-28 the bare skill creates the same job. Naming a cadence in
# a document is cheap and unenforced — the control panel's
# knowledge/findings/a-rule-with-no-reader-is-not-a-rule.md counts six rules in one month
# that were prose and therefore were not rules — so the half that is BEHAVIOUR is driven
# for real here against a lock file on disk, and the half that is a CONTRACT is pinned by
# phrase.
#
# THE PROPERTY, STATED SO A REVIEWER CAN REFUSE THE CHANGE ON IT. A clock knows nothing
# about tick length, so most firings of a 10m loop land while an earlier tick is still
# running. For that caller a held lock is the ORDINARY outcome, and it must read as one:
# ONE line, on STDOUT, naming when the running tick started. Not the launcher's three-to-
# six-line HELD block on stderr, which is written for a human who typed a command and
# expected a dispatch, and which repeated six times an hour teaches an operator to stop
# reading the loop's output.
#
# AND THE HALF THAT IS EASY TO GET BACKWARDS: THE EXIT CODE DOES NOT MOVE. A held lock is
# still exit 1 under `--as loop`. `0 is the only clearance to dispatch` is the invariant
# every caller of tick-lock.sh rests on, and a mode where 0 sometimes meant "do not
# dispatch" would leave the caller telling the two apart by PARSING WHAT WAS PRINTED — the
# failure recorded in the control panel's
# a-caller-cannot-act-on-a-distinction-its-classifier-does-not-draw. So section 1 asserts
# BOTH directions: the report is one quiet line, AND the code is still 1. A future edit
# that "finishes the job" by returning 0 turns this red.
#
# SECTION 3 IS A MEASUREMENT, NOT AN OPINION. The reason a scheduled cloud routine cannot
# run this loop is that `/schedule` creates REMOTE agents, which get a fresh clone of a
# GitHub repository — and a bundle's operating inputs are gitignored, so a fresh clone has
# none of them. That is checkable against the seed `.gitignore` every stamped bundle
# carries, with `git check-ignore` as the oracle, so the doc's "7 of 7" is re-measured on
# every run rather than trusted. The `.tick-lock` row is the load-bearing one: the lock is
# per clone, so a routine in its own clone is a SECOND orchestrator by a route the lock
# cannot see.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

LOCKSH="$REPO/plugin/scripts/tick-lock.sh"
DISPATCH="$REPO/plugin/skills/dispatch/SKILL.md"
AUDIT="$REPO/plugin/skills/audit/SKILL.md"
OPS="$REPO/docs/operations.md"
SEEDIGNORE="$REPO/plugin/seed/.gitignore"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/loop-cadence.XXXXXX")" || {
  echo "loop-cadence.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# One line, single-spaced: phrase matching survives a re-wrap of the document.
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }
saw() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

# =======================================================================================
echo "== 1. BEHAVIOUR: a firing that lands mid-tick is one quiet line, and still exit 1 =="
# =======================================================================================
INST="$TMP/inst"; mkdir -p "$INST" "$INST/$AB_DIR"

# A free lock: `--as loop` is the launcher in every respect — it takes it, silently, 0.
out="$(bash "$LOCKSH" acquire --as loop --agent project-manager --instance "$INST" 2>"$TMP/e1")"; rc=$?
ok "free lock: --as loop takes it"        "$rc" 0
ok "…and says nothing on stdout"          "$([ -z "$out" ] && echo yes || echo no)" yes
ok "…and nothing on stderr either"        "$([ -s "$TMP/e1" ] && echo no || echo yes)" yes
ok "…the lock is on disk"                 "$(yn test -e "$INST/$AB_LOCK")" yes

# THE CASE THIS FILE IS FOR: the lock is held (a tick from an earlier firing is running)
# and the clock fires again.
out="$(bash "$LOCKSH" acquire --as loop --agent project-manager --instance "$INST" 2>"$TMP/e2")"; rc=$?
ok "held lock: --as loop is still exit 1" "$rc" 1
ok "…the report is exactly ONE line"      "$(printf '%s\n' "$out" | grep -c .)" 1
ok "…on STDOUT, because it is not an error" "$([ -n "$out" ] && echo yes || echo no)" yes
ok "…and stderr stays empty"              "$([ -s "$TMP/e2" ] && echo no || echo yes)" yes
ok "…it says a tick is in progress"       "$(saw "$out" 'tick in progress since ')" yes
ok "…it names WHEN, from the lock"        \
  "$(saw "$out" "$(grep '^timestamp:' "$INST/$AB_LOCK" | sed 's/^timestamp: //')")" yes
ok "…it names the agent holding it"       "$(saw "$out" 'project-manager')" yes
ok "…and it dispatches nothing"           "$(saw "$out" 'nothing to dispatch this pass')" yes

# A skipped pass must leave the running tick's lock exactly as it found it. A mode that
# quietly refreshed or released it would hand the next firing a dispatch the running tick
# has not finished — the double-dispatch the lock exists to prevent, arriving via cadence.
before="$(cat "$INST/$AB_LOCK")"
bash "$LOCKSH" acquire --as loop --agent project-manager --instance "$INST" >/dev/null 2>&1
ok "a skipped pass leaves the lock untouched" "$([ "$before" = "$(cat "$INST/$AB_LOCK")" ] && echo yes || echo no)" yes
ok "…and writes no claim"                 "$(yn test -e "$INST/$AB_LOCK_CLAIM")" no

# NON-VACUITY, both halves. The launcher's own report must still be the loud multi-line
# one on stderr, or "one quiet line" above would be measuring a change everyone got.
lout="$(bash "$LOCKSH" acquire --as launcher --agent project-manager --instance "$INST" 2>"$TMP/e3")"; lrc=$?
ok "…while --as launcher is unchanged: 1" "$lrc" 1
ok "…still on stderr"                     "$([ -s "$TMP/e3" ] && echo yes || echo no)" yes
ok "…still more than one line"            "$([ "$(grep -c . "$TMP/e3")" -gt 1 ] && echo yes || echo no)" yes
ok "…and still silent on stdout"          "$([ -z "$lout" ] && echo yes || echo no)" yes

# The loud paths stay loud. A clock asking does not make a stale lock less of a human's
# problem, so STALE keeps exit 2 and its stderr text under `--as loop` too.
STALE="$TMP/stale"; mkdir -p "$STALE" "$STALE/$AB_DIR"
OLD=$(( $(date -u +%s) - 60*60*24 ))
if date -u -r 0 +%Y >/dev/null 2>&1; then OLD_ISO="$(date -u -r "$OLD" +%Y-%m-%dT%H:%M:%SZ)"
else OLD_ISO="$(date -u -d "@$OLD" +%Y-%m-%dT%H:%M:%SZ)"; fi
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$STALE/$AB_LOCK"
sout="$(bash "$LOCKSH" acquire --as loop --agent project-manager --instance "$STALE" 2>"$TMP/e4")"; src=$?
ok "stale lock under --as loop: exit 2"   "$src" 2
ok "…and it is LOUD, on stderr"           "$(grep -q '^STALE:' "$TMP/e4" && echo yes || echo no)" yes
ok "…not quietly on stdout"               "$([ -z "$sout" ] && echo yes || echo no)" yes

# `--as` still refuses a value it does not know, so the mode is a closed vocabulary and a
# typo is not silently the launcher.
bash "$LOCKSH" acquire --as lopo --instance "$INST" >/dev/null 2>"$TMP/e5"; brc=$?
ok "an unknown --as value is exit 3"      "$brc" 3
ok "…and the message lists loop"          "$(grep -q 'launcher, loop or tick' "$TMP/e5" && echo yes || echo no)" yes

# =======================================================================================
echo "== 2. CONTRACT: the dispatch skill owns the cadence — one session cron, never two =="
# =======================================================================================
D="$(flatten "$DISPATCH")"

# SINCE 2026-10-28 THE BARE COMMAND IS THE LOOP. `/loop 10m /<plugin>:dispatch` was the
# documented form, and it is a `CronCreate` over the prompt — so the skill creates that
# same job itself on its first pass, and a human typing the `/loop` form gets the same loop
# rather than a second one. The three properties that make it one loop and not two are the
# guard (create only when NO job names the skill), the grant (`CronCreate` in the
# frontmatter, or the skill prompts on every firing), and the stop (delete every job that
# names it, the skill's own or a `/loop`'s).
ok "the standard form is named, bare"     "$(saw "$D" '`/'"${PN}:"'dispatch` is the standard way to run this loop in a session — bare')" yes
ok "…it is a loop, not a tick"            "$(saw "$D" 'It is a loop, not a tick')" yes
ok "…the job's prompt is the skill, with its gap" "$(saw "$D" '`prompt` = `/'"${PN}:"'dispatch <gap>`')" yes
ok "…created only when no job names it"   "$(saw "$D" 'if **no** listed job'"'"'s prompt names `/'"${PN}:"'dispatch`, `CronCreate` one')" yes
ok "…never two jobs"                      "$(saw "$D" '**Never two jobs.**')" yes
ok "…a human's /loop job is honoured, not doubled" "$(saw "$D" 'one a human'"'"'s `/loop 10m /'"${PN}:"'dispatch` created — means the cadence is owned: create nothing')" yes
ok "…CronCreate is granted"               "$(saw "$(awk '/^---$/{d++; next} d==1 && /^allowed-tools:/' "$DISPATCH")" 'CronCreate')" yes
ok "…once is a single tick"               "$(saw "$D" '**`/'"${PN}:"'dispatch once`** | one tick, no cadence')" yes
ok "…stop deletes every job naming the skill" "$(saw "$D" '`CronDelete` every listed job whose prompt names `/'"${PN}:"'dispatch`')" yes
ok "…the seven-day expiry is stated"      "$(saw "$D" 'The job expires after seven days')" yes
ok "…and the scheduler's offset"          "$(saw "$D" 'a 10m job fires 10–15 minutes apart')" yes
ok "…the self-paced form, for a quiet bundle" "$(saw "$D" '**`/loop /'"${PN}:"'dispatch`** | no interval')" yes
ok "…and that omitting it is dynamic mode" "$(saw "$D" 'dynamic mode — the model paces its own iterations')" yes
ok "…under which no cron is created"      "$(saw "$D" 'Precondition 2 creates no cron under it; step 3 is the cadence')" yes

# THE REASON FOR THE NUMBER, not just the number. An interval with no stated basis is one
# the next reader changes by taste; the criterion asks for tick length vs review
# round-trips explicitly, because those are the two candidate bases and only one is right.
ok "the interval is NOT tuned to tick length" "$(saw "$D" 'The gap is not tuned to tick length')" yes
ok "…it is tuned to the review round-trip" "$(saw "$D" 'CodeRabbit review plus the required checks lands in')" yes

ok "under /loop the acquire uses --as loop" "$(saw "$D" 'acquire --as loop --agent project-manager')" yes
ok "…exit 1 is named a CLEAN SKIP"        "$(saw "$D" 'Exit 1 from that acquire is a CLEAN SKIP, not an error')" yes
ok "…the pass ends successfully"          "$(saw "$D" 'end the pass successfully')" yes
ok "…nothing is put in front of the human" "$(saw "$D" 'nothing put in front of the human')" yes
# /loop IS the cadence, so the skill's own wakeup must stand down or the session runs two
# schedulers and doubles its passes.
ok "…and step 3's wakeup is skipped"      "$(saw "$D" '**Skip step 3.**')" yes

# THE ONE-ORCHESTRATOR STORY, said out loud and attributed to the lock rather than to the
# paragraph — the criterion asks for the doc to say so, and for the lock to be the proof.
ok "a clock never spawns a second orchestrator" "$(saw "$D" 'A clock can never spawn a second orchestrator, and the lock is the proof')" yes
ok "…the refusal happens before any spawn" "$(saw "$D" 'refuses with exit 1 in that firing, before anything is spawned')" yes
ok "…one loop per clone still holds"      "$(saw "$D" 'per clone**, exactly as before')" yes

# NO NEW MACHINERY FOR CADENCE. The criterion is a prohibition, so it is asserted as one.
# The session cron is not machinery: it is written to no file and dies with the session,
# and the doc says so beside the prohibition.
ok "no watcher, no sleep loop, no script" \
  "$(saw "$D" 'no watcher, no `sleep` loop and no script for cadence')" yes
ok "…the one cron job is session-only"    "$(saw "$D" 'the one cron job is session-only, written to no file, and gone when the session ends')" yes
ok "…and precondition 2 still deletes the old cron" \
  "$(saw "$D" 'deletes the fixed-interval cron an older approach left behind')" yes

# THE RECONCILIATION, IN BOTH DIRECTIONS. "Serial, gated on completion, NEVER ON A CLOCK"
# was true when it was written and is the exact sentence a /loop cadence contradicts. It
# predates `.tick-lock`: what the lock changed is that an overlapping FIRING is refused
# before anything is spawned, so a clock may ask without being able to overlap. Leaving the
# old wording in place would have shipped a skill that forbids its own documented cadence,
# so the new distinction is asserted AND the old absolute is asserted gone.
ok "…the old 'never on a clock' absolute is gone" "$(saw "$D" 'never on a clock')" no
ok "…(control: the phrase is findable)"   "$(saw 'Serial, gated on completion, never on a clock.' 'never on a clock')" yes
ok "…a clock may ASK, not overlap"        "$(saw "$D" 'A clock is allowed to ASK — it is not allowed to overlap')" yes
ok "…and pm-design.md agrees"             "$(saw "$(flatten "$REPO/docs/pm-design.md")" 'A clock is allowed to *ask*; it is not allowed to *overlap*')" yes
ok "…README shows the bare form"          "$(saw "$(flatten "$REPO/README.md")" '```text /'"${PN}:"'dispatch ```')" yes
ok "…and still names the /loop form as the same loop" "$(saw "$(flatten "$REPO/README.md")" '`/loop 10m /'"${PN}:"'dispatch` creates, which still works and is the same loop')" yes

# =======================================================================================
echo "== 3. MEASURED: a remote routine's clone has none of a bundle's operating inputs =="
# =======================================================================================
# The oracle is git itself, over the seed `.gitignore` a stamped bundle carries. This is
# the doc's "7 of 7" claim, re-derived on every run.
CLONE="$TMP/clone"; mkdir -p "$CLONE" "$CLONE/$AB_DIR"
cp "$SEEDIGNORE" "$CLONE/.gitignore"
( cd "$CLONE" && git init -q . ) >/dev/null 2>&1

ignored=0
for f in instance.config.local.json "$AB_LOCK" "$AB_LOCK_CLAIM" "$AB_AWAITING" "$AB_SNAPSHOT" \
         repos/ai-bridge "$AB_BOARD_DIR/board.html"; do
  if ( cd "$CLONE" && git check-ignore -q "$f" ); then ignored=$((ignored+1))
  else printf '        NOT IGNORED (a remote clone WOULD have it): %s\n' "$f" >&2; fi
done
ok "7 of 7 operating inputs are gitignored" "$ignored" 7
# Non-vacuity: the check must be able to say "tracked", or the count above proves nothing.
ok "…while instance.config.json is tracked" \
  "$( ( cd "$CLONE" && git check-ignore -q instance.config.json ) && echo no || echo yes)" yes
ok "…and SCHEMA.md is tracked"            \
  "$( ( cd "$CLONE" && git check-ignore -q "$AB_SCHEMA" ) && echo no || echo yes)" yes

O="$(flatten "$OPS")"
ok "operations.md names the standard form" "$(saw "$O" '**`/'"${PN}:"'dispatch`.** That is the whole answer')" yes
ok "…as one session cron the skill creates" "$(saw "$O" 'the skill creates **one session-scoped cron job**')" yes
ok "…the same job /loop creates"          "$(saw "$O" '`/loop 10m /'"${PN}:"'dispatch` still works and is the same loop')" yes
ok "…and the self-paced form"             "$(saw "$O" "no interval ⇒ \`/loop\`'s dynamic mode")" yes
ok "…the measured Claude Code build"      "$(saw "$O" 'measured on **2.1.261**')" yes
ok "…that nothing is installed for cadence" "$(saw "$O" 'no watcher process, no `sleep` loop and no script in this repo')" yes
ok "…the seven-day expiry"                "$(saw "$O" 'it expires after seven days')" yes
ok "…the interval's basis"                "$(saw "$O" 'What the interval *is* tuned to is the slowest thing a tick waits on')" yes
ok "…the one-orchestrator claim, with the lock as proof" \
  "$(saw "$O" 'A clock never spawns a second orchestrator, and the lock is the proof')" yes
ok "…and the in-session never-two-jobs rule" "$(saw "$O" '**never two jobs** rule')" yes
ok "…and that the exit code does not move" "$(saw "$O" '**The exit code deliberately does not move.**')" yes

ok "…/schedule is quoted as REMOTE"       "$(saw "$O" 'scheduled **remote** Claude Code agents (routines)')" yes
ok "…the 7-of-7 measurement is stated"    "$(saw "$O" '**7 of 7 operating inputs are gitignored, so a fresh clone has none of them**')" yes
ok "…the per-clone lock is the unsafe row" "$(saw "$O" 'a routine driving `/'"${PN}:"'dispatch` would be a **second orchestrator**')" yes
ok "…and the fallback is /loop at 7d"     "$(saw "$O" '**`/loop 7d /'"${PN}:"'audit`**')" yes
ok "…pointing at the recorded Finding"    "$(saw "$O" 'a-cloud-routine-cannot-run-a-bundle-checkout')" yes

A="$(flatten "$AUDIT")"
ok "the audit skill's fallback is /loop 7d" "$(saw "$A" '`/loop 7d /'"${PN}:"'audit`')" yes
ok "…it says a routine is remote"         "$(saw "$A" 'creates *remote* Claude Code agents')" yes
# THE BABYSITTER THAT WAS REMOVED. "a cron job or your scheduler of choice" was the whole
# of the audit cadence, and it is exactly the hand-driven instruction this task deletes.
ok "…and the vague cron line is GONE"     "$(saw "$A" 'a cron job or your scheduler of')" no
ok "…(the assertion can see it: control)" "$(saw 'run it (e.g. a cron job or your scheduler of choice).' 'a cron job or your scheduler of')" yes

echo
# A suite can LOSE assertions without going red — an unterminated string once swallowed
# nine of them and the file still reported fail=0. Pin the count so a block that stops
# executing shows up here rather than as silence.
total=$((pass + fail))
ok "exactly 79 assertions ran"            "$total" 79

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
