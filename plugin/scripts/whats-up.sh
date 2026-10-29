#!/usr/bin/env bash
#
# whats-up.sh — reprint AWAITING.md's rows as a numbered `Needs you:` block, from the
# instance root. Reads that file and `tick-lock.sh status`, nothing else: no task document,
# no `gh`, no `git`, so it never becomes a second status view (docs/conventions.md #3).
#
# Exit: 0 printed (`awaiting: false` or an absent file is off; never created here) · 2 not an
# instance root · 3 AWAITING.md unreadable or not a file. Backs /<plugin>:whats-up; verified by
# tests/whats-up.test.sh.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$here/bundle-paths.sh" || exit 2

ab_is_bundle . || { echo "whats-up: run from a control-panel instance root (instance.config.json)."; exit 2; }
f="$AB_AWAITING"

if ! ab_awaiting_on .; then
  echo "The Needs-you queue is off: \"awaiting\": false in instance.config.json. Remove the key (or set it true) and run /${PLUGIN_NAME}:init to turn it back on."
  exit 0
fi
if [ ! -e "$f" ]; then
  echo "The Needs-you queue is off until the next stamp: no $f. /${PLUGIN_NAME}:init recreates it; the next dispatch tick that changes something fills it."
  exit 0
fi
[ -f "$f" ] || { echo "whats-up: $f exists but is not a regular file — remove it, then run /${PLUGIN_NAME}:init."; exit 3; }
[ -r "$f" ] || { echo "whats-up: $f exists but cannot be read — chmod +r $f."; exit 3; }

if ! grep -qE '^##[[:space:]].*Awaiting you' "$f"; then
  echo "The Needs-you queue is on, and not yet filled: the next dispatch tick that changes something writes it."
  exit 0
fi

# The banner's extraction, so the two cannot disagree about which lines are rows.
items="$(awk '/^##[[:space:]].*Awaiting you/ { inblk=1; next }
              inblk && /^##[[:space:]]/       { exit }
              inblk && /^[[:space:]]*\* /     { sub(/^[[:space:]]*\* /, ""); print }' "$f")"

# The seed writes `Last refreshed: never (…)` mid-line; build-awaiting.sh writes an ISO line.
stamp="$(sed -n 's/.*Last refreshed:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$f" | head -1)"
stamp="${stamp%.}"
case "$stamp" in
  never)
    fresh="Never refreshed: no dispatch tick has changed anything since this file was created." ;;
  *)
    age="age unknown"
    e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$stamp" +%s 2>/dev/null || date -u -d "$stamp" +%s 2>/dev/null)"
    case "$e" in
      ''|*[!0-9]*) ;;
      *) d=$(( $(date -u +%s) - e ))
         if [ "$d" -lt 0 ]; then age="dated in the future — check the clock"; else age="$(( d / 60 )) min ago"; fi ;;
    esac
    fresh="Last refreshed ${stamp:-at an unknown time} ($age) — the last tick that changed something; an idle tick does not restamp it, so this age is not staleness." ;;
esac

if [ -z "$items" ]; then
  echo "Nothing needs you. $fresh"
  exit 0
fi

lock="$(bash "$here/tick-lock.sh" status --instance . 2>&1)"; rc=$?
case "$rc" in
  0) tick="No tick is in flight." ;;
  1) tick="A tick is in flight — this list may be about to change." ;;
  2) tick="No tick is known to be in flight; the lock needs a look: $(printf '%s\n' "$lock" | head -1)" ;;
  *) tick="Whether a tick is in flight is unknown: tick-lock.sh status could not answer (exit $rc): $(printf '%s\n' "$lock" | head -1)" ;;
esac

# AWAITING.md links documents bundle-root-relative (`[title](/projects/…)`, SCHEMA.md), which a
# terminal renders as file:///projects/… and opens nothing. Printed here, every such target
# that names a file under this instance becomes its ABSOLUTE path, so the link opens the
# local file the owner edits; URLs and targets that resolve to nothing are left as they are.
inst="$(pwd -P)"
items="$(printf '%s\n' "$items" | awk -v inst="$inst" '
  { line = $0; out = ""
    while (match(line, /\]\(\/[^)]*\)/)) {
      pre = substr(line, 1, RSTART + 1); tgt = substr(line, RSTART + 2, RLENGTH - 3); line = substr(line, RSTART + RLENGTH)
      path = inst tgt
      if ((getline _ < path) >= 0) { close(path); tgt = path }
      out = out pre tgt ")"
    }
    print out line }')"

echo "ℹ️ **Needs you:**"
printf '%s\n' "$items" | awk '{ printf "%d. %s\n", NR, $0 }'
echo
echo "$fresh"
echo "$tick"
echo "In-flight work and progress: /${PLUGIN_NAME}:brief-me"
