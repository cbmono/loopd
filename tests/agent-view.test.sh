#!/usr/bin/env bash
#
# agent-view.test.sh — `agent-sessions.sh view` and the status line's `agents` segment:
# the in-session view of the detached role agents (dispatch-reporting-defects/task-014).
#
# THE PROPERTIES:
#   * IT READS `claude agents --json`, NEVER THE BARE FORM. The stub refuses the bare form
#     the way the real CLI does without a TTY, so a view that dropped `--json` goes unknown.
#   * A FAILING READ IS UNKNOWN, NEVER ZERO — a failing `claude`, malformed JSON, no
#     `claude` at all: exit 2 and no count from the reader, `agents ?` on the status line.
#   * A SESSION IS ATTRIBUTED BY A JOIN ON THE RECORDED `worktree:`, and a cwd in this
#     bundle that matches no task is rendered `unattributed`, never dropped or guessed.
#   * PROCESS, NOT REGISTRY. A `blocked` row with no live pid is `none` — the registry
#     claims it, nothing runs it — and is counted apart from the ones that do run.
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
ok "the tally" "$(view | tail -1)" "2 running · 3 no process · 1 ended, not listed"
ok "--summary is the same two counts" "$(view --summary)" "2 3"

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
   "$(FIXTURE="$TMP/zw.json" view --summary)" "0 1"

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
ok "…while an EMPTY list is a real zero" "$(FIXTURE="$TMP/empty.json" view --summary)" "0 0"

echo "== 5. the status line's agents segment =="
sl() { rm -rf "$XDG_CACHE_HOME"; PATH="$P" bash "$SL" --instance "$B" --color "${C:-never}" </dev/null 2>/dev/null; }
seg() { awk -F ' · ' '{print $3}'; }
ok "running and no-process, side by side" "$(sl | seg)" "agents 2 running, 3 no process"
ok "a failing read renders ?, never 0"    "$(FAIL=1 sl | seg)" "agents ?"
ok "…and so does malformed JSON"          "$(FIXTURE="$TMP/bad.json" sl | seg)" "agents ?"
ok "an empty list is 0 running"           "$(FIXTURE="$TMP/empty.json" sl | seg)" "agents 0 running"
ok "the line is still one line"           "$(sl | wc -l | tr -d ' ')" 1
sgr() { printf '%s' "$1" | tr '\033' '\n' | grep -F "$2" | sed -n 's/^\[\([0-9;]*\)m.*/\1/p' | head -n1; }
ok "unknown is a warning, so pink"        "$(sgr "$(C=always FAIL=1 sl)" 'agents ?')" 95
ok "a session with no process is pink"    "$(sgr "$(C=always sl)" 'agents 2')" 95

echo "== 6. the read is cached and shared, so N sessions do not each pay for it =="
rm -rf "$XDG_CACHE_HOME"; : > "$CALLS"
for _ in 1 2 3; do PATH="$P" bash "$SL" --instance "$B" --color never </dev/null >/dev/null 2>&1; done
ok "three renders inside the TTL ⇒ one claude call" "$(wc -l < "$CALLS" | tr -d ' ')" 1
CF="$(ls "$XDG_CACHE_HOME"/loopd/agents-* 2>/dev/null | head -1)"
printf '1 9 9\n' > "$CF"; : > "$CALLS"
ok "a stale cache is re-read, not shown" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "agents 2 running, 3 no process"
printf '%s garbage\n' "$(date +%s)" > "$CF"
ok "a fresh but malformed cache is unknown, not a number" \
   "$(PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" "agents ?"
ok "an unwritable cache still renders" \
   "$(XDG_CACHE_HOME=/dev/null/x PATH="$P" bash "$SL" --instance "$B" --color never </dev/null 2>/dev/null | seg)" \
   "agents 2 running, 3 no process"

echo "== 7. the mutants: the assertions above discriminate =="
# A copy of the whole scripts dir, so a mutant still finds its siblings.
cp -R "$REPO/plugin/scripts" "$TMP/scripts"; M="$TMP/scripts/agent-sessions.sh"
sed 's/claude agents --json --all/claude agents --all/' "$SESS" > "$M"
ok "dropping --json makes the read unknown" "$(PATH="$P" bash "$M" view "$B" --summary >/dev/null 2>&1; echo $?)" 2
sed 's/^    if alive(pid):$/    if pid or alive(pid):/' "$SESS" > "$M"
ok "keying on pid PRESENCE counts the dead pid as running" \
   "$(PATH="$P" bash "$M" view "$B" --summary 2>/dev/null)" "3 2"

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
