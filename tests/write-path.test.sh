#!/usr/bin/env bash
#
# write-path.test.sh — plugin/hooks/write-path.sh, run through the command hooks.json
# registers. In a marked worktree it reports a write outside the worktree, its task's
# project and knowledge/, and never refuses; every other session shape is silent.
# Mutants: a home-directory path, a sibling project, `..` out of tmp/, and the four
# un-armed shapes (main session, no instance, unmarked worktree, main clone).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOKSJSON="$REPO/plugin/hooks/hooks.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/write-path.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not installed (the hook requires it)"; exit 1; }

B="$TMP/bundle"; mkdir -p "$B/projects/p1/tasks" "$B/projects/p2" "$B/knowledge/findings"
echo '{}' > "$B/instance.config.json"
G="$TMP/repo"; git init -q -b main "$G"
git -C "$G" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
WT="$TMP/wt/task-001"; git -C "$G" worktree add -q "$WT" -b feat/a >/dev/null 2>&1
WT2="$TMP/wt/untasked"; git -C "$G" worktree add -q "$WT2" -b feat/b >/dev/null 2>&1
printf '%s\n' "$B" > "$G/.git/loopd-bundle"
printf -- '---\ntype: Task\nworktree: %s\n---\n' "$WT" > "$B/projects/p1/tasks/task-001.md"
U="$TMP/unmarked"; git init -q -b main "$U"
git -C "$U" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
UWT="$TMP/wt/unmarked"; git -C "$U" worktree add -q "$UWT" -b feat/u >/dev/null 2>&1
PLAIN="$TMP/plain"; mkdir -p "$PLAIN"

REGCMD="$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("write-path.sh")) | .hooks[].command' "$HOOKSJSON")"
# run <project-dir> <tool> <file_path> [cwd] — prints "<rc>|<stdout><stderr>"
run() {
  local payload out rc
  payload="$(jq -cn --arg t "$2" --arg f "$3" --arg c "${4:-$1}" \
           '{hook_event_name:"PreToolUse", tool_name:$t, cwd:$c, tool_input:{file_path:$f}}')" && [ -n "$payload" ] \
    || { echo "run: building the jq payload failed" >&2; printf 'payload-failed|'; return; }
  out="$(CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_PROJECT_DIR="$1" bash -c "exec ${REGCMD}" 2>&1 <<<"$payload")"; rc=$?
  printf '%s|%s' "$rc" "$out"
}
reported() { local r; r="$(run "$@")"; printf '%s' "${r#*|}" | jq -e '.systemMessage | test("write-path")' >/dev/null 2>&1 && echo reported || echo "silent:${r%%|*}"; }
silent() { local r; r="$(run "$@")"; [ "$r" = "0|" ] && echo silent || echo "spoke:$r"; }

echo "== registration"
ok "hooks.json registers write-path.sh on PreToolUse" "$([ -n "$REGCMD" ] && echo yes || echo no)" yes
ok "…matched to Write|Edit" \
   "$(jq -r '[.hooks.PreToolUse[] | select(.hooks[].command | test("write-path.sh")) | .matcher] | join(",")' "$HOOKSJSON")" "Write|Edit"
ok "…and the hook file is executable" "$([ -x "$REPO/plugin/hooks/write-path.sh" ] && echo yes || echo no)" yes

echo "== a marked worktree: reports outside, silent inside"
ok "a home-directory path is reported"          "$(reported "$WT" Write "$HOME/loopd-write-path-probe.txt")" reported
ok "…exit 0 and no permissionDecision (never refuses)" \
   "$(r="$(run "$WT" Write "$HOME/loopd-write-path-probe.txt")"; printf '%s' "${r%%|*}:"; printf '%s' "${r#*|}" | jq -r '.hookSpecificOutput | has("permissionDecision")')" "0:false"
ok "…and the agent gets it as additionalContext" \
   "$(r="$(run "$WT" Write "$HOME/x")"; printf '%s' "${r#*|}" | jq -r '.hookSpecificOutput.additionalContext | test("Where files go")')" true
ok "an Edit is reported under its own name" \
   "$(r="$(run "$WT" Edit "$HOME/x")"; printf '%s' "${r#*|}" | jq -r '.systemMessage | test("Edit to ")')" true
ok "a write under the worktree's tmp/ is silent" "$(silent "$WT" Write "$WT/tmp/task-001/draft.md")" silent
ok "a write in the worktree is silent"           "$(silent "$WT" Edit "$WT/src/a.sh")" silent
ok "a relative path inside it is silent"         "$(silent "$WT" Write "tmp/x.md" "$WT")" silent
ok "a relative path out of it is reported"       "$(reported "$WT" Write "../escape.md" "$WT")" reported
ok "\`..\` out of tmp/ is reported"              "$(reported "$WT" Write "$WT/tmp/../../escape.md")" reported
ok "its task's project folder is silent"         "$(silent "$WT" Edit "$B/projects/p1/tasks/task-001.md")" silent
ok "…and a new file under it too"                "$(silent "$WT" Write "$B/projects/p1/deliverables/sheet.md")" silent
ok "the bundle's knowledge/ is silent"           "$(silent "$WT" Write "$B/knowledge/findings/new.md")" silent
ok "another project's folder is reported"        "$(reported "$WT" Write "$B/projects/p2/x.md")" reported
ok "the bundle root is reported"                 "$(reported "$WT" Write "$B/notes.md")" reported
ok "no task names the worktree: any project is silent" "$(silent "$WT2" Write "$B/projects/p2/x.md")" silent
ok "…and a home path is still reported"          "$(reported "$WT2" Write "$HOME/x")" reported

echo "== every other session is silent (exit 0, no output)"
ok "the main session (rooted in the bundle)"     "$(silent "$B" Write "$HOME/x")" silent
ok "outside an instance"                         "$(silent "$PLAIN" Write "$HOME/x")" silent
ok "a worktree of a repo link-repos.sh never marked" "$(silent "$UWT" Write "$HOME/x")" silent
ok "the marked repo's main clone"                "$(silent "$G" Write "$HOME/x")" silent
printf '%s\n' "$TMP/no-bundle" > "$G/.git/loopd-bundle"
ok "a marker naming no instance"                 "$(silent "$WT" Write "$HOME/x")" silent
printf '%s\n' "$B" > "$G/.git/loopd-bundle"
ok "a payload with no file_path"                 "$(r="$(printf '{"tool_name":"Write"}' | CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_PROJECT_DIR="$WT" bash -c "exec ${REGCMD}" 2>&1)"; echo "$?|$r")" "0|"

echo
echo "write-path: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
