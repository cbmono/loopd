#!/usr/bin/env bash
#
# resolve-model.sh — print the model alias a given agent should run on.
#
#   Usage: resolve-model.sh <agent-name> [--instance DIR]
#          resolve-model.sh --all        [--instance DIR]
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
#
# `--all` RESOLVES EVERY ROLE IN ONE CALL, for the stamp. `/loopd:init` asks "does every
# role resolve?" of this script, the real reader, and asking it once per role cost eight
# bash+python starts — 0.49 s of a 1.14 s stamp, measured 2026-10-05 — at ~220 stamp
# call sites in the suite. Both modes run the SAME `resolve_one` below over ONE `--dump`
# of `resolve-config.sh`; there is no second implementation, so the batch cannot drift
# from the single answer. Output, one row per `roleTiers` entry in `--dump` order:
#
#   <role> TAB <from> TAB <tier> TAB <model>
#
# `from` is which file won the role's tier (`tracked`/`local`); when the alias came from
# the OTHER file it reads `<tier-winner>/<model-winner>`, the banner's owner-row spelling.
# `model` is EMPTY for a role that does not resolve — the row still prints, so a caller
# gets the partial answer, and stderr names the failure as the single call would. Exit 0
# when every role resolved, else 1 (the single call's code). THE COLUMN ORDER IS
# LOAD-BEARING: `IFS=$'\t' read` collapses ADJACENT tabs, so an empty field is only read
# correctly when it is trailing — and an empty `tier` implies an empty `model`, which is
# why the two fields that can be empty come last and `from`, never empty, comes second.
set -uo pipefail
_pn="$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"; if [ -r "$_pn" ]; then . "$_pn"; fi

agent=""; inst="."; all=0
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--instance` leaves one argument, and
    # `shift 2` then FAILS WITHOUT SHIFTING. With no `set -e` that returns to the top
    # of the loop with the same argv and spins forever — verified by running it.
    --instance)
      [ $# -ge 2 ] || { echo "resolve-model: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    --all) all=1; shift ;;
    -h|--help) sed -n '3,6p' "$0"; exit 0 ;;
    -*) echo "resolve-model: unknown flag $1" >&2; exit 2 ;;
    *) agent="$1"; shift ;;
  esac
done
if [ "$all" -eq 1 ]; then
  [ -z "$agent" ] || { echo "resolve-model: --all takes no agent name (got '$agent')" >&2; exit 2; }
else
  [ -n "$agent" ] || {
    echo "Usage: resolve-model.sh <agent-name> [--instance DIR]" >&2
    echo "       resolve-model.sh --all        [--instance DIR]" >&2; exit 2; }
fi

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

# ONE read of both files, for either mode. `--dump` is `<from> TAB <key> TAB <entry> TAB
# <value>`, one leaf per line, null leaves already omitted and values folded to one line
# by the resolver — so a lookup here is string equality on two fields and nothing is
# re-derived about precedence. A failed dump (no python3) is an empty one: every lookup
# then misses, which is the same answer the two value calls gave.
dump="$(bash "$resolver" --instance "$inst" --dump)" || dump=""
tab=$'\t'

# lookup <key> <entry> — LEAF_FROM/LEAF_VALUE for one leaf of the dump; 1 when absent.
# Split by parameter expansion, not `read`: the dump's entry column is EMPTY for a scalar
# key, and `IFS=tab read` would collapse that tab and shift the value into the entry.
lookup() {
  local line rest k e
  LEAF_FROM=""; LEAF_VALUE=""
  while IFS= read -r line; do
    rest="${line#*"$tab"}"; k="${rest%%"$tab"*}"
    rest="${rest#*"$tab"}"; e="${rest%%"$tab"*}"
    [ "$k" = "$1" ] && [ "$e" = "$2" ] || continue
    LEAF_FROM="${line%%"$tab"*}"; LEAF_VALUE="${rest#*"$tab"}"
    return 0
  done <<EOF
$dump
EOF
  return 1
}

# roleTiers[<agent>] -> a tier name, then models[<tier>] -> an alias. Either step missing
# means this prints nothing on stdout and exits 1 — and says so on stderr first.
#
# The line names the CONSEQUENCE, not just the gap. "no roleTiers entry" is a fact about a
# file; "this agent will run on whatever the session happens to be" is what the reader has
# to decide about, and it is the half a caller cannot work out for itself. It also names
# both files, because which one is missing the entry decides where the fix goes: the
# per-machine file is where spend belongs, and the bundle stamp seeds it.
unresolved() { # <agent> <what-is-missing> <fix> — stderr only; the caller owns the exit
  echo "resolve-model: no model for '$1' — $2." >&2
  echo "  Nothing was printed, so a caller that ignores this exit code will dispatch on" >&2
  echo "  the SESSION model instead of a chosen one, silently, for this agent." >&2
  echo "  Fix: $3" >&2
  echo "       to instance.config.local.json — per-machine spend, and the tracked" >&2
  echo "       instance.config.json is the fallback. Or re-run /${PLUGIN_NAME}:init on this" >&2
  echo "       bundle, which seeds both keys into the local file." >&2
}

# resolve_one <agent> — RES_TIER, RES_MODEL, RES_FROM for one agent; 1 when unresolved.
# The ONE implementation both modes run.
resolve_one() {
  RES_TIER=""; RES_MODEL=""; RES_FROM=""
  if lookup roleTiers "$1"; then RES_TIER="$LEAF_VALUE"; RES_FROM="$LEAF_FROM"; fi
  [ -n "$RES_TIER" ] || { unresolved "$1" \
    "neither instance.config.local.json nor instance.config.json has a roleTiers entry for it" \
    "add \"roleTiers\": { \"$1\": \"<light|standard|deep|apex>\" }"; return 1; }
  if lookup models "$RES_TIER"; then RES_MODEL="$LEAF_VALUE"; fi
  [ -n "$RES_MODEL" ] || { unresolved "$1" \
    "its tier is '$RES_TIER', and neither config file maps that tier to a model alias" \
    "add \"models\": { \"$RES_TIER\": \"<alias>\" }"; return 1; }
  [ "$LEAF_FROM" = "$RES_FROM" ] || RES_FROM="$RES_FROM/$LEAF_FROM"
  return 0
}

if [ "$all" -eq 0 ]; then
  resolve_one "$agent" || exit 1
  printf '%s\n' "$RES_MODEL"
  exit 0
fi

# --all: every `roleTiers` entry the merged view has, in the dump's (sorted) order.
rc=0; seen=0
while IFS= read -r line; do
  rest="${line#*"$tab"}"; k="${rest%%"$tab"*}"
  rest="${rest#*"$tab"}"; role="${rest%%"$tab"*}"
  [ "$k" = roleTiers ] && [ -n "$role" ] || continue
  seen=1
  resolve_one "$role" || rc=1
  printf '%s\t%s\t%s\t%s\n' "$role" "$RES_FROM" "$RES_TIER" "$RES_MODEL"
done <<EOF
$dump
EOF
# THE EMPTY CASE IS THE LOUDEST ONE: with no roles there is nothing to fail, and a silent
# exit 0 here would read as "every role resolves" to a stamp that is looking for exactly
# the opposite — every dispatch inheriting the session model with nothing saying so.
[ "$seen" -eq 1 ] || {
  echo "resolve-model: this instance has NO roleTiers at all, in either config file, so" >&2
  echo "  every dispatched agent will resolve to NO model and inherit the session model." >&2
  exit 1; }
exit "$rc"
