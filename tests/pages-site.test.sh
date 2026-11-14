#!/usr/bin/env bash
#
# pages-site.test.sh — the GitHub Pages site under docs/ stays on-palette, self-contained
# and on slugs spelled under the plugin's manifest name (loopd/task-006, task-007).
#
# Every check is a function over a site directory, run once against docs/ (must pass) and
# once against a mutant copy carrying the exact regression it exists for (must fail) — a
# check that only ever passes cannot tell a clean page from an unread one.
#
# The palette is the redesign handover's section 3 tokens plus the eight hexes and five
# rgba() values its approved reference uses outside them (loopd-website-redesign, Q6); the
# handover lives in the control panel, so the list is typed here. The page is index.html
# plus every local stylesheet it links, and a url() resolves against its own stylesheet.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/tools/plugin-name.sh"
SITE="$REPO/docs"
for f in "$SITE/index.html" "$SITE/assets/site.css" "$SITE/assets/loopd-mark-color.svg"; do
  [ -f "$f" ] || { echo "pages-site.test: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "pages-site.test: python3 builds the mutants" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pages-site.XXXXXX")" || {
  echo "pages-site.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$1" = "$2" ]; then printf '  PASS  %s\n' "$3"; pass=$((pass+1));
       else printf '  FAIL  %s (got %s, want %s)\n' "$3" "$1" "$2"; fail=$((fail+1)); fi; }
rc() { "$@" >/dev/null 2>&1 && echo pass || echo fail; }

TOKEN_HEXES='#0b0d12 #131720 #141925 #0f1219 #262d3d #3a4358 #1c2230 #e9ecf3 #a3acbf #8d96aa
#7b8498 #5b9cf5 #2c3a52 #3b5f94 #16203a #ff7ab8 #1a1420 #21162a #160f1a #6b3a55
#ffffff #4a5368 #1e2432 #3a2533 #2a1826 #1d2330 #c3cad8 #2c3445'
RGBAS='rgba(0,0,0,.25) rgba(0,0,0,.5) rgba(255,122,184,.08) rgba(255,122,184,.14) rgba(255,122,184,.25)'

# index.html, then each local stylesheet it links; no stylesheet at all fails every reader.
pages() {
  local css found=0
  echo "$1/index.html"
  for css in $(grep -oE '<link rel="stylesheet" href="[^"]*"' "$1/index.html" | sed -E 's/.*href="//; s/"$//'); do
    case "$css" in https://*|http://*|/*) continue ;; esac
    [ -f "$1/$css" ] && { echo "$1/$css"; found=1; }
  done
  [ "$found" = 1 ]
}
# FILES=(those paths), one element each so a path with a space stays whole; fails on no stylesheet.
load_pages() {
  local l; FILES=()
  while IFS= read -r l; do [ -n "$l" ] && FILES+=("$l"); done <<< "$(pages "$1")"
  [ "${#FILES[@]}" -ge 2 ]
}

check_hex() {
  local h bad=0
  load_pages "$1" || { echo "no local stylesheet"; return 1; }
  for h in $(grep -hoE '#[0-9a-fA-F]{6}' "${FILES[@]}" | tr 'A-F' 'a-f' | sort -u); do
    case " $(echo $TOKEN_HEXES) " in *" $h "*) ;; *) echo "off-palette $h"; bad=1 ;; esac
  done
  return "$bad"
}

check_rgba() {
  local v bad=0
  load_pages "$1" || { echo "no local stylesheet"; return 1; }
  for v in $(grep -hoE 'rgba\([^)]*\)' "${FILES[@]}" | tr -d ' ' | sort -u); do
    case " $RGBAS " in *" $v "*) ;; *) echo "unlisted $v"; bad=1 ;; esac
  done
  return "$bad"
}

check_slugs() {
  local cmds; cmds="$(ls "$REPO/plugin/skills" | tr '\n' '|' | sed 's/|$//')"
  [ "$(grep -oE "/[a-z][a-z0-9-]*:(${cmds})([^a-z-]|\$)" "$1/index.html" | grep -vc "^/${PN}:")" = 0 ] \
    && grep -qF "${PN}@${PMK}" "$1/index.html"
}

# Every src/href/url() that is not a remote URL or a fragment is relative and resolves
# against the directory of the file that names it; url() is read quoted either way or bare.
check_refs() {
  local ref path bad=0 n=0 f
  load_pages "$1" || { echo "no local stylesheet"; return 1; }
  for f in "${FILES[@]}"; do
    while IFS= read -r ref; do
      case "$ref" in ''|https://*|http://*|mailto:*|'#'*) continue ;; esac
      n=$((n+1))
      case "$ref" in /*|//*) echo "root-absolute $ref"; bad=1; continue ;; esac
      path="$(dirname "$f")/${ref%%[#?]*}"
      [ -e "$path" ] || { echo "unresolved $ref in ${f##*/}"; bad=1; }
    done <<< "$(grep -oE "(src|href)=\"[^\"]*\"|url\\([^)]*\\)" "$f" \
                 | sed -E "s/^(src|href)=\"//; s/\"\$//; s/^url\\([[:space:]]*[\"']?//; s/[\"']?[[:space:]]*\\)\$//")"
  done
  [ "$n" -gt 0 ] || { echo "no local refs found"; bad=1; }
  return "$bad"
}

check_nojekyll() { [ -f "$1/.nojekyll" ]; }

check_fonts() {
  local d
  load_pages "$1" || return 1
  ! grep -qiE 'fonts\.(googleapis|gstatic)\.com' "${FILES[@]}" || return 1
  grep -qE "@font-face\{font-family:'Inter';" "${FILES[@]}" || return 1
  grep -qE "@font-face\{font-family:'JetBrains Mono';" "${FILES[@]}" || return 1
  for d in "$1/assets/fonts/inter" "$1/assets/fonts/jetbrains-mono"; do
    ls "$d"/*.woff2 >/dev/null 2>&1 || return 1
    grep -lqi 'SIL Open Font License' "$d"/*.txt 2>/dev/null || return 1
  done
}

# Both renderings of the loop diagram carry the dashed retry: a blue edge in the wide
# stage's SVG whose dash array starts with a positive length (not none, not 0), and the
# stacked list's dashed fix tag.
check_retry() {
  load_pages "$1" || return 1
  grep -qE '<path class="edge" [^>]*stroke-dasharray="[0-9.]*[1-9][0-9.]*[ ,"]' "$1/index.html" \
    && grep -qE '\.flow-svg \.edge\{stroke:var\(--blue\)\}' "${FILES[@]}" \
    && grep -q 'class="fix-tag"' "$1/index.html" \
    && grep -qE '\.fix-tag\{[^}]*dashed' "${FILES[@]}"
}

check_c2pa() {
  local f
  for f in "$1"/assets/*.svg; do grep -q '<c2pa:manifest>' "$f" || return 1; done
}

CHECKS="hex rgba slugs refs nojekyll fonts retry c2pa"

echo "== the published site passes every check"
for c in $CHECKS; do ok "$(rc "check_$c" "$SITE")" pass "docs/ — $c"; done
check_refs "$SITE" >/dev/null || check_refs "$SITE"
check_hex "$SITE" >/dev/null || check_hex "$SITE"

echo "== each check fails on the regression it exists for"
mutant() { rm -rf "$TMP/site"; mkdir -p "$TMP/site"; cp -R "$SITE/index.html" "$SITE/.nojekyll" "$SITE/assets" "$TMP/site/"; }
# edit <anchor> <replacement> [file under the site, default index.html]
edit() { python3 - "$TMP/site/${3:-index.html}" "$1" "$2" <<'PY'
import sys
p,a,b=sys.argv[1:]; s=open(p,encoding='utf-8').read()
assert a in s, "mutation anchor missing: "+a
open(p,'w',encoding='utf-8').write(s.replace(a,b,1))
PY
}
M="$TMP/site"
CSS=assets/site.css

mutant; edit ':root{' ':root{--x:#a9b1c2;' "$CSS"
ok "$(rc check_hex "$M")" fail "hex — cli-theme.json's terminal-only #a9b1c2 in the stylesheet is refused"
mutant; edit ':root{' ':root{--x:#5ea2ff;' "$CSS"
ok "$(rc check_hex "$M")" fail "hex — the retired site blue #5ea2ff is refused"
mutant; edit '</main>' '<p style="color:#a9b1c2">x</p></main>'
ok "$(rc check_hex "$M")" fail "hex — an off-palette hex inline in index.html is refused"
mutant; edit '<link rel="stylesheet" href="assets/site.css">' ''
ok "$(rc check_hex "$M")" fail "hex — a page linking no stylesheet is refused, not read as clean"
mutant; edit ':root{' ':root{--x:0 24px 80px rgba(0,0,0,.6);' "$CSS"
ok "$(rc check_rgba "$M")" fail "rgba — an unlisted rgba() in the stylesheet is refused"
mutant; edit '</main>' '<p style="box-shadow:0 0 1px rgba(0,0,0,.6)">x</p></main>'
ok "$(rc check_rgba "$M")" fail "rgba — an unlisted rgba() in index.html is refused"
mutant; edit '</main>' "<code>/not-${PN}:dispatch</code></main>"
ok "$(rc check_slugs "$M")" fail "slugs — a slug under another name is refused"
mutant; sed "s/${PN}@${PMK}/not-${PN}@not-${PMK}/g" "$SITE/index.html" > "$M/index.html"
ok "$(rc check_slugs "$M")" fail "slugs — losing ${PN}@${PMK} is refused"
mutant; edit 'src="assets/loopd-mark-color.svg"' 'src="/assets/loopd-mark-color.svg"'
ok "$(rc check_refs "$M")" fail "refs — a root-absolute src is refused"
mutant; edit 'src="assets/loopd-mark-color.svg"' 'src="assets/loopd-hero.png"'
ok "$(rc check_refs "$M")" fail "refs — a relative src to a missing file is refused"
mutant; edit 'url("fonts/inter/Inter-Medium.woff2")' 'url("assets/fonts/inter/Inter-Medium.woff2")' "$CSS"
ok "$(rc check_refs "$M")" fail "refs — a stylesheet url() resolved against the page, not the stylesheet, is refused"
mutant; edit 'url("fonts/inter/Inter-Medium.woff2")' 'url("/fonts/inter/Inter-Medium.woff2")' "$CSS"
ok "$(rc check_refs "$M")" fail "refs — a root-absolute url() in the stylesheet is refused"
mutant; edit 'url("fonts/inter/Inter-Medium.woff2")' "url('fonts/inter/Missing.woff2')" "$CSS"
ok "$(rc check_refs "$M")" fail "refs — a single-quoted url() to a missing file is refused"
mutant; edit 'url("fonts/inter/Inter-Medium.woff2")' 'url(fonts/inter/Missing.woff2)' "$CSS"
ok "$(rc check_refs "$M")" fail "refs — an unquoted url() to a missing file is refused"
mutant; edit 'url("fonts/inter/Inter-Medium.woff2")' "url( 'fonts/inter/Inter-Medium.woff2' )" "$CSS"
ok "$(rc check_refs "$M")" pass "refs — a single-quoted url() to a real file still resolves"
mutant; rm -f "$M/.nojekyll"
ok "$(rc check_nojekyll "$M")" fail "nojekyll — a missing docs/.nojekyll is refused"
mutant; edit '</head>' '<link href="https://fonts.googleapis.com/css2?family=Inter" rel="stylesheet"></head>'
ok "$(rc check_fonts "$M")" fail "fonts — linking Google Fonts is refused"
mutant; edit '@font-face' '@import url("https://fonts.googleapis.com/css2?family=Inter");@font-face' "$CSS"
ok "$(rc check_fonts "$M")" fail "fonts — importing Google Fonts from the stylesheet is refused"
mutant; sed -E "/@font-face\{font-family:'Inter';/d" "$SITE/$CSS" > "$M/$CSS"
ok "$(rc check_fonts "$M")" fail "fonts — a stylesheet with no self-hosted Inter face is refused"
mutant; rm -f "$M"/assets/fonts/jetbrains-mono/*.txt
ok "$(rc check_fonts "$M")" fail "fonts — a font directory without its OFL is refused"
mutant; python3 - "$M/index.html" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8').write(re.sub(r' stroke-dasharray="[^"]*"','',s))
PY
ok "$(rc check_retry "$M")" fail "retry — a wide diagram with no dashed edge is refused"
mutant; edit 'stroke-dasharray="5 5"' 'stroke-dasharray="none"'
ok "$(rc check_retry "$M")" fail "retry — a dash array of none is refused"
mutant; edit 'stroke-dasharray="5 5"' 'stroke-dasharray="0"'
ok "$(rc check_retry "$M")" fail "retry — a dash array of 0 is refused"
mutant; edit '.fix-tag{border:1.5px dashed' '.fix-tag{border:1.5px solid' "$CSS"
ok "$(rc check_retry "$M")" fail "retry — a stacked list whose fix tag is not dashed is refused"
mutant; edit '.flow-svg .edge{stroke:var(--blue)}' '.flow-svg .edge{stroke:var(--pink)}' "$CSS"
ok "$(rc check_retry "$M")" fail "retry — a retry edge that is not blue is refused"
mutant; sed -E 's#<metadata>.*</metadata>##' "$SITE/assets/loopd-mark-color.svg" > "$M/assets/loopd-mark-color.svg"
ok "$(rc check_c2pa "$M")" fail "c2pa — an SVG stripped of its manifest is refused"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
