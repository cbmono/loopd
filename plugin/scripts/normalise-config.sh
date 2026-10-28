#!/usr/bin/env bash
#
# normalise-config.sh — report, or --apply, config findings across a bundle's two files.
#
#   Usage: normalise-config.sh [<bundle>] [--apply] [--quiet]
#
# MISPLACED a per-machine key in the tracked file, or a tracked-only key in the local one ·
# MISSING a seed key the tracked file lacks · ORDER keys not in seed order. Values are
# never changed: only placed, ordered, or added when absent. With --apply the tracked file
# is left STAGED, never committed. Exit 0 clean/applied · 1 findings · 2 usage · 3 write.
# The overridable set has one source, SCHEMA.md → "Per-machine config overrides"; the
# reasoning lives in docs/operations.md § 1.
set -uo pipefail
_pn="$(dirname "${BASH_SOURCE[0]:-$0}")/plugin-name.sh"; if [ -r "$_pn" ]; then . "$_pn"; fi

BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SEED="$BIN_DIR/../seed/instance.config.json"
TARGET="."
APPLY=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    # For a caller that has already printed the report and only wants the outcome line.
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "normalise-config: unknown flag '$arg'" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

[ -d "$TARGET" ] || { echo "normalise-config: no such directory: $TARGET" >&2; exit 2; }
[ -f "$TARGET/instance.config.json" ] || {
  echo "normalise-config: $TARGET is not a bundle (no instance.config.json)." >&2; exit 2; }
[ -f "$SEED" ] || { echo "normalise-config: seed config not found at $SEED" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || {
  echo "normalise-config: python3 is needed to read these files; nothing was checked." >&2
  exit 2; }

STATUS="$(mktemp "${TMPDIR:-/tmp}/normalise-config.XXXXXX")" || exit 2
trap 'rm -f "$STATUS"' EXIT
rc=0
python3 - "$TARGET" "$SEED" "$APPLY" "$STATUS" "$QUIET" <<'PY' || rc=$?
import json, os, sys

target, seed_path, status_path = sys.argv[1], sys.argv[2], sys.argv[4]
apply_mode, quiet = sys.argv[3] == "1", sys.argv[5] == "1"
TRACKED, LOCAL = "instance.config.json", "instance.config.local.json"

# SCHEMA.md → "Per-machine config overrides", in that table's order: the local file's key
# order and the membership test for what may live there, in one list.
LOCAL_ORDER = ["$schema", "ownerGithubUser", "authorEmail", "reposRoot", "worktreeRoot",
               "boardInstances", "boardArtifactUrl", "boardPort", "models", "roleTiers",
               "roleEffort",
               "maxAgentsInFlight", "maxRepeatedToolCalls", "maxAgentMinutes", "roleMinutes",
               "commitAttribution", "reclaimIgnoreOk"]

# The overridable keys whose TRACKED copy is NOT a documented fallback. That column is the
# whole test: SCHEMA names the tracked value as the answer for authorEmail, models,
# roleTiers, maxAgentsInFlight and commitAttribution, and names no tracked answer for these.
PER_MACHINE_ONLY = ["ownerGithubUser", "reposRoot", "worktreeRoot", "boardInstances",
                    "boardArtifactUrl", "boardPort"]


def load(path, what):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return None
    except Exception:
        print("normalise-config: %s does not parse as JSON; nothing was checked." % what,
              file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(data, dict):
        print("normalise-config: %s is not a JSON object; nothing was checked." % what,
              file=sys.stderr)
        raise SystemExit(2)
    return data


def canonical(keys, order):
    """The order `keys` should be in. A key the order does not name — a bundle's own
    `$doc` key, a setting this seed never shipped — is ANCHORED to the last named key
    before it, so it travels with its neighbour instead of being swept to the end."""
    anchored, prev = {}, ""
    for k in keys:
        if k in order:
            prev = k
        else:
            anchored.setdefault(prev, []).append(k)
    out = list(anchored.get("", []))
    for k in order:
        if k in keys:
            out.append(k)
            out.extend(anchored.get(k, []))
    return out


seed = load(seed_path, "the seed instance.config.json")
tracked = load(os.path.join(target, TRACKED), TRACKED)
local = load(os.path.join(target, LOCAL), LOCAL)
before = {TRACKED: dict(tracked), LOCAL: dict(local or {})}

new_tracked = dict(tracked)
new_local = dict(local or {})
findings = {TRACKED: [], LOCAL: []}
dropped = []


def misplace(src, dst, key, src_map, dst_map):
    """One per-machine (or tracked-only) key, out of the file it does not belong in.
    The DESTINATION's value always wins — moving is how a value survives, dropping is
    how a duplicate goes — so nothing here ever rewrites a value. A destination null is
    ABSENCE (SCHEMA.md), so it is filled rather than treated as the winner."""
    if dst_map.get(key) is not None:
        dropped.append((src, key))
        why = "dropped: it already has one"
    else:
        dst_map[key] = src_map[key]
        why = "moved"
    del src_map[key]
    findings[src].append(("MISPLACED", key, "-> %s (%s)" % (dst, why)))


for key in list(new_tracked):
    if key in PER_MACHINE_ONLY:
        misplace(TRACKED, LOCAL, key, new_tracked, new_local)
for key in list(new_local):
    # The local file may hold the overridable set and nothing else: everything outside it
    # is a shared fact one clone would be deciding for the other.
    if not key.startswith("$") and key not in LOCAL_ORDER:
        misplace(LOCAL, TRACKED, key, new_local, new_tracked)

# Seed keys whose value is an EXAMPLE, not a default: adding them would plant a placeholder
# organisation, a reserved example.com address or two unclaimed logins into a real bundle.
# Their absence is reported nowhere, because the seed cannot know the right value.
PLACEHOLDER_VALUED = {"org", "authorEmail", "people"}
# Seed keys whose absence already reads as the seed value, so adding one migrates nothing.
ABSENT_IS_SEED = {"awaiting", "boardServe"}

for key, value in seed.items():
    # A `$doc` key is the seed's own commentary, so it is never added to a bundle; a
    # per-machine key is not missing from the tracked file, it is absent by design.
    if key.startswith("$") or key in PER_MACHINE_ONLY or key in PLACEHOLDER_VALUED or key in ABSENT_IS_SEED or key in new_tracked:
        continue
    new_tracked[key] = value
    findings[TRACKED].append(("MISSING", key, "added with the seed default"))

seed_order = [k for k in seed if k not in PER_MACHINE_ONLY]
ordered = {}
for name, data, order in ((TRACKED, new_tracked, seed_order), (LOCAL, new_local, LOCAL_ORDER)):
    want = canonical(list(data), order)
    if want != list(data):
        moved = sum(1 for a, b in zip(want, list(data)) if a != b)
        findings[name].append(("ORDER", "%d of %d keys" % (moved, len(want)),
                               "were out of the seed's order"))
    ordered[name] = {k: data[k] for k in want}

new_tracked, new_local = ordered[TRACKED], ordered[LOCAL]

# NO VALUE MAY CHANGE. Every key that was there is still there with the value it had,
# somewhere, unless it was dropped as a duplicate of one the destination already held.
after = {TRACKED: new_tracked, LOCAL: new_local}
for name, was in before.items():
    other = after[LOCAL if name == TRACKED else TRACKED]
    for key, value in was.items():
        # A null was absence to begin with, so nothing that happens to it is a change.
        if value is None or (name, key) in dropped:
            continue
        here = after[name][key] if key in after[name] else other.get(key, ())
        if here != value:
            print("normalise-config: refusing to write — %s.%s would change value." % (name, key),
                  file=sys.stderr)
            raise SystemExit(3)

# WHAT WAS WRITTEN IS ASKED OF THE BYTES, not of the finding list. A key moved OUT of one
# file lands in the other with no finding of its own, and deriving "write it" from that
# file's findings would drop the value on the floor.
changed = {name: list(after[name].items()) != list(before[name].items())
           for name in (TRACKED, LOCAL)}
total = len(findings[TRACKED]) + len(findings[LOCAL])
if total and not quiet:
    print("Config findings (normalise-config.sh):")
    for name in (TRACKED, LOCAL):
        if not findings[name]:
            continue
        print("  %s" % name)
        for kind, what, note in findings[name]:
            print("    %-10s %-22s %s" % (kind, what, note))

with open(status_path, "w") as fh:
    fh.write("%d %d %d\n" % (total, int(changed[TRACKED]), int(changed[LOCAL])))

if not total:
    raise SystemExit(0)
if not apply_mode:
    print("  %d finding(s). Apply them with: /%s:init --normalise-config" % (total, os.environ.get("PLUGIN_NAME", "")))
    raise SystemExit(1)


def write(name, data):
    path = os.path.join(target, name)
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    if os.path.exists(path):
        try:
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        except OSError:
            pass
    with open(tmp) as fh:
        if json.load(fh) != data:
            os.unlink(tmp)
            raise SystemExit(3)
    os.replace(tmp, path)


for name, data in ((TRACKED, new_tracked), (LOCAL, new_local)):
    if changed[name]:
        write(name, data)
print("  applied %d finding(s); no value was changed." % total)
PY

tracked_written=0
if [ -f "$STATUS" ]; then
  read -r _total tracked_written _local < "$STATUS" || true
fi

# Criterion 5: STAGED, never committed. Whether these keys belong in a commit at all is
# the human's call, and it is the only reason a stamp may not just write and forget.
if [ "$APPLY" = 1 ] && [ "$rc" = 0 ] && [ "${tracked_written:-0}" != 0 ]; then
  if command -v git >/dev/null 2>&1 \
     && git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && git -C "$TARGET" add -- instance.config.json 2>/dev/null; then
    echo "  staged instance.config.json — yours to review and commit."
  else
    echo "  note  instance.config.json was rewritten but not staged (no git here)."
  fi
fi

exit "$rc"
