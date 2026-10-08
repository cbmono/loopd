#!/usr/bin/env bash
#
# init-bundle.sh — create or refresh a loopd BUNDLE, or link the CONFIG LAYER.
#
#   Usage:
#     init-bundle.sh [TARGET]           # create/refresh a bundle at TARGET (default: cwd)
#     init-bundle.sh --instance [TARGET]  # the same thing, stated explicitly
#     init-bundle.sh --refresh-seeds [TARGET]  # accepted and ignored — always applied now
#     init-bundle.sh --with-objectives [TARGET]  # also create the OPTIONAL objectives/ dir
#     init-bundle.sh --normalise-config [TARGET]  # also APPLY the config findings it reports
#     init-bundle.sh --owner LOGIN --email ADDR --repos-root DIR [TARGET]
#                                       # supply any of this clone's three per-machine
#                                       # identity values instead of deriving them (4c)
#     init-bundle.sh --org ORG [--name REPO] [TARGET]
#                                       # the ORG'S bundle: clone <ORG>/<REPO> when it is
#                                       # there, else create it private and push (step 0).
#                                       # REPO defaults to <ORG>-okf
#     init-bundle.sh --config           # link config/required/ into ~/.claude (CLAUDE_CONFIG_DIR wins)
#     init-bundle.sh --uninstall [TARGET]  # remove the repos/ view and any legacy machinery links
#     init-bundle.sh --config --uninstall   # remove only the config-layer symlinks this created
#     init-bundle.sh --help
#
# THE ENGINE BEHIND `/<plugin>:init`. It ships in the PLUGIN, and a human never needs a
# clone of this repo: the skill invokes it as ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh.
# It replaces install.sh, which now exists only as a deprecation stub.
#
# A BUNDLE CARRIES NO MACHINERY, AND THAT IS THE WHOLE CHANGE. install.sh stamped 37 files
# into a bundle as symlinks into a template checkout, by absolute path. A plugin-shipped
# installer cannot keep that design: the plugin cache path changes on every update, so
# every link would dangle. The live-symlink design existed to propagate a template `git
# pull` into every bundle; `claude plugin update` swaps the whole tree and gives the same
# property, so the symlinks lost their reason to exist.
#
# BUNDLE mode therefore does DATA and nothing else:
#   1. CONVERTS a symlink-era bundle in place — removes machinery links into a template
#      checkout and every dangling link outside repos/, and retires the managed machinery
#      block from .gitignore. Data is never touched. Idempotent: a bundle with none is
#      silent. Runs FIRST, so the seed step below can put a real file where a link was.
#   2. COPIES the `seed/` content into TARGET *only if absent* — never clobbering bundle
#      data (objectives/projects/knowledge/log/config/CLAUDE.md/SCHEMA.md/CONVENTIONS.md).
#      `objectives/` is NOT seeded: SCHEMA.md makes it an optional layer, so only
#      `--with-objectives` creates it. An existing one is data and is never touched.
#   3. Writes the derived-ignore lines, the awaiting queue and the board snapshot.
#   4. LINKS the group's product repos into TARGET/repos/ — one symlink each, via
#      link-repos.sh. Gitignored, and skipped while reposRoot is still the seeded
#      placeholder. THESE ARE THE ONLY SYMLINKS A STAMPED BUNDLE HOLDS.
#   5. On a FIRST stamp, at a terminal, OFFERS to collect the team's GitHub logins and
#      commit emails into `people` + `defaultOwner`, and writes this clone's
#      `instance.config.local.json`. One batched prompt; nothing is written until you
#      confirm it. Skipped (with the instruction printed) when stdin is not a terminal,
#      never asked on a refresh, and it never overwrites a value already there.
#   5b. WRITES `instance.config.local.json` when it is ABSENT — this clone's identity,
#      DERIVED (`gh api user`, the tracked `people` map, the bundle's parent directory)
#      and never guessed: what it cannot derive it names, and --owner/--email/--repos-root
#      supply it without a terminal. An existing local file is never rewritten here.
#   6. Reports seed DRIFT — a seed doc this repo has changed since the bundle was stamped
#      — via refresh-seeds.sh, report-only unless `--refresh-seeds` is given.
#   7. Its ONE write outside TARGET: re-points the per-machine link
#      ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/<plugin>/bin at this plugin's scripts/ (step 1g),
#      and prints — never writes — the shell-rc line that puts it on PATH.
#
# CONFIG mode links `config/required/` into the Claude Code config dir, one FILE at a
# time — never a whole directory (see the CONFIG LAYER block below). That is the WHOLE
# set: three agents this repo's own role agents probe for by absolute path
# (`code-architect`, `deep-bug-scan`, `plan-architect`). Everything else under
# `~/.claude` belongs to `cbmono/ai-setup` and is installed from there — see
# docs/claude-config-ownership.md for why, and for what not to re-add here.
# Absence is safe in the direction that matters: a bundle stamp never needs `config/`,
# and the config layer never needs a bundle. Deleting `config/required/` leaves
# `--config` linking nothing, exit 0; deleting `config/` itself makes `--config` exit 2
# saying there is nothing to link, which is a refusal to do nothing, not a breakage.
#
# Idempotent: re-running seeds nothing new and reports what is already in place.
# Backs up any conflicting real file as <name>.bak.<epoch> before writing.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

# WHERE THE PLUGIN IS — ONE RULE FOR BOTH LAYOUTS, and that is the whole of task-022.
# `source: ./plugin` in the marketplace manifest means an INSTALLED plugin is the CONTENTS
# of `plugin/`, not the repo around it: the cache holds `agents/ evals/ hooks/ scripts/
# skills/` and nothing else. The previous rule ("two directories up from scripts/") was
# written against a checkout and only ever verified against one, so `/<plugin>:init` exited
# 2 with "cannot locate the loopd template root" on every machine that installed the
# plugin the supported way — measured on 0.15.0, 2026-09-05.
#
# The rule now is ONE directory up from scripts/, which is the plugin root in both places:
#   installed:  <cache>/scripts/init-bundle.sh   ->  <cache>
#   checkout:   <root>/plugin/scripts/init-bundle.sh  ->  <root>/plugin
# That only works because everything a stamp READS now ships inside `plugin/` — `seed/`,
# `VERSION` and `RETIRED` all moved there in the same change. Derived and then VERIFIED
# (`VERSION` and `seed/` must be there), never searched for: a walk that keeps climbing
# will eventually find SOME ancestor with a VERSION file, and answering with an unrelated
# repo is worse than refusing.
# Through the operator's plugins/<plugin>/bin link (step 1g) a logical `cd ..` lands beside
# the link, so a linked scripts dir whose parent is not a plugin root is followed one hop.
_d="$(dirname "$0")"; if [ -L "$_d" ] && [ ! -f "$(dirname "$_d")/VERSION" ]; then _t="$(readlink "$_d")"; case "$_t" in /*) _d="$_t" ;; *) _d="$(dirname "$_d")/$_t" ;; esac; fi
BIN_DIR="$(cd "$_d" && pwd)"
PLUGIN_ROOT="$(cd "$BIN_DIR/.." 2>/dev/null && pwd || true)"
if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/VERSION" ] || [ ! -d "$PLUGIN_ROOT/seed" ]; then
  echo "error: cannot locate the loopd plugin root from $BIN_DIR" >&2
  echo "       (expected <plugin>/scripts/, with VERSION and seed/ at <plugin>)" >&2
  exit 2
fi

# THE CHECKOUT AROUND THE PLUGIN, WHEN THERE IS ONE — and empty is the NORMAL case, because
# an installed plugin has no repo around it. It answers for exactly one thing a stamp does
# not need: the `--config` layer (`config/` is not shipped in the plugin — it links files
# into ~/.claude, which is a machine decision, not a bundle one). Every other use below is a
# path printed inside a hint, and each one is guarded rather than left to print `/docs/...`.
#
# Recognised by the marketplace manifest itself rather than by climbing until something
# looks right: `<root>/.claude-plugin/marketplace.json` is the file that DEFINES this
# layout, so it is the only honest marker for it.
TEMPLATE_DIR=""
if [ -f "$PLUGIN_ROOT/../.claude-plugin/marketplace.json" ]; then
  TEMPLATE_DIR="$(cd "$PLUGIN_ROOT/.." && pwd)"
fi

SEED_SRC="$PLUGIN_ROOT/seed"

# A DOC PATH A HUMAN CAN OPEN, printable from either layout. Inside a checkout it is the
# file; from an installed plugin there is no checkout, so it is the same path under a
# placeholder for one. Never a bare `/docs/...`, which is what an unguarded `$TEMPLATE_DIR`
# would have printed once TEMPLATE_DIR became legitimately empty.
doc_ref() { printf '%s/%s' "${TEMPLATE_DIR:-<loopd>}" "$1"; }
# The managed machinery block a symlink-era bundle carries. It is RETIRED, never
# rewritten: there is no machinery in a bundle to list any more.
BEGIN_MARK="# >>> ai-bridge machinery (symlinked) >>>"
END_MARK="# <<< ai-bridge machinery <<<"


MODE="install"
# Which half of the repo this run is about. `instance` is the default because a BARE
# directory argument has always meant "stamp an instance here" — three live instances and
# upgrade.sh call it that way, so `--instance` is only the explicit spelling of the
# existing behaviour, never a new requirement.
LAYER="instance"
LAYER_FLAG=""
TARGET=""
REFRESH_SEEDS=0
WITH_OBJECTIVES=0
NORMALISE_CONFIG=0
# This clone's three per-machine identity values, when the caller supplies them instead of
# letting step 4c derive them. Empty means "derive it"; the values are validated there,
# where the validators live, and a rejected one is REPORTED rather than silently derived.
ID_OWNER_FLAG=""
ID_EMAIL_FLAG=""
ID_REPOS_FLAG=""
# The ORGANISATION whose bundle this is, and the repo name under it. Empty means the old
# behaviour exactly: a local folder, no host call, no remote.
ORG_FLAG=""
ORG_NAME_FLAG=""
# A while/shift loop rather than `for arg in "$@"`, because three of these flags take a
# value. Both spellings are accepted: `--owner x` and `--owner=x`.
while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --uninstall) MODE="uninstall" ;;
    # ACCEPTED AND IGNORED, for one release. The seed merge is part of every refresh now
    # (step 5), so a saved command line does not become a fatal "unknown argument".
    --refresh-seeds) REFRESH_SEEDS=1 ;;
    # `objectives/` is the OPTIONAL layer (SCHEMA.md -> type: Objective), so the seed
    # ships none and this flag is how a bundle that wants one asks for it.
    --with-objectives) WITH_OBJECTIVES=1 ;;
    # APPLY the config findings step 4d reports, instead of only printing them. Off by
    # default for the same reason --refresh-seeds is: this one rewrites a TRACKED file.
    --normalise-config) NORMALISE_CONFIG=1 ;;
    --config|--instance)
      # Mutually exclusive, and said so rather than letting the last flag win: the two
      # write to completely different places, so a run that meant one and did the other
      # is not something to guess at.
      if [ -n "$LAYER_FLAG" ] && [ "$LAYER_FLAG" != "$arg" ]; then
        echo "error: --config and --instance are mutually exclusive" >&2; exit 2
      fi
      LAYER_FLAG="$arg"; LAYER="${arg#--}" ;;
    --help|-h)
      # Range must cover the whole header block above (through the "Backs up…"
      # line) — extend it when you add lines there, or --help truncates silently.
      # tests/config-layer.test.sh asserts the flags appear in the output, which is
      # what notices a stale range instead of leaving --help quietly truncated.
      sed -n '3,74p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --owner|--email|--repos-root|--org|--name)
      [ "$#" -ge 2 ] || { echo "error: $arg needs a value" >&2; exit 2; }
      case "$arg" in
        --owner)      ID_OWNER_FLAG="$2" ;;
        --email)      ID_EMAIL_FLAG="$2" ;;
        --repos-root) ID_REPOS_FLAG="$2" ;;
        --org)        ORG_FLAG="$2" ;;
        --name)       ORG_NAME_FLAG="$2" ;;
      esac
      shift ;;
    --owner=*)      ID_OWNER_FLAG="${arg#*=}" ;;
    --email=*)      ID_EMAIL_FLAG="${arg#*=}" ;;
    --repos-root=*) ID_REPOS_FLAG="${arg#*=}" ;;
    --org=*)        ORG_FLAG="${arg#*=}" ;;
    --name=*)       ORG_NAME_FLAG="${arg#*=}" ;;
    -*) echo "error: unknown flag '$arg'" >&2; exit 2 ;;
    *)
      [ -z "$TARGET" ] || { echo "error: multiple target directories given" >&2; exit 2; }
      TARGET="$arg" ;;
  esac
  shift
done
if [ "$LAYER" = "config" ] && [ -n "$TARGET" ]; then
  echo "error: --config takes no target directory (it links into" >&2
  echo "       \${CLAUDE_CONFIG_DIR:-\$HOME/.claude}); got '$TARGET'" >&2
  exit 2
fi
if [ "$LAYER" = "config" ] && [ -n "$ORG_FLAG$ORG_NAME_FLAG" ]; then
  echo "error: --org/--name are about a bundle repo; they do not apply to --config" >&2
  exit 2
fi
if [ -n "$ORG_NAME_FLAG" ] && [ -z "$ORG_FLAG" ]; then
  echo "error: --name needs --org (the repo is <org>/<name>)" >&2
  exit 2
fi
if [ "$MODE" = "uninstall" ] && [ -n "$ORG_FLAG" ]; then
  echo "error: --org creates or clones a bundle; it does not apply to --uninstall" >&2
  exit 2
fi

# Refuse to run the CONFIG LAYER from a git WORKTREE — and ONLY the config layer.
#
# The guard used to cover both halves, because BUNDLE mode created symlinks pointing at
# this checkout too: an instance's whole machinery set, every one of them dangling the
# moment `git worktree remove` ran. Bundle mode creates no such link any more (the whole
# point of this file's rewrite), so the refusal that made a role agent's worktree unable
# to stamp a fixture is gone with the hazard that justified it.
#
# `--config` still writes absolute symlinks into ${CLAUDE_CONFIG_DIR:-~/.claude} that
# point AT this source directory, so for that layer the hazard is unchanged and so is the
# refusal. (`ai-setup`'s own installer carries the same guard.)
#
# The test is `--git-dir` vs `--git-common-dir`: equal in the main working tree, different
# in a linked one (the former becomes <main>/.git/worktrees/<name>). Both are asked for in
# absolute form, because one side is otherwise relative and the comparison would always
# differ. A plain `git init` repo — what the test fixtures build — is a MAIN tree, so this
# never fires there; outside git entirely it cannot fire at all.
#
# The message deliberately does NOT compute the main checkout's path. Both obvious
# derivations are wrong once the git metadata lives apart from the working tree
# (`git init --separate-git-dir`, or a `.git` file pointing elsewhere): `dirname` of the
# common dir yields the metadata's parent, and even `git worktree list` reports the git
# dir rather than the main tree in that setup — measured both. Printing a confidently
# wrong path to paste is worse than printing none, so it names the command that always
# knows instead of guessing. Don't "improve" this by deriving it.
if [ "$LAYER" = "config" ] && [ -n "$TEMPLATE_DIR" ] && command -v git >/dev/null 2>&1; then
  _gd="$(git -C "$TEMPLATE_DIR" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _gc="$(git -C "$TEMPLATE_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_gd" ] && [ -n "$_gc" ] && [ "$_gd" != "$_gc" ]; then
    cat >&2 <<GUARDEOF
error: refusing to link the config layer from a git worktree.

  source:      $TEMPLATE_DIR
  git dir:     $_gd

Every symlink this creates would point into the worktree, and deleting the worktree
(ExitWorktree, or git worktree remove) would silently break all of them — nothing
fails now, the agents just disappear later.

Run it from the repository's MAIN working tree instead. To find it:
  git -C $TEMPLATE_DIR worktree list      # the first entry is the main tree
GUARDEOF
    exit 2
  fi
fi

# ===========================================================================
# CONFIG LAYER (--config) — link config/ into the Claude Code config dir.
# ===========================================================================
#
# WHY IT IS HERE AT ALL. loopd used to depend on a *separate* config repo for four
# things, and all four failed SILENTLY: the `@~/.claude/claude-defaults.md` import every
# instance inherited from seed/CLAUDE.md (now inlined there, so nothing can dangle), and
# three probed-for agents — `code-architect`, `deep-bug-scan`, `plan-architect`. A fresh
# laptop is now one clone and one install.
#
# AND WHY IT IS NOW ONLY THREE FILES. Closing those four dependencies by forking the
# whole of `cbmono/ai-setup`'s `.claude/` tree bought a second problem: two installers
# claiming `${CLAUDE_CONFIG_DIR:-~/.claude}`, 24 entries shipped by both, 14 diverged, and
# ownership decided by whichever ran last. ai-setup owns that directory now. This layer
# keeps exactly the paths loopd itself PROBES for and nothing else — the smallest set
# that makes a fresh laptop work without cloning another repo. Re-adding anything here
# re-creates the collision; `tests/config-ownership.test.sh` fails if you do.
# Full reasoning: docs/claude-config-ownership.md.
#
# THE ARROW IS ONE-WAY. The plugin must never *require* `config/`. The role agents keep
# probing with `test -f`, so an instance stamped on a machine that never ran `--config`
# works — it loses a second opinion, not a feature. `tests/config-layer.test.sh` asserts
# a config-less stamp. `rm -rf config/required` must leave `--config` at exit 0 with
# nothing linked; `rm -rf config` must leave an INSTANCE stamp completely unaffected.
#
# EVERY LINK IS PER FILE, NEVER PER DIRECTORY. agents/, commands/, hooks/, scripts/ and
# skills/ are DROP-IN directories — a skill or plugin installer can write a new
# subdirectory into ~/.claude/skills at any moment. Linking such a directory as a unit
# aims it at this repo's working tree, so every drop-in lands INSIDE a public git repo.
# That is not hypothetical: it is how four uninvited skills got committed to the parent
# repo on 2026-08-22, three of them dangling symlinks its installer would then have
# pushed into every consumer's ~/.claude. Per-file linking leaves ~/.claude/<dir> a real
# directory that owns its own contents, so a drop-in can never reach this checkout and
# no .gitignore allow-list is needed to keep it out. Do not "simplify" this to whole-dir
# links — `tests/config-layer.test.sh` asserts a fresh drop-in stays outside the repo.
# EMPTY WHEN THERE IS NO CHECKOUT, never `/config`: an unguarded expansion would turn the
# absence of the repo into a probe of the filesystem root. `config_require_src` refuses on
# it by name, so `--config` from an installed plugin says what to clone instead of
# reporting that some directory it never named is missing.
CONFIG_SRC=""
if [ -n "$TEMPLATE_DIR" ]; then CONFIG_SRC="$TEMPLATE_DIR/config"; fi
CONFIG_TIERS="required"
# Honour CLAUDE_CONFIG_DIR: when it is set, Claude Code reads settings, agents and hooks
# from there instead of ~/.claude, so installing into $HOME would put the layer somewhere
# nothing loads it from. It is the same expression ai-setup's settings.json uses to
# reference its hooks, so the two installers cannot disagree about where the config dir is.
CONFIG_DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Every linkable file, as "<tier><TAB><relative path>".
#
# Three kinds of file are never linked, at any depth: `README.md` (a repo doc — and in
# commands/ Claude Code would register it as the command `/README`), `*.example.json`
# (copy-from templates: a linked one is clutter that dangles if this checkout moves), and
# `settings.json`. This layer no longer ships a settings.json at all — it is ai-setup's,
# and it is the one file that can already hold permissions and plugins a human tuned by
# hand, so a second installer must never touch it. The exclusion stays because it is
# cheap and because a settings.json appearing under `config/` would otherwise be linked
# silently; a stale link from when this layer DID ship one is retired by config_sweep.
#
# ITS STATUS CANNOT TRAVEL OUT OF HERE, and that is a property of the interface, not an
# oversight left to fix later. Its stdout IS the payload, every caller consumes it as
# `$(config_entries)` inside a here-doc, and the `cd`/`find` statuses vanish into a
# pipeline whose status is `sort`'s. So no caller can ask "did discovery succeed?" — which
# is why the destructive consumer does not ask. `config_src_probe` names the cause once
# per run, and `config_sweep`'s refusal is stated over the RESULT instead. See both.
config_entries() {
  local tier
  for tier in $CONFIG_TIERS; do
    [ -d "$CONFIG_SRC/$tier" ] || continue
    ( cd "$CONFIG_SRC/$tier" && find . -type f -print ) | sed 's#^\./##' | sort \
    | while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        # Parameter expansion, not basename: this scan runs a few times per invocation
        # and one fork per file per pass is a measurable cost on a loaded machine.
        case "${rel##*/}" in
          README.md|settings.json|*.example.json|.DS_Store) continue ;;
        esac
        printf '%s\t%s\n' "$tier" "$rel"
      done
  done
}

# Can this run LOOK at its own source tree? Named per directory, once per run, before
# anything is counted — the mirror of the probe config_sweep runs over the DESTINATION,
# and for the same reason: "nothing is shipped" and "I could not read the shipment" must
# never print the same thing.
#
# This is the cheap half of the repair, not the fix. It reports the CAUSE where the cause
# is a permission on a directory, which is every mode measured — but it is a cause-based
# check, so it can only ever cover the causes someone thought of. The guard that does not
# depend on that is in config_sweep, stated over the result.
CONFIG_SRC_FAIL=0
config_src_probe() {
  local tier d
  CONFIG_SRC_FAIL=0
  for tier in $CONFIG_TIERS; do
    [ -d "$CONFIG_SRC/$tier" ] || continue
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      { [ -r "$d" ] && [ -x "$d" ]; } && continue
      echo "  fail  ${d#"$TEMPLATE_DIR"/} — cannot list this source directory; the files" >&2
      echo "        under it were NOT discovered, so nothing here can act on their absence." >&2
      CONFIG_SRC_FAIL=$((CONFIG_SRC_FAIL+1))
    done <<EOF
$( printf '%s\n' "$CONFIG_SRC/$tier"
   find "$CONFIG_SRC/$tier" -type d -print 2>/dev/null || true )
EOF
    # `find`'s own status, kept rather than discarded — the backstop for a traversal that
    # fails some way a per-directory probe cannot predict. Reported only when the probe
    # found nothing, so one cause is never counted twice.
    if [ "$CONFIG_SRC_FAIL" -eq 0 ] \
       && ! find "$CONFIG_SRC/$tier" -type f -print >/dev/null 2>&1; then
      echo "  fail  config/$tier — could not be traversed; its file list is INCOMPLETE." >&2
      CONFIG_SRC_FAIL=$((CONFIG_SRC_FAIL+1))
    fi
  done
  [ "$CONFIG_SRC_FAIL" -eq 0 ]
}

# What the source probe could not do, said out loud. Separate from config_sweep_warn
# because the two failures have opposite remedies: that one asks you to fix the CONFIG
# DIR, this one asks you to fix the CHECKOUT.
config_src_warn() {
  [ "$CONFIG_SRC_FAIL" -gt 0 ] || return 0
  echo "warn  $CONFIG_SRC_FAIL source directory/ies could not be listed (named above), so the" >&2
  echo "      set of files this layer ships was discovered INCOMPLETE. Nothing was retired" >&2
  echo "      on the strength of it. Make $CONFIG_SRC readable and listable (r-x)," >&2
  echo "      then re-run." >&2
  return 1
}

# Top-level entries the config layer manages — the roots of the dangling-link sweep.
# Roots to sweep for retired links. Deliberately NOT just the roots present in the
# current source tree: if the last file under `config/required/commands/` is removed,
# that root disappears from `config_entries`, the sweep stops searching
# `$CONFIG_DEST/commands`, and its dangling links stay registered — a retired command that
# still shows up, or a retired hook that exits 127 on every startup. The whole point of the
# sweep is the case where a source file is GONE, so it cannot be driven by what remains.
#
# The fixed list is the set this installer has ever managed. Add to it when a new root
# ships; never prune it, for the same reason RETIRED is never pruned — an install from
# years ago still has the directory.
# It is ALSO what performs the handover to ai-setup: this layer used to ship commands/,
# hooks/, output-styles/, scripts/, skills/, MEMORY.md and settings.json, so the roots
# stay listed and `--config` retires those now-dangling links on the next run. Pruning
# them would strand a retired command that still registers and a retired hook that exits
# 127 on every launch.
CONFIG_MANAGED_TOPS="agents commands hooks output-styles scripts skills rules claude-defaults.md MEMORY.md settings.json"
config_tops() { { config_entries | cut -f2 | sed 's#/.*##'; printf '%s\n' $CONFIG_MANAGED_TOPS; } | sort -u; }

# Print the first DIRECTORY component of $1 that is a symlink under the config dir.
#
# This guard is what keeps the per-file fix honest. A whole-directory symlink left over
# from another setup turns "$CONFIG_DEST/agents/x.md" into a write INSIDE that other
# checkout — modifying a repo nobody asked us to touch, silently, and leaving the config
# dir with no file of its own. So this layer NEVER writes through one.
#
# It is not hypothetical and it is not rare: ai-setup — which owns this directory — links
# `~/.claude/agents` as a whole directory. So on any machine that ran its installer, every
# entry here has a symlinked parent, by design rather than by accident. That is why
# "refuse" is no longer the only answer; see config_install.
config_link_parent() {
  local rel="$1" dir cur part
  case "$rel" in */*) dir="${rel%/*}" ;; *) return 1 ;; esac
  cur="$CONFIG_DEST"
  local IFS=/
  for part in $dir; do
    cur="$cur/$part"
    if [ -L "$cur" ]; then printf '%s' "$cur"; return 0; fi
  done
  return 1
}

# Is a `.bak.<epoch>` entry a superseded copy of a link this run has just recreated?
#
# WHY IT IS NEEDED. Both halves of this installer move a conflicting entry aside as
# `<name>.bak.<epoch>` before linking. When the conflict was itself a symlink of OURS
# pointing into a template that has MOVED, the backup is a dangling symlink whose entire
# content is the old, wrong path — and neither retire sweep can remove it, because
# `ours`/`config_ours` test the target against the template's CURRENT location and a moved
# link fails that test by construction. Measured: one plain `mv` of the checkout followed
# by one repair install left 38 dead `.bak.*` links in a single fixture instance, and the
# real move left 122 across two. Each one is noise that makes the next dangling-link
# report unreadable, which is how this class of failure stays invisible.
#
# THE THREE CONDITIONS ARE THE WHOLE SAFETY PROPERTY, and the middle one most of all:
#   · the NAME is one this installer writes — `.bak.<digits>` — and nothing else;
#   · it is a dangling SYMLINK, never a regular file. A `.bak.*` FILE is a human's own
#     content that this installer moved aside, and deleting that would spend the property
#     the whole script rests on. A dangling symlink holds no content at all, only a path
#     string — which is printed as it goes rather than dropped;
#   · the entry it backs up EXISTS AGAIN as a link of ours, i.e. this run has already
#     recreated the thing the backup is a copy of. That is what makes it *superseded*
#     rather than merely dead, and it is why an uninstall — which removes the link instead
#     of recreating it — sweeps nothing and leaves every backup where it is.
#
# Takes the ownership predicate as an argument so the instance and config halves share one
# rule: the debris is identical because the backup path that creates it is.
dead_backup() { # <ownership-predicate> <relative path> <absolute path>
  case "$2" in *.bak.[0-9]*) ;; *) return 1 ;; esac
  # The glob above only requires the FIRST character after ".bak." to be a digit, so
  # "SCHEMA.md.bak.1700000000.manual" — not this installer's format at all — would
  # otherwise pass. Require the WHOLE suffix after the last ".bak." to be digits only;
  # anything else (letters, punctuation, a further extension, or nothing) is somebody
  # else's name, not ours to remove.
  case "${2##*.bak.}" in ''|*[!0-9]*) return 1 ;; esac
  [ -L "$3" ] && [ ! -e "$3" ] || return 1
  "$1" "${2%.bak.*}"
}

# True only when CONFIG_DEST/$1 is a symlink we created (points into this checkout's
# config/), decided by the target rather than by name — the same `ours` test the instance
# half uses, and the reason an uninstall can never remove somebody else's link.
config_ours() {
  local dst="$CONFIG_DEST/$1"
  [ -L "$dst" ] || return 1
  case "$(readlink "$dst")" in "$CONFIG_SRC"/*) return 0 ;; esac
  return 1
}

# Remove links into this checkout's config/ whose target is gone.
#
# Same reasoning as the instance half's step 2b, and the same narrowness: the link must
# point INTO $CONFIG_SRC *and* its target must be missing. A dangling entry is worse than
# an absent one — Claude Code registers a command whose file has vanished, and a hook
# whose script is gone exits 127 on every launch — so retiring a config file has to sweep
# too. Scoped to the entries this layer manages, never the whole config dir: ~/.claude
# also holds plugins/, projects/ and sessions/, none of it ours to walk.
#
# THE ROOT LIST IS AN ARRAY, AND THAT IS LOAD-BEARING. It used to be a space-separated
# string expanded as `find $roots`, with a `# shellcheck disable=SC2086` above it so lint
# could not object. `CLAUDE_CONFIG_DIR` is a path a human chooses — `~/Library/Application
# Support/claude` is an ordinary thing to pick — and one space in it split every root into
# fragments that exist nowhere. `find` then printed its errors to the /dev/null this
# function already redirects, returned non-zero into the `|| true`, and the sweep reported
# NOTHING while exiting 0. Measured on the handover fixture: 21 retired / 0 dangling
# without a space in the path, 2 retired / 19 dangling with one — the two survivors being
# the top-level entries, whose `find` was already quoted. Everything under `commands/`,
# `hooks/`, `scripts/`, `output-styles/` and `agents/` stayed registered and dangling,
# which is precisely the "retired command still shows up, retired hook exits 127" failure
# the comment above describes. Pinned by a fixture whose config dir has a space in it.
#
# THE ROOTS INCLUDE WHAT ai-setup MOVED ASIDE, and this one needs no unusual permissions at
# all — it is the order this repo recommends. ai-setup links each top-level entry as a whole
# unit, renaming the real directory to `<root>.bak.<epoch>` first. After it runs,
# `$CONFIG_DEST/commands` is a SYMLINK, so the `[ ! -L … ]` test below drops it, and the 11
# links this layer must retire sit in `commands.bak.<epoch>/` — a directory, so the
# top-level `-maxdepth 1` scan does not see them either. Measured on the real in-place
# upgrade in the recommended order: `--config` retired **2 of 21** and reported "Those 2
# path(s) … they moved", leaving 19 dangling, un-retired and unreported; `--config
# --uninstall` exited **0** with three links STILL LIVE into the checkout the user had just
# detached from. The same failure as the unquoted `find $roots`, reached by a third route.
# So a moved-aside copy of a managed root is itself a sweep root — restricted to
# `.bak.<digits>`, the name both installers write, and to real directories, because a `.bak`
# FILE is a human's own content that an installer moved and never ours to walk into.
#
# `find` CANNOT ANSWER "NOTHING TO RETIRE" WHEN IT COULD NOT LOOK, and both calls used to
# end `2>/dev/null || true`, discarding precisely that distinction. A config dir whose
# `commands/` is mode 0300 — writable but not readable, which is what a `chmod` typo or an
# odd umask leaves behind — measured **exit 0, 11 `retire` lines, "Those 11 path(s) … they
# moved", 0 fail, 0 warn, and ten dangling commands still registered**: the identical
# failure the checked `rm` below was added for, in the DISCOVERY half rather than the
# REMOVAL half. Unreadable is the worse of the two because it is silent — mode 500 at least
# made `rm` fail. So every directory the sweep must list is probed first and NAMED if it
# cannot be listed, and `find`'s own status is kept as a backstop for whatever a probe
# cannot predict.
#
# THE LOOP RUNS IN THIS SHELL, not down a pipe, so $CONFIG_RETIRED survives it. The count
# is what lets the caller point at cbmono/ai-setup: a user whose 19 links just vanished is
# owed the name of the repo that ships them now.
#
# EVERY `rm` HERE IS CHECKED, and $CONFIG_SWEEP_FAIL is why. The same defect that made
# `config_install` print "3 linked" having linked nothing lived in this function for one
# more round: `rm -f` ran unchecked while the counter and the `retire` line ran regardless,
# and errexit is suspended for the whole call by `config_install || config_rc=$?`. A config
# dir whose `commands/` is not writable — mode 500, or root-owned after a `sudo` install —
# measured **21 `retire` lines and "Those 21 path(s) … moved" for 11 actual removals, exit
# 0, ten dangling commands still registered**, and on `--uninstall` three links still LIVE
# into the checkout the user had just detached from. The only signal was `rm:` on stderr,
# under a success epilogue. This function IS the handover for ~21 paths, so a count printed
# regardless of what it did is the worst possible thing for it to print: the user is told
# the migration completed and given a repo to re-install from, while a dangling command
# stays registered. The counter now moves only after the write succeeded, and the caller
# turns any failure into a non-zero exit through config_sweep_warn.
CONFIG_RETIRED=0
CONFIG_DETACHED=0
CONFIG_SWEEP_FAIL=0
# Absolute paths the CALLER's own loop owns and has already reported on, newline-delimited
# and newline-terminated. Only `detach` mode reads it, and only so one unremovable link is
# not counted and named twice — once by config_uninstall's entries loop and once here.
CONFIG_SWEEP_SKIP=""
config_sweep() { # [retire|detach]
  local mode="${1:-retire}" t b d l rel was n_roots=0 blind=0 find_rc=0 scan="" part="" sorted=""
  local roots=()
  CONFIG_RETIRED=0
  CONFIG_DETACHED=0
  CONFIG_SWEEP_FAIL=0
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if [ -d "$CONFIG_DEST/$t" ] && [ ! -L "$CONFIG_DEST/$t" ]; then
      roots+=("$CONFIG_DEST/$t"); n_roots=$((n_roots+1))
    fi
    # …and the copy another installer moved aside, which is where this layer's links go when
    # ai-setup takes the root over. An unmatched glob stays literal, and `-d` rejects it.
    for b in "$CONFIG_DEST/$t".bak.*; do
      [ -d "$b" ] && [ ! -L "$b" ] || continue
      case "${b##*.bak.}" in ''|*[!0-9]*) continue ;; esac
      roots+=("$b"); n_roots=$((n_roots+1))
    done
  done <<EOF
$(config_tops)
EOF
  # CAN WE LOOK? Probed per directory so the answer names the path, and before anything is
  # counted, because "0 to retire" and "could not read the directory" must never print the
  # same. `find` lists an unreadable directory (its parent supplies the name) and only fails
  # to descend, so this sees the one it is about to be blind inside.
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    { [ -r "$d" ] && [ -x "$d" ]; } && continue
    case "$d" in
      "$CONFIG_DEST") rel="." ;;
      *) rel="${d#"$CONFIG_DEST"/}" ;;
    esac
    echo "  fail   $rel — cannot list this directory; links under it were NOT examined" >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); blind=$((blind+1))
  done <<EOF
$( printf '%s\n' "$CONFIG_DEST"
   if [ "$n_roots" -gt 0 ]; then find "${roots[@]}" -type d -print 2>/dev/null || true; fi )
EOF
  # The status of each `find`, kept rather than discarded into `|| true`. The probe above is
  # more precise when it fires; this is the backstop for a traversal that fails some other
  # way, and it reports only when the probe found nothing, so one cause is not counted twice.
  if ! part="$(find "$CONFIG_DEST" -maxdepth 1 -type l -print 2>/dev/null)"; then find_rc=1; fi
  scan="$part"
  if [ "$n_roots" -gt 0 ]; then
    if ! part="$(find "${roots[@]}" -type l -print 2>/dev/null)"; then find_rc=1; fi
    scan="$scan
$part"
  fi
  if [ "$find_rc" -ne 0 ] && [ "$blind" -eq 0 ]; then
    echo "  fail   . — could not fully traverse $CONFIG_DEST; this sweep is INCOMPLETE" >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
  fi

  # AN EMPTY SOURCE SET IS NOT A LICENCE TO DELETE, and this is the guard that says so.
  #
  # `config_sweep` decides what to retire by asking "is this link's target still in the
  # source set?". An empty source set therefore does not mean "the source is gone, retire
  # everything" — it can equally mean "I could not look", and until this guard existed the
  # function took the destructive reading of both. Measured on a real in-place upgrade,
  # three ways — `config/required` at 0400, `config/required/agents` at 0000, and
  # `config/required/agents` at 0400 — each identical: exit 0, a `retire` line for every
  # link including the three this layer still ships, ZERO left, and no warning. The 0400
  # subdirectory case produced no stderr at all. `retire` is a success word printed for a
  # data loss.
  #
  # WHY THIS IS NOT A STATUS CHECK. `find . -type f` in a directory that is unreadable but
  # executable exits 0 and prints nothing. There is no error to propagate, so `pipefail`,
  # keeping `find`'s status, or checking the subshell would every one of them pass cleanly
  # on the exact input that empties the layer. config_src_probe above catches the causes we
  # know; this catches the consequence, whatever caused it.
  #
  # WHAT IT ASSERTS, over two sets rather than over an exit code:
  #     discovery returned NO entries, while links into $CONFIG_SRC still exist
  #     => a refusal, not a retirement.
  # The one state where an empty source set really does mean "nothing is shipped" is a
  # tier directory that is GONE — `rm -rf config/required`, the AUTONOMY.md contract this
  # file documents, where retiring those links is exactly right. So a tier that is still
  # PRESENT and yielded nothing is the discriminator, and it is checked here rather than
  # inferred from a status. A tier deliberately emptied but left in place lands on the
  # refusing side: it is the rarer intent, the message says how to express it, and being
  # wrong in that direction costs a re-run instead of a layer.
  #
  # TWO REFUSALS, AND NEITHER SUBSUMES THE OTHER. The probe's fires on an INCOMPLETE list
  # even when it is non-empty — one unreadable subdirectory among several readable ones
  # still yields files, so the set-emptiness test below is structurally blind to it while
  # the links under that directory read as dangling and get retired. The set test fires on
  # an EMPTY list whatever the cause, including causes no probe was written for. Each
  # covers the other's blind spot; both are pinned by mutation in config-layer.test.sh.
  # It is also what makes config_src_warn's "nothing was retired on the strength of it"
  # true rather than merely likely — a warning that overstates is the same defect again.
  #
  # RETIRE MODE ONLY, both of them. On `--uninstall` the removals are what the user asked
  # for, not an inference from the source set, so a blind read must not stop them.
  if [ "$mode" != detach ] && [ "${CONFIG_SRC_FAIL:-0}" -gt 0 ]; then
    echo "  fail   . — REFUSING to retire: the source list is INCOMPLETE (the directory it" >&2
    echo "         could not read is named above). This sweep retires whatever is MISSING" >&2
    echo "         from that list, so acting on it would retire files that are present and" >&2
    echo "         merely unlisted. Nothing was retired." >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
    return 0
  fi
  if [ "$mode" != detach ]; then
    local n_src=0 n_ours=0 tier src_present=0
    for tier in $CONFIG_TIERS; do
      [ -d "$CONFIG_SRC/$tier" ] && src_present=1
    done
    while IFS= read -r l; do [ -n "$l" ] && n_src=$((n_src+1)); done <<EOF
$(config_entries)
EOF
    if [ "$n_src" -eq 0 ] && [ "$src_present" -eq 1 ]; then
      while IFS= read -r l; do
        [ -n "$l" ] || continue
        case "$(readlink "$l")" in "$CONFIG_SRC"/*) n_ours=$((n_ours+1)) ;; esac
      done <<EOF
$scan
EOF
      if [ "$n_ours" -gt 0 ]; then
        echo "  fail   . — REFUSING to retire: this run discovered no files under" >&2
        echo "         $CONFIG_SRC, yet $n_ours link(s) here still point into it." >&2
        echo "         A source directory that exists and lists nothing is 'I could not" >&2
        echo "         look', not 'nothing is shipped', and only the second one licenses a" >&2
        echo "         delete. Nothing was retired. Make $CONFIG_SRC" >&2
        echo "         readable and listable (r-x) and re-run; if you really meant to drop" >&2
        echo "         the layer, remove the tier directory or run --config --uninstall." >&2
        CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
        return 0
      fi
    fi
  fi

  # De-duplicated into a variable first, so `sort`'s status is looked at rather than
  # discarded into the here-doc that consumes it. A failed `sort` leaves `$sorted` empty
  # and the loop below therefore removes nothing, which is the safe direction — but it
  # used to do that silently, and silence is the whole defect class this function keeps
  # meeting. Cheap and correct; it is not the guard above, which does not need a status.
  if ! sorted="$(printf '%s\n' "$scan" | sort -u)"; then
    echo "  fail   . — could not de-duplicate the link scan; this sweep is INCOMPLETE" >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
    sorted=""
  fi
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    rel="${l#"$CONFIG_DEST"/}"
    case "$(readlink "$l")" in
      "$CONFIG_SRC"/*)
        if [ ! -e "$l" ]; then
          if ! rm -f "$l" 2>/dev/null; then
            echo "  fail   $rel — cannot retire this dangling link" >&2
            CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); continue
          fi
          CONFIG_RETIRED=$((CONFIG_RETIRED+1))
          echo "  retire $rel (no longer shipped by the config layer)"
          continue
        fi
        # LIVE, and ours. On an install that is nothing to act on — it is a link to a file
        # this layer still ships. On an UNINSTALL it is the opposite: a link still pointing
        # into the checkout the user is detaching from. config_uninstall's own loop walks
        # `config_entries`, i.e. paths spelled as they are shipped, so it cannot see one
        # stranded inside a `<root>.bak.<epoch>` directory that ai-setup moved aside — which
        # is exactly where the three that survived the measured uninstall were.
        [ "$mode" = detach ] || continue
        case "$CONFIG_SWEEP_SKIP" in
          *"
$l
"*) continue ;;
        esac
        if ! rm -f "$l" 2>/dev/null; then
          echo "  fail   $rel — cannot remove this link; it is STILL pointing into this checkout" >&2
          CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); continue
        fi
        CONFIG_DETACHED=$((CONFIG_DETACHED+1))
        echo "  detach $rel (was still linked into this checkout)"
        continue ;;
    esac
    # Not ours by target, so the branch above cannot see it — but it may be OUR OWN dead
    # backup of a link we relinked a moment ago. See dead_backup() for why that is the one
    # thing safe to delete here. The config layer accumulates this debris exactly as the
    # instance half does: 24 links dangled in ~/.claude when the checkout moved.
    if dead_backup config_ours "$rel" "$l"; then
      was="$(readlink "$l")"
      if ! rm -f "$l" 2>/dev/null; then
        echo "  fail   $rel — cannot remove this dead backup (was -> $was)" >&2
        CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); continue
      fi
      echo "  sweep  $rel (dead backup of a relinked file, was -> $was)"
    fi
  done <<EOF
$sorted
EOF
}

# Where the paths this layer just retired went. Printed only when something WAS retired, so
# a steady-state run stays quiet. Without it the handover tells a user what vanished and
# not where it went: on the machine this split was measured on, one `--config` run retired
# 19 live links and named `cbmono/ai-setup` zero times in anything it printed.
config_handover_note() {
  [ "$CONFIG_RETIRED" -gt 0 ] || return 0
  echo "      Those $CONFIG_RETIRED path(s) are not gone from your setup — they moved."
  echo "      cbmono/ai-setup owns $CONFIG_DEST now and installs them: clone it and run"
  echo "      its install.sh to get them back. Why, and what not to re-add here:"
  echo "        docs/claude-config-ownership.md"
}

# What the sweep could NOT do, said out loud, and non-zero so a script can see it.
#
# Called by both halves — `config_install` and `config_uninstall` share the sweep, and the
# earlier fix for this defect class landed on `config_install`'s own writes only, leaving
# its sibling to report a full retirement it had not performed. A partial handover is worse
# than a refused one: the paths that survived are dangling links Claude Code still
# registers, and the epilogue has already pointed the user at another repo to install from.
# It counts what the sweep could not LOOK AT as well as what it could not remove, because a
# directory it cannot list is not "nothing to retire" — that was blocker B3, measured as
# exit 0 with ten dangling commands still registered.
config_sweep_warn() {
  [ "$CONFIG_SWEEP_FAIL" -gt 0 ] || return 0
  echo "warn  $CONFIG_SWEEP_FAIL path(s) the sweep could not finish (named above). A link it" >&2
  echo "      could not remove is still registered and still dangling, and a directory it" >&2
  echo "      could not list may hold more. The counts above exclude them. Make" >&2
  echo "      $CONFIG_DEST and its subdirectories readable and writable, then re-run." >&2
  return 1
}

config_require_src() {
  # THE ONE THING AN INSTALLED PLUGIN CANNOT DO, and it says so by name rather than by
  # reporting a missing directory. `config/` deliberately does not ship in the plugin: it
  # links files into ~/.claude, which is a per-machine decision and not a bundle one, and
  # `plugin/` must never *require* `config/` (CLAUDE.md, docs/claude-config-ownership.md).
  # A bundle stamp never needs this layer — only `--config` does.
  if [ -z "$CONFIG_SRC" ]; then
    echo "error: --config needs a checkout of this repo, and this is an installed plugin." >&2
    echo "       config/ is not shipped in the plugin: it links three agent files into" >&2
    echo "       \${CLAUDE_CONFIG_DIR:-~/.claude}, which is a machine decision, not a bundle one." >&2
    ab_say_run "       git clone https://github.com/cbmono/loopd &&" loopd/plugin/scripts/init-bundle.sh --config >&2
    echo "       Bundle stamps (init-bundle.sh [TARGET]) need none of this." >&2
    exit 2
  fi
  if [ ! -d "$CONFIG_SRC" ]; then
    echo "error: this checkout has no config layer ($CONFIG_SRC)." >&2
    echo "       Nothing to link. A bundle stamp (init-bundle.sh [TARGET]) never needs it." >&2
    exit 2
  fi
  if [ -L "$CONFIG_DEST" ]; then
    echo "error: $CONFIG_DEST is itself a symlink ($(readlink "$CONFIG_DEST"))." >&2
    echo "       This expects a real directory that owns your runtime state (plugins/," >&2
    echo "       projects/, history). Replace the symlink with a real directory first." >&2
    exit 2
  fi
}

config_install() {
  local tier rel src dst dstdir bak off tgt n_link=0 n_ok=0 n_moved=0 n_refused=0 n_else=0 n_fail=0 reported=" "
  config_require_src
  # BEFORE the link loop and before the sweep, so a source tree this run cannot read is
  # named while the run still has everything it needs to name it — and so the two writes
  # that follow are already known to be acting on a partial list.
  config_src_probe || true

  # NO two-tier duplicate refusal any more. It guarded the case where `required` and
  # `opinionated` both declared one path — whichever ran second would move the first aside
  # as a .bak and shadow it. There is one tier now, so the check could not fire, and an
  # unreachable guard is one no test can cover. What replaced it is stronger and does fire:
  # `tests/config-ownership.test.sh` derives the whole shippable set from the `test -f`
  # probes in the plugin, so a second tier cannot appear here unnoticed in the first place.
  # The LAST unchecked write in this half, and it is checked for the reason blocker A
  # existed: fixing the writes one loop noticed and leaving the sibling it did not is how a
  # false success survives a round of review. Its failure is currently reported per file by
  # the `mkdir -p "$dstdir"` guard below, but only because every shipped entry happens to
  # live in a subdirectory — an incidental guarantee, not a stated one. A config dir that
  # cannot be created is a refusal, not a run with nothing to do.
  if ! mkdir -p "$CONFIG_DEST" 2>/dev/null; then
    echo "error: cannot create $CONFIG_DEST." >&2
    echo "       Nothing was written. Check the permissions on its parent directory." >&2
    return 1
  fi
  echo "Linking the loopd config layer into $CONFIG_DEST"
  while IFS=$'\t' read -r tier rel; do
    [ -n "$rel" ] || continue
    src="$CONFIG_SRC/$tier/$rel"; dst="$CONFIG_DEST/$rel"
    off="$(config_link_parent "$rel" || true)"
    # A symlinked parent means another config provider owns this directory. Two cases, and
    # only one of them is a problem:
    #
    #   · THE ENTRY ALREADY RESOLVES THROUGH IT. That provider ships this path — which is
    #     ai-setup, shipping the same three probed-for agents. Our contract for the
    #     required tier is that the file EXISTS on this machine, not that our copy is the
    #     one used, so the guarantee is already met: report it and write nothing. Without
    #     this, `--config` would exit non-zero on every machine that ran ai-setup's
    #     installer — the normal configuration, not an edge case — and the order the two
    #     installers ran in would change the outcome.
    #   · IT DOES NOT RESOLVE. Nobody ships it, and we cannot write it without writing
    #     into someone else's checkout. Refuse, name the directory, print the fix.
    #
    # `-f`, NOT `-e`. `-e` is true for a DIRECTORY, so a directory named `code-architect.md`
    # inside the provider's tree would count as "provided": this run would write nothing,
    # exit 0, and the `test -f ~/.claude/agents/code-architect.md` probe in
    # `plugin/agents/qa-reviewer.md` would still fail — silently, in a session. The
    # contract is "a FILE exists at this path", so the test has to be the same one the
    # consumer makes. This line is the whole content of its own commit; the fixture that
    # pins it is in `tests/config-layer.test.sh` (a directory in the provider's slot).
    if [ -n "$off" ] && [ -f "$CONFIG_DEST/$rel" ]; then
      echo "  ok    $rel (provided by $off -> $(readlink "$off"))"; n_else=$((n_else+1)); continue
    fi
    if [ -n "$off" ]; then
      n_refused=$((n_refused+1))
      case "$reported" in
        *" $off "*) ;;
        *)
          reported="$reported$off "
          # THE FIRST OPTION IS THE PROVIDER'S OWN INSTALLER, and it is printed first
          # because the `mv` used to be printed alone — actively harmful advice on the
          # normal machine. cbmono/ai-setup owns this config dir and links these roots as
          # whole directories BY DESIGN, so following a bare `mv` there deactivates every
          # agent, command and hook it ships, and its next run moves the replacement aside
          # again: the two installers ping-pong. The `mv` is right only for a link that is
          # nobody's design — some other tool's leftover — so it is offered second, and it
          # says which case it is for.
          echo "  skip  ${rel%/*}/ — $off is a symlink -> $(readlink "$off")" >&2
          echo "        Linking through it would write into that other checkout, so nothing" >&2
          echo "        was written. If that link is cbmono/ai-setup's — it owns" >&2
          echo "        $CONFIG_DEST and links these directories as units — run ITS" >&2
          echo "        install.sh; it ships this file and the requirement is then met." >&2
          echo "        Only if the link belongs to no installer, replace it with a real" >&2
          echo "        directory, keeping whatever it holds:" >&2
          echo "          mv $(printf '%q' "$off") $(printf '%q' "$off").bak.\$(date +%s) && mkdir -p $(printf '%q' "$off")" >&2
          ;;
      esac
      continue
    fi
    if [ -L "$dst" ]; then
      tgt="$(readlink "$dst")"
      if [ "$tgt" = "$src" ]; then
        echo "  ok    $rel (already linked)"; n_ok=$((n_ok+1)); continue
      fi
      # Ours, but aimed at the other tier: the file changed tier between two runs. Our
      # own link is not worth preserving, so relink rather than leave a .bak symlink
      # behind — the backup path below is for a REAL file, which is never ours to lose.
      #
      # The one `rm` here that does not report, and deliberately so: a failure FALLS
      # THROUGH to the `mv`-aside below, which is checked, names the file and counts a
      # failure — so the outcome is already reported, once, by the write that actually
      # matters. Silencing the duplicate `rm:` line is the only change; with one tier the
      # branch is unreachable anyway ($tgt can only be $src). Flagged in review as an
      # unchecked write, kept explicit here so the next reader does not have to re-derive
      # that it is the one place where falling through IS the check.
      case "$tgt" in "$CONFIG_SRC"/*) rm -f "$dst" 2>/dev/null || true ;; esac
    fi
    # EVERY WRITE IS CHECKED, and the reason is that none of them used to be. `mkdir -p`,
    # `mv` and `ln -s` all ran unchecked while the `link`/counter lines ran regardless — and
    # `set -e` cannot catch it, because the only caller is `config_install || config_rc=$?`,
    # which suspends errexit for the whole function by construction. Measured with `agents/`
    # at mode 500: three `Permission denied` on stderr, `Done. 3 linked`, exit 0, and zero
    # links created. The consumers of this layer are `test -f` probes, so a false "3 linked"
    # is invisible for the rest of the session — the role agent simply skips its fan-out.
    # A failure is now named per file, counted separately from success, and returns 1.
    dstdir="$(dirname "$dst")"
    if ! mkdir -p "$dstdir" 2>/dev/null; then
      echo "  fail  $rel — cannot create $dstdir" >&2
      n_fail=$((n_fail+1)); continue
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      bak="$dst.bak.$(date +%s)"
      if ! mv "$dst" "$bak" 2>/dev/null; then
        echo "  fail  $rel — cannot move the entry in the way aside" >&2
        n_fail=$((n_fail+1)); continue
      fi
      echo "  moved $rel -> ${bak##*/}"; n_moved=$((n_moved+1))
    fi
    if ! ln -s "$src" "$dst" 2>/dev/null; then
      echo "  fail  $rel — cannot create the symlink" >&2
      n_fail=$((n_fail+1)); continue
    fi
    echo "  link  $rel"; n_link=$((n_link+1))
  done <<EOF
$(config_entries)
EOF

  # NO settings.json BLOCK, deliberately. This layer used to link its own baseline here.
  # It is ai-setup's file now, and it is the one file in the config dir that can already
  # hold permissions and plugins a human tuned by hand — the only place where replacing a
  # value could widen what Claude is allowed to *do*. Two installers writing it is exactly
  # the collision this split removes, so loopd does not write, merge, or even report on
  # it. A link left over from when this layer DID ship one dangles the moment
  # config/opinionated/settings.json goes, and config_sweep below retires it.

  config_sweep

  echo "Done. $n_link linked, $n_ok already in place, $n_moved moved aside."
  # Counted and reported separately from "already in place": those are OUR links, these are
  # another layer's, and conflating them would hide the fact that this run wrote nothing.
  [ "$n_else" -eq 0 ] || echo "      $n_else already provided by another config layer — nothing written for those."
  config_handover_note
  # ACCUMULATED, not returned from the first branch that fires. An unwritable config dir
  # produces link failures AND sweep failures at once, and returning on the first would
  # hide the second — leaving the "still registered and still dangling" line unprinted in
  # exactly the run where it matters most.
  local rc=0
  if [ "$n_fail" -gt 0 ]; then
    echo "warn  $n_fail file(s) could not be written (above) — the config dir is not writable" >&2
    echo "      for them. Nothing here is partially applied: each failure is per file." >&2
    rc=1
  fi
  if [ "$n_refused" -gt 0 ]; then
    echo "warn  $n_refused file(s) NOT linked: a directory in the way is a symlink (above)." >&2
    echo "      Fix those directories and re-run; nothing was written through them." >&2
    rc=1
  fi
  config_sweep_warn || rc=1
  config_src_warn || rc=1
  [ "$rc" -eq 0 ] || return "$rc"
  echo "Next: restart Claude Code (/exit, then \`claude\`) so it re-scans agents and commands."
  return 0
}

config_uninstall() {
  config_require_src
  config_src_probe || true
  echo "Removing loopd config-layer symlinks from $CONFIG_DEST"
  # `rm` IS CHECKED HERE for the same reason it is in config_install: `rm` failing on an
  # unwritable directory printed "  rm  <path>" anyway, because errexit is suspended by
  # `config_uninstall || config_rc=$?` and nothing looked at the status. Measured with
  # `commands/` and `agents/` at mode 500: three `rm` lines, 21 `retire` lines, 8 removals,
  # exit 0 — and THREE LINKS STILL LIVE into the checkout the user had just detached from.
  # An uninstall that says it detached and did not is worse than one that refuses.
  local tier rel n_fail=0 handled=""
  while IFS=$'\t' read -r tier rel; do
    [ -n "$rel" ] || continue
    # Recorded whether or not the `rm` below runs, so the sweep's detach pass never counts
    # or names a path this loop already owns. Without it, an unwritable `agents/` reports
    # each of its three links twice.
    handled="$handled
$CONFIG_DEST/$rel"
    if config_ours "$rel"; then
      if rm "$CONFIG_DEST/$rel" 2>/dev/null; then
        echo "  rm    $rel"
      else
        echo "  fail  $rel — cannot remove this link; it is STILL pointing into this checkout" >&2
        n_fail=$((n_fail+1))
      fi
    fi
  done <<EOF
$(config_entries)
EOF
  # No explicit settings.json removal: this layer does not ship one, and a link left from
  # when it did is dangling — config_sweep retires it by target, along with every other
  # link into this checkout whose file is gone.
  #
  # DETACH, not just retire. The loop above walks `config_entries`, i.e. paths spelled the
  # way this layer ships them, so it cannot see a LIVE link of ours that is no longer
  # spelled that way — the three in `agents.bak.<epoch>/` after ai-setup took the root over,
  # which a measured `--config --uninstall` left resolving into the just-detached checkout
  # while exiting 0. An uninstall that reports success and did not detach is worse than one
  # that refuses, so the sweep removes live links into this checkout too on this path only.
  CONFIG_SWEEP_SKIP="$handled
"
  config_sweep detach
  CONFIG_SWEEP_SKIP=""
  # It no longer says "*.bak.* backups were left untouched" without qualification, because
  # the detach pass above removes links into THIS checkout wherever it finds them — including
  # inside a `<root>.bak.<epoch>` directory another installer moved aside, which is where the
  # three that survived a measured uninstall were. A `.bak.*` regular FILE is still never
  # touched: that is a human's content.
  echo "Done. Your runtime state and your own real files were left untouched, backups"
  echo "      included — apart from links into this checkout, which is what you asked to remove."
  [ "$CONFIG_DETACHED" -eq 0 ] || \
    echo "      $CONFIG_DETACHED further link(s) into this checkout were detached (above)."
  config_handover_note
  local rc=0
  if [ "$n_fail" -gt 0 ]; then
    echo "warn  $n_fail link(s) into this checkout could NOT be removed (named above) — this" >&2
    echo "      uninstall is INCOMPLETE and those paths still resolve into it. Make" >&2
    echo "      $CONFIG_DEST and its subdirectories writable and re-run." >&2
    rc=1
  fi
  config_sweep_warn || rc=1
  config_src_warn || rc=1
  return "$rc"
}

if [ "$LAYER" = "config" ]; then
  config_rc=0
  if [ "$MODE" = "uninstall" ]; then config_uninstall || config_rc=$?
  else config_install || config_rc=$?; fi
  exit "$config_rc"
fi

# CREATE THE DIRECTORY IF IT IS NOT THERE — the one behaviour `install.sh` did not have.
# It required the target to exist, because `mkdir && cd && install.sh .` was the documented
# first step. `/<plugin>:init <dir>` is supposed to BE that first step, so refusing an
# absent directory would leave the command unable to do the thing it is named for. Only
# the leaf is created (`mkdir -p` on the whole path), and an existing path that is not a
# directory is refused rather than replaced.
_want="${TARGET:-$PWD}"
if [ ! -e "$_want" ]; then
  mkdir -p "$_want" || { echo "error: could not create $_want" >&2; exit 2; }
elif [ ! -d "$_want" ]; then
  echo "error: $_want exists and is not a directory" >&2; exit 2
fi
TARGET="$(cd "$_want" 2>/dev/null && pwd || true)"
[ -n "$TARGET" ] || { echo "error: target directory does not exist" >&2; exit 2; }
[ -d "$SEED_SRC" ] || { echo "error: template missing $SEED_SRC" >&2; exit 2; }

# A BUNDLE STILL HOLDING ITS STATE IN THE PRE-3.3 DIRECTORY IS REFUSED BEFORE ANYTHING IS
# WRITTEN. A stamp copies a seed file only if absent, and to this plugin every file under
# $AB_DIR/ is absent in such a bundle — so it seeded a second, empty state directory beside
# the real one (three bundles, 2026-10-05), and migrate-bundle.sh then stopped because its
# destination existed. Refusing costs one command; stamping cost a hand recovery each.
if [ "$MODE" = install ] && ab_is_bundle "$TARGET" && [ -d "$TARGET/$AB_DIR_BEFORE" ]; then
  echo "error: this bundle still keeps its state in $AB_DIR_BEFORE/, and this plugin reads $AB_DIR/." >&2
  echo "       Nothing was written. Migrate it first, from the bundle root:" >&2
  ab_say_run "        " migrate-bundle.sh --layout-only >&2
  ab_say_run "        " migrate-bundle.sh --layout-only --apply >&2
  [ ! -e "$TARGET/$AB_DIR" ] || echo "       $AB_DIR/ exists too (an earlier stamp made it): move it aside first, or the migration stops." >&2
  exit 2
fi

# =========================================================================================
# 0. THE ORG'S BUNDLE (--org) — clone <org>/<name>, or create it private and push.
# =========================================================================================
#
# One organisation, one OKF knowledge bundle, and a clone of it per person. Without --org
# this whole block is skipped and a bundle is what it always was: a local folder somebody
# pushes wherever they like — which is also why nothing here is gated on a TTY the way the
# roster prompt is: the EXPLICIT flag is the consent, and upgrade.sh, a background agent
# and every other caller pass no such flag, so none of them can reach a host call.
#
# THE NAME DEFAULTS TO `<org>-okf` because the repo IS the org's Open Knowledge Format
# bundle — OKF names the whole repository the bundle, so the name says what the repo is
# rather than which tool stamped it, and it does not collide with a product repo.
#
# A 404 FROM `gh repo view` IS NOT "DOES NOT EXIST". The host answers the same 404 for a
# repo that is absent and for a private one the caller cannot yet see, so taking it as
# absence seeds a fresh bundle over the org's real one — for the second person, on their
# first command. The create path is therefore entered only after the caller's ACCESS is
# established by a second, positive probe (`gh api orgs/<org>/memberships/<me>`, or the
# org being the caller's own account). Probe unanswered ⇒ refuse and say so; the safe
# direction is "ask for access", never "seed".
#
# AND AN EXISTING REPO THAT IS NOT A BUNDLE IS REFUSED BY NAME. `<org>-okf` may already be
# somebody's unrelated repo; stamping seed docs into it is the same accident one step
# later. `instance.config.json` or `SCHEMA.md` is the marker. A repo with NO COMMITS is
# neither — it is an empty repo somebody made for this, so it is seeded and pushed like a
# fresh one.
#
# NOT BEING AN ORG ADMIN IS THE DOCUMENTED PATH, NOT A FAILURE. When `gh repo create
# <org>/<name>` is refused, the repo is created under the CALLER's account instead,
# stamped and pushed exactly as it would have been, and the `gh repo transfer` command
# that moves it to the org is printed. The stamp succeeds either way, and says which of
# the two it did.
ORG_SLUG=""      # <owner>/<name> this bundle belongs to
ORG_HOST=""      # org | user | existing — which of the three step 7 reports
ORG_REMOTE=""    # the URL step 7 pushes to
ORG_PUSH=no      # does this run owe a first commit and a push?
ORG_NAME=""

# A GitHub owner or repository name. Deliberately narrow: the value is interpolated into a
# slug, a URL and a shell word, and every name the host actually issues fits this.
org_valid_name() { # <value>
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    -*|.*) return 1 ;;
  esac
  [ "${#1}" -le 100 ]
}

if [ -n "$ORG_FLAG" ]; then
  org_valid_name "$ORG_FLAG" || { echo "error: --org '$ORG_FLAG' is not a GitHub owner name" >&2; exit 2; }
  ORG_NAME="${ORG_NAME_FLAG:-$ORG_FLAG-okf}"
  org_valid_name "$ORG_NAME" || { echo "error: --name '$ORG_NAME' is not a GitHub repo name" >&2; exit 2; }
  ORG_SLUG="$ORG_FLAG/$ORG_NAME"

  command -v gh >/dev/null 2>&1 || {
    echo "error: --org needs the GitHub CLI. Install gh, run 'gh auth login', and re-run." >&2; exit 3; }
  command -v git >/dev/null 2>&1 || { echo "error: --org needs git." >&2; exit 3; }
  gh auth status >/dev/null 2>&1 || {
    echo "error: gh is not authenticated, so nothing about $ORG_SLUG can be established." >&2
    echo "       Run 'gh auth login' and re-run — this refuses rather than seeding blind." >&2; exit 3; }
  if [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
    echo "error: --org needs an empty or absent directory; $TARGET has content." >&2
    echo "       A bundle that is already here is refreshed by: /${PLUGIN_NAME}:init $TARGET" >&2; exit 3
  fi

  if gh repo view "$ORG_SLUG" --json name >/dev/null 2>&1; then
    echo "  clone $ORG_SLUG -> $TARGET"
    gh repo clone "$ORG_SLUG" "$TARGET" -- --quiet >/dev/null 2>&1 \
      || { echo "error: could not clone $ORG_SLUG" >&2; exit 3; }
    ORG_HOST=existing
    ORG_REMOTE="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"
    if [ -e "$TARGET/instance.config.json" ] || [ -e "$TARGET/$AB_SCHEMA" ]; then
      :
    elif [ -z "$(git -C "$TARGET" rev-parse --verify HEAD 2>/dev/null || true)" ]; then
      echo "  empty $ORG_SLUG has no commits — seeding it as this org's bundle"
      ORG_PUSH=yes
    else
      echo "error: $ORG_SLUG exists and is not a loopd bundle" >&2
      echo "       (no instance.config.json, no $AB_SCHEMA). Refusing to stamp over it." >&2
      echo "       Pick another name: --org $ORG_FLAG --name <repo>" >&2
      echo "       The clone is at $TARGET — remove it if you did not want it:" >&2
      echo "         rm -rf $TARGET" >&2
      exit 3
    fi
  else
    org_me="$(gh api user --jq .login 2>/dev/null || true)"
    org_access=""
    if [ -n "$org_me" ] && [ "$ORG_FLAG" = "$org_me" ]; then
      org_access="it is your own account (gh api user)"
    elif [ -n "$org_me" ]; then
      org_state="$(gh api "orgs/$ORG_FLAG/memberships/$org_me" --jq .state 2>/dev/null || true)"
      case "$org_state" in
        active|pending) org_access="gh api orgs/$ORG_FLAG/memberships/$org_me -> $org_state" ;;
      esac
    fi
    if [ -z "$org_access" ]; then
      echo "error: $ORG_SLUG did not resolve, and your access to $ORG_FLAG could not be" >&2
      echo "       established (gh api orgs/$ORG_FLAG/memberships/<you>). A 404 means" >&2
      echo "       'absent' OR 'private, and you cannot see it yet' — so this refuses" >&2
      echo "       rather than seeding a fresh bundle over the org's real one." >&2
      echo "       Ask for membership of $ORG_FLAG, then re-run this command." >&2
      exit 3
    fi
    echo "  access $ORG_FLAG — $org_access"
    if gh repo create "$ORG_SLUG" --private >/dev/null 2>&1; then
      ORG_HOST=org
    else
      ORG_SLUG="$org_me/$ORG_NAME"
      gh repo create "$ORG_SLUG" --private >/dev/null 2>&1 || {
        echo "error: could not create $ORG_FLAG/$ORG_NAME or $ORG_SLUG." >&2
        echo "       Nothing was stamped. Create the repo by hand and re-run." >&2; exit 3; }
      ORG_HOST=user
    fi
    ORG_PUSH=yes
    ORG_REMOTE="$(gh repo view "$ORG_SLUG" --json sshUrl --jq .sshUrl 2>/dev/null || true)"
    [ -n "$ORG_REMOTE" ] || ORG_REMOTE="https://github.com/$ORG_SLUG.git"
    echo "  create $ORG_SLUG (private)"
  fi
fi

# Name the seeded workspace file after the group so an open editor window is
# identifiable (VS Code shows the .code-workspace *filename* — there's no top-level
# name field). The group is `group` in the bundle's config, else its directory name
# minus a bundle prefix — bundle-paths.sh owns both halves.
WS_GROUP="$(ab_group "$TARGET")"
WS_NAME="${WS_GROUP}.code-workspace"
case "$WS_GROUP" in */*) WS_NAME="" ;; esac

# =========================================================================================
# THE CONVERSION SWEEP — a symlink-era bundle becomes a plugin-native one, in place.
# =========================================================================================
#
# WHAT A LEGACY LINK IS, and why the test is on the LINK rather than on a path list. Every
# machinery file a bundle carried was an absolute symlink into a template checkout, and
# the set of those paths changed across template versions — 37 at the last count, sixteen
# more retired before that. A closed list of names would therefore be wrong for exactly the
# oldest bundles, which are the ones that most need converting. So the classification is
# structural and has three cases, in this order:
#
#   · the target is GONE                      => dangling. One possible meaning: remove.
#   · the target path contains `/symlink/`    => a machinery link from any template
#                                                version this project ever shipped.
#   · the target resolves inside a TEMPLATE   => a link stamped by a checkout that is
#     CHECKOUT (a directory holding both        still on disk — the live half of the same
#     `seed/` and `VERSION`)                    design.
#
# ANYTHING ELSE IS REPORTED AND LEFT. A symlink a human made to their own notes directory
# is theirs; `repos/` is skipped entirely (it IS the derived view this script maintains,
# and its links point at reposRoot, never into a template).
#
# DATA IS NEVER TOUCHED. Only the link is removed — never a real file, never a directory,
# never anything under projects/, knowledge/ or objectives/. A removed link leaves the path
# ABSENT, which is what lets the seed step below put a real file there: that is how
# SCHEMA.md, CONVENTIONS.md, agents/index.md and .claude/settings.json stop being links
# into a checkout and become the bundle's own copies.
#
# AUTONOMY.md IS NOT REPLACED, AND THAT IS DELIBERATE. It is the "one deletable file"
# capability, so shipping it with CORE would arm delegated authority everywhere — which is
# why it ships from the separate yolo companion plugin instead, and why the
# note below names an install rather than a `cp`. A
# bundle that had it loses it here, in the safe direction (no file = always ask), and the
# removal is reported LOUDLY with the exact command to put it back, because a capability
# disappearing quietly is the one outcome worse than losing it.
#
# Idempotent: a bundle with no such links prints nothing and changes nothing.
# The LEGACY root shape — `seed/` and `VERSION` at the top — and deliberately not the
# current one. Every link this can classify was written by the retired install.sh, from a
# checkout of a version that kept them there; a post-move checkout stamps no links at all.
looks_like_template() { # <dir> — is this a template checkout a legacy stamp came from?
  [ -d "$1/seed" ] && [ -f "$1/VERSION" ]
}

legacy_link_kind() { # <absolute path to a symlink> — prints a reason, or nothing
  local dst="$1" target resolved probe
  target="$(readlink "$dst" 2>/dev/null || true)"
  [ -n "$target" ] || return 0
  if [ ! -e "$dst" ]; then printf 'dangling (was -> %s)' "$target"; return 0; fi
  case "$target" in */symlink/*) printf 'machinery link into a template checkout'; return 0 ;; esac
  resolved="$(cd "$(dirname "$dst")" 2>/dev/null && cd "$(dirname "$target")" 2>/dev/null && pwd || true)"
  [ -n "$resolved" ] || return 0
  probe="$resolved"
  while [ "$probe" != "/" ] && [ -n "$probe" ]; do
    if looks_like_template "$probe"; then printf 'link into the template checkout at %s' "$probe"; return 0; fi
    probe="$(dirname "$probe")"
  done
  return 0
}

convert_bundle() { # removes legacy machinery links; prints one line each
  local dst rel kind n=0 autonomy_lost=0
  while IFS= read -r dst; do
    [ -n "$dst" ] || continue
    # "$TARGET" must be QUOTED inside the prefix operator: unquoted it is matched as a
    # GLOB, so a bundle path containing [ ] * or ? strips nothing and the relative path
    # stays absolute. (SC2295.)
    rel="${dst#"$TARGET"/}"
    # NEVER INSIDE THE DATA DIRECTORIES, and that is the guarantee this whole step makes.
    # No installer ever stamped machinery under `projects/`, `knowledge/` or `objectives/`,
    # so a symlink there is the human's — a linked spec, a shared notes folder, a broken
    # one they have not fixed yet — and none of that is ours to judge, dangling or not.
    # `repos/` is excluded for the opposite reason: it IS the derived view this script
    # maintains, and its links point at reposRoot rather than into any checkout.
    case "$rel" in
      repos|repos/*|projects|projects/*|knowledge|knowledge/*|objectives|objectives/*) continue ;;
    esac
    kind="$(legacy_link_kind "$dst")"
    [ -n "$kind" ] || { echo "  keep  $rel (a symlink of your own — left alone)"; continue; }
    rm -f "$dst"
    n=$((n + 1))
    echo "  retire $rel — $kind"
    [ "$rel" = "AUTONOMY.md" ] && autonomy_lost=1
  done <<EOF
$(find "$TARGET" -name .git -prune -o -type l -print 2>/dev/null | sort)
EOF
  # The directories those links lived in are the old machinery's, not the bundle's, so an
  # EMPTY one left behind is litter. `rmdir` and not `rm -r`: a directory that still holds
  # anything — a file the human put there, a link left alone above — is kept, silently,
  # because the failure is the whole guard.
  local d
  for d in scripts .claude/hooks .claude/commands .claude/agents .claude/rules agents; do
    [ -d "$TARGET/$d" ] && rmdir "$TARGET/$d" 2>/dev/null && echo "  rmdir  $d/ (emptied by the conversion)"
  done
  rmdir "$TARGET/.claude" 2>/dev/null || true
  if [ "$n" -gt 0 ]; then
    echo "  Converted: $n machinery link(s) removed. The machinery runs from the plugin now."
  fi
  if [ "$autonomy_lost" -eq 1 ]; then
    echo "  NOTE: AUTONOMY.md was a machinery link and is GONE, so this bundle is back to" >&2
    echo "        ask-first for every delegated write. That is the safe end of the change," >&2
    echo "        and it is not silent: to opt back in, install the companion that ships it —" >&2
    echo "          /plugin install loopd-yolo@loopd" >&2
  fi
}

if [ "$MODE" = "uninstall" ]; then
  echo "Removing the loopd derived views from $TARGET"
  ( cd "$TARGET" && bash "$BIN_DIR/link-repos.sh" --remove ) || true
  convert_bundle
  echo "Done. Seed content, bundle data, and backups were left untouched."
  exit 0
fi

echo "Initialising the loopd bundle at $TARGET"

# STEP 0 — convert first, so the seed step can fill a path a link used to occupy.
convert_bundle

# Is this the first stamp, or a refresh of an existing instance? Decided BEFORE
# seeding, since seeding is what creates instance.config.json. Only the awaiting
# queue below needs to know, and it needs to badly: see there for why.
# Read a boolean from instance.config.json without requiring jq. Absent key, absent
# file, or an unreadable file all yield the DEFAULT — absence must never flip a
# behaviour to the unsafe side, and here the default is the caller's business.
cfg_bool() { # <key> <default> <config-path>
  # No jq dependency, and NO BRE ALTERNATION. `\(true\|false\)` is a GNU sed extension:
  # BSD sed matches nothing and this function silently returned the default forever, so
  # `board: false` was ignored. Measured — it is the third time today that `\|` outside
  # ERE has produced a silent wrong answer in this codebase. Two fixed-string greps
  # instead; `false` is checked FIRST so a malformed file cannot turn an opt-out into an
  # opt-in.
  _k="$1"; _d="$2"; _f="$3"
  [ -f "$_f" ] || { printf '%s' "$_d"; return 0; }
  if grep -q "\"$_k\"[[:space:]]*:[[:space:]]*false" "$_f" 2>/dev/null; then printf 'false'
  elif grep -q "\"$_k\"[[:space:]]*:[[:space:]]*true" "$_f" 2>/dev/null; then printf 'true'
  else printf '%s' "$_d"; fi
}

FIRST_STAMP=no
[ -e "$TARGET/instance.config.json" ] || FIRST_STAMP=yes

# THE STAMPED-SEED RECORD — the merge base a machine with no clone still has.
#
# `refresh-seeds.sh` 3-way merges a later seed change into a bundle, and to do that it
# needs the version the bundle's copy was made FROM. It used to find that in git history,
# which an INSTALLED plugin has none of: the cache is a plain copy, so on a real machine
# every seed file a bundle had edited came back UNKNOWN (measured 2026-09-06: 8 of 12 on
# `_ai-bridge-private`). The stamp is the one moment that knows the answer for certain, so
# it writes it down: a pristine copy of every seed file THIS stamp actually copied.
#
# Only what the stamp WROTE. A `keep`d path was placed by some earlier stamp — from a seed
# this copy may never have carried — and recording today's seed as its base would be a
# fabricated provenance, which is worse than none: a false base merges silently.
# The record is bundle content, not machine state, so it is tracked and travels with a
# shared bundle's clone. ~190 KB, and it is what makes the refresh work offline.
SEED_BASE_DIR="$TARGET/$AB_DIR/seed-base"
record_seed_base() { # <rel> <the seed file just copied>
  local d=.; case "$1" in */*) d="${1%/*}" ;; esac   # dirname, without the process
  [ -d "$SEED_BASE_DIR/$d" ] || mkdir -p "$SEED_BASE_DIR/$d" 2>/dev/null || return 0
  cp "$2" "$SEED_BASE_DIR/$1" 2>/dev/null || true
}

# 1. Seed content — copy only what's absent (never clobber instance data).
if [ -d "$SEED_SRC" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # The workspace file is seeded under a group-specific name (see WS_NAME above).
    if [ "$rel" = "bridge.code-workspace" ]; then
      existing="$(find "$TARGET" -maxdepth 1 -name '*.code-workspace' 2>/dev/null | head -1)"
      if [ -n "$existing" ]; then
        echo "  keep  $(basename "$existing") (workspace exists)"
      elif [ -z "$WS_NAME" ]; then
        echo "  warn  group '$WS_GROUP' is not a file name; no .code-workspace seeded — fix \`group\` in instance.config.json" >&2
      else
        # The seed ships terminal.integrated.cwd commented out with a __BRIDGE_DIR__
        # placeholder; uncomment it with this instance's absolute path so every new
        # terminal in the workspace starts in the instance rather than the group
        # root — see the comment in seed/bridge.code-workspace for why the wrong
        # cwd silently hides the bundle's linked agents and its banner. Whole-line
        # replacement, so a marker that ever stops matching degrades to "no pin"
        # rather than to a broken workspace file. Escaped for sed's replacement
        # side ('&' means "the match", '\' escapes, '|' is our delimiter) so a path
        # containing any of them can't corrupt the file. JSON-escaped first (a
        # literal '\' or '"' in a path would otherwise emit an invalid string).
        ws_dir="$(printf '%s' "$TARGET" | sed 's/["\\]/\\&/g; s/[\\&|]/\\&/g')"
        sed "s|^ *// \"terminal.integrated.cwd\": \"__BRIDGE_DIR__\",|    \"terminal.integrated.cwd\": \"$ws_dir\",|" \
          "$SEED_SRC/$rel" > "$TARGET/$WS_NAME"
        echo "  seed  $WS_NAME"
        # No live setting line means the marker stopped matching the seed; say so
        # rather than leaving a silently unpinned workspace. (Checking for a
        # leftover placeholder wouldn't work — a drifted line is still a comment.)
        if ! grep -q '^ *"terminal\.integrated\.cwd":' "$TARGET/$WS_NAME"; then
          echo "  warn  $WS_NAME: terminal cwd not stamped; set terminal.integrated.cwd to $TARGET by hand" >&2
        fi
      fi
      continue
    fi
    # THE SEED IS FLAT AND THE BUNDLE IS NOT — the mapping happens here, on the copy.
    # `record_seed_base` is keyed by the SEED path, so `$AB_DIR/seed-base/` stays flat
    # and refresh-seeds.sh's merge base is unchanged by the move.
    dest="$(ab_seed_dest "$rel")"
    src="$SEED_SRC/$rel"; dst="$TARGET/$dest"
    dstdir="${dst%/*}"
    if [ -e "$dst" ]; then
      echo "  keep  $dest (exists)"
    elif [ "${rel##*/}" = ".gitkeep" ] && [ -d "$dstdir" ] && [ -n "$(ls -A "$dstdir" 2>/dev/null)" ]; then
      # The dir already has real content — a placeholder .gitkeep would just be clutter.
      echo "  skip  $dest (dir already populated)"
    else
      [ -d "$dstdir" ] || mkdir -p "$dstdir"
      cp "$src" "$dst"
      record_seed_base "$rel" "$src"
      echo "  seed  $dest"
    fi
  done <<EOF
$(cd "$SEED_SRC" && find . -type f | sed 's#^\./##' | sort)
EOF
fi

# 1a. objectives/ — created ONLY when asked. Absence is the default, not a gap.
if [ "$WITH_OBJECTIVES" = 1 ] && [ "$LAYER" = instance ]; then
  if [ -d "$TARGET/objectives" ]; then
    echo "  keep  objectives/ (exists)"
  else
    mkdir -p "$TARGET/objectives" && : > "$TARGET/objectives/.gitkeep"
    echo "  seed  objectives/ (optional layer: goals that outlive one project)"
  fi
fi

# 1b. The awaiting-you queue, created ONLY on the first stamp.
#
# AWAITING.md is opt-in by presence: the project-manager refreshes it only when
# it exists and never creates it, so deleting it turns the startup nudge off for
# good. That switch is the whole design — but it also means a brand-new instance
# would start with the queue OFF, and the SessionStart nudge would never fire
# until someone happened to read the docs and touch the file. So the installer
# provides the initial file, exactly once.
#
# It must NOT run on a refresh: re-creating the file would silently undo a
# deliberate `rm`, which is the one thing the off switch has to survive. That's
# what FIRST_STAMP guards. It's also gitignored, so this never becomes tracked
# state. Content is a valid empty queue, so session-banner.sh stays silent until
# the first tick fills it in.
if [ "$FIRST_STAMP" = yes ] && [ ! -e "$TARGET/$AB_AWAITING" ]; then
  cat > "$TARGET/$AB_AWAITING" <<'AWAITING'
# Awaiting you

Derived and gitignored — **do not hand-edit**. Rewritten from `projects/*/tasks/*.md`
by each dispatch tick that changed something. Delete this file to turn the queue off for good;
the loop never recreates it. Last refreshed: never (no tick has run yet).

## 🔴 Awaiting you (0)
_None._
AWAITING
  echo "  seed  $AB_AWAITING (queue on; delete it to turn the startup nudge off)"
elif [ "$FIRST_STAMP" = no ] && [ ! -e "$TARGET/$AB_AWAITING" ]; then
  echo "  skip  $AB_AWAITING (absent by choice — run 'touch $AB_AWAITING' to re-enable)"
fi

# 1c. The board snapshot, created ONLY on the first stamp — same contract, same
# reason, same guard as AWAITING.md above.
#
# SNAPSHOT.json is ON BY DEFAULT, and `board` in instance.config.json is the off switch.
#
# It used to be opt-in by presence, with FIRST_STAMP making `rm SNAPSHOT.json`
# permanent. That inverted the common case: every instance stamped before the board
# existed silently stayed off it, and putting one back on meant knowing to `touch` a file
# nothing mentioned. Three of three instances here were in that state.
#
# So the decision moved to config, where it is visible and survives a re-stamp:
#
#   · `board` absent or true  => create SNAPSHOT.json when missing, on ANY stamp.
#   · `board: false`          => never create it, and say so.
#
# `rm SNAPSHOT.json` still takes the instance off the board immediately — the writer
# never resurrects it (see write-snapshot.sh) — but it is no longer PERMANENT: the next
# stamp brings it back unless config says otherwise. That is the trade, and it is the
# right way round: a deletion is a moment's decision, a config key is a durable one.
#
# WHAT THIS DOES NOT CHANGE, and the distinction matters for a no-PII instance:
# SNAPSHOT.json is a LOCAL, gitignored file, and so is the page rendered from it. Having
# one puts an instance on the TERMINAL board and makes a page renderable — and since the
# account-scoped publish path was deleted, nothing this repo ships sends any of it
# anywhere. Question TEXT is never in either; only board-serve.sh's response carries it.
# On-by-default is therefore safe even for an instance whose board must not leave the
# machine.
#
# THIS IS NO LONGER THE ONLY READER OF `board`, AND THAT IS THE POINT. The key is read
# here at STAMP time, deciding whether the file below is created at all; each dispatch
# tick and the SessionStart board hook read it again at TICK time, deciding whether the
# page is rendered and surfaced. Until 2026-08-29 nothing re-read it, so `board: false`
# stopped the seed and stopped nothing afterwards. Every reader takes it from THIS
# tracked config — never from a per-machine override — so one key cannot become two
# switches that disagree.
#
# NO SCRIPT IS NAMED HERE, ON PURPOSE. This comment used to name the renderer it meant,
# and when that renderer was folded into another the name went stale — install.sh never
# calls it, so nothing noticed until retire-machinery.test.sh (which asserts install.sh
# carries no machinery name at all) went red. Name the capability; leave the entry point
# to docs/operations.md, which is checked against the tree.
#
# It is deliberately generated ROOT content and not seed content: a seed file is restored
# whenever it is absent, so a deletable capability built out of one comes back by itself.
# A gitignored root file created only under this guard has no such hole.
#
# Seeded content is a VALID EMPTY snapshot rather than an empty file: build-board.sh
# parses this as JSON, and a zero-byte file would render an "unreadable snapshot" note
# on a brand-new instance that has done nothing wrong.
BOARD_OPT="$(cfg_bool board true "$TARGET/instance.config.json")"
if [ "$BOARD_OPT" = false ]; then
  echo "  skip  $AB_SNAPSHOT (board: false in instance.config.json)"
elif [ ! -e "$TARGET/$AB_SNAPSHOT" ]; then
  cat > "$TARGET/$AB_SNAPSHOT" <<'SNAPSHOT'
{
  "_schema": "ai-bridge board snapshot v1",
  "_sensitivity": "Derived and gitignored. Rewritten by write-snapshot.sh each dispatch tick. Delete this file to drop off the board until the next stamp; set \"board\": false in instance.config.json to stay off.",
  "group": "",
  "generated_at": "",
  "counts": {"projects": 0, "tasks": 0, "awaiting": 0},
  "projects": []
}
SNAPSHOT
  echo "  seed  $AB_SNAPSHOT (on the board; set \"board\": false to opt out)"
fi

# 1d. THE STATUS LINE — into the BUNDLE's own .claude/settings.json, never the user's.
#
# PROJECT settings, so the install is scoped to this bundle and touches no file in
# ${CLAUDE_CONFIG_DIR:-~/.claude}. That is also why it needs no ask: nothing outside the
# bundle moves. It runs on every stamp rather than only the first, because the seed copy
# above is copy-if-absent — an already-stamped bundle has a settings.json and would
# otherwise never receive the key.
#
# AND PROJECT SETTINGS OVERRIDE USER SETTINGS FOR THE SAME KEY, so a `statusLine` the human
# already has is SHADOWED here for every session opened in this bundle. Shadowed, not
# changed — their file is untouched — but they are told, by name, rather than finding out.
#
# The command is written as an ABSOLUTE path to a seeded shim and not to the plugin: a
# `statusLine` command gets no `${CLAUDE_PLUGIN_ROOT}` expansion, and a version-scoped
# cache path rots on the next plugin update. The shim resolves the plugin at run time.
#
# The insert is jq-free (nothing in this plugin may need jq) and FAILS CLOSED: it goes in
# directly under a top-level `{` on its own line, and a settings.json shaped any other way
# is reported for the human to edit rather than rewritten by a guess.
SL_SETTINGS="$TARGET/.claude/settings.json"
SL_SHIM="$TARGET/.claude/loopd-statusline.sh"
if [ ! -f "$SL_SETTINGS" ]; then
  echo "  skip  statusLine (no $SL_SETTINGS to write it into)"
elif grep -q '"statusLine"' "$SL_SETTINGS"; then
  echo "  keep  statusLine (this bundle's .claude/settings.json already has one)"
elif [ "$(sed -n '/[^[:space:]]/{p;q;}' "$SL_SETTINGS")" != "{" ]; then
  echo "  warn  statusLine not installed: $SL_SETTINGS does not open with a bare \`{\`." >&2
  echo "        Add it by hand: \"statusLine\": {\"type\": \"command\", \"command\": \"bash $SL_SHIM\", \"refreshInterval\": 5000}" >&2
else
  sl_cmd="$(printf '%s' "bash $SL_SHIM" | sed 's/["\\]/\\&/g')"
  sl_tmp="$SL_SETTINGS.statusline.$$"
  # `refreshInterval`, not triggers: the documented update events go quiet exactly while a
  # coordinator waits on background subagents, which is the dispatch loop in its steady state.
  CMD="$sl_cmd" awk '
    !ins && /^[[:space:]]*\{[[:space:]]*$/ {
      print
      print "  \"statusLine\": {"
      print "    \"type\": \"command\","
      print "    \"command\": \"" ENVIRON["CMD"] "\","
      print "    \"refreshInterval\": 5000"
      print "  },"
      ins = 1
      next
    }
    { print }
  ' "$SL_SETTINGS" > "$sl_tmp" 2>/dev/null
  if [ -s "$sl_tmp" ] && grep -q '"statusLine"' "$sl_tmp"; then
    mv "$sl_tmp" "$SL_SETTINGS"
    echo "  wrote statusLine into .claude/settings.json (AI Bridge · in flight · agents · need you · lock · last tick)"
    sl_user="$CONFIG_DEST/settings.json"
    if [ -f "$sl_user" ] && grep -q '"statusLine"' "$sl_user"; then
      echo "  note  PROJECT settings win, so this shadows the statusLine in $sl_user"
      echo "        for sessions in this bundle. That file is untouched; drop the block"
      echo "        from .claude/settings.json to get yours back."
    fi
  else
    rm -f "$sl_tmp" 2>/dev/null
    echo "  warn  statusLine not installed: could not rewrite $SL_SETTINGS." >&2
  fi
fi

# 1e. THE SCRIPT ALLOWLIST — into the gitignored .claude/settings.local.json, because the
# rule is an absolute $HOME path. Only the version is wild: `*.sh:*` and `~` forms match
# nothing (Claude Code 2.1.284, task-016). jq-free and fail-closed like 1d.
AL_FILE="$TARGET/.claude/settings.local.json"
AL_OPEN='"allow"[[:space:]]*:[[:space:]]*\[[[:space:]]*$'
al_mk="${PLUGIN_ROOT%/*}"
case "${al_mk##*/}|${al_mk%/*/*}|$PLUGIN_ROOT" in
  *'"'*|*'\'*|*'('*|*')'*) al_mk="" ;;
  "$PLUGIN_NAME"\|*/plugins/cache\|*) ;;
  *) al_mk="" ;;
esac
al_write() { # <missing entries, one per line> -> the rewritten file on stdout, or nothing
  local body add
  add="$1"
  body="$(tr -d '[:space:]' < "$AL_FILE" 2>/dev/null)"
  if [ -z "$body" ] || [ "$body" = "{}" ]; then
    printf '{\n  "permissions": {\n    "allow": [\n%s\n    ]\n  }\n}\n' "$(printf '%s' "$add" | sed '$s/,$//')"
  elif [ "$(grep -c "$AL_OPEN" "$AL_FILE")" = 1 ]; then
    # Blank lines between `[` and `]` still mean an empty array, which takes the entries
    # WITHOUT the trailing comma; a non-empty one keeps it, ahead of its first element.
    if O="$AL_OPEN" awk '$0 ~ ENVIRON["O"] {
           while ((getline) > 0) if ($0 !~ /^[[:space:]]*$/) exit !/^[[:space:]]*\]/
           exit 0 }' "$AL_FILE"; then
      add="$(printf '%s' "$add" | sed '$s/,$//')"
    fi
    O="$AL_OPEN" AL="$add" awk '{ print } $0 ~ ENVIRON["O"] { print ENVIRON["AL"] }' "$AL_FILE"
  fi
}
if [ -z "$al_mk" ]; then
  echo "  skip  script allowlist (not run from a plugin cache install)"
else
  al_missing=""
  for r in "Bash($al_mk/*/scripts/*)" "Bash(bash $al_mk/*/scripts/*)"; do
    grep -qF "\"$r\"" "$AL_FILE" 2>/dev/null || al_missing="${al_missing:+$al_missing
}      \"$r\","
  done
  al_tmp="$AL_FILE.allow.$$"
  if [ -z "$al_missing" ]; then
    echo "  keep  script allowlist (.claude/settings.local.json already has both rules)"
  elif [ ! -L "$AL_FILE" ] && mkdir -p "$TARGET/.claude" && al_write "$al_missing" > "$al_tmp" &&
       [ -s "$al_tmp" ] &&
       printf '%s\n' "$al_missing" | while IFS= read -r l; do grep -qF "${l%,}" "$al_tmp" || exit 1; done &&
       { ! command -v python3 >/dev/null 2>&1 ||
         python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$al_tmp" 2>/dev/null; } &&
       mv "$al_tmp" "$AL_FILE"; then
    echo "  wrote script allowlist into .claude/settings.local.json:"
    printf '%s\n' "$al_missing" | sed 's/,$//'
  else
    rm -f "$al_tmp"
    echo "  warn  script allowlist not written: no safe edit of $AL_FILE (a multi-line \"allow\": [ is the one shape edited)." >&2
    echo "        Add to permissions.allow by hand:" >&2
    printf '%s\n' "$al_missing" | sed 's/,$//' >&2
  fi
  if grep -qF '/scripts/*.sh:*)' "$AL_FILE" 2>/dev/null; then
    echo "  note  .claude/settings.local.json has a \`scripts/*.sh:*\` rule; that form matches nothing — drop it."
  fi
fi

# 1f. THE `claude --bg` GRANT IS NOTICED, NEVER WRITTEN: a plugin must not grant itself a
# permissions bypass (owner, 2026-09-25/30). tests/no-bg-grant.test.sh pins it; task-019.
BG_RULE="Bash(claude --bg * --agent ${PLUGIN_NAME}:* --permission-mode auto --add-dir *)"
BG_OLD="Bash(claude --bg * --agent ${PLUGIN_NAME}:* --permission-mode bypassPermissions --add-dir *)"
BG_INERT="Bash(claude --bg ' *)"
if grep -qF "\"$BG_INERT\"" "$AL_FILE" 2>/dev/null; then
  echo "  note  .claude/settings.local.json has \`$BG_INERT\`; it matches no spawn form measured (Claude Code 2.1.285)."
  echo "        The narrowest that does: $BG_RULE"
elif grep -qF "\"$BG_OLD\"" "$AL_FILE" 2>/dev/null; then
  echo "  note  .claude/settings.local.json grants a \`bypassPermissions\` spawn; the tick spawns in auto mode now, so it matches nothing."
  echo "        The narrowest that does: $BG_RULE"
elif ! grep -qE '"Bash\(claude --bg' "$AL_FILE" 2>/dev/null; then
  echo "  note  init writes no \`claude --bg\` grant. The narrowest rule measured to match the tick's spawn:"
  echo "          $BG_RULE"
  echo "        It lets the tick spawn any ${PLUGIN_NAME} role, in auto mode, unprompted."
  echo "        Adding it to .claude/settings.local.json is yours, not the plugin's."
fi

# 1g. A STABLE PATH TO THE SCRIPTS, for the operator's terminal only: a link this stamp
# re-points at its own scripts/, and a PATH line it prints but never writes (task-022).
# Ours = a symlink into a plugin cache's <plugin>/<version>/scripts; anything else is left.
BIN_LINK="$CONFIG_DEST/plugins/$PLUGIN_NAME/bin"
bin_prev="$(readlink "$BIN_LINK" 2>/dev/null || true)"
bin_ok=1
if [ -z "$al_mk" ]; then
  bin_ok=0; echo "  skip  $BIN_LINK (not run from a plugin cache install)"
elif [ "$bin_prev" = "$BIN_DIR" ]; then
  echo "  keep  $BIN_LINK -> $BIN_DIR"
elif [ -L "$BIN_LINK" ] && case "$bin_prev" in */plugins/cache/*/"$PLUGIN_NAME"/*/scripts) true ;; *) false ;; esac; then
  ln -sfn "$BIN_DIR" "$BIN_LINK" && echo "  link  $BIN_LINK -> $BIN_DIR (was $bin_prev)" \
    || { bin_ok=0; echo "  warn  could not re-point $BIN_LINK" >&2; }
elif [ -e "$BIN_LINK" ] || [ -L "$BIN_LINK" ]; then
  bin_ok=0
  echo "  warn  $BIN_LINK exists and is not a link this stamp made; left alone." >&2
  echo "        Move it aside and re-run /${PLUGIN_NAME}:init to get the stable scripts path." >&2
elif mkdir -p "${BIN_LINK%/*}" && ln -s "$BIN_DIR" "$BIN_LINK"; then
  echo "  link  $BIN_LINK -> $BIN_DIR"
else
  bin_ok=0; echo "  warn  could not create $BIN_LINK" >&2
fi
bin_shown="$BIN_LINK"
case "$BIN_LINK" in
  *[\"\`\\\$]*) [ "$bin_ok" = 0 ] || echo "  warn  $BIN_LINK needs shell quoting; no PATH line printed" >&2; bin_ok=0 ;;
  "$HOME"/*) bin_shown="\$HOME/${BIN_LINK#"$HOME"/}" ;;
esac
if [ "$bin_ok" = 1 ]; then
  case ":$PATH:" in
    *":$BIN_LINK:"*) ;;
    *)
      echo "  note  for your terminal only, add this line to your shell rc yourself (init never edits it):"
      echo "          if [ -d \"$bin_shown\" ]; then export PATH=\"$bin_shown:\$PATH\"; fi"
      echo "        Agents and permission rules keep the absolute versioned path; never point them here." ;;
  esac
fi

# 2. RETIRE the managed machinery block from the bundle's .gitignore.
#
# The block used to be REWRITTEN on every stamp from the list of files this template
# symlinked in — 37 lines on the last symlink-era bundle. There is no machinery in a
# bundle now, so the block has nothing to list, and an empty marker pair is a place for
# the design to grow back. It is removed entirely, once, and a bundle that never had one
# is untouched.
#
# EVERYTHING OUTSIDE THE MARKERS IS PRESERVED, byte for byte — a human's own rules sit in
# the same file, and the seed's ignores (AWAITING.md, SNAPSHOT.json, the board caches) all
# live outside it. A BEGIN with no END after it is left ALONE and reported: the awk below
# would otherwise drop every line from BEGIN to EOF, and an interrupted stamp or a
# hand-edit reaches exactly that state.
gi="$TARGET/.gitignore"
[ -f "$gi" ] || : > "$gi"

# EVERY PATTERN THIS SECTION APPENDS GOES INTO THE BUNDLE'S OWN `# Instance additions`
# BLOCK, AND THAT BLOCK STAYS LAST. refresh-seeds.sh treats the heading through end of
# file as bundle-owned, so a pattern written there never reads as seed drift — appending
# after the seed's managed blocks instead is what made `.gitignore` conflict on every
# bundle forever (2x/task-008). The marker-wrapped blocks go AHEAD of the heading, so the
# layout is: seed, then the managed markers, then the instance block.
GI_ADDITIONS="# Instance additions (kept across seed refreshes)"
gi_add() {          # stdin -> the end of the instance block, creating its heading if absent
  grep -qxF "$GI_ADDITIONS" "$gi" || printf '\n%s\n' "$GI_ADDITIONS" >> "$gi"
  ab_expand >> "$gi"
}
gi_add_before() {   # stdin -> immediately before that heading; at EOF when there is none
  local ln tmp
  ln="$(grep -nxF "$GI_ADDITIONS" "$gi" | head -1 | cut -d: -f1)" || true
  if [ -z "$ln" ]; then { printf '\n'; cat; } >> "$gi"; return 0; fi
  tmp="$gi.tmp.$$"
  { sed -n "1,$((ln-1))p" "$gi"; cat; sed -n "$ln,\$p" "$gi"; } > "$tmp" && mv "$tmp" "$gi"
}
if grep -qxF "$BEGIN_MARK" "$gi"; then
  mb="$(grep -nxF "$BEGIN_MARK" "$gi" | head -1 | cut -d: -f1)" || true
  me="$(grep -nxF "$END_MARK" "$gi" | head -1 | cut -d: -f1)" || true
  if [ -z "$me" ] || [ "$me" -lt "$mb" ]; then
    echo "  warn  $gi carries a machinery BEGIN marker with no matching END after it." >&2
    echo "        Left UNCHANGED rather than risk dropping everything after it. Delete the" >&2
    echo "        stray line by hand, then re-run." >&2
  else
    tmp="$gi.tmp.$$"
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      $0==b { inblock=1; next }
      $0==e { inblock=0; next }
      !inblock { print }
    ' "$gi" > "$tmp" && mv "$tmp" "$gi"
    echo "  retire .gitignore machinery block (a bundle carries no machinery now)"
  fi
fi

# The repos/ view is derived, so it must be ignored too — but OUTSIDE the managed
# block, which is regenerated from the machinery file list and would drop any line
# that isn't a machinery path. Appended once; a hand-written `repos/` also counts.
if ! grep -qE '^/?repos/?$' "$gi"; then
  gi_add <<'GI'

# Derived view of the group's product repos (link-repos.sh) — symlinks
# into reposRoot, never content, and machine-local like the rest. Delete it
# freely; the next /<plugin>:init run recreates it.
/repos/
GI
fi

# The local live board (watch-board.sh) writes its page here. Appended for the
# same reason as /repos/ and instance.config.local.json below: seed content is copied
# only when ABSENT, so an instance stamped before this directory existed — which is
# every instance in existence — would otherwise commit a generated HTML page.
if ! grep -qE "^/?${AB_BOARD_DIR//./\\.}/?$" "$gi"; then
  gi_add <<'GI'

# The local live board page (watch-board.sh). Derived output, regenerated on
# every task-document change, and per-machine. Delete it freely.
/__AB_BOARD_DIR__/
GI
fi

# The board's other-owners cache (build-board.sh), appended for exactly the same
# reason: every instance in existence was stamped before this file existed, and a derived
# cache of committed state has no business being committed back.
if ! grep -qE "^/?${AB_BOARD_OTHERS//./\\.}$" "$gi"; then
  gi_add <<'GI'

# The board's other-owners cache (build-board.sh) — the second half of the page,
# read from the tracked documents at HEAD and stored against the SHA it was computed for.
# Derived and per-machine. Delete it freely; the next render rebuilds it.
/__AB_BOARD_OTHERS__
GI
fi

# The PM dispatch lock (tick-lock.sh), appended for the third time for exactly the
# same reason: every instance in existence was stamped before this file existed, and a lock
# that got committed would stop being per-clone — which is the one property it has.
if ! grep -qE "^/?${AB_LOCK//./\\.}$" "$gi"; then
  gi_add <<'GI'

# The PM dispatch lock (tick-lock.sh) — written by /<plugin>:dispatch
# immediately before it dispatches a tick and released when that tick reports, so the
# one-tick-at-a-time guarantee survives a compaction instead of resting on a session's
# memory. PER CLONE and never committed: two humans sharing one bundle work from two
# clones and each dispatches independently, which a shared lock would break. Derived and
# safe to delete when no tick is running.
/__AB_LOCK__
GI
fi

# The tick's claim on that lock — the second half of the same mechanism, appended under its
# OWN guard rather than inside the block above. That is the whole point: every instance
# stamped since the lock shipped already carries `/.tick-lock`, so the guard above is
# satisfied and would never append a line added to its heredoc. A second file needs a second
# guard, or the ignore silently reaches nobody who has the first one.
if ! grep -qE "^/?${AB_LOCK_CLAIM//./\\.}$" "$gi"; then
  gi_add <<'GI'

# The tick's claim on the dispatch lock (tick-lock.sh) — the tick checks the lock on
# entry too, because a resumed tick never passes through the launcher, and this file is what
# tells "held by the launcher that dispatched me" from "held by another tick". Per clone and
# derived exactly like the lock beside it, and removed with it by
# `tick-lock.sh release`.
/__AB_LOCK_CLAIM__
GI
fi

# The idle-tick fingerprint (tick-delta.sh) — its OWN guard, the .tick-lock.claim
# lesson applied again: every instance stamped since the lock shipped satisfies the guards
# above, so a line added to their heredocs reaches nobody. Per clone and derived: a full
# tick records it, the next tick's probe compares against it, and deleting it costs one
# full tick, never correctness.
if ! grep -qE "^/?${AB_STATE_DIR//./\\.}$" "$gi"; then
  gi_add <<'GI'

# The idle-tick fingerprint (tick-delta.sh) — written at the end of a FULL tick,
# compared by the next tick's fast-path probe. PER CLONE and never committed; delete
# freely (absence = the next tick runs in full).
/__AB_STATE_DIR__
GI
fi

# The merge gate's clearance records — its OWN guard, the .tick-lock.claim lesson again:
# every bundle already satisfies the guards above, so a line added to one of their heredocs
# reaches nobody.
if ! grep -qE "^/?${AB_RECEIPTS//./\\.}/?$" "$gi"; then
  gi_add <<'GI'

# The merge gate's clearance records (clearance-receipt.sh) — one file per PR and head,
# written by the clearance scripts and read by the PreToolUse hook. Per clone, derived and
# never committed; delete freely (absence = the next merge waits for a fresh clearance).
/__AB_RECEIPTS__/
GI
fi

# The copies refresh-seeds.sh keeps — its own guard, the .tick-lock.claim lesson again:
# every bundle in existence satisfies the guards above, so a line added to one of their
# heredocs reaches nobody.
if ! grep -qE "^/?${AB_DIR//./\\.}/refresh/?\$" "$gi"; then
  gi_add <<'GI'

# Copies refresh-seeds.sh keeps when it merges a seed change in — the file it replaced,
# and any merge it could not resolve, with its conflict markers. Derived and per-machine;
# delete it freely. (`__AB_DIR__/seed-base/` beside it IS tracked — it is the merge base
# this bundle was stamped from, and it is the same on every clone.)
/__AB_DIR__/refresh/
GI
fi

# The knowledge-base mount's gitdirs (kb-sync.sh) — its OWN guard, the .tick-lock.claim
# lesson again. Unignored, `kb-migrate.sh` saw its own first half as a dirty tree.
if ! grep -qE "^/?${AB_DIR//./\\.}/kb\.git/?$" "$gi"; then
  gi_add <<'GI'

# The knowledge-base mount's own git directories (kb-sync.sh mount) — nested clones
# the machinery creates and never commits. Per clone; never delete one with unpushed
# commits in it (`kb-sync.sh status` says).
/__AB_DIR__/kb.git/
/__AB_DIR__/kb-src/
GI
fi

# The board page (/board.html) is DERIVED again, so it is ignored again. This block used
# to append the opposite line — `!/board.html` — for the era when the tick committed the
# page; a derived path every clone re-renders and pushes is contended on every tick, and
# the local server replaced it. Purely additive as always: the old un-ignore is never
# removed, and git's LAST-MATCH-WINS rule is what makes a trailing `/board.html` beat it.
#
# The grep runs in `if` CONDITION position, where `set -e` does not apply, so a no-match
# exit 1 is a branch and not an abort. It asks whether the LAST board.html pattern in the
# file is already an ignore, so re-stamping appends nothing.
if [ "$(grep -E '^!?/?board\.html$' "$gi" | tail -1)" != "/board.html" ]; then
  gi_add <<'GI'

# The bundle's board page (build-board.sh) — DERIVED, never tracked. `/<plugin>:board
# serve` serves it out of AB_BOARD_DIR (bundle-paths.sh) on 127.0.0.1, so nothing is pushed.
# This line re-ignores it for instances stamped while it was tracked; git takes the LAST
# matching pattern, so it wins over an older `!/board.html` without editing it.
/board.html
GI
fi

# And the file itself goes, once, for a bundle that has one tracked. It is derived output
# — the next tick re-renders it under AB_BOARD_DIR (bundle-paths.sh) — so this is the one removal the stamp
# makes, and it is reported rather than silent.
if [ -e "$TARGET/board.html" ] && git -C "$TARGET" ls-files --error-unmatch board.html >/dev/null 2>&1; then
  if git -C "$TARGET" rm --cached --quiet board.html 2>/dev/null; then
    rm -f "$TARGET/board.html"
    echo "  drop  board.html — removed and STAGED; commit it. The board is served"
    echo "        locally now: /${PLUGIN_NAME}:board serve."
  fi
fi

# 3b. Two more ignores, appended once each if missing — OUTSIDE the managed block,
# for the same reason as /repos/ above.
#
# Why appended here at all: the seed is copied only if ABSENT, so an instance stamped
# before these lines existed would never receive them, and both are load-bearing.
# `instance.config.local.json` holds per-machine IDENTITY (authorEmail,
# ownerGithubUser) — committing it would push one human's identity into a bundle the
# other reads, which is the exact failure the file exists to prevent. The derived
# indexes are rewritten every tick, so on a shared bundle they conflict on every push.
#
# And why the INDEX lines live ONLY here, never in seed/.gitignore: that file is an
# active .gitignore inside the template's own `seed/` directory, so a `/index.md`
# line in it matches `seed/index.md` and silently stops the template from
# tracking its own seed file. Measured — it broke the upgrade.sh fixture, which
# re-inits a repo over a copy of seed/. `instance.config.local.json` has no such
# collision (no seed file is named that), so it is in both places, harmlessly.
if ! grep -qxF 'instance.config.local.json' "$gi"; then
  gi_add <<'GI'

# Per-machine identity overrides (authorEmail, ownerGithubUser), winning over the
# TRACKED instance.config.json for those keys only. Never commit it: a shared bundle
# would otherwise author both humans' commits as one person.
instance.config.local.json
GI
fi
# Same shape, same reason, for `.env`: a bundle stamped before this line existed would
# otherwise carry an API key into git the first time somebody wrote one down.
if ! grep -qxF '.env' "$gi"; then
  gi_add <<'GI'

# API keys — for a substituted model backend (the llm companion) or anything
# else. NEVER tracked: a key in a tracked file is a published key.
.env
GI
fi
# The derived-index ignore block, behind its own marker pair — the same mechanism the
# machinery block above uses (BEGIN_MARK/END_MARK), and for the same reason. This used
# to be guarded by "append only if the two literal rule lines are missing"
# (`grep -qxF '/index.md' ... || ! grep -qxF '/projects/*/index.md' ...`), which is a
# short-circuit, not a safeguard: once an instance is stamped once, both rule lines exist
# forever, so the whole block is skipped on every later run — a corrected comment, or a
# new rule line added here in the future, would reach only fresh installs. Measured
# twice in one hour against real instances: ai-bridge-v4/task-009.
#
# The fix mirrors the machinery block: fully rewrite the region between two markers on
# every run, and touch nothing outside them. That is also what keeps a RETAINED
# project's escape hatch safe. A negation line (`!projects/<slug>/index.md`, task-008 /
# #29) must be added by hand AFTER the two blanket lines this block emits — i.e. after
# its END marker, never inside the block, since everything between the markers is
# unconditionally replaced on every stamp. Git applies .gitignore patterns in file
# order, so a line after the END marker is a line after the two blanket rules, which is
# the only thing that makes the negation win.
IDX_BEGIN_MARK="# >>> ai-bridge index ignore >>>"
IDX_END_MARK="# <<< ai-bridge index ignore <<<"
idxbody="$(mktemp)"
cat <<'GI' | ab_expand > "$idxbody"
# Derived navigation indexes — the root one and each project's, rewritten by every
# /<plugin>:dispatch tick from the documents they summarise. A view, not source: on
# a bundle shared by more than one human it would otherwise conflict on every push.
# `knowledge/index.md` is deliberately NOT ignored: it is the KB's curated lookup
# surface, changes only when the KB changes, and a fresh clone needs it present.
#
# The one exception is a RETAINED project (`status: done`, kept instead of closed):
# the tick stops touching a retained project at all, so its index.md becomes a
# permanent, hand-committed front door instead of a rewritten view. To retain one,
# add a negation line AFTER the two blanket lines below (i.e. after this block's END
# marker, never inside it — /<plugin>:init rewrites everything between the markers on
# every run), then `git add -f` the file once — e.g. `!projects/<slug>/index.md`.
# Git applies .gitignore patterns in file order, so a LATER negation overrides an
# earlier blanket pattern; putting the override before the two blanket lines below,
# or inside this block, does not survive the next `/<plugin>:init` run.
/__AB_INDEX__
/projects/*/index.md
GI

# `|| true` throughout this section: under `set -o pipefail`, a `grep` that matches
# nothing makes the whole pipeline (and a bare assignment built from it) exit non-zero
# even though `head`/`cut` succeed, and a bare non-zero assignment — unlike one used
# directly as an `if`/`elif` condition — is NOT exempt from `set -e`. Without it, the
# ordinary "no such line" case aborts the whole install.sh run right here instead of
# falling through to the next branch. See knowledge/findings/a-bare-pipeline-assignment-
# aborts-under-set-e-even-when-a-sibling-guard-is-fine.md in the control-panel bundle.
idx_begin_line="$(grep -nxF "$IDX_BEGIN_MARK" "$gi" | head -1 | cut -d: -f1)" || true
if [ -n "$idx_begin_line" ]; then
  # Already migrated to the marker pair by an earlier run of this (fixed) install.sh —
  # rewrite in place, exactly like the machinery block above. EXACT line match
  # (`-qxF`), not a substring one: a comment that merely mentions or resembles this
  # marker text (e.g. quoting it while explaining the mechanism) must not be mistaken
  # for the real marker line, matching the exact-match awk below.
  #
  # BEGIN alone is not enough to rewrite: this awk's `!inblock { print }` only resumes
  # printing once it sees an EXACT END line, so a file with BEGIN and no (or a
  # preceding) END would have every line from BEGIN to EOF silently dropped by the
  # rewrite below — an interrupted stamp or a hand-edit that removed the END line reaches
  # exactly this state. Verify END exists AFTER BEGIN before touching the file at all;
  # if it does not, leave the file untouched and report the problem instead of writing.
  idx_end_line="$(grep -nxF "$IDX_END_MARK" "$gi" | head -1 | cut -d: -f1)" || true
  if [ -z "$idx_end_line" ] || [ "$idx_end_line" -lt "$idx_begin_line" ]; then
    echo "warn  $gi carries an index-ignore BEGIN marker ('$IDX_BEGIN_MARK') with no" >&2
    echo "      matching END marker after it. Left UNCHANGED rather than risk dropping" >&2
    echo "      everything after the BEGIN line. Fix by hand: add '$IDX_END_MARK' right" >&2
    echo "      after the two blanket rule lines (/$AB_INDEX, /projects/*/index.md), or" >&2
    echo "      remove the stray BEGIN line — then re-run." >&2
  else
    tmp="$gi.tmp.$$"
    awk -v b="$IDX_BEGIN_MARK" -v e="$IDX_END_MARK" -v body="$idxbody" '
      $0==b { print; while ((getline line < body) > 0) print line; close(body); inblock=1; next }
      $0==e { print; inblock=0; next }
      !inblock { print }
    ' "$gi" > "$tmp" && mv "$tmp" "$gi"
  fi
else
  # No marker pair yet. An instance stamped by the OLD guard-based install.sh carries
  # the two literal rule lines, adjacent, with no markers — every version of that guard
  # ever emitted them in exactly that shape. Find them and splice the marker pair in
  # where the old comment + two rule lines were, so a negation a human already added
  # right after the old two rule lines ends up right after the new END marker — still
  # after the two blanket rules, which is the only ordering that matters.
  #
  # The old comment is walked off by scanning upward from `/index.md` while lines are
  # comments (`^#`), never by matching its exact text — the whole point of this fix is
  # that the comment has drifted across template versions and instances, so there is no
  # one string to match.
  #
  # Scan EVERY standalone `/index.md` line, not just the first: an earlier, unrelated
  # `/index.md` line (rare, but not impossible — nothing stops a human from ignoring
  # some other file with that exact name) must not steal the adjacency match away from
  # the real index-ignore pair sitting later in the file. Stopping at the first
  # candidate that ISN'T followed by `/projects/*/index.md` would fall through to the
  # fresh-instance append path below and append the blanket block at EOF — after an
  # existing retained-project negation, silently reversing it (criterion 4).
  idxline=""
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ "$(sed -n "$((candidate+1))p" "$gi")" = "/projects/*/index.md" ]; then
      idxline="$candidate"
      break
    fi
  done <<EOF
$(grep -nxE "/(${AB_INDEX//./\\.}|index\.md)" "$gi" | cut -d: -f1)
EOF
  if [ -n "$idxline" ]; then
    start="$idxline"
    while [ "$start" -gt 1 ] && sed -n "$((start-1))p" "$gi" | grep -q '^#'; do
      start=$((start-1))
    done
    tmp="$gi.tmp.$$"
    {
      if [ "$start" -gt 1 ]; then
        sed -n "1,$((start-1))p" "$gi"
      fi
      printf '%s\n' "$IDX_BEGIN_MARK"
      cat "$idxbody"
      printf '%s\n' "$IDX_END_MARK"
      sed -n "$((idxline+2)),\$p" "$gi"
    } > "$tmp"
    mv "$tmp" "$gi"
  else
    # Genuinely fresh: no marker pair, and no legacy two-line block in the expected,
    # adjacent shape (or one reordered enough that guessing at it risks a bad splice —
    # left alone rather than guessed at). Append a new marker-wrapped block.
    {
      printf '%s\n' "$IDX_BEGIN_MARK"
      cat "$idxbody"
      printf '%s\n' "$IDX_END_MARK"
      printf '\n'
    } | gi_add_before
  fi
fi
rm -f "$idxbody"

# A .gitignore line is INERT for a file git already tracks, so on an instance whose
# index.md files are committed this change would silently do nothing. Report the exact
# command instead of running it: untracking a file is a commit the human makes and the
# other clone then pulls (which deletes their copy until the next tick or install
# re-creates it). Report-only, like RETIRED and prune-worktrees.sh.
if [ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ]; then
  tracked_idx="$( ( cd "$TARGET" && git ls-files -- "$AB_INDEX" 'projects/*/index.md' 2>/dev/null ) || true )"
  if [ -n "$tracked_idx" ]; then
    echo "Derived indexes are still tracked here (now gitignored, so the ignore is inert):"
    while IFS= read -r ti; do
      [ -n "$ti" ] || continue
      echo "  tracked $ti"
    done <<EOF
$tracked_idx
EOF
    echo "        To untrack them (keeps the files on disk), from $TARGET:"
    echo "          git rm --cached -- $AB_INDEX 'projects/*/index.md'"
    echo "        …then commit. Needed only if this bundle is shared by more than one human."
  fi
fi

# 4. Product-repo view — one symlink per repo under TARGET/repos/, so the peer
# repos are reachable from inside the instance without being nested in it.
# Best-effort by design: a fresh instance still has the placeholder reposRoot, and
# the script exits 0 with an explanation in that case rather than failing the
# install. Template copy, for the same reason as in --uninstall.
( cd "$TARGET" && bash "$BIN_DIR/link-repos.sh" ) \
  || echo "  warn  repos/ view not refreshed; run /${PLUGIN_NAME}:init again" >&2

# ===========================================================================
# 4b. THE TEAM ROSTER — offered once, on a first stamp, only at a terminal.
# ===========================================================================
#
# WHAT IT WRITES, AND WHY IT IS WORTH ASKING. Three values, all of them already
# specified in docs/sharing.md and SCHEMA.md → "Per-machine config overrides": the
# TRACKED `people` map (GitHub login → commit email, so commit-as.sh can author
# each clone's commits as the human running it), the TRACKED `defaultOwner` (so two
# clones of one bundle agree who *unowned* work belongs to instead of both dispatching
# it), and this clone's own gitignored `instance.config.local.json`, naming which login
# this clone IS. Hand-editing all three after the stamp was exactly the "several manual
# steps" shape that produced upgrade.sh: fine for whoever wrote it, an eight-step
# checklist for the next person. Nothing here redesigns that model — this is only the
# collection step it was missing.
#
# THREE GUARDS, each protecting a flow that already works:
#
#   1. FIRST_STAMP ONLY. upgrade.sh calls this installer on EVERY run, including its
#      non-interactive report-only mode, so an unguarded prompt would block every
#      upgrade. It reuses the FIRST_STAMP computed before seeding for AWAITING.md rather
#      than inventing a second notion of "new" — two notions are two things to get out
#      of step.
#   2. A TTY ONLY. Otherwise skip, leave the placeholder, and print the instruction.
#      This script has to stay safe to run from a script, from upgrade.sh, and from a
#      background agent with no terminal: a prompt nobody can see is a hang, and a hang
#      in a background agent is invisible.
#   3. NEVER OVERWRITE. Only the SEEDED placeholder is ever rewritten — the awk pass
#      below recognises the exact placeholder lines and refuses when it does not find
#      them — and the local file is written only when absent. That seeds-if-absent
#      contract is what makes this installer safe to re-run on a repo full of somebody's
#      work, so it is checked against the FILE rather than merely inferred from
#      FIRST_STAMP.
#
# And a fourth, which is really the verification rule: NO VERIFIER, NO WRITE. A broken
# instance.config.json breaks every later script in the instance, so the result is parsed
# back — before the temp file lands and again after it lands — and if neither jq nor
# python3 is on this machine the prompt is not offered at all. This codebase has a
# recorded incident of a script printing FIXED for a write that never landed
# (migrate-bundle.sh); verify-after-write is the standing answer, and a write we cannot
# verify is one we do not make.
#
# ONE BATCHED PROMPT, NOT N SERIAL ONES, and the reason is the failure mode rather than
# the keystrokes. Asked person-by-person, a roster accumulates state across reads: enter
# one pair, hit ctrl-C, and the instance is left with a map that resolves for one human
# and silently falls through for the other. Here the whole roster arrives as ONE block
# and nothing is written until a separate confirmation, so a partial answer cannot become
# a partial file — EOF, an interrupt, an unreadable line and a declined confirmation all
# take the same exit: write nothing, and say which happened. It is also two reads
# regardless of team size, which is the reasoning /new-project already uses to batch its
# capability questions.
#
# VALIDATION IS ALSO THE ESCAPING. Every login must match the GitHub-username rule
# task-owner.sh and commit-as.sh already apply (1-39 alphanumerics, single hyphens
# between them), and every address a deliberately conservative mail shape. Both reject
# quotes, backslashes, whitespace and control characters, so no ACCEPTED value can carry
# a character that would need JSON escaping: the file cannot be broken by its content,
# only by a bug in this block — which is what the parse-back catches.
TEAM_CFG="$TARGET/instance.config.json"
TEAM_LCFG="$TARGET/instance.config.local.json"

# How to do it by hand. Printed on every path that decides not to write, so a skip is
# never a dead end — the same "say the exact thing to do" contract as RETIRED.
team_manual_note() {
  echo "        Set it by hand instead (the full order is in $(doc_ref docs/sharing.md)):"
  echo "          instance.config.json        \"people\": { \"<login>\": \"<commit-email>\" }"
  echo "          instance.config.json        \"defaultOwner\": \"<login>\""
  echo "          instance.config.local.json  { \"ownerGithubUser\": \"<your-login>\" }"
}

# A GitHub username, by the same rule task-owner.sh's valid_user uses. Deliberately not a
# looser one: the value is compared against `owner:` in task documents and interpolated
# into a grep there, so a shape those readers refuse must be refused here too.
team_valid_login() { # <value>
  [ ${#1} -ge 1 ] && [ ${#1} -le 39 ] || return 1
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'
}
# A conservative address shape. It rejects plenty of technically-legal addresses, and
# that is the trade: an address nobody can type here can still be written by hand,
# whereas a quote or a backslash accepted here would land inside a JSON string.
team_valid_email() { # <value>
  [ ${#1} -ge 3 ] && [ ${#1} -le 254 ] || return 1
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$'
}

# Does this file parse as JSON?  0 = yes, 1 = NO, 2 = no parser on this machine.
# The three answers are distinguished on purpose: "we could not check" must never be
# reported as "it is fine" — the required-checks.sh discipline, applied to a write.
team_json_ok() { # <file>
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$1" >/dev/null 2>&1 && return 0
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 <"$1" && return 0
    return 1
  fi
  return 2
}

# The inner text of the `people` object, flattened onto one line. Same problem
# commit-as.sh's people_email() solves, and awk for the same reason it uses awk: this is
# a nested object, so a same-named key elsewhere in the file must not answer.
team_people_segment() { # <file>
  [ -f "$1" ] || return 0
  awk '
    !inb {
      i = index($0, "\"people\""); if (i == 0) next
      $0 = substr($0, i + 8)
      i = index($0, "{"); if (i == 0) next
      $0 = substr($0, i + 1); inb = 1
    }
    {
      e = index($0, "}")
      if (e) { printf "%s ", substr($0, 1, e - 1); exit }
      printf "%s ", $0
    }
  ' "$1"
}

# Read `defaultOwner` back out, with the same portable extractor the machinery uses.
team_read_owner() { # <file>
  [ -f "$1" ] || return 0
  sed -n 's/.*"defaultOwner"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
}

# Everything this claims to have written, checked by reading the file back. Structural
# validity is not enough: a JSON file can parse perfectly and still be missing the pair
# we said we added, which is the false-success shape this repo has already been bitten by.
team_verify() { # <file> <owner> <roster-file>
  local f="$1" who="$2" rf="$3" seg pair l e
  team_json_ok "$f" || return 1
  [ "$(team_read_owner "$f")" = "$who" ] || return 1
  seg="$(team_people_segment "$f")"
  # Exactly as many pairs as the roster has, so a placeholder that SURVIVED the rewrite
  # fails here: the object must have been replaced, not added to, and a stranger's login
  # left in a real roster is worse than a missing one. Counting colons is enough because
  # a validated login and address contain none.
  [ "$(printf '%s' "$seg" | tr -cd ':' | wc -c | tr -d ' ')" = "$(grep -c . "$rf")" ] || return 1
  while read -r l e; do
    [ -n "$l" ] || continue
    pair="\"$l\": \"$e\""
    printf '%s' "$seg" | grep -qF -- "$pair" || return 1
  done < "$rf"
  return 0
}

# ---------------------------------------------------------------- the three guards
team_ask=yes
[ "$FIRST_STAMP" = yes ] || team_ask=no
[ -f "$TEAM_CFG" ] || team_ask=no
# Guard 2. TEAM_SETUP_STDIN=1 is the ONE way past the TTY test, and it exists so the
# refusals here can be tested at all — the role SNAPSHOT_NOW plays for write-snapshot.sh.
# It must be set deliberately (nothing in upgrade.sh, in a role agent, or in a background
# agent's environment sets it), and even then it cannot hang: every read in forced mode
# carries a timeout.
TEAM_FORCED="${TEAM_SETUP_STDIN:-}"
if [ "$team_ask" = yes ] && [ ! -t 0 ] && [ "$TEAM_FORCED" != 1 ]; then
  team_ask=no
  echo "  skip  team roster (stdin is not a terminal, so nothing was asked)."
  team_manual_note
fi
# Guard 3, asked of the FILE. On a first stamp this is the seed verbatim, but
# seeds-if-absent is a property of the file rather than of FIRST_STAMP, and a value
# somebody already put there is never ours to replace — so this is checked, not inferred.
#
# What counts as "still the placeholder" is deliberately name-INDEPENDENT: an entry whose
# login equals the local part of its address at example.com (`"x": "x@example.com"`),
# which is the shape seed/instance.config.json ships and a shape no real roster has. A
# hard-coded `example-user-007` would stop recognising the placeholder the day somebody
# renames it — silently, since the failure is "the prompt is never offered again". The
# back-reference is why this is sed rather than awk (awk regexes have none).
if [ "$team_ask" = yes ]; then
  team_seg="$(team_people_segment "$TEAM_CFG")"
  team_rest="$(printf '%s' "$team_seg" | sed 's/"\([A-Za-z0-9-]\{1,\}\)"[[:space:]]*:[[:space:]]*"\1@example\.com"//g')"
  if [ -n "$(team_read_owner "$TEAM_CFG")" ] || printf '%s' "$team_rest" | grep -q '"'; then
    team_ask=no
    echo "  keep  team roster in instance.config.json (already set — left alone)"
  fi
fi
# Guard 4: no verifier, no write.
if [ "$team_ask" = yes ]; then
  team_vrc=0
  team_json_ok "$TEAM_CFG" || team_vrc=$?
  if [ "$team_vrc" = 2 ]; then
    team_ask=no
    echo "  skip  team roster (neither jq nor python3 here, so a write could not be verified)."
    team_manual_note
  elif [ "$team_vrc" != 0 ]; then
    team_ask=no
    echo "  skip  team roster (instance.config.json does not parse as JSON — fix that first)."
    team_manual_note
  fi
fi

# ---------------------------------------------------------------- the prompt
if [ "$team_ask" = yes ]; then
  # The prompt goes to STDERR and the result lines to stdout with the rest of the install
  # report. Two reasons: upgrade.sh filters this script's stdout line by line, and stderr
  # is unbuffered, so an interrupted prompt is still on screen where it happened.
  TEAM_ABORT=0
  team_on_int() { TEAM_ABORT=1; printf '\n' >&2; }
  trap team_on_int INT
  # One line into REPLY_LINE; non-zero on EOF, timeout or interrupt. The TRAP FLAG is
  # what distinguishes an interrupt from EOF, and it has to be: bash 3.2 (what macOS
  # ships) returns plain 1 from an interrupted `read`, exactly as it does at EOF —
  # measured — so an exit-status test would report ctrl-C as "input ended" and take the
  # wrong branch. Same status, different meaning: read the flag, not the code.
  team_read() {
    REPLY_LINE=""
    local rc=0
    if [ "$TEAM_FORCED" = 1 ]; then
      IFS= read -r -t 10 REPLY_LINE || rc=$?
    else
      IFS= read -r REPLY_LINE || rc=$?
    fi
    [ "$rc" = 0 ] || return 1
    [ "$TEAM_ABORT" = 0 ] || return 1
    return 0
  }

  TEAM_ROSTER="$(mktemp "${TMPDIR:-/tmp}/ai-bridge-roster.XXXXXX")"
  team_state=ask   # ask → write, or one of: eof, interrupt, declined, unreadable
  team_tries=0
  while [ "$team_state" = ask ]; do
    team_tries=$((team_tries+1))
    : > "$TEAM_ROSTER"
    team_n=0
    {
      echo ""
      echo "Team roster for this instance — asked once, on a first stamp."
      echo "  One person per line:  <github-login> <commit-email>"
      echo "  YOURSELF FIRST: your login becomes this instance's defaultOwner and this"
      echo "  clone's identity in instance.config.local.json."
      echo "  An empty line ends the list. Nothing is written until you confirm it, and"
      echo "  ctrl-C, ctrl-D or an empty first line all write nothing at all."
    } >&2
    while :; do
      printf '  %d> ' "$((team_n+1))" >&2
      if ! team_read; then
        if [ "$TEAM_ABORT" = 0 ]; then team_state=eof; else team_state=interrupt; fi
        break
      fi
      # Surrounding whitespace is a typo, not an answer — stripped before deciding whether
      # the line is empty, or a stray space would end the list without meaning to.
      team_line="$(printf '%s' "$REPLY_LINE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -n "$team_line" ] || break
      team_login="$(printf '%s' "$team_line" | awk '{print $1}')"
      team_email="$(printf '%s' "$team_line" | awk '{print $2}')"
      team_extra="$(printf '%s' "$team_line" | awk '{print $3}')"
      if [ -n "$team_extra" ] || [ -z "$team_email" ]; then
        echo "        ✗ expected exactly two fields: <github-login> <commit-email>" >&2
        team_state=unreadable; break
      fi
      if ! team_valid_login "$team_login"; then
        echo "        ✗ '$team_login' is not a GitHub username (1-39 alphanumerics, single hyphens between them)" >&2
        team_state=unreadable; break
      fi
      if ! team_valid_email "$team_email"; then
        echo "        ✗ '$team_email' is not an address this can write safely" >&2
        team_state=unreadable; break
      fi
      if grep -q "^$team_login " "$TEAM_ROSTER"; then
        echo "        ✗ '$team_login' is already in this roster" >&2
        team_state=unreadable; break
      fi
      printf '%s %s\n' "$team_login" "$team_email" >> "$TEAM_ROSTER"
      team_n=$((team_n+1))
    done
    if [ "$team_state" = unreadable ]; then
      # Re-ask the whole block rather than patching the one line: the block is the unit
      # that gets confirmed, so a half-corrected block is the state this design avoids.
      if [ "$team_tries" -lt 3 ]; then
        echo "        Let's take the list again from the top." >&2
        team_state=ask
        continue
      fi
      break
    fi
    [ "$team_state" = ask ] || break
    if [ "$team_n" -eq 0 ]; then team_state=declined; break; fi

    TEAM_OWNER="$(head -n1 "$TEAM_ROSTER" | awk '{print $1}')"
    {
      echo ""
      echo "  About to write:"
      echo "    instance.config.json        defaultOwner = $TEAM_OWNER"
      while read -r team_l team_e; do
        [ -n "$team_l" ] && echo "                                people[$team_l] = $team_e"
      done < "$TEAM_ROSTER"
      echo "    instance.config.local.json  ownerGithubUser = $TEAM_OWNER  (gitignored)"
      printf '  Write it? [y/N] '
    } >&2
    if ! team_read; then
      if [ "$TEAM_ABORT" = 0 ]; then team_state=eof; else team_state=interrupt; fi
      break
    fi
    case "$(printf '%s' "$REPLY_LINE" | tr '[:upper:]' '[:lower:]')" in
      y|yes) team_state=write ;;
      *)     team_state=declined ;;
    esac
  done
  trap - INT

  case "$team_state" in
    write) ;;
    interrupt)
      rm -f "$TEAM_ROSTER"
      echo "  roster: nothing written (interrupted). No partial map was left behind."
      team_manual_note
      # The install itself is complete — only the roster was skipped — but ctrl-C should
      # still feel like it stopped something, so this exits with the conventional SIGINT
      # code rather than pretending nothing happened. Everything below on a FIRST stamp is
      # a no-op anyway: nothing is retired, and a fresh seed validates clean.
      exit 130 ;;
    *)
      rm -f "$TEAM_ROSTER"
      case "$team_state" in
        eof)        echo "  roster: nothing written (input ended)." ;;
        unreadable) echo "  roster: nothing written (could not read the list)." ;;
        *)          echo "  roster: nothing written (declined)." ;;
      esac
      team_manual_note ;;
  esac
fi

# ---------------------------------------------------------------- the write
if [ "${team_state:-}" = write ]; then
  # The tracked half, as ONE awk pass that only ever replaces lines it RECOGNISES:
  # `"defaultOwner": null,`, the `$people` note, and a `people` object holding nothing but
  # placeholder entries. Anything else — a drifted seed, a roster somebody already wrote —
  # makes it exit 3, and then nothing is written at all. That is guard 3 and a seed-drift
  # guard in one mechanism, and it degrades to "print the instruction", never to a
  # half-rewritten file.
  team_lines="$(mktemp "${TMPDIR:-/tmp}/ai-bridge-people.XXXXXX")"
  team_total="$(grep -c . "$TEAM_ROSTER" || true)"
  team_i=0
  while read -r team_l team_e; do
    [ -n "$team_l" ] || continue
    team_i=$((team_i+1))
    if [ "$team_i" -lt "$team_total" ]; then
      printf '    "%s": "%s",\n' "$team_l" "$team_e" >> "$team_lines"
    else
      printf '    "%s": "%s"\n' "$team_l" "$team_e" >> "$team_lines"
    fi
  done < "$TEAM_ROSTER"

  team_note="Collected by /${PLUGIN_NAME}:init when this bundle was stamped: GitHub login -> commit email, for THIS instance. The address is PER-INSTANCE, not per-person -- it says which entity the work belongs to -- so never derive it from the login, and never move it into instance.config.local.json (that file says which login this clone IS). Read by commit-as.sh via ownerGithubUser; see $AB_SCHEMA 'Per-machine config overrides' and docs/sharing.md. Edit by hand to add or remove someone."

  # Temp file BESIDE the target, carrying the target's mode: mktemp creates 0600, so a
  # rename from $TMPDIR would silently make this config 0600, and a cross-filesystem mv
  # degrades to copy-and-remove, where an interruption leaves a half-written file. Same
  # rule as migrate-bundle.sh.
  team_tmp="$TEAM_CFG.tmp.$$"
  team_orig="$TEAM_CFG.orig.$$"
  cp -p "$TEAM_CFG" "$team_tmp" 2>/dev/null || cp "$TEAM_CFG" "$team_tmp"
  cp -p "$TEAM_CFG" "$team_orig" 2>/dev/null || cp "$TEAM_CFG" "$team_orig"
  team_rc=0
  awk -v owner="$TEAM_OWNER" -v note="$team_note" -v rf="$team_lines" '
    /^[[:space:]]*"defaultOwner"[[:space:]]*:[[:space:]]*null[[:space:]]*,[[:space:]]*$/ {
      printf "  \"defaultOwner\": \"%s\",\n", owner; dow++; next
    }
    /^[[:space:]]*"\$people"[[:space:]]*:/ { printf "  \"$people\": \"%s\",\n", note; next }
    /^[[:space:]]*"people"[[:space:]]*:[[:space:]]*\{[[:space:]]*$/ {
      print "  \"people\": {"
      while ((getline line < rf) > 0) print line
      close(rf)
      print "  },"
      ppl++; inppl = 1; next
    }
    inppl {
      # Guard 3 above has already established that this object is the untouched
      # placeholder, so these lines are being DISCARDED, not judged: all this has to do
      # is refuse a shape it cannot safely replace. A flat "key": "value" pair is
      # discarded; anything else — a nested object, an array, a comment — sets bad, and
      # then nothing is written at all.
      if ($0 ~ /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*,?[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$/) { inppl = 0; next }
      bad = 1; next
    }
    { print }
    END { if (bad || dow != 1 || ppl != 1) exit 3 }
  ' "$TEAM_CFG" > "$team_tmp" || team_rc=$?

  if [ "$team_rc" != 0 ]; then
    rm -f "$team_tmp" "$team_orig" "$team_lines" "$TEAM_ROSTER"
    echo "  roster: nothing written — instance.config.json does not carry the placeholder" >&2
    echo "          roster this expected to replace, so it was left exactly as it is." >&2
    team_manual_note >&2
  elif ! team_verify "$team_tmp" "$TEAM_OWNER" "$TEAM_ROSTER"; then
    # Verified BEFORE the rename, so an unparseable file never lands at all.
    rm -f "$team_tmp" "$team_orig" "$team_lines" "$TEAM_ROSTER"
    echo "error: the roster this would have written does not verify, so instance.config.json" >&2
    echo "       was left exactly as it is. That is a bug in init-bundle.sh, not something you did." >&2
    team_manual_note >&2
    exit 1
  else
    mv "$team_tmp" "$TEAM_CFG"
    # And verified AGAIN once it lands. A write this script only *believes* it made is the
    # failure migrate-bundle.sh recorded: FIXED printed for an insert that silently
    # no-opped. A false success is worse than the error it claims to fix.
    if ! team_verify "$TEAM_CFG" "$TEAM_OWNER" "$TEAM_ROSTER"; then
      mv "$team_orig" "$TEAM_CFG"
      rm -f "$team_lines" "$TEAM_ROSTER"
      echo "error: instance.config.json did not verify after the write, and has been" >&2
      echo "       restored to the file that was there before. Nothing was kept." >&2
      team_manual_note >&2
      exit 1
    fi
    rm -f "$team_orig"
    echo "  wrote instance.config.json (people: $team_total, defaultOwner: $TEAM_OWNER)"
  fi
  rm -f "$team_lines"

  # The local half — this clone's identity. Written only when absent, like every other
  # seeded file, and gitignored (step 3b above appends the line), so it never becomes one
  # human's identity inside the other's clone.
  if [ -e "$TEAM_LCFG" ]; then
    echo "  keep  instance.config.local.json (exists — this clone's identity left alone)"
  else
    team_ltmp="$TEAM_LCFG.tmp.$$"
    {
      echo "{"
      echo "  \"\$schema\": \"Per-machine overrides for THIS clone -- gitignored, never committed. Which GitHub login this clone is, what each model tier costs THIS human, plus any absolute path or address that cannot be right on both machines. See $AB_SCHEMA, 'Per-machine config overrides'.\","
      printf '  "ownerGithubUser": "%s"\n' "$TEAM_OWNER"
      echo "}"
    } > "$team_ltmp"
    if team_json_ok "$team_ltmp" \
       && [ "$(sed -n 's/.*"ownerGithubUser"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$team_ltmp" | head -n1)" = "$TEAM_OWNER" ]; then
      mv "$team_ltmp" "$TEAM_LCFG"
      echo "  wrote instance.config.local.json (ownerGithubUser: $TEAM_OWNER)"
    else
      rm -f "$team_ltmp"
      echo "error: instance.config.local.json did not verify, so nothing was written." >&2
      echo "       Create it by hand: { \"ownerGithubUser\": \"$TEAM_OWNER\" }" >&2
    fi
  fi
  rm -f "$TEAM_ROSTER"
fi

# ===========================================================================
# 4c. THIS CLONE'S IDENTITY — write instance.config.local.json when it is ABSENT.
# ===========================================================================
#
# WHY A SECOND BLOCK AND NOT 4b. A clone of a shared bundle is not a FIRST stamp, so 4b's
# roster prompt never runs there and every second human hand-wrote the same three keys
# (docs/sharing.md). All three are knowable on the machine running this, so they are
# DERIVED — and a value that cannot be derived is NAMED on a `needs` line, never guessed.
# `--owner/--email/--repos-root` supply one without a terminal, which is how
# /<plugin>:init hands a human's answer back to this script.
#
# ABSENT ONLY, and that is the whole guard: an existing local file is somebody's config,
# 4e's normaliser owns its shape, and a file already carrying the three keys makes this
# step print nothing at all.
ID_LCFG="$TARGET/instance.config.local.json"
ID_NOTE="Per-machine overrides for THIS clone -- gitignored, never committed. Which GitHub login this clone is, what each model tier costs THIS human, plus any absolute path or address that cannot be right on both machines. See $AB_SCHEMA, 'Per-machine config overrides'."

id_manual_note() {
  echo "        Set them by hand instead ($AB_SCHEMA → 'Per-machine config overrides'):"
  echo "          instance.config.local.json  { \"ownerGithubUser\": \"<login>\","
  echo "                                        \"authorEmail\": \"<address>\","
  echo "                                        \"reposRoot\": \"<absolute path>\" }"
}
# One string value out of a flat JSON file.
id_read() { # <key> <file>
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" | head -n1
}
# What the TRACKED config already answers for one of the three keys. A value a human put
# there is never shadowed by a derived one — local wins over tracked, so writing a guess
# here would silently override their answer and leave 4e's normaliser nothing to move.
# The seed's own example.com address is a placeholder, not an answer.
id_tracked() { # <key>
  [ -f "$TEAM_CFG" ] || return 0
  local v; v="$(id_read "$1" "$TEAM_CFG")"
  case "$v" in *@example.com) v="" ;; esac
  printf '%s' "$v"
}
# A path this can write into a JSON string, and that the readers will accept: absolute,
# and free of the three characters that would need escaping.
id_valid_path() { # <value>
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *'"'*|*'\'*|*'
'*) return 1 ;;
  esac
  return 0
}

if [ -e "$ID_LCFG" ]; then
  # Never rewritten. Only ever reported, so a clone that already has the file but not the
  # keys still learns which ones are missing.
  id_absent=""
  for id_k in ownerGithubUser authorEmail reposRoot; do
    grep -q "\"$id_k\"[[:space:]]*:" "$ID_LCFG" 2>/dev/null || id_absent="$id_absent $id_k"
  done
  if [ -n "$id_absent" ]; then
    echo "  keep  instance.config.local.json (exists — left alone; it has no$id_absent)"
    if [ -n "$ID_OWNER_FLAG$ID_EMAIL_FLAG$ID_REPOS_FLAG" ]; then
      echo "        --owner/--email/--repos-root only apply when that file is absent."
    fi
  fi
else
  # ------------------------------------------------------------- derive, or report
  # A flag wins over everything (the human said it), then a value the tracked file already
  # answers with is left alone, and only what is left is derived.
  id_answered=""
  id_owner=""
  if [ -n "$ID_OWNER_FLAG" ]; then
    if team_valid_login "$ID_OWNER_FLAG"; then id_owner="$ID_OWNER_FLAG"
    else echo "  warn  --owner '$ID_OWNER_FLAG' is not a GitHub username; not written." >&2
    fi
  elif [ -n "$(id_tracked ownerGithubUser)" ]; then
    id_answered="$id_answered ownerGithubUser"
  else
    # gh first (it knows which account is authenticated), then the git config key a human
    # may have set for the same purpose. Both are best-effort and neither may hang the
    # stamp, so a failure of either is just an empty answer.
    if command -v gh >/dev/null 2>&1; then
      id_owner="$(gh api user --jq .login 2>/dev/null || true)"
    fi
    [ -n "$id_owner" ] || id_owner="$(git -C "$TARGET" config --get github.user 2>/dev/null || true)"
    team_valid_login "$id_owner" || id_owner=""
  fi

  id_email=""
  if [ -n "$ID_EMAIL_FLAG" ]; then
    if team_valid_email "$ID_EMAIL_FLAG"; then id_email="$ID_EMAIL_FLAG"
    else echo "  warn  --email '$ID_EMAIL_FLAG' is not an address this can write safely; not written." >&2
    fi
  elif [ -n "$(id_tracked authorEmail)" ]; then
    id_answered="$id_answered authorEmail"
  else
    # The tracked `people` map first: that address says which ENTITY this instance's work
    # belongs to, and is never derived from the login (docs/sharing.md).
    if [ -n "$id_owner" ] && [ -f "$TEAM_CFG" ]; then
      id_seg="$(team_people_segment "$TEAM_CFG")"
      id_email="$(printf '%s' "$id_seg" \
        | sed -n "s/.*\"$id_owner\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1)"
    fi
    [ -n "$id_email" ] || id_email="$(git -C "$TARGET" config --get user.email 2>/dev/null || true)"
    team_valid_email "$id_email" || id_email=""
  fi

  id_repos=""
  if [ -n "$ID_REPOS_FLAG" ]; then
    if id_valid_path "$ID_REPOS_FLAG"; then id_repos="$ID_REPOS_FLAG"
    else echo "  warn  --repos-root '$ID_REPOS_FLAG' is not an absolute path; not written." >&2
    fi
  elif [ -n "$(id_tracked reposRoot)" ]; then
    id_answered="$id_answered reposRoot"
  else
    # The bundle's PARENT: the instance and the product repos are physical peers on disk
    # (link-repos.sh), so the directory holding this bundle is reposRoot on every machine
    # that follows the documented layout.
    id_repos="$(cd "$TARGET/.." 2>/dev/null && pwd || true)"
    id_valid_path "$id_repos" || id_repos=""
    [ "$id_repos" != "$TARGET" ] || id_repos=""
  fi

  # ------------------------------------------------------------- no verifier, no write
  id_write=yes
  id_vrc=0
  team_json_ok "$TEAM_CFG" >/dev/null 2>&1 || id_vrc=$?
  if [ "$id_vrc" = 2 ]; then
    id_write=no
    echo "  skip  instance.config.local.json (neither jq nor python3 here, so a write"
    echo "        could not be verified)."
    id_manual_note
  elif [ -z "$id_owner$id_email$id_repos" ]; then
    id_write=no
    # Silent when the tracked file answers all three: there is nothing to derive and
    # nothing missing, which is not a skip worth a line.
    if [ "$(printf '%s\n' $id_answered | grep -c . || true)" != 3 ]; then
      echo "  skip  instance.config.local.json (none of the three values could be derived here)."
      id_manual_note
    fi
  fi

  if [ "$id_write" = yes ]; then
    id_pairs="$(mktemp "${TMPDIR:-/tmp}/ai-bridge-local.XXXXXX")"
    [ -z "$id_owner" ] || printf '  "ownerGithubUser": "%s"\n' "$id_owner" >> "$id_pairs"
    [ -z "$id_email" ] || printf '  "authorEmail": "%s"\n' "$id_email" >> "$id_pairs"
    [ -z "$id_repos" ] || printf '  "reposRoot": "%s"\n' "$id_repos" >> "$id_pairs"
    # Temp file BESIDE the target, for the reason 4b states: a rename out of $TMPDIR
    # carries mktemp's 0600, and a cross-filesystem mv is copy-and-remove.
    id_tmp="$ID_LCFG.tmp.$$"
    {
      echo "{"
      printf '  "$schema": "%s",\n' "$ID_NOTE"
      awk 'NR > 1 { print prev "," } { prev = $0 } END { if (NR) print prev }' "$id_pairs"
      echo "}"
    } > "$id_tmp"
    rm -f "$id_pairs"

    # Parsed back and read back BEFORE it lands: a file can parse perfectly and still be
    # missing the pair we claim to have written (migrate-bundle.sh's recorded incident).
    id_ok=yes
    team_json_ok "$id_tmp" || id_ok=no
    for id_k in ownerGithubUser:"$id_owner" authorEmail:"$id_email" reposRoot:"$id_repos"; do
      id_want="${id_k#*:}"; [ -n "$id_want" ] || continue
      [ "$(id_read "${id_k%%:*}" "$id_tmp")" = "$id_want" ] || id_ok=no
    done
    if [ "$id_ok" != yes ] || ! mv "$id_tmp" "$ID_LCFG"; then
      rm -f "$id_tmp"
      echo "error: instance.config.local.json did not verify, so nothing was written." >&2
      id_manual_note >&2
    else
      id_said=""
      [ -z "$id_owner" ] || id_said="ownerGithubUser: $id_owner"
      [ -z "$id_email" ] || id_said="${id_said:+$id_said, }authorEmail: $id_email"
      [ -z "$id_repos" ] || id_said="${id_said:+$id_said, }reposRoot: $id_repos"
      echo "  wrote instance.config.local.json ($id_said)"
      # reposRoot only became readable now, so step 4 above had nothing to link.
      if [ -n "$id_repos" ]; then
        ( cd "$TARGET" && bash "$BIN_DIR/link-repos.sh" ) \
          || echo "  warn  repos/ view not refreshed; run /${PLUGIN_NAME}:init again" >&2
      fi
    fi
  fi

  # What it could NOT derive, named one key at a time. `needs` is the marker
  # /<plugin>:init reads: one batched question for exactly these, then re-run with the
  # flags. Never a guess, and never a question about a value that was derived.
  id_needs() { # <key> <value> <flag>
    [ -z "$2" ] || return 0
    case " $id_answered " in *" $1 "*) return 0 ;; esac
    echo "  needs  $1 — re-run with: $3"
  }
  id_needs ownerGithubUser "$id_owner" "--owner <github-login>"
  id_needs authorEmail     "$id_email" "--email <commit-address>"
  id_needs reposRoot       "$id_repos" "--repos-root <absolute path>"
fi

# ===========================================================================
# 4d. PER-MACHINE SPEND — seed `models` and `roleTiers` into the local file.
# ===========================================================================
#
# WHY THE INSTALLER WRITES THEM AT ALL. These two keys decide what every dispatched
# agent COSTS, and the bill is per human rather than per bundle (SCHEMA.md →
# "Per-machine config overrides"). Left only in the TRACKED `instance.config.json`,
# the map one human committed is the map every clone of that bundle pays for, and the
# session banner's FROM column says `tracked` — which is the honest report of a
# decision the reader did not make. Seeding them here makes the per-machine file the
# one in force on every machine, so the banner reads `local` and the human can see
# whose decision is operating.
#
# THE TRACKED KEYS DELIBERATELY STAY, AS A FALLBACK. That is the migration design and
# not an oversight. `resolve-model.sh` with NEITHER source resolves to nothing,
# and a caller that gets nothing inherits the session model — for every role at once,
# with no error. Removing the tracked keys in the same change would open exactly that
# window on any instance this step had not yet reached, and a merge is not a stamp: an
# instance is only re-stamped when somebody runs this script. Keeping them means there
# is no ordering in which the pair resolves to nothing. Local wins wherever it exists;
# tracked answers wherever it does not; this step is what makes local exist.
#
# SEEDS PER KEY, AND NEVER RECONCILES. A key already present in the local file is left
# exactly as it is — including one explicitly `null`, which is how SCHEMA.md says a
# human UNSETS an inherited key, and including a PARTIAL map, which
# `resolve-config.sh` merges entry by entry over the tracked one. Topping a partial map
# up to the full set would be reconciling a human's edit, which this installer does not
# do anywhere else either. So the unit is the key: present ⇒ untouched, absent ⇒ seeded.
#
# PYTHON3 OR NOTHING, and the reason is that the only reader of these keys is
# `resolve-config.sh`, which requires python3 outright. On a machine without it
# a seeded value would be a value nothing can read, so the honest outcome is to say so
# and leave the tracked fallback answering — the same "no verifier, no write" rule the
# roster block above applies, for the same reason. Never silent: the skip prints.
SPEND_TCFG="$TARGET/instance.config.json"
SPEND_LCFG="$TARGET/instance.config.local.json"

spend_manual_note() {
  echo "        Set them by hand instead ($AB_SCHEMA → 'Per-machine config overrides'):"
  echo "          instance.config.local.json  { \"models\": { \"deep\": \"opus\", … },"
  echo "                                        \"roleTiers\": { \"software-engineer\": \"deep\", … } }"
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip  per-machine models/roleTiers (no python3 here, and resolve-config.sh"
  echo "        needs it to read them at all — the tracked instance.config.json still answers)."
  spend_manual_note
else
  # Temp file BESIDE the target for the reason the roster block states: a rename out of
  # $TMPDIR would carry mktemp's 0600, and a cross-filesystem mv degrades to
  # copy-and-remove, where an interruption leaves a half-written config.
  spend_tmp="$SPEND_LCFG.tmp.$$"
  spend_rc=0
  spend_out="$(python3 - "$SPEND_TCFG" "$SPEND_LCFG" "$spend_tmp" <<'PY'
import json, os, sys

tracked_path, local_path, tmp_path = sys.argv[1], sys.argv[2], sys.argv[3]

# THE DOCUMENTED DEFAULTS, and this list is the fallback of a fallback: it is used only
# when the tracked file has no such key at all (an instance whose config predates it, or
# one somebody trimmed). Keep it in step with seed/instance.config.json and with
# SCHEMA.md — tests/local-tier-seed.test.sh asserts the two agree, so drift fails there
# rather than on a machine.
DEFAULTS = {
    "models": {"light": "haiku", "standard": "sonnet", "deep": "opus", "apex": "fable"},
    "roleTiers": {
        "project-manager": "deep",
        "software-engineer": "deep",
        "devops-engineer": "deep",
        "qa-reviewer": "deep",
        "cataloguer": "standard",
        "plan-architect": "apex",
        "auditor": "deep",
        "explorer": "light",
    },
}
SCHEMA_NOTE = (
    "Per-machine overrides for THIS clone -- gitignored, never committed. Which GitHub "
    "login this clone is, what each model tier costs THIS human, plus any absolute path "
    "or address that cannot be right on both machines. See " + os.environ["AB_SCHEMA"]
    + ", 'Per-machine config overrides'."
)


def load(path):
    """A layer, or None when it is missing/unreadable/not an object. None is NOT {}:
    an unreadable local file must stop this step rather than be overwritten with a
    fresh one, because the thing we cannot read is somebody's hand-edited config."""
    if not os.path.exists(path):
        return None
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        return False
    return data if isinstance(data, dict) else False


local = load(local_path)
if local is False:
    print("unreadable")
    sys.exit(3)

tracked = load(tracked_path)
if tracked in (None, False):
    tracked = {}

existed = local is not None
if not existed:
    local = {"$schema": SCHEMA_NOTE}

seeded = []
for key in ("models", "roleTiers"):
    # `in`, not a truth test: a key present and null is a deliberate unset, and a key
    # present and empty is a deliberate empty map. Both are answers, so both are kept.
    if key in local:
        continue
    value = tracked.get(key)
    if not isinstance(value, dict) or not value:
        value = DEFAULTS[key]
    local[key] = dict(value)
    seeded.append(key)

if not seeded:
    print("keep")
    sys.exit(1)

with open(tmp_path, "w") as fh:
    json.dump(local, fh, indent=2)
    fh.write("\n")

# The existing file's MODE travels with its content. A fresh temp takes the umask, so
# rewriting a file somebody had tightened to 0600 would quietly widen it — the same
# reason the roster block above copies the target's mode with `cp -p` rather than
# renaming a 0600 mktemp over a config.
if existed:
    try:
        os.chmod(tmp_path, os.stat(local_path).st_mode & 0o7777)
    except OSError:
        pass

# Parsed back BEFORE it lands, and checked for the pairs we claim to have written — a
# file can parse perfectly and still be missing them, which is the false-success shape
# this codebase has already been bitten by (migrate-bundle.sh).
with open(tmp_path) as fh:
    back = json.load(fh)
for key in seeded:
    if back.get(key) != local[key]:
        print("verify-failed")
        sys.exit(4)

print("wrote %s" % " ".join(seeded))
PY
  )" || spend_rc=$?

  case "${spend_out%% *}" in
    wrote)
      spend_keys="${spend_out#wrote }"
      if mv "$spend_tmp" "$SPEND_LCFG"; then
        echo "  wrote instance.config.local.json ($spend_keys — this machine's model spend)"
      else
        rm -f "$spend_tmp"
        echo "  warn  could not write instance.config.local.json; the tracked models/roleTiers" >&2
        echo "        still answer, so nothing is degraded." >&2
        spend_manual_note >&2
      fi ;;
    keep)
      echo "  keep  instance.config.local.json models/roleTiers (already set — left alone)" ;;
    unreadable)
      rm -f "$spend_tmp"
      echo "  warn  instance.config.local.json does not parse as JSON, so models/roleTiers" >&2
      echo "        were NOT seeded and the tracked map is what answers. Fix that file." >&2 ;;
    *)
      rm -f "$spend_tmp"
      echo "  warn  models/roleTiers were not seeded (installer exit $spend_rc); the tracked" >&2
      echo "        instance.config.json still answers, so no role is left without a model." >&2
      spend_manual_note >&2 ;;
  esac

  # AND THEN ASK THE REAL READER, every time — not only when something was written.
  # The property this whole step exists for is "every role this instance dispatches
  # resolves to a model", and that is a question for `resolve-model.sh`, not for the
  # bytes we just wrote. A role that resolves to nothing would otherwise inherit the
  # session model in silence, which is the one outcome this section is against; so it
  # is named here, at the only moment a human is reading this script's output.
  spend_unresolved=""
  # `|| true` on the ASSIGNMENT, not inside it: under `set -e` with `pipefail` a pipeline
  # assigned to a variable outside an `if` condition kills the whole script when any stage
  # exits non-zero, and an instance with no roleTiers at all is exactly that case. Recorded
  # in this codebase once already (a `grep|head|cut` assignment beside a guard that was fine).
  spend_roles="$(bash "$BIN_DIR/resolve-config.sh" --instance "$TARGET" --dump 2>/dev/null \
                 | awk -F'\t' '$2=="roleTiers" && $3!="" { print $3 }')" || true
  while IFS= read -r spend_role; do
    [ -n "$spend_role" ] || continue
    if [ -z "$(bash "$BIN_DIR/resolve-model.sh" --instance "$TARGET" "$spend_role" 2>/dev/null)" ]; then
      spend_unresolved="$spend_unresolved $spend_role"
    fi
  done <<EOF
$spend_roles
EOF
  if [ -z "$spend_roles" ]; then
    # THE EMPTY CASE IS THE LOUDEST ONE, and it is the case a per-role loop cannot see:
    # with `roleTiers` resolving to nothing at all there are no roles to iterate, so a
    # loop alone reports success by having nothing to complain about. That is precisely
    # the silent degradation this section exists against — every dispatch inherits the
    # session model, and the instance looks fine. Reachable by design, since a local
    # `"roleTiers": null` is the documented way to unset an inherited key.
    echo "  warn  this instance has NO roleTiers at all, in either config file, so every" >&2
    echo "        dispatched agent will resolve to NO model and inherit whatever model the" >&2
    echo "        session happens to be on." >&2
    spend_manual_note >&2
  elif [ -n "$spend_unresolved" ]; then
    echo "  warn  these roles resolve to NO model, so a dispatch inherits whatever the" >&2
    echo "        session happens to be:$spend_unresolved" >&2
    echo "        Give each one's tier an entry in \`models\`, in instance.config.local.json." >&2
  fi
fi

# ===========================================================================
# 4e. THE TWO CONFIG FILES — report what is out of place, apply when asked.
# ===========================================================================
#
# Nothing else looks at both files together: the validator sees no error here, and a
# plugin update cannot reach a bundle's data at all. So keys drift into the file they do
# not belong in, keys added since the bundle was stamped stay absent, and three bundles
# end up in three key orders. The stamp is the moment to say so. REPORTING is the default
# because the fix rewrites a TRACKED file, which is the human's call to make;
# `--normalise-config`, or a yes at a terminal, is that call. Silent on a clean pair.
NORMALISER="$BIN_DIR/normalise-config.sh"
if [ -f "$NORMALISER" ]; then
  norm_rc=0
  bash "$NORMALISER" "$TARGET" || norm_rc=$?
  if [ "$norm_rc" = 1 ]; then
    norm_apply="$NORMALISE_CONFIG"
    # NORMALISE_CONFIG_STDIN=1 is the one way past the TTY test, and it exists so this
    # prompt can be tested — the same role TEAM_SETUP_STDIN plays for the roster block.
    if [ "$norm_apply" = 0 ] && { [ -t 0 ] || [ "${NORMALISE_CONFIG_STDIN:-}" = 1 ]; }; then
      printf '  Apply them now? [y/N] ' >&2
      norm_reply=""
      IFS= read -r -t 30 norm_reply || norm_reply=""
      case "$norm_reply" in [Yy]|[Yy][Ee][Ss]) norm_apply=1 ;; esac
    fi
    if [ "$norm_apply" = 1 ]; then
      bash "$NORMALISER" "$TARGET" --apply --quiet || true
    fi
  fi
fi

echo "Done. Seed content in place; this bundle carries no machinery and no template links."
echo "Next: edit instance.config.json, then run /${PLUGIN_NAME}:dispatch from this directory."
echo "      (Set reposRoot in instance.config.local.json — it is per-machine — then"
echo "       re-run /${PLUGIN_NAME}:init to fill in repos/.)"
# THE OTHER HALF, and it is not this script's to install. Every slash command ships in the
# loopd PLUGIN now, per machine rather than per instance, so a perfect stamp still
# leaves a bundle nobody can drive if the plugin is missing — and the only symptom is
# "unknown command", which accuses nothing. Printed unconditionally: this script cannot see
# what Claude Code has installed, and a nudge that fires only when it is sure would never
# fire at all. See docs/operations.md § 1.
echo "      (The commands are the loopd PLUGIN, installed once per machine:"
echo "       /plugin marketplace add cbmono/loopd, then"
echo "       /plugin install ${PLUGIN_NAME}@${PLUGIN_MARKETPLACE} — then restart Claude Code."
echo "       Or /plugin install ${PLUGIN_NAME}-all@${PLUGIN_MARKETPLACE}: core plus every companion, one command.)"

# Retired seed content — REPORT, never remove. See RETIRED for why the conversion sweep
# above may delete and this may not: a machinery symlink into a template checkout has one
# possible meaning; a seed file the human has owned since it was copied does not. Absence
# of the manifest, or an empty one, is silence — not an error.
RETIRED_LIST="$PLUGIN_ROOT/RETIRED"
if [ -f "$RETIRED_LIST" ]; then
  retired_found=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    # <path><TAB><reason>; a line with no tab is all path and no reason.
    rpath="${line%%	*}"
    reason="${line#*	}"
    [ "$reason" = "$rpath" ] && reason="no longer shipped by the template"
    [ -n "$rpath" ] || continue
    # Refuse a path that escapes the instance root. The manifest is our own file, so this
    # is not about a hostile author — it is that `../victim.md` would make the printed
    # `rm` command operate OUTSIDE the instance, and a human pasting a command this script
    # handed them has every reason to trust it. Reject rather than normalise: a path with
    # `..` in it is a mistake in the manifest, and silently rewriting a mistake into a
    # different path is how you delete the wrong file.
    case "$rpath" in
      /*|~*)      echo "  warn  RETIRED entry ignored (not instance-relative): $rpath" >&2; continue ;;
      ..|../*|*/..|*/../*) echo "  warn  RETIRED entry ignored (escapes the instance root): $rpath" >&2; continue ;;
    esac
    # Only ever report something that is actually there, and only a real file — a
    # leftover symlink is step 2b's business, not this list's.
    if [ -f "$TARGET/$rpath" ] && [ ! -L "$TARGET/$rpath" ]; then
      [ "$retired_found" -eq 0 ] && echo "Retired content still present (yours to keep or delete):"
      retired_found=$((retired_found+1))
      echo "  stale $rpath — $reason"
      echo "        rm $(printf '%q' "$TARGET/$rpath")"
    fi
  done < "$RETIRED_LIST"
fi

# One report-only nudge for a stale session-defaults import.
#
# seed/CLAUDE.md used to end with `@~/.claude/claude-defaults.md` — a file only a
# SEPARATE repo's installer ever created, and the one hard dependency this template had
# on it. Every instance inherited the line, and on a machine that never ran that
# installer it resolved to nothing: a missing @import is a silent no-op, which is exactly
# why nobody noticed. The section is inlined in seed/CLAUDE.md now, but seed content is
# copied only when ABSENT, so an instance stamped earlier keeps the dead import forever.
#
# Report it, never rewrite it: CLAUDE.md is instance data the human owns and has very
# likely edited around. Same contract as RETIRED — say the exact thing to do, once.
# The pattern is ANCHORED to the start of a line: seed/CLAUDE.md's replacement section
# explains itself by quoting the old import inside an HTML comment, and an unanchored
# match would nag every freshly-stamped instance about a line it does not have.
if [ -f "$TARGET/CLAUDE.md" ] \
   && grep -qE '^[[:space:]]*@~/\.claude/claude-defaults\.md[[:space:]]*$' "$TARGET/CLAUDE.md"; then
  echo "This instance's CLAUDE.md still imports ~/.claude/claude-defaults.md:"
  echo "      that file is no longer shipped, and a missing @import fails SILENTLY."
  echo "      Replace that one line with the '## Session defaults' section from:"
  echo "        $SEED_SRC/CLAUDE.md"
fi

# 5. SEED DRIFT — the case a copy-if-absent stamp can never deliver by itself.
#
# `seed/` is copied ONLY when a path is absent, which is what makes this script safe to
# run blindly on a repo full of somebody's work — and the price is that a later seed edit
# never reaches a bundle already stamped. That was `upgrade.sh`'s whole job. It is
# `refresh-seeds.sh` now, it ships beside this file in the plugin, and it APPLIES: it
# never resolves a conflict by force, it keeps every copy it makes out of the bundle tree,
# and the classes it decides for itself have one right answer on every bundle.
#
# Non-fatal on every path. A template with no git history, a bundle that is not a
# checkout, an absent helper — all of them report and none of them fails the stamp.
# Skipped on a FIRST stamp: everything was just copied, so nothing can have drifted.
#
# AND IT IS THE WELCOME CHECK-AND-FIX PASS, NOT THE SEED REFRESH ALONE. A bundle used to
# be brought up to the installed plugin by two commands in an order nobody could derive —
# this stamp, then `/<plugin>:welcome fix`. One command does it now: the pass runs the
# same rows, the same tiers and the same refusals (config files and tick locks are
# reported, never written).
#
# SKIPPED WHEN `AI_BRIDGE_INIT_PASS` IS ALREADY SET, which is what makes it terminate: the
# pass's own `bundle-unconverted` repair re-stamps this bundle, and that stamp inherits the
# variable and runs no second pass. Without it, a symlink the sweep KEEPS (a human's own)
# and that row still counts would loop forever.
[ "$REFRESH_SEEDS" -eq 0 ] || REFRESH_SEEDS=0   # read and dropped — see the flag above
if [ "$FIRST_STAMP" = no ] && [ -z "${AI_BRIDGE_INIT_PASS:-}" ]; then
  if [ -f "$BIN_DIR/welcome.sh" ]; then
    echo
    AI_BRIDGE_INIT_PASS=1 bash "$BIN_DIR/welcome.sh" fix --instance "$TARGET" || true
  elif [ -f "$BIN_DIR/refresh-seeds.sh" ]; then
    bash "$BIN_DIR/refresh-seeds.sh" "$TARGET" --apply || true
  fi
  # 5a. ONE COPY OF EACH MANAGED IGNORE LINE, and the order is why this exists at all.
  # The guards above run BEFORE this pass, so on a bundle whose copy of a seed-managed
  # line had been deleted they append it — and then the seed-drift resolver restores the
  # seed's own copy, because a seed-managed line is exactly what it takes the seed side
  # for. Two identical lines, harmless to git and a defect to anyone reading the file.
  # Keeps the FIRST occurrence, so the seed's placement wins over the appended one.
  #
  # SPACE-SEPARATED, NOT NEWLINE. `awk -v` refuses a value containing a newline
  # ("newline in string") and the whole tidy then silently did nothing. Every path here is
  # a resolver constant, so none can contain a space.
  if [ -f "$gi" ]; then
    gi_managed="/$AB_LOCK /$AB_LOCK_CLAIM /$AB_STATE_DIR /$AB_BOARD_OTHERS"
    gi_managed="$gi_managed /$AB_BOARD_DIR/ /$AB_AWAITING /$AB_SNAPSHOT /$AB_DIR/kb.git/ /$AB_DIR/kb-src/"
    tmp="$gi.tmp.$$"
    if awk -v managed="$gi_managed" '
         BEGIN { n = split(managed, m, " "); for (i = 1; i <= n; i++) if (m[i] != "") mine[m[i]] = 1 }
         ($0 in mine) && seen[$0]++ { next }
         { print }
       ' "$gi" > "$tmp" && ! cmp -s "$tmp" "$gi"; then
      mv "$tmp" "$gi"
      echo "  tidy  .gitignore (a managed ignore line appeared twice)"
    else
      rm -f "$tmp"
    fi
  fi
fi

# 5b. The plugin version this stamp ran with, tracked with the rest of the record. The
# banner's Update row compares it with the installed plugin and names /<plugin>:init when
# they differ — "re-run init after every plugin update" had no reader before this file.
if [ -f "$PLUGIN_ROOT/VERSION" ] && { [ -d "$SEED_BASE_DIR" ] || mkdir -p "$SEED_BASE_DIR" 2>/dev/null; }; then
  cp "$PLUGIN_ROOT/VERSION" "$SEED_BASE_DIR/VERSION" 2>/dev/null || true
fi

# 6. One nudge, and only a nudge, when the bundle's own documents do not satisfy the
# schema. Silent unless the validator says exactly "there are errors" (exit 1): absent,
# clean, or "not a bundle root" (exit 2) are not things a human can act on from here.
if [ -f "$BIN_DIR/validate-bundle.sh" ]; then
  vrc=0
  ( cd "$TARGET" && bash "$BIN_DIR/validate-bundle.sh" ) >/dev/null 2>&1 || vrc=$?
  if [ "$vrc" -eq 1 ]; then
    echo "Note: this bundle has schema errors. To see and repair them, run:"
    echo "      /${PLUGIN_NAME}:welcome check   (or: bash $BIN_DIR/validate-bundle.sh from $TARGET)"
  fi
fi

# ===========================================================================
# 7. THE ORG BUNDLE'S FIRST COMMIT — only when step 0 created or found an empty repo.
# ===========================================================================
#
# Last, because everything it commits is what the steps above just wrote. A clone of a
# bundle that already has commits reaches here with ORG_PUSH=no and does nothing.
if [ "$ORG_PUSH" = yes ]; then
  echo
  if [ ! -d "$TARGET/.git" ]; then
    git -C "$TARGET" init --quiet >/dev/null 2>&1 || true
  fi
  git -C "$TARGET" remote get-url origin >/dev/null 2>&1 \
    || git -C "$TARGET" remote add origin "$ORG_REMOTE" >/dev/null 2>&1 || true
  org_rc=0
  git -C "$TARGET" add -A >/dev/null 2>&1 || org_rc=1
  git -C "$TARGET" commit --quiet -m "chore: stamp the $ORG_FLAG OKF knowledge bundle" >/dev/null 2>&1 || org_rc=1
  [ "$org_rc" != 0 ] || git -C "$TARGET" push --quiet -u origin HEAD >/dev/null 2>&1 || org_rc=1
  if [ "$org_rc" = 0 ]; then
    echo "  pushed $ORG_SLUG — the first commit is on the default branch"
  else
    echo "  warn  the first commit was not pushed. From $TARGET, finish it by hand:" >&2
    echo "          git add -A && git commit -m 'chore: stamp the bundle' && git push -u origin HEAD" >&2
  fi
  # WHICH OF THE TWO IT DID — said on every path, because "it worked" is not the answer to
  # "is this the org's bundle yet?".
  case "$ORG_HOST" in
    org)  echo "  bundle $ORG_SLUG is the organisation's — everyone clones this." ;;
    user) cat <<ORGNOTE
  bundle $ORG_SLUG is under YOUR account: creating $ORG_FLAG/$ORG_NAME was refused,
         which is the normal path for anyone who is not an org admin. The stamp is
         complete. Move it to $ORG_FLAG when an admin can:
           gh repo transfer $ORG_SLUG $ORG_FLAG
           # or: gh api -X POST repos/$ORG_SLUG/transfer -f new_owner=$ORG_FLAG
         Then every clone re-points with: git remote set-url origin <new url>
ORGNOTE
    ;;
    *)    echo "  bundle $ORG_SLUG was empty and is now this org's bundle." ;;
  esac
  echo "  note  \"org\" in instance.config.json names the org whose PRODUCT repos the tasks"
  echo "        target — a separate value from --org, which is who hosts this bundle."
fi
if [ -n "$ORG_SLUG" ]; then
  echo "  note  everyone else on this bundle starts here:"
  echo "        https://github.com/cbmono/ai-bridge/blob/main/docs/sharing.md"
fi

# 8. The mount, and one WARNING when it carries uncommitted edits or unpushed commits. It reports, it never
# writes: a local KB commit is somebody's work, and pushing it on their behalf from an
# installer is exactly the surprise this pass exists to avoid.
if [ -f "$BIN_DIR/kb-sync.sh" ]; then
  # The mount runs FIRST: it refuses a bundle still awaiting kb-migrate.sh, and ignoring
  # knowledge/ with no mount behind it would hide ~200 untracked documents from `git add`.
  mrc=0
  bash "$BIN_DIR/kb-sync.sh" --instance "$TARGET" mount || mrc=$?
  if [ "$mrc" -eq 0 ] \
     && [ -n "$(bash "$BIN_DIR/resolve-config.sh" --instance "$TARGET" knowledge repo 2>/dev/null)" ] \
     && ! grep -qxF '/knowledge/' "$TARGET/.gitignore" 2>/dev/null; then
    printf '\n# The knowledge base is MOUNTED from another repository (`knowledge` in\n# instance.config.json). A clone that has not synced yet has no knowledge/ at all;\n# make one with: scripts/kb-sync.sh mount\n/knowledge/\n/knowledge-sources/\n' >> "$TARGET/.gitignore"
  fi
  krc=0
  bash "$BIN_DIR/kb-sync.sh" --instance "$TARGET" status >/dev/null 2>&1 || krc=$?
  if [ "$krc" -eq 1 ]; then
    echo "warn  the mounted knowledge base has uncommitted edits or unpushed commits. To see and push them:"
    ab_say_run "     " bash "$BIN_DIR/kb-sync.sh" status
    ab_say_run "      then:" kb-sync.sh commit --message '"<message>"' -- '<path>...'
  fi
fi
