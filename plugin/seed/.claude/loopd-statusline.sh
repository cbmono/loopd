#!/usr/bin/env bash
# loopd-statusline.sh — this bundle's `statusLine`. SEED content: yours once copied,
# safe to delete with the key in .claude/settings.json. It resolves the plugin at RUN
# time: a `statusLine` command gets no `${CLAUDE_PLUGIN_ROOT}` and a pinned path rots.
set -uo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)" || exit 0
cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache"
line="$(ls -d "$cache"/*/loopd/*/scripts/status-line.sh 2>/dev/null | sort -V | tail -n1)"
[ -n "$line" ] || exit 0
exec bash "$line" --instance "$here"
