#!/usr/bin/env bash
#
# bg-brief-quoting.test.sh — the brief in plugin/tick-steps/step-3-dispatch.md's spawn reaches
# `claude` byte-identical. It runs the documented block itself, the brief single-quoted with
# each ' written '\'', against a stub `claude` that records argv, and proves the old
# double-quoted form loses a backtick span so the check can fail. Reasoning:
# dispatch-reporting-defects/task-034.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S3="$REPO/plugin/tick-steps/step-3-dispatch.md"
S4="$REPO/plugin/tick-steps/step-4-advance.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bgbrief.XXXXXX")" || {
  echo "bg-brief-quoting.test: mktemp -d failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

mkdir -p "$TMP/bin" "$TMP/wt"
printf '#!/bin/sh\nprintf %%s "$2" > "$GOT"\necho "backgrounded · stub0000"\n' > "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"

MARK="<the whole brief>"
BLOCK="$(awk -v m="$MARK" '/^   ```bash$/ {f=1; b=""; next}
  f && /^   ```$/ {f=0; if (index(b, m)) {printf "%s", b; exit}; next}
  f {b = b $0 "\n"}' "$S3")"
ok 'step 3 has one spawn block naming the brief once' \
   "$(grep -cF "$MARK" <<<"$BLOCK" | tr -d ' ')" 1

# The trailing newline of the brief is kept out of $(…) by the x sentinel.
BRIEF="$(printf 'Fix `touch %s/ran` and $(touch %s/ran2) and $HOME,\nthe owner'"'"'s \\n "quoted" line' "$TMP" "$TMP"; echo x)"
BRIEF="${BRIEF%x}"
ESC="$(printf '%s' "$BRIEF" | sed "s/'/'\\\\''/g"; echo x)"
ESC="${ESC%x}"

run() { # <block with the brief marker replaced by its quoted form>
  local cmd="$1"
  cmd="${cmd//<worktree>/$TMP/wt}"; cmd="${cmd//<assignee>/software-engineer}"
  cmd="${cmd//<the alias you resolved>/haiku}"; cmd="${cmd//<bundle root>/$TMP}"
  rm -f "$TMP/got" "$TMP/ran" "$TMP/ran2"
  printf '%s\n' "$cmd" > "$TMP/spawn.sh"
  PATH="$TMP/bin:$PATH" GOT="$TMP/got" bash "$TMP/spawn.sh" >/dev/null 2>&1
}
expected() { printf '%s' "$BRIEF" > "$TMP/want"; }
expected

echo "== the documented single-quoted form =="
run "${BLOCK%%"$MARK"*}$ESC${BLOCK#*"$MARK"}"
ok 'the spawn ran the stub' "$(yn test -f "$TMP/got")" yes
ok 'the brief arrives byte-identical' "$(yn cmp -s "$TMP/got" "$TMP/want")" yes
ok 'the backtick span did not run' "$(yn test -e "$TMP/ran")" no
ok 'the $(...) span did not run' "$(yn test -e "$TMP/ran2")" no

echo "== control: the old double-quoted form mangles the same brief =="
DQ="${BLOCK//\'$MARK\'/\"$MARK\"}"
ok 'control block is double-quoted' "$(grep -cF "\"$MARK\"" <<<"$DQ" | tr -d ' ')" 1
run "${DQ%%"$MARK"*}$BRIEF${DQ#*"$MARK"}"
ok 'the brief does NOT arrive intact' "$(yn cmp -s "$TMP/got" "$TMP/want")" no
ok 'the backtick span ran' "$(yn test -e "$TMP/ran")" yes

echo "== the docs say so, and no double-quoted spawn is left =="
ok 'step 3 spells an embedded quote the escaped way' "$(yn grep -qF "'\\''" "$S3")" yes
ok 'step 3 says backticks and $ are literal' "$(yn grep -qF 'a backtick and a `$` are literal' "$S3")" yes
ok 'step 4 resume message is single-quoted' "$(yn grep -qF -e "--resume \"\$full\" '<the message>'" "$S4")" yes
ok 'no claude --bg "…" form left in plugin/' "$(grep -rlF 'claude --bg "' "$REPO/plugin" | wc -l | tr -d ' ')" 0

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
