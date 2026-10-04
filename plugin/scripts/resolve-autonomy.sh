#!/usr/bin/env bash
#
# resolve-autonomy.sh — the ONE reader of "does delegated autonomy exist here, and
# which file defines its modes".
#
#   Usage: resolve-autonomy.sh [--bundle DIR]
#
#   exit 0  prints the absolute path of the AUTONOMY.md in force
#   exit 1  prints nothing — no capability file, so EVERY project is `gated`
#   exit 2  usage error
#
# WHY IT EXISTS. `AUTONOMY.md` is the capability: present, a project's `autonomy:` field
# selects a mode; absent, the field is inert and both human gates hold. That presence
# check used to be one `[ -f "$root/AUTONOMY.md" ]` inside `commit-as.sh`, against a file
# `install.sh` stamped from `symlink/`. Nothing stamps it any more (ai-bridge-v2/task-013),
# so this turns the presence check into the EXTENSION POINT: core stays gated-only and
# ships no capability file at all, and the yolo companion — a separate plugin in
# the same marketplace — is what ships one.
#
# THE ORDER IS ROOT FIRST, AND THAT IS A COMPATIBILITY GUARANTEE, NOT A PREFERENCE. A
# v1-era bundle carries a real `AUTONOMY.md` at its root; it keeps working byte for byte,
# with or without any companion installed, and a companion can never override what such a
# bundle says. Root wins.
#
# WHERE A COMPANION'S FILES LIVE — `<companion plugin root>/companion/<name>`, a fixed
# relative path, here `companion/AUTONOMY.md`. A dedicated directory rather than the
# plugin root itself, so a companion's own `README.md` or docs can never be mistaken for
# something core reads, and so the next companion (an account switch, an alternative LLM
# backend) has one obvious place to put its file.
#
# WHICH PLUGINS COUNT AS COMPANIONS — the ones installed from the SAME MARKETPLACE core
# itself came from, which is what "registers as a marketplace entry" cashes out to. Not
# "any installed plugin carrying that path": arming delegated authority is exactly the
# capability that must not be reachable by an unrelated plugin someone installed for some
# other reason.
#
# READ THE REGISTRY, NEVER THE CACHE TREE. `~/.claude/plugins/cache/<marketplace>/<plugin>/
# <version>/` keeps every version ever fetched, uninstalled ones included (measured: 11
# stale `ai-bridge-v2` version directories on a machine with it uninstalled). A cache scan
# would therefore keep answering "yes" forever, and "uninstall the companion and every
# project is gated again" — the whole point of the design — would be false.
# `installed_plugins.json` is what is INSTALLED. A registry entry naming a directory that
# is GONE is likewise not a companion: the answer is `gated`, never "then use a sibling
# version that is still cached", which is the half-uninstalled state a failed upgrade
# leaves behind.
# THAT PARAGRAPH HAS A READER — `tests/companion-plugins.test.sh` § 9, against a fixture
# laid out as the real cache is (three stale version directories under
# `<config>/plugins/cache/<marketplace>/<plugin>/<version>/`). It is there because § 4(c),
# which already said "no registry entry -> gated", uses a fixture that is nowhere near a
# cache tree: measured on this branch, splicing a cache-tree fallback into this file left
# § 1-8 at 37 PASS / 0 FAIL. § 9 drives that same mutant and refuses it.
#
# IT FAILS CLOSED ON EVERYTHING IT CANNOT READ. No registry, an unparseable one, a
# registry whose formatting changed under us, a companion root that no longer exists on
# disk: all of them yield no companion, which is `gated`. The safe end of every unknown is
# the end where the human keeps both gates, so a degraded read costs a human decision and
# never a merge nobody approved.
#
# GENERIC TEMPLATE FILE — ships with the `loopd` plugin; do not edit per instance. It
# reads no org, repo or path literal, and derives even its own marketplace's name.
#
# Verified by tests/companion-plugins.test.sh and tests/plugin-name.test.sh.
set -uo pipefail
_pn="$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"; if [ -r "$_pn" ]; then . "$_pn"; fi

COMPANION_REL="companion/AUTONOMY.md"
DEFAULT_MARKETPLACE="${PLUGIN_MARKETPLACE:-}"

bundle="."
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--bundle` leaves one argument and `shift 2`
    # FAILS WITHOUT SHIFTING, which with no `set -e` spins this loop forever.
    --bundle)
      [ $# -ge 2 ] || { echo "resolve-autonomy: --bundle needs a directory" >&2; exit 2; }
      bundle="$2"; shift 2 ;;
    -h|--help) sed -n '3,9p' "$0"; exit 0 ;;
    -*) echo "resolve-autonomy: unknown flag $1" >&2; exit 2 ;;
    *)  echo "resolve-autonomy: unexpected argument $1" >&2; exit 2 ;;
  esac
done

# 1. The bundle root, which wins outright.
if [ -f "$bundle/AUTONOMY.md" ]; then
  root_abs="$(cd "$bundle" 2>/dev/null && pwd)" || root_abs=""
  [ -n "$root_abs" ] || { echo "resolve-autonomy: cannot resolve $bundle" >&2; exit 2; }
  printf '%s\n' "$root_abs/AUTONOMY.md"
  exit 0
fi

# 2. An installed companion.
#
# `${HOME:-}` and not `$HOME`: under `set -u` a bare `$HOME` ABORTS where the variable is
# unset (a `git` hook, a stripped `env -i` shell), and this script's callers read its exit
# status — an abort is exit 1, which happens to be the right answer here by luck rather
# than by design, and a stderr line nobody asked for. Unset resolves to a path that does
# not exist, which is the same fail-closed `gated` every other unknown gets.
registry="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/plugins/installed_plugins.json"
[ -f "$registry" ] || exit 1

# This plugin's own root: `<...>/scripts/resolve-autonomy.sh` -> `<...>`. Used twice —
# to learn which marketplace core came from, and to make sure core is never read as its
# own companion.
_d="$(dirname "$0")"; if [ -L "$_d" ] && [ ! -f "$(dirname "$_d")/VERSION" ]; then _t="$(readlink "$_d")"; case "$_t" in /*) _d="$_t" ;; *) _d="$(dirname "$_d")/$_t" ;; esac; fi
self_root="$(cd "$_d/.." 2>/dev/null && pwd)" || self_root=""

# `<plugin>@<marketplace>` TAB `<installPath>`, one per installed copy.
#
# The registry is written pretty-printed, one key per line, so a line-wise read is enough
# and a JSON string cannot span lines. A future format this parser does not understand
# yields NO pairs, which is the fail-closed direction (no companion => gated) rather than
# a wrong answer — the reason this is not worth a jq dependency the promotion guard would
# then inherit.
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
[ -n "$entries" ] || exit 1

# Which marketplace is core's own? Answered from the registry (match this plugin root
# against the recorded install paths) rather than from the cache directory's shape, which
# is the plugin manager's business and not a contract. Running from a checkout matches
# nothing and falls back to this repo's own marketplace name.
marketplace=""
if [ -n "$self_root" ]; then
  while IFS="$(printf '\t')" read -r key path; do
    [ "$path" = "$self_root" ] || continue
    marketplace="${key##*@}"
    break
  done <<EOF
$entries
EOF
fi
[ -n "$marketplace" ] || marketplace="$DEFAULT_MARKETPLACE"

while IFS="$(printf '\t')" read -r key path; do
  [ -n "$key" ] && [ -n "$path" ] || continue
  case "$key" in *"@$marketplace") ;; *) continue ;; esac
  [ "$path" = "$self_root" ] && continue   # core is not its own companion
  if [ -f "$path/$COMPANION_REL" ]; then
    printf '%s\n' "$path/$COMPANION_REL"
    exit 0
  fi
done <<EOF
$entries
EOF

exit 1
