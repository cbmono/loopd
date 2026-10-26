#!/usr/bin/env bash
#
# board-autoserve.test.sh — the board server that starts with a Claude session and stops
# after the last one: the `boardServe` reader, the SessionStart start, the session records,
# the SessionEnd nudge, the server's own stop decision, and every path that starts nothing.
#
# A FAKE `claude` IS A LOOP THAT RUNS QUEUED JOBS AS ITS CHILDREN, through `sh -c` the way
# Claude Code runs a hook, so a hook's ancestry is real and one pid can end a session and
# start the next (`/clear`). Each loop and each server carries its own bound.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$REPO/plugin/hooks"
SESSION="$HOOKS/board-session.sh"
SERVE="$REPO/plugin/scripts/board-serve.sh"
for f in "$SESSION" "$SERVE" "$HOOKS/session-banner.sh"; do
  [ -f "$f" ] || { echo "board-autoserve.test: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "board-autoserve.test: needs python3" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "board-autoserve.test: needs curl" >&2; exit 2; }
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-autoserve.XXXXXX")" \
  || { echo "board-autoserve.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
case "$TMP" in /*) ;; *) echo "board-autoserve.test: mktemp returned a relative path" >&2; exit 2 ;; esac
TMP="$(cd "$TMP" && pwd -P)"
export BOARD_SERVE_GRACE=3 BOARD_SERVE_REAP=2

LOOPS=""
cleanup() {
  local p s
  for p in $LOOPS; do kill -9 "$p" 2>/dev/null; done
  [ -n "${WD:-}" ] && { pkill -P "$WD" 2>/dev/null; kill "$WD" 2>/dev/null; }
  for s in "$TMP"/*/"$AB_BOARD_DIR"/.serve; do
    [ -f "$s" ] && kill -TERM "$(sed -n 2p "$s")" 2>/dev/null
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

pass=0; fail=0; skip=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }

bundle() { # <name> <tracked config json> -> prints the path
  local b="$TMP/$1"
  mkdir -p "$b/projects" "$b/$AB_DIR"
  : > "$b/$AB_SCHEMA"
  printf '%s\n' "$2" > "$b/instance.config.json"
  printf '%s' "$b"
}

mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexec python3 -c "import time; print(int(time.time() * 1000))"\n' > "$TMP/ms"; chmod +x "$TMP/ms"
cat > "$TMP/bin/claude" <<'FAKE'
#!/usr/bin/env bash
q="$1"; end="$2"
echo $$ > "$q/pid"
while [ "$(date +%s)" -lt "$end" ]; do
  for j in "$q"/*.job; do
    [ -f "$j" ] || continue
    mv "$j" "$j.run"; sh -c "sh '$j.run'" > "$j.out" 2>&1; mv "$j.run" "$j.done"
  done
  sleep 0.1
done
FAKE
chmod +x "$TMP/bin/claude"

claude_up() { # <name> -> sets Q (its queue dir) and CPID (its pid); never call it in $( )
  local q="$TMP/q-$1"
  mkdir -p "$q"
  "$TMP/bin/claude" "$q" "$(( $(date +%s) + 150 ))" </dev/null >/dev/null 2>&1 &
  LOOPS="$LOOPS $!"; CPID=$!
  local i=0; while [ ! -f "$q/pid" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  Q="$q"
}
job() { # <queue> <timeout s> <script> — runs it inside that fake claude; prints seconds taken
  local q="$1" t="$2" n s
  n="$q/$(find "$q" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  printf '%s\n' "$3" > "$n.tmp"; s=$(date +%s); mv "$n.tmp" "$n.job"
  while [ ! -f "$n.job.done" ] && [ $(( $(date +%s) - s )) -le "$t" ]; do sleep 0.1; done
  if [ -f "$n.job.done" ]; then echo $(( $(date +%s) - s )); else echo timeout; fi
}
payload() { printf "printf '%%s' '{\"session_id\":\"%s\",\"hook_event_name\":\"x\"}'" "$1"; }
start_in() { # <queue> <bundle> <session id>
  job "$1" 8 "$(payload "$3") | CLAUDE_PROJECT_DIR='$2' bash '$HOOKS/session-banner.sh' --format json --session > '$1/banner.$3'"
}
end_in() { job "$1" 8 "$(payload "$3") | CLAUDE_PROJECT_DIR='$2' bash '$SESSION' end"; }
serve_pid() { sed -n 2p "$1/$AB_BOARD_DIR/.serve" 2>/dev/null; }
serve_port() { sed -n 1p "$1/$AB_BOARD_DIR/.serve" 2>/dev/null; }
up() { local p; p="$(serve_pid "$1")"; [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo up || echo down; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H "Host: ${3:-localhost:$1}" "http://127.0.0.1:$1$2"; }
wait_down() { # <bundle> <seconds> -> down | up
  local i=0; while [ "$(up "$1")" = up ] && [ $i -lt $(( $2 * 5 )) ]; do sleep 0.2; i=$((i+1)); done
  up "$1"
}
records() { find "$1/$AB_BOARD_DIR/sessions" -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' '; }

echo "== ONE READER: boardServe from the tracked file, newline-tolerant =="
R="$(bundle reader '{ "org": "x" }')"
on() { (cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$SESSION" enabled) && echo on || echo off; }
ok "absent reads on"                                  "$(on)" on
printf '{ "boardServe": true }\n' > "$R/instance.config.json";     ok "true reads on" "$(on)" on
printf '{ "boardServe":\n  false }\n' > "$R/instance.config.json"; ok "false reads off, across a newline" "$(on)" off
printf '{ "board": false, "boardServe": true }\n' > "$R/instance.config.json"; ok "board: false reads off" "$(on)" off
printf '{ "org": "x" }\n' > "$R/instance.config.json"
printf '{ "boardServe": false }\n' > "$R/instance.config.local.json"
ok "the local file is not read"                        "$(on)" on
ok "normalise-config calls a local boardServe MISPLACED" \
  "$(bash "$REPO/plugin/scripts/normalise-config.sh" "$R" | grep -c 'MISPLACED  boardServe')" 1
printf '{ "boardPort": 41999 }\n' > "$R/instance.config.local.json"
ok "...and leaves a local boardPort where it is" \
  "$(bash "$REPO/plugin/scripts/normalise-config.sh" "$R" | grep -c 'boardPort')" 0
rm -f "$R/instance.config.local.json"
ok "...and reports no MISSING boardServe: absent already reads on" \
  "$(bash "$REPO/plugin/scripts/normalise-config.sh" "$R" | grep -c 'boardServe')" 0
# shellcheck disable=SC2016 # `$boardServe` is a JSON key, not a variable
ok "the seed ships boardServe: true beside board"      \
  "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("boardServe"), "$boardServe" in d, d.get("board"))' "$REPO/plugin/seed/instance.config.json")" "True True True"
ok "hooks.json registers SessionEnd on board-session.sh end" \
  "$(python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["hooks"]; print([x["command"].split("/")[-1] for b in h.get("SessionEnd",[]) for x in b["hooks"]])' "$HOOKS/hooks.json")" "['board-session.sh\" end']"

echo "== NO SESSION, NO START, and the fixture opt-out =="
N="$(bundle nosession '{ "org": "x" }')"
claude_up nosession; QN=$Q
job "$QN" 8 "printf '{\"hook_event_name\":\"x\"}' | CLAUDE_PROJECT_DIR='$N' bash '$HOOKS/session-banner.sh' --format json --session >/dev/null" >/dev/null
ok "no session_id: no record"                          "$(records "$N")" 0
ok "...and nothing serves"                             "$(up "$N")" down
job "$QN" 8 "$(payload s0) | CLAUDE_PROJECT_DIR='$N' bash '$HOOKS/session-banner.sh' --format json >/dev/null" >/dev/null
ok "without --session (every fixture) a payload starts nothing" "$(up "$N"):$(records "$N")" down:0

echo "== AUTO START, NO HANG, ROUTE =="
A="$(bundle auto '{ "org": "x" }')"
mkdir -p "$A/projects/p"
printf -- '---\ntype: Project\ntitle: Demo\nkind: build\nstatus: active\n---\n' > "$A/projects/p/project.md"
touch "$A/$AB_SNAPSHOT"
( cd "$A" && SNAPSHOT_NOW=2026-09-06T00:00:00Z bash "$REPO/plugin/scripts/write-snapshot.sh" --quiet )
claude_up a; QA=$Q; PA=$CPID
T="$(job "$QA" 8 "'$TMP/ms' > '$QA/t0'; $(payload s-a) | CLAUDE_PROJECT_DIR='$A' bash '$HOOKS/session-banner.sh' --format json --session | { cat > '$QA/piped'; '$TMP/ms' > '$QA/t1'; }")"
MS=$(( $(cat "$QA/t1" 2>/dev/null || echo 99999999999999) - $(cat "$QA/t0") ))
ok "the hook's stdout pipe reaches EOF within 5 s"     "$([ "$T" != timeout ] && [ "$MS" -lt 5000 ] && echo yes || echo "no (${MS} ms)")" yes
ok "...while the server keeps running"                 "$(up "$A")" up
PORT="$(serve_port "$A")"
ok "the first banner prints the served URL"            "$(grep -c "http://localhost:$PORT" "$QA/piped")" 1
ok "...and the starting SessionStart returns in under 3 s"    "$([ "$MS" -lt 3000 ] && echo yes || echo "no (${MS} ms)")" yes
start_in "$QA" "$A" s-a2 >/dev/null
i=0; while [ "$(code "$PORT" /loopd/board)" != 200 ] && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done
ok "GET /loopd/board answers 200 within 10 s"         "$(code "$PORT" /loopd/board)" 200
ok ".serve says the server is auto-started"            "$(sed -n 4p "$A/$AB_BOARD_DIR/.serve")" auto
ok "the record names the fake claude, not the hook's shell" "$(sed -n 1p "$A/$AB_BOARD_DIR/sessions/s-a")" "$PA"
ok "...with that process's start time"                 "$(sed -n 2p "$A/$AB_BOARD_DIR/sessions/s-a")" "$(ps -o lstart= -p "$PA" | tr -s ' ' | sed 's/^ //; s/ $//')"
ok "the log sits under the board dir"                  "$(grep -c 'serving http://localhost' "$A/$AB_BOARD_DIR/.serve.log")" 1
i=0; while [ ! -f "$A/$AB_BOARD_DIR/board.html" ] && [ $i -lt 100 ]; do sleep 0.2; i=$((i+1)); done
same() { [ "$(curl -s --max-time 3 -H "Host: $2" "http://127.0.0.1:$PORT/loopd/board")" = "$(curl -s --max-time 3 -H "Host: $2" "http://127.0.0.1:$PORT/board.html")" ] && echo same || echo differs; }
ok "/loopd/board serves the page /board.html serves"   "$(same "$PORT" "localhost:$PORT")" same
ok "...and carries the queue token only for an allowed Host" \
  "$(curl -s --max-time 3 -H "Host: localhost:$PORT" "http://127.0.0.1:$PORT/loopd/board" | grep -o 'name="loopd-queue" content' | wc -l | tr -d ' ')|$(curl -s --max-time 3 -H 'Host: evil.example.com' "http://127.0.0.1:$PORT/loopd/board" | grep -o 'name="loopd-queue" content' | wc -l | tr -d ' ')" "1|0"
ok "session records are never served"                  "$(code "$PORT" /sessions/s-a)|$(code "$PORT" /.serve)" "404|404"

echo "== IDEMPOTENT and SESSION RECORD =="
SP="$(serve_pid "$A")"
claude_up b; QB=$Q; PB=$CPID
start_in "$QB" "$A" s-b >/dev/null
ok "a second session starts no second server"          "$(serve_pid "$A")" "$SP"
ok "...and the log was not truncated by a second start" "$(grep -c 'serving' "$A/$AB_BOARD_DIR/.serve.log")" 1
start_in "$QB" "$A" s-b >/dev/null
ok "a resume/compact start overwrites the same record" "$(records "$A"):$(sed -n 1p "$A/$AB_BOARD_DIR/sessions/s-b")" "3:$PB"

echo "== LIFECYCLE: the first end leaves it up, /clear does not bounce it, the last stops it =="
end_in "$QA" "$A" s-a >/dev/null; end_in "$QA" "$A" s-a2 >/dev/null
kill -9 "$PA" 2>/dev/null
sleep 4
ok "the first session's end leaves the server up"      "$(serve_pid "$A")" "$SP"
end_in "$QB" "$A" s-b >/dev/null
start_in "$QB" "$A" s-b2 >/dev/null
sleep 4
ok "/clear (end, then a new id) does not bounce it"    "$(serve_pid "$A")" "$SP"
end_in "$QB" "$A" s-b2 >/dev/null
kill -9 "$PB" 2>/dev/null
ok "the last end stops it within 60 s"                 "$(wait_down "$A" 60)" down
ok "...the port is free"                               "$(code "$PORT" /__bundle)" 000
ok "...and .serve is gone"                             "$([ -f "$A/$AB_BOARD_DIR/.serve" ] && echo present || echo gone)" gone

echo "== a kill -9 session is reaped; a reused pid is not alive =="
K="$(bundle killed '{ "org": "x" }')"
claude_up k; QK=$Q; PK=$CPID
start_in "$QK" "$K" s-k >/dev/null
ok "the server is up"                                  "$(up "$K")" up
kill -9 "$PK" 2>/dev/null
ok "a session killed with -9 (no SessionEnd) is reaped" "$(wait_down "$K" 30)" down
mkdir -p "$K/$AB_BOARD_DIR/sessions"
printf '%s\nThu Jan  1 00:00:00 1970\n' "$$" > "$K/$AB_BOARD_DIR/sessions/reused"
ok "a live pid with a mismatched start time is not alive" \
  "$(CLAUDE_PROJECT_DIR="$K" bash "$SESSION" alive && echo alive || echo dead)" dead
ok "...and its record is pruned"                       "$(records "$K")" 0
printf '%s\n%s\n' "$$" "$(ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ //; s/ $//')" > "$K/$AB_BOARD_DIR/sessions/live"
ok "a live pid with its own start time is alive"       "$(CLAUDE_PROJECT_DIR="$K" bash "$SESSION" alive && echo alive || echo dead)" alive
rm -rf "$K/$AB_BOARD_DIR/sessions"
ok "a missing records directory counts as none alive"  "$(CLAUDE_PROJECT_DIR="$K" bash "$SESSION" alive && echo alive || echo dead)" dead

echo "== OWNERSHIP: a hand-started server survives every session =="
Hb="$(bundle hand '{ "org": "x" }')"
( cd "$Hb" && exec bash "$SERVE" ) >"$TMP/hand.log" 2>&1 &
HP=$!; LOOPS="$LOOPS $HP"
( sleep 120; kill -TERM "$HP" 2>/dev/null ) >/dev/null 2>&1 &
WD=$!
i=0; while [ "$(up "$Hb")" != up ] && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done
ok ".serve says the server was started by hand"        "$(sed -n 4p "$Hb/$AB_BOARD_DIR/.serve")" hand
claude_up h; QH=$Q; PH=$CPID
start_in "$QH" "$Hb" s-h >/dev/null
end_in "$QH" "$Hb" s-h >/dev/null
kill -9 "$PH" 2>/dev/null
sleep 4
ok "...and survives the session's end and death"       "$(serve_pid "$Hb")" "$HP"
kill -TERM "$HP" 2>/dev/null
ok "...and still stops on SIGTERM, removing .serve"    "$(wait_down "$Hb" 10)" down

echo "== CONCURRENT starts leave exactly one server =="
C="$(bundle concurrent '{ "org": "x" }')"
claude_up c1; QC1=$Q; claude_up c2; QC2=$Q
start_in "$QC1" "$C" s-c1 >/dev/null & w1=$!
start_in "$QC2" "$C" s-c2 >/dev/null & w2=$!
wait "$w1" "$w2"
ok "one server answers"                                "$(up "$C")" up
ok "...and exactly one ever started"                   "$(grep -c 'serving' "$C/$AB_BOARD_DIR/.serve.log")" 1
if command -v lsof >/dev/null 2>&1; then
  ok "...and one process listens on the port"          "$(lsof -nP -iTCP:"$(serve_port "$C")" -sTCP:LISTEN -t 2>/dev/null | sort -u | wc -l | tr -d ' ')" 1
else skipped "lsof absent: the listener count"; fi
kill -TERM "$(serve_pid "$C")" 2>/dev/null

echo "== FALLBACK: each of these starts nothing and exits 0 =="
nothing() { # <bundle> <queue> <session id> [env…]
  local q="$2" b="$1" s="$3"; shift 3
  job "$q" 8 "$(payload "$s") | env $* CLAUDE_PROJECT_DIR='$b' bash '$SESSION' start; echo \$? > '$q/rc.$s'" >/dev/null
  echo "$(up "$b"):$(cat "$q/rc.$s" 2>/dev/null)"
}
claude_up f; QF=$Q
ok "boardServe: false"   "$(nothing "$(bundle off1 '{ "boardServe": false }')" "$QF" f1)" down:0
ok "board: false"        "$(nothing "$(bundle off2 '{ "board": false }')" "$QF" f2)" down:0
mkdir -p "$TMP/nopy"
for t in bash sh ps sed tr grep mkdir mv rm cat sleep dirname date env; do
  p="$(command -v "$t")" && ln -sf "$p" "$TMP/nopy/$t"
done
ok "python3 missing"     "$(nothing "$(bundle off3 '{ "org": "x" }')" "$QF" f3 "PATH='$TMP/nopy'")" down:0
O="$(bundle held '{ "org": "x" }')"
OP="$(cd "$O" && bash "$SERVE" --print-port)"
python3 -c 'import socket,sys,time; s=socket.socket(); s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(1); time.sleep(max(0,int(sys.argv[2])-time.time()))' "$OP" "$(( $(date +%s) + 20 ))" &
HELD=$!; LOOPS="$LOOPS $HELD"; sleep 0.5
ok "a port held by something else" "$(nothing "$O" "$QF" f4)" down:0
kill "$HELD" 2>/dev/null

echo
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
