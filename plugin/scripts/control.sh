#!/usr/bin/env bash
#
# control.sh — the operator side of the live kill switch. Steer, gate or cleanly
# halt ONE dispatched role agent while it is still running.
#
#   control.sh agents                        # who is in flight, with ids
#   control.sh halt  <agent-id> [reason...]   # stop it cleanly
#   control.sh gate  <agent-id> [reason...]   # pause its tool use
#   control.sh steer <agent-id>  note...      # one course correction
#   control.sh status                         # what is pending, what fired
#   control.sh clear <agent-id> | --all       # release
#   control.sh round <session-id>             # a resumed role session starts a fresh round
#   control.sh arm | disarm                   # turn the surface on / off
#   control.sh log [n]                        # the action log
#
# Enforcement happens in the `agent-control.sh` PreToolUse hook, which reads the
# files this script writes. Read that file's header for the design; this one is the
# human interface, and everything below is about being usable under pressure,
# because a kill switch nobody can find is not a kill switch.
#
# THE TWO HALVES ARE INSTALLED SEPARATELY, and an operator needs to know it here:
# this script is instance machinery, stamped by the installer, while the hook now
# ships with the plugin. Arming an instance whose plugin is not installed writes
# directives nothing reads — `status` still lists them, and nothing fires. The
# install steps are in the operations guide, deliberately not repeated here.
#
# ---------------------------------------------------------------- WHERE STATE LIVES
# `<instance>/.claude/control/`, created on demand:
#   directives   the control file — one pending directive per line, TAB-separated
#   agents       roster of agent ids the hook has observed, newest last
#   control.log  append-only record of every action the hook actually took
#   .gitignore   a single `*`, so the whole directory is invisible to git
#
# THE `.gitignore` IS NOT COSMETIC. This is machine-local runtime state. Committed,
# it would travel to another clone of a shared bundle and gate that human's agents
# from a file they never wrote. A `*` inside the directory ignores every file in it
# INCLUDING itself, so git sees the directory as empty and never tracks any of it —
# and an empty directory is not a thing git records. That keeps the whole feature
# out of `/<plugin>:init` and out of `seed/.gitignore`: it works identically on an
# instance stamped today and one stamped a year ago, with no installer run.
#
# ------------------------------------------------------------------- ARM / DISARM
# `.claude/control/` ABSENT means the hook is a strict no-op — no read, no write,
# no output. That is the `AUTONOMY.md` idiom: a deployment that never arms this has
# the capability off, with no edits anywhere. `disarm` removes the directory and
# the feature is gone until someone arms it again.
#
# Armed, the hook maintains the roster so `agents` can tell you what to halt. That
# is why arming is a separate act and worth doing BEFORE you need it: an agent
# dispatched while disarmed is not in the roster, and its id is not recorded
# anywhere else in the instance. On an instance running with `AUTONOMY.md` present,
# arm it once and leave it armed — armed-and-empty gates nothing.
#
# ------------------------------------------------------------ ONE LINE, ONE PLACE
# `oneline()` below is the SINGLE choke point where operator text becomes a record
# field, and it is the security boundary rather than tidiness: TAB is the field
# separator, and a newline or a carriage return in a reason would either split the
# record or forge the closing marker of the fence the hook injects it inside. Both
# failures are `push-state.sh`'s, measured there. Every reason and note goes
# through this function exactly once; the hook adds no second sanitising pass,
# because the record format itself then makes a raw newline unrepresentable.
#
# ---------------------------------------------------------- THE CAP REFUSES, LOUDLY
# `CONTROL_MAX` (default **20**) pending directives. Past that this script REFUSES
# to add another and prints what is pending, rather than FIFO-dropping the oldest
# the way the mechanism this is modelled on does. Silently dropping a halt is the
# one failure the whole feature exists to prevent, so the queue overflowing is a
# human decision about which directive to release.
#
# --------------------------------------------------- RECORDING A HALT IN THE BUNDLE
# The hook writes every action it takes to `control.log` — that is the durable
# record, and `status` surfaces it. This script additionally PRINTS the exact
# `log.md` bullet and its `commit-as.sh` command, and never runs either: the same
# report-the-command shape as `RETIRED`, `prune-worktrees.sh` and `/<plugin>:init`'s
# `git rm --cached`. Two reasons. `log.md` is tracked and several agents share one
# working tree, so a spontaneous diff there gets absorbed under the wrong author by
# whichever sibling stages `log.md` by name next. And whether a halt belongs in the
# bundle's permanent history is a judgement — a fat-fingered dispatch and an agent
# pushing to the wrong repo are not the same event.
#
# Verified by tests/agent-control.test.sh.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

usage() {
  cat <<'USAGE'
control.sh — steer, gate or cleanly halt ONE dispatched role agent, live.

  control.sh agents                        who is in flight, with ids
  control.sh halt  <agent-id> [reason...]  stop it cleanly
  control.sh gate  <agent-id> [reason...]  pause its tool use (alias: pause)
  control.sh steer <agent-id>  note...     one course correction, delivered once
  control.sh status                        what is pending, what fired
  control.sh clear <agent-id> | --all      release
  control.sh round <session-id>            restart a role session's clock and counters,
                                           before step 4 resumes it
  control.sh arm | disarm                  turn the surface on / off
  control.sh log [n]                       the action log

Absent `.claude/control/` means the PreToolUse hook is a strict no-op. `disarm`
removes it. Env: CONTROL_MAX (pending directives, default 20).
USAGE
  exit "${1:-1}"
}

# ------------------------------------------------------------------ the instance
# Walk up for the instance root, so this works from anywhere inside the bundle.
# The same pair the hooks use. `.claude/agents` was a third condition until the name
# swap retired it — the role agents ship in the `loopd` plugin now, so testing for
# that directory would refuse in every instance rather than in none.
find_root() {
  d="$(pwd -P)"
  while [ "$d" != / ]; do
    if ab_is_bundle "$d"; then
      printf '%s\n' "$d"; return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

MAX="${CONTROL_MAX:-20}"
case "$MAX" in ''|*[!0-9]*) MAX=20 ;; esac
MAX=$((10#$MAX))
[ "$MAX" -gt 0 ] || MAX=20

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# THE SINGLE CHOKE POINT. See the header. A tab or a carriage return becomes its
# two-character escape (a tab would split the record, a CR would let the text
# forge the hook's closing fence marker), a newline becomes a literal `\n`, and
# anything else in [[:cntrl:]] becomes `?`. Lossy on purpose — the property that
# matters is "one line, no control characters", not round-tripping.
oneline() {
  printf '%s' "$*" | LC_ALL=C awk '
    { gsub(/\t/, "\\t"); gsub(/\r/, "\\r"); gsub(/[[:cntrl:]]/, "?")
      printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }
  '
}

# An agent id is a harness-generated identifier. Reject whitespace, control
# characters and anything over 128 bytes — not to guess its alphabet (which would
# make a real id unhaltable the day it changes), but because the record format
# cannot represent those and a reason field that swallows the id is worse than a
# refusal.
check_id() { # <id>
  case "$1" in
    '' ) echo "error: no agent id. Run 'control.sh agents' to see them." >&2; return 1 ;;
    *[[:space:]]*|*[[:cntrl:]]* )
      echo "error: agent id contains whitespace or a control character: '$1'" >&2; return 1 ;;
  esac
  if [ "${#1}" -gt 128 ]; then
    echo "error: agent id is longer than 128 characters." >&2; return 1
  fi
  return 0
}

# Counts real records, ignoring the header comment and blank lines. awk rather
# than `grep -c`, because `grep -c` exits 1 on a zero count and the obvious
# `|| echo 0` fallback then prints the count TWICE — a false "00" pending.
pending_count() {
  [ -f "$DIRECTIVES" ] || { echo 0; return 0; }
  awk '!/^[[:space:]]*(#|$)/ { n++ } END { print n+0 }' "$DIRECTIVES" 2>/dev/null || echo 0
}

armed() { [ -d "$CTL" ]; }

arm() { # <quiet?>
  if [ ! -d "$CTL" ]; then
    mkdir -p "$CTL" || { echo "error: could not create $CTL" >&2; exit 1; }
  fi
  # `*` ignores every file here including this .gitignore itself, so git sees the
  # directory as empty and tracks none of it. Rewritten if missing or changed, so
  # a hand-edit that would expose the state cannot survive the next command.
  if [ ! -f "$CTL/.gitignore" ] || [ "$(cat "$CTL/.gitignore" 2>/dev/null)" != '*' ]; then
    printf '*\n' > "$CTL/.gitignore" || { echo "error: could not write $CTL/.gitignore" >&2; exit 1; }
  fi
  [ "${1:-}" = quiet ] || echo "armed  $CTL (agent control on; 'disarm' turns it off completely)"
}

# ------------------------------------------------------------------- the verbs
# PARSED BEFORE THE INSTANCE GUARD, so a printed `control.sh <verb> <id>` can be probed
# from a non-instance directory without reaching `arm` (tests/printed-commands.test.sh).
cmd="${1:-}"; [ -n "$cmd" ] || usage 1
shift || true
case "$cmd" in
  -h|--help|help) usage 0 ;;
  halt|gate|pause|steer|round) check_id "${1:-}" || exit 1 ;;
  arm|disarm|agents|status|log|clear) ;;
  *) echo "error: unknown command '$cmd'" >&2; usage 1 ;;
esac

ROOT="$(find_root)" || {
  echo "error: not inside a loopd instance (no instance.config.json)." >&2
  echo "       Run this from an instance root." >&2
  exit 1
}

CTL="$ROOT/.claude/control"
DIRECTIVES="$CTL/directives"
ROSTER="$CTL/agents"
ACTIONLOG="$CTL/control.log"

case "$cmd" in

arm)
  # jq is a HARD requirement of the hook: the payload's tool_input is arbitrary
  # nested JSON, so a grep-based parser can be fooled by `"agent_id"` appearing
  # inside a tool argument, which would let a halted agent spoof past its halt.
  # The hook fails OPEN without jq, by design — so refuse to arm here instead,
  # which is the one moment a human is watching.
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required — the hook cannot read a PreToolUse payload safely without it," >&2
    echo "       and it fails OPEN rather than blocking work, so arming now would give you a" >&2
    echo "       kill switch that silently does nothing. Install jq, then arm." >&2
    exit 1
  fi
  arm
  echo "       Roster starts filling on the next agent tool call: control.sh agents"
  ;;

disarm)
  if ! armed; then echo "not armed (nothing to do)."; exit 0; fi
  n="$(pending_count)"
  rm -rf "$CTL" || { echo "error: could not remove $CTL" >&2; exit 1; }
  echo "disarmed  agent control is off; the hook is now a strict no-op."
  # `[ "$n" != 0 ] && echo …` as the LAST command in the branch made a successful disarm
  # of an empty queue exit 1, because the test itself is the exit status. The removal had
  # already happened, so the status contradicted the result — and a kill switch whose
  # "off" reports failure is one an operator stops trusting.
  if [ "$n" != 0 ]; then echo "          ${n} pending directive(s) went with it."; fi
  exit 0
  ;;

round)
  if ! armed; then echo "not armed — no clock to restart."; exit 0; fi
  # The hook files a role session under its id as-is only when it is a safe short name.
  case "$1" in *[!A-Za-z0-9._-]*) echo "error: not a session id: '$1'" >&2; exit 1 ;; esac
  [ "${#1}" -le 64 ] || { echo "error: not a session id: '$1'" >&2; exit 1; }
  rm -f "$CTL/agents.d/$1.started" "$CTL/agents.d/$1.capped" "$CTL/agents.d/$1.unclocked" "$CTL/repeats/$1" \
    "$CTL/stuck/$1" "$CTL/stuck/$1.n" "$CTL/stuck/$1.logged" \
    || { echo "error: could not reset $1" >&2; exit 1; }
  echo "round  $1: its wall clock, repeat and stuck-signature counters restart at its next tool call"
  ;;

agents)
  if ! armed; then
    echo "not armed — no roster. Run 'control.sh arm' (do it before you need it:"
    echo "an agent dispatched while disarmed is not recorded, and its id is not kept"
    echo "anywhere else in the instance)."
    exit 0
  fi
  if [ ! -s "$ROSTER" ]; then
    echo "no agents seen yet. The roster fills on a dispatched agent's first tool call."
    exit 0
  fi
  # Newest last in the file; shown newest first, which is what anyone reaching for
  # this under pressure actually wants. `tail -r` is BSD, `tac` is GNU, `cat` is
  # the honest fallback (oldest first) rather than no output at all.
  { tail -r "$ROSTER" 2>/dev/null || tac "$ROSTER" 2>/dev/null || cat "$ROSTER"; } \
    | awk -F'\t' 'BEGIN { printf "%-40s %-22s %s\n", "AGENT ID", "TYPE", "FIRST SEEN" }
                  { printf "%-40s %-22s %s\n", $1, $2, $3 }'
  echo
  ab_say_run "Halt one with:" control.sh halt '<agent-id>' '"<why>"'
  ;;

status)
  if ! armed; then echo "not armed — agent control is off (the hook is a strict no-op)."; exit 0; fi
  echo "armed    $CTL"
  n="$(pending_count)"
  echo "pending  ${n}/${MAX} directive(s)"
  if [ "$n" != 0 ]; then
    echo
    printf '%-8s %-40s %-22s %s\n' "VERB" "AGENT ID" "SET AT" "REASON"
    awk -F'\t' '/^[[:space:]]*(#|$)/ { next }
      { printf "%-8s %-40s %-22s %s\n", $1, $2, $3, $4 }' "$DIRECTIVES"
    echo
    ab_say_run "Release one with:" control.sh clear '<agent-id>'
    ab_say_run "     or all with:" control.sh clear --all
  fi
  if [ -s "$ACTIONLOG" ]; then
    echo
    echo "last actions the hook actually took (control.sh log for more):"
    tail -n 5 "$ACTIONLOG" | sed 's/^/  /'
  fi
  ;;

log)
  if ! armed || [ ! -s "$ACTIONLOG" ]; then echo "no actions recorded."; exit 0; fi
  tail -n "${1:-50}" "$ACTIONLOG"
  ;;

clear)
  if ! armed || [ ! -f "$DIRECTIVES" ]; then echo "nothing pending."; exit 0; fi
  target="${1:-}"
  if [ "$target" = --all ]; then
    n="$(pending_count)"
    rm -f "$DIRECTIVES"
    echo "cleared  ${n} directive(s). Every agent is released."
    exit 0
  fi
  check_id "$target" || exit 1
  before="$(pending_count)"
  tmp="$DIRECTIVES.tmp.$$"
  # Temp file BESIDE the target, then rename — never $TMPDIR: mktemp creates 0600
  # and a cross-filesystem mv degrades to copy-and-remove, where an interruption
  # leaves a half-written control file. Same reasoning as migrate-bundle.sh.
  awk -F'\t' -v id="$target" '$2 != id' "$DIRECTIVES" > "$tmp" \
    && mv "$tmp" "$DIRECTIVES" \
    || { rm -f "$tmp"; echo "error: could not rewrite $DIRECTIVES" >&2; exit 1; }
  after="$(pending_count)"
  removed=$((before - after))
  if [ "$removed" -eq 0 ]; then
    echo "no directive for $target (nothing changed)."
  else
    echo "cleared  ${removed} directive(s) for $target. It is released at its next tool call."
  fi
  ;;

halt|gate|pause|steer)
  verb="$cmd"; [ "$verb" = pause ] && verb=gate
  id="${1:-}"; check_id "$id" || exit 1
  shift || true
  raw="$*"
  if [ "$verb" = steer ] && [ -z "$raw" ]; then
    echo "error: steer needs a note — it exists to say what to do instead." >&2
    exit 1
  fi
  reason="$(oneline "${raw:-no reason given}")"
  # Bound the stored reason too, so the file the hook reads on every tool call
  # cannot be grown without limit from here.
  if [ "${#reason}" -gt 500 ]; then reason="$(printf '%s' "$reason" | cut -c1-500)"; fi

  arm quiet

  # Does a directive for this agent already exist? Decide BEFORE the cap, because a
  # replacement swaps a record rather than adding one, so it cannot grow the queue —
  # and refusing it would block exactly the operation you most need at a full queue:
  # escalating an agent already gated to a halt.
  replacing=0
  if [ -f "$DIRECTIVES" ] && awk -F'\t' -v id="$id" '$2 == id { found=1 } END { exit !found }' "$DIRECTIVES"; then
    replacing=1
  fi

  n="$(pending_count)"
  if [ "$replacing" -eq 0 ] && [ "$n" -ge "$MAX" ]; then
    echo "error: ${n} directives already pending and CONTROL_MAX is ${MAX}. Refusing to add" >&2
    echo "       another rather than dropping one — silently dropping a halt is the failure" >&2
    echo "       this whole mechanism exists to prevent. Release one first:" >&2
    echo >&2
    awk -F'\t' '/^[[:space:]]*(#|$)/ { next } { printf "         %-8s %s\n", $1, $2 }' "$DIRECTIVES" >&2
    echo >&2
    ab_say_run "        " control.sh clear '<agent-id>' >&2
    ab_say_run "        " control.sh clear --all >&2
    exit 1
  fi

  # A second directive for the same agent would make "the first match wins"
  # depend on file order, so replace rather than stack.
  if [ "$replacing" -eq 1 ]; then
    tmp="$DIRECTIVES.tmp.$$"
    awk -F'\t' -v id="$id" '$2 != id' "$DIRECTIVES" > "$tmp" && mv "$tmp" "$DIRECTIVES" || rm -f "$tmp"
    echo "note   replaced the directive already pending for $id"
  fi

  [ -f "$DIRECTIVES" ] || printf '%s\n' "# loopd agent control — <verb>\\t<agent-id>\\t<set-at>\\t<reason>. Written by control.sh." > "$DIRECTIVES"
  printf '%s\t%s\t%s\t%s\n' "$verb" "$id" "$(now)" "$reason" >> "$DIRECTIVES" \
    || { echo "error: could not write $DIRECTIVES" >&2; exit 1; }

  if ! awk -F'\t' -v id="$id" -v v="$verb" '$1 == v && $2 == id { found=1 } END { exit !found }' "$DIRECTIVES"; then
    echo "error: FAILED — the directive is not in $DIRECTIVES after writing it." >&2
    echo "       Do not assume the agent is stopped." >&2
    exit 1
  fi

  case "$verb" in
    halt)
      echo "HALT set for $id."
      echo "  It takes effect at that agent's NEXT tool call: the call is refused and the"
      echo "  agent is told to stop. It does not interrupt a command already running, and"
      echo "  an agent doing no tool calls at all is not reached."
      ab_say_run "  Release with:" control.sh clear "$id"
      echo
      echo "  If this halt belongs in the bundle's permanent history, add it yourself —"
      echo "  the hook deliberately never edits tracked files (see its header). Prepend to"
      echo "  $AB_LEDGER under a '## $(date -u +%Y-%m-%d)' heading:"
      echo
      echo "    * **Agent halted**: $id — $reason"
      echo
      ab_say_run "   " commit-as.sh human "\"chore: record halt of $id\"" -- "$AB_LEDGER"
      ;;
    gate)
      echo "GATE set for $id. Every tool call is refused until you clear it; the agent is"
      echo "  told to report what it was about to do and wait."
      ab_say_run "  Release with:" control.sh clear "$id"
      ;;
    steer)
      echo "STEER queued for $id — delivered once, at its next tool call, then consumed."
      echo "  The note does not change what the agent is allowed to do; it is context."
      ;;
  esac
  ;;

esac
