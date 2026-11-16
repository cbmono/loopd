#!/usr/bin/env bash
#
# pr-title-hook.test.sh — plugin/hooks/pr-title.sh (all-code-is-slop-lessons/task-009).
# Both directions per prefix setting, fail-open on an unreadable title or payload, silence
# outside a bundle and in an unmarked worktree, and the hooks.json registration.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/plugin/hooks/pr-title.sh"
HOOKSJSON="$REPO/plugin/hooks/hooks.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-title.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not installed (the hook requires it)"; exit 1; }

res() { (cd "$1" 2>/dev/null && pwd -P); }
mkdir -p "$TMP/bundle" "$TMP/elsewhere"
BUNDLE="$(res "$TMP/bundle")"
ELSEWHERE="$(res "$TMP/elsewhere")"
prefix() { printf '{"ticketPrefix": %s}\n' "$1" > "$BUNDLE/instance.config.json"; }

# verdict <project-dir> <command> — allow, deny, or stderr when the hook spoke there
verdict() {
  local out
  out="$(jq -n --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>"$TMP/err")"
  [ -s "$TMP/err" ] && { printf 'stderr'; return; }
  [ -n "$out" ] || { printf 'allow'; return; }
  printf '%s' "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "bad"' 2>/dev/null)"
}
v() { verdict "$BUNDLE" "$1"; }

echo "== ticketPrefix: none =="
prefix null
ok "a stray [task-009] tag is refused"                 "$(v 'gh pr create --title "fix: retry on 429 [task-009]" --body x')" deny
ok "fix: retry on 429 is allowed"                       "$(v 'gh pr create --title "fix: retry on 429" --body x')" allow
ok "a title with no <type>: is refused"                 "$(v 'gh pr create --title "Refuse a PR title" --fill')" deny
ok "an uppercase type is refused"                       "$(v 'gh pr create --title=Fix:thing')" deny
ok "scope, breaking mark and -t are allowed"            "$(v "cd x && gh pr create -t 'feat(hooks)!: add a hook' -B main")" allow
ok "a continued multi-line command is read"             "$(v $'gh pr create \\\n  --title "Refuse a title" \\\n  --body-file b.md')" deny
ok "brackets inside the subject are allowed"            "$(v 'gh pr create --title "fix: handle a[0]"')" allow
ok "a non-Jira prefix in config means none"             "$(prefix '"abc"'; v 'gh pr create --title "fix: x [abc-1]"')" deny

echo "== ticketPrefix: ABC =="
prefix '"ABC"'
ok "[ABC-12] is allowed"                                "$(v 'gh pr create --title "fix: retry [ABC-12]"')" allow
ok "[ABC-0] is allowed"                                 "$(v 'gh pr create --title "fix: retry [ABC-0]"')" allow
ok "a missing tag is refused"                           "$(v 'gh pr create --title "fix: retry"')" deny
ok "a second tag is refused"                            "$(v 'gh pr create --title "fix: retry [task-9] [ABC-1]"')" deny
ok "another prefix is refused"                          "$(v 'gh pr create --title "fix: retry [XYZ-1]"')" deny

echo "== unreadable ⇒ allowed =="
prefix null
ok "no --title"                                         "$(v 'gh pr create --fill')" allow
ok "a command substitution"                             "$(v 'gh pr create --title "$(cat t.txt)"')" allow
ok "a variable"                                         "$(v 'gh pr create --title "$T"')" allow
ok "an escaped quote"                                   "$(v 'gh pr create --title "a \"b\""')" allow
ok "a title glued to more text"                         "$(v 'gh pr create --title "Bad"y')" allow
ok "gh pr create only as an argument"                   "$(v 'echo gh pr create --title "Bad"')" allow
ok "another command"                                    "$(v 'git commit -m "Bad [task-9]"')" allow

echo "== plumbing fails open =="
ok "malformed JSON"                                     "$(printf 'not json gh pr create' | CLAUDE_PROJECT_DIR="$BUNDLE" bash "$HOOK" 2>&1; printf allow)" allow
ok "unparseable config"                                 "$(printf '{' > "$BUNDLE/instance.config.json"; v 'gh pr create --title "Bad"')" allow
prefix null
ok "no jq on PATH"                                      "$(jq -n '{tool_input:{command:"gh pr create --title \"Bad\""}}' > "$TMP/p.json"
  PATH="$TMP/nojq" CLAUDE_PROJECT_DIR="$BUNDLE" /bin/bash "$HOOK" < "$TMP/p.json" 2>&1; printf allow)" allow

echo "== silent outside an instance =="
BAD='gh pr create --title "Bad [task-009]"'
ok "a directory with no instance.config.json"           "$(verdict "$ELSEWHERE" "$BAD")" allow
git init -q -b main "$TMP/repo" && git -C "$TMP/repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
REPOD="$(res "$TMP/repo")"
git -C "$REPOD" worktree add -q "$TMP/wt" -b feat/x >/dev/null 2>&1
WT="$(res "$TMP/wt")"
ok "an unmarked linked worktree"                        "$(verdict "$WT" "$BAD")" allow
printf '%s\n' "$BUNDLE" > "$REPOD/.git/loopd-bundle"
ok "a marked linked worktree refuses"                   "$(verdict "$WT" "$BAD")" deny
ok "…and allows a good title"                           "$(verdict "$WT" 'gh pr create --title "fix: retry on 429"')" allow
ok "the main clone stays un-armed with the marker"      "$(verdict "$REPOD" "$BAD")" allow
printf '%s\n' "$ELSEWHERE" > "$REPOD/.git/loopd-bundle"
ok "a marker naming a non-bundle is ignored"            "$(verdict "$WT" "$BAD")" allow

echo "== registration =="
ok "hooks.json registers it once, Bash-matched" \
   "$(jq -r '[.hooks.PreToolUse[] | select(.hooks[].command | test("pr-title[.]sh")) | .matcher] | join(",")' "$HOOKSJSON")" Bash
ok "…via \${CLAUDE_PLUGIN_ROOT}" \
   "$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("pr-title[.]sh"))' "$HOOKSJSON")" '"${CLAUDE_PLUGIN_ROOT}/hooks/pr-title.sh"'
ok "the hook is executable"                             "$([ -x "$HOOK" ] && echo yes || echo no)" yes

echo; echo "pr-title-hook: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
