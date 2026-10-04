#!/usr/bin/env bash
#
# check-template-version.sh — is the template this instance links BEHIND the remote?
#
# One question, one answer, and the answer is usually silence. It compares the `VERSION`
# file in the template checkout the instance's symlinks point into against the same file
# on the remote's default branch, and prints a line ONLY when the remote is newer.
#
# WHY A VERSION COMPARISON AND NOT A COMMIT COUNT. An instance consumes the template
# through per-file symlinks, so most changes are live the moment they are merged and a
# "you are N commits behind" line would fire constantly for changes that already reached
# here. The two that do NOT arrive by themselves are the ones worth a line: a NEW file
# in the plugin reaches a machine only when the plugin is UPDATED, and `seed/` content is
# copied into a bundle once, ever. Both are exactly the changes the bump convention
# (`docs/conventions.md` §20) requires a version bump for, so the version — not the commit
# graph — is the signal.
#
# IT SPEAKS ONLY WHEN BEHIND. Equal or ahead is byte-empty output. A line every session is
# wallpaper, and wallpaper is how AWAITING.md rows come to be skipped; the banner this
# feeds has the same rule for every one of its sections.
#
# AND A FAILURE IS NEVER "BEHIND". Unreachable, unauthenticated, offline, no git, not a
# checkout, no remote-tracking ref, no VERSION on either side, a version this cannot parse
# — every one of those exits 0 with nothing printed. A false "you are behind" trains the
# human to ignore the true one, and absence is never an error anywhere else in this
# machinery.
#
# TWO SUBJECTS, TWO NETWORK POLICIES. Against a TEMPLATE CHECKOUT nothing is fetched unless
# `--fetch` says so, so the comparison reads the ref already on disk and can only ever
# under-report. Against a PLUGIN INSTALL — no checkout above it — the marketplace clone is
# fetched with a two-second cap and the result cached for six hours, so a session is never
# blocked on a socket and most sessions make no call at all; `--fetch` forces past the cache.
#
# WHAT IT CANNOT SEE, stated because a checker that overclaims is worse than none: a
# template checkout parked on an old commit or a stale branch whose VERSION happens to
# equal the remote's is INVISIBLE here. The version moves when the bump convention says it
# moves, so this detects drift across a bump and nothing finer.
#
# NEVER WRITES, NEVER FETCHES UNLESS ASKED, NEVER REPAIRS. It reports; the human pulls and
# re-stamps. Exit status is 0 on every path, including "behind": the caller is a
# SessionStart banner, and a non-zero exit there is a failed hook, not a message.
#
#   check-template-version.sh [--template <dir>] [--plugin <dir>] [--instance <dir>]
#                             [--ref <ref>] [--fetch] [--state]
#
# Verified by tests/template-version.test.sh.
set -uo pipefail
_pn="$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"; if [ -r "$_pn" ]; then . "$_pn"; fi

TEMPLATE=""; PLUGIN=""; PLUGIN_SET=0; INSTANCE=""; REF=""; FETCH=0; STATE=0
# Six hours, and a two-second cap: the SessionStart banner may not wait on a socket, and a
# fetch per session would be one per session for an answer that moves a few times a month.
CACHE_TTL=21600; FETCH_SECS=2; CACHE_FILE=version-check
while [ $# -gt 0 ]; do
  case "$1" in
    --template)   shift; TEMPLATE="${1:-}"; shift || true ;;
    --template=*) TEMPLATE="${1#--template=}"; shift ;;
    --plugin)     shift; PLUGIN="${1:-}"; PLUGIN_SET=1; shift || true ;;
    --plugin=*)   PLUGIN="${1#--plugin=}"; PLUGIN_SET=1; shift ;;
    --state)      STATE=1; shift ;;
    --instance)   shift; INSTANCE="${1:-}"; shift || true ;;
    --instance=*) INSTANCE="${1#--instance=}"; shift ;;
    --ref)        shift; REF="${1:-}"; shift || true ;;
    --ref=*)      REF="${1#--ref=}"; shift ;;
    --fetch)      FETCH=1; shift ;;
    # An unknown argument is IGNORED rather than fatal, for the same reason the banner
    # ignores one: this runs at session start, and refusing to start over a flag a future
    # settings.json passed is a worse outcome than not understanding it.
    *) shift ;;
  esac
done

[ -n "$INSTANCE" ] || INSTANCE="${CLAUDE_PROJECT_DIR:-$PWD}"

# WHERE THE TEMPLATE IS, read from this script's own path when it was not passed one. The
# instance's copy of this file IS a symlink into the template, so resolving it is the one
# lookup that cannot be wrong, because it is executing. Callers that already
# know (the banner, the tests) pass `--template` and skip this.
self="${BASH_SOURCE[0]:-$0}"
# ABSOLUTE BEFORE ANYTHING ELSE: a relative invocation would make the walk below start
# from a path that means nothing outside this process's cwd, and a symlink is allowed to
# hold a relative target that only means anything beside the link itself.
case "$self" in /*) ;; *) self="$PWD/$self" ;; esac
if [ -L "$self" ]; then
  target="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
  case "$target" in /*) self="$target" ;; *) self="$(dirname "$self")/$target" ;; esac
fi
_d="$(dirname "$self")"; if [ -L "$_d" ] && [ ! -f "$(dirname "$_d")/VERSION" ]; then _t="$(readlink "$_d")"; case "$_t" in /*) _d="$_t" ;; *) _d="$(dirname "$_d")/$_t" ;; esac; fi
selfdir="$(cd "$_d" 2>/dev/null && pwd || true)"

if [ -z "$TEMPLATE" ] && [ "$PLUGIN_SET" -eq 0 ] && [ -n "$selfdir" ]; then
  # The layout is fixed by the marketplace manifest (`source: ./plugin`): this file sits at
  # <root>/plugin/scripts/, so the template root is exactly two directories up. Derived and
  # then VERIFIED against `VERSION`, never searched for — a walk that keeps climbing finds
  # SOME ancestor with a VERSION file eventually, and comparing against an unrelated repo
  # is the one answer worse than silence.
  guess="$(cd "$selfdir/../.." 2>/dev/null && pwd || true)"
  [ -n "$guess" ] && [ -f "$guess/VERSION" ] && TEMPLATE="$guess"
fi
[ -n "$TEMPLATE" ] && [ -d "$TEMPLATE" ] || TEMPLATE=""
# THE PLUGIN INSTALL IS THE OTHER SUBJECT, and on a marketplace install it is the only one:
# what lands on a machine is the CONTENTS of `plugin/` under a version directory, so there
# is no checkout above it and `$selfdir/..` is the installed copy carrying its own VERSION.
if [ -z "$PLUGIN" ] && [ -n "$selfdir" ]; then
  PLUGIN="$(cd "$selfdir/.." 2>/dev/null && pwd || true)"
fi
[ -n "$PLUGIN" ] && [ -f "$PLUGIN/VERSION" ] || PLUGIN=""

# ---------------------------------------------------------------------------------------
# READING A VERSION — strict, because the two values are compared AND printed.
# ---------------------------------------------------------------------------------------
# STRICTER THAN THE BANNER'S DISPLAY FILTER, on purpose. The banner may print `9.9.9-rc1`;
# there is no defensible ordering between a pre-release and a release, so anything that is
# not a plain dotted run of digits is unparseable HERE and unparseable means silence. The
# same filter also settles the injection question for free: a value that reaches stdout is
# digits and dots, so a VERSION file carrying an ESC sequence cannot repaint a terminal.
# Fields are capped at 9 digits so the numeric compare below cannot overflow.
read_version() { # <raw file contents> ; prints a normalised version, or nothing
  local v
  v="$(printf '%s\n' "$1" | sed -n '1p' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$v" in
    ''|.*|*.|*..*) return 0 ;;
    *[!0-9.]*)     return 0 ;;
  esac
  [ "${#v}" -le 32 ] || return 0
  local IFS=. f
  for f in $v; do [ "${#f}" -le 9 ] || return 0; done
  printf '%s' "$v"
}

# newer <a> <b> — true when version <a> is strictly greater than version <b>. Field by
# field, numerically: `0.10.0` is newer than `0.9.1` and a string compare says the
# opposite, which is the single most likely way this check could lie. A missing field is 0,
# so `1.0` and `1.0.0` are equal. `10#` forces base 10 — `08` is an invalid octal literal
# and would otherwise abort the comparison mid-way.
newer() { # <a> <b>
  local IFS=. i n x y
  # shellcheck disable=SC2206  # the split on IFS IS the parse
  local -a A=($1) B=($2)
  n=${#A[@]}; [ "${#B[@]}" -gt "$n" ] && n=${#B[@]}
  for (( i = 0; i < n; i++ )); do
    x=$(( 10#${A[i]:-0} )); y=$(( 10#${B[i]:-0} ))
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 1
}

# ---------------------------------------------------------------------------------------
# THE TWO SIDES — a template checkout when there is one, otherwise the plugin install.
# ---------------------------------------------------------------------------------------
HERE=""; THERE=""; REF_NAME=""; LABEL=""; PNAME=""

# A BOUND THAT SURVIVES THIS SHELL, because `timeout` is not on a stock macOS: the watchdog
# is a detached SIBLING, so it still fires if we are killed, and `sleep` bounds it in turn.
bounded() { # <seconds> <command…>
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@" >/dev/null 2>&1; return; fi
  # ONE SUBSHELL, ITS STDERR DISCARDED: a killed background job otherwise prints the
  # shell's own `Terminated` notice, which is not this file's output.
  ( "$@" >/dev/null 2>&1 &
    local child=$! dog rc=0
    # The watchdog's stdio is redirected too, because killing the subshell leaves the
    # `sleep` holding a pipe a caller reading us with `$( … )` would block on.
    ( sleep "$secs"; kill "$child" ) >/dev/null 2>&1 &
    dog=$!
    wait "$child" || rc=1
    kill "$dog" >/dev/null 2>&1 || true
    exit "$rc" ) 2>/dev/null
}

# DERIVED FROM THE INSTALL PATH'S OWN SHAPE, never searched for: `plugins/marketplaces/`
# holds every marketplace this machine has added, and the wrong one is a stranger's version.
plugin_paths() { # -> "<marketplace clone>\t<data dir>\t<plugin name>"
  local ver name mkt cache plugins
  ver="$(cd "$PLUGIN" 2>/dev/null && pwd)" || return 1
  mkt="$(cd "$ver/../.." 2>/dev/null && pwd)" || return 1
  cache="$(dirname "$mkt")"; plugins="$(dirname "$cache")"
  [ "$(basename "$cache")" = cache ] && [ "$(basename "$plugins")" = plugins ] || return 1
  # Filtered, not trusted: it is a directory name and it reaches a banner.
  name="$(basename "$(dirname "$ver")" | tr -cd 'A-Za-z0-9._-')"
  [ -n "$name" ] || return 1
  printf '%s\t%s\t%s' "$plugins/marketplaces/$(basename "$mkt")" "$plugins/data/$name-$(basename "$mkt")" "$name"
}

# HERE is the WORKING TREE, not HEAD: the working tree is what the instance's symlinks
# actually resolve into and what the banner prints, so it is what "this instance links"
# means. A checkout with an uncommitted VERSION is answered about as it is on disk.
#
# THE ONLY NETWORK CALL ON THIS PATH IS OPT-IN, and a failed fetch ends the run rather than
# falling through to the on-disk ref: the caller asked for a fresh answer and could not have
# one. `GIT_TERMINAL_PROMPT=0` because the failure to survive here is not an error but a
# HANG — a remote whose credentials expired otherwise asks for a username on the terminal.
resolve_checkout() {
  HERE="$(read_version "$(cat -- "$TEMPLATE/VERSION" 2>/dev/null || true)")"
  [ -n "$HERE" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$TEMPLATE" rev-parse --git-dir >/dev/null 2>&1 || return 0
  if [ "$FETCH" -eq 1 ]; then
    GIT_TERMINAL_PROMPT=0 git -C "$TEMPLATE" fetch --quiet origin >/dev/null 2>&1 || return 0
  fi
  local ref="$REF"
  # NEVER ASSUME `main` — NOT EVEN AS A FALLBACK. `origin/HEAD` is what the remote itself
  # says its default branch is, and unresolvable ⇒ silence like everything else here.
  [ -n "$ref" ] || ref="$(git -C "$TEMPLATE" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  [ -n "$ref" ] || return 0
  THERE="$(read_version "$(git -C "$TEMPLATE" show "$ref:VERSION" 2>/dev/null || true)")"
  [ -n "$THERE" ] || return 0
  REF_NAME="$ref"
  LABEL="$(basename -- "$TEMPLATE" 2>/dev/null | tr -d '[:cntrl:]')"
}

# THE INSTALLED PLUGIN against the marketplace clone `claude plugin update` pulls from.
# The fetch is BOUNDED and its result cached for six hours, so most sessions make no network
# call at all — and a failure or a timeout leaves THERE empty, which is unknown, never behind.
resolve_plugin() {
  HERE="$(read_version "$(cat -- "$PLUGIN/VERSION" 2>/dev/null || true)")"
  [ -n "$HERE" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  local paths mkt data ref now stamp
  paths="$(plugin_paths)" || return 0
  IFS="$(printf '\t')" read -r mkt data PNAME <<<"$paths"
  [ -d "$mkt" ] && git -C "$mkt" rev-parse --git-dir >/dev/null 2>&1 || return 0
  now="$(date +%s 2>/dev/null || echo 0)"; stamp=0
  if [ "$FETCH" -eq 0 ] && [ -r "$data/$CACHE_FILE" ]; then
    stamp="$(sed -n 1p "$data/$CACHE_FILE" 2>/dev/null)"
    case "$stamp" in ''|*[!0-9]*) stamp=0 ;; esac
  fi
  if [ "$((now - stamp))" -ge "$CACHE_TTL" ]; then
    bounded "$FETCH_SECS" env GIT_TERMINAL_PROMPT=0 git -C "$mkt" fetch --quiet origin || return 0
    mkdir -p "$data" 2>/dev/null && printf '%s\n' "$now" > "$data/$CACHE_FILE" 2>/dev/null || true
  fi
  ref="$REF"
  [ -n "$ref" ] || ref="$(git -C "$mkt" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  [ -n "$ref" ] || return 0
  THERE="$(read_version "$(git -C "$mkt" show "$ref:VERSION" 2>/dev/null || true)")"
  [ -n "$THERE" ] || return 0
  REF_NAME="$ref"
  LABEL="$(basename -- "$mkt" 2>/dev/null | tr -d '[:cntrl:]')"
}

if [ -n "$TEMPLATE" ]; then resolve_checkout
elif [ -n "$PLUGIN" ]; then resolve_plugin
fi

# ---------------------------------------------------------------------------------------
# THE ANSWER. `--state` is the machine-readable one, and it is the only mode that speaks
# when the answer is unavailable — its caller has a row to fill either way.
# ---------------------------------------------------------------------------------------
if [ "$STATE" -eq 1 ]; then
  if [ -z "$HERE" ] || [ -z "$THERE" ]; then printf 'unknown\t%s\t\t%s\n' "$HERE" "$PNAME"
  elif newer "$THERE" "$HERE"; then printf 'behind\t%s\t%s\t%s\n' "$HERE" "$THERE" "$PNAME"
  else printf 'current\t%s\t%s\t%s\n' "$HERE" "$THERE" "$PNAME"
  fi
  exit 0
fi

[ -n "$HERE" ] && [ -n "$THERE" ] || exit 0
newer "$THERE" "$HERE" || exit 0

# ---------------------------------------------------------------------------------------
# THE LINE. Reached only when the remote is strictly newer.
# ---------------------------------------------------------------------------------------
# PLAIN TEXT, NO COLOUR. The caller that prints this is the session banner, whose stdout is
# a pipe into Claude Code rather than a terminal; escape codes on that path land in the
# transcript as literal bytes. The banner owns presentation, this file owns the verdict.
#
# THE REPAIR IS TWO COMMANDS AND THE SECOND ONE IS THE POINT: pulling the template updates
# every file already linked, but a file that is NEW in that pull reaches this instance only
# when the bundle is re-stamped. Someone who updates and stops is exactly the state this check
# exists to end.
#
# THE NAME IS DERIVED, NEVER A LITERAL — `plugin/**` carries no org, repo or path literals
# (`.claude/rules/machinery.md`), so a fork or a renamed clone names itself.
label="TEMPLATE UPDATE"
[ -n "$LABEL" ] && label="TEMPLATE UPDATE ($LABEL)"
printf '%s\n' "⬆️  $label — this machine runs ${HERE}, ${REF_NAME} has ${THERE}"
echo "    Update the plugin, then re-stamp this bundle (a seed change reaches a bundle"
echo "    only through a stamp, and only that way):"
echo "        /plugin update ${PLUGIN_NAME}@${PLUGIN_MARKETPLACE}      (then restart Claude Code)"
printf '        /%s:init %q\n' "$PLUGIN_NAME" "$INSTANCE"
exit 0
