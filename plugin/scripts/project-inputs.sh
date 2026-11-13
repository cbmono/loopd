#!/usr/bin/env bash
#
# project-inputs.sh — is the project that owns <path> still waiting for the human's input
# files? The ONE reader of `inputs:` (SCHEMA.md → type: Project), and its one writer.
#
#   Usage: project-inputs.sh [--release] <path>   # under projects/<slug>/, from the instance root
#
# Exit: 0 ready — `inputs:` absent, empty or `now` · 1 WAITING — `inputs: later` and
# `sources/` holds nothing but its README.md · 2 cannot answer (usage, not an instance root,
# unreadable project.md, an `inputs:` value that is neither `later` nor `now`) · 3 ARRIVED —
# `inputs: later`, but `sources/` now holds a file: the next tick releases it.
#
# `--release` turns 3 into the flip: `inputs: later` becomes `inputs: now` in project.md's
# frontmatter and a dated bullet goes to the project's log.md; prints `released: …`, exit 0.
# On any other state it changes nothing and exits as above.
#
# What a waiting project gates: REFINEMENT only (tick-steps/step-2-refine-drafts.md), and
# AWAITING.md shows one `📥 inputs` row for it instead of its task rows. Never dispatch, never
# a status. Only file PRESENCE is read — never a name or a byte of content: sources/ may hold
# raw exports, and nothing here may carry them to the queue, the board or the log.
# Verified by tests/project-inputs.test.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

refuse() { echo "error: $1" >&2; exit 2; }

release=0
[ "${1:-}" = --release ] && { release=1; shift; }
[ "$#" -eq 1 ] && [ -n "$1" ] && [ "${1#-}" = "$1" ] || refuse "usage: $(basename "$0") [--release] <path>"
ab_is_bundle . || refuse "run from a control-panel instance root (instance.config.json)."

# Canonicalised both sides, as project-paused.sh does: macOS /var is a link to /private/var.
tdir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || refuse "no such path: $1"
rel="$tdir/$(basename "$1")"; rel="${rel#"$(pwd -P)"/}"
slug="$(printf '%s\n' "$rel" | sed -n 's#^projects/\([^/][^/]*\)/.*#\1#p')"
[ -n "$slug" ] || refuse "$1 is not under projects/<slug>/."
pm="projects/$slug/project.md"
[ -f "$pm" ] && [ -r "$pm" ] || refuse "cannot read $pm."

# First `inputs:` inside a CLOSED frontmatter block; an unterminated block is unreadable.
v="$(awk '
  NR==1 && $0!="---" { exit 3 }
  /^---$/ { if (++n==2) { closed=1; exit } ; next }
  n==1 && !got && /^inputs:/ {
    v=$0; sub(/^inputs:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
    gsub(/["\047]/, "", v); sub(/[[:space:]]+$/, "", v); got=1
  }
  END { if (!closed) exit 4; print v }
' "$pm")" || refuse "$pm has no readable frontmatter."

case "$v" in
  ""|now) echo "ok: $pm takes no inputs first."; exit 0 ;;
  later) ;;
  *) refuse "$pm has inputs: '$v' — neither later nor now." ;;
esac

src="projects/$slug/sources"
# Presence only: the first regular file that is neither README.md nor a dotfile (.DS_Store).
have="$(find "$src" -type f ! -name README.md ! -name '.*' 2>/dev/null | head -n1 || true)"
if [ -z "$have" ]; then
  echo "waiting: $pm — add your files to $src/, then set inputs: now (a file there releases it)."
  exit 1
fi
if [ "$release" = 0 ]; then
  echo "arrived: $src/ has input files — the next tick releases $pm."
  exit 3
fi

n="$(find "$src" -type f ! -name README.md ! -name '.*' 2>/dev/null | wc -l | tr -d ' ' || true)"
tmp="$pm.inputs.$$"
awk '/^---$/ { n++ } n==1 && !done && /^inputs:/ { print "inputs: now"; done=1; next } { print }' "$pm" > "$tmp" \
  && [ -s "$tmp" ] && mv "$tmp" "$pm" || { rm -f "$tmp"; refuse "cannot rewrite $pm."; }
# Newest-first, as /loopd:new-project writes it: under today's `## <date>` when it is the top
# heading, else a new one above the first. A count, never a file name.
log="projects/$slug/log.md"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ -f "$log" ]; then
  awk -v day="${ts%%T*}" -v b="* \`inputs: now\` — released by $n file(s) in \`sources/\` ($ts, project-inputs.sh)." '
    !put && /^## / { if ($0 == "## " day) { print; print ""; print b; put=1; next }
                     print "## " day; print ""; print b; print ""; put=1 }
    { print }
    END { if (!put) { print ""; print "## " day; print ""; print b } }' "$log" > "$log.inputs.$$" \
    && mv "$log.inputs.$$" "$log" || rm -f "$log.inputs.$$"
fi
echo "released: $pm — $n input file(s) in $src/, inputs: now. Refine its drafts from them."
