#!/usr/bin/env bash
# kb-compare.sh — ONE candidate Finding against every `type: Finding` under knowledge/: the
# instance proposer behind `kb-propose.sh --proposer`. It writes nothing. From a bundle root.
#
#   kb-compare.sh [--instance DIR] <candidate.md>
#
# stdout: at most one kb-propose.sh proposal (merge, or patch as `edit`). stderr: one verdict —
# merge · patch · append as new · human-authored, review only · no proposal: unreadable.
# The key is the content words of title + description + lesson:; only an EQUAL key is the same.
# Exit: 0 compared · 1 no proposal: unreadable · 2 usage. Reasoning: knowledge-base-reflector/task-004.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

NEAR=0.50
ORIGPWD="$PWD"; INST="$PWD"; CAND=""
die() { echo "kb-compare: $2" >&2; exit "$1"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || die 2 "--instance needs a value"; INST="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" >&2; exit 2 ;;
    -*) die 2 "unknown argument '$1'" ;;
    *) [ -z "$CAND" ] || die 2 "one candidate at a time"; CAND="$1"; shift ;;
  esac
done
[ -n "$CAND" ] || die 2 "usage: kb-compare.sh [--instance DIR] <candidate.md>"
cdir="$(cd "$ORIGPWD" && cd -P "$(dirname "$CAND")" 2>/dev/null && pwd -P)" || die 2 "no such candidate: $CAND"
CAND="$cdir/$(basename "$CAND")"
[ -f "$CAND" ] || die 2 "no such candidate: $CAND"
CSLUG="$(basename "$CAND" .md)"
case "$CSLUG" in ""|*[!A-Za-z0-9._-]*) die 2 "'$CSLUG' is not a slug" ;; esac
INST="$(cd -P "$INST" 2>/dev/null && pwd -P)" || die 2 "no such instance directory"
cd "$INST" || exit 2
[ -d knowledge ] || die 2 "run from a bundle root (no knowledge/ here)"

# A mount is compared as it stands, never pulled: the HEAD it was read at goes in the reason.
if [ -d "$AB_DIR/kb.git" ]; then
  KBHEAD="mount@$(GIT_OPTIONAL_LOCKS=0 git --git-dir="$AB_DIR/kb.git" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
else
  KBHEAD="bundle@$(GIT_OPTIONAL_LOCKS=0 git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
fi

ITEMS=()
while IFS= read -r f; do
  [ -n "$f" ] && [ "$INST/$f" != "$CAND" ] && ITEMS+=("$f")
done <<EOF
$(find knowledge -mindepth 2 -maxdepth 2 -type f -name '*.md' | LC_ALL=C sort)
EOF

# Row per document: C|I, slug, type, provenance, superseded_by, tags, timestamp, lesson-ok,
# score, equal, words only in the candidate, words only in the item. Tab-separated.
FACTS="$(LC_ALL=C awk -v q="'" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function unq(s) { if (length(s) > 1 && (s ~ /^".*"$/ || (substr(s, 1, 1) == q && substr(s, length(s), 1) == q))) s = substr(s, 2, length(s) - 2); return s }
# Read with a tab IFS, which collapses empty fields, so an empty one is `-`.
function nz(s) { return (s == "") ? "-" : s }
function flat(s) { gsub(/[\t\r]/, " ", s); return s }
# Wording is normalised away (case, punctuation, order, articles, plurals); every other word is
# content, so an interpreter, a harness or a calling context that differs is a different key.
function words(s, set,   n, i, w, p, list) {
  s = tolower(s); gsub(/[^a-z0-9._-]/, " ", s); n = split(s, p, " "); list = ""
  for (i = 1; i <= n; i++) {
    w = p[i]; sub(/^[._-]+/, "", w); sub(/[._-]+$/, "", w)
    if (w == "" || (w in STOP)) continue
    if (length(w) > 4 && w ~ /ies$/) w = substr(w, 1, length(w) - 3) "y"
    else if (length(w) > 3 && w ~ /s$/ && w !~ /ss$/) w = substr(w, 1, length(w) - 1)
    if (!(w in set)) { set[w] = 1; list = list " " w }
  }
  return substr(list, 2)
}
BEGIN {
  split("a an the and of to is are was were be been being it its this that these those as", sw, " ")
  for (i in sw) STOP[sw[i]] = 1
  n = 0
}
FNR == 1 { n++; F[n] = FILENAME; infm = ($0 == "---"); blk = ""; lst = ""; next }
!infm { next }
$0 == "---" { infm = 0; next }
/^[A-Za-z_][A-Za-z0-9_]*:/ {
  k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*:/, "", v); v = trim(v); blk = ""; lst = ""
  if (v ~ /^[>|][-+]?[0-9]*$/) { blk = k; V[n, k] = ""; next }
  if (v == "") { lst = k; V[n, k] = ""; next }
  V[n, k] = unq(v); next
}
/^[ \t]/ {
  if (blk != "") { V[n, blk] = trim(V[n, blk] " " trim($0)); next }
  if (lst != "" && $0 ~ /^[ \t]*-[ \t]/) { x = $0; sub(/^[ \t]*-[ \t]*/, "", x); V[n, lst] = V[n, lst] "," unq(trim(x)) }
}
END {
  for (i = 1; i <= n; i++) {
    s = F[i]; sub(/.*\//, "", s); sub(/\.md$/, "", s); SLUG[i] = s
    g = V[i, "tags"]; gsub(/[][ ]/, "", g); gsub(/^,+|,+$/, "", g); gsub(/,,+/, ",", g); TAGS[i] = g
    LOK[i] = (trim(V[i, "lesson"]) != "") ? 1 : 0
  }
  delete CK; delete CS
  ck = words(V[1, "title"] " " V[1, "description"] " " V[1, "lesson"], CK); cn = split(ck, cw, " ")
  words(V[1, "title"] " " V[1, "description"], CS)
  printf "C\t%s\t%s\t%s\t-\t%s\t%s\t%d\n", SLUG[1], nz(V[1, "type"]), nz(V[1, "provenance"]), nz(TAGS[1]), nz(flat(V[1, "timestamp"])), (LOK[1] && cn > 0)
  for (i = 2; i <= n; i++) {
    if (V[i, "type"] != "Finding") continue
    delete IK
    if (LOK[i]) { ik = words(V[i, "title"] " " V[i, "description"] " " V[i, "lesson"], IK); ref = "CK" }
    else        { ik = words(V[i, "title"] " " V[i, "description"], IK); ref = "CS" }
    m = split(ik, iw, " "); inter = 0; plus = ""; minus = ""
    for (j = 1; j <= m; j++) {
      w = iw[j]
      if ((ref == "CK" && (w in CK)) || (ref == "CS" && (w in CS))) inter++; else minus = minus "," w
    }
    if (ref == "CK") { base = cn; for (j = 1; j <= cn; j++) if (!(cw[j] in IK)) plus = plus "," cw[j] }
    else { base = 0; for (w in CS) base++ }
    u = base + m - inter; sc = (u > 0) ? inter / u : 0
    sb = V[i, "superseded_by"]; sub(/[ \t]+#.*/, "", sb); pv = V[i, "provenance"]; sub(/[ \t]+#.*/, "", pv)
    printf "I\t%s\tFinding\t%s\t%s\t%s\t%s\t%d\t%.2f\t%d\t%s\t%s\n", SLUG[i], nz(pv), nz(sb), nz(TAGS[i]), nz(flat(V[i, "timestamp"])), LOK[i], sc, (LOK[i] && inter == cn && inter == m && cn > 0), nz(substr(plus, 2)), nz(substr(minus, 2))
  }
}' "$CAND" ${ITEMS[@]+"${ITEMS[@]}"})" || die 2 "could not read knowledge/"

IFS=$'\t' read -r _ _ ctype _ _ ctags cts cok _ <<<"$(sed -n 1p <<<"$FACTS")"
[ "$ctype" = Finding ] || die 2 "$CSLUG is not a 'type: Finding' — only a Finding is compared"
verdict() { echo "kb-compare: $1 · $CSLUG · $2 · $3 · kb $KBHEAD" >&2; }
row() { awk -F'\t' -v s="$1" '$1 == "I" && $2 == s { print; exit }' <<<"$FACTS"; }
[ "$cok" = 1 ] || { verdict "no proposal: unreadable" - "its lesson: is empty or unreadable, so nothing can be ruled out"; exit 1; }

NEARS="$(awk -F'\t' -v near="$NEAR" '$1 == "I" && $9 + 0 >= near + 0' <<<"$FACTS" | LC_ALL=C sort -t$'\t' -k9,9nr -k2,2)"
[ -n "$NEARS" ] || { verdict "append as new" - "no Finding shares $NEAR of its content words"; exit 0; }
blind="$(awk -F'\t' '$8 == 0 { printf "%s%s", s, $2; s = "," }' <<<"$NEARS")"
[ -z "$blind" ] || { verdict "no proposal: unreadable" "$blind" "a near Finding has an empty or unreadable lesson:, so it cannot be ruled out"; exit 1; }

IFS=$'\t' read -r _ best _ _ _ _ _ _ bscore bequal bplus bminus <<<"$(sed -n 1p <<<"$NEARS")"
rest="$(sed 1d <<<"$NEARS" | awk -F'\t' '{ printf "%s%s %s", s, $2, $9; s = ", " }')"
also="${rest:+; also near: $rest}"
if [ "$bequal" != 1 ]; then
  verdict "append as new" "$best" "nearest $best ($bscore) differs in content words — only here: $bplus; only there: $bminus$also"
  exit 0
fi

target="$best"; via=""; hops=0
while :; do
  r="$(row "$target")"
  [ -n "$r" ] || { verdict "no proposal: unreadable" "$best" "superseded_by names $target, which is no Finding$also"; exit 1; }
  IFS=$'\t' read -r _ _ _ tprov tsup ttags _ <<<"$r"
  [ "$tsup" != - ] || break
  hops=$((hops + 1)); [ "$hops" -le 10 ] || { verdict "no proposal: unreadable" "$best" "superseded_by does not end within 10 hops"; exit 1; }
  via="$via$target → "; target="$tsup"
done
edge="${via:+; matched ${via}$target via superseded_by}"
if [ "$tprov" != machine ]; then
  verdict "human-authored, review only" "$target" "every content word equals $best (1.00), but $target is not provenance: machine$edge$also"
  exit 0
fi

new=""
[ "$ttags" != - ] || ttags=""; [ "$ctags" != - ] || ctags=""; [ "$cts" != - ] || cts=""
IFS=, read -ra ct <<<"$ctags"
for t in ${ct[@]+"${ct[@]}"}; do
  case ",$ttags,$new," in *",$t,"*) ;; *) new="$new,$t" ;; esac
done
why="every content word of title, description and lesson: equals $best (1.00)$edge$also; kb $KBHEAD"
if [ -n "$new" ]; then
  union="$ttags$new"; union="${union#,}"
  echo "edit · $target · tags=[${union//,/, }] · $CSLUG · patch: $CSLUG adds tags ${new#,} — $why"
  verdict patch "$target" "tags=[${union//,/, }]"
else
  [ -n "$cts" ] || cts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "merge · $target · timestamp=$cts · $CSLUG · merge: $CSLUG restates $target — $why"
  verdict merge "$target" "timestamp=$cts"
fi
exit 0
