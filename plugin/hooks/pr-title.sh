#!/usr/bin/env bash
#
# pr-title.sh — PreToolUse hook (Bash). Refuses a `gh pr create` whose `--title` breaks
# CONVENTIONS.md → "Branch, commit and title": `<type>: <subject>`, then nothing when
# `ticketPrefix` is absent or not Jira-shaped, else exactly ` [<PREFIX>-<n>]`; no task id.
# A title it cannot read (a variable, an escape, an open quote or heredoc) is allowed, as is
# every plumbing failure. Outside a bundle or a worktree `link-repos.sh` marked: silent.
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

IFS= read -r -d '' prog <<'JQ' || true
def word: "(?:\"[^\"]*\"|'[^']*'|[^\\s'\";&|()<>])+";
def title_of:
  if test("[$`\\\\]") then null
  else [scan("\"([^\"]*)\"|'([^']*)'|([^\"']+)") | .[0] // .[1] // .[2]] | add // "" end;
def commands:
  gsub("\\\\\n"; " ")
  | gsub("<<-?[ \\t]*(?<q>['\"]?)(?<d>[A-Za-z_][A-Za-z0-9_]*)\\k<q>(?<l>[^\\n]*)\\n[\\s\\S]*?\\n[ \\t]*\\k<d>(?=\\n|\\z)"; " \(.l)")
  | if test("(^|[^<])<<(?!<)") then error("heredoc")
    elif test("^(?:\\s|[0-9]*[<>]+&?[0-9-]*|;|&&?|\\|\\|?|\\(|\\)|" + word + ")*\\z") | not then error("unbalanced")
    else [scan("(?<r>[0-9]*[<>]+&?[0-9-]*)|(?<s>\\n|;|&&?|\\|\\|?|\\(|\\))|(?<w>" + word + ")")]
      | reduce .[] as $t ([[]];
          if $t[1] != null then . + [[]] elif $t[2] != null then .[-1] += [$t[2]] else . end)
      | map((index(map(select(startswith("#")))[0]) // null) as $h
            | if $h then .[:$h] else . end
            | until(length == 0 or (.[0] | test("^[A-Za-z_][A-Za-z0-9_]*=") | not); .[1:]))
    end;
def titles:
  commands[] | select(.[0:3] == ["gh", "pr", "create"]) | .[3:]
  | [foreach range(length) as $i (.; .;
      if .[$i] == "--title" or .[$i] == "-t" then .[$i + 1]
      elif .[$i] | startswith("--title=") then .[$i][8:]
      else empty end)]
  | last | select(. != null) | title_of | select(. != null) | sub("\\s+\\z"; "");
def ok($p):
  "^[a-z]+(\\([^()\\s]+\\))?!?: \\S" as $head | " \\[[^\\]]*\\]\\z" as $tag
  | (test("(?i)\\btask-[0-9]+\\b") | not)
    and if $p == "" then test($head) and (test($tag) | not)
        else test($head + "[\\s\\S]* \\[" + $p + "-[0-9]+\\]\\z")
          and (sub(" \\[" + $p + "-[0-9]+\\]\\z"; "") | test($tag) | not) end;
[.tool_input.command // "" | strings | try titles catch empty | select(ok($p) | not)][0] // empty
| "PR title `\(.)` breaks the title rule (CONVENTIONS.md → \"Branch, commit and title\"), which wants "
  + (if $p == "" then "`<type>: <subject>` and nothing after it — ticketPrefix is none, so no bracketed tag"
     else "`<type>: <subject> [\($p)-<n>]`, `[\($p)-0]` when the task names no ticket, and no other tag" end)
  + ", and no OKF task id anywhere. Re-run `gh pr create` with a title in that shape."
JQ
reason="$(printf '%s' "$payload" | jq -r --arg p "$prefix" "$prog" 2>/dev/null)" || exit 0
[ -n "$reason" ] || exit 0

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
