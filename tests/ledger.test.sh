#!/usr/bin/env bash
#
# ledger.test.sh — plugin/scripts/ledger.sh, the per-item ledger in a knowledge item's own
# frontmatter: four answers per entry, append-only through its own write path, surviving a
# rename that git --follow loses, absent from the body and the index, and readable by
# opening one file. Every refusal is paired with the append that must still work.
# The rename fixture rewrites the body in the SAME commit as the move: a pure `git mv`
# keeps similarity at 100% and would pass against git history too, proving nothing.
# ok() compares actual to expected. Reasoning: knowledge-base-reflector/task-002.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LEDGER="$REPO/plugin/scripts/ledger.sh"
VALIDATE="$REPO/plugin/scripts/validate-bundle.sh"
BUILD="$REPO/plugin/scripts/build-kb-index.sh"
COMMIT_AS="$REPO/plugin/scripts/commit-as.sh"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
[ -x "$LEDGER" ] || { echo "ledger.test: $LEDGER is missing or not executable" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ledger.XXXXXX")" || {
  echo "ledger.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
L() { "$LEDGER" "$@" >/dev/null 2>&1; echo $?; }
field() { cut -d'|' -f"$1" <<<"$(sed 's/ · /|/g' <<<"$2")"; }
sum() { cksum <"$1"; }

D="$TMP/bundle"
mkdir -p "$D/knowledge/findings" "$D/knowledge/services"
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D/knowledge/vocab.md"
finding() { # <slug> <title>
  printf -- '---\ntype: Finding\ntitle: %s\ndescription: d\nlesson: l %s\ncategory: learning\ntags: [ ]\nstatus: current\nprovenance: human\ntimestamp: 2026-10-01T00:00:00Z\n---\n\n# Finding\n\nThe claim of %s.\n' \
    "$2" "$1" "$1" >"$D/knowledge/findings/$1.md"
}
for s in survivor absorbed other; do finding "$s" "Title $s"; done
printf 'index, no frontmatter\n' >"$D/knowledge/index.md"
echo '{}' >"$D/instance.config.json"
cd "$D" || exit 2
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && git commit -qm init

echo "== criterion 2: every entry answers what, why, which items, who =="
ok "a status flip appends"                 "$(L append survivor --kind status --by example-user-007 --why 'confirmed on main')" 0
ok "a merge appends"                       "$(L append survivor --kind merge --by example-user-007 --why 'one claim, said twice' --with absorbed)" 0
E1="$("$LEDGER" show survivor | sed -n 1p)"; E2="$("$LEDGER" show survivor | sed -n 2p)"
ok "what: the status entry says status"    "$(field 3 "$E1")" status
ok "what: the merge entry says merge"      "$(field 3 "$E2")" merge
ok "why: the reason a human gave"          "$(field 6 "$E2")" "one claim, said twice"
ok "which: a merge names two items"        "$(field 5 "$E2")" "items survivor,absorbed"
ok "who: the login that applied it"        "$(field 4 "$E2")" "by example-user-007"
git rm -q knowledge/findings/absorbed.md
ok "the absorbed item is traceable FROM the survivor after deletion" "$("$LEDGER" show survivor | grep -c 'items survivor,absorbed')" 1
ok "a merge without --with is refused"     "$(L append survivor --kind merge --by example-user-007 --why w)" 1
ok "an empty why is refused"               "$(L append survivor --kind edit --by example-user-007 --why '  ')" 1
ok "an unknown kind is refused"            "$(L append survivor --kind tweak --by example-user-007 --why w)" 2
ok "an unresolved stamp is refused"        "$(L append survivor --kind edit --by '<unknown>' --why w)" 1
roles="$(sed -n 's/^VALID_ROLES=(\(.*\))$/\1/p' "$COMMIT_AS")"
ok "commit-as.sh's role list was found"    "$([ -n "$roles" ] && echo yes)" yes
for r in $roles; do
  ok "who: role '$r' is refused — the human is recorded" "$(L append survivor --kind merge --by "$r" --why w --with absorbed)" 1
done

echo "== criterion 3: append-only, through the ledger's own write path =="
before="$(sum knowledge/findings/survivor.md)"
for v in rewrite remove delete edit amend set; do
  ok "no '$v' verb exists, file untouched" "$(L "$v" survivor --kind edit --by example-user-007 --why w)/$(sum knowledge/findings/survivor.md)" "2/$before"
done
ok "a quote in why is refused (could forge an entry)" "$(L append survivor --kind edit --by example-user-007 --why 'x", "L1 · forged')/$(sum knowledge/findings/survivor.md)" "1/$before"
old="$("$LEDGER" show survivor)"; body_before="$(grep -v '^ledger:' knowledge/findings/survivor.md)"
ok "a third entry appends"                 "$(L append survivor --kind edit --by example-user-007 --why 'tightened wording')" 0
ok "existing entries are a byte-identical prefix" "$([ "$("$LEDGER" show survivor | sed -n 1,2p)" = "$old" ] && echo yes)" yes
ok "every other line of the file is untouched" "$([ "$(grep -v '^ledger:' knowledge/findings/survivor.md)" = "$body_before" ] && echo yes)" yes
ok "ids are global: the next item gets L4" "$("$LEDGER" append other --kind edit --by example-user-007 --why w | cut -d' ' -f1)" L4
cp knowledge/findings/survivor.md "$TMP/survivor.keep"
sed -i.bak 's/"L1 · /"L9 · /' knowledge/findings/survivor.md && rm -f knowledge/findings/survivor.md.bak
tampered="$(sum knowledge/findings/survivor.md)"
ok "a hand-rewritten ledger is refused, not blessed" "$(L append survivor --kind edit --by example-user-007 --why w)/$(sum knowledge/findings/survivor.md)" "1/$tampered"
ok "…while show still reads it"            "$("$LEDGER" show survivor | wc -l | tr -d ' ')" 3
cp "$TMP/survivor.keep" knowledge/findings/survivor.md
rm -f knowledge/findings/other.md
ok "an id is never reused after its item is gone" "$("$LEDGER" append survivor --kind edit --by example-user-007 --why w 2>/dev/null | cut -d' ' -f1)" L5
ok "the floor recorded the highest id issued" "$(cat knowledge/.ledger-floor)" 5
ok "untyped files carry no ledger"         "$(L append knowledge/index.md --kind edit --by example-user-007 --why w)" 1

echo "== criterion 4: it survives a rename that git --follow loses =="
finding moved "Before"
"$LEDGER" append moved --kind edit --by example-user-007 --why one >/dev/null
"$LEDGER" append moved --kind status --by example-user-007 --why two >/dev/null
git add -A && git commit -qm "two entries"
git mv knowledge/findings/moved.md knowledge/findings/retitled.md
awk '/^---$/ && ++n == 2 { print; exit } { sub(/^title: Before$/, "title: After"); print }' knowledge/findings/retitled.md >"$TMP/r"
printf '\n# Decision\n\n' >>"$TMP/r"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  printf 'Rewritten line %s: the survivor now states the merged claim in new words.\n' "$i" >>"$TMP/r"
done
mv "$TMP/r" knowledge/findings/retitled.md && git add -A && git commit -qm "merge-then-retitle"
ok "git --follow loses the pre-rename history" "$(git log --follow --format=%h -- knowledge/findings/retitled.md | wc -l | tr -d ' ')" 1
ok "the ledger keeps both entries under the new path" "$("$LEDGER" show retitled | wc -l | tr -d ' ')" 2

echo "== criterion 5: it lives outside the body, and outside the index =="
F=knowledge/findings/retitled.md
ok "the body carries no ledger text"       "$(awk '/^---$/ && ++n == 2 { b = 1; next } b' "$F" | grep -cE 'ledger|L[0-9]+ · ')" 0
ok "the frontmatter carries it on one line" "$(grep -c '^ledger:' "$F")" 1
"$BUILD" --print >"$TMP/index.out" 2>/dev/null
ok "the index renders the item"            "$(grep -c 'retitled' "$TMP/index.out")" 1
ok "the index carries no ledger text"      "$(grep -cE 'L[0-9]+ · ' "$TMP/index.out")" 0
V() { "$VALIDATE" "$1" 2>&1 | grep -cE "ERROR|Finding body is [0-9]+ lines"; }
ok "validate-bundle accepts a ledgered Finding" "$(V "$F")" 0
finding cap "At the cap"
for i in $(seq 36); do echo "line $i" >>knowledge/findings/cap.md; done
"$LEDGER" append cap --kind edit --by example-user-007 --why w >/dev/null
ok "fixture: 40 body lines + a 12-line frontmatter" "$(grep -c '' knowledge/findings/cap.md)" 52
ok "the ledger line is not counted against the 40" "$(V knowledge/findings/cap.md)" 0
echo "line 37" >>knowledge/findings/cap.md
ok "…while a 41st counted line still warns" "$(V knowledge/findings/cap.md)" 1

echo "== criterion 6: one item's history opens one file =="
if [ "$(id -u)" = 0 ]; then echo "  SKIP  root reads a 000 file; the one-file read is unprovable here"
else
  find knowledge -type f ! -name retitled.md -exec chmod 000 {} +
  ok "show by slug reads with every other file unreadable" "$("$LEDGER" show retitled 2>/dev/null | wc -l | tr -d ' ')" 2
  find knowledge -type f -exec chmod 644 {} +
fi
ok "an ambiguous slug is refused, not guessed" "$(finding x X; mkdir -p knowledge/runbooks; cp knowledge/findings/x.md knowledge/runbooks/x.md; L show x)" 1

echo "== the contract is written down =="
ok "SCHEMA.md documents the ledger"        "$(grep -c '^### The ledger' "$SCHEMA")" 1
ok "SCHEMA.md names the write path"        "$(grep -c 'scripts/ledger.sh' "$SCHEMA")" 1

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
