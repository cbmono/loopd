#!/usr/bin/env bash
#
# plugin-native-bootstrap.test.sh — a bundle carries NO machinery, and everything the
# plugin invokes lives under `plugin/` and is reached through `${CLAUDE_PLUGIN_ROOT}`.
#
# WHY THIS FILE EXISTS SEPARATELY FROM THE HARNESSES THAT ALREADY STAMP FIXTURES.
# `moved-template`, `retire-machinery` and `config-layer` each check one behaviour of the
# installer. What none of them can check is the property the migration is FOR: that no
# path anywhere in the plugin reaches back into a bundle for a script, and that a bundle a
# stamp produces holds nothing but data. Both are grep-and-find questions over the whole
# tree rather than assertions about one run, so they get their own file — and a property
# nothing measures is a property that comes back.
#
# THE FOUR THINGS PINNED HERE, one per section:
#   1. no skill, agent or hook references `symlink/scripts`, `symlink/hooks`, or an
#      instance-relative `scripts/<name>.sh` path — every reference is
#      `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`, and every script it names EXISTS;
#   2. a freshly stamped bundle passes `validate-bundle.sh` and the welcome banner;
#   3. that bundle holds ZERO symlinks outside `repos/`;
#   4. a fixture stamped the symlink-era way converts in place, and its data survives
#      byte for byte.
#
# ok() compares actual to expected, per this directory's convention.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/plugin-native.XXXXXX")" || {
  echo "plugin-native-bootstrap.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

INIT="$REPO/plugin/scripts/init-bundle.sh"

# =========================================================================================
echo "== 1. every script the plugin invokes lives under plugin/ and is named through \${CLAUDE_PLUGIN_ROOT} =="
# =========================================================================================
# THE THREE SURFACES THE CRITERION NAMES — a skill, an agent, a hook — plus the machinery
# itself, because a script that tells a human to run a path a bundle does not have is the
# same defect one layer down. `${CLAUDE_PLUGIN_ROOT}/scripts/x.sh` contains the substring
# `scripts/x.sh`, so the pattern is anchored on what precedes it: a match is a reference
# NOT already qualified.
SCAN=$(cd "$REPO" && find plugin -type f \( -name '*.md' -o -name '*.sh' -o -name '*.json' \) | sort)
ok "there is something to scan"          "$([ -n "$SCAN" ] && echo yes || echo no)" yes

# (a) the two retired source roots, by name.
ok "no reference to symlink/scripts anywhere in plugin/" \
   "$(cd "$REPO" && grep -rl 'symlink/scripts' plugin/ 2>/dev/null | grep -v 'plugin/scripts/init-bundle.sh\|plugin/hooks/session-banner.sh' | wc -l | tr -d ' ')" 0
ok "no reference to symlink/hooks anywhere in plugin/" \
   "$(cd "$REPO" && grep -rl 'symlink/hooks' plugin/ 2>/dev/null | wc -l | tr -d ' ')" 0
# init-bundle.sh and session-banner.sh are the two exceptions, and they are exceptions for
# one reason: they are the code that RECOGNISES a legacy link. Asserted positively so the
# waiver names what it is for rather than hiding a regression.
ok "…except where the conversion sweep matches one, on purpose" \
   "$(cd "$REPO" && grep -c 'symlink/' plugin/scripts/init-bundle.sh | tr -d ' ')" 2

# (b) an instance-relative script path, in a skill, an agent or a hook.
# WHOLE LINES, not just the matched fragment: the one legitimate mention is the banner's
# PROBES list, which names the symlink-era paths it is LOOKING FOR, and a fragment-only
# grep cannot tell that line from any other. Filtering needs the line.
UNQUAL="$(cd "$REPO" && grep -rnE '(^|[^/A-Za-z_])scripts/[a-z0-9-]+\.sh' \
           plugin/skills plugin/agents plugin/hooks 2>/dev/null \
         | grep -v 'PROBES=' || true)"
ok "no instance-relative scripts/ path in a skill, agent or hook" \
   "$(printf '%s' "$UNQUAL" | grep -c . | tr -d ' ')" 0
[ -z "$UNQUAL" ] || printf '%s\n' "$UNQUAL" | sed 's/^/        /'

# (c) NON-VACUITY. The pattern above must actually catch one, or "0 matches" means the
# grep is broken rather than the tree being clean.
printf 'run scripts/commit-as.sh now\n' > "$TMP/decoy.md"
ok "…and the same pattern DOES catch a bare reference" \
   "$(grep -coE '(^|[^/A-Za-z_])scripts/[a-z0-9-]+\.sh' "$TMP/decoy.md" | tr -d ' ')" 1

# (d) every script the plugin NAMES through the variable exists under plugin/scripts/.
# A reference that is correctly spelled and points at nothing is the failure this catches.
MISSING=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -f "$REPO/plugin/scripts/$name" ] || MISSING="${MISSING:+$MISSING }$name"
done <<EOF
$(cd "$REPO" && grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[a-z0-9-]+\.sh' plugin/ 2>/dev/null \
  | sed 's#.*/##' | sort -u)
EOF
ok "every \${CLAUDE_PLUGIN_ROOT}/scripts/… reference resolves" "${MISSING:-none}" none

# (e) the hooks manifest names its own files the same way, and every one exists.
# `agent-control.sh` is on `SubagentStart` and `SubagentStop` as well as `PreToolUse` — the
# two events that start and drop its per-agent state; `report-shape.sh` is on `SubagentStop`.
HOOKCMDS="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for ev in d["hooks"].values():
    for g in ev:
        for h in g["hooks"]:
            print(h["command"])' "$REPO/plugin/hooks/hooks.json" 2>/dev/null)"
ok "hooks.json registers nine commands" "$(printf '%s\n' "$HOOKCMDS" | grep -c . | tr -d ' ')" 9
ok "…naming seven distinct scripts"      "$(printf '%s\n' "$HOOKCMDS" | sort -u | grep -c . | tr -d ' ')" 7
ok "…every one through \${CLAUDE_PLUGIN_ROOT}" \
   "$(printf '%s\n' "$HOOKCMDS" | grep -cv '^"\${CLAUDE_PLUGIN_ROOT}/hooks/[a-z-]*\.sh"' | tr -d ' ')" 0
HOOKMISS=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  f="${c#\"\$\{CLAUDE_PLUGIN_ROOT\}/}"; f="${f%%\"*}"
  [ -f "$REPO/plugin/$f" ] || HOOKMISS="${HOOKMISS:+$HOOKMISS }$f"
done <<EOF
$HOOKCMDS
EOF
ok "…and every registered hook file exists"  "${HOOKMISS:-none}" none

# (f) the retired design is gone from the tree entirely.
# path-scan: absent — asserted GONE; this line IS the assertion that it went
ok "the repo ships no symlink/ directory"    "$(yn test -e "$REPO/symlink")" no
ok "install.sh is a stub that refuses"       "$(bash "$REPO/install.sh" /tmp >/dev/null 2>&1; echo $?)" 2
ok "…naming /${PN}:init"                 "$(bash "$REPO/install.sh" 2>&1 | grep -c '/'"${PN}:"'init' | tr -d ' ')" 1
ok "…on ONE screen (≤ 40 lines)"             "$([ "$(bash "$REPO/install.sh" 2>&1 | grep -c .)" -le 40 ] && echo yes || echo no)" yes
ok "upgrade.sh is a stub that refuses"       "$(bash "$REPO/upgrade.sh" /tmp >/dev/null 2>&1; echo $?)" 2
ok "…naming /${PN}:welcome fix"          "$(bash "$REPO/upgrade.sh" 2>&1 | grep -c ''"${PN}:"'welcome fix' | tr -d ' ')" 1
ok "…on ONE screen (≤ 40 lines)"             "$([ "$(bash "$REPO/upgrade.sh" 2>&1 | grep -c .)" -le 40 ] && echo yes || echo no)" yes

# =========================================================================================
echo "== 2. a stamped bundle passes the validator and the banner =="
# =========================================================================================
FRESH="$TMP/_ai-bridge-fresh"
bash "$INIT" "$FRESH" >"$TMP/fresh.out" 2>&1
FRC=$?
ok "the stamp exits 0"                   "$FRC" 0
ok "…creating the directory it was given" "$(yn test -d "$FRESH")" yes
ok "…with instance.config.json"          "$(yn test -f "$FRESH/instance.config.json")" yes
ok "…and instance.config.local.json"     "$(yn test -f "$FRESH/instance.config.local.json")" yes
ok "…the seed docs"                      "$(yn bash -c 'test -f "$1/CLAUDE.md" && test -f "$1/$AB_SCHEMA" && test -f "$1/$AB_CONVENTIONS" && test -f "$1/$AB_ROSTER"' _ "$FRESH")" yes
ok "…its own .claude/settings.json"      "$(yn test -f "$FRESH/.claude/settings.json")" yes
ok "…the awaiting queue, on a FIRST stamp only" "$(yn test -f "$FRESH/$AB_AWAITING")" yes
ok "…and a .gitignore with no machinery block" \
   "$(grep -c 'ai-bridge machinery' "$FRESH/.gitignore" | tr -d ' ')" 0
ok "…and the derived-index ignore block"  "$(grep -c 'ai-bridge index ignore' "$FRESH/.gitignore" | tr -d ' ')" 2
ok "validate-bundle.sh reports no error" \
   "$( ( cd "$FRESH" && bash "$REPO/plugin/scripts/validate-bundle.sh" >/dev/null 2>&1 ); echo $? )" 0
BANNER="$(CLAUDE_PROJECT_DIR="$FRESH" bash "$REPO/plugin/hooks/session-banner.sh" 2>&1)"
ok "the welcome banner prints"           "$([ -n "$BANNER" ] && echo yes || echo no)" yes
ok "…and raises no machinery alarm"      "$(printf '%s' "$BANNER" | grep -c 'MACHINERY SYMLINKS' | tr -d ' ')" 0
ok "the roster prompt is skipped with no tty" "$(grep -c 'stdin is not a terminal' "$TMP/fresh.out" | tr -d ' ')" 1
# The roster note's own placeholder, not a bare `ownerGithubUser`: step 4c now reports the
# identity it DERIVED, and that line names the key too.
ok "…and says how to set the three values by hand" "$(grep -c '<your-login>' "$TMP/fresh.out" | tr -d ' ')" 1
# …and the clone's own per-machine file is written for it, with the one value that is
# derivable on any machine (the bundle's parent). Login and address depend on the host.
ok "…while this clone's local config is written" "$(yn test -f "$FRESH/instance.config.local.json")" yes
ok "…carrying the derived reposRoot"     "$(grep -c '"reposRoot"' "$FRESH/instance.config.local.json" | tr -d ' ')" 1
# IDEMPOTENT, and the queue's off switch survives it: AWAITING.md is created on a FIRST
# stamp only, so a deletion must be permanent.
rm -f "$FRESH/$AB_AWAITING"
bash "$INIT" "$FRESH" >"$TMP/fresh2.out" 2>&1
ok "a re-stamp exits 0"                  "$?" 0
ok "…and does NOT resurrect AWAITING.md" "$(yn test -e "$FRESH/$AB_AWAITING")" no
ok "…seeding nothing new"                "$(grep -c '^  seed ' "$TMP/fresh2.out" | tr -d ' ')" 0

# =========================================================================================
echo "== 3. that bundle holds ZERO symlinks outside repos/ =="
# =========================================================================================
# THE CRITERION, MEASURED. `find` does not follow symlinks, so it cannot descend into a
# linked repo; `repos/` is excluded because those links point at reposRoot and are the one
# derived view a bundle is supposed to hold.
STRAY="$(find "$FRESH" -type l -not -path "$FRESH/repos/*" 2>/dev/null)"
ok "no symlink outside repos/"           "$(printf '%s' "$STRAY" | grep -c . | tr -d ' ')" 0
[ -z "$STRAY" ] || printf '%s\n' "$STRAY" | sed 's/^/        /'
# NON-VACUITY: the same find, given one, reports it.
ln -s "$TMP" "$FRESH/decoy-link"
ok "…and the same scan DOES see one when there is one" \
   "$(find "$FRESH" -type l -not -path "$FRESH/repos/*" 2>/dev/null | grep -c . | tr -d ' ')" 1
rm -f "$FRESH/decoy-link"

# =========================================================================================
echo "== 4. a symlink-era bundle converts in place, and its data survives =="
# =========================================================================================
# The fixture is stamped the way the retired install.sh stamped: absolute symlinks into a
# template checkout, a managed .gitignore block, and real data beside them.
OLD="$TMP/oldtpl"
mkdir -p "$OLD/seed" "$OLD/symlink/scripts" "$OLD/symlink/.claude/hooks" "$(dirname "$OLD/symlink/$AB_ROSTER")"
printf '0.20.0\n' > "$OLD/VERSION"; printf '{}\n' > "$OLD/seed/instance.config.json"
for f in SCHEMA.md CONVENTIONS.md AUTONOMY.md; do printf 'old %s\n' "$f" > "$OLD/symlink/$f"; done
printf 'old roster\n' > "$OLD/symlink/$AB_ROSTER"
printf '#!/bin/sh\n' > "$OLD/symlink/scripts/commit-as.sh"
printf '#!/bin/sh\n' > "$OLD/symlink/.claude/hooks/push-state.sh"

LEG="$TMP/_ai-bridge-legacy"
mkdir -p "$LEG/scripts" "$LEG/.claude/hooks" "$LEG/agents" \
         "$LEG/projects/demo/tasks" "$LEG/knowledge/findings" "$LEG/objectives"
cp "$REPO/plugin/seed/instance.config.json" "$LEG/instance.config.json"
printf 'a decision only this bundle holds\n' > "$LEG/projects/demo/index.md"
printf -- '---\ntype: Task\ntitle: t\nstatus: draft\ntimestamp: 2026-01-01T00:00:00Z\n---\nbody\n' > "$LEG/projects/demo/tasks/task-001-x.md"
printf -- '---\ntype: Finding\ntitle: F\nstatus: current\nprovenance: human\ntimestamp: 2026-01-01T00:00:00Z\n---\na finding\n' > "$LEG/knowledge/findings/f.md"
printf 'the log\n' > "$LEG/log.md"
DATA_BEFORE="$(cat "$LEG/projects/demo/index.md" "$LEG/projects/demo/tasks/task-001-x.md" \
                   "$LEG/knowledge/findings/f.md" "$LEG/log.md")"
for p in SCHEMA.md CONVENTIONS.md AUTONOMY.md; do ln -s "$OLD/symlink/$p" "$LEG/$p"; done
# The legacy links sat at the PRE-3.0 root, which is what makes this a legacy bundle.
ln -s "$OLD/symlink/agents/index.md" "$LEG/agents/index.md"
ln -s "$OLD/symlink/scripts/commit-as.sh" "$LEG/scripts/commit-as.sh"
ln -s "$OLD/symlink/.claude/hooks/push-state.sh" "$LEG/.claude/hooks/push-state.sh"
ln -s "$TMP/never-existed/x.sh" "$LEG/scripts/dead.sh"
mkdir -p "$TMP/mynotes"; ln -s "$TMP/mynotes" "$LEG/mynotes"
cat > "$LEG/.gitignore" <<'GI'
.DS_Store
my-own-rule/

# >>> ai-bridge machinery (symlinked) >>>
/SCHEMA.md
/scripts/commit-as.sh
# <<< ai-bridge machinery <<<
GI

ok "the fixture really carries 8 symlinks" \
   "$(find "$LEG" -type l | grep -c . | tr -d ' ')" 8
bash "$INIT" "$LEG" >"$TMP/convert.out" 2>&1
ok "the conversion exits 0"              "$?" 0
ok "…and only the human's own link is left" \
   "$(find "$LEG" -type l | grep -c . | tr -d ' ')" 1
ok "…which is theirs"                    "$(yn test -L "$LEG/mynotes")" yes
# AT LEAST ONCE, not exactly once. The stamp runs the welcome check-and-fix pass after its
# sweep, and `bundle-unconverted` counts every symlink outside the data dirs — including
# one the sweep KEEPS — so its repair re-stamps once more and the line is printed again.
# Bounded at one extra stamp: that stamp inherits AI_BRIDGE_INIT_PASS and runs no pass.
ok "…reported as kept, not removed" \
   "$([ "$(grep -c 'keep  mynotes' "$TMP/convert.out" | tr -d ' ')" -ge 1 ] && echo yes || echo no)" yes
ok "…and a dangling one was retired as such" \
   "$(grep -c 'retire scripts/dead.sh — dangling' "$TMP/convert.out" | tr -d ' ')" 1
ok "…and a LIVE one as a machinery link" \
   "$(grep -c 'retire scripts/commit-as.sh — machinery link' "$TMP/convert.out" | tr -d ' ')" 1
ok "SCHEMA.md is a real file now"        "$(yn bash -c 'test -f "$1/$AB_SCHEMA" && ! test -L "$1/$AB_SCHEMA"' _ "$LEG")" yes
ok "CONVENTIONS.md too"                  "$(yn bash -c 'test -f "$1/$AB_CONVENTIONS" && ! test -L "$1/$AB_CONVENTIONS"' _ "$LEG")" yes
ok "agents/index.md too"                 "$(yn bash -c 'test -f "$1/$AB_ROSTER" && ! test -L "$1/$AB_ROSTER"' _ "$LEG")" yes
# AUTONOMY.md is the deliberate exception — absence is the safe default, so it is NOT
# restored, and the loss is reported loudly with the command to undo it.
ok "AUTONOMY.md is NOT restored"         "$(yn test -e "$LEG/AUTONOMY.md")" no
ok "…and the loss is reported"           "$(grep -c 'ask-first' "$TMP/convert.out" | tr -d ' ')" 1
ok "…with the install that opts back in" "$(grep -c 'loopd-yolo@loopd' "$TMP/convert.out" | tr -d ' ')" 1
ok "the machinery .gitignore block is retired" \
   "$(grep -c 'ai-bridge machinery' "$LEG/.gitignore" | tr -d ' ')" 0
ok "…while the human's own rule survives" "$(grep -cx 'my-own-rule/' "$LEG/.gitignore" | tr -d ' ')" 1
ok "the DATA is byte-identical" \
   "$([ "$DATA_BEFORE" = "$(cat "$LEG/projects/demo/index.md" "$LEG/projects/demo/tasks/task-001-x.md" \
                                "$LEG/knowledge/findings/f.md" "$LEG/log.md")" ] && echo yes || echo no)" yes
ok "the emptied scripts/ directory is gone" "$(yn test -e "$LEG/scripts")" no
ok "the banner is green afterwards" \
   "$(CLAUDE_PROJECT_DIR="$LEG" bash "$REPO/plugin/hooks/session-banner.sh" 2>&1 | grep -c 'MACHINERY SYMLINKS' | tr -d ' ')" 0
ok "validate-bundle.sh reports no error" \
   "$( ( cd "$LEG" && bash "$REPO/plugin/scripts/validate-bundle.sh" >/dev/null 2>&1 ); echo $? )" 0
# Idempotent: a second conversion retires nothing and keeps their link.
bash "$INIT" "$LEG" >"$TMP/convert2.out" 2>&1
ok "a second conversion retires nothing" "$(grep -c '^  retire ' "$TMP/convert2.out" | tr -d ' ')" 0
ok "…and the human's link is still there" "$(yn test -L "$LEG/mynotes")" yes

# =========================================================================================
echo "== 5. the INSTALLED layout: a stamp from a plugin cache, with no checkout anywhere =="
# =========================================================================================
# THE SECTION THIS FILE WAS MISSING, AND THE BUG IT MISSED. Section 2 stamps from
# `$REPO/plugin/scripts/`, which is a CHECKOUT — the only layout every harness here has
# ever exercised. A marketplace install is `source: ./plugin`, so what lands on a machine
# is the CONTENTS of `plugin/` under a version directory and nothing above it. Measured on
# the real 0.15.0 cache, 2026-09-05: `agents/ evals/ hooks/ scripts/ skills/ README.md`,
# and `init-bundle.sh` exited 2 with "cannot locate the loopd template root". A
# criterion of "no clone is needed" that is only ever verified against the repo is a
# criterion verified against the one layout where it could not fail.
#
# The fixture is therefore built from `git ls-files plugin/` ALONE, flattened by one level,
# under a parent that holds nothing else — so a rule that reaches upward finds what the
# real cache offers it, which is nothing.
CACHE="$TMP/cache/${PMK}/${PN}/9.9.9"
mkdir -p "$CACHE"
( cd "$REPO" && git ls-files plugin ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#plugin/}"
  mkdir -p "$CACHE/$(dirname "$rel")"; cp "$REPO/$f" "$CACHE/$rel" 2>/dev/null || true
done
chmod +x "$CACHE"/scripts/*.sh "$CACHE"/hooks/*.sh 2>/dev/null || true

# THE FIXTURE IS THE BROKEN SHAPE, asserted before anything is run against it. Without
# these three lines the section below could pass on a fixture that is quietly a checkout.
ok "the cache fixture carries VERSION where the plugin ships it" "$(yn test -f "$CACHE/VERSION")" yes
ok "…and seed/ beside scripts/"                                  "$(yn test -d "$CACHE/seed")" yes
ok "…and the OLD rule's target does not exist"                   "$(yn test -e "$CACHE/../VERSION")" no
ok "…nor does a marketplace manifest above it"                   "$(yn test -e "$CACHE/../.claude-plugin/marketplace.json")" no

CFRESH="$TMP/_ai-bridge-from-cache"
CLAUDE_PLUGIN_ROOT="$CACHE" bash "$CACHE/scripts/init-bundle.sh" "$CFRESH" >"$TMP/cache.out" 2>&1
CRC=$?
ok "the stamp exits 0 from the installed layout" "$CRC" 0
[ "$CRC" -eq 0 ] || sed 's/^/        /' "$TMP/cache.out" >&2
ok "…with instance.config.json"                  "$(yn test -f "$CFRESH/instance.config.json")" yes
ok "…the seed docs"                              "$(yn bash -c 'test -f "$1/CLAUDE.md" && test -f "$1/$AB_SCHEMA" && test -f "$1/$AB_CONVENTIONS" && test -f "$1/$AB_ROSTER"' _ "$CFRESH")" yes
ok "…and its own .claude/settings.json"          "$(yn test -f "$CFRESH/.claude/settings.json")" yes
ok "validate-bundle.sh reports no error" \
   "$( ( cd "$CFRESH" && bash "$CACHE/scripts/validate-bundle.sh" >/dev/null 2>&1 ); echo $? )" 0
CBANNER="$(CLAUDE_PROJECT_DIR="$CFRESH" CLAUDE_PLUGIN_ROOT="$CACHE" bash "$CACHE/hooks/session-banner.sh" 2>&1)"
ok "the welcome banner prints"                   "$([ -n "$CBANNER" ] && echo yes || echo no)" yes
ok "…and raises no machinery alarm"              "$(printf '%s' "$CBANNER" | grep -c 'MACHINERY SYMLINKS' | tr -d ' ')" 0
# THE VERSION REACHES THE HEADER, which is the other half of "readable from inside the
# plugin": before the mirror the banner looked one directory ABOVE the cache and found
# nothing, so an installed plugin printed a versionless header.
ok "…and the header carries the plugin's own version" \
   "$(printf '%s\n' "$CBANNER" | grep -cF "loopd v$(head -n 1 "$REPO/VERSION")" | tr -d ' ')" 1
# BYTE-FOR-BYTE THE SAME BUNDLE either layout stamps. A cache run that merely EXITS 0
# while seeding something different is the failure this catches, and it is the assertion
# that makes the rest of this section about the LAYOUT rather than about exit codes.
# Against a bundle stamped fresh here rather than section 2's `$FRESH`, which that section
# then re-stamps and mutates — comparing to it would compare two histories, not two
# layouts. The exclusions are the four paths that are per-bundle by construction: the
# workspace file is named after the directory, and the other three are generated.
RFRESH="$TMP/_ai-bridge-from-repo"
bash "$INIT" "$RFRESH" >"$TMP/repo-layout.out" 2>&1
ok "the checkout layout stamps its own control bundle" "$?" 0
ok "the two layouts stamp identical seed content" \
   "$(yn bash -c 'diff -r -q --exclude=.git --exclude=instance.config.local.json --exclude=SNAPSHOT.json --exclude=.board-live --exclude=*.code-workspace --exclude=settings.json "$1" "$2" >/dev/null' _ "$RFRESH" "$CFRESH")" yes
# `.claude/settings.json` JOINS THE PER-BUNDLE EXCLUSIONS (ai-bridge-v3/task-025): its
# `statusLine.command` names the bundle's own absolute path, so two bundles at two paths
# differ there by construction, exactly as the workspace file does. Excluding it would
# blind the comparison to a real settings difference, so the file is compared with each
# bundle's own root substituted out — same content, same one varying value.
ok "…and settings.json matches once each bundle's own root is substituted" \
   "$(yn bash -c 'diff -q <(sed "s#$1#__ROOT__#g" "$1/.claude/settings.json") \
                          <(sed "s#$2#__ROOT__#g" "$2/.claude/settings.json") >/dev/null' \
      _ "$RFRESH" "$CFRESH")" yes
ok "…and it really does carry that root, so the substitution is not a no-op" \
   "$(grep -cF "$RFRESH" "$RFRESH/.claude/settings.json" | tr -d ' ')" 1

# …and the same comparison sees a difference when there is one.
printf 'planted\n' >> "$CFRESH/CLAUDE.md"
ok "…and that comparison catches a planted difference" \
   "$(yn bash -c 'diff -r -q --exclude=.git --exclude=instance.config.local.json --exclude=SNAPSHOT.json --exclude=.board-live --exclude=*.code-workspace --exclude=settings.json "$1" "$2" >/dev/null' _ "$RFRESH" "$CFRESH")" no

# NON-VACUITY, by mutation: the derivation is VERIFIED, not assumed. Take `seed/` away and
# the same run must refuse rather than stamp an empty bundle — which is what tells this
# apart from a script that would accept any directory it is started from.
MUT="$TMP/cache-mut"; cp -R "$CACHE" "$MUT"; rm -rf "$MUT/seed"
bash "$MUT/scripts/init-bundle.sh" "$TMP/_never" >"$TMP/mut.out" 2>&1
ok "a plugin root with no seed/ is REFUSED"      "$?" 2
ok "…naming the plugin root it could not verify" "$(grep -c 'cannot locate the loopd plugin root' "$TMP/mut.out" | tr -d ' ')" 1
ok "…and nothing was stamped"                    "$(yn test -e "$TMP/_never")" no

# `--config` is the ONE thing an installed plugin cannot do, and it must say so by name.
# `config/` links absolute paths into ${CLAUDE_CONFIG_DIR:-~/.claude}, a per-machine
# decision, so it deliberately stays outside the plugin — and the refusal has to be
# distinguishable from "some directory is missing" or nobody knows to clone.
CLAUDE_CONFIG_DIR="$TMP/cfgdest" bash "$CACHE/scripts/init-bundle.sh" --config >"$TMP/cfg.out" 2>&1
ok "--config from an installed plugin refuses"   "$?" 2
ok "…saying a checkout is what it needs"         "$(grep -c 'needs a checkout of this repo' "$TMP/cfg.out" | tr -d ' ')" 1
ok "…and printing the clone command"             "$(grep -c 'git clone' "$TMP/cfg.out" | tr -d ' ')" 1
ok "…having written nothing into the config dir" "$(yn test -e "$TMP/cfgdest")" no
# AND THE UNINSTALL HALF, which is the one with teeth. `config_ours` classifies a link by
# `case $(readlink …) in "$CONFIG_SRC"/*`, so an EMPTY $CONFIG_SRC would make that pattern
# `/*` — matching every absolute symlink in the config dir and removing links this layer
# never wrote. `config_require_src` runs first on both paths, which is what keeps the
# empty value from ever reaching the glob; asserted here rather than trusted.
mkdir -p "$TMP/cfgdest2/agents"
ln -s "$TMP" "$TMP/cfgdest2/agents/somebody-elses.md"
CLAUDE_CONFIG_DIR="$TMP/cfgdest2" bash "$CACHE/scripts/init-bundle.sh" --config --uninstall >"$TMP/cfgu.out" 2>&1
ok "--config --uninstall refuses too"            "$?" 2
ok "…leaving a stranger's absolute link alone"   "$(yn test -L "$TMP/cfgdest2/agents/somebody-elses.md")" yes

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
