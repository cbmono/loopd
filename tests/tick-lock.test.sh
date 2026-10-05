#!/usr/bin/env bash
#
# tick-lock.test.sh — the dispatch lock has a REAL reader, and this is it.
#
# WHY THIS FILE IS BEHAVIOURAL AND NOT A GREP. `/pm-loop` has promised "at most one PM
# tick at a time" since it was written, and on 2026-08-29 two ticks ran concurrently for
# about 34 minutes anyway, because the promise was kept by the launching session
# REMEMBERING it had dispatched — and memory does not survive a compaction. That is the
# sixth rule in one month enforced by prose rather than by a mechanism (see the control
# panel's knowledge/findings/a-rule-with-no-reader-is-not-a-rule.md), and a lock whose only
# test asserted that `pm-loop.md` mentions a lock would be the seventh. So the first half of
# this file drives the launcher's documented check-then-write path for real, against a real
# lock file on disk, including a genuine 20-way concurrent race; the document assertions in
# the second half only pin the WIRING, and are not what the criterion is satisfied by.
#
# THE FOUR PROPERTIES THAT ARE EASY TO GET BACKWARDS, each of which a reviewer should be
# able to refuse the change on, and each of which is asserted here:
#
#   1. ABSENCE IS NEVER AN ERROR. With no lock file the launcher dispatches exactly as it
#      did before this mechanism existed: silently, exit 0. The obvious implementation
#      inverts this and refuses to dispatch, which would break every instance on its first
#      upgrade. Asserted on the exit code AND on the output being byte-empty.
#   2. THE STALE PATH NEITHER STALLS NOR ADOPTS. Past the threshold the lock's timestamp
#      and agent id are surfaced, the file is NOT deleted and NOT rewritten, and no
#      dispatch happens. Silent deletion re-opens the double-dispatch; silent adoption is
#      the pressure that makes a stalled loop tempting to override.
#   3. IT IS PER CLONE, NOT CROSS-MACHINE. Two instance directories hold two independent
#      locks — because two humans sharing one bundle from two clones each dispatching is
#      the SUPPORTED design, not the bug. A test that let one lock refuse the other would
#      be pinning the wrong thing.
#   4. IT BOUNDS TICKS, NOT ROLE AGENTS. `maxAgentsInFlight` is the other concurrency
#      limit and is untouched; nothing on the role-agent path may read this file, or a
#      held lock would block the very agents the tick holding it dispatched.
#
# AND TWO MORE, ADDED 2026-08-30 AFTER THE MECHANISM SHIPPED AND THE BUG HAPPENED ANYWAY.
# About an hour after the lock merged, two `project-manager` agents ran at once: one was
# **resumed** with a message rather than dispatched, so it never passed through the launcher,
# took no lock, and was invisible to one. The guard behaved exactly as designed. So:
#
#   5. THE TICK RUNS THE ACQUIRE TOO, NOT ONLY THE LAUNCHER. A tick that began without a
#      dispatch reaches the same gate. Everything above this line passed while that gap was
#      open, which is precisely how it survived a whole harness: a mechanism on the path
#      you were thinking about is not a mechanism on every path.
#   6. AND A DISPATCHED TICK MUST NOT REFUSE ITS OWN LOCK — the crux, and the failure mode
#      of the obvious fix. The launcher takes the lock and then spawns; the tick then finds
#      a held lock that is its own. Get that wrong and EVERY dispatched tick deadlocks on
#      entry, a total outage strictly worse than the concurrency bug. So the sequence is
#      driven here for real, in order, and the tick is asserted to PROCEED — and to proceed
#      by ADOPTING (`adopted:`) rather than by taking a lock of its own, because a tick that
#      "proceeded" because the lock had vanished would pass a weaker test for the wrong
#      reason.
#
# AND A SEVENTH, ADDED HOURS AFTER THE SIXTH SHIPPED, FOR THE SAME REASON ONE LEVEL DOWN.
# A dispatched tick held and dispatched nothing, reporting a different tick — and the claim
# it had found was its own (`taken 13:28:49Z` by the launcher, `claimed 13:29:33Z` by the
# tick it spawned). Existence was the claim's whole signal, so it recorded THAT somebody
# claimed and never WHO, and any re-entry — a second acquire, a resume, a retry — made a
# tick an intruder to itself. So:
#
#   7. A TICK MEETING ITS OWN CLAIM PROCEEDS; A TICK MEETING A DIFFERENT ONE STILL HOLDS.
#      Both halves, or neither is worth anything: drop the first and every re-entering
#      dispatch deadlocks (the outage property 6 exists to prevent, moved one level down);
#      drop the second and the 34-minute double-dispatch of 2026-08-29 is back. The exact
#      failing sequence is driven below, in order, and so is a genuinely different tick at
#      the same lock.
#
# AND AN EIGHTH, WHICH IS WHAT MADE THE SEVENTH SAFE TO SHIP. Property 7's first
# implementation resolved identity from `CLAUDE_CODE_SESSION_ID`. That variable was then
# MEASURED, in a parent session and in a subagent it dispatched:
#
#     parent    CLAUDE_CODE_SESSION_ID=aaf01a1c-fc30-4e96-99e9-a2c43733c10f
#     subagent  CLAUDE_CODE_SESSION_ID=aaf01a1c-fc30-4e96-99e9-a2c43733c10f
#
# One id per SESSION, so every tick a loop starts is one claimant and a match proves nothing
# — and the sequence it would wave through (launcher dispatches A, A claims, the SAME
# session resumes R, R meets A's claim) is precisely the one property 7 keeps the claimed
# branch for. Hence:
#
#   8. A DERIVED IDENTITY MAY REFUSE A CLAIM AND MAY NEVER CLEAR ONE. Only two DECLARED ids
#      (`--claimant`, `TICK_CLAIMANT`) that match are a re-entry. A session-derived id that
#      merely matches is exit 2, a human's call. THIS IS THE PROPERTY TO REFUSE A CHANGE ON:
#      a diff that turns any exit 2 below into an exit 0 has re-opened 2026-08-29, and no
#      other assertion in this file would notice.
#
#
# AND A NINTH, WHICH IS WHERE THE FIFTH TURNED OUT TO BE HALF AN ANSWER:
#
#   9. A RESUMED TICK IS REFUSED, NOT MERELY DETECTED. Property 5 let the resumed tick take
#      a lock of its own, so the next genuine dispatch stood down instead: exactly one tick
#      ran, and it was the wrong one — a tick re-entering a loop whose state has moved on.
#      A tick may now only ADOPT a launcher's lock; finding none is proof that nothing
#      dispatched it, and it exits 4 without running, without taking a lock, and without
#      leaving a claim. Asserted on the exit code, on the empty instance directory
#      afterwards, and — because a guard nobody can break is not a guard — against a MUTANT
#      copy of the script with the refusal stripped out, which must proceed where the real
#      one refuses. The half that has no reader is named here too, and asserted in the
#      "whichever order they arrive in" section: a resume landing inside the launcher's
#      dispatch window meets an unclaimed lock and is indistinguishable from the tick that
#      lock was taken for.
#
# AND A TENTH, WHICH IS THE FIRST TIME EITHER ACQUIRE SITE ACTUALLY DECLARES AN ID:
#
#  10. THE LAUNCHER MINTS THE ID AND BOTH SITES PASS IT. Property 8 made a DECLARED match
#      the only proof, and then nobody declared: both callers ran with `--agent` alone, so
#      the derived tier answered and a tick meeting its own claim reached exit 2 on the
#      ordinary path. The launcher now mints one literal per tick, records it in the LOCK
#      (the only place it lives — it writes no claim), and hands it to the tick. What must
#      NOT come with it: an id checked on ADOPT. Adopting proves you are the dispatch, not
#      who you are, so a mismatch there is reported and never refused — matching it would
#      close the 41-47s window at the price of one mis-typed literal refusing EVERY tick.
#
# EVERY TICK IN THIS FILE STATES ITS IDENTITY, AND THE ENVIRONMENT'S IS UNSET ON PURPOSE.
# `--claimant` is the explicit source; absent one the script falls back to `TICK_CLAIMANT`
# and then to the runtime's `CLAUDE_CODE_SESSION_ID`. A harness that inherited either would
# hand EVERY subshell here one identity — 20 "concurrent ticks" would all be the same tick,
# correctly, and the race assertions would go quietly vacuous. Unset, so a call without
# `--claimant` models the OTHER real case: a tick whose environment cannot identify it,
# which must degrade to exactly the pre-claimant behaviour and never past it. The
# environment-derived path gets its own block below, where it is set deliberately.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail
unset CLAUDE_CODE_SESSION_ID TICK_CLAIMANT

TPL="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

LOCKSH="$TPL/plugin/scripts/tick-lock.sh"
LAUNCHER="$TPL/plugin/skills/dispatch/SKILL.md"
TICK="$TPL/plugin/agents/project-manager.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tick-lock.XXXXXX")" || {
  echo "tick-lock.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
has() { # <file> <fixed-string> -> yes|no
  grep -qF -- "$2" "$1" && echo yes || echo no
}
# Read one field back out of a lock or claim, the way a human would. Deliberately a
# different (and dumber) reader than the script's own, so a bug in one is not hidden by the
# same bug in the other.
# How many of the lock's files exist. A glob rather than `ls | grep`, so a name with a
# space could not be miscounted — and the point of the count is that there are only ever two.
lock_files() { # <instance-dir>
  local n=0 f
  for f in "$1/$AB_LOCK"*; do [ -e "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

lock_field_of() { # <file> <key>
  head -1 <<<"$(sed -n "s/^$2: *//p" "$1" 2>/dev/null)"
}

# The same BSD-then-GNU order the script itself uses: `-r` is macOS's, `-d @…` is
# coreutils', and each is an error to the other.
iso_of() { # <epoch>
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# ============================================================ THE LAUNCHER, DRIVEN
# `/pm-loop` step 1, transcribed: resolve the model, run `acquire`, and spawn the tick if
# and ONLY if it exits 0 — with nothing between the acquire and the spawn. The spawn is a
# line appended to `dispatched.log`, which stands in for the `Agent` call a harness cannot
# make; everything the criterion is about (did a dispatch happen, and what decided it)
# is visible in that file.
ATTEMPT_RC=0; ATTEMPT_OUT=""
attempt() { # <instance-dir> [agent-id]
  local inst="$1" agent="${2:-project-manager}"
  ATTEMPT_OUT="$(bash "$LOCKSH" acquire --instance "$inst" --agent "$agent" 2>&1)"
  ATTEMPT_RC=$?
  [ "$ATTEMPT_RC" -eq 0 ] && printf 'tick dispatched: %s\n' "$agent" >> "$inst/dispatched.log"
  return 0
}
# The same launcher, declaring the per-tick id it minted — `/<plugin>:dispatch` step 1
# since 2026-09-06. Separate from attempt() so the un-declared path above stays driven too:
# a bundle whose launcher declares nothing must behave exactly as it did before.
attempt_as() { # <instance-dir> <minted-id>
  ATTEMPT_OUT="$(bash "$LOCKSH" acquire --instance "$1" --agent project-manager \
    --claimant "$2" 2>&1)"
  ATTEMPT_RC=$?
  [ "$ATTEMPT_RC" -eq 0 ] && printf 'tick dispatched: %s\n' "$2" >> "$1/dispatched.log"
  return 0
}
dispatches() { # <instance-dir> -> how many ticks the launcher actually spawned
  [ -f "$1/dispatched.log" ] && wc -l < "$1/dispatched.log" | tr -d ' ' || echo 0
}

# And the TICK's own step 0.5, transcribed the same way: `project-manager.md` runs the
# acquire before it re-derives anything, and does its tick if and only if that exits 0. A
# line in `ran.log` stands in for the tick actually running. `dispatched.log` counts what
# the launcher spawned; `ran.log` counts what actually RAN — and the two differ precisely
# in the cases this file was extended for, which is why they are counted separately.
TICK_RC=0; TICK_OUT=""
tick() { # <instance-dir> [agent-id] [claimant] — a tick at its step 0.5, however it began
  # The third argument is WHICH TICK this is, and it is what the same-tick / different-tick
  # assertions turn on — `--agent` names a ROLE and cannot separate two ticks of one role,
  # which is the case that failed. Omitted means no identity at all (see the header).
  local inst="$1" agent="${2:-project-manager}" who="${3:-}"
  TICK_OUT="$(bash "$LOCKSH" acquire --as tick --instance "$inst" --agent "$agent" \
    ${who:+--claimant "$who"} 2>&1)"
  TICK_RC=$?
  [ "$TICK_RC" -eq 0 ] && printf 'tick ran: %s\n' "$agent" >> "$inst/ran.log"
  return 0
}
ran() { # <instance-dir> -> how many ticks actually proceeded past step 0.5
  [ -f "$1/ran.log" ] && wc -l < "$1/ran.log" | tr -d ' ' || echo 0
}
said() { # <fixed-string> -> yes|no, against the last tick's output
  grep -qF -- "$1" <<<"$TICK_OUT" && echo yes || echo no
}

echo "== absence is never an error: no lock, so it dispatches, in silence =="
A="$TMP/a"; mkdir -p "$A" "$A/$AB_DIR"
attempt "$A"
ok "exit 0 on a missing lock"            "$ATTEMPT_RC" 0
ok "…and it dispatched"                  "$(dispatches "$A")" 1
ok "…printing nothing at all"            "$ATTEMPT_OUT" ""
ok "…having created the lock"            "$(yn test -f "$A/$AB_LOCK")" yes
ok "…which names the agent"              "$(has "$A/$AB_LOCK" 'agent: project-manager')" yes
ok "…and an ISO-8601 UTC timestamp" \
  "$(grep -cE '^timestamp: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$A/$AB_LOCK" | tr -d ' ')" 1

echo
echo "== the same attempt against a FRESH lock does not dispatch =="
attempt "$A"
ok "exit 1 — held"                       "$ATTEMPT_RC" 1
ok "…and NO second tick was dispatched"  "$(dispatches "$A")" 1
ok "…saying a tick is in flight"         "$(grep -qF 'HELD' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes
ok "…and naming who holds it"            "$(grep -qF 'project-manager' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes

echo
echo "== release, and the very same attempt dispatches again =="
bash "$LOCKSH" release --instance "$A" >/dev/null 2>&1
ok "release exits 0"                     "$?" 0
ok "…and the lock is gone"               "$(yn test -e "$A/$AB_LOCK")" no
attempt "$A"
ok "exit 0 again"                        "$ATTEMPT_RC" 0
ok "…and it dispatched a second tick"    "$(dispatches "$A")" 2
# Releasing a lock nobody holds is the normal outcome of an interrupted loop, so it must
# be a silent success rather than a failure the launcher has to reason about.
bash "$LOCKSH" release --instance "$A" >/dev/null 2>&1
OUT="$(bash "$LOCKSH" release --instance "$A" 2>&1)"; RC=$?
ok "release on a missing lock: exit 0"   "$RC" 0
ok "…in silence"                         "$OUT" ""

echo
echo "== the race the mechanism exists for: 20 attempts, one dispatch =="
# The real property, not a proxy for it. `acquire` creates the file with O_EXCL, so the
# check and the write are one syscall and there is no window to interleave with — which is
# exactly what the tick's own ledger check (project-manager.md step 0.5) cannot claim,
# since it reads, then syncs, then writes.
R="$TMP/race"; mkdir -p "$R" "$R/$AB_DIR"
for i in $(seq 1 20); do
  ( bash "$LOCKSH" acquire --instance "$R" >/dev/null 2>&1 && : > "$R/won.$i" ) &
done
wait
ok "exactly one attempt won the lock" \
  "$(find "$R" -maxdepth 1 -name 'won.*' | wc -l | tr -d ' ')" 1
# NON-VACUITY: the same 20 parallel attempts must be able to produce 20 wins, or "one
# winner" would be a property of the loop rather than of the lock.
for i in $(seq 1 20); do
  ( mkdir -p "$TMP/solo/$i" && bash "$LOCKSH" acquire --instance "$TMP/solo/$i" >/dev/null 2>&1 \
    && : > "$TMP/solo/$i/won" ) &
done
wait
ok "…and 20 separate instances give 20 wins" \
  "$(find "$TMP/solo" -maxdepth 3 -name 'won' | wc -l | tr -d ' ')" 20

echo
echo "== stale: surfaced to the human, not deleted and not adopted =="
S="$TMP/stale"; mkdir -p "$S" "$S/$AB_DIR"
OLD=$(( $(date -u +%s) - 9000 ))          # 2h30m ago, past the 120m default
OLD_ISO="$(iso_of "$OLD")"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$S/$AB_LOCK"
BEFORE="$(cat "$S/$AB_LOCK")"
attempt "$S"
ok "exit 2 — a human decides"            "$ATTEMPT_RC" 2
ok "…and NOTHING was dispatched"         "$(dispatches "$S")" 0
ok "…it says STALE"                      "$(grep -qF 'STALE' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes
ok "…surfacing the lock's timestamp"     "$(grep -qF "$OLD_ISO" <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes
ok "…and the agent id it names"          "$(grep -qF 'agent:     project-manager' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes
ok "…and the age it computed"            "$(grep -qF '2h30m' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes
ok "the lock was NOT deleted"            "$(yn test -f "$S/$AB_LOCK")" yes
ok "…and NOT rewritten (not adopted)"    "$( [ "$(cat "$S/$AB_LOCK")" = "$BEFORE" ] && echo yes || echo no)" yes
# The threshold is a knob, not a constant, and the same lock reads live under a bigger one
# — so "stale" is a computation over the file, not a property baked into the code path.
OUT="$(TICK_LOCK_STALE_MINUTES=600 bash "$LOCKSH" status --instance "$S" 2>&1)"; RC=$?
ok "…and a larger threshold reads it as held" "$RC" 1

echo
echo "== liveness is computed FROM THE FILE, timestamp alone is enough =="
# A lock carrying only the human-readable field still answers "is this stale?" — the
# criterion is that a reader never needs session memory, git log or the tick ledger.
T2="$TMP/tsonly"; mkdir -p "$T2" "$T2/$AB_DIR"
printf 'timestamp: %s\nagent: cataloguer\n' "$OLD_ISO" > "$T2/$AB_LOCK"
attempt "$T2"
ok "exit 2 from the timestamp alone"     "$ATTEMPT_RC" 2
ok "…still no dispatch"                  "$(dispatches "$T2")" 0
ok "…naming the agent the file records"  "$(grep -qF 'cataloguer' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes

echo
echo "== a lock that cannot answer, and one dated in the future, both ask a human =="
U="$TMP/unreadable"; mkdir -p "$U" "$U/$AB_DIR"
printf 'this is not a lock\n' > "$U/$AB_LOCK"
attempt "$U"
ok "unreadable: exit 2"                  "$ATTEMPT_RC" 2
ok "…no dispatch"                        "$(dispatches "$U")" 0
ok "…and it is left on disk"             "$(yn test -f "$U/$AB_LOCK")" yes
F="$TMP/future"; mkdir -p "$F" "$F/$AB_DIR"
AHEAD=$(( $(date -u +%s) + 86400 ))
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$(iso_of "$AHEAD")" "$AHEAD" > "$F/$AB_LOCK"
attempt "$F"
# A future-dated lock can never age out, so treating it as merely "held" would stall the
# loop forever with nobody told why.
ok "future-dated: exit 2, not a silent wait" "$ATTEMPT_RC" 2
ok "…no dispatch"                        "$(dispatches "$F")" 0

echo
echo "== per clone, NOT cross-machine: two clones dispatch independently =="
# The supported design (`/pm-loop` -> "Why serial"; SCHEMA.md -> "Ownership on a shared
# instance"): two humans, one bundle, two clones. A lock that reached across them would
# break it, which is why it is gitignored and why this is asserted rather than assumed.
C1="$TMP/clone1"; C2="$TMP/clone2"; mkdir -p "$C1" "$C1/$AB_DIR" "$C2" "$C2/$AB_DIR"
attempt "$C1"; ok "clone 1 dispatches"   "$ATTEMPT_RC" 0
attempt "$C2"; ok "clone 2 dispatches too, while clone 1 holds" "$ATTEMPT_RC" 0
ok "…each holding its own lock" \
  "$( [ -f "$C1/$AB_LOCK" ] && [ -f "$C2/$AB_LOCK" ] && echo yes || echo no)" yes
attempt "$C1"; ok "…and clone 1 still refuses ITSELF" "$ATTEMPT_RC" 1

echo
echo "== THE CRUX: the launcher takes it, then the tick it spawned takes it and PROCEEDS =="
# The real sequence, in order, with nothing mocked: /pm-loop step 1 acquires and spawns;
# project-manager.md step 0.5 acquires. If the tick cannot tell "held by the launcher that
# spawned me" from "held by someone else", this is where every dispatched tick deadlocks —
# an outage of the whole loop, worse than the bug being fixed.
H="$TMP/handoff"; mkdir -p "$H" "$H/$AB_DIR"
attempt "$H"
ok "the launcher took the lock"          "$ATTEMPT_RC" 0
ok "…and spawned a tick"                 "$(dispatches "$H")" 1
tick "$H"
ok "the tick it spawned PROCEEDS"        "$TICK_RC" 0
ok "…and actually ran"                   "$(ran "$H")" 1
ok "…by adopting the launcher's lock"    "$(said 'adopted:')" yes
# Not by taking one of its own: a tick that "proceeded" because the lock had gone would
# pass the exit-code assertion above for entirely the wrong reason.
ok "…not by taking a lock of its own"    "$(said 'took:')" no
ok "…and the lock is still the launcher's one lock" \
  "$(yn test -f "$H/$AB_LOCK")" yes
ok "…now carrying the tick's claim"      "$(yn test -f "$H/$AB_LOCK_CLAIM")" yes

echo
echo "== …and a DIFFERENT tick, at that same lock, reports and holds =="
# The resumed tick of 2026-08-30 arriving while a dispatched one is running.
tick "$H" cataloguer
ok "the second tick is refused"          "$TICK_RC" 1
ok "…and did NOT run"                    "$(ran "$H")" 1
ok "…saying another tick holds it"       "$(said 'HELD BY ANOTHER TICK')" yes
ok "…naming who claimed it"              "$(said 'project-manager')" yes
ok "…and telling it to hold, not adopt"  "$(said 'adopt nothing')" yes
ok "…and to release nothing"             "$(said 'release nothing')" yes
# The launcher, meanwhile, sees exactly what it saw before this change: a held lock.
attempt "$H"
ok "the launcher still just sees HELD"   "$ATTEMPT_RC" 1
ok "…and dispatched nothing more"        "$(dispatches "$H")" 1
ok "…and can see the tick is RUNNING, not merely dispatched" \
  "$(grep -qF 'it is RUNNING' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes

echo
echo "== the measured bug: a RESUMED tick is REFUSED, and never runs at all =="
# The whole point, and property 9. A message wakes a completed agent directly — no
# launcher, no dispatch — so nothing took a lock before it started, and the ABSENCE of one
# is the evidence: the launcher takes the lock in the same breath as the spawn, so a tick
# that finds none did not come through it.
#
# THE FIRST FIX HERE LET THAT TICK TAKE A LOCK OF ITS OWN, and this section asserted it.
# That made the next genuine dispatch stand down, so exactly one tick ran — the property
# being defended — and it was the WRONG one: a tick re-entering a loop whose state has
# moved on, holding context from work already finished. Inverted deliberately, in the same
# change that makes a tick never resumable; the ordering assertions below are what proves
# the inversion did not simply delete the guarantee.
R2="$TMP/resume"; mkdir -p "$R2" "$R2/$AB_DIR"
tick "$R2"                                # resumed: it did not pass through the launcher
ok "the resumed tick is REFUSED"         "$TICK_RC" 4
ok "…and did NOT run"                    "$(ran "$R2")" 0
ok "…saying no launcher took a lock for it" "$(said 'NO DISPATCH LOCK')" yes
ok "…naming the resume as the case"      "$(said 'never resumed')" yes
ok "…and telling it to end the tick"     "$(said 'End the tick')" yes
# It must leave NOTHING behind. A refusal that still created the lock would block the next
# genuine dispatch for two hours, turning a refused resume into an outage.
ok "…taking no lock of its own"          "$(yn test -e "$R2/$AB_LOCK")" no
ok "…and writing no claim either"        "$(yn test -e "$R2/$AB_LOCK_CLAIM")" no
# …so the loop is entirely unaffected: the next real dispatch proceeds exactly as it would
# have if the resumed tick had never happened.
attempt "$R2"
ok "the launcher then dispatches normally" "$ATTEMPT_RC" 0
ok "…and its own tick adopts that lock"  "$(tick "$R2"; said 'adopted:')" yes
ok "…so exactly one tick ran, the dispatched one" "$(ran "$R2")" 1

echo
echo "== and the refusal is not decoration: strip it and the resumed tick runs again =="
# A guard is only a guard if its removal is detectable, so the removal is performed here.
# `MUTANT` is this script with the two `refuse_unlaunched` calls in `acquire` deleted —
# nothing else — which is exactly the edit a future "simplification" would make.
MUT="$TMP/mutant"; mkdir -p "$MUT" "$MUT/$AB_DIR"
MUTANT="$MUT/tick-lock.sh"
sed 's/^\( *\)refuse_unlaunched$/\1: # refusal removed/' "$LOCKSH" > "$MUTANT"
ok "the mutant differs from the real script" \
  "$(cmp -s "$MUTANT" "$LOCKSH" && echo same || echo differs)" differs
ok "…and is still valid shell"           "$(yn bash -n "$MUTANT")" yes
# The same sequence against both scripts, from identical empty instances, so the only
# variable is the refusal itself.
MR="$TMP/mutant-run"; MRR="$TMP/real-run"; mkdir -p "$MR" "$MR/$AB_DIR" "$MRR" "$MRR/$AB_DIR"
# tick-lock.sh sources its sibling resolver (ai-bridge-v3/task-031); the mutant lives in
# $TMP, so the resolver has to as well or it exits 2 before reaching the refusal.
cp "$(dirname "$LOCKSH")/bundle-paths.sh" "$MUT/bundle-paths.sh"
bash "$MUTANT" acquire --as tick --instance "$MR"  >/dev/null 2>&1; MUT_RC=$?
bash "$LOCKSH" acquire --as tick --instance "$MRR" >/dev/null 2>&1; REAL_RC=$?
ok "the real script refuses that resumed tick"    "$REAL_RC" 4
ok "…and with the refusal stripped it does not"   "$MUT_RC" 0
ok "…so an assertion here fails the moment the refusal is removed" \
  "$(if [ "$MUT_RC" != "$REAL_RC" ]; then echo detectable; else echo invisible; fi)" detectable

echo
echo "== two concurrent ticks cannot both proceed, whichever order they arrive in =="
# Order A is the paragraph above (the resume never starts). Order B is the launcher
# first: a resumed tick reaching step 0.5 before the dispatched one meets an unclaimed
# lock and adopts it, and the dispatched tick then holds — still exactly one tick running,
# which is the property, though not the same one. This is the one way a resumed tick still
# gets through, and it is asserted rather than left implicit: closing it would mean telling
# two ticks apart at the instant neither has claimed anything.
B="$TMP/order-b"; mkdir -p "$B" "$B/$AB_DIR"
attempt "$B"                              # launcher takes the lock…
tick "$B" cataloguer                      # …a resumed tick gets to step 0.5 first
tick "$B" project-manager                 # …and the dispatched tick arrives after
ok "exactly one of the two ticks ran"    "$(ran "$B")" 1
ok "…and it is the one that got there first" \
  "$(grep -c 'cataloguer' "$B/ran.log" | tr -d ' ')" 1

echo
echo "== 20 ticks racing for ONE unclaimed dispatch lock: exactly one adopts it =="
# The claim is created with O_EXCL for the same reason the lock is. A claim written by
# read-then-write would re-open, one layer down, the very race `acquire` exists to close —
# and it would do it in the adoption path, which is the one nobody would think to test.
A2="$TMP/adopt-race"; mkdir -p "$A2" "$A2/$AB_DIR"
bash "$LOCKSH" acquire --instance "$A2" >/dev/null 2>&1     # the launcher's lock
for i in $(seq 1 20); do
  ( bash "$LOCKSH" acquire --as tick --instance "$A2" >/dev/null 2>&1 && : > "$A2/adopted.$i" ) &
done
wait
ok "exactly one tick adopted it" \
  "$(find "$A2" -maxdepth 1 -name 'adopted.*' | wc -l | tr -d ' ')" 1

echo
echo "== THE 2026-08-30 SEQUENCE: a tick meets its OWN claim and PROCEEDS =="
# The exact failing sequence, in order and with nothing mocked: the launcher acquires
# (13:28:49Z), the tick it spawned claims (13:29:33Z), and then THAT SAME TICK acquires
# again — a retry, a resume, a re-run of step 0.5. Until the claim recorded a claimant it
# read as a different tick, so the tick stood down on its own claim and dispatched nothing.
# Note both ticks below carry `--agent project-manager`: the role is identical and cannot
# be what separates them, which is precisely why `--agent` is not the identity.
E="$TMP/reentry"; mkdir -p "$E" "$E/$AB_DIR"
attempt "$E"
ok "the launcher took the lock"          "$ATTEMPT_RC" 0
tick "$E" project-manager pm-tick-1
ok "the tick it spawned adopted it"      "$TICK_RC" 0
ok "…and ran"                            "$(ran "$E")" 1
CLAIM_BEFORE="$(cat "$E/$AB_LOCK_CLAIM")"
tick "$E" project-manager pm-tick-1       # ← THE SAME TICK, acquiring a second time
ok "the SAME tick proceeds, not holds"   "$TICK_RC" 0
ok "…and actually ran"                   "$(ran "$E")" 2
ok "…saying it re-entered its own claim" "$(said 're-entered:')" yes
ok "…and NOT that another tick holds it" "$(said 'HELD BY ANOTHER TICK')" no
# The obligation is re-stated, not re-derived: this tick ADOPTED the launcher's lock, and a
# re-entry that answered `took:` would have it delete a lock /pm-loop is still holding.
ok "…re-stating the obligation it was given" "$(said 'adopted:')" yes
ok "…and never turning it into one it may release" "$(said 'took:')" no
# Nothing on disk moved. Asserted byte-for-byte because the claim carries a timestamp, and
# a re-entry that refreshed it would have quietly built the second clock this design refuses.
ok "…and the claim is byte-identical afterwards" \
  "$( [ "$(cat "$E/$AB_LOCK_CLAIM")" = "$CLAIM_BEFORE" ] && echo yes || echo no)" yes
ok "…with the lock still the launcher's one lock" "$(yn test -f "$E/$AB_LOCK")" yes

echo
echo "== …and a genuinely DIFFERENT tick at that same claim still HOLDS =="
# The other half, and the one that must not be paid for the half above: losing it re-opens
# the 34-minute double-dispatch of 2026-08-29. Same role, same lock, different tick.
tick "$E" project-manager pm-tick-2
ok "the different tick is refused"       "$TICK_RC" 1
ok "…and did NOT run"                    "$(ran "$E")" 2
ok "…saying another tick holds it"       "$(said 'HELD BY ANOTHER TICK')" yes
ok "…telling it to adopt nothing"        "$(said 'adopt nothing')" yes
ok "…and to release nothing"             "$(said 'release nothing')" yes
ok "…and it is not called a re-entry"    "$(said 're-entered:')" no

echo
echo "== a resume is refused in BOTH directions, which is why both guards are here =="
# THE COMPOSED PROPERTY, and the reason neither guard replaces the other. `SendMessage` wakes
# a completed tick in a NEW process — no launcher, nothing in memory surviving — and it meets
# exactly one of two states on disk, in neither of which it may run:
#
#   its predecessor is STILL RUNNING  a live lock carrying that tick's claim. The CLAIMANT
#                                     check answers it: a different id holds (1), a merely
#                                     matching one is a human's call (2).
#   its predecessor already RELEASED  no lock at all. The ABSENCE is the evidence, because
#                                     only a launcher takes one before a tick exists (4).
#
# Drop the second and a resume takes a lock of its own and stands the next genuine dispatch
# down; drop the first and a resume runs beside a live tick. Both halves, driven in order.
RE="$TMP/resume-id"; mkdir -p "$RE" "$RE/$AB_DIR"
attempt "$RE"                             # the launcher, dispatching tick A
tick "$RE" project-manager tick-A
ok "the dispatched tick adopts"          "$TICK_RC" 0
ok "…the launcher's lock, not one of its own" "$(said 'adopted:')" yes
ok "…so it is never told it may release it"   "$(said 'took:')" no
tick "$RE" project-manager resumed-R      # woken while A is still running
ok "a resume beside a live tick holds"   "$TICK_RC" 1
ok "…saying another tick holds it"       "$(said 'HELD BY ANOTHER TICK')" yes
ok "…and did not run"                    "$(ran "$RE")" 1
bash "$LOCKSH" release --instance "$RE" >/dev/null 2>&1   # A ends; the launcher releases
tick "$RE" project-manager resumed-R      # woken again, after its predecessor is gone
ok "a resume after that lock went is REFUSED" "$TICK_RC" 4
ok "…saying no launcher took one for it" "$(said 'NO DISPATCH LOCK')" yes
ok "…and still did not run"              "$(ran "$RE")" 1
ok "…leaving no lock of its own behind"  "$(yn test -e "$RE/$AB_LOCK")" no

echo
echo "== THE LAUNCHER MINTS THE ID: it lives in the lock, and in no second file =="
# 2026-09-06 (ai-bridge-next/task-009). Property 8 made a DECLARED match the only proof and
# then neither caller declared, so the derived tier answered and a tick meeting its own claim
# was exit 2 on the ORDINARY path. The launcher now mints one literal per tick and passes it
# to its own acquire; `.tick-lock` records it and nothing else on disk does.
ID=tick-20260906T152233Z-a7f3
MINT="$TMP/minted"; mkdir -p "$MINT" "$MINT/$AB_DIR"
attempt_as "$MINT" "$ID"
ok "the launcher takes the lock with an id" "$ATTEMPT_RC" 0
ok "…still in silence"                     "$ATTEMPT_OUT" ""
ok "…the LOCK records the claimant"        "$(lock_field_of "$MINT/$AB_LOCK" claimant)" "$ID"
ok "…and the source that declared it"      "$(lock_field_of "$MINT/$AB_LOCK" claimant-source)" flag
ok "…the launcher writes NO claim"         "$(yn test -e "$MINT/$AB_LOCK_CLAIM")" no
ok "…and there is exactly one lock file"   "$(lock_files "$MINT")" 1
# The dispatch window is 41-47s wide, and inside it the lock is the only thing on disk that
# can say which tick is coming. `status` reads it out rather than making a human cat the file.
SOUT="$(bash "$LOCKSH" status --instance "$MINT" 2>&1)"
ok "status names the tick it was minted for" "$(grep -qF "minted for: $ID" <<<"$SOUT" && echo yes || echo no)" yes
ok "…and still says nobody has claimed it"   "$(grep -qF 'No tick has claimed it yet' <<<"$SOUT" && echo yes || echo no)" yes

echo
echo "== …so the tick that carries it RE-ENTERS (0) where it used to reach a human (2) =="
tick "$MINT" project-manager "$ID"
ok "the dispatched tick adopts"          "$TICK_RC" 0
ok "…and says nothing about a mismatch"  "$(said 'note:')" no
tick "$MINT" project-manager "$ID"        # the same tick, acquiring a second time
ok "its second acquire is exit 0"        "$TICK_RC" 0
ok "…as a proved re-entry"               "$(said 're-entered:')" yes
ok "…and never as a human'\''s call"       "$(said 'CANNOT ATTRIBUTE')" no
# THE ROW THAT DOES NOT MOVE. Two DECLARED ids that differ are `theirs` — exit 1, today's
# answer — and exit 2 keeps maybe/stale/future/unreadable and nothing else. Routing this to
# 2 would send the resumed-tick case this whole mechanism exists for to a human every time.
tick "$MINT" project-manager tick-20260906T152233Z-b9c1
ok "a DIFFERENT declared id is exit 1"   "$TICK_RC" 1
ok "…reported as another tick'\''s"        "$(said 'HELD BY ANOTHER TICK')" yes
ok "…and never as CANNOT ATTRIBUTE"      "$(said 'CANNOT ATTRIBUTE')" no
ok "…and it did not run"                 "$(ran "$MINT")" 2
# Released with the lock, and outliving nothing: the id is a field in a file `release` removes.
bash "$LOCKSH" release --instance "$MINT" >/dev/null 2>&1
ok "release takes the id with the lock"  "$(lock_files "$MINT")" 0

echo
echo "== adopting proves RE-ENTRY ONLY: a mis-copied id still runs, and is told so =="
# THE PROPERTY TO REFUSE A CHANGE ON, and the inverse of the one above. Matching the id on
# ADOPT would close the 41-47s dispatch window — and one mis-typed literal would then refuse
# every dispatched tick, the total outage this design calls strictly worse than the bug. So a
# mismatch here is REPORTED and the tick runs.
WIN="$TMP/mint-typo"; mkdir -p "$WIN" "$WIN/$AB_DIR"
attempt_as "$WIN" tick-A
tick "$WIN" project-manager tick-typo
ok "a tick whose id differs still adopts" "$TICK_RC" 0
ok "…and actually ran"                    "$(ran "$WIN")" 1
ok "…adopting, not taking a lock"         "$(said 'adopted:')" yes
ok "…and is told which id the lock carries" "$(said 'was minted for tick-A')" yes
ok "…without being refused"               "$(said 'HELD BY ANOTHER TICK')" no

echo
echo "== declare nothing and NOTHING changes: the derived tier is still the fallback =="
# Criterion 4, and the direction that must never invert: a bundle that never adopts the
# launcher path behaves exactly as it did before any of this. A session-derived id names the
# session that ran the LAUNCHER, not the tick it is about to spawn, so it is not recorded.
OLDW="$TMP/undeclared"; mkdir -p "$OLDW" "$OLDW/$AB_DIR"
CLAUDE_CODE_SESSION_ID=aaf01a1c-fc30-4e96-99e9-a2c43733c10f \
  bash "$LOCKSH" acquire --instance "$OLDW" --agent project-manager >/dev/null 2>&1
ok "an undeclared launcher writes no claimant" "$(grep -c '^claimant:' "$OLDW/$AB_LOCK" | tr -d ' ')" 0
ok "…nor a source for one"                     "$(grep -c '^claimant-source:' "$OLDW/$AB_LOCK" | tr -d ' ')" 0
ok "…and the lock is the same three fields"    "$(grep -cE '^(timestamp|epoch|agent):' "$OLDW/$AB_LOCK" | tr -d ' ')" 3

echo
echo "== the claimant is checked LAST: a stale lock is stale even to its own claimant =="
# The claim must never become a second clock, and "recognise yourself" is the tempting way
# to build one by accident. Staleness is computed from `.tick-lock` alone, before identity
# is looked at at all — so the tick whose claim it is gets the same exit 2 as anyone else.
SM="$TMP/stale-mine"; mkdir -p "$SM" "$SM/$AB_DIR"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$SM/$AB_LOCK"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\norigin: adopted\nclaimant: mine\n' \
  "$(iso_of "$(date -u +%s)")" "$(date -u +%s)" > "$SM/$AB_LOCK_CLAIM"
tick "$SM" project-manager mine
ok "its own fresh claim does not rejuvenate it" "$TICK_RC" 2
ok "…it still says STALE"                "$(said 'STALE')" yes
ok "…and it did not run"                 "$(ran "$SM")" 0
ok "…and was not treated as a re-entry"  "$(said 're-entered:')" no

echo
echo "== --as launcher is unchanged: it refuses a claimed lock, identity or not =="
# The strict path must not learn the new trick. A launcher carrying the very identity that
# made the claim still gets HELD, and still writes no claim of its own.
LA="$TMP/launcher-id"; mkdir -p "$LA" "$LA/$AB_DIR"
attempt "$LA"                             # the dispatch lock a tick may claim
tick "$LA" project-manager L
ok "a tick claims that lock as L"        "$TICK_RC" 0
OUT="$(TICK_CLAIMANT=L bash "$LOCKSH" acquire --instance "$LA" 2>&1)"; RC=$?
ok "the launcher is refused even as L"   "$RC" 1
ok "…and is not offered a re-entry"      "$(grep -qF 're-entered:' <<<"$OUT" && echo yes || echo no)" no
LB="$TMP/launcher-claim"; mkdir -p "$LB" "$LB/$AB_DIR"
TICK_CLAIMANT=L bash "$LOCKSH" acquire --instance "$LB" >/dev/null 2>&1
ok "…and a launcher never writes a claim" "$(yn test -e "$LB/$AB_LOCK_CLAIM")" no
# `release` is still the human's override: it asks nobody who they are and takes both files,
# including a claim stamped with somebody else's identity.
bash "$LOCKSH" release --instance "$LA" >/dev/null 2>&1
ok "release still clears a claim that is not yours" \
  "$(if [ -e "$LA/$AB_LOCK" ] || [ -e "$LA/$AB_LOCK_CLAIM" ]; then echo no; else echo yes; fi)" yes

echo
echo "== no identity available: exactly the old behaviour, said out loud =="
# The degradation that must never invert. With nothing to identify a tick, a claim it made
# itself is indistinguishable from a sibling's — so it HOLDS, as it did before claimants
# existed, and the refusal names the reason rather than letting it read as a live sibling.
ND="$TMP/no-id"; mkdir -p "$ND" "$ND/$AB_DIR"
attempt "$ND"
tick "$ND"                                # no --claimant, and the environment is unset
ok "an unidentified tick still adopts"   "$TICK_RC" 0
ok "…writing no claimant at all"         "$(grep -c '^claimant:' "$ND/$AB_LOCK_CLAIM" | tr -d ' ')" 0
tick "$ND"                                # the same tick again, still unidentifiable
ok "…and a second acquire holds, as before" "$TICK_RC" 1
ok "…naming the missing identity as the reason" "$(said 'No identity for THIS tick')" yes
ok "…and it did not run twice"           "$(ran "$ND")" 1
# The mirror: an identified tick meeting a claim written before claimants existed. It cannot
# be matched to anybody, so it is nobody's — hold, and say which side is missing.
OLDC="$TMP/old-claim"; mkdir -p "$OLDC" "$OLDC/$AB_DIR"
attempt "$OLDC"
NOW_T="$(date -u +%s)"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$(iso_of "$NOW_T")" "$NOW_T" > "$OLDC/$AB_LOCK_CLAIM"
tick "$OLDC" project-manager whoever
ok "a claim with no claimant matches nobody" "$TICK_RC" 1
ok "…and says the claim is the unmatchable side" "$(said 'records no claimant')" yes

echo
echo "== THE MEASUREMENT: the runtime's id names a SESSION, so it may never clear a claim =="
# Parent and dispatched subagent were read side by side on 2026-08-30 and carried the SAME
# `CLAUDE_CODE_SESSION_ID`, byte for byte. So this block drives the sequence that fact makes
# dangerous — launcher dispatches A, A claims, the SAME SESSION arrives again (a resume) —
# and asserts the one thing that keeps 2026-08-29 shut: it does NOT proceed.
EV="$TMP/env-id"; mkdir -p "$EV" "$EV/$AB_DIR"
bash "$LOCKSH" acquire --instance "$EV" >/dev/null 2>&1
OUT="$(CLAUDE_CODE_SESSION_ID=sess-aaa bash "$LOCKSH" acquire --as tick --instance "$EV" 2>&1)"; RC=$?
ok "a session id is enough to claim"     "$RC" 0
ok "…adopting the launcher's lock"       "$(grep -qF 'adopted:' <<<"$OUT" && echo yes || echo no)" yes
ok "…recording which source answered"    "$(has "$EV/$AB_LOCK_CLAIM" 'claimant-source: session')" yes
OUT="$(CLAUDE_CODE_SESSION_ID=sess-aaa bash "$LOCKSH" acquire --as tick --instance "$EV" 2>&1)"; RC=$?
ok "the same session does NOT proceed"   "$( [ "$RC" -eq 0 ] && echo yes || echo no)" no
ok "…it is exit 2, a human's call"       "$RC" 2
ok "…saying it cannot attribute the claim" "$(grep -qF 'CANNOT ATTRIBUTE' <<<"$OUT" && echo yes || echo no)" yes
ok "…and never calling it a re-entry"    "$(grep -qF 're-entered:' <<<"$OUT" && echo yes || echo no)" no
# The question an operator actually has, answerable from the output alone. Both sides, and
# the source of each — without them, "is that a sibling or did my id move?" needs a probe,
# which is exactly the probe that had to be run by hand to find this bug.
ok "…printing this caller's identity"    "$(grep -qF 'yours: sess-aaa (session)' <<<"$OUT" && echo yes || echo no)" yes
ok "…and the claim's, with its source"   "$(grep -qF 'claim: sess-aaa (session)' <<<"$OUT" && echo yes || echo no)" yes
ok "…and how to make it decidable"       "$(grep -qF -- '--claimant' <<<"$OUT" && echo yes || echo no)" yes
OUT="$(CLAUDE_CODE_SESSION_ID=sess-bbb bash "$LOCKSH" acquire --as tick --instance "$EV" 2>&1)"; RC=$?
ok "…while another session still HOLDS"  "$RC" 1
ok "…naming both ids there too"          "$(grep -qF 'yours: sess-bbb (session)' <<<"$OUT" && echo yes || echo no)" yes
# The drift half, said out loud: two DIFFERENT session ids can also be one tick whose
# session forked or compacted. It holds either way — the safe half — but the human is told
# which reading they are looking at instead of deducing it.
ok "…and naming the id-moved reading"    "$(grep -qF 'session id moved' <<<"$OUT" && echo yes || echo no)" yes

echo
echo "== the two tiers: a DECLARED match is proof, a mixed one is not =="
# `--claimant`/`TICK_CLAIMANT` are a caller PROMISING "this names this tick"; the runtime's
# variable promises only "this names this session". Equal strings from different tiers are
# therefore not the same statement, and the script must not average them into one.
TD="$TMP/tier-declared"; mkdir -p "$TD" "$TD/$AB_DIR"
bash "$LOCKSH" acquire --instance "$TD" >/dev/null 2>&1
bash "$LOCKSH" acquire --as tick --instance "$TD" --claimant tick-x >/dev/null 2>&1
OUT="$(TICK_CLAIMANT=tick-x bash "$LOCKSH" acquire --as tick --instance "$TD" 2>&1)"; RC=$?
ok "declared on both sides re-enters"    "$RC" 0
ok "…as a re-entry, not a fresh claim"   "$(grep -qF 're-entered:' <<<"$OUT" && echo yes || echo no)" yes
OUT="$(CLAUDE_CODE_SESSION_ID=tick-x bash "$LOCKSH" acquire --as tick --instance "$TD" 2>&1)"; RC=$?
ok "a DERIVED id matching a declared claim cannot clear it" "$RC" 2
TM="$TMP/tier-mixed"; mkdir -p "$TM" "$TM/$AB_DIR"
bash "$LOCKSH" acquire --instance "$TM" >/dev/null 2>&1
CLAUDE_CODE_SESSION_ID=tick-y bash "$LOCKSH" acquire --as tick --instance "$TM" >/dev/null 2>&1
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$TM" --claimant tick-y 2>&1)"; RC=$?
ok "…and a declared id cannot clear a DERIVED claim either" "$RC" 2
ok "…because the claim on disk was never a promise" \
  "$(grep -qF 'claim: tick-y (session)' <<<"$OUT" && echo yes || echo no)" yes

echo
echo "== THE SEQUENCE THE COLLISION WOULD HAVE RE-OPENED, counted end to end =="
# Not an exit code this time but a COUNT, because the failure is "two ticks ran" and only
# ran.log can say that. One `/pm-loop` session S: it takes the lock, dispatches tick A, and
# then — the bypass the whole claim exists for — resumes a completed tick R. Every one of
# those carries S's session id, measured identical. Exactly one of A and R may run.
SIB="$TMP/sibling-resume"; mkdir -p "$SIB" "$SIB/$AB_DIR"
attempt "$SIB"
ok "session S takes the lock and dispatches" "$ATTEMPT_RC" 0
TICK_OUT="$(CLAUDE_CODE_SESSION_ID=sess-S bash "$LOCKSH" acquire --as tick --instance "$SIB" 2>&1)"
TICK_RC=$?; [ "$TICK_RC" -eq 0 ] && printf 'tick ran: A\n' >> "$SIB/ran.log"
ok "…tick A adopts it and runs"          "$TICK_RC" 0
TICK_OUT="$(CLAUDE_CODE_SESSION_ID=sess-S bash "$LOCKSH" acquire --as tick --instance "$SIB" 2>&1)"
TICK_RC=$?; [ "$TICK_RC" -eq 0 ] && printf 'tick ran: R\n' >> "$SIB/ran.log"
ok "…and the resumed sibling does NOT run" "$(ran "$SIB")" 1
ok "…it is escalated, not waved through" "$TICK_RC" 2

echo
echo "== status answers 'whose claim is that?' without a probe =="
# The refusal and `status` must both print BOTH identities. Until they did, the only way to
# answer the one question an operator has was to cat the claim and echo the environment by
# hand — which is how the session id's real granularity went unnoticed until it shipped.
ST="$TMP/status-id"; mkdir -p "$ST" "$ST/$AB_DIR"
bash "$LOCKSH" acquire --instance "$ST" >/dev/null 2>&1
bash "$LOCKSH" acquire --as tick --instance "$ST" --claimant tick-s >/dev/null 2>&1
OUT="$(CLAUDE_CODE_SESSION_ID=sess-other bash "$LOCKSH" status --instance "$ST" 2>&1)"; RC=$?
ok "status on a claimed lock is still HELD" "$RC" 1
ok "…and names the claim's owner"        "$(grep -qF 'claim: tick-s (flag)' <<<"$OUT" && echo yes || echo no)" yes
ok "…and who is asking"                  "$(grep -qF 'yours: sess-other (session)' <<<"$OUT" && echo yes || echo no)" yes
OUT="$(bash "$LOCKSH" status --instance "$ST" 2>&1)"
ok "…spelling out an absent identity"    "$(grep -qF 'yours: <none> (none)' <<<"$OUT" && echo yes || echo no)" yes

echo
echo "== a claim that names a claimant always names its source =="
# The invariant that a truncated write must not satisfy. `claim_exclusive` used to end its
# group with a bare `:`, which swallowed a failed `printf` — out of disk, a claim missing
# `claimant:` still returned success and the next tick was told it "was written by hand".
# The two fields are written by one `printf`, so a claim carrying one carries both.
for d in "$TD" "$TM" "$EV" "$ST"; do
  c="$d/$AB_LOCK_CLAIM"; [ -e "$c" ] || continue
  ok "claim in $(basename "$d") pairs claimant with its source" \
    "$( [ "$(grep -c '^claimant:' "$c")" = "$(grep -c '^claimant-source:' "$c")" ] && echo yes || echo no)" yes
done

echo
echo "== an empty value is not a declaration, and an empty flag is =="
# The one place the two declared sources differ, and it is deliberate: `TICK_CLAIMANT=` is
# how a caller UNSETS a variable, so it falls through to the runtime rather than refusing,
# while `--claimant ''` is a caller declaring nothing and stays exit 3. The header says so;
# this asserts the header is describing the code and not the other way round.
EMPTY="$TMP/empty-id"; mkdir -p "$EMPTY" "$EMPTY/$AB_DIR"
bash "$LOCKSH" acquire --instance "$EMPTY" >/dev/null 2>&1   # a tick only ever claims
OUT="$(TICK_CLAIMANT= CLAUDE_CODE_SESSION_ID=sess-fallback bash "$LOCKSH" acquire --as tick --instance "$EMPTY" 2>&1)"; RC=$?
ok "an empty TICK_CLAIMANT falls through" "$RC" 0
ok "…to the runtime's id, recorded as such" \
  "$(lock_field_of "$EMPTY/$AB_LOCK_CLAIM" claimant-source)" session
mkdir -p "$TMP/empty-flag" "$TMP/empty-flag/$AB_DIR"
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$TMP/empty-flag" --claimant '' 2>&1)"; RC=$?
ok "…while an empty --claimant is still refused" "$RC" 3

echo
echo "== precedence, and it is visible in the claim rather than inferred =="
# A caller that names an identity and is quietly given a different one is worse off than one
# that names none, so the order is asserted — and asserted on what gets WRITTEN, because
# `claimant-source:` is what a later reader (and a human) judges the tier from.
PR="$TMP/precedence"
for combo in "session:::sess-env-only" "env::envwins:sess-loser" "flag:flagwins:envloser:sessloser"; do
  want="${combo%%:*}"; rest="${combo#*:}"
  fl="${rest%%:*}"; rest="${rest#*:}"; ev="${rest%%:*}"; se="${rest##*:}"
  d="$PR-$want"; mkdir -p "$d" "$d/$AB_DIR"
  bash "$LOCKSH" acquire --instance "$d" >/dev/null 2>&1     # a tick only ever claims
  CLAUDE_CODE_SESSION_ID="$se" TICK_CLAIMANT="$ev" bash "$LOCKSH" acquire --as tick \
    --instance "$d" ${fl:+--claimant "$fl"} >/dev/null 2>&1
  ok "$want wins"                        "$(lock_field_of "$d/$AB_LOCK_CLAIM" claimant-source)" "$want"
done
# A runtime that renames or reshapes its variable must not stop ticks: an unusable IMPLICIT
# identity is ignored (no identity, old behaviour), where an unusable EXPLICIT one refuses.
EV2="$TMP/env-junk"; mkdir -p "$EV2" "$EV2/$AB_DIR"
bash "$LOCKSH" acquire --instance "$EV2" >/dev/null 2>&1     # a tick only ever claims
OUT="$(CLAUDE_CODE_SESSION_ID='not a plain id' bash "$LOCKSH" acquire --as tick --instance "$EV2" 2>&1)"; RC=$?
ok "a malformed session id is ignored, not fatal" "$RC" 0
ok "…and simply leaves the claim unattributed" \
  "$(grep -c '^claimant:' "$EV2/$AB_LOCK_CLAIM" | tr -d ' ')" 0
mkdir -p "$TMP/env-bad" "$TMP/env-bad/$AB_DIR"
OUT="$(TICK_CLAIMANT='not a plain id' bash "$LOCKSH" acquire --as tick --instance "$TMP/env-bad" 2>&1)"; RC=$?
ok "a malformed TICK_CLAIMANT is refused" "$RC" 3

echo
echo "== --claimant is validated, and belongs to acquire alone =="
V="$TMP/claimant-args"; mkdir -p "$V" "$V/$AB_DIR"
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$V" --claimant 'two words' 2>&1)"; RC=$?
ok "a non-id --claimant is refused"      "$RC" 3
ok "…saying what an id may contain"      "$(grep -qF 'plain id' <<<"$OUT" && echo yes || echo no)" yes
ok "…and it wrote no lock"               "$(yn test -e "$V/$AB_LOCK")" no
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$V" --claimant 2>&1)"; RC=$?
ok "a bare trailing --claimant is refused" "$RC" 3
for sub in release status; do
  OUT="$(bash "$LOCKSH" "$sub" --instance "$V" --claimant x 2>&1)"; RC=$?
  ok "$sub refuses an identity argument" "$RC" 3
  ok "…saying it is unconditional"       "$(grep -qF 'unconditional' <<<"$OUT" && echo yes || echo no)" yes
done

echo
echo "== the claim is part of the lock, not a second clock and not a second lock =="
# A tick must not be able to refresh its own deadline by claiming: staleness is computed
# from `.tick-lock` alone, exactly as before this change.
SC="$TMP/stale-claim"; mkdir -p "$SC" "$SC/$AB_DIR"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$SC/$AB_LOCK"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$(iso_of "$(date -u +%s)")" "$(date -u +%s)" \
  > "$SC/$AB_LOCK_CLAIM"
attempt "$SC"
ok "a fresh claim does not rejuvenate a stale lock" "$ATTEMPT_RC" 2
ok "…and it still says STALE"            "$(grep -qF 'STALE' <<<"$ATTEMPT_OUT" && echo yes || echo no)" yes
tick "$SC"
ok "…and a TICK gets the same verdict, not an adoption" "$TICK_RC" 2
ok "…so it did not run"                  "$(ran "$SC")" 0
# `release` is the human's override and stays unconditional — it asks nobody who they are,
# and it takes the claim with the lock rather than leaving half a mechanism behind.
bash "$LOCKSH" release --instance "$SC"
ok "release clears the lock"             "$(yn test -e "$SC/$AB_LOCK")" no
ok "…and the claim with it"              "$(yn test -e "$SC/$AB_LOCK_CLAIM")" no
OUT="$(bash "$LOCKSH" release --as tick --instance "$SC" 2>&1)"; RC=$?
ok "release refuses an identity argument" "$RC" 3
ok "…saying it is unconditional"         "$(grep -qF 'unconditional' <<<"$OUT" && echo yes || echo no)" yes

echo
echo "== a claim that outlived its lock is residue, and must not deadlock the next tick =="
# The other way to get this wrong: leave a claim behind (a hand-removed lock, a release
# that died between its two rm's) and every subsequently dispatched tick refuses a lock
# nobody holds. `acquire` clears it on the create — and only when it was there BEFORE the
# create, so it can never delete a live tick's claim.
RS="$TMP/residue"; mkdir -p "$RS" "$RS/$AB_DIR"
printf 'timestamp: %s\nepoch: %s\nagent: project-manager\n' "$OLD_ISO" "$OLD" > "$RS/$AB_LOCK_CLAIM"
ok "status says the claim outlived its lock" \
  "$(grep -qF 'outlived' <<<"$(bash "$LOCKSH" status --instance "$RS" 2>&1)" && echo yes || echo no)" yes
attempt "$RS"
ok "the launcher still dispatches"       "$ATTEMPT_RC" 0
ok "…having cleared the residue"         "$(yn test -e "$RS/$AB_LOCK_CLAIM")" no
tick "$RS"
ok "…and its tick is not deadlocked by it" "$TICK_RC" 0
ok "…and ran"                            "$(ran "$RS")" 1

echo
echo "== absence is never an error for the LAUNCHER — and is the refusal for a tick =="
# The two halves of "absence" are opposite answers on purpose, and neither may drift into
# the other: for the launcher an absent lock is the ordinary case it exists to take, and
# for a tick it is proof that no launcher ran.
N="$TMP/tick-absent"; mkdir -p "$N" "$N/$AB_DIR"
OUT="$(bash "$LOCKSH" acquire --as tick --instance "$N" 2>/dev/null)"; RC=$?
ok "no lock: the tick is refused"        "$RC" 4
ok "…with nothing on stdout"             "$([ -z "$OUT" ] && echo empty || echo "$OUT")" empty
OUT="$(bash "$LOCKSH" acquire --instance "$N" 2>&1)"; RC=$?
ok "…while the LAUNCHER takes one, silently" "$RC" 0
ok "…byte-empty, exactly as before"      "$([ -z "$OUT" ] && echo empty || echo "$OUT")" empty
bash "$LOCKSH" release --instance "$N" >/dev/null 2>&1
# The launcher's path stays byte-silent — that contract is unchanged and is asserted at the
# top of this file; what follows only pins that `--as` is validated rather than assumed.
OUT="$(bash "$LOCKSH" acquire --as sideways --instance "$N" 2>&1)"; RC=$?
ok "an unknown --as is refused"          "$RC" 3
# THREE since `--as loop` joined them (the interval-driven launcher). The refusal must name
# the whole vocabulary or a typo reads as "not that one" rather than "one of these".
ok "…naming the three it accepts"        "$(grep -qF 'launcher, loop or tick' <<<"$OUT" && echo yes || echo no)" yes
OUT="$(bash "$LOCKSH" acquire --as --instance "$N" 2>&1)"; RC=$?
ok "a bare trailing --as is refused too" "$RC" 3

echo
echo "== a claim that cannot be WRITTEN is not a claim somebody else holds =="
# Two causes, two answers — the distinction `acquire` already refuses to collapse for the
# lock. Collapsing it here would report an unwritable instance root as "another tick is
# running", which is the one message nobody would think to debug.
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP  running as root: permission bits refuse nobody"
else
  W="$TMP/readonly"; mkdir -p "$W" "$W/$AB_DIR"
  attempt "$W"                              # the launcher takes the lock while it can
  chmod a-w "$W/$AB_DIR"
  tick "$W"; RC_RO="$TICK_RC"; OUT_RO="$TICK_OUT"
  REL_OUT="$(bash "$LOCKSH" release --instance "$W" 2>&1)"; REL_RC=$?
  chmod u+w "$W/$AB_DIR"                    # …restored before anything else runs
  ok "the tick refuses with exit 3"        "$RC_RO" 3
  ok "…naming the unwritable root"         "$(grep -qF 'not writable' <<<"$OUT_RO" && echo yes || echo no)" yes
  ok "…and NOT blaming another tick"       "$(grep -qF 'HELD BY ANOTHER TICK' <<<"$OUT_RO" && echo yes || echo no)" no
  ok "…so it did not run"                  "$(ran "$W")" 0
  # And a release that cannot remove says which file it left, rather than reporting a
  # success the caller would take as "the lock is gone".
  ok "a release that cannot remove exits 3" "$REL_RC" 3
  ok "…naming the file still on disk"      "$(grep -qF '.tick-lock' <<<"$REL_OUT" && echo yes || echo no)" yes
fi

echo
echo "== it bounds TICKS, not role agents =="
# A held lock must never block the role agents the tick holding it dispatched, so nothing on
# THAT path may read the file. This assertion was "no agent names the lock" until 2026-08-30
# and is now an exact set, deliberately: the tick had to become a reader (property 5 above),
# and "no agent" would have had to be deleted to let it, which is how a guard quietly becomes
# "some agents". Naming the one file that may read it keeps the other half enforced — add a
# second agent to this list and you are back to a held lock blocking role agents.
agent_readers="$(grep -rlF 'tick-lock' "$TPL/plugin/agents" 2>/dev/null \
  | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ *$//')"
ok "exactly one agent may name the lock — the tick" "$agent_readers" "project-manager.md"
ok "the launcher does"                   "$(has "$LAUNCHER" 'scripts/tick-lock.sh')" yes
ok "…and says which limit this is"       "$(has "$LAUNCHER" 'bounds **PM')" yes
ok "…while the cap stays resolve-max-agents.sh" "$(has "$LAUNCHER" 'resolve-max-agents.sh')" yes
ok "the script says it reads no config"  "$(has "$LOCKSH" 'IT READS NO CONFIG')" yes

echo
echo "== the contract in prose says what the code does, in all four places =="
# A header that still called existence the signal would be the more dangerous half of this
# change: the code would be right and every reader of it wrong. Asserted as an ABSENCE,
# because that sentence is the one a partial revert leaves behind.
# path-scan: absent — $TPL/symlink is the retired directory this sweep must still cover;
# the other two roots on the line resolve, so the grep is a scan that WAS able to act.
ok "no file still calls existence the whole signal" \
  "$(grep -rlF 'EXISTENCE is the' "$TPL/symlink" "$TPL/docs" "$TPL/README.md" 2>/dev/null | wc -l | tr -d ' ')" 0
ok "the header says the claim records whose it is" \
  "$(has "$LOCKSH" 'It records WHOSE it is')" yes
ok "…and the claim it writes says so too"  "$(has "$LOCKSH" 'It records WHOSE the claim is')" yes
# The argument, not just the conclusion: the narrower fix has a true premise and is still
# wrong, and a future reader who re-derives only the premise would delete this branch.
ok "…and answers the narrower fix rather than ignoring it" \
  "$(has "$LOCKSH" 'THE NARROWER FIX WAS CONSIDERED AND DOES NOT HOLD')" yes
ok "…naming the one-launcher sequence that refutes it" \
  "$(has "$LOCKSH" 'has only ONE launcher in it')" yes
# Both known-wrong mechanisms stay named as wrong, so neither is rediscovered as an idea.
ok "…still refusing elapsed time"        "$(has "$LOCKSH" 'NOT elapsed time.')" yes
ok "…and a nonce in the dispatch prompt" "$(has "$LOCKSH" 'NOT a nonce in the')" yes
ok "…and saying why --agent cannot be the identity" "$(has "$LOCKSH" 'NOT `--agent`.')" yes
ok "…and which way it degrades"          "$(has "$LOCKSH" 'DEGRADES TOWARDS THE OLD BEHAVIOUR')" yes
ok "…and that the claimant is judged after staleness" \
  "$(has "$LOCKSH" 'checked LAST')" yes
# CRITERION 6. The header used to say the derived tier was the normal case and that supplying
# a literal was refused; both are false since the launcher supplies one, and a header that
# still said them would be the more dangerous half of this change.
ok "…that the launcher now supplies the id" "$(has "$LOCKSH" 'THE LAUNCHER SUPPLIES THE ID')" yes
ok "…while the script still cannot derive one" \
  "$(has "$LOCKSH" 'CANNOT SELF-DERIVE A PER-TICK ID')" yes
ok "…exit 2 documenting four cases only"    "$(has "$LOCKSH" 'needs a human, and these four only')" yes
ok "…and a differing DECLARED id reading exit 1" \
  "$(has "$LOCKSH" 'INCLUDING two DECLARED ids that DIFFER')" yes
ok "…the window left open as a decision"    "$(has "$LOCKSH" 'THAT IS A DECISION AND NOT A GAP')" yes
ok "…because adopt must never match the id" "$(has "$LOCKSH" 'ADOPT NEVER MATCHES')" yes
# THE MEASUREMENT AND THE RULE IT FORCED. Both are pinned because both were re-derived the
# expensive way once: the first implementation of this claimant reasoned that the session id
# "names that agent's own transcript", and the two ids above are what that reasoning cost.
# A reader who deletes the asymmetry needs to see, in the same file, the measurement that
# put it there.
ok "…and the measured session/subagent collision" \
  "$(has "$LOCKSH" 'THE RUNTIME'\''S ID NAMES A SESSION, NOT A TICK — MEASURED')" yes
ok "…quoting both ids it was measured from" \
  "$(has "$LOCKSH" 'subagent  CLAUDE_CODE_SESSION_ID=aaf01a1c')" yes
ok "…and the asymmetry that follows from it" \
  "$(has "$LOCKSH" 'A DERIVED ID MAY REFUSE, BUT MAY NEVER CLEAR')" yes
ok "…and that CHILD_SESSION does not rescue it" \
  "$(has "$LOCKSH" 'CLAUDE_CODE_CHILD_SESSION')" yes
ok "…and where a per-tick id would have to come from" \
  "$(has "$LOCKSH" 'nothing per-agent is exported to the shell')" yes
# The two windows this deliberately does not close, written down rather than found later.
ok "…and release's two non-atomic rm's"  "$(has "$LOCKSH" 'CANNOT REMOVE THEM AS ONE')" yes
ok "…and a session id that moves mid-tick" \
  "$(has "$LOCKSH" 'CHANGES ITS ID MID-TICK STILL DEADLOCKS')" yes

echo
echo "== the dispatch window is a NUMBER, and the identity question has an ANSWER =="
# WHY THESE ARE PINNED. This window was prose twice before it was a measurement — "the
# seconds between", "the rarer half of an already rare race" — and prose is what let it read
# as microseconds when it is most of a minute. So both figures, and the spawn latency that
# prices every "just acquire earlier" remedy, are asserted as digits in both the file a
# maintainer reads and the page an operator reads. A future edit that rounds them, drops the
# second one, or reverts to an adjective goes red here rather than in an incident.
OPSDOC="$TPL/docs/operations.md"
for f in "$LOCKSH" "$OPSDOC"; do
  n="$(basename "$f")"
  ok "$n keeps the first window as digits"  "$(has "$f" '16:00:11Z')" yes
  ok "…and what it was claimed at"          "$(has "$f" '16:00:58Z')" yes
  ok "…and the second, independent one"     "$(has "$f" '18:18:30Z')" yes
  ok "…claimed at"                          "$(has "$f" '18:19:11Z')" yes
  ok "…the first duration, as digits"       "$(has "$f" '47')" yes
  ok "…and the second"                      "$(has "$f" '41')" yes
  ok "…and the spawn latency that prices a reorder" "$(has "$f" '26-27s')" yes
done
# The retracted phrasing may survive ONLY as the retraction itself, and nowhere else. An
# operator page has no reason to quote it at all, so there it must be absent outright.
ok "the retraction is quoted once, in the script" \
  "$(grep -cF 'the seconds between' "$LOCKSH" | tr -d ' ')" 1
ok "…and the operator page never says it"  "$(grep -cF 'the seconds between' "$OPSDOC" | tr -d ' ')" 0
ok "…nor the other unmeasured adjective"   "$(grep -cF 'rarer half' "$OPSDOC" | tr -d ' ')" 0

# THE ANSWER, which is the deliverable this window's task actually asked for: the per-tick
# identity is REACHABLE, and is still not wired in. Both halves are asserted, because either
# one alone reads as the opposite conclusion — "reachable" alone invites a mechanism nobody
# priced, and "not wired in" alone reads as "we never looked".
ok "the script records that the id is reachable" \
  "$(has "$LOCKSH" 'THE PER-TICK IDENTITY IS REACHABLE')" yes
ok "…with the corrected on-disk path"      "$(has "$LOCKSH" 'subagents/agent-<agent-id>.jsonl')" yes
ok "…and says the old guess was wrong"     "$(has "$LOCKSH" 'both guesses')" yes
ok "…and that nothing per-agent is exported" \
  "$(has "$LOCKSH" 'NOTHING PER-AGENT IS EXPORTED')" yes
ok "…naming the pooled process it is not"  "$(has "$LOCKSH" 'a REUSED CLI process')" yes
ok "…and that the id survives a resume"    "$(has "$LOCKSH" 'THE ID SURVIVES A RESUME')" yes
ok "…and that it is STILL not used"        "$(has "$LOCKSH" 'AND IT IS STILL NOT USED HERE')" yes
ok "…reason 1: no per-invocation literal"  "$(has "$LOCKSH" 'THIS SCRIPT'\''S ARGV HAS NONE')" yes
ok "…reason 2: it ties where it matters"   "$(has "$LOCKSH" 'AMBIGUOUS EXACTLY WHERE IT MATTERS')" yes
ok "…reason 3: a generic template"         "$(has "$LOCKSH" 'UNDOCUMENTED PRIVATE LAYOUT')" yes
# The variant that needs no identity at all is the one a reader is most likely to re-derive,
# so it is priced in the file rather than left to be rebuilt and then measured.
ok "…and the ordering variant is priced, not left open" \
  "$(has "$LOCKSH" 'THE ORDERING-INVARIANT VARIANT')" yes
ok "…as shrinking, never closing"          "$(has "$LOCKSH" 'CANNOT CLOSE IT')" yes
# Classifying the channel BEFORE anything could use it is the asymmetric rule doing its job.
ok "…and the channel is classed as derived" "$(has "$LOCKSH" 'transcript channel is DERIVED')" yes
ok "the operator page carries the answer too" "$(has "$OPSDOC" 'It exists, and this bundle still cannot use it')" yes
ok "…and classes the channel as derived"   "$(has "$OPSDOC" 'The channel is **derived**, not declared')" yes

# The launcher's own page must not read as if the claim now lets anything through.
ok "the launcher says its step 1 is unchanged" \
  "$(has "$LAUNCHER" 'Your step 1 is unchanged')" yes
ok "…and that it refuses a claimed lock too" \
  "$(has "$LAUNCHER" 'refuses any live lock,')" yes
ok "…naming the tick'\''s own claim as not a conflict" \
  "$(has "$LAUNCHER" 'own claim')" yes
# And the operator page, which is where a human goes when the loop is not dispatching.
OPS="$TPL/docs/operations.md"
ok "the operator docs carry the re-entry rule" "$(has "$OPS" 're-entered:')" yes
ok "…and the argument for keeping the hold"    "$(has "$OPS" 'only **one** launcher in')" yes
ok "…and where the identity comes from"        "$(has "$OPS" 'CLAUDE_CODE_SESSION_ID')" yes
# The asymmetry is the whole safety argument, so the page a human reads must carry it in
# words and not only the script's header. Same for the measurement it rests on: an operator
# who does not know the runtime's id is per-SESSION cannot read an exit 2 correctly.
ok "…and the rule that makes it safe"        "$(has "$OPS" 'may refuse a claim, but may never clear one')" yes
ok "…and that the runtime's id names a session" "$(has "$OPS" 'it names the *session*')" yes
ok "…and the exit 2 that follows from it"    "$(has "$OPS" 'CANNOT ATTRIBUTE')" yes
ok "…and the drift failure mode it leaves open" "$(has "$OPS" 'gets a new id mid-tick')" yes
ok "…and release's two-rm window"            "$(has "$OPS" 'removes two files with two')" yes
ok "the README summary carries the asymmetry too" \
  "$(has "$TPL/README.md" 'may refuse a claim but never clears one')" yes

echo
echo "== the tick's own ledger still exists — it moved to step 0.9, it was not deleted =="
# Moved 2026-09-02 (task-011 finding 9): the append dirties tracked log.md, and
# tick-delta.sh calls ANY tracked dirt an immediate DELTA before it fingerprints — so an
# entry opened in 0.5 forces the answer the 0.9 probe exists to give, and the idle
# fast-path never runs. The entry is unchanged; only the step that writes it moved, so
# these pin the LOCATION in both directions rather than the file-wide presence they used to.
# The literal gained ` by <login>` in ai-bridge-2x/task-011 — a shared bundle's ledger is one
# file both loops append to, so a line that does not say whose tick it was cannot be attributed.
# step05only stops at 0.9; the step05() defined below deliberately runs on to step 1, so it
# would report 0.9's line as 0.5's and this pair would not be able to fail.
step05only() { awk '/^0\.5\. \*\*Take the tick lock/{p=1;next} p&&/^0\.9\. /{p=0} p' "$TICK"; }
step09() { awk '/^0\.9\. \*\*Probe the idle fast-path/{p=1;next} p&&/^1\. \*\*Orient/{p=0} p' "$TICK"; }
ok "the tick still opens a ledger entry" "$(has "$TICK" '* TICK <ISO-8601 timestamp> by <login> open:')" yes
ok "…and step 0.9 is what opens it" \
  "$(grep -qF '* TICK <ISO-8601 timestamp> by <login> open:' <<<"$(step09)" && echo yes || echo no)" yes
ok "…step 0.5 no longer does" \
  "$(grep -qF '* TICK <ISO-8601 timestamp> by <login> open:' <<<"$(step05only)" && echo yes || echo no)" no
ok "…and the probe's reason for the move is stated" \
  "$(grep -qF 'the probe reads a tree that append would have dirtied' <<<"$(step09)" && echo yes || echo no)" yes
ok "…still re-deriving from disk first"  "$(has "$TICK" 're-derive the in-flight set from disk')" yes

echo
echo "== the second acquire site: the TICK takes the lock, and holds when it is another's =="
# This assertion is the exact inverse of the one that stood here until 2026-08-30 ("the tick
# knows nothing of the lock"). It was a faithful pin of the design that shipped, and the
# design was wrong: the launcher is on one of the two paths that start a tick, and the other
# one — a resume — is where two project-managers ran at once. Inverted deliberately, in the
# same change that puts the acquire in the tick, so neither half can drift from the other.
step05() { awk '/^0\.5\. \*\*Take the tick lock/{p=1;next} p&&/^1\. \*\*Orient/{p=0} p' "$TICK"; }
ok "step 0.5 runs the tick's own acquire" \
  "$(grep -qF 'scripts/tick-lock.sh acquire --as tick' <<<"$(step05)" && echo yes || echo no)" yes
ok "…before it re-derives anything"      "$(grep -qF 'The lock comes first' <<<"$(step05)" && echo yes || echo no)" yes
# Every exit code the script can return has a branch here too — the launcher's step 1 has
# had one since #62, and a second caller with three of the four is a caller improvising on
# the one that mattered.
for code in 0 1 2 3 4; do
  ok "step 0.5 handles exit $code"       "$(grep -qE "^   - \*\*$code\*\*" <<<"$(step05)" && echo yes || echo no)" yes
done
# Exit 4 is the resume refusal, and the tick's branch for it has to say the two things a
# refused tick could still get wrong: run nothing, and take no lock of its own.
ok "…and its exit-4 branch ends the tick" \
  "$(grep -qF 'End the tick' <<<"$(step05)" && echo yes || echo no)" yes
ok "…taking no lock of its own"          "$(grep -qF 'take no lock of your own' <<<"$(step05)" && echo yes || echo no)" yes
ok "…and naming the rule it is the absolute of" \
  "$(grep -qF 'never resumed' <<<"$(step05)" && echo yes || echo no)" yes
ok "…holding, not adopting, on a live sibling" \
  "$(grep -qF 'adopt nothing as your in-flight set' <<<"$(step05)" && echo yes || echo no)" yes
ok "…and opening no ledger entry when it holds" \
  "$(grep -qF 'open no ledger entry' <<<"$(step05)" && echo yes || echo no)" yes
ok "…and never deleting a stale lock itself" \
  "$(grep -qF 'their answer, not' <<<"$(step05)" && echo yes || echo no)" yes
# The claimant, in the one place a tick reads before it acts. A step that documented only
# `took:`/`adopted:` would leave a tick meeting `re-entered:` to improvise — and this step
# is the whole of what the tick knows about the lock.
ok "…documenting the re-entry line on exit 0" \
  "$(grep -qF 're-entered:' <<<"$(step05)" && echo yes || echo no)" yes
ok "…saying a re-entry changed nothing"  "$(grep -qF 'nothing' <<<"$(step05)" && echo yes || echo no)" yes
ok "…and that exit 1 therefore means somebody else" \
  "$(grep -qF 'somebody else' <<<"$(step05)" && echo yes || echo no)" yes
# The one value the tick carries is its BRIEF's, passed verbatim on a fixed command line —
# never one it invents, and never one it remembers between ticks.
ok "…passing the brief's id and inventing none" \
  "$(grep -qF 'not yours to invent' <<<"$(step05)" && echo yes || echo no)" yes
ok "…and running unchanged when the brief has none" \
  "$(grep -qF 'drop the flag entirely' <<<"$(step05)" && echo yes || echo no)" yes
ok "…with nothing else carried between calls" \
  "$(grep -qF 'Nothing else is carried between' <<<"$(step05)" && echo yes || echo no)" yes
# Criterion 1's second call site, in the file that is the whole of what a tick knows.
ok "…and step 0.5 declares the id" \
  "$(grep -qF -- '--claimant <the tick id from your brief>' <<<"$(step05)" && echo yes || echo no)" yes
ok "…and the command line unchanged from the one acquire above" \
  "$(step05 | grep -c 'scripts/tick-lock.sh acquire --as tick --agent project-manager' | tr -d ' ')" 1
ok "…naming the path the launcher is not on" \
  "$(grep -qF 'a resume never' <<<"$(step05)" && echo yes || echo no)" yes
# The tick now calls a script that a merge alone does not deliver: `scripts/tick-lock.sh` is
# a per-file symlink `install.sh` creates, and it was measured ABSENT in all three instances
# after it merged. A step that stopped dead on that would take every un-re-stamped loop with
# it, and one that carried on silently would hide a missing guard — which is the failure
# this whole step exists because of. So: carry on, and say so.
ok "…and handles the script not being installed at all" \
  "$(grep -qF 'TICK LOCK: absent' <<<"$(step05)" && echo yes || echo no)" yes
ok "…visibly rather than silently"       "$(grep -qF 'Never silently' <<<"$(step05)" && echo yes || echo no)" yes
# The release obligation from #62 is unchanged and now has a second caller, so the tick has
# to say which lock is its own to release. A tick that released an ADOPTED lock would free
# one the launcher is still holding for it.
rel() { awk '/\*\*Finally, release the tick lock/{p=1} p&&/^9\. /{p=0} p' "$TICK"; }
ok "step 8 was extractable (or the next assertions are vacuous)" \
  "$([ -n "$(rel)" ] && echo yes || echo no)" yes
ok "step 8 releases nothing, in every case" \
  "$(grep -qF 'a tick releases no lock, ever' <<<"$(rel)" && echo yes || echo no)" yes
ok "…leaving the adopted one to the launcher" \
  "$(grep -qF 'adopted:' <<<"$(rel)" && echo yes || echo no)" yes
# A `grep 'releases'` matched "releases nothing" AND "releases it", so it passed on the
# instruction's own inverse — the "test that cannot fail" shape this repo has hit repeatedly.
# What has to hold is semantic and has two halves, a positive and a negative:
#
#   POSITIVE  every exit that is NOT a dispatch is named as releasing nothing, so a step
#             that quietly covered only exit 1 fails here.
unwrap() { tr '\n' ' ' | tr -s ' '; }   # the prose is hard-wrapped; the sentence is not
ok "…and every non-dispatch exit is named as releasing nothing" \
  "$(grep -qF 'all release nothing too' <<<"$(rel | unwrap)" && echo yes || echo no)" yes
for code in 1 2 4; do
  ok "…exit $code among them"            "$(grep -qF "exit $code" <<<"$(rel)" && echo yes || echo no)" yes
done
#   NEGATIVE  step 8's command block RUNS NOTHING — every line in it is a comment or blank.
#             This is the assertion the old one should have been: put `tick-lock.sh release`
#             back into that block and it fails, which is the only mutation that matters.
fence() { rel | awk '/^   ```/{f=!f; next} f'; }
ok "…and the command block was extractable (or the next line is vacuous)" \
  "$([ "$(fence | wc -l | tr -d ' ')" -gt 0 ] && echo yes || echo no)" yes
ok "…and it runs nothing at all"         "$(fence | grep -cvE '^[[:space:]]*(#.*)?$' | tr -d ' ')" 0
# `release` is still NAMED in step 8's prose, and must be — as the human's override, not
# as something the tick may run. Asserted on that framing, because deleting the framing is
# how the command comes back as an instruction.
ok "…and the release command is named only as the human's" \
  "$(grep -qF "not yours to run at the end of a tick" <<<"$(rel | unwrap)" && echo yes || echo no)" yes
# The case that used to be here — a tick releasing a lock it created — must not come back
# by itself: it can only exist again if a tick can take a lock, which step 0.5 refuses.
ok "…with no surviving instruction to release a lock the tick took" \
  "$(grep -qF 'printed `took:`' <<<"$(rel)" && echo yes || echo no)" no

echo
echo "== the wiring: the launcher runs the acquire, and holds exactly the grant for it =="
grants() { awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
  | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'; }
ok "allowed-tools grants the script"     "$(grep -qx 'Bash(bash \${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh:\*)' <<<"$(grants "$LAUNCHER")" && echo yes || echo no)" yes
# 8: the eighth is bundle-paths.sh, which prints a layout constant for precondition 1.
ok "…and grants nothing else new"        "$(grants "$LAUNCHER" | wc -l | tr -d ' ')" 8
ok "step 1 runs the acquire"             "$(has "$LAUNCHER" 'scripts/tick-lock.sh acquire --agent project-manager')" yes
ok "…and step 2 releases on the notification" "$(has "$LAUNCHER" 'scripts/tick-lock.sh release')" yes
ok "…only on the notification, nothing weaker" "$(has "$LAUNCHER" 'before you schedule the gap')" yes
# Every exit code the script can return has a documented branch in the launcher, or the
# launcher would be improvising on the one that mattered.
step1() { awk '/^1\. \*\*Take the lock/{p=1;next} p&&/^2\. /{p=0} p' "$LAUNCHER"; }
for code in 0 1 2 3; do
  ok "step 1 handles exit $code"         "$(grep -qE "^   - \*\*$code\*\*" <<<"$(step1)" && echo yes || echo no)" yes
done
# CRITERION 1, THE LAUNCHER HALF. It mints the literal, passes it to its OWN acquire, and
# hands the same one to the tick — writing no file itself, because its allowed-tools cannot
# and because `.tick-lock.claim` is the TICK's O_EXCL adopt record, not a launcher's to touch.
ok "step 1 mints a per-tick id"          "$(grep -qF "mint this tick's id" <<<"$(step1)" && echo yes || echo no)" yes
ok "…passing it to its own acquire"      "$(has "$LAUNCHER" 'acquire --agent project-manager --claimant <id>')" yes
ok "…handing the same literal to the tick" "$(has "$LAUNCHER" 'id you minted at step 1, verbatim')" yes
ok "…recorded in the lock and nowhere else" "$(grep -qF 'the only place it lives' <<<"$(step1)" && echo yes || echo no)" yes
ok "…and it writes no file of its own"   "$(grep -qF 'you write no file yourself' <<<"$(step1)" && echo yes || echo no)" yes
ok "…nor is a mis-copy allowed to refuse the tick" "$(grep -qF 'never matches the id' <<<"$(step1)" && echo yes || echo no)" yes
ok "…and /loop declares one too"         "$(has "$LAUNCHER" 'acquire --as loop --agent project-manager --claimant <id>')" yes
ok "step 1 forbids anything in between"  "$(grep -qF 'nothing may sit between the acquire and the spawn' <<<"$(step1)" && echo yes || echo no)" yes
ok "…and names the window it closes"     "$(grep -qF 'seconds to minutes' <<<"$(step1)" && echo yes || echo no)" yes
ok "…refusing to delete a stale lock itself" \
  "$(grep -qF "the human's answer, not yours" <<<"$(step1)" && echo yes || echo no)" yes

# STOPPING THE LOOP MUST NOT RELEASE SOMEBODY ELSE'S LOCK. `release` holds no session
# identity — it is the human's override and cannot have one — so the condition has to live
# in the caller. A session that skipped at step 1 because another loop held the lock, and
# then released on its way out, would delete a LIVE holder's lock and re-open exactly the
# double-dispatch this file closes. Raised by review on ai-bridge#62.
step5() { awk '/^5\. \*\*Stop\*\*/{p=1;next} p&&/^[A-Za-z]/{p=0} p' "$LAUNCHER"; }
ok "step 5 releases only a lock this session took" \
  "$(grep -qF 'only if THIS session took it' <<<"$(step5)" && echo yes || echo no)" yes
ok "…naming the sibling it would otherwise delete" \
  "$(grep -qF 'live' <<<"$(step5)" && echo yes || echo no)" yes
ok "…and leaves a dispatched tick's lock to age out" \
  "$(grep -qF 'ages out' <<<"$(step5)" && echo yes || echo no)" yes
# And clearance to dispatch is the lock being CREATED, not merely missing: an unwritable
# root refuses rather than dispatching unguarded, which is the other way "absence is never
# an error" gets read backwards.
ok "the script says a failed create refuses" "$(has "$LOCKSH" 'A FAILED CREATE IS')" yes
ok "…and the operator docs say so too" \
  "$(has "$TPL/docs/operations.md" 'Dispatch follows the lock being')" yes

echo
echo "== the lock is one of the launcher's THREE allowed operations, and the list is closed =="
# The launcher's rule is an allowlist: three operations, and anything else is a tick or a
# subagent by category. The lock is entry 2 — asserted here, beside the lock, because
# this is the one grant that was ever added back. The shape of the list, the deleted
# blocklist and the further-entry regression are pm-loop-launcher.test.sh's.
section() { awk '/^### The launcher reads nothing else/{p=1;next} p&&/^#/{p=0} p' "$LAUNCHER"; }
ok "the lock is an allowed operation"    "$(grep -qF 'scripts/tick-lock.sh acquire' <<<"$(section)" && echo yes || echo no)" yes
ok "…and the list is closed against analogy" "$(grep -qF 'No other reader may be added by analogy' <<<"$(section)" && echo yes || echo no)" yes
ok "…keeping the economy justification"  "$(grep -qF "main session's context" <<<"$(section)" && echo yes || echo no)" yes
ok "…and it is an allowlist of exactly three" \
  "$(section | grep -c -E '^[0-9]+\. ' | tr -d ' ')" 3

echo
echo "== the lock is gitignored on a freshly stamped instance =="
# install.sh refuses to run from a linked git worktree (its own header says why, and every
# role agent's checkout of this template is one), so stamp from a filesystem copy taken
# outside any repo — the same dance tests/derived-indexes.test.sh does, and see there for
# the full rationale and this TMPDIR-recursion guard.
BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"
if command -v git >/dev/null 2>&1; then
  _tpl_gd="$(git -C "$TPL" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _tpl_gc="$(git -C "$TPL" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_tpl_gd" ] && [ -n "$_tpl_gc" ] && [ "$_tpl_gd" != "$_tpl_gc" ]; then
    INSTALL_SRC="$TMP/install-src"
    _tpl_res="$(cd -- "$TPL" && pwd -P)"
    _src_res="$(cd -- "$TMP" && pwd -P)"
    case "$_src_res/" in
      "$_tpl_res"/*) echo "tick-lock.test: TMPDIR ($_src_res) is inside the template tree ($_tpl_res); the install-source copy would recurse. Point TMPDIR outside the checkout." >&2; exit 2 ;;
    esac
    mkdir -p "$INSTALL_SRC" "$INSTALL_SRC/$AB_DIR"
    cp -R "$TPL"/. "$INSTALL_SRC"/
    rm -rf "$INSTALL_SRC/.git"
    BRIDGE_INSTALL="$INSTALL_SRC/plugin/scripts/init-bundle.sh"
  fi
fi
ok "seed/.gitignore carries the line"    "$(grep -qxF "/$AB_LOCK" "$TPL/plugin/seed/.gitignore" && echo yes || echo no)" yes
INST="$TMP/g/_ai-bridge-g"; mkdir -p "$INST" "$INST/$AB_DIR"
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "a fresh stamp gets the line"         "$(grep -qxF "/$AB_LOCK" "$INST/.gitignore" && echo yes || echo no)" yes
( cd "$INST" && git init -q . && git config user.email t@e.st && git config user.name t )
printf 'agent: x\n' > "$INST/$AB_LOCK"
# git's own answer, not the pattern text — the same standard derived-indexes.test.sh holds
# its lines to.
ok "git itself ignores the lock"         "$( ( cd "$INST" && git check-ignore -q "$AB_LOCK" ) && echo yes || echo no)" yes
( cd "$INST" && git add -A >/dev/null 2>&1 )
ok "…so a git add -A never stages it" \
  "$( grep -qxF "$AB_LOCK" <<<"$( ( cd "$INST" && git diff --cached --name-only ) )" && echo yes || echo no)" no
# And it must reach an instance whose .gitignore predates the line — which is every
# instance in existence — exactly once, not once per stamp.
grep -v "^/${AB_LOCK//./\\.}\$" "$INST/.gitignore" > "$INST/.gi" && mv "$INST/.gi" "$INST/.gitignore"
ok "…(removed for the re-stamp)"         "$(grep -cxF "/$AB_LOCK" "$INST/.gitignore" | tr -d ' ')" 0
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "a re-stamp appends it back"          "$(grep -cxF "/$AB_LOCK" "$INST/.gitignore" | tr -d ' ')" 1
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "…and a third stamp adds no duplicate" "$(grep -cxF "/$AB_LOCK" "$INST/.gitignore" | tr -d ' ')" 1

echo
echo "== …and so is the claim beside it, under its OWN guard =="
# `/.tick-lock` does not match `.tick-lock.claim`, so the claim needs its own line — and,
# more importantly, its own GUARD. Every instance stamped since the lock shipped already
# carries `/.tick-lock`, which satisfies that guard, so a line added inside its heredoc
# would reach exactly nobody who has the first one. That is the case asserted here: remove
# ONLY the claim line, leave the lock's, and a re-stamp must still append it.
ok "seed/.gitignore carries the claim too" "$(grep -qxF "/$AB_LOCK_CLAIM" "$TPL/plugin/seed/.gitignore" && echo yes || echo no)" yes
ok "a fresh stamp gets it"               "$(grep -cxF "/$AB_LOCK_CLAIM" "$INST/.gitignore" | tr -d ' ')" 1
printf 'agent: x\n' > "$INST/$AB_LOCK_CLAIM"
ok "git itself ignores the claim"        "$( ( cd "$INST" && git check-ignore -q "$AB_LOCK_CLAIM" ) && echo yes || echo no)" yes
( cd "$INST" && git add -A >/dev/null 2>&1 )
ok "…so a git add -A never stages it" \
  "$( grep -qxF "$AB_LOCK_CLAIM" <<<"$( ( cd "$INST" && git diff --cached --name-only ) )" && echo yes || echo no)" no
grep -v "^/${AB_LOCK_CLAIM//./\\.}\$" "$INST/.gitignore" > "$INST/.gi" && mv "$INST/.gi" "$INST/.gitignore"
ok "…(removed, with the lock's line left in place)" \
  "$(grep -cxF "/$AB_LOCK" "$INST/.gitignore" | tr -d ' ')" 1
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "a re-stamp appends the claim anyway" "$(grep -cxF "/$AB_LOCK_CLAIM" "$INST/.gitignore" | tr -d ' ')" 1
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1
ok "…and a third stamp adds no duplicate" "$(grep -cxF "/$AB_LOCK_CLAIM" "$INST/.gitignore" | tr -d ' ')" 1

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
