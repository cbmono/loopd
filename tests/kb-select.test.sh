#!/usr/bin/env bash
#
# kb-select.test.sh — plugin/scripts/kb-select.sh picks the 1-5 Findings a brief carries:
# status: current only, the vocab-tag gate (2 shared words) against the seed's empty Services
# table (3), a block-scalar lesson:, 0 / 1-5 / >5 qualifiers, byte-identical reruns, and a
# --record whose set --recorded returns after the KB changed. Reasoning:
# kb-retrieval-and-papercut-fixes/task-003.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/kb-select.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kb-select.XXXXXX")" || { echo "kb-select.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
run()   { bash "$SCRIPT" "$@" 2>&1; }
rc()    { bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }
slugs() { run "$@" | sed -n 's/^\[\[\([^]]*\)\]\].*/\1/p' | paste -sd, -; }

F="$TMP/knowledge/findings"
fnd() { # <slug> <status> <lesson> [tags]
  printf -- '---\ntype: Finding\ntitle: "A note"\nlesson: %s\nstatus: %s\ntags: [%s]\n---\n\n# Finding\nx\n' \
    "$3" "$2" "${4:-}" > "$F/$1.md"
}
mkdir -p "$F" "$TMP/knowledge/services" "$TMP/projects/p/tasks"
echo '{}' > "$TMP/instance.config.json"
cp "$REPO/plugin/seed/knowledge/vocab.md" "$TMP/knowledge/vocab.md"
printf -- '---\ntype: Service\ntitle: widget\nrepo: acme/widget\npath: (whole repo)\nstatus: active\n---\n' \
  > "$TMP/knowledge/services/widget.md"
T="$TMP/projects/p/tasks/task-001.md"
printf -- '---\ntype: Task\ntitle: "Rotate widget cache keys before eviction"\ntarget_repo: acme/widget\nacceptance_criteria:\n  - "stale entries expire after the ttl"\n---\n\n# Context\n\nx\n\n# Notes\n- created\n' > "$T"

echo "== zero qualifiers: one explicit line, never an empty section =="
fnd unrelated current "Deploys need a green pipeline"
OUT="$(run "$T")"
ok "one line"                    "$(printf '%s\n' "$OUT" | grep -c '')" 1
ok "…and it says none matched"   "$(grep -c '^none matched' <<<"$OUT")" 1
ok "exit 0"                      "$(rc "$T")" 0

echo "== status: current only =="
fnd keys-rotate current "Rotate cache keys only after eviction"
fnd keys-old superseded "Rotate cache keys only after eviction"
fnd keys-wrong corrected "Rotate cache keys only after eviction"
fnd keys-gone archived "Rotate cache keys only after eviction"
ok "the current one prints; superseded, corrected, archived never" "$(slugs "$T")" keys-rotate
ok "the row is [[slug]] — lesson" "$(run "$T")" "[[keys-rotate]] — Rotate cache keys only after eviction"

echo "== the Services-vocab gate: 2 words when tagged and in vocab, else 3 =="
fnd two-words current "widget eviction matters" widget
ok "seed's empty Services table ⇒ a 2-word overlap is out" "$(slugs "$T")" keys-rotate
awk '/^\| Tag \| Kind \| Aliases \|$/ && !d { print; getline; print; print "| `widget` | service | |"; d = 1; next } 1' \
  "$REPO/plugin/seed/knowledge/vocab.md" > "$TMP/knowledge/vocab.md"
ok "widget in the Services table ⇒ the tagged 2-word one is in" "$(slugs "$T")" keys-rotate,two-words
fnd two-untagged current "widget eviction matters"
ok "…but an untagged 2-word overlap still is not" "$(slugs "$T")" keys-rotate,two-words
cp "$REPO/plugin/seed/knowledge/vocab.md" "$TMP/knowledge/vocab.md"
rm "$F/two-words.md" "$F/two-untagged.md"

echo "== a block-scalar lesson: counts and prints on one row =="
printf -- '---\ntype: Finding\ntitle: "Block"\nlesson: >\n  Stale entries\n     expire on   the\n  ttl, not before.\nstatus: current\n---\n\nx\n' > "$F/block.md"
ok "its continuation lines qualify it" "$(slugs "$T")" block,keys-rotate
ok "…and print whitespace-collapsed"   "$(grep '^\[\[block\]\]' <<<"$(run "$T")")" "[[block]] — Stale entries expire on the ttl, not before."

echo "== more than five: the top five, ties by slug, byte-identical reruns =="
for i in 1 2 3 4 5 6 7; do fnd "q$i" current "rotate cache keys"; done
A="$(run "$T")"; B="$(run "$T")"
ok "five rows"                   "$(printf '%s\n' "$A" | grep -c '^\[\[')" 5
ok "two runs are byte-identical" "$([ "$A" = "$B" ] && echo same || echo differ)" same
ok "best first, ties by slug"    "$(slugs "$T")" block,keys-rotate,q1,q2,q3

echo "== --record, then --recorded after the KB changed =="
ok "--recorded with nothing recorded exits 1" "$(rc --recorded "$T")" 1
LINE="$(run --record "$T")"
ok "--record prints the line it appended" \
  "$(grep -cE '^\* KNOWLEDGE [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z · block,keys-rotate,q1,q2,q3$' <<<"$LINE")" 1
ok "…into # Notes, after its last line" "$(awk '/^# Notes/{f=1;next} f&&NF' "$T" | tail -n 1)" "$LINE"
rm "$F/block.md" "$F/q1.md"; fnd zz-new current "Rotate widget cache keys before eviction; stale entries expire after the ttl"
ok "a fresh selection now differs"     "$([ "$(slugs "$T")" != block,keys-rotate,q1,q2,q3 ] && echo yes || echo no)" yes
ok "…but --recorded returns the recorded set" "$(run --recorded "$T")" block,keys-rotate,q1,q2,q3
rm "$F"/*.md; run --record "$T" >/dev/null
ok "a second --record of nothing records none, and wins" "$(run --recorded "$T")" none
ok "the task kept its frontmatter"     "$(head -n 1 "$T")" ---

echo "== it refuses rather than guessing =="
ok "a missing task exits 2"  "$(rc "$TMP/nope.md")" 2
ok "no arguments exits 2"    "$(rc)" 2

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
