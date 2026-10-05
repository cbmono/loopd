#!/usr/bin/env bash
#
# bundle-paths.sh — the one place a bundle's layout is spelled.
#
#   . "$(dirname "$0")/bundle-paths.sh"   sourced: exports AB_*, each RELATIVE to a
#                                         bundle root, so a caller composes "$root/$AB_X"
#   bundle-paths.sh                       prints KEY=value, one per line
#   bundle-paths.sh AB_SCHEMA             prints one value
#
# Exit: 0 ok, 1 no such key. Reasoning: ai-bridge-v3/task-031.

AB_DIR=".loopd"
AB_SCHEMA="$AB_DIR/SCHEMA.md"
AB_CONVENTIONS="$AB_DIR/CONVENTIONS.md"
AB_SNAPSHOT="$AB_DIR/SNAPSHOT.json"
AB_AWAITING="$AB_DIR/AWAITING.md"
AB_LEDGER="$AB_DIR/log.md"
AB_INDEX="$AB_DIR/index.md"
AB_ROSTER="$AB_DIR/agents/index.md"
# A FILE, not a directory, despite the name — tick-delta.sh writes one fingerprint line
# to it. The key is named in ai-bridge-v3/task-031's criteria, so it is spelled as filed.
AB_STATE_DIR="$AB_DIR/.tick-state"
# A DIRECTORY, unlike the fingerprint above: one file per PR and head (ai-bridge-v3/task-044).
AB_RECEIPTS="$AB_DIR/.tick-receipts"
AB_MODE_DIR="$AB_DIR/.permission-mode"
AB_BOARD_DIR="$AB_DIR/.board-live"
AB_BOARD_OTHERS="$AB_DIR/.board-others.json"
AB_LOCK="$AB_DIR/.tick-lock"
AB_LOCK_CLAIM="$AB_DIR/.tick-lock.claim"

# The pre-3.0 root spellings, as `<old>:<new>` pairs in the order migrate-bundle.sh moves
# them. One list, so the migration, the un-migrated detector and the harnesses agree on
# what moved without any of them re-deriving it.
AB_MOVES="SCHEMA.md:$AB_SCHEMA CONVENTIONS.md:$AB_CONVENTIONS log.md:$AB_LEDGER \
agents/index.md:$AB_ROSTER AWAITING.md:$AB_AWAITING SNAPSHOT.json:$AB_SNAPSHOT \
index.md:$AB_INDEX .tick-state:$AB_STATE_DIR .board-live:$AB_BOARD_DIR \
.board-others.json:$AB_BOARD_OTHERS"

export AB_DIR AB_SCHEMA AB_CONVENTIONS AB_SNAPSHOT AB_AWAITING AB_LEDGER AB_INDEX AB_ROSTER
export AB_STATE_DIR AB_RECEIPTS AB_MODE_DIR AB_BOARD_DIR AB_BOARD_OTHERS AB_LOCK AB_LOCK_CLAIM AB_MOVES

AB_KEYS="AB_DIR AB_SCHEMA AB_CONVENTIONS AB_SNAPSHOT AB_AWAITING AB_LEDGER AB_INDEX AB_ROSTER \
AB_STATE_DIR AB_RECEIPTS AB_MODE_DIR AB_BOARD_DIR AB_BOARD_OTHERS AB_LOCK AB_LOCK_CLAIM"
export AB_KEYS

# Is <root> a bundle, and has it been migrated to the 3.0 layout?
#
# The marker is instance.config.json ALONE. It used to be `SCHEMA.md + instance.config.json`
# in ten scripts and both hooks, and every one of those readers treats "not a bundle" as
# silence — so with SCHEMA.md moved, an un-migrated bundle would read as a switched-off one
# and no reader would say why.
ab_is_bundle() { [ -f "${1:-.}/instance.config.json" ]; }

# A bundle's GROUP — the short name the board, the terminal board and the seeded
# `<group>.code-workspace` all label it by. `group` in its TRACKED instance.config.json
# (a shared fact, so never per-machine), else the directory name minus a bundle prefix.
#
# CONFIG FIRST is the whole point: with the name as the only source, renaming a bundle
# directory renames the bundle everywhere and the KB indexer stops recognising it.
# BOTH PREFIXES, because both exist — the bundle repos were renamed `_ai-bridge-*` ->
# `_loopd-*` while the local directories were not, and the fallback has to stay right on
# either side of that. The list is exported so the two python renderers read it from here
# rather than carrying a third and fourth copy of the literal.
AB_BUNDLE_PREFIXES="_ai-bridge- _loopd-"
export AB_BUNDLE_PREFIXES

ab_group() { # [<bundle root>] — prints the group, always something
  local root="${1:-.}" g name p
  # Parsed, never grepped: a text match takes a NESTED "group" (a `people` entry, say)
  # and disagrees with the board renderers' json read. No python3 => the name fallback.
  g="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
g=d.get("group") if isinstance(d,dict) else None
print(g if isinstance(g,str) else "")' "$root/instance.config.json" 2>/dev/null)"
  if [ -n "$g" ]; then printf '%s\n' "$g"; return 0; fi
  name="$(cd "$root" 2>/dev/null && pwd || printf '%s' "$root")"
  name="${name##*/}"
  for p in $AB_BUNDLE_PREFIXES; do
    case "$name" in "$p"?*) printf '%s\n' "${name#"$p"}"; return 0 ;; esac
  done
  printf '%s\n' "$name"
}

# Every AB_* path now has a PARENT DIRECTORY, which the pre-3.0 root spellings did not.
# A writer that skipped this reported "the instance root is not writable" on a perfectly
# writable bundle, so it is the resolver's job rather than each caller's.
ab_ensure_dir() { # <root>
  mkdir -p "${1:-.}/$AB_DIR" 2>/dev/null
}

# THE SEED STAYS FLAT; this is the mapping onto the bundle.
#
# `plugin/seed/` ships `SCHEMA.md` and friends at its top level and keeps `seed-base/`
# where it is. Nesting the seed instead would re-arm the documented gitignore trap — a
# `/.loopd/index.md` line in the seed's own `.gitignore` hides the seed's own file.
ab_seed_dest() { # <seed-relative path> — where the stamp puts it
  local pair
  for pair in $AB_MOVES; do
    [ "$1" = "${pair%%:*}" ] && { printf '%s' "${pair#*:}"; return 0; }
  done
  printf '%s' "$1"
}

ab_unmigrated() { # <root> — a bundle still carrying plugin files at its root
  local r="${1:-.}" pair
  ab_is_bundle "$r" || return 1
  for pair in $AB_MOVES; do
    [ -e "$r/${pair%%:*}" ] && return 0
  done
  return 1
}

# THE ONE FORM an operator-facing "run this" notice takes, and the reason it is a function:
# its call sites are the inventory tests/printed-commands.test.sh probes, so the script and
# its flags stay separate literal words instead of being welded into a sentence.
ab_say_run() { # <lead> <script> [arg...] — on STDOUT; redirect at the call site
  local lead="$1"; shift
  printf '%s %s\n' "$lead" "$*"
}

ab_unmigrated_notice() { # <root> — names what is still at the root, and the one fix
  local r="${1:-.}" pair old
  echo "loopd: this bundle still has plugin-owned files at its root:" >&2
  for pair in $AB_MOVES; do
    old="${pair%%:*}"; [ -e "$r/$old" ] && echo "             $old -> ${pair#*:}" >&2
  done
  ab_say_run "           Fix it with:" migrate-bundle.sh --apply >&2
}

ab_expand() {   # stdin -> stdout, __AB_SCHEMA__ and friends replaced by their values.
  local k; local -a e=()
  for k in $AB_KEYS; do e+=(-e "s|__${k}__|${!k}|g"); done
  sed "${e[@]}"
}

# The plugin's own name rides along: a script that knows the layout can spell its slugs.
# `if [ -r ]`, never `|| true`: bash 3.2 under `set -e` exits on sourcing a missing file.
_pn="$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"
if [ -r "$_pn" ]; then . "$_pn"; fi; unset _pn
PLUGIN_NAME="${PLUGIN_NAME:-}" PLUGIN_MARKETPLACE="${PLUGIN_MARKETPLACE:-}"   # set -u callers, helper absent

# Sourced ⇒ stop here. Executed ⇒ answer, so a harness, a doc or a non-bash reader gets
# the same answer as a script does.
(return 0 2>/dev/null) && return 0

if [ "$#" -eq 0 ]; then
  for k in $AB_KEYS; do printf '%s=%s\n' "$k" "${!k}"; done
  exit 0
fi

for k in $AB_KEYS; do
  [ "$k" = "$1" ] || continue
  printf '%s\n' "${!k}"
  exit 0
done

echo "bundle-paths: no such key: $1" >&2
echo "              keys: $AB_KEYS" >&2
exit 1
