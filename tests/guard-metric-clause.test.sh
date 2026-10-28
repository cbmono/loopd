#!/usr/bin/env bash
#
# guard-metric-clause.test.sh — a criterion that moves a measured number names a guard
# metric, the number that must not get worse. Refine (step 2), /loopd:new-project and
# SCHEMA.md each carry four strings: the guard-metric sentence, `today's value`, the
# cannot-measure-yet fallback and the docs/behaviour exemption. Text is whitespace-
# normalised first so a rewrap cannot fail it; a mutant per string per doc must fail.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DOCS=(
  "$REPO/plugin/tick-steps/step-2-refine-drafts.md"
  "$REPO/plugin/skills/new-project/SKILL.md"
  "$REPO/plugin/seed/SCHEMA.md"
)
PINS=(
  "names a guard metric — the number that must not get worse — as a second criterion with its own command and today's value"
  "today's value"
  '`a measurement exists for <X>`'
  'A docs or behaviour criterion needs no guard metric, and a guard metric is not `/audit`'"'"'s counter-metric'
)
TMP="$(mktemp -d "${TMPDIR:-/tmp}/guard-metric.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-72s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %-72s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
flat() { tr '\n\t' '  ' < "$1" | tr -s ' '; }
has() { # <flat-file> <pin>
  grep -qF -- "$2" "$1" && echo yes || echo no; }

for doc in "${DOCS[@]}"; do
  name="${doc#"$REPO"/plugin/}"
  ok "$name exists" "$([ -f "$doc" ] && echo yes || echo no)" yes
  flat "$doc" > "$TMP/flat"
  for i in "${!PINS[@]}"; do
    pin="${PINS[$i]}"
    ok "$name pins #$((i+1)): ${pin:0:40}…" "$(has "$TMP/flat" "$pin")" yes
    awk -v p="$pin" '{ while ((k = index($0, p)) > 0) $0 = substr($0, 1, k-1) substr($0, k+length(p)); print }' \
      "$TMP/flat" > "$TMP/mutant"
    ok "$name mutant without #$((i+1)) fails the pin" "$(has "$TMP/mutant" "$pin")" no
  done
done

echo
echo "guard-metric-clause: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
