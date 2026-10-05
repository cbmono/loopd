#!/usr/bin/env bash
#
# background-dispatch.test.sh — role agents are DETACHED sessions, and the two readers
# that replace the notification say so. Pins `agent-sessions.sh` against a stubbed
# `claude agents --json` (offline, no auth, no session spawned), pins that
# `check-dispatch.sh` still returns every verdict it returned before it learned
# `session:`, and pins the prose clauses a tick would otherwise re-invent: the
# `--bg`/`-p` conflict, `bypassPermissions`, and the cap counting sessions.
#
# Reasoning and the live measurements: docs/pm-design.md#step-3-background, re-runnable
# as docs/spikes/bg-dispatch-probe.sh --live.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
SESS="$REPO/plugin/scripts/agent-sessions.sh"
CHECK="$REPO/plugin/scripts/check-dispatch.sh"
CORE="$REPO/plugin/agents/project-manager.md"
S3="$REPO/plugin/tick-steps/step-3-dispatch.md"
S4="$REPO/plugin/tick-steps/step-4-advance.md"
SKILL="$REPO/plugin/skills/dispatch/SKILL.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
PROBE="$REPO/docs/spikes/bg-dispatch-probe.sh"
for f in "$SESS" "$CHECK" "$CORE" "$S3" "$S4" "$SKILL" "$SCHEMA" "$PROBE"; do
  [ -f "$f" ] || { echo "background-dispatch.test: $f not found" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "background-dispatch.test: python3 required" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bg-dispatch.XXXXXX")" || {
  echo "background-dispatch.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# A stub `claude` on PATH, so every assertion below is offline and spawns nothing. It
# answers only `agents --json`; anything else exits 1, which is what proves the readers
# never reach for a second subcommand.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "agents" ] || exit 1
cat <<'JSON'
[ {"id":"aaaa1111","sessionId":"aaaa1111-0000-4000-8000-000000000001","kind":"background","state":"working"},
  {"id":"bbbb2222","sessionId":"bbbb2222-0000-4000-8000-000000000002","kind":"background","state":"blocked"},
  {"id":"cccc3333","sessionId":"cccc3333-0000-4000-8000-000000000003","kind":"background","state":"done"},
  {"id":"dddd4444","sessionId":"dddd4444-0000-4000-8000-000000000004","kind":"background","state":"stopped"},
  {"id":"eeee5555","sessionId":"eeee5555-0000-4000-8000-000000000005","kind":"background","state":"idle"} ]
JSON
STUB
chmod +x "$TMP/bin/claude"
PATH_WITH="$TMP/bin:$PATH"

echo "== agent-sessions.sh state: one recorded value matches either spelling =="
ok "short id -> working"   "$(PATH="$PATH_WITH" bash "$SESS" state aaaa1111 2>/dev/null)" working
ok "full sessionId -> blocked" \
  "$(PATH="$PATH_WITH" bash "$SESS" state bbbb2222-0000-4000-8000-000000000002 2>/dev/null)" blocked
ok "a finished session -> done"   "$(PATH="$PATH_WITH" bash "$SESS" state cccc3333 2>/dev/null)" done
ok "an id nobody lists -> gone"   "$(PATH="$PATH_WITH" bash "$SESS" state deadbeef 2>/dev/null)" gone

echo "== no \`claude\` at all is UNKNOWN, and unknown is never a state =="
# `/usr/bin:/bin` still carries bash and python3 on both platforms this runs on, and
# carries `claude` on neither — which is the case under test, not a missing interpreter.
OUT="$(PATH="/usr/bin:/bin" bash "$SESS" state aaaa1111 2>/dev/null)"; RC=$?
ok "exit 2"        "$RC"   2
ok "prints nothing on stdout" "${OUT:-<empty>}" "<empty>"

echo "== agent-sessions.sh in-flight: the cap counts SESSIONS, not documents =="
mk() { # <name> <status> <session>
  mkdir -p "$TMP/bundle/projects/p/tasks"
  printf -- '---\ntype: Task\nstatus: %s\nsession: %s\n---\n' "$2" "$3" \
    > "$TMP/bundle/projects/p/tasks/$1.md"
}
mk live      in-progress aaaa1111
mk reviewing in-review   bbbb2222
mk finished  in-progress cccc3333
mk vanished  in-progress deadbeef
mk merged    done        aaaa1111
printf -- '---\ntype: Task\nstatus: in-progress\n---\n' > "$TMP/bundle/projects/p/tasks/nosession.md"
ok "working + blocked hold a slot; done/gone do not" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/bundle" 2>/dev/null)" 2
ok "a \`done\` task's stale id is history, not a slot" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/bundle" 2>&1 >/dev/null \
     | grep -c merged)" 0
ok "every live-eligible session is reported by name" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/bundle" 2>&1 >/dev/null | wc -l | tr -d ' ')" 4
ok "an empty bundle is 0, not an error" \
  "$(mkdir -p "$TMP/none" && PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/none" 2>/dev/null)" 0

echo "== in-flight: only an explicitly terminal state frees a slot =="
one() { # <bundle> <session> -> a bundle whose only recorded session is <session>
  mkdir -p "$TMP/$1/projects/p/tasks"
  printf -- '---\ntype: Task\nstatus: in-progress\nsession: %s\n---\n' "$2" \
    > "$TMP/$1/projects/p/tasks/t.md"
}
one b-stopped dddd4444
one b-idle    eeee5555
ok "the allowlist is spelled out once" \
  "$(grep -c '^TERMINAL="done gone stopped completed cancelled failed error exited"$' "$SESS")" 1
ok "a \`stopped\` session frees its slot" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/b-stopped" 2>/dev/null)" 0
ok "…and is not named unrecognised" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/b-stopped" 2>&1 >/dev/null | grep -c unrecognised)" 0
ok "an \`idle\` session still holds one" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/b-idle" 2>/dev/null)" 1
ok "…and is named once as unrecognised, with its id" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/b-idle" 2>&1 >/dev/null \
     | grep -c "unrecognised state 'idle' for session eeee5555")" 1
ok "working/blocked are known, not unrecognised" \
  "$(PATH="$PATH_WITH" bash "$SESS" in-flight "$TMP/bundle" 2>&1 >/dev/null | grep -c unrecognised)" 0
ok "\`state\` passes stopped through raw" "$(PATH="$PATH_WITH" bash "$SESS" state dddd4444 2>/dev/null)" stopped
ok "\`state\` passes idle through raw, unflagged" \
  "$(PATH="$PATH_WITH" bash "$SESS" state eeee5555 2>&1)" idle
ok "one classifier, and in-flight its only caller" \
  "$(grep -c 'holds_slot' "$SESS")" 2
OUT="$(PATH="/usr/bin:/bin" bash "$SESS" in-flight "$TMP/b-idle" 2>/dev/null)"; RC=$?
ok "no \`claude\`: in-flight exits 2" "$RC" 2
ok "…and prints no count" "${OUT:-<empty>}" "<empty>"

echo "== check-dispatch.sh keeps every verdict it returned before it learned session: =="
parked() { printf -- '---\ntype: Task\nkind: build\nstatus: in-progress\n%spr: [ ]\n---\n' "$1"; }
parked ""                      > "$TMP/no-session.md"
parked "session: aaaa1111
"                              > "$TMP/live.md"
parked "session: cccc3333
"                              > "$TMP/exited.md"
PATH="$PATH_WITH" bash "$CHECK" "$TMP/no-session.md" >/dev/null 2>"$TMP/e1"; ok "no session: still exit 1" "$?" 1
PATH="$PATH_WITH" bash "$CHECK" "$TMP/live.md"       >/dev/null 2>"$TMP/e2"; ok "a WORKING session: still exit 1" "$?" 1
PATH="$PATH_WITH" bash "$CHECK" "$TMP/exited.md"     >/dev/null 2>"$TMP/e3"; ok "an exited session: still exit 1" "$?" 1
ok "…and the field-less report gains no SESSION line" "$(grep -c SESSION "$TMP/e1")" 0
ok "…the live one is named WORKING"                   "$(grep -c 'is WORKING' "$TMP/e2")" 1
ok "…the exited one is named EXITED"                  "$(grep -c 'has EXITED' "$TMP/e3")" 1

echo "== the tick's own instructions carry the clauses a wave costs =="
ok "step 3 spawns with claude --bg"       "$(has "$S3" 'claude --bg "<the whole brief>"')" yes
ok "…and names the --bg/-p conflict"      "$(has "$S3" '**`--bg` and `-p` conflict**')"    yes
ok "…in auto mode: the command line asks for it" "$(has "$S3" '--permission-mode auto --add-dir <bundle root>')" yes
ok "…and never for a bypass agent"         "$(has "$S3" '--permission-mode bypassPermissions --add-dir')" no
ok "…saying why, in one clause"            "$(has "$S3" '**`--permission-mode auto`, and never `bypassPermissions`.**')" yes
ok "…and that haiku cannot hold auto mode" "$(has "$S3" '**Never on `haiku`**')" yes
ok "…and the cap counts sessions"         "$(has "$S3" 'agent-sessions.sh in-flight')"      yes
ok "step 4 reads state, never a notification" "$(has "$S4" 'COMPLETION IS READ, NEVER AWAITED')" yes
ok "…and refuses \`claude rm\` on a role agent" "$(has "$S4" 'Never `claude rm` a role agent')" yes

# The every-tick core must not carry a SECOND, contradicting copy of either step: the
# split (#215) left steps 3 and 4 duplicated there, and the stale copy still said
# `Agent` tool. A grep over both files is the only thing that keeps them from diverging.
ok "no role agent is spawned with the Agent tool anywhere" \
  "$(grep -rc "subagent_type: ${PN}:<assignee>" "$CORE" "$S3" "$S4" | grep -cv ':0$')" 0
ok "the core points at step 3 rather than restating it" \
  "$(has "$CORE" 'tick-steps/step-3-dispatch.md')" yes
ok "…and at step 4"                       "$(has "$CORE" 'tick-steps/step-4-advance.md')"  yes
ok "the launcher says the notification is the tick's own exit" \
  "$(has "$SKILL" "That notification now means the tick's OWN exit")" yes
ok "SCHEMA.md documents session:"         "$(has "$SCHEMA" 'session: <id>')"                yes
ok "…including why it cannot be pre-written" "$(has "$SCHEMA" '`--session-id` is')"         yes
ok "the probe is executable"              "$([ -x "$PROBE" ] && echo yes || echo no)"       yes

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
