#!/usr/bin/env bash
# push-commit.sh — the push tail `/loopd:new-project` and `/loopd:answer` share, against a
# real clone of a bare remote: pushed, no upstream (silent), rejected, remote moved under a
# dirty tree, a rebase already running, and a copy with the push removed fails the pushed case.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/push-commit.sh"
SKILL="$REPO/plugin/skills/new-project/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/push-commit-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

ident() { git -C "$1" config user.name t; git -C "$1" config user.email t@example.com; }
fixture() { # <name> — a clone tracking a bare remote, plus one new local commit
  local b="$TMP/$1"
  git init -q --bare "$b.git"; git init -q -b main "$b"; ident "$b"
  echo a > "$b/log.md"; git -C "$b" add -A; git -C "$b" commit -qm init
  git -C "$b" remote add origin "$b.git"; git -C "$b" push -q -u origin main
  mkdir -p "$b/projects/p"; echo p > "$b/projects/p/project.md"
  git -C "$b" add -A; git -C "$b" commit -qm "feat: add p project"
  echo "$b"
}
other_pushes() { # <bundle> <file> — another clone pushes a commit
  git clone -q -b main "$1.git" "$1.other" 2>/dev/null; ident "$1.other"
  echo o >> "$1.other/$2"; git -C "$1.other" add -A; git -C "$1.other" commit -qm "other clone"; git -C "$1.other" push -q origin main
}
remote() { git -C "$1.git" log -1 --format=%s main; }
rebasing() { [ -d "$1/.git/rebase-merge" ] || [ -d "$1/.git/rebase-apply" ] && echo yes || echo no; }

echo "== PUSHED: the commit reaches the remote, silently =="
B="$(fixture pushed)"
OUT="$(bash "$SH" "$B" 2>&1)"; RC=$?
ok "exit 0, nothing printed"                  "$RC,$OUT" "0,"
ok "the remote has the commit"                "$(remote "$B")" "feat: add p project"
B="$(fixture dirty)"; echo wip >> "$B/log.md"
ok "a dirty tree, remote unmoved: exit 0"     "$(bash "$SH" "$B" 2>/dev/null; echo $?)" 0
ok "…pushed"                                  "$(remote "$B")" "feat: add p project"
B="$(fixture moved)"; other_pushes "$B" other.md
ok "remote moved, clean tree: exit 0"         "$(bash "$SH" "$B" 2>/dev/null; echo $?)" 0
ok "…rebased onto it and pushed"              "$(git -C "$B.git" log -2 --format=%s main | tr '\n' '|')" "feat: add p project|other clone|"

echo
echo "== NO UPSTREAM: exit 3, silent, nothing pushed =="
B="$(fixture solo)"; git -C "$B" branch -q --unset-upstream
OUT="$(bash "$SH" "$B" 2>&1)"; RC=$?
ok "exit 3, nothing printed"                  "$RC,$OUT" "3,"
ok "…the remote is untouched"                 "$(remote "$B")" "init"

echo
echo "== REJECTED: exit 4, one line, the commit stays local, nothing forced =="
B="$(fixture rejected)"; printf '#!/bin/sh\nexit 1\n' > "$B.git/hooks/pre-receive"; chmod +x "$B.git/hooks/pre-receive"
OUT="$(bash "$SH" "$B" 2>&1)"; RC=$?
ok "exit 4"                                   "$RC" 4
ok "…one line saying so"                      "$(printf '%s\n' "$OUT" | wc -l | tr -d ' '),$(printf '%s' "$OUT" | grep -c 'push was rejected')" "1,1"
ok "…the commit is still local"               "$(git -C "$B" log -1 --format=%s)" "feat: add p project"
ok "…the remote is untouched"                 "$(remote "$B")" "init"
B="$(fixture dirtymoved)"; other_pushes "$B" log.md; echo wip >> "$B/log.md"
OUT="$(bash "$SH" "$B" 2>&1)"; RC=$?
ok "remote moved under a dirty tree: exit 4"  "$RC" 4
ok "…pull --rebase failed, said once"         "$(printf '%s' "$OUT" | grep -c 'pull --rebase failed')" 1
ok "…no rebase left in progress"              "$(rebasing "$B")" no
ok "…the dirty edit is still there"           "$(tail -n1 "$B/log.md")" wip
B="$(fixture conflict)"; other_pushes "$B" log.md
echo mine >> "$B/log.md"; git -C "$B" commit -qam "local edit"
ok "a conflicting rebase: exit 4"             "$(bash "$SH" "$B" 2>/dev/null; echo $?)" 4
ok "…its own rebase is aborted"               "$(rebasing "$B")" no
ok "…the commit is still local"               "$(git -C "$B" log -1 --format=%s)" "local edit"
GIT_REFLOG_ACTION=tick git -C "$B" rebase '@{u}' >/dev/null 2>&1
OUT="$(bash "$SH" "$B" 2>&1)"; RC=$?
ok "a rebase already in progress: exit 4"     "$RC" 4
ok "…left in progress, not aborted"           "$(rebasing "$B")" yes
ok "…saying so"                               "$(printf '%s' "$OUT" | grep -c 'already in progress')" 1
ok "the script never forces"                  "$(grep -cE -- '--force|push -f|-f( |$)' "$SH" | tr -d ' ')" 0

echo
echo "== THE PROBE BITES: a copy with the push removed fails the pushed case =="
sed '/ push --quiet/d' "$SH" > "$TMP/nopush.sh"
B="$(fixture mutant)"; bash "$TMP/nopush.sh" "$B" >/dev/null 2>&1
ok "the mutant leaves the remote at init"     "$(remote "$B")" "init"

echo
echo "== THE SKILL runs the script, and may =="
ok "allowed-tools grants push-commit.sh"      "$(sed -n '/^allowed-tools:/p' "$SKILL" | grep -cF 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/push-commit.sh:*)')" 1
ok "…step 7 calls it with that prefix"        "$(grep -cF '`bash ${CLAUDE_PLUGIN_ROOT}/scripts/push-commit.sh .`' "$SKILL")" 1
ok "…and runs no git pull or push itself"     "$(grep -cE 'git (pull|push)' "$SKILL" | tr -d ' ')" 0
ok "answer.sh shares the same tail"           "$(grep -c 'push-commit.sh' "$REPO/plugin/scripts/answer.sh")" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
