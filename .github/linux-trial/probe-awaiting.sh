#!/usr/bin/env bash
# LINUX TRIAL DIAGNOSTIC — not a harness, not shipped, deleted with the trial branch.
# awaiting-queue.test.sh's "no AWAITING.md and an empty AWAITING.md say the same nothing"
# failed on ubuntu-latest and prints no diff on FAIL, so this reproduces its two banner
# runs and prints both human channels verbatim, plus stderr and the raw envelope.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
. "$REPO/plugin/scripts/bundle-paths.sh"
HOOK="$REPO/plugin/hooks/session-banner.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/probe-awaiting.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
INST="$TMP/inst"
mkdir -p "$INST/.claude/agents" "$INST/$AB_DIR"
printf '{\n  "org": "example-org"\n}\n' > "$INST/instance.config.json"

field() { python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception as e: print("<unparseable: %s>" % e); sys.exit(0)
for k in sys.argv[1].split("."): d = d.get(k, "") if isinstance(d, dict) else ""
print(d)' "$1"; }

run_banner() { # <label>
  local out
  out="$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK" --format json 2>"$TMP/stderr")"; local rc=$?
  echo "===== $1: rc=$rc"
  echo "--- stderr:"; cat "$TMP/stderr"
  echo "--- systemMessage:"; printf '%s' "$out" | field systemMessage | cat -A 2>/dev/null || printf '%s' "$out" | field systemMessage | od -c | head -40
  echo "--- raw envelope (first 60 lines):"; printf '%s\n' "$out" | head -60
}

run_banner "no AWAITING.md"
printf '%s' "$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK" --format json 2>/dev/null | field systemMessage)" > "$TMP/a"
printf '## 🔴 Awaiting you (0)\n_None._\n' > "$INST/$AB_AWAITING"
run_banner "AWAITING.md with (0)"
printf '%s' "$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK" --format json 2>/dev/null | field systemMessage)" > "$TMP/b"
echo "===== diff (no file vs (0) file):"
diff "$TMP/a" "$TMP/b" && echo "(identical)"
echo "===== environment: LANG=${LANG:-<unset>} LC_ALL=${LC_ALL:-<unset>} TERM=${TERM:-<unset>} CI=${CI:-<unset>}"
