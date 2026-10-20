#!/usr/bin/env bash
#
# companion-account-switch.test.sh — the `loopd-accounts` companion: which account a
# bundle is on, the three renderings that answer says, the launcher's refusals, and the
# one boundary that is not a preference — NO CREDENTIAL EVER REACHES A BUNDLE REPO.
#
# WHY A FIXTURE REGISTRY AND A FIXTURE HOME. The real registry says whatever this machine
# happens to have installed, and the real ~/.claude holds the developer's live credential.
# Every case below points CLAUDE_CONFIG_DIR and HOME at trees this file wrote, so each
# answer is a property of the code and no assertion can touch a real secret.
#
# NON-VACUOUS BY CONSTRUCTION: the match, mismatch and no-account cases run against ONE
# fixture and differ only in the field under test, so a resolver answering the same thing
# to everything fails here instead of passing three cases in four.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
RESOLVE="$REPO/plugin/scripts/resolve-account.sh"
LAUNCH="$REPO/plugin-accounts/bin/loopd-claude"
OLD_LAUNCH="$REPO/plugin-accounts/bin/ai-bridge-claude"
BANNER="$REPO/plugin/hooks/session-banner.sh"
MJ="$REPO/.claude-plugin/marketplace.json"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/account-switch.XXXXXX")" || {
  echo "companion-account-switch.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd)" || { echo "companion-account-switch.test: could not resolve $TMP" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# ------------------------------------------------------------------ the fixture machine
BUNDLE="$TMP/bundle"; mkdir -p "$BUNDLE"
printf 'x\n' > "$BUNDLE/SCHEMA.md"
CFG="$TMP/cfg";       mkdir -p "$CFG/plugins"
EMPTY="$TMP/empty";   mkdir -p "$EMPTY"
COMPANION="$TMP/companion"; mkdir -p "$COMPANION/companion" "$COMPANION/bin"
printf '# fixture capability file\n' > "$COMPANION/companion/accounts.md"
printf '#!/usr/bin/env bash\n' > "$COMPANION/bin/loopd-claude"
ACCT_HOME="$TMP/accounts"; mkdir -p "$ACCT_HOME"

declare_account() { printf '{ "org": "x", "account": %s }\n' "$1" > "$BUNDLE/instance.config.json"; }
declare_account '"proceso"'

cat > "$CFG/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "loopd-accounts@${PMK}": [
      { "scope": "user", "installPath": "$COMPANION", "version": "1.0.0" }
    ]
  }
}
JSON

resolve() { # <LOOPD_ACCOUNT> — RCFG overrides which config dir holds the registry
  out="$(CLAUDE_CONFIG_DIR="${RCFG:-$CFG}" LOOPD_ACCOUNT="${1-}" \
         LOOPD_ACCOUNTS_HOME="$ACCT_HOME" "$RESOLVE" --bundle "$BUNDLE" 2>/dev/null)"; rc=$?
}
field() { printf '%s' "$out" | cut -f"$1"; }

echo
echo "== 1. the three renderings — speak, speak differently, stay silent =="
# One fixture, one field moved. A resolver that answered the same thing to all three would
# fail two of them rather than passing by accident.
resolve proceso
ok "on the declared account -> exit 0"          "$rc" 0
ok "…and names it"                              "$(field 1)" proceso
ok "…and names the active one"                  "$(field 2)" proceso
ok "…and names the launcher core never runs"    "$(field 3)" "$COMPANION/bin/loopd-claude"

# THE PRE-RENAME NAMES, read as aliases. A session a pre-rename launcher started carries
# only AI_BRIDGE_ACCOUNT; a companion installed before the rename ships only its old name.
out="$(CLAUDE_CONFIG_DIR="$CFG" AI_BRIDGE_ACCOUNT=proceso LOOPD_ACCOUNTS_HOME="$ACCT_HOME" \
       "$RESOLVE" --bundle "$BUNDLE" 2>/dev/null)"; rc=$?
ok "the old AI_BRIDGE_ACCOUNT alone still resolves -> 0" "$rc" 0
OLDCOMP="$TMP/oldcomp"; mkdir -p "$OLDCOMP/companion" "$OLDCOMP/bin" "$TMP/oldcfg/plugins"
cp "$COMPANION/companion/accounts.md" "$OLDCOMP/companion/"
printf '#!/usr/bin/env bash\n' > "$OLDCOMP/bin/ai-bridge-claude"
sed "s#$COMPANION#$OLDCOMP#" "$CFG/plugins/installed_plugins.json" > "$TMP/oldcfg/plugins/installed_plugins.json"
RCFG="$TMP/oldcfg" resolve proceso
ok "a pre-rename companion: the launcher it HAS is named" "$(field 3)" "$OLDCOMP/bin/ai-bridge-claude"

resolve alteos
ok "on the OTHER account -> exit 3 (mismatch)"   "$rc" 3
ok "…and both labels are printed"               "$(field 1)/$(field 2)" "proceso/alteos"

resolve ""
ok "started with no account at all -> exit 4"    "$rc" 4
ok "…and the active field is empty"             "$([ -z "$(field 2)" ] && echo yes || echo no)" yes

# Silent, and ONLY here: the capability is what makes the question exist.
RCFG="$EMPTY" resolve proceso
ok "no companion installed -> exit 1"            "$rc" 1
ok "…and it prints NOTHING"                      "$([ -z "$out" ] && echo yes || echo no)" yes

declare_account 'null'
resolve proceso
ok "companion installed, nothing declared -> 1"  "$rc" 1
ok "…and it prints nothing"                      "$([ -z "$out" ] && echo yes || echo no)" yes
declare_account '"proceso"'

echo
echo "== 2. CLAUDE_CONFIG_DIR is the fallback identity, and only under the accounts home =="
# The launcher exports both vars; a session carrying only the config dir is still
# identifiable, but a config dir ANYWHERE ELSE names no account — deriving a label from an
# arbitrary path is how an unrelated directory would silently satisfy the check.
out="$(CLAUDE_CONFIG_DIR="$CFG" LOOPD_ACCOUNTS_HOME="$ACCT_HOME" LOOPD_ACCOUNT="" \
       "$RESOLVE" --bundle "$BUNDLE" 2>/dev/null)"; rc=$?
ok "a config dir outside the accounts home -> 4"   "$rc" 4
mkdir -p "$CFG/plugins" "$ACCT_HOME/proceso/plugins"
cp "$CFG/plugins/installed_plugins.json" "$ACCT_HOME/proceso/plugins/installed_plugins.json"
out="$(CLAUDE_CONFIG_DIR="$ACCT_HOME/proceso" LOOPD_ACCOUNTS_HOME="$ACCT_HOME" \
       LOOPD_ACCOUNT="" "$RESOLVE" --bundle "$BUNDLE" 2>/dev/null)"; rc=$?
ok "…but one UNDER it names the account -> 0"      "$rc" 0
ok "…deriving the label from its basename"         "$(field 2)" proceso

# A label reaches the banner, so it is a closed charset — not whatever the config says.
declare_account '"pro ject|x"'
resolve proceso
ok "a punctuation-shaped label is refused"         "$rc" 1
declare_account '"proceso"'

echo
echo "== 3. NO CREDENTIAL EVER REACHES A BUNDLE REPO — the boundary, not a preference =="
# (a) STRUCTURAL. The launcher computes a config dir and REFUSES one inside the bundle or
#     inside any git work tree, so the guarantee does not rest on the default path.
before="$(find "$BUNDLE" -type f | LC_ALL=C sort)"
out="$(cd "$BUNDLE" && LOOPD_ACCOUNTS_HOME="$ACCT_HOME" HOME="$TMP/h" bash "$LAUNCH" --print-env 2>&1)"; rc=$?
ok "the launcher resolves an env, exit 0"          "$rc" 0
ok "…CLAUDE_CONFIG_DIR is under the accounts home" \
   "$(printf '%s' "$out" | grep -c "^CLAUDE_CONFIG_DIR=$ACCT_HOME/proceso$")" 1
ok "…and it labels the session for the banner"     \
   "$(printf '%s' "$out" | grep -c '^LOOPD_ACCOUNT=proceso$')" 1
ok "…under the new name only"                      \
   "$(printf '%s' "$out" | grep -c '^AI_BRIDGE_')" 0
ok "…and the bundle tree is UNCHANGED"             \
   "$([ "$before" = "$(find "$BUNDLE" -type f | LC_ALL=C sort)" ] && echo yes || echo no)" yes

# The pre-rename env var and launcher name still work — each says so once, on stderr.
out="$(cd "$BUNDLE" && AI_BRIDGE_ACCOUNTS_HOME="$ACCT_HOME" HOME="$TMP/h" bash "$LAUNCH" --print-env 2>&1)"; rc=$?
ok "the old AI_BRIDGE_ACCOUNTS_HOME is still read" \
   "$rc/$(printf '%s' "$out" | grep -c "^CLAUDE_CONFIG_DIR=$ACCT_HOME/proceso$")" 0/1
ok "…with a one-line deprecation note"             "$(printf '%s' "$out" | grep -c 'AI_BRIDGE_ACCOUNTS_HOME is deprecated')" 1
out="$(cd "$BUNDLE" && LOOPD_ACCOUNTS_HOME="$ACCT_HOME" HOME="$TMP/h" bash "$OLD_LAUNCH" --print-env 2>&1)"; rc=$?
ok "the old launcher name runs the new one"        \
   "$rc/$(printf '%s' "$out" | grep -c '^LOOPD_ACCOUNT=proceso$')" 0/1
ok "…and says it was renamed"                      "$(printf '%s' "$out" | grep -c 'renamed loopd-claude')" 1

# Refused BEFORE anything is created: the earlier version made the directory and then said
# no, which is a directory in a git repo that nobody asked for.
beforeall="$(find "$BUNDLE" | LC_ALL=C sort)"
rc=0; ( cd "$BUNDLE" && LOOPD_ACCOUNTS_HOME="$BUNDLE/.accounts" bash "$LAUNCH" --print-env ) >/dev/null 2>&1 || rc=$?
ok "an accounts home INSIDE the bundle -> exit 5"  "$rc" 5
ok "…and it created NOTHING there first"          \
   "$([ "$beforeall" = "$(find "$BUNDLE" | LC_ALL=C sort)" ] && echo yes || echo no)" yes

GITTREE="$TMP/gittree"; mkdir -p "$GITTREE"
git -C "$GITTREE" init -q >/dev/null 2>&1
rc=0; ( cd "$BUNDLE" && LOOPD_ACCOUNTS_HOME="$GITTREE/accounts" bash "$LAUNCH" --print-env ) >/dev/null 2>&1 || rc=$?
ok "an accounts home in a git work tree -> exit 5" "$rc" 5

# (b) BY INSPECTION. Nothing that ships may name a credential source, and the account
#     status the launcher does read is reported as an ORG and never as the email beside it.
creds=0
for f in "$RESOLVE" "$LAUNCH"; do
  grep -qE 'credentials\.json|find-generic-password|ANTHROPIC_API_KEY|oauth' "$f" && creds=$((creds+1))
done
ok "neither file names a credential source"        "$creds" 0
ok "the launcher never touches the email field"    "$(grep -c '"email"' "$LAUNCH")" 0
ok "…and reads orgName out of auth status"         "$(grep -c 'orgName' "$LAUNCH")" 2
ok "the resolver spawns no claude at all"          "$(grep -c 'claude auth' "$RESOLVE")" 0

echo
echo "== 4. the banner says which account is active, and warns when it is wrong =="
# The criterion is about what a human SEES, so these read the banner's own output rather
# than the resolver it calls.
BB="$TMP/bb"; mkdir -p "$BB"
cp "$BUNDLE/instance.config.json" "$BB/instance.config.json"
banner() { CLAUDE_PROJECT_DIR="$BB" CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_CONFIG_DIR="$CFG" \
           LOOPD_ACCOUNTS_HOME="$ACCT_HOME" LOOPD_ACCOUNT="${1-}" \
           bash "$BANNER" --no-color 2>/dev/null; }
ok "on the declared account the banner names it"   \
   "$(banner proceso | grep -c '^Account proceso — active$')" 1
ok "on the wrong one it says WRONG"                \
   "$(banner alteos | grep -c 'WRONG CLAUDE ACCOUNT')" 1
ok "…and names both, so the human can act"         \
   "$(banner alteos | grep -c 'this bundle is proceso, the session is alteos')" 1
ok "on no account it says so"                      \
   "$(banner '' | grep -c 'NO CLAUDE ACCOUNT SELECTED')" 1
ok "…and both warnings print the launcher path"    \
   "$( { banner alteos; banner ''; } | grep -c "$COMPANION/bin/loopd-claude")" 2
# STAY SILENT is a rendering too, and the one that must not leak: no companion, no line.
ok "no companion -> the banner says nothing at all" \
   "$(CLAUDE_PROJECT_DIR="$BB" CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_CONFIG_DIR="$EMPTY" \
      bash "$BANNER" --no-color 2>/dev/null | grep -ciE 'account|CLAUDE_CONFIG_DIR')" 0

echo
echo "== 5. it ships as a companion, on the contract core already has =="
ok "the marketplace registers loopd-accounts"  \
   "$(grep -c '"name": "loopd-accounts"' "$MJ")" 1
ok "…from ./plugin-accounts"                       \
   "$(grep -c '"source": "./plugin-accounts"' "$MJ")" 1
ok "the capability file is at the fixed path"      \
   "$(yn test -f "$REPO/plugin-accounts/companion/accounts.md")" yes
ok "it ships no hook and no agent"                 \
   "$(find "$REPO/plugin-accounts" -type d \( -name hooks -o -name agents \) | grep -c .)" 0
ok "the mechanism names the version it was measured on" \
   "$(grep -c 'Claude Code 2\.1\.263' "$REPO/plugin-accounts/companion/accounts.md")" 1
ok "…and records that there is no native switch"   \
   "$(grep -c 'no.*account or profile switch' "$REPO/plugin-accounts/companion/accounts.md")" 1
ok "the seed config carries the account key"       \
   "$(grep -c '"account": null' "$REPO/plugin/seed/instance.config.json")" 1
ok "…documented as a label and never a credential" \
   "$(grep -c 'A LABEL, never a credential' "$REPO/plugin/seed/instance.config.json")" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
