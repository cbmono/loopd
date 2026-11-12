#!/usr/bin/env bash
#
# snapshot-after-write.test.sh — the in-session writers rewrite SNAPSHOT.json after their
# commit, so /pane needs no tick: plugin/scripts/new-project-file.sh end to end, then
# plugin/scripts/answer.sh and plugin/scripts/unblock.sh, and the step in the new-project,
# close-project and handoff skills. Both directions: a copy with the call removed leaves the
# snapshot stale, an absent SNAPSHOT.json stays absent, a failing writer fails no caller.
# Fixtures under mktemp; no gh, no network. Exit: 0 all pass · 1 one failed · 2 no fixture.
# Reasoning: pane-refresh-in-session/task-001.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
command -v python3 >/dev/null 2>&1 || { echo "  (python3 absent — skipped)"; echo "pass=0 fail=0"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/snapshot-after-write.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s — got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

S="$REPO/plugin/scripts"
# The same scripts with the one call removed: what the tree was before this harness existed.
MUT="$TMP/mutant"
mkdir -p "$MUT" && cp -R "$S" "$REPO/plugin/.claude-plugin" "$MUT/" || exit 2
for f in new-project-file answer unblock; do
  grep -v 'write-snapshot\.sh' "$S/$f.sh" > "$MUT/scripts/$f.sh"
  ok "$f.sh calls write-snapshot.sh on exactly one line" \
     "$(( $(wc -l < "$S/$f.sh") - $(wc -l < "$MUT/scripts/$f.sh") ))" 1
done

N=0
fresh() { # -> a committed fixture bundle in $D, on the board, its snapshot stamped in the past
  D="$TMP/b$((++N))"
  bash "$REPO/tests/fixtures/simple-board/mk.sh" "$D" >/dev/null 2>&1 || { echo "fixture failed"; exit 2; }
  printf '%s\n' "/$AB_SNAPSHOT" > "$D/.gitignore"
  ( cd "$D" && git init -q -b main && git config user.name "Example Human" && git config user.email t@example.com &&
    git add -A && git commit -qm fixture ) || { echo "fixture failed"; exit 2; }
}
# snap <python expression over d> — read off the bundle's SNAPSHOT.json; `unreadable` when it is not JSON.
# The expression is always a literal of this file, never fixture or bundle text.
snap() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' "$D/$AB_SNAPSHOT" "$1" 2>/dev/null || echo unreadable; }
task() { snap "[t[\"$3\"] for p in d[\"projects\"] if p[\"slug\"] == \"$1\" for t in p[\"tasks\"] if t[\"id\"] == \"$2\"]"; }
has() { snap "\"$1\" in [p[\"slug\"] for p in d[\"projects\"]]"; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
ENTRY="$TMP/entry.json"
printf '{"id":"aaaaaaaa","title":"Pane refresh probe","what":"w","who":"p","doneWhen":"d","repo":"owner/name","from":"example-user-007"}\n' > "$ENTRY"
SLUG=pane-refresh-probe

echo "== 1. new-project-file.sh: the project is in SNAPSHOT.json with no tick =="
fresh
ok "before: the snapshot does not know the slug" "$(has $SLUG)" False
ok "new-project-file.sh creates it" "$(rc bash "$S/new-project-file.sh" --instance "$D" "$ENTRY")" 0
ok "…committed" "$(git -C "$D" log -1 --format=%s)" "feat: add $SLUG project"
ok "…and its slug is in SNAPSHOT.json" "$(has $SLUG)" True
ok "…with its seed task a draft" "$(task $SLUG task-001-$SLUG status)" "['draft']"
ok "…and the snapshot is still untracked" "$(git -C "$D" status --porcelain | wc -l | tr -d ' ')" 0
fresh
ok "without the call the project is still created" "$(rc bash "$MUT/scripts/new-project-file.sh" --instance "$D" "$ENTRY")|$([ -f "$D/projects/$SLUG/project.md" ] && echo made)" "0|made"
ok "…and the snapshot stays stale: this harness sees the call go" "$(has $SLUG)" False

echo "== 2. absent stays absent; a failing writer fails nobody =="
fresh; rm -f "$D/$AB_SNAPSHOT"
ok "board off: the project is created" "$(rc bash "$S/new-project-file.sh" --instance "$D" "$ENTRY")|$([ -f "$D/projects/$SLUG/project.md" ] && echo made)" "0|made"
ok "…and SNAPSHOT.json is not" "$([ -e "$D/$AB_SNAPSHOT" ] && echo present || echo absent)" absent
fresh; rm -f "$D/$AB_SNAPSHOT"; mkdir "$D/$AB_SNAPSHOT"
ok "write-snapshot.sh refuses a directory at that path" "$(cd "$D" && rc bash "$S/write-snapshot.sh" --quiet)" 2
ok "…and new-project-file.sh still exits 0" "$(rc bash "$S/new-project-file.sh" --instance "$D" "$ENTRY")" 0
ok "…with the project committed" "$(git -C "$D" log -1 --format=%s)" "feat: add $SLUG project"
ok "…and answer.sh still exits 0" "$(rc bash "$S/answer.sh" --instance "$D" "$D/projects/invoices/tasks/task-003.md" Q14 --text Monday)" 0
ok "…and unblock.sh still exits 0" "$(rc bash "$S/unblock.sh" --instance "$D" "$D/projects/invoices/tasks/task-002.md" --decision go)" 0

echo "== 3. answer.sh and unblock.sh =="
for tree in "$S" "$MUT/scripts"; do
  [ "$tree" = "$S" ] && { want_q=0; want_s=ready; say="the shipped script"; } || { want_q=1; want_s=blocked; say="without the call"; }
  fresh
  ok "before: Q14 is open in the snapshot, task-002 blocked" \
     "$(task invoices task-003 open_questions)|$(task invoices task-002 status)" "[1]|['blocked']"
  ok "$say: answer.sh answers Q14" "$(rc bash "$tree/answer.sh" --instance "$D" "$D/projects/invoices/tasks/task-003.md" Q14 --text Monday)" 0
  ok "…and the snapshot's open question count is $want_q" "$(task invoices task-003 open_questions)" "[$want_q]"
  ok "$say: unblock.sh returns task-002 to ready" "$(rc bash "$tree/unblock.sh" --instance "$D" "$D/projects/invoices/tasks/task-002.md" --decision go)|$(grep -c '^status: ready' "$D/projects/invoices/tasks/task-002.md")" "0|1"
  ok "…and the snapshot says $want_s" "$(task invoices task-002 status)" "['$want_s']"
done

echo "== 4. the three skills: the step is last, and allowed where a skill declares its tools =="
CALL='scripts/write-snapshot.sh --quiet'
for sk in new-project close-project handoff; do
  f="$REPO/plugin/skills/$sk/SKILL.md"
  at="$(grep -nF "$CALL" "$f" | tail -n1 | cut -d: -f1)"
  ok "$sk names the call" "$([ -n "$at" ] && echo yes || echo no)" yes
  last="$(awk '/^allowed-tools:/ { next } /commit-as\.sh|push-commit\.sh|build-awaiting\.sh/ { n = NR } END { print n + 0 }' "$f")"
  ok "…after its last commit, push and queue rebuild" "$([ "${at:-0}" -gt "$last" ] && echo after || echo "line ${at:-none} vs $last")" after
  if grep -q '^allowed-tools:' "$f"; then
    ok "…and its allowed-tools permits it" "$(grep '^allowed-tools:' "$f" | grep -cF 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-snapshot.sh:*)')" 1
  fi
done

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
