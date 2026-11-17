#!/usr/bin/env bash
#
# wording-notes.sh — report-only: each banned word (plugin/data/banned-words.txt) and each
# sentence over 25 words, 20 in a numbered step. Code, URLs and table rows are not sentences.
#
#   Usage: wording-notes.sh <file|->   one `note: line N: …` per hit, on stdout
#
#   0 always, after reading · 2 usage or IO. Callers print it on stderr and ignore its exit.
# Reasoning: all-code-is-slop-lessons/task-019 (ASD-STE100 rules 3 and 6).
set -uo pipefail

[ $# -eq 1 ] || { echo "Usage: $(basename "$0") <file|->" >&2; exit 2; }
[ "$1" = - ] || [ -r "$1" ] || { echo "wording-notes: cannot read '$1'" >&2; exit 2; }
words="$(dirname "${BASH_SOURCE[0]}")/../data/banned-words.txt"
[ -r "$words" ] || { echo "note: banned-word list missing ($words) — words not checked"; words=/dev/null; }

LC_ALL=C awk -v LIST="$words" '
function clean(s) {
  gsub(/`[^`]*`/, " ", s); gsub(/\]\([^)]*\)/, "]", s); gsub(/<?https?:\/\/[^ \t)>]+>?/, " ", s)
  return s
}
function banned(s, n,   t, w, i, k, b) {
  t = tolower(s); gsub(/[^a-z]+/, " ", t); k = split(t, w, " ")
  for (i = 1; i <= k; i++) {
    b = w[i]
    if (!(b in BAN)) { sub(/(s|es|d|ed|ing)$/, "", b); if (!(b in BAN) && !((b "e") in BAN)) continue }
    printf "note: line %d: banned word \"%s\"\n", n, w[i]
  }
}
function flush(   t, s, cnt, k, i, w, lim) {
  if (para == "") return
  lim = step ? 20 : 25
  t = para; gsub(/(e\.g|i\.e|etc|vs|cf)\./, "x", t)
  while (t != "") {
    if (match(t, /[.!?]+([ \t]|$)/)) { s = substr(t, 1, RSTART); t = substr(t, RSTART + RLENGTH) }
    else { s = t; t = "" }
    k = split(s, w, /[ \t]+/); cnt = 0
    for (i = 1; i <= k; i++) if (w[i] ~ /[A-Za-z0-9]/) cnt++
    if (cnt > lim) printf "note: line %d: sentence of %d words, over %d%s — split it, keep every fact\n", pline, cnt, lim, step ? " in a numbered step" : ""
  }
  para = ""; step = 0
}
BEGIN { while ((getline w < LIST) > 0) { w = tolower(w); gsub(/[^a-z]/, "", w); if (w != "") BAN[w] = 1 } }
{
  line = $0
  if (line ~ /^[ \t]*(```|~~~)/) { flush(); fence = !fence; next }
  if (fence) next
  c = clean(line)
  banned(c, NR)
  if (c ~ /^[ \t]*$/ || line ~ /^[ \t]*\|/) { flush(); next }
  if (c ~ /^[ \t]*(#|>|[-*+][ \t]|[0-9]+[.)][ \t])/) {
    flush(); step = (c ~ /^[ \t]*[0-9]+[.)][ \t]/)
    sub(/^[ \t]*(#+|>+|[-*+]|[0-9]+[.)])[ \t]*/, "", c)
  }
  if (para == "") pline = NR
  para = para " " c
}
END { flush() }' "$1"
exit 0
