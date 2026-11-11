#!/usr/bin/env bash
#
# gitignore-managed-once.test.sh — a re-stamp leaves ONE copy of each managed ignore line.
# init-bundle.sh appends a missing line, then the seed merge restores the seed's copy, and
# step 5a's `gi_managed` tidy drops the second. A pattern missing from that list was written
# twice (the KB stamp, measured 2026-11-02), so the list is checked against every guarded
# `gi_add` heredoc, and a 4.3.0-shaped bundle is stamped for real, mutant included.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT_SRC="$REPO/plugin/scripts/init-bundle.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gi-once.XXXXXX")" || {
  echo "gitignore-managed-once.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
mkdir -p "$HOME"
repo_print() { git -C "$REPO" rev-parse HEAD 2>/dev/null; git -C "$REPO" status --porcelain 2>/dev/null | cksum; }
REPO_BEFORE="$(repo_print)"

echo "== every guarded gi_add pattern is in gi_managed =="
HEREDOC="$(awk '/gi_add <<.GI.$/ { on=1; next } on && /^GI$/ { on=0 } on && NF && !/^#/' "$INIT_SRC" \
  | sed -E 's/__(AB_[A-Z_]+)__/$\1/g' | grep -vxF '/board.html')"
MANAGED="$(sed -n 's/^ *gi_managed="\(.*\)"$/\1/p' "$INIT_SRC" | tr ' ' '\n' | grep -vxF '$gi_managed' | grep .)"
ok "the heredocs were read (not an empty set)" "$([ "$(printf '%s\n' "$HEREDOC" | grep -c .)" -ge 12 ] && echo yes || echo no)" yes
MISSING="$(printf '%s\n' "$HEREDOC" | while IFS= read -r p; do grep -qxF "$p" <<<"$MANAGED" || printf '%s ' "$p"; done)"
ok "no guarded pattern is missing from gi_managed" "${MISSING:-none}" none
ok "/board.html stays out (its trailing copy outranks !/board.html)" \
  "$(printf '%s\n' "$MANAGED" | grep -cxF '/board.html' | tr -d ' ')" 0

# A plain-directory template OUTSIDE this checkout: inside it, refresh-seeds.sh takes this
# repo's history as the merge base and the 4.3.0 shape below never reaches the merge.
TPL="$TMP/tpl"
( cd "$REPO" && git ls-files plugin ) | while IFS= read -r f; do
  mkdir -p "$TPL/$(dirname "$f")"; cp "$REPO/$f" "$TPL/$f" 2>/dev/null || true
done
MUT="$TMP/mut"; cp -R "$TPL" "$MUT"
grep -v 'gi_managed="$gi_managed /$AB_KB_STAMP\*' "$INIT_SRC" > "$MUT/plugin/scripts/init-bundle.sh"

KB="/$AB_KB_STAMP*"; REF="/$AB_DIR/refresh/"; CNT="/$AB_COUNTS"
count() { grep -cxF "$2" "$1/.gitignore" | tr -d ' '; }
stamp() { bash "$1/plugin/scripts/init-bundle.sh" "$2" </dev/null >"$TMP/out" 2>&1; }
commit() { ( cd "$1" && { [ -d .git ] || git init -q .; } && git add -A && git commit -qm s ) >/dev/null 2>&1; }
# Stamp fresh, then take the two lines out of the bundle AND its merge base: the shape a
# 4.3.0 stamp left, so the next stamp's append and the seed merge both write them.
old_bundle() { # <dir>
  mkdir -p "$1"; stamp "$TPL" "$1"
  local f; for f in "$1/.gitignore" "$1/$AB_DIR/seed-base/.gitignore"; do
    grep -vxF -e "$KB" -e "$REF" -e "$CNT" "$f" > "$f.n" && mv "$f.n" "$f"
  done
  commit "$1"
}

echo
echo "== a fresh stamp =="
FRESH="$TMP/fresh"; mkdir -p "$FRESH"; stamp "$TPL" "$FRESH"; ok "init-bundle.sh exits 0" "$?" 0
ok "one KB-stamp line" "$(count "$FRESH" "$KB")" 1
commit "$FRESH"
ok "  and it ignores .kb-check-stamp.123" \
  "$(cd "$FRESH" && git check-ignore -q "$AB_KB_STAMP.123" && echo yes || echo no)" yes

echo
echo "== a 4.3.0-shaped bundle, stamped twice =="
OLD="$TMP/old"; old_bundle "$OLD"
ok "the fixture starts with no KB-stamp line" "$(count "$OLD" "$KB")" 0
ok "  and no counts.json line" "$(count "$OLD" "$CNT")" 0
stamp "$TPL" "$OLD"; ok "the re-stamp exits 0" "$?" 0
ok "  the seed merge ran (PORTED .gitignore)" "$(grep -q 'PORTED    .gitignore' "$TMP/out" && echo yes || echo no)" yes
ok "  one KB-stamp line" "$(count "$OLD" "$KB")" 1
ok "  one refresh/ line" "$(count "$OLD" "$REF")" 1
ok "  one counts.json line" "$(count "$OLD" "$CNT")" 1
ok "  and counts.json is ignored" "$(cd "$OLD" && git check-ignore -q "$AB_COUNTS" && echo yes || echo no)" yes
commit "$OLD"; stamp "$TPL" "$OLD"
ok "a second stamp leaves one KB-stamp line" "$(count "$OLD" "$KB")" 1
ok "  and one refresh/ line" "$(count "$OLD" "$REF")" 1
ok "  and one counts.json line" "$(count "$OLD" "$CNT")" 1

echo
echo "== a negation between two copies keeps the repeat (git's last match wins) =="
NEG="$TMP/neg"; mkdir -p "$NEG"; stamp "$TPL" "$NEG"
printf '!/.env\n.env\n%s\n' "$KB" >> "$NEG/.gitignore"; commit "$NEG"; stamp "$TPL" "$NEG"
ok "both .env lines stay" "$(count "$NEG" .env)" 2
ok "  and .env is still ignored" "$(cd "$NEG" && git check-ignore -q .env && echo yes || echo no)" yes
ok "  while the un-negated KB-stamp repeat is still dropped" "$(count "$NEG" "$KB")" 1
GLOB="$TMP/glob"; mkdir -p "$GLOB"; stamp "$TPL" "$GLOB"
printf '!*.json\n/%s\n' "$AB_SNAPSHOT" >> "$GLOB/.gitignore"; commit "$GLOB"; stamp "$TPL" "$GLOB"
ok "a glob negation between keeps the repeat too" "$(count "$GLOB" "/$AB_SNAPSHOT")" 2
ok "  and the snapshot is still ignored" "$(cd "$GLOB" && git check-ignore -q "$AB_SNAPSHOT" && echo yes || echo no)" yes

echo
echo "== MUTATION: gi_managed without the KB stamp writes it twice =="
M="$TMP/mutant"; old_bundle "$M"; stamp "$MUT" "$M"
ok "the mutant leaves two KB-stamp lines" "$(count "$M" "$KB")" 2

ok "the repo under test is untouched" "$(repo_print)" "$REPO_BEFORE"
echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
