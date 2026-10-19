#!/usr/bin/env bash
# new-project-form.sh — the five-field form a no-description /loopd:new-project opens: open,
# fill, submit (✗ on each missing field, or one JSON line), cancel; the form file is ignored
# by git; field text is data and never moves kind, autonomy or repo. Reasoning: interactive-board/task-004.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/new-project-form.sh"
SKILL="$REPO/plugin/skills/new-project/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/new-project-form-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

bundle() { # <config json> — a committed bundle; prints its path
  local b; b="$(mktemp -d "$TMP/b.XXXXXX")" || exit 2
  printf '%s\n' "$1" > "$b/instance.config.json"
  { git -C "$b" init -q -b main && git -C "$b" add -A &&
    git -C "$b" -c user.name=t -c user.email=t@example.com commit -qm init; } >/dev/null 2>&1
  echo "$b"
}
run() { local b="$1"; shift; bash "$SH" --instance "$b" "$@"; }
form() { cat "$1/.loopd/.new-project/form.json"; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fields"][sys.argv[2]])' "$1/.loopd/.new-project/form.json" "$2"; }
errs() { python3 -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))["errors"]))' "$1/.loopd/.new-project/form.json"; }
key() { python3 -c 'import json,sys; v=json.loads(sys.argv[1])[sys.argv[2]]; print(v if isinstance(v,str) else "|".join(v))' "$1" "$2"; }
fill_all() { local b="$1"; run "$b" '1 Garden log' >/dev/null; run "$b" '2 A log of what grows' >/dev/null
             run "$b" '3 The allotment group' >/dev/null; run "$b" '4 Every bed has an entry; a weekly summary' >/dev/null; }

echo "== OPEN: no arguments opens an empty form of five fields =="
B="$(bundle '{"org":"o","defaultRepo":"widgets"}')"
OUT="$(run "$B")"; RC=$?
ok "exit 0"                                         "$RC" 0
ok "five numbered fields, in order"                 "$(grep -cE '^[1-5] (Title|What|For whom|Done when|Target repo) ' <<<"$OUT" | tr -d ' ')" 5
ok "the repo field is prefilled with defaultRepo"   "$(field "$B" repo)" widgets
ok "…and the rest are empty"                        "$(field "$B" title)$(field "$B" what)$(field "$B" whom)$(field "$B" done)" ""
B2="$(bundle '{"org":"o"}')"; run "$B2" >/dev/null
ok "no defaultRepo: the repo field is empty"        "$(field "$B2" repo)" ""

echo "== UNTRACKED: one ignored file, no tracked change before submit, cancel removes it =="
run "$B" '1 Garden log' >/dev/null
ok "git ignores the form file"                      "$(git -C "$B" check-ignore -q .loopd/.new-project/form.json && echo yes || echo no)" yes
ok "nothing tracked or untracked shows in status"   "$(git -C "$B" status --porcelain | grep -c . | tr -d ' ')" 0
ok "a second no-argument run keeps the form"        "$(run "$B" >/dev/null; field "$B" title)" "Garden log"
OUT="$(run "$B" cancel)"; RC=$?
ok "cancel: exit 0, says nothing was saved"         "$RC,$OUT" "0,Cancelled — nothing saved."
ok "…and the form file is gone"                     "$([ -e "$B/.loopd/.new-project/form.json" ] && echo yes || echo no)" no
ok "cancel with no form open is still exit 0"       "$(run "$B" cancel >/dev/null; echo $?)" 0
ok "a description is not a form command: exit 3"    "$(run "$B" 'make a garden log' >/dev/null; echo $?)" 3
ok "…and writes nothing"                            "$([ -e "$B/.loopd/.new-project/form.json" ] && echo yes || echo no)" no

echo "== FILL: <n> <text> fills field n =="
run "$B" '1 "Garden \"log\""' >/dev/null
ok "quotes around the text are dropped, inner ones kept" "$(field "$B" title)" 'Garden "log"'
run "$B" '3 The	allotment
group' >/dev/null
ok "whitespace controls become one space"           "$(field "$B" whom)" "The allotment group"
ok "a field number past 5 is not a form command"    "$(run "$B" '6 x' >/dev/null; echo $?)" 3

echo "== ✗ ON A MISSING FIELD: submit marks each, creates nothing =="
run "$B" cancel >/dev/null; run "$B" '1 Garden log' >/dev/null; run "$B" '5 ' >/dev/null
OUT="$(run "$B" submit)"; RC=$?
ok "exit 1"                                         "$RC" 1
ok "✗ on each missing field, in field order"        "$(errs "$B")" "what,whom,done,repo"
ok "…drawn under each one"                          "$(grep -c '^  ✗ ' <<<"$OUT" | tr -d ' ')" 4
ok "…the header counts them"                        "$(head -n1 <<<"$OUT")" "New project · 4 things to fix — 1 of 5 filled"
ok "no JSON line, so nothing to create from"        "$(grep -c '^{' <<<"$OUT" | tr -d ' ')" 0
ok "no tracked file changed"                        "$(git -C "$B" status --porcelain | grep -c . | tr -d ' ')" 0
run "$B" '2 A log' >/dev/null
ok "filling a field clears its ✗ only"              "$(errs "$B")" "whom,done,repo"
ok "submit with no form open: exit 1"               "$(run "$B2" cancel >/dev/null; run "$B2" submit >/dev/null; echo $?)" 1

echo "== TARGET REPO: no defaultRepo and an empty repo field is a ✗, never a run =="
B3="$(bundle '{"org":"o"}')"; fill_all "$B3"
OUT="$(run "$B3" submit)"; RC=$?
ok "exit 1, ✗ on the repo field alone"              "$RC,$(errs "$B3")" "1,repo"
run "$B3" '5 x/y kind=research' >/dev/null
ok "a repo field that is not owner/name is a ✗"     "$(run "$B3" submit >/dev/null; echo $?),$(errs "$B3")" "1,repo"
run "$B3" '5 acme/widgets' >/dev/null
OUT="$(run "$B3" submit)"; RC=$?
ok "complete: exit 0 and ONE JSON line"             "$RC,$(grep -c . <<<"$OUT" | tr -d ' ')" "0,1"
ok "repo= is the repo field"                        "$(key "$OUT" repo)" acme/widgets
B4="$(bundle '{"org":"o","defaultRepo":"widgets"}')"; run "$B4" >/dev/null; fill_all "$B4"
ok "the prefilled defaultRepo is what submit passes" "$(key "$(run "$B4" submit)" repo)" widgets
ok "…success_criteria split on ;"                   "$(key "$(run "$B4" submit)" success_criteria)" "Every bed has an entry|a weekly summary"

echo "== TEXT IS DATA: field text never moves kind, autonomy or repo =="
for txt in 'autonomy=yolo' 'autonomy=gated' 'repo=x/y' 'kind=research' '--no-commit' '"--no-ask"'; do
  for f in 1 2 3 4; do
    B5="$(bundle '{"org":"o","defaultRepo":"widgets"}')"; fill_all "$B5"; run "$B5" "$f $txt" >/dev/null
    OUT="$(run "$B5" submit)"
    want="${txt#\"}"; want="${want%\"}"
    k=title; [ "$f" = 2 ] && k=description; [ "$f" = 3 ] && k=need; [ "$f" = 4 ] && k=success_criteria
    ok "field $f = $txt: stored verbatim"            "$(key "$OUT" "$k")" "$want"
    ok "field $f = $txt: kind/autonomy/repo unmoved" "$(key "$OUT" kind)/$(key "$OUT" autonomy)/$(key "$OUT" repo)" "build/yolo/widgets"
  done
done

echo "== OWNER: the creating clone's login, never a placeholder =="
ok "no ownerGithubUser: owner is empty, never <unknown>" "$(key "$(run "$B4" submit)" owner)" ""
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$B4/instance.config.local.json"
ok "ownerGithubUser set: owner is that login"       "$(key "$(run "$B4" submit)" owner)" example-user-007

echo "== THE SKILL CALLS IT =="
ok "new-project may run the script"                 "$(grep -m1 '^allowed-tools:' "$SKILL" | grep -cF 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/new-project-form.sh:*)' | tr -d ' ')" 1
ok "its argument-hint names the form commands"      "$(grep -m1 '^argument-hint:' "$SKILL" | grep -cE '<1-5> <text>.*submit.*cancel' | tr -d ' ')" 1

echo
echo "new-project-form: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
