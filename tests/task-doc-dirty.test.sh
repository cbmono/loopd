#!/usr/bin/env bash
#
# task-doc-dirty.test.sh — `plugin/hooks/task-doc-dirty.sh`, the Stop hook that reports a role
# agent's task doc left uncommitted in the bundle (all-code-is-slop-lessons/task-013).
#   * WIRED on Stop, executable.
#   * REPORTS a modified or untracked doc of the task whose `worktree:` is the session's path,
#     as one JSON systemMessage; SILENT on a clean doc and on another task's dirty doc.
#   * WRITES NOTHING: bundle HEAD, index and doc bytes unchanged.
#   * SILENT outside an instance, at a bundle root, in an unmarked worktree and in one whose
#     marker names a bundle that does not link the repo back.
# Exit: 0 all assertions pass, 1 one failed, 2 the fixture could not be built.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/plugin/hooks/task-doc-dirty.sh"
[ -f "$HOOK" ] || { echo "task-doc-dirty.test: missing $HOOK" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/taskdocdirty.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
unset CLAUDE_PLUGIN_ROOT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
run() { out="$(CLAUDE_PROJECT_DIR="$1" bash "$HOOK" </dev/null 2>&1)"; rc=$?; }

# <repo> <worktree> <marker target> — a linked worktree of <repo>; empty target ⇒ no marker.
wt() { mkdir -p "$1/.git/worktrees/w" "$2"; [ -n "$3" ] && printf '%s\n' "$3" > "$1/.git/loopd-bundle"
       printf 'gitdir: %s\n' "$1/.git/worktrees/w" > "$2/.git"; printf '../..\n' > "$1/.git/worktrees/w/commondir"; }
# <dir> <worktree of task-001> — a committed bundle with two tasks.
mk() {
  mkdir -p "$1/projects/p/tasks" "$1/repos" || return 1
  printf '{ "org": "acme" }\n' > "$1/instance.config.json"
  printf -- '---\ntitle: "one"\nstatus: in-progress\nworktree: %s\n---\n' "$2" > "$1/projects/p/tasks/task-001.md"
  printf -- '---\ntitle: "two"\nstatus: in-progress\nworktree: %s/elsewhere\n---\n' "$TMP" > "$1/projects/p/tasks/task-002.md"
  git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.com commit -qm init
}
B="$TMP/bundle"; R="$TMP/repo"; W="$TMP/wt"
mk "$B" "$W" && wt "$R" "$W" "$B" && ln -s "$R" "$B/repos/repo" || { echo "task-doc-dirty.test: fixture failed" >&2; exit 2; }
DOC="$B/projects/p/tasks/task-001.md"

echo "== wiring"
reg="$(python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"].get("Stop",[])
print(sum(1 for b in h for x in b["hooks"] if x["command"].endswith("/hooks/task-doc-dirty.sh\"")))' "$REPO/plugin/hooks/hooks.json")"
ok "hooks.json registers it on Stop" "$reg" 1
ok "it is executable" "$([ -x "$HOOK" ] && echo yes || echo no)" yes

echo "== silent where it does not apply"
mkdir -p "$TMP/plain"; run "$TMP/plain"; ok "outside an instance: exit 0, no output" "$rc:$out" "0:"
run "$B"; ok "at the bundle root: exit 0, no output" "$rc:$out" "0:"
wt "$TMP/repo2" "$TMP/wt2" ""; run "$TMP/wt2"; ok "an unmarked worktree: exit 0, no output" "$rc:$out" "0:"
echo x >> "$DOC"
wt "$TMP/repo3" "$TMP/wt3" "$B"; run "$TMP/wt3"
ok "a marker whose bundle does not link the repo back: silent" "$rc:$out" "0:"
git -C "$B" checkout -q -- projects

echo "== clean and dirty"
# A stat-only change to the doc: a plain `git status -- <doc>` would rewrite the index.
sleep 1; touch "$DOC"; idx0="$(cksum < "$B/.git/index")"
run "$W"; ok "a clean task doc (stat changed): exit 0, no output" "$rc:$out" "0:"
ok "…and the bundle's index is not rewritten" "$(cksum < "$B/.git/index")" "$idx0"
echo x >> "$B/projects/p/tasks/task-002.md"; run "$W"
ok "another task's dirty doc: silent" "$rc:$out" "0:"
git -C "$B" checkout -q -- projects
echo x >> "$DOC"
head0="$(git -C "$B" rev-parse HEAD)"; idx0="$(cksum < "$B/.git/index")"; doc0="$(cksum < "$DOC")"
run "$W"
msg="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["systemMessage"])' 2>/dev/null)"
ok "a modified task doc: exit 0" "$rc" 0
ok "…one JSON systemMessage naming the doc" "$(has "$msg" projects/p/tasks/task-001.md)" yes
ok "…and not the clean one" "$(has "$msg" task-002)" no
ok "nothing written: HEAD, index and doc unchanged" \
   "$([ "$(git -C "$B" rev-parse HEAD)" = "$head0" ] && [ "$(cksum < "$B/.git/index")" = "$idx0" ] && [ "$(cksum < "$DOC")" = "$doc0" ] && echo yes || echo no)" yes
ok "…and nothing staged" "$(git -C "$B" diff --cached --name-only | grep -c . | tr -d ' ')" 0
git -C "$B" checkout -q -- projects
git -C "$B" rm -q --cached "$DOC"; git -C "$B" -c user.name=t -c user.email=t@example.com commit -qm untrack
run "$W"; ok "an untracked task doc is reported too" "$(has "$out" task-001.md)" yes

echo
echo "task-doc-dirty: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
