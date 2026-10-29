#!/usr/bin/env bash
# overload-decisions.test.sh — step 2's "how it fails" sentences (loopd-improvements/task-006):
# the overload D<n> class beside the decision classes, the design.md label rule and the
# design pass's missing-row check. Refine is a model step, so its text is pinned, and a
# mutant dropping each sentence must fail the pin.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S2="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

SENT=(
  'Every queue, buffer, cache, connection pool, retry budget or in-memory map the project adds or changes the load on gets one `D<n>` stating its bound and what happens at it — dropped, refused, delayed, or unbounded on purpose — recorded per draft at refine whatever its reversibility. `unbounded` is a legal answer; an unstated one is not.'
  '**Label each queue, buffer, cache or connection pool that is a node with its overload `D<n>` id, not the bound'"'"'s text**, so an overturn needs no redraw of the label — the diagram itself still redraws under the redraw rule below; retry budgets and in-memory maps need no node.'
  '**Before you stop, check each such node against the project'"'"'s overload `D<n>` rows and add any missing row.**'
)
# where each sentence must sit: after <from>, before <to>
FROM=( 'security-model or external-dependency choice' '**Design diagram' '**Design diagram' )
TO=(   '**Design diagram' '**Approach critique' '**Approach critique' )

flat="$(tr '\n' ' ' < "$S2" | tr -s ' ')"
# pinned <flat text> <i>: yes when sentence i is present inside its section
pinned() {
  local t="$1" s="${SENT[$2]}" head rest
  head="${1#*"${FROM[$2]}"}"; [ "$head" = "$t" ] && { echo no; return; }
  rest="${head%%"${TO[$2]}"*}"
  case "$rest" in *"$s"*) echo yes ;; *) echo no ;; esac
}

echo "== step 2 carries the three sentences, each in its section =="
for i in 0 1 2; do ok "sentence $((i+1)): ${SENT[$i]:0:48}…" "$(pinned "$flat" "$i")" yes; done
ok "the six-class string decisions.test.sh pins is untouched" \
   "$(grep -cF 'technology, topology, data-model, consistency or caching, security-model or external-dependency choice' <<<"$flat")" 1

echo; echo "== a mutant removing any one sentence fails its pin =="
for i in 0 1 2; do
  mutant="${flat/"${SENT[$i]}"/}"
  ok "mutant $((i+1)) differs from the real text" "$([ "$mutant" != "$flat" ] && echo yes || echo no)" yes
  ok "mutant $((i+1)) fails sentence $((i+1))" "$(pinned "$mutant" "$i")" no
done

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
