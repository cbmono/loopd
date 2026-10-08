#!/usr/bin/env bash
#
# companion-plugins.test.sh — the companion extension point: `resolve-autonomy.sh`'s
# resolution order against a FIXTURE companion root, the `loopd-yolo` marketplace
# entry, and the one rule the whole design rests on — a companion may ADD behaviour but
# never remove a core gate.
#
# THE FAILURE THIS EXISTS FOR. `AUTONOMY.md` is the capability: found, a project's
# `autonomy:` field selects a mode; not found, both human gates hold absolutely. It used
# to be stamped to the bundle root from `symlink/`, and after ai-bridge-v2/task-013
# nothing stamps it — so the presence check survived with nothing left to make the file
# present. Turning that check into an extension point moves it from one `[ -f ]` to a
# lookup across a machine-level plugin registry, and every new way for that lookup to say
# "yes" is a new way for the loop to promote and merge without a human. So the cases below
# are weighted towards the answers that must stay NO.
#
# WHY A FIXTURE REGISTRY AND NOT THE REAL ONE. The real
# `~/.claude/plugins/installed_plugins.json` says whatever this machine happens to have
# installed, so a test that read it would pass or fail on a developer's install state and
# tell nobody anything. Every case here points `CLAUDE_CONFIG_DIR` at a registry this file
# wrote, so each answer is a property of the resolver.
#
# NON-VACUOUS BY CONSTRUCTION. The positive case (a companion IS found) runs against the
# same fixture as the negative ones and differs only in the one field under test — the
# marketplace suffix, the fixed relative path, the file's existence — so a resolver that
# said "no" to everything would fail here rather than passing three cases out of four.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
RESOLVE="$REPO/plugin/scripts/resolve-autonomy.sh"
MJ="$REPO/.claude-plugin/marketplace.json"
YOLO="$REPO/plugin-yolo"
PLUGIN_README="$REPO/plugin/README.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/companion-plugins.XXXXXX")" || {
  echo "companion-plugins.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# NORMALISE IT. A TMPDIR with a trailing slash yields `…/tmp//companion-plugins.X`, and the
# resolver prints a `cd`-normalised path — so every expected string below would differ from
# the actual one by a slash nobody typed.
TMP="$(cd "$TMP" && pwd)" || { echo "companion-plugins.test: could not resolve $TMP" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------- the fixture machine
# A bundle with no AUTONOMY.md of its own, a config dir holding a registry, and a
# companion plugin root laid out the way the contract says.
BUNDLE="$TMP/bundle";      mkdir -p "$BUNDLE"
CFG="$TMP/cfg";            mkdir -p "$CFG/plugins"
COMPANION="$TMP/companion"; mkdir -p "$COMPANION/companion"
printf '# fixture capability file\n' > "$COMPANION/companion/AUTONOMY.md"
EMPTY="$TMP/empty-cfg";    mkdir -p "$EMPTY"

write_registry() { # <key> [<extra-key> <extra-path>]
  cat > "$CFG/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "$1": [
      {
        "scope": "user",
        "installPath": "$COMPANION",
        "version": "0.15.0",
        "installedAt": "2026-09-05T00:00:00.000Z"
      }
    ]
  }
}
JSON
}

# `resolve <config-dir>` — sets `out` to the resolver's stdout and `rc` to its exit
# status. NOT a function whose output is captured with `$( … )`: that runs it in a
# SUBSHELL, so the `rc` it assigns dies with the subshell and every caller reads the
# stale one. Measured here first time out — eight assertions comparing against an `rc`
# that never left 0.
out=""; rc=0
resolve() { out="$(CLAUDE_CONFIG_DIR="$1" "$RESOLVE" --bundle "$BUNDLE" 2>/dev/null)"; rc=$?; }

echo
echo "== 1. absent both — every project is gated, exactly as before =="
# The floor. No file at the bundle root and no registry at all: exit 1, nothing on stdout.
# `commit-as.sh`'s promotion guard reads exactly this, so this case IS "both human gates
# hold" for a machine that has installed no companion.
resolve "$EMPTY"
ok "no bundle file, no registry -> exit 1"     "$rc" 1
ok "…and it prints nothing"                    "$([ -z "$out" ] && echo yes || echo no)" yes

# A registry that exists but lists no companion is the same answer by a different route:
# the machine has plugins, none of them ours.
write_registry "some-other-plugin@some-other-market"
resolve "$CFG"
ok "a registry listing no companion -> exit 1" "$rc" 1

echo
echo "== 2. an installed companion answers — the extension point itself =="
write_registry "loopd-yolo@${PMK}"
resolve "$CFG"
ok "companion installed -> exit 0"             "$rc" 0
ok "…and it prints that companion's file"      "$out" "$COMPANION/companion/AUTONOMY.md"

echo
echo "== 3. the bundle root WINS — a v1-era bundle keeps working unchanged =="
# The compatibility guarantee: a bundle carrying its own real AUTONOMY.md behaves byte for
# byte as it did, and no companion can override what it says. Asserted with the companion
# installed, because root-first is only meaningful when there is something to beat.
printf '# a v1-era bundle brought its own\n' > "$BUNDLE/AUTONOMY.md"
resolve "$CFG"
ok "root + companion -> exit 0"                "$rc" 0
ok "…and the ROOT file is what is returned"    "$out" "$BUNDLE/AUTONOMY.md"
# …and with no companion at all, which is the actual v1 machine.
resolve "$EMPTY"
ok "root alone, no registry -> exit 0"         "$rc" 0
ok "…still the root file"                      "$out" "$BUNDLE/AUTONOMY.md"
rm -f "$BUNDLE/AUTONOMY.md"

echo
echo "== 4. the three ways a lookup must still say NO =="
# (a) THE MARKETPLACE IS PART OF THE CONTRACT. Arming delegated authority must not be
#     reachable by an unrelated plugin someone installed for an unrelated reason, so a
#     plugin carrying the right path under the WRONG marketplace is not a companion.
write_registry "loopd-yolo@somebody-elses-market"
resolve "$CFG"
ok "right path, wrong marketplace -> exit 1"   "$rc" 1

# (b) THE RELATIVE PATH IS FIXED. A file at the companion's plugin ROOT is not what core
#     reads — otherwise a companion's own README or docs could be mistaken for it.
write_registry "loopd-yolo@${PMK}"
mv "$COMPANION/companion/AUTONOMY.md" "$COMPANION/AUTONOMY.md"
resolve "$CFG"
ok "file at the plugin root, not companion/ -> exit 1" "$rc" 1
mv "$COMPANION/AUTONOMY.md" "$COMPANION/companion/AUTONOMY.md"

# (c) UNINSTALLED MEANS OFF, which is the whole design and the reason the resolver reads
#     the registry rather than the plugin CACHE tree: the cache keeps every version ever
#     fetched, uninstalled ones included, so a cache scan would answer "installed"
#     forever. Modelled by leaving the companion's files exactly where they are and
#     removing only its registry entry.
write_registry "some-other-plugin@some-other-market"
resolve "$CFG"
ok "files on disk but no registry entry -> exit 1" "$rc" 1
ok "…and the companion's file is still there (so this proves the registry decided)" \
   "$(yn test -f "$COMPANION/companion/AUTONOMY.md")" yes

echo
echo "== 5. commit-as.sh's promotion guard reads the same lookup =="
# The guard is where the extension point has teeth: it decides whether an agent-role
# commit may carry `status: ready`. One reader, so the guard and the loop cannot come to
# disagree about whether delegation exists at all.
ok "commit-as.sh calls resolve-autonomy.sh" \
   "$(grep -c 'resolve-autonomy.sh' "$REPO/plugin/scripts/commit-as.sh" | tr -d ' ')" 2
ok "…and still falls back to the root-only check it used to be" \
   "$(grep -c '\[ -f "\$repo_root/AUTONOMY.md" \] && delegation_possible=1' "$REPO/plugin/scripts/commit-as.sh" | tr -d ' ')" 1

echo
echo "== 6. loopd-yolo is a real, installable marketplace entry =="
if command -v jq >/dev/null 2>&1; then
  ok "the marketplace lists loopd-yolo" \
     "$(jq -r '[.plugins[].name] | index("loopd-yolo") | if . == null then "no" else "yes" end' "$MJ")" yes
  SRC="$(jq -r '.plugins[] | select(.name=="loopd-yolo") | .source' "$MJ")"
  ok "…its source is a same-repo relative path" "$(printf '%s' "$SRC" | grep -c '^\./' | tr -d ' ')" 1
  ok "…which resolves to a plugin manifest" \
     "$(yn test -f "$REPO/${SRC#./}/.claude-plugin/plugin.json")" yes
  ok "…whose name matches the entry" "$(jq -r .name "$REPO/${SRC#./}/.claude-plugin/plugin.json")" "loopd-yolo"
  ok "…and whose versions agree" \
     "$([ "$(jq -r .version "$REPO/${SRC#./}/.claude-plugin/plugin.json")" \
        = "$(jq -r '.plugins[] | select(.name=="loopd-yolo") | .version' "$MJ")" ] && echo yes || echo no)" yes
  # The deprecation stub was removed at 1.0.0 (ai-bridge-v2/task-019) after its one
  # version. Asserted from this file too, because the entry sat NEXT to the companion's
  # and a re-add would silently restore an install path for a name nothing maintains.
  ok "the ai-bridge-v2 stub entry is gone" \
     "$(jq -r '[.plugins[].name] | index("ai-bridge-v2") | if . == null then "no" else "yes" end' "$MJ")" no
  ok "…and core is still plugins[0]" "$(jq -r '.plugins[0].name' "$MJ")" "$PN"
else
  echo "  SKIP  jq not installed — the manifest checks need it"
fi

# The vendor's own validator, when present. It is the closest thing to "installable" that
# can be answered before the entry is on the default branch: `/plugin install` resolves the
# marketplace from the REMOTE, so the install itself is only exercisable after merge — and
# actually installing it here would arm delegated autonomy on this machine, which is a
# decision, not a test step.
# Not in the merge-gate tier: AB_TIER=gate (tests/run.sh) spawns no claude CLI at all.
if [ "${AB_TIER:-deep}" = deep ] && command -v claude >/dev/null 2>&1; then
  vout="$(claude plugin validate "$YOLO" --strict 2>&1)"; vrc=$?
  ok "claude plugin validate --strict passes on plugin-yolo" "$vrc" 0
  [ "$vrc" -eq 0 ] || printf '%s\n' "$vout" | sed 's/^/        | /'
else
  echo "  SKIP  claude CLI not spawned here (tier=${AB_TIER:-deep}) — the jq manifest checks above still hold"
fi

echo
echo "== 7. the companion ships the capability file AND NOTHING ELSE core needs =="
ok "plugin-yolo/companion/AUTONOMY.md exists" "$(yn test -f "$YOLO/companion/AUTONOMY.md")" yes
ok "…at the fixed relative path the resolver reads" \
   "$(grep -c 'COMPANION_REL="companion/AUTONOMY.md"' "$RESOLVE" | tr -d ' ')" 1
ok "…and it is the type SCHEMA.md gives it" \
   "$(grep -c '^type: Reference$' "$YOLO/companion/AUTONOMY.md" | tr -d ' ')" 1
# A companion shipping a second copy of a PreToolUse enforcement hook would fire it in
# every session on the machine; a second agent set would shadow the real one.
ok "ships no hooks"   "$(yn test -e "$YOLO/hooks")"   no
ok "ships no agents"  "$(yn test -e "$YOLO/agents")"  no
ok "ships no skills"  "$(yn test -e "$YOLO/skills")"  no
ok "ships no scripts" "$(yn test -e "$YOLO/scripts")" no
# The core file is gone from where the template used to keep it: one copy, never two.
# path-scan: absent — asserted GONE; one copy, never two
ok "core no longer carries a capability file" "$(yn test -e "$REPO/docs/autonomy")" no

echo
echo "== 8. the contract is documented where a companion author would look =="
ok "plugin/README.md has a Companion plugins section" \
   "$(grep -c '^## Companion plugins$' "$PLUGIN_README" | tr -d ' ')" 1
# The three things criterion 1 asks the contract to state. Matched on the substantive
# words rather than a whole sentence, so a rewrite that keeps the rule keeps the test.
ok "…it says how a companion registers (a marketplace entry)" \
   "$(grep -c 'marketplace.json' "$PLUGIN_README" | tr -d ' ')" 1
ok "…it names the fixed relative path core reads" \
   "$(grep -c 'companion plugin root>/companion/' "$PLUGIN_README" | tr -d ' ')" 1
ok "…and it states the ADD-never-remove rule" \
   "$(grep -c 'may ADD behaviour' "$PLUGIN_README" | tr -d ' ')" 1
ok "…naming the thing that may not be removed" \
   "$(grep -c 'remove a core gate' "$PLUGIN_README" | tr -d ' ')" 2
# The rule is only worth anything if the gates it protects are still there with NO
# companion installed, which is section 1 above plus this: core seeds the deny baseline
# and SCHEMA.md's two human authorities regardless of what is installed.
ok "…and core still states the two human authorities" \
   "$(grep -c 'Two human authorities' "$REPO/plugin/seed/SCHEMA.md" | tr -d ' ')" 1

echo
echo "== 9. UNINSTALLED BUT STILL CACHED — the case the design rests on, laid out as the =="
echo "==    real cache is. This is a security boundary, not a refactor.                  =="
# WHY THIS SECTION EXISTS WHEN 4(c) ALREADY SAYS "no registry entry -> exit 1".
# 4(c) models the uninstall by putting the companion's files at $TMP/companion — a path
# that is nowhere near a cache tree. So it pins "the registry decided" and is BLIND to the
# one regression the resolver's own header names: a fallback that globs
# `<config>/plugins/cache/<marketplace>/*/*/` when the registry comes back empty. MEASURED
# on this branch: with exactly that fallback spliced into the resolver, sections 1-8 above
# report 37 PASS and 0 FAIL. A green suite over a resolver that re-arms delegated autonomy
# after the human uninstalled the thing that armed it.
#
# The regression is not hypothetical-looking from the inside, which is why it needs a
# reader rather than a comment: on a real machine the plugin IS on disk, with its
# `companion/AUTONOMY.md` intact, in every version ever fetched (measured: 11 stale
# version directories with the companion uninstalled). "The registry is stale, read the
# disk" is the obvious-looking fix, and it silently delegates the human's promotion and
# merge gates.
#
# So the fixture below is cache-SHAPED: the exact path the plugin manager writes, several
# stale versions deep, under the same CLAUDE_CONFIG_DIR the resolver reads its registry
# from. Every assertion here must answer `gated`.
CACHE="$CFG/plugins/cache/${PMK}/loopd-yolo"
for v in 0.13.0 0.14.0 0.15.0; do
  mkdir -p "$CACHE/$v/companion"
  printf '# a capability file left behind by version %s\n' "$v" > "$CACHE/$v/companion/AUTONOMY.md"
done

# write_registry_at <key> <installPath> — write_registry() above always points at
# $COMPANION; these cases need the path under test.
write_registry_at() {
  cat > "$CFG/plugins/plugins.tmp" <<JSON
{
  "version": 2,
  "plugins": {
    "$1": [
      {
        "scope": "user",
        "installPath": "$2",
        "version": "0.15.0",
        "installedAt": "2026-09-05T00:00:00.000Z"
      }
    ]
  }
}
JSON
  mv "$CFG/plugins/plugins.tmp" "$CFG/plugins/installed_plugins.json"
}

# (a) THE HEADLINE CASE. Three cached versions on disk, each carrying the capability file
#     at the fixed relative path, and the registry lists somebody else entirely.
write_registry_at "some-other-plugin@some-other-market" "$TMP/unrelated"
resolve "$CFG"
ok "3 cached versions on disk, none installed -> exit 1" "$rc" 1
ok "…and it prints nothing"                              "$([ -z "$out" ] && echo yes || echo no)" yes
ok "…while the cached file is demonstrably still there"  \
   "$(yn test -f "$CACHE/0.15.0/companion/AUTONOMY.md")" yes

# (b) NO REGISTRY AT ALL, cache intact. The shape of a machine that has never installed a
#     companion but fetched one once, and of a config dir whose registry was deleted.
mv "$CFG/plugins/installed_plugins.json" "$CFG/plugins/installed_plugins.json.away"
resolve "$CFG"
ok "cache intact, registry file absent -> exit 1"        "$rc" 1
mv "$CFG/plugins/installed_plugins.json.away" "$CFG/plugins/installed_plugins.json"

# (c) THE REGISTRY NAMES A VERSION THAT IS GONE, and another version is still cached. The
#     answer is NOT "then use the one that is there": an entry pointing at a directory
#     that no longer exists is a companion that is not installed, and falling through to a
#     sibling version would resolve a capability the registry never granted. This is the
#     half-uninstalled state a failed upgrade leaves behind.
write_registry_at "loopd-yolo@${PMK}" "$CACHE/9.9.9"
resolve "$CFG"
ok "registry names a missing version, 0.15.0 cached -> exit 1" "$rc" 1

# (d) NON-VACUOUS BY CONSTRUCTION, in the direction that matters. The same fixture with
#     the registry pointing at a version that IS on disk must clear — otherwise (a)-(c)
#     would pass on a resolver that says no to everything, and this whole section would
#     be measuring nothing.
write_registry_at "loopd-yolo@${PMK}" "$CACHE/0.15.0"
resolve "$CFG"
ok "the SAME cached tree, this time installed -> exit 0"  "$rc" 0
ok "…and it is the registry's version that answers"       "$out" "$CACHE/0.15.0/companion/AUTONOMY.md"

# (e) THE REGRESSION GUARD. Everything above is an assertion about the resolver we ship;
#     this is the assertion about the TEST. It runs a MUTANT resolver — the cache-tree
#     fallback, spliced in exactly where a well-meaning fix would go — and proves two
#     things at once: the new cases KILL it, and 4(c)'s non-cache-shaped fixture does NOT.
#     Without this, a later tidy-up could delete the cache-shaped fixture, keep the
#     assertions, and leave the hole open with the suite still green.
# Checkout-shaped, beside the real name helper and both manifests: a lone copy derives no
# marketplace at all and refuses for that reason, which would prove nothing about the splice.
MUT_ROOT="$TMP/mutant-checkout"
mkdir -p "$MUT_ROOT/plugin/scripts" "$MUT_ROOT/plugin/.claude-plugin" "$MUT_ROOT/.claude-plugin"
cp "$REPO/plugin/scripts/plugin-name.sh" "$MUT_ROOT/plugin/scripts/"
cp "$REPO/plugin/.claude-plugin/plugin.json" "$MUT_ROOT/plugin/.claude-plugin/"
cp "$MJ" "$MUT_ROOT/.claude-plugin/"
MUTANT="$MUT_ROOT/plugin/scripts/resolve-autonomy.sh"
awk '
  /^exit 1$/ && !done {
    print "cache_root=\"${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/plugins/cache/$marketplace\""
    print "for d in \"$cache_root\"/*/*/; do"
    print "  if [ -f \"$d$COMPANION_REL\" ]; then printf \"%s\\n\" \"$d$COMPANION_REL\"; exit 0; fi"
    print "done"
    done = 1
  }
  { print }
' "$RESOLVE" > "$MUTANT"
chmod +x "$MUTANT"
# The splice must have landed, or the two assertions below are comparing the resolver to
# itself and would both "pass" while proving nothing.
ok "the mutant differs from the shipped resolver" \
   "$(cmp -s "$MUTANT" "$RESOLVE" && echo same || echo differs)" differs

mutant_rc() { # <config-dir> <companion-root-for-4c> -> the mutant's exit status
  ( CLAUDE_CONFIG_DIR="$1" "$MUTANT" --bundle "$BUNDLE" >/dev/null 2>&1 ); echo $?
}

# The cache-shaped fixture of (a): the mutant finds a cached version and CLEARS. That is
# the hole, and case (a) is what fails on it.
write_registry_at "some-other-plugin@some-other-market" "$TMP/unrelated"
ok "the new cache-shaped case KILLS the mutant (it clears where we refuse)" \
   "$(mutant_rc "$CFG")" 0

# 4(c)'s fixture: companion files at $TMP/companion, nothing in the cache tree for THIS
# config dir. The mutant survives it untouched — which is the measured blindness this
# section was added for, asserted rather than asserted-about-in-a-comment.
rm -rf "$CACHE"
ok "…while 4(c)'s non-cache fixture lets the mutant survive" \
   "$(mutant_rc "$CFG")" 1

echo
echo "== 10. loopd-all is a BUNDLE: a dependencies list this marketplace resolves, and =="
echo "==     NO component of its own                                                   =="
# THE FAILURE THIS EXISTS FOR. The bundle is a plugin whose manifest is a `name` and a
# `dependencies` list — the shape the host docs call a bundle. The host disables a
# dependent when one of its dependencies is disabled, so the ONE property that lets a human
# turn a mod off in `/plugin` at no cost is that the bundle ships nothing to lose: a hook or
# a skill added here would be the first thing gone the day a mod is disabled. The list has
# to resolve too — a bare name is looked up in THIS marketplace, so a name no entry carries
# fails the install for everyone who runs the one command this plugin exists to provide.
ALL="$REPO/plugin-all"
ALLM="$ALL/.claude-plugin/plugin.json"
ok "plugin-all ships a manifest" "$(yn test -f "$ALLM")" yes
ok "…and a README"               "$(yn test -f "$ALL/README.md")" yes
for d in hooks skills agents commands companion bin scripts; do
  ok "…and no $d/ (component-free by contract)" "$(yn test -e "$ALL/$d")" no
done
if command -v jq >/dev/null 2>&1; then
  COMPONENT_KEYS='["hooks","skills","agents","commands","mcpServers","lspServers","outputStyles","workflows","experimental","settings","userConfig"]'
  ok "the manifest declares no component key" \
     "$(jq -r --argjson ck "$COMPONENT_KEYS" '[keys[] | select(. as $k | $ck | index($k))] | length' "$ALLM")" 0
  ok "…and a non-empty dependencies list" \
     "$(jq -r '(.dependencies // []) | length > 0' "$ALLM")" true
  # Every entry is a BARE NAME some entry of this marketplace carries. A `name@market` or an
  # object form would be a cross-marketplace claim this bundle has no business making.
  # `$d` is bound FIRST: inside `$names | index(.)` jq rebinds `.` to `$names`, which
  # searches the array for itself and finds it at 0 — the planted control below caught that.
  UNRESOLVED='($mkt[0].plugins | map(.name)) as $names
              | .dependencies[] | . as $d
              | select(($d | type) != "string" or ($d | contains("@")) or (($names | index($d)) == null))'
  ok "…every dependency is a bare name this marketplace resolves" \
     "$(jq -r --slurpfile mkt "$MJ" "$UNRESOLVED" "$ALLM" | grep -c . || true)" 0
  ok "…core is among them"              "$(jq -r --arg pn "$PN" '.dependencies | index($pn) != null' "$ALLM")" true
  ok "…and the bundle never lists itself" "$(jq -r '.dependencies | index("loopd-all") == null' "$ALLM")" true
  # THE OTHER DIRECTION, and the reason the bundle is a separate plugin at all: core carries
  # no `dependencies`. Put the list on core and a disabled mod would disable the loop —
  # every command, both enforcement hooks, the agents.
  ok "core declares no dependencies (a disabled mod must never disable the loop)" \
     "$(jq -r 'has("dependencies") | not' "$REPO/plugin/.claude-plugin/plugin.json")" true
  # The two launcher companions are OUT by decision — per-machine choices their READMEs make
  # the human take by hand — so the list is pinned closed in that direction too. Adding one
  # means changing this line and saying why in the PR.
  ok "…and neither launcher companion is forced on a default install" \
     "$(jq -r '[.dependencies[] | select(. == "loopd-accounts" or . == "loopd-llm")] | length' "$ALLM")" 0
  ok "the marketplace lists loopd-all" \
     "$(jq -r '[.plugins[].name] | index("loopd-all") | if . == null then "no" else "yes" end' "$MJ")" yes
  ok "…with a same-repo source that is this directory" \
     "$(jq -r '.plugins[] | select(.name=="loopd-all") | .source' "$MJ")" "./plugin-all"
  # Non-vacuity: the resolver check must fire on a name no entry carries, or the 0 above is
  # a jq filter that matches nothing.
  ok "…and that resolution check catches a planted unknown name" \
     "$(printf '{"dependencies":["%s","no-such-plugin"]}\n' "$PN" \
        | jq -r --slurpfile mkt "$MJ" "$UNRESOLVED" | grep -c . || true)" 1
else
  echo "  SKIP  jq not installed — the bundle manifest checks need it"
fi
# `resolve-autonomy.sh` reads what is INSTALLED (section 9), and a plugin disabled from
# `/plugin` is still installed — so for loopd-yolo the off switch is uninstall, and the
# bundle's README is where a human who installed everything in one line will look for it.
ok "its README says loopd-yolo's off switch is uninstall, not disable" \
   "$(grep -c 'uninstall\*\* — not disable' "$ALL/README.md" | tr -d ' ')" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
