#!/usr/bin/env bash
#
# init-local-config.test.sh — `/<plugin>:init` writes this clone's
# `instance.config.local.json` when there is none, DERIVING what the machine already knows
# and REPORTING by name what it cannot. ai-bridge-2x/task-009.
#
# WHY. A clone of a shared bundle is not a first stamp, so the roster prompt never runs
# there: every second human hand-wrote `ownerGithubUser`, `authorEmail` and `reposRoot`
# before the banner knew who they were. All three are knowable on that machine.
#
# THE FOUR PROPERTIES, and each is a refusal as much as a write:
#   1. ABSENT + DERIVABLE — the file is written with the three keys, from `gh api user`,
#      the tracked `people` map and the bundle's parent directory.
#   2. ABSENT + NOTHING TO DERIVE FROM — the key is NAMED on a `needs` line and left out.
#      Never guessed, and the rest of the file is still written.
#   3. FLAGS override the derivation, so the skill can pass a human's answer back with no
#      terminal in the loop; an invalid one is refused rather than written.
#   4. AN EXISTING LOCAL FILE IS NEVER REWRITTEN — the normaliser owns its shape — and one
#      already carrying the three keys makes the step silent.
# Plus the guard the normaliser needs: a value the TRACKED config answers is not shadowed
# by a derived one.
#
# THE ENVIRONMENT IS PINNED, not inherited: a `gh` stub on PATH and a neutralised git
# identity. Without that this file passes or fails on whether the developer happens to be
# logged into GitHub — the same machine-dependence that makes a fixture useless.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/initlocal.XXXXXX")" || {
  echo "init-local-config.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd)"   # a TMPDIR ending in `/` yields `//`, which no `pwd` returns
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "init-local-config.test: python3 absent — every assertion here reads JSON." >&2
  echo "pass=0 fail=0"; exit 0
fi

# A throwaway plain-directory copy of the template: init-bundle.sh reads `plugin/seed/`,
# and a harness that passed this checkout would stamp from a git worktree.
make_tpl() { # <dir>
  local d="$1" f
  mkdir -p "$d"
  ( cd "$REPO" && git ls-files . ) | while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$d/$(dirname "$f")"; cp "$REPO/$f" "$d/$f" 2>/dev/null || true
  done
  chmod +x "$d"/plugin/scripts/*.sh 2>/dev/null || true
}
TPL="$TMP/tpl"; make_tpl "$TPL"
INIT="$TPL/plugin/scripts/init-bundle.sh"
[ -f "$INIT" ] || { echo "init-local-config.test: missing $INIT" >&2; exit 2; }

# The `gh` this run sees. `login <name>` answers as that account; `logout` refuses, which
# is what an unauthenticated machine looks like.
STUB="$TMP/bin"; mkdir -p "$STUB"
gh_says() { # <login>|''
  if [ -n "$1" ]; then
    printf '#!/bin/sh\n[ "$1" = api ] || exit 1\nprintf %%s\\\\n "%s"\n' "$1" > "$STUB/gh"
  else
    printf '#!/bin/sh\nexit 1\n' > "$STUB/gh"
  fi
  chmod +x "$STUB/gh"
}
# A stamp with a PINNED identity environment: the stub gh, and a git that can read no
# user.email or github.user of the developer running this.
stamp() { # <instance> [flags…]
  local i="$1"; shift
  PATH="$STUB:$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/home/none" \
    bash "$INIT" "$i" "$@" >"$TMP/out" 2>&1
}
mkdir -p "$TMP/home"
newinst() { local d="$TMP/i$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
said()  { grep -q -- "$1" "$TMP/out" && echo yes || echo no; }
jget()  { python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable"); raise SystemExit(0)
print(d.get(sys.argv[2], "-"))
PY
}
LOCAL=instance.config.local.json
TRACKED=instance.config.json

# =========================================================================== #
echo "-- 1. absent file + derivable values: all three keys are written"
gh_says example-user-007          # the seed's own placeholder login, so people[] answers
I="$(newinst 1)"; stamp "$I"
ok "exits 0"                               "$?" 0
ok "the local file now exists"             "$(yn test -f "$I/$LOCAL")" yes
ok "…and it parses as JSON"                "$(yn python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$I/$LOCAL")" yes
ok "ownerGithubUser came from gh"          "$(jget "$I/$LOCAL" ownerGithubUser)" example-user-007
ok "authorEmail came from people[login]"   "$(jget "$I/$LOCAL" authorEmail)" example-user-007@example.com
ok "reposRoot is the bundle's parent"      "$(jget "$I/$LOCAL" reposRoot)" "$TMP"
ok "…and it says what it wrote"            "$(said 'wrote instance.config.local.json (ownerGithubUser')" yes
ok "nothing is reported missing"           "$(grep -c '  needs ' "$TMP/out" | tr -d ' ')" 0

# =========================================================================== #
echo
echo "-- 2. absent file + no gh login: the key is NAMED, never guessed"
gh_says ''
I="$(newinst 2)"; stamp "$I"
ok "exits 0"                               "$?" 0
ok "ownerGithubUser is left out"           "$(jget "$I/$LOCAL" ownerGithubUser)" -
ok "…and reported by name"                 "$(said 'needs  ownerGithubUser')" yes
ok "…naming the flag that supplies it"     "$(said -- '--owner <github-login>')" yes
ok "authorEmail is left out too"           "$(jget "$I/$LOCAL" authorEmail)" -
ok "…and reported"                         "$(said 'needs  authorEmail')" yes
# The rest of the file is still written: a value that IS derivable is not withheld
# because another one was not.
ok "reposRoot is still written"            "$(jget "$I/$LOCAL" reposRoot)" "$TMP"
ok "…and no reposRoot line is needed"      "$(said 'needs  reposRoot')" no

# =========================================================================== #
echo
echo "-- 3. the flags override the derivation, with no terminal in the loop"
gh_says example-user-007
I="$(newinst 3)"
stamp "$I" --owner example-user-008 --email second@example.org --repos-root /tmp/elsewhere
ok "exits 0"                               "$?" 0
ok "--owner wins over gh"                  "$(jget "$I/$LOCAL" ownerGithubUser)" example-user-008
ok "--email wins over the people map"      "$(jget "$I/$LOCAL" authorEmail)" second@example.org
ok "--repos-root wins over the parent"     "$(jget "$I/$LOCAL" reposRoot)" /tmp/elsewhere
ok "…and nothing is left to ask for"       "$(grep -c '  needs ' "$TMP/out" | tr -d ' ')" 0
# The `--flag=value` spelling too, because a skill may write either.
I="$(newinst 4)"; stamp "$I" --owner=example-user-008
ok "--owner=<value> is accepted"           "$(jget "$I/$LOCAL" ownerGithubUser)" example-user-008
# A flag with no value is a mistake, not an empty answer.
gh_says ''
I="$(newinst 5)"; stamp "$I" --email
ok "a flag with no value exits 2"          "$?" 2
# An invalid value is REFUSED and reported, never written and never silently re-derived.
gh_says example-user-007
I="$(newinst 6)"; stamp "$I" --owner 'not a login'
ok "an invalid --owner is not written"     "$(jget "$I/$LOCAL" ownerGithubUser)" -
ok "…it says why"                          "$(said 'is not a GitHub username')" yes
ok "…and still asks for the value"         "$(said 'needs  ownerGithubUser')" yes

# =========================================================================== #
echo
echo "-- 4. an existing local file is never rewritten by this step"
gh_says example-user-008
I="$(newinst 7)"
cat > "$I/$LOCAL" <<'JSON'
{
  "ownerGithubUser": "example-user-007",
  "authorEmail": "first@example.org",
  "reposRoot": "/somewhere/of/their/own",
  "models": { "deep": "opus" },
  "roleTiers": { "software-engineer": "deep" }
}
JSON
BEFORE="$(cat "$I/$LOCAL")"
stamp "$I" --owner example-user-008
ok "exits 0"                               "$?" 0
ok "the file is byte-identical"            "$([ "$(cat "$I/$LOCAL")" = "$BEFORE" ] && echo yes || echo no)" yes
ok "…so a flag does not reach it either"   "$(jget "$I/$LOCAL" ownerGithubUser)" example-user-007
ok "…and the step says nothing about it"   "$(said 'exists — left alone')" no
ok "…nor asks for anything"                "$(grep -c '  needs ' "$TMP/out" | tr -d ' ')" 0
# A file that exists but is short of a key: the one key the tracked `people` map already
# answers — `authorEmail`, for the login the file names — is FILLED (measured 2026-10-09: a
# second clone typed it by hand although `people` held it); everything else is reported so
# the human knows what their own file is missing.
I="$(newinst 8)"
cat > "$I/$LOCAL" <<'JSON'
{
  "ownerGithubUser": "example-user-007",
  "models": { "deep": "opus" },
  "roleTiers": { "software-engineer": "deep" }
}
JSON
stamp "$I"
ok "authorEmail is filled from people[ownerGithubUser]" "$(jget "$I/$LOCAL" authorEmail)" example-user-007@example.com
ok "…and it says so, naming the source"    "$(said 'set   authorEmail example-user-007@example.com (from people.example-user-007)')" yes
ok "…the other keys survive"               "$(jget "$I/$LOCAL" ownerGithubUser)-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["models"]["deep"])' "$I/$LOCAL")" example-user-007-opus
ok "…and the key it cannot fill is still named" "$(said 'it has no reposRoot')" yes
ok "…with no needs line for authorEmail"   "$(said 'needs  authorEmail')" no
BEFORE="$(cat "$I/$LOCAL")"
stamp "$I"
ok "a second stamp changes nothing"        "$([ "$(cat "$I/$LOCAL")" = "$BEFORE" ] && echo yes || echo no)" yes
# The login is not in `people`: nothing is guessed, the file is byte-identical, and ONE
# needs line names both halves of what is missing. The tracked config is written here so
# the roster holds one login only (the seed's holds both placeholders); the welcome pass a
# non-first stamp runs is skipped, since only step 4c's lines are read.
one_person_cfg() { printf '{ "org": "acme", "group": "acme", "people": { "example-user-007": "example-user-007@example.com" } }\n' > "$1/$TRACKED"; }
I="$(newinst 8b)"; one_person_cfg "$I"
printf '{\n  "ownerGithubUser": "example-user-008",\n  "models": { "deep": "opus" },\n  "roleTiers": { "software-engineer": "deep" }\n}\n' > "$I/$LOCAL"
BEFORE="$(cat "$I/$LOCAL")"
AI_BRIDGE_INIT_PASS=1 stamp "$I"
ok "a login absent from people: untouched" "$([ "$(cat "$I/$LOCAL")" = "$BEFORE" ] && echo yes || echo no)" yes
ok "…and the needs line names the login"   "$(said "names ownerGithubUser 'example-user-008' and \`people\`")" yes
ok "…and the flag that fills it"           "$(said 'needs  authorEmail — re-run with: --email <commit-address>')" yes
AI_BRIDGE_INIT_PASS=1 stamp "$I" --email second@example.org
ok "--email fills an existing file's missing authorEmail" "$(jget "$I/$LOCAL" authorEmail)" second@example.org
ok "…saying where it came from"            "$(said 'set   authorEmail second@example.org (from --email)')" yes
# No ownerGithubUser at all: the same one line, with the absence spelled out.
I="$(newinst 8c)"; one_person_cfg "$I"
printf '{\n  "reposRoot": "/x"\n}\n' > "$I/$LOCAL"
AI_BRIDGE_INIT_PASS=1 stamp "$I"
ok "no login in the file: nothing is guessed" "$(jget "$I/$LOCAL" authorEmail)" -
ok "…and the needs line says so"           "$(said "names ownerGithubUser '<unset>'")" yes

# =========================================================================== #
echo
echo "-- 5. a value the TRACKED config answers is never shadowed"
gh_says example-user-007
I="$(newinst 9)"
python3 - "$TPL/plugin/seed/$TRACKED" "$I/$TRACKED.pre" <<'PY'
import json, sys, collections
d = json.load(open(sys.argv[1]), object_pairs_hook=collections.OrderedDict)
d["reposRoot"] = "/a/path/somebody/chose"
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
mv "$I/$TRACKED.pre" "$I/$TRACKED"
stamp "$I"
ok "the derived parent does not win"       "$(jget "$I/$LOCAL" reposRoot)" -
ok "…and it is not reported missing"       "$(said 'needs  reposRoot')" no
ok "…while the rest is still derived"      "$(jget "$I/$LOCAL" ownerGithubUser)" example-user-007

# =========================================================================== #
echo
echo "-- 6. the wiring: the skill asks only for what was reported, and the docs match"
SKILL="$TPL/plugin/skills/init/SKILL.md"
ok "SKILL.md names the needs line"         "$(yn grep -q 'needs' "$SKILL")" yes
ok "…says ask ONE batched question"        "$(yn grep -q 'one batched question' "$SKILL")" yes
ok "…and never for a derived value"        "$(yn grep -q 'Never ask for a value the script derived' "$SKILL")" yes
ok "…and to re-run with the flags"         "$(yn grep -q 're-run the same command with the flags' "$SKILL")" yes
ok "the flags are in the argument-hint"    "$(yn grep -q 'argument-hint.*--owner' "$SKILL")" yes
SHARING="$TPL/docs/sharing.md"
ok "sharing.md keeps the hand-clone route"  "$(yn grep -q 'git clone <bundle-remote>' "$SHARING")" yes
ok "…naming the plugin install"            "$(yn grep -q '/plugin install '"${PN}@${PMK}"'' "$SHARING")" yes
ok "…stamped by /${PN}:init ."          "$(yn grep -q '^/'"${PN}:"'init \.$' "$SHARING")" yes
ok "…and what init derives each from"      "$(yn grep -q 'the bundle.s parent directory' "$SHARING")" yes
ok "…and that no hand-written file is needed" "$(yn grep -q 'writes the gitignored' "$SHARING")" yes
PATH="$STUB:$PATH" bash "$INIT" --help >"$TMP/out" 2>&1
ok "--help documents --owner"              "$(said -- '--owner')" yes
ok "…and --repos-root"                     "$(said -- '--repos-root')" yes
ok "…and is still not truncated"           "$(said 'Backs up any conflicting real file')" yes

# =========================================================================== #
echo
echo "-- 7. this branch carries no version change (the bump happens at merge)"
# The general rule has its own harness (tests/release-bump.test.sh); this row is the one
# task-009 was asked for, measured against the default branch when there is one to
# measure against.
BASE="$(git -C "$REPO" merge-base origin/main HEAD 2>/dev/null || true)"
if [ -n "$BASE" ]; then
  # The MERGE BASE, not `origin/main`: main carries its own bump commits, and diffing
  # against its tip would report those as this branch's.
  ok "no VERSION file differs from the merge base" \
     "$(git -C "$REPO" diff --name-only "$BASE" HEAD -- VERSION plugin/VERSION \
          | wc -l | tr -d ' ')" 0
  # THE TWO MANIFESTS ARE READ FOR THEIR VERSION STRINGS, NOT COMPARED AS FILES. They carry
  # the number and everything else the plugin declares, so a file-identity check refuses any
  # manifest edit at all — it turned #218 red for adding `experimental.themes`, which moves
  # no version. What this section asserts is that the branch carries no version CHANGE, so
  # that is what is read: every `"version": "…"` in the file, in order.
  vers() { # <rev> <path>
    git -C "$REPO" show "$1:$2" 2>/dev/null \
      | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr '\n' ' '
  }
  # A marketplace entry the branch ADDS carries a version and changes none, so the
  # marketplace is compared per source: every base entry keeps its number.
  if command -v jq >/dev/null 2>&1; then
    vers_mk() { git -C "$REPO" show "$1:.claude-plugin/marketplace.json" 2>/dev/null \
      | jq -r '.plugins[] | "\(.source)=\(.version)"' 2>/dev/null | LC_ALL=C sort; }
    ok "every base marketplace entry keeps its version" \
       "$(LC_ALL=C comm -23 <(vers_mk "$BASE") <(vers_mk HEAD) | tr '\n' ' ')" ""
  fi
  for m in plugin/.claude-plugin/plugin.json .claude-plugin/marketplace.json; do
    [ "$m" = .claude-plugin/marketplace.json ] && command -v jq >/dev/null 2>&1 \
      || ok "$m carries the merge base's version" "$(vers HEAD "$m")" "$(vers "$BASE" "$m")"
    # Two empty reads compare equal, which is how a renamed path would pass this vacuously.
    ok "…and that read found a version at all" \
       "$([ -n "$(vers "$BASE" "$m")" ] && echo yes || echo no)" yes
  done
else
  echo "  SKIP  no merge base with origin/main to compare against"
fi

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
