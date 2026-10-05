#!/usr/bin/env bash
# papercuts.sh — the cheap end of the knowledge loop: one line per papercut, appended.
#
#   papercuts.sh add --task <ref> --surface <skill|agent|script>:<name> --note <text>
#   papercuts.sh check | report [--all] | due [--every <days>] | pass
#
# Entry shape, one line: `DATE | TASK | KIND:NAME | what hurt` (note 15-160 bytes).
# Exit: 0 clean / a pass is due · 1 refused, named on stderr (or: not due) · 2 unknown
# (usage, an unreadable record). Record: knowledge/papercuts.md, appended, never edited.
# Why: CONVENTIONS.md → the papercut bullet. Reasoning: ai-bridge-next/task-016.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

NOTE_MIN=15
NOTE_MAX=160

CMD="${1:-}"; [ $# -gt 0 ] && shift
usage() { sed -n '2,9p' "$0" >&2; }
need2() { [ "$1" -ge 2 ] || { echo "papercuts: $2 needs a value" >&2; exit 2; }; }

FILE=""; TASK=""; SURFACE=""; NOTE=""; DATE=""; EVERY=7; ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --file)    need2 $# "$1"; FILE="$2";    shift 2 ;;
    --task)    need2 $# "$1"; TASK="$2";    shift 2 ;;
    --surface) need2 $# "$1"; SURFACE="$2"; shift 2 ;;
    --note)    need2 $# "$1"; NOTE="$2";    shift 2 ;;
    --date)    need2 $# "$1"; DATE="$2";    shift 2 ;;
    --every)   need2 $# "$1"; EVERY="$2";   shift 2 ;;
    --all)     ALL=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *) echo "papercuts: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ -n "$DATE" ] || DATE="$(date -u +%Y-%m-%d)"
# Shared, the record shards per month so a month goes cold on its own; a single-writer
# bundle keeps the flat file. Readers take BOTH, so neither form loses an entry.
DIR="knowledge/papercuts"
GIVEN="$FILE"
[ -n "$FILE" ] || FILE="knowledge/papercuts.md"
if [ -z "$GIVEN" ] && { [ -d "$DIR" ] || [ -d "$AB_DIR/kb.git" ]; }; then
  FILE="$DIR/${DATE%-*}.md"
fi
sources() {
  [ -n "$GIVEN" ] && { printf '%s\n' "$GIVEN"; return; }
  [ -r "knowledge/papercuts.md" ] && printf '%s\n' "knowledge/papercuts.md"
  find "$DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort
}
printf '%s' "$EVERY" | grep -qE '^[0-9]+$' || { echo "papercuts: --every wants days" >&2; exit 2; }
printf '%s' "$DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
  || { echo "papercuts: --date wants YYYY-MM-DD" >&2; exit 2; }

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
bytes() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }

# Empty output means the line is a valid entry; anything else is why it is not.
bad_entry() {
  local l="$1" d t s n rest b
  case "$l" in *'|'*) : ;; *) printf 'not an entry — wants DATE | TASK | KIND:NAME | what hurt'; return ;; esac
  d="${l%%|*}"; rest="${l#*|}"; t="${rest%%|*}"; rest="${rest#*|}"; s="${rest%%|*}"; n="${rest#*|}"
  case "$n" in *'|'*) printf 'more than 4 fields — a "|" in the note breaks the record'; return ;; esac
  d="$(trim "$d")"; t="$(trim "$t")"; s="$(trim "$s")"; n="$(trim "$n")"
  printf '%s' "$d" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
    || { printf 'field 1 is not an ISO date: "%s"' "$d"; return; }
  [ -n "$t" ] || { printf 'field 2 (task) is empty'; return; }
  printf '%s' "$s" | grep -qE '^(skill|agent|script):[A-Za-z0-9][A-Za-z0-9._/-]*$' \
    || { printf 'field 3 is not skill|agent|script:<name>: "%s"' "$s"; return; }
  b="$(bytes "$n")"
  [ "$b" -ge "$NOTE_MIN" ] || { printf 'field 4 is %s bytes, under the %s floor — say what hurt' "$b" "$NOTE_MIN"; return; }
  [ "$b" -le "$NOTE_MAX" ] || { printf 'field 4 is %s bytes, over the %s ceiling — one line, not a paragraph' "$b" "$NOTE_MAX"; return; }
}

# Everything below `## Entries`, across every shard in name order: candidate lines,
# blanks and pass markers dropped.
region() {
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    awk '/^## Entries[[:space:]]*$/ { f=1; next } f' "$s" 2>/dev/null
  done <<EOF
$(sources)
EOF
}
newest() { sources | tail -1; }
have_record() { [ -n "$(sources)" ]; }
candidates() { region | grep -vE '^[[:space:]]*(<!--|$)' || true; }
since_pass() { region | awk '/^[[:space:]]*<!-- pass /{ n=0; next } { a[n++]=$0 } END{ for(i=0;i<n;i++) print a[i] }' \
               | grep -vE '^[[:space:]]*$' || true; }
last_pass() { region | grep -E '^[[:space:]]*<!-- pass ' | tail -1 \
              | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true; }

# Julian day number — `date -d` and `date -v` disagree across GNU and BSD; arithmetic does not.
days() {
  local y="${1%%-*}" r="${1#*-}" m d a yy mm
  m="${r%%-*}"; d="${r#*-}"; y=$((10#$y)); m=$((10#$m)); d=$((10#$d))
  a=$(( (14 - m) / 12 )); yy=$(( y + 4800 - a )); mm=$(( m + 12*a - 3 ))
  echo $(( d + (153*mm + 2)/5 + 365*yy + yy/4 - yy/100 + yy/400 - 32045 ))
}


case "$CMD" in
  add)
    [ -n "$TASK" ] && [ -n "$SURFACE" ] && [ -n "$NOTE" ] \
      || { echo "papercuts: add wants --task, --surface and --note" >&2; usage; exit 2; }
    case "$TASK$SURFACE$NOTE" in *$'\n'*|*$'\r'*) echo "papercuts: an entry is ONE line" >&2; exit 1 ;; esac
    line="$DATE | $TASK | $SURFACE | $NOTE"
    why="$(bad_entry "$line")"
    [ -z "$why" ] || { echo "papercuts: refused — $why" >&2; exit 1; }
    if [ ! -e "$FILE" ]; then
      mkdir -p "$(dirname "$FILE")" || exit 2
      printf '# Papercuts\n\nOne line per papercut: `DATE | TASK | KIND:NAME | what hurt`.\nAppend with `papercuts.sh add`; never edit or delete a line.\n\n## Entries\n\n' > "$FILE" || exit 2
    fi
    [ -w "$FILE" ] || { echo "papercuts: cannot write '$FILE'" >&2; exit 2; }
    grep -qE '^## Entries[[:space:]]*$' "$FILE" || { echo "papercuts: '$FILE' has no '## Entries' heading" >&2; exit 2; }
    [ -z "$(tail -c 1 "$FILE")" ] || printf '\n' >> "$FILE"
    printf '%s\n' "$line" >> "$FILE" || exit 2
    echo "papercuts: appended to $FILE"
    ;;
  check)
    have_record || { echo "papercuts: no record to read (looked at $FILE and $DIR/)" >&2; exit 2; }
    heading=no
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      grep -qE '^## Entries[[:space:]]*$' "$s" 2>/dev/null && { heading=yes; break; }
    done <<EOF
$(sources)
EOF
    [ "$heading" = yes ] \
      || { echo "papercuts: no '## Entries' heading in any record" >&2; exit 2; }
    n=0; bad=0
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      n=$((n + 1)); why="$(bad_entry "$l")"
      [ -z "$why" ] && continue
      bad=$((bad + 1)); printf 'BAD  %s — %s\n' "$l" "$why" >&2
    done < <(candidates)
    echo "papercuts: $n entries, $bad malformed"
    [ "$bad" -eq 0 ] || exit 1
    ;;
  report)
    have_record || { echo "papercuts: no record to read (looked at $FILE and $DIR/)" >&2; exit 2; }
    if [ "$ALL" -eq 1 ]; then
      src="$(candidates)"; scope="all time"
    else
      src="$(since_pass)"; lp="$(last_pass)"
      scope="since the first entry"; [ -n "$lp" ] && scope="since the $lp pass"
    fi
    if [ -z "$src" ]; then echo "papercuts: no entries $scope"; exit 0; fi
    surfaces="$(printf '%s\n' "$src" | awk -F'|' '{ gsub(/[ \t]/, "", $3); print $3 }' | sort | uniq -c | sort -rn | awk '{ print $2 }')"
    printf '== %s entries · %s surfaces · %s\n' \
      "$(printf '%s\n' "$src" | wc -l | tr -d ' ')" "$(printf '%s\n' "$surfaces" | wc -l | tr -d ' ')" "$scope"
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      printf '\n%s  (%s)\n' "$s" \
        "$(printf '%s\n' "$src" | awk -F'|' -v s="$s" '{ k=$3; gsub(/[ \t]/, "", k); if (k == s) n++ } END { print n+0 }')"
      printf '%s\n' "$src" | awk -F'|' -v s="$s" '
        function t(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
        { k = $3; gsub(/[ \t]/, "", k); if (k == s) printf "  %s  %s  %s\n", t($1), t($2), t($4) }'
    done <<EOF
$surfaces
EOF
    ;;
  due)
    have_record || { echo "papercuts: no record at '$FILE' — nothing to group"; exit 1; }
    pending="$(since_pass | grep -c . || true)"
    lp="$(last_pass)"
    if [ "$pending" -eq 0 ]; then echo "papercuts: 0 entries since the last pass — not due"; exit 1; fi
    if [ -n "$lp" ]; then
      age=$(( $(days "$DATE") - $(days "$lp") ))
      if [ "$age" -lt "$EVERY" ]; then
        echo "papercuts: $pending entries, last pass $lp ($age days ago) — not due for $((EVERY - age)) days"; exit 1
      fi
      echo "papercuts: DUE — $pending entries since the $lp pass ($age days)"
    else
      echo "papercuts: DUE — $pending entries, no pass on record"
    fi
    ;;
  pass)
    target="$(newest)"; [ -n "$target" ] || target="$FILE"
    [ -w "$target" ] || { echo "papercuts: cannot write '$target'" >&2; exit 2; }
    src="$(since_pass)"
    n="$(printf '%s' "$src" | grep -c . || true)"
    m="$(printf '%s\n' "$src" | grep . | awk -F'|' '{ gsub(/[ \t]/, "", $3); print $3 }' | sort -u | grep -c . || true)"
    [ -z "$(tail -c 1 "$target")" ] || printf '\n' >> "$target"
    printf '<!-- pass %s — %s entries, %s surfaces -->\n' "$DATE" "$n" "$m" >> "$target"
    echo "papercuts: marked a pass at $DATE over $n entries, $m surfaces"
    ;;
  *) usage; exit 2 ;;
esac
