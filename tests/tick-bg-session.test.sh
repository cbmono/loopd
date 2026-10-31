#!/usr/bin/env bash
#
# tick-bg-session.test.sh — the dispatch tick as a detached `claude --bg` session.
# tick-spawn.sh: the spawn line, the template-built brief (today's guardrails verbatim, the
# single-quoted form byte for byte) and the session recorded on the lock. tick-reap.sh: the
# lock released only on a committed close for the minted id, a dead or vanished tick closed
# by the reaper, BLOCKED reported as such, the --wait form, the COST: footer from the ended
# session's transcript, and Needs-you from AWAITING.md, never the transcript. Offline: a stub
# `claude` answers `--bg`, `agents` and `stop`. Reasoning: tick-as-bg-session/task-002.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
SC="$REPO/plugin/scripts"
SKILL="$REPO/plugin/skills/dispatch/SKILL.md"
PM="$REPO/plugin/agents/project-manager.md"
FIX="$REPO/tests/fixtures/tick-brief/guardrails-2026-10-29.txt"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tickbg.XXXXXX")" || { echo "tick-bg-session.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

ST="$TMP/st"; mkdir -p "$TMP/bin" "$ST"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  agents) cat "$ST/agents.json" ;;
  stop)   echo "$2" >> "$ST/stopped" ;;
  --bg)   pwd -P > "$ST/cwd"; n=$#; args=("$@")
          printf '%s ' "${args[@]:0:n-1}" | sed 's/ $//' > "$ST/flags"
          printf '%s' "${args[n-1]}" > "$ST/brief"
          [ -f "$ST/fail-spawn" ] && exit 1
          echo "backgrounded · 1234abcd" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/claude"
export ST PATH="$TMP/bin:$PATH" CLAUDE_CONFIG_DIR="$TMP/cfg"
SID="1234abcd-0000-4000-8000-00000000000a"
state() { # <state|none|garbage>
  case "$1" in
    none) echo '[]' ;; garbage) echo 'not json' ;;
    *) printf '[{"id":"1234abcd","sessionId":"%s","state":"%s"%s}]\n' "$SID" "$1" \
         "${STATUS:+,\"status\":\"$STATUS\"}" ;;
  esac > "$ST/agents.json"
}

mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
cat > "$CLAUDE_CONFIG_DIR/projects/p/$SID.jsonl" <<'JSONL'
{"type":"assistant","timestamp":"2026-10-29T10:00:00Z","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"output_tokens":30,"cache_read_input_tokens":5},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}},{"type":"text","text":"TRANSCRIPT-SENTINEL"}]}}
{"type":"assistant","timestamp":"2026-10-29T10:01:00Z","message":{"id":"m2","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"output_tokens":3,"cache_read_input_tokens":0},"content":[]}}
JSONL

n=0
bundle() { # [effort] -> B: a fresh git bundle with a ledger, an AWAITING.md and a config
  n=$((n+1)); local b="$TMP/b$n"
  mkdir -p "$b/.loopd"
  local eff=""; [ -n "${1:-}" ] && eff=', "roleEffort": { "project-manager": "'"$1"'" }'
  printf '{ "roleTiers": { "project-manager": "deep" }, "models": { "deep": "opus" }%s }\n' "$eff" > "$b/instance.config.json"
  printf '# Log\n\n* TICK 2026-10-29T09:00:00Z by someone close: an older tick\n' > "$b/.loopd/log.md"
  printf '/.loopd/.tick-lock\n/.loopd/.tick-lock.claim\n/.loopd/AWAITING.md\n' > "$b/.gitignore"
  printf '# Awaiting you\n\n## 🔴 Awaiting you (2)\n* answer task-007\n* merge #12\n\n## Later\n* not this\n' > "$b/.loopd/AWAITING.md"
  { git -C "$b" init -q && git -C "$b" add -A && git -C "$b" -c user.name=t -c user.email=t@example.com commit -qm init; } >/dev/null 2>&1
  B="$b"
}
commit() { { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.com commit -qm tick; } >/dev/null 2>&1; }
spawned() { # [effort] -> a bundle whose lock holds a spawned tick; sets B ID
  bundle "${1:-}"; ID="$(bash "$SC/tick-lock.sh" mint)"; state working; rm -f "$ST/fail-spawn" "$ST/stopped"
  bash "$SC/tick-lock.sh" acquire --instance "$B" --agent project-manager --claimant "$ID" >/dev/null 2>&1 \
    && bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" --gap 10m >/dev/null 2>&1
}
reap() { OUT="$(bash "$SC/tick-reap.sh" --instance "$B" "$@" 2>&1)"; RC=$?; }
locked() { [ -e "$B/.loopd/.tick-lock" ] && echo yes || echo no; }
TS=2026-10-29T10:00:00Z

echo "== criterion 1: the launcher spawns no Agent-tool tick =="
ok "SKILL.md has no subagent_type: loopd:project-manager" "$(grep -c 'subagent_type: loopd:project-manager' "$SKILL" | tr -d ' ')" 0
ok "…and grants no Agent tool" "$(sed -n '/^allowed-tools:/p' "$SKILL" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -cx Agent | tr -d ' ')" 0
ok "…and names tick-spawn.sh as the spawn" "$(has "$(cat "$SKILL")" 'scripts/tick-spawn.sh --tick <id>')" yes

echo "== tick-spawn.sh: the spawn line and the record =="
spawned high
ok "spawn exits 0" "$?" 0
ok "flags: --bg --agent ${PN}:project-manager --permission-mode auto --model --effort" "$(cat "$ST/flags")" \
   "--bg --agent ${PN}:project-manager --permission-mode auto --model opus --effort high"
ok "it runs in the bundle root" "$(cat "$ST/cwd")" "$B"
ok "the lock records the full session id" "$(grep -c "^session: $SID\$" "$B/.loopd/.tick-lock" | tr -d ' ')" 1
spawned
ok "no roleEffort ⇒ no --effort flag" "$(has "$(cat "$ST/flags")" '--effort')" no

echo "== criterion 2: the brief is the template, guardrails verbatim =="
BRIEF="$(cat "$ST/brief")"
ok "the brief carries the minted id" "$(has "$BRIEF" "--claimant $ID")" yes
ok "…in the ledger line it asks for" "$(has "$BRIEF" "open: $ID · <what you are about to do>")" yes
ok "…and the gap" "$(has "$BRIEF" 'Gap: `10m`')" yes
ok "no placeholder left" "$(has "$BRIEF" '{{')" no
missing=0; lines=0
while IFS= read -r l; do
  [ -n "${l// /}" ] || continue; lines=$((lines+1))
  grep -qxF -- "$l" <<<"$BRIEF" || { missing=$((missing+1)); echo "    missing: $l"; }
done < "$FIX"
ok "the fixture holds today's guardrails" "$([ "$lines" -ge 60 ] && echo yes || echo no)" yes
ok "every guardrail line appears verbatim" "$missing" 0
cp "$ST/brief" "$TMP/real-brief"
bash -c "$(bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" --print 2>/dev/null)" >/dev/null
ok "the single-quoted --print form reaches claude byte for byte" "$(cmp -s "$ST/brief" "$TMP/real-brief" && echo yes || echo no)" yes
bash -c "$(bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" --print 2>/dev/null | sed "s/'\\\\''/'/g; s/ '/ \"/; s/' < \/dev\/null/\" < \/dev\/null/")" >/dev/null 2>&1
ok "…while a double-quoted form does not (non-vacuity)" "$(cmp -s "$ST/brief" "$TMP/real-brief" && echo same || echo differs)" differs
bundle; bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" --dry-run --print 2>/dev/null > "$TMP/dry"
ok "--dry-run: the brief says DRY RUN" "$(has "$(cat "$TMP/dry")" 'Mode: DRY RUN — do steps 1–2')" yes
ok "…spawn no role agent and modify no target repo" "$(has "$(cat "$TMP/dry")" 'spawn no role agent and modify no target repo')" yes
ok "…and never LIVE" "$(has "$(cat "$TMP/dry")" 'Mode: LIVE')" no

echo "== tick-spawn.sh refusals =="
bundle; rm -f "$ST/brief"
bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" >/dev/null 2>&1
ok "no lock minted for the id ⇒ exit 3" "$?" 3
ok "…and nothing spawned" "$([ -e "$ST/brief" ] && echo yes || echo no)" no
bash "$SC/tick-lock.sh" acquire --instance "$B" --claimant "$ID"; touch "$ST/fail-spawn"
bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" >/dev/null 2>&1
ok "a spawn that fails ⇒ exit 1" "$?" 1
ok "…and the lock is released" "$(locked)" no
rm -f "$ST/fail-spawn"
bundle; printf '{ "roleTiers": { "project-manager": "light" }, "models": { "light": "haiku" } }\n' > "$B/instance.config.json"
bash "$SC/tick-lock.sh" acquire --instance "$B" --claimant "$ID"
bash "$SC/tick-spawn.sh" --instance "$B" --tick "$ID" >/dev/null 2>&1
ok "a tick resolved to haiku is refused" "$?" 3

echo "== tick-reap.sh: nothing to reap =="
bundle; reap
ok "no lock ⇒ exit 0, silent" "$RC:$OUT" "0:"
bash "$SC/tick-lock.sh" acquire --instance "$B" --claimant "$ID"; reap
ok "a lock with no session (an Agent-tool tick) ⇒ exit 0, untouched" "$RC:$(locked)" "0:yes"

echo "== criterion 5 (D4): a live tick keeps the lock; the fire is dropped =="
spawned; printf '* TICK %s by me open: %s · dispatching\n' "$TS" "$ID" >> "$B/.loopd/log.md"; commit "$B"
reap
ok "open entry, session working ⇒ exit 1" "$RC" 1
ok "…one report line" "$(printf '%s\n' "$OUT" | grep -c . | tr -d ' ')" 1
ok "…naming the dropped fire" "$(has "$OUT" 'nothing to dispatch this pass')" yes
ok "…and the lock is kept" "$(locked)" yes
printf '* TICK %s by me close: dispatched task-001\n' "$TS" >> "$B/.loopd/log.md"; state done; reap
ok "a close on disk, not committed, session done ⇒ released (it ended)" "$RC:$(locked)" "0:no"
spawned; printf '* TICK %s by me open: %s · x\n* TICK %s by me close: y\n' "$TS" "$ID" "$TS" >> "$B/.loopd/log.md"; reap
ok "an uncommitted close while the session works ⇒ held" "$RC:$(locked)" "1:yes"
commit "$B"; reap
ok "a committed close while the session works ⇒ held, still finishing" "$RC:$(has "$OUT" 'still finishing')" "1:yes"
STATUS=busy state working; reap
ok "…and while its turn is still running ⇒ held" "$RC:$(locked)" "1:yes"
rm -f "$ST/stopped"; STATUS=idle state working; reap
ok "a committed close, turn over (status idle) ⇒ reaped" "$RC:$(locked)" "0:no"
ok "…and the idle session is stopped, not left an hour" "$(cat "$ST/stopped" 2>/dev/null)" 1234abcd
ok "…and the report says why" "$(has "$OUT" "session 1234abcd idle-after-close")" yes
spawned; printf '* TICK %s by me open: %s · x\n' "$TS" "$ID" >> "$B/.loopd/log.md"; commit "$B"
STATUS=idle state working; reap
ok "an OPEN entry, turn idle ⇒ held: only a committed close frees it" "$RC:$(locked):$(cat "$ST/stopped" 2>/dev/null)" "1:yes:"
# Back to a committed close with the session working, for the section below.
spawned; printf '* TICK %s by me open: %s · x\n* TICK %s by me close: y\n' "$TS" "$ID" "$TS" >> "$B/.loopd/log.md"; commit "$B"

echo "== criterion 4 + 9: a committed close is reaped, Needs-you and COST printed =="
state done; reap
ok "committed close, session done ⇒ exit 0" "$RC" 0
ok "…the lock is released" "$(locked)" no
ok "…the report names the minted tick" "$(has "$OUT" "reaped: $ID · closed")" yes
ok "…prints that entry's close line verbatim" "$(has "$OUT" "* TICK $TS by me close: y")" yes
ok "…Needs-you from AWAITING.md" "$(has "$OUT" $'Needs you:\n* answer task-007\n* merge #12')" yes
ok "…stopping at the next heading" "$(has "$OUT" 'not this')" no
ok "…the COST: footer from the ended session's transcript" "$(printf '%s\n' "$OUT" | tail -1)" "COST: usage tokens=66 tools=1 ms=60000"
ok "…and nothing of the transcript itself" "$(has "$OUT" 'TRANSCRIPT-SENTINEL')" no
bash "$SC/tick-lock.sh" acquire --instance "$B" --as loop --claimant "$(bash "$SC/tick-lock.sh" mint)"
ok "…so the same fire's acquire succeeds" "$?" 0
spawned; printf '* TICK %s by me idle — fingerprint unchanged (tick-delta) · %s\n' "$TS" "$ID" >> "$B/.loopd/log.md"; commit "$B"
state blocked; reap
ok "a committed idle line with the id ⇒ reaped" "$RC:$(locked)" "0:no"
ok "…and a blocked finished turn is stopped" "$(cat "$ST/stopped" 2>/dev/null)" 1234abcd
mv "$CLAUDE_CONFIG_DIR/projects/p/$SID.jsonl" "$TMP/t.jsonl"
spawned; printf '* TICK %s by me idle · %s\n' "$TS" "$ID" >> "$B/.loopd/log.md"; commit "$B"; state done; reap
ok "no transcript ⇒ no COST: line at all" "$(has "$OUT" 'COST:')" no
mv "$TMP/t.jsonl" "$CLAUDE_CONFIG_DIR/projects/p/$SID.jsonl"

echo "== criterion 7: BLOCKED is reported as BLOCKED =="
spawned; printf '* TICK %s by me open: %s · x\n' "$TS" "$ID" >> "$B/.loopd/log.md"; commit "$B"; state blocked; reap
ok "open entry, session blocked ⇒ exit 4" "$RC" 4
ok "…reported BLOCKED" "$(has "$OUT" "BLOCKED: tick $ID")" yes
ok "…never idle, done or reaped" "$(grep -ciE 'idle|done|reaped' <<<"$OUT" | tr -d ' ')" 0
ok "…and the lock is kept" "$(locked)" yes
state garbage; reap
ok "an unreadable session list ⇒ exit 2, lock kept" "$RC:$(locked)" "2:yes"

echo "== criterion 6 (D2): a dead tick's entry is closed by the reaper =="
for s in done gone stopped; do
  spawned; printf '* TICK %s by me open: %s · x\n' "$TS" "$ID" >> "$B/.loopd/log.md"; commit "$B"
  [ "$s" = gone ] && state none || state "$s"; reap
  ok "open entry, session $s ⇒ exit 0, lock released" "$RC:$(locked)" "0:no"
  ok "…a close: line beside it names it dead" \
     "$(grep -c "^\* TICK $TS by me close: dead — $ID session 1234abcd $s with its entry open (tick-reap)\$" "$B/.loopd/log.md" | tr -d ' ')" 1
done
ok "…and the report says dead" "$(has "$OUT" "reaped: $ID · dead")" yes
spawned; state stopped; reap
ok "no entry at all, session ended ⇒ released" "$RC:$(locked)" "0:no"
ok "…after a close: line naming the id" "$(grep -c "close: $ID ended with no ledger entry" "$B/.loopd/log.md" | tr -d ' ')" 1
spawned; reap
ok "no entry yet, session working ⇒ held" "$RC:$(locked)" "1:yes"

echo "== criterion 8: once / DRY RUN wait through the reaper; stop releases nothing =="
spawned; printf '* TICK %s by me open: %s · x\n' "$TS" "$ID" >> "$B/.loopd/log.md"; commit "$B"
( sleep 2; printf '* TICK %s by me close: z\n' "$TS" >> "$B/.loopd/log.md"; commit "$B"; state done ) &
TICK_REAP_POLL=1 TICK_REAP_SLICE=30 reap --wait; wait
ok "--wait returns when the close is committed" "$RC:$(locked)" "0:no"
ok "…printing Needs-you, never the transcript" "$(has "$OUT" 'Needs you:'):$(has "$OUT" 'TRANSCRIPT-SENTINEL')" "yes:no"
spawned; TICK_REAP_POLL=1 TICK_REAP_SLICE=1 reap --wait
ok "--wait past its slice ⇒ exit 5, run again" "$RC:$(has "$OUT" 'waiting:')" "5:yes"
sed -i.bak "s/^spawned: .*/spawned: $(( $(date +%s) - 3600 ))/" "$B/.loopd/.tick-lock"
TICK_REAP_POLL=1 reap --wait
ok "--wait past maxAgentMinutes (absent ⇒ 45) ⇒ exit 1, lock kept" "$RC:$(has "$OUT" 'past its 45m budget'):$(locked)" "1:yes:yes"
STOP="$(awk '/^5\. \*\*Stop\*\*/{p=1} p&&/^This guarantees/{p=0} p' "$SKILL")"
ok "stop: the step exists" "$([ -n "$STOP" ] && echo yes || echo no)" yes
ok "…releases no lock" "$(has "$STOP" 'tick-lock.sh release')" no
ok "…and leaves the tick to the next fire's reaper" "$(has "$STOP" 'next fire')" yes
ok "once waits on tick-reap.sh --wait" "$(has "$(cat "$SKILL")" 'tick-reap.sh --wait')" yes
ok "dry-run spawns with --dry-run" "$(has "$(cat "$SKILL")" 'tick-spawn.sh --tick <id> --gap <gap> --dry-run')" yes
ok "the tick's open line carries the id" "$(has "$(cat "$PM")" 'open: <the tick id from your brief> ·')" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
