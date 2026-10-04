#!/usr/bin/env bash
# cite-check.sh — keep only the `[[slug]]` citations a brief actually carried.
#
#   cite-check.sh --text-file <f> (--brief <a,b> | --brief-file <f>) [--index <f>] [--strip]
#
# Exit: 0 nothing dropped · 1 a citing line lost every citation · 2 unknown (usage, an
# unreadable input, or an id no index can classify) · 3 dropped, every citing line
# still cites something. Report on stdout, one
# `KEPT|SUPERSEDED|ARCHIVED|UNREAD|FABRICATED|UNKNOWN|EMPTY` line per citation; `--strip` puts the
# cleaned text on stdout and the report on stderr.
# Offline by construction — files only, no network, no `gh`.
# Why: CONVENTIONS.md → the citation bullet. Reasoning: ai-bridge-next/task-014.
set -uo pipefail

TEXT=""; BRIEF=""; BRIEF_FILE=""; INDEX=""; STRIP=0
usage() { sed -n '2,10p' "$0" >&2; }
need2() { [ "$1" -ge 2 ] || { echo "cite-check: $2 needs a value" >&2; usage; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --text-file)  need2 $# "$1"; TEXT="$2";       shift 2 ;;
    --brief)      need2 $# "$1"; BRIEF="${BRIEF:+$BRIEF }$2"; shift 2 ;;
    --brief-file) need2 $# "$1"; BRIEF_FILE="$2"; shift 2 ;;
    --index)      need2 $# "$1"; INDEX="$2";      shift 2 ;;
    --strip)      STRIP=1; shift ;;
    -h|--help)    usage; exit 2 ;;
    *) echo "cite-check: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

[ -n "$TEXT" ] || { echo "cite-check: --text-file is required" >&2; usage; exit 2; }
[ -r "$TEXT" ] || { echo "cite-check: cannot read '$TEXT'" >&2; exit 2; }
if [ -n "$BRIEF_FILE" ]; then
  [ -r "$BRIEF_FILE" ] || { echo "cite-check: cannot read '$BRIEF_FILE'" >&2; exit 2; }
  BRIEF="$BRIEF $(sed 's/#.*//' "$BRIEF_FILE")"
fi

# An id is `<slug>`, `[[<slug>]]` or a path to `<slug>.md` — all three normalise to the
# slug, so a brief can paste whichever form it has.
slugs_of() { tr -c 'A-Za-z0-9._/-' ' ' | tr ' ' '\n' | sed 's#.*/##; s#\.md$##' \
             | grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$' | sort -u; }

CARRIED=" $(printf '%s' "$BRIEF" | slugs_of | tr '\n' ' ')"

# The `cataloguer`'s index rows are the id source of truth: every doc it writes gets a
# row, so a slug in no row names no document. Default to the bundle's own index.
[ -n "$INDEX" ] || { [ -r knowledge/index.md ] && INDEX=knowledge/index.md; }
# A superseded doc keeps its row — it is history — so it is KNOWN and still not citable.
# The generated index puts those rows under their own `### Superseded` heading, which is
# what makes "never cite one" checkable instead of a rule agents remember. An archived doc
# (no brief cited it) is history the same way, under its own `### Archived` heading.
HAVE_INDEX=0; KNOWN=" "; GONE=" "; ARCH=" "
under() { awk -v h="$1" '/^#{2,}[[:space:]]/ { in_h = ($0 ~ h) } in_h' "$INDEX" \
          | grep -oE '[A-Za-z0-9._/-]+\.md' | slugs_of | tr '\n' ' '; }
if [ -n "$INDEX" ] && [ -r "$INDEX" ]; then
  HAVE_INDEX=1
  KNOWN=" $(grep -oE '[A-Za-z0-9._/-]+\.md' "$INDEX" | slugs_of | tr '\n' ' ')"
  GONE=" $(under '[Ss]uperseded')"
  ARCH=" $(under '^#+[[:space:]]+[Aa]rchived')"
elif [ -n "$INDEX" ]; then
  echo "cite-check: cannot read index '$INDEX' — a dropped id stays unclassified" >&2
fi

has() { case "$1" in *" $2 "*) return 0 ;; esac; return 1; }

report=""; out=""; lineno=0
kept=0; unread=0; fabricated=0; unknown=0; empty=0; superseded=0; archived=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  cites="$(printf '%s\n' "$line" | grep -o '\[\[[A-Za-z0-9._-]\{1,\}\]\]' || true)"
  if [ -z "$cites" ]; then out="$out$line"$'\n'; continue; fi
  surviving=0
  while IFS= read -r cite; do
    slug="${cite#\[\[}"; slug="${slug%\]\]}"
    if has "$GONE" "$slug"; then
      superseded=$((superseded + 1))
      report="${report}SUPERSEDED $slug (line $lineno) — history; cite the replacement"$'\n'
      line="${line//" $cite"/}"; line="${line//"$cite"/}"; continue
    fi
    if has "$ARCH" "$slug"; then
      archived=$((archived + 1))
      report="${report}ARCHIVED $slug (line $lineno) — history; no brief cited it"$'\n'
      line="${line//" $cite"/}"; line="${line//"$cite"/}"; continue
    fi
    if has "$CARRIED" "$slug"; then
      surviving=$((surviving + 1)); kept=$((kept + 1))
      report="${report}KEPT $slug (line $lineno)"$'\n'; continue
    fi
    if [ "$HAVE_INDEX" -eq 0 ]; then verdict=UNKNOWN; unknown=$((unknown + 1))
    elif has "$KNOWN" "$slug"; then verdict=UNREAD; unread=$((unread + 1))
    else verdict=FABRICATED; fabricated=$((fabricated + 1)); fi
    report="${report}${verdict} $slug (line $lineno)"$'\n'
    line="${line//" $cite"/}"; line="${line//"$cite"/}"
  done <<< "$cites"
  [ "$surviving" -gt 0 ] || { empty=$((empty + 1))
    report="${report}EMPTY (line $lineno) — every citation on this line was dropped"$'\n'; }
  out="$out$line"$'\n'
done < "$TEXT"

dropped=$((unread + fabricated + unknown + superseded + archived))
report="${report}cite-check: ${kept} kept, ${dropped} dropped (${unread} unread, "
report="${report}${fabricated} fabricated, ${superseded} superseded, ${archived} archived, ${unknown} unclassified), ${empty} empty block(s)."
if [ "$STRIP" -eq 1 ]; then printf '%s' "$out"; printf '%s\n' "$report" >&2
else printf '%s\n' "$report"; fi

# Unknown outranks a verdict built on no index: without one, a dropped id cannot be told
# from a real document nobody read.
[ "$unknown" -eq 0 ] || exit 2
[ "$empty" -eq 0 ] || exit 1
[ "$dropped" -eq 0 ] || exit 3
exit 0
