#!/usr/bin/env bash
#
# two-plugins.test.sh — the marketplace is exactly `loopd` and `loopd-yolo`, the mods are
# core with a switch each, and the seven entries retired on 2026-10-28 stay retired.
#
# WHAT WENT: the three mod companions (folded into core as plugin/hooks/register.ts, each a
# /config switch), the `loopd-all` bundle (a one-command install that includes yolo makes
# delegated autonomy a default instead of a choice), the `ai-bridge` rename alias (one
# release, since 3.0.0), and the accounts and llm launchers (installed nowhere; core already
# behaved as if they were absent). MIGRATION.md tells a machine what to uninstall.
#
# THE PROPERTIES, each with the failure it exists for:
#   1. The marketplace lists exactly the two names. A third entry is a decision, taken in
#      this file, never a drive-by.
#   2. Core ships the mods: hooks.json names the module, the manifest carries the switches.
#   3. No shipped document still tells a human to install a retired name, names the retired
#      command namespace, or links a retired directory — except MIGRATION.md, whose job is
#      to name them. A historical mention ("retired 2026-10-28") is fine; an install line or
#      a dead link is not. A mutant proves the sweep names both kinds.
#   4. What core kept of the retired launchers is NOTHING: no resolver, no account row in
#      the banner, no `account` key in the seed, no local-only backend key in SCHEMA — while
#      the banner's own-environment backend warning, which never depended on a companion,
#      still fires. (Ported from the two retired harnesses, which tested the launchers.)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
MJ="$REPO/.claude-plugin/marketplace.json"
BANNER="$REPO/plugin/hooks/session-banner.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/two-plugins.XXXXXX")" || {
  echo "two-plugins.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; echo "pass=0 fail=0"; exit 0; }

echo "== 1. the marketplace is exactly loopd and loopd-yolo =="
ok "two entries, by name"             "$(jq -r '[.plugins[].name] | sort | join(" ")' "$MJ")" "loopd loopd-yolo"
ok "…from ./plugin and ./plugin-yolo" "$(jq -r '[.plugins[].source] | sort | join(" ")' "$MJ")" "./plugin ./plugin-yolo"
ok "…and both sources resolve to a manifest" \
   "$(for s in plugin plugin-yolo; do [ -f "$REPO/$s/.claude-plugin/plugin.json" ] || echo "$s"; done | grep -c . | tr -d ' ')" 0
ok "no other plugin-* directory is tracked" \
   "$(git -C "$REPO" ls-files -- 'plugin-*' | cut -d/ -f1 | sort -u | grep -vx plugin-yolo | tr '\n' ' ' | sed 's/ $//')" ""
ok "core declares no dependencies" "$(jq -r 'has("dependencies") | not' "$REPO/plugin/.claude-plugin/plugin.json")" true

echo
echo "== 2. the mods are core, each a /config switch =="
ok "core ships hooks/register.ts"    "$(yn test -f "$REPO/plugin/hooks/register.ts")" yes
ok "…named by hooks/hooks.json"      "$(jq -r '.modules // [] | index("./register.ts") != null' "$REPO/plugin/hooks/hooks.json")" true
ok "…and hooks/MODS.md documents it" "$(yn test -f "$REPO/plugin/hooks/MODS.md")" yes
ok "the three switches are in userConfig, boolean, default true" \
   "$(jq -c '[.userConfig.usage, .userConfig.pane, .userConfig.signal] | map([.type, .default]) | unique' "$REPO/plugin/.claude-plugin/plugin.json")" '[["boolean",true]]'
ok "…beside the pane's mode"         "$(jq -r '.userConfig.paneMode.default' "$REPO/plugin/.claude-plugin/plugin.json")" operator
ok "the kit tests ship beside the module" \
   "$(find "$REPO/plugin/hooks/tests" -name '*.test.ts' 2>/dev/null | grep -c . | tr -d ' ')" 4

echo
echo "== 3. no shipped document still installs or links a retired name — except MIGRATION.md =="
# An INSTALL form (`<name>@…`), the retired command namespace (`/ai-bridge:…`), or a retired
# directory as a path (`plugin-mod-*/` and the four others). A bare historical name — "the
# loopd-all bundle was retired" — is allowed: the retirement has to be explainable where it bit.
RETIRED='(loopd-all|loopd-mod-usage|loopd-mod-pane|loopd-mod-signal|loopd-accounts|loopd-llm|ai-bridge)@|/ai-bridge:|plugin-(all|alias|accounts|llm|mod-usage|mod-pane|mod-signal)/'
shipped() { # <root> -> the documents a reader is shipped: core, the companion, the root docs, the rules
  ( cd "$1" && git ls-files -- plugin plugin-yolo README.md CLAUDE.md .claude docs ':!docs/releases' ':!docs/spikes' 2>/dev/null \
      | grep -E '\.(md|html|json|sh|ts)$' )
}
hits() { # <root> -> file:line per hit, outside MIGRATION.md
  ( cd "$1" && shipped "$1" | tr '\n' '\0' | xargs -0 grep -nE -- "$RETIRED" 2>/dev/null ) | grep -v '^MIGRATION.md:' || true
}
ok "no install line, namespace or retired path on the shipped surface" "$(hits "$REPO" | cut -c1-200 | tr '\n' ' ' | sed 's/ $//')" ""
ok "…while MIGRATION.md names every retired install, with the uninstall" \
   "$(for n in loopd-mod-usage loopd-mod-pane loopd-mod-signal loopd-all ai-bridge loopd-accounts loopd-llm; do
        grep -qF "/plugin uninstall $n@" "$REPO/MIGRATION.md" || echo "$n"; done | tr '\n' ' ' | sed 's/ $//')" ""
ok "…and says the mods now live in core with /config switches" \
   "$([ "$(grep -cE 'register\.ts' "$REPO/MIGRATION.md")" -ge 1 ] && [ "$(grep -cF '/config' "$REPO/MIGRATION.md")" -ge 1 ] && echo yes || echo no)" yes
# The sweep bites: a doc that takes an install line back, and one that links a retired
# directory, are both NAMED — and a mention that is neither stays quiet.
MUT="$TMP/mut"; mkdir -p "$MUT/plugin/hooks" "$MUT/docs"
( cd "$MUT" && git init -q . && git config user.email t@example.com && git config user.name t ) >/dev/null 2>&1
printf 'Install the usage mod: `/plugin install loopd-mod-usage@loopd`\n' > "$MUT/plugin/hooks/MODS.md"
printf 'See [the pane](../plugin-mod-pane/README.md).\n' > "$MUT/README.md"
printf 'The loopd-all bundle and the ai-bridge alias were retired on 2026-10-28.\n' > "$MUT/docs/history.md"
printf '/plugin uninstall loopd-all@loopd\n' > "$MUT/MIGRATION.md"
( cd "$MUT" && git add -A >/dev/null && git commit -q -m x ) >/dev/null 2>&1
ok "mutant: an install line and a dead link are both named, the history line and MIGRATION.md are not" \
   "$(hits "$MUT" | cut -d: -f1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" "README.md plugin/hooks/MODS.md"

echo
echo "== 4. what core kept of the launchers is nothing — and the backend warning still fires =="
# path-scan: absent — asserted GONE; the resolver was retired with the accounts companion
ok "no resolve-account.sh"            "$(yn test -e "$REPO/plugin/scripts/resolve-account.sh")" no
ok "…and nothing in the plugin calls it" \
   "$(grep -rl 'resolve-account.sh' "$REPO/plugin" 2>/dev/null | grep -c . | tr -d ' ')" 0
ok "no core script or hook runs a launcher" \
   "$(grep -rlE '(ai-bridge|loopd)-(claude|deepseek)|LOOPD_ACCOUNTS_HOME|allowSubstituteBackend' "$REPO/plugin" 2>/dev/null | grep -c . | tr -d ' ')" 0
ok "the seed config carries no account key" "$(jq -r 'has("account") or has("$account")' "$REPO/plugin/seed/instance.config.json")" false
ok "SCHEMA.md carries no allowSubstituteBackend row" "$(grep -c 'allowSubstituteBackend' "$REPO/plugin/seed/SCHEMA.md")" 0
# The banner, on a fixture bundle with an EMPTY config dir: no account row, ever; and the
# NOT ANTHROPIC warning, read from the banner's own environment, fires with nothing installed.
BB="$TMP/bb"; mkdir -p "$BB"
printf '{ "org": "x" }\n' > "$BB/instance.config.json"
EMPTY="$TMP/empty-cfg"; mkdir -p "$EMPTY"
banner() { CLAUDE_PROJECT_DIR="$BB" CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_CONFIG_DIR="$EMPTY" \
           ANTHROPIC_BASE_URL="${1-}" bash "$BANNER" --no-color 2>/dev/null; }
ok "the banner prints no account row"               "$(banner | grep -ciE 'CLAUDE ACCOUNT|^Account ')" 0
ok "a substituted backend is called out"            "$(banner 'https://api.deepseek.com/anthropic' | grep -c 'NOT ANTHROPIC')" 1
ok "…and the backend is NAMED"                      "$(banner 'https://api.deepseek.com/anthropic' | grep -c 'backend is api.deepseek.com')" 1
ok "…with nothing installed at all"                 "$(yn test ! -e "$EMPTY/plugins/installed_plugins.json")" yes
ok "another backend is named as itself"             "$(banner 'https://gateway.example.org/v1' | grep -c 'backend is gateway.example.org')" 1
ok "unset -> the banner says nothing about a backend" "$(banner | grep -c 'NOT ANTHROPIC')" 0
# /<plugin>:welcome EXECS this hook — asserted on the skill's own contract, so a second copy
# of the banner could not satisfy it.
ok "/${PN}:welcome execs the hook, not a copy"      "$(grep -c 'exec bash "$hook"' "$REPO/plugin/scripts/welcome.sh")" 3
# Keys come from the environment or a gitignored .env — never a tracked file (the rule the
# llm launcher's README used to carry; the seed and the stamp still hold it).
ok "the seed .gitignore ignores .env"               "$(grep -cxF '.env' "$REPO/plugin/seed/.gitignore")" 1
ok "…and /${PN}:init appends it to an older bundle" "$(grep -c "grep -qxF '.env'" "$REPO/plugin/scripts/init-bundle.sh")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
