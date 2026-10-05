#!/usr/bin/env bash
#
# report-clearance.test.sh — the tick report's three-part shape is refused by a reader, not
# requested by prose: plugin/scripts/report-clearance.sh decides, and plugin/hooks/report-shape.sh
# runs it on SubagentStop over the project-manager's final message.
#
# Every refusal fixture in tests/fixtures/report-clearance/ is named for the criterion it
# pins and asserted with its RULE, not only its exit code; the clean fixtures are the
# controls. c4-known-miss-no-word.md is asserted to CLEAR — it is the documented miss.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/report-clearance.sh"
HOOK="$REPO/plugin/hooks/report-shape.sh"
FIX="$REPO/tests/fixtures/report-clearance"
PM="$REPO/plugin/agents/project-manager.md"
[ -x "$SCRIPT" ] && [ -x "$HOOK" ] || { echo "report-clearance.test: script or hook not executable" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/report-clearance.XXXXXX")" || {
  echo "report-clearance.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

# verdict <fixture> → "<exit> <rules, sorted, unique>"
verdict() {
  local out rc
  out="$("$SCRIPT" --body-file "$FIX/$1")"; rc=$?
  printf '%s %s' "$rc" "$(sed -n 's/^REFUSED \([a-z]*\):.*/\1/p' <<<"$out" | sort -u | tr '\n' ' ' | sed 's/ $//')"
}

echo "-- the checker runs"
ok "self-test"                    "$("$SCRIPT" --self-test >/dev/null 2>&1; echo $?)" 0
head -n 20 "$SCRIPT" > "$TMP/truncated.sh"; chmod +x "$TMP/truncated.sh"
ok "…and refuses a truncated copy" "$("$TMP/truncated.sh" --self-test >/dev/null 2>&1; echo $?)" 2
ok "no file ⇒ exit 2"              "$("$SCRIPT" --body-file "$TMP/absent" >/dev/null 2>&1; echo $?)" 2

echo "-- controls clear"
ok "clean: what happened, Blocking:, Needs you:, BOARD:" "$(verdict clean.md)" "0 "
ok "clean: an IDLE: line alone"                          "$(verdict clean-idle.md)" "0 "
ok "clean: nothing needed, no Needs you: at all"         "$(verdict clean-nothing-needed.md)" "0 "

echo "-- criterion 2: the shape"
ok "Blocking: nothing is refused"            "$(verdict c2-blocking-says-nothing.md)" "1 shape"
ok "a numbered list with no Needs you:"       "$(verdict c2-list-without-header.md)" "1 outside"
ok "numbering that skips"                    "$(verdict c2-numbering-skips.md)" "1 shape"

echo "-- criterion 3: the precedence check fails both 2026-09-28 reports"
ok "(a) 'Stop the finished agents first' at item 2"     "$(verdict c3a-stop-agents-first.md)" "1 precedence"
ok "(b) a grant item below the item it unblocks"        "$(verdict c3b-grant-below-unblocked.md)" "1 precedence"
ok "…while 'after CI is green' at item 3 clears (clean.md)" "$(grep -c 'after CI is green' "$FIX/clean.md")" 1

echo "-- criterion 4: the word list is a detector, and its miss is pinned"
ok "an inversion using none of the four words CLEARS (known miss)" "$(verdict c4-known-miss-no-word.md)" "0 "
ok "…the shipped text says it is a detector"  "$(has "$PM" '**The order check is a detector, not the rule.** The rule is dependency.')" yes
ok "…and that a clear report is not proof"    "$(has "$PM" 'a clear report is not proof the order is right')" yes

echo "-- criterion 5: every item"
ok "no URL or path"           "$(verdict c5-no-link.md)" "1 item"
ok "not an imperative"        "$(verdict c5-not-imperative.md)" "1 item"
ok "no why"                   "$(verdict c5-no-why.md)" "1 item"
ok "a choice, not a recommendation" "$(verdict c5-choice.md)" "1 item"
ok "two actions"              "$(verdict c5-two-actions.md)" "1 item"

echo "-- criterion 6: reasoning is refused, and the text says where it goes"
ok "a Steps taken: list"      "$(verdict c6-steps-taken.md)" "1 outside reasoning"
ok "alternatives in the outcome" "$(verdict c6-alternatives.md)" "1 reasoning"
ok "an outcome past 2 sentences" "$(verdict c6-long-outcome.md)" "1 reasoning"
ok "…reasoning goes to the task document, commit or Finding" \
   "$(has "$PM" 'go in the task document, the commit message or a `Finding`')" yes

echo "-- criterion 1: the binding point is SubagentStop, and it acts"
ok "hooks.json registers report-shape.sh on SubagentStop" \
   "$(jq -r '[.hooks.SubagentStop[].hooks[].command] | index("\"${CLAUDE_PLUGIN_ROOT}/hooks/report-shape.sh\"") != null' "$REPO/plugin/hooks/hooks.json")" true
INST="$TMP/inst"; mkdir -p "$INST"; echo '{}' > "$INST/instance.config.json"
payload() { # <fixture|-> <agent_type> <stop_hook_active> [<agent_id>]
  if [ "$1" = - ]; then jq -cn --arg t "$2" --argjson a "$3" --arg i "${4:-a1}" \
    '{hook_event_name:"SubagentStop",agent_id:$i,agent_type:$t,stop_hook_active:$a}'
  else jq -cn --rawfile m "$FIX/$1" --arg t "$2" --argjson a "$3" --arg i "${4:-a1}" \
    '{hook_event_name:"SubagentStop",agent_id:$i,agent_type:$t,stop_hook_active:$a,last_assistant_message:$m}'; fi
}
hook() { # <dir> → "<exit>|<what stdout carried>|<what stderr carried>"
  local o e rc
  o="$(TMPDIR="$TMP" CLAUDE_PROJECT_DIR="$1" "$HOOK" 2>"$TMP/err")"; rc=$?
  e="$(cat "$TMP/err")"
  case "$o" in
    '') o=silent ;;
    '{"systemMessage":"loopd: this tick report failed its shape check twice'*) o=went-out-flagged ;;
    '{"systemMessage":"loopd: the tick report went out unchecked'*) o=unchecked-flagged ;;
    *) o=other ;;
  esac
  case "$e" in
    '') e=silent ;;
    'Your report was refused.'*REFUSED*) e=rewrite-with-reasons ;;
    *) e=other ;;
  esac
  printf '%s|%s|%s' "$rc" "$o" "$e"
}
ok "inverted tick report ⇒ exit 2, sent back to rewrite" \
   "$(payload c3a-stop-agents-first.md loopd:project-manager false a2 | hook "$INST")" "2|silent|rewrite-with-reasons"
ok "…refused again ⇒ passes, systemMessage to the human" \
   "$(payload c3a-stop-agents-first.md loopd:project-manager false a2 | hook "$INST")" "0|went-out-flagged|silent"
ok "stop_hook_active ⇒ never a second block" \
   "$(payload c3a-stop-agents-first.md loopd:project-manager true a3 | hook "$INST")" "0|went-out-flagged|silent"
ok "a clean tick report ⇒ silent"   "$(payload clean.md loopd:project-manager false a4 | hook "$INST")" "0|silent|silent"
ok "any other agent ⇒ silent"       "$(payload c3a-stop-agents-first.md loopd:qa-reviewer false a5 | hook "$INST")" "0|silent|silent"
ok "outside an instance ⇒ silent"   "$(payload c3a-stop-agents-first.md loopd:project-manager false a6 | hook "$TMP")" "0|silent|silent"
ok "no last_assistant_message ⇒ unchecked, and says so" \
   "$(payload - loopd:project-manager false a7 | hook "$INST")" "0|unchecked-flagged|silent"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
