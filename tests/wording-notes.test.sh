#!/usr/bin/env bash
#
# wording-notes.test.sh — the banned-word and sentence-length report (wording-notes.sh) runs
# in pr-body-, pr-comment- and report-clearance.sh, and never moves their exit code: each
# fixture is decided by a copy whose reporter is real, a no-op, and one that fails.
# Reasoning: all-code-is-slop-lessons/task-019.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NOTES="$REPO/plugin/scripts/wording-notes.sh"
LIST="$REPO/plugin/data/banned-words.txt"
FIX="$REPO/tests/fixtures/wording-notes"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wording-notes.XXXXXX")" || {
  echo "wording-notes.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
notes() { printf '%s\n' "$1" | "$NOTES" - | grep -c '^note:'; }
words() { local i; for ((i = 1; i <= $1; i++)); do printf 'word%d ' "$i"; done; }

echo "== 1. one data file holds the list; no script carries a word of it =="
ok "the list is readable"                  "$([ -r "$LIST" ] && echo yes || echo no)" yes
ok "…one word per line"                    "$(grep -cvE '^[a-z]+$' "$LIST")" 0
ok "…and names utilize"                    "$(grep -cx utilize "$LIST")" 1
ok "git grep -i -w utilize in plugin/scripts" "$(cd "$REPO" && git grep -n -i -w utilize -- plugin/scripts | wc -l | tr -d ' ')" 0

echo "== 2. sentence length: 25 words, 20 in a numbered step; code, URL, table excluded =="
ok "25 words: no note"                     "$(notes "$(words 25).")" 0
ok "26 words: one note"                    "$(notes "$(words 26).")" 1
ok "numbered step of 20: no note"          "$(notes "1. $(words 20).")" 0
ok "numbered step of 21: one note"         "$(notes "1. $(words 21).")" 1
ok "a code span is not counted"            "$(notes "$(words 20) \`$(words 10)\`.")" 0
ok "a URL is not counted"                  "$(notes "$(words 25) https://example.com/a/b.")" 0
ok "a table row is not a sentence"         "$(notes "| $(words 30) |")" 0
ok "a fenced block is not a sentence"      "$(notes "$(printf '```\n%s\n```' "$(words 30).")")" 0
ok "two short sentences on one line"       "$(notes "$(words 15). $(words 15).")" 0
ok "a banned word in a code span is not reported" "$(notes 'Run `utilize` now.')" 0
ok "an inflected banned word is reported"  "$(notes 'It ensures nothing.')" 1

echo "== 3. each clearance script reports both, and its exit code does not move =="
cp -R "$REPO/plugin" "$TMP/real"
cp -R "$REPO/plugin" "$TMP/noop";  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/noop/scripts/wording-notes.sh"
cp -R "$REPO/plugin" "$TMP/broken"; printf '#!/usr/bin/env bash\necho boom\nexit 2\n' > "$TMP/broken/scripts/wording-notes.sh"
chmod +x "$TMP"/*/scripts/wording-notes.sh
for spec in pr-body:--body-file pr-comment:--comment-file report:--body-file; do
  name="${spec%%:*}"; flag="${spec#*:}"
  s="scripts/$name-clearance.sh"; f="$FIX/$name.md"
  "$TMP/real/$s" "$flag" "$f" >"$TMP/out" 2>"$TMP/err"; rc=$?
  ok "$name: clears with the notes"        "$rc" 0
  ok "$name: reports the banned word with its line" "$(grep -c '^note: line [0-9]*: banned word "utilize"' "$TMP/err")" 1
  ok "$name: reports the long sentence"    "$(grep -c '^note: line [0-9]*: sentence of' "$TMP/err")" 1
  ok "$name: no note on stdout"            "$(grep -c '^note:' "$TMP/out")" 0
  ok "$name: same exit with a no-op reporter" "$("$TMP/noop/$s" "$flag" "$f" >/dev/null 2>&1; echo $?)" "$rc"
  ok "$name: same exit with a failing reporter" "$("$TMP/broken/$s" "$flag" "$f" >/dev/null 2>&1; echo $?)" "$rc"
  g="$FIX/$name-refused.md"
  r1="$("$TMP/real/$s" "$flag" "$g" 2>"$TMP/err" >/dev/null; echo $?)"
  ok "$name: a refusal is not cleared by the notes" "$([ "$r1" -ne 0 ] && echo yes || echo no)" yes
  ok "$name: …and its code matches the no-op reporter's" "$r1" "$("$TMP/noop/$s" "$flag" "$g" >/dev/null 2>&1; echo $?)"
  ok "$name: …and still reports the banned word" "$(grep -c 'banned word "utilize"' "$TMP/err")" 1
done

echo "== 4. a missing list costs the word check, never the run =="
mv "$TMP/real/data/banned-words.txt" "$TMP/list"
printf '%s.\n' "$(words 26)" > "$TMP/long.md"
ok "exit 0 without the list"               "$("$TMP/real/scripts/wording-notes.sh" "$TMP/long.md" >/dev/null; echo $?)" 0
ok "…and the sentence still reported"      "$("$TMP/real/scripts/wording-notes.sh" "$TMP/long.md" | grep -c 'sentence of')" 1

echo "wording-notes.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
