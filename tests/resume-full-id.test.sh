#!/usr/bin/env bash
#
# resume-full-id.test.sh — every `claude --resume` in plugin/ takes the FULL session id
# from `agent-sessions.sh full`, step 3 records that id, `full` refuses to guess, and
# `stalled` tells a resume parked on the picker from one that worked. Offline: `claude` is
# a stub.
# Reasoning: docs/pm-design.md#step-4.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SESS="$REPO/plugin/scripts/agent-sessions.sh"
S3="$REPO/plugin/tick-steps/step-3-dispatch.md"
S4="$REPO/plugin/tick-steps/step-4-advance.md"
for f in "$SESS" "$S3" "$S4"; do
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
# Prints each offending `file:line`: a resume whose id is anything but what `full`
# printed, or one in a file that never calls `full`.
ARG='--resume <the UUID full printed>'
RESOLVE='${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh full <'
offenders() { # <dir>
  grep -rnE 'claude[^`]*[[:space:]](--resume|-r)([[:space:]=]|$)' "$1" 2>/dev/null \
    | while IFS= read -r hit; do
        f="${hit%%:*}"; rest="${hit#*:}"; n="${rest%%:*}"; line="${rest#*:}"
        case "$line" in
          *"$ARG"*) grep -qF -- "$RESOLVE" "$f" && continue ;;
          *'Bash(claude --bg --resume *)'*) continue ;;  # init's allow rule names no id
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
ok "…and so does a file that never calls full" "$(offenders "$TMP/mut2" | wc -l | tr -d ' ')" 1
printf '   `cd <wt> && claude --bg -r abcd1234 msg`\n' > "$TMP/mut/r.md"
ok "…and so does the -r spelling"              "$(offenders "$TMP/mut" | wc -l | tr -d ' ')" 2
printf 'claude --bg --resume "$sid" "$msg"\n' > "$TMP/mut/r.sh"
ok "…and so does a script"                     "$(offenders "$TMP/mut" | wc -l | tr -d ' ')" 3

echo "== a resume carries none of the four spawn flags (it would start a copy) =="
# Command forms only: every code span (a paragraph joined first, so a wrapped span is one
# span) and every fenced or script line, `\`-continuations joined. Prose that NAMES a
# flag is a separate span with no `claude … --resume` in it, so it never counts.
cat > "$TMP/flags.py" <<'PY'
import re, sys
FLAG = re.compile(r"(?:^|\s)--(agent|model|permission-mode|add-dir)(?:[=\s]|$)")
RES = re.compile(r"\bclaude\b.*\s(?:--resume|-r)(?:[=\s]|$)")
FENCE = re.compile(r"^ {0,3}(```|~~~)")
def joined(rows):
    buf, start = "", None
    for n, l in rows:
        start = n if start is None else start
        if l.endswith("\\"):
            buf += l[:-1] + " "
            continue
        yield start, buf + l
        buf, start = "", None
    if start is not None:
        yield start, buf
def spans(rows):
    if not rows:
        return
    text = "\n".join(l for _, l in rows)
    for m in re.finditer(r"(`+)(.+?)\1", text.replace("\n", " ")):
        yield rows[0][0] + text.count("\n", 0, m.start()), m.group(2)
def segments(path):
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    rows = list(enumerate(lines, 1))
    if not path.endswith(".md"):
        yield from joined(rows)
        return
    fence, code, para = None, [], []
    for n, l in rows:
        m = FENCE.match(l)
        if fence:
            if m and m.group(1) == fence:
                yield from joined(code)
                fence, code = None, []
            else:
                code.append((n, l))
        elif m:
            yield from spans(para)
            fence, para = m.group(1), []
        elif l.strip():
            para.append((n, l))
        else:
            yield from spans(para)
            para = []
    yield from spans(para)
    yield from joined(code)
for path in sys.argv[1:]:
    for n, seg in segments(path):
        if RES.search(seg):
            print("%s %s:%d" % ("OFFENDER" if FLAG.search(seg) else "resume", path, n))
PY
scan() { find "$@" -type f \( -name '*.md' -o -name '*.sh' \) -print0 2>/dev/null \
           | xargs -0 python3 "$TMP/flags.py"; }
REAL="$(scan "$REPO/plugin/tick-steps" "$REPO/plugin/agents" "$REPO/docs")"
ok "no --resume under tick-steps/, agents/ or docs/ carries a spawn flag" \
   "$(printf '%s\n' "$REAL" | grep -c '^OFFENDER')" 0
ok "…and the scan is not vacuous: it reads step 4's resume" \
   "$(printf '%s\n' "$REAL" | grep -c "^resume $S4:")" 1
ok "the forking phrase is gone from plugin/ and docs/" \
   "$(grep -rn 'same flags step 3' "$REPO/plugin" "$REPO/docs" | wc -l | tr -d ' ')" 0
ok "…and so is the 2.1.295 new-id sentence" "$(grep -c 'Every resume prints' "$S4")" 0
mkdir -p "$TMP/flags"
printf 'Run `cd <wt> && claude --bg --agent loopd:x --resume <id> m`.\n' > "$TMP/flags/a.md"
printf '```bash\nclaude --bg --resume <id> \\\n  --model sonnet m\n```\n' > "$TMP/flags/b.md"
printf 'Wrapped `cd <wt> && claude --bg --resume <id>\n--permission-mode auto m` span.\n' > "$TMP/flags/c.md"
printf 'claude --bg --resume "$sid" --add-dir "$d" "$msg"\n' > "$TMP/flags/d.sh"
printf 'Never pass `--agent`, `--model`, `--permission-mode` or `--add-dir` to\n`cd <wt> && claude --bg --resume <id> m`.\n' > "$TMP/flags/e.md"
FL="$(scan "$TMP/flags")"
ok "a flag in a one-line code span fails it"  "$(printf '%s\n' "$FL" | grep -c '^OFFENDER .*/a.md:1$')" 1
ok "…so does a \`\\\`-continued fenced line"   "$(printf '%s\n' "$FL" | grep -c '^OFFENDER .*/b.md:2$')" 1
ok "…and a code span wrapped across lines"     "$(printf '%s\n' "$FL" | grep -c '^OFFENDER .*/c.md:1$')" 1
ok "…and a script"                             "$(printf '%s\n' "$FL" | grep -c '^OFFENDER .*/d.sh:1$')" 1
ok "prose naming the flags is not a command"   "$(printf '%s\n' "$FL" | grep -c 'e.md')" 1
ok "…and its flag-free resume passes"          "$(printf '%s\n' "$FL" | grep -c '^resume .*/e.md:2$')" 1

echo "== step 3 records the full id, never the printed short one =="
ok "step 3 runs full on the printed id"        "$(has "$S3" '${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh full <the printed id>')" yes
ok "…records what full prints as session:"     "$(has "$S3" '36-character id it prints as')" yes
ok "…and never the printed id itself"          "$(grep -c 'Record that id as' "$S3")" 0
ok "…a failed full records nothing, and says so" "$(has "$S3" 'spawned; session id unresolved: <the')" yes

# A stub `claude`: `agents` prints $STUB_JSON, anything else exits 1.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
case " $* " in *" --resume "*) cat "$STUB_RESUME"; exit 0 ;; esac
[ "${1:-}" = "agents" ] || exit 1
cat "$STUB_JSON"
STUB
chmod +x "$TMP/bin/claude"
P="$TMP/bin:$PATH"
U1=aaaa1111-0000-4000-8000-000000000001
U2=bbbb2222-0000-4000-8000-000000000002
U3=bbbb2222-0000-4000-8000-000000000003
U4=cccc3333-0000-4000-8000-000000000004
U5=eeee5555-0000-4000-8000-000000000005
U6=abab6666-0000-4000-8000-000000000006
STARTED=1791557649233   # 2026-10-09T14:54:09.233Z
cat > "$TMP/agents.json" <<JSON
[ {"id":"aaaa1111","sessionId":"$U1","kind":"background","state":"blocked","startedAt":$STARTED},
  {"id":"bbbb2222","sessionId":"$U2","kind":"background","state":"done","startedAt":$STARTED},
  {"id":"bbbb2222","sessionId":"$U3","kind":"background","state":"done","startedAt":$STARTED},
  {"id":"cccc3333","sessionId":"$U4","kind":"background","state":"working","startedAt":$STARTED},
  {"id":"eeee5555","sessionId":"$U5","kind":"background","state":"blocked","waitingFor":"login","startedAt":$STARTED},
  {"id":"abab6666","sessionId":"$U6","kind":"background","state":"blocked","startedAt":1792141798653} ]
JSON
export STUB_JSON="$TMP/agents.json"
run() { PATH="$P" bash "$SESS" "$@" 2>/dev/null; echo "rc=$?"; }

echo "== full: one match is the full UUID; two is exit 1, none exit 2, never a guess =="
ok "1 match, short id -> the full UUID"        "$(run full aaaa1111 | tr '\n' ' ')" "$U1 rc=0 "
ok "1 match, full id -> itself"                "$(run full "$U4" | tr '\n' ' ')" "$U4 rc=0 "
ok "0 matches -> exit 2, nothing on stdout"    "$(run full deadbeef)" "rc=2"
ok "an unknown full id -> exit 2"              "$(run full ffff6666-0000-4000-8000-000000000006)" "rc=2"
ok "2 matches -> exit 1, nothing on stdout"    "$(run full bbbb2222)" "rc=1"
ok "…and says how many matched"                "$(PATH="$P" bash "$SESS" full bbbb2222 2>&1 >/dev/null | grep -c '2 sessions match')" 1
ok "a full id still resolves when its prefix is shared" "$(run full "$U3" | tr '\n' ' ')" "$U3 rc=0 "
printf 'not json' > "$TMP/bad.json"
ok "unreadable list -> exit 2"                 "$(STUB_JSON="$TMP/bad.json" run full aaaa1111)" "rc=2"
printf '[{"id":"dddd4444","sessionId":"dddd4444","state":"done"}]' > "$TMP/short.json"
ok "a match with no full UUID -> exit 2"       "$(STUB_JSON="$TMP/short.json" run full dddd4444)" "rc=2"
ok "no claude on PATH -> exit 2"               "$(PATH="/usr/bin:/bin" bash "$SESS" full aaaa1111 >/dev/null 2>&1; echo "rc=$?")" "rc=2"
ok "resolve is the older name for full"        "$(run resolve aaaa1111 | tr '\n' ' ')" "$U1 rc=0 "

echo "== resume-id: the id is read off the resume's stdout (2.1.296 shapes, stubbed CLI) =="
RS="$TMP/resume.out"; export STUB_RESUME="$RS"
rid() { PATH="$P" claude --bg --resume "$1" msg | PATH="$P" bash "$SESS" resume-id "$1" - 2>/dev/null; echo "rc=$?"; }
printf 'note: woke session aaaa1111 with its saved options (--agent, --permission-mode, --add-dir, --model).\nbackgrounded \302\267 aaaa1111 \302\267 demo-task-001\n' > "$RS"
ok "a flag-free resume keeps the id: same, session: stays" "$(rid "$U1" | tr '\n' ' ')" "same $U1 rc=0 "
printf 'note: background session aaaa1111 keeps its own saved options, so the flags you passed started a copy as cccc3333. Without flags, the same command continues aaaa1111 itself.\nbackgrounded \302\267 cccc3333\n' > "$RS"
ok "a forked resume: copy, the new id's full UUID" "$(rid "$U1" | tr '\n' ' ')" "copy $U4 rc=0 "
sed 's/cccc3333/deadbeef/g' "$RS" > "$RS.x" && mv "$RS.x" "$RS"
ok "…a copy full cannot resolve -> unresolved, exit 1" "$(rid "$U1" | tr '\n' ' ')" "unresolved deadbeef rc=1 "
printf 'note: … started a copy as cccc3333.\nbackgrounded \302\267 deadbeef\n' > "$RS"
ok "a copy note the backgrounded line contradicts -> exit 2" "$(rid "$U1")" "rc=2"
printf 'Error: something else\n' > "$RS"
ok "no backgrounded line -> exit 2, never a guess" "$(rid "$U1")" "rc=2"
ok "the stdout may also be passed as an argument" \
   "$(PATH="$P" bash "$SESS" resume-id "$U1" "backgrounded $(printf '\302\267') aaaa1111" | tr '\n' ' ')" "same $U1 "

echo "== stalled: blocked AND no assistant turn since the session started =="
PD="$TMP/projects"; mkdir -p "$PD/-wt"
st() { run stalled "$1" --projects-dir "$PD" | tr '\n' ' '; }
ok "blocked, no transcript, no waitingFor -> stalled" "$(st aaaa1111)" "stalled $U1 rc=0 "
ok "blocked on waitingFor before a turn -> not stalled" "$(st eeee5555)" "not-stalled waiting-for rc=1 "
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
# An in-place resume keeps the transcript and resets startedAt (measured 1792089555834 ->
# 1792141798653), so the earlier rounds' turns are older than the resume.
printf '%s\n' '{"type":"assistant","timestamp":"2026-10-15T18:45:00.000Z"}' > "$PD/-wt/$U6.jsonl"
ok "an in-place resume with no turn since it -> stalled" "$(st abab6666)" "stalled $U6 rc=0 "
printf '%s\n' '{"type":"assistant","timestamp":"2026-10-16T09:10:30.000Z"}' >> "$PD/-wt/$U6.jsonl"
ok "…and one that took a turn -> not stalled"  "$(st abab6666)" "not-stalled took-a-turn rc=1 "
ok "an id nobody lists -> not stalled"         "$(st deadbeef)" "not-stalled unresolved rc=1 "
ok "an ambiguous id -> not stalled, never guessed" "$(st bbbb2222)" "not-stalled unresolved rc=1 "

echo "== step 4: the fallback is the one exception, and the other rules stand =="
ok "the blocked row names the exception"       "$(has "$S4" '**One named exception: a stalled resume** (below)')" yes
ok "the sweep reads it with \`stalled\`"       "$(has "$S4" 'agent-sessions.sh stalled <the task')" yes
ok "…stops by the UUID's first field"          "$(has "$S4" '`claude stop <the UUID'"'"'s first field>`')" yes
ok "…records the stall with stall-counter"     "$(has "$S4" "stall-counter.sh record <task-doc> --blocker 'resume stalled'")" yes
ok "…and escalates a second one"               "$(has "$S4" 'exit 1 ⇒ `stall-counter.sh escalate <task-doc>`')" yes
ok "a copy's full UUID becomes session:"      "$(has "$S4" "**\`copy <uuid>\`** is that new id's full UUID")" yes
ok "…and a kept id writes a woke note"         "$(has "$S4" '`# Notes` line `woke <that UUID>`')" yes
ok "…step 4 runs resume-id on the resume's stdout" "$(has "$S4" "agent-sessions.sh resume-id <the UUID> '<everything the resume printed>'")" yes
ok "…and the stalled sweep reads woke notes too" "$(has "$S4" '`resumed` or `woke` note')" yes
ok "…an unresolved id blocks, never resumes old" "$(has "$S4" 'write `resume launched; session id unresolved: <the printed id>`')" yes
ok "a failed full is never a re-dispatch"      "$(has "$S4" '**A non-zero `full` is neither a resume nor a re-dispatch**')" yes
ok "…and a short session: is resolved first"   "$(has "$S4" '`full` runs on every recorded value')" yes
ok "…and no line tells it to dispatch fresh"   "$(grep -c 'not resume; dispatch fresh' "$S4")" 0
ok "a waitingFor prompt stays the human's"      "$(has "$S4" 'on a login or other `waitingFor` prompt before its first turn')" yes
ok "the stalled command is one code span"     "$(has "$S4" 'agent-sessions.sh stalled <the task'"'"'s session UUID>`')" yes
ok "the never-wait rule is unchanged"         "$(has "$S4" 'COMPLETION IS READ, NEVER AWAITED')" yes
ok "the no-re-dispatch rule is unchanged"      "$(has "$S4" 'A non-zero verdict is never a re-dispatch.')" yes

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
