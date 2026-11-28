#!/usr/bin/env bash
#
# open-project-match.sh — the one open project a new ask most likely belongs to, or nothing.
#
#   Usage: open-project-match.sh <bundle> <build|research> [<org>/<repo>] --text-file <f>
#
# Prints at most one `<slug>\t<title>`: an open project (not done; no kind: is build) of that kind
# and, when given, that target_repo, sharing the most content words (two or more) with its title
# and description; ties go to the newest timestamp. Read-only. Exit: 0 printed or none · 2 usage.
# Reasoning: prefer-tasks-in-open-projects/task-003.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/kb-words.sh" || exit 2
usage() { sed -n '5p' "$0" >&2; exit 2; }

text=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --text-file) [ $# -ge 2 ] || usage; text="$2"; shift 2 ;;
    -*) usage ;;
    *) args+=("$1"); shift ;;
  esac
done
[ -n "$text" ] && [ ${#args[@]} -ge 2 ] && [ ${#args[@]} -le 3 ] || usage
bundle="${args[0]}"; kind="${args[1]}"; repo=""
[ ${#args[@]} -eq 3 ] && repo="$(kb_repo_norm "${args[2]}")"
case "$kind" in build|research) ;; *) usage ;; esac
[ -d "$bundle" ] || { echo "open-project-match: no bundle at $bundle" >&2; exit 2; }
[ -f "$text" ] && [ -r "$text" ] || { echo "open-project-match: cannot read $text" >&2; exit 2; }

shopt -s nullglob
docs=("$bundle"/projects/*/project.md)
[ ${#docs[@]} -gt 0 ] && [ -s "$text" ] || exit 0

awk -v want_kind="$kind" -v want_repo="$repo" -v q="'" "$KB_WORDS_AWK"'
function norm(r) {
  r = tolower(r); sub(/^https:\/\/github\.com\//, "", r); sub(/^git@github\.com:/, "", r)
  sub(/\/$/, "", r); sub(/\.git$/, "", r); sub(/\/$/, "", r); return r
}
function val(s) {
  sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+$/, "", s)
  if (s ~ /^".*"$/) { s = substr(s, 2, length(s) - 2); gsub(/\\"/, "\"", s) }
  else if (length(s) > 1 && substr(s, 1, 1) == q && substr(s, length(s)) == q) { s = substr(s, 2, length(s) - 2); gsub(q q, q, s) }
  else sub(/[ \t]+#.*$/, "", s)
  return s
}
function content(s, out,   raw, n, p, i, k) {
  delete raw; n = split(words(s, raw), p, " "); k = 0
  for (i = 1; i <= n; i++) if (length(p[i]) > 1 && !(p[i] in STOPX)) { out[p[i]] = 1; k++ }
  return k
}
function judge(   have, w, shared) {
  if (!slug || st == "done" || (kd == "" ? "build" : kd) != want_kind) return
  if (want_repo != "" && norm(rp) != want_repo) return
  delete have; content(ti " " de, have); shared = 0
  for (w in have) if (w in ASK) shared++
  if (shared < 2) return
  if (shared > best || (shared == best && ts > best_ts)) { best = shared; best_ts = ts; best_slug = slug; best_title = ti }
}
BEGIN {
  words("add also all any are can could do does done each for from get has have how in into " \
        "just loopd make may more must new not now on one only or our over per project run same " \
        "should skill so some such than then task there they too two up use via want we when " \
        "where which while who will with would you your", STOPX)
}
FNR == 1 && NR != 1 { judge(); slug = ""; fm = 0; st = kd = rp = ti = de = ts = ""; key = "" }
NR == FNR { ask = ask " " $0; next }
FNR == 1 {
  if (ASK_SET == "") { content(ask, ASK); ASK_SET = 1 }
  n = split(FILENAME, a, "/"); slug = a[n - 1]
  if ($0 == "---") fm = 1
  next
}
!fm { next }
$0 == "---" { fm = 0; next }
/^[A-Za-z_][A-Za-z0-9_]*:/ {
  key = $0; sub(/:.*/, "", key); v = val($0)
  if (key == "status") st = v; else if (key == "kind") kd = v; else if (key == "target_repo") rp = v
  else if (key == "title") ti = v; else if (key == "description") de = v; else if (key == "timestamp") ts = v
  next
}
/^[ \t]/ { if (key == "title") ti = ti " " $0; else if (key == "description") de = de " " $0 }
END {
  judge()
  if (best_slug != "") { gsub(/[\t\r\n]+/, " ", best_title); printf "%s\t%s\n", best_slug, best_title }
}' "$text" "${docs[@]}"
