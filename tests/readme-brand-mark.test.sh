#!/usr/bin/env bash
#
# readme-brand-mark.test.sh — the README's loopd mark is COPIED, every command slug is
# spelled under the plugin's own manifest name, and no shipped file carries the old brand
# as PROSE.
#
# WHY THE MARK IS PINNED AS BYTES. The three rows are box-drawing glyphs (▄ ▐ ▌ ▝ ◀ ━),
# not ASCII, and nothing else in this repo holds a copy to compare against. A row retyped
# by eye renders plausibly and is still wrong — one glyph or one space of drift and the
# loop no longer closes in a terminal. So the owner's `assets/ascii-logo.txt` rows are the
# fixture below, and the README is diffed against them (loopd/task-001).
#
# AND THE HALF THAT IS EASY TO SHIP EARLY OR LATE. A slug under any name but the manifest's
# documents an instruction nobody can run, so the name is read from the manifests
# (tests/tools/plugin-name.sh) and the rename (loopd/task-007) moves both together. Each
# command is checked against an EXPLICIT baseline, one by one: a count of surviving slugs
# passes while one command is silently dropped (ai-bridge#231, r4119584839). The
# foreign-slug assertion runs over the whole shipped surface rather than this one file — the
# knowledge/findings/a-zero-mention-assertion-scoped-to-the-renamed-file-is-not-a-sweep.md
# is the measured cost of the narrower version (104 surviving mentions behind a green check).
#
# AND THE PROSE HALF (loopd/task-012), WHICH IS A PINNED LIST AND NOT A PATTERN. `ai-bridge`
# survives legitimately in five classes — provenance, the `.ai-bridge/` bundle directory,
# `_ai-bridge-*` instance names, filenames, and frozen identifiers — and no regex separates
# those from brand prose without encoding a different class precisely. So the owner's ruling
# of 2026-10-02 was to hand-classify all 202 matching files once and PIN the survivors:
# tests/fixtures/brand/survivors.txt is the list, § 5 compares it to the repository in both
# directions, and a file joining or leaving it does so in a PR that says why.
#
# NON-VACUOUS BY CONSTRUCTION. Each predicate also runs on a mutant carrying exactly the
# drift it exists to catch, and the mutant must go red.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
README="$REPO/README.md"
[ -f "$README" ] || { echo "readme-brand-mark.test: missing $README" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/readme-brand-mark.XXXXXX")" \
  || { echo "readme-brand-mark.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
count() { grep -cF -- "$2" "$1" | tr -d ' '; }

# The mark, byte for byte, from projects/loopd/sources/loopd-design/assets/ascii-logo.txt.
cat > "$TMP/mark.txt" <<'MARK'
   ▄▄▄▄
◀━▐    ▌   loopd — the loop, running
  ▝▄▄▄▄▘
MARK

# The fenced rows of a README: lines 2-4, which is where the mark is required to be.
rows() { sed -n '2,4p' "$1"; }
mark_matches() { diff -q "$TMP/mark.txt" <(rows "$1") >/dev/null 2>&1 && echo yes || echo no; }

# Every tracked path a reader is shipped: the docs plus CLAUDE.md's closed `core` list —
# the companion plugins and both deprecation stubs carry slugs too.
# Minus docs/releases/: a release note records what that version shipped under.
shipped_surface() {
  ( cd "$REPO" && git ls-files -- README.md docs .claude plugin 'plugin-*' config \
      install.sh upgrade.sh ':!docs/releases' 2>/dev/null )
}
in_surface() { grep -qxF -- "$1" <<<"$(shipped_surface)" && echo yes || echo no; }

echo
echo "== 1. the README opens with the mark, copied =="
ok "line 1 opens a fenced block"      "$(head -1 "$README")" '```text'
ok "line 5 closes it"                 "$(sed -n '5p' "$README")" '```'
ok "rows 2-4 are the mark, byte for byte" "$(mark_matches "$README")" yes

echo
echo "== 2. the name, the line and the two-colour rule =="
ok "the tagline appears once"         "$(count "$README" 'loopd — the loop, running')" 1
ok "the motto appears once"           "$(count "$README" 'You steer. They build. Two gates stay yours.')" 1
ok "blue is stated once"              "$(count "$README" '#5ea2ff')" 1
ok "pink is stated once"              "$(count "$README" '#ff7ac2')" 1
ok "blue is the machine's"            "$(count "$README" "Blue \`#5ea2ff\` is the machine's")" 1
ok "pink is the human's"              "$(count "$README" 'Pink `#ff7ac2` is yours')" 1

echo
echo "== 3. every command is documented, and only under /${PN}: =="
# The baseline is EXPLICIT, never derived from plugin/skills/: a derived list would let a
# deleted skill take its README line with it and stay green. The first check keeps it honest.
COMMANDS="answer audit board brief-me capture close-project dispatch fanout handoff init kb-apply new-project pr-review-request welcome work"
ok "the baseline is exactly plugin/skills/" "$(ls "$REPO/plugin/skills" | tr '\n' ' ' | sed 's/ $//')" "$COMMANDS"
undocumented() { # <file> -> each baseline command it never names as /$PN:<cmd>, or none
  local c miss=""
  for c in $COMMANDS; do grep -qE "/${PN}:${c}([^a-z-]|\$)" "$1" || miss="${miss:+$miss }$c"; done
  echo "${miss:-none}"
}
CMD_ALT="$(printf '%s' "$COMMANDS" | tr ' ' '|')"
foreign() { # <file>... -> how many /<name>:<command> slugs name something other than $PN
  grep -ohE "/[a-z][a-z0-9-]*:(${CMD_ALT})([^a-z-]|\$)" "$@" 2>/dev/null | grep -vc "^/${PN}:" | tr -d ' '
}
ok "the README names every command as /${PN}:<cmd>" "$(undocumented "$README")" none
ok "no slug under another name in the README" "$(foreign "$README")" 0
ok "…nor anywhere on the shipped surface" \
   "$(shipped_surface | tr '\n' '\0' | (cd "$REPO" && xargs -0 grep -ohE "/[a-z][a-z0-9-]*:(${CMD_ALT})([^a-z-]|\$)" 2>/dev/null) | grep -vc "^/${PN}:" | tr -d ' ')" 0
ok "the sweep covers the install.sh stub"   "$(in_surface install.sh)" yes
ok "the sweep covers the upgrade.sh stub"   "$(in_surface upgrade.sh)" yes
ok "the sweep covers the plugin-yolo companion" "$(in_surface plugin-yolo/companion/AUTONOMY.md)" yes
ok "the marketplace line names this repo" \
   "$([ "$(count "$README" "/plugin marketplace add $GH")" -gt 0 ] && echo yes || echo no)" yes
ok "the install line names this plugin and marketplace" \
   "$([ "$(count "$README" "/plugin install $PN@$PMK")" -gt 0 ] && echo yes || echo no)" yes

echo
echo "== 4. four mutants go RED — the checks discriminate =="
sed '3s/▐/|/' "$README" > "$TMP/redrawn.md"
ok "mutant A: one retyped glyph fails the byte check" "$(mark_matches "$TMP/redrawn.md")" no

sed "s|/${PN}:dispatch|/not-${PN}:dispatch|" "$README" > "$TMP/renamed.md"
ok "mutant B: a slug under another name is reported" \
   "$([ "$(foreign "$TMP/renamed.md")" -gt 0 ] && echo yes || echo no)" yes

sed "s|${PN}@${PMK}|not-${PN}@not-${PMK}|" "$README" > "$TMP/unresolvable.md"
ok "mutant C: a renamed install line is reported" \
   "$(count "$TMP/unresolvable.md" "/plugin install $PN@$PMK")" 0

sed "s|/${PN}:new-project||g" "$README" > "$TMP/dropped.md"
ok "mutant D: one dropped command is named, while the rest survive" \
   "$(undocumented "$TMP/dropped.md")" new-project

echo
echo "== 5. the brand-prose class is empty, against the pinned survivor list =="
SURV="$REPO/tests/fixtures/brand/survivors.txt"
[ -f "$SURV" ] || { echo "readme-brand-mark.test: missing $SURV" >&2; exit 2; }
listed()    { grep -v '^#' "$SURV" | cut -f2 | sort; }
# The measure is criterion 1's own command, run from a root so a mutant tree can take it.
sweep()     { ( cd "$1" && grep -rIl ai-bridge plugin docs README.md tests scripts 2>/dev/null ) | sort; }
pinned_in() { local r="$1" p; listed | while IFS= read -r p; do [ -e "$r/$p" ] && echo "$p"; done; }
new_brand() { comm -13 <(pinned_in "$1") <(sweep "$1") | tr '\n' ' ' | sed 's/ $//'; }
left_list() { comm -23 <(pinned_in "$1") <(sweep "$1") | tr '\n' ' ' | sed 's/ $//'; }

ok "the list is sorted and has no duplicate" \
   "$(listed | sort -u | cmp -s - <(listed) && echo yes || echo no)" yes
ok "every pinned path is a tracked file" \
   "$(listed | while IFS= read -r p; do (cd "$REPO" && git ls-files --error-unmatch "$p") >/dev/null 2>&1 || echo "$p"; done | tr '\n' ' ' | sed 's/ $//')" ""
ok "no file outside the list carries the old brand" "$(new_brand "$REPO")" ""
ok "…and no listed file has quietly stopped carrying it" "$(left_list "$REPO")" ""

# Mutant E: a cleaned file takes the brand back as prose. The check must NAME it.
MUT="$TMP/mut"; mkdir -p "$MUT/plugin/scripts"
sed 's/`loopd` plugin/`ai-bridge` plugin/' "$REPO/plugin/scripts/task-owner.sh" > "$MUT/plugin/scripts/task-owner.sh"
ok "mutant E: reintroduced brand prose is named" "$(new_brand "$MUT")" plugin/scripts/task-owner.sh

# Mutant F: a listed file stops matching without leaving the list. The check must NAME it.
MUT2="$TMP/mut2"; mkdir -p "$MUT2/plugin/scripts"
sed 's/ai-bridge//g' "$REPO/plugin/scripts/bundle-paths.sh" > "$MUT2/plugin/scripts/bundle-paths.sh"
ok "mutant F: a listed file that no longer matches is named" "$(left_list "$MUT2")" plugin/scripts/bundle-paths.sh

# Mutant G: scripts/ is swept — the retired install.sh line comes back and must be NAMED.
MUT3="$TMP/mut3"; mkdir -p "$MUT3/scripts"
{ cat "$REPO/scripts/add-second-human.sh"; echo 'echo "  ~/workspace/ai-bridge/install.sh \"\$PWD\""'; } \
  > "$MUT3/scripts/add-second-human.sh"
ok "mutant G: the retired install.sh line in scripts/ is named" "$(new_brand "$MUT3")" scripts/add-second-human.sh

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
