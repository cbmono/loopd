#!/usr/bin/env bash
#
# conventions-pointers.test.sh — the CONVENTIONS.md split stays reachable (leaner-prompts/task-002).
#   (a) the core is at most 5,000 words and every rule in it is a ## or ### heading;
#   (b) every `CONVENTIONS.md` → "<heading>" or `conventions/<topic>.md` → "<heading>" pointer
#       in plugin/, CLAUDE.md, .claude/ and docs/ quotes a heading of the file it names, and
#       none paraphrases one;
#   (c) every detail heading is reached from the core by a pointer carrying a trigger, so moved
#       text is read only when one fires.
# Mutants: a dangling pointer, a paraphrase, an orphan detail heading and a trigger-less pointer.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$REPO/plugin/seed/CONVENTIONS.md"
DETAIL="$REPO/plugin/seed/conventions"
EXTRACT="$REPO/tests/tools/conventions-pointers.pl"
MAX_WORDS=5000
TMP="$(mktemp -d "${TMPDIR:-/tmp}/conventions-pointers.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

headings() { sed -n 's/^#\{1,3\} \(.*\)$/\1/p' "$1" | tr -s ' '; }
# bad <root> — every pointer under <root> whose heading its target does not carry.
bad() {
  local root="$1" f target h file
  ( cd "$root" && { git ls-files plugin CLAUDE.md .claude docs 2>/dev/null; ls plugin/seed/conventions/*.md 2>/dev/null; } \
      | sort -u | xargs perl "$EXTRACT" ) |
  while IFS=$'\t' read -r f target h; do
    case "$target" in
      CONVENTIONS.md) file="$root/plugin/seed/CONVENTIONS.md" ;;
      *) file="$root/plugin/seed/$target" ;;
    esac
    case "$h" in '!'*) echo "$f -> $target paraphrases: ${h#!}"; continue ;; esac
    [ -f "$file" ] || { echo "$f -> $target: no such file"; continue; }
    headings "$file" | grep -qxF -- "$h" || echo "$f -> $target \"$h\": no such heading"
  done
}
# core_pointers <core> — `conventions/<topic>.md<TAB>heading<TAB>text after the closing quote`.
core_pointers() {
  tr '\n' ' ' < "$1" | tr -s ' ' \
    | perl -ne 'while (/`(conventions\/[a-z-]+\.md)` → "([^"]+)"(.{0,12})/g) { print "$1\t$2\t$3\n" }'
}
# orphans <seed> — detail headings no core pointer names.
orphans() {
  local seed="$1" d h
  for d in "$seed"/conventions/*.md; do
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      core_pointers "$seed/CONVENTIONS.md" | cut -f1,2 | grep -qxF -- "conventions/${d##*/}	$h" \
        || echo "conventions/${d##*/} \"$h\""
    done <<<"$(sed -n 's/^### //p' "$d")"
  done
}
# untriggered <core> — core pointers not followed by " — when|before|if …".
untriggered() { core_pointers "$1" | awk -F'\t' '$3 !~ /^ — (when|before|if) /{print $1" \""$2"\""}'; }

echo "== (a) the core =="
words="$(wc -w < "$CORE" | tr -d ' ')"
ok "core is at most $MAX_WORDS words (is $words)" "$([ "$words" -le "$MAX_WORDS" ] && echo yes || echo no)" yes
ok "detail files exist" "$(ls "$DETAIL"/*.md 2>/dev/null | wc -l | tr -d ' ' | awk '{print ($1>=5)?"yes":"no"}')" yes
ok "no detail file has a rule outside a ### heading (first ### before any bullet)" \
   "$(for d in "$DETAIL"/*.md; do awk '/^### /{h=1} /^- /&&!h{print FILENAME; exit}' "$d"; done | wc -l | tr -d ' ')" 0

echo "== (b) every pointer resolves to a heading =="
BAD="$(bad "$REPO")"
ok "pointers found at all" "$(cd "$REPO" && git ls-files plugin | xargs perl "$EXTRACT" | wc -l | awk '{print ($1>=50)?"yes":"no"}')" yes
ok "no pointer dangles or paraphrases" "$(printf '%s' "$BAD" | grep -c . | tr -d ' ')" 0
[ -z "$BAD" ] || printf '%s\n' "$BAD" | sed 's/^/        /'

echo "== (c) the core reaches every detail heading, with a trigger =="
O="$(orphans "$REPO/plugin/seed")"
ok "every detail heading has a core pointer" "$(printf '%s' "$O" | grep -c . | tr -d ' ')" 0
[ -z "$O" ] || printf '%s\n' "$O" | sed 's/^/        /'
U="$(untriggered "$CORE")"
ok "every core pointer names a trigger" "$(printf '%s' "$U" | grep -c . | tr -d ' ')" 0
[ -z "$U" ] || printf '%s\n' "$U" | sed 's/^/        /'

echo "== (d) mutants =="
M="$TMP/m"; mkdir -p "$M/plugin/seed/conventions" "$M/plugin/agents"
cp "$CORE" "$M/plugin/seed/CONVENTIONS.md"; cp "$DETAIL"/*.md "$M/plugin/seed/conventions/"
( cd "$M" && git init -q . && printf 'Read `CONVENTIONS.md` → "Write less".\n' > plugin/agents/a.md && git add -A )
ok "CONTROL: a resolving pointer is clean" "$(bad "$M" | grep -c . | tr -d ' ')" 0
printf 'See `CONVENTIONS.md` → "No such rule".\nSee `conventions/review.md` → "Write less".\nSee `CONVENTIONS.md` → the same rule.\n' >> "$M/plugin/agents/a.md"
( cd "$M" && git add -A )
MB="$(bad "$M")"
ok "mutant: a heading the core lacks is caught" "$(grep -c '"No such rule": no such heading' <<<"$MB" | tr -d ' ')" 1
ok "mutant: a core heading quoted against a detail file is caught" "$(grep -c 'review.md "Write less": no such heading' <<<"$MB" | tr -d ' ')" 1
ok "mutant: a paraphrase is caught" "$(grep -c 'paraphrases: the same rule' <<<"$MB" | tr -d ' ')" 1
printf '\n### A planted rule\n\n- nothing points here\n' >> "$M/plugin/seed/conventions/review.md"
ok "mutant: an orphan detail heading is caught" "$(orphans "$M/plugin/seed" | grep -c 'A planted rule' | tr -d ' ')" 1
perl -0pi -e 's/never a gate" — when/never a gate". Read it when/' "$M/plugin/seed/CONVENTIONS.md"
ok "mutant: a trigger-less pointer is caught" "$(untriggered "$M/plugin/seed/CONVENTIONS.md" | grep -c 'PR size' | tr -d ' ')" 1

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
