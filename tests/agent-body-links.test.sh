#!/usr/bin/env bash
#
# agent-body-links.test.sh — a path written in an agent body must resolve from where the
# BODY lives, which is never where the agent runs.
#
# THE CLASS. An agent body is READ from `~/.claude/plugins/cache/<marketplace>/<plugin>/
# <version>/agents/`, but the agent EXECUTES with a bundle or a product-repo worktree as
# its cwd. So a relative escape is correct from at most one of the two, and `](../../
# CONVENTIONS.md)` — 13 of them, every agent file — was correct from neither: it resolved
# to `cache/<marketplace>/<plugin>/CONVENTIONS.md`, the directory that holds version
# directories. Roughly one third of dispatched engineers opened with `File does not exist`.
#
# WHY NOT tests/seed-doc-links.test.sh. That harness walks the SEEDED docs inside a
# stamped bundle and resolves each link where it lands. Agent bodies are never stamped
# into a bundle, so there is no tree there in which to resolve them.
#
# WHAT THIS REACHES. Two spellings, because the fix converted one into the other:
#   1. markdown links — `](<target>)` — resolved from `plugin/agents/`, the body's own
#      directory, which is what `<version>/agents/` is in an install.
#   2. `${CLAUDE_PLUGIN_ROOT}/<path>` references, resolved under `plugin/`. These are the
#      42 live subjects today; section 1 alone would be a guard over an empty set, which
#      is this file's own failure mode.
# External targets (http, https, mailto), bare `#anchor`s, `<url>`-style placeholders and
# bare prose words are not paths and are skipped.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
[ -d "$TPL/plugin/agents" ] || { echo "agent-body-links.test: missing $TPL/plugin/agents" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# scan <plugin-dir> — one `<file>:<line>: <target>` per reference that does not resolve.
# Empty output is the green state. Reports the file and the line because the spelling
# alone ("../../CONVENTIONS.md") never says which of thirteen copies is meant.
scan() {
  local plug="$1" agents="$1/agents" hit f ln target abs
  [ -d "$agents" ] || { echo "$agents: not a directory"; return; }

  grep -onE '\]\([^)]*\)' "$agents"/*.md 2>/dev/null | while IFS= read -r hit; do
    f="${hit%%:*}"; hit="${hit#*:}"
    ln="${hit%%:*}"; target="${hit#*:}"
    target="${target#](}"; target="${target%)}"
    target="${target%%#*}"
    case "$target" in
      ''|http://*|https://*|mailto:*|'<'*) continue ;;
      [A-Za-z0-9_-]*) case "$target" in */*|*.*) ;; *) continue ;; esac ;;
    esac
    case "$target" in
      '${CLAUDE_PLUGIN_ROOT}'/*) abs="$plug/${target#'${CLAUDE_PLUGIN_ROOT}'/}" ;;
      *)                         abs="$agents/$target" ;;
    esac
    [ -e "$abs" ] || echo "$f:$ln: $target"
  done

  grep -onE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./*-]*' "$agents"/*.md 2>/dev/null | while IFS= read -r hit; do
    f="${hit%%:*}"; hit="${hit#*:}"
    ln="${hit%%:*}"; target="${hit#*:}"
    target="${target#'${CLAUDE_PLUGIN_ROOT}'/}"
    target="${target%"${target##*[!.,;:)]}"}"
    [ -n "$target" ] || continue
    [ -e "$plug/$target" ] || echo "$f:$ln: \${CLAUDE_PLUGIN_ROOT}/$target"
  done
}

# =======================================================================================
echo "== 1. every path an agent body names resolves from the body's own directory =="
# =======================================================================================
FOUND="$(scan "$TPL/plugin")"
[ -z "$FOUND" ] || printf '%s\n' "$FOUND" | sed 's/^/        /'
ok "no unresolvable path in plugin/agents/*.md" "$(printf '%s' "$FOUND" | grep -c . | tr -d ' ')" 0

# The escape this harness exists for, pinned by spelling as well as by resolution: it is
# dead from the cache no matter what follows it, so no future target makes it correct.
ok "no '](../../' escape survives in an agent body" \
  "$(grep -rlF '](../../' "$TPL/plugin/agents" 2>/dev/null | grep -c . | tr -d ' ')" 0

# =======================================================================================
echo "== 2. mutant: one dead link and one dead plugin-root path are both caught, by line =="
# =======================================================================================
MUT="$(mktemp -d "${TMPDIR:-/tmp}/agent-body-links.XXXXXX")" || { echo "agent-body-links.test: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$MUT"' EXIT
cp -R "$TPL/plugin" "$MUT/plugin"

ok "the copy is green before mutation" "$(scan "$MUT/plugin" | grep -c . | tr -d ' ')" 0

printf '%s\n' 'See [`CONVENTIONS.md`](../../CONVENTIONS.md) for the rest.' >> "$MUT/plugin/agents/auditor.md"
printf '%s\n' 'Run `${CLAUDE_PLUGIN_ROOT}/scripts/no-such-script.sh` first.' >> "$MUT/plugin/agents/cataloguer.md"
AUD_LN="$(grep -c '' "$MUT/plugin/agents/auditor.md")"
CAT_LN="$(grep -c '' "$MUT/plugin/agents/cataloguer.md")"
MFOUND="$(scan "$MUT/plugin")"
[ -z "$MFOUND" ] || printf '%s\n' "$MFOUND" | sed 's/^/        /'

ok "the dead link is reported at auditor.md:$AUD_LN" \
  "$(printf '%s\n' "$MFOUND" | grep -cF "agents/auditor.md:$AUD_LN: ../../CONVENTIONS.md" | tr -d ' ')" 1
ok "the dead plugin-root path is reported at cataloguer.md:$CAT_LN" \
  "$(printf '%s\n' "$MFOUND" | grep -cF "agents/cataloguer.md:$CAT_LN: \${CLAUDE_PLUGIN_ROOT}/scripts/no-such-script.sh" | tr -d ' ')" 1
ok "…and no untouched agent body is reported" \
  "$(printf '%s\n' "$MFOUND" | grep -c . | tr -d ' ')" 2

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
