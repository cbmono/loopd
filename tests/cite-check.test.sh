#!/usr/bin/env bash
#
# cite-check.test.sh — the reader for `CONVENTIONS.md` → cite knowledge as
# `[[finding-slug]]`, and a behavioural drive of `plugin/scripts/cite-check.sh`.
#
# THE THREE FIXTURES ARE THE CONTRACT, and they are chosen so the middle one cannot be
# reached by accident. `tests/fixtures/cite-check/` holds one small index and three
# answers written against the same two-slug brief:
#
#   all-valid.md     every id was in the brief                          -> exit 0
#   one-invented.md  each citing line pairs a carried id with a dropped
#                    one — a FABRICATED id (in no index row) on one line,
#                    an UNREAD id (a row nobody briefed) on the other, so
#                    both drop classes are exercised and both lines survive -> exit 3
#   all-invented.md  the same two dropped ids, now ALONE on their lines,
#                    so each line's whole provenance vanishes              -> exit 1
#
# The pairing is the point: a citing line that loses every id is the failure, so
# "one invented" only differs from "all invented" when the invented id has company.
#
# NON-VACUITY. Two mutants over the same committed fixtures, no temp files: run
# all-valid.md with an EMPTY brief (must flip 0 -> 1, proving the brief list is really
# read) and one-invented.md with no index (must flip 3 -> 2, proving the verdict is not
# guessed when nothing can classify it).
#
# OFFLINE BY CONSTRUCTION, asserted rather than assumed: the script names no network
# tool. It is the cheapest gate an agent has and it must work in a tick with no host.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CITE="$REPO/plugin/scripts/cite-check.sh"
FIX="$REPO/tests/fixtures/cite-check"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
PM="$REPO/plugin/tick-steps/step-5-reflect-merges.md"
CAT="$REPO/plugin/agents/cataloguer.md"
BRIEF='worktree-isolation-spike,green-check-from-a-reviewer-that-declined'
[ -x "$CITE" ] || { echo "cite-check.test: missing or non-executable $CITE" >&2; exit 2; }
[ -d "$FIX" ]  || { echo "cite-check.test: missing $FIX" >&2; exit 2; }

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

OUT=""; RC=0
run() { # <fixture> [extra args…] — sets $RC and $OUT. Never behind $( ), which would
        # run it in a subshell and lose the report the assertions below read.
  local f="$1"; shift
  OUT="$("$CITE" --text-file "$FIX/$f" --brief "$BRIEF" --index "$FIX/index.md" "$@" 2>&1)"
  RC=$?
}
saw() { grep -Fq -- "$1" <<<"$OUT" && echo yes || echo no; }
in_file() { grep -Fq -- "$2" "$1" && echo yes || echo no; }

echo "== the three fixtures =="
run all-valid.md
ok "all valid -> exit 0"                      "$RC" 0
ok "…and every citation is reported KEPT"     "$(saw 'KEPT worktree-isolation-spike')" yes
ok "…with a summary line the PM can quote"    "$(saw '2 kept, 0 dropped')" yes

run one-invented.md
ok "one invented -> exit 3 (dropped, blocks survive)" "$RC" 3
ok "…the id in no index row is FABRICATED"    \
   "$(saw 'FABRICATED a-worktree-finding-that-does-not-exist')" yes
ok "…the id that IS a row but was unbriefed is UNREAD" \
   "$(saw 'UNREAD stale-local-main-is-not-the-remote-default-branch')" yes
ok "…and no line is reported EMPTY"           "$(saw 'EMPTY')" no

run all-invented.md
ok "all invented -> exit 1 (a citing line lost every id)" "$RC" 1
ok "…both citing lines are named EMPTY"       \
   "$(printf '%s\n' "$OUT" | grep -c '^EMPTY ')" 2
ok "…and nothing was kept"                    "$(saw '0 kept, 2 dropped')" yes

echo
echo "== --strip prints the text with only the carried ids left =="
STRIPPED="$("$CITE" --text-file "$FIX/one-invented.md" --brief "$BRIEF" \
            --index "$FIX/index.md" --strip 2>/dev/null)"
ok "the carried id survives"      \
   "$(grep -Fq '[[worktree-isolation-spike]]' <<<"$STRIPPED" && echo yes || echo no)" yes
ok "the fabricated id is gone"    \
   "$(grep -Fq 'a-worktree-finding-that-does-not-exist' <<<"$STRIPPED" && echo yes || echo no)" no
ok "the unread id is gone"        \
   "$(grep -Fq 'stale-local-main-is-not' <<<"$STRIPPED" && echo yes || echo no)" no
ok "the prose around them is untouched" \
   "$(grep -Fq 'The base branch was read from the host' <<<"$STRIPPED" && echo yes || echo no)" yes

echo
echo "== non-vacuity: the two inputs that decide the verdict really decide it =="
"$CITE" --text-file "$FIX/all-valid.md" --brief '' --index "$FIX/index.md" >/dev/null 2>&1
ok "an empty brief flips all-valid 0 -> 1"    "$?" 1
"$CITE" --text-file "$FIX/one-invented.md" --brief "$BRIEF" --index "$FIX/nonexistent.md" >/dev/null 2>&1
ok "no index flips one-invented 3 -> 2 (unknown, never a guess)" "$?" 2
"$CITE" --brief "$BRIEF" >/dev/null 2>&1
ok "a missing --text-file is exit 2"          "$?" 2

echo
echo "== offline by construction =="
ok "the script names no network tool"         \
   "$(grep -cE '(^|[^-[:alnum:]])(gh|curl|wget|nc) ' "$CITE")" 0

echo
echo "== the rule is written where the agents read it =="
ok "CONVENTIONS.md defines the citation form"   \
   "$(in_file "$CONV" 'Cite knowledge as `[[finding-slug]]`, and only ids your brief actually carried')" yes
ok "…and says free-text references are not citations" \
   "$(in_file "$CONV" 'bracketed slug is the ONLY thing that counts as a citation')" yes
ok "…names the index as the id source of truth" \
   "$(in_file "$CONV" 'is the id source of truth**: the `cataloguer` writes one row per doc')" yes
ok "…names the script and its exit codes"       "$(in_file "$CONV" 'scripts/cite-check.sh --text-file')" yes
ok "…and keeps UNREAD and FABRICATED apart"     \
   "$(in_file "$CONV" 'The two ways an id gets dropped are reported apart')" yes
ok "the project-manager runs it at reflect time" \
   "$(in_file "$PM" 'scripts/cite-check.sh --text-file')" yes
ok "…over the # Result section and each PR body" \
   "$(in_file "$PM" '`# Result` section and over each merged PR body')" yes
ok "…recording a stripped citation as a # Notes line" \
   "$(in_file "$PM" '**recorded as a `# Notes` line**')" yes
ok "the cataloguer owns the id source of truth"  \
   "$(in_file "$CAT" 'row reads as fabricated, so a doc you write and don'"'"'t index')" yes
# The reflect step is step 5; a move of this paragraph out of it would leave the rule
# true and the timing wrong, which no other assertion here would see. Since
# ai-bridge-v3/task-024 each step is its own file, so "inside step 5, before step 6" is the
# pair of file claims below — the same property, checked one boundary tighter.
ok "…and the PM's rule sits inside step 5" \
   "$([ "$(awk '/^5\. \*\*Reflect merges/{s=NR} /^<!-- end of step 5 -->/{e=NR} \
        /scripts\/cite-check\.sh/{c=NR} END{print (s<c && c<e) ? "yes" : "no"}' "$PM")" = yes ] \
      && echo yes || echo no)" yes
ok "…and NOT in step 6, which runs after it" \
   "$(grep -qF 'cite-check.sh' "$REPO/plugin/tick-steps/step-6-close-projects.md" && echo yes || echo no)" no

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
