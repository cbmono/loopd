#!/usr/bin/env bash
#
# review-request-hook.test.sh — plugin/hooks/review-request.sh (all-code-is-slop-lessons/task-011).
# Reports a second `@coderabbitai review` against a stubbed gh, never refuses, reads gh once per
# matching call and never otherwise, fails open, is silent outside a bundle or marked worktree.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/plugin/hooks/review-request.sh"
HOOKSJSON="$REPO/plugin/hooks/hooks.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-request.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not installed (the hook requires it)"; exit 1; }

res() { (cd "$1" 2>/dev/null && pwd -P); }
mkdir -p "$TMP/bundle" "$TMP/elsewhere" "$TMP/bin"
BUNDLE="$(res "$TMP/bundle")"
ELSEWHERE="$(res "$TMP/elsewhere")"
printf '{}\n' > "$BUNDLE/instance.config.json"
CALLS="$TMP/calls"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
printf '%s\n' "$PWD" >> "$GH_CALLS.cwd"
[ -n "${GH_FAIL:-}" ] && { echo "HTTP 404" >&2; exit 1; }
cat "$GH_FIXTURE"
GH
chmod +x "$TMP/bin/gh"
comments() { jq -n --argjson c "$1" '{comments: $c}' > "$TMP/fixture.json"; }
ASKED='[{"author":{"login":"example-user-007"},"body":"@coderabbitai review"}]'
NONE='[{"author":{"login":"example-user-007"},"body":"looks good"}]'
BOTTIPS='[{"author":{"login":"coderabbitai"},"body":"Tips: `@coderabbitai review` to trigger"},{"author":{"login":"github-actions[bot]"},"body":"@coderabbitai review"}]'

verdict() {
  local out rc
  : > "$CALLS"; : > "$CALLS.cwd"
  jq -n --arg c "$2" --arg d "${PCWD:-$1}" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' > "$TMP/payload"
  out="$(PATH="$TMP/bin:$PATH" GH_CALLS="$CALLS" GH_FIXTURE="$TMP/fixture.json" \
    CLAUDE_PROJECT_DIR="$1" bash "$HOOK" < "$TMP/payload" 2>"$TMP/err")"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'exit%s' "$rc"; return; }
  [ -s "$TMP/err" ] && { printf 'stderr'; return; }
  [ -n "$out" ] || { printf 'silent'; return; }
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1 && { printf 'deny'; return; }
  printf '%s' "$out" | jq -e '(keys == ["hookSpecificOutput","systemMessage"])
    and (.hookSpecificOutput | keys == ["additionalContext","hookEventName"])
    and (.hookSpecificOutput.additionalContext | test("Not refused"))' >/dev/null 2>&1 \
    && printf 'report' || printf 'bad'
}
v() { verdict "$BUNDLE" "$1"; }
reads() { grep -c . "$CALLS" | tr -d ' '; }
ASK='gh pr comment 42 --body "@coderabbitai review"'

echo "== a PR that already carries the trigger =="
comments "$ASKED"
ok "gh pr comment is reported"                          "$(v "$ASK")" report
ok "…with exactly one gh read"                          "$(v "$ASK" >/dev/null; reads)" 1
ok "…and that read is gh pr view 42"                    "$(v "$ASK" >/dev/null; cat "$CALLS")" "pr view 42 --json comments"
ok "--repo is passed through"                           "$(v 'gh pr comment 42 -R example-user-007/x -b "@coderabbitai review"' >/dev/null; cat "$CALLS")" "pr view 42 --repo example-user-007/x --json comments"
ok "a PR URL is passed through"                         "$(v 'gh pr comment https://github.com/example-user-007/x/pull/7 --body "@coderabbitai review"' >/dev/null; cat "$CALLS")" "pr view https://github.com/example-user-007/x/pull/7 --json comments"
ok "no selector reads the payload cwd's branch PR"      "$(PCWD="$ELSEWHERE" v 'gh pr comment --body "@coderabbitai review"' >/dev/null; cat "$CALLS")|$(cat "$CALLS.cwd")" "pr view --json comments|$ELSEWHERE"
ok "--repo=<o/r> is passed through"                     "$(v 'gh pr comment 42 --repo=example-user-007/x -b "@coderabbitai review"' >/dev/null; cat "$CALLS")" "pr view 42 --repo example-user-007/x --json comments"
ok "a POST via --method is reported"                    "$(v 'gh api --method POST repos/example-user-007/x/issues/9/comments -f "body=@coderabbitai review"')" report

echo "== selector, --repo and body come from the one gh pr comment invocation =="
ok "a flag-first call reads the PR named after the flag" "$(v 'gh pr comment --body "@coderabbitai review" 42' >/dev/null; cat "$CALLS")" "pr view 42 --json comments"
ok "an earlier command's PR is not taken"               "$(v 'gh pr view 7 && gh pr comment 42 -b "@coderabbitai review"' >/dev/null; cat "$CALLS")" "pr view 42 --json comments"
ok "a later command's -R is not taken"                  "$(v 'gh pr comment 42 -b "@coderabbitai review" && gh pr view 7 -R example-user-008/y' >/dev/null; cat "$CALLS")" "pr view 42 --json comments"
ok "a later gh pr comment is found after another"       "$(v $'gh pr comment 3 -b "thanks"\ngh pr comment 42 -b "@coderabbitai review"' >/dev/null; cat "$CALLS")" "pr view 42 --json comments"
ok "gh api issues/<n>/comments is reported"             "$(v 'gh api repos/example-user-007/x/issues/9/comments -f body="@coderabbitai review"')" report
ok "…reading that repo and PR"                          "$(cat "$CALLS")" "pr view 9 --repo example-user-007/x --json comments"
ok "gh api with {owner}/{repo} reads the cwd repo"      "$(v 'gh api repos/{owner}/{repo}/issues/9/comments -f body="@coderabbitai review"' >/dev/null; cat "$CALLS")" "pr view 9 --json comments"

echo "== a PR that does not =="
comments "$NONE"
ok "gh pr comment is silent"                            "$(v "$ASK")" silent
ok "…after one gh read"                                 "$(reads)" 1
comments "$BOTTIPS"
ok "the bot's own tips and a [bot] comment don't count" "$(v "$ASK")" silent
comments '[]'
ok "a PR with no comments is silent"                    "$(v "$ASK")" silent

echo "== no gh read when the call does not match =="
comments "$ASKED"
for c in 'gh pr comment 42 --body "thanks"' \
         'echo gh pr comment 42 --body "@coderabbitai review"' \
         'git commit -m "@coderabbitai review"' \
         'gh api repos/o/r/pulls/9 --jq ".body" # @coderabbitai review' \
         'gh pr comment 42 -b "thanks" && echo "@coderabbitai review"' \
         'gh pr comment 42 --body-file b.md # @coderabbitai review' \
         'gh api repos/o/r/issues/9/comments --jq "[.[] | select(.body | contains(\"@coderabbitai review\"))]"' \
         'gh api -X GET repos/o/r/issues/9/comments -f "body=@coderabbitai review"' \
         'gh api repos/o/r/issues/9/comments -f "title=@coderabbitai review"'; do
  ok "silent, no read: ${c:0:44}"                       "$(v "$c")/$(reads)" silent/0
done

echo "== an unreadable PR is silently allowed =="
ok "gh exits non-zero"                                  "$(GH_FAIL=1 v "$ASK")" silent
printf 'not json' > "$TMP/fixture.json"
ok "gh prints something unparseable"                    "$(v "$ASK")" silent
comments "$ASKED"
ok "malformed JSON payload"                             "$(: > "$CALLS"; printf 'gh pr comment @coderabbitai review' | PATH="$TMP/bin:$PATH" GH_CALLS="$CALLS" GH_FIXTURE="$TMP/fixture.json" CLAUDE_PROJECT_DIR="$BUNDLE" bash "$HOOK" 2>&1; printf silent/; reads)" silent/0

echo "== silent outside an instance =="
ok "a directory with no instance.config.json"           "$(verdict "$ELSEWHERE" "$ASK")/$(reads)" silent/0
git init -q -b main "$TMP/repo" && git -C "$TMP/repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
REPOD="$(res "$TMP/repo")"
git -C "$REPOD" worktree add -q "$TMP/wt" -b feat/x >/dev/null 2>&1
WT="$(res "$TMP/wt")"
ok "an unmarked linked worktree"                        "$(verdict "$WT" "$ASK")/$(reads)" silent/0
printf '%s\n' "$BUNDLE" > "$REPOD/.git/loopd-bundle"
ok "a marked linked worktree reports"                   "$(verdict "$WT" "$ASK")" report
ok "the main clone stays un-armed with the marker"      "$(verdict "$REPOD" "$ASK")/$(reads)" silent/0
printf '%s\n' "$ELSEWHERE" > "$REPOD/.git/loopd-bundle"
chmod 000 "$WT/.git"
ok "an unreadable .git file is silent, with no stderr"  "$(verdict "$WT" "$ASK")/$(reads)" silent/0
chmod 644 "$WT/.git"
ok "a marker naming a non-bundle is ignored"            "$(verdict "$WT" "$ASK")/$(reads)" silent/0

echo "== registration =="
ok "hooks.json registers it once, Bash-matched" \
   "$(jq -r '[.hooks.PreToolUse[] | select(.hooks[].command | test("review-request[.]sh")) | .matcher] | join(",")' "$HOOKSJSON")" Bash
ok "…via \${CLAUDE_PLUGIN_ROOT}" \
   "$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("review-request[.]sh"))' "$HOOKSJSON")" '"${CLAUDE_PLUGIN_ROOT}/hooks/review-request.sh"'
ok "the hook is executable"                             "$([ -x "$HOOK" ] && echo yes || echo no)" yes

echo; echo "review-request-hook: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
