#!/usr/bin/env bash
#
# init-refuses-pre-rename.test.sh — a bundle still holding its state in the pre-3.3
# directory is REFUSED by the stamp, and named by the detector, the banner's notice and
# the welcome check: `plugin/scripts/init-bundle.sh`, `bundle-paths.sh`, `welcome.sh`.
#
# THE FAILURE THIS EXISTS FOR, MEASURED 2026-10-05 ON THREE BUNDLES. The plugin was updated
# to 3.3.0 before `migrate-bundle.sh` had moved the state directory. Nothing said so. The
# next stamp found every file under the new directory absent, so it seeded them: an empty
# ledger beside the real one, the knowledge mount invisible, and the migration then stopped
# because its destination existed. Each bundle was recovered by hand.
#
# BOTH DIRECTIONS, because a refusal that also fired on a healthy bundle would be switched
# off: the pre-rename bundle is refused with NOTHING written, and a first stamp, a migrated
# bundle and a bundle that is not one are all left alone.
# Fixtures live under mktemp; ok() compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/plugin/scripts/init-bundle.sh"
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/initprerename.XXXXXX")" || {
  echo "init-refuses-pre-rename.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { if grep -qF -e "$2" <<<"$1"; then echo yes; else echo no; fi; }

# A stamp with an isolated HOME and config dir, and a `gh` that fails: nothing here may
# reach the network or the operator's own Claude Code configuration.
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/home"; printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"
stamp() { ( cd "$TMP" && PATH="$BIN:$PATH" HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/home/.claude" \
            bash "$INIT" "$1" </dev/null 2>&1 ); }
listing() { ( cd "$1" && find . -not -path './.git/*' | sort ); }

echo "== a pre-rename bundle is refused, and NOTHING is written =="
B="$TMP/old"; mkdir -p "$B/$AB_DIR_BEFORE"
: > "$B/instance.config.json"; echo ledger > "$B/$AB_DIR_BEFORE/log.md"
before="$(listing "$B")"
out="$(stamp "$B")"; rc=$?
ok "the stamp exits 2"                               "$rc" 2
ok "…names the directory it found"                   "$(has "$out" "still keeps its state in $AB_DIR_BEFORE/")" yes
ok "…says nothing was written"                       "$(has "$out" 'Nothing was written')" yes
# --layout-only, not --apply: the content repairs are a separate decision, and on a bundle
# with a mounted knowledge/ they landed as hundreds of edits in another repository's tree.
ok "…prints the report command, layout only"         "$(grep -cE '^ +migrate-bundle\.sh --layout-only$' <<<"$out")" 1
ok "…and the apply command, flags and all"           "$(grep -cE '^ +migrate-bundle\.sh --layout-only --apply$' <<<"$out")" 1
ok "…and never the content pass"                     "$(grep -cE 'migrate-bundle\.sh( --apply)?$' <<<"$out")" 0
ok "…and the tree is exactly as it was"              "$([ "$(listing "$B")" = "$before" ] && echo same || echo CHANGED)" same
ok "…in particular no second state directory"        "$([ -e "$B/$AB_DIR" ] && echo made || echo none)" none
ok "…and the real ledger is untouched"               "$(cat "$B/$AB_DIR_BEFORE/log.md")" ledger

echo "== the half-stamped shape (both directories) is refused too, and says which to move =="
H="$TMP/half"; mkdir -p "$H/$AB_DIR_BEFORE" "$H/$AB_DIR"; : > "$H/instance.config.json"
out="$(stamp "$H")"; rc=$?
ok "the stamp exits 2"                               "$rc" 2
ok "…and names the stray new directory"              "$(has "$out" "$AB_DIR/ exists too")" yes

echo "== the allowed neighbours: none of these is refused =="
N="$TMP/new"
out="$(stamp "$N")"; rc=$?
ok "a FIRST stamp of an absent directory still works" "$rc" 0
ok "…and seeds the state directory"                  "$([ -f "$N/$AB_SCHEMA" ] && echo yes || echo no)" yes
out="$(stamp "$N")"; rc=$?
ok "a re-stamp of that migrated bundle still works"  "$rc" 0
ok "…with no refusal in its output"                  "$(has "$out" 'still keeps its state')" no
# Not stamped: a stamp would MAKE it a bundle. What matters is that the name alone is not
# what the refusal keys on — instance.config.json is, as everywhere else.
P="$TMP/plain"; mkdir -p "$P/$AB_DIR_BEFORE"

echo "== the detector and its notice, which the session banner prints =="
ok "the pre-rename bundle reads as unmigrated"       "$(ab_unmigrated "$B" && echo yes || echo no)" yes
ok "…the migrated one does not"                      "$(ab_unmigrated "$N" && echo yes || echo no)" no
ok "…nor does a non-bundle holding the old name"     "$(ab_unmigrated "$P" && echo yes || echo no)" no
notice="$(ab_unmigrated_notice "$B" 2>&1)"
ok "the notice names the move"                       "$(has "$notice" "$AB_DIR_BEFORE/ -> $AB_DIR/")" yes
ok "…and the command, flags and all"                 "$(grep -cE 'migrate-bundle\.sh --layout-only --apply$' <<<"$notice")" 1
ok "…and stays quiet about a stray directory that is not there" "$(has "$notice" 'exists too')" no
ok "…but names it in the half-stamped shape"         "$(has "$(ab_unmigrated_notice "$H" 2>&1)" 'exists too')" yes

echo "== the welcome check =="
wout="$( cd "$B" && PATH="$BIN:$PATH" HOME="$TMP/home" bash "$REPO/plugin/scripts/welcome.sh" check </dev/null 2>&1 )"
ok "check names the directory"                       "$(has "$wout" "still keeps its state in $AB_DIR_BEFORE/")" yes
ok "…and the move"                                   "$(has "$wout" "$AB_DIR_BEFORE/ -> $AB_DIR/")" yes

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
