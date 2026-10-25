#!/usr/bin/env bash
#
# review-next.test.sh — plugin/scripts/review-next.sh, the one decision the tick takes on an
# in-review PR: its table row by row (--decide), then three live ticks through a gh stub
# (a real refusal dispatches QA, the record holds a second tick, the verdict ends it).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/review-next.sh"
FIXTURES="$REPO/tests/fixtures/reviewer"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-next.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
d() { "$SCRIPT" --decide "$@" 2>/dev/null; }
# Defaults: coderabbitRounds 1, qaRounds 1, no rounds yet, no QA record.
base="crr=1 qar=1 crd=0 qad=0 qlast=none qhead=no qrec=no"

echo "== every review-clearance exit, at the defaults =="
# shellcheck disable=SC2086
{
ok "exit 0 -> merge path"                          "$(d rc=0 $base)" merge-path
ok "exit 1 placeholder -> hold"                    "$(d rc=1 class=placeholder $base)" hold
ok "exit 1 real refusal -> dispatch QA"            "$(d rc=1 class=declined $base)" dispatch-qa
ok "exit 2 -> hold"                                "$(d rc=2 $base)" hold
ok "exit 3 -> hold"                                "$(d rc=3 $base)" hold
ok "exit 4 -> request a review at the head"        "$(d rc=4 $base)" request-review
ok "exit 5 (terminal) -> dispatch QA"              "$(d rc=5 class=declined $base)" dispatch-qa
ok "exit 6 -> implementer round, never a merge"    "$(d rc=6 $base)" implementer-round
ok "…also at coderabbitRounds"                       "$(d rc=6 crr=1 qar=1 crd=1 qad=0)" implementer-round
ok "exit 7 -> rebase round"                        "$(d rc=7 $base)" rebase-round
ok "exit 8 -> request a review at the head"        "$(d rc=8 $base)" request-review
ok "exit 4 at coderabbitRounds -> merge path (no re-review)" "$(d rc=4 crr=1 qar=1 crd=1 qad=0)" merge-path

echo "== QA triggers =="
ok "coderabbitRounds 0, qaRounds 1, exit 8 -> dispatch QA (8 never consulted)" "$(d rc=8 crr=0 qar=1 crd=0 qad=0)" dispatch-qa
ok "coderabbitRounds 0, qaRounds 1, exit 3 -> dispatch QA (3 never consulted)" "$(d rc=3 crr=0 qar=1 crd=0 qad=0)" dispatch-qa
ok "coderabbitRounds 2, round 1 done, then a rate limit -> dispatch QA" "$(d rc=1 class=declined crr=2 qar=1 crd=1 qad=0)" dispatch-qa
ok "coderabbitRounds 2, round 1 done, then out of credits -> dispatch QA" "$(d rc=5 class=declined crr=2 qar=1 crd=1 qad=0)" dispatch-qa

echo "== not triggers: nothing here dispatches QA =="
ok "placeholder -> hold"                           "$(d rc=1 class=placeholder $base)" hold
ok "exit 3 -> hold"                                "$(d rc=3 $base)" hold
ok "exit 8 -> request a review"                    "$(d rc=8 $base)" request-review
ok "coderabbitRounds 2, round 1 done, placeholder -> hold" "$(d rc=1 class=placeholder crr=2 qar=1 crd=1 qad=0)" hold

echo "== no QA after CodeRabbit finished its rounds =="
ok "coderabbitRounds 1 done, then a rate limit -> merge path, no QA" "$(d rc=1 class=declined crr=1 qar=1 crd=1 qad=0)" merge-path
ok "coderabbitRounds 2 done, then out of credits -> merge path, no QA" "$(d rc=5 class=declined crr=2 qar=1 crd=2 qad=0)" merge-path
ok "coderabbitRounds 1 done, exit 8 -> merge path, no QA" "$(d rc=8 crr=1 qar=1 crd=1 qad=0)" merge-path
ok "coderabbitRounds 1 done, placeholder -> hold"     "$(d rc=1 class=placeholder crr=1 qar=1 crd=1 qad=0)" hold

echo "== idempotent: a QA in flight at the head holds =="
ok "record at the head, no verdict yet -> hold"    "$(d rc=1 class=declined crr=1 qar=1 crd=0 qad=0 qrec=yes)" hold
ok "…also when coderabbitRounds is 0"              "$(d rc=8 crr=0 qar=1 crd=0 qad=0 qrec=yes)" hold
ok "record at the head, round 1 failed earlier -> hold" "$(d rc=1 class=declined crr=1 qar=2 crd=0 qad=1 qlast=fail qhead=no qrec=yes)" hold

echo "== QA rounds =="
ok "round 1 PASS at the head -> merge path (stop)" "$(d rc=1 class=declined crr=1 qar=2 crd=0 qad=1 qlast=pass qhead=yes qrec=yes)" merge-path
ok "round 1 PASS, a commit after it -> merge path, no round 2" "$(d rc=1 class=declined crr=1 qar=2 crd=0 qad=1 qlast=pass qhead=no)" merge-path
ok "round 1 FAIL at the head, no fix yet -> implementer round" "$(d rc=1 class=declined crr=1 qar=2 crd=0 qad=1 qlast=fail qhead=yes qrec=yes)" implementer-round
ok "round 1 FAIL, fix landed, qaRounds 2 -> dispatch QA round 2" "$(d rc=1 class=declined crr=1 qar=2 crd=0 qad=1 qlast=fail qhead=no)" dispatch-qa
ok "…the same once CodeRabbit answers 8 at the fix commit" "$(d rc=8 crr=1 qar=2 crd=0 qad=1 qlast=fail qhead=no)" dispatch-qa
ok "round 2 FAIL, fix landed, qaRounds 2 -> merge path (cap)" "$(d rc=1 class=declined crr=1 qar=2 crd=0 qad=2 qlast=fail qhead=no)" merge-path
ok "round 1 FAIL, fix landed, qaRounds 1 -> merge path (cap)" "$(d rc=1 class=declined crr=1 qar=1 crd=0 qad=1 qlast=fail qhead=no)" merge-path
ok "QA verdict at the head inconclusive or unreadable (exit 6) -> hold, surface" "$(d rc=1 class=declined crr=1 qar=2 crd=0 qad=1 qlast=unknown qhead=yes qrec=yes)" hold
ok "…the same after a commit landed: no endless round" "$(d rc=8 crr=1 qar=2 crd=0 qad=1 qlast=unknown qhead=no)" hold
ok "qaRounds 0 with a real refusal -> merge path, no QA" "$(d rc=1 class=declined crr=1 qar=0 crd=0 qad=0)" merge-path
ok "coderabbitRounds 0, qaRounds 0 -> merge path, no round at all" "$(d rc=8 crr=0 qar=0 crd=0 qad=0)" merge-path
ok "…the same with no reviewer signal (exit 3)"     "$(d rc=3 crr=0 qar=0 crd=0 qad=0)" merge-path
ok "qaRounds 0, out of credits -> merge path, no QA" "$(d rc=5 class=declined crr=1 qar=0 crd=0 qad=0)" merge-path
}

echo "== unknown input holds =="
ok "no rc -> hold"            "$(d crr=1 qar=1 crd=0 qad=0)" hold
"$SCRIPT" --decide crr=1 qar=1 crd=0 qad=0 >/dev/null 2>&1
ok "…and exits 2"             "$?" 2
ok "a non-integer cap -> hold" "$(d rc=1 crr=x qar=1 crd=0 qad=0)" hold
ok "the decision reads no autonomy mode: gated and yolo answer alike" \
   "$(grep -cE 'resolve-autonomy|AUTONOMY|autonomy:' "$SCRIPT")" 0

echo
echo "== three live ticks through a gh stub =="
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
REAL_JQ="$(command -v jq)"
export FIX="$TMP/fix"; mkdir -p "$FIX" "$TMP/bin"
H="8f40f2ed565a31e141f5ae54a6935ad0810314c4"
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
REAL_JQ="$REAL_JQ"
STUB
cat >> "$TMP/bin/gh" <<'STUB'
filter=""; prev=""
for a in "$@"; do [ "$prev" = "--jq" ] && { filter="$a"; break; }; prev="$a"; done
case "${1:-} ${2:-}" in
  "pr view") src="$FIX/pr_json" ;;
  "api graphql") [ -f "$FIX/threads_json" ] && { cat "$FIX/threads_json"; exit 0; }
                printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}\n'; exit 0 ;;
  *) case "${2:-}" in
       */compare/*) src="$FIX/compare_json" ;;
       */pulls/*/commits*) src="$FIX/commits_json" ;;
       */pulls/*/reviews*) src="$FIX/reviews_json" ;;
       */issues/*/comments*) src="$FIX/comments_json" ;;
       *) echo "stub: unhandled gh $*" >&2; exit 99 ;;
     esac ;;
esac
if [ -n "$filter" ]; then "$REAL_JQ" -r "$filter" "$src"; else cat "$src"; fi
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
B="$TMP/bundle"; mkdir -p "$B"; printf '{}\n' > "$B/instance.config.json"
export CLAUDE_PROJECT_DIR="$B"
"$REAL_JQ" -n --arg h "$H" '{url:"https://github.com/acme/widgets/pull/42", number:42, headRefOid:$h,
  author:{login:"dev"}, mergeable:"MERGEABLE", mergeStateStatus:"CLEAN", commits:[]}' > "$FIX/pr_json"
printf '[{"sha":"%s"}]\n' "$H" > "$FIX/commits_json"
printf '[]\n' > "$FIX/reviews_json"
"$REAL_JQ" -n --rawfile b "$FIXTURES/rate-limit-refusal.pr30.md" '[{user:{login:"coderabbitai[bot]"}, body:$b}]' \
  > "$FIX/comments_json"
live() { "$SCRIPT" 42 --repo acme/widgets 2>/dev/null; }
ok "tick 1: the recorded rate limit -> dispatch QA" "$(live)" dispatch-qa
n="$("$REPO/plugin/scripts/qa-dispatch.sh" mint --repo acme/widgets --pr 42 --head "$H")"
ok "tick 2: the dispatch record at the head -> hold, no second QA" "$(live)" hold
v="$(printf 'Verified.\n\n— dev-qa\n\n<!-- okf-verdict v1\nverdict: pass\nhead_sha: %s\nreviewer: qa-reviewer\nlenses: correctness=done security=done repro=done\nunverified_criteria: none\ncaveats: none\ndispatch: %s\n-->\n' "$H" "$n")"
"$REAL_JQ" --arg b "$v" '. + [{user:{login:"dev"}, body:$b, created_at:"2099-01-01T00:00:00Z"}]' \
  "$FIX/comments_json" > "$FIX/c2" && mv "$FIX/c2" "$FIX/comments_json"
ok "tick 3: the recorded QA's PASS at the head -> merge path" "$(live)" merge-path

echo
echo "== --clear: may the head merge with no review at it? =="
X="1111111111111111111111111111111111111111"
B="$TMP/bundle2"; mkdir -p "$B"; export CLAUDE_PROJECT_DIR="$B"; printf '{}\n' > "$B/instance.config.json"
RCPT="$("$REPO/plugin/scripts/clearance-receipt.sh" path --bundle "$B" --repo acme/widgets --pr 42 --head "$H")"
printf '**Actionable comments posted: 1**\n\nQuote `$dir` in run.sh.\n' > "$TMP/review.md"
reviewed_at_x() { # a CodeRabbit review object at X, then a fix commit H; no comments, no threads
  rm -f "$FIX/threads_json" "$RCPT" "$TMP/clear.err"
  printf '[{"sha":"%s"},{"sha":"%s"}]\n' "$X" "$H" > "$FIX/commits_json"
  "$REAL_JQ" -n --arg x "$X" --rawfile b "$TMP/review.md" \
    '[{user:{login:"coderabbitai[bot]"}, state:"COMMENTED", commit_id:$x, body:$b}]' > "$FIX/reviews_json"
  printf '[]\n' > "$FIX/comments_json"
  printf '{}\n' > "$B/instance.config.json"
}
cmpf() { # <status> <file-json>... — the host's compare of X...H
  "$REAL_JQ" -n --arg st "$1" '{status:$st, commits:[{sha:"c", parents:[{sha:"p"}]}], files:[$ARGS.positional[] | fromjson]}' \
    --args "${@:2}" > "$FIX/compare_json"
}
f() { # <status> <name> <additions> <deletions> [patch]
  "$REAL_JQ" -cn --arg s "$1" --arg n "$2" --argjson a "$3" --argjson d "$4" --arg p "${5-@@ -1 +1 @@}" \
    '{filename:$n, status:$s, additions:$a, deletions:$d} + (if $p == "" then {} else {patch:$p} end)'
}
clear() { "$SCRIPT" 42 --repo acme/widgets --clear 2>"$TMP/clear.err"; echo "rc=$?"; }
said() { grep -Fq -- "$1" "$TMP/clear.err" && echo yes || echo no; }

reviewed_at_x; cmpf ahead "$(f modified a.sh 6 2)" "$(f added b.md 2 0)"
ok "past CodeRabbit's last round, decision -> merge path" "$(live)" merge-path
ok "ahead, 10 of 300 lines -> clears as last-round" "$(clear | tr '\n' ' ')" "last-round rc=0 "
ok "…and writes the named receipt line at the head" "$(grep -c '^last-round review-next.sh ' "$RCPT")" 1
"$SCRIPT" 42 --repo acme/widgets --head "$X" --clear >/dev/null 2>&1
ok "--clear at a head that is not the PR's -> hold" "rc=$?" rc=1
"$REAL_JQ" 'del(.files)' "$FIX/compare_json" > "$FIX/c" && mv "$FIX/c" "$FIX/compare_json"
ok "a compare with no files array is unknown, never 0 lines" "$(clear | tail -n 1)" rc=2
reviewed_at_x; cmpf ahead "$(f modified a.sh 6 2)"
printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[{"isResolved":false,"path":"a.sh","line":3,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"url":"https://example.invalid/t/1","body":"quote it"}]}}]}}}}}' > "$FIX/threads_json"
ok "threads still open from the last round, a fix after it -> clears" "$(clear | tr '\n' ' ')" "last-round rc=0 "
reviewed_at_x; cmpf diverged "$(f modified a.sh 6 2)"
ok "a rebase orphaned the reviewed commit (diverged) -> hold" "$(clear)" rc=1
ok "…naming the rebase" "$(said 'orphaned the reviewed commit')" yes
ok "…and writes no line" "$([ -f "$RCPT" ] && echo yes || echo no)" no
reviewed_at_x; cmpf ahead "$(f modified a.sh 250 51)"
ok "301 lines over the 300 cap -> hold" "$(clear)" rc=1
ok "…naming both numbers" "$(said 'changes 301 lines')/$(said 'reviewFixMaxLines (300)')" yes/yes
reviewed_at_x; cmpf ahead "$(f modified a.sh 400 100)"
"$REAL_JQ" '.commits += [{sha:"m", parents:[{sha:"p1"},{sha:"p2"}]}]' "$FIX/compare_json" > "$FIX/c" && mv "$FIX/c" "$FIX/compare_json"
ok "a merge from main busts the cap -> hold" "$(clear)" rc=1
ok "…naming the merge" "$(said 'a merge from the base branch after the last round')" yes
reviewed_at_x; printf '{"reviewFixMaxLines": 5}\n' > "$B/instance.config.json"; cmpf ahead "$(f modified a.sh 6 2)"
ok "reviewFixMaxLines 5, 8 lines -> hold" "$(clear)/$(said 'reviewFixMaxLines (5)')" rc=1/yes
for kind in "binary:$(f modified logo.png 0 0 '')" "rename:$(f renamed new.sh 0 0 '')" \
            "mode-only:$(f changed run.sh 0 0 '')" \
            "submodule:$(f modified vendor/lib 1 1 "$(printf '@@ -1 +1 @@\n-Subproject commit a\n+Subproject commit b')")"; do
  reviewed_at_x; cmpf ahead "$(f modified a.sh 6 2)" "${kind#*:}"
  ok "a ${kind%%:*} file holds rather than counting 0" "$(clear)/$(said 'no countable lines')" rc=1/yes
done

reviewed_at_x; printf '[]\n' > "$FIX/reviews_json"
sed "s/$H/$X/g" "$FIXTURES/clean-review.pr29.md" > "$TMP/route-c.md"
"$REAL_JQ" -n --rawfile b "$TMP/route-c.md" '[{user:{login:"coderabbitai[bot]"}, body:$b}]' > "$FIX/comments_json"
cmpf ahead "$(f modified a.sh 6 2)"
ok "route C only: the round counts, decision -> merge path" "$(live)" merge-path
ok "…but --clear holds: no review object pins it" "$(clear)/$(said 'only its edited summary comment')" rc=1/yes

reviewed_at_x; printf '{"coderabbitRounds": 2}\n' > "$B/instance.config.json"; cmpf ahead "$(f modified a.sh 6 2)"
ok "before the last round, no review at the head -> request a review" "$(live)" request-review
ok "…and --clear refuses (exit 4 stands)" "$(clear)/$(said 'not finished (request-review)')" rc=1/yes

reviewed_at_x; printf '[{"sha":"%s"}]\n' "$X" > "$FIX/commits_json"
"$REAL_JQ" --arg x "$X" '.headRefOid = $x' "$FIX/pr_json" > "$FIX/p" && mv "$FIX/p" "$FIX/pr_json"
printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[{"isResolved":false,"path":"a.sh","line":3,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"url":"https://example.invalid/t/1","body":"quote it"}]}}]}}}}}' > "$FIX/threads_json"
cmpf identical
ok "zero commits after the round, threads open (exit 6) -> implementer round" "$(live)" implementer-round
ok "…and --clear never merges it" "$(clear)" rc=1
"$REAL_JQ" --arg h "$H" '.headRefOid = $h' "$FIX/pr_json" > "$FIX/p" && mv "$FIX/p" "$FIX/pr_json"

reviewed_at_x; printf '[]\n' > "$FIX/reviews_json"; printf '{"qaRounds": 0}\n' > "$B/instance.config.json"
"$REAL_JQ" -n --rawfile b "$FIXTURES/rate-limit-refusal.pr30.md" '[{user:{login:"coderabbitai[bot]"}, body:$b}]' > "$FIX/comments_json"
ok "qaRounds 0 with a real refusal -> merge path, no QA" "$(live)" merge-path
ok "…--clear clears as qa-zero" "$(clear | tr '\n' ' ')" "qa-zero rc=0 "
ok "…and writes the qa-zero line" "$(grep -c '^qa-zero review-next.sh ' "$RCPT")" 1

reviewed_at_x; printf '[]\n' > "$FIX/reviews_json"; printf '{"coderabbitRounds": 0, "qaRounds": 0}\n' > "$B/instance.config.json"
ok "0/0 with no reviewer at all -> merge path" "$(live)" merge-path
ok "…--clear clears as zero-zero" "$(clear | tr '\n' ' ')" "zero-zero rc=0 "

qa_at_x() { # <verdict> [<sha>] — a qa-bot trailer at X (or <sha>), the head H
  reviewed_at_x; printf '[]\n' > "$FIX/reviews_json"
  "$REAL_JQ" -n --arg b "$(printf 'Checked.\n\n<!-- okf-verdict v1\nverdict: %s\nhead_sha: %s\nreviewer: qa-reviewer\nlenses: correctness=done security=done repro=done\nunverified_criteria: none\ncaveats: none\n-->\n' "$1" "${2:-$X}")" \
    '[{user:{login:"qa-bot"}, body:$b}]' > "$FIX/comments_json"
}
qa_at_x changes-requested; cmpf ahead "$(f modified a.sh 6 2)"
ok "QA FAIL at the last round, a fix after it -> merge path" "$(live)" merge-path
ok "…--clear measures from the QA round and clears" "$(clear | tr '\n' ' ')" "last-round rc=0 "
qa_at_x changes-requested; cmpf ahead "$(f modified a.sh 250 51)"
ok "…over the cap from the QA round -> hold" "$(clear)" rc=1

echo "== QA round 1 fixes: no waiver without a fix =="
reviewed_at_x; cmpf ahead
"$REAL_JQ" '.files = []' "$FIX/compare_json" > "$FIX/c" && mv "$FIX/c" "$FIX/compare_json"
printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[{"isResolved":false,"path":"a.sh","line":3,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"url":"https://example.invalid/t/1","body":"quote it"}]}}]}}}}}' > "$FIX/threads_json"
ok "1: an empty commit after the last round, threads open -> hold" "$(clear)/$(said 'no fix has landed')" rc=1/yes
ok "…and writes no line" "$([ -f "$RCPT" ] && echo yes || echo no)" no
reviewed_at_x; cmpf identical
ok "1: compare identical after a CodeRabbit round -> hold" "$(clear)/$(said 'no fix has landed')" rc=1/yes
qa_at_x pass "$H"
ok "2: a QA PASS at the head -> merge path" "$(live)" merge-path
ok "…--clear files it as qa-head, never last-round" "$(clear | tr '\n' ' ')" "qa-head rc=0 "
ok "…and writes no last-round line" "$(grep -c '^last-round ' "$RCPT")" 0
ok "3: qaRounds 0, no refusal, QA FAIL at the head -> implementer round" \
   "$(d rc=4 crr=1 qar=0 crd=0 qad=1 qlast=fail qhead=yes)" implementer-round
ok "3: qaRounds 0, a refusal, QA FAIL at the head -> implementer round" \
   "$(d rc=1 class=declined crr=1 qar=0 crd=0 qad=1 qlast=fail qhead=yes)" implementer-round
qa_at_x changes-requested "$H"; printf '{"qaRounds": 0}\n' > "$B/instance.config.json"
ok "3: …the same live: --clear refuses" "$(clear)" rc=1
ok "…and writes no waiver line" "$(grep -cE '^(last-round|qa-head|qa-zero|zero-zero) ' "$RCPT" 2>/dev/null || true)" 0

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
