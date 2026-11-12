#!/usr/bin/env bash
#
# tick-delta-inflight.test.sh — `tick-delta.sh check` lets an in-progress task whose session is
# busy and unchanged go IDLE, and every in-flight fact that moves is still a DELTA: head SHA,
# a check run, mergeable/mergeStateStatus, a review, the session's status, a stop coming due,
# and an in-progress task with no live session (cheaper-tidier-ticks/task-006). Rows come from
# `mk` in tests/session-sweep-bounds.test.sh, read out of that file rather than copied; `claude`
# and `gh` are PATH stubs that log each call. Exit 0 pass, 1 fail, 2 setup.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/plugin/scripts"; TD="$S/tick-delta.sh"; MKSRC="$REPO/tests/session-sweep-bounds.test.sh"
for f in "$TD" "$MKSRC"; do [ -f "$f" ] || { echo "tick-delta-inflight.test: $f not found" >&2; exit 2; }; done
for t in python3 jq git; do command -v "$t" >/dev/null 2>&1 || { echo "tick-delta-inflight.test: $t required" >&2; exit 2; }; done
. "$S/bundle-paths.sh" || exit 2
TMP="$(mktemp -d "${TMPDIR:-/tmp}/td-inflight.XXXXXX")" || exit 2
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.email=t@example.com \
          -c user.name=Test -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

eval "$(sed -n '/^mk() {$/,/^}$/p' "$MKSRC")"
declare -F mk >/dev/null || { echo "tick-delta-inflight.test: no mk() in $MKSRC" >&2; exit 2; }

LIVE=$$
B="$TMP/bundle"; WT="$TMP/wt"; T="$B/projects/p/tasks"
mkdir -p "$T" "$WT" "$TMP/cfg/projects/p" "$TMP/bin" "$TMP/gh"
printf '{ "worktreeRoot": "%s", "maxBgRoundMinutes": 240, "maxIdleMinutes": 120 }\n' "$WT" > "$B/instance.config.json"
printf 'type: Project\nstatus: active\n' > "$B/projects/p/project.md"
printf '/%s\n' "$AB_STATE_DIR" > "$B/.gitignore"
u() { printf '%s-0000-4000-8000-000000000000' "$1"; }
URL=https://github.com/example-org/example-repo/pull
task() { # <name> <status> <session-short|-> <pr-n|->
  { printf -- '---\ntype: Task\nkind: build\nstatus: %s\nworktree: %s/%s\n' "$2" "$WT" "$1"
    [ "$3" = - ] || printf 'session: %s\n' "$(u "$3")"
    [ "$4" = - ] && printf 'pr: []\n' || printf 'pr: ["%s/%s"]\n' "$URL" "$4"
    printf -- '---\n'; } > "$T/$1.md"
}
task task-001-run in-progress a1a10001 1
task task-002-rev in-review b2b20002 2
GIT -C "$B" init -q && GIT -C "$B" add -A && GIT -C "$B" commit -qm init

cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "${1:-}" in agents) cat "$FIXTURE" ;; *) exit 1 ;; esac
STUB
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
n=""; filter="."
while [ $# -gt 0 ]; do
  case "$1" in -F) case "$2" in n=*) n="${2#n=}" ;; esac; shift 2 ;; --jq) filter="$2"; shift 2 ;; *) shift ;; esac
done
jq -r "$filter" "$GHDIR/$n"
STUB
chmod +x "$TMP/bin/claude" "$TMP/bin/gh"
export FIXTURE="$TMP/rows.json" CALLS="$TMP/calls" GHDIR="$TMP/gh" CLAUDE_CONFIG_DIR="$TMP/cfg"
export CLAUDE_CODE_SESSION_ID="$(u 5e1f0001)" PATH="$TMP/bin:$PATH"

run() { : > "$CALLS"; local out rc; out="$(bash "$TD" check --instance "$B" 2>&1)"; rc=$?
        printf 'rc:%s %s' "$rc" "$(head -1 <<<"$out" | cut -c1-12)"; }
rec() { rm -rf "$B/$AB_TICK_START"; bash "$TD" digest --instance "$B" >/dev/null 2>&1; bash "$TD" record --instance "$B" >/dev/null 2>&1; }
# <n> [head] [check-run conclusion] [mergeable] [mergeStateStatus] [reviews]
prj() {
  local runs='[{"__typename":"CheckRun","name":"harness suite","status":"COMPLETED","conclusion":"'"${3:-SUCCESS}"'"},{"__typename":"StatusContext","context":"CodeRabbit","state":"SUCCESS","description":"Review completed"}]'
  local revs='{"totalCount":0,"nodes":[]}'
  [ "${6:-0}" -gt 0 ] && revs='{"totalCount":'"$6"',"nodes":[{"id":"PRR_'"$6"'","state":"COMMENTED"}]}'
  printf '{"data":{"repository":{"pullRequest":{"state":"OPEN","headRefOid":"%s","reviewDecision":null,"mergeable":"%s","mergeStateStatus":"%s","reviewThreads":{"totalCount":0,"nodes":[]},"reviews":%s,"comments":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"totalCount":2,"nodes":%s}}}}]}}}}}\n' \
    "${2:-abc1234}" "${4:-MERGEABLE}" "${5:-CLEAN}" "$revs" "$runs" > "$GHDIR/$1"
}
# <short> <cwd|-> <state|-> <status|-> <kind|-> <age h> [<assistant m ago> <user-text m ago>]
BASE0="a1a10001 $WT/task-001-run working busy background 2 1 30
b2b20002 $WT/task-002-rev working idle background 3 20 60"
rows() { printf '%s\n' "$BASE" "$@" | grep . > "$TMP/spec"; mk "$TMP/spec"; }
base() { BASE="$BASE0"; prj 1; prj 2; rows; rec; }

echo "== IDLE: an in-progress task whose session is busy, nothing else moved =="
base
ok "a busy in-progress session, every field unchanged, is IDLE" "$(run)" "rc:0 IDLE: finger"
ok "…from ONE claude agents call" "$(grep -cx 'agents --json --all' "$CALLS")" 1
ok "…and one gh call per PR (two PRs)" "$(grep -c '^gh api graphql' "$CALLS")" 2
ok "…the record carries the session's state and status" "$(grep -cx "session $(u a1a10001) working busy" "$B/$AB_STATE_DIR")" 1
ok "…the in-progress task's PR, head and checks included" \
   "$(grep -c "^pr $URL/1 OPEN abc1234 NONE merge=MERGEABLE/CLEAN threads=0 reviews=0:-:- .*harness suite" "$B/$AB_STATE_DIR")" 1
ok "…and no moving age column in the record" "$(grep -c '^due ' "$B/$AB_STATE_DIR")" 0
ok "a second check is IDLE too" "$(run)" "rc:0 IDLE: finger"

echo "== GUARD: each moved fact is a DELTA, and restoring it is IDLE again =="
guard() { # <what> <mutate> <restore>
  base; eval "$2"; ok "$1 is a DELTA" "$(run)" "rc:1 DELTA: the f"
  eval "$3"; ok "…restored, it is IDLE" "$(run)" "rc:0 IDLE: finger"
}
guard "a new head SHA"                    "prj 1 def5678"                 "prj 1"
guard "a check run flipping red"          "prj 1 abc1234 FAILURE"         "prj 1"
base; prj 1 abc1234 FAILURE; rec
prj 1; ok "a check run flipping green is a DELTA" "$(run)" "rc:1 DELTA: the f"
guard "mergeable turning CONFLICTING (DIRTY)" "prj 1 abc1234 SUCCESS CONFLICTING DIRTY" "prj 1"
guard "a new review"                      "prj 2 abc1234 SUCCESS MERGEABLE CLEAN 1" "prj 2"
guard "a session status change (busy to idle)" 'BASE="${BASE/working busy/working idle}"; rows' 'BASE="$BASE0"; rows'

echo "== GUARD: a row entering the stop-ids due set =="
due() { # <what> <extra spec row> [<base substitution>]
  base; if [ -n "${3:-}" ]; then eval "$3"; rows; else rows "$2"; fi
  ok "$1 is a DELTA" "$(run)" "rc:1 DELTA: the f"
  ok "…the new due row is named by uuid and class" "$(bash "$TD" check --instance "$B" 2>&1 | grep -c "now: *due .* $4\$")" 1
}
due "busy past maxBgRoundMinutes (240)" "" 'BASE="${BASE/working busy background 2 1 30/working busy background 5 1 241}"' busy
due "idle past maxIdleMinutes (120)" "" 'BASE="${BASE/working idle background 3 20 60/working idle background 3 121 130}"' idle
due "a finished row holding a pid" "f1f10001 $B done idle background 5" "" finished
base; rows "dead0001 $B working idle background 1"
python3 -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); [x.pop("pid") for x in r if x["id"]=="dead0001"]; json.dump(r,open(p,"w"))' "$FIXTURE"
ok "a dead row (no pid, 1h) is a DELTA" "$(run)" "rc:1 DELTA: the f"
ok "…named as dead" "$(bash "$TD" check --instance "$B" 2>&1 | grep -c "now: *due dead0001-.* dead$")" 1
base; rows "f1f10001 $B done idle background 5"; rec; rows "f1f10001 $B done idle background 6"
ok "a recorded due row an hour older (only <age> moved) stays IDLE" "$(run)" "rc:0 IDLE: finger"

echo "== NO SESSION STAYS DELTA: step 4's recovery stays reachable, on every tick =="
nosess() { # <what> <mutate>
  base; eval "$2"; GIT -C "$B" add -A && GIT -C "$B" commit -q --allow-empty -m "$1"; rec
  ok "$1 is a DELTA against its own record" "$(run)" "rc:1 DELTA: proje"
  ok "…naming the task" "$(bash "$TD" check --instance "$B" 2>&1 | grep -c 'task-001-run.md is in-progress with no live session')" 1
  GIT -C "$B" checkout -q HEAD~1 -- projects; GIT -C "$B" commit -q --allow-empty -m undo
}
nosess "an in-progress task with no session:" 'task task-001-run in-progress - 1'
nosess "an in-progress task whose session is gone" 'BASE="$(grep -v a1a10001 <<<"$BASE")"; rows'
nosess "an in-progress task whose session is done" 'BASE="${BASE/working busy/done busy}"; rows'
nosess "an in-progress task whose session is stopped" 'BASE="${BASE/working busy/stopped busy}"; rows'
nosess "an in-progress task whose session's process died" \
  'rows; python3 -c "import json,sys; p=sys.argv[1]; r=json.load(open(p)); [x.pop(\"pid\") for x in r if x[\"id\"]==\"a1a10001\"]; json.dump(r,open(p,\"w\"))" "$FIXTURE"'

echo "== UNKNOWN MERGE STATE is fingerprinted as-is =="
base; prj 1 abc1234 SUCCESS UNKNOWN UNKNOWN; rec
ok "a recorded UNKNOWN merge state is IDLE" "$(run)" "rc:0 IDLE: finger"
prj 1; ok "…and settling to CLEAN is one DELTA" "$(run)" "rc:1 DELTA: the f"

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
