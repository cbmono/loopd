#!/usr/bin/env bash
#
# normalise-config.test.sh — `normalise-config.sh` reports the three finding kinds, moves
# and adds without ever changing a value, and `/<plugin>:init` runs it on every stamp.
#
# WHY. Measured 2026-09-07 across the owner's three bundles: absolute paths in the TRACKED
# `instance.config.json`, `defaultOwner` duplicated into a per-machine file, every key
# added since 1.x missing, and three different key orders. Nothing was an error the
# validator caught, and a plugin update cannot reach a bundle's data — so the stamp is
# where the two files get put right.
#
# WHAT IS PINNED, one group each:
#
#   1. MISPLACED — a per-machine key in the tracked file, a tracked-only key in the local
#      one — and the LOCAL-WINS rule: an existing destination value is never overwritten,
#      the source copy is dropped, and a destination `null` is ABSENCE and gets filled
#      (SCHEMA.md → "Per-machine config overrides").
#   2. MISSING and the `$doc` rule: a seed key absent from the tracked file is added with
#      the seed default; a `$`-prefixed seed comment is NEVER added, and a bundle's own
#      `$` key is kept and travels with the key it annotates.
#   3. ORDER, and the ROUND TRIP: a normalised pair reports nothing on a second run, which
#      is the property that makes this safe to run on every stamp.
#   4. NO VALUE EVER CHANGES — asserted over every key of a deliberately mangled pair,
#      the one rule whose violation would be silent and unrecoverable.
#   5. `/<plugin>:init` — silent about config on a clean pair, reports on a dirty one,
#      applies with `--normalise-config` and at an interactive yes, and leaves the tracked
#      file STAGED rather than committed.
#   6. The stamp leaves NO per-machine path in the tracked file and invents none in the
#      local one — criterion 7, and the defect the whole task was opened for.
#
# THE FIXTURE TEMPLATE IS A PLAIN DIRECTORY COPY of `git ls-files`, never this checkout,
# for the reason local-tier-seed.test.sh states: an uncommitted edit under review is what
# runs, and no fixture ever writes into the repo.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/normcfg.XXXXXX")" || {
  echo "normalise-config.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "normalise-config.test: python3 absent — the script under test needs it." >&2
  echo "pass=0 fail=0"; exit 0
fi

make_tpl() { # <dir> — a throwaway plain-directory copy of the template
  local d="$1" f
  mkdir -p "$d"
  ( cd "$REPO" && git ls-files . ) | while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$d/$(dirname "$f")"; cp "$REPO/$f" "$d/$f" 2>/dev/null || true
  done
  chmod +x "$d"/plugin/scripts/*.sh 2>/dev/null || true
}
TPL="$TMP/tpl"; make_tpl "$TPL"
NORM="$TPL/plugin/scripts/normalise-config.sh"
INIT="$TPL/plugin/scripts/init-bundle.sh"
SEED="$TPL/plugin/seed/instance.config.json"
[ -f "$NORM" ] || { echo "normalise-config.test: $NORM is not committed yet" >&2; exit 2; }

# A stamped bundle, in its own git repo (the staging assertion needs one).
newinst() { # <n> — prints the path
  local d="$TMP/i$1"
  rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q . >/dev/null 2>&1
  bash "$INIT" "$d" >"$TMP/stamp.$1" 2>&1
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@example.com -c user.name=t commit -qm base >/dev/null 2>&1
  printf '%s' "$d"
}
norm()  { ( cd "$1" && shift && bash "$NORM" . "$@" >"$TMP/out" 2>&1; echo $? ); }
said()  { grep -q -- "$1" "$TMP/out" && echo yes || echo no; }
# One finding line's presence, by kind and key.
finding() { grep -qE "^ +$1 +$2( |\$)" "$TMP/out" && echo yes || echo no; }

# Edit a JSON file with a python snippet on stdin; `d` is the parsed object.
jedit() { # <file>
  python3 - "$1" <<PY
import collections, json, sys
p = sys.argv[1]
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
$(cat)
json.dump(d, open(p, "w"), indent=2)
PY
}
jget() { # <file> <key>
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable"); raise SystemExit(0)
if sys.argv[2] not in d:
    print("-"); raise SystemExit(0)
v = d[sys.argv[2]]
print("null" if v is None else v if isinstance(v, str) else json.dumps(v, sort_keys=True))
PY
}
jkeys() { python3 -c "
import collections, json, sys
print(' '.join(json.load(open(sys.argv[1]), object_pairs_hook=collections.OrderedDict)))" "$1"; }

TCFG=instance.config.json
LCFG=instance.config.local.json

# =========================================================================== #
echo "-- 1. MISPLACED, in both directions, and the destination always wins"
I="$(newinst 1)"
# The stamp DERIVES this clone's identity into the local file (init-bundle.sh 4c). This
# case is about a key misplaced in the TRACKED one, so the destination starts empty —
# exactly the state it was in before that step existed.
jedit "$I/$LCFG" <<'PY'
for k in ("reposRoot", "ownerGithubUser", "authorEmail"):
    d.pop(k, None)
PY
jedit "$I/$TCFG" <<'PY'
d["reposRoot"] = "/abs/path/on/one/machine"
d["ownerGithubUser"] = "example-user-007"
PY
jedit "$I/$LCFG" <<'PY'
d["defaultOwner"] = "example-user-008"
d["org"] = "wrong-org"
d["maxAgentMinutes"] = 120
d["roleMinutes"] = {"project-manager": 200}
d["reclaimIgnoreOk"] = ["target"]
d["coderabbitRounds"] = 2
d["continueAfterTasks"] = 16
d["continueAfterDays"] = 20
PY
RC="$(norm "$I")"
ok "a dirty pair exits 1"                     "$RC" 1
ok "reposRoot in the tracked file is MISPLACED"      "$(finding MISPLACED reposRoot)" yes
ok "…and so is ownerGithubUser"                      "$(finding MISPLACED ownerGithubUser)" yes
ok "defaultOwner in the local file is MISPLACED"     "$(finding MISPLACED defaultOwner)" yes
ok "…and so is a shared fact like org"               "$(finding MISPLACED org)" yes
# SCHEMA marks both overridable, so the per-machine wall-clock budget stays where it is.
ok "a local maxAgentMinutes is NOT misplaced"        "$(finding MISPLACED maxAgentMinutes)" no
ok "…nor a local roleMinutes"                        "$(finding MISPLACED roleMinutes)" no
ok "…nor a local reclaimIgnoreOk"                    "$(finding MISPLACED reclaimIgnoreOk)" no
# SCHEMA marks these three shared facts, so a local copy is misplaced.
ok "a local coderabbitRounds is MISPLACED"           "$(finding MISPLACED coderabbitRounds)" yes
ok "…and so is continueAfterTasks"                   "$(finding MISPLACED continueAfterTasks)" yes
ok "…and so is continueAfterDays"                    "$(finding MISPLACED continueAfterDays)" yes
ok "report mode wrote nothing"                "$(jget "$I/$TCFG" reposRoot)" /abs/path/on/one/machine
RC="$(norm "$I" --apply)"
ok "--apply exits 0"                          "$RC" 0
ok "reposRoot left the tracked file"          "$(jget "$I/$TCFG" reposRoot)" -
ok "…and arrived in the local one, value intact" \
   "$(jget "$I/$LCFG" reposRoot)"             /abs/path/on/one/machine
ok "ownerGithubUser moved too"                "$(jget "$I/$LCFG" ownerGithubUser)" example-user-007
ok "defaultOwner left the local file"         "$(jget "$I/$LCFG" defaultOwner)" -
# The tracked seed ships `defaultOwner: null`, and SCHEMA says a null IS absence — so the
# move fills it rather than reading the null as a value that wins.
ok "…and filled the tracked null"             "$(jget "$I/$TCFG" defaultOwner)" example-user-008
ok "org did NOT overwrite the tracked value"  "$(jget "$I/$TCFG" org)" your-github-org
ok "…and the duplicate is gone from local"    "$(jget "$I/$LCFG" org)" -

echo
echo "-- 1b. an existing LOCAL value wins and the tracked copy is dropped"
I="$(newinst 2)"
jedit "$I/$TCFG" <<'PY'
d["worktreeRoot"] = "/tracked/one"
PY
jedit "$I/$LCFG" <<'PY'
d["worktreeRoot"] = "/local/one"
PY
norm "$I" --apply >/dev/null
ok "the local value stands"                   "$(jget "$I/$LCFG" worktreeRoot)" /local/one
ok "…and the tracked copy is dropped"         "$(jget "$I/$TCFG" worktreeRoot)" -

echo
echo "-- 1c. a move with no finding of its own on the DESTINATION still writes it"
# The regression: whether a file gets written is asked of its BYTES, not of its finding
# list. A key moved out of one file lands in the other carrying no finding there, and an
# unknown key anchors to its neighbour so it triggers no ORDER finding either — deriving
# the write from findings dropped it on the floor.
I="$(newinst 10)"
jedit "$I/$LCFG" <<'PY'
d["zzCustom"] = "a setting no seed ships"
PY
norm "$I" --apply >/dev/null
ok "the tracked file has no finding of its own" "$(grep -c '^  instance.config.json$' "$TMP/out")" 0
ok "…and the value still arrived there"       "$(jget "$I/$TCFG" zzCustom)" "a setting no seed ships"
ok "…and left the local file"                 "$(jget "$I/$LCFG" zzCustom)" -

# =========================================================================== #
echo
echo "-- 2. MISSING adds seed keys; \$doc keys are never added, and a bundle's own is kept"
I="$(newinst 3)"
jedit "$I/$TCFG" <<'PY'
for k in ("maxPrFiles", "maxStallRounds", "commitAttribution", "$commitAttribution", "authorEmail", "people"):
    d.pop(k, None)
d["$mine"] = "a note this bundle wrote itself"
PY
norm "$I" >/dev/null
ok "a key added since 1.x is MISSING"         "$(finding MISSING maxPrFiles)" yes
ok "…and so is maxStallRounds"                "$(finding MISSING maxStallRounds)" yes
ok "…and commitAttribution"                   "$(finding MISSING commitAttribution)" yes
ok "the seed's \$doc key is NOT reported"      "$(grep -c 'MISSING *\$' "$TMP/out")" 0
ok "a placeholder-valued key (authorEmail) is NOT added" "$(finding MISSING authorEmail)" no
ok "…nor the example people map"             "$(finding MISSING people)" no
norm "$I" --apply >/dev/null
ok "maxPrFiles arrived with the seed default" "$(jget "$I/$TCFG" maxPrFiles)" "$(jget "$SEED" maxPrFiles)"
ok "maxStallRounds too"                       "$(jget "$I/$TCFG" maxStallRounds)" "$(jget "$SEED" maxStallRounds)"
ok "commitAttribution too"                    "$(jget "$I/$TCFG" commitAttribution)" claude
ok "the seed's \$commitAttribution was NOT added" "$(jget "$I/$TCFG" '$commitAttribution')" -
ok "the bundle's own \$mine is still there"    "$(jget "$I/$TCFG" '$mine')" "a note this bundle wrote itself"

# =========================================================================== #
echo
echo "-- 3. ORDER, and a normalised pair round-trips to no findings"
I="$(newinst 4)"
jedit "$I/$TCFG" <<'PY'
for k in list(d)[:6]:
    d[k] = d.pop(k)          # rotate the first six keys to the end
PY
norm "$I" >/dev/null
ok "an out-of-order file reports ORDER"       "$(said 'ORDER')" yes
norm "$I" --apply >/dev/null
ok "…and after --apply the order is the seed's" \
   "$(jkeys "$I/$TCFG")"                      "$(jkeys "$SEED")"
RC="$(norm "$I")"
ok "a normalised pair exits 0"                "$RC" 0
ok "…and says nothing at all"                 "$(wc -c <"$TMP/out" | tr -d ' ')" 0
RC="$(norm "$I" --apply)"
ok "…and --apply on it is a no-op too"        "$RC" 0
# The seed itself must round-trip: a per-machine key shipped in the tracked seed would
# make every fresh stamp report a finding against its own seed.
ok "the seed ships no per-machine path"       "$(jget "$SEED" reposRoot)$(jget "$SEED" worktreeRoot)" --

# =========================================================================== #
echo
echo "-- 4. no value is ever changed"
I="$(newinst 5)"
jedit "$I/$LCFG" <<'PY'
d.pop("reposRoot", None)          # derived by the stamp; this case moves the tracked one
PY
jedit "$I/$TCFG" <<'PY'
d["reposRoot"] = "/moved/away"
d["maxPrLoc"] = 7777
d["org"] = "kept-exactly"
d.pop("maxPrFiles", None)
for k in list(d)[:4]:
    d[k] = d.pop(k)
PY
python3 - "$I/$TCFG" "$I/$LCFG" "$TMP/before.json" <<'PY'
import json, sys
out = {n: json.load(open(p)) for n, p in (("t", sys.argv[1]), ("l", sys.argv[2]))}
json.dump(out, open(sys.argv[3], "w"))
PY
norm "$I" --apply >/dev/null
CHANGED="$(python3 - "$I/$TCFG" "$I/$LCFG" "$TMP/before.json" <<'PY'
import json, sys
now = {n: json.load(open(p)) for n, p in (("t", sys.argv[1]), ("l", sys.argv[2]))}
was = json.load(open(sys.argv[3]))
bad = []
for where, keys in was.items():
    other = now["l" if where == "t" else "t"]
    for k, v in keys.items():
        if v is None:
            continue                      # a null was absence to begin with
        here = now[where][k] if k in now[where] else other.get(k, "<gone>")
        if here not in (v, "<gone>"):
            bad.append("%s.%s" % (where, k))
print(" ".join(bad) or "none")
PY
)"
ok "every surviving value is byte-identical"  "$CHANGED" none
ok "the value that moved is intact"           "$(jget "$I/$LCFG" reposRoot)" /moved/away
ok "a number nobody touched is intact"        "$(jget "$I/$TCFG" maxPrLoc)" 7777
ok "…and a string too"                        "$(jget "$I/$TCFG" org)" kept-exactly

# =========================================================================== #
echo
echo "-- 5. /${PN}:init runs it on every stamp"
I="$(newinst 6)"
ok "a clean pair: the stamp says nothing about config" \
   "$(grep -ci 'config findings' "$TMP/stamp.6" | tr -d ' ')" 0
ok "…and the stamp exits 0"                   "$(grep -c '^Done\.' "$TMP/stamp.6" | tr -d ' ')" 1
jedit "$I/$TCFG" <<'PY'
d.pop("maxPrFiles", None)
PY
# Committed as it stands, so the normalised file really differs from HEAD — otherwise
# `git add` stages nothing and the staging assertion below passes vacuously.
git -C "$I" add -A >/dev/null 2>&1
git -C "$I" -c user.email=t@example.com -c user.name=t commit -qm drift >/dev/null 2>&1
bash "$INIT" "$I" >"$TMP/out" 2>&1
ok "a dirty pair: the stamp REPORTS"          "$(said 'Config findings')" yes
ok "…naming the missing key"                  "$(finding MISSING maxPrFiles)" yes
ok "…and report mode wrote nothing"           "$(jget "$I/$TCFG" maxPrFiles)" -
bash "$INIT" "$I" --normalise-config >"$TMP/out" 2>&1
ok "--normalise-config applies"               "$(said 'applied 2 finding')" yes
ok "…and the key is there"                    "$(jget "$I/$TCFG" maxPrFiles)" 100
ok "…and the tracked file is STAGED"          "$(git -C "$I" diff --cached --name-only)" instance.config.json
ok "…and NOT committed"                       "$(git -C "$I" log --oneline | wc -l | tr -d ' ')" 2

echo
echo "-- 5b. an interactive stamp asks, and takes yes for an answer"
I="$(newinst 7)"
jedit "$I/$TCFG" <<'PY'
d.pop("maxPrFiles", None)
PY
printf 'n\n' | NORMALISE_CONFIG_STDIN=1 bash "$INIT" "$I" >"$TMP/out" 2>&1
ok "it asks"                                  "$(said 'Apply them now')" yes
ok "…and no is no"                            "$(jget "$I/$TCFG" maxPrFiles)" -
printf 'y\n' | NORMALISE_CONFIG_STDIN=1 bash "$INIT" "$I" >"$TMP/out" 2>&1
ok "…and yes applies"                         "$(jget "$I/$TCFG" maxPrFiles)" 100
ok "…saying how many findings were applied"   "$(said 'applied 2 finding')" yes

# =========================================================================== #
echo
echo "-- 6. a stamp never writes a per-machine path into the tracked file"
I="$(newinst 8)"
ok "the tracked file has no reposRoot"        "$(jget "$I/$TCFG" reposRoot)" -
ok "…and no worktreeRoot"                     "$(jget "$I/$LCFG" worktreeRoot)" -
# Nor is a path INVENTED in the local file. The measured harm was a seeded worktreeRoot
# that existed on no disk while 17 tasks used the documented `<reposRoot>/_wt` fallback —
# so worktreeRoot is still written nowhere, while reposRoot is DERIVED from the bundle's
# own parent (init-bundle.sh 4c), a directory that exists by construction.
ok "…and worktreeRoot is invented nowhere"    "$(jget "$I/$LCFG" worktreeRoot)" -
ok "…while reposRoot is the bundle's parent"  "$(jget "$I/$LCFG" reposRoot)" "$(cd "$I/.." && pwd)"
ok "and the stamp is still clean"             "$(grep -ci 'config findings' "$TMP/stamp.8" | tr -d ' ')" 0
# A bundle that already carries a real path keeps it: the seeder must not plant a
# placeholder over a value the normaliser is about to move.
I="$(newinst 9)"
rm -f "$I/$LCFG"
jedit "$I/$TCFG" <<'PY'
d["reposRoot"] = "/real/path/here"
PY
bash "$INIT" "$I" --normalise-config >"$TMP/out" 2>&1
ok "a real tracked path is moved, not replaced" "$(jget "$I/$LCFG" reposRoot)" /real/path/here
ok "…and the tracked file is clean"             "$(jget "$I/$TCFG" reposRoot)" -

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
