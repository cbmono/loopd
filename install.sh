#!/usr/bin/env bash
#
# install.sh — RETIRED. `/loopd:init` replaces it.
#
# It shipped for one version as this stub so a bookmarked command, a stale doc or a
# muscle-memory `./install.sh ~/workspace/foo/_ai-bridge-foo` says what to run instead
# of failing with "no such file". Delete it at the next version.
#
# Exits 2 on every path: this is a refusal, not a no-op, and a script that called it
# must see a failure rather than a silent success it did not get.
set -eu

cat >&2 <<'EOF'
install.sh is retired. The bundle installer ships in the loopd PLUGIN now.

  1. Install the plugin, once per machine:
       /plugin marketplace add cbmono/loopd
       /plugin install loopd@loopd
     …then restart Claude Code.

  2. Create or refresh a bundle, from any session:
       /loopd:init <dir>

That command creates a bundle, refreshes an existing one, and CONVERTS a bundle
stamped by this script: it removes the machinery symlinks into a template checkout
and leaves your data untouched. You no longer need a clone of cbmono/loopd on
this machine at all.

  · the ~/.claude config layer (was `install.sh --config`): RETIRED — the three agents
       it linked ship in the plugin now (loopd:code-architect, loopd:deep-bug-scan,
       loopd:plan-architect); nothing to install
  · the seed 3-way merge (was `upgrade.sh`):
       /loopd:welcome fix

Why: a plugin-shipped installer cannot stamp absolute symlinks into a plugin cache
whose path changes on every update. docs/migrating.md walks the conversion.
EOF
exit 2
