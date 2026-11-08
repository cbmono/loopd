#!/usr/bin/env bash
#
# task-doc-commit.test.sh — a role agent commits its task-doc edit right after the write,
# from the bundle, and `commit-as.sh` refuses the two places that commit would go wrong.
#
# Measured case (cheaper-tidier-ticks/task-004): a session edited its task doc at 15:13 and
# was still working two hours later; every tick in between saw tick-delta's dirty-tree DELTA
# and deferred its pull. There is deliberately no tick-side commit of a leftover edit.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT_AS="$REPO/plugin/scripts/commit-as.sh"
TICK_DELTA="$REPO/plugin/scripts/tick-delta.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/task-doc-commit.XXXXXX")" || {
  echo "task-doc-commit.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

export CLAUDE_CONFIG_DIR="$TMP/no-plugins"; mkdir -p "$CLAUDE_CONFIG_DIR"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\temail = t@example.com\n\tname = Test\n[commit]\n\tgpgsign = false\n[core]\n\thooksPath = /dev/null\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
BIN="$TMP/bin"; mkdir -p "$BIN"; printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"
# CI puts a refusing `claude` on PATH; this one refuses too, so no verdict below can rest on it.
printf '#!/bin/sh\nexit 99\n' > "$BIN/claude"; chmod +x "$BIN/claude"
export PATH="$BIN:$PATH"

echo "== 1. the rule is in the prose of every role that edits its task doc =="
RULE="Commit your task-doc edit immediately after each write — never at the round's end."
ok "CONVENTIONS.md states the rule" "$(has "$REPO/plugin/seed/conventions/rounds.md" "$RULE")" yes
ok "CONVENTIONS.md names the bundle-side command" \
   "$(has "$REPO/plugin/seed/CONVENTIONS.md" 'scripts/commit-as.sh <role> "<msg>" --stage -- <task-doc>')" yes
ok "CONVENTIONS.md: retry once, then leave it" \
   "$(has "$REPO/plugin/seed/CONVENTIONS.md" 'or before your final message if there is none, then leave it.')" yes
for role in software-engineer devops-engineer qa-reviewer; do
  f="$REPO/plugin/agents/$role.md"
  ok "$role.md states the rule" "$(has "$f" "$RULE")" yes
  ok "$role.md: cd <bundle> then commit-as.sh $role" \
     "$(has "$f" "\`cd <bundle>\`, then \`\${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh $role \"<msg>\" --stage -- <task-doc>\`")" yes
  ok "$role.md: retry once on the next write, then leave it" \
     "$(has "$f" 'retry once on your next write, or before your final message if there is none, then leave it.')" yes
done

# A bundle: tracked config, a task doc, a remote to rebase against.
BUNDLE="$TMP/bundle"; TASK=projects/p/tasks/task-001.md
mkdir -p "$BUNDLE/projects/p/tasks"
printf '{ "authorEmail": "t@example.com" }\n' > "$BUNDLE/instance.config.json"
printf 'type: Project\nstatus: active\nautonomy: gated\n' > "$BUNDLE/projects/p/project.md"
printf -- '---\ntype: Task\nkind: build\nstatus: in-progress\npr: []\n---\n# Notes\n' > "$BUNDLE/$TASK"
printf '/.tick-state\n/.loopd/\n' > "$BUNDLE/.gitignore"
git -C "$BUNDLE" init -q && git -C "$BUNDLE" add -A && git -C "$BUNDLE" commit -qm init

# A target repo with a worktree, where the agent's session lives.
TARGET="$TMP/target"; WT="$TMP/wt"
mkdir -p "$TARGET" && git -C "$TARGET" init -q && echo x > "$TARGET/f" \
  && git -C "$TARGET" add f && git -C "$TARGET" commit -qm init && git -C "$TARGET" worktree add -q -b feat "$WT"
echo y > "$WT/f"; git -C "$WT" add f

echo
echo "== 2. BUNDLE ONLY: from the worktree, commit-as.sh refuses and commits nothing =="
before="$(git -C "$WT" rev-parse HEAD)"
out="$(cd "$WT" && bash "$COMMIT_AS" software-engineer "docs: x" --stage -- f 2>&1)"; rc=$?
ok "exit 2" "$rc" 2
ok "…naming instance.config.json" "$(grep -cF 'no instance.config.json' <<<"$out" | tr -d ' ')" 1
ok "…and the target repo's HEAD did not move" "$(git -C "$WT" rev-parse HEAD)" "$before"
out="$(cd "$TMP" && bash "$COMMIT_AS" human "docs: x" -- f 2>&1)"; rc=$?
ok "outside any git repo: exit 2, same refusal" "$rc:$(grep -cF 'not a bundle' <<<"$out" | tr -d ' ')" "2:1"

echo
echo "== 3. NO REBASE RACE: a rebase in progress in the bundle is refused =="
REB="$TMP/reb"; git clone -q "$BUNDLE" "$REB"
printf 'upstream\n' >> "$BUNDLE/$TASK"; git -C "$BUNDLE" commit -qam upstream
printf 'local\n' >> "$REB/$TASK"; git -C "$REB" commit -qam local
git -C "$REB" pull -q --rebase >/dev/null 2>&1
ok "fixture: the pull --rebase stopped mid-rebase" \
   "$([ -d "$(git -C "$REB" rev-parse --absolute-git-dir)/rebase-merge" ] && echo yes || echo no)" yes
printf 'mine\n' > "$REB/projects/p/tasks/task-002.md"
before="$(git -C "$REB" rev-parse HEAD)"
out="$(cd "$REB" && bash "$COMMIT_AS" software-engineer "docs: x" --stage -- projects/p/tasks/task-002.md 2>&1)"; rc=$?
ok "exit 2" "$rc" 2
ok "…naming the rebase" "$(grep -cF 'a rebase is in progress' <<<"$out" | tr -d ' ')" 1
ok "…and nothing was committed into it" "$(git -C "$REB" rev-parse HEAD)" "$before"
git -C "$REB" rebase --abort
out="$(cd "$REB" && bash "$COMMIT_AS" software-engineer "docs: x" --stage -- projects/p/tasks/task-002.md 2>&1)"; rc=$?
ok "the retry after the rebase ends commits" "$rc" 0

echo
echo "== 4. OUTCOME: the 15:13 state, committed per the rule, is no dirty-tree DELTA =="
printf -- '---\ntype: Task\nkind: build\nstatus: in-progress\npr: []\n---\n# Notes\n* 15:13 still working\n' > "$BUNDLE/$TASK"
out="$(bash "$TICK_DELTA" check --instance "$BUNDLE" 2>&1)"
ok "control: the uncommitted edit IS the dirty-tree DELTA" "$(grep -cF 'tracked files are dirty' <<<"$out" | tr -d ' ')" 1
(cd "$WT" && bash "$COMMIT_AS" software-engineer "docs: task-001 pr" --stage -- "$BUNDLE/$TASK" >/dev/null 2>&1)
ok "…committing it from the worktree does not clean it" \
   "$(git -C "$BUNDLE" status --porcelain --untracked-files=no | wc -l | tr -d ' ')" 1
(cd "$BUNDLE" && bash "$COMMIT_AS" software-engineer "docs: task-001 pr" --stage -- "$TASK" >/dev/null 2>&1)
ok "cd <bundle> then commit-as.sh: the tree is clean" \
   "$(git -C "$BUNDLE" status --porcelain --untracked-files=no | wc -l | tr -d ' ')" 0
ok "…authored as the role" "$(git -C "$BUNDLE" log -1 --format=%an)" software-engineer
bash "$TICK_DELTA" record --instance "$BUNDLE" >/dev/null 2>&1
out="$(bash "$TICK_DELTA" check --instance "$BUNDLE" 2>&1)"; rc=$?
verdict="rc=$rc ${out%%$'\n'*}"
[ "$rc" = 0 ] || [ "$rc" = 1 ] && verdict="$(grep -cE 'untracked file|cannot be judged' <<<"$out" | tr -d ' ')"
ok "tick-delta.sh check reaches a verdict past the tree gate (rc 0/1)" "$verdict" 0
ok "tick-delta.sh check: no dirty-tree DELTA" "$(grep -cF 'tracked files are dirty' <<<"$out" | tr -d ' ')" 0

echo
echo "task-doc-commit.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
