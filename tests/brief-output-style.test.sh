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
ok "…every item executable, with the URL inline" "$(has "$STYLE" 'with the URL inline, or a local file as a markdown link whose target is its absolute path')" yes
ok "…a command is its own inline-code line, no bullet, number, prompt or prose" "$(has "$STYLE" 'A command the human runs goes on its own line as inline code, with no bullet, number, `$` prompt or trailing prose on the line, and never in a fenced block')" yes
ok "…several commands are several lines, in run order" "$(has "$STYLE" 'Several commands are several such lines, in run order.')" yes
ok "…every item carries a recommendation" "$(has "$STYLE" 'Every `Needs you` item ends with `Recommend: <the answer> — <one-line reason>`** on the item'"'"'s line')" yes
ok "…except a lone merge or close whose verb is the advice, and no other" "$(has "$STYLE" '**except a lone merge or close item whose verb already is the advice** (🔀 merge once green, 🏁 close a finished project), which carries none; no other verb is exempt.')" yes
ok "…a real choice still carries it"      "$(has "$STYLE" 'A real choice (options, yes/no, `go`/`prom`) keeps it')" yes
ok "…and so does advice unlike the verb, with its reason" "$(has "$STYLE" 'an item whose advice differs from the obvious action (wait, don'"'"'t merge yet), with its reason')" yes
ok "…a relayed row keeps its recommendation, its link made absolute" "$(has "$STYLE" 'keep that text unchanged, a merge or close row included, and rewrite only its link target to an absolute path.')" yes
ok "…which an AWAITING row already carries" "$(has "$STYLE" 'carries it as `(recommended: …)` or `(no recommendation)`, which satisfies this')" yes
ok "…or says why it has none"             "$(has "$STYLE" 'An item with no sensible default says why')" yes
ok "…display-only on promote and merge"   "$(has "$STYLE" 'On a promote or merge item it is display-only — only a typed `prom` or `mrg` acts')" yes
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

# =======================================================================================
echo "== 3. Links, keywords, hand-off text, clean copy and the icon set; CLAUDE.md points here =="
# =======================================================================================
SEED_CLAUDE="$REPO/plugin/seed/CLAUDE.md"
ok "the style stays at or under 90 lines" "$([ "$(wc -l < "$STYLE")" -le 90 ] && echo yes || echo no)" yes
ok "keywords go in inline code"           "$(has "$STYLE" '**Keywords go in inline code**: task ids, branches, file names, config keys, command names.')" yes
ok "every PR, run, URL and local file is a link" "$(has "$STYLE" 'Every PR, run, URL and local file is a markdown link')" yes
ok "…bare URLs only inside copy-ready text" "$(has "$STYLE" 'Never a bare URL, except inside copy-ready text.')" yes
ok "a linked keyword keeps an inline-code label" "$(has "$STYLE" '[`task-001`](/Users/…/task-001.md). A branch or commit links to its GitHub URL.')" yes
ok "a command is always its own inline-code line" "$(has "$STYLE" '**A command is always its own inline-code line**')" yes
ok "reply shorthand is inline code, as typed" "$(has "$STYLE" '`prom 10 11`, `mrg`, `go`, `ok`, `1 n 2`')" yes
ok "recap items open with a bold label, Needs-you items with their verb" "$(has "$STYLE" '**Each numbered `Done so far` item opens with a short bold label**')" yes
ok "a hand-off block sits above Needs you" "$(has "$STYLE" '**A hand-off block sits above `Needs you:`**')" yes
ok "tick reports are exempt"              "$(has "$STYLE" '**Tick reports are exempt from hand-off blocks, clean copy and recap labels**')" yes
ok "hand-off text: a label line, then plain paragraphs" "$(has "$STYLE" 'no `>` blockquote, no indentation, no bullets.')" yes
ok "nothing copy-ready is quoted or indented" "$(has "$STYLE" '**Never a `>` quote or indentation for anything meant to be copied.**')" yes
ok "clean copy is interactive only"       "$(has "$STYLE" 'in an interactive session only, never a background tick or subagent.')" yes
ok "…checks tmp/copy is ignored first"    "$(has "$STYLE" '`git check-ignore -q tmp/copy`')" yes
ok "…and a failed check stops the whole sequence" "$(has "$STYLE" 'If it exits non-zero, stop the clean copy: write no file, skip steps 2–5, and tell the human the clipboard was not updated.')" yes
ok "…clears old files, writes with the Write tool, text only" "$(has "$STYLE" 'Delete `tmp/copy/copy-*.txt`, then write `tmp/copy/copy-1.txt`, `copy-2.txt` … with the Write tool, one per block: the text only, never its label line.')" yes
ok "…pbcopy is named"                     "$([ "$(grep -c pbcopy "$STYLE")" -ge 1 ] && echo yes || echo no)" yes
ok "…several blocks: one pbcopy line each, run with !" "$(has "$STYLE" 'one `pbcopy < <abs path>` line each, which the human runs with `!`')" yes
ok "…no pbcopy: print the path"           "$(has "$STYLE" 'No `pbcopy` on this machine: print each file'"'"'s absolute path instead.')" yes
ok "the seed settings allow exactly one pbcopy form" "$(jq -r '[.permissions.allow[] | select(test("pbcopy"))] | join("|")' "$SETTINGS")" 'Bash(pbcopy < tmp/copy/copy-1.txt)'
ok "…the form the style runs"             "$(has "$STYLE" 'run `pbcopy < tmp/copy/copy-1.txt` from the bundle root')" yes
# LC_ALL=C: a UTF-8 collation can rank distinct emoji equal, and sort -u then merges them.
ok "five new icons, distinct"             "$(grep -o -E '📋|🌐|🔗|🔍|⚠️' "$STYLE" | LC_ALL=C sort -u | wc -l | tr -d ' ')" 5
ok "…each listed once with its meaning"   "$(grep -c -F -- '- ⚠️ don'"'"'t do this yet · 📋 a message to send to a person · 🌐 a Claude in Chrome prompt · 🔗 a link the human must open · 🔍 something to check by eye and report back.' "$STYLE" | tr -d ' ')" 1
ok "only the 13 start a line, never a command line" "$(has "$STYLE" '**Only these 13 may start a line**, and a command line carries none')" yes
ok "a board glyph is named mid-sentence only" "$(has "$STYLE" 'a relayed `AWAITING.md` row starts with one of the 13 and names its board glyph mid-line.')" yes

example() { awk '/^## Hand-off example$/{f=1; next} f && /^## /{exit} f && NF' "$1"; }
EX="$(example "$STYLE")"
ok "the hand-off example has a label line, then text" "$(head -1 <<<"$EX")" '📋 **WhatsApp → <name>**'
ok "…at least one plain paragraph under it" "$([ "$(wc -l <<<"$EX")" -ge 2 ] && echo yes || echo no)" yes
ok "…no > line, indentation or bullet in it" "$(grep -c -E '^(>|[[:space:]]|[-*+] |[0-9]+\. )' <<<"$EX" | tr -d ' ')" 0
ok "…and exactly one example heading"     "$(grep -c '^## Hand-off example$' "$STYLE" | tr -d ' ')" 1
awk '/^## Hand-off example$/{print; print ""; print "> quoted"; next} 1' "$STYLE" > "$TMP/mutant-style.md"
ok "mutant: a > line in the example -> check FAILS" "$(grep -c -E '^(>|[[:space:]]|[-*+] |[0-9]+\. )' <<<"$(example "$TMP/mutant-style.md")" | tr -d ' ')" 1

SHARED=('Always link to the real artifacts' 'Lead with the outcome' '`prom` or `mrg`')
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
agree() { local p n=0; for p in "${SHARED[@]}"; do [ "$(saw "$(flat "$1")" "$p")" = yes ] && [ "$(saw "$(flat "$2")" "$p")" = yes ] && n=$((n+1)); done; echo "$n"; }
ok "each shared phrase is in both seed CLAUDE.md and the style" "$(agree "$SEED_CLAUDE" "$STYLE")" "${#SHARED[@]}"
grep -vF 'Always link to the real artifacts' "$STYLE" > "$TMP/mutant-noshare.md"
ok "mutant: a shared phrase gone from the style -> check FAILS" "$(agree "$SEED_CLAUDE" "$TMP/mutant-noshare.md")" "$(( ${#SHARED[@]} - 1 ))"
ok "seed CLAUDE.md names the style as the source" "$(grep -c -F '.claude/output-styles/brief.md' "$SEED_CLAUDE" | tr -d ' ')" 2
ok "…and its Output style section is one pointer line" "$(awk '/^### Output style$/{f=1; next} f && /^#/{exit} f && NF' "$SEED_CLAUDE" | wc -l | tr -d ' ')" 1

echo
total=$((pass + fail))
ok "exactly 69 assertions ran"            "$total" 69

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
