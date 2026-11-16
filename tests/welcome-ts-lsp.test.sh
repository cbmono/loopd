#!/usr/bin/env bash
# welcome-ts-lsp.test.sh — the `ts-lsp-binary` row of plugin/scripts/welcome.sh check.
# The official typescript-lsp plugin configures a language server but installs no binary;
# the row warns only when the plugin is enabled AND typescript-language-server is not on
# PATH, prints the install command, and runs nothing. HOME, CLAUDE_CONFIG_DIR and PATH are
# all fixtures, so the machine's own settings and npm globals never decide a case.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WELCOME="$HERE/../plugin/scripts/welcome.sh"
[ -f "$WELCOME" ] || { echo "welcome-ts-lsp.test: missing $WELCOME" >&2; exit 2; }
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$HERE/../plugin/scripts/bundle-paths.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/welcome-ts-lsp.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
saw() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

# The smallest bundle `welcome.sh check` accepts.
B="$TMP/bundle"; mkdir -p "$B/.claude" "$B/$AB_DIR"
printf '{\n  "org": "example-org"\n}\n' > "$B/instance.config.json"
printf 'stub\n' > "$B/$AB_SCHEMA"

# PATH without any directory that already holds the binary, so "missing" is missing here
# even on a machine that has it installed globally.
CLEAN_PATH=""
IFS=: read -r -a _dirs <<<"$PATH"
for d in "${_dirs[@]}"; do
  [ -n "$d" ] && [ ! -x "$d/typescript-language-server" ] && CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$d"
done
STUB="$TMP/stub-bin"; mkdir -p "$STUB"
printf '#!/bin/sh\nexit 0\n' > "$STUB/typescript-language-server"; chmod +x "$STUB/typescript-language-server"

CFG="$TMP/home/.claude"; mkdir -p "$CFG"
settings() { printf '%s\n' "$1" > "$CFG/settings.json"; }
run() { # <PATH> — the row's lines only: its verdict and the hint under it
  HOME="$TMP/home" CLAUDE_CONFIG_DIR="$CFG" PATH="$1" \
    bash "$WELCOME" check --instance "$B" --style plain 2>/dev/null \
    | awk '/^(✓|⚠) typescript-lsp:/{print; f=1; next} f && /^    ↳/{print} {f=0}'
}
INSTALL='npm i -g typescript-language-server typescript'

echo "== 1. the row is listed, human tier, off the banner path, never repaired =="
ok "ts-lsp-binary|human|no" \
  "$(bash "$WELCOME" check --list | awk -F'\t' '$1=="ts-lsp-binary"{print $2"|"$3}')" "human|no"
ok "…with no fix function" "$(grep -c '^fix_ts_lsp_binary()' "$WELCOME" | tr -d ' ')" 0

echo "== 2. enabled + binary missing ⇒ one ⚠ naming the binary, and the install command =="
settings '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":true}}'
out="$(run "$CLEAN_PATH")"
ok "⚠ line"                                "$(grep -c '^⚠ typescript-lsp:' <<<"$out" | tr -d ' ')" 1
ok "…naming typescript-language-server"    "$(saw "$out" 'typescript-language-server is not on PATH')" yes
ok "…and the install command"              "$(saw "$out" "$INSTALL")" yes

echo "== 3. enabled + binary present ⇒ no warning, no install line =="
out="$(run "$STUB:$CLEAN_PATH")"
ok "a ✓ verdict, not silence"              "$(grep -c '^✓ typescript-lsp: enabled' <<<"$out" | tr -d ' ')" 1
ok "no ⚠"                                  "$(grep -c '^⚠' <<<"$out" | tr -d ' ')" 0
ok "no install line"                       "$(saw "$out" "$INSTALL")" no

echo "== 4. not enabled ⇒ no warning, no install line =="
for case in '{"enabledPlugins":{"security-guidance@claude-plugins-official":true}}' \
            '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":false}}'; do
  settings "$case"
  out="$(run "$CLEAN_PATH")"
  ok "✓ not enabled for $case"             "$(grep -c '^✓ typescript-lsp: not enabled' <<<"$out" | tr -d ' ')" 1
  ok "no ⚠ for $case"                      "$(grep -c '^⚠' <<<"$out" | tr -d ' ')" 0
  ok "…no install line"                    "$(saw "$out" "$INSTALL")" no
done
# A bundle's own settings can switch the user's `true` off.
settings '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":true}}'
printf '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":false}}\n' > "$B/.claude/settings.local.json"
out="$(run "$CLEAN_PATH")"
ok "a project-local false overrides the user's true" "$(grep -c '^⚠' <<<"$out" | tr -d ' ')" 0
rm -f "$B/.claude/settings.local.json"

echo
total=$((pass + fail))
ok "exactly 15 assertions ran"             "$total" 15

echo
echo "welcome-ts-lsp.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
