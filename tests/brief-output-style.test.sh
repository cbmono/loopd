#!/usr/bin/env bash
#
# brief-output-style.test.sh — the Brief output style (the `Needs you:` contract every
# loopd report follows) ships in the SEED, the seed settings select it, and the welcome
# check names a bundle that has one half without the other.
#
# WHY THIS EXISTS. Until 2026-10-28 the style lived only in a separate repository
# (cbmono/ai-setup) linked into the operator's ~/.claude, so a machine that installed the
# loopd plugin and nothing else got the seed CLAUDE.md's shorthand rules ("Replies to a
# `Needs you:` list are shorthand") with nothing that ever produced a `Needs you:` list.
# The owner's decision: install loopd and be good to go, no second repo.
#
# WHERE IT SHIPS IS A MEASUREMENT, NOT A PREFERENCE. Claude Code 2.1.312 accepts
# `output-styles/` as plugin content, but a style placed there was NOT loaded under either
# `Brief` or `loopd:Brief` (two probes, each answered NO to "does your system prompt contain
# 'Report like a briefing.'"), while the same file at a project's `.claude/output-styles/`
# was (YES; an unknown name as the negative control: NO). So the style is seed content,
# bundle-scoped, and the seed `.claude/settings.json` selects it. Section 1 pins both.
#
# THE TWO HALVES HAVE TWO OWNERS, AND THAT IS WHAT THE CHECK IS FOR. The style FILE is a
# seed document: a stamp delivers it to any bundle that lacks it, because a stamp seeds
# what is absent. The settings KEY is config: copied once, never merged, so a bundle stamped
# before 2026-10-28 never receives it, and then the style is a file nothing selects. The
# `output-style` welcome row says which half is missing and prints the one-line fix; it
# writes neither (config is the human's; a style choice is per bundle). A different style
# chosen on purpose is a choice, reported as ✓ — section 2 asserts all four states.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

STYLE="$REPO/plugin/seed/.claude/output-styles/brief.md"
SETTINGS="$REPO/plugin/seed/.claude/settings.json"
WELCOME="$REPO/plugin/scripts/welcome.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/brief-style.XXXXXX")" || {
  echo "brief-output-style.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# Here-strings, never a pipe into grep -q (no-early-exit-pipe.test.sh).
has() { grep -qF -- "$2" <<<"$(cat "$1")" && echo yes || echo no; }
saw() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
fm_name() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1 && /^name:/{sub(/^name:[[:space:]]*/,""); print}' "$1"; }

# =======================================================================================
echo "== 1. The style is seed content, and the seed settings select it by its own name =="
# =======================================================================================
ok "the style ships under the seed's .claude/output-styles/" "$([ -f "$STYLE" ] && echo yes || echo no)" yes
ok "…its frontmatter names it Brief"      "$(fm_name "$STYLE")" Brief
ok "…and keeps the coding instructions"  "$(has "$STYLE" 'keep-coding-instructions: true')" yes
# The contract the seed CLAUDE.md's shorthand rules presuppose: a `Needs you:` list of
# executable steps, each with its URL or path. Pinned by phrase so the style cannot drift
# into a different shape under the same name.
ok "…it defines the Needs-you heading"   "$(has "$STYLE" 'ℹ️ **Needs you:**')" yes
ok "…every item executable, with the URL inline" "$(has "$STYLE" 'with the URL or exact path inline')" yes
ok "…and the Done-so-far heading"        "$(has "$STYLE" '🚀 **Done so far:**')" yes
ok "…and never invents state"            "$(has "$STYLE" 'Report only what you verified')" yes

sel="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("outputStyle",""))' "$SETTINGS" 2>/dev/null)"
ok "the seed settings select it"         "$sel" Brief
ok "…by the style's own name, so the two cannot drift apart" "$([ "$sel" = "$(fm_name "$STYLE")" ] && echo yes || echo no)" yes
ok "…and the settings' own note says a pre-2026-10-28 bundle adds the key by hand" \
  "$(has "$SETTINGS" 'a bundle stamped before 2026-10-28 adds the key by hand')" yes
# NOT in the plugin: the measured non-loading location. A copy there would be a second
# source the next reader keeps in sync by hand.
# path-scan: absent plugin/output-styles — the measured non-loading location; its absence IS the assertion
ok "no copy under plugin/output-styles/" "$([ -e "$REPO/plugin/output-styles" ] && echo yes || echo no)" no

# =======================================================================================
echo "== 2. The welcome row names the missing half, writes nothing, and respects a choice =="
# =======================================================================================
ok "output-style is a row in CHECKS, ambiguous, off the banner path" "$(bash "$WELCOME" check --list | awk -F'\t' '$1=="output-style"{print $2"|"$3}')" "ambiguous|no"
ok "…with no fix function (never repaired)" "$(grep -c '^fix_output_style()' "$WELCOME" | tr -d ' ')" 0

mkinst() { # <dir> — the smallest bundle welcome.sh check accepts
  mkdir -p "$1/.claude" "$1/$AB_DIR"
  printf '{\n  "org": "example-org"\n}\n' > "$1/instance.config.json"
  printf 'stub\n' > "$1/$AB_SCHEMA"
}
# The check form prints verdict lines, not section headings, so the row is found by its own
# text. Here-strings, never a pipe into an early-exiting awk (no-early-exit-pipe.test.sh).
checkout() { bash "$WELCOME" check --instance "$1" --template "$REPO" 2>&1; }
row() { awk '/^(✓|⚠) .*output style:/{print; exit}' <<<"$(checkout "$1")"; }   # this row's verdict line, and only it
hintline() { awk 'f{print; exit} /^(✓|⚠) .*output style:/{f=1}' <<<"$(checkout "$1")"; }

# (a) neither half: a bundle never stamped since the style shipped.
A="$TMP/a"; mkinst "$A"; printf '{}\n' > "$A/.claude/settings.json"
out="$(row "$A")"
ok "no file ⇒ ⚠"                          "$(saw "$out" '⚠')" yes
ok "…naming the seed file"               "$(saw "$out" '.claude/output-styles/brief.md is not in this bundle')" yes
ok "…and the fix is a stamp"             "$(saw "$(hintline "$A")" ":init $A")" yes
# (b) file but no key: stamped after 2026-10-28, settings copied before — the common case.
B="$TMP/b"; mkinst "$B"; mkdir -p "$B/.claude/output-styles"; cp "$STYLE" "$B/.claude/output-styles/"
printf '{}\n' > "$B/.claude/settings.json"
before="$(cat "$B/.claude/settings.json")"
out="$(row "$B")"
ok "file, no key ⇒ ⚠"                     "$(saw "$out" '⚠')" yes
ok "…saying the key is what is missing"  "$(saw "$out" 'selects no outputStyle')" yes
ok "…and the fix names the key and the file" "$(saw "$(hintline "$B")" '"outputStyle": "Brief"')" yes
ok "…and the settings were not written"  "$([ "$before" = "$(cat "$B/.claude/settings.json")" ] && echo yes || echo no)" yes
# (c) both halves: a fresh stamp.
C="$TMP/c"; mkinst "$C"; mkdir -p "$C/.claude/output-styles"; cp "$STYLE" "$C/.claude/output-styles/"
cp "$SETTINGS" "$C/.claude/settings.json"
out="$(row "$C")"
ok "both ⇒ ✓"                             "$(saw "$out" '✓')" yes
ok "…naming Brief"                        "$(saw "$out" 'output style: Brief')" yes
# (d) a different style, chosen: a choice, never a problem.
D="$TMP/d"; mkinst "$D"; mkdir -p "$D/.claude/output-styles"; cp "$STYLE" "$D/.claude/output-styles/"
printf '{"outputStyle":"Explanatory"}\n' > "$D/.claude/settings.json"
out="$(row "$D")"
ok "another style ⇒ ✓, not ⚠"             "$(saw "$out" '✓')" yes
ok "…naming the chosen one"               "$(saw "$out" 'output style: Explanatory')" yes
ok "…and where the seed's Brief is"       "$(saw "$out" '.claude/output-styles/brief.md')" yes

echo
total=$((pass + fail))
ok "exactly 25 assertions ran"            "$total" 25

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
