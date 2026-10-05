#!/usr/bin/env bash
#
# spawn-preflight.test.sh — the dispatch preflight answers auto / not-auto / could-not-read
# from the mode the hook recorded for THIS call (matched by its --token), claims no launch
# outcome, never collapses the third, spawns nothing, writes nothing, and runs before the
# wave's first status write. Drives the REGISTERED hook command off hooks.json. Offline.
#
# Reasoning: dispatch-reporting-defects/task-005.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/plugin/hooks/permission-mode.sh"
PRE="$REPO/plugin/scripts/spawn-preflight.sh"
HOOKSJSON="$REPO/plugin/hooks/hooks.json"
S3="$REPO/plugin/tick-steps/step-3-dispatch.md"
AW="$REPO/plugin/scripts/build-awaiting.sh"
for f in "$HOOK" "$PRE" "$HOOKSJSON" "$S3" "$AW"; do
  [ -f "$f" ] || { echo "spawn-preflight.test: $f not found" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "spawn-preflight.test: jq required" >&2; exit 2; }
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/spawn-preflight.XXXXXX")" || {
  echo "spawn-preflight.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }
yn() { "$@" && echo yes || echo no; }

SID="1a2b3c4d-0000-4000-8000-00000000abcd"
INST="$TMP/inst"; mkdir -p "$INST/$AB_DIR"; printf '{ "org": "demo" }\n' > "$INST/instance.config.json"
git -C "$INST" init -q 2>/dev/null
REGCMD="$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("permission-mode[.]sh")) | .hooks[].command' "$HOOKSJSON")"

payload() { # <mode or ""> <command> [session id]
  jq -nc --arg m "$1" --arg c "$2" --arg s "${3:-$SID}" \
    '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}
     + (if $m == "" then {} else {permission_mode: $m} end)'
}
hook() { # <project dir> — the registered command, run the way the loader runs it
  CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_PROJECT_DIR="$1" bash -c "exec $REGCMD"
}
TOK=9f3c1a77
CALL='${CLAUDE_PLUGIN_ROOT}/scripts/spawn-preflight.sh --instance . --token '"$TOK"
pre() { CLAUDE_CODE_SESSION_ID="${SID_OVERRIDE-$SID}" bash "$PRE" --instance "$INST" "$@"; }
run() { # <mode or ""> — the hook for the preflight's own call, then the preflight; prints "<exit> <line>"
  payload "$1" "$CALL" | hook "$INST" >/dev/null 2>&1
  local out rc; out="$(pre --token "$TOK" 2>&1)"; rc=$?
  printf '%s %s' "$rc" "$out"
}
verdict() { printf '%s' "$1" | awk '{ sub(/:.*/, "", $2); print $1, $2 }'; }

echo "== the hook: registered on Bash, records only the preflight's own call =="
ok "hooks.json registers it once, on PreToolUse"  "$(printf '%s\n' "$REGCMD" | grep -c .)" 1
ok "…matched to Bash" \
   "$(jq -r '[.hooks.PreToolUse[] | select(.hooks[].command | test("permission-mode[.]sh")) | .matcher] | join(",")' "$HOOKSJSON")" Bash
ok "the hook file is executable"                  "$(yn test -x "$HOOK")" yes
OUT="$TMP/outside"; mkdir -p "$OUT"
ok "outside an instance: silent"                  "$(payload auto "$CALL" | hook "$OUT" 2>&1 | wc -c | tr -d ' ')" 0
ok "…and no state"                                "$(find "$OUT" -mindepth 1 | grep -c .)" 0
payload auto 'ls -la' | hook "$INST" >/dev/null 2>&1
ok "any other Bash call records nothing"          "$(yn test -e "$INST/$AB_MODE_DIR")" no
jq -nc --arg s "$SID" '{session_id: $s, permission_mode: "auto", tool_input: {command: "ls", description: "spawn-preflight.sh"}}' \
  | hook "$INST" >/dev/null 2>&1
ok "…nor one naming it outside tool_input.command" "$(yn test -e "$INST/$AB_MODE_DIR")" no
payload auto "$CALL" '../../etc' | hook "$INST" >/dev/null 2>&1
ok "a session id that is not an id is refused"    "$(yn test -e "$INST/$AB_MODE_DIR")" no
ok "the preflight's call: stdout empty, never a decision" "$(payload auto "$CALL" | hook "$INST" 2>/dev/null | wc -c | tr -d ' ')" 0
ok "…records the mode under the session id"       "$(awk '{print $2}' "$INST/$AB_MODE_DIR/$SID" 2>/dev/null)" auto
ok "…with the token off that call's command"      "$(awk '{print $3}' "$INST/$AB_MODE_DIR/$SID" 2>/dev/null)" "$TOK"
ok "…and the record stays out of git"             "$(yn git -C "$INST" check-ignore -q "$AB_MODE_DIR/$SID")" yes

echo
echo "== three outcomes: the MODE it read, never a launch outcome it cannot know =="
ok "auto ⇒ auto"                          "$(verdict "$(run auto)")" "1 auto"
ok "default ⇒ not-auto"                   "$(verdict "$(run default)")" "0 not-auto"
ok "bypassPermissions ⇒ not-auto"         "$(verdict "$(run bypassPermissions)")" "0 not-auto"
ok "dontAsk ⇒ not-auto"                   "$(verdict "$(run dontAsk)")" "0 not-auto"
ok "the auto line names auto mode"        "$(yn grep -qF 'auto mode' <<<"$(run auto)")" yes
# Measured 2026-09-30: the classifier judges the brief, not the command, so no mode predicts.
ok "no answer predicts the spawn"         "$(grep -cE 'will-refuse|will-not-refuse' "$PRE" "$S3" | awk -F: '{s+=$2} END {print s}')" 0
ok "…and auto says so on the line"        "$(yn grep -qF 'predicts nothing' <<<"$(run auto)")" yes

echo
echo "== could-not-read is reachable from every cause, and never folded into a pass or a failure =="
cnr() { ok "$1 ⇒ could-not-read" "$(verdict "$2")" "2 could-not-read"; }
cnr "no permission_mode in the payload" "$(run '')"
cnr "an unrecognised mode"              "$(run turbo)"
cnr "a mode that is not a word"         "$(run 'auto; rm')"
payload default "$CALL" | hook "$INST" >/dev/null 2>&1
x="$(env -u CLAUDE_CODE_SESSION_ID bash "$PRE" --instance "$INST" --token "$TOK")"; cnr "no session id in the shell" "$? $x"
x="$(SID_OVERRIDE='../x' pre --token "$TOK")"; cnr "a session id that is not an id" "$? $x"
x="$(SID_OVERRIDE=feedface pre --token "$TOK")"; cnr "no record for this session" "$? $x"
x="$(pre)"; cnr "no --token, so nothing correlates" "$? $x"
x="$(pre --token 'a b')"; cnr "a token that is not a token" "$? $x"
x="$(pre --token deadbeef)"; cnr "the record is another call's" "$? $x"
printf '%s auto %s\n' "$(( $(date +%s) - 120 ))" "$TOK" > "$INST/$AB_MODE_DIR/$SID"
x="$(pre --token "$TOK")"; cnr "a stale record (an earlier call's)" "$? $x"
printf 'garbage\n' > "$INST/$AB_MODE_DIR/$SID"
x="$(pre --token "$TOK")"; cnr "a malformed record" "$? $x"
x="$(CLAUDE_CODE_SESSION_ID="$SID" bash "$PRE" --instance "$TMP/nowhere" --token "$TOK")"; cnr "no hook ever ran" "$? $x"
ok "the reason is on the line"            "$(yn grep -qF 'not set in this shell' <<<"$(env -u CLAUDE_CODE_SESSION_ID bash "$PRE" --instance "$INST" --token "$TOK")")" yes
ok "a usage error is none of the three"   "$(bash "$PRE" --bogus >/dev/null 2>&1; echo $?)" 3

echo
echo "== a REFRESH THAT FAILED never reads as this call's, however recent the record =="
# The record's age proves recency, not that this invocation's hook write landed.
payload auto "$CALL" | hook "$INST" >/dev/null 2>&1
NEXT='${CLAUDE_PLUGIN_ROOT}/scripts/spawn-preflight.sh --instance . --token beef1234'
chmod a-w "$INST/$AB_MODE_DIR"
ok "the hook genuinely cannot write"      "$(yn test -w "$INST/$AB_MODE_DIR")" no
payload default "$NEXT" | hook "$INST" >/dev/null 2>&1
chmod u+w "$INST/$AB_MODE_DIR"
ok "…so the PREVIOUS call's record survives" "$(awk '{print $2, $3}' "$INST/$AB_MODE_DIR/$SID")" "auto $TOK"
ok "…and it is inside the 30s window"     "$(yn test "$(( $(date +%s) - $(awk '{print $1}' "$INST/$AB_MODE_DIR/$SID") ))" -le 30)" yes
x="$(pre --token beef1234)"; cnr "a failed refresh with a recent previous record" "$? $x"
ok "…and says the refresh did not land"   "$(yn grep -qF 'refresh did not land' <<<"$x")" yes

echo
echo "== no probe and no repair: nothing spawned, nothing written =="
mkdir -p "$TMP/bin" "$TMP/home"
printf '#!/bin/sh\necho called >> "%s/claude-calls"\n' "$TMP" > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
payload auto "$CALL" | hook "$INST" >/dev/null 2>&1
: > "$TMP/marker"; sleep 1
CLAUDE_CODE_SESSION_ID="$SID" HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash "$PRE" --instance "$INST" --token "$TOK" >/dev/null 2>&1
ok "no claude invocation, not even a stub"  "$(yn test -e "$TMP/claude-calls")" no
ok "the preflight writes no file anywhere"  "$(find "$TMP" -newer "$TMP/marker" -type f | grep -c .)" 0
ok "neither file names a settings or grant write" \
   "$(grep -cE 'settings(\.local)?\.json|permissions\.allow|defaultMode' "$PRE" "$HOOK" | awk -F: '{s+=$2} END {print s}')" 0

echo
echo "== step 3: the preflight runs before the wave, through task-003's channel =="
pre_at="$(head -n1 <<<"$(grep -n 'scripts/spawn-preflight.sh --instance' "$S3")" | cut -d: -f1)"
write_at="$(head -n1 <<<"$(grep -n 'set `assignee` +' "$S3")" | cut -d: -f1)"
spawn_at="$(head -n1 <<<"$(grep -n 'claude --bg "<the whole brief>"' "$S3")" | cut -d: -f1)"
ok "the preflight is named in step 3"        "$([ -n "$pre_at" ] && echo yes || echo no)" yes
ok "…before the first status write"          "$([ "${pre_at:-999}" -lt "${write_at:-0}" ] && echo yes || echo no)" yes
ok "…and so before the first spawn"          "$([ "${pre_at:-999}" -lt "${spawn_at:-0}" ] && echo yes || echo no)" yes
ok "…with a per-call token"                  "$(yn grep -qF 'spawn-preflight.sh --instance <bundle root> --token <token>' "$S3")" yes
ok "every answer dispatches"                 "$(yn grep -qF '**Dispatch on every answer**' "$S3")" yes
ok "…so no answer skips the wave"            "$(grep -ciE 'dispatch nothing this tick|never skips the wave' "$S3" | tr -d ' ')" 1
ok "the mode predicts nothing, and step 3 says so" "$(yn grep -qF 'no mode predicts a refusal' "$S3")" yes
ok "could-not-read is neither a pass nor a failure" "$(yn grep -qF 'never a pass and never a failure' "$S3")" yes
ok "the preflight writes no grant entry"     "$(yn grep -qF 'preflight writes no `open_questions` entry' "$S3")" yes
ok "ONE entry shape: task-003's"             "$(grep -c 'Q<n>: dispatch refused: ' "$S3" | tr -d ' ')" 1
ok "the remedy is stated once, in one place" \
   "$(grep -rlF 'check the spawn asked for --permission-mode auto' "$REPO/plugin" | sed "s|$REPO/||" | tr '\n' ' ')" "plugin/tick-steps/step-3-dispatch.md "
row1="$(awk '/\| The text carries \|/ { t = 1; next } t && /^[[:space:]]*\|---/ { next } t { print; exit }' "$S3")"
cell() { printf '%s' "$row1" | awk -F' [|] ' -v n="$1" '{ gsub(/^[[:space:]]*[|] | [|][[:space:]]*$/, ""); print $n }' | sed 's/^`//; s/`$//'; }
which="$(cell 2)"; remedy="$(cell 3)"
line_tpl="$(head -n1 <<<"$(sed -n 's/^[[:space:]]*\(dispatch refused: <which>\. .*\)$/\1/p' "$S3")")"
line="${line_tpl//<which>/$which}"; line="${line//<remedy>/$remedy}"; line="${line//<k>/3}"
ok "the report line template is there"       "$([ -n "$line_tpl" ] && echo yes || echo no)" yes
ok "…carrying the remedy: the spawn's own mode" "$(yn grep -qF 'asked for --permission-mode auto' <<<"$line")" yes
ok "…and never telling the operator to leave auto mode" "$(yn grep -qF 'shift+tab' <<<"$line")" no
ok "…never a claude --bg or bypass grant"    "$(yn grep -qE 'claude --bg|bypassPermissions' <<<"$line")" no
ok "…never a cap"                            "$( { grep -qiw 'cap' || grep -qiE 'in[- ]flight'; } <<<"$line" && echo yes || echo no)" no
entry_tpl="$(head -n1 <<<"$(sed -n 's/^[[:space:]]*\(Q<n>: dispatch refused: .*\)$/\1/p' "$S3")")"
entry="${entry_tpl//<n>/1}"; entry="${entry//<which>/$which}"; entry="${entry//<remedy>/$remedy}"
D="$TMP/aw"; mkdir -p "$D/projects/demo/tasks" "$D/$AB_DIR"; printf '{ "org": "demo" }\n' > "$D/instance.config.json"
printf '# SCHEMA\n' > "$D/$AB_SCHEMA"; : > "$D/$AB_AWAITING"
printf -- '---\ntype: Project\ntitle: "Demo"\nstatus: active\n---\n' > "$D/projects/demo/project.md"
printf -- '---\ntype: Task\ntitle: "First"\nkind: build\nstatus: ready\nacceptance_criteria: [ "x" ]\nopen_questions: [ "%s" ]\n---\n' \
  "$entry" > "$D/projects/demo/tasks/task-001-a.md"
bash "$AW" --instance "$D" >/dev/null 2>&1
ok "task-003's entry still renders as one grant row" "$(grep -c '^\* 🧰 \*\*grant\*\* — \[First\]' "$D/$AB_AWAITING" | tr -d ' ')" 1

echo
echo "spawn-preflight.test: $pass passed, $fail failed"
[ "$fail" = 0 ]
