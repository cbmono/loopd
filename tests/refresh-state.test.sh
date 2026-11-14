#!/usr/bin/env bash
#
# refresh-state.test.sh — `plugin/hooks/refresh-state.sh` and the worker it starts,
# `plugin/scripts/refresh-state.sh`: the two files /pane polls follow a session's turn.
#
# THE PROPERTIES:
#   * WIRED: hooks.json registers the hook on Stop, SubagentStop and UserPromptSubmit.
#   * THE HOOK RETURNS AT ONCE AND SAYS NOTHING; outside a bundle it starts nothing.
#   * A TURN'S EDIT REACHES THE FILES: a task doc moves ⇒ SNAPSHOT.json and counts.json are
#     rewritten seconds later, by write-snapshot.sh and counts.sh, never by a second writer.
#   * AN UNCHANGED TREE COSTS NO WRITE of the snapshot; a missing snapshot is never created.
#   * A FAILING WRITER IS NOT RETRIED until an input moves again (the stamp).
#   * ONE RUN AT A TIME: a held lock turns a second run away; a dead run's lock is taken over.
#   * A LINKED WORKTREE'S SESSION refreshes its bundle only when that bundle links the repo
#     back; a marker naming any other folder, or a board that is off, starts no worker.
#   * THE STATUS LINE starts it for a stale snapshot only (a hand edit with no turn).
#   * OFFLINE: `gh` and `curl` are PATH stubs that leave a sentinel.
# Fixtures live under mktemp; no real bundle is touched.
# Exit: 0 all assertions pass, 1 one failed, 2 the fixture could not be built.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLUG="$REPO/plugin"
HOOK="$PLUG/hooks/refresh-state.sh"
WORKER="$PLUG/scripts/refresh-state.sh"
SL="$PLUG/scripts/status-line.sh"
for f in "$HOOK" "$WORKER" "$SL"; do [ -f "$f" ] || { echo "refresh-state.test: missing $f" >&2; exit 2; }; done
TMP="$(mktemp -d "${TMPDIR:-/tmp}/refreshstate.XXXXXX")" || {
  echo "refresh-state.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"   # the worker keys its stamp and lock on the canonical root

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
SENTINEL="$TMP/network-was-touched"
for t in gh curl; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "%s"\nexit 99\n' "$SENTINEL" > "$BIN/$t"; chmod +x "$BIN/$t"
done
printf '#!/usr/bin/env bash\necho "[]"\n' > "$BIN/claude"; chmod +x "$BIN/claude"
export PATH="$BIN:$PATH" XDG_CACHE_HOME="$TMP/cache" REFRESH_STATE_DEBOUNCE=0
unset CLAUDE_PLUGIN_ROOT

mt() { stat -c %.9Y "$1" 2>/dev/null || stat -f %Fm "$1" 2>/dev/null || echo none; }
tick() { sleep 1.1; }   # past the one-second mtime some `-nt` builds compare
# <file> <old mtime> — wait up to 10 s for the file to move; prints yes/no.
moved() { local i=0; while [ "$i" -lt 100 ]; do [ "$(mt "$1")" != "$2" ] && { echo yes; return; }; sleep 0.1; i=$((i+1)); done; echo no; }
# <root> — let a detached run finish (its lock gone), at most 10 s.
settle() { local i=0 l; l="$(ab_refresh_stamp "$1").lock"; while [ -d "$l" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done; sleep 0.3; }
stale() { ab_snapshot_stale "$1" && echo yes || echo no; }

mk() { # <dir> — a bundle with one project, two tasks, the board on
  local d="$1"
  mkdir -p "$d/projects/proj-a/tasks" "$d/$AB_DIR" || return 1
  printf '{ "org": "acme" }\n' > "$d/instance.config.json"
  printf -- '---\ntitle: "A"\nstatus: active\n---\n' > "$d/projects/proj-a/project.md"
  printf -- '---\ntitle: "one"\nstatus: ready\n---\n' > "$d/projects/proj-a/tasks/task-001.md"
  printf -- '---\ntitle: "two"\nstatus: in-progress\n---\n' > "$d/projects/proj-a/tasks/task-002.md"
  : > "$d/$AB_SNAPSHOT"
  (cd "$d" && bash "$PLUG/scripts/write-snapshot.sh" --quiet) || return 1
}
B="$TMP/bundle"; mk "$B" || { echo "refresh-state.test: fixture failed" >&2; exit 2; }

echo "== wiring"
reg() { python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"].get(sys.argv[2],[])
print(sum(1 for b in h for x in b["hooks"] if x["command"].endswith("/hooks/refresh-state.sh\"")))' "$PLUG/hooks/hooks.json" "$1"; }
for ev in Stop SubagentStop UserPromptSubmit; do ok "hooks.json registers it on $ev" "$(reg "$ev")" 1; done
ok "both scripts are executable" "$([ -x "$HOOK" ] && [ -x "$WORKER" ] && echo yes || echo no)" yes

echo "== outside a bundle: silent, nothing started"
mkdir -p "$TMP/elsewhere"
out="$(CLAUDE_PROJECT_DIR="$TMP/elsewhere" bash "$HOOK" </dev/null 2>&1)"; rc=$?
ok "exit 0, no output" "$rc:$out" "0:"
ok "no stamp or lock under the cache" "$(ls "$XDG_CACHE_HOME/loopd" 2>/dev/null | grep -c refresh)" 0

echo "== a turn's edit reaches SNAPSHOT.json and counts.json"
ok "fresh fixture is not stale" "$(stale "$B")" no
tick
sed -i.bak 's/^status: ready$/status: in-review/' "$B/projects/proj-a/tasks/task-001.md" && rm -f "$B/projects/proj-a/tasks/task-001.md.bak"
ok "an edited task doc makes it stale" "$(stale "$B")" yes
s0="$(mt "$B/$AB_SNAPSHOT")"
t0="$(date +%s)"
out="$(CLAUDE_PROJECT_DIR="$B" bash "$HOOK" </dev/null 2>&1)"; rc=$?
ok "the hook exits 0 at once, saying nothing" "$rc:$out:$(( $(date +%s) - t0 < 2 ))" "0::1"
ok "SNAPSHOT.json is rewritten" "$(moved "$B/$AB_SNAPSHOT" "$s0")" yes
settle "$B"
ok "…carrying the new status" "$(grep -c '"status": *"in-review"' "$B/$AB_SNAPSHOT" | awk '{print ($1>0)?"yes":"no"}')" yes
ok "counts.json is written, the doc's status in it" "$(grep -o '"in_review":[0-9]*' "$B/$AB_COUNTS")" '"in_review":1'
ok "no longer stale" "$(stale "$B")" no

echo "== an unchanged tree writes no snapshot"
s1="$(mt "$B/$AB_SNAPSHOT")"; c1="$(mt "$B/$AB_COUNTS")"
tick; bash "$WORKER" "$B"
ok "snapshot mtime unchanged" "$(mt "$B/$AB_SNAPSHOT")" "$s1"
ok "counts.json still rewritten (session words have no file to stat)" "$([ "$(mt "$B/$AB_COUNTS")" != "$c1" ] && echo yes || echo no)" yes

echo "== no snapshot: the off switch holds"
N="$TMP/off"; mk "$N"; rm -f "$N/$AB_SNAPSHOT"; tick; touch "$N/projects/proj-a/tasks/task-001.md"
bash "$WORKER" "$N"
ok "SNAPSHOT.json is not created" "$([ -e "$N/$AB_SNAPSHOT" ] && echo yes || echo no)" no

echo "== a failing writer is not retried until an input moves"
F="$TMP/failplug"; mkdir -p "$F"; cp -R "$PLUG/scripts" "$F/scripts"
printf '#!/usr/bin/env bash\necho x >> "%s"\nexit 1\n' "$TMP/writer-calls" > "$F/scripts/write-snapshot.sh"
tick; touch "$B/projects/proj-a/tasks/task-002.md"
bash "$F/scripts/refresh-state.sh" "$B"; bash "$F/scripts/refresh-state.sh" "$B"
ok "two runs after one edit call the writer once" "$(wc -l < "$TMP/writer-calls" | tr -d ' ')" 1
tick; touch "$B/projects/proj-a/tasks/task-002.md"; bash "$F/scripts/refresh-state.sh" "$B"
ok "…and again after the next edit" "$(wc -l < "$TMP/writer-calls" | tr -d ' ')" 2

echo "== one run at a time"
bash "$WORKER" "$B"; settle "$B"   # clean again with the real writer
lock="$(ab_refresh_stamp "$B").lock"; mkdir -p "$lock"
tick; touch "$B/projects/proj-a/tasks/task-002.md"; s2="$(mt "$B/$AB_SNAPSHOT")"
bash "$WORKER" "$B"
ok "a held lock turns the run away" "$(mt "$B/$AB_SNAPSHOT")" "$s2"
touch -t 202001010000 "$lock"
bash "$WORKER" "$B"
ok "a dead run's lock (over 2 min) is taken over" "$([ "$(mt "$B/$AB_SNAPSHOT")" != "$s2" ] && echo yes || echo no)" yes
ok "…and released" "$([ -d "$lock" ] && echo held || echo free)" free

echo "== a linked worktree's session: the marker is trusted only as far as it is checked"
# <repo> <worktree> <marker target> — a worktree of <repo> whose common dir's marker names it.
wt() { mkdir -p "$1/.git/worktrees/w" "$2"; printf '%s\n' "$3" > "$1/.git/loopd-bundle"
       printf 'gitdir: %s\n' "$1/.git/worktrees/w" > "$2/.git"; printf '../..\n' > "$1/.git/worktrees/w/commondir"; }
cache_n() { ls "$XDG_CACHE_HOME/loopd" 2>/dev/null | grep -c refresh; }
R="$TMP/repo"; W="$TMP/wt"; wt "$R" "$W" "$B"
mkdir -p "$B/repos"; ln -s "$R" "$B/repos/repo"
tick; touch "$B/projects/proj-a/project.md"; s3="$(mt "$B/$AB_SNAPSHOT")"
CLAUDE_PROJECT_DIR="$W" bash "$HOOK" </dev/null
ok "a marked bundle that links the repo back is refreshed" "$(moved "$B/$AB_SNAPSHOT" "$s3")" yes
settle "$B"
X="$TMP/victim"; mkdir -p "$X"; printf 'keep\n' > "$X/file"; n0="$(cache_n)"
wt "$TMP/repo2" "$TMP/wt2" "$X"
out="$(CLAUDE_PROJECT_DIR="$TMP/wt2" bash "$HOOK" </dev/null 2>&1)"; rc=$?; sleep 1
ok "a marker naming a folder with no .loopd/ or config: exit 0, silent" "$rc:$out" "0:"
ok "…no worker: nothing written there, no stamp" "$(ls -A "$X" | tr '\n' ' ')|$(cache_n)" "file |$n0"
O="$TMP/other"; mk "$O"; tick; touch "$O/projects/proj-a/project.md"; so="$(mt "$O/$AB_SNAPSHOT")"
wt "$TMP/repo3" "$TMP/wt3" "$O"
CLAUDE_PROJECT_DIR="$TMP/wt3" bash "$HOOK" </dev/null; sleep 1.5
ok "a real bundle that does not link the repo back is not written" "$(mt "$O/$AB_SNAPSHOT")" "$so"
bash "$WORKER" "projects/../$(basename "$O")" </dev/null; ( cd "$TMP" && bash "$WORKER" other ); sleep 0.5
ok "the worker refuses a relative argv" "$(mt "$O/$AB_SNAPSHOT")" "$so"
F2="$TMP/boardoff"; mk "$F2"; rm -f "$F2/$AB_SNAPSHOT"
CLAUDE_PROJECT_DIR="$F2" bash "$HOOK" </dev/null; sleep 1
ok "no SNAPSHOT.json (board off): the hook starts no worker" "$([ -e "$F2/$AB_COUNTS" ] && echo written || echo none)" none

echo "== the status line starts it for a stale snapshot only"
s4="$(mt "$B/$AB_SNAPSHOT")"
bash "$SL" --instance "$B" --color never </dev/null >/dev/null 2>&1; sleep 1.5; settle "$B"
ok "fresh snapshot: the status line leaves it alone" "$(mt "$B/$AB_SNAPSHOT")" "$s4"
tick; touch "$B/projects/proj-a/tasks/task-001.md"
bash "$SL" --instance "$B" --color never </dev/null >/dev/null 2>&1
ok "stale snapshot: the status line has it rewritten" "$(moved "$B/$AB_SNAPSHOT" "$s4")" yes
settle "$B"

ok "offline: no gh or curl was run" "$([ -e "$SENTINEL" ] && echo touched || echo clean)" clean

echo
echo "refresh-state: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
