#!/usr/bin/env bash
#
# update-plugin.sh — behind /<plugin>:update: refresh the marketplace, update every plugin of
# it installed at user scope, stamp the bundle in the cwd with the NEW version's init-bundle.sh
# (read from the registry's user entry), then say to reload. No arguments.
#
# Exit: 0 done · 1 a plugin update failed (the rest, and init, still ran) · 2 the marketplace
# update failed, or no usable registry entry (no init ran) · else init-bundle.sh's own exit.
# Never installs, never touches a project/local/managed install, never passes init a flag.
# Reasoning: loopd-update-command/task-001, decisions D1-D5.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
MKT="$PLUGIN_MARKETPLACE" CORE="$PLUGIN_NAME"
[ -n "$MKT" ] && [ -n "$CORE" ] || { echo "update: cannot derive this plugin's name" >&2; exit 2; }
REGISTRY="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/plugins/installed_plugins.json"
TAB="$(printf '\t')"

reload_lines() { echo "Now run /reload-plugins"; echo "If a command is missing, restart Claude Code"; }
finish() { reload_lines; exit "$1"; }

# One line per registry entry: key TAB scope TAB version TAB installPath TAB projectPath.
# The registry is pretty-printed one key per line, the same assumption resolve-autonomy.sh makes.
entries() {
  awk -v OFS="$TAB" '
    function val(l) { sub(/^[^:]*:[[:space:]]*"/, "", l); sub(/".*$/, "", l); return l }
    /^[[:space:]]*"[^"]+@[^"]+"[[:space:]]*:[[:space:]]*\[/ { k = $0; sub(/^[[:space:]]*"/, "", k); sub(/".*$/, "", k); key = k; next }
    key != "" && /^[[:space:]]*\{[[:space:]]*$/ { inobj = 1; sc = ve = ip = pp = ""; next }
    inobj && /"scope"[[:space:]]*:/       { sc = val($0) }
    inobj && /"version"[[:space:]]*:/     { ve = val($0) }
    inobj && /"installPath"[[:space:]]*:/ { ip = val($0) }
    inobj && /"projectPath"[[:space:]]*:/ { pp = val($0) }
    inobj && /^[[:space:]]*\},?[[:space:]]*$/ { print key, sc, ve, ip, pp; inobj = 0; next }
    /^[[:space:]]*\],?[[:space:]]*$/ { key = "" }
  ' "$REGISTRY" 2>/dev/null
}
mine() { awk -F "$TAB" -v m="@$MKT" 'substr($1, length($1) - length(m) + 1) == m'; }
user_field() { # <key> <field#> — from the scope: user entry of <key>
  entries | awk -F "$TAB" -v k="$1" -v f="$2" '$1 == k && $2 == "user" { print $f; exit }'
}
ver_lt() { # <a> <b> — true when a is an older dotted version than b
  awk -v a="$1" -v b="$2" 'BEGIN { na = split(a, x, "."); nb = split(b, y, "."); n = na > nb ? na : nb
    for (i = 1; i <= n; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }; exit 1 }'
}

echo "marketplace: claude plugin marketplace update $MKT"
if ! command -v claude >/dev/null 2>&1; then
  echo "update: no claude CLI on PATH — nothing was updated" >&2; exit 2
fi
if ! out="$(claude plugin marketplace update "$MKT" 2>&1)"; then
  printf '%s\n' "$out" | sed 's/^/  /' >&2
  echo "update: the marketplace update failed — no plugin was updated and no bundle stamped" >&2
  exit 2
fi

[ -r "$REGISTRY" ] || { echo "update: no plugin registry at $REGISTRY — no init ran" >&2; finish 2; }
before="$(entries | mine)"
[ -n "$before" ] || { echo "update: no $MKT plugin readable in $REGISTRY — no init ran" >&2; finish 2; }

rc=0 failed=""
users="$(printf '%s\n' "$before" | awk -F "$TAB" '$2 == "user" { print $1 }')"
for key in $users; do
  if ! out="$(claude plugin update "$key" -s user 2>&1)"; then
    failed="$failed $key"; rc=1
    echo "${key%@*} update failed: $(printf '%s\n' "$out" | grep . | tail -1)" >&2
  fi
done
after="$(entries | mine)"
for key in $users; do
  case " $failed " in *" $key "*) continue ;; esac
  old="$(printf '%s\n' "$before" | awk -F "$TAB" -v k="$key" '$1 == k && $2 == "user" { print $3; exit }')"
  new="$(printf '%s\n' "$after" | awk -F "$TAB" -v k="$key" '$1 == k && $2 == "user" { print $3; exit }')"
  if [ -n "$new" ] && [ "$new" != "$old" ]; then echo "${key%@*} $old → $new"; else echo "${key%@*} up to date"; fi
done

here="$(pwd -P)"
while IFS="$TAB" read -r key sc ve ip pp; do
  [ -n "$key" ] && [ "$sc" != user ] || continue
  echo "${key%@*} $ve ($sc scope${pp:+, $pp}) — listed, not updated"
  uv="$(printf '%s\n' "$after" | awk -F "$TAB" -v k="$key" '$1 == k && $2 == "user" { print $3; exit }')"
  if [ -n "$pp" ] && [ "$pp" = "$here" ] && [ -n "$uv" ] && ver_lt "$ve" "$uv"; then
    echo "  warn  this bundle's $sc-scope ${key%@*} is $ve, older than the user-scope $uv it is stamped from" >&2
  fi
done <<<"$after"

if ! ab_is_bundle "$here"; then
  echo "init: skipped — $here is not a bundle root"
  finish "$rc"
fi
ip="$(user_field "$CORE@$MKT" 4)"
if [ -z "$ip" ] || [ ! -f "$ip/scripts/init-bundle.sh" ]; then
  echo "update: no init-bundle.sh under the user-scope $CORE@$MKT install (${ip:-none recorded}) — no init ran" >&2
  finish 2
fi
echo "init: $ip/scripts/init-bundle.sh $here"
bash "$ip/scripts/init-bundle.sh" "$here"
irc=$?
[ "$irc" -eq 0 ] || rc="$irc"
finish "$rc"
