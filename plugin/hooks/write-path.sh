#!/usr/bin/env bash
#
# write-path.sh — PreToolUse hook (Write|Edit). In a session rooted in a linked worktree of
# a repo link-repos.sh marked, reports a write outside that worktree, the bundle's
# knowledge/ and the projects/<slug>/ of the task whose `worktree:` names it (any
# projects/<slug>/ when no task does). A report, never a decision: systemMessage plus
# additionalContext, no permissionDecision. Exit 0 always. Every other session, the main
# one included, is silent: no output, no state.
# Rule: seed/CONVENTIONS.md "Parallel-safety", "Where files go". Test: tests/write-path.test.sh.
set -u

raw="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$raw/.git" ] || exit 0
wt="$(cd "$raw" 2>/dev/null && pwd -P)" || exit 0
[ -f "$wt/instance.config.json" ] && exit 0

# The marker walk is the one in deny-destructive.sh: .git file → gitdir → commondir → marker.
gd=""; IFS= read -r gd < "$wt/.git" 2>/dev/null || exit 0
gd="${gd#gitdir:}"; gd="${gd# }"
case "$gd" in "") exit 0 ;; /*) ;; *) gd="$wt/$gd" ;; esac
cd_="$gd"
if [ -f "$gd/commondir" ]; then
  c=""; IFS= read -r c < "$gd/commondir" 2>/dev/null || c=""
  case "$c" in "") ;; /*) cd_="$c" ;; *) cd_="$gd/$c" ;; esac
fi
[ -f "$cd_/loopd-bundle" ] || exit 0
b=""; IFS= read -r b < "$cd_/loopd-bundle" 2>/dev/null || exit 0
[ -n "$b" ] && [ -f "$b/instance.config.json" ] || exit 0
b="$(cd "$b" 2>/dev/null && pwd -P)" || exit 0

command -v jq >/dev/null 2>&1 || exit 0
payload="$(cat 2>/dev/null || true)"
fp="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -n "$fp" ] || exit 0
tool="$(printf '%s' "$payload" | jq -r '.tool_name // "Write"' 2>/dev/null)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"

# Lexically drop . and .., then resolve the deepest existing ancestor physically, so a
# file not written yet and /tmp → /private/tmp both compare against pwd -P prefixes.
abspath() {
  local p="$1" out="" seg d rest=""
  case "$p" in /*) ;; *) p="${cwd:-$wt}/$p" ;; esac
  local segs; IFS=/ read -ra segs <<<"$p"
  for seg in ${segs[@]+"${segs[@]}"}; do
    case "$seg" in ""|.) ;; ..) out="${out%/*}" ;; *) out="$out/$seg" ;; esac
  done
  d="${out:-/}"
  while [ ! -d "$d" ]; do rest="/${d##*/}$rest"; d="${d%/*}"; [ -n "$d" ] || d=/; done
  d="$(cd "$d" 2>/dev/null && pwd -P)" || d="${out%/*}"
  printf '%s%s' "${d%/}" "$rest"
}
under() { case "$1/" in "$2"/*) return 0 ;; esac; return 1; }
phys() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

p="$(abspath "$fp")"
under "$p" "$wt" && exit 0
under "$p" "$(phys "$b/knowledge")" && exit 0

task=""
for f in "$b"/projects/*/tasks/*.md; do
  [ -f "$f" ] || continue
  v="$(sed -n 's/^worktree:[[:space:]]*//p' "$f" | head -1 | tr -d "\"'")"
  v="${v%/}"
  if [ -n "$v" ] && { [ "$v" = "$raw" ] || [ "$v" = "${raw%/}" ] || [ "$v" = "$wt" ]; }; then task="$f"; break; fi
done
if [ -n "$task" ]; then
  under "$p" "$(phys "${task%/tasks/*}")" && exit 0
else
  under "$p" "$(phys "$b/projects")" && exit 0
fi

shown="$(printf '%s' "$p" | tr -d '\000-\037')"
msg="loopd write-path: $tool to $shown is outside this worktree, its task's projects/<slug>/ and the bundle's knowledge/ — CONVENTIONS.md → \"Where files go\". Reported, not refused."
jq -cn --arg m "$msg" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
