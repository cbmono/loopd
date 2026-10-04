#!/usr/bin/env bash
#
# bundle-group.test.sh — a bundle's group comes from its CONFIG, so the directory can be
# renamed. Exit: 0 clean, 1 an assertion failed, 2 the tree is not readable.
#
# The property, and why each half is asserted. Five live sites used to derive the group
# from the directory NAME — plugin/scripts/write-snapshot.sh, plugin/scripts/build-board.sh,
# plugin/scripts/print-board.sh, plugin/scripts/index-kb.sh and plugin/scripts/init-bundle.sh
# — so renaming `_ai-bridge-private` to `_loopd-private` relabelled the bundle on the board
# and stopped the KB indexer recognising it. Reasoning: loopd/task-013.
#
#   · THE FALLBACK STRIPS BOTH PREFIXES, because no bundle sets `group` today and the
#     fallback is therefore the live path on BOTH sides of a rename.
#   · index-kb.sh's skip is a DIFFERENT question — is this sibling a bundle? — so it
#     reads the `instance.config.json` marker. A bundle named neither way must still be
#     skipped, or a sibling control panel is indexed as a product repo.
#   · THE RENAME IS ASSERTED END TO END, not just per unit: the same bundle under both
#     names must produce the same snapshot `group` and the same rendered board.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$TPL/plugin/scripts/bundle-paths.sh"
WRITER="$TPL/plugin/scripts/write-snapshot.sh"
BOARD="$TPL/plugin/scripts/build-board.sh"
PRINT="$TPL/plugin/scripts/print-board.sh"
INDEXKB="$TPL/plugin/scripts/index-kb.sh"
CHECK="$TPL/plugin/scripts/ai-bridge.sh"
BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"
SEED_WS="$TPL/plugin/seed/bridge.code-workspace"
SEED_CFG="$TPL/plugin/seed/instance.config.json"
for f in "$WRITER" "$BOARD" "$PRINT" "$INDEXKB" "$CHECK" "$BRIDGE_INSTALL" "$SEED_WS" "$SEED_CFG"; do
  [ -f "$f" ] || { echo "bundle-group.test: missing $f" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bundle-group.XXXXXX")" || {
  echo "bundle-group.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
case "$TMP" in /*) ;; *) echo "bundle-group.test: mktemp returned a relative path" >&2; exit 2 ;; esac
trap 'rm -rf "$TMP"' EXIT

# init-bundle.sh refuses to run from a linked git worktree by design, and a role agent's
# checkout routinely IS one — so §5 would stamp nothing and assert on the silence. Same
# resolution as tests/board-renderers.test.sh: a filesystem copy outside any repository,
# where the guard's own question has no repo to answer about.
if command -v git >/dev/null 2>&1; then
  _gd="$(git -C "$TPL" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _gc="$(git -C "$TPL" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_gd" ] && [ -n "$_gc" ] && [ "$_gd" != "$_gc" ]; then
    _tpl_res="$(cd -- "$TPL" && pwd -P)"; _tmp_res="$(cd -- "$TMP" && pwd -P)"
    case "$_tmp_res/" in
      "$_tpl_res"/*) echo "bundle-group.test: TMPDIR is inside the checkout; the install-source copy would recurse." >&2; exit 2 ;;
    esac
    mkdir -p "$TMP/install-src"
    cp -R "$TPL"/. "$TMP/install-src"/
    rm -rf "$TMP/install-src/.git"
    BRIDGE_INSTALL="$TMP/install-src/plugin/scripts/init-bundle.sh"
  fi
fi

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# A bundle with one project and one task, enough for the writer and both renderers.
new_bundle() { # <dir> [<json body of instance.config.json>]
  mkdir -p "$1/$AB_DIR" "$1/projects/p/tasks"
  printf '%s\n' "${2:-{ \"org\": \"fixture-org\" \}}" > "$1/instance.config.json"
  cat > "$1/projects/p/project.md" <<'PRJ'
---
type: Project
title: Demo
kind: build
status: active
---
PRJ
  cat > "$1/projects/p/tasks/task-001.md" <<'TSK'
---
type: Task
title: A task
kind: build
status: ready
assignee: software-engineer
---
TSK
  touch "$1/$AB_SNAPSHOT"
}

echo
echo "== 1. ab_group — the config first, then both prefixes =="
mkdir -p "$TMP/g"
new_bundle "$TMP/g/_ai-bridge-x"
cp -R "$TMP/g/_ai-bridge-x" "$TMP/g/_loopd-x"
new_bundle "$TMP/g/bare"
new_bundle "$TMP/g/_loopd-named" '{ "org": "fixture-org", "group": "configured" }'
ok "the legacy prefix is stripped"          "$(ab_group "$TMP/g/_ai-bridge-x")" x
ok "the new prefix is stripped too"         "$(ab_group "$TMP/g/_loopd-x")" x
ok "an unprefixed directory is its own name" "$(ab_group "$TMP/g/bare")" bare
ok "a configured group WINS over the name"  "$(ab_group "$TMP/g/_loopd-named")" configured
# A text match passes this and a JSON parse does not: the nested key comes first.
new_bundle "$TMP/g/_loopd-nested" \
  '{ "people": { "group": "nested-value" }, "group": "chosen" }'
ok "only the TOP-LEVEL group is read"       "$(ab_group "$TMP/g/_loopd-nested")" chosen
new_bundle "$TMP/g/_loopd-esc" '{ "group": "a\u0062c" }'
ok "a JSON-escaped group is decoded"         "$(ab_group "$TMP/g/_loopd-esc")" abc
new_bundle "$TMP/g/_loopd-onlynested" '{ "people": { "group": "nested-value" } }'
ok "a nested-only group falls back to the name" "$(ab_group "$TMP/g/_loopd-onlynested")" onlynested
# The prefix alone is a whole name, not an empty group — `${name#prefix}` would blank it.
mkdir -p "$TMP/g/_loopd-" && printf '{}\n' > "$TMP/g/_loopd-/instance.config.json"
ok "a bare prefix is left alone, never blanked" "$(ab_group "$TMP/g/_loopd-")" "_loopd-"
ok "the prefixes are spelled in ONE file" \
  "$(grep -lE '_ai-bridge-|_loopd-' "$TPL"/plugin/scripts/*.sh \
     | xargs grep -lE '^[^#]*(_ai-bridge-|_loopd-)' | xargs -n1 basename | sort | tr '\n' ' ')" \
  "bundle-paths.sh "

echo
echo "== 2. the rename is a no-op, end to end =="
for d in "$TMP/g/_ai-bridge-x" "$TMP/g/_loopd-x"; do
  ( cd "$d" && SNAPSHOT_NOW=2026-01-01T00:00:00Z bash "$WRITER" --quiet )
done
snapgroup() { head -1 <<<"$(grep -o '"group": "[^"]*"' "$1/$AB_SNAPSHOT")" | sed 's/.*: "//; s/"$//'; }
ok "write-snapshot.sh writes the same group under both names" \
  "$(snapgroup "$TMP/g/_ai-bridge-x"):$(snapgroup "$TMP/g/_loopd-x")" "x:x"
boardrow() { awk '/^x /{print $1; exit}' <<<"$( ( cd "$1" && bash "$PRINT" --color never --width 0 . ) )"; }
ok "print-board.sh labels both rows the same" \
  "$(boardrow "$TMP/g/_ai-bridge-x"):$(boardrow "$TMP/g/_loopd-x")" "x:x"
( cd "$TMP/g/_ai-bridge-x" && bash "$BOARD" --standalone --out "$TMP/a.html" . >/dev/null 2>&1 )
( cd "$TMP/g/_loopd-x"     && bash "$BOARD" --standalone --out "$TMP/b.html" . >/dev/null 2>&1 )
ok "build-board.sh renders a byte-identical page" \
  "$(cmp -s "$TMP/a.html" "$TMP/b.html" && echo same || echo differs)" same
ok "…and neither page carries a directory name" \
  "$(grep -c -e '_ai-bridge-x' -e '_loopd-x' "$TMP/a.html" "$TMP/b.html" | awk -F: '{s+=$2} END{print s+0}')" 0
# The direction that proves the config is read and not merely tolerated: a bundle whose
# directory says one thing and whose config says another is labelled by the config.
( cd "$TMP/g/_loopd-named" && SNAPSHOT_NOW=2026-01-01T00:00:00Z bash "$WRITER" --quiet )
ok "a configured group reaches the snapshot"  "$(snapgroup "$TMP/g/_loopd-named")" configured
ok "…and the terminal board" \
  "$(( cd "$TMP/g/_loopd-named" && bash "$PRINT" --color never --width 0 . ) | grep -c '^configured ')" 1
# A renderer must still read the config of an instance whose snapshot predates the key.
python3 - "$TMP/g/_loopd-named/$AB_SNAPSHOT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["group"] = ""
json.dump(d, open(sys.argv[1], "w"))
PY
ok "…even when the snapshot itself carries no group" \
  "$(( cd "$TMP/g/_loopd-named" && bash "$PRINT" --color never --width 0 . ) | grep -c '^configured ')" 1

echo
echo "== 3. index-kb.sh skips a sibling BUNDLE, by its marker and not its name =="
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/codegraph"; chmod +x "$TMP/bin/codegraph"
mkdir -p "$TMP/repos/product/.git" "$TMP/repos/_wt/.git" \
         "$TMP/repos/_ai-bridge-old/.git" "$TMP/repos/_loopd-new/.git" "$TMP/repos/unprefixed/.git"
for b in _ai-bridge-old _loopd-new unprefixed; do
  printf '{ "org": "fixture-org" }\n' > "$TMP/repos/$b/instance.config.json"
done
IK="$TMP/ik"; mkdir -p "$IK/$AB_DIR"
printf '{ "org": "fixture-org", "reposRoot": "%s/repos" }\n' "$TMP" > "$IK/instance.config.json"
IKOUT="$( cd "$IK" && PATH="$TMP/bin:$PATH" bash "$INDEXKB" 2>&1 )"
for b in _ai-bridge-old _loopd-new unprefixed _wt; do
  ok "…skips $b" "$(printf '%s\n' "$IKOUT" | grep -c "^-- skip $b\$")" 1
done
# The other direction: a plain product repo is still indexed, so the skip is not universal.
ok "…and a product repo is still indexed" \
  "$(printf '%s\n' "$IKOUT" | grep -c '^== \[product\]')" 1

echo
echo "== 4. \`group\` is a key the machinery knows =="
GI="$TMP/groupinst"; mkdir -p "$GI/$AB_DIR" "$GI/.claude/agents"
printf 'stub\n' > "$GI/$AB_SCHEMA"
printf '{ "org": "fixture-org", "group": "private" }\n' > "$GI/instance.config.json"
ok "the seed ships the key, so the known set carries it" \
  "$(grep -c '^  "group":' "$SEED_CFG")" 1
ok "a bundle that sets it is not warned about" \
  "$(bash "$CHECK" check --instance "$GI" --template "$TPL" 2>&1 | grep -c 'nothing reads.*group')" 0
# Non-vacuity: the same check on the same bundle still names a key nothing reads.
printf '{ "org": "fixture-org", "group": "private", "notAKeyProbe": 1 }\n' > "$GI/instance.config.json"
ok "…while an invented key still is" \
  "$(bash "$CHECK" check --instance "$GI" --template "$TPL" 2>&1 | grep -c 'nothing reads.*notAKeyProbe')" 1

echo
echo "== 5. the seeded workspace file, and the pane that hides the bundle =="
WS="$TMP/g/_loopd-stamped"; mkdir -p "$WS"
( cd "$WS" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$WS" >/dev/null 2>&1 </dev/null
ok "a stamp names the workspace after the stripped directory" \
  "$([ -f "$WS/stamped.code-workspace" ] && echo yes || echo no)" yes
WSC="$TMP/g/_loopd-ignored"; mkdir -p "$WSC"
printf '{ "org": "fixture-org", "group": "chosen" }\n' > "$WSC/instance.config.json"
( cd "$WSC" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$WSC" >/dev/null 2>&1 </dev/null
ok "…and after the configured group when there is one" \
  "$([ -f "$WSC/chosen.code-workspace" ] && echo yes || echo no)" yes
WSS="$TMP/g/_loopd-slashed"; mkdir -p "$WSS"
printf '{ "org": "fixture-org", "group": "../escaped" }\n' > "$WSS/instance.config.json"
( cd "$WSS" && git init -q . ) 2>/dev/null || true
WSSOUT="$(bash "$BRIDGE_INSTALL" "$WSS" 2>&1 </dev/null)"
ok "a group with a slash writes no workspace outside the bundle" \
  "$(ls "$TMP/g"/*.code-workspace "$WSS"/*.code-workspace 2>/dev/null | wc -l | tr -d ' ')" 0
ok "…and says so" "$(printf '%s\n' "$WSSOUT" | grep -c "group '../escaped' is not a file name")" 1
for p in _ai-bridge- _loopd-; do
  ok "the seed workspace hides a ${p}* bundle from the repos pane" \
    "$(grep -cF "\"$p*\": true" "$SEED_WS")" 1
done

echo
printf '  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
