#!/usr/bin/env bash
#
# bundle-paths.test.sh — the resolver answers the same sourced, executed and per key, and
# plugin/scripts/ spells the layout nowhere else.
#
# Exit codes: 0 clean, 1 an assertion failed, 2 the tree is not readable.
# Reasoning: ai-bridge-v3/task-031.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO/plugin/scripts/bundle-paths.sh"
SCRIPTS="$REPO/plugin/scripts"
[ -x "$RESOLVER" ] || { echo "bundle-paths.test: missing or not executable: $RESOLVER" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# The keys ai-bridge-v3/task-031 names, plus the three the triage folded in.
KEYS="AB_DIR AB_SCHEMA AB_CONVENTIONS AB_SNAPSHOT AB_AWAITING AB_LEDGER AB_INDEX AB_ROSTER
AB_STATE_DIR AB_RECEIPTS AB_MODE_DIR AB_BOARD_DIR AB_BOARD_OTHERS AB_LOCK AB_LOCK_CLAIM"

echo
echo "== 1. every key resolves, three ways =="
# shellcheck source=/dev/null
. "$RESOLVER"
for k in $KEYS; do
  sourced="${!k-__unset__}"
  ok "$k is exported when sourced"        "$([ -n "${sourced#__unset__}" ] && [ "$sourced" != "__unset__" ] && echo yes || echo no)" yes
  ok "$k agrees with the one-key form"    "$("$RESOLVER" "$k")" "$sourced"
  ok "$k agrees with the KEY=value form"  "$("$RESOLVER" | sed -n "s/^$k=//p")" "$sourced"
done
ok "an unknown key is refused"           "$("$RESOLVER" NOPE >/dev/null 2>&1; echo $?)" 1
ok "the printed set is the named set"    "$("$RESOLVER" | wc -l | tr -d ' ')" "$(echo $KEYS | wc -w | tr -d ' ')"

echo
echo "== 2. ab_expand substitutes a quoted heredoc's placeholders =="
ok "__AB_LOCK__ expands"    "$(printf '/__AB_LOCK__\n' | ab_expand)"     "/$AB_LOCK"
ok "__AB_INDEX__ expands"   "$(printf '/__AB_INDEX__\n' | ab_expand)"    "/$AB_INDEX"
ok "an unknown token is left alone" "$(printf '__AB_NOPE__\n' | ab_expand)" "__AB_NOPE__"

echo
echo "== 3. the layout is spelled in ONE file =="
# A literal assignment of one of these names is the shape that forks the layout. The
# grep is the criterion's own, narrowed to an assignment so a comment is not a failure.
NAMES='SCHEMA\.md|CONVENTIONS\.md|SNAPSHOT\.json|AWAITING\.md|\.tick-state|\.tick-receipts|\.permission-mode|\.board-live|\.tick-lock|\.board-others\.json'
spellers="$(grep -lE "^[A-Za-z_]+=\"?(\\\$AB_DIR/)?($NAMES)\"?$" "$SCRIPTS"/*.sh | xargs -n1 basename | sort | tr '\n' ' ')"
ok "only bundle-paths.sh assigns a layout literal" "$spellers" "bundle-paths.sh "

# The regression that costs a run rather than a review: a script reaches for $AB_* and
# never sourced the resolver, so `set -u` kills it on the first use.
missing=""
for f in "$SCRIPTS"/*.sh; do
  [ "$(basename "$f")" = "bundle-paths.sh" ] && continue
  grep -q '\$AB_\|\${AB_\|os.environ\["AB_\|__AB_' "$f" || continue
  grep -q 'bundle-paths.sh' "$f" || missing="$missing $(basename "$f")"
done
ok "every AB_* reader sources the resolver" "$([ -z "$missing" ] && echo none || echo "$missing")" none

# Non-vacuous: the same predicate over a copy that drops the source line must report it.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bundle-paths.XXXXXX")" || { echo "bundle-paths.test: no temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
grep -v 'bundle-paths.sh' "$SCRIPTS/tick-delta.sh" > "$TMP/tick-delta.sh"
ok "…and it reports a script that dropped it" \
   "$(grep -q 'bundle-paths.sh' "$TMP/tick-delta.sh" && echo sourced || echo missing)" missing

echo
echo "== 4. the 3.0 layout: every plugin-owned path is under .loopd/ =="
ok "the directory is .loopd" "$AB_DIR" ".loopd"
under=""
for k in $KEYS; do
  [ "$k" = AB_DIR ] && continue
  case "${!k}" in "$AB_DIR"/*) ;; *) under="$under $k" ;; esac
done
ok "every other key is under it" "$([ -z "$under" ] && echo all || echo "$under")" all

echo
echo "== 5. the seed stays FLAT and the stamp maps it =="
ok "SCHEMA.md maps"            "$(ab_seed_dest SCHEMA.md)"           "$AB_SCHEMA"
ok "agents/index.md maps"      "$(ab_seed_dest agents/index.md)"     "$AB_ROSTER"
ok "log.md maps"               "$(ab_seed_dest log.md)"              "$AB_LEDGER"
ok "CLAUDE.md stays at the root" "$(ab_seed_dest CLAUDE.md)"         "CLAUDE.md"
# The KB index is the human's curated surface and shares a basename with the derived one.
ok "knowledge/index.md is untouched" "$(ab_seed_dest knowledge/index.md)" "knowledge/index.md"

echo
echo "== 6. an un-migrated bundle is DETECTED, never half-read =="
B="$TMP/bundle"; mkdir -p "$B/$AB_DIR"
ok "an empty dir is not a bundle"  "$(ab_is_bundle "$B" && echo yes || echo no)" no
: > "$B/instance.config.json"
ok "instance.config.json alone is the marker" "$(ab_is_bundle "$B" && echo yes || echo no)" yes
ok "a migrated bundle is not flagged" "$(ab_unmigrated "$B" && echo yes || echo no)" no
: > "$B/SCHEMA.md"
ok "a root SCHEMA.md is flagged"   "$(ab_unmigrated "$B" && echo yes || echo no)" yes
notice="$(ab_unmigrated_notice "$B" 2>&1)"
ok "the notice names the file"     "$(printf '%s' "$notice" | grep -c "SCHEMA.md -> $AB_SCHEMA")" 1
# The FLAGS, not just the script name: this assertion was `grep -c migrate-bundle.sh` and
# stayed green while the notice printed a --layout the parser refuses.
ok "…and the one command that fixes it" "$(printf '%s' "$notice" | grep -c 'migrate-bundle.sh --apply$')" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
