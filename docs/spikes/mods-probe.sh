#!/usr/bin/env bash
#
# mods-probe.sh — measures docs/spikes/mods-in-background-sessions.md: which mod events fire
# in a NON-interactive session (`claude -p`, and `claude --bg` when it accepts --plugin-dir),
# what `turn.step` / `turn.complete` carry, and where `$.store` lands on disk.
# Probe 1 needs no auth. Probes 2-4 spend one cheap haiku turn each in a temp cwd and are
# skipped without --live. Nothing here touches a bundle; the probe mod writes only to its
# own plugin store file, which probe 4 names so you can delete it.
# Exit 0 always: this reports, it never gates.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROBE="$HERE/mods-probe"
STORE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/store"
LAB="$(mktemp -d)"; LIVE="${1:-}"
trap 'rm -rf "$LAB"' EXIT
say() { printf '%-46s %s\n' "$1" "$2"; }

printf 'claude %s\n\n' "$(claude --version </dev/null 2>/dev/null)"
say "1 validate --strict" "$(claude plugin validate "$PROBE" --strict </dev/null 2>&1 | grep -E 'hooks:|calls:|passed|error' | tr '\n' ' ' | cut -c1-200)"
say "  types written beside the mod" "$(ls "$PROBE/.claude-plugin/types/claude-code/index.d.ts" 2>/dev/null || echo 'not yet: a --plugin-dir session writes it')"

[ "$LIVE" = "--live" ] || { printf '\n(probes 2-4 need auth and one haiku turn each: re-run with --live)\n'; exit 0; }
cd "$LAB" || exit 0

T0=$(date +%s)
claude -p "reply with the single word ok" --model haiku --plugin-dir "$PROBE" --output-format json </dev/null > "$LAB/p.json" 2>"$LAB/p.err"
say "2 claude -p with --plugin-dir, exit" "$? after $(( $(date +%s) - T0 ))s; result usage: $(sed -n 's/.*"usage":{\([^}]*\)}.*/\1/p' "$LAB/p.json" | cut -c1-120)"
say "  stderr (first line)" "$(sed -n 1p "$LAB/p.err" | cut -c1-120)"

say "3 /probe-dump in a second -p run" "$(claude -p "/probe-dump" --plugin-dir "$PROBE" </dev/null 2>/dev/null | cut -c1-160 | sed -n '1,12p' | tr '\n' ';')"

if claude --help </dev/null 2>&1 | grep -q -- '--plugin-dir' && claude --help </dev/null 2>&1 | grep -q -- '--bg'; then
  OUT="$(claude --bg 'reply with the single word ok' --model haiku --plugin-dir "$PROBE" </dev/null 2>&1)"
  say "4 claude --bg with --plugin-dir" "$(printf '%s' "$OUT" | sed -n 1p | cut -c1-100)"
  sleep 20
fi

printf '\nstore files written by the probe (delete them when done):\n'
ls -la "$STORE"/loopd-probe_* 2>/dev/null || echo "  none under $STORE"
for f in "$STORE"/loopd-probe_*.json; do
  [ -f "$f" ] || continue
  printf '\n%s\n' "$f"; jq -r 'to_entries[] | "\(.key) \(.value | tojson)"' "$f" 2>/dev/null | cut -c1-240
done
