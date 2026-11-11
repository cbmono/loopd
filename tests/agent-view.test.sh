#!/usr/bin/env bash
#
# agent-view.test.sh — `agent-sessions.sh view` and the status line's `agents` segment:
# the in-session view of the detached role agents (dispatch-reporting-defects/task-014).
#
# THE PROPERTIES:
#   * IT READS `claude agents --json`, NEVER THE BARE FORM. The stub refuses the bare form
#     the way the real CLI does without a TTY, so a view that dropped `--json` goes unknown.
#   * A FAILING READ IS UNKNOWN, NEVER ZERO — a failing `claude`, malformed JSON, no
#     `claude` at all: exit 2 and no count from the reader, `? working` on the status line.
#   * A SESSION IS ATTRIBUTED BY A JOIN ON THE RECORDED `worktree:`, and a cwd in this
#     bundle that matches no task is rendered `unattributed`, never dropped or guessed.
#   * PROCESS, NOT REGISTRY. A `blocked` row with no live pid is `none` — the registry
#     claims it, nothing runs it — and is counted apart from the ones that do run.
#   * ONE BUCKET PER ROW: no live pid ⇒ dead, else `status: busy` ⇒ working, `idle` ⇒ idle,
#     else the `state` fallback (`working` ⇒ working). `working` names each busy one's task.
# Every `claude` here is a PATH stub; no real session is read. Exit 0 pass, 1 fail, 2 setup.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SESS="$REPO/plugin/scripts/agent-sessions.sh"
SL="$REPO/plugin/scripts/status-line.sh"
for f in "$SESS" "$SL"; do [ -f "$f" ] || { echo "agent-view.test: $f not found" >&2; exit 2; }; done
command -v python3 >/dev/null 2>&1 || { echo "agent-view.test: python3 required" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-view.XXXXXX")" || { echo "agent-view.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# A dead pid: a child that has exited and been reaped.
( exit 0 ) & DEAD=$!; wait "$DEAD"
LIVE=$$

B="$TMP/bundle"; WT="$TMP/wt"; OTHER="$TMP/other-bundle"
mkdir -p "$B/projects/p/tasks" "$WT/t1" "$WT/t2" "$WT/t3" "$WT/orphan" "$OTHER"
printf '{ "worktreeRoot": "%s" }\n' "$WT" > "$B/instance.config.json"
task() { # <file stem> <status> <worktree>
  printf -- '---\ntype: Task\nstatus: %s\nworktree: %s\n---\n\nworktree: /not/frontmatter\n' "$2" "$3" \
    > "$B/projects/p/tasks/$1.md"
}
task task-001-working  in-progress "$WT/t1"
task task-002-ghost    in-progress "$WT/t2"
task task-003-merged   done        "$WT/t3"

# The stub answers ONLY `agents --json`; the bare form fails the way it does with no TTY.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf 'x\n' >> "$CALLS"
[ "${1:-}" = agents ] || exit 1
case " $* " in *" --json "*) ;; *) echo "claude agents requires an interactive terminal" >&2; exit 1 ;; esac
[ -n "${FAIL:-}" ] && exit 1
cat "$FIXTURE"
STUB
chmod +x "$TMP/bin/claude"
export CALLS="$TMP/calls"; : > "$CALLS"

FIX="$TMP/rows.json"
cat > "$FIX" <<JSON
[ {"id":"aaaa0001","sessionId":"aaaa0001-x","kind":"background","cwd":"$WT/t1","pid":$LIVE,"state":"working","startedAt":1},
  {"id":"bbbb0002","sessionId":"bbbb0002-x","kind":"background","cwd":"$WT/t2","state":"blocked"},
  {"id":"cccc0003","sessionId":"cccc0003-x","kind":"background","cwd":"$WT/t3","pid":$DEAD,"state":"blocked"},
  {"id":"dddd0004","sessionId":"dddd0004-x","kind":"background","cwd":"$WT/t3","state":"stopped"},
  {"id":"eeee0005","sessionId":"eeee0005-x","kind":"background","cwd":"$WT/orphan","state":"blocked"},
  {"id":"ffff0006","sessionId":"ffff0006-x","kind":"background","cwd":"$OTHER","state":"blocked"},
  {"sessionId":"9999-x","kind":"interactive","cwd":"$B","pid":$LIVE,"status":"busy"},
  {"id":"abab0007","sessionId":"abab0007-x","kind":"background","cwd":"$B","pid":$LIVE,"status":"idle","state":"done"} ]
JSON
export FIXTURE="$FIX"
P="$TMP/bin:$PATH"
view() { PATH="$P" bash "$SESS" view "$B" "$@" 2>/dev/null; }
row() { view | awk -v id="$1" '$0 ~ id'; }

echo "== 1. it reads \`claude agents --json\`, never the bare form =="
ok "the stub refuses the bare form, and the view still answers" "$(view >/dev/null; echo $?)" 0
ok "every \`claude agents\` call in the reader carries --json" \
   "$(grep -n 'claude agents' "$SESS" | grep -v '^[0-9]*:[[:space:]]*#' | grep -vc -- '--json' | tr -d ' ')" 0
ok "…and the status line calls no \`claude\` of its own" \
   "$(grep -v '^[[:space:]]*#' "$SL" | grep -c 'claude agents' | tr -d ' ')" 0

echo "== 2. each session is attributed by the recorded worktree: =="
ok "cwd = a task's worktree ⇒ that task" "$(row aaaa0001 | awk '{print $1}')" p/task-001
ok "…for a merged task's lingering session too" "$(row cccc0003 | awk '{print $1}')" p/task-003
ok "a cwd in this bundle matching no task ⇒ unattributed, cwd shown" \
   "$(row eeee0005 | awk '{print $1, $NF}')" "unattributed $WT/orphan"
ok "the bundle root itself is this bundle's, unattributed" "$(row abab0007 | awk '{print $1}')" unattributed
ok "another bundle's session is not listed here" "$(row ffff0006 | wc -l | tr -d ' ')" 0
ok "an interactive session is not a detached agent" "$(view | grep -c 9999 | tr -d ' ')" 0
ok "a body \`worktree:\` is not frontmatter" "$(view | grep -c not/frontmatter | tr -d ' ')" 0

echo "== 3. the process, not the registry's word for it =="
ok "a live pid ⇒ running, with the pid"     "$(row aaaa0001 | awk '{print $2, $3, $4}')" "working pid $LIVE"
ok "blocked, no pid ⇒ none"                 "$(row bbbb0002 | awk '{print $2, $3}')" "blocked none"
ok "blocked, dead pid ⇒ none"               "$(row cccc0003 | awk '{print $2, $3}')" "blocked none"
ok "a terminal state with no process is not listed" "$(row dddd0004 | wc -l | tr -d ' ')" 0
ok "…a terminal state WITH a live process is" "$(row abab0007 | awk '{print $2, $3}')" "done pid"
ok "running rows sort above the ones with no process" \
   "$(view | sed -n '2p' | grep -c "pid $LIVE" | tr -d ' ')" 1
ok "the tally" "$(view | tail -1)" "1 working · 1 idle · 3 dead · 1 ended, not listed"
ok "--summary is the same three counts" "$(view --summary)" "1 1 3"

cat > "$TMP/hostile.json" <<JSON
[ {"id":"\u001b]0;x\u0007ab","kind":"background","cwd":"$WT/\u001b[2Jesc","state":"blocked\u001b[31m"},
  {"id":"root0001","kind":"background","cwd":"$WT/t1","pid":1,"state":"working"} ]
JSON
H="$(FIXTURE="$TMP/hostile.json" view)"
ok "no control character from the JSON reaches the terminal" \
   "$(printf '%s' "$H" | tr -d '\n' | LC_ALL=C tr -cd '\000-\037\177' | wc -c | tr -d ' ')" 0
if [ "$(id -u)" -ne 0 ]; then
  ok "a pid we may not signal still EXISTS — never rendered as none" \
     "$(printf '%s\n' "$H" | awk '/root0001/ {print $3, $4}')" "pid 1"
fi
printf '[{"id":"zw000001","kind":"background","cwd":"%s/t2","state":"done\\u200b"}]' "$WT" > "$TMP/zw.json"
ok "a state that only LOOKS terminal is classified raw, as in-flight does" \
   "$(FIXTURE="$TMP/zw.json" view --summary)" "0 0 1"

echo "== 4. a failing read is UNKNOWN, never zero =="
OUT="$(FAIL=1 view)"; RC=$?
ok "claude fails ⇒ exit 2"     "$RC" 2
ok "…and no table, no count"   "${OUT:-<empty>}" "<empty>"
OUT="$(FAIL=1 view --summary)"; RC=$?
ok "--summary: exit 2 and nothing on stdout" "$RC:${OUT:-<empty>}" "2:<empty>"
printf 'not json' > "$TMP/bad.json"
OUT="$(FIXTURE="$TMP/bad.json" view --summary)"; RC=$?
ok "malformed JSON ⇒ exit 2, no count" "$RC:${OUT:-<empty>}" "2:<empty>"
printf '{"rows":[]}' > "$TMP/obj.json"
ok "a JSON object, not a list ⇒ exit 2" "$(FIXTURE="$TMP/obj.json" view --summary >/dev/null; echo $?)" 2
OUT="$(PATH="/usr/bin:/bin" bash "$SESS" view "$B" --summary 2>/dev/null)"; RC=$?
ok "no claude on PATH ⇒ exit 2, no count" "$RC:${OUT:-<empty>}" "2:<empty>"
printf '[]' > "$TMP/empty.json"
ok "…while an EMPTY list is a real zero" "$(FIXTURE="$TMP/empty.json" view --summary)" "0 0 0"

echo "== 4b. precedence: one bucket per row, dead before status before state =="
cat > "$TMP/prec.json" <<JSON
[ {"id":"b0000001","sessionId":"b0000001-x","kind":"background","cwd":"$WT/t1","pid":$LIVE,"status":"busy","state":"done"},
  {"id":"b0000002","sessionId":"b0000002-x","kind":"background","cwd":"$WT/t1","pid":$LIVE,"status":"idle","state":"working"},
  {"id":"b0000003","sessionId":"b0000003-x","kind":"background","cwd":"$WT/t1","status":"busy","state":"working"},
  {"id":"b0000004","sessionId":"b0000004-x","kind":"background","cwd":"$WT/t1","pid":$LIVE,"state":"working"},
  {"id":"b0000005","sessionId":"b0000005-x","kind":"background","cwd":"$WT/t1","pid":$LIVE,"state":"blocked"},
  {"id":"b0000006","sessionId":"b0000006-x","kind":"background","cwd":"$WT/t1","status":"busy","state":"done"},
  {"id":"b0000007","sessionId":"b0000007-x","cwd":"$WT/t1","pid":$LIVE,"status":"busy"},
  {"id":"b0000008","sessionId":"b0000008-x","kind":"background","cwd":"$WT/t1","pid":$LIVE,"status":"waiting","state":"working"} ]
JSON
one() { printf '[%s]' "$(grep "\"$1\"" "$TMP/prec.json" | sed 's/^\[ *//; s/,$//; s/ *\]$//')" > "$TMP/one.json"
        FIXTURE="$TMP/one.json" view --summary; }
ok "live pid, status busy (state done) ⇒ working"    "$(one b0000001)" "1 0 0"
ok "live pid, status idle (state working) ⇒ idle"    "$(one b0000002)" "0 1 0"
ok "status busy, NO pid ⇒ dead"                      "$(one b0000003)" "0 0 1"
ok "no status, state working ⇒ working (fallback)"   "$(one b0000004)" "1 0 0"
ok "no status, state blocked ⇒ idle (fallback)"      "$(one b0000005)" "0 1 0"
ok "busy but terminal with no pid stays dropped"     "$(one b0000006)" "0 0 0"
ok "a row with no kind is counted, as today"         "$(one b0000007)" "1 0 0"
ok "an unknown status is not absent: no fallback ⇒ idle" "$(one b0000008)" "0 1 0"
ok "all eight: each row in exactly one bucket"       "$(FIXTURE="$TMP/prec.json" view --summary)" "3 3 1"
cat > "$B/projects/p/tasks/task-004-open.md" <<EOF
---
type: Task
status: in-review
session: b0000004
---
EOF
cat > "$B/projects/p/tasks/task-005-closed.md" <<EOF
---
type: Task
status: done
session: b0000001-x
---
EOF
cat > "$B/projects/p/tasks/task-006-full.md" <<EOF
---
type: Task
status: in-progress
session: b0000007-x
---
EOF
W="$(FIXTURE="$TMP/prec.json" PATH="$P" bash "$SESS" working "$B" 2>/dev/null | sort | tr '\n' ';')"
ok "working: short id ⇒ its open task, full uuid too, done task ⇒ unrecorded" "$W" \
   "b0000001 unrecorded;b0000004 task-004-open;b0000007 task-006-full;"
OUT="$(FAIL=1 PATH="$P" bash "$SESS" working "$B" 2>/dev/null)"; RC=$?
ok "working: a failing read ⇒ exit 2, no line" "$RC:${OUT:-<empty>}" "2:<empty>"
rm -f "$B/projects/p/tasks/task-00[456]-"*.md

CT="$(FIXTURE="$FIX" PATH="$P" bash "$SESS" view "$B" --counts 2>/dev/null)"
ok "--counts: first line is --summary's" "$(head -1 <<<"$CT")" \
   "$(FIXTURE="$FIX" PATH="$P" bash "$SESS" view "$B" --summary 2>/dev/null)"
ok "…then <word> TAB <json task path>, relative to the bundle" "$(sed 1d <<<"$CT" | cut -f2 | sort | tr '\n' ';')" \
   '"projects/p/tasks/task-001-working.md";"projects/p/tasks/task-002-ghost.md";"projects/p/tasks/task-003-merged.md";'
ok "…each word working, idle or dead" "$(sed 1d <<<"$CT" | cut -f1 | grep -cvE '^(working|idle|dead)$' | tr -d ' ')" 0

echo "== 5. the status line's agents segment =="
sl() { rm -rf "$XDG_CACHE_HOME"; PATH="$P" bash "$SL" --instance "$B" --color "${C:-never}" </dev/null 2>/dev/null; }
seg() { grep -oE '[0-9?]+ working · [0-9?]+ idle · [0-9?]+ dead'; }
ok "working, idle and dead, side by side" "$(sl | seg)" "1 working · 1 idle · 3 dead"
ok "a failing read renders ?, never 0"    "$(FAIL=1 sl | seg)" "? working · ? idle · ? dead"
ok "…and so does malformed JSON"          "$(FIXTURE="$TMP/bad.json" sl | seg)" "? working · ? idle · ? dead"
ok "an empty list is three zeros"         "$(FIXTURE="$TMP/empty.json" sl | seg)" "0 working · 0 idle · 0 dead"
ok "the line is still one line"           "$(sl | wc -l | tr -d ' ')" 1
sgr() { head -n1 <<<"$(printf '%s' "$1" | tr '\033' '\n' | grep -F "$2" | sed -n 's/^\[\([0-9;]*\)m.*/\1/p')"; }
ok "unknown is a warning, so pink"        "$(sgr "$(C=always FAIL=1 sl)" '? working')" 95
ok "a session with no process is pink"    "$(sgr "$(C=always sl)" '3 dead')" 95

echo "== 6. the read is cached and shared, so N sessions do not each pay for it =="
rm -rf "$XDG_CACHE_HOME"; : > "$CALLS"
for _ in 1 2 3; do PATH="$P" bash "$SL" --instance "$B" --color never </dev/null >/dev/null 2>&1; done
ok "three renders inside the TTL ⇒ one claude call" "$(wc -l < "$CALLS" | tr -d ' ')" 1
CF="$(head -1 <<<"$(ls "$XDG_CACHE_HOME"/loopd/counts-* 2>/dev/null)")"
ok "the cache's first line is tagged v3" "$(awk 'NR == 1 {print $2, NF}' "$CF")" "v3 5"
printf '1 v3 9 9 9\n' > "$CF"; : > "$CALLS"
ok "a stale cache is re-read, not shown" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "1 working · 1 idle · 3 dead"
printf '%s 2 3\n' "$(date +%s)" > "$CF"
ok "a fresh two-count line from an older version is unknown" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "? working · ? idle · ? dead"
printf '%s 2 3 4\n' "$(date +%s)" > "$CF"
ok "…and three untagged counts are not read as v3" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "? working · ? idle · ? dead"
printf '%s garbage\n' "$(date +%s)" > "$CF"
ok "a fresh but malformed cache is unknown, not a number" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "? working · ? idle · ? dead"
printf '%s v2 1 2 3\n' "$(date +%s)" > "$CF"
ok "a fresh v2 line (no per-task words) is unknown" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "? working · ? idle · ? dead"
printf '%s v3 1 2 3 4\n' "$(date +%s)" > "$CF"
ok "a v3 line with four counts is unknown" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "? working · ? idle · ? dead"
ok "an unwritable cache still renders" \
   "$(XDG_CACHE_HOME=/dev/null/x PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" \
   "1 working · 1 idle · 3 dead"

echo "== 7. the mutants: the assertions above discriminate =="
# A copy of the whole scripts dir, so a mutant still finds its siblings.
cp -R "$REPO/plugin/scripts" "$TMP/scripts"; M="$TMP/scripts/agent-sessions.sh"
sed 's/claude agents --json --all/claude agents --all/' "$SESS" > "$M"
ok "dropping --json makes the read unknown" "$(PATH="$P" bash "$M" view "$B" --summary >/dev/null 2>&1; echo $?)" 2
cp "$SESS" "$M"; C="$TMP/scripts/agent-sessions-classify.py"; CSRC="$REPO/plugin/scripts/agent-sessions-classify.py"
sed 's/^    if alive(pid):$/    if pid or alive(pid):/' "$CSRC" > "$C"
ok "keying on pid PRESENCE counts the dead pid as running" \
   "$(PATH="$P" bash "$M" view "$B" --summary 2>/dev/null)" "1 2 2"
mone() { one "$1" >/dev/null; PATH="$P" FIXTURE="$TMP/one.json" bash "$M" view "$B" --summary 2>/dev/null; }
sed 's/if st == "busy" or (st is None and state == "working"):/if state == "working":/' "$CSRC" > "$C"
ok "reading state before status makes the idle row working" "$(mone b0000002)" "1 0 0"
sed 's/(st is None and state == "working")/(st != "idle" and state == "working")/' "$CSRC" > "$C"
ok "falling back on any non-idle status makes the unknown one working" "$(mone b0000008)" "1 0 0"

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
