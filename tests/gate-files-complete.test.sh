#!/usr/bin/env bash
#
# gate-files-complete.test.sh — every file the merge gate executes, sources or reads is in
# GATE_FILES (plugin/scripts/required-checks.sh), and every entry is reached or justified.
#
# Walk: from plugin/hooks/deny-destructive.sh, plugin/scripts/merge-permit.sh and each ALLOW
# entry, transitively through every reached .sh. Resolution rule:
#   - a path counts only appended to a directory expression: $(dirname <self>), ${<self>%/*},
#     a variable assigned from one ($HERE, $RC_DIR, $D, $here, plugin-name.sh's $root — a
#     trailing /.. is kept), or ${CLAUDE_PLUGIN_ROOT…} = plugin/. <self> is
#     ${BASH_SOURCE[0]…}, $0 or a variable assigned from either; that directory is the
#     calling script's own.
#   - executed, sourced and read files all count, a .json manifest a gate script reads
#     included; a path that names no file in the tree is a runtime path and does not.
#   - comment lines and heredoc bodies are skipped, and a bare basename never resolves, so
#     a basename inside a message, comment or heredoc does not count.
#   - mapped(): resolve-autonomy.sh's COMPANION_REL lookup is plugin-yolo/companion/AUTONOMY.md;
#     clearance-receipt.sh's REQUIRED and CHECKER name the scripts whose receipt it verifies,
#     resolved in its own directory. Either reads as stale (a failure) when it stops parsing.
#   - ALLOW: a GATE_FILES entry justified outside the walk, with its reason.
# Usage: gate-files-complete.test.sh [<tree>] — checks <tree> alone, exit 1 on a gap.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOTS="plugin/hooks/deny-destructive.sh plugin/scripts/merge-permit.sh"
ALLOW="plugin/scripts/merge-queue.sh|decides yolo merge order: holds a merge while a default-branch run is pending (AUTONOMY.md precondition 5, tick step 4)"

mapped() { # <tree> <file> — targets reached by a lookup no directory expression shows
  local tree="$1" f="$2" w n=0
  case "$f" in
    plugin/scripts/resolve-autonomy.sh)
      grep -q '^COMPANION_REL="companion/AUTONOMY.md"$' "$tree/$f" && [ -f "$tree/plugin-yolo/companion/AUTONOMY.md" ] \
        && echo plugin-yolo/companion/AUTONOMY.md || echo "MAP-STALE $f: COMPANION_REL no longer names companion/AUTONOMY.md" ;;
    plugin/scripts/clearance-receipt.sh)
      for w in $(sed -nE 's/^(REQUIRED|CHECKER)="([^"]*)"$/\2/p' "$tree/$f"); do
        [ -f "$tree/${f%/*}/$w" ] && { echo "${f%/*}/$w"; n=$((n+1)); }
      done
      [ "$n" -gt 0 ] || echo "MAP-STALE $f: REQUIRED/CHECKER name no script beside it" ;;
  esac
}

refs() { # <tree> <file> — repo-relative paths the file names through a directory expression
  local own; own="$(dirname "$2")"
  awk -v own="$own" '
    function rep(s, re, to) { gsub(re, to, s); return s }
    hd != "" { t = $0; if (hdtab) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
    /^[[:space:]]*#/ { next }
    {
      l = $0
      if (match(l, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) && substr(l, RSTART - 1, 1) != "<") {
        tok = substr(l, RSTART, RLENGTH); hdtab = (tok ~ /^<<-/)
        gsub(/^<<-?[[:space:]]*|["\047]/, "", tok); hd = tok
        l = substr(l, 1, RSTART - 1)
      }
      sub(/[[:space:]]#.*$/, "", l)
      gsub(/["\047]/, "", l)
      l = rep(l, "\\$\\{CLAUDE_PLUGIN_ROOT(:-\\$\\{[^}]*\\})?[^}]*\\}", "@D:plugin@")
      l = rep(l, "\\$\\(cd (-P )?", ""); l = rep(l, " 2>/dev/null", "")
      l = rep(l, " && pwd( \\|\\| true)?\\)", "")
      l = rep(l, "\\$\\{BASH_SOURCE\\[0\\](:-\\$0)?\\}", "@SELF@"); l = rep(l, "\\$0", "@SELF@")
      for (v in selfv) {
        l = rep(l, "\\$\\{" v "%/\\*\\}", "@D:" own "@")
        l = rep(l, "\\$\\{" v "\\}", "@SELF@"); l = rep(l, "\\$" v "([^A-Za-z0-9_]|$)", "@SELF@&")
        gsub("@SELF@\\$" v, "@SELF@", l)
      }
      l = rep(l, "\\$\\(dirname @SELF@\\)", "@D:" own "@")
      for (v in dirv) {
        l = rep(l, "\\$\\{" v "%/\\*\\}", "@D:" dirname(dirv[v]) "@")
        l = rep(l, "\\$\\{" v "\\}", "@D:" dirv[v] "@")
        while (match(l, "\\$" v "([^A-Za-z0-9_]|$)"))
          l = substr(l, 1, RSTART - 1) "@D:" dirv[v] "@" substr(l, RSTART + length(v) + 1)
      }
      if (match(l, /(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*=@SELF@/)) {
        a = substr(l, RSTART, RLENGTH); sub(/^[^A-Za-z_]/, "", a); sub(/=.*/, "", a); selfv[a] = 1
      }
      s = l
      while (match(s, /[A-Za-z_][A-Za-z0-9_]*=(\$\{1:-)?@D:[^@]*@[A-Za-z0-9_.\/-]*/)) {
        a = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        n = a; sub(/=.*/, "", n); val = a; sub(/^[^@]*@D:/, "", val); sub(/@/, "", val)
        dirv[n] = val
      }
      s = l
      while (match(s, /@D:[^@]*@(\/[A-Za-z0-9_.-]+)+/)) {
        a = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^@D:/, "", a); sub(/@/, "", a); print a
      }
    }
    function dirname(p) { if (p !~ /\//) return "."; sub(/\/[^\/]*$/, "", p); return p }
  ' "$1/$2" | while IFS= read -r p; do
    p="$(norm "$p")"
    [ -n "$p" ] && [ -f "$1/$p" ] && printf '%s\n' "$p"
  done
}

norm() { # collapse . and .. in a relative path; empty when it climbs out of the tree
  local out="" seg IFS=/
  for seg in $1; do
    case "$seg" in
      ''|.) ;;
      ..) [ -n "$out" ] || return 0
          case "$out" in */*) out="${out%/*}" ;; *) out="" ;; esac ;;
      *) out="${out:+$out/}$seg" ;;
    esac
  done
  printf '%s\n' "$out"
}

walk() { # <tree> — every file reached from ROOTS and the ALLOW entries, one per line
  local tree="$1" queue seen="" f m
  queue="$ROOTS $(printf '%s\n' "$ALLOW" | cut -d'|' -f1)"
  for f in $queue; do [ -f "$tree/$f" ] || queue="$(printf '%s' "$queue" | sed "s#$f##")"; done
  while [ -n "$(printf '%s' "$queue" | tr -d ' ')" ]; do
    set -- $queue; f="$1"; shift; queue="$*"
    grep -Fxq "$f" <<<"$seen" && continue
    seen="$seen"$'\n'"$f"
    case "$f" in *.sh) ;; *) continue ;; esac
    queue="$queue $(refs "$tree" "$f" | tr '\n' ' ')"
    while IFS= read -r m; do
      case "$m" in '') ;; MAP-STALE*) echo "$m" ;; *) queue="$queue $m" ;; esac
    done <<<"$(mapped "$tree" "$f")"
  done
  printf '%s\n' "$seen" | grep -v '^$'
}

gates() { sed -n '/^GATE_FILES="$/,/^"$/p' "$1/plugin/scripts/required-checks.sh" | grep -v '"'; }

check_tree() { # <tree> — prints each gap, returns 1 on any
  local tree="$1" reached listed bad=0 f
  reached="$(walk "$tree")"; listed="$(gates "$tree")"
  grep '^MAP-STALE ' <<<"$reached" && bad=1
  for f in $(grep -v '^MAP-STALE ' <<<"$reached"); do
    grep -Fxq "$f" <<<"$listed" || { echo "MISSING $f — the merge path reaches it; add it to GATE_FILES"; bad=1; }
  done
  for f in $listed; do
    grep -Fxq "$f" <<<"$reached" && continue
    grep -Fxq "$f" <<<"$(cut -d'|' -f1 <<<"$ALLOW")" && continue
    echo "UNJUSTIFIED $f — no walk reaches it and ALLOW does not name it"; bad=1
  done
  return "$bad"
}

if [ $# -gt 0 ]; then check_tree "$1"; exit; fi

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1 — got [$2] want [$3]"; fail=$((fail+1)); fi; }
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

fixture() { # <dir> <GATE_FILES entries...>
  local d="$1"; shift
  mkdir -p "$d/plugin/hooks" "$d/plugin/scripts"
  printf '%s\n' '#!/usr/bin/env bash' '. "${CLAUDE_PLUGIN_ROOT:-${_self%/hooks/*}}/scripts/merge-permit.sh"' > "$d/plugin/hooks/deny-destructive.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"' '"$HERE/a.sh"' > "$d/plugin/scripts/merge-permit.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"' '"$HERE/b.sh" --check' \
    'echo "c.sh is not installed" >&2' '# "$HERE/d.sh" in a comment' 'cat <<EOF' '"$HERE/e.sh"' 'EOF' > "$d/plugin/scripts/a.sh"
  for f in b c d e; do echo '#!/usr/bin/env bash' > "$d/plugin/scripts/$f.sh"; done
  { echo 'GATE_FILES="'; printf '%s\n' "$@"; echo '"'; } > "$d/plugin/scripts/required-checks.sh"
}

echo "== fixture: a.sh runs \"\$HERE/b.sh\", b.sh unlisted =="
fixture "$TMP/gap" plugin/hooks/deny-destructive.sh plugin/scripts/merge-permit.sh plugin/scripts/a.sh
out="$(bash "$0" "$TMP/gap")"; rc=$?
ok "the check exits non-zero" "$rc" 1
ok "it names b.sh" "$(grep -c '^MISSING plugin/scripts/b.sh' <<<"$out")" 1
ok "a basename in a message, comment or heredoc is not a gap" "$(grep -cE 'plugin/scripts/[cde]\.sh' <<<"$out")" 0
fixture "$TMP/full" plugin/hooks/deny-destructive.sh plugin/scripts/merge-permit.sh plugin/scripts/a.sh plugin/scripts/b.sh
out="$(bash "$0" "$TMP/full")"; rc=$?
ok "the same tree with b.sh listed passes" "$rc" 0
fixture "$TMP/extra" plugin/hooks/deny-destructive.sh plugin/scripts/merge-permit.sh plugin/scripts/a.sh plugin/scripts/b.sh plugin/scripts/c.sh
out="$(bash "$0" "$TMP/extra")"; rc=$?
ok "an entry nothing reaches is named unjustified" "$(grep -c '^UNJUSTIFIED plugin/scripts/c.sh' <<<"$out")" 1

echo "== this repo =="
reached="$(walk "$REPO")"
for f in plugin/scripts/resolve-autonomy.sh plugin/.claude-plugin/plugin.json .claude-plugin/marketplace.json \
         plugin-yolo/companion/AUTONOMY.md plugin/scripts/bundle-paths.sh plugin/scripts/qa-dispatch.sh; do
  ok "the walk reaches $f" "$(grep -cFx "$f" <<<"$reached")" 1
done
out="$(check_tree "$REPO")"; rc=$?
[ -z "$out" ] || printf '        %s\n' "$out"
ok "every file the merge path reaches is in GATE_FILES, every entry justified" "$rc" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
