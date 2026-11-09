#!/usr/bin/env bash
#
# init-migrate-hint.test.sh — when validate-bundle.sh fails, `/<plugin>:init` step 6 runs
# migrate-bundle.sh in REPORT mode and prints `<n> schema errors, <m> fixable: <path>/
# migrate-bundle.sh --apply`, instead of pointing at a `welcome check` row that does not
# exist. A sibling bundle showed 354 validator errors, 307 of them a missing `provenance`
# that `--apply` fixes, with no fix named (docs/conventions.md §9).
#
# The two numbers are parsed from the summary lines of plugin/scripts/validate-bundle.sh and
# plugin/scripts/migrate-bundle.sh, so the exact `4 schema errors, 3 fixable` line below is
# the drift test for both formats: a reworded summary falls back to the bare pointer and
# fails these assertions.
#
# The fixture is a git repo whose Findings are committed by a nameable author in their own
# commit: an uncommitted file, or one inside the stamp's bulk commit, is `unknowable` to
# migrate-bundle.sh and would read `0 fixable`.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/plugin/scripts/init-bundle.sh"
BIN_DIR="$REPO/plugin/scripts"
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/initmigratehint.XXXXXX")" || {
  echo "init-migrate-hint.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { if grep -qF -e "$2" <<<"$1"; then echo yes; else echo no; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/home"; printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"
stamp() { ( cd "$TMP" && PATH="$BIN:$PATH" HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/home/.claude" \
            GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none" \
            bash "$INIT" "$1" </dev/null 2>&1 ); }
as_pat() { git -C "$B" -c user.name="Pat Example" -c user.email=pat@example.com "$@"; }
sums() { ( cd "$B" && find knowledge projects -type f -print0 | sort -z | xargs -0 cksum ); }
finding() { # <file> [extra frontmatter line]
  printf -- '---\ntype: Finding\ntitle: %s\nstatus: current\n%stimestamp: 2026-01-01T00:00:00Z\n---\nbody\n' \
    "$(basename "$1" .md)" "${2:+$2$'\n'}" > "$B/knowledge/findings/$1"; }

B="$TMP/bundle"
out="$(stamp "$B")"; rc=$?
ok "a first stamp succeeds"                                  "$rc" 0
ok "…and a clean bundle gets no schema note"                 "$(has "$out" 'schema errors')" no
as_pat init -q -b main && as_pat add -A && as_pat commit -qm stamp

finding f1.md; finding f2.md; finding f3.md
finding f4.md 'provenance: robot'   # an error no migration fixes: errors ≠ fixable
( cd "$B" && bash "$BIN_DIR/build-kb-index.sh" >/dev/null 2>&1 )
as_pat add -A && as_pat commit -qm findings
before="$(sums)"

echo "== 3 Findings missing provenance: init names the count and the command =="
out="$(stamp "$B")"; rc=$?
ok "the re-stamp succeeds"                                   "$rc" 0
ok "…prints both numbers and the apply command"              "$(has "$out" "Note: 4 schema errors, 3 fixable: $BIN_DIR/migrate-bundle.sh --apply")" yes
ok "…on exactly one line"                                    "$(grep -c 'schema errors' <<<"$out")" 1
ok "…and says where to run it"                               "$(has "$out" "from $B; see every error with: bash $BIN_DIR/validate-bundle.sh")" yes
ok "…never the unparsed fallback"                            "$(has "$out" 'this bundle has schema errors')" no
ok "…never a welcome check pointer"                          "$(has "$out" 'welcome check')" no
ok "…no mount note on an unmounted bundle"                   "$(has "$out" 'mounted')" no
ok "knowledge/ and projects/ are byte-identical (cksum)"     "$([ "$(sums)" = "$before" ] && echo same || echo CHANGED)" same
ok "…and git sees no change there"                           "$(as_pat status --porcelain -- knowledge projects | wc -l | tr -d ' ')" 0

echo "== a mounted knowledge/: migrate skips it, and the line carries the count =="
mkdir -p "$B/$AB_DIR/kb.git"
out="$(stamp "$B")"
ok "the line names 0 fixable and the skipped count"          "$(has "$out" 'Note: 4 schema errors (4 knowledge/ documents skipped: mounted, repair them from that repository), 0 fixable')" yes
ok "…and offers no --apply that would fix nothing here"      "$(has "$out" 'migrate-bundle.sh --apply')" no
ok "…and still writes nothing"                               "$([ "$(sums)" = "$before" ] && echo same || echo CHANGED)" same
rmdir "$B/$AB_DIR/kb.git"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
