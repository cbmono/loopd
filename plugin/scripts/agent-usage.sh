#!/usr/bin/env bash
# agent-usage.sh — what the harness handed back, recorded where the work is.
# `fmt` prints the ONE fixed usage form (tick-delta.sh's close line calls it too);
# `dispatch <task>` appends one `# Notes` line per role dispatch; `total <task>` sums
# those lines against the merged PR(s) at reflect time; `settle <task>` fills the LAST
# `usage UNKNOWN` dispatch line once a detached session's numbers exist (session-usage.sh
# supplies them, `--cached`/`--errors`/`--by` appended after the fixed three — this file
# still reads no transcript); `series` prints the monthly
# figures from log.md's TICK pairs and the task docs' dispatch lines — file reads only,
# no `gh`, no transcript. Denominated in TOKENS: no money anywhere, ever.
# Exit: 0 done, 1 refused (already written), 2 cannot answer, 3 usage.
# Reasoning: ai-bridge-v3/task-001.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

NOTES='# Notes'
UNKNOWN='usage UNKNOWN'

usage() { sed -n '2,10p' "$0" >&2; exit 3; }
die2() { echo "agent-usage: $1" >&2; exit 2; }
die3() { echo "agent-usage: $1" >&2; exit 3; }

cmd="${1:-}"; [ "$#" -gt 0 ] && shift
case "$cmd" in fmt|dispatch|total|settle|series) ;; *) usage ;; esac

doc=""
case "$cmd" in
  dispatch|total|settle)
    doc="${1:-}"; [ -n "$doc" ] || usage; shift
    [ -f "$doc" ] && [ -w "$doc" ] || die2 "no writable task document: $doc" ;;
esac

inst="."; tokens=""; tools=""; ms=""; role=""; model=""; prs=""; cached=""; errors=""; by=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die3 "$1 needs a value"
  case "$1" in
    --instance)    inst="$2" ;;
    --tokens)      tokens="$2" ;;
    --tools)       tools="$2" ;;
    --duration-ms) ms="$2" ;;
    --cached)      cached="$2" ;;
    --errors)      errors="$2" ;;
    --by)          by="$2" ;;
    --role)        role="$2" ;;
    --model)       model="$2" ;;
    --pr)          prs="${prs:+$prs }$2" ;;
    *) usage ;;
  esac
  shift 2
done

num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# All three or none: a partial notification is not a measurement, and a half-filled line
# would be summed as though it were one.
fmt() { # <tokens> <tools> <ms>
  if num "${1:-}" && num "${2:-}" && num "${3:-}"
  then printf 'usage tokens=%s tools=%s ms=%s\n' "$1" "$2" "$3"
  else printf '%s\n' "$UNKNOWN"; fi
}

append_note() { # <file> <line> — into the FIRST `# Notes` section, created if absent
  local tmp="$1.usage.$$"
  LINE="$2" HEAD="$NOTES" awk '
    { buf[NR] = $0 }
    END {
      line = ENVIRON["LINE"]; head = ENVIRON["HEAD"]
      for (i = 1; i <= NR; i++) if (!start && buf[i] == head) start = i
      if (!start) {
        for (i = 1; i <= NR; i++) print buf[i]
        print ""; print head; print ""; print line; exit
      }
      ins = NR
      for (i = start + 1; i <= NR; i++) if (buf[i] ~ /^# /) { ins = i - 1; break }
      while (ins > start && buf[ins] ~ /^[[:space:]]*$/) ins--
      for (i = 1; i <= NR; i++) {
        print buf[i]
        if (i == ins) { if (buf[ins] !~ /^\* (DISPATCH|TOTAL) /) print ""; print line }
      }
    }
  ' "$1" > "$tmp" || { rm -f "$tmp"; die2 "cannot write beside $1"; }
  [ -s "$tmp" ] || { rm -f "$tmp"; die2 "refusing to replace $1 with an empty file"; }
  mv "$tmp" "$1" || { rm -f "$tmp"; die2 "cannot replace $1"; }
}

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "$cmd" in
  fmt)
    fmt "$tokens" "$tools" "$ms" ;;

  dispatch)
    [ -n "$role" ] || die3 "dispatch needs --role"
    append_note "$doc" "* DISPATCH $now · $role · model ${model:-unset} · $(fmt "$tokens" "$tools" "$ms")"
    echo "recorded: $doc" ;;

  settle)
    # Numbers or nothing: an UNKNOWN is left as it is, never overwritten with a guess.
    num "$tokens" && num "$tools" && num "$ms" || die3 "settle needs --tokens, --tools and --duration-ms"
    grep -q "^\* DISPATCH .*$UNKNOWN\$" "$doc" || {
      echo "REFUSED: $doc has no dispatch line still recording $UNKNOWN." >&2; exit 1; }
    new="$(fmt "$tokens" "$tools" "$ms")"; num "$cached" && new="$new cached=$cached"
    # `by` is the one value that is not a number: it must stay one space-free token, in the
    # shape session-usage.sh prints, or the line it lands on stops being one key=value line.
    by_re='^(-|[A-Za-z0-9_.-]+:[0-9]+(,[A-Za-z0-9_.-]+:[0-9]+){0,4})$'
    [ -z "$by" ] || [[ $by =~ $by_re ]] || die3 "settle: --by takes Name:N,… (at most five) or -"
    num "$errors" && new="$new errors=$errors"
    [ -n "$by" ] && new="$new by=$by"
    tmp="$doc.usage.$$"
    NEW="$new" UNK="$UNKNOWN" awk '
      { buf[NR] = $0; if ($0 ~ /^\* DISPATCH / && substr($0, length($0) - length(ENVIRON["UNK"]) + 1) == ENVIRON["UNK"]) last = NR }
      END { for (i = 1; i <= NR; i++) {
              if (i == last) print substr(buf[i], 1, length(buf[i]) - length(ENVIRON["UNK"])) ENVIRON["NEW"]
              else print buf[i] } }
    ' "$doc" > "$tmp" || { rm -f "$tmp"; die2 "cannot write beside $doc"; }
    [ -s "$tmp" ] || { rm -f "$tmp"; die2 "refusing to replace $doc with an empty file"; }
    mv "$tmp" "$doc" || { rm -f "$tmp"; die2 "cannot replace $doc"; }
    echo "settled: $doc" ;;

  total)
    [ -n "$prs" ] || die3 "total needs at least one --pr"
    if grep -q '^\* TOTAL ' "$doc"; then
      echo "REFUSED: $doc already carries a TOTAL line — not double-writing." >&2; exit 1
    fi
    sums="$(awk '
      /^\* DISPATCH / {
        rounds++
        if (match($0, /usage tokens=[0-9]+ tools=[0-9]+ ms=[0-9]+/)) {
          split(substr($0, RSTART, RLENGTH), a, " ")
          sub(/^[a-z]+=/, "", a[2]); sub(/^[a-z]+=/, "", a[3]); sub(/^[a-z]+=/, "", a[4])
          t += a[2]; c += a[3]; d += a[4]; measured++
        }
      }
      END { printf "%d %d %d %d %d\n", rounds + 0, measured + 0, t + 0, c + 0, d + 0 }
    ' "$doc")"
    set -- $sums
    [ "$#" -eq 5 ] || die2 "could not read the dispatch lines in $doc"
    # A task nobody measured is UNKNOWN, never zero — zero is a claim nothing supports.
    [ "$2" -gt 0 ] || { set -- "$1" "$2" "" "" ""; }
    append_note "$doc" "* TOTAL $now · rounds=$1 · $(fmt "$3" "$4" "$5") · $prs"
    echo "recorded: $doc" ;;

  series)
    [ -d "$inst" ] || die2 "no such instance directory: $inst"
    [ -r "$inst/$AB_LEDGER" ] || die2 "no readable $inst/$AB_LEDGER"
    { cat "$inst/$AB_LEDGER"
      for f in "$inst"/projects/*/tasks/*.md; do [ -r "$f" ] && cat "$f"; done
    } | awk '
      function val(s, k,   r) {
        if (match(s, k "=[0-9]+")) { r = substr(s, RSTART, RLENGTH); sub(/^[a-z]+=/, "", r); return r + 0 }
        return -1
      }
      function acc(kind, m, s,   a, b, c) {
        a = val(s, "tokens"); b = val(s, "tools"); c = val(s, "ms")
        if (a < 0 || b < 0 || c < 0) return 0
        tok[kind m] += a; tol[kind m] += b; dur[kind m] += c; return 1
      }
      function ord(m) { return substr(m, 1, 4) * 12 + substr(m, 6, 2) - 1 }
      function shape(n, k) {
        return n > 0 ? sprintf("usage tokens=%d tools=%d ms=%d", tok[k], tol[k], dur[k]) : "usage UNKNOWN"
      }
      # Whichever marker comes FIRST decides the line — the same rule tick-delta.sh
      # closes by. A close summary is free prose and may quote the other word.
      $0 ~ /^\* TICK [0-9][0-9][0-9][0-9]-[0-9][0-9]-/ {
        o = index($0, " open: "); c = index($0, " close: ")
        if (o == 0 || (c > 0 && c < o)) {
          m = substr($3, 1, 7); tick[m]++; tickm[m] += acc("t", m, $0); seen[m] = 1
        }
        next
      }
      $0 ~ /^\* DISPATCH [0-9][0-9][0-9][0-9]-[0-9][0-9]-/ {
        m = substr($3, 1, 7); disp[m]++; dispm[m] += acc("d", m, $0); seen[m] = 1
      }
      END {
        for (m in seen) { o = ord(m); if (!lo || o < lo) lo = o; if (o > hi) hi = o }
        if (!lo) { print "UNKNOWN — no TICK or DISPATCH lines recorded in this bundle"; exit }
        for (o = lo; o <= hi; o++) {
          m = sprintf("%04d-%02d", int(o / 12), o % 12 + 1)
          printf "%s · ticks %d (%d measured) %s · dispatches %d (%d measured) %s\n", m,
            tick[m] + 0, tickm[m] + 0, shape(tickm[m], "t" m),
            disp[m] + 0, dispm[m] + 0, shape(dispm[m], "d" m)
        }
      }
    ' ;;
esac
