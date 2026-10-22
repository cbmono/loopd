#!/usr/bin/env bash
# kb-select.sh — the Findings a dispatch brief carries, chosen the same way every time.
#   kb-select.sh <task-doc> [--instance <bundle>]           1-5 `[[slug]] — lesson` rows, or `none matched`
#   kb-select.sh --record <task-doc> [--instance <bundle>]  appends `* KNOWLEDGE <ISO 8601> · <slugs|none>` to # Notes
#   kb-select.sh --recorded <task-doc>                      that latest line's slugs, for kb-usage.sh --brief
# Qualifies: status: current, and >=2 content words (kb-words.sh) shared with the task's title,
# description and criteria when tagged with its Service doc's slug and that tag is in vocab.md's
# Services table, else >=3. Ranked by shared words, then slug; the top 5 print.
# Exit: 0 · 1 --recorded found no line · 2 usage or unreadable task.
# Reasoning: kb-retrieval-and-papercut-fixes/task-003.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/kb-words.sh" || exit 2

MAX=5
# Selector-only, on top of the shared key: a task's criteria run to hundreds of words, so
# without these every Finding long enough "shares" three of them and the longest lessons win.
FUNCTION_WORDS="with without within for from on in at by or nor but if then than so when where which who whom whose what why how all any each every both either neither some such only own same other into onto over under out up down off about after before again once here there can could will would shall should may might must do does did done doing has have had having he she they them their we our us you your i me my one also just more most very too yet still via per not no never"
usage() { sed -n '2,10p' "$0" >&2; exit 2; }
TASK=""; INSTANCE=""; MODE=select
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; INSTANCE="$2"; shift 2 ;;
    --record) MODE=record; shift ;;
    --recorded) MODE=recorded; shift ;;
    -h|--help) usage ;;
    -*) echo "kb-select: unexpected option '$1'" >&2; usage ;;
    *) [ -z "$TASK" ] || usage; TASK="$1"; shift ;;
  esac
done
[ -n "$TASK" ] || usage
{ [ -f "$TASK" ] && [ -r "$TASK" ] && [ "$(head -n 1 "$TASK")" = --- ]; } ||
  { echo "kb-select: cannot read a task document at $TASK" >&2; exit 2; }

if [ "$MODE" = recorded ]; then
  line="$(grep '^\* KNOWLEDGE ' "$TASK" | tail -n 1)"
  [ -n "$line" ] || exit 1
  printf '%s\n' "${line##* · }"; exit 0
fi

if [ -z "$INSTANCE" ]; then
  d="$(cd "$(dirname "$TASK")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -f "$d/instance.config.json" ] && { INSTANCE="$d"; break; }
    d="$(dirname "$d")"
  done
fi

select_rows() { # slug<TAB>lesson, best first
  [ -n "$INSTANCE" ] && [ -d "$INSTANCE/knowledge/findings" ] || return 0
  local tag="" svc
  if svc="$(bash "$HERE/service-doc.sh" "$TASK" --instance "$INSTANCE")"; then
    svc="$(basename "$svc" .md)"
    awk '/^## /{ s = ($0 ~ /^## Services/) } s && /^\|/ { c = $0; sub(/^\|[ \t]*/, "", c); sub(/[ \t]*\|.*/, "", c); gsub(/`/, "", c); print c }' \
      "$INSTANCE/knowledge/vocab.md" 2>/dev/null | grep -qxF -e "$svc" && tag="$svc"
  fi
  set -- "$INSTANCE"/knowledge/findings/*.md
  [ -f "$1" ] || return 0
  awk -v task="$(kb_task_text "$TASK")" -v tag="$tag" -v fw="$FUNCTION_WORDS" -v q="'" "$KB_WORDS_AWK"'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function unq(s,   d) {
  d = (s ~ /^".*"$/)
  if (length(s) > 1 && (d || (substr(s, 1, 1) == q && substr(s, length(s), 1) == q))) s = substr(s, 2, length(s) - 2)
  if (d) gsub(/\\"/, "\"", s)
  return s
}
function keep(w) { return length(w) > 1 && w !~ /^[0-9._-]+$/ }
function done_file(   k, n, i, w, F) {
  if (V["type"] != "Finding" || V["status"] != "current") return
  m++; SL[m] = slug; k = words(V["title"] " " V["lesson"], F); n = split(k, w, " "); K[m] = ""
  for (i = 1; i <= n; i++) if (keep(w[i])) { K[m] = K[m] " " w[i]; DF[w[i]]++ }
  TG[m] = (tag != "" && index("," V["tags"] ",", "," tag ",")) ? 1 : 0
  L[m] = V["lesson"]; if (L[m] == "") L[m] = V["title"]; gsub(/[ \t\r]+/, " ", L[m])
}
BEGIN {
  n = split(fw, p, " "); for (i = 1; i <= n; i++) STOP[p[i]] = 1
  words(task, T)
}
FNR == 1 {
  if (NR > 1) done_file()
  delete V; slug = FILENAME; sub(/.*\//, "", slug); sub(/\.md$/, "", slug)
  infm = ($0 == "---"); blk = ""; lst = ""; next
}
!infm { next }
$0 == "---" { infm = 0; next }
/^[A-Za-z_][A-Za-z0-9_]*:/ {
  k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*:/, "", v); v = trim(v); blk = ""; lst = ""
  if (k == "status" || k == "type") sub(/[ \t]+#.*/, "", v)
  if (v ~ /^[>|][-+]?[0-9]*$/) { blk = k; V[k] = ""; next }
  if (v == "") { lst = k; V[k] = ""; next }
  if (k == "tags") { gsub(/[][ "\047]/, "", v) }
  V[k] = unq(v); next
}
/^[ \t]/ {
  if (blk != "") { V[blk] = trim(V[blk] " " trim($0)); next }
  if (lst != "" && $0 ~ /^[ \t]*-[ \t]/) { x = $0; sub(/^[ \t]*-[ \t]*/, "", x); V[lst] = V[lst] "," unq(trim(x)) }
}
END {
  if (NR > 0) done_file()
  # Ranked by the rarity of each shared word across current Findings, so a word every lesson uses
  # cannot outvote one only this task and that Finding share.
  for (j = 1; j <= m; j++) {
    n = split(K[j], w, " "); c = 0; sc = 0
    for (i = 1; i <= n; i++) if (w[i] in T) { c++; sc += log((m + 1) / DF[w[i]]) }
    if (c >= (TG[j] ? 2 : 3)) printf "%.6f\t%s\t%s\n", sc, SL[j], L[j]
  }
}' "$@" | sort -t "$(printf '\t')" -k1,1nr -k2,2 | head -n "$MAX" | cut -f2-
}

ROWS="$(select_rows)"
if [ "$MODE" = record ]; then
  SLUGS="$(printf '%s\n' "$ROWS" | cut -f1 | paste -sd, -)"
  LINE="* KNOWLEDGE $(date -u +%Y-%m-%dT%H:%M:%SZ) · ${SLUGS:-none}"
  tmp="$TASK.kb-select.$$"
  LINE="$LINE" awk '
    { buf[NR] = $0 }
    END {
      line = ENVIRON["LINE"]
      for (i = 1; i <= NR; i++) if (!start && buf[i] == "# Notes") start = i
      if (!start) { for (i = 1; i <= NR; i++) print buf[i]; print ""; print "# Notes"; print ""; print line; exit }
      ins = NR
      for (i = start + 1; i <= NR; i++) if (buf[i] ~ /^# /) { ins = i - 1; break }
      while (ins > start && buf[ins] ~ /^[[:space:]]*$/) ins--
      for (i = 1; i <= NR; i++) { print buf[i]; if (i == ins) { if (ins == start) print ""; print line } }
    }' "$TASK" > "$tmp" && [ -s "$tmp" ] && mv "$tmp" "$TASK" ||
    { rm -f "$tmp"; echo "kb-select: could not write # Notes in $TASK" >&2; exit 2; }
  printf '%s\n' "$LINE"; exit 0
fi

if [ -z "$ROWS" ]; then
  printf 'none matched — no current Finding shares enough content words with this task.\n'
else
  printf '%s\n' "$ROWS" | awk -F'\t' '{ printf "[[%s]] — %s\n", $1, $2 }'
fi
