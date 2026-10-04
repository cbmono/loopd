#!/usr/bin/env bash
#
# ai-bridge.sh — the welcome command (plugin skill `/welcome`), in three forms.
#
#   ai-bridge.sh                      reprint the SessionStart banner
#   ai-bridge.sh check  [flags]       report the state of this instance
#   ai-bridge.sh fix    [flags]       RETIRED — points at /<plugin>:init and exits 0
#
# `fix` MOVED INTO `/<plugin>:init` — it stamps the bundle, then runs this file's pass
# (`AI_BRIDGE_INIT_PASS=1`, same tiers, same refusals). This form is a pointer for one release.
#
# WHAT THIS IS NOT, because the rejected shape is the one that keeps getting proposed. It
# does NOT load rules into context. `CLAUDE.md` is injected into every turn and the banner
# already fires unprompted, and of the failures this file was written from, not one was
# caused by a rule not being loaded — every one was invisible STATE (a stamp taken from a
# stale template clone that printed `already linked` and changed nothing; config keys left
# uncommitted; an instance configured to call a hook it did not have) or a missing READER.
# Reciting rules costs context every session and enforces nothing.
#
# So the rule for every line this file prints: it is a FACT THAT CAN BE FALSE, with its
# evidence. Never a reminder, never a convention, never "always use the loop". If a line
# would read the same on a healthy instance and a broken one, it does not belong here.
#
# ---------------------------------------------------------------------------------------
# THE ONE LIST, AND WHY IT IS ONE
# ---------------------------------------------------------------------------------------
# `check` and `fix` read `CHECKS` below and nothing else. Two lists drift — the checker
# learns about seven things, the fixer about five, and the gap is silent — so `fix` does
# not know the name of a single check: it walks the same rows, reads the TIER each row
# declares, and dispatches on that. Adding a check is one edit in one place (a row here
# plus its `check_<id>` function), and `assert_no_rogue_fixers` below turns the invariant
# into a refusal rather than a convention.
#
# THE THREE TIERS ARE A RISK CLASSIFICATION, NOT A PRIORITY. Collapsing them is how this
# command becomes dangerous:
#
#   idempotent  re-running the repair on an already-correct instance changes nothing, and
#               the repair has exactly one right answer. `fix` ACTS.
#   ambiguous   whether it is even wrong is a judgement only the human can make. `fix`
#               PRINTS. Measured 2026-08-30: an instance carried an uncommitted
#               `maxPrLoc: 2000 -> 500` that was a deliberate decision by its owner, made
#               minutes earlier and indistinguishable to a checker from drift. A `fix`
#               that "helpfully" reverted it would have destroyed that choice.
#               UNCOMMITTED CONFIG IS A QUESTION, NEVER A DEFECT.
#   human       acting is unsafe even when the diagnosis is right. `fix` PRINTS. The live
#               case is `.tick-lock`: `tick-lock.sh release` is documented as the
#               human's override (`/<plugin>:dispatch`, `SCHEMA.md`), and a `fix` that cleared a
#               lock it judged stale re-opens the double-dispatch that ran two ticks
#               concurrently for 34 minutes on 2026-08-29. A long tick is not a dead one.
#
# The two SHIP-BLOCKERS are structural, not a promise: there is no `fix_config_uncommitted`
# and no `fix_tick_lock` in this file, the dispatcher calls `fix_<id>` only for a row whose
# declared tier is `idempotent`, and `check` and `fix` both REFUSE TO RUN if either function
# is ever defined (the banner form `exec`s before that point, deliberately — it dispatches
# no repair, and nothing may come between it and the hook). `tests/ai-bridge-command.test.sh` asserts the non-action against a modified
# config and a stale lock — the two files come out byte-identical, unstaged and unremoved.
#
# ---------------------------------------------------------------------------------------
# NEVER WRITES OUTSIDE `fix`, AND NEVER FAILS LOUDLY
# ---------------------------------------------------------------------------------------
# `check` reads. Every unknown — no git, no remote-tracking ref, no python3, no template,
# an instance that is not a checkout — is reported AS a fact ("cannot compare, because X")
# and never as an error and never as a warning. A false alarm trains the human to ignore
# the true one, which is the failure mode this whole file exists to prevent; `check` exits
# 0 on every path except a usage error, because its caller can be a SessionStart hook and a
# non-zero exit there is a failed hook, not a message.
#
# WHICH EMPHASIS SURVIVES DEPENDS ON WHO IS READING, AND IT WAS MEASURED. `check` output is
# read three ways and two of them render different things — Claude Code 2.1.251, probed
# 2026-08-30 by emitting candidates and reading the bytes the terminal received:
#
#   relayed by the model (`/<plugin>:welcome check` in a session)   markdown renders; ANSI DOES NOT.
#       0 of 4 ESC bytes survived the relay and the human was left reading a literal `[1m`.
#       Single newlines and leading indent survive, so the block keeps its shape.
#   a human's terminal (`bash ai-bridge.sh check`)   ANSI renders; markdown does not.
#   inlined into the SessionStart banner (`--banner`)        NEITHER, here. That channel does
#       render ANSI — but `session-banner.sh` owns the weight of every line it prints, so
#       this side stays plain and the banner colours it. Two writers on one line is how a
#       column drifts.
#
# Hence `--style`, resolved below. The SIGIL IS NEVER INSIDE THE EMPHASIS: `⚠ **text**`, not
# `**⚠ text**`, so `^⚠` keeps matching for the banner's filter and for the harness whatever
# the style is.
#
# GENERIC PLUGIN FILE — ships inside this plugin; it reads no org, repo or path literal,
# and no brand literal either: every message below spells the name through `$PLUGIN_NAME`,
# which plugin-name.sh derives. tests/banner-user-channel.test.sh asserts this file carries
# no copy of the brand — its proof that the wrapper prints no banner text of its own, and
# the reason a rename does not reach in here. Verified by tests/ai-bridge-command.test.sh.
#
# EVERY `check_*` AND `fix_*` FUNCTION IS INVOKED INDIRECTLY, by a name built from the row
# in `CHECKS` — which is the whole design, and is exactly what shellcheck cannot see. The
# disable is file-scoped rather than repeated eleven times, and the wiring the linter is
# thereby stopped from checking is checked properly instead, at runtime, by
# `assert_list_is_wired`: a row with no function makes the command refuse to start.
# shellcheck disable=SC2329
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

# =========================================================================================
# THE LIST. `id|tier|banner`
# =========================================================================================
# `banner` says whether the row is allowed to speak on the SessionStart path. It is a
# COLUMN HERE rather than a second list in the hook, for the same reason `tier` is: the
# hook must not carry the name of a check. Two rows say `no` and both for the banner's own
# "only fire what is true, and never twice" rule —
#
#   template-behind    the banner already prints the VERSION drift line, from the same
#                      helper this row delegates to; the commits-behind fact is the
#                      on-demand half and would otherwise print a second line about the
#                      same clone at every session start.
#   config-layers      the banner's settings table already carries the FROM column, which
#                      IS this fact, laid out better.
#
# Order is execution order, and it is load-bearing for `fix`: pulling the template clone
# must happen before re-stamping from it, or the stamp is taken from the stale tree — the
# exact failure that produced this file.
CHECKS='template-behind|idempotent|no
bundle-unmigrated|human|yes
bundle-unconverted|idempotent|yes
seed-drift|idempotent|no
config-uncommitted|ambiguous|yes
config-layers|ambiguous|no
config-unknown-keys|ambiguous|yes
tick-lock|human|yes
orphan-processes|human|yes'

# =========================================================================================
# ARGUMENTS
# =========================================================================================
FORM=""; ROOT=""; TEMPLATE=""; ONLY_PROBLEMS=0; BANNER_ONLY=0; FETCH=0
# `--since <ref>` is ACCEPTED AND IGNORED, deliberately. It asked the retired
# `unstamped-machinery` check for the literal post-merge form — which machinery files a
# template range ADDED, because only a stamp delivered a new machinery file. A bundle has
# no machinery, so the question has no answer to give; the flag stays parsed for one
# version so a saved command line does not become a fatal "unknown argument".
SINCE=""
LIST=0; STYLE=auto

# usage — the three forms and their flags, on stderr so `--help` never pollutes a pipeline.
usage() {
  cat >&2 <<'USAGE'
Usage: ai-bridge.sh [banner]                       reprint the SessionStart banner
       ai-bridge.sh check [--instance DIR] [--template DIR] [--fetch]
                          [--since <ref>] [--only-problems] [--banner] [--list]
                          [--style auto|markdown|ansi|plain]
       ai-bridge.sh fix   [--instance DIR] [--template DIR] [--fetch]
                          [--style auto|markdown|ansi|plain]
USAGE
}

# The form is the FIRST argument or nothing. Anything else is a flag, and an unrecognised
# flag is fatal here (unlike the banner, which is a hook and must start anyway): this is an
# interactive command, and silently ignoring `--intsance` would report on the wrong root.
case "${1:-}" in
  check|fix)   FORM="$1"; shift ;;
  banner)      FORM=banner; shift ;;
  -h|--help)   usage; exit 0 ;;
  "")          FORM=banner ;;
  -*)          FORM=banner ;;   # `ai-bridge.sh --color=never` — flags belong to the banner
  *)           usage; exit 2 ;;
esac

# Everything left over on the banner path stays in `$@` untouched, including flags this
# file has never heard of: it is the one form that must not grow a second opinion about its
# own options. `"$@"` is also the one array expansion that is safe under `set -u` when it is
# empty, on the bash 3.2 macOS still ships.
if [ "$FORM" != banner ]; then
  while [ $# -gt 0 ]; do
    case "$1" in
      --instance)    [ $# -ge 2 ] || { echo "${PLUGIN_NAME}: --instance needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
      --instance=*)  ROOT="${1#--instance=}"; shift ;;
      --template)    [ $# -ge 2 ] || { echo "${PLUGIN_NAME}: --template needs a directory" >&2; exit 2; }; TEMPLATE="$2"; shift 2 ;;
      --template=*)  TEMPLATE="${1#--template=}"; shift ;;
      --since)       [ $# -ge 2 ] || { echo "${PLUGIN_NAME}: --since needs a git ref" >&2; exit 2; }; SINCE="$2"; shift 2 ;;  # accepted, ignored — see above
      --since=*)     SINCE="${1#--since=}"; shift ;;                                                                       # accepted, ignored
      --only-problems) ONLY_PROBLEMS=1; shift ;;
      --banner)      BANNER_ONLY=1; shift ;;
      --list)        LIST=1; shift ;;
      --style)       [ $# -ge 2 ] || { echo "${PLUGIN_NAME}: --style needs a value" >&2; exit 2; }; STYLE="$2"; shift 2 ;;
      --style=*)     STYLE="${1#--style=}"; shift ;;
      --fetch)       FETCH=1; shift ;;
      -h|--help)     usage; exit 0 ;;
      *)             echo "${PLUGIN_NAME}: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done
fi

[ -n "$ROOT" ] || ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# `--since` IS READ AND THEN DROPPED, and that is stated here rather than left as an
# unused variable somebody deletes as dead code. It asked the retired
# `unstamped-machinery` row for the literal post-merge form; a bundle has no machinery, so
# the question has no answer to give. Parsed for one version so a saved command line does
# not become a fatal "unknown argument".
[ -z "$SINCE" ] || SINCE=""

# WHERE THE SIBLING MACHINERY IS. Beside this file, always — it is the plugin's own
# `scripts/` directory and this script is executing out of it, so `dirname $0` is right by
# construction whether the plugin came from a marketplace cache or a checkout of this repo.
# The hooks are one level up, in the plugin's `hooks/`.
SELF_PATH="${BASH_SOURCE[0]:-$0}"
case "$SELF_PATH" in /*) ;; *) SELF_PATH="$PWD/$SELF_PATH" ;; esac
if [ -L "$SELF_PATH" ]; then
  _t="$(readlink "$SELF_PATH" 2>/dev/null || printf '%s' "$SELF_PATH")"
  case "$_t" in /*) SELF_PATH="$_t" ;; *) SELF_PATH="$(dirname "$SELF_PATH")/$_t" ;; esac
fi
_d="$(dirname "$SELF_PATH")"; if [ -L "$_d" ] && [ ! -f "$(dirname "$_d")/VERSION" ]; then _t="$(readlink "$_d")"; case "$_t" in /*) _d="$_t" ;; *) _d="$(dirname "$_d")/$_t" ;; esac; fi
BIN="$(cd "$_d" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$BIN/.." && pwd)}"
HOOKS="$PLUGIN_ROOT/hooks"

# WHERE THE TEMPLATE CHECKOUT IS — the repo AROUND the plugin, when there is one. It is
# used for exactly one thing: comparing this plugin's VERSION against the remote's. A
# plugin installed from a marketplace sits inside a clone of this repo, so it is normally
# there; a plugin vendored some other way has none, and that is reported as "cannot
# compare" rather than guessed at.
#
# NOTE WHAT THIS IS NOT ANY MORE. It used to be the checkout an instance's symlinks
# pointed into, derived from a marker in this file's own path. A
# bundle has no such links, so there is no per-bundle template at all — one plugin per
# machine answers for every bundle on it.
if [ -z "$TEMPLATE" ]; then
  TEMPLATE="$(cd "$BIN/../.." 2>/dev/null && pwd || true)"
  [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE/VERSION" ] || TEMPLATE=""
fi
[ -n "$TEMPLATE" ] && [ -d "$TEMPLATE" ] || TEMPLATE=""

# =========================================================================================
# FORM 1 — THE BANNER. One `exec`, no output of its own, ever.
# =========================================================================================
# IT INVOKES THE HOOK, IT DOES NOT REPRODUCE IT. The banner is `session-banner.sh` and this
# form exists for one reason: a long session scrolls it out of view. Any line printed here
# — a header, a "reprinting…", a blank line — is a way for the two to differ, and the
# moment they differ this form is wrong. `exec` rather than a call so even the exit status
# is the hook's own. `tests/ai-bridge-command.test.sh` asserts the output is BYTE-IDENTICAL
# to the hook's own, in the rendering this run asked the hook for.
#
# IT ASKS FOR THE RENDERING ITS READER CAN SEE, AND THAT IS THE ONLY OPINION IT HAS. When
# stdout is a pipe, this form IS the `/welcome` relay path: the output is relayed by the model
# into an assistant message, which renders markdown and destroys ANSI (measured — 0 of 4 ESC
# bytes reached the reader). So it asks the hook for `--format md`, the hook's third
# rendering, whose only difference from the plain text one is `**…**` on the identity line
# and the two table headers. A terminal gets the bare form and its SGR, exactly as before.
#
# `--no-logo`: relayed through markdown the ship loses its leading space and its colour, so
# the human saw a shifted second copy under the Bash tool's own. Arguments pass through as is.
# THE LADDER IS THE SAME ONE `--style` RESOLVES BELOW, and deliberately: `NO_COLOR` first,
# because it is the READER's opt-out and emphasis on a channel that draws `**bold**` as bold
# is that reader's colour. `--style` has no counterpart here — a caller that wants a specific
# rendering passes the hook's own `--format`, which is why ANY argument leaves this decision
# alone. That is the one form that must not grow a second opinion about its own options: the
# flags belong to the banner, and `bash ai-bridge.sh --format json` must reach it
# unedited.
#
# `CLAUDE_PROJECT_DIR` is exported because it is the only thing the hook reads to decide
# which instance it is describing. This form takes none of our own flags — `--instance` is a
# `check`/`fix` option — so the value is whatever the environment already said, or this
# directory; setting it explicitly is what makes `bash ai-bridge.sh` from an
# instance root print the same thing the hook prints at session start.
if [ "$FORM" = banner ]; then
  hook="$HOOKS/session-banner.sh"
  if [ ! -f "$hook" ]; then
    echo "${PLUGIN_NAME}: the session banner is not where this script expects it ($hook)." >&2
    echo "           That is a broken plugin install, not a bundle problem. Re-install:" >&2
    echo "           /plugin install ${PLUGIN_NAME}@${PLUGIN_MARKETPLACE}, then restart Claude Code." >&2
    exit 2
  fi
  export CLAUDE_PROJECT_DIR="$ROOT"
  if [ $# -eq 0 ]; then
    # `--full` because the two tables are what `welcome` is documented BY: the SessionStart
    # banner drops them to hold 12 lines, and a human who typed the command asked to look.
    if [ -z "${NO_COLOR:-}" ] && [ ! -t 1 ]; then
      exec bash "$hook" --format md --no-logo --full
    fi
    exec bash "$hook" --no-logo --full
  fi
  exec bash "$hook" "$@"
fi

# =========================================================================================
# SHARED PLUMBING FOR THE CHECKS
# =========================================================================================
# A check function prints its lines and RETURNS 1 when it found a problem, 0 otherwise. The
# return code is the only channel that survives the command substitution the runner wraps
# it in, which is why `warn` sets a flag the function returns rather than a global.
#
# THREE LINE KINDS, AND THE DIFFERENCE IS NOT COSMETIC. `--only-problems` — the
# SessionStart path — keeps `warn` and `hint` lines and drops everything else, so the
# banner gains AT MOST TWO LINES PER FAILING CHECK: what is wrong, and the one command
# that addresses it. That bound is the whole reason `hint` exists as its own helper rather
# than as a `note` someone remembered to keep short: the banner has a measured line budget
# (tests/session-banner.test.sh), and a section that can grow with the number of affected
# files would blow it the first time an instance is badly out of date — which is precisely
# when the banner most needs to stay readable. Emit ONE `hint` per check.
# ---------------------------------------------------------------------------------------
# STYLE — which emphasis this run's reader can actually see.
# ---------------------------------------------------------------------------------------
# RESOLVED ONCE, HERE, AND THE ORDER OF THE TESTS IS THE WHOLE OF IT:
#
#   NO_COLOR set and non-empty  -> plain.    The template's one opt-out (print-board.sh,
#                                            session-banner.sh state the same contract), and
#                                            it covers markdown too: bold is not "not colour"
#                                            when the client renders it AS colour, and one
#                                            switch a reader already knows beats a second one.
#   --style markdown|ansi|plain -> as asked. A caller that knows its reader.
#   --banner                    -> plain.    session-banner.sh inlines this block and colours
#                                            it; see the header.
#   stdout is a terminal        -> ansi.     A human ran it by hand.
#   otherwise                   -> markdown. A pipe here is the Bash tool, and what comes out
#                                            of it is relayed into an assistant message. That
#                                            was measured rendering markdown and DESTROYING
#                                            ANSI, so this is the branch `/<plugin>:welcome check`
#                                            actually takes.
#
# `NO_COLOR` IS TESTED BEFORE `--style`, AND THAT ORDER IS THE WHOLE OF THE CONTRACT. It is
# the READER's opt-out, set in their environment; `--style` is the CALLER's guess about that
# reader. A caller cannot consent on the reader's behalf, so `--style ansi` under `NO_COLOR=1`
# is the one combination that has to lose — the alternative is an opt-out that holds only for
# the paths which happen not to pass a style, i.e. one that works until something uses the
# flag. `markdown` loses to it for the same reason `auto` does: the client renders bold AS
# emphasis, so it is not "not colour" (see the first entry above).
#
# AN UNRECOGNISED VALUE IS `auto`, not fatal: `check` can be called from a SessionStart hook,
# and exiting 2 over a spelling mistake in a style name would cost the whole banner.
if [ -n "${NO_COLOR:-}" ]; then STYLE=plain
else
  case "$STYLE" in
    markdown|ansi|plain) ;;
    *) if   [ "$BANNER_ONLY" -eq 1 ]; then STYLE=plain
       elif [ -t 1 ];                 then STYLE=ansi
       else                                STYLE=markdown
       fi ;;
  esac
fi
# The ansi spelling comes from `cli-theme.sh` and nowhere else. `warn` is the one line here
# that carries emphasis and it is a fact that is false for this reader, so it is pink.
_B_ON=""; _B_OFF=""
case "$STYLE" in
  markdown) _B_ON='**'; _B_OFF='**' ;;
  ansi)     # shellcheck source=cli-theme.sh
            . "$(dirname "${BASH_SOURCE[0]:-$0}")/cli-theme.sh" 2>/dev/null
            command -v ab_theme >/dev/null 2>&1 || ab_theme() { :; }
            ab_theme 1 auto
            _B_ON="${T_BOLD:-}${T_PINK:-}"; _B_OFF="${T_OFF:-}" ;;
esac

_warned=0
# warn <text> — a fact that is FALSE here, and the only kind that sets the found-a-problem
# flag its check returns. Survives `--only-problems`.
#
# THE ONE LINE IN THIS FILE THAT CARRIES EMPHASIS, AND THAT IS DELIBERATE. `good` is left
# plain, `note` and `hint` are left plain: a reader scanning `check` is looking for the row
# that is WRONG, and a page where every kind of line has its own decoration gives them
# nothing to find. Emphasis here tracks significance, so it goes on exactly the lines that
# set the found-a-problem flag.
#
# THE SIGIL STAYS OUTSIDE IT. `⚠ **text**`, never `**⚠ text**` — `session-banner.sh` filters
# this block with `grep -e '^⚠'` and the harness pins the same anchor, so the line must start
# with the sigil in every style.
warn() { _warned=1; printf '%s\n' "⚠ ${_B_ON}$*${_B_OFF}"; }
# good <text> — the same fact, true. Dropped by `--only-problems`; never silent otherwise.
good() { printf '%s\n' "✓ $*"; }
# note <text> — indented evidence under the line above it. Dropped by `--only-problems`.
note() { printf '%s\n' "    $*"; }
# hint <text> — the ONE command that addresses the warning above it. Survives
# `--only-problems`; emit at most one per check, which is what bounds the banner section.
hint() { printf '%s\n' "    ↳ $*"; }

# tier_note <tier> — what `fix` does with a row of this tier, said in `fix`'s own output so
# the human is never left to infer why something was reported and not repaired.
tier_note() {
  case "$1" in
    idempotent) printf '%s' "idempotent — repairing it has one right answer and re-running changes nothing" ;;
    ambiguous)  printf '%s' "ambiguous — whether this is even wrong is your call, so fix printed it and did nothing" ;;
    human)      printf '%s' "yours — acting on this is unsafe even when the diagnosis is right, so fix did nothing" ;;
    *)          printf '%s' "unknown tier — treated as print-only" ;;
  esac
}

# fn_of <id> / fixfn_of <id> — the ONLY place a row's id becomes a function name. Both
# forms build the name the same way, which is what makes the one list one list.
fn_of() { printf 'check_%s' "$(printf '%s' "$1" | tr '-' '_')"; }
fixfn_of() { printf 'fix_%s' "$(printf '%s' "$1" | tr '-' '_')"; }

# git_ok <dir> — is this a git checkout we may ask questions of? Every caller treats "no"
# as a reportable fact, never an error.
git_ok() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# =========================================================================================
# CHECK 1 — template-behind (idempotent)
# =========================================================================================
# THE FACT: a stamp taken from this template clone would deliver what `origin` has.
#
# TWO EVIDENCE LINES, BECAUSE THE VERSION ALONE CANNOT SEE THIS. `check-template-version.sh`
# compares the `VERSION` file and is deliberately coarse — it detects drift across a bump
# and nothing finer, and its own header says a checkout parked on an old commit whose
# VERSION happens to equal the remote's is invisible to it. That invisible case is exactly
# what was measured twice in one day: stamping at `61535c9` while the default branch was
# three merges ahead reported `ok … (already linked)` for everything and changed nothing —
# output indistinguishable from a real stamp. So this row asks the commit graph too.
#
# THE VERSION VERDICT IS NOT RECOMPUTED HERE. It is delegated verbatim to the shipped
# helper, so there is no second reader of that question to drift from the first.
#
# NO NETWORK UNLESS ASKED. Without `--fetch` the comparison reads the remote-tracking ref
# already on disk, which can only ever UNDER-report — never a false alarm, and never a
# command that waits on a socket.
check_template_behind() {
  _warned=0
  local st here there pname state
  if [ -z "$TEMPLATE" ]; then
    # NO CHECKOUT ⇒ THE PLUGIN INSTALL IS THE SUBJECT, and it is judged by the very helper
    # the banner's Update row reads, so this row and that one can never disagree.
    if [ ! -f "$BIN/check-template-version.sh" ]; then
      good "plugin version: no checkout around this plugin, so drift cannot be judged"
      note "cannot compare VERSION drift: no check-template-version.sh at $BIN"
      return 0
    fi
    if [ "$FETCH" -eq 1 ]; then
      state="$(bash "$BIN/check-template-version.sh" --plugin "$PLUGIN_ROOT" --instance "$ROOT" --state --fetch 2>/dev/null)"
    else
      state="$(bash "$BIN/check-template-version.sh" --plugin "$PLUGIN_ROOT" --instance "$ROOT" --state 2>/dev/null)"
    fi
    IFS="$(printf '\t')" read -r st here there pname <<<"$state"
    case "${st:-}" in
      behind)  warn "plugin ${here} is behind the marketplace, which carries ${there}"
               hint "claude plugin update ${pname:-$PLUGIN_NAME}   (then restart Claude Code)" ;;
      current) good "plugin version: ${here} is what the marketplace's default branch carries" ;;
      *)       good "plugin version: the marketplace could not be read, so drift is not judged"
               note "a plugin installed from a marketplace has one; a vendored copy may not" ;;
    esac
    return "$_warned"
  fi
  if ! git_ok "$TEMPLATE"; then
    good "template clone at $TEMPLATE is not a git checkout — nothing to compare it to"
    return 0
  fi

  if [ "$FETCH" -eq 1 ]; then
    # A failed fetch is never a verdict. `GIT_TERMINAL_PROMPT=0` because the failure that
    # must not happen here is not an error, it is a HANG: an expired credential otherwise
    # asks for a username on the human's terminal.
    GIT_TERMINAL_PROMPT=0 git -C "$TEMPLATE" fetch --quiet origin >/dev/null 2>&1 || \
      note "(--fetch could not reach origin; comparing against the ref already on disk)"
  fi

  local ref behind version
  ref="$(git -C "$TEMPLATE" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -z "$ref" ]; then
    good "template clone: no origin/HEAD to compare against, so being behind cannot be seen"
    note "git -C $TEMPLATE remote set-head origin --auto   teaches it the default branch"
  else
    behind="$(git -C "$TEMPLATE" rev-list --count "HEAD..$ref" 2>/dev/null)"
    case "$behind" in
      ''|*[!0-9]*) good "template clone: cannot count commits against $ref, so it is not judged" ;;
      0)           good "template clone is level with $ref — a stamp from here delivers what origin has" ;;
      *)           warn "template clone is $behind commit(s) behind $ref — a stamp from here would be inert"
                   note "it would print 'already linked' for everything and change nothing"
                   hint "git -C $TEMPLATE pull --ff-only" ;;
    esac
  fi

  # The version half, delegated. Its output is multi-line and already written for a human.
  # `--fetch` is NOT passed on even when we were given it: the fetch above already updated
  # the remote-tracking ref this helper reads, so passing it would be a second network
  # round-trip for an answer that is already on disk.
  #
  # AND ITS ABSENCE IS ITSELF REPORTED. Silence here would let a level commit graph print a
  # clean row while the VERSION half of the same question went unasked — the one shape this
  # file exists to prevent, since "no line" and "nothing wrong" would then look identical.
  # A `note`, not a `warn`: a helper this instance never received is not a defect, and the
  # SessionStart path (`--only-problems`) drops it.
  if [ -f "$BIN/check-template-version.sh" ]; then
    version="$(bash "$BIN/check-template-version.sh" --template "$TEMPLATE" --instance "$ROOT" 2>/dev/null)"
    if [ -n "$version" ]; then
      _warned=1
      printf '%s\n' "$version" | sed 's/^/    /'
    fi
  else
    note "cannot compare VERSION drift: no check-template-version.sh at $BIN"
  fi
  return "$_warned"
}

# fix_template_behind — `git pull --ff-only`, and nothing else, ever.
#
# `--ff-only` IS THE IDEMPOTENCE. A merge or a rebase can conflict, and a conflicted
# template clone is a worse state than a stale one: it is stale AND now has a half-written
# working tree that a stamp would ship into every instance at once. Fast-forward or refuse.
# A dirty working tree refuses before the network call for the same reason.
fix_template_behind() {
  [ -n "$TEMPLATE" ] || { note "nothing to pull: no template checkout located"; return 0; }
  git_ok "$TEMPLATE" || { note "nothing to pull: $TEMPLATE is not a git checkout"; return 0; }
  if [ -n "$(git -C "$TEMPLATE" status --porcelain 2>/dev/null)" ]; then
    note "NOT pulled: the template checkout has uncommitted changes."
    note "A pull here is only safe when it is a fast-forward onto a clean tree. Deal with"
    note "those changes first: git -C $TEMPLATE status"
    return 0
  fi
  note "running: git -C $TEMPLATE pull --ff-only"
  if GIT_TERMINAL_PROMPT=0 git -C "$TEMPLATE" pull --ff-only 2>&1 | sed 's/^/      /'; then
    return 0
  fi
  note "the pull did not fast-forward — the checkout is unchanged. The supported route is"
  note "/plugin update ${PLUGIN_NAME}@${PLUGIN_MARKETPLACE}, then restart Claude Code."
  return 0
}

# =========================================================================================
# CHECK 2 — bundle-unconverted (idempotent)
# =========================================================================================
# THE FACT: this bundle carries machinery symlinks into a template checkout, and/or seed
# documents this template has changed since the bundle was stamped.
#
# THIS ROW REPLACED `unstamped-machinery`, AND THE QUESTION INVERTED. That check asked
# which of the template's machinery files were NOT linked here, because a stamp was how a
# new machinery file reached a bundle. There is no machinery in a bundle now — it runs
# from the plugin root — so the question worth asking is the opposite one: is anything
# still linked? A LIVE link is as wrong as a dead one, and quieter: it resolves into a
# checkout that `claude plugin update` never touches, so the bundle runs machinery frozen
# at whatever that clone last pulled, with nothing anywhere saying so.
#
# THE OTHER HALF — a seed document a stamp cannot deliver — is CHECK 3 below, and it is a
# separate row on purpose: it has something to say on a healthy bundle, so it stays off the
# banner path while this one, which does not, stays on it.
#
# EMPTY IS AN ANSWER, NOT SILENCE. "No links at all" is the useful answer on most days and
# it prints as a `✓` line.
check_bundle_unconverted() {
  _warned=0
  # A walk of the whole bundle, not a probe list: the set of paths the old installer
  # stamped changed across template versions, so a closed list is wrong for exactly the
  # oldest bundles. `repos/` is excluded because it IS the derived view the stamp
  # maintains, and `find` does not follow symlinks so it cannot descend into a linked
  # repo. `.git` is pruned for speed.
  local l rel n=0 dead=0 shown=""
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    rel="${l#"$ROOT"/}"
    # THE SAME EXCLUSIONS THE SWEEP USES, and they have to be the same or this row warns
    # about something `/<plugin>:init` will never remove: `repos/` is the derived view,
    # and `projects/`, `knowledge/` and `objectives/` are DATA, where no installer ever
    # stamped machinery and a symlink is therefore the human's own.
    case "$rel" in
      repos|repos/*|projects|projects/*|knowledge|knowledge/*|objectives|objectives/*) continue ;;
    esac
    n=$((n + 1))
    [ -e "$l" ] || dead=$((dead + 1))
    [ "$n" -le 12 ] && shown="${shown:+$shown
}    $rel"
  done <<EOF
$(find "$ROOT" -name .git -prune -o -type l -print 2>/dev/null | sort)
EOF

  if [ "$n" -eq 0 ]; then
    good "no symlinks outside repos/ and the data dirs — no machinery, no template link"
    return 0
  fi
  _warned=1
  warn "$n symlink(s) outside repos/ and the data dirs — this bundle has not been converted ($dead already dead)"
  printf '%s\n' "$shown"
  [ "$n" -gt 12 ] && note "… and $((n - 12)) more"
  note "the machinery ships in the plugin now; a link into a checkout is frozen there"
  hint "/${PLUGIN_NAME}:init $ROOT"
  return "$_warned"
}

# check_bundle_unmigrated — plugin-owned files still sitting at the bundle ROOT.
#
# HUMAN TIER, and that is the whole point: the repair MOVES tracked files, which is not an
# idempotent repair this pass may make on its own. It names every file and prints the one
# command. Between a plugin update and the migration every reader looks at a path that is
# not there, and each of them treats absence as an off switch — so an un-migrated bundle
# reads as a switched-off one unless something says otherwise. This is that something.
check_bundle_unmigrated() {
  if ! ab_unmigrated "$ROOT"; then
    good "the 3.0 layout: plugin-owned files are under $AB_DIR/"
    return 0
  fi
  local pair old
  warn "plugin-owned files are still at the bundle root — this bundle predates the 3.0 layout"
  for pair in $AB_MOVES; do
    old="${pair%%:*}"; [ -e "$ROOT/$old" ] && printf '    %s -> %s\n' "$old" "${pair#*:}"
  done
  note "every reader looks at the new path, and an absent one reads as 'switched off'"
  hint "cd $ROOT && migrate-bundle.sh        # then again with --apply"
  return 1
}

# fix_bundle_unconverted — run the bundle installer this plugin ships.
#
# `init-bundle.sh` removes machinery links, seeds-if-absent and retires the managed
# `.gitignore` block. It never removes bundle content and never overwrites a file the
# bundle owns. That is what makes re-running it the idempotent repair rather than a risk.
fix_bundle_unconverted() {
  if [ ! -f "$BIN/init-bundle.sh" ]; then
    note "NOT stamped: $BIN/init-bundle.sh is missing — re-install the plugin"
    return 0
  fi
  # The stamp inherits AI_BRIDGE_INIT_PASS and runs no pass — one extra stamp, never a loop.
  note "running: bash $BIN/init-bundle.sh $ROOT"
  bash "$BIN/init-bundle.sh" "$ROOT" 2>&1 | sed 's/^/      /'
  return 0
}

# =========================================================================================
# CHECK 3 — seed-drift (idempotent, and deliberately NOT on the banner path)
# =========================================================================================
# THE FACT: this template has changed a seed document since this bundle was stamped, and a
# stamp alone cannot deliver it — `seed/` is copied only where a path is ABSENT.
#
# `banner:no`, AND THAT IS THE WHOLE REASON IT IS ITS OWN ROW. Every bundle edits its
# `instance.config.json` and most edit `CLAUDE.md`, so this row has something to say on a
# perfectly healthy bundle — which on a SessionStart banner is wallpaper, and wallpaper is
# how the lines that matter come to be skipped. It belongs in `check`, where somebody asked.
#
# UNKNOWN IS A NOTE, NEVER A WARNING. "No merge base, so I cannot tell" is the shape every
# other row here reports as a fact; a plugin vendored without its git history would
# otherwise warn about every seed document there is.
check_seed_drift() {
  _warned=0
  if [ ! -f "$BIN/refresh-seeds.sh" ]; then
    note "cannot compare seed drift: no refresh-seeds.sh at $BIN"
    return 0
  fi
  local report drift unknown
  report="$(bash "$BIN/refresh-seeds.sh" "$ROOT" 2>/dev/null || true)"
  drift="$(printf '%s\n' "$report" | grep -E '^  (PORTABLE|DECIDABLE|CONFLICT) ' || true)"
  unknown="$(printf '%s\n' "$report" | grep -cE '^  UNKNOWN ' || true)"
  if [ -n "$drift" ]; then
    _warned=1
    warn "seed documents have drifted from this template — a stamp cannot deliver a seed edit"
    printf '%s\n' "$drift" | sed 's/^  /    /'
    hint "/${PLUGIN_NAME}:init $ROOT   (3-way merges what it can; conflicts stay yours)"
  else
    good "seed documents are in step with this template — nothing to port"
  fi
  if [ "${unknown:-0}" -gt 0 ] 2>/dev/null; then
    note "$unknown seed document(s) differ with no merge base to judge them by"
  fi
  return "$_warned"
}

# fix_seed_drift — the 3-way merge, applied.
#
# NEVER A COPY, AND NEVER OVER A CONFLICT. `refresh-seeds.sh --apply` writes the MERGE
# RESULT of (bundle, old seed, new seed) and reads it back; a hand-diverged file that
# conflicts is left exactly as it is and the conflicted merge is saved beside it as
# `.bak.<epoch>`. That is what makes this the idempotent tier rather than the human one.
fix_seed_drift() {
  if [ ! -f "$BIN/refresh-seeds.sh" ]; then
    note "NOT ported: $BIN/refresh-seeds.sh is missing — re-install the plugin"
    return 0
  fi
  note "running: bash $BIN/refresh-seeds.sh $ROOT --apply"
  bash "$BIN/refresh-seeds.sh" "$ROOT" --apply 2>&1 | sed 's/^/      /'
  return 0
}

# =========================================================================================
# CHECK 4 — config-uncommitted (AMBIGUOUS — SHIP-BLOCKER: never repaired)
# =========================================================================================
# THE FACT: `instance.config.json` / `instance.config.local.json` carry changes git has not
# recorded. That is ALL this says. It is a QUESTION, never a defect.
#
# On 2026-08-30 an instance carried an uncommitted `maxPrLoc: 2000 -> 500` that was a
# deliberate decision by the owner, taken minutes earlier, and completely indistinguishable
# from drift to anything that reads only the file. There is no `fix_config_uncommitted` in
# this file and there must never be one: reverting, staging or rewriting either file would
# have destroyed that choice, silently, while printing a success line.
#
# WHY ONLY TOP-LEVEL KEY NAMES ARE NAMED, AND NO VALUES. This output can land in session
# context. `people` maps humans to commit ADDRESSES — the banner's settings table excludes
# it for exactly this reason — so nothing nested is named and no value is ever printed. The
# scope test is indentation: a top-level key in these files sits at two spaces, `people`
# and `roleTiers` entries at four. It is a heuristic on a file this machinery itself
# writes, and it fails in the safe direction (a reformatted file names fewer keys, never
# more). The exact `git diff` command is printed instead, for a human, in their terminal.
check_config_uncommitted() {
  _warned=0
  if ! git_ok "$ROOT"; then
    good "config changes: this instance is not a git checkout, so nothing can be compared"
    return 0
  fi

  local f st keys n
  for f in instance.config.json instance.config.local.json; do
    if [ ! -f "$ROOT/$f" ]; then
      continue
    fi
    # TRACKED FIRST, AND THAT ORDER IS THE WHOLE CORRECTNESS OF THIS CHECK. `git status
    # --porcelain -- <path>` prints NOTHING for an ignored file no matter how heavily it
    # has been edited, and `instance.config.local.json` is gitignored in every stamped
    # instance — so reading emptiness as "matches git" published a confident, false "no
    # uncommitted change" about the one file most likely to have been hand-edited. Measured
    # on a real instance before this branch existed. Ask git what it TRACKS, then ask what
    # changed; never infer the first from the second.
    if ! git -C "$ROOT" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      if git -C "$ROOT" check-ignore -q -- "$f" 2>/dev/null; then
        good "$f is git-ignored here — per-machine by design, so there is nothing to commit"
      else
        good "$f is untracked — git holds no version of it to differ from"
      fi
      continue
    fi
    st="$(git -C "$ROOT" status --porcelain -- "$f" 2>/dev/null)"
    if [ -z "$st" ]; then
      good "$f matches git — no uncommitted change"
      continue
    fi

    keys="$(git -C "$ROOT" diff HEAD -- "$f" 2>/dev/null \
            | sed -n 's/^[+-]  \("[A-Za-z_$][A-Za-z0-9_$]*"\).*/\1/p' \
            | tr -d '"' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    n="$(printf '%s' "$st" | sed -n '1s/^\(..\).*/\1/p')"
    warn "$f has uncommitted changes${keys:+ (${keys})}"
    note "git status code: '$n' (XY from git status --porcelain)"
    note "THIS IS A QUESTION, NOT A DEFECT — a value here can be a decision somebody made"
    note "minutes ago, and fix will not write, revert or stage this file. You decide:"
    hint "yours, not fix's: git -C $ROOT diff -- $f"
  done
  return "$_warned"
}

# =========================================================================================
# CHECK 5 — config-layers (ambiguous — nothing to repair, by construction)
# =========================================================================================
# THE FACT: which of the two config files won, per resolved key. A key can be set in the
# tracked file, read by everything, and still not be the one in force — `resolve-config.sh`
# merges `instance.config.local.json` over `instance.config.json` PER LEAF, so the answer
# differs entry by entry inside a map and is invisible in either file alone.
#
# DELEGATED, NEVER RE-DERIVED. `resolve-config.sh --dump` is the one implementation of that
# precedence; a second reader here is exactly the drift that would make this line lie.
#
# KEY NAMES ONLY, NEVER VALUES, AND NEVER `people`. Same boundary as the check above: this
# reaches session context, and that map holds commit addresses.
check_config_layers() {
  _warned=0
  if [ ! -f "$BIN/resolve-config.sh" ] || ! command -v python3 >/dev/null 2>&1; then
    good "config layers: not resolvable here (resolve-config.sh or python3 absent)"
    return 0
  fi
  local dump local_keys tracked_keys tracked_n local_n
  dump="$(bash "$BIN/resolve-config.sh" --instance "$ROOT" --dump 2>/dev/null || true)"
  if [ -z "$dump" ]; then
    good "config layers: nothing resolved (no readable config in $ROOT)"
    return 0
  fi
  # `<source> TAB <key> TAB <entry> TAB <value>`; field 4 is never read here.
  tracked_n="$(printf '%s\n' "$dump" | awk -F'\t' '$1=="tracked" && $2!="people"' | wc -l | tr -d ' ')"
  local_n="$(printf '%s\n' "$dump"   | awk -F'\t' '$1=="local"   && $2!="people"' | wc -l | tr -d ' ')"
  local_keys="$(printf '%s\n' "$dump" | awk -F'\t' '$1=="local" && $2!="people" {print ($3=="" ? $2 : $2 "." $3)}' \
                | sort -u | tr '\n' ' ' | sed 's/ $//')"
  tracked_keys="$(printf '%s\n' "$dump" | awk -F'\t' '$1=="tracked" && $2!="people" {print ($3=="" ? $2 : $2 "." $3)}' \
                  | sort -u | tr '\n' ' ' | sed 's/ $//')"
  # Counted per RESOLVED LEAF, not per top-level key, because that is the granularity the
  # precedence actually works at: a one-line local override moves one entry of `roleTiers`
  # and leaves every other entry tracked, and a per-file count would report that as the
  # whole map having been overridden.
  # BOTH SIDES ARE NAMED, not just the surprising one. "which layer won" has to be
  # answerable FOR EACH KEY, and a list of only the local winners leaves the reader
  # inferring the rest from a count — which is the same half-answer as printing the file
  # and letting them work out what is in force.
  if [ "$local_n" -gt 0 ]; then
    good "config resolves: $((local_n + tracked_n)) keys — $local_n from local, $tracked_n from tracked"
    note "local:   $local_keys"
    [ -n "$tracked_keys" ] && note "tracked: $tracked_keys"
  else
    good "config resolves: $tracked_n keys, all from tracked — no local override is in force"
    [ -n "$tracked_keys" ] && note "tracked: $tracked_keys"
  fi
  # NO TRAILING CAVEAT LINE. "values are not shown here" would read the same on a healthy
  # instance and a broken one, which is this command's own test for a line that does not
  # belong. Why values and `people` stay out is stated above, where the next editor reads it.
  return 0
}

# =========================================================================================
# CHECK 6 — config-unknown-keys (ambiguous — a key nothing reads may still be somebody's intent)
# =========================================================================================
# THE FACT: whether either config file carries a top-level key the machinery does not know.
# Nothing else validates config keys, so a retired key sits in the file looking
# authoritative long after its reader was deleted — the published board's URL key
# outlived that feature's deletion in two of three live instances (audit 2026-08-31;
# its literal is banished from this tree by tests/banner-board-line.test.sh, which is
# why it is described rather than named here) — and a
# typo'd key silently configures nothing, the "a config switch is inert until something
# reads it" class the KB records.
#
# THE KNOWN SET IS THE SEED'S OWN KEY LIST — `seed/instance.config.json`, read from THIS
# PLUGIN rather than from the checkout around it — because the seed ships every key the
# machinery reads, and a name list here would be a second copy that drifts. From the plugin
# because that is where the seed now lives (task-022), and because it is the only one of
# the two that exists on a machine that installed the plugin and never cloned this repo:
# resolving it from `$TEMPLATE` degraded this row to a non-answer on exactly those
# machines, which is every ordinary install. Keys beginning `$` are
# comments by convention, on both sides. FIVE additions, each justified by its reader the
# way the tool vocabulary's hand-list entries are, and each never seeded for the same
# reason — seeding a per-machine key writes one machine's answer into every clone:
#   · `ownerGithubUser` — per-machine by design (docs/sharing.md); `task-owner.sh` reads it;
#   · `reposRoot`, `worktreeRoot`, `boardInstances` — per-machine paths, read by
#     `link-repos.sh`, `prune-worktrees.sh` and `build-board.sh` from EITHER file, so they
#     are known in both. `normalise-config.sh` is what reports a tracked copy, because
#     that is misplacement rather than a key nothing reads;
#   · `boardArtifactUrl` — the page `/<plugin>:board publish` published FROM THIS CLONE.
#     **Known in `instance.config.local.json` ONLY**, which is where it differs from the
#     entry above and why the known set is built per file. Publishing is account-scoped,
#     so exactly one account can update a given page; `session-banner.sh` reads it from
#     the local layer and drops a `tracked` value in silence, so a tracked copy is read by
#     NOTHING and this check must say so rather than bless it. It is deliberately NOT in
#     `seed/instance.config.json`, and tests/banner-board-line.test.sh fails if it appears
#     there.
#
# AMBIGUOUS TIER, NO FIXER, for the `maxPrLoc` reason: deleting a key could delete a
# decision. `fix` prints it and does nothing. No template seed to compare against — a
# hand-copied deployment, a moved checkout — degrades to a reported non-answer, never a
# guess in either direction.
check_config_unknown_keys() {
  _warned=0
  if ! command -v jq >/dev/null 2>&1; then
    good "config keys: not resolvable here (jq absent)"
    return 0
  fi
  local seedcfg known f k unknown
  seedcfg="$PLUGIN_ROOT/seed/instance.config.json"
  if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$seedcfg" ]; then
    good "config keys: not resolvable here (no template seed to compare against)"
    return 0
  fi
  known="$(jq -r 'keys[]' "$seedcfg" 2>/dev/null | grep -v '^\$')" || known=""
  if [ -z "$known" ]; then
    good "config keys: not resolvable here (the template seed did not parse)"
    return 0
  fi
  known="$known
ownerGithubUser
reposRoot
worktreeRoot
boardInstances"

  # A file jq cannot parse yields NO keys, and no keys reads exactly like no unknown keys —
  # a false healthy about a corrupt config, the false-zero class this file's own header
  # names as the one to guard. So the parse status is captured per file and an unparseable
  # file gets a non-answer, never a clean bill.
  # ONE KEY IS KNOWN IN ONE FILE ONLY, and making that per-file is the whole point rather
  # than a refinement of it. `boardArtifactUrl` is read from the LOCAL layer and nowhere
  # else (SCHEMA.md → "Per-machine config overrides"; `session-banner.sh` checks the
  # source and drops a `tracked` value in silence), so a tracked copy is read by NOTHING —
  # which is precisely the "looks authoritative, configures nothing" state this check
  # exists to name. Adding it to the global set would have made that state pass as
  # healthy, and it is the exact shape the key was deleted for the first time round.
  unknown=""; unparsed=""; fkeys=""
  for f in instance.config.json instance.config.local.json; do
    [ -f "$ROOT/$f" ] || continue
    fknown="$known"
    if [ "$f" = "instance.config.local.json" ]; then
      fknown="$fknown
boardArtifactUrl"
    fi
    if ! fkeys="$(jq -r 'keys[]' "$ROOT/$f" 2>/dev/null)"; then
      unparsed="${unparsed:+$unparsed }$f"
      continue
    fi
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      case "$k" in \$*) continue ;; esac
      if ! printf '%s\n' "$fknown" | grep -qFx -- "$k"; then
        unknown="${unknown:+$unknown }$f:$k"
      fi
    done <<EOF
$fkeys
EOF
  done

  if [ -z "$unknown" ]; then
    # Exactly ONE headline either way — the banner's row count depends on it. A corrupt
    # file is a non-answer about ITS keys, not a clean bill for the instance.
    if [ -n "$unparsed" ]; then
      good "config keys: no answer for $unparsed — not parseable as JSON, so its keys cannot be judged"
    else
      good "config keys: every top-level key is one the machinery knows"
    fi
    return 0
  fi
  warn "config carries key(s) nothing reads: $unknown"
  [ -n "$unparsed" ] && note "(and no answer for $unparsed — not parseable as JSON)"
  note "a retired or typo'd key looks authoritative and configures nothing; the known set"
  note "is the template seed's key list, plus ownerGithubUser in either file and"
  note "boardArtifactUrl in instance.config.local.json only — nothing reads a tracked one"
  note "THIS IS A QUESTION, NOT A DEFECT — the key may be a decision; fix will not touch it"
  hint "yours, not fix's: edit the file, or compare: jq -r 'keys[]' $ROOT/instance.config.json"
  return "$_warned"
}

# =========================================================================================
# CHECK 7 — tick-lock (HUMAN — SHIP-BLOCKER: never repaired)
# =========================================================================================
# THE FACT: whether an `/<plugin>:dispatch` tick lock is held, claimed, or past its staleness
# threshold. The verdict is `tick-lock.sh status`'s, replayed here — this file has no
# opinion about what stale means and must never grow one, or the two would drift about the
# only question that matters.
#
# THERE IS NO `fix_tick_lock`, AND THERE MUST NEVER BE ONE. `tick-lock.sh release`
# is documented as the HUMAN's override. A tick that dispatched role agents can legitimately
# run long, so "stale" is a threshold, not a death certificate; clearing a lock on that
# evidence re-opens the double-dispatch that ran two ticks concurrently for 34 minutes on
# 2026-08-29, doing the same refinement work twice. Neither `.tick-lock` nor
# `.tick-lock.claim` is written, removed or rewritten anywhere in this file.
#
# `status` IS THE READ-ONLY PROBE and it is the right one to call here — the prohibition in
# `/<plugin>:dispatch` is on a LAUNCHER calling `status` before `acquire`, which would rebuild the
# check-then-write race `acquire` exists to close. This command dispatches nothing.
check_tick_lock() {
  _warned=0
  local sh out rc
  # The plugin's copy, and only that one: a bundle no longer carries a `scripts/`
  # directory, so the old bundle-first lookup could only ever find an unconverted
  # bundle's frozen link.
  sh=""
  [ -f "$BIN/tick-lock.sh" ] && sh="$BIN/tick-lock.sh"
  if [ -z "$sh" ]; then
    good "tick lock: tick-lock.sh is not installed here, so no lock is being kept"
    return 0
  fi

  out="$(bash "$sh" status --instance "$ROOT" 2>&1)"; rc=$?
  case "$rc" in
    0) good "no tick lock held — the next dispatch tick takes it"
       case "$out" in *"$AB_LOCK_CLAIM"*) note "note: a claim file outlived its lock; the next acquire clears it" ;; esac ;;
    1) good "an /${PLUGIN_NAME}:dispatch tick is in flight (this is a live lock, not a fault)"
       printf '%s\n' "$out" | sed -n '1,3p' | sed 's/^/    /'
       case "$out" in *"No tick has claimed it yet"*) note "unclaimed: taken for a dispatch that is starting" ;; esac ;;
    *) warn "the tick lock needs YOUR decision — this is not repaired for you"
       printf '%s\n' "$out" | sed -n '1,4p' | sed 's/^/    /'
       note "a long tick is not a dead one. If you decide it is dead, YOU release it:"
       hint "yours, not fix's: bash $sh release --instance $ROOT" ;;
  esac
  return "$_warned"
}

# =========================================================================================
# CHECK 8 — orphan-processes (HUMAN — never repaired)
# =========================================================================================
# THE FACT: processes of YOURS whose parent is gone (`ppid 1`) are still running out of a
# directory under `worktreeRoot`. Nothing on this machine will ever reap them.
#
# WHY THIS ROW EXISTS. Measured 2026-08-31: an agent generating CPU load to reproduce a
# flaky suite left 34 orphans across three batches, every one with `ppid 1`, at ~24% of a
# core each — load average 310, 0% idle. The owner found it in Activity Monitor. The
# machinery that manages those very worktrees never noticed: `prune-worktrees.sh` does look
# for live processes, but only when somebody prunes, and it does not ask whose they are.
# This row is the line that would have printed all 34 at the next session start.
#
# `ppid 1` AND YOUR OWN UID ARE THE WHOLE FILTER, and together they are what make this
# narrow enough to print at all. A live process under a worktree is ordinary — an editor, a
# dev server someone is watching, this session. A live process under a worktree WHOSE PARENT
# IS GONE is nobody's by construction: there is no shell left to press Ctrl-C in. Own-uid,
# because another user's daemon is not this instance's business and its cwd is unreadable
# anyway (measured on the machine that produced the incident: 449 `ppid 1` processes, 200 of
# them other users' with no readable cwd; own-uid alone, 248 candidates and 248 cwds read).
#
# IT NEVER REPORTS ZERO ON A QUESTION IT COULD NOT ASK. Four ways it cannot answer, each
# said out loud instead: no config reader, no worktree root to compare against, no `ps`, or
# no readable cwd (neither `lsof` nor `/proc`, or a restricted one). "None found" is printed
# ONLY after a scan that could have found one, and it carries the two counts that make it
# checkable. Reporting zero on an unanswerable question is the failure this row is written
# against — see `CONVENTIONS.md`, "Anything you background must be reaped".
#
# NO COMMAND LINE IS EVER PRINTED, only `comm`. `check` output lands in session context and
# a full argv can carry a token or a path nobody chose to publish; the executable name is
# enough to recognise a spinner, and the human's own `ps -p` is one hint line away.
#
# TIER `human`, AND THERE IS NO `fix_orphan_processes`. A bounded background job is
# legitimate work and an orphan is not always a mistake — a deliberately detached build has
# `ppid 1` too. Killing a process on this evidence is exactly the class of repair this
# command does not perform.
check_orphan_processes() {
  _warned=0

  # WHERE TO LOOK: `worktreeRoot`, then the legacy `<reposRoot>/_wt`. The same two roots
  # `prune-worktrees.sh` scans and the same documented fallback, so the two readers cannot
  # come to disagree about where worktrees live. Delegated to `resolve-config.sh` for the
  # per-machine precedence rather than re-reading the files here.
  if [ ! -f "$BIN/resolve-config.sh" ] || ! command -v python3 >/dev/null 2>&1; then
    good "orphaned processes: the worktree roots are not resolvable here, so this is UNKNOWN"
    note "resolve-config.sh or python3 is absent — that is not a zero, it is an unasked question"
    return 0
  fi
  local wt repos d c roots=""
  wt="$(bash "$BIN/resolve-config.sh" --instance "$ROOT" worktreeRoot 2>/dev/null)" || wt=""
  repos="$(bash "$BIN/resolve-config.sh" --instance "$ROOT" reposRoot 2>/dev/null)" || repos=""
  # `${HOME:-}` and not `$HOME`: this file runs under `set -u`, and a session with HOME
  # unset would abort the whole check on a tilde nobody wrote.
  wt="${wt/#\~/${HOME:-}}"; repos="${repos/#\~/${HOME:-}}"
  local configured=0 unreachable=""
  for d in "$wt" "${repos:+$repos/_wt}"; do
    [ -n "$d" ] || continue
    configured=$((configured + 1))
    # Canonicalised, because `lsof` reports a resolved cwd and macOS symlinks /tmp and
    # /var — an unresolved prefix match misses every process and the scan becomes a
    # silent no-op that looks exactly like a clean machine.
    c="$(cd "$d" 2>/dev/null && pwd -P)" || c=""
    if [ -z "$c" ]; then unreachable="${unreachable:+$unreachable, }$d"; continue; fi
    case "$roots" in *"|$c|"*) continue ;; esac
    roots="${roots}|$c|"
  done
  if [ -z "$roots" ]; then
    if [ "$configured" -eq 0 ]; then
      good "orphaned processes: this instance names no worktree root, so there is nowhere to scan"
      note "neither worktreeRoot nor reposRoot resolves here — nothing was scanned, and nothing is claimed"
    else
      good "orphaned processes: every configured worktree root is unreadable, so this is UNKNOWN"
      note "could not enter: $unreachable"
    fi
    return 0
  fi

  if ! command -v ps >/dev/null 2>&1; then
    good "orphaned processes: no ps on PATH, so no process can be asked about its parent"
    note "UNKNOWN, not zero — nothing was enumerated"
    return 0
  fi

  # POSIX `ps`: `-u <uid>` selects by effective user, `-o <keyword>=` suppresses the header.
  # `pid`, `ppid`, `etime` and `comm` are all in the POSIX keyword set and behave the same on
  # the BSD `ps` macOS ships and the procps one Linux does. `comm` and NOT `args` — see the
  # header. A uid rather than a name: `ps -o user=` truncates a long login name on macOS.
  local uid pslist
  uid="$(id -u 2>/dev/null)" || uid=""
  if [ -z "$uid" ]; then
    good "orphaned processes: cannot read your own uid, so 'whose process is it' is UNKNOWN"
    return 0
  fi
  pslist="$(ps -u "$uid" -o pid=,ppid=,etime=,comm= 2>/dev/null)" || pslist=""
  if [ -z "$pslist" ]; then
    good "orphaned processes: ps returned nothing for uid $uid, so this is UNKNOWN"
    note "an empty process table is not a result — nothing was scanned"
    return 0
  fi

  # THE CANDIDATES: your processes whose parent is gone. `ppid 1` is what "reparented to
  # launchd/init" looks like from outside, and it is the signature every one of the 34 had.
  local cands pidlist n_cand
  cands="$(printf '%s\n' "$pslist" | awk '$2 == 1 && $1 != 1 {print}')"
  n_cand="$(printf '%s' "$cands" | grep -c . || true)"
  if [ "$n_cand" -eq 0 ]; then
    good "no process of yours has ppid 1 — no orphan exists to be in a worktree"
    return 0
  fi
  pidlist="$(printf '%s\n' "$cands" | awk '{printf "%s%s", sep, $1; sep=","}')"

  # CWD, FROM ONE SOURCE, CHOSEN IN A STATED ORDER. `lsof -d cwd` answers for every pid in
  # a single call (0.19s for 449 pids, measured) and is what `prune-worktrees.sh` already
  # uses; `/proc/<pid>/cwd` is the fallback where lsof is absent. Neither present is an
  # UNANSWERABLE question, not a clean scan.
  local cwds="" pid dir line readable=0
  if command -v lsof >/dev/null 2>&1; then
    pid=""
    while IFS= read -r line; do
      case "$line" in
        p*) pid="${line#p}" ;;
        n*) dir="${line#n}"
            [ -n "$pid" ] || continue
            cwds="${cwds}${pid} ${dir}
"
            readable=$((readable + 1)); pid="" ;;
      esac
    done <<EOF
$(lsof -a -d cwd -n -P -Fpn -p "$pidlist" 2>/dev/null)
EOF
  elif [ -d /proc ]; then
    for pid in $(printf '%s\n' "$cands" | awk '{print $1}'); do
      dir="$(readlink "/proc/$pid/cwd" 2>/dev/null)" || dir=""
      [ -n "$dir" ] || continue
      cwds="${cwds}${pid} ${dir}
"
      readable=$((readable + 1))
    done
  else
    good "orphaned processes: $n_cand of yours have ppid 1, and where they run is UNKNOWN"
    note "no lsof and no /proc, so no process cwd is readable on this machine"
    note "that is why this is not reported as none found"
    return 0
  fi
  if [ "$readable" -eq 0 ]; then
    good "orphaned processes: $n_cand of yours have ppid 1, and where they run is UNKNOWN"
    note "not one cwd was readable (a restricted lsof, or every candidate exited mid-scan)"
    return 0
  fi

  # THE MATCH. A prefix test against each canonical root, and the root itself counts: a
  # process sitting in the root directory of a removed worktree is as unreapable as one
  # inside a live worktree. Collected first and printed once, so the warn line carries the
  # TOTAL — the number the reader acts on — rather than a running count.
  local hits=0 pids_hit="" detail="" matched r
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pid="${line%% *}"; dir="${line#* }"
    matched=0
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      case "$dir" in "$r"|"$r"/*) matched=1; break ;; esac
    done <<EOF
$(printf '%s\n' "$roots" | tr '|' '\n')
EOF
    [ "$matched" -eq 1 ] || continue
    hits=$((hits + 1))
    pids_hit="${pids_hit:+$pids_hit }$pid"
    # `etime` is field 3 and `comm` is everything after it — a path with a space in it is
    # one field to `$4` and would print truncated.
    [ "$hits" -le 12 ] && detail="${detail}    pid $pid  up $(printf '%s\n' "$cands" \
      | awk -v want="$pid" '$1 == want {e=$3; $1=$2=$3=""; sub(/^ +/, ""); print e "  " $0; exit}')  in $dir
"
  done <<EOF
$cwds
EOF

  if [ "$hits" -eq 0 ]; then
    good "no orphan runs out of a worktree root ($n_cand of your processes have ppid 1, $readable cwds read)"
    return 0
  fi
  warn "$hits orphaned process(es) of yours (ppid 1) run out of a worktree — nothing will reap them"
  printf '%s' "$detail"
  [ "$hits" -gt 12 ] && note "… and $((hits - 12)) more not listed"
  note "a bound on the child is what stops this — $AB_CONVENTIONS, 'Anything you background'"
  hint "yours, not fix's: ps -p ${pids_hit%% *} -o command= ; then kill $pids_hit"
  return 1
}

# =========================================================================================
# THE DRIFT GUARD — a refusal, not a convention
# =========================================================================================
# TWO WAYS THE ONE LIST CAN BE WIRED WRONG, AND BOTH ARE FATAL RATHER THAN NOTED.
#
#   1. A `fix_<id>` defined for a row whose declared tier is NOT `idempotent`. That is the
#      exact shape of the two ship-blockers, and it is invisible in review the day somebody
#      adds one — a function beside four other functions, in a file full of them.
#   2. A row with no `check_<id>` at all. Bash would call a command that does not exist,
#      print `command not found` and hand back 127 — which this file's own convention reads
#      as "a problem was found", so an idempotent row added without its checker would go
#      straight to running its REPAIR on the strength of a typo.
#
# So neither is a rule: `check` and `fix` both REFUSE TO RUN, loudly, exit 2. `check` is
# guarded and not only `fix`, because a command that reports on an instance while carrying a
# fixer it must not have should not be trusted to report either. The banner form is already
# gone by here, by design: it repairs nothing, and its whole contract is that nothing comes
# between it and the hook.
assert_list_is_wired() {
  local id tier rogue="" unwired=""
  while IFS='|' read -r id tier _; do
    [ -n "$id" ] || continue
    declare -F "$(fn_of "$id")" >/dev/null 2>&1 || unwired="${unwired:+$unwired, }$id"
    [ "$tier" = idempotent ] && continue
    if declare -F "$(fixfn_of "$id")" >/dev/null 2>&1; then
      rogue="${rogue:+$rogue, }$(fixfn_of "$id") (tier: $tier)"
    fi
  done <<EOF
$CHECKS
EOF
  [ -z "$rogue" ] && [ -z "$unwired" ] && return 0
  if [ -n "$rogue" ]; then
    echo "${PLUGIN_NAME}: REFUSING TO RUN — a repair exists for a tier that must never be repaired:" >&2
    echo "           $rogue" >&2
    echo "           The tier declared in CHECKS is the only dispatch. Delete the function." >&2
  fi
  if [ -n "$unwired" ]; then
    echo "${PLUGIN_NAME}: REFUSING TO RUN — a row in CHECKS has no check function:" >&2
    echo "           $unwired" >&2
    echo "           Add check_<id>, or remove the row. A missing one reads as a problem." >&2
  fi
  exit 2
}
assert_list_is_wired

# rows_for <mode> — the one list, filtered. `banner` keeps only the rows that declare
# themselves fit for the SessionStart path. Every consumer below reads THIS list: `check`
# through here, `fix` and `--list` straight off `$CHECKS`. There is no second enumeration
# of checks anywhere in this file, which is the property the harness asserts.
rows_for() {
  if [ "$1" = banner ]; then
    printf '%s\n' "$CHECKS" | awk -F'|' '$3=="yes"'
  else
    printf '%s\n' "$CHECKS"
  fi
}

if [ "$LIST" -eq 1 ]; then
  printf '%s\n' "$CHECKS" | awk -F'|' '{printf "%s\t%s\t%s\n", $1, $2, $3}'
  exit 0
fi

# =========================================================================================
# FORM 2 — check
# =========================================================================================
if [ "$FORM" = check ]; then
  mode=all; [ "$BANNER_ONLY" -eq 1 ] && mode=banner
  header_printed=0
  while IFS='|' read -r id tier _; do
    [ -n "$id" ] || continue
    out="$("$(fn_of "$id")")"; rc=$?
    if [ "$ONLY_PROBLEMS" -eq 1 ]; then
      # THE SessionStart CONTRACT: only fire what is true. A clean instance prints
      # BYTE-NOTHING here, because a block that appears every session becomes wallpaper and
      # wallpaper is how the lines that matter come to be skipped.
      [ "$rc" -eq 0 ] && continue
      if [ "$header_printed" -eq 0 ]; then
        printf '%s\n' "⚠️  ${PLUGIN_NAME} check — state worth a look (/${PLUGIN_NAME}:welcome check for all of it):"
        header_printed=1
      fi
      # The verdict and its one command, nothing else. See `hint` above for the bound.
      printf '%s\n' "$out" | grep -e '^⚠' -e '^    ↳'
      continue
    fi
    printf '%s\n' "$out"
  done <<EOF
$(rows_for "$mode")
EOF
  exit 0
fi

# =========================================================================================
# FORM 3 — fix
# =========================================================================================
# THE SAME LIST, THE SAME ORDER, AND NO NAMES. This loop cannot tell you what
# `config-uncommitted` is; it reads the tier the row declares and dispatches on that alone.
# The two ship-blockers therefore hold by construction rather than by care: there is no
# branch here that could be pointed at a config file or a lock file.
if [ -z "${AI_BRIDGE_INIT_PASS:-}" ]; then
  echo "${PLUGIN_NAME} fix has moved into /${PLUGIN_NAME}:init — run that instead; it stamps the bundle and then runs this same pass."
  exit 0
fi
echo "${PLUGIN_NAME} fix — acting ONLY on the idempotent tier."
echo "                Config files and tick locks are NEVER written, reverted, staged,"
echo "                cleared or rewritten by this command. They are reported."
echo
while IFS='|' read -r id tier _; do
  [ -n "$id" ] || continue
  printf '%s\n' "── $id [$tier]"
  out="$("$(fn_of "$id")")"; rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo
    continue
  fi
  if [ "$tier" = idempotent ]; then
    fixfn="$(fixfn_of "$id")"
    if declare -F "$fixfn" >/dev/null 2>&1; then
      "$fixfn"
    else
      note "no repair is implemented for this row — reported only"
    fi
  else
    note "NOT ACTED ON — $(tier_note "$tier")"
  fi
  echo
done <<EOF
$CHECKS
EOF
exit 0
