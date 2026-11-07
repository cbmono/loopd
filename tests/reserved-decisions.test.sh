#!/usr/bin/env bash
#
# reserved-decisions.test.sh — pins every entry of CONVENTIONS.md → "Reserved decisions", the
# blocked-with-a-question rule in the three agents bound by it, and qa-reviewer's blocking
# finding. Each check runs once against the shipped files and once per mutant with one
# anchor removed, so deleting an entry or a rule fails here.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
AG="$REPO/plugin/agents"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/reserved-decisions.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 — got [$2], want [$3]"; fi; }

ENTRIES=(
  '`eslint-disable`' '`@ts-ignore`' '`@ts-expect-error`' '`# shellcheck disable=`'
  'a config override that turns a rule off'
  '`.skip`' '`xit`' 'a skip marker' 'a deleted assertion'
  '**`continue-on-error`**' '**Widening an interface**' '**A new runtime dependency or pattern**'
  '**Weakening a gate**' '**Changing an auth or exposure boundary**'
)
RULE=(
  '**On a hit, make no such change.**' 'Set the task `status: blocked`'
  'numbered\n`open_questions` entry naming the decision and the failing check'
  'with its `### Q<n>` block' '`software-engineer`, `devops-engineer` and\n`qa-reviewer`'
  'never a row under a PR body'"'"'s `### Decided\nwithout asking`'
  'never an "Unapproved decision:" advisory' '**blocking finding**'
  '**A hit is a line your diff ADDS to code or CI config to make a check pass.**'
)
AGENT_RULE=(
  '**A reserved decision is never your route to green**' '`CONVENTIONS.md` → "Reserved\ndecisions"): if getting CI green would need one'
  'make no such change, set the task\n`status: blocked`' 'numbered `open_questions`'
  '`### Q<n>` block naming\nthe decision and the failing check, and stop.'
)
QA_FINDING=(
  '**A reserved decision is a blocking finding, never an advisory**'
  '`verdict: changes-requested` with the decision and its file in `caveats`'
  'never an\n   "Unapproved decision:" line'
)

section() { awk '/^## Reserved decisions$/{on=1; next} on && /^## /{exit} on' "$1"; }
# Whitespace-normalised containment, so a re-wrap never fails a check but a deletion does.
flat() { tr '\n' ' ' | tr -s ' '; }
contains() { local hay needle; hay="$(flat)"; needle="$(printf '%b' "$1" | sed 's/^ *//' | flat)"
  case "$hay" in *"$needle"*) echo yes ;; *) echo no ;; esac; }
missing() { # <text-file> <anchor...> → count of anchors not found
  local f="$1" n=0 a; shift
  for a in "$@"; do [ "$(contains "$a" < "$f")" = yes ] || n=$((n+1)); done; echo "$n"; }
without() { # <src> <anchor> <dst> — drop the anchor's first occurrence, whitespace-normalised
  local needle; needle="$(printf '%b' "$2" | flat)"
  flat < "$1" | awk -v n="$needle" '{ i=index($0,n); if (i) $0=substr($0,1,i-1) substr($0,i+length(n)); print }' > "$3"; }

echo "== the shipped files =="
ok "CONVENTIONS has exactly one '## Reserved decisions'" "$(grep -c '^## Reserved decisions$' "$CONV")" 1
section "$CONV" > "$TMP/sec"
ok "section lists every entry" "$(missing "$TMP/sec" "${ENTRIES[@]}")" 0
ok "section states the blocked-with-a-question rule" "$(missing "$TMP/sec" "${RULE[@]}")" 0
for r in software-engineer devops-engineer qa-reviewer; do
  ok "$r states the rule" "$(missing "$AG/$r.md" "${AGENT_RULE[@]}")" 0
done
ok "qa-reviewer: a hit is a blocking finding" "$(missing "$AG/qa-reviewer.md" "${QA_FINDING[@]}")" 0
for r in software-engineer devops-engineer; do
  ok "$r: never a Decided-without-asking row" \
     "$(contains 'It is never a `### Decided without asking` row.' < "$AG/$r.md")" yes
done

echo "== mutants: one anchor removed, the check must fail =="
mut() { # <label> <file> <anchor> <anchor-set...>
  local label="$1" f="$2" a="$3"; shift 3
  without "$f" "$a" "$TMP/m"
  [ "$(cmp -s <(flat < "$f") "$TMP/m"; echo $?)" = 0 ] && { ok "$label: anchor present to remove" no yes; return; }
  ok "$label" "$( [ "$(missing "$TMP/m" "$@")" -gt 0 ] && echo caught || echo missed)" caught
}
for a in "${ENTRIES[@]}"; do mut "entry deleted: $a" "$TMP/sec" "$a" "${ENTRIES[@]}"; done
for a in "${RULE[@]}"; do mut "rule deleted: $(printf '%b' "$a" | head -1)" "$TMP/sec" "$a" "${RULE[@]}"; done
for r in software-engineer devops-engineer qa-reviewer; do
  for a in "${AGENT_RULE[@]}"; do mut "$r rule deleted: $(printf '%b' "$a" | head -1)" "$AG/$r.md" "$a" "${AGENT_RULE[@]}"; done
done
for a in "${QA_FINDING[@]}"; do mut "qa finding deleted: $(printf '%b' "$a" | head -1)" "$AG/qa-reviewer.md" "$a" "${QA_FINDING[@]}"; done
awk '/^## Reserved decisions$/{skip=1; next} skip && /^## /{skip=0} !skip' "$CONV" > "$TMP/nosec"
ok "mutant: section removed ⇒ no heading" "$(grep -c '^## Reserved decisions$' "$TMP/nosec")" 0

echo "reserved-decisions: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
