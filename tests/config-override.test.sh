#!/usr/bin/env bash
#
# config-override.test.sh — instance.config.local.json overrides the TRACKED config,
# for the documented set of per-machine keys, in every script that reads one.
#
# WHY. `instance.config.json` is tracked, so every value in it is a statement both
# clones of a shared bundle read. `reposRoot`, `worktreeRoot` and `boardInstances` are
# absolute paths on ONE machine, so a tracked value cannot be right for both. The
# override exists for exactly those, plus the two identity keys — and, since 2026-08-29,
# for the three SPEND AND CAPACITY keys: `models`, `roleTiers` and `maxAgentsInFlight`.
# Those are not paths, so they need their own argument: two clones disagreeing about them
# breaks nothing (each dispatch runs on its own machine), while a TRACKED value forces one
# number on every clone — measured 2026-08-29, `maxAgentsInFlight` read 4 / 6 / 10 across
# three instances on one 11-core machine, up to 20 concurrent agents against a ceiling
# near 4.
#
# They also carry a failure mode the paths do not, which is why they are exercised entry
# by entry below rather than as "the override won". `roleTiers` is a MAP, and the override
# anyone actually writes is a PARTIAL one — a single agent moved to a cheaper tier. A
# layering that merges with `dict.update()` replaces the whole map with that one entry, so
# every OTHER agent silently loses its tier and inherits the session model: a one-line
# local file changes seven agents' models, six of them by accident, and nothing looks
# broken.
#
# The failure this file is built to catch is a HALF-HONOURED override: one reader picks
# it up and another does not, so the loop dispatches against one reposRoot while
# `link-repos.sh` links from another. That is worse than having no override at all,
# because nothing looks broken. So every reader is exercised, and there is a static
# check besides — a new reader added without the two-file lookup fails here rather than
# on someone's machine.
#
# The keys that are NOT overridable are asserted too, and they are the sharper half:
# `defaultOwner`, `people` and `externalReviewer` are only correct while both clones
# agree, so an override is precisely the disagreement that breaks them (`defaultOwner`'s
# own case lives in task-owner.test.sh, where the two-clone fixture is). `externalReviewer`
# is the one to hold the line on: it names WHERE THIS CODE MAY BE SENT, which is policy
# rather than preference, and a clone quietly routing diffs to another reviewer breaks in
# the direction nobody notices.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

SCRIPTS="$TPL/plugin/scripts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/config-override.XXXXXX")" || {
  echo "config-override.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
# NOT `grep -q`: under `set -o pipefail`, -q exits at the first match and a LARGE $2 (a
# rendered board page) then SIGPIPEs the printf — pipeline status 141, read as FAIL on
# content that matched. Measured as this suite's recurring CI flake (2026-09-01: three
# reds on unchanged trees, "line 51: printf: write error: Broken pipe" in the one hot
# log). Plain grep reads ALL input, so the writer always finishes; stdout is discarded.
has()    { printf '%s\n' "$2" | grep -- "$1" >/dev/null && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -- "$1" >/dev/null && echo 1 || echo 0; }

# Two candidate roots, so "which one did the script use" is answerable from output.
TRACKED_ROOT="$TMP/tracked-repos"; mkdir -p "$TRACKED_ROOT/repo-t/.git"
LOCAL_ROOT="$TMP/local-repos";     mkdir -p "$LOCAL_ROOT/repo-l/.git"

INST="$TMP/_ai-bridge-fixture"; mkdir -p "$INST/$AB_DIR"
printf 'stub\n' > "$INST/$AB_SCHEMA"
tracked() { printf '{\n  "org": "o",\n  "reposRoot": "%s"\n}\n' "$TRACKED_ROOT" > "$INST/instance.config.json"; }
local_cfg() { printf '%s\n' "$1" > "$INST/instance.config.local.json"; }
no_local() { rm -f "$INST/instance.config.local.json"; }
tracked

echo "== link-repos.sh: which reposRoot did it link from? =="
no_local
OUT="$( cd "$INST" && bash "$SCRIPTS/link-repos.sh" 2>&1 )"
assert "no local file -> the tracked root"       "$(has 'repo-t' "$OUT")"
assert "…and not the other one"                  "$(hasnt 'repo-l' "$OUT")"
( cd "$INST" && bash "$SCRIPTS/link-repos.sh" --remove >/dev/null 2>&1 )
local_cfg "{ \"reposRoot\": \"$LOCAL_ROOT\" }"
OUT="$( cd "$INST" && bash "$SCRIPTS/link-repos.sh" 2>&1 )"
assert "with the override -> the local root"     "$(has 'repo-l' "$OUT")"
assert "…and the tracked one is not used"        "$(hasnt 'repo-t' "$OUT")"
( cd "$INST" && bash "$SCRIPTS/link-repos.sh" --remove >/dev/null 2>&1 )
# A local file that does not mention the key is not an override.
local_cfg '{ "ownerGithubUser": "example-user-007" }'
OUT="$( cd "$INST" && bash "$SCRIPTS/link-repos.sh" 2>&1 )"
assert "a local file without the key defers"     "$(has 'repo-t' "$OUT")"
( cd "$INST" && bash "$SCRIPTS/link-repos.sh" --remove >/dev/null 2>&1 )

echo
echo "== prune-worktrees.sh: reposRoot and worktreeRoot =="
# Naming a root that does not exist is the cheapest unambiguous probe: the script
# reports the path it resolved, so the message says which file answered.
local_cfg '{ "reposRoot": "/nonexistent-local-root" }'
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"; RC=$?
assert "the overridden reposRoot is the one used" "$(has 'nonexistent-local-root' "$OUT")"
assert "…and it refuses rather than guessing"    "$([[ $RC -ne 0 ]] && echo 0 || echo 1)"
no_local
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"
assert "without the override, the tracked root"  "$(hasnt 'nonexistent-local-root' "$OUT")"
# worktreeRoot: an overridden path that does not exist is reported by name.
local_cfg '{ "worktreeRoot": "/nonexistent-local-wt" }'
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"
assert "the overridden worktreeRoot is used"     "$(has 'nonexistent-local-wt' "$OUT")"
# Absent from both, the documented fallback still applies: <reposRoot>/_wt.
no_local
OUT="$( cd "$INST" && bash "$SCRIPTS/prune-worktrees.sh" 2>&1 )"
assert "absent worktreeRoot -> <reposRoot>/_wt"  "$(has '_wt' "$OUT")"

echo
echo "== index-kb.sh: reposRoot (behind a stubbed codegraph) =="
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/codegraph"; chmod +x "$TMP/bin/codegraph"
local_cfg '{ "reposRoot": "/nonexistent-local-root" }'
OUT="$( cd "$INST" && PATH="$TMP/bin:$PATH" bash "$SCRIPTS/index-kb.sh" 2>&1 )"
assert "the overridden reposRoot is the one used" "$(has 'nonexistent-local-root' "$OUT")"
no_local
OUT="$( cd "$INST" && PATH="$TMP/bin:$PATH" bash "$SCRIPTS/index-kb.sh" 2>&1 )"
assert "without it, the tracked root is used"     "$(hasnt 'nonexistent-local-root' "$OUT")"
# codegraphSkip is NOT overridable: it names repos, which both clones share. Assert
# the extraction line itself, not proximity — the file mentions both names elsewhere.
assert "codegraphSkip is extracted from \$CONFIG only" \
  "$(grep -q 'CONFIG_SKIP=.*"\$CONFIG"' \
       <<<"$(grep -n 'codegraphSkip' "$SCRIPTS/index-kb.sh" | grep -v '^[0-9]*:#')" && echo 0 || echo 1)"

echo
echo "== build-board.sh: boardInstances =="
if command -v python3 >/dev/null 2>&1; then
  # The fixture carries a PROJECT whose title is the group name, and the assertions read
  # that title off the page. An instance with no projects renders nothing that names it
  # (the masthead title is derived and title-cased), so a bare `has '<group>'` on an
  # empty snapshot would be asserting against a page the group never reaches — green
  # whichever list won.
  mk_inst() { mkdir -p "$1/$AB_DIR"; printf '{"group":"%s","counts":{"projects":1,"tasks":0,"awaiting":0},"projects":[{"slug":"p","title":"%s","status":"active","tasks":[]}]}\n' "$2" "$2" > "$1/$AB_SNAPSHOT"; }
  mk_inst "$TMP/inst-tracked" tracked-group
  mk_inst "$TMP/inst-local"   local-group
  printf '{\n  "org": "o",\n  "boardInstances": ["%s"]\n}\n' "$TMP/inst-tracked" > "$INST/instance.config.json"
  no_local
  ( cd "$INST" && bash "$SCRIPTS/build-board.sh" --out "$TMP/b1.html" >/dev/null 2>&1 )
  assert "no local file -> the tracked list"     "$(has 'class="ptitle">tracked-group' "$(cat "$TMP/b1.html" 2>/dev/null)")"
  local_cfg "{ \"boardInstances\": [\"$TMP/inst-local\"] }"
  ( cd "$INST" && bash "$SCRIPTS/build-board.sh" --out "$TMP/b2.html" >/dev/null 2>&1 )
  B2="$(cat "$TMP/b2.html" 2>/dev/null)"
  assert "with the override -> the local list"   "$(has 'class="ptitle">local-group' "$B2")"
  assert "…and not the tracked one"              "$(hasnt 'class="ptitle">tracked-group' "$B2")"
  # An unreadable local file must not blank the board: the tracked list still answers.
  local_cfg '{ not json at all'
  ( cd "$INST" && bash "$SCRIPTS/build-board.sh" --out "$TMP/b3.html" >"$TMP/b3.out" 2>&1 )
  assert "an unreadable local file falls back"   "$(has 'class="ptitle">tracked-group' "$(cat "$TMP/b3.html" 2>/dev/null)")"
  assert "…and says so without claiming more"    "$(has 'ignoring it' "$(cat "$TMP/b3.out")")"
  no_local
  tracked
else
  echo "  (python3 absent — build-board cases skipped)"
fi

echo
echo "== resolve-model.sh / resolve-max-agents.sh: spend and capacity read local-first =="
if command -v python3 >/dev/null 2>&1; then
  spend_cfg() { printf '%s\n' '{
  "org": "o",
  "maxAgentsInFlight": 9,
  "models":    { "light": "haiku", "standard": "sonnet", "deep": "opus" },
  "roleTiers": { "software-engineer": "deep", "cataloguer": "standard" }
}' > "$INST/instance.config.json"; }
  MODEL() { ( cd "$INST" && bash "$SCRIPTS/resolve-model.sh" "$1" 2>/dev/null ); }
  CAP()   { ( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null ); }
  spend_cfg
  no_local
  assert "no local file -> the tracked tier answers (deep -> opus)" \
    "$([ "$(MODEL software-engineer)" == opus ] && echo 0 || echo 1)"
  assert "no local file -> the tracked cap answers (9)" \
    "$([ "$(CAP)" == 9 ] && echo 0 || echo 1)"

  # THE PARTIAL OVERRIDE. One roleTiers entry named; every other entry must survive.
  local_cfg '{ "roleTiers": { "cataloguer": "light" }, "maxAgentsInFlight": 2 }'
  assert "a partial roleTiers override moves the entry it names (light -> haiku)" \
    "$([ "$(MODEL cataloguer)" == haiku ] && echo 0 || echo 1)"
  assert "…and the entries it does NOT name keep their tracked tier" \
    "$([ "$(MODEL software-engineer)" == opus ] && echo 0 || echo 1)"
  assert "…and the cap comes from the local file (2, not the tracked 9)" \
    "$([ "$(CAP)" == 2 ] && echo 0 || echo 1)"

  # Same shape for `models`: retier ONE alias, leave the rest of the map standing. The
  # two agents resolve to different aliases here on purpose — an override making both
  # equal would pass whichever map won.
  local_cfg '{ "models": { "deep": "haiku" } }'
  assert "a partial models override retiers the tier it names (deep -> haiku)" \
    "$([ "$(MODEL software-engineer)" == haiku ] && echo 0 || echo 1)"
  assert "…and the tiers it does not name are untouched (standard -> sonnet)" \
    "$([ "$(MODEL cataloguer)" == sonnet ] && echo 0 || echo 1)"

  # A local file naming neither key is not an override of either — absence behaves as
  # it always did, which is what a single-human instance sees.
  local_cfg '{ "ownerGithubUser": "example-user-007" }'
  assert "a local file without the keys defers to the tracked tier" \
    "$([ "$(MODEL software-engineer)" == opus ] && echo 0 || echo 1)"
  assert "…and to the tracked cap" \
    "$([ "$(CAP)" == 9 ] && echo 0 || echo 1)"

  # An unreadable local file must not blank the tracked answer, for the same reason
  # build-board.sh must not blank the board.
  local_cfg '{ not json at all'
  assert "an unreadable local file falls back to the tracked tier" \
    "$([ "$(MODEL software-engineer)" == opus ] && echo 0 || echo 1)"
  assert "…and to the tracked cap" \
    "$([ "$(CAP)" == 9 ] && echo 0 || echo 1)"

  # Absent from BOTH files, neither resolver invents a value: it prints nothing and
  # exits 1, and the CALLER applies the fallback its own document states.
  printf '{\n  "org": "o"\n}\n' > "$INST/instance.config.json"
  no_local
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )"; RC=$?
  assert "no cap in either file -> prints nothing"  "$([ -z "$OUT" ] && echo 0 || echo 1)"
  assert "…and exits 1 rather than inventing a number" "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-model.sh" software-engineer 2>/dev/null )"; RC=$?
  assert "no roleTiers in either file -> prints nothing" "$([ -z "$OUT" ] && echo 0 || echo 1)"
  assert "…and exits 1, so the agent inherits the session model" "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
  # …AND IT IS NOT QUIET ABOUT IT. Absence is still not an error and stdout is still
  # empty — every caller captures stdout, and a word printed there becomes a model alias
  # — but exiting silently was the failure shape rather than the fallback: an unresolved
  # role is indistinguishable from a resolved one at the call site, so every role can run
  # on the wrong tier with nothing anywhere saying so. `local-tier-seed.test.sh` owns the
  # detail of that line; what belongs HERE, beside the two-file precedence, is that the
  # per-machine layering can never end in silence.
  ERR="$( cd "$INST" && bash "$SCRIPTS/resolve-model.sh" software-engineer 2>&1 >/dev/null )"
  assert "…and says so on stderr rather than exiting quietly" \
    "$([ -n "$ERR" ] && echo 0 || echo 1)"
  assert "…naming the agent it could not resolve" "$(has 'software-engineer' "$ERR")"

  # A cap that is not a positive integer is refused, not rounded. `isinstance(True, int)`
  # is True in Python, so `true` would otherwise resolve to a cap of 1 and look chosen.
  printf '{\n  "maxAgentsInFlight": true\n}\n' > "$INST/instance.config.json"
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )"; RC=$?
  assert "a boolean cap is refused, not read as 1" \
    "$([ -z "$OUT" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1)"
  printf '{\n  "maxAgentsInFlight": 0\n}\n' > "$INST/instance.config.json"
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )"; RC=$?
  assert "a cap of 0 is refused rather than dispatching nothing forever" \
    "$([ -z "$OUT" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1)"
  # THE TYPE, NOT JUST THE DIGITS, and this pair exists because the merge moved into
  # resolve-config.sh. Its plain output prints a string BARE, so `"4"` and `4` would reach
  # a shell caller identical and a quoted cap would silently start being accepted — a
  # widening of a contract whose whole job is to refuse. `resolve-max-agents.sh` asks for
  # `--json` precisely so the quotes survive; without that it passes this test's first
  # half and fails its second.
  printf '{\n  "maxAgentsInFlight": "4"\n}\n' > "$INST/instance.config.json"
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )"; RC=$?
  assert "a QUOTED cap is refused, not read as the number 4" \
    "$([ -z "$OUT" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1)"
  printf '{\n  "maxAgentsInFlight": 4.0\n}\n' > "$INST/instance.config.json"
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )"; RC=$?
  assert "…and a float is refused rather than truncated"  \
    "$([ -z "$OUT" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1)"
  # A JSON `null` IS ABSENCE, at every layer and in every mode. THE DEFECT THIS PINS,
  # reproduced before it was fixed: with `"models": {"deep": null}` and a role on `deep`,
  # `resolve-model.sh` printed the four letters `null` and exited 0 — so a dispatcher would
  # have asked for a model NAMED "null" instead of falling back to the session model. The
  # `--dump` side matters just as much: the banner reads the dump, and a null leaf there is
  # a settings row asserting a value the config does not have.
  printf '%s\n' '{
  "org": "o",
  "maxAgentsInFlight": 9,
  "models":    { "light": "haiku", "standard": "sonnet", "deep": null },
  "roleTiers": { "software-engineer": "deep", "cataloguer": "standard" }
}' > "$INST/instance.config.json"
  no_local
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-model.sh" software-engineer 2>/dev/null )"; RC=$?
  assert "a null model alias prints nothing…" "$([ -z "$OUT" ] && echo 0 || echo 1)"
  assert "…and exits 1, exactly as an absent key does" "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
  assert "…never the literal string 'null' as an alias" \
    "$([ "$OUT" != null ] && echo 0 || echo 1)"
  assert "…while the sibling entry still resolves (standard -> sonnet)" \
    "$([ "$(MODEL cataloguer)" == sonnet ] && echo 0 || echo 1)"
  DUMP="$( bash "$SCRIPTS/resolve-config.sh" --instance "$INST" --dump 2>/dev/null )"
  assert "--dump omits the null leaf entirely" \
    "$(grep -qE '^[a-z]+	models	deep	' <<<"$DUMP" && echo 1 || echo 0)"
  assert "…and still carries the leaves beside it" \
    "$(grep -q 'models	standard	sonnet' <<<"$DUMP" && echo 0 || echo 1)"
  for M in "" --source --json; do
    OUT="$( bash "$SCRIPTS/resolve-config.sh" --instance "$INST" $M models deep 2>/dev/null )"; RC=$?
    assert "resolve-config ${M:---value} models.deep: nothing, exit 1" \
      "$([ -z "$OUT" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1)"
  done
  # A whole key set to null, and the same key nulled in the LOCAL file over a real tracked
  # value: "null is absence" has to hold at every layer, or the per-machine file could not
  # UNSET an inherited key at all.
  printf '{\n  "maxAgentsInFlight": null\n}\n' > "$INST/instance.config.json"
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )"; RC=$?
  assert "a null cap is refused, not read as a value" \
    "$([ -z "$OUT" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1)"
  printf '{\n  "maxAgentsInFlight": 9\n}\n' > "$INST/instance.config.json"
  local_cfg '{ "maxAgentsInFlight": null }'
  OUT="$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )"; RC=$?
  assert "a LOCAL null unsets the tracked value rather than being ignored" \
    "$([ -z "$OUT" ] && [ "$RC" -eq 1 ] && echo 0 || echo 1)"
  no_local

  # And the mirror, without which the assertion above would pass a resolver that
  # complained on every call — as useless as one that never complained, since a warning
  # printed on the happy path is a warning nobody reads.
  printf '%s\n' '{
  "org": "o",
  "models":    { "deep": "opus" },
  "roleTiers": { "software-engineer": "deep" }
}' > "$INST/instance.config.json"
  ERR="$( cd "$INST" && bash "$SCRIPTS/resolve-model.sh" software-engineer 2>&1 >/dev/null )"
  assert "…while a RESOLVABLE agent prints nothing on stderr at all" \
    "$([ -z "$ERR" ] && echo 0 || echo 1)"

  # Non-vacuity for the three refusals above: the same resolver still answers a real one.
  printf '{\n  "maxAgentsInFlight": 4\n}\n' > "$INST/instance.config.json"
  assert "…while a plain integer cap still resolves"      \
    "$([ "$( cd "$INST" && bash "$SCRIPTS/resolve-max-agents.sh" 2>/dev/null )" = 4 ] && echo 0 || echo 1)"
  tracked
else
  echo "  (python3 absent — resolver cases skipped)"
fi

echo
echo "== static: every reader of an overridable key does the two-file lookup =="
# The drift guard. A reader added later that parses only instance.config.json makes the
# override a half-truth, which is the failure mode this file exists for.
for pair in "link-repos.sh:reposRoot" "index-kb.sh:reposRoot" \
            "prune-worktrees.sh:reposRoot" "prune-worktrees.sh:worktreeRoot" \
            "build-board.sh:boardInstances" "commit-as.sh:authorEmail" \
            "task-owner.sh:ownerGithubUser" "resolve-model.sh:roleTiers" \
            "resolve-model.sh:models" "resolve-max-agents.sh:maxAgentsInFlight" \
            "resolve-config.sh:instance.config.json"; do
  f="${pair%%:*}"; k="${pair##*:}"
  assert "$f reads $k, and knows the local file" \
    "$( grep -q "$k" "$SCRIPTS/$f" && grep -q 'instance.config.local.json' "$SCRIPTS/$f" && echo 0 || echo 1 )"
done
# THE TWO SPEND RESOLVERS NO LONGER IMPLEMENT THE RULE, THEY DELEGATE IT. The grep above
# is satisfied by prose, which was tolerable while each script carried its own copy of the
# merge and became a hole the moment they stopped. `resolve-config.sh` is now the single
# implementation — one file to keep correct, and one file the banner's FROM column reads
# through — so assert the delegation rather than the vocabulary.
for f in resolve-model.sh resolve-max-agents.sh; do
  assert "$f delegates the precedence to resolve-config.sh" \
    "$( grep -q 'resolve-config\.sh' "$SCRIPTS/$f" && echo 0 || echo 1 )"
  # And does not keep a private copy beside it: a second json.load of the two layers in
  # the same file is the drift this consolidation exists to prevent.
  assert "…and re-implements no second reader of its own" \
    "$( grep -q 'json\.load' "$SCRIPTS/$f" && echo 1 || echo 0 )"
done
assert "resolve-config.sh reports which file won, per leaf" \
  "$( grep -q -- '--source' "$SCRIPTS/resolve-config.sh" && echo 0 || echo 1 )"
# And the keys that must NOT be overridable are read from the tracked file only.
# `board` is the newest of them, and the sharpest illustration of why the direction
# matters: it has TWO readers at opposite ends of an instance's life — `install.sh` at
# stamp time, deciding whether SNAPSHOT.json is seeded, and the SessionStart hook plus the
# /pm-loop tick afterwards, deciding whether the board is rendered and surfaced. The
# installer reads the tracked file and nothing else, so a per-machine override would give
# one key two answers, and the half that disagreed would be the silent one.
# ASSERTED BEHAVIOURALLY, NOT BY GREP, and the change is forced rather than stylistic.
# The old form here grepped `show-board-link.sh` for `instance.config.local.json` and
# demanded NO match. That hook is now one section of `session-banner.sh`, which reads the
# local file legitimately for its settings block — so the grep would fail on a correct
# hook, and relaxing it would leave the property untested. What matters is not which
# strings the file contains but whether a LOCAL `board: false` can silence a board the
# TRACKED file switched on. So flip the switch in each file in turn and look at the
# output, which is the same two-sided shape that caught `board` shipping inert once
# already (a reader that always answers "default" passes any one-sided test).
BANNER="$TPL/plugin/hooks/session-banner.sh"
BINST="$TMP/_board-gate"; mkdir -p "$BINST/.claude/agents" "$BINST/$AB_BOARD_DIR"
printf '<!doctype html>\n' > "$BINST/$AB_BOARD_DIR/board.html"
banner_out() { CLAUDE_PROJECT_DIR="$BINST" bash "$BANNER" 2>&1; }

printf '{ "org": "o", "board": true }\n'  > "$BINST/instance.config.json"
printf '{ "board": false }\n'             > "$BINST/instance.config.local.json"
assert "a LOCAL board:false cannot switch off a tracked board:true" \
  "$(has 'Board   file://' "$(banner_out)")"
# The mirror: the tracked file is the one that decides, so flipping it there DOES work.
# Without this half, a banner that never printed a board line would pass the assertion
# above and the gate would be untested in the direction that matters.
printf '{ "org": "o", "board": false }\n' > "$BINST/instance.config.json"
printf '{ "board": true }\n'              > "$BINST/instance.config.local.json"
assert "…while the TRACKED board:false still switches it off" \
  "$(hasnt 'Board   file://' "$(banner_out)")"
rm -rf "$BINST"
assert "install.sh still reads the same key, at stamp time" \
  "$( grep -q 'cfg_bool board true' "$TPL/plugin/scripts/init-bundle.sh" && echo 0 || echo 1 )"
assert "…from the tracked instance.config.json" \
  "$( grep -q 'cfg_bool board true "$TARGET/instance.config.json"' "$TPL/plugin/scripts/init-bundle.sh" && echo 0 || echo 1 )"
assert "task-owner.sh reads defaultOwner from the tracked config" \
  "$(grep -q 'json_string "\$CONFIG" defaultOwner' "$SCRIPTS/task-owner.sh" && echo 0 || echo 1)"
assert "…and never from the local one" \
  "$(grep -q 'LOCAL_CONFIG" defaultOwner' "$SCRIPTS/task-owner.sh" && echo 1 || echo 0)"
assert "commit-as.sh reads people from the tracked config" \
  "$(grep -q 'TRACKED_CONFIG' "$SCRIPTS/commit-as.sh" && echo 0 || echo 1)"
assert "…and never people from the local one" \
  "$(grep -q 'LOCAL_CONFIG.*people\|people.*LOCAL_CONFIG' "$SCRIPTS/commit-as.sh" && echo 1 || echo 0)"
# `externalReviewer` has only PROSE readers today (new-project.md's review route). Same
# rule, other path — and the sharpest of the three, because it decides where a diff is
# sent, so a local override is a policy change nobody reviews.
NEWPROJ="$TPL/plugin/skills/new-project/SKILL.md"
assert "new-project.md reads externalReviewer from the tracked config" \
  "$(grep -q 'externalReviewer.*instance\.config\.json' "$NEWPROJ" && echo 0 || echo 1)"
assert "…and never from the local one" \
  "$(grep -q 'externalReviewer.*instance\.config\.local\.json' "$NEWPROJ" && echo 1 || echo 0)"
# A resolver nothing calls does not make an override real: the cap's only consumers are
# the PM's prose, so they must name the script rather than the tracked file alone.
# The tick's dispatch step is its own file since ai-bridge-v3/task-024.
for f in "$TPL/plugin/skills/dispatch/SKILL.md" "$TPL/plugin/tick-steps/step-3-dispatch.md"; do
  assert "$(basename "$f") resolves the cap with resolve-max-agents.sh" \
    "$(grep -q 'resolve-max-agents\.sh' "$f" && echo 0 || echo 1)"
done

echo
echo "== the overridable set is documented in ONE place =="
SCHEMA="$TPL/plugin/seed/SCHEMA.md"
assert "SCHEMA.md has the override section" \
  "$(grep -q '^## Per-machine config overrides' "$SCHEMA" && echo 0 || echo 1)"
for k in ownerGithubUser authorEmail reposRoot worktreeRoot boardInstances board \
         models roleTiers maxAgentsInFlight defaultOwner people externalReviewer; do
  assert "…and names $k"  "$(grep -q "\`$k\`" "$SCHEMA" && echo 0 || echo 1)"
done
# The three keys that moved on 2026-08-29 must be listed as overridable IN THE TABLE, not
# merely mentioned somewhere in the section — `maxAgentsInFlight` has a whole subsection
# of its own, so "is named" would pass with the row absent.
for k in models roleTiers maxAgentsInFlight; do
  assert "…and its table row marks $k overridable" \
    "$(grep -q "^| \`$k\` | \*\*yes\*\*" "$SCHEMA" && echo 0 || echo 1)"
done
assert "…and no longer files them under 'everything else'" \
  "$(grep -qE 'models|roleTiers|maxAgentsInFlight' <<<"$(grep '^| everything else' "$SCHEMA")" && echo 1 || echo 0)"
# And the one that deliberately did NOT move, with the reason stated — an override there
# is a change to where code may be sent, which is the disagreement that breaks it.
# The backtick is UNESCAPED inside these single quotes: `\`` is a GNU regex anchor (the
# start of the buffer), so the escaped spelling matched on BSD grep and never on GNU grep
# (Linux CI, 2026-10-08). The double-quoted patterns above are unaffected — the shell
# strips their backslash before grep sees it.
assert "…and its table row marks externalReviewer NOT overridable, by design" \
  "$(grep -q '^| `externalReviewer` | \*\*no, by design\*\*' "$SCHEMA" && echo 0 || echo 1)"
assert "…and its table row marks board NOT overridable" \
  "$(grep -q '^| `board` | \*\*no\*\*' "$SCHEMA" && echo 0 || echo 1)"
assert "…and says the installer reads it from the tracked file at stamp time" \
  "$(grep -q '^| `board` | .*tracked file at stamp time' "$SCHEMA" && echo 0 || echo 1)"
assert "…and says why: it names where this code may be sent" \
  "$(grep -q 'where this code may be sent' "$SCHEMA" && echo 0 || echo 1)"
assert "…and states the worktreeRoot fallback" \
  "$(grep -q '<reposRoot>/_wt' "$SCHEMA" && echo 0 || echo 1)"
assert "…and that worktreeRoot must not sit inside reposRoot" \
  "$(grep -q 'never sit inside' "$SCHEMA" && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
