#!/usr/bin/env bash
#
# add-second-human.sh — put a second human on an existing loopd bundle.
#
#   Usage:  ./scripts/add-second-human.sh <instance-dir> [--apply]
#
#   SECOND_LOGIN=octocat SECOND_EMAIL=o@example.com ./scripts/add-second-human.sh <dir>
#
# REPORT-ONLY BY DEFAULT, like migrate-bundle.sh and upgrade.sh. A default run reads,
# checks and prints; nothing is written until --apply.
#
# WHY A SCRIPT AND NOT A CHECKLIST. docs/sharing.md documents nine steps. Steps 3-5 are
# the ones that matter and the ones people get wrong, because getting them wrong is
# SILENT: with `defaultOwner` absent, unowned work resolves to "mine" on BOTH clones, so
# both loops dispatch the same task and you get two PRs for one slice. That is the exact
# failure ownership exists to prevent, and nothing errors when it happens.
#
# WHAT THIS DOES NOT DO. It does not touch the second human's machine — it cannot. It
# prepares the SHARED, TRACKED half (the `people` map and `defaultOwner`, which must be
# identical on both clones) and then prints the commands the second human runs on their
# own machine, where their own paths and identity live.
set -uo pipefail

# ---------------------------------------------------------------- fill these in
# The second human. A GitHub LOGIN, never an email, for the owner value: it is public,
# stable, and keeps addresses out of tracked documents. The email is only for git
# authorship via the `people` map.
SECOND_LOGIN="${SECOND_LOGIN:-REPLACE-github-login}"
SECOND_EMAIL="${SECOND_EMAIL:-REPLACE@example.com}"
# Who owns work carrying no explicit `owner:`. MUST be one login, MUST be identical on
# both clones, and HAS NO SAFE DEFAULT — which is why this one is not defaulted.
#
# The first version defaulted it to SECOND_LOGIN. That is wrong in the common case and
# wrong in the expensive direction: on an existing bundle the unowned backlog is the
# FIRST human's, so defaulting to the newcomer hands them every untagged task and gives
# the original owner none. Caught on the first real run.
DEFAULT_OWNER="${DEFAULT_OWNER:-}"

# The first human, so `people` maps both and ownership can resolve on either clone.
FIRST_LOGIN="${FIRST_LOGIN:-}"
# ------------------------------------------------------------------------------

APPLY=0
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "add-second-human: unknown flag '$1'" >&2; exit 2 ;;
    *) TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "add-second-human: need an instance directory." >&2; exit 2; }
CFG="$TARGET/instance.config.json"
[ -f "$CFG" ] || { echo "add-second-human: $CFG not found — is that an instance root?" >&2; exit 2; }

case "$SECOND_LOGIN" in
  REPLACE*)
    echo "add-second-human: fill in SECOND_LOGIN and SECOND_EMAIL at the top of this" >&2
    echo "                  script, or pass them as environment variables:" >&2
    echo "  SECOND_LOGIN=octocat SECOND_EMAIL=o@example.com $0 $TARGET" >&2
    exit 2 ;;
esac
[ -n "$DEFAULT_OWNER" ] || {
  echo "add-second-human: DEFAULT_OWNER is required — there is no safe default." >&2
  echo "                  It is who owns work with no explicit \`owner:\`, and on an" >&2
  echo "                  existing bundle that is almost always the FIRST human, not" >&2
  echo "                  the one being added. Set it explicitly:" >&2
  echo "  DEFAULT_OWNER=<first-human-login> SECOND_LOGIN=... SECOND_EMAIL=... $0 $TARGET" >&2
  exit 2; }

command -v python3 >/dev/null 2>&1 || {
  echo "add-second-human: needs python3 to edit JSON safely (never line-wise)." >&2; exit 2; }

# Validate before writing, the same shapes task-owner.sh accepts — so no accepted value
# can carry a character that would need escaping into a JSON string.
case "$SECOND_LOGIN" in
  *[!A-Za-z0-9-]*|-*|*-)
    echo "add-second-human: '$SECOND_LOGIN' is not a GitHub username." >&2; exit 2 ;;
esac
case "$SECOND_EMAIL" in
  *@*.*) ;;
  *) echo "add-second-human: '$SECOND_EMAIL' is not an email address." >&2; exit 2 ;;
esac

echo "== the shared, TRACKED half (both clones must agree) =================="
python3 - "$CFG" "$SECOND_LOGIN" "$SECOND_EMAIL" "$DEFAULT_OWNER" "$APPLY" "$FIRST_LOGIN" <<'PYEOF'
import json, sys
cfg, login, email, owner = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
apply_ = sys.argv[5] == "1"
first = sys.argv[6] if len(sys.argv) > 6 else ""
d = json.load(open(cfg))
people = dict(d.get("people") or {})
changes = []

# Never DERIVE an address from a login. The mapping is a business fact, not a naming
# convention — and GitHub requires the id-prefixed noreply form for accounts created
# after 2017-07-18, so a derived plain address silently fails to link.
if people.get(login) != email:
    changes.append(("people[%s]" % login, people.get(login), email))
    people[login] = email

# The FIRST human must be in the map too, or their commits fall through to authorEmail
# and ownership cannot resolve on their clone.
me = d.get("authorEmail")
if me and me not in people.values():
    if first:
        changes.append(("people[%s]" % first, people.get(first), me))
        people[first] = me
    else:
        print("  NOTE: authorEmail %s is not in `people`, and FIRST_LOGIN was not given." % me)
        print("        Pass FIRST_LOGIN=<your-github-login> so both humans are mapped —")
        print("        otherwise ownership cannot resolve on the first human's clone.")

if d.get("defaultOwner") != owner:
    changes.append(("defaultOwner", d.get("defaultOwner"), owner))

if not changes:
    print("  nothing to change — `people` and `defaultOwner` are already set.")
else:
    for k, was, now in changes:
        print("  %-22s %s -> %s" % (k, "(absent)" if was is None else was, now))

if apply_ and changes:
    d["people"] = people
    d["defaultOwner"] = owner
    with open(cfg, "w") as fh:
        json.dump(d, fh, indent=2)
        fh.write("\n")
    json.load(open(cfg))            # parse it back before claiming success
    print("  written, and re-parsed OK.")
elif changes:
    print("  (report only — re-run with --apply to write)")
PYEOF

REMOTE="$(git -C "$TARGET" remote get-url origin 2>/dev/null || echo '<bundle-remote>')"
TPL="$(cd "$(dirname "$0")/.." && pwd)"
. "$TPL/plugin/scripts/plugin-name.sh"
GH_REPO="$(sed -n 's#^  "repository": *"https://github.com/\([^"]*\)".*#\1#p' "$TPL/plugin/.claude-plugin/plugin.json" | head -1)"

echo
echo "== what the SECOND human runs, on their own machine ==================="
echo "  # 1. install the plugin, once per machine, in Claude Code:"
echo "  #      /plugin marketplace add $GH_REPO"
echo "  #      /plugin install $PLUGIN_NAME@$PLUGIN_MARKETPLACE"
echo
echo "  # 2. clone the bundle"
echo "  git clone $REMOTE _loopd-<group> && cd _loopd-<group>"
echo
echo "  # 3. stamp the clone, in Claude Code. It writes their GITIGNORED"
echo "  #    instance.config.local.json, which must never be committed, or both humans'"
echo "  #    commits get authored as one person. Add --repos-root <dir> if their repos"
echo "  #    do not sit beside the bundle."
echo "  /$PLUGIN_NAME:init . --owner $SECOND_LOGIN"
echo
echo "  # 4. A CLONE IS NOT A FIRST STAMP, so the queue is not created. Turn it on:"
echo "  touch AWAITING.md"
echo "  ./scripts/write-snapshot.sh        # board presence (\`board\` defaults to on)"
echo
echo "  # 5. sanity-check ownership BEFORE starting a loop — exit 0 means 'this clone's'"
echo "  ./scripts/task-owner.sh projects/<slug>/tasks/<id>.md; echo \"exit=\$?\""

echo
echo "== the two things that break SILENTLY if skipped ======================"
echo "  1. \`defaultOwner\` must be identical on both clones. Absent => unowned work is"
echo "     BOTH clones' => both loops dispatch it => two PRs for one slice, no error."
echo "  2. One active /loopd:dispatch loop per CLONE. The serial guarantee is"
echo "     per-session with no cross-session lock; two loops on one clone reintroduce"
echo "     the same double dispatch, plus a shared package store corrupting an"
echo "     in-flight worktree."
echo
echo "  Full reasoning: $TPL/docs/sharing.md"
