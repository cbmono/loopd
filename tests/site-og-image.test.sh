#!/usr/bin/env bash
#
# site-og-image.test.sh — the site's link preview names a PNG that exists, at the size the
# tags declare, by an absolute URL.
#
# WHY. A link to cbmono.github.io/loopd unfurled in Slack with an empty image box: the page
# had og:title and og:description but no og:image (2026-11-16). Unfurlers take og:image only
# as an absolute URL and do not render SVG, so the logo the site already ships
# (loopd-mark-color.svg) cannot be it. Each predicate below is one of those ways to be blank
# again: the tag missing, a relative or SVG URL, the file missing, or a size the tags do not
# match.
#
# NON-VACUOUS BY CONSTRUCTION. Each predicate also runs on a mutant carrying exactly the drift
# it exists to catch, and the mutant must go red.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PAGE="$REPO/docs/index.html"
BASE="https://cbmono.github.io/loopd/"
[ -f "$PAGE" ] || { echo "site-og-image.test: missing $PAGE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/site-og-image.XXXXXX")" \
  || { echo "site-og-image.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# meta <file> <attr> <key> — the content of the one <meta attr="key"> in <head>, or empty.
meta() {
  sed -n '1,/<\/head>/p' "$1" \
    | grep -o "<meta $2=\"$3\" content=\"[^\"]*\">" | sed -n 1p \
    | sed 's/.*content="\([^"]*\)".*/\1/'
}

# png_dims <file> — "WxH" from the IHDR chunk, or "not-png".
png_dims() {
  local sig w h
  sig="$(head -c 8 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  [ "$sig" = "89504e470d0a1a0a" ] || { echo not-png; return; }
  w="$(dd if="$1" bs=1 skip=16 count=4 2>/dev/null | od -An -tu1 | tr '\n' ' ' | awk '{print $1*16777216+$2*65536+$3*256+$4}')"
  h="$(dd if="$1" bs=1 skip=20 count=4 2>/dev/null | od -An -tu1 | tr '\n' ' ' | awk '{print $1*16777216+$2*65536+$3*256+$4}')"
  echo "${w}x${h}"
}

# verdict <page> <docs-root> — "ok", or the first reason the preview would be blank.
verdict() {
  local img tw path w h card
  img="$(meta "$1" property og:image)"
  [ -n "$img" ] || { echo no-og-image; return; }
  case "$img" in "$BASE"*) ;; *) echo og-image-not-absolute; return ;; esac
  case "$img" in *.png) ;; *) echo og-image-not-png; return ;; esac
  path="$2/${img#"$BASE"}"
  [ -f "$path" ] || { echo og-image-file-missing; return; }
  w="$(meta "$1" property og:image:width)"; h="$(meta "$1" property og:image:height)"
  [ "$(png_dims "$path")" = "${w}x${h}" ] || { echo og-image-size-mismatch; return; }
  [ "$(meta "$1" property og:image:alt)" != "" ] || { echo og-image-no-alt; return; }
  tw="$(meta "$1" name twitter:image)"
  [ "$tw" = "$img" ] || { echo twitter-image-differs; return; }
  card="$(meta "$1" name twitter:card)"
  [ "$card" = "summary_large_image" ] || { echo twitter-card-not-large; return; }
  echo ok
}

echo "site-og-image.test"
ok "the real page has a usable link preview" "$(verdict "$PAGE" "$REPO/docs")" ok
ok "the preview is 1200x630 (large-card ratio)" \
   "$(png_dims "$REPO/docs/$(meta "$PAGE" property og:image | sed "s#^$BASE##")")" 1200x630
ok "og:url is unchanged" "$(meta "$PAGE" property og:url)" "$BASE"

# Mutants: copy docs/ once, then break one thing per case.
mkdir -p "$TMP/docs/assets"
cp "$REPO/docs/assets/og-image.png" "$TMP/docs/assets/og-image.png"
mut() { # <name> <sed-expr> <expected verdict>
  sed "$2" "$PAGE" > "$TMP/page.html"
  ok "mutant: $1" "$(verdict "$TMP/page.html" "$TMP/docs")" "$3"
}
mut "og:image removed"      '/property="og:image"/d'                                   no-og-image
mut "og:image relative"     's#content="https://cbmono.github.io/loopd/assets/og-image.png"#content="assets/og-image.png"#' og-image-not-absolute
mut "og:image is the SVG"   's#assets/og-image.png">#assets/loopd-mark-color.svg">#'  og-image-not-png
mut "og:image file missing" 's#og-image.png#og-image-gone.png#g'                       og-image-file-missing
mut "declared width wrong"  's#og:image:width" content="1200"#og:image:width" content="800"#' og-image-size-mismatch
mut "twitter:card small"    's#content="summary_large_image"#content="summary"#'       twitter-card-not-large

echo "site-og-image.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
