#!/usr/bin/env bash
#
# update-plugin.test.sh — plugin/scripts/update-plugin.sh, the engine behind /<plugin>:update.
#
# A stubbed `claude` first on PATH logs every call and swaps in an "after" registry on a
# plugin update; CLAUDE_CONFIG_DIR is a temp dir, so the real registry is never read. Each
# fixture install carries an init-bundle.sh stub that logs its own path and arguments.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
. "$TPL/tests/tools/plugin-name.sh"
SCRIPT="$TPL/plugin/scripts/update-plugin.sh"
[ -f "$SCRIPT" ] || { echo "update-plugin.test: missing $SCRIPT" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/update-plugin.XXXXXX")" || exit 2
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin" CFG="$TMP/cfg" CALLS="$TMP/calls" BUNDLE="$TMP/bundle" AFTER="$TMP/after.json"
REG="$CFG/plugins/installed_plugins.json" CACHE="$CFG/plugins/cache/$PMK"
mkdir -p "$BIN" "$CFG/plugins" "$BUNDLE/sub"
echo '{}' > "$BUNDLE/instance.config.json"

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$1" <<<"$2" && echo yes || echo no; }

cat > "$BIN/claude" <<STUB
#!/usr/bin/env bash
printf 'claude %s\n' "\$*" >> "$CALLS"
case "\$1 \$2" in
  "plugin marketplace") [ -z "\${MKT_FAIL:-}" ] || { echo "marketplace unreachable"; exit 1; } ;;
  "plugin update") [ "\$3" != "\${FAIL_KEY:-}" ] || { echo "update of \$3 broke"; exit 1; }
                   [ ! -f "$AFTER" ] || cp "$AFTER" "$REG" ;;
esac
exit 0
STUB
chmod +x "$BIN/claude"

install_at() { # <plugin> <version> — a cache dir whose init-bundle.sh logs and exits $INIT_RC
  mkdir -p "$CACHE/$1/$2/scripts"
  printf '#!/usr/bin/env bash\nprintf "init %%s %%s\\n" "$0" "$*" >> "%s"\nprintf "root %%s\\n" "$CLAUDE_PLUGIN_ROOT" >> "%s"\nexit "${INIT_RC:-0}"\n' "$CALLS" "$CALLS" \
    > "$CACHE/$1/$2/scripts/init-bundle.sh"
}
install_at "$PN" 1.0.0; install_at "$PN" 1.0.1; install_at "$PN-yolo" 4.4.0
mkdir -p "$CACHE/$PN/2.0.0"   # recorded in a registry below, carries no init

registry() { # <file> <line>… — each line key|scope|version|installPath|projectPath
  local f="$1"; shift
  printf '%s\n' "$@" | awk -F'|' '
    { if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 }
      e = "      {\n        \"scope\": \"" $2 "\",\n"
      if ($5 != "") e = e "        \"projectPath\": \"" $5 "\",\n"
      e = e "        \"installPath\": \"" $4 "\",\n        \"version\": \"" $3 "\"\n      }"
      body[$1] = ($1 in body) ? body[$1] ",\n" e : e }
    END { print "{\n  \"version\": 2,\n  \"plugins\": {"
          for (i = 1; i <= n; i++) printf "    \"%s\": [\n%s\n    ]%s\n", order[i], body[order[i]], (i < n ? "," : "")
          print "  }\n}" }' > "$f"
}
U_OLD="$PN@$PMK|user|1.0.0|$CACHE/$PN/1.0.0|"
U_NEW="$PN@$PMK|user|1.0.1|$CACHE/$PN/1.0.1|"
Y="$PN-yolo@$PMK|user|4.4.0|$CACHE/$PN-yolo/4.4.0|"
P_HERE="$PN@$PMK|project|1.0.0|$CACHE/$PN/1.0.0|$BUNDLE"
OTHER="lsp@elsewhere|user|1.0.0|$TMP/elsewhere|"

run() { # [dir] — runs the script there; OUT, RC, LOG
  : > "$CALLS"
  OUT="$(cd "${1:-$BUNDLE}" && PATH="$BIN:$PATH" CLAUDE_CONFIG_DIR="$CFG" \
         CLAUDE_PLUGIN_ROOT="$CACHE/$PN/1.0.0" bash "$SCRIPT" 2>&1)"; RC=$?
  LOG="$(cat "$CALLS")"
}
last2() { printf '%s\n' "$OUT" | tail -2 | tr '\n' '|'; }
RELOAD='Now run /reload-plugins|If a command is missing, restart Claude Code|'

echo "== update available =="
registry "$REG" "$U_OLD" "$Y" "$P_HERE" "$OTHER"; registry "$AFTER" "$U_NEW" "$Y" "$P_HERE" "$OTHER"
run
ok "exit 0"                                     "$RC" 0
ok "the marketplace update is the first call"   "$(sed -n 1p <<<"$LOG")" "claude plugin marketplace update $PMK"
ok "core updated at user scope"                 "$(has "claude plugin update $PN@$PMK -s user" "$LOG")" yes
ok "…and the companion"                         "$(has "claude plugin update $PN-yolo@$PMK -s user" "$LOG")" yes
ok "another marketplace's plugin is not touched" "$(has 'lsp@elsewhere' "$LOG")" no
ok "nothing is installed"                       "$(has 'plugin install' "$LOG")" no
ok "exactly two plugin updates"                 "$(grep -c '^claude plugin update' <<<"$LOG")" 2
ok "prints old → new"                           "$(has "$PN 1.0.0 → 1.0.1" "$OUT")" yes
ok "prints up to date for the unchanged one"    "$(has "$PN-yolo up to date" "$OUT")" yes
ok "the project-scope install is listed"        "$(has "$PN 1.0.0 (project scope, $BUNDLE) — listed, not updated" "$OUT")" yes
ok "…and warned about, older than user scope"   "$(has "this bundle's project-scope $PN is 1.0.0, older than the user-scope 1.0.1" "$OUT")" yes
ok "init runs from the NEW user-scope version"  "$(grep '^init ' <<<"$LOG")" "init $CACHE/$PN/1.0.1/scripts/init-bundle.sh $BUNDLE"
ok "…never from CLAUDE_PLUGIN_ROOT"             "$(has "$CACHE/$PN/1.0.0/scripts" "$LOG")" no
ok "…and hands init the NEW root as CLAUDE_PLUGIN_ROOT" "$(grep '^root ' <<<"$LOG")" "root $CACHE/$PN/1.0.1"
ok "…with no flag"                              "$(grep -c -- '--spawn-grant\|--normalise-config\|--owner\|--email\|--repos-root' <<<"$LOG")" 0
ok "the last two lines are reload, then restart" "$(last2)" "$RELOAD"

echo "== already up to date =="
registry "$REG" "$U_OLD" "$Y"; rm -f "$AFTER"
run
ok "exit 0"                                     "$RC" 0
ok "core up to date"                            "$(has "$PN up to date" "$OUT")" yes
ok "init from the version installed"            "$(grep '^init ' <<<"$LOG")" "init $CACHE/$PN/1.0.0/scripts/init-bundle.sh $BUNDLE"
ok "no warning without a project install"       "$(has 'warn' "$OUT")" no
ok "reload lines last"                          "$(last2)" "$RELOAD"

echo "== the marketplace update fails =="
MKT_FAIL=1 run
ok "exit non-zero"                              "$([ "$RC" -ne 0 ] && echo yes || echo no)" yes
ok "no plugin update ran"                       "$(grep -c '^claude plugin update' <<<"$LOG")" 0
ok "no init ran"                                "$(grep -c '^init ' <<<"$LOG")" 0
ok "the failure is relayed"                     "$(has 'marketplace unreachable' "$OUT")" yes

echo "== one plugin's update fails (D2) =="
registry "$REG" "$U_OLD" "$Y"; registry "$AFTER" "$U_NEW" "$Y"
FAIL_KEY="$PN-yolo@$PMK" run
ok "exit 1"                                     "$RC" 1
ok "the other plugin still updated"             "$(has "$PN 1.0.0 → 1.0.1" "$OUT")" yes
ok "the failure is named"                       "$(has "$PN-yolo update failed: update of $PN-yolo@$PMK broke" "$OUT")" yes
ok "init still ran, from the new version"       "$(grep '^init ' <<<"$LOG")" "init $CACHE/$PN/1.0.1/scripts/init-bundle.sh $BUNDLE"
ok "reload lines last"                          "$(last2)" "$RELOAD"

echo "== outside a bundle =="
registry "$REG" "$U_OLD"; rm -f "$AFTER"
run "$BUNDLE/sub"
ok "exit 0"                                     "$RC" 0
ok "a subdirectory is outside: no init"         "$(grep -c '^init ' <<<"$LOG")" 0
ok "one skip line"                              "$(grep -c '^init: skipped' <<<"$OUT")" 1
ok "reload lines last"                          "$(last2)" "$RELOAD"

echo "== no usable registry (D5) =="
rm -f "$REG"; run
ok "missing registry: exit 2"                   "$RC" 2
ok "…no init"                                   "$(grep -c '^init ' <<<"$LOG")" 0
ok "…reload lines still last"                   "$(last2)" "$RELOAD"
echo 'not json at all' > "$REG"; run
ok "unparseable registry: exit 2"               "$RC" 2
ok "…no init"                                   "$(grep -c '^init ' <<<"$LOG")" 0
registry "$REG" "$PN@$PMK|user|2.0.0|$CACHE/$PN/2.0.0|"; run
ok "user entry with no init-bundle.sh: exit 2"  "$RC" 2
ok "…no init"                                   "$(grep -c '^init ' <<<"$LOG")" 0
ok "…and CLAUDE_PLUGIN_ROOT is not the fallback" "$(has "$CACHE/$PN/1.0.0" "$LOG")" no

echo "== init's own exit propagates =="
registry "$REG" "$U_OLD"
INIT_RC=3 run
ok "exit 3"                                     "$RC" 3
ok "reload lines last"                          "$(last2)" "$RELOAD"

echo
echo "update-plugin.test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
