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
ok "exit 6 -> merge path"                          "$(d rc=6 $base)" merge-path
ok "exit 7 -> rebase round"                        "$(d rc=7 $base)" rebase-round
ok "exit 8 -> request a review at the head"        "$(d rc=8 $base)" request-review
ok "exit 4 at coderabbitRounds -> hold (surface)"  "$(d rc=4 crr=1 qar=1 crd=1 qad=0)" hold

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
ok "coderabbitRounds 1 done, then a rate limit -> hold, no QA" "$(d rc=1 class=declined crr=1 qar=1 crd=1 qad=0)" hold
ok "coderabbitRounds 2 done, then out of credits -> hold, no QA" "$(d rc=5 class=declined crr=2 qar=1 crd=2 qad=0)" hold
ok "coderabbitRounds 1 done, exit 8 -> hold, no QA"  "$(d rc=8 crr=1 qar=1 crd=1 qad=0)" hold

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
ok "qaRounds 0 with a real refusal -> merge path, no QA" "$(d rc=1 class=declined crr=1 qar=0 crd=0 qad=0)" merge-path
ok "coderabbitRounds 0, qaRounds 0 -> no QA (CodeRabbit flow)" "$(d rc=8 crr=0 qar=0 crd=0 qad=0)" hold
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
  "api graphql") printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}\n'; exit 0 ;;
  *) case "${2:-}" in
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
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
