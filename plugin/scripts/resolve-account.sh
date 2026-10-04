#!/usr/bin/env bash
#
# resolve-account.sh — the ONE reader of "which Claude account is this bundle on".
#
#   Usage: resolve-account.sh [--bundle DIR]
#
#   Prints one TSV line: <declared><TAB><active><TAB><launcher>
#   exit 0  match      declared == active
#   exit 1  inert      no accounts companion, or no `account:` declared — silent
#   exit 3  MISMATCH   declared != active
#   exit 4  NO ACCOUNT declared, but this session was not started on one
#   exit 2  usage
#
# It reads a config key, an env var and a plugin registry. It never reads, writes or
# prints a credential. Reasoning: projects/ai-bridge-next/tasks/task-002-*.md.
# GENERIC TEMPLATE FILE — ships with the `loopd` plugin; do not edit per instance.
# Verified by tests/companion-account-switch.test.sh.
set -uo pipefail
_pn="$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"; if [ -r "$_pn" ]; then . "$_pn"; fi

COMPANION_REL="companion/accounts.md"
LAUNCHER_REL="bin/ai-bridge-claude"
DEFAULT_MARKETPLACE="${PLUGIN_MARKETPLACE:-}"

bundle="."
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--bundle` leaves one argument and `shift 2`
    # FAILS WITHOUT SHIFTING, which with no `set -e` spins this loop forever.
    --bundle)
      [ $# -ge 2 ] || { echo "resolve-account: --bundle needs a directory" >&2; exit 2; }
      bundle="$2"; shift 2 ;;
    -h|--help) sed -n '3,13p' "$0"; exit 0 ;;
    -*) echo "resolve-account: unknown flag $1" >&2; exit 2 ;;
    *)  echo "resolve-account: unexpected argument $1" >&2; exit 2 ;;
  esac
done

TAB="$(printf '\t')"

# A label reaches a banner, so it is a closed charset rather than whatever the config says.
sane() { case "$1" in ""|*[!A-Za-z0-9._-]*) return 1 ;; esac; [ "${#1}" -le 32 ]; }

# --- the installed companion -----------------------------------------------------------
# Same registry read as resolve-autonomy.sh, and deliberately its own copy: that file is
# the delegated-authority gate and is not refactored by a feature branch.
companion_root=""
registry="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/plugins/installed_plugins.json"
if [ -f "$registry" ]; then
  _d="$(dirname "$0")"; if [ -L "$_d" ] && [ ! -f "$(dirname "$_d")/VERSION" ]; then _t="$(readlink "$_d")"; case "$_t" in /*) _d="$_t" ;; *) _d="$(dirname "$_d")/$_t" ;; esac; fi
  self_root="$(cd "$_d/.." 2>/dev/null && pwd)" || self_root=""
  entries="$(awk '
    /^[[:space:]]*"[^"]+@[^"]+"[[:space:]]*:[[:space:]]*\[/ {
      k = $0
      sub(/^[[:space:]]*"/, "", k)
      sub(/"[[:space:]]*:[[:space:]]*\[.*$/, "", k)
      key = k
      next
    }
    /"installPath"[[:space:]]*:[[:space:]]*"/ {
      p = $0
      sub(/^.*"installPath"[[:space:]]*:[[:space:]]*"/, "", p)
      sub(/".*$/, "", p)
      if (key != "" && p != "") print key "\t" p
    }
  ' "$registry" 2>/dev/null)" || entries=""

  marketplace=""
  if [ -n "$self_root" ] && [ -n "$entries" ]; then
    while IFS="$TAB" read -r key path; do
      [ "$path" = "$self_root" ] || continue
      marketplace="${key##*@}"; break
    done <<EOF
$entries
EOF
  fi
  [ -n "$marketplace" ] || marketplace="$DEFAULT_MARKETPLACE"

  while IFS="$TAB" read -r key path; do
    [ -n "$key" ] && [ -n "$path" ] || continue
    case "$key" in *"@$marketplace") ;; *) continue ;; esac
    [ "$path" = "$self_root" ] && continue
    if [ -f "$path/$COMPANION_REL" ]; then companion_root="$path"; break; fi
  done <<EOF
$entries
EOF
fi
[ -n "$companion_root" ] || exit 1

# --- what the bundle declares ----------------------------------------------------------
declared=""
resolver="$(dirname "$0")/resolve-config.sh"
if [ -f "$resolver" ] && command -v python3 >/dev/null 2>&1; then
  declared="$(bash "$resolver" --instance "$bundle" account 2>/dev/null)" || declared=""
fi
if [ -z "$declared" ]; then
  for f in "$bundle/instance.config.local.json" "$bundle/instance.config.json"; do
    [ -f "$f" ] || continue
    declared="$(sed -n 's/.*"account"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
    [ -n "$declared" ] && break
  done
fi
sane "$declared" || exit 1

# --- what this session is actually on --------------------------------------------------
# The launcher exports AI_BRIDGE_ACCOUNT beside CLAUDE_CONFIG_DIR; a session started any
# other way carries neither, which is the "or none" case and must be loud, not silent.
active="${AI_BRIDGE_ACCOUNT:-}"
if [ -z "$active" ] && [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  home="${AI_BRIDGE_ACCOUNTS_HOME:-${HOME:-}/.claude-accounts}"
  case "$CLAUDE_CONFIG_DIR" in "$home"/*) active="$(basename "$CLAUDE_CONFIG_DIR")" ;; esac
fi
sane "$active" || active=""

printf '%s\t%s\t%s\n' "$declared" "$active" "$companion_root/$LAUNCHER_REL"
[ -n "$active" ] || exit 4
[ "$active" = "$declared" ] || exit 3
exit 0
