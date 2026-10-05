#!/usr/bin/env bash
#
# team-setup.test.sh — install.sh offers the team roster on a first stamp, and every
# path that is not "a complete, confirmed answer at a terminal" writes NOTHING.
#
# WHY. The roster (`people` login → commit email, `defaultOwner`, and this clone's
# `instance.config.local.json`) used to be hand-edited after the stamp — the same
# "several manual steps" shape that produced upgrade.sh. Collecting it at install time is
# only safe if the refusals hold, and the refusals are what this file mostly asserts:
#
#   1. A NON-TTY STAMP NEVER PROMPTS. install.sh has to stay safe from a script, from
#      upgrade.sh and from a background agent with no terminal. A prompt nobody can see
#      is a hang, and a hang in a background agent is invisible.
#   2. A REFRESH NEVER PROMPTS. upgrade.sh calls install.sh on EVERY run, including its
#      non-interactive report-only mode, so a prompt outside FIRST_STAMP blocks upgrades.
#   3. A VALUE ALREADY THERE IS NEVER OVERWRITTEN. Seeds-if-absent is what makes this
#      installer safe to re-run on a repo full of somebody's work.
#   4. A HALF-ANSWERED PROMPT WRITES NOTHING. An interrupt, EOF, a declined confirmation
#      and an unreadable line all leave the config byte-identical — a map that resolves
#      for one human and silently falls through for the other is the failure this whole
#      design exists to avoid.
#   5. --config NEVER PROMPTS. It writes into ~/.claude and has no instance at all.
#
# …and then the positive path, because a test that only asserts the refusal would pass a
# script that refuses everything (this directory's rule, and the reason
# installer-worktree-guard.test.sh asserts both directions).
#
# ok() compares actual to expected, in that argument order — the convention in
# config-layer.test.sh, which tests the same script. Inverting it is the mistake this
# codebase keeps making: a command that fails for the WRONG reason becomes a pass through
# a negated helper.
#
# TEAM_SETUP_STDIN=1 is how a piped answer reaches a prompt that is otherwise TTY-only —
# the role SNAPSHOT_NOW plays for write-snapshot.sh. It is set explicitly here and
# nowhere else; the guard it bypasses is asserted directly, above.
#
# Only placeholder identities appear here: `example-user-007` / `example-user-008` (both
# verified 404 on github.com) at `example.com` (RFC 2606). This repo is public and a test
# fixture is copied as readily as a seed file.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/teamsetup.XXXXXX")" || {
  echo "team-setup.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'git -C "$TMP/wtmain" worktree remove --force "$TMP/wtlinked" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# A throwaway copy of the template, so nothing here can touch the real one or a real
# instance. Copied from `git ls-files` (the working tree, so an edit under review is what
# runs) like retire-machinery.test.sh does.
make_tpl() { # <dir>
  local d="$1" f
  mkdir -p "$d"
  ( cd "$REPO" && git ls-files . ) | while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$d/$(dirname "$f")"; cp "$REPO/$f" "$d/$f" 2>/dev/null || true
  done
  chmod +x "$d/plugin/scripts/init-bundle.sh" "$d"/plugin/scripts/*.sh 2>/dev/null || true
}
TPL="$TMP/tpl"; make_tpl "$TPL"

newinst() { local d="$TMP/i$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
said()    { grep -q -- "$1" "$TMP/out" && echo yes || echo no; }
# Did the roster prompt appear at all? The header is printed before the first read, so its
# absence means nothing was asked — which is the property, not "the answer was refused".
asked()   { grep -q 'Team roster for this instance' "$TMP/out" && echo yes || echo no; }
owner()   { head -n1 <<<"$(sed -n 's/.*"defaultOwner"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/instance.config.json")"; }
# The seeded config, byte for byte, so "unchanged" is a comparison rather than a spot check.
SEED_CFG="$(cat "$TPL/plugin/seed/instance.config.json")"
same_as_seed() { [ "$(cat "$1/instance.config.json")" = "$SEED_CFG" ] && echo yes || echo no; }
# WHAT "NOTHING WAS WRITTEN" MEANS FOR THE LOCAL FILE. A completed stamp now writes two
# things into it that have nothing to do with the roster: this machine's `models`/
# `roleTiers` (step 4d) and this clone's DERIVED identity (step 4c). Neither its existence
# nor a `ownerGithubUser` in it says anything about the prompt, so the property these cases
# are about is asked exactly: NOTHING FROM THE ANSWER BELOW reached the file — no login and
# no address the refused block contained. (The interrupt case is the exception and keeps
# the file-absent form — it exits 130 from inside the roster block, so 4c never runs.)
no_identity() { # <instance>
  [ -e "$1/instance.config.local.json" ] || { echo yes; return 0; }
  grep -qE 'example-user-00[78]' "$1/instance.config.local.json" && echo no || echo yes
}
# Two complete pairs and a confirmation — the answer the positive path expects.
ANSWER='example-user-007 example-user-007@example.com
example-user-008 example-user-008@example.com

y
'

# =========================================================================== #
echo "-- 1. a non-TTY first stamp: no prompt, and it still succeeds"
I="$(newinst 1)"
printf '%s' "$ANSWER" | bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "exits 0"                              "$?" 0
ok "nothing was asked"                    "$(asked)" no
ok "…it says why"                          "$(said 'stdin is not a terminal')" yes
ok "…and prints the manual instruction"    "$(said 'ownerGithubUser')" yes
ok "the config is byte-identical to the seed" "$(same_as_seed "$I")" yes
ok "…so the placeholder roster survives"   "$(said 'nothing was asked')" yes
ok "no identity in instance.config.local.json" "$(no_identity "$I")" yes
ok "…though step 4c seeded this machine's tiers" "$(yn grep -q '"roleTiers"' "$I/instance.config.local.json")" yes
# A STAMP DELIVERS SEED CONTENT AND NO LINK (task-013). Both halves, so the change cannot
# be read as a loss: the document arrived, and it arrived as the bundle's own file.
ok "the bundle is otherwise stamped"       "$(yn test -f "$I/$AB_SCHEMA")" yes
ok "…as a real file, not a link"           "$(yn test -L "$I/$AB_SCHEMA")" no
ok "…and no machinery came with it"        "$(yn test -e "$I/scripts")" no

# =========================================================================== #
echo "-- 2. the positive path: one batched answer, at (a simulated) terminal"
I="$(newinst 2)"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "exits 0"                              "$?" 0
ok "it asked"                             "$(asked)" yes
ok "…and says what it wrote"              "$(said 'wrote instance.config.json')" yes
ok "defaultOwner is the FIRST person"     "$(owner "$I")" example-user-007
ok "person 1 is in the map"               "$(yn grep -q '"example-user-007": "example-user-007@example.com"' "$I/instance.config.json")" yes
ok "person 2 is in the map"               "$(yn grep -q '"example-user-008": "example-user-008@example.com"' "$I/instance.config.json")" yes
ok "no placeholder note survives"         "$(yn grep -q 'EXAMPLE ONLY' "$I/instance.config.json")" no
# The whole point of writing JSON with awk is that the result must still parse. jq is a
# hard requirement of the prompt itself (guard 4: no verifier, no write), so it is a hard
# requirement here too rather than a conditional assertion.
ok "the config still parses as JSON"       "$(yn jq -e . "$I/instance.config.json")" yes
ok "…and every other key survived"        "$(jq -r '.maxPrLoc, .roleTiers."project-manager"' "$I/instance.config.json" | tr '\n' ' ')" "2000 deep "
ok "the local file names this clone"      "$(jq -r '.ownerGithubUser' "$I/instance.config.local.json")" example-user-007
ok "…and it parses too"                   "$(yn jq -e . "$I/instance.config.local.json")" yes
ok "…and is gitignored"                   "$(yn grep -qxF 'instance.config.local.json' "$I/.gitignore")" yes
# The property that matters is not the file's text but that the REAL consumer reads it.
# task-owner.sh resolves "who is this clone?" from exactly these two files.
ok "task-owner.sh --self resolves it"     "$( cd "$I" && head -1 <<<"$(bash "$TPL/plugin/scripts/task-owner.sh" --self 2>&1)" )" \
                                          "self: example-user-007 (from instance.config.local.json)"
# commit-as.sh looks the address up in `people` via that login, with its own awk parser —
# a shape it cannot read would strand every agent commit.
ok "commit-as.sh can read the address"    "$( cd "$I" && awk -v who='"example-user-007"' '
      !inb { i=index($0,"\"people\""); if(i==0) next; $0=substr($0,i+8); i=index($0,"{"); if(i==0) next; $0=substr($0,i+1); inb=1 }
      { e=index($0,"}"); seg=(e?substr($0,1,e-1):$0)
        if (match(seg, who "[[:space:]]*:[[:space:]]*\"[^\"]*\"")) { m=substr(seg,RSTART,RLENGTH); sub(/^[^:]*:[[:space:]]*"/,"",m); sub(/"$/,"",m); print m; exit }
        if (e) exit }' instance.config.json )" "example-user-007@example.com"

# A one-person roster is the trailing-comma case: the last entry must have none.
I="$(newinst 3)"
printf 'example-user-007 example-user-007@example.com\n\ny\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "a one-person roster parses"           "$(yn jq -e . "$I/instance.config.json")" yes
ok "…and holds exactly one person"        "$(jq -r '.people | length' "$I/instance.config.json")" 1

# =========================================================================== #
echo "-- 3. a refresh never prompts (upgrade.sh calls this on every run)"
BEFORE="$(cat "$I/instance.config.json")"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "the second stamp exits 0"             "$?" 0
ok "…asks nothing"                        "$(asked)" no
ok "…and changes not one byte"            "$([ "$(cat "$I/instance.config.json")" = "$BEFORE" ] && echo yes || echo no)" yes
# The same run through upgrade.sh, which is the flow an unguarded prompt would block: it
# is non-interactive, and it calls install.sh with stdin wherever it happens to point.
printf '%s' "$ANSWER" | bash "$TPL/plugin/scripts/refresh-seeds.sh" "$I" >"$TMP/out" 2>&1
ok "upgrade.sh asks nothing"              "$(asked)" no
ok "…and the config is still untouched"   "$([ "$(cat "$I/instance.config.json")" = "$BEFORE" ] && echo yes || echo no)" yes
# FIRST_STAMP has to be asserted on an instance that still carries the PLACEHOLDER: a
# refresh of an instance whose roster was answered is also refused by guard 3, so a test
# that only used that one would pass with FIRST_STAMP removed entirely. Here the first
# stamp was non-interactive (roster skipped, placeholder intact), so guard 1 is the only
# thing standing between a refresh and a prompt.
I="$(newinst 19)"
printf '%s' "$ANSWER" | bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "a skipped roster stays the placeholder" "$(same_as_seed "$I")" yes
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "refreshing it still asks nothing"     "$(asked)" no
ok "…and writes nothing"                  "$(same_as_seed "$I")" yes
ok "…and no identity into the local file"  "$(no_identity "$I")" yes

# =========================================================================== #
echo "-- 4. a value already there is never overwritten"
# A first stamp whose SEED already names an owner: FIRST_STAMP is yes, stdin answers are
# piped, and the value still has to survive. (Guard 3 is checked against the FILE
# precisely so it does not depend on FIRST_STAMP being right.)
T2="$TMP/tpl-owned"; make_tpl "$T2"
sed 's/"defaultOwner": null,/"defaultOwner": "example-user-008",/' \
  "$T2/plugin/seed/instance.config.json" > "$T2/plugin/seed/instance.config.json.new"
mv "$T2/plugin/seed/instance.config.json.new" "$T2/plugin/seed/instance.config.json"
I="$(newinst 4)"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$T2/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "an existing defaultOwner: exits 0"    "$?" 0
ok "…nothing is asked"                    "$(asked)" no
ok "…it says the roster is left alone"    "$(said 'already set')" yes
ok "…and the value is untouched"          "$(owner "$I")" example-user-008
ok "…no identity is written either"       "$(no_identity "$I")" yes
# The other half: a `people` entry that is not the seeded placeholder shape. The
# placeholder is recognised as `"x": "x@example.com"`, so an address that is not the
# login's own is somebody's real roster, whatever the login looks like.
T3="$TMP/tpl-peopled"; make_tpl "$T3"
sed 's/"example-user-007": "example-user-007@example.com",/"example-user-007": "billing@example.com",/' \
  "$T3/plugin/seed/instance.config.json" > "$T3/plugin/seed/instance.config.json.new"
mv "$T3/plugin/seed/instance.config.json.new" "$T3/plugin/seed/instance.config.json"
I="$(newinst 5)"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$T3/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "an existing people entry: exits 0"    "$?" 0
ok "…nothing is asked"                    "$(asked)" no
ok "…and the entry is untouched"          "$(jq -r '.people."example-user-007"' "$I/instance.config.json")" billing@example.com
# An existing LOCAL file is this clone's identity, and is never replaced either — while
# the tracked half is still collected, since the two are separate decisions.
I="$(newinst 6)"
printf '{ "ownerGithubUser": "example-user-008" }\n' > "$I/instance.config.local.json"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "an existing local file is kept"       "$(jq -r '.ownerGithubUser' "$I/instance.config.local.json")" example-user-008
ok "…and it says so"                      "$(said "keep  instance.config.local.json")" yes
ok "…while the tracked half is written"   "$(owner "$I")" example-user-007

# =========================================================================== #
echo "-- 5. a half-answered prompt writes NOTHING"
# (a) A REAL interrupt, delivered while the installer waits at the second line. The pair
# already typed must not survive in any form: this is the exact failure — one login
# entered, ctrl-C, and the map resolves for one human and falls through for the other.
I="$(newinst 7)"
mkfifo "$TMP/fifo"
: > "$TMP/int.err"
# `set -m` around the launch is load-bearing, and it is a measured fact rather than a
# style choice: a command started asynchronously by a NON-interactive shell inherits
# SIGINT as ignored, and bash refuses to trap a signal that was ignored on entry — so
# without job control the installer's handler is never installed, the SIGINT does
# nothing, and this case silently degrades into the EOF case below (which passes for the
# wrong reason). With job control the child gets its own process group and the default
# disposition. Measured on bash 3.2.
set -m
TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/int.out" 2>"$TMP/int.err" <"$TMP/fifo" &
INT_PID=$!
set +m
# THE BOUND GOES ON THE CHILD. This installer is blocked reading a fifo nothing has written
# to yet, so if THIS harness dies before `exec 9>` below it waits there forever, reparented
# to pid 1 — `CONVENTIONS.md` → "Anything you background must be reaped by something that
# outlives YOU". The watchdog is a sibling, so it fires whether or not we are here; `sleep`
# bounds the watchdog itself; 60s is far past the measured sub-second answer, so it never
# fires in a healthy run, and it is retired below the moment the installer is really gone.
( sleep 60; kill -TERM "$INT_PID" 2>/dev/null ) >/dev/null 2>&1 &
INT_WD=$!
exec 9>"$TMP/fifo"
printf 'example-user-007 example-user-007@example.com\n' >&9
# Wait until the SECOND prompt is on screen — that is the proof the interrupt lands
# mid-answer rather than somewhere harmless earlier in the install. The prompt goes to
# stderr, which is unbuffered, so this does not race with a stdio flush.
i=0
while [ "$i" -lt 200 ]; do
  grep -q '2> ' "$TMP/int.err" && break
  sleep 0.05; i=$((i+1))
done
ok "the installer reached the 2nd prompt" "$(grep -q '2> ' "$TMP/int.err" && echo yes || echo no)" yes
kill -INT "$INT_PID" 2>/dev/null
exec 9>&-
wait "$INT_PID"; INT_RC=$?
kill "$INT_WD" 2>/dev/null || true
cat "$TMP/int.out" "$TMP/int.err" > "$TMP/out"
ok "interrupted: exits 130 (SIGINT)"      "$INT_RC" 130
ok "…it says nothing was written"         "$(said 'nothing written (interrupted)')" yes
ok "…the config is byte-identical"        "$(same_as_seed "$I")" yes
ok "…no half-written map anywhere"        "$(yn grep -q 'example-user-007@example.com' "$I/instance.config.local.json")" no
ok "…no local file at all"                "$(yn test -e "$I/instance.config.local.json")" no
ok "…and no temp file was left behind"    "$(find "$I" -maxdepth 1 -name 'instance.config.json.*' | wc -l | tr -d ' ')" 0
rm -f "$TMP/fifo"

# (b) EOF after one pair — ctrl-D, or a script whose input simply ran out.
I="$(newinst 8)"
printf 'example-user-007 example-user-007@example.com\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "EOF mid-answer: exits 0"              "$?" 0
ok "…it asked"                            "$(asked)" yes
ok "…and wrote nothing"                   "$(said 'nothing written (input ended)')" yes
ok "…config byte-identical"               "$(same_as_seed "$I")" yes
ok "…and no identity in the local file"   "$(no_identity "$I")" yes

# (c) The confirmation declined. The whole reason the write is a separate step.
I="$(newinst 9)"
printf 'example-user-007 example-user-007@example.com\n\nn\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "declined: exits 0"                    "$?" 0
ok "…it showed what it would write"       "$(said 'About to write')" yes
ok "…wrote nothing"                       "$(said 'nothing written (declined)')" yes
ok "…config byte-identical"               "$(same_as_seed "$I")" yes
# Anything that is not y/yes declines — silence included.
I="$(newinst 10)"
printf 'example-user-007 example-user-007@example.com\n\n\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "a blank confirmation declines"        "$(same_as_seed "$I")" yes

# (d) An empty first line skips, which is the documented way out.
I="$(newinst 11)"
printf '\n' | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "an empty list: exits 0"               "$?" 0
ok "…wrote nothing"                       "$(said 'nothing written (declined)')" yes
ok "…config byte-identical"               "$(same_as_seed "$I")" yes

# (e) Input this cannot write safely. Three re-asks, then nothing — never a partial map,
# and never a value that would have to be escaped into a JSON string.
I="$(newinst 12)"
printf 'not a login at all\nnot a login at all\nnot a login at all\ny\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "an unreadable line: exits 0"          "$?" 0
ok "…it names the expected shape"         "$(said 'expected exactly two fields')" yes
ok "…wrote nothing"                       "$(said 'nothing written (could not read the list)')" yes
ok "…config byte-identical"               "$(same_as_seed "$I")" yes
I="$(newinst 13)"
printf 'bad"login example-user-007@example.com\nbad"login x@example.com\nbad"login x@example.com\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "a quote in a login is refused"        "$(said 'is not a GitHub username')" yes
ok "…and nothing is written"              "$(same_as_seed "$I")" yes
ok "…the file still parses"               "$(yn jq -e . "$I/instance.config.json")" yes
I="$(newinst 14)"
printf 'example-user-007 not-an-address\nexample-user-007 nope\nexample-user-007 nope\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "an unwritable address is refused"     "$(said 'is not an address this can write safely')" yes
ok "…and nothing is written"              "$(same_as_seed "$I")" yes
# A duplicate login would silently shadow itself in the map.
I="$(newinst 15)"
printf 'example-user-007 example-user-007@example.com\nexample-user-007 example-user-008@example.com\n' \
  | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "a duplicate login is refused"         "$(said 'already in this roster')" yes
ok "…and nothing is written"              "$(same_as_seed "$I")" yes

# (f) No verifier on this machine, no write — and it says so BEFORE taking an answer,
# rather than collecting a roster it would then have to throw away. A PATH holding
# everything in the system directories EXCEPT jq and python3 is how that is arranged;
# anything installed elsewhere (homebrew) is out of PATH already.
I="$(newinst 20)"
mkdir -p "$TMP/nobin"
for d in /usr/bin /bin /usr/sbin /sbin; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    case "$b" in jq|python|python3|python3.*) continue ;; esac
    [ -e "$TMP/nobin/$b" ] || ln -s "$f" "$TMP/nobin/$b" 2>/dev/null
  done
done
# Only meaningful if the fixture PATH really can run the installer at all.
ok "the stripped PATH still has bash+git" \
   "$(PATH="$TMP/nobin" sh -c 'command -v bash >/dev/null && command -v git >/dev/null && echo yes || echo no')" yes
ok "…and really has no JSON parser"       "$(PATH="$TMP/nobin" sh -c 'command -v jq >/dev/null || command -v python3 >/dev/null && echo yes || echo no')" no
printf '%s' "$ANSWER" | PATH="$TMP/nobin" TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "no verifier: exits 0"                 "$?" 0
ok "…nothing is asked"                    "$(asked)" no
ok "…it says a write could not be verified" "$(said 'could not be verified')" yes
ok "…and the config is byte-identical"    "$(same_as_seed "$I")" yes

# =========================================================================== #
echo "-- 6. --config never prompts (it has no instance at all)"
# The negative is paired with the positive above deliberately: the same piped answer and
# the same TEAM_SETUP_STDIN=1 that DO produce a prompt in instance mode (section 2) must
# produce none here, so this cannot pass by the prompt being broken everywhere.
D="$TMP/cfgdest"; mkdir -p "$D"
printf '%s' "$ANSWER" | CLAUDE_CONFIG_DIR="$D" TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" --config >"$TMP/out" 2>&1
ok "--config exits 0"                     "$?" 0
ok "…asks nothing"                        "$(asked)" no
ok "…and writes no instance config"       "$(yn test -e "$D/instance.config.json")" no
printf '%s' "$ANSWER" | CLAUDE_CONFIG_DIR="$D" TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" --config --uninstall >"$TMP/out" 2>&1
ok "--config --uninstall asks nothing"    "$(asked)" no

# =========================================================================== #
echo "-- 7. the guards that were already here still hold"
# THE WORKTREE GUARD IS `--config`'s ALONE NOW (task-013). It existed because a bundle
# stamp wrote absolute symlinks into the source checkout — delete the worktree and every
# one of them dangled. A stamp writes no such link any more, so refusing here would refuse
# a stamp that is perfectly safe, and it was the reason every fixture in this suite had to
# copy the template out of the checkout first. `--config` still links into
# ${CLAUDE_CONFIG_DIR:-~/.claude} by absolute path, so for that half nothing changed.
WM="$TMP/wtmain"; make_tpl "$WM"
( cd "$WM" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) >/dev/null 2>&1
git -C "$WM" worktree add -q "$TMP/wtlinked" -b wt >/dev/null 2>&1
I="$(newinst 16)"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$TMP/wtlinked/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "from a worktree: a bundle stamp is allowed" "$?" 0
ok "…and it asked, like any other stamp"  "$(asked)" yes
ok "…and it stamped"                      "$(yn test -e "$I/instance.config.json")" yes
ok "…leaving no symlink behind"           "$([ -z "$(find "$I" -type l 2>/dev/null)" ] && echo yes || echo no)" yes
D_WT="$TMP/dest-wt"; mkdir -p "$D_WT"
CLAUDE_CONFIG_DIR="$D_WT" bash "$TMP/wtlinked/plugin/scripts/init-bundle.sh" --config >"$TMP/out" 2>&1
ok "…while --config from that same worktree still exits 2" "$?" 2
ok "…saying why"                          "$(said 'refusing to link the config layer from a git worktree')" yes
# The bare-TARGET interface: three live instances and upgrade.sh call it that way.
I="$(newinst 17)"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/out" 2>&1
ok "bare TARGET still stamps"             "$(yn test -f "$I/instance.config.json")" yes
ok "…and asks"                            "$(asked)" yes
I="$(newinst 18)"
printf '%s' "$ANSWER" | TEAM_SETUP_STDIN=1 bash "$TPL/plugin/scripts/init-bundle.sh" --instance "$I" >"$TMP/out" 2>&1
ok "--instance TARGET does the same"      "$(owner "$I")" example-user-007
# --help is a line range over the header; adding the roster to that header truncates it
# silently if the range is not extended with it.
bash "$TPL/plugin/scripts/init-bundle.sh" --help >"$TMP/out" 2>&1
ok "--help documents the roster"          "$(said 'OFFERS to collect')" yes
ok "--help is still not truncated"        "$(said 'Backs up any conflicting real file')" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
