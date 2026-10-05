#!/usr/bin/env bash
# Exercises scripts/link-repos.sh — the `repos/` symlink view of reposRoot.
#
# The view exists so the product repos are reachable from inside an instance while
# staying PHYSICAL PEERS of it on disk. Two properties are load-bearing and both are
# pinned here: it must never link the instance that holds it (that recurses through
# repos/<instance>/repos/... forever), and it must never touch anything that isn't a
# symlink it owns. The rest of the cases cover the skip rules, idempotence, pruning,
# and the unconfigured-reposRoot path the installer depends on.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$TPL/plugin/scripts/link-repos.sh"
TMP="$(mktemp -d)" || {
  echo "link-repos.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# install.sh refuses to run from a linked git worktree (deliberately — see its own
# header), and every role agent's checkout of this template is one (CONVENTIONS.md).
# Re-point $BRIDGE_INSTALL at a filesystem-level copy of $TPL outside any git
# repository, exactly as tests/board-renderers.test.sh does — see there for the full
# rationale and the TMPDIR-recursion guard this carries along with it. Skipped when
# $TPL is already a main tree or no repo at all, so a plain clone pays nothing extra.
# ai-bridge-v4/task-030.
BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"
if command -v git >/dev/null 2>&1; then
  _tpl_gd="$(git -C "$TPL" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _tpl_gc="$(git -C "$TPL" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_tpl_gd" ] && [ -n "$_tpl_gc" ] && [ "$_tpl_gd" != "$_tpl_gc" ]; then
    INSTALL_SRC="$TMP/install-src"
    _tpl_res="$(cd -- "$TPL" && pwd -P)"
    _src_res="$(cd -- "$TMP" && pwd -P)"
    case "$_src_res/" in
      "$_tpl_res"/*) echo "link-repos.test: TMPDIR ($_src_res) is inside the template tree ($_tpl_res); the install-source copy would recurse. Point TMPDIR outside the checkout." >&2; exit 2 ;;
    esac
    mkdir -p "$INSTALL_SRC"
    cp -R "$TPL"/. "$INSTALL_SRC"/
    rm -rf "$INSTALL_SRC/.git"
    BRIDGE_INSTALL="$INSTALL_SRC/plugin/scripts/init-bundle.sh"
  fi
fi
pass=0; fail=0

ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s expected %s, got %s\n' "$1" "$3" "$2"; fail=$((fail+1)); fi
}

# A group folder: reposRoot with repos beside the instance, exactly as on disk.
# `bridge` is deliberately NOT `_`-prefixed and IS a git repo, so the only thing
# keeping it out of its own view is the resolved-path check.
setup() { # [instance-dir-name]
  local inst_name="${1:-bridge}"
  rm -rf "$TMP/group"
  mkdir -p "$TMP/group"
  # `.github` stands in for the real case of a DOT-NAMED repo: an org's `.github`
  # repo is ordinary to clone, and a plain `*` glob cannot see it.
  for r in repo1 repo2 .github; do mkdir -p "$TMP/group/$r/.git"; done
  mkdir -p "$TMP/group/not-a-repo"                 # no .git
  mkdir -p "$TMP/group/_wt/some-worktree/.git"     # agent worktree root
  mkdir -p "$TMP/group/_ai-bridge-other/.git"      # a sibling instance
  INST="$TMP/group/$inst_name"
  mkdir -p "$INST/.git" "$INST/scripts"
  printf '{ "reposRoot": "%s" }\n' "$TMP/group" > "$INST/instance.config.json"
}

run() { ( cd "$INST" && bash "$SCRIPT" "$@" 2>&1 ); }

# Names of entries in the view, sorted and comma-joined. LC_ALL=C so a dot-named
# entry sorts predictably rather than by the runner's locale collation.
view() { ( cd "$INST/repos" 2>/dev/null && LC_ALL=C ls -A | LC_ALL=C sort | paste -sd, - ) 2>/dev/null; }

# --- what gets linked, and what must not -----------------------------------
setup
out="$(run)"
ok "links every git repo under reposRoot" "$(view)" ".github,repo1,repo2"
ok "a dot-named repo is linked (needs dotglob)" \
  "$([ -L "$INST/repos/.github" ] && echo linked || echo MISSED)" linked
# Compared against the CANONICAL path: the script resolves reposRoot with `pwd -P`
# so the instance-identity check compares like with like (on macOS /var is a
# symlink to /private/var, and an unresolved path would defeat that check).
ok "a link resolves to the real clone" \
  "$(readlink "$INST/repos/repo1")" "$(cd "$TMP/group" && pwd -P)/repo1"
ok "_wt and _ai-bridge-* are skipped" \
  "$(printf '%s' "$(view)" | grep -c '_' || true)" "0"
ok "a dir without .git is skipped" \
  "$([ -e "$INST/repos/not-a-repo" ] && echo linked || echo skipped)" skipped

# The recursion guard. `bridge` passes every other test (not `_`-prefixed, has a
# .git), so only the instance-identity check can keep it out.
ok "never links the instance that holds the view" \
  "$([ -e "$INST/repos/bridge" ] && echo RECURSES || echo skipped)" skipped

# --- the hook marker: the way back from a worktree to this bundle -----------
# deny-destructive.sh / agent-control.sh resolve a linked worktree's bundle by reading
# `<repo>/.git/loopd-bundle`; this script is the one writer. Written for every linked
# repo, never for the worktree root or a sibling instance, idempotent, and reversed
# by --remove (below) — only when the marker names THIS instance.
ok "writes the hook marker into each linked repo" \
  "$(cat "$TMP/group/repo1/.git/loopd-bundle" 2>/dev/null)" "$(cd "$INST" && pwd -P)"
ok "…into the dot-named repo too" \
  "$([ -f "$TMP/group/.github/.git/loopd-bundle" ] && echo marked || echo MISSED)" marked
ok "…never into _wt or a sibling instance" \
  "$( { [ -e "$TMP/group/_wt/some-worktree/.git/loopd-bundle" ] || [ -e "$TMP/group/_ai-bridge-other/.git/loopd-bundle" ]; } && echo LEAKED || echo clean)" clean
ok "…and never into the holder itself" \
  "$([ -e "$INST/.git/loopd-bundle" ] && echo MARKED || echo clean)" clean
ok "the first run reports the markers it wrote" \
  "$(printf '%s' "$out" | grep -c 'hook marker(s) written' || true)" "1"

# --- idempotence and pruning ----------------------------------------------
out="$(run)"
ok "second run relinks nothing" "$(printf '%s' "$out" | grep -c '^  link' || true)" "0"
ok "second run rewrites no marker (idempotent)" "$(printf '%s' "$out" | grep -c 'mark ' || true)" "0"
ok "second run leaves the view identical" "$(view)" ".github,repo1,repo2"

mv "$TMP/group/repo2" "$TMP/group/repo2-renamed"
out="$(run)"
ok "a renamed repo is relinked under its new name" \
  "$(view)" ".github,repo1,repo2-renamed"

rm -rf "$TMP/group/repo1"
run >/dev/null
ok "a deleted repo's link is pruned" "$(view)" ".github,repo2-renamed"

# Pruning must see a dot-named link too, or a removed `.github` clone leaves a
# dangling one behind forever.
rm -rf "$TMP/group/.github"
run >/dev/null
ok "a deleted dot-named repo's link is pruned" "$(view)" "repo2-renamed"

# --- never clobber anything that isn't ours -------------------------------
setup
run >/dev/null
rm "$INST/repos/repo1"
printf 'my notes\n' > "$INST/repos/repo1"          # a REAL file in the namespace
out="$(run)"
ok "a real file is kept, not replaced by a link" \
  "$([ -L "$INST/repos/repo1" ] && echo replaced || echo kept)" kept
ok "its content survives" "$(cat "$INST/repos/repo1")" "my notes"

# --- --dry-run changes nothing -------------------------------------------
setup
out="$(run --dry-run)"
ok "dry-run creates no view" \
  "$([ -e "$INST/repos" ] && echo created || echo none)" none
ok "dry-run still reports what it would link" \
  "$(printf '%s' "$out" | grep -c 'would   link' || true)" "3"

# --- --remove tears it down, sparing real entries -------------------------
setup
run >/dev/null
printf 'keep me\n' > "$INST/repos/notes.txt"
run --remove >/dev/null
ok "--remove deletes the links" \
  "$([ -e "$INST/repos/repo1" ] && echo left || echo gone)" gone
ok "--remove takes this instance's marker with it" \
  "$([ -e "$TMP/group/repo1/.git/loopd-bundle" ] && echo left || echo gone)" gone
ok "--remove keeps a real file (so the dir survives)" \
  "$(cat "$INST/repos/notes.txt" 2>/dev/null)" "keep me"

setup
run >/dev/null
printf '%s\n' "/some/other/bundle" > "$TMP/group/repo2/.git/loopd-bundle"
run --remove >/dev/null
ok "--remove leaves a marker that names ANOTHER bundle alone" \
  "$(cat "$TMP/group/repo2/.git/loopd-bundle")" "/some/other/bundle"

setup
run >/dev/null
run --remove >/dev/null
ok "--remove drops the empty dir entirely" \
  "$([ -e "$INST/repos" ] && echo left || echo gone)" gone

# --remove is the one mode that must work on a half-torn-down instance: the config
# is often already gone by then (install.sh --uninstall calls this), and refusing
# would leave the links dangling with nothing left to clean them up.
setup
run >/dev/null
rm "$INST/instance.config.json"
run --remove >/dev/null 2>&1
ok "--remove works with the config deleted" "$?" "0"
ok "--remove with no config still cleared the view" \
  "$([ -e "$INST/repos" ] && echo left || echo gone)" gone

# --- unconfigured reposRoot must be a clean skip, not a failure -----------
# install.sh calls this script on a FIRST stamp, when the seeded config still
# holds the `~/workspace/<group>` placeholder. A non-zero exit there would make a
# brand-new instance look like a broken install.
setup
printf '{ "reposRoot": "~/workspace/<group>" }\n' > "$INST/instance.config.json"
out="$(run)"; rc=$?
ok "placeholder reposRoot exits 0" "$rc" "0"
ok "placeholder reposRoot creates no view" \
  "$([ -e "$INST/repos" ] && echo created || echo none)" none
ok "placeholder reposRoot says why" \
  "$(printf '%s' "$out" | grep -c 'reposRoot' || true)" "1"

setup
printf '{ "org": "x" }\n' > "$INST/instance.config.json"   # no reposRoot at all
run >/dev/null 2>&1
ok "missing reposRoot key exits 0" "$?" "0"

# Outside an instance it must refuse rather than scribble in a random directory.
mkdir -p "$TMP/elsewhere"
( cd "$TMP/elsewhere" && bash "$SCRIPT" >/dev/null 2>&1 )
ok "refuses to run outside an instance root" "$?" "1"

# --- installer integration ------------------------------------------------
# The view is part of `install.sh`, and `--uninstall` must take it back out.
rm -rf "$TMP/group"; mkdir -p "$TMP/group"
for r in repoA repoB; do mkdir -p "$TMP/group/$r/.git"; done
inst="$TMP/group/_ai-bridge-grp"; mkdir -p "$inst"
( cd "$inst" && git init -q . ) 2>/dev/null
bash "$BRIDGE_INSTALL" "$inst" >/dev/null 2>&1
# The stamp DERIVES reposRoot from the bundle's parent (init-bundle.sh 4c), and this
# fixture's bundle sits beside the group's repos — which is the documented layout — so the
# view is built on the FIRST stamp now, with nothing configured by hand.
ok "first stamp derives reposRoot and links the view" \
  "$( ( cd "$inst/repos" && ls -A | sort | paste -sd, - ) )" "repoA,repoB"
ok "first stamp gitignores the view up front" \
  "$(grep -cE '^/repos/$' "$inst/.gitignore")" "1"

# Now configure it the way a user would, and refresh.
printf '{ "reposRoot": "%s" }\n' "$TMP/group" > "$inst/instance.config.json"
bash "$BRIDGE_INSTALL" "$inst" >/dev/null 2>&1
ok "refresh builds the view once reposRoot is real" \
  "$( ( cd "$inst/repos" && ls -A | sort | paste -sd, - ) )" "repoA,repoB"
ok "the gitignore line is added only once" \
  "$(grep -cE '^/repos/$' "$inst/.gitignore")" "1"
ok "the view is ignored by git in practice" \
  "$( cd "$inst" && git status --porcelain 2>/dev/null | grep -c 'repos' || true )" "0"

bash "$BRIDGE_INSTALL" --uninstall "$inst" >/dev/null 2>&1
ok "--uninstall removes the view" \
  "$([ -e "$inst/repos" ] && echo left || echo gone)" gone
ok "--uninstall leaves the real repos alone" \
  "$([ -d "$TMP/group/repoA/.git" ] && echo intact || echo DELETED)" intact

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
