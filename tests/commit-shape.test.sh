#!/usr/bin/env bash
#
# commit-shape.test.sh — plugin/scripts/commit-shape.sh reports a commit over 72 subject
# characters, over 5 body lines above the trailers, off `<type>(<scope>)!: `, or with an
# attribution trailer that disagrees with the bundle's commitAttribution; skips merge, Revert
# and fixup!; exits 0 on every path. plugin/hooks/commit-shape.sh, run as hooks.json
# registers it, reports on `git push` from a marked worktree on both channels, never decides,
# and is silent everywhere else. Fixture origin's default branch is `trunk`.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CS="$REPO/plugin/scripts/commit-shape.sh"
HOOKSJSON="$REPO/plugin/hooks/hooks.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/commitshape.XXXXXX")" || {
  echo "commit-shape.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }
count() { sed -n 's/^commit-shape: \([0-9]*\) commit.*/\1/p' <<<"$1"; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
TR="Co-Authored-By: Claude Test <noreply@example.com>"
g() { git -C "$W" -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
c() { printf '%s\n' "$1" > "$TMP/msg"; date +%s%N >> "$W/f.${W##*/}"; g add -A; g commit -q -F "$TMP/msg"; }
git init -q --bare -b trunk "$TMP/origin.git"
MAIN="$TMP/main"; git clone -q "$TMP/origin.git" "$MAIN" 2>/dev/null
W="$MAIN"; g checkout -q -b trunk; c "chore: base"; g push -q origin trunk
git -C "$MAIN" remote set-head origin trunk >/dev/null 2>&1
BUNDLE="$TMP/bundle"; mkdir -p "$BUNDLE"; echo '{}' > "$BUNDLE/instance.config.json"
MARKER="$MAIN/.git/loopd-bundle"
W="$TMP/wt"; git -C "$MAIN" worktree add -q -b feat "$W" trunk >/dev/null 2>&1

echo "== the script"
S73="feat: $(printf 'x%.0s' $(seq 67))"
c "$S73

$TR"
OUT="$(bash "$CS" -C "$W")"; rc=$?
ok "a 73-character subject is reported"            "$(count "$OUT")" "1"
ok "…naming its length"                            "$(has "$OUT" "subject 73 chars > 72")" "yes"
ok "…and the script exits 0"                       "$rc" "0"
ok "with no marker the attribution is unknown"     "$(has "$OUT" "attribution: unknown")" "yes"

W="$TMP/wt2"; git -C "$MAIN" worktree add -q -b clean "$W" trunk >/dev/null 2>&1
c "feat(scope)!: a clean commit — with an em dash $(printf 'y%.0s' $(seq 25))

One body line.
Two.

Claude-Session: https://example.com/s
$TR"
c "fix: five body lines and trailers

1
2
3

4
5

$TR"
c "fixup! anything at all, however long it runs past the seventy-two character limit"
c "Revert \"feat: something\""
OUT="$(bash "$CS" -C "$W")"
ok "a clean branch passes (scope, !, 72 UTF-8 chars, 5 lines)" "$(count "$OUT")" "0"

c "update stuff

$TR"
c "fix: six body lines

1
2
3
4
5
6

$TR"
OUT="$(bash "$CS" -C "$W" --range HEAD~2..HEAD)"
ok "a subject with no type is reported"            "$(has "$OUT" "not <type>(<scope>)!: <subject>")" "yes"
ok "six non-blank body lines are reported"         "$(has "$OUT" "body 6 lines > 5")" "yes"

printf '%s\n' "$BUNDLE" > "$MARKER"
c "docs: no trailer here"
OUT="$(bash "$CS" -C "$W" --range HEAD~1..HEAD)"
ok "marker + absent key ⇒ claude; a missing trailer is reported" "$(has "$OUT" "no Co-Authored-By: Claude trailer")" "yes"
echo '{"commitAttribution":"none"}' > "$BUNDLE/instance.config.json"
OUT="$(bash "$CS" -C "$W" --range HEAD~1..HEAD)"
ok "commitAttribution none: the same commit is clean"  "$(count "$OUT")" "0"
OUT="$(bash "$CS" -C "$W" --range HEAD~2..HEAD~1)"
ok "…and a commit carrying the trailer is reported"    "$(has "$OUT" "(commitAttribution: none)")" "yes"
echo '{}' > "$BUNDLE/instance.config.json"

W="$MAIN"; c "chore: trunk moves on

$TR"; W="$TMP/wt2"
g merge -q --no-ff trunk -m "Merge branch trunk into a branch with a name far longer than seventy-two chars"
OUT="$(bash "$CS" -C "$W" --range HEAD~1..HEAD)"
ok "a merge commit is skipped"                     "$(count "$OUT")" "0"

W="$TMP/wt3"; git -C "$MAIN" worktree add -q -b many "$W" trunk >/dev/null 2>&1
for i in $(seq 22); do c "bad $i $(printf '\033')[31m"; done
OUT="$(bash "$CS" -C "$W")"
ok "22 offenders: 20 listed, then a count line"    "$(grep -c ' — ' <<<"$OUT")/$(tail -1 <<<"$OUT")" "20/… and 2 more"
ok "…and no control byte reaches the report"       "$(LC_ALL=C grep -c "$(printf '\033')" <<<"$OUT")" "0"

git init -q "$TMP/noorigin"
OUT="$(bash "$CS" -C "$TMP/noorigin")"; rc=$?
ok "origin/HEAD unset ⇒ UNKNOWN"                   "$(has "$OUT" "commit-shape: UNKNOWN")" "yes"
ok "…exit 0"                                       "$rc" "0"
OUT="$(bash "$CS" --bogus)"; rc=$?
ok "a bad flag ⇒ UNKNOWN, exit 0"                  "$(has "$OUT" "UNKNOWN")/$rc" "yes/0"

echo "== the hook, as hooks.json registers it"
REGCMD="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command | select(test("commit-shape[.]sh"))' "$HOOKSJSON")"
ok "registered once under PreToolUse, matcher Bash" "$(grep -c . <<<"$REGCMD")" "1"
hook() { # <project-dir> <cwd> <command>
  jq -cn --arg c "$3" --arg d "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' \
    | CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_PROJECT_DIR="$1" bash -c "exec ${REGCMD}" 2>&1
}
W1="$TMP/wt"
OUT="$(hook "$W1" "$W1" 'git push -u origin feat')"
ok "git push from a marked worktree: systemMessage carries the report" \
   "$(jq -r '.systemMessage' <<<"$OUT" | grep -c 'subject 73 chars')" "1"
ok "…and additionalContext the same finding, inside the data fence" \
   "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT" | sed -n '/^--- BEGIN COMMIT REPORT (untrusted data) ---$/,/^--- END COMMIT REPORT ---$/p' | grep -c 'subject 73 chars')" "1"
ok "…on the PreToolUse event"                       "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT")" "PreToolUse"
ok "…never a permission decision" \
   "$(jq -r '[.. | objects | select(has("permissionDecision") or has("decision") or has("continue"))] | length' <<<"$OUT")" "0"
ok "git -C <wt> push from the bundle reports too" \
   "$(hook "$BUNDLE" "$BUNDLE" "git add -A && git -C '$W1' push origin feat" | jq -r '.systemMessage' | grep -c '73 chars')" "1"
git -C "$TMP/wt2" reset -q --hard HEAD~6 >/dev/null 2>&1
ok "a clean branch: no output"                     "$(hook "$TMP/wt2" "$TMP/wt2" 'git push')" ""
ok "not a push: no output"                         "$(hook "$W1" "$W1" 'git status && echo push')" ""
ok "the main clone (.git a directory): no output"  "$(hook "$MAIN" "$MAIN" 'git push')" ""
rm -f "$MARKER"
ok "unmarked worktree: no output"                  "$(hook "$W1" "$W1" 'git push')" ""
mkdir -p "$TMP/elsewhere"
ok "outside an instance and any repo: no output"   "$(hook "$TMP/elsewhere" "$TMP/elsewhere" 'git push')" ""

echo; echo "commit-shape: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
