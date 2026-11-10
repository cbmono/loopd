#!/usr/bin/env bash
#
# stall-counter.test.sh — the same blocker twice escalates to the human, and a slow PR
# does not.
#
# WHAT IS BEING PINNED, AND WHY IT NEEDED A HARNESS RATHER THAN A PARAGRAPH. "After N
# rounds on the same blocker, stop dispatching and ask the human" is a rule with two
# failure directions that look identical from a tick's own report: escalating a PR that is
# merely SLOW (a review round-trip is minutes, and a task waiting on one has moved), and
# NOT escalating a task that has hit the same wall three times (which reads as an ordinary
# in-flight task and costs a full agent per tick). Prose cannot separate those; a fixture
# that fails twice on the same check and a fixture whose PR keeps moving can.
#
# THE MUTANT THIS FILE EXISTS FOR is the one the implementation got wrong first. The
# human-edit reset — a stale count dropped when the human puts a task back in the queue —
# is one line, and written as "at the cap and not `blocked`" it also matches the window
# BETWEEN `record` and `escalate`, where the task is `in-progress` and at the cap with
# nothing wrong. That version zeroes the count between the two calls, `escalate` then
# refuses, and the escalation never happens — the single path the whole feature exists for,
# defeated by a check that looks like a safety net. So the window is asserted directly
# ("== the record→escalate window is not a human edit ==") rather than left to be implied
# by the happy path, which passes under both spellings.
#
# NON-VACUOUS BY CONSTRUCTION elsewhere too: every reset is asserted against the SAME
# fixture and the same call that escalates without it, so a reset that stopped working
# would flip a verdict rather than merely printing a different number.
#
# `assert()` uses exit-code semantics: 0 is a PASS, matching the other harnesses.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
SCRIPT="$REPO/plugin/scripts/stall-counter.sh"
PM_DOC="$REPO/plugin/agents/project-manager.md"
[ -f "$SCRIPT" ] || { echo "stall-counter.test: missing $SCRIPT" >&2; exit 2; }
[ -f "$PM_DOC" ] || { echo "stall-counter.test: missing $PM_DOC" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/stall-counter-fixture.XXXXXX")" || {
  echo "stall-counter.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [ "$2" = 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
has()  { grep -qF -e "$1" <<<"$2" && echo 0 || echo 1; }
hasnt(){ grep -qF -e "$1" <<<"$2" && echo 1 || echo 0; }
eq()   { [ "$1" = "$2" ] && echo 0 || echo 1; }

INST="$TMP/_ai-bridge-fixture"
DOC="$INST/projects/demo/tasks/task-001.md"

# A minimal bundle: `instance.config.json` at the root is the instance signature the
# script walks up to, exactly as check-dispatch.sh does.
reset() { # [<maxStallRounds>] [<status>]
  rm -rf "$INST"; mkdir -p "$INST/projects/demo/tasks"
  { printf '{\n  "org": "o"'
    [ "${1:-}" = "" ] || printf ',\n  "maxStallRounds": %s' "$1"
    printf '\n}\n'
  } > "$INST/instance.config.json"
  { printf -- '---\ntype: Task\ntitle: "Ship the widget"\nkind: build\n'
    printf 'status: %s\nassignee: software-engineer\npr: [ ]\n' "${2:-in-progress}"
    printf 'timestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n\nSomething.\n'
  } > "$DOC"
}
run()  { bash "$SCRIPT" "$@" 2>&1; }
rc()   { bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }
fm()   { grep -m1 "^$1:" "$DOC" | sed "s/^$1:[[:space:]]*//"; }

BLOCKER='harness suite failed: tests/foo.test.sh 3/1'

echo "== the two fields, and what moves them =="

reset
assert "a fresh task carries neither field"        "$(eq "$(fm stall_count)$(fm last_blocker)" "")"
assert "round 1 on a new blocker -> DISPATCH"      "$(rc record "$DOC" --blocker "$BLOCKER")"
assert "…and stall_count is now 1"                 "$(eq "$(fm stall_count)" 1)"
assert "…and last_blocker records the text"        "$(eq "$(fm last_blocker)" "\"$BLOCKER\"")"
assert "round 2 on the SAME blocker -> exit 1"     "$(eq "$(rc record "$DOC" --blocker "$BLOCKER")" 1)"
assert "…and it says ESCALATE, not DISPATCH"       "$(has 'ESCALATE' "$(run status "$DOC"; run record "$DOC" --blocker "$BLOCKER")")"

reset
run record "$DOC" --blocker "$BLOCKER" >/dev/null
assert "a CHANGED blocker counts from 1 again"     "$(rc record "$DOC" --blocker 'a different wall')"
assert "…and stall_count really is 1, not 2"       "$(eq "$(fm stall_count)" 1)"
assert "…and last_blocker followed it"             "$(eq "$(fm last_blocker)" '"a different wall"')"

echo
echo "== two rounds on the same check escalate: status, # Notes, ONE awaiting line =="

reset
run record "$DOC" --blocker "$BLOCKER" >/dev/null
run record "$DOC" --blocker "$BLOCKER" >/dev/null
OUT="$(run escalate "$DOC")"
assert "escalate exits 0 at the cap"               "$(rc escalate "$DOC")"
assert "…status: blocked"                          "$(eq "$(fm status)" blocked)"
assert "…the blocker is recorded under # Notes"    "$(has "$BLOCKER" "$(sed -n '/^# Notes/,$p' "$DOC")")"
assert "…the note names the tally"                 "$(has 'Stalled 2/2 rounds' "$(cat "$DOC")")"
assert "…it emits exactly ONE awaiting line"       "$(eq "$(printf '%s\n' "$OUT" | grep -c '^\* ')" 1)"
assert "…with the ⛔ **unblock** verb"              "$(has '* ⛔ **unblock** — ' "$OUT")"
assert "…the task title, linked bundle-relative"   "$(has '[Ship the widget](/projects/demo/tasks/task-001.md)' "$OUT")"
assert "…and the blocker after the · separator"    "$(has "· stalled 2/2 rounds: $BLOCKER" "$OUT")"

# The line has to be one AWAITING.md already renders. Read the contract from the shipped
# document rather than restating it here: a drift on either side then fails, which a
# hand-copied literal in this file could never catch.
# The queue is RENDERED by build-awaiting.sh since ai-bridge-v3/task-024, so the contract
# is read off a live render rather than off prose: the row shape is now a thing that runs.
QI="$TMP/queue-inst"; mkdir -p "$QI/projects/p/tasks" "$QI/$AB_DIR"
printf '{ "org": "x" }\n' > "$QI/instance.config.json"; printf '# S\n' > "$QI/$AB_SCHEMA"; : > "$QI/$AB_AWAITING"
printf -- '---\ntype: Project\ntitle: "P"\nstatus: active\n---\n' > "$QI/projects/p/project.md"
printf -- '---\ntype: Task\ntitle: "T"\nstatus: blocked\nacceptance_criteria: [ "x" ]\nopen_questions: [ ]\n---\n' \
  > "$QI/projects/p/tasks/task-001-t.md"
bash "$REPO/plugin/scripts/build-awaiting.sh" --instance "$QI" >/dev/null 2>&1
assert "build-awaiting.sh renders that same row"   "$(has '* ⛔ **unblock** — ' "$(cat "$QI/$AB_AWAITING" 2>/dev/null)")"
assert "…whose default trailer names /loopd:answer" "$(has '· blocked — run `/loopd:answer <task path>` with your decision' "$(cat "$QI/$AB_AWAITING" 2>/dev/null)")"

echo
echo "== re-running the escalation is idempotent =="

BEFORE="$(cat "$DOC")"
AGAIN="$(run escalate "$DOC")"
assert "a second escalate prints the same line"    "$(eq "$AGAIN" "$OUT")"
assert "…and appends no second note"               "$(eq "$(grep -c 'Stalled 2/2 rounds' "$DOC")" 1)"
assert "…and leaves the document byte-identical"   "$(eq "$(cat "$DOC")" "$BEFORE")"

echo
echo "== the record→escalate window is not a human edit =="

# THE MUTANT. Between `record` (which returns 1) and `escalate` the task is `in-progress`
# and at the cap. A reset spelled "at the cap and not blocked" fires here, zeroes the
# count, and `escalate` refuses — no escalation, ever. The happy path above passes under
# BOTH spellings, so this is the assertion that tells them apart.
reset '' in-progress
run record "$DOC" --blocker "$BLOCKER" >/dev/null
run record "$DOC" --blocker "$BLOCKER" >/dev/null
assert "at the cap while in-progress: still 2"     "$(has 'stall_count=2' "$(run status "$DOC")")"
assert "…and escalate is NOT refused there"        "$(rc escalate "$DOC")"

echo
echo "== a human edit resets it: the unblock buys a real dispatch =="

# The human's answer is putting the task back in the queue. `ready` and `draft` are the
# only two states that mean that, and only the human writes them.
for state in ready draft; do
  reset
  run record "$DOC" --blocker "$BLOCKER" >/dev/null
  run record "$DOC" --blocker "$BLOCKER" >/dev/null
  run escalate "$DOC" >/dev/null
  sed -i.bak "s/^status: blocked$/status: $state/" "$DOC" && rm -f "$DOC.bak"
  assert "un-blocked to '$state' -> counter reads 0"  "$(has 'stall_count=0' "$(run status "$DOC")")"
  assert "…so the next round DISPATCHes, not escalates" "$(rc record "$DOC" --blocker "$BLOCKER")"
done

echo
echo "== a legitimately slow PR is not a stall =="

# Same blocker every round — a required check that stays red while the work continues —
# but the PR moves each time (a new commit, a new review thread), which the tick reports
# as --progress. Three rounds, and it must never escalate: without the reset, round 2
# already would.
reset
worst=0
for _ in 1 2 3; do
  r="$(rc record "$DOC" --blocker "$BLOCKER" --progress)"
  [ "$r" -gt "$worst" ] && worst="$r"
done
assert "3 rounds with PR activity never escalate"  "$(eq "$worst" 0)"
assert "…and the counter sits at 0, not 3"         "$(eq "$(fm stall_count)" 0)"
assert "…while the SAME 3 rounds without it do"    "$(reset; \
  rc record "$DOC" --blocker "$BLOCKER" >/dev/null; \
  eq "$(rc record "$DOC" --blocker "$BLOCKER")" 1)"

echo
echo "== the cap is maxStallRounds, and absent means 2 =="

reset 4
OUT3=""
for _ in 1 2 3; do OUT3="$(run record "$DOC" --blocker "$BLOCKER")"; done
assert "maxStallRounds: 4 -> round 3 still dispatches" "$(has 'DISPATCH' "$OUT3")"
assert "…and the verdict prints the configured cap"    "$(has 'stall 3/4' "$OUT3")"
assert "…the two rounds that escalate by default do not here" \
       "$(hasnt 'ESCALATE' "$OUT3")"

reset
assert "no key -> the documented fallback of 2 is used" "$(has 'max=2' "$(run status "$DOC")")"

# A per-machine override behaves like every other key, because the cap is read through
# resolve-config.sh rather than by a fourth copy of the precedence rule.
reset 5
printf '{\n  "maxStallRounds": 1\n}\n' > "$INST/instance.config.local.json"
assert "instance.config.local.json wins over tracked"  "$(has 'max=1' "$(run status "$DOC")")"
assert "…and at a cap of 1 the FIRST round escalates"  "$(eq "$(rc record "$DOC" --blocker "$BLOCKER")" 1)"

echo
echo "== the resolver is found through a symlink, and its absence is LOUD =="

# TWO SHAPES, and they are opposite verdicts on purpose. A bundle stamped before
# `resolve-config.sh` shipped reaches this script through a SYMLINK, and a plain
# `dirname "$0"` would look in that bundle's own `scripts/`, miss the sibling, and answer
# with the fallback while a configured cap sat in the file — silently. `readlink` lands in
# the template where the helper is guaranteed to sit, so the symlink still reads 5.
reset 5
mkdir -p "$TMP/lonely" && ln -sf "$SCRIPT" "$TMP/lonely/stall-counter.sh"
assert "reached via a symlink, it still reads the configured 5" \
       "$(has 'max=5' "$(bash "$TMP/lonely/stall-counter.sh" status "$DOC" 2>&1)")"

# A detached COPY genuinely has no sibling. The fallback is then correct — the cap has a
# documented default and stopping a tick over it would be worse — but it is SAID, because
# answering 2 in silence for a bundle that configured 5 is the silent wrong answer this
# repo refuses.
cp "$SCRIPT" "$TMP/lonely/detached.sh"
DETACHED="$(bash "$TMP/lonely/detached.sh" status "$DOC" 2>&1)"
assert "a detached copy falls back to the documented 2" "$(has 'max=2' "$DETACHED")"
assert "…and says so, naming the key it could not read" "$(has 'maxStallRounds' "$DETACHED")"
assert "…and names the sibling it went looking for"     "$(has 'resolve-config.sh' "$DETACHED")"

echo
echo "== refusals: unknown is never reported as fine =="

reset
assert "a task document that does not exist -> 2"  "$(eq "$(rc record "$TMP/nope.md" --blocker x)" 2)"
printf 'no frontmatter here\n' > "$TMP/bad.md"
assert "unreadable frontmatter -> 2, nothing written" "$(eq "$(rc record "$TMP/bad.md" --blocker x)" 2)"
assert "…and that document is untouched"           "$(eq "$(cat "$TMP/bad.md")" 'no frontmatter here')"
assert "an unknown command -> 2"                   "$(eq "$(rc bogus "$DOC")" 2)"
assert "record without --blocker -> 2"             "$(eq "$(rc record "$DOC")" 2)"
assert "escalate under the cap -> 2, refused"      "$(eq "$(rc escalate "$DOC")" 2)"
assert "…and it did not set status: blocked anyway" "$(eq "$(fm status)" in-progress)"

echo
echo "== the blocker text survives the round trip =="

reset
ODD='check "unit" failed \ hard'
run record "$DOC" --blocker "$ODD" >/dev/null
assert "quotes and backslashes are escaped in YAML" "$(eq "$(fm last_blocker)" '"check \"unit\" failed \\ hard"')"
assert "…and read back as written"                  "$(has "last_blocker=$ODD" "$(run status "$DOC")")"
assert "…so the same text is the SAME round"        "$(eq "$(rc record "$DOC" --blocker "$ODD")" 1)"

reset
MULTI="$(printf 'line one\n\tline   two')"
run record "$DOC" --blocker "$MULTI" >/dev/null
assert "newlines and tabs fold to single spaces"    "$(eq "$(fm last_blocker)" '"line one line two"')"
assert "…so last_blocker is always ONE yaml line"   "$(eq "$(grep -c '^last_blocker:' "$DOC")" 1)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
