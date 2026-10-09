#!/usr/bin/env bash
#
# resume-full-id.test.sh — every `claude --resume` in plugin/ takes the FULL session id
# from `agent-sessions.sh resolve`, the resolver refuses to guess, and `stalled` tells a
# resume parked on the picker from one that worked. Offline: `claude` is a stub.
# Reasoning: docs/pm-design.md#step-4.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SESS="$REPO/plugin/scripts/agent-sessions.sh"
S4="$REPO/plugin/tick-steps/step-4-advance.md"
for f in "$SESS" "$S4"; do
  [ -f "$f" ] || { echo "resume-full-id.test: $f not found" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "resume-full-id.test: python3 required" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/resume-full-id.XXXXXX")" || {
  echo "resume-full-id.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

echo "== static: every claude --resume in plugin/ is given the resolved full id =="
# Prints each offending `file:line`: a resume whose id is anything but what `resolve`
# printed, or one in a file that never calls `resolve`.
ARG='--resume <the UUID resolve printed>'
RESOLVE='${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh resolve <'
offenders() { # <dir>
  grep -rnE 'claude[^`]*[[:space:]](--resume|-r)([[:space:]=]|$)' "$1" 2>/dev/null \
    | while IFS= read -r hit; do
        f="${hit%%:*}"; rest="${hit#*:}"; n="${rest%%:*}"; line="${rest#*:}"
        case "$line" in
          *"$ARG"*) grep -qF -- "$RESOLVE" "$f" && continue ;;
        esac
        printf '%s:%s\n' "$f" "$n"
      done
}
ok "no resume takes a recorded or short id"   "$(offenders "$REPO/plugin" | wc -l | tr -d ' ')" 0
ok "…and the check is not vacuous: step 4 has one" "$(grep -cF -- "$ARG" "$S4")" 1
mkdir -p "$TMP/mut"
sed "s|$ARG|--resume <the recorded session>|" "$S4" > "$TMP/mut/s4.md"
ok "a resume of the recorded session fails it" "$(offenders "$TMP/mut" | wc -l | tr -d ' ')" 1
mkdir -p "$TMP/mut2"; grep -vF -- "$RESOLVE" "$S4" > "$TMP/mut2/s4.md"
ok "…and so does a file that never calls resolve" "$(offenders "$TMP/mut2" | wc -l | tr -d ' ')" 1
printf '   `cd <wt> && claude --bg -r abcd1234 msg`\n' > "$TMP/mut/r.md"
ok "…and so does the -r spelling"              "$(offenders "$TMP/mut" | wc -l | tr -d ' ')" 2

# A stub `claude`: `agents` prints $STUB_JSON, anything else exits 1.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "agents" ] || exit 1
cat "$STUB_JSON"
STUB
chmod +x "$TMP/bin/claude"
P="$TMP/bin:$PATH"
U1=aaaa1111-0000-4000-8000-000000000001
U2=bbbb2222-0000-4000-8000-000000000002
U3=bbbb2222-0000-4000-8000-000000000003
U4=cccc3333-0000-4000-8000-000000000004
STARTED=1791557649233   # 2026-10-09T14:54:09.233Z
cat > "$TMP/agents.json" <<JSON
[ {"id":"aaaa1111","sessionId":"$U1","kind":"background","state":"blocked","startedAt":$STARTED},
  {"id":"bbbb2222","sessionId":"$U2","kind":"background","state":"done","startedAt":$STARTED},
  {"id":"bbbb2222","sessionId":"$U3","kind":"background","state":"done","startedAt":$STARTED},
  {"id":"cccc3333","sessionId":"$U4","kind":"background","state":"working","startedAt":$STARTED} ]
JSON
export STUB_JSON="$TMP/agents.json"
run() { PATH="$P" bash "$SESS" "$@" 2>/dev/null; echo "rc=$?"; }

echo "== resolve: one match is the full UUID; none or two is exit 1, never a guess =="
ok "1 match, short id -> the full UUID"        "$(run resolve aaaa1111 | tr '\n' ' ')" "$U1 rc=0 "
ok "1 match, full id -> itself"                "$(run resolve "$U4" | tr '\n' ' ')" "$U4 rc=0 "
ok "0 matches -> exit 1, nothing on stdout"    "$(run resolve deadbeef)" "rc=1"
ok "2 matches -> exit 1, nothing on stdout"    "$(run resolve bbbb2222)" "rc=1"
ok "…and says how many matched"                "$(PATH="$P" bash "$SESS" resolve bbbb2222 2>&1 >/dev/null | grep -c '2 sessions match')" 1
ok "a full id still resolves when its prefix is shared" "$(run resolve "$U3" | tr '\n' ' ')" "$U3 rc=0 "
printf 'not json' > "$TMP/bad.json"
ok "unreadable list -> exit 2"                 "$(STUB_JSON="$TMP/bad.json" run resolve aaaa1111)" "rc=2"
printf '[{"id":"dddd4444","sessionId":"dddd4444","state":"done"}]' > "$TMP/short.json"
ok "a match with no full UUID -> exit 2"       "$(STUB_JSON="$TMP/short.json" run resolve dddd4444)" "rc=2"
ok "no claude on PATH -> exit 2"               "$(PATH="/usr/bin:/bin" bash "$SESS" resolve aaaa1111 >/dev/null 2>&1; echo "rc=$?")" "rc=2"

echo "== stalled: blocked AND no assistant turn since the session started =="
PD="$TMP/projects"; mkdir -p "$PD/-wt"
st() { run stalled "$1" --projects-dir "$PD" | tr '\n' ' '; }
ok "blocked, no transcript -> stalled"         "$(st aaaa1111)" "stalled $U1 rc=0 "
printf '%s\n' '{"type":"user","timestamp":"2026-10-09T14:55:00.000Z"}' \
  '{"type":"assistant","timestamp":"2026-10-09T14:50:00.000Z"}' > "$PD/-wt/$U1.jsonl"
ok "…a copied history older than the resume -> stalled" "$(st aaaa1111)" "stalled $U1 rc=0 "
printf '%s\n' '{"type":"assistant","timestamp":"2026-10-09T14:54:10.000Z"}' '{"type":"assi' >> "$PD/-wt/$U1.jsonl"
ok "a turn after the resume -> not stalled"    "$(st aaaa1111)" "not-stalled took-a-turn rc=1 "
# A permission prompt follows a tool call, and a tool call is written as an assistant entry.
printf '%s\n' '{"type":"assistant","timestamp":"2026-10-09T14:54:12.000Z","message":{"content":[{"type":"tool_use"}]}}' > "$PD/-wt/$U1.jsonl"
ok "blocked on a permission prompt -> not stalled" "$(st aaaa1111)" "not-stalled took-a-turn rc=1 "
printf '%s\n' '{"type":"user"}' 'garbage' '{"type":"user"}' > "$PD/-wt/$U1.jsonl"
ok "an unreadable line mid-transcript -> unknown" "$(st aaaa1111)" "rc=2 "
rm "$PD/-wt/$U1.jsonl"; mkdir -p "$PD/-a" "$PD/-b"; : > "$PD/-a/$U1.jsonl"; : > "$PD/-b/$U1.jsonl"
ok "two transcripts -> unknown"                "$(st aaaa1111)" "rc=2 "
rm -rf "$PD/-a" "$PD/-b"
ok "working -> not stalled"                    "$(st cccc3333)" "not-stalled working rc=1 "
ok "an id nobody lists -> not stalled"         "$(st deadbeef)" "not-stalled unresolved rc=1 "
ok "an ambiguous id -> not stalled, never guessed" "$(st bbbb2222)" "not-stalled unresolved rc=1 "

echo "== step 4: the fallback is the one exception, and the other rules stand =="
ok "the blocked row names the exception"       "$(has "$S4" '**One named exception: a stalled resume** (below)')" yes
ok "the sweep reads it with \`stalled\`"       "$(has "$S4" 'agent-sessions.sh stalled <the task')" yes
ok "…stops by the UUID's first field"          "$(has "$S4" '`claude stop <the UUID'"'"'s first field>`')" yes
ok "…records the stall with stall-counter"     "$(has "$S4" "stall-counter.sh record <task-doc> --blocker 'resume stalled'")" yes
ok "…and escalates a second one"               "$(has "$S4" 'exit 1 ⇒ `stall-counter.sh escalate <task-doc>`')" yes
ok "a new id becomes session: as the full UUID" "$(has "$S4" 'resolve <the new id>` —')" yes
ok "a failed resolve is never a re-dispatch"   "$(has "$S4" '**A non-zero `resolve` is neither a resume nor a re-dispatch**')" yes
ok "…and no line tells it to dispatch fresh"   "$(grep -c 'not resume; dispatch fresh' "$S4")" 0
ok "the stalled command is one code span"     "$(has "$S4" 'agent-sessions.sh stalled <the task'"'"'s session UUID>`')" yes
ok "the never-wait rule is unchanged"         "$(has "$S4" 'COMPLETION IS READ, NEVER AWAITED')" yes
ok "the no-re-dispatch rule is unchanged"      "$(has "$S4" 'A non-zero verdict is never a re-dispatch.')" yes

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
