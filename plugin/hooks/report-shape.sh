#!/usr/bin/env bash
#
# report-shape.sh — SubagentStop hook (loopd PLUGIN). Runs a project-manager tick's final
# message (`last_assistant_message`) through report-clearance.sh before the launcher
# relays it. Refused the first time ⇒ exit 2: the tick is sent back to rewrite it. Refused
# again ⇒ it goes out as written with a systemMessage naming what failed, so a detector's
# false positive costs one rewrite and can never loop a tick. Every other agent type: exit 0.
# Silent (no output, no state) outside an instance — a plugin hook fires in every session.
# Reasoning: dispatch-reporting-defects/task-006.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
root="$(cd "$root" 2>/dev/null && pwd -P || printf '%s' "$root")"
[ -f "$root/instance.config.json" ] || exit 0

payload="$(cat)"
command -v jq >/dev/null 2>&1 || { echo "loopd report-shape: jq not found — the tick report went out unchecked" >&2; exit 1; }
field() { printf '%s' "$payload" | jq -r "$1" 2>/dev/null; }
type="$(field '.agent_type // ""')"
[ "${type##*:}" = project-manager ] || exit 0

say() { jq -cn --arg m "$1" '{systemMessage: $m}'; exit 0; }
[ "$(field 'has("last_assistant_message")')" = true ] \
  || say "loopd: the tick report went out unchecked — this Claude Code sends no last_assistant_message on SubagentStop."

mark="${TMPDIR:-/tmp}/loopd-report-shape.$(field '.agent_id // ""' | tr -cd 'A-Za-z0-9_-')"
verdict="$(field '.last_assistant_message' | "$(dirname "${BASH_SOURCE[0]}")/../scripts/report-clearance.sh" --body-file -)"
case $? in
  0) rm -f "$mark"; exit 0 ;;
  1) if [ "$(field '.stop_hook_active')" != true ] && [ ! -e "$mark" ]; then
       : > "$mark"
       printf '%s\n%s\n' "Your report was refused. Rewrite it as: what happened (≤2 sentences), Blocking: only if something is, then a numbered Needs you: list — one imperative per item, its URL or path inline, and one clause of why after ' — '. Reasoning and steps go in the task document, the commit message or a Finding, never the report." "$verdict" >&2
       exit 2
     fi
     rm -f "$mark"
     say "loopd: this tick report failed its shape check twice and went out as written:
$verdict" ;;
  *) say "loopd: report-clearance.sh failed — the tick report went out unchecked." ;;
esac
