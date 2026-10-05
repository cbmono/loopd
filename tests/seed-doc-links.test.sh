#!/usr/bin/env bash
#
# seed-doc-links.test.sh — every intra-bundle markdown link in the seeded docs resolves
# in a bundle `init-bundle.sh` has just stamped.
#
# The seed is FLAT and the bundle is NOT: `ab_seed_dest` maps `SCHEMA.md` onto
# `.loopd/SCHEMA.md` and friends, but it maps PATHS, never link TEXT — so a link that
# is correct in `plugin/seed/` is dead the moment a stamp finishes. No migration is
# involved: `init-bundle.sh` already writes the 3.0 layout.
#
# Exit codes: 0 clean, 1 an assertion failed, 2 the tree is not readable.
# Reasoning: seed-gaps-and-worktree-cleanup/task-002.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$TPLSRC/plugin/seed/CLAUDE.md" ] || { echo "seed-doc-links.test: no seed at $TPLSRC/plugin/seed" >&2; exit 2; }
[ -f "$TPLSRC/plugin/seed/index.md" ] || { echo "seed-doc-links.test: no seed index.md" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/seed-doc-links.XXXXXX")" || {
  echo "seed-doc-links.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# ---------------------------------------------------------------------------------
# WHAT COUNTS AS INTRA-BUNDLE. The rule lives here, beside the code that applies it,
# because a rule stated only in a PR body is one nobody can re-derive from the failure.
#
#   IN   a link target naming a path in the bundle — the target class is exactly the
#        one that resolves in the flat seed and not after the move.
#   OUT  an external URL (`scheme://`, `mailto:`), because nothing on disk answers it;
#        an anchor-only target (`#section`), which addresses the linking file itself;
#        a PLACEHOLDER — a target carrying `<`, `>` or `…`, or spelled bare `url`. The
#        seed documents link SHAPES in five places (`index.md`'s commented Objectives and
#        Projects rows, `CLAUDE.md`'s `<url>`, `SCHEMA.md`'s `url`, `CONVENTIONS.md`'s
#        `…`); each names no file, and flagging them would be five false positives on
#        day one — the noisy-validator failure of docs/conventions.md §8.
#   HOW  a leading `/` resolves against the BUNDLE ROOT; anything else against the
#        LINKING FILE's own directory — which for the moved `index.md` is `.loopd/`.
#        Those two rules are the whole of it, and criterion 3's negative control
#        (`/knowledge/index.md`) is only decidable once both are stated.
# ---------------------------------------------------------------------------------
extract_links='
function emit(t) { printf "%s\t%d\t%s\n", REL, FNR, t }
BEGIN { incomment = 0 }
{
  line = $0; out = ""
  while (length(line)) {                       # strip HTML comments, across lines
    if (incomment) {
      p = index(line, "-->"); if (p == 0) { line = ""; break }
      line = substr(line, p + 3); incomment = 0
    } else {
      p = index(line, "<!--"); if (p == 0) { out = out line; line = ""; break }
      out = out substr(line, 1, p - 1); line = substr(line, p + 4); incomment = 1
    }
  }
  line = out; pos = 1
  while ((p = index(substr(line, pos), "](")) > 0) {
    s = pos + p + 1; depth = 1; i = s; t = ""
    while (i <= length(line)) {
      c = substr(line, i, 1)
      if (c == "(") depth++
      else if (c == ")") { depth--; if (depth == 0) break }
      t = t c; i++
    }
    if (depth == 0) emit(t)
    pos = (i > s ? i : s)
  }
}'

# walk <bundle-root> — prints "<rel>:<line>:<target>:<OK|DEAD>", one per intra-bundle link.
walk() {
  local root="$1" rel dest line target abs verdict dir
  while IFS= read -r rel; do
    dest="$(ab_seed_dest "$rel")"
    [ -f "$root/$dest" ] || { echo "$rel:0:<not stamped>:DEAD"; continue; }
    dir="$(dirname "$dest")"
    while IFS=$'\t' read -r _ line target; do
      target="${target%%[[:space:]]*}"              # [text](path "title")
      target="${target%%#*}"                        # drop the fragment
      case "$target" in
        ''|'#'*)                       continue ;;  # anchor-only, or empty
        *://*|mailto:*)                continue ;;  # external
        *'<'*|*'>'*|*'…'*|url)         continue ;;  # a documented shape, not a file
      esac
      case "$target" in
        /*) abs="$root$target" ;;
        *)  abs="$root/$dir/$target" ;;
      esac
      if [ -e "$abs" ]; then verdict=OK; else verdict=DEAD; fi
      echo "$dest:$line:$target:$verdict"
    done < <(awk -v REL="$dest" "$extract_links" "$root/$dest")
  done < <(cd "$TPLSRC/plugin/seed" && find . -name '*.md' -type f | sed 's#^\./##' | sort)
}

# A copy of the template, so install.sh's worktree refusal never fires on it.
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL"/plugin/scripts/*.sh 2>/dev/null || true

INST="$TMP/inst"; mkdir -p "$INST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/stamp.out" 2>&1

echo
echo "== 1. the stamp produced a 3.0 bundle (no migrate step exists to run) =="
ok "a bundle was stamped"          "$(test -f "$INST/instance.config.json" && echo yes || echo no)" yes
ok "CONVENTIONS.md is under $AB_DIR" "$(test -f "$INST/$AB_CONVENTIONS" && echo yes || echo no)" yes
ok "…and NOT at the bundle root"   "$(test -e "$INST/CONVENTIONS.md" && echo yes || echo no)" no
ok "index.md is under $AB_DIR"     "$(test -f "$INST/$AB_INDEX" && echo yes || echo no)" yes

walk "$INST" > "$TMP/links"
checked="$(wc -l < "$TMP/links" | tr -d ' ')"
dead="$(grep -c ':DEAD$' "$TMP/links")"

echo
echo "== 2. every intra-bundle link in the seeded docs resolves =="
# The seed carries 19 markdown links, of which 8 are intra-bundle once the exclusions in
# section 6 are applied. The floor is an anti-vacuous guard, not a pinned inventory: a
# walker that reads nothing reports zero dead links and looks exactly like a pass.
ok "the walker walked the intra-bundle links" "$([ "$checked" -ge 8 ] && echo yes || echo "no ($checked)")" yes
[ "$dead" = 0 ] || { echo "  --- dead links ---"; grep ':DEAD$' "$TMP/links" | sed 's/^/  /'; }
ok "no dead intra-bundle link"     "$dead" 0

echo
echo "== 3. the five instances resolve, by destination =="
# Asserted by where a link LANDS, not by its text, so a different correct spelling passes.
hits() { # <seeded doc> <expected bundle-relative target> — links in <doc> landing on it
  local doc="$1" want="$2" dir n=0 f line target verdict abs
  dir="$(dirname "$doc")"
  while IFS=: read -r f line target verdict; do
    [ "$f" = "$doc" ] && [ "$verdict" = OK ] || continue
    case "$target" in /*) abs="$INST$target" ;; *) abs="$INST/$dir/$target" ;; esac
    [ "$abs" -ef "$INST/$want" ] && n=$((n+1))
  done < "$TMP/links"
  echo "$n"
}
ok "CLAUDE.md links to $AB_CONVENTIONS twice" "$(hits CLAUDE.md "$AB_CONVENTIONS")" 2
ok "$AB_INDEX links to $AB_SCHEMA"            "$(hits "$AB_INDEX" "$AB_SCHEMA")" 1
ok "$AB_INDEX links to $AB_LEDGER"            "$(hits "$AB_INDEX" "$AB_LEDGER")" 1
ok "$AB_INDEX links to $AB_ROSTER"            "$(hits "$AB_INDEX" "$AB_ROSTER")" 1

echo
echo "== 4. the negative control: knowledge/ does not move, so it is NOT reported =="
# Asserted as CHECKED-and-OK, never as merely absent from the failures: a walker that
# examines nothing would pass an "is not reported" test. This is the fixture that catches
# an over-broad checker.
ok "$AB_INDEX links to knowledge/index.md"  "$(hits "$AB_INDEX" knowledge/index.md)" 1
ok "knowledge/index.md is checked, not skipped" \
  "$(grep -c ':/knowledge/index.md:OK$' "$TMP/links")" 1
ok "…and it is never reported dead"         "$(grep -c ':/knowledge/index.md:DEAD$' "$TMP/links")" 0
ok "knowledge/vocab.md survives too"        "$(grep -c ':/knowledge/vocab.md:DEAD$' "$TMP/links")" 0

echo
echo "== 5. the walker CATCHES a planted dead link (a green-only harness proves nothing) =="
# Both pre-3.0 spellings, planted into the stamped bundle: the relative form CLAUDE.md
# shipped, and the root-absolute form index.md shipped. The third plant is the same dead
# link inside an HTML comment — the only way to show the comment stripper works, since
# every commented link the seed ships is also a `<slug>` placeholder.
printf '\n[planted relative](CONVENTIONS.md)\n' >> "$INST/CLAUDE.md"
printf '\n[planted absolute](/SCHEMA.md)\n'     >> "$INST/$AB_INDEX"
printf '\n<!-- [planted, commented out](/NOPE-commented-out.md) -->\n' >> "$INST/$AB_INDEX"
walk "$INST" > "$TMP/links.planted"
planted_dead="$(grep -c ':DEAD$' "$TMP/links.planted")"
ok "the relative pre-3.0 form is caught" \
  "$(grep -c "^CLAUDE.md:[0-9]*:CONVENTIONS.md:DEAD$" "$TMP/links.planted")" 1
ok "the root-absolute pre-3.0 form is caught" \
  "$(grep -c "^$AB_INDEX:[0-9]*:/SCHEMA.md:DEAD$" "$TMP/links.planted")" 1
ok "the commented-out plant is NOT reported" \
  "$(grep -c NOPE-commented-out "$TMP/links.planted")" 0
ok "exactly the two live plants are reported" "$planted_dead" 2
ok "…and the negative control still is not" \
  "$(grep -c ':/knowledge/index.md:DEAD$' "$TMP/links.planted")" 0

echo
echo "== 6. the exclusions are asserted, so the scope rule is not merely written down =="
# Five placeholder targets ship in the seed today. Each would be a dead link to any
# walker that took it literally, and all five together are what a noisy validator looks
# like on day one.
ok "an external URL is out"      "$(grep -c '://' "$TMP/links")" 0
ok "a bare 'url' shape is out"   "$(grep -c ':url:' "$TMP/links")" 0
ok "a '<slug>' shape is out"     "$(grep -c '<' "$TMP/links")" 0
ok "an ellipsis shape is out"    "$(grep -c '…' "$TMP/links")" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
