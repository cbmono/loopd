#!/usr/bin/env bash
# stall-counter.sh — a task stuck on the same blocker for maxStallRounds (default 2) rounds
# is escalated to the human instead of re-dispatched. PM-owned fields on the task doc:
# stall_count (consecutive rounds on one blocker) and last_blocker. Progress resets it:
# a changed blocker, a human edit (a capped task back in draft/ready), or --progress from
# the tick (PR activity it observed). Usage: record <task> --blocker <text> [--progress] |
# escalate <task> | status <task> | reset <task> (stall_count 0, last_blocker kept). Exit: 0
# under the cap (count on stdout), 1 at/over the cap (do not dispatch; run escalate), 2
# cannot answer, 3 write failed (temp-file writes, nothing partial). Reasoning:
# ai-bridge-next/task-011 and its Finding.
set -uo pipefail

# THE SELF PATH IS RESOLVED THROUGH THE SYMLINK, the same idiom and the same reason as
# resolve-model.sh: an instance stamped before `resolve-config.sh` shipped has no such file
# in its own `scripts/`, so a plain `dirname "$0"` would look there and miss it. Here that
# would not error — it would silently answer with the fallback cap while a configured one
# sat in the file — which is the class of silent wrong answer this repo refuses.
SELF="${BASH_SOURCE[0]:-$0}"
[ -L "$SELF" ] && SELF="$(readlink "$SELF" 2>/dev/null || printf '%s' "$SELF")"
HERE="$(cd -- "$(dirname -- "$SELF")" 2>/dev/null && pwd -P)" || HERE=""
DEFAULT_MAX=2

usage() {
  sed -n '6,9p' "$0" >&2
  exit 2
}

# ---------------------------------------------------------------------------------------
# readers

# The frontmatter block. Exit 3 when the file does not open with `---`, exit 4 when it
# opens but never closes — the same reader check-dispatch.sh and task-owner.sh use, for
# the same reason: an unterminated block returns the whole file, and a `status:` line in
# the BODY would then be read as the record.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# Only the FIRST occurrence of a key counts — a document with the key repeated would
# otherwise be judged from the later value.
field() { # <key>
  printf '%s\n' "$FM" | awk -v key="$1" '
    !got && index($0, key ":") == 1 {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

# A stored double-quoted scalar, back to text. Anything else is returned as written: the
# fields are only ever written by this script, so the quoted form is the one that matters
# and a hand-typed bare word must still read as itself rather than as nothing.
yaml_unquote() { # <raw value>
  local v="$1"
  case "$v" in
    '"'*'"') v="${v%\"}"; v="${v#\"}"; printf '%s' "$v" | sed 's/\\"/"/g; s/\\\\/\\/g' ;;
    *) printf '%s' "$v" ;;
  esac
}

# Text to a double-quoted scalar. Whitespace runs fold to one space and the result is
# truncated, because this value is read by a human in `AWAITING.md` and in `# Notes`: a
# blocker is a line, never a pasted stack trace. Folding also makes the round-to-round
# comparison stable, since the same failure rarely arrives with the same line breaks.
BLOCKER_MAX_CHARS=200
yaml_quote() { # <text>
  printf '"%s"' "$(printf '%s' "$1" \
    | tr '\n\t\r' '   ' \
    | sed 's/  */ /g; s/^ //; s/ $//' \
    | cut -c "1-$BLOCKER_MAX_CHARS" \
    | sed 's/\\/\\\\/g; s/"/\\"/g')"
}
normalise() { # <text> — exactly what yaml_quote would store, unquoted
  local q; q="$(yaml_quote "$1")"; yaml_unquote "$q"
}

# The bundle root, by walking UP from the task document to the directory carrying the
# instance signature — the same `instance.config.json` marker check-dispatch.sh uses.
# Deliberately not $CLAUDE_PROJECT_DIR and not a path literal: this ships in the plugin,
# serves every instance, and a task document already knows where it lives.
bundle_root() { # <task-doc>
  local d
  d="$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P)" || return 1
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/instance.config.json" ] && { printf '%s\n' "$d"; return 0; }
    d="$(dirname -- "$d")"
  done
  return 1
}

# `maxStallRounds`, or the documented fallback. Every failure is silent and lands on the
# fallback: a task outside a bundle, a bundle with no such key, no python3. A cap that
# errored would stop the tick over a number that has a stated default.
resolve_max() { # <task-doc>
  local root max
  root="$(bundle_root "$1")" || { printf '%s\n' "$DEFAULT_MAX"; return 0; }
  # A MISSING SIBLING IS SAID OUT LOUD, then falls back. Silence here would answer 2 for a
  # bundle that had configured 5, and nothing anywhere would say which number was used.
  if [ -z "$HERE" ] || [ ! -f "$HERE/resolve-config.sh" ]; then
    echo "stall-counter: resolve-config.sh not found beside this script — using the" >&2
    echo "               documented fallback of $DEFAULT_MAX, not this bundle's maxStallRounds." >&2
    printf '%s\n' "$DEFAULT_MAX"; return 0
  fi
  max="$("$HERE/resolve-config.sh" --instance "$root" maxStallRounds 2>/dev/null)" || max=""
  case "$max" in
    ''|*[!0-9]*) printf '%s\n' "$DEFAULT_MAX" ;;
    *) printf '%s\n' "$max" ;;
  esac
}

# `/projects/<slug>/tasks/<id>.md` — the bundle-relative link form AWAITING.md uses.
task_link() { # <task-doc>
  local root abs
  abs="$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P)/$(basename -- "$1")" || abs="$1"
  root="$(bundle_root "$1")" || { printf '%s\n' "$1"; return 0; }
  printf '%s\n' "${abs#"$root"}"
}

# ---------------------------------------------------------------------------------------
# writers — every one lands through a temp file, so a failed rewrite leaves the document
# exactly as it was rather than half-written.

set_field() { # <task-doc> <key> <yaml-value>
  local tmp rc=0
  tmp="$(mktemp "${TMPDIR:-/tmp}/stall-counter.XXXXXX")" || return 3
  # The value travels in the ENVIRONMENT, never through `awk -v`: -v applies escape
  # processing, so a stored `\"` would arrive as a bare quote and corrupt the scalar.
  SC_KEY="$2" SC_VAL="$3" awk '
    BEGIN { k = ENVIRON["SC_KEY"]; v = ENVIRON["SC_VAL"] }
    NR == 1 && $0 == "---" { n = 1; print; next }
    n == 1 && $0 == "---" { if (!done) { print k ": " v; done = 1 } n = 2; print; next }
    n == 1 && !done && index($0, k ":") == 1 { print k ": " v; done = 1; next }
    { print }
  ' "$1" > "$tmp" || rc=3
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return 3; }
  cat "$tmp" > "$1" || rc=3            # rewrite in place: keeps the inode and the mode
  rm -f "$tmp"
  return "$rc"
}

# Append one bullet under `# Notes`, creating the heading when the document has none.
#
# THE DEDUPE KEY IS SEPARATE FROM THE LINE, and that is not tidiness: the bullet carries a
# timestamp, so matching on the whole line would find no match on a re-run one second later
# and append a copy per tick — burying the one note a human needs. The key is the stable
# half (the tally and the blocker); the timestamp rides after it. `-e` is required because
# a bullet starts with `-` and grep would otherwise read it as a flag.
append_note() { # <task-doc> <bullet> <dedupe-key>
  local tmp rc=0
  grep -qF -e "$3" "$1" && return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/stall-counter.XXXXXX")" || return 3
  SC_NOTE="$2" awk '
    BEGIN { note = ENVIRON["SC_NOTE"] }
    # Inside `# Notes`, the section ends at the next column-0 heading or at EOF; the
    # bullet goes at the end of the section, after a blank line so it is a list either
    # way — the section may end in prose.
    !placed && insec && /^# / { print ""; print note; print ""; placed = 1; insec = 0 }
    /^# Notes[[:space:]]*$/ { insec = 1; seen = 1 }
    { print; last = $0 }
    END {
      if (!placed && insec) { if (last != "") print ""; print note }
      else if (!seen) { if (last != "") print ""; print "# Notes"; print ""; print note }
    }
  ' "$1" > "$tmp" || rc=3
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return 3; }
  cat "$tmp" > "$1" || rc=3
  rm -f "$tmp"
  return "$rc"
}

# ---------------------------------------------------------------------------------------
# commands

CMD="${1:-}"; shift 2>/dev/null || true
case "$CMD" in record|escalate|status|reset) ;; -h|--help|'') usage ;; *) echo "stall-counter: unknown command '$CMD'" >&2; usage ;; esac

TASK="${1:-}"; [ -n "$TASK" ] || usage; shift
[ -f "$TASK" ] || { echo "stall-counter: no such task document: $TASK" >&2; exit 2; }

BLOCKER=""; HAVE_BLOCKER=no; PROGRESS=no
while [ $# -gt 0 ]; do
  case "$1" in
    --blocker) [ $# -ge 2 ] || { echo "stall-counter: --blocker needs a value" >&2; exit 2; }
               BLOCKER="$2"; HAVE_BLOCKER=yes; shift 2 ;;
    --progress) PROGRESS=yes; shift ;;
    *) echo "stall-counter: unexpected argument '$1'" >&2; usage ;;
  esac
done

FM=""; fm_rc=0
FM="$(fm_block "$TASK")" || fm_rc=$?
[ "$fm_rc" -eq 0 ] || {
  echo "stall-counter: $TASK has no readable YAML frontmatter — refusing rather than" >&2
  echo "               writing a counter into a document whose shape is unknown." >&2
  exit 2
}

MAX="$(resolve_max "$TASK")"
STATUS="$(field status)"
LAST="$(yaml_unquote "$(field last_blocker)")"
COUNT="$(field stall_count)"
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

# THE HUMAN-EDIT RESET, applied before anything reads the count. A task at or past the cap
# that is back in the QUEUE — `draft` or `ready` — was put there by the only party that can
# un-block one, and their edit must buy a real dispatch rather than an instant
# re-escalation off a stale number.
#
# THE TWO QUEUE STATES ARE THE CONDITION, NOT "anything but `blocked`", and the difference
# is the whole correctness of this block. `record` raises the count to the cap and returns
# 1; the tick then calls `escalate`, and in that window the task is `in-progress` and at the
# cap with nothing wrong. Reading that window as a human edit would zero the count between
# the two calls and the escalation would never happen — the one path this file exists for.
if [ "$COUNT" -ge "$MAX" ] && { [ "$STATUS" = ready ] || [ "$STATUS" = draft ]; }; then
  COUNT=0; LAST=""
fi

case "$CMD" in
  status)
    printf 'stall_count=%s max=%s last_blocker=%s\n' "$COUNT" "$MAX" "$LAST"
    [ "$COUNT" -lt "$MAX" ]
    exit $?
    ;;

  reset)
    set_field "$TASK" stall_count 0 || { echo "stall-counter: could not write stall_count" >&2; exit 3; }
    printf 'RESET  stall 0/%s\n' "$MAX"
    exit 0
    ;;

  record)
    [ "$HAVE_BLOCKER" = yes ] || { echo "stall-counter: record needs --blocker <text>" >&2; exit 2; }
    NEW="$(normalise "$BLOCKER")"
    if [ "$PROGRESS" = yes ]; then
      COUNT=0; why="progress reported — counter reset"
    elif [ -z "$NEW" ]; then
      COUNT=0; why="no blocker — counter reset"
    elif [ "$NEW" != "$LAST" ]; then
      COUNT=1; why="new blocker — counting from 1"
    else
      COUNT=$((COUNT + 1)); why="same blocker as last round"
    fi
    set_field "$TASK" stall_count "$COUNT" || { echo "stall-counter: could not write stall_count" >&2; exit 3; }
    set_field "$TASK" last_blocker "$(yaml_quote "$NEW")" || { echo "stall-counter: could not write last_blocker" >&2; exit 3; }
    if [ "$COUNT" -ge "$MAX" ]; then
      printf 'ESCALATE  stall %s/%s — %s: %s\n' "$COUNT" "$MAX" "$why" "$NEW"
      exit 1
    fi
    printf 'DISPATCH  stall %s/%s — %s\n' "$COUNT" "$MAX" "$why"
    exit 0
    ;;

  escalate)
    if [ "$COUNT" -lt "$MAX" ]; then
      echo "stall-counter: $TASK is at $COUNT/$MAX — nothing to escalate. Refusing." >&2
      exit 2
    fi
    TITLE="$(yaml_unquote "$(field title)")"
    [ -n "$TITLE" ] || TITLE="$(basename -- "$TASK")"
    NOTE_KEY="- **Stalled ${COUNT}/${MAX} rounds on the same blocker** — ${LAST}"
    NOTE="${NOTE_KEY}  _($(date -u +%Y-%m-%dT%H:%M:%SZ))_"
    # The note first: a document that gains `blocked` without the reason is the state this
    # exists to avoid, and re-running recovers a failed second write either way.
    append_note "$TASK" "$NOTE" "$NOTE_KEY" || { echo "stall-counter: could not write # Notes" >&2; exit 3; }
    [ "$STATUS" = blocked ] || set_field "$TASK" status blocked \
      || { echo "stall-counter: could not write status" >&2; exit 3; }
    printf '* ⛔ **unblock** — [%s](%s) · stalled %s/%s rounds: %s\n' \
      "$TITLE" "$(task_link "$TASK")" "$COUNT" "$MAX" "$LAST"
    exit 0
    ;;
esac
