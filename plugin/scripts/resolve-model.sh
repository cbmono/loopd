#!/usr/bin/env bash
#
# resolve-model.sh — print the model alias a given agent should run on.
#
#   Usage: resolve-model.sh <agent-name> [--instance DIR]
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A SENTENCE.
# `roleTiers`/`models` lived only as prose in SCHEMA.md, project-manager.md,
# advisor.md (an agent since retired), audit.md and the loop's step file — five files telling an agent to go and
# look something up, and NO code that read it. So the config governed exactly the dispatch
# paths whose markdown happened to mention it (the /<plugin>:dispatch tick, the PM's own
# dispatches) and nothing else. Every ad-hoc `Agent` dispatch from a main session — a
# documented, legitimate mode — silently ignored it, because the Agent tool takes its
# model from its own parameter, else the agent's frontmatter, else the parent. Measured
# 2026-08-28: three separate sessions each reported, independently, that they had not
# consulted the file.
#
# A rule in prose is obeyed where somebody remembered to obey it. This makes it
# answerable by one command, so "what model should X run on" has a mechanical answer
# any caller can get without reading five documents.
#
# RESOLUTION ORDER:
#   roleTiers[<agent>]  ->  a tier name (light|standard|deep|apex)
#   models[<tier>]      ->  an alias (e.g. sonnet)
#
# ABSENCE IS NOT AN ERROR, BUT IT IS NEVER SILENT — and that distinction is the whole
# point of this block. An agent with no `roleTiers` entry, or a tier with no `models`
# entry, still prints NOTHING on stdout and still exits 1, because every caller captures
# stdout and a word printed there becomes a model alias. What changed is stderr: it now
# says which agent, which lookup failed, in which two files, and what a caller that
# ignores the exit code will actually do — INHERIT THE SESSION MODEL. Exiting quietly was
# the failure shape, not the fallback: an unresolved role is indistinguishable from a
# resolved one at the call site, so every role can quietly run on the wrong tier and
# nothing anywhere says so. The line is what makes that visible; it costs nothing when
# resolution succeeds, since it is only ever printed on the way out. Never guess an alias.
#
# Both keys are read from `instance.config.local.json` FIRST and the tracked
# `instance.config.json` second, per entry. THAT RULE IS NOT WRITTEN HERE: it lives in
# `resolve-config.sh`, which this delegates to, because the session banner needs
# the same precedence plus the answer to "which file won" and a second copy of the merge
# is how the two would come to disagree. This file owns the two-step lookup below and the
# contract that absence is not an error; precedence is that file's.
set -uo pipefail
_pn="$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"; if [ -r "$_pn" ]; then . "$_pn"; fi

agent=""; inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--instance` leaves one argument, and
    # `shift 2` then FAILS WITHOUT SHIFTING. With no `set -e` that returns to the top
    # of the loop with the same argv and spins forever — verified by running it.
    --instance)
      [ $# -ge 2 ] || { echo "resolve-model: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    -h|--help) sed -n '3,5p' "$0"; exit 0 ;;
    -*) echo "resolve-model: unknown flag $1" >&2; exit 2 ;;
    *) agent="$1"; shift ;;
  esac
done
[ -n "$agent" ] || { echo "Usage: resolve-model.sh <agent-name> [--instance DIR]" >&2; exit 2; }

# THE SELF PATH IS RESOLVED THROUGH THE SYMLINK, and that is load-bearing rather than
# tidy. A bundle carries no machinery at all now, so an
# instance stamped BEFORE `resolve-config.sh` shipped has no such file in its own
# `scripts/` — a plain `dirname "$0"` would look there, miss it, and break a resolver that
# worked yesterday. `readlink` lands in the template that is actually executing, where the
# helper is guaranteed to sit beside this file. (The same idiom check-machinery.sh uses to
# name the template's current location.)
self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
resolver="$here/resolve-config.sh"
[ -n "$here" ] && [ -f "$resolver" ] || {
  echo "resolve-model: resolve-config.sh not found beside this script" >&2; exit 2; }

# roleTiers[<agent>] -> a tier name, then models[<tier>] -> an alias. Either step missing
# means this prints nothing on stdout and exits 1 — and says so on stderr first.
#
# The line names the CONSEQUENCE, not just the gap. "no roleTiers entry" is a fact about a
# file; "this agent will run on whatever the session happens to be" is what the reader has
# to decide about, and it is the half a caller cannot work out for itself. It also names
# both files, because which one is missing the entry decides where the fix goes: the
# per-machine file is where spend belongs, and the bundle stamp seeds it.
unresolved() { # <what-is-missing> <fix>
  echo "resolve-model: no model for '$agent' — $1." >&2
  echo "  Nothing was printed, so a caller that ignores this exit code will dispatch on" >&2
  echo "  the SESSION model instead of a chosen one, silently, for this agent." >&2
  echo "  Fix: $2" >&2
  echo "       to instance.config.local.json — per-machine spend, and the tracked" >&2
  echo "       instance.config.json is the fallback. Or re-run /${PLUGIN_NAME}:init on this" >&2
  echo "       bundle, which seeds both keys into the local file." >&2
  exit 1
}

tier="$(bash "$resolver" --instance "$inst" roleTiers "$agent")" || tier=""
[ -n "$tier" ] || unresolved \
  "neither instance.config.local.json nor instance.config.json has a roleTiers entry for it" \
  "add \"roleTiers\": { \"$agent\": \"<light|standard|deep|apex>\" }"
alias_name="$(bash "$resolver" --instance "$inst" models "$tier")" || alias_name=""
[ -n "$alias_name" ] || unresolved \
  "its tier is '$tier', and neither config file maps that tier to a model alias" \
  "add \"models\": { \"$tier\": \"<alias>\" }"
printf '%s\n' "$alias_name"
