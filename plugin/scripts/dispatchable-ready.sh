#!/usr/bin/env bash
# dispatchable-ready.sh — the ONE reader of "which `ready` tasks could step 3 dispatch?"
#   Usage: dispatchable-ready.sh [--instance DIR] [--first]
# Prints `/projects/<slug>/tasks/<id>.md` per task: `ready`, kind build (task, else project,
# else build), no open_questions, every depends_on (a path, or a bare id in the same project)
# done or cancelled — unresolvable is unmet — then project-paused.sh and task-owner.sh not 1.
# Their exit 2 COUNTS: doubt never hides work. Cheapest gates first; `--first` stops at one.
# Exit 0 answered (maybe empty) · 2 cannot read · 3 usage. The cap is the caller's.
# Read by tick-delta.sh check and session-banner.sh; verified by tests/tick-delta.test.sh.
set -uo pipefail

inst="."; first=0
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || exit 3; inst="$2"; shift 2 ;;
    --first) first=1; shift ;;
    *) echo "Usage: $(basename "$0") [--instance DIR] [--first]" >&2; exit 3 ;;
  esac
done
root="$(cd "$inst" 2>/dev/null && pwd)" || exit 2
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

files=()
for f in "$root"/projects/*/project.md "$root"/projects/*/tasks/*.md; do
  [ -f "$f" ] && files+=("$f")
done
[ "${#files[@]}" -gt 0 ] || exit 0

cands="$(awk -v rootlen="${#root}" '
  function flush() {
    if (cur == "") return
    if (isproj) { pkind[slug] = kd; return }
    status[cur] = st; kindof[cur] = kd; slugof[cur] = slug; nq[cur] = q; depsof[cur] = deps
  }
  function add(v,   k) {
    sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
    if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
    if (v == "") return
    if (key == "open_questions") q++
    else deps = deps "\t" v
  }
  # Quote-aware: a `,` or `]` inside a quoted entry neither splits nor ends the list.
  function scan(s,   i, c) {
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (qt != "") { if (c == qt) qt = ""; buf = buf c; continue }
      if (c == "\"" || c == "\047") { qt = c; buf = buf c }
      else if (c == "]") { add(buf); buf = ""; inlist = 0; return }
      else if (c == ",") { add(buf); buf = "" }
      else if (c == "#" && buf ~ /(^|[[:space:]])$/) { return }
      else buf = buf c
    }
  }
  FNR == 1 {
    flush(); cur = substr(FILENAME, rootlen + 1); isproj = (cur ~ /\/project\.md$/)
    slug = cur; sub(/^\/projects\//, "", slug); sub(/\/.*/, "", slug)
    st = ""; kd = ""; q = 0; deps = ""; infm = ($0 == "---"); fmdone = 0; inlist = 0; inblock = 0
    next
  }
  fmdone || !infm { next }
  $0 == "---" { fmdone = 1; next }
  inlist { scan($0); next }
  inblock {
    if ($0 ~ /^[[:space:]]*-([[:space:]]|$)/) { v = $0; sub(/^[[:space:]]*-/, "", v); sub(/[[:space:]]+#.*$/, "", v); add(v); next }
    if ($0 ~ /^[[:space:]]*(#.*)?$/) next
    inblock = 0
  }
  /^(status|kind):/ {
    v = $0; sub(/^[a-z]+:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v)
    gsub(/["\047]/, "", v); sub(/[[:space:]]+$/, "", v)
    if ($0 ~ /^status:/ && st == "") st = v
    if ($0 ~ /^kind:/ && kd == "") kd = v
    next
  }
  /^(open_questions|depends_on):/ {
    key = $0; sub(/:.*/, "", key)
    v = $0; sub(/^[a-z_]+:[[:space:]]*/, "", v)
    if (substr(v, 1, 1) == "[") { inlist = 1; buf = ""; qt = ""; scan(substr(v, 2)) }
    else if (v == "" || substr(v, 1, 1) == "#") inblock = 1
    else add(v)
  }
  END {
    flush()
    for (p in status) {
      if (status[p] != "ready") continue
      k = kindof[p]; if (k == "") k = pkind[slugof[p]]
      if (k != "" && k != "build") continue
      if (nq[p] > 0) continue
      ok = 1; n = split(depsof[p], d, "\t")
      for (i = 2; i <= n; i++) {
        t = d[i]
        if (t ~ /^\/?projects\/[^\/]+\/tasks\/[^\/]+\.md$/) { if (substr(t, 1, 1) != "/") t = "/" t }
        else if (t ~ /^[A-Za-z0-9._-]+$/) { sub(/\.md$/, "", t); t = "/projects/" slugof[p] "/tasks/" t ".md" }
        else { ok = 0; break }
        if (!(t in status) || (status[t] != "done" && status[t] != "cancelled")) { ok = 0; break }
      }
      if (ok) print p
    }
  }
' "${files[@]}" | sort)" || exit 2

[ -n "$cands" ] || exit 0
while IFS= read -r p; do
  for gate in project-paused.sh task-owner.sh; do
    rc=0
    ( cd "$root" && bash "$here/$gate" "$root$p" >/dev/null 2>&1 ) || rc=$?
    [ "$rc" -eq 1 ] && continue 2
  done
  printf '%s\n' "$p"
  [ "$first" -eq 1 ] && exit 0
done <<EOF
$cands
EOF
exit 0
