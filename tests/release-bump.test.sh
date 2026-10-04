#!/usr/bin/env bash
#
# release-bump.test.sh — the version moves at MERGE time, on the default branch, and a pull
# request that touches `plugin/` carries no bump at all.
#
# WHY THIS FILE EXISTS. Every core PR used to edit the same five places — `VERSION`,
# `plugin/VERSION`, both manifests and the banner sample in `docs/operations.md` — so any
# two open core PRs conflicted on those five and had to land one at a time, each after a
# fresh merge-main and a full suite run. Measured 2026-09-06 with seven open PRs: the
# version files were the only conflict in five of six merges
# (knowledge/findings/parallel-core-prs-collide-on-one-version-number-…). A user-owned repo
# cannot have a merge queue, so the fix is to take the number out of the PR entirely.
#
# THE INVERSION IS THE PROPERTY, and it is pinned END TO END rather than by grepping prose:
# a fixture checkout takes a real `plugin/` edit with NO version change and
# `tests/template-version.test.sh` must PASS on it, and the same fixture after
# `release-bump.sh` must pass it again. Nothing weaker would notice a harness quietly
# reinstating "a plugin change bumps the version".
#
# THE RELEASE NOTE RIDES IN THE BUMP COMMIT, and `docs/releases/v<new>.md` is the one path
# release-bump.sh forgives on an otherwise clean tree. It is asserted as a file set keyed to
# the version the bump mints, not to a literal, so the next release cannot re-break it; a
# bump that dropped the note turns that assertion red. The flip side is asserted too: a note
# that already shipped is a RECORD, so a later bump must not rewrite its header.
#
# THE LOCKSTEP GUARANTEE IS NOT WEAKENED — the five still have to agree with each other,
# which is exactly what running the real harness in both fixtures asserts.
#
# THE FIXTURE IS `git archive HEAD`, not a clone: a CI checkout of a pull request is a
# DETACHED head, and cloning one produces an empty working tree. It also means this reads
# your last commit, not your unstaged edits.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$REPO/plugin/scripts/release-bump.sh"
[ -f "$BUMP" ] || { echo "release-bump.test: missing $BUMP" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-bump.XXXXXX")" \
  || { echo "release-bump.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# Identity is forced rather than inherited: a machine with no `user.email` would otherwise
# fail every fixture commit for a reason that has nothing to do with this change.
GIT() { git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false "$@"; }
run() { "$BUMP" "$@" >/dev/null 2>&1; echo $?; }

fixture() { # <dir> — this repo at HEAD, committed, on `main`, with an origin/HEAD to match
  mkdir -p "$1"
  GIT -C "$REPO" archive HEAD | tar -x -C "$1"
  GIT -C "$1" init -q -b main >/dev/null 2>&1 || { GIT -C "$1" init -q; GIT -C "$1" checkout -q -b main; }
  GIT -C "$1" add -A >/dev/null
  GIT -C "$1" commit -q -m "fixture: the repo at HEAD"
  GIT -C "$1" update-ref refs/remotes/origin/main "$(GIT -C "$1" rev-parse HEAD)"
  GIT -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
plant() { # <dir> <version> — set VERSION alone, so the bump has to move the other four
  printf '%s\n' "$2" > "$1/VERSION"
  GIT -C "$1" commit -q -am "plant $2"
}
plant_companions() { # <dir> <version> — every non-core entry, in BOTH manifests, so the
  # fixture never depends on where the live repo's companions happen to sit
  python3 -c '
import json, io, sys
root, v = sys.argv[1], sys.argv[2]
p = root + "/.claude-plugin/marketplace.json"
mkt = json.load(io.open(p, encoding="utf-8"))
for e in mkt["plugins"]:
    if e["source"] == "./plugin": continue
    e["version"] = v
    m = root + "/" + e["source"].lstrip("./") + "/.claude-plugin/plugin.json"
    d = json.load(io.open(m, encoding="utf-8")); d["version"] = v
    io.open(m, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
io.open(p, "w", encoding="utf-8").write(json.dumps(mkt, indent=2, ensure_ascii=False) + "\n")
' "$1" "$2"
  GIT -C "$1" commit -q -am "plant companions $2"
}
plant_five() { # <dir> <version> — ALL five places, so a fixture built from a HEAD that already
  # sits on the target version still has every place to move (the count assertion needs that)
  python3 -c '
import io, json, re, sys
root, v = sys.argv[1], sys.argv[2]
for rel in ("VERSION", "plugin/VERSION"):
    io.open(root + "/" + rel, "w", encoding="utf-8").write(v + "\n")
for rel in ("plugin/.claude-plugin/plugin.json",):
    d = json.load(io.open(root + "/" + rel, encoding="utf-8")); d["version"] = v
    io.open(root + "/" + rel, "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
p = root + "/.claude-plugin/marketplace.json"; mkt = json.load(io.open(p, encoding="utf-8"))
for e in mkt["plugins"]:
    if e["source"] == "./plugin": e["version"] = v
io.open(p, "w", encoding="utf-8").write(json.dumps(mkt, indent=2, ensure_ascii=False) + "\n")
p = root + "/docs/operations.md"; lines = io.open(p, encoding="utf-8").read().split("\n")
for i, l in enumerate(lines):
    if l.startswith("loopd v"):
        lines[i] = re.sub(r"^loopd v[0-9.]+", "loopd v" + v, l)
        if i + 1 < len(lines) and lines[i+1] and set(lines[i+1]) == {u"\u2500"}: lines[i+1] = u"\u2500" * len(lines[i])
io.open(p, "w", encoding="utf-8").write("\n".join(lines))
' "$1" "$2"
  GIT -C "$1" commit -q -am "plant five $2"
}
next_version() { # <dir> <field> — the number the bump is about to mint, so every assertion
  # below is keyed to it rather than to whatever version this repo happens to sit on
  python3 -c '
import sys
ma, mi, pa = [int(x) for x in open(sys.argv[1] + "/VERSION").read().strip().split(".")]
f = sys.argv[2]
print("%d.0.0" % (ma + 1) if f == "major" else
      "%d.%d.0" % (ma, mi + 1) if f == "minor" else "%d.%d.%d" % (ma, mi, pa + 1))' "$1" "$2"
}
note() { # <dir> <version> — the release note an author writes under docs/releases/
  mkdir -p "$1/docs/releases"
  printf '# loopd %s\n\nwhat changed.\n' "$2" > "$1/docs/releases/v$2.md"
}
mkt_core() { # <dir> — the marketplace version of the entry the host resolves
  python3 -c '
import json, sys
mkt = json.load(open(sys.argv[1] + "/.claude-plugin/marketplace.json", encoding="utf-8"))
print([p["version"] for p in mkt["plugins"] if p.get("source") == "./plugin"][0])' "$1"
}
companions() { # <dir> — every non-core entry as "<marketplace version>/<plugin.json version>"
  python3 -c '
import json, os, sys
root = sys.argv[1]
mkt = json.load(open(root + "/.claude-plugin/marketplace.json", encoding="utf-8"))
out = []
for p in mkt["plugins"]:
    src = p.get("source", "")
    if src == "./plugin":
        continue
    man = os.path.join(root, os.path.normpath(src), ".claude-plugin", "plugin.json")
    out.append("%s/%s" % (p["version"], json.load(open(man, encoding="utf-8"))["version"]))
print(" ".join(out))' "$1"
}
five() { # <dir> — the five places, space-separated, so one assertion reads them all
  printf '%s %s %s %s %s' \
    "$(head -n 1 "$1/VERSION")" "$(head -n 1 "$1/plugin/VERSION")" \
    "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]+"/plugin/.claude-plugin/plugin.json",encoding="utf-8"))["version"])' "$1")" \
    "$(mkt_core "$1")" \
    "$(grep -hoE 'loopd v?[0-9]+\.[0-9]+\.[0-9]+' "$1/docs/operations.md" | sed 's/^loopd v\{0,1\}//' | sort -u)"
}
harness() { # <dir> <harness> — run a real harness IN the fixture; its tally and its exit
  local out rc
  out="$(cd "$1" && bash "tests/$2" 2>&1)"; rc=$?
  printf '%s rc=%d' "$(printf '%s' "$out" | grep -oE 'fail=[0-9]+' | tail -n 1)" "$rc"
}

echo
echo "== 1. the guards: the bump lands on the default branch, on a clean tree =="
ok "no field is a usage error"            "$(run)" 2
ok "an unknown argument is too"           "$(run mayor)" 2
ok "a directory with no VERSION is refused" "$(run patch --repo "$TMP")" 1

fixture "$TMP/guards"
ok "…a clean fixture on its default branch is accepted" "$(run patch --repo "$TMP/guards")" 0
GIT -C "$TMP/guards" checkout -q -b feat/something
ok "…and a FEATURE branch is refused (the PR never carries it)" \
  "$(run patch --repo "$TMP/guards")" 1
ok "…naming the branch it wanted" \
  "$("$BUMP" patch --repo "$TMP/guards" 2>&1 >/dev/null | grep -c "not the default branch 'main'")" 1
GIT -C "$TMP/guards" checkout -q main
printf 'dirty\n' >> "$TMP/guards/README.md"
ok "…and a dirty tree is refused (the bump is its own commit)" \
  "$(run patch --repo "$TMP/guards")" 1
# Three refusals a WRITER must make rather than fall back on. An empty `--repo` used to
# select the script's own checkout, and an unresolvable default branch used to pass.
ok "an empty --repo value is a usage error, not a fallback" "$(run patch --repo)" 2
ok "…and so is --repo="                    "$(run patch --repo=)" 2
fixture "$TMP/noref"
GIT -C "$TMP/noref" symbolic-ref -d refs/remotes/origin/HEAD
ok "…and no origin/HEAD fails CLOSED"      "$(run patch --repo "$TMP/noref")" 1

# NOTHING IS WRITTEN UNTIL EVERY TARGET IS READ AND TRANSFORMED. The two VERSION files used
# to be written before the manifests were even parsed, so a broken marketplace.json left the
# checkout half-moved — the one failure this script must never produce.
fixture "$TMP/partial"
before="$(five "$TMP/partial")"
printf 'not json\n' > "$TMP/partial/.claude-plugin/marketplace.json"
GIT -C "$TMP/partial" commit -q -am "break the marketplace"
ok "an unparseable manifest is refused"    "$(run minor --repo "$TMP/partial")" 1
ok "…having written NOTHING"               "$(head -n 1 "$TMP/partial/VERSION") $(head -n 1 "$TMP/partial/plugin/VERSION")" \
  "$(printf '%s' "$before" | cut -d' ' -f1) $(printf '%s' "$before" | cut -d' ' -f2)"

echo
echo "== 2. one script writes all five places, and the banner rule follows =="
fixture "$TMP/five"
plant "$TMP/five" 2.4.7
ok "patch is accepted"                     "$(run patch --repo "$TMP/five")" 0
ok "…and moves the last field in all five" "$(five "$TMP/five")" "2.4.8 2.4.8 2.4.8 2.4.8 2.4.8"
ok "…while minor moves the middle one and zeroes the last" \
  "$(run minor --repo "$TMP/five" >/dev/null; five "$TMP/five")" "2.5.0 2.5.0 2.5.0 2.5.0 2.5.0"
# The `─` rule under the sampled banner header is as wide as the header, in CHARACTERS —
# `·` is two bytes and `─` is three, so this is the one place a byte count reads as correct
# and is not. 2.9.0 -> 2.10.0 is the shortest bump that lengthens the header.
plant "$TMP/five" 2.9.0
run minor --repo "$TMP/five" >/dev/null
ok "…and the banner rule is re-cut to the new header's WIDTH" \
  "$(python3 -c '
import io, re, sys
lines = io.open(sys.argv[1] + "/docs/operations.md", encoding="utf-8").read().splitlines()
bad = [i for i, l in enumerate(lines[:-1])
       if l.startswith("loopd ") and set(lines[i+1]) == {u"─"} and len(lines[i+1]) != len(l)]
print(len(bad))' "$TMP/five")" 0
ok "…on a header that really did get longer"  "$(five "$TMP/five" | cut -d' ' -f1)" 2.10.0

# The v2 release is the case this field was added for: 1.20.0 -> 2.0.0 zeroes BOTH lower
# fields and SHORTENS the banner header, the direction the re-cut had never taken.
fixture "$TMP/major"
plant_five "$TMP/major" 1.20.0
plant_companions "$TMP/major" 1.0.0
ok "major is accepted"                     "$(run major --repo "$TMP/major")" 0
ok "…and moves 1.20.0 to 2.0.0 in all five" "$(five "$TMP/major")" "2.0.0 2.0.0 2.0.0 2.0.0 2.0.0"
ok "…with the banner rule re-cut to the SHORTER header" \
  "$(python3 -c '
import io, sys
lines = io.open(sys.argv[1] + "/docs/operations.md", encoding="utf-8").read().splitlines()
bad = [i for i, l in enumerate(lines[:-1])
       if l.startswith("loopd ") and set(lines[i+1]) == {u"\u2500"} and len(lines[i+1]) != len(l)]
print(len(bad))' "$TMP/major")" 0
# A companion tracks core's MAJOR (plugin/README.md), so the five are not the whole set on
# a major bump — and template-version.test.sh section 3b is what goes red if they are missed.
# Every non-./plugin entry counts, the ai-bridge alias included: its major bump is what
# offers the stub to an install still on ai-bridge@ai-bridge (loopd/task-007).
NC="$(python3 -c 'import json,sys; print(sum(p.get("source") != "./plugin" for p in json.load(open(sys.argv[1]))["plugins"]))' "$REPO/.claude-plugin/marketplace.json")"
each() { local i out=""; for i in $(seq "$NC"); do out="${out:+$out }$1"; done; printf '%s' "$out"; }
ok "…and every companion moved to 2.0.0 in BOTH its manifests" \
  "$(companions "$TMP/major")" "$(each 2.0.0/2.0.0)"
ok "…while a patch bump leaves the companions alone" \
  "$(plant_companions "$TMP/five" 1.0.0; run patch --repo "$TMP/five" >/dev/null; companions "$TMP/five")" "$(each 1.0.0/1.0.0)"
ok "…and template-version.test.sh passes on 2.0.0" \
  "$(harness "$TMP/major" template-version.test.sh)" "fail=0 rc=0"
ok "…in ONE commit naming the move"        \
  "$(GIT -C "$TMP/major" log -1 --format=%s)" "chore: VERSION 1.20.0 -> 2.0.0 (bumped on main after the merge)"
ok "…carrying the five places and the $NC non-core manifests, nothing else" \
  "$(GIT -C "$TMP/major" show --name-only --format= HEAD | grep -c .)" "$((5 + NC))"

fixture "$TMP/dry"
before="$(five "$TMP/dry")"
ok "--dry-run is accepted"                 "$(run minor --dry-run --repo "$TMP/dry")" 0
ok "…and writes nothing"                   "$(five "$TMP/dry")" "$before"
ok "…and leaves the tree clean"             "$(GIT -C "$TMP/dry" status --porcelain | wc -l | tr -d ' ')" 0
ok "…while naming the five places it would write" \
  "$("$BUMP" minor --dry-run --repo "$TMP/dry" | grep -cE '^(VERSION|plugin/VERSION|plugin/\.claude-plugin/plugin\.json|\.claude-plugin/marketplace\.json|docs/operations\.md)$')" 5

echo
echo "== 3. a PR touching plugin/ WITHOUT a bump passes — the whole point of the change =="
fixture "$TMP/pr"
base="$(head -n 1 "$TMP/pr/VERSION")"
GIT -C "$TMP/pr" checkout -q -b feat/a-plugin-change
printf '\n# a change under plugin/, carrying no version bump\n' >> "$TMP/pr/plugin/scripts/task-owner.sh"
GIT -C "$TMP/pr" commit -q -am "feat: a plugin change with no bump"
ok "the branch really did change plugin/ and NOT the version" \
  "$(GIT -C "$TMP/pr" diff --name-only origin/main...HEAD | grep -cE '^plugin/|^VERSION$' )" 1
ok "…VERSION is untouched"                 "$(head -n 1 "$TMP/pr/VERSION")" "$base"
ok "…and template-version.test.sh PASSES on it" "$(harness "$TMP/pr" template-version.test.sh)" "fail=0 rc=0"

echo
echo "== 4. …and main after release-bump.sh passes the same harness =="
GIT -C "$TMP/pr" checkout -q main
GIT -C "$TMP/pr" merge -q --no-ff -m "merge: the plugin change" feat/a-plugin-change
# A note that already SHIPPED records the version it shipped. Planted and committed here so
# the assertion below reads a fixture rather than whatever docs/releases/ holds today.
note "$TMP/pr" 0.1.0
GIT -C "$TMP/pr" add -A >/dev/null
GIT -C "$TMP/pr" commit -q -m "docs: a release note that already shipped"
# The note for the version being cut is written and left UNCOMMITTED: the bump commit is
# what carries it, which is the only way "the release commit carries the note" can hold —
# the script refuses a dirty tree, so there is no second commit to put it in.
NEXT="$(next_version "$TMP/pr" minor)"
note "$TMP/pr" "$NEXT"
ok "release-bump.sh runs on the merged main" "$(run minor --repo "$TMP/pr")" 0
ok "…template-version.test.sh passes there too" "$(harness "$TMP/pr" template-version.test.sh)" "fail=0 rc=0"
ok "…in ONE commit carrying the five places AND the note for $NEXT" \
  "$(GIT -C "$TMP/pr" show --name-only --format= HEAD | grep . | LC_ALL=C sort | tr '\n' ' ')" \
  ".claude-plugin/marketplace.json VERSION docs/operations.md docs/releases/v$NEXT.md plugin/.claude-plugin/plugin.json plugin/VERSION "
ok "…leaving the SHIPPED note on the version it shipped" \
  "$(head -n 1 "$TMP/pr/docs/releases/v0.1.0.md")" "# loopd 0.1.0"
# The note is the ONLY path the dirty-tree refusal forgives; widening it to anything else
# would let an unrelated edit ride into a release commit.
printf '\n# an edit that is not a release note\n' >> "$TMP/pr/plugin/scripts/task-owner.sh"
ok "…while any OTHER dirty path still refuses" "$(run patch --repo "$TMP/pr")" 1
GIT -C "$TMP/pr" checkout -q -- .
# `claude plugin update` compares the installed version against plugin.json and does
# nothing when they match, so a bump that misses that file is a release nobody is offered.
ok "…including plugin.json, so a plugin update sees the bump" \
  "$(GIT -C "$TMP/pr" show --name-only --format= HEAD | grep -c '^plugin/\.claude-plugin/plugin\.json$')" 1
ok "…and the commit names the move"        \
  "$(GIT -C "$TMP/pr" log -1 --format=%s | grep -cE '^chore: VERSION [0-9.]+ -> [0-9.]+ \(bumped on main')" 1

echo
echo "== 5. it is the ONLY writer — nothing else moves a version place =="
# A WRITE is a redirection, a `sed -i` or a `tee` whose TARGET is one of the five — not a
# line that merely names one, which is why the place has to follow the operator with no
# space between. Comment lines are dropped first: `<root>/…` in prose carries a `>`.
WRITE='(>[[:space:]]*"?[^[:space:]|&]*(VERSION|plugin\.json|marketplace\.json)'
WRITE="$WRITE"'|sed -i[^|]*(VERSION|plugin\.json|marketplace\.json)'
WRITE="$WRITE"'|tee[[:space:]][^|]*(VERSION|plugin\.json|marketplace\.json))'
writers() { # <file…> -> the basenames that write a version place
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = release-bump.sh ] && continue
    grep -qE "$WRITE" <<<"$(grep -vE '^[[:space:]]*#' "$f")" && printf '%s\n' "${f##*/}"
  done
  return 0
}
ok "no other shipped script or workflow writes one" \
  "$(writers "$REPO"/plugin/scripts/*.sh "$REPO"/plugin/hooks/*.sh "$REPO"/.github/workflows/* | tr '\n' ' ')" ""
# The detector has to be able to fire, or the line above passes on a scan that matches
# nothing — the planted script is the shape a second bump path would actually take.
mkdir -p "$TMP/planted"
printf '#!/usr/bin/env bash\nprintf "9.9.9\\n" > "$root/VERSION"\n' > "$TMP/planted/second-bumper.sh"
ok "…and that scan catches a planted second writer" \
  "$(writers "$TMP/planted/second-bumper.sh")" second-bumper.sh
ok "…nothing bumps automatically on merge either" \
  "$(grep -rlE '(VERSION|marketplace\.json)' "$REPO"/.github/workflows/ | wc -l | tr -d ' ')" 0

echo
echo "== 6. the docs carry the new order: merge, bump, push =="
saw() { grep -Fq -- "$2" "$1" && echo yes || echo no; }
OPS="$REPO/docs/operations.md"
ok "operations.md names the order"          "$(saw "$OPS" 'merge, bump, push')" yes
ok "…and the three fields it takes"         "$(saw "$OPS" 'release-bump.sh <major|minor|patch>')" yes
ok "conventions.md 20 says when major is right" \
  "$(saw "$REPO/docs/conventions.md" '`major` when the owner declares a release')" yes
ok "…and the script that does it"           "$(saw "$OPS" 'release-bump.sh')" yes
ok "…and that the bump commit goes straight to main" "$(saw "$OPS" 'straight to main')" yes
ok "…and that main's own suite on push is the check" \
  "$(saw "$OPS" "main's suite on the push is the check")" yes
ok "CLAUDE.md's core bullet says the PR does not carry it" \
  "$(saw "$REPO/CLAUDE.md" 'A change to `core` carries NO version bump')" yes
ok "machinery.md carries it"                "$(saw "$REPO/.claude/rules/machinery.md" 'carries NO version bump')" yes
ok "installer.md carries it"                "$(saw "$REPO/.claude/rules/installer.md" 'carries NO version bump')" yes
ok "the seed CONVENTIONS.md carves the repo out" \
  "$(saw "$REPO/plugin/seed/CONVENTIONS.md" 'THE BUMP HAPPENS ON THE DEFAULT BRANCH AT MERGE TIME')" yes

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
