#!/usr/bin/env bash
#
# lib.test.sh — tests/lib.sh's fixture_bundle is only worth having if a copy IS a stamp.
#
# The oracle is plugin/scripts/init-bundle.sh itself: every shape a caller uses is stamped
# for real and diffed against a cached copy, with the one legitimate difference — the
# directory each landed in — normalised out. Three shapes, because three things in a
# stamp depend on where it lands: the paths it writes, the sibling repos that
# plugin/scripts/link-repos.sh links into repos/, and whatever the directory already held.
# If the stamp grows a fourth, a diff below goes red before a migrated harness goes wrong.
#
# The cache MECHANICS (built once, hit after, keyed on plugin/, safe under two builders,
# never served when it should not be) are measured against a stand-in repo whose "stamp"
# is five lines that count their own runs: a hit is "the counter did not move", not a
# timing, and none of it needs the real 3,000-line script a second time.
# ok() compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lib-test.XXXXXX")" || {
  echo "lib.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# A private cache: nothing here reads or leaves a slot in the suite's shared one.
mkdir -p "$TMP/t"; export TMPDIR="$TMP/t"
. "$REPO/tests/lib.sh"

norm() { A="$2" B="$3" perl -pe 's/\Q$ENV{A}\E/\@PARENT\@/g; s/\Q$ENV{B}\E/\@PARENT\@/g' "${@:4}"; }
# sig <bundle> — every path, its type, a file's mode and content, a link's target, with
# the bundle's parent (as given, and resolved: link-repos.sh writes `pwd -P`) normalised.
sig() {
  local phys logi p
  logi="$(cd "$1/.." && pwd)"; phys="$(cd "$1/.." && pwd -P)"
  ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then printf 'L %s -> %s\n' "$p" "$(readlink "$p" | norm - "$phys" "$logi")"
      elif [ -d "$p" ]; then printf 'D %s\n' "$p"
      else printf 'F %s %s %s\n' "$p" "$(ls -l "$p" | cut -c1-10)" "$(norm - "$phys" "$logi" "$p" | shasum | cut -c1-40)"
      fi
    done )
}
same() { if [ "$(sig "$1")" = "$(sig "$2")" ]; then echo yes; else echo no; diff <(sig "$1") <(sig "$2") | head -20 >&2; fi; }
names() { ( cd "$1" && grep -rlF -- "$2" . 2>/dev/null | LC_ALL=C sort | paste -sd, - ); }
HOME_CACHE="$(fixture_cache_home)"

echo "== ok / finish =="
out="$( pass=0; fail=0; ok "a match" 1 1; ok "a mismatch" 1 2; finish; echo "rc=$?" )"
ok "a match prints PASS"            "$(printf '%s\n' "$out" | grep -c '^  PASS  a match .*(1)$')" 1
ok "a mismatch prints got/want"     "$(printf '%s\n' "$out" | grep -c '^  FAIL  a mismatch .*got 1, want 2$')" 1
ok "finish prints the tally"        "$(printf '%s\n' "$out" | grep -c '^pass=1 fail=1$')" 1
ok "…and is non-zero on a failure"  "$(printf '%s\n' "$out" | tail -1)" rc=1
ok "…and zero without one"          "$( pass=3; fail=0; finish >/dev/null; echo $? )" 0

echo "== shape 1: an absent directory in an empty parent =="
mkdir -p "$TMP/a/real" "$TMP/a/copy"
fixture_stamp_real "$TMP/a/real/inst" >/dev/null 2>&1
ok "the real stamp exits 0"                    "$?" 0
fixture_bundle "$TMP/a/copy/inst"
ok "fixture_bundle exits 0"                    "$?" 0
ok "the real stamp is a bundle (not vacuous)"  "$(test -f "$TMP/a/real/inst/instance.config.json" && echo yes || echo no)" yes
ok "the copy equals it, parent normalised"     "$(same "$TMP/a/real/inst" "$TMP/a/copy/inst")" yes
# The normalisation is not hiding the comparison: these files really do carry the path.
WANT="./.claude/settings.json,./inst.code-workspace,./instance.config.local.json"
ok "the real stamp names its own location in"  "$(names "$TMP/a/real/inst" "$(cd "$TMP/a/real" && pwd)")" "$WANT"
ok "the copy names ITS location in the same"   "$(names "$TMP/a/copy/inst" "$(cd "$TMP/a/copy" && pwd)")" "$WANT"
ok "no file in the copy names the cache"       "$(grep -rlF -- "$HOME_CACHE" "$TMP/a/copy/inst" | wc -l | tr -d ' ')" 0
ok "…and no symlink does"                      "$(find "$TMP/a/copy/inst" -type l -exec readlink {} \; | grep -cF -- "$HOME_CACHE")" 0
ok "the cache slot itself does (not vacuous)"  "$(grep -rlF -- "$HOME_CACHE" "$HOME_CACHE" | grep -c 'settings.json$')" 1

echo "== shape 2: a prefixed bundle name, and sibling repos the stamp links into repos/ =="
for side in real copy; do
  mkdir -p "$TMP/b/$side/repoA/.git" "$TMP/b/$side/.github/.git" "$TMP/b/$side/_wt/.git" "$TMP/b/$side/plain"
done
fixture_stamp_real "$TMP/b/real/_ai-bridge-grp" >/dev/null 2>&1
fixture_bundle "$TMP/b/copy/_ai-bridge-grp"
ok "fixture_bundle exits 0"                    "$?" 0
ok "the real stamp names the workspace after the GROUP" "$(cd "$TMP/b/real/_ai-bridge-grp" && ls *.code-workspace)" grp.code-workspace
ok "the real stamp linked the siblings"        "$(ls -A "$TMP/b/real/_ai-bridge-grp/repos" | LC_ALL=C sort | paste -sd, -)" ".github,repoA"
ok "the copy equals it, links included"        "$(same "$TMP/b/real/_ai-bridge-grp" "$TMP/b/copy/_ai-bridge-grp")" yes
ok "a copy's link reaches ITS sibling"         "$(cd "$TMP/b/copy/_ai-bridge-grp/repos/repoA" 2>/dev/null && pwd -P)" "$(cd "$TMP/b/copy/repoA" && pwd -P)"

echo "== shape 3: why a directory that already holds something is stamped for real =="
# Not a detail: with projects/ already there the stamp seeds no projects/.gitkeep, so
# "copy, then mkdir" is a DIFFERENT bundle. That is why a non-empty <dest> never gets a copy.
mkdir -p "$TMP/c/real/inst/projects/demo" "$TMP/c/copy"
fixture_stamp_real "$TMP/c/real/inst" >/dev/null 2>&1
fixture_bundle "$TMP/c/copy/inst"; mkdir -p "$TMP/c/copy/inst/projects/demo"
ok "copy-then-mkdir is NOT mkdir-then-stamp"   "$(same "$TMP/c/real/inst" "$TMP/c/copy/inst" 2>/dev/null)" no
ok "…the stamp seeded no projects/.gitkeep there" "$(test -e "$TMP/c/real/inst/projects/.gitkeep" && echo yes || echo no)" no

echo "== the cache: built once, hit after, and missed when plugin/ changes =="
# A stand-in repo: this lib.sh, the real bundle-paths.sh, and a stamp that writes the two
# location-dependent things (its own path, its parent) and is slow enough to overlap.
R="$TMP/repo"; mkdir -p "$R/tests" "$R/plugin/scripts" "$R/plugin/seed"
cp "$REPO/tests/lib.sh" "$R/tests/lib.sh"
cp "$REPO/plugin/scripts/bundle-paths.sh" "$R/plugin/scripts/bundle-paths.sh"
printf 'seed v1\n' > "$R/plugin/seed/CLAUDE.md"
export FX_COUNT="$TMP/count"; : > "$FX_COUNT"
cat > "$R/plugin/scripts/init-bundle.sh" <<'STAMP'
#!/usr/bin/env bash
echo run >> "$FX_COUNT"; mkdir -p "$1/repos"; d="$(cd "$1" && pwd)"; sleep 0.5
[ -e "$d/CLAUDE.md" ] || cp "$(dirname "$0")/../seed/CLAUDE.md" "$d/CLAUDE.md"
printf '{ "cwd": "%s", "reposRoot": "%s" }\n' "$d" "${d%/*}" > "$d/instance.config.json"
: > "$d/${d##*/}.code-workspace"
STAMP
runs() { wc -l < "$FX_COUNT" | tr -d ' '; }
inr() { ( export TMPDIR="$TMP/t2"; mkdir -p "$TMPDIR"; . "$R/tests/lib.sh"; "$@" ); }

# Two cold callers at once — the suite runs harnesses in a pool, so this is the normal case.
inr fixture_bundle "$TMP/d/one/inst" & p1=$!
inr fixture_bundle "$TMP/d/two/inst" & p2=$!
wait "$p1"; r1=$?; wait "$p2"; r2=$?
ok "two concurrent cold calls both exit 0"     "$r1,$r2" 0,0
ok "…and produce the same bundle"              "$(same "$TMP/d/one/inst" "$TMP/d/two/inst")" yes
ok "…from ONE slot, with no build left behind" "$(ls -A "$TMP/t2"/loopd-test-cache.* | wc -l | tr -d ' ')" 1
cold="$(runs)"
ok "…having BOTH built (the race is real)"     "$cold" 2
ok "…and a copy names its own location"        "$(cat "$TMP/d/one/inst/instance.config.json")" "{ \"cwd\": \"$(cd "$TMP/d/one/inst" && pwd)\", \"reposRoot\": \"$(cd "$TMP/d/one" && pwd)\" }"
inr fixture_bundle "$TMP/d/three/inst"
ok "a warm call exits 0"                       "$?" 0
ok "…and runs NO stamp"                        "$(runs)" "$cold"
ok "…yet is the same bundle"                   "$(same "$TMP/d/one/inst" "$TMP/d/three/inst")" yes

K1="$(inr fixture_key)"
inr fixture_bundle "$TMP/d/five/_loopd-other"
ok "another basename is served from the SAME slot" "$(runs)" "$cold"
ok "…under its own group's workspace name"   "$(cd "$TMP/d/five/_loopd-other" && ls *.code-workspace)" other.code-workspace
printf '\nan edit\n' >> "$R/plugin/seed/CLAUDE.md"
K2="$(inr fixture_key)"
ok "editing a file under plugin/ changes the key" "$([ -n "$K2" ] && [ "$K2" != "$K1" ] && echo yes || echo no)" yes
inr fixture_bundle "$TMP/d/four/inst"
ok "…so the next call stamps again"            "$(runs)" "$((cold+1))"
ok "…and carries the edit"                     "$(tail -1 "$TMP/d/four/inst/CLAUDE.md")" "an edit"
chmod +x "$R/plugin/seed/CLAUDE.md"
ok "a mode change is a new key too"            "$([ "$(inr fixture_key)" != "$K2" ] && echo yes || echo no)" yes
chmod -x "$R/plugin/seed/CLAUDE.md"
ok "…and reverting it restores the old one"    "$(inr fixture_key)" "$K2"

echo "== what is never served from the cache =="
now="$(runs)"
mkdir -p "$TMP/e/full/inst/projects/p"
inr fixture_bundle "$TMP/e/full/inst"
ok "a non-empty directory gets the real stamp" "$(runs)" "$((now+1))"
inr fixture_bundle "$TMP/e/odd [x]/inst"
ok "a path outside the safe set does too"      "$(runs)" "$((now+2))"
ok "…and is still a bundle"                    "$(test -f "$TMP/e/odd [x]/inst/inst.code-workspace" && echo yes || echo no)" yes
( export FIXTURE_BUNDLE_NO_CACHE=1; inr fixture_bundle "$TMP/e/off/inst" )
ok "FIXTURE_BUNDLE_NO_CACHE=1 does too"        "$(runs)" "$((now+3))"
# A slot that names the cache somewhere the rewrite does not reach must be refused.
home2="$(inr fixture_cache_home)"
printf '%s/elsewhere\n' "$home2" >> "$home2/$K2/root/$FX_ORIGIN/README.md"
err="$(inr fixture_bundle "$TMP/e/leak/inst" 2>&1)"; rc=$?
ok "a copy that still names the cache is refused" "$rc" 1
ok "…saying why"                               "$(printf '%s\n' "$err" | grep -c 'still names the cache')" 1

finish
