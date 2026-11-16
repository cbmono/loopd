#!/usr/bin/env bash
#
# pr-title.sh — PreToolUse hook (Bash). Refuses a `gh pr create` whose `--title` breaks
# CONVENTIONS.md → "Branch, commit and title": `<type>: <subject>`, then nothing when
# `ticketPrefix` is absent or not Jira-shaped, else exactly ` [<PREFIX>-<n>]`.
# A title it cannot read (a variable, an escape, none at all) is allowed; so is every
# plumbing failure. Outside a bundle or a worktree `link-repos.sh` marked: silent, exit 0.
# A refusal is JSON on stdout; exit 0 always. Reasoning: all-code-is-slop-lessons/task-009.
# Verified by tests/pr-title-hook.test.sh.
set -uo pipefail

INSTANCE_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INSTANCE_ROOT="$(cd "$INSTANCE_ROOT" 2>/dev/null && pwd -P || printf '%s' "$INSTANCE_ROOT")"
if [ ! -f "$INSTANCE_ROOT/instance.config.json" ] && [ -f "$INSTANCE_ROOT/.git" ]; then
  _gd=""; IFS= read -r _gd < "$INSTANCE_ROOT/.git" 2>/dev/null || _gd=""
  _gd="${_gd#gitdir:}"; _gd="${_gd# }"
  case "$_gd" in ""|/*) ;; *) _gd="$INSTANCE_ROOT/$_gd" ;; esac
  _cd="$_gd"
  if [ -n "$_gd" ] && [ -f "$_gd/commondir" ]; then
    _c=""; IFS= read -r _c < "$_gd/commondir" 2>/dev/null || _c=""
    case "$_c" in "") ;; /*) _cd="$_c" ;; *) _cd="$_gd/$_c" ;; esac
  fi
  if [ -n "$_cd" ] && [ -f "$_cd/loopd-bundle" ]; then
    _b=""; IFS= read -r _b < "$_cd/loopd-bundle" 2>/dev/null || _b=""
    if [ -n "$_b" ] && [ -f "$_b/instance.config.json" ]; then
      INSTANCE_ROOT="$(cd "$_b" 2>/dev/null && pwd -P || printf '%s' "$_b")"
    fi
  fi
fi
[ -f "$INSTANCE_ROOT/instance.config.json" ] || exit 0

payload="$(cat 2>/dev/null || true)"
case "$payload" in *gh*pr*create*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0

prefix="$(jq -r '.ticketPrefix // "" | strings' "$INSTANCE_ROOT/instance.config.json" 2>/dev/null)" || exit 0
[[ "$prefix" =~ ^[A-Z][A-Z0-9_]+$ ]] || prefix=""

reason="$(printf '%s' "$payload" | jq -r --arg p "$prefix" '
  def stop: "(?=[\\s;&|)]|\\z)";
  (.tool_input.command // "" | strings) as $c
  | ($c | capture("(?:^|[;&|(\\n])\\s*gh\\s+pr\\s+create(?<rest>(?:\\s[\\s\\S]*)?)\\z").rest) as $rest
  | ($rest | capture("\\s(?:--title|-t)(?:=|\\s+)(?:\"(?<d>[^\"\\\\$`]*)\"" + stop
      + "|\u0027(?<s>[^\u0027]*)\u0027" + stop
      + "|(?<b>[^\\s\u0027\"\\\\$`;&|()<>]+)" + stop + ")")) as $m
  | ($m.d // $m.s // $m.b) as $t
  | ($t | sub("\\s+\\z"; "")) as $t
  | "^[a-z]+(\\([^()\\s]+\\))?!?: \\S" as $head
  | " \\[[^\\]]*\\]\\z" as $tag
  | (if $p == "" then ($t | test($head)) and ($t | test($tag) | not)
     else ($t | test($head + "[\\s\\S]* \\[" + $p + "-[0-9]+\\]\\z"))
          and ($t | sub(" \\[" + $p + "-[0-9]+\\]\\z"; "") | test($tag) | not) end) as $ok
  | if $ok then empty
    else "PR title `\($t)` breaks the title rule (CONVENTIONS.md → \"Branch, commit and title\"), which wants "
      + (if $p == "" then "`<type>: <subject>` and nothing after it — ticketPrefix is none, so no bracketed tag."
         else "`<type>: <subject> [\($p)-<n>]`, `[\($p)-0]` when the task names no ticket, and no other tag." end)
      + " Re-run `gh pr create` with a title in that shape." end
' 2>/dev/null)" || exit 0
[ -n "$reason" ] || exit 0

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
