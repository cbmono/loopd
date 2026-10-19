#!/usr/bin/env bash
# iced — the board is on hold (owner's decision, 2026-10-05). `run.sh --iced`, the nightly
# workflow and any PR whose diff names this file's subject still run it. Thaw: delete these lines.
#
# banner-logo.test.sh — the loopd mark with the banner's header and rule BESIDE it
# (interactive-board/task-008): three rows of DATA, coloured POSITIONALLY, rows 2 and 3
# carrying the header and its rule from one shared column.
#
# The claims: the three rows are byte-exact, with the header and rule as row 2's and row 3's
# suffixes; the gate and the `◀━` exit arrow are the ONLY pink in the mark, in all three
# colour tiers; every escape the mark emits is one `cli-theme.json` defines; the opt-outs
# leave the rows with no SGR at all; the header and rule spans are the `--no-logo` banner's
# own bytes, colour included, so only their POSITION changed; and (§5) the mark renders on
# the SessionStart channel ALONE, never on the relayed `/welcome` path.
#
# assert(): 0 is a PASS, matching the banner harnesses next door.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
HOOK="$TPL/plugin/hooks/session-banner.sh"
SH="$TPL/plugin/scripts/welcome.sh"
SKILL="$TPL/plugin/skills/welcome/SKILL.md"
DOC="$TPL/docs/operations.md"
THEME="$TPL/plugin/scripts/cli-theme.sh"
for f in "$HOOK" "$SH" "$SKILL" "$DOC" "$THEME"; do
  [ -f "$f" ] || { echo "banner-logo.test: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || {
  echo "banner-logo.test: python3 is required to parse the hook's JSON" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/banner-logo.XXXXXX")" || {
  echo "banner-logo.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [ "$2" -eq 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
eq()    { [ "$1" = "$2" ] && echo 0 || echo 1; }
has()   { grep -qF -- "$1" <<<"$2" && echo 0 || echo 1; }

# Named once. A literal ESC is invisible in a diff and in a grep, which is why nothing in
# this repo types one.
ESC="$(printf '\033')"
no_esc()    { LC_ALL=C grep -q "$ESC" <<<"$1" && echo 1 || echo 0; }
strip_sgr() { printf '%s' "$1" | LC_ALL=C sed "s/$ESC\[[0-9;]*m//g"; }
nth()       { printf '%s\n' "$1" | sed -n "$2p"; }
head_no()   { awk '$0 != "" { print NR; f = 1; exit } END { if (!f) print 0 }' <<<"$1"; }
# CHARACTERS, not bytes and not the locale's opinion — the hook's `nchars`, restated.
chars()     { printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '; }

# THE THREE ROWS, TYPED HERE AND NOWHERE ELSE IN THIS FILE — copied from the design
# source's `cli-banner.sh`. The hook keeps its own copy as `indent|pink|blue` data; that the
# two agree glyph for glyph is the first assertion below.
L1='   ▄▄▄▄'
L2='◀━▐    ▌'
L3='  ▝▄▄▄▄▘'
# The rows as the hook stores them, so "kept once, as data" is countable.
D1='   |▄|▄▄▄'
D2='|◀━|▐    ▌'
D3='  ||▝▄▄▄▄▘'

# --- the fixture instance ----------------------------------------------------------------
INST="$TMP/_ai-bridge-fixture"
mkdir -p "$INST/.claude/agents"
printf 'stub\n' > "$INST/SCHEMA.md"
printf '{ "org": "example-org" }\n' > "$INST/instance.config.json"

run() { # <hook> [args…] -> the plain-text banner
  CLAUDE_PROJECT_DIR="$INST" bash "$1" "${@:2}" 2>/dev/null
}
runenv() { # <env assignment…> -- <hook> [args…]
  local env=(); while [ "$1" != -- ]; do env+=("$1"); shift; done; shift
  env "${env[@]}" CLAUDE_PROJECT_DIR="$INST" bash "$@" 2>/dev/null
}

# =======================================================================================
echo "== 1. the three rows, verbatim, with the header and rule beside them =="
# =======================================================================================
OUT="$(run "$HOOK")"
n="$(head_no "$OUT")"
r2="$(nth "$OUT" "$((n+1))")"; r3="$(nth "$OUT" "$((n+2))")"
HDR="${r2#"$L2 "}"; RULE="${r3#"$L3 "}"
assert "row 1 is the top edge with its gate, alone, byte for byte" "$(eq "$(nth "$OUT" "$n")" "$L1")"
assert "row 2 is the exit arrow and the tube, then one space" "$(eq "${r2:0:${#L2}+1}" "$L2 ")"
assert "row 3 is the bottom edge, then one space" "$(eq "${r3:0:${#L3}+1}" "$L3 ")"
# THE VERSION LINE'S SHAPE IS LITERAL — the `·` separators and the `org: ` label included.
assert "row 2's suffix is the version line, in its literal shape" \
  "$(grep -qE '^loopd v[0-9][^ ]* · [^ ]+ · org: .+$' <<<"$HDR" && echo 0 || echo 1)"
assert "row 3's suffix is the rule" "$([ -n "$RULE" ] && [ -z "${RULE//─/}" ] && echo 0 || echo 1)"
assert "…as wide as the header, in characters" "$(eq "$(chars "$RULE")" "$(chars "$HDR")")"
assert "the header and the rule start in the same column" \
  "$(eq "$(chars "${r2%"$HDR"}")" "$(chars "${r3%"$RULE"}")")"
assert "…one past the mark's widest row" "$(eq "$(chars "${r2%"$HDR"}")" "$(( $(chars "$L2") + 1 ))")"
assert "…and nothing follows the block but a blank line" "$(eq "$(nth "$OUT" "$((n+3))")" "")"
# KEPT ONCE, AS DATA. Three inline printf fragments would satisfy every assertion above and
# be three places to edit; the hook holds one array and this counts it.
for l in "$D1" "$D2" "$D3"; do
  assert "the hook carries that row exactly once" "$(eq "$(grep -cF -- "$l" "$HOOK")" 1)"
done
assert "…on one line, as an array rather than three printfs" \
  "$(eq "$(grep -cF -- "LOGO_ROWS=(" "$HOOK")" 1)"
# THE DOCS SAMPLE IS A SAMPLE OF THIS OUTPUT, so it carries the same three rows.
SAMPLE="$(cat "$DOC")"
for l in "$L1" "$L2" "$L3"; do
  assert "the operations.md banner sample shows it too" "$(has "$l" "$SAMPLE")"
done
assert "…and the sample's version line carries the brand, lowercase, beside row 2" \
  "$(grep -qE "^$L2 loopd v" <<<"$SAMPLE" && echo 0 || echo 1)"
assert "no ASCII alien survives in the hook" \
  "$(eq "$(grep -ci 'AI-Bridge v' "$HOOK")" 0)"

# =======================================================================================
echo "== 2. the gate and the exit arrow are the only pink, in all three tiers =="
# =======================================================================================
# The claim is not "the rows are coloured" — it is WHICH TWO SPANS are the human's. Row 1
# proves it alone: the same `▄` is pink in column 4 and blue in column 5, so a split by
# glyph class cannot produce it. Row 3 is the control — all machine, no pink at all.
OFF="${ESC}[0m"   # the reset the rest of the banner already uses, not a second one
tier() { # <tier name> <blue> <pink> <env…>
  local name="$1" b="$2" k="$3"; shift 3
  local out l1 l2 l3 m nl h
  out="$(runenv "$@" -- "$HOOK" --color always)"; m="$(head_no "$out")"
  l1="$(nth "$out" "$m")"; l2="$(nth "$out" "$((m+1))")"; l3="$(nth "$out" "$((m+2))")"
  nl="$(runenv "$@" -- "$HOOK" --color always --no-logo)"; h="$(head_no "$nl")"
  assert "$name: row 1 is indent, pink gate, blue tube" \
    "$(eq "$l1" "   ${ESC}[${k}m▄${ESC}[${b}m▄▄▄${OFF}")"
  # COLOURS UNCHANGED: the header and rule spans are the `--no-logo` lines' own bytes —
  # bold ink, dim grey, one reset each — so the block moved them and recoloured nothing.
  assert "$name: row 2 is the pink exit arrow, blue, then the header in its own colour" \
    "$(eq "$l2" "${ESC}[${k}m◀━${ESC}[${b}m▐    ▌${OFF} $(nth "$nl" "$h")")"
  assert "$name: row 3 is all blue, then the rule in its own colour — no third pink span" \
    "$(eq "$l3" "  ${ESC}[${b}m▝▄▄▄▄▘${OFF} $(nth "$nl" "$((h+1))")")"
  assert "$name: …and the header span is coloured at all (not vacuous)" \
    "$(eq "$(no_esc "$(nth "$nl" "$h")")" 1)"
  assert "$name: …and exactly two pink spans in the whole mark" \
    "$(eq "$(printf '%s%s%s' "$l1" "$l2" "$l3" | grep -oF -- "${ESC}[${k}m" | grep -c .)" 2)"
  assert "$name: …and stripping the SGR gives the three plain rows back" \
    "$(eq "$(strip_sgr "$l1")$(strip_sgr "$l2")$(strip_sgr "$l3")" "$L1$L2 $HDR$L3 $RULE")"
}
# ONE RESET, AND SINCE loopd/task-004 IT IS THE THEME'S. A second escape spelling would
# render the same and be a second thing to keep in step, so both files are asked how many
# they build: the theme exactly one, the hook none at all.
assert "the reset after each run is the theme's one" \
  "$(eq "$(grep -cF -- '${esc}[0m' "$THEME")" 1)"
assert "…and the hook builds no SGR of its own — strip_sgr's ESC matcher aside" \
  "$(eq "$(grep -cF -- '${esc}[' "$HOOK")" 0)"
# THE COLOUR COUNT IS STUBBED, NEVER THE HOST'S. `tput colors` answers 0 wherever the
# terminfo entry cannot be loaded, so a TERM name alone asserts the 16-colour palette as 256.
stub_tput() { # <count|fail> -> a bin dir whose `tput colors` answers that
  local d="$TMP/tput-$1"; mkdir -p "$d"
  if [ "$1" = fail ]; then printf '#!/bin/sh\nexit 1\n' > "$d/tput"
  else printf '#!/bin/sh\n[ "$1" = colors ] || exit 1\necho %s\n' "$1" > "$d/tput"; fi
  chmod +x "$d/tput"; printf '%s' "$d"
}
# THE CODES ARE `cli-theme.json`'s, TYPED HERE AS FIXTURES BECAUSE THE THEME FILE IS A
# DESIGN SOURCE IN THE BUNDLE AND NOT IN THIS REPO: `truecolor.blue` / `truecolor.pink`,
# then `ansi256.blue` (75) / `ansi256.pink` (212). Nothing between them is composed.
tier truecolor '38;2;94;162;255' '38;2;255;122;194' COLORTERM=truecolor
tier 24bit     '38;2;94;162;255' '38;2;255;122;194' COLORTERM=24bit
tier 256 '38;5;75' '38;5;212' COLORTERM= TERM=xterm-256color \
  PATH="$(stub_tput 256):$PATH"
# THE 3/4-BIT TIER IS THE ONE THIS FILE ALREADY HAD AND IT SURVIVES: `cli-theme.json`
# defines none, and inventing codes is what the palette rule forbids.
tier 16  '94' '95' COLORTERM= TERM=xterm PATH="$(stub_tput 8):$PATH"
# AND THE HOST WITH NO USABLE TERMINFO: tput answers nothing, tc is 0, and the 16-colour
# palette is the correct output — which is also what makes the tier above non-vacuous.
tier 'no terminfo' '94' '95' COLORTERM= TERM=xterm-256color \
  PATH="$(stub_tput fail):$PATH"
for code in '[94m' '[95m' '[1;93m'; do
  assert "the 3/4-bit tier still carries $code" "$(eq "$(grep -cF -- "$code" "$THEME")" 1)"
done
# EVERY ESCAPE THE THEME HELPER SPELLS IS ONE cli-theme.json DEFINES — nothing composed.
# The one addition is T_GREEN, the brand's #76d6a4 (theme-palette.txt) and its nearest 256
# code, by the owner's decision of 2026-10-18 (interactive-board/task-007).
assert "every truecolor escape in cli-theme.sh is a cli-theme.json value" \
  "$(eq "$(grep -oE '38;2;[0-9;]+' "$THEME" | sort -u \
      | grep -vcE '^(38;2;94;162;255|38;2;255;122;194|38;2;233;237;244|38;2;154;164;181|38;2;108;116;136|38;2;118;214;164)$')" 0)"
assert "every 256-colour escape in cli-theme.sh is a cli-theme.json value" \
  "$(eq "$(grep -oE '38;5;[0-9]+' "$THEME" | sort -u \
      | grep -vcE '^38;5;(75|212|255|248|243|115)$')" 0)"

# =======================================================================================
echo "== 3. the opt-outs leave the three rows with NO SGR at all =="
# =======================================================================================
plain_logo() { # <banner> -> 0 when the three lines are present and carry no escape
  local out="$1" m; m="$(head_no "$out")"
  [ "$(nth "$out" "$m")" = "$L1" ] && [ "$(nth "$out" "$((m+1))")" = "$L2 $HDR" ] \
    && [ "$(nth "$out" "$((m+2))")" = "$L3 $RULE" ] \
    && [ "$(no_esc "$(nth "$out" "$m")$(nth "$out" "$((m+1))")$(nth "$out" "$((m+2))")")" = 0 ] \
    && echo 0 || echo 1
}
# ON THE JSON PATH, where the field is drawn by the client and the logo is coloured by
# default — the only channel on which "the opt-out turned it off" is a real observation.
sm() { printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["systemMessage"])'; }
assert "NO_COLOR=1 prints them plain on the channel that renders SGR" \
  "$(plain_logo "$(sm "$(runenv NO_COLOR=1 -- "$HOOK" --format json)")")"
assert "--color never prints them plain there too" \
  "$(plain_logo "$(sm "$(run "$HOOK" --format json --color never)")")"
assert "a pipe with no flags prints them plain"  "$(plain_logo "$OUT")"
# NON-VACUITY: the same path DOES colour them when nothing is opting out, so the assertions
# above are about the opt-out and not about a logo that is never coloured at all.
assert "…while the same json run without it colours them" \
  "$(eq "$(plain_logo "$(sm "$(run "$HOOK" --format json)")")" 1)"
# THE `/welcome` RELAY. Markdown renders there and SGR does not, so that rendering carries
# the same three lines and no escape — colour is not promised on that channel. Its `**` is
# emphasis, not content: it wraps the WHOLE header row, because `emit_md` reads only a
# prefix, so row 2 still renders the header bold.
MD="$(run "$HOOK" --format md)"
assert "the hook's md rendering shows the same three lines" "$(plain_logo "$(sed 's/\*\*//g' <<<"$MD")")"
assert "…with the header row wrapped in emphasis, start to end" \
  "$(eq "$(nth "$MD" "$(( $(head_no "$MD") + 1 ))")" "**$L2 $HDR**")"
assert "…and rows 1 and 3 left alone" \
  "$(eq "$(nth "$MD" "$(head_no "$MD")")$(nth "$MD" "$(( $(head_no "$MD") + 2 ))")" "$L1$L3 $RULE")"
assert "…and the hook's own header says colour is not promised there" \
  "$(has 'colour is not promised' "$(sed -n '1,260p' "$HOOK")")"
# AND THE EQUALITY THE TWO CHANNELS RUN ON: strip_sgr(systemMessage) is the text banner.
JSON="$(run "$HOOK" --format json --color always)"
SM="$(printf '%s' "$JSON" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["systemMessage"])')"
assert "strip_sgr(systemMessage) still equals the text banner" "$(eq "$(strip_sgr "$SM")" "$OUT")"

# =======================================================================================
echo "== 4. the header and its rule are the --no-logo banner's, MOVED and nothing else =="
# =======================================================================================
# Drop row 1 and strip the mark from rows 2 and 3, and the intact banner must BE the
# `--no-logo` one byte for byte — so "only the position changed" is measured, on the plain
# rendering and on the coloured one alike.
OUT="$(run "$HOOK")"; n="$(head_no "$OUT")"
NL="$(run "$HOOK" --no-logo)"
assert "the --no-logo banner prints the header, then the rule, alone" \
  "$(eq "$(nth "$NL" "$(head_no "$NL")")|$(nth "$NL" "$(( $(head_no "$NL") + 1 ))")" "$HDR|$RULE")"
assert "the intact banner, minus the mark, IS that banner" \
  "$(eq "$(printf '%s\n' "$OUT" | sed -e "${n}d" -e "$((n+1))s/^$L2 //" -e "$((n+2))s/^$L3 //")" "$NL")"
COL="$(run "$HOOK" --color always)"; n="$(head_no "$COL")"
NLC="$(run "$HOOK" --color always --no-logo)"
assert "…and so it is with colour on: the mark's two spans are all that is added" \
  "$(eq "$(printf '%s\n' "$COL" | LC_ALL=C sed -e "${n}d" -e "$((n+1)),$((n+2))s/^.*${ESC}\[0m //")" "$NLC")"

# =======================================================================================
echo "== 5. the mark is the SessionStart channel's alone =="
# =======================================================================================
# BOTH SIDES, IN ONE SECTION, because the claim is a difference between two channels and
# either half alone passes on a hook that lost the mark entirely. The hook keeps it; the
# `/welcome` path — `welcome.sh`, which `exec`s that same hook — starts at the version line.
SMJ="$(strip_sgr "$(sm "$(run "$HOOK" --format json)")")"
assert "the SessionStart channel carries the mark's three rows" \
  "$([ "$(has "$L1" "$SMJ")" = 0 ] && [ "$(has "$L2" "$SMJ")" = 0 ] \
     && [ "$(has "$L3" "$SMJ")" = 0 ] && echo 0 || echo 1)"

welcome() { CLAUDE_PROJECT_DIR="$INST" bash "$SH" "$@" 2>/dev/null; }
no_logo_at_all() { # <output> -> 0 when no logo line is anywhere in it
  local o="$1"
  [ "$(has "$L1" "$o")" = 1 ] && [ "$(has "$L2" "$o")" = 1 ] \
    && [ "$(has "$L3" "$o")" = 1 ] && echo 0 || echo 1
}
# The three forms the welcome skill can run, and the relay's own two branches: a pipe with
# no NO_COLOR is the `--format md` one, and NO_COLOR hands back the plain rendering.
W="$(welcome)"
assert "the welcome path carries no logo line"   "$(no_logo_at_all "$W")"
assert "…and its first line IS the version line" \
  "$(eq "$(nth "$W" "$(head_no "$W")" | sed 's/\*\*//g' | cut -c1-5)" 'loopd')"
assert "…and it is not empty (not a vacuous pass)" "$(has 'loopd' "$W")"
NCW="$(NO_COLOR=1 CLAUDE_PROJECT_DIR="$INST" bash "$SH" 2>/dev/null)"
assert "NO_COLOR takes the other branch and carries none either" "$(no_logo_at_all "$NCW")"
assert "the explicit \`banner\` form carries none"  "$(eq "$(welcome banner)" "$W")"
assert "\`check\` carries none"  "$(no_logo_at_all "$(welcome check --instance "$INST" --template "$TPL")")"
assert "\`fix\` carries none"    "$(no_logo_at_all "$(welcome fix --instance "$INST" --template "$TPL")")"
# A FLAG THE CALLER PASSED LEAVES THE DECISION ALONE — that contract is the reason this is
# `--no-logo` on the wrapper's own branches and not a format the hook picks for itself.
assert "a caller's own --format md still gets the mark" \
  "$(plain_logo "$(welcome --format md | sed 's/\*\*//g')")"
assert "--no-logo drops them from the hook too"   "$(no_logo_at_all "$NL")"
# THE SUPERSESSION IS RECORDED WHERE THE LOGO LIVES, in one line, so the next reader of
# task-024's criterion finds the reversal in the file it is a criterion about.
assert "the hook's header records that this supersedes task-024" \
  "$(eq "$(grep -c 'SUPERSEDES task-024' "$HOOK")" 1)"
# AND THE SKILL SAYS WHY THE MARK IS ABSENT THERE, so the model relaying the output does
# not read it as a missing line and reach for a copy of its own.
assert "the welcome skill says why the logo is absent there" \
  "$(has 'the SessionStart channel alone' "$(cat "$SKILL")")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
