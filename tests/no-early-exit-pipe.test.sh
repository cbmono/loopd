#!/usr/bin/env bash
# no-early-exit-pipe.test.sh — no test pipes into a reader that can stop before EOF.
# Under `set -o pipefail` such a reader leaves its writer to die on EPIPE, so a MATCH reports
# as a FAILURE, intermittently (knowledge: grep-q-under-pipefail-reports-a-match-as-a-failure).
# The pattern keys on the READER, never on what the left side interpolates: grep -q/-m/-l/-L
# (and long forms), head, a bare read, sed …q and awk …exit. The fix is a here-string.
# Lines that are data, not a pipe the harness runs: tests/fixtures/no-early-exit-pipe/exempt.tsv.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEMPT="$HERE/fixtures/no-early-exit-pipe/exempt.tsv"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/no-early-exit-pipe.XXXXXX")" || {
  echo "no-early-exit-pipe.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [ "$2" = 0 ]; then pass=$((pass+1)); echo "  PASS  $1"; else fail=$((fail+1)); echo "  FAIL  $1"; fi; }

# The reader names are bracketed so this file never matches itself.
PFX='(^|[^|])[|][[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|command|env)[[:space:]]+)*'
GREP='[g]rep([[:space:]]+[^|&;)[:space:]]+)*[[:space:]]+(-[A-Za-z0-9]*[qmlL]|--(quiet|silent|max-count|files-with(out)?-match))'
OTHER='([h]ead|[r]ead)([[:space:]]|$|[)])|[s]ed[[:space:]][^|]*[0-9$/;{][[:space:]]*q([[:space:]0-9;}'"'"'"]|$)|[a]wk[[:space:]][^|]*[^A-Za-z_]exit([^A-Za-z_]|$)'
RE="$PFX($GREP|$OTHER)"

exempt() { # <file> <text> -> 0 when exempt.tsv names this line
  local f t why
  while IFS=$'\t' read -r f t why; do
    [ "$f" = "$1" ] && [[ "$2" == *"$t"* ]] && return 0
  done < "$EXEMPT"
  return 1
}

scan() { # <dir> -> `file:line: text` per pipe into an early-exiting reader
  local hit loc text
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    loc="${hit%%:*}"; hit="${hit#*:}"; loc="${loc##*/}:${hit%%:*}"; text="${hit#*:}"
    [[ "$text" =~ ^[[:space:]]*# ]] && continue
    exempt "${loc%%:*}" "$text" && continue
    printf '%s: %s\n' "$loc" "$text"
  done <<<"$(grep -HnE "$RE" "$1"/*.test.sh || true)"
}

echo "== no test pipes into an early-exiting reader =="
hits="$(scan "$HERE")"
[ -z "$hits" ] || printf '%s\n' "$hits"
assert "no pipe into grep -q/-m/-l, head, read, sed q or awk exit in tests/" "$([ -z "$hits" ] && echo 0 || echo 1)"

echo "== every exemption still names a line =="
while IFS=$'\t' read -r f t why; do
  case "$f" in '#'*|'') continue ;; esac
  n=0
  while IFS= read -r line; do [[ "$line" == *"$t"* ]] && n=$((n+1)); done < "$HERE/$f"
  assert "exempt: $f — $why ($n)" "$([ "$n" -ge 1 ] && echo 0 || echo 1)"
done < "$EXEMPT"

echo "== the pattern keys on the reader, not on what the left side interpolates =="
# `¦` stands for the pipe, so these cases are not hits in this file.
flagged() { # <case> -> 0 when scan reports it
  rm -f "$TMP"/*.test.sh
  printf '%s\n' "${1//¦/|}" > "$TMP/case.test.sh"
  [ -n "$(scan "$TMP")" ] && echo 0 || echo 1
}
while IFS= read -r c; do
  assert "flags: $c" "$(flagged "$c")"
done <<'CASES'
printf '%s\n' "$1" ¦ grep -q x && echo 0
printf '%s\n' "$OUT" ¦ grep -q x && echo 0
printf '%s' "$IDX_SELF" ¦ grep -qF 'SKIP'
printf '%s\n' "${arr[@]}" ¦ grep -qxF "$t"
step05 ¦ grep -qF 'End the tick'
grep -o 'a' "$f" ¦ grep -Fq -- "$1"
printf '%s' "$OUT" ¦ LC_ALL=C grep -q "$ESC"
printf '%s' "$OUT" ¦ grep -E -q x
printf '%s' "$OUT" ¦ grep --quiet x
printf '%s' "$OUT" ¦ grep -m1 x
printf '%s' "$OUT" ¦ grep --max-count=1 x
printf '%s' "$OUT" ¦ grep -l x
     ¦ grep -qE '^loopd' && echo 0 || echo 1)"
x="$(ls "$d" ¦ head -1)"
yes ¦ head -40
printf '%s' "$OUT" ¦ read -r first
printf '%s' "$OUT" ¦ sed -n '1p;q'
printf '%s' "$OUT" ¦ awk '/x/{print; exit}'
CASES
while IFS= read -r c; do
  assert "passes: $c" "$(flagged "$c" | tr 01 10)"
done <<'CASES'
grep -q x <<<"$OUT" && echo 0
grep -qF -- "$2" <<<"$(step05)"
printf '%s\n' "$OUT" ¦ while read -r l; do :; done
[ "$(printf '%s\n' "$B" ¦ grep -c .)" -le 4 ]
printf '%s\n' "$OUT" ¦ grep -v x ¦ wc -l
printf '%s\n' "$OUT" ¦ grep --line-number x
printf '%s\n' "$OUT" ¦ sed 's/q/x/'
printf '%s\n' "$OUT" ¦ awk '{print $1}'
printf '%s\n' "$OUT" ¦ headline
[ -f "$f" ] ¦¦ grep -q x "$f"
# printf '%s\n' "$OUT" ¦ grep -q x
CASES

echo "== a named-variable pipe in a real harness turns the guard red =="
cp "$HERE"/*.test.sh "$TMP/"
rm -f "$TMP/case.test.sh"
before="$(scan "$TMP")"
mutant='assert x "$(printf '"'"'%s\n'"'"' "$IDX_SELF" ¦ grep -q '"'"'SKIP'"'"' && echo 1 || echo 0)"'
printf '%s\n' "${mutant//¦/|}" >> "$TMP/validate-bundle.test.sh"
after="$(scan "$TMP")"
assert "the copied tree scans clean before the mutant" "$([ -z "$before" ] && echo 0 || echo 1)"
assert "…and names validate-bundle.test.sh after it" "$([[ "$after" == validate-bundle.test.sh:* ]] && echo 0 || echo 1)"

echo "== the here-string form is what has()/hasnt() use =="
n="$(grep -l -E '^has\(\)  *\{ grep -q' "$HERE"/*.test.sh | wc -l | tr -d ' ')"
assert "at least a dozen harnesses define has() on a here-string ($n)" "$([ "$n" -ge 12 ] && echo 0 || echo 1)"

echo
echo "pass=$pass fail=$fail skip=0"
[ "$fail" -eq 0 ]
