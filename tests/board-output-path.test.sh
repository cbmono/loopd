#!/usr/bin/env bash
#
# board-output-path.test.sh — WHERE the board lands, which is the whole of this file.
#
# After the 3.0 layout moved plugin-owned paths under `.loopd/`, the renderer's
# default and two shipped instruction files still named the pre-3.0 root path. The
# resolver was right the whole time; the callers passed an explicit `--out` that
# overrode it, so a tick following its own instructions rendered to `./.board-live/`
# while `watch-board.sh` and `board-serve.sh` read `$AB_BOARD_DIR`. Two consequences,
# both measured on a live bundle:
#
#   · THE VIEWER SHOWED A STALE PAGE. The root copy was two hours fresher than the one
#     `board serve` reads, and nothing said so — the render reported success each time.
#   · THE DERIVED PAGE WAS NOT IGNORED. `/.loopd/.board-live/` is gitignored;
#     `/.board-live/` is not, so the page accumulated as untracked files at the bundle
#     root, which is exactly what the local-render route was introduced to stop.
#
# So this file asserts the default resolves to AB_BOARD_DIR, and — the part that keeps
# it fixed — that no shipped file hands the renderer the old literal again.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
BUILD="$TPL/plugin/scripts/build-board.sh"
PATHS="$TPL/plugin/scripts/bundle-paths.sh"
[ -f "$BUILD" ] || { echo "board-output-path.test: no build-board.sh at $BUILD" >&2; exit 2; }

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

BOARD_DIR="$(bash "$PATHS" AB_BOARD_DIR)"
ok "the resolver still answers AB_BOARD_DIR" "$BOARD_DIR" ".loopd/.board-live"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-output-path.XXXXXX")" || {
  echo "board-output-path.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
B="$TMP/bundle"; mkdir -p "$B/.loopd"
cd "$B"
echo '{ "org": "x", "reposRoot": "/tmp", "board": true }' > instance.config.json
touch SCHEMA.md .loopd/SCHEMA.md
bash "$TPL/plugin/scripts/write-snapshot.sh" --quiet 2>/dev/null || true
[ -f .loopd/SNAPSHOT.json ] || printf '{"instance":"bundle","generated":"2026-01-01T00:00:00Z","projects":[],"awaiting":[]}\n' > .loopd/SNAPSHOT.json

echo
echo "== the default output lands in AB_BOARD_DIR =="
OUT_LINE="$(bash "$BUILD" --standalone . 2>&1 | tail -1)"
ok "the renderer reports the resolved path" \
   "$(printf '%s' "$OUT_LINE" | grep -c "$BOARD_DIR/board.html" | tr -d ' ')" 1
ok "…the file is there"           "$([ -f "$BOARD_DIR/board.html" ] && echo yes || echo no)" yes
ok "…and NOT at the bundle root"  "$([ -e board.html ] && echo yes || echo no)" no
ok "…nor in a root .board-live/"  "$([ -e .board-live ] && echo yes || echo no)" no

echo
echo "== no shipped file hands the renderer the pre-3.0 literal =="
# The regression is a copied command line, not a code path, so the guard is a grep over
# what ships. `--out` with the old root path is the exact shape that broke it.
STALE="$(grep -rn -- '--out[= ]\.board-live' "$TPL/plugin" 2>/dev/null | grep -v '^Binary' || true)"
ok "no --out .board-live in plugin/" "$(printf '%s' "$STALE" | grep -c . | tr -d ' ')" 0
[ -n "$STALE" ] && printf '        %s\n' "$STALE"

# watch-board and board-serve must keep resolving it rather than hardcoding one.
ok "watch-board.sh uses AB_BOARD_DIR" \
   "$(grep -c 'OUT_DIR="\$AB_BOARD_DIR"' "$TPL/plugin/scripts/watch-board.sh" | tr -d ' ')" 1
ok "board-serve.sh uses AB_BOARD_DIR" \
   "$(grep -c 'OUT_DIR="\$AB_BOARD_DIR"' "$TPL/plugin/scripts/board-serve.sh" | tr -d ' ')" 1

echo
echo "== the board dir is spelled ONCE in what a stamped .gitignore inherits =="
# init-bundle.sh appends the ignore pattern when it cannot find one, and "find" is a
# grep for the literal — so a COMMENT repeating that literal reads as the pattern and
# the append is skipped, or the merge restores it and the line lands twice (#251, where
# rewording one comment took the count 1 -> 2). The literal belongs to bundle-paths.sh;
# everything else names the variable.
ok "seed/.gitignore names it once" \
   "$(grep -cF "$BOARD_DIR" "$TPL/plugin/seed/.gitignore" | tr -d ' ')" 1
ok "…and that one line IS the pattern" \
   "$(grep -F "$BOARD_DIR" "$TPL/plugin/seed/.gitignore")" "/$BOARD_DIR/"
ok "init-bundle.sh spells it nowhere" \
   "$(grep -cF "$BOARD_DIR" "$TPL/plugin/scripts/init-bundle.sh" | tr -d ' ')" 0

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
