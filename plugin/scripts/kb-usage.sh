#!/usr/bin/env bash
# kb-usage.sh — the citation store, and the sweep that reads it. From a bundle root.
#
#   kb-usage.sh [--instance DIR] record --source <id> --text-file <f> (--brief <a,b> | --brief-file <f>)
#   kb-usage.sh [--instance DIR] sweep [--propose] [--today YYYY-MM-DD] [--min-age-days N]
#                                      [--categories "a b"] [--min-texts N] [--min-citations N]
#
# record: runs cite-check.sh, prints its report, exits with its code, and stores the
#   KEPT/UNREAD/ARCHIVED slugs as .ai-bridge/citations/<id>.txt — one file per text, so a
#   re-run rewrites the same file and two clones never append to one. Exit 2: nothing stored.
# sweep: per current Finding, the qualifiers and its remaining grace, derived from disk on
#   every run. --propose prints only the archivable ones, as kb-propose.sh proposals.
# A Finding is archivable only when ALL hold: category in --categories (learning measurement),
#   uncited for --min-age-days (180) since max(timestamp, last citation), --min-texts (10)
#   texts recorded in that window, and the store holding --min-citations (20) overall.
#   "Today" is --today, else KB_USAGE_TODAY, else the UTC date.
# Exit: 0 answered · 1-3 record: cite-check.sh's code · 2 usage, or nothing could be read.
# Reasoning: knowledge-base-reflector/task-005.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

MIN_AGE=180; CATEGORIES="learning measurement"; MIN_TEXTS=10; MIN_CITES=20
INST="$PWD"; VERB=""; SOURCE=""; TEXT=""; BRIEF=""; BRIEF_FILE=""; PROPOSE=0
TODAY="${KB_USAGE_TODAY:-$(date -u +%Y-%m-%d)}"
die() { echo "kb-usage: $2" >&2; exit "$1"; }
need2() { [ "$1" -ge 2 ] || die 2 "$2 needs a value"; }
num() { case "$2" in ""|*[!0-9]*) die 2 "$1 wants a non-negative integer" ;; esac; }

while [ $# -gt 0 ]; do
  case "$1" in
    --instance)      need2 $# "$1"; INST="$2"; shift 2 ;;
    record|sweep)    [ -z "$VERB" ] || die 2 "one verb at a time"; VERB="$1"; shift ;;
    --source)        need2 $# "$1"; SOURCE="$2"; shift 2 ;;
    --text-file)     need2 $# "$1"; TEXT="$2"; shift 2 ;;
    --brief)         need2 $# "$1"; BRIEF="${BRIEF:+$BRIEF,}$2"; shift 2 ;;
    --brief-file)    need2 $# "$1"; BRIEF_FILE="$2"; shift 2 ;;
    --propose)       PROPOSE=1; shift ;;
    --today)         need2 $# "$1"; TODAY="$2"; shift 2 ;;
    --min-age-days)  need2 $# "$1"; num "$1" "$2"; MIN_AGE="$2"; shift 2 ;;
    --categories)    need2 $# "$1"; CATEGORIES="$2"; shift 2 ;;
    --min-texts)     need2 $# "$1"; num "$1" "$2"; MIN_TEXTS="$2"; shift 2 ;;
    --min-citations) need2 $# "$1"; num "$1" "$2"; MIN_CITES="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" >&2; exit 2 ;;
    *) die 2 "unknown argument '$1'" ;;
  esac
done
[ -n "$VERB" ] || die 2 "usage: kb-usage.sh [--instance DIR] record|sweep …"
[ -d "$INST/knowledge" ] || die 2 "no knowledge/ under $INST — run from a bundle root"
[[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die 2 "--today wants YYYY-MM-DD"
STORE="$INST/$AB_DIR/citations"

if [ "$VERB" = record ]; then
  [[ "$SOURCE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 2 "--source wants an id of [A-Za-z0-9._-], e.g. <task-slug>.result or <repo>-pr-<n>"
  [ -n "$TEXT" ] || die 2 "record needs --text-file"
  args=(--text-file "$TEXT")
  [ -z "$BRIEF" ] || args+=(--brief "$BRIEF")
  [ -z "$BRIEF_FILE" ] || args+=(--brief-file "$BRIEF_FILE")
  [ ! -r "$INST/knowledge/index.md" ] || args+=(--index "$INST/knowledge/index.md")
  report="$(bash "$HERE/cite-check.sh" "${args[@]}")"; rc=$?
  printf '%s\n' "$report"
  [ "$rc" -ne 2 ] || die 2 "cite-check.sh could not classify every citation — nothing stored"
  mkdir -p "$STORE" || die 2 "cannot create $STORE"
  f="$STORE/$SOURCE.txt"
  recorded="$(sed -n 's/^recorded: //p' "$f" 2>/dev/null | head -1)"
  t="$(mktemp "$STORE/.$SOURCE.XXXXXX")" || die 2 "cannot write under $STORE"
  { printf 'recorded: %s\n' "${recorded:-$TODAY}"
    printf '%s\n' "$report" | awk '/^(KEPT|UNREAD|ARCHIVED) [A-Za-z0-9._-]+ / { print $1, $2 }' | LC_ALL=C sort -u
  } >"$t" && mv "$t" "$f" || { rm -f "$t"; die 2 "could not write $f"; }
  echo "kb-usage: stored $(($(grep -c '' "$f") - 1)) citation(s) from $SOURCE" >&2
  exit "$rc"
fi

fmval() { awk -v k="$2" 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit}
  NR>1 && index($0, k ":")==1 { v=substr($0, length(k)+2); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+#.*$/, "", v); print v; exit }' "$1"; }

# One awk pass over every store file: "T <date>" per text, "C <date> <slug>" per citation.
STORE_LINES=""
if [ -d "$STORE" ]; then
  STORE_LINES="$(find "$STORE" -maxdepth 1 -type f -name '*.txt' -exec awk '
    FNR==1 { d = ""; if ($1 == "recorded:") { d = $2; print "T " d } ; next }
    d != "" && NF >= 2 { print "C " d " " $2 }' {} + 2>/dev/null)"
fi
FINDINGS="$(find "$INST/knowledge/findings" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)"
ROWS=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  st="$(fmval "$f" status)"; [ -n "$st" ] || st=current
  [ "$st" = current ] || continue
  ROWS="$ROWS$(basename "$f" .md)	$(fmval "$f" category)	$(fmval "$f" timestamp | cut -c1-10)
"
done <<<"$FINDINGS"

printf '%s\n' "$STORE_LINES" | ROWS="$ROWS" awk -v today="$TODAY" -v minage="$MIN_AGE" \
  -v cats=" $CATEGORIES " -v mintexts="$MIN_TEXTS" -v mincites="$MIN_CITES" -v propose="$PROPOSE" '
  function days(s,  y, m, d, era, yoe, doy) {
    if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (m <= 2) y--
    era = int(y / 400); yoe = y - era * 400
    doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
    return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  }
  $1 == "T" { ntexts++; texts[ntexts] = days($2) }
  $1 == "C" { ncites++; dd = days($2); if (!($3 in last) || dd > last[$3]) last[$3] = dd }
  END {
    now = days(today)
    if (!propose)
      printf "thresholds: category in {%s} · uncited >= %dd · >= %d text(s) in that window · store >= %d citation(s) (has %d in %d text(s))\n",
        substr(cats, 2, length(cats) - 2), minage, mintexts, mincites, ncites + 0, ntexts + 0
    n = split(ENVIRON["ROWS"], r, "\n")
    for (i = 1; i <= n; i++) {
      if (r[i] == "") continue
      split(r[i], c, "\t"); slug = c[1]; cat = c[2]; ts = days(c[3]); why = ""
      start = ts; if ((slug in last) && last[slug] > start) start = last[slug]
      if (ts < 0) { why = why ",no-timestamp"; start = now }
      age = now - start; grace = minage - age; if (grace < 0) grace = 0
      seen = 0; for (k = 1; k <= ntexts; k++) if (texts[k] >= start) seen++
      if (index(cats, " " cat " ") == 0 || cat == "") why = why ",category"
      if (age < minage) why = why ",age"
      if (seen < mintexts) why = why ",texts"
      if (ncites + 0 < mincites) why = why ",store"
      since = (slug in last) ? "last cited" : "uncited since"
      if (why == "") {
        if (propose) printf "status · %s · status=archived · - · uncited in %d text(s) over %d days, category %s\n", slug, seen, age, cat
        else printf "ARCHIVE %s · category=%s · %s %dd ago · grace 0d · %d text(s)\n", slug, cat, since, age, seen
      } else if (!propose)
        printf "KEEP %s · category=%s · %s %dd ago · grace %dd · %d text(s) · fails %s\n", slug, (cat == "" ? "-" : cat), since, age, grace, seen, substr(why, 2)
    }
  }'
