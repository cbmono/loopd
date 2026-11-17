#!/usr/bin/env bash
#
# review-request.sh — PreToolUse hook (Bash). Reports, never refuses, a `gh pr comment` or a
# `gh api …/issues|pulls/<n>/comments` call carrying `@coderabbitai review` when the PR already
# has a comment carrying it (CONVENTIONS.md → "Ask for the independent review once, at the head
# you consider final"). One `gh pr view` read per matching call; bot comments are not counted.
# An unreadable PR, and every plumbing failure, is silent. Outside a bundle or a worktree
# `link-repos.sh` marked: silent. The report is JSON on stdout; exit 0 always.
# Reasoning: all-code-is-slop-lessons/task-011. Verified by tests/review-request-hook.test.sh.
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
case "$payload" in *@coderabbitai\ review*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

target="$(printf '%s' "$payload" | jq -r '
  def tok: "[\u0027\"]?(?<s>[A-Za-z0-9_][A-Za-z0-9_./:#-]*)[\u0027\"]?(?=\\s|\\z)";
  (.tool_input.command // "" | strings) as $c
  | select($c | contains("@coderabbitai review"))
  | ($c | capture("(?:^|[;&|(\\n])\\s*gh\\s+(?<sub>pr\\s+comment|api)(?<rest>(?:\\s[\\s\\S]*)?)\\z")) as $m
  | if ($m.sub | startswith("pr")) then
      ((($m.rest | capture("^\\s+" + tok)).s) // "") + "|"
      + ((($m.rest | capture("\\s(?:--repo|-R)(?:=|\\s+)[\u0027\"]?(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)")).r) // "")
    else
      ($m.rest | capture("(?:^|[\\s\u0027\"=])/?repos/(?<o>[^/\\s\u0027\"]+)/(?<r>[^/\\s\u0027\"]+)/(?:issues|pulls)/(?<n>[0-9]+)/comments")) as $p
      | $p.n + "|" + (if $p.o == "{owner}" then "" else "\($p.o)/\($p.r)" end)
    end
' 2>/dev/null)" || exit 0
[ -n "$target" ] || exit 0
sel="${target%%|*}"; repo="${target#*|}"
case "$sel$repo" in *[!A-Za-z0-9_./:#-]*) exit 0 ;; esac
cwd="$(printf '%s' "$payload" | jq -r '.cwd // "" | strings' 2>/dev/null)" || cwd=""
[ -d "$cwd" ] || cwd="$PWD"

comments="$(cd "$cwd" 2>/dev/null && GH_PROMPT_DISABLED=1 gh pr view ${sel:+"$sel"} ${repo:+--repo "$repo"} --json comments 2>/dev/null)" || exit 0
n="$(printf '%s' "$comments" | jq -r '
  [.comments[]? | select((.author.login // "") | test("coderabbit|\\[bot\\]$"; "i") | not)
   | select((.body // "") | contains("@coderabbitai review"))] | length' 2>/dev/null)" || exit 0
case "$n" in ''|0|*[!0-9]*) exit 0 ;; esac

msg="This PR already carries $n \`@coderabbitai review\` comment(s); this call adds another. CONVENTIONS.md → \"Ask for the independent review once, at the head you consider final\": once per PR, never after a fix commit — ask again only when a rewrite invalidated the review. Not refused."
jq -n --arg r "$msg" '{
  systemMessage: $r,
  hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $r }
}'
exit 0
