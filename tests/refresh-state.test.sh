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
#   * METRICS.json: ONE detached metrics.sh run, reading no PR, when the file is absent or
#     older than the newest full tick; one attempt per tick, one run at a time, a non-zero
#     exit marked and not retried; nothing with the board off.
#   * A PANE REFRESH: the store record whose root resolves to this one starts one run while
#     METRICS.json is older than it, served once (newer, older, same-second, already served,
#     future-dated, a symlinked root, a held lock); the status line starts the worker for it.
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
export PATH="$BIN:$PATH" XDG_CACHE_HOME="$TMP/cache" REFRESH_STATE_DEBOUNCE=0 CLAUDE_CONFIG_DIR="$TMP/config"
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
ln -s "$B" "$TMP/alias"; tick; touch "$B/projects/proj-a/tasks/task-002.md"
bash "$F/scripts/refresh-state.sh" "$TMP/alias"
ok "…and the status line's symlinked spelling stops asking too" "$(stale "$TMP/alias")" no
M="$TMP/midplug"; mkdir -p "$M"; cp -R "$PLUG/scripts" "$M/scripts"; mv "$M/scripts/write-snapshot.sh" "$M/scripts/real-write.sh"
printf '#!/usr/bin/env bash\necho x >> "%s"\n[ -f "%s" ] || { : > "%s"; sleep 1.1; touch "%s"; }\nexec bash "$(dirname "$0")/real-write.sh" "$@"\n' \
  "$TMP/mid-calls" "$TMP/mid-once" "$TMP/mid-once" "$B/projects/proj-a/tasks/task-001.md" > "$M/scripts/write-snapshot.sh"
tick; touch "$B/projects/proj-a/tasks/task-002.md"; bash "$M/scripts/refresh-state.sh" "$B"
ok "an edit made during the write is written next" "$(wc -l < "$TMP/mid-calls" | tr -d ' '):$(stale "$B")" 2:no
mkdir -p "$TMP/evil"; printf '{}\n' > "$TMP/evil/instance.config.json"; ln -s "$B/$AB_DIR" "$TMP/evil/$AB_DIR"
ok "a root whose .loopd is a symlink is refused" "$(ab_board_root "$TMP/evil" >/dev/null && echo yes || echo no)" no

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

echo "== METRICS.json: one run when absent or older than the newest full tick"
S="$TMP/metricsplug"; mkdir -p "$S"; cp -R "$PLUG/scripts" "$S/scripts"
STARTS="$TMP/metrics-starts"; : > "$STARTS"
cat > "$S/scripts/metrics.sh" <<STUB
#!/usr/bin/env bash
printf 'prs=%s wait=%s\\n' "\${METRICS_GH_MAX_PRS:-unset}" "\${METRICS_LOCK_WAIT:-unset}" >> "$STARTS"
mkdir -p "\$1/$AB_METRICS_RUN/lock"; sleep "\${STUB_SLEEP:-0}"; rmdir "\$1/$AB_METRICS_RUN/lock"
exit "\${STUB_RC:-0}"
STUB
starts() { sleep "${1:-0.6}"; grep -c . "$STARTS" | tr -d ' '; }
fire() { bash "$S/scripts/refresh-state.sh" "$1"; }
full() { printf '* TICK %s by example-user-007 open: tick-x · full walk\n* TICK %s by example-user-007 close: walked\n' "$2" "$2" >> "$1/$AB_LEDGER"; }
gen() { printf '{"schema_version":2,"generated_at":"%s"}\n' "$2" > "$1/$AB_METRICS"; }
MB="$TMP/mbundle"; mk "$MB"; RUN="$MB/$AB_METRICS_RUN"
full "$MB" 2026-10-01T01:00:00Z
fire "$MB"
ok "absent starts one" "$(starts)" 1
ok "…reading no PR, waiting on no lock" "$(cat "$STARTS")" "prs=0 wait=0"
ok "…its attempt recorded for that tick" "$(cat "$RUN/attempt")" 2026-10-01T01:00:00Z
fire "$MB"
ok "absent again, same tick: none (one attempt per tick)" "$(starts)" 1
gen "$MB" 2026-10-01T02:00:00Z; rm -f "$RUN/attempt"; fire "$MB"
ok "fresh starts none" "$(starts)" 1
printf '* TICK 2026-10-05T01:00:00Z by example-user-007 close: reaped\n* TICK 2026-10-06T01:00:00Z by example-user-007 idle — fingerprint unchanged\n' >> "$MB/$AB_LEDGER"
fire "$MB"
ok "an unpaired close and an idle line are not a full tick: none" "$(starts)" 1
full "$MB" 2026-10-02T01:00:00Z; fire "$MB"
ok "stale starts one" "$(starts)" 2
fire "$MB"
ok "a run that exits 0 and leaves the file stale is not restarted" "$(starts)" 2
full "$MB" 2026-10-03T01:00:00Z; fire "$MB"
ok "…until a newer full tick" "$(starts)" 3
ok "no failure marker after exit 0" "$([ -e "$RUN/failed" ] && echo marked || echo none)" none

echo "== METRICS.json: one run at a time"
full "$MB" 2026-10-04T01:00:00Z
STUB_SLEEP=2 fire "$MB"; sleep 0.5; full "$MB" 2026-10-07T01:00:00Z; fire "$MB"
ok "a second fire inside one run starts none" "$(starts)" 4
sleep 2; fire "$MB"
ok "…and one once the lock is released" "$(starts)" 5
mkdir -p "$RUN/lock"; full "$MB" 2026-10-08T01:00:00Z; fire "$MB"
ok "a held lock starts none" "$(starts)" 5
touch -t 202001010000 "$RUN/lock"; fire "$MB"
ok "a lock older than 10 minutes is reclaimed" "$(starts)" 6

echo "== METRICS.json: a failed run is marked and not retried"
full "$MB" 2026-10-09T01:00:00Z
STUB_RC=2 fire "$MB"
ok "a non-zero exit starts one" "$(starts)" 7
ok "…and names the exit code and the tick" "$(cat "$RUN/failed")" "exit 2 close 2026-10-09T01:00:00Z"
fire "$MB"
ok "…no new run for that tick" "$(starts)" 7
full "$MB" 2026-10-10T01:00:00Z; fire "$MB"
ok "…one for the next" "$(starts)" 8

echo "== METRICS.json: no full tick, no ledger, board off"
NL="$TMP/noledger"; mk "$NL"; : > "$STARTS"
fire "$NL"; fire "$NL"
ok "no log.md, absent: two fires start one" "$(starts)" 1
ok "…recorded as no tick" "$(cat "$NL/$AB_METRICS_RUN/attempt")" none
printf '* TICK 2026-10-01T01:00:00Z by example-user-007 close: reaped\n' > "$NL/$AB_LEDGER"; fire "$NL"
ok "an unpaired close alone starts none" "$(starts)" 1
BO="$TMP/metricsoff"; mk "$BO"; printf '{ "org": "acme", "board": false }\n' > "$BO/instance.config.json"; fire "$BO"
ok "board off starts none" "$(starts)" 1
ok "…and writes no run directory" "$([ -e "$BO/$AB_METRICS_RUN" ] && echo written || echo none)" none
LK="$TMP/linked"; mk "$LK"; mkdir -p "$TMP/outside/lock"; touch -t 202001010000 "$TMP/outside/lock"
ln -s "$TMP/outside" "$LK/$AB_METRICS_RUN"; fire "$LK"
ok "a symlinked run directory starts none and touches nothing behind it" "$(starts):$(ls -A "$TMP/outside" | tr '\n' ' ')" "1:lock "
SW="$TMP/swapped"; mk "$SW"; mkdir -p "$TMP/outside2"
STUB_SLEEP=1 STUB_RC=2 fire "$SW"; sleep 0.4; mv "$SW/$AB_METRICS_RUN" "$TMP/run-moved"; ln -s "$TMP/outside2" "$SW/$AB_METRICS_RUN"
ok "a run directory swapped for a link mid-run: one start, no marker behind the link" "$(starts 1.5):$(ls -A "$TMP/outside2" | tr '\n' ' ')" "2:"
KD="$TMP/killed"; mk "$KD"
STUB_SLEEP=5 REFRESH_STATE_METRICS_MAX=1 fire "$KD"
i=0; while [ ! -f "$KD/$AB_METRICS_RUN/failed" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
ok "a run past REFRESH_STATE_METRICS_MAX is killed and marked" "$(starts 0):$(cat "$KD/$AB_METRICS_RUN/failed" 2>/dev/null)" "3:exit 143 close none"
OD="$TMP/oddstamp"; mk "$OD"; full "$OD" '2026-10-01T01:00:00Z/../x'; fire "$OD"
ok "a full-tick stamp that is not a timestamp starts none and is never written" "$(starts):$([ -e "$OD/$AB_METRICS_RUN" ] && echo written || echo none)" "3:none"

echo "== METRICS.json: a pane Refresh request"
STORE="$CLAUDE_CONFIG_DIR/plugins/store"; mkdir -p "$STORE"
req() { printf '{"loopd.usage.s1":{"input":1},"loopd.metrics.refresh.%s":{"sessionId":"s1","at":"%s"}}\n' "$1" "$2" > "$STORE/loopd_loopd-x.json"; }
RQ="$TMP/rbundle"; mk "$RQ"; RR="$RQ/$AB_METRICS_RUN"; : > "$STARTS"
full "$RQ" 2026-11-01T09:00:00Z; gen "$RQ" 2026-11-01T10:00:00Z
req "$RQ" 2026-11-01T10:00:05Z; fire "$RQ"
ok "a request newer than generated_at starts one" "$(starts)" 1
ok "…served before the run" "$(cat "$RR/served")" 2026-11-01T10:00:05Z
ok "…reading no PR, so gh figures stay marked stale (METRICS_GH_MAX_PRS=0)" "$(tail -n 1 "$STARTS")" "prs=0 wait=0"
fire "$RQ"
ok "already served, file still older: none" "$(starts)" 1
req "$RQ" 2026-11-01T09:59:00Z; fire "$RQ"
ok "an older request starts none" "$(starts)" 1
req "$RQ" 2026-11-01T10:00:00Z; fire "$RQ"
ok "a same-second request starts none" "$(starts)" 1
req "$RQ" 2099-01-01T00:00:00Z; STUB_RC=2 fire "$RQ"
ok "a future-dated request that fails starts one" "$(starts)" 2
ok "…marked failed against it" "$(cat "$RR/failed")" "exit 2 request 2099-01-01T00:00:00Z"
fire "$RQ"; fire "$RQ"
ok "…and is never restarted" "$(starts)" 2
req "$TMP/elsewhere" 2026-11-01T10:00:08Z; fire "$RQ"
ok "another folder's record starts none" "$(starts)" 2
ln -s "$RQ" "$TMP/rlink"; req "$TMP/rlink" 2026-11-01T10:00:09Z; fire "$RQ"
ok "a record keyed by a symlinked spelling of this root starts one" "$(starts)" 3
mkdir -p "$RR/lock"; req "$RQ" 2026-11-01T10:00:20Z; fire "$RQ"
ok "a request while the run lock is held starts none" "$(starts)" 3
rmdir "$RR/lock"; fire "$RQ"
ok "…and one once it is released" "$(starts)" 4

echo "== the status line starts the worker on a pending request only"
SQ="$TMP/sline"; mk "$SQ"; gen "$SQ" 2026-11-01T10:00:00Z; mkdir -p "$SQ/$AB_METRICS_RUN"; SV="$SQ/$AB_METRICS_RUN/served"
sl() { bash "$SL" --instance "$SQ" --color never </dev/null >/dev/null 2>&1; }
req "$SQ" 2099-01-02T00:00:30Z; tick; : > "$SV"; sv="$(mt "$SV")"
sl; sleep 1.5
ok "store older than the served marker: the status line starts no worker" "$(mt "$SV")" "$sv"
tick; req "$SQ" 2099-01-02T00:00:30Z; sl
ok "a newer store write: its worker serves the request" "$(moved "$SV" "$sv"):$(settle "$SQ"; cat "$SV")" yes:2099-01-02T00:00:30Z
i=0; while [ -d "$SQ/$AB_METRICS_RUN/lock" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done; settle "$SQ"
sv="$(mt "$SV")"; sl; sleep 1.5
ok "…after which nothing starts it" "$(mt "$SV")" "$sv"
mkdir "$SQ/$AB_METRICS_RUN/lock"; tick; req "$SQ" 2099-01-02T00:00:40Z; sl; sleep 1.5
ok "a press during a run: nothing starts while the lock is held" "$(mt "$SV")" "$sv"
tick; touch "$SQ/$AB_METRICS"; rmdir "$SQ/$AB_METRICS_RUN/lock"; sl
ok "…and it is served once the run has replaced METRICS.json and let go" "$(moved "$SV" "$sv"):$(settle "$SQ"; cat "$SV")" yes:2099-01-02T00:00:40Z

echo "== METRICS.json: the real run"
RB="$TMP/realmetrics"; mk "$RB"; full "$RB" 2026-10-01T01:00:00Z
git -C "$RB" init -q 2>/dev/null
bash "$WORKER" "$RB"
i=0; while [ ! -f "$RB/$AB_METRICS" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done; sleep 0.3
ok "the hook's run writes METRICS.json" "$(jq -r .schema_version "$RB/$AB_METRICS" 2>/dev/null)" 2
ok "…releases the lock and leaves no failure marker" "$(ls "$RB/$AB_METRICS_RUN" | tr '\n' ' ')" "attempt "
ok "…and git sees nothing under the run directory" "$(git -C "$RB" status --porcelain --untracked-files=all --ignored=no | grep -c 'metrics-run')" 0

ok "offline: no gh or curl was run" "$([ -e "$SENTINEL" ] && echo touched || echo clean)" clean

echo
echo "refresh-state: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
