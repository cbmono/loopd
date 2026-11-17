#!/usr/bin/env bash
#
# review-request.sh — PreToolUse hook (Bash). Reports, never refuses, a `gh pr comment` or a POST
# `gh api …/issues|pulls/<n>/comments` whose body carries `@coderabbitai review` when the PR already
# has a comment carrying it (CONVENTIONS.md → "Ask for the independent review once, at the head
# you consider final"). Selector, `--repo` and body come from that one `gh` invocation;
# one `gh pr view` read per matching call; bot comments are not counted.
# An unreadable PR, and every plumbing failure, is silent. Outside a bundle or a worktree
# `link-repos.sh` marked: silent. The report is JSON on stdout; exit 0 always.
# Reasoning: all-code-is-slop-lessons/task-011. Verified by tests/review-request-hook.test.sh.
set -uo pipefail

INSTANCE_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INSTANCE_ROOT="$(cd "$INSTANCE_ROOT" 2>/dev/null && pwd -P || printf '%s' "$INSTANCE_ROOT")"
if [ ! -f "$INSTANCE_ROOT/instance.config.json" ] && [ -f "$INSTANCE_ROOT/.git" ]; then
  _gd=""; IFS= read -r _gd 2>/dev/null < "$INSTANCE_ROOT/.git" || _gd=""
  _gd="${_gd#gitdir:}"; _gd="${_gd# }"
  case "$_gd" in ""|/*) ;; *) _gd="$INSTANCE_ROOT/$_gd" ;; esac
  _cd="$_gd"
  if [ -n "$_gd" ] && [ -f "$_gd/commondir" ]; then
    _c=""; IFS= read -r _c 2>/dev/null < "$_gd/commondir" || _c=""
    case "$_c" in "") ;; /*) _cd="$_c" ;; *) _cd="$_gd/$_c" ;; esac
  fi
  if [ -n "$_cd" ] && [ -f "$_cd/loopd-bundle" ]; then
    _b=""; IFS= read -r _b 2>/dev/null < "$_cd/loopd-bundle" || _b=""
    if [ -n "$_b" ] && [ -f "$_b/instance.config.json" ]; then
      INSTANCE_ROOT="$(cd "$_b" 2>/dev/null && pwd -P || printf '%s' "$_b")"
    fi
  fi
fi
[ -f "$INSTANCE_ROOT/instance.config.json" ] || exit 0

payload="$(cat 2>/dev/null || true)"
case "$payload" in *@coderabbitai\ review*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
target="$(printf '%s' "$payload" | jq -r '
  def words: gsub("\\\\\\n"; " ")
    | [scan("(?:\"(?:[^\"\\\\]|\\\\.)*\"|\u0027[^\u0027]*\u0027|[^\\s\u0027\";&|()])+|[;&|()\\n]+")];
  def unq: gsub("\"(?<a>(?:[^\"\\\\]|\\\\.)*)\"|\u0027(?<b>[^\u0027]*)\u0027"; "\(.a // .b)");
  def cmds: reduce words[] as $w ([[]];
    if ($w | test("^[;&|()\\n]+$")) then . + [[]] else .[length - 1] += [$w | unq] end);
  def parse($vf): . as $a
    | reduce range(0; $a | length) as $i ({pos: [], o: [], skip: false};
        if .skip then .skip = false
        else $a[$i] as $t
        | if ($t | test("^--?[A-Za-z][A-Za-z-]*=")) then
            ($t | capture("^(?<f>--?[A-Za-z][A-Za-z-]*)=(?<v>[\\s\\S]*)\\z")) as $m | .o += [[$m.f, $m.v]]
          elif any($vf[]; . == $t) then .o += [[$t, ($a[$i + 1] // "")]] | .skip = true
          elif ($t | startswith("-")) then .o += [[$t, true]]
          else .pos += [$t] end
        end);
  "@coderabbitai review" as $T
  | (.tool_input.command // "" | strings) as $c
  | first($c | cmds[] | select(length >= 2 and .[0] == "gh")
    | if .[1:3] == ["pr", "comment"] then
        (.[3:] | parse(["-b", "--body", "-F", "--body-file", "-R", "--repo"])) as $p
        | select(any($p.o[]; (.[0] == "-b" or .[0] == "--body") and (.[1] | strings | contains($T))))
        | select(all($p.o[]; .[0] != "--delete-last"))
        | "\($p.pos[0] // "")|\([$p.o[] | select(.[0] == "-R" or .[0] == "--repo") | .[1] | strings] | last // "")"
      elif .[1] == "api" then
        (.[2:] | parse(["-f", "--raw-field", "-F", "--field", "-H", "--header", "-X", "--method",
                        "--input", "-q", "--jq", "-t", "--template", "-p", "--preview", "--hostname", "--cache"])) as $p
        | select(([$p.o[] | select(.[0] == "-X" or .[0] == "--method") | .[1] | strings | ascii_upcase] | last // "POST") == "POST")
        | select(any($p.o[]; (.[0] | test("^(-f|-F|--field|--raw-field)$")) and (.[1] | strings | startswith("body=") and contains($T))))
        | ($p.pos[0] // "" | capture("^/?repos/(?<o>[^/]+)/(?<r>[^/]+)/(?:issues|pulls)/(?<n>[0-9]+)/comments$")) as $e
        | "\($e.n)|\(if $e.o == "{owner}" then "" else "\($e.o)/\($e.r)" end)"
      else empty end)
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
