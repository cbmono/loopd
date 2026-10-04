#!/usr/bin/env bash
#
# stable-bin-path.test.sh — plugin/scripts/init-bundle.sh re-points
# <config>/plugins/<plugin>/bin at its own scripts/, owns only that name, and prints a
# guarded PATH line it never writes. The plugin is copied to two cache-shaped version
# directories under a fixture HOME, because the link is derived from where init lives.
# Reasoning: dispatch-reporting-defects/task-022.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/stablebin.XXXXXX")" || {
  echo "stable-bin-path.test: mktemp -d failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
n() { grep -c "$@" | tr -d ' '; }

copy_plugin() { # <dest> — the tracked plugin/ tree as plain files
  ( cd "$REPO/plugin" && git ls-files . ) | while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")"; cp "$REPO/plugin/$f" "$1/$f"
  done
  chmod +x "$1"/scripts/*.sh
}
H="$TMP/home"
MK="$H/.claude/plugins/cache/mk/${PN}"
copy_plugin "$MK/1.0.0"; copy_plugin "$MK/2.0.0"; copy_plugin "$TMP/checkout/plugin"
LINK="$H/.claude/plugins/$PN/bin"
for rc in .zshrc .bashrc .profile .zprofile .bash_profile .zshenv; do
  printf '# sentinel %s\n' "$rc" > "$H/$rc"
done

STUB="$TMP/stub"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
CLEAN_PATH="$STUB:/usr/bin:/bin"
stamp() { # <plugin root> <instance> [extra env…]
  local root="$1" inst="$2"; shift 2
  env -u CLAUDE_CONFIG_DIR PATH="$CLEAN_PATH" HOME="$H" XDG_CONFIG_HOME="$H" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$H/none" PYTHONDONTWRITEBYTECODE=1 "$@" \
    bash "$root/scripts/init-bundle.sh" "$inst" </dev/null >"$TMP/out" 2>&1
}
tree() { ( cd "$H" && find . ! -path './.claude/plugins/cache*' | LC_ALL=C sort ); }
line() { grep -E '^ +if \[ -d ' "$TMP/out" | sed 's/^ *//'; }

echo "== 1. a cache-install stamp creates the link and prints one guarded line =="
tree > "$TMP/tree0"
I="$TMP/i1"; git init -q "$I"; stamp "$MK/1.0.0" "$I"; rc=$?
ok "stamp exits 0" "$rc" 0
ok "bin is a symlink" "$(yn test -L "$LINK")" yes
ok "…to the 1.0.0 scripts dir" "$(readlink "$LINK")" "$MK/1.0.0/scripts"
ok "exactly one PATH line printed" "$(line | wc -l | tr -d ' ')" 1
WANT="if [ -d \"\$HOME/.claude/plugins/$PN/bin\" ]; then export PATH=\"\$HOME/.claude/plugins/$PN/bin:\$PATH\"; fi"
ok "the line is the static guarded form" "$(line)" "$WANT"
ok "the notice says agents keep the absolute path" "$(n -c 'never point them here' "$TMP/out")" 1

echo "== 2. a stamp from a NEW version re-points the link =="
stamp "$MK/2.0.0" "$I"; rc=$?
ok "stamp exits 0" "$rc" 0
ok "the link now resolves to 2.0.0" "$(readlink "$LINK")" "$MK/2.0.0/scripts"
ok "…and says what it was" "$(n -cF "(was $MK/1.0.0/scripts)" "$TMP/out")" 1

echo "== 3. idempotent: re-stamps change nothing under HOME =="
tree > "$TMP/tree1"; stamp "$MK/2.0.0" "$I"; stamp "$MK/2.0.0" "$I"; tree > "$TMP/tree2"
ok "the HOME tree is identical after two re-stamps" "$(yn cmp -s "$TMP/tree1" "$TMP/tree2")" yes
ok "the stamp says keep" "$(n -c "keep  $LINK" "$TMP/out")" 1
ok "one entry in the namespace dir" "$(ls -A "$H/.claude/plugins/$PN" | wc -l | tr -d ' ')" 1
ok "the only HOME paths added are the namespace dir and bin" \
  "$(LC_ALL=C comm -13 "$TMP/tree0" "$TMP/tree2" | tr '\n' ' ')" "./.claude/plugins/$PN ./.claude/plugins/$PN/bin "

echo "== 4. the printed line works as printed, in a fresh shell =="
L1="$(line)"
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || { echo "  SKIP  $sh not installed"; continue; }
  flag=--norc; [ "$sh" = zsh ] && flag=-f
  got="$(env -i HOME="$H" PATH=/usr/bin:/bin "$sh" "$flag" -c "$L1"'
    command -v init-bundle.sh; init-bundle.sh --help >/dev/null 2>&1; echo "help=$?"' 2>&1)"
  ok "$sh: bare name resolves through the link" "$(head -1 <<<"$got")" "$LINK/init-bundle.sh"
  ok "$sh: init-bundle.sh --help by bare name exits 0" "$(printf '%s\n' "$got" | tail -1)" help=0
done
got="$(env -i HOME="$H" PATH=/usr/bin:/bin bash --norc -c "$L1"'; plugin-name.sh' 2>&1)"
ok "plugin-name.sh by bare name derives the name" "$(head -1 <<<"$got")" "PLUGIN_NAME=$PN"
got="$(env -i HOME="$H" PATH=/usr/bin:/bin bash --norc -c "$L1"'; refresh-seeds.sh --help >/dev/null 2>&1; echo $?')"
ok "refresh-seeds.sh --help by bare name exits 0" "$got" 0

echo "== 5. an absent or dangling link never touches PATH =="
guard() { env -i HOME="$H" PATH=/usr/bin:/bin bash --norc -c "${1:-$L1}"'; printf %s "$PATH"'; }
empty_elt() { case ":$(guard "$@"):" in *::*) echo yes ;; *) echo no ;; esac; }
mv "$LINK" "$TMP/saved"; ln -s "$MK/9.9.9/scripts" "$LINK"
ok "dangling: the target really is missing" "$(yn test -e "$LINK")" no
ok "dangling: PATH unchanged" "$(guard)" /usr/bin:/bin
ok "dangling: no empty PATH element" "$(empty_elt)" no
rm "$LINK"
ok "absent: PATH unchanged" "$(guard)" /usr/bin:/bin
ok "absent: no empty PATH element" "$(empty_elt)" no
ok "…and the check sees one in an unguarded glob form (mutant)" \
  "$(empty_elt 'export PATH="$(ls -d "$HOME"/nope/*/scripts 2>/dev/null):$PATH"')" yes

echo "== 6. a dangling link of our own shape is re-pointed =="
ln -s "$MK/0.9.0/scripts" "$LINK"; stamp "$MK/2.0.0" "$I"
ok "re-pointed to the running version" "$(readlink "$LINK")" "$MK/2.0.0/scripts"

echo "== 7. a path the stamp did not make is reported and left =="
rm "$LINK"; mkdir "$LINK"; echo mine > "$LINK/tool"
stamp "$MK/2.0.0" "$I"; rc=$?
ok "stamp still exits 0" "$rc" 0
ok "the real dir is still a dir" "$(yn test -L "$LINK")" no
ok "…with its file intact" "$(cat "$LINK/tool")" mine
ok "it says it left it alone" "$(n -c 'not a link this stamp made' "$TMP/out")" 1
ok "no PATH line for a path it does not own" "$(line | wc -l | tr -d ' ')" 0
rm -r "$LINK"
for t in "$TMP/elsewhere/scripts" "$H/.claude/plugins/cache/mk/other/1.0.0/scripts"; do
  ln -s "$t" "$LINK"; stamp "$MK/2.0.0" "$I"
  ok "a link to ${t#"$TMP"/} is left as it was" "$(readlink "$LINK")" "$t"
  rm "$LINK"
done

echo "== 8. a checkout stamp makes no link; CLAUDE_CONFIG_DIR is honoured =="
stamp "$TMP/checkout/plugin" "$I"
ok "no link from a checkout" "$(yn test -L "$LINK")" no
ok "…and it says it skipped" "$(n -c "skip  $LINK" "$TMP/out")" 1
CFG="$TMP/cfg"; MK2="$CFG/plugins/cache/mk/${PN}"; copy_plugin "$MK2/3.0.0"
stamp "$MK2/3.0.0" "$I" CLAUDE_CONFIG_DIR="$CFG"
ok "link made under CLAUDE_CONFIG_DIR" "$(readlink "$CFG/plugins/$PN/bin")" "$MK2/3.0.0/scripts"
ok "the printed line names that absolute path" "$(line)" \
  "if [ -d \"$CFG/plugins/$PN/bin\" ]; then export PATH=\"$CFG/plugins/$PN/bin:\$PATH\"; fi"
ok "nothing made under HOME's config dir" "$(yn test -L "$LINK")" no
stamp "$MK/2.0.0" "$I" PATH="$LINK:$CLEAN_PATH"
ok "already on PATH: no line printed" "$(line | wc -l | tr -d ' ')" 0

echo "== 9. no shell rc is ever written =="
for rc in .zshrc .bashrc .profile .zprofile .bash_profile .zshenv; do
  ok "$rc byte-identical" "$(cat "$H/$rc")" "# sentinel $rc"
done
RCW='(>|>>|tee|sed -i|perl -[a-z]*i|cp |mv |ln |install ).*\.(zshrc|bashrc|profile|zprofile|bash_profile|zshenv)\b'
ok "no plugin script or hook writes a shell rc" \
  "$(grep -rnE "$RCW" "$REPO/plugin" --include='*.sh' | wc -l | tr -d ' ')" 0
printf 'echo "$x" >> ~/.zshrc\n' > "$TMP/mutant.sh"
ok "…and that grep catches an append (mutant)" "$(grep -cE "$RCW" "$TMP/mutant.sh" | tr -d ' ')" 1

echo "== 10. every script that climbs out of scripts/ follows a linked scripts dir first =="
ok "no cd from a script's own dirname straight up" \
  "$(grep -lE 'cd "\$\(dirname [^)]*\)/\.\.' "$REPO"/plugin/scripts/*.sh | wc -l | tr -d ' ')" 0
for f in $(grep -lE 'cd "\$\{?(BIN_DIR|BIN|selfdir|_d)\}?/\.\.' "$REPO"/plugin/scripts/*.sh); do
  ok "${f##*/} follows its own dir link" "$(grep -cF 'if [ -L "$_d" ]' "$f" | tr -d ' ')" 1
done

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
