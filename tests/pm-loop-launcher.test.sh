#!/usr/bin/env bash
#
# pm-loop-launcher.test.sh — the loop launcher does its three preconditions and
# nothing else, and the crash-recovery property it used to carry lives in the tick.
# The launcher is the plugin's `/dispatch` skill: the contract moved there verbatim and
# `symlink/.claude/commands/pm-loop.md` retired in the same change, so this harness
# follows the CONTRACT rather than the path it used to live at.
#
# WHY THIS IS A TEST AND NOT ONLY A CONVENTION. Measured on a real first tick,
# 2026-08-23: `pm-loop.md` documented three cheap preconditions, and what actually ran
# in the MAIN session before "Dispatching the tick" was roughly ten wide `bash` calls —
# every task's frontmatter, 120 lines of `log.md`, a tick-ledger grep, a worktree
# listing, `gh repo view`, `gh pr list`, and two `git status`/`git log` pairs. Two costs:
# a screen of noise before anything useful, and — the one that matters — all of it in the
# context the loop has to survive on for hours across many ticks, when the tick itself is
# a backgrounded agent whose context is free and discarded.
#
# The regression is invisible from reading either file alone, because it is a *pair*: a
# reader deleting the launcher's reads can silently take the crash-recovery property with
# them (the loop is long-lived, compaction discards session history, so the in-flight set
# must be re-derived FROM DISK), and a reader restoring "just a quick orient" to the
# launcher undoes the fix while every doc still reads correctly. So both halves are
# asserted together: the launcher stays closed, and the property has a home.
#
# It is deliberately NOT a check that the launcher prints few lines — that is behaviour of
# a model, not of a file. What is checkable is the instruction it reads, which is this.
#
# IT ALSO OWNS THE GRANT THAT WAS NOT A PRECONDITION — WHICH IS NOW ITS ABSENCE. A publish
# grant was added once so a tick could republish the board to a hosted page, together with
# a step 2c that finished the job whenever the tick could not. Both are deleted: publishing
# was account-scoped, so exactly one account could ever update a page and the recorded
# board vanished from under its own owner at the next login. The board is a local file now.
# Narrowing a tool contract is the harder direction to hold — a deleted grant leaves no
# trace, and nothing but an assertion stops the next "the tick could just publish this" —
# so the absence of the grant, the absence of the step, and the switch that replaced them
# are asserted together at the bottom.
#
# THE RULE IS AN ALLOWLIST NOW, AND THAT IS WHAT THIS FILE COUNTS. The 2026-08-23 version
# enumerated the forbidden sources — task docs, `log.md`, the ledger, `git log`, `gh pr
# list` — and said the list was closed. It was, and it rotted anyway: the reads that
# actually happened next were CI logs, built SPA chunks and `curl` probes, a category the
# enumeration never had. So the section is now three allowed operations, everything else is
# a tick or a subagent by category, and the assertion the old fix lacked is here: the
# count fails when the list grows.
#
# AND IT OWNS THE ONE GRANT THAT WAS DELIBERATELY ADDED BACK. `Bash(scripts/tick-lock.sh:*)`
# joined the allowlist on 2026-08-30, and a file whose subject is "the launcher stays
# closed" is exactly where that has to be visible. The reason it is not a regression: the
# launcher is the ONLY place that knows "I am dispatching right now" — the tick learns it
# seconds later, which is the window that let two ticks run concurrently for 34 minutes on
# 2026-08-29 — so the dispatch lock cannot live one context deeper the way every other read
# on this list can. What keeps it from being a hole is its shape: one script over one
# gitignored file, which WRITES and returns an exit code rather than returning content, and
# which prints nothing at all on the path that dispatches. The approved list below grows by
# that one entry and by nothing else, so any second addition still fails here.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
LAUNCHER="$REPO/plugin/skills/dispatch/SKILL.md"
TICK="$REPO/plugin/agents/project-manager.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pmloop.XXXXXX")" || {
  echo "pm-loop-launcher.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { # <file> <fixed-string> -> yes|no
  grep -qF -- "$2" "$1" && echo yes || echo no
}

ok "launcher exists" "$([ -f "$LAUNCHER" ] && echo yes || echo no)" yes
ok "tick agent exists" "$([ -f "$TICK" ] && echo yes || echo no)" yes

# --- the launcher's preconditions are a closed list of three ---------------------
# Numbered items inside `## Preconditions`, stopping at the next heading of any depth.
# `/^#/` and not an interval like `{2,}`: not every awk supports interval expressions,
# and one that doesn't would silently run the scan on into the next section.
count_preconditions() { # <file>
  awk '/^## Preconditions/{p=1;next} p&&/^#/{p=0} p&&/^[0-9]+\. /{n++} END{print n+0}' "$1"
}
# TWO, not three. The third — "read instance.config.json for reposRoot and org" — was
# removed: the launcher never used those values, the TICK does and reads config itself,
# and a precondition the tool contract forbids reads as licence to widen allowed-tools.
ok "preconditions listed" "$(count_preconditions "$LAUNCHER")" 2

# --- allowed-tools grants the launcher no reader ---------------------------------
# `pwd` and `ls` are the instance-root probe and are fine. Anything that can read a
# document, the git history or the GitHub API is the regression — including a bare
# `Bash`, which grants all of them at once.
readers_granted() { # <file> -> count of grants that are NOT on the approved list
  # AN ALLOWLIST, NOT A DENYLIST. The first version grepped for a fixed set of readers
  # — Read|Grep|Glob|WebFetch and a handful of Bash commands — so `Bash(curl:*)`,
  # `Bash(python:*)` and `Bash(node:*)` all returned 0 and this check PASSED while the
  # launcher could read anything on the machine or the network. A denylist over an open
  # set cannot be completed, which is why this repo's own permission guidance prefers
  # the simple allowlist shapes. So: extract every grant, subtract the approved forms,
  # and count what is left.
  #
  # THE APPROVED SET IS NOW EXACTLY THE PRECONDITIONS. `Artifact` used to be on it — a
  # publish grant, not a reader, and the only entry here that was not a precondition. It
  # is gone with the publish step, so it is gone from this list too: a closed list that
  # keeps approving a grant nothing uses is how the next one gets added by analogy. The
  # consequence is deliberate — re-granting it now fails THIS check, under a name about
  # readers, and the assertions further down say plainly that the grant itself is out.
  awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
    | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | grep -v -x -e 'Bash(pwd)' -e 'Bash(ls:\*)' -e 'Agent' \
                 -e 'ScheduleWakeup' -e 'CronList' -e 'CronDelete' \
                 -e 'Bash(bash \${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh:\*)' \
                 -e 'Bash(bash \${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh:\*)' \
    | wc -l | tr -d ' '
}

granted() { # <file> <tool> -> yes|no — is <tool> an exact grant in allowed-tools?
  grep -qx -- "$2" <<<"$(awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
    | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" && echo yes || echo no
}

ok "no reader in allowed-tools" "$(readers_granted "$LAUNCHER")" 0

# NON-VACUITY. A check that cannot fail proves nothing, and the previous one could not
# fail on these three — each was outside its fixed denylist. Every fixture is a real
# reader: curl reaches the network, python and node read any file on the machine.
for probe in 'Bash(curl:*)' 'Bash(python:*)' 'Bash(node:*)' 'Read' 'Bash'; do
  printf -- '---\nallowed-tools: Bash(pwd), Bash(ls:*), Agent, %s\n---\nbody\n' "$probe" \
    > "$TMP/probe.md"
  ok "…and it FAILS on a $probe grant" "$( [ "$(readers_granted "$TMP/probe.md")" -ge 1 ] && echo yes || echo no )" yes
done
# …while the real launcher's exact grant list still passes, so the allowlist is not
# simply rejecting everything.
printf -- '---\nallowed-tools: Bash(pwd), Bash(ls:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh:*), Agent, ScheduleWakeup, CronList, CronDelete\n---\nbody\n' \
  > "$TMP/probe.md"
ok "…and PASSES on the approved set alone" "$(readers_granted "$TMP/probe.md")" 0
# The approved set is EXACTLY those seven. A near-miss — another script under the same
# directory — is not covered by the tick-lock entry and must still count as a grant, or
# "one exception" would quietly mean "any script".
printf -- '---\nallowed-tools: Bash(pwd), Bash(scripts/write-snapshot.sh:*), Agent\n---\nbody\n' \
  > "$TMP/probe.md"
ok "…and FAILS on a different script grant" \
  "$( [ "$(readers_granted "$TMP/probe.md")" -ge 1 ] && echo yes || echo no )" yes

# --- the launcher says, in the file, that it reads nothing else -------------------
# `The launcher reads nothing else` is an anchor both files cite, so it is grepped
# literally — the same reason `awaiting-queue.test.sh` greps a heading.
ok "launcher carries the closed-list rule" "$(has "$LAUNCHER" 'The launcher reads nothing else')" yes
section() { awk '/^### The launcher reads nothing else/{p=1;next} p&&/^#/{p=0} p' "$1"; }
in_section() { grep -qF -- "$1" <<<"$(section "$LAUNCHER")" && echo yes || echo no; }

# THE RULE IS AN ALLOWLIST, AND ITS SIZE IS THE ASSERTION THE OLD FIX DID NOT HAVE. The
# 2026-08-23 version enumerated the forbidden sources and said the list was closed. It
# was closed, and it rotted anyway, because the next day's expensive reads were a
# category it had never named. An inversion with no check that FAILS WHEN THE LIST GROWS
# is that same fix again — so the count is pinned here, and "just a quick orient" coming
# back as a further allowed operation is exactly what it catches. Op 3 is the cron cleanup:
# admitted on 2026-09-09 because precondition 2 always ran it, so the prose and the
# frontmatter's `CronList, CronDelete` grant now agree instead of contradicting each other.
count_allowed_ops() { section "$1" | grep -c -E '^[0-9]+\. ' | tr -d ' '; }
ok "the allowlist is exactly three operations" "$(count_allowed_ops "$LAUNCHER")" 3
ok "…op 1 is the cwd precondition"    "$(in_section 'The cwd precondition')" yes
ok "…and says nothing wider"           "$(in_section 'precondition 1 above and nothing wider')" yes
ok "…op 2 is the lock, by script name" "$(in_section 'scripts/tick-lock.sh acquire')" yes
ok "…op 3 is the cron cleanup, by tool name" "$(in_section 'The cron cleanup')" yes
ok "…naming both cron tools"          "$(in_section '`CronList`, then `CronDelete`')" yes
# NON-VACUITY, and it IS the property: a FOURTH allowed operation must fail this check.
printf -- '### The launcher reads nothing else — an ALLOWLIST of three\n\n1. cwd\n2. lock\n3. cron\n4. just a quick orient\n\n## Next\n' > "$TMP/fourth.md"
ok "…and a FOURTH allowed operation fails it" \
  "$( [ "$(count_allowed_ops "$TMP/fourth.md")" -ne 3 ] && echo yes || echo no )" yes
printf -- '### The launcher reads nothing else — an ALLOWLIST of three\n\n1. cwd\n2. lock\n3. cron\n\n## Next\n' > "$TMP/three.md"
ok "…while exactly three still passes" "$(count_allowed_ops "$TMP/three.md")" 3

# THE ENUMERATION OF FORBIDDEN NOUNS IS DELETED, NOT KEPT BESIDE THE ALLOWLIST. Keeping
# both is how the list nobody can complete survives the inversion that replaced it.
nouns_named() { # <file> -> count of the old blocklist's nouns still in that section
  section "$1" \
    | grep -o -E 'log\.md|tick ledger|task documents|AWAITING\.md|SNAPSHOT\.json|worktree listing|git status|git log|gh repo view|gh pr list' \
    | sort -u | wc -l | tr -d ' '
}
ok "the blocklist of nouns is gone"   "$(nouns_named "$LAUNCHER")" 0
printf -- '### The launcher reads nothing else\n\nDo not read `log.md` or run `gh pr list`.\n\n## Next\n' > "$TMP/nouns.md"
ok "…and the check sees nouns that ARE there" \
  "$( [ "$(nouns_named "$TMP/nouns.md")" -ge 1 ] && echo yes || echo no )" yes

# The category, the disposal, and the sentence that stops a third entry arriving by
# analogy. The disposal matters on its own: a rule that only refuses leaves the reader
# holding the work with no route, which is how "just to orient" gets rationalised.
ok "…stated as a category, not a list" "$(in_section 'is a TICK or a SUBAGENT')" yes
ok "…naming the tick as the disposal" "$(in_section 'dispatch the tick and let it read')" yes
ok "…and the subagent as the other"   "$(in_section 'subagent** and let that context pay')" yes
ok "…closing the list against analogy" "$(in_section 'No other reader may be added by analogy')" yes
ok "…keeping the cost argument"       "$(in_section "main session's context")" yes
# The Preconditions pointer must not still read as a blocklist either — both ends of the
# cross-reference were rewritten, or half the file still teaches the old polarity.
ok "the Preconditions pointer is inverted too" \
  "$(grep -c -F 'Two checks, and the list is closed' "$LAUNCHER" | tr -d ' ')" 0
ok "…and names the allowlist instead" "$(has "$LAUNCHER" 'is an ALLOWLIST of three')" yes
# The launcher must never look before it takes it: a `status` then `acquire` would rebuild
# the check-then-write window the lock exists to close.
ok "…and forbids reading it separately" "$(in_section 'never call `${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh status` before `acquire`')" yes
# And the launcher must not carry the old imperative that made it do the re-derivation.
ok "old launcher imperative gone" \
  "$(grep -c -E '^[[:space:]]*Re-derive it from the root' "$LAUNCHER" | tr -d ' ')" 0
# The pair is only safe while each half points at the other: a reader who deletes the
# launcher's reads must land on the tick that now owns them, and vice versa.
ok "launcher points at the tick's step 0"  "$(has "$LAUNCHER" 'project-manager.md` step 0')" yes
ok "tick points back at the launcher rule" "$(has "$TICK" 'The launcher reads nothing else')" yes
# …and it must point back at the ALLOWLIST. A cross-reference that still describes the
# launcher as a set of refusals is half the pair teaching the polarity the other half
# just deleted, and both files would still read correctly on their own.
ok "…as an allowlist, not a set of refusals" "$(has "$TICK" 'allowlist of three')" yes

# --- precondition 1 runs, and finds SCHEMA.md where the layout puts it ----------
# It read `SCHEMA.md` in the cwd, so every migrated bundle was "not an instance root".
# The command is extracted from the skill and RUN, never re-typed here; the layout comes
# from bundle-paths.sh, so neither file spells the bundle directory.
pre1() { awk '/^## Preconditions/{p=1;next} p&&/^2\. /{p=0} p' "$LAUNCHER"; }
PRE_CMD="$(pre1 | grep -o '`ls instance\.config\.json[^`]*`' | tr -d '`')"
ok "precondition 1 carries one runnable check" "$([ -n "$PRE_CMD" ] && echo yes || echo no)" yes
AB_SCHEMA_REL="$(bash "$REPO/plugin/scripts/bundle-paths.sh" AB_SCHEMA)"
pre_runs() { # <dir> -> pass|refuse
  (cd "$1" && CLAUDE_PLUGIN_ROOT="$REPO/plugin" eval "$PRE_CMD") >/dev/null 2>&1 && echo pass || echo refuse
}
mkfx() { # <name> <file>... — files created empty under $TMP/fx/<name>
  local d="$TMP/fx/$1" f; shift; mkdir -p "$d"
  for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; : > "$d/$f"; done
  printf '%s' "$d"
}
ok "…passes a migrated bundle, no root SCHEMA.md" "$(pre_runs "$(mkfx migrated instance.config.json "$AB_SCHEMA_REL")")" pass
ok "…passes a legacy root layout"           "$(pre_runs "$(mkfx legacy instance.config.json SCHEMA.md)")" pass
ok "…refuses no instance.config.json (migrated)" "$(pre_runs "$(mkfx nocfg-m "$AB_SCHEMA_REL")")" refuse
ok "…refuses no instance.config.json (legacy)"   "$(pre_runs "$(mkfx nocfg-l SCHEMA.md)")" refuse
ok "…refuses a config with no SCHEMA.md"    "$(pre_runs "$(mkfx noschema instance.config.json)")" refuse
ok "…and spells no bundle directory" \
  "$( { pre1; section "$LAUNCHER" | grep -F 'The cwd precondition' -A1; } | grep -c -E '\.ai-bridge/|\.loopd/' | tr -d ' ')" 0

# --- the property is not lost: it lives in the tick, naming all four disk sources --
step0() { awk '/^0\. /{p=1} p&&/^1\. /{p=0} p' "$TICK"; }
S0="$(step0)"
ok "tick has a step 0" "$([ -n "$S0" ] && echo yes || echo no)" yes
in_step0() { grep -qF -- "$1" <<<"$S0" && echo yes || echo no; }
ok "step 0: from disk, not the brief"  "$(in_step0 'never from your brief')" yes
ok "step 0: reads the tick ledger"     "$(in_step0 'tick ledger')" yes
ok "step 0: reads task status:"        "$(in_step0 'own `status:`')" yes
ok "step 0: reads git log"             "$(in_step0 'git log')" yes
ok "step 0: reads gh pr list"          "$(in_step0 'gh pr list')" yes
ok "step 0: task doc outranks ledger"  "$(in_step0 'the task document wins')" yes
ok "step 0: names the duplicate-PR failure" "$(in_step0 'duplicate PRs')" yes

# --- the board: no publish grant, no step 2c, and a switch read at TICK time -------
#
# WHY THESE ARE ASSERTED HERE. The board is where this launcher's tool contract was
# widened, and it has now been narrowed back — the harder direction to keep, because a
# deleted grant leaves nothing behind to review. Four properties, each the kind that reads
# as satisfied while being wrong, which is this file's whole subject:
#
#   · THE GRANT AND THE STEP WENT TOGETHER, AND BOTH MUST STAY GONE. Publishing was
#     account-scoped: one account could ever update a given page, no share level granted a
#     second human write access, and the recorded board vanished from under its own owner
#     the moment they switched Claude accounts. So the grant bought a step that could not
#     work. Its absence is asserted on the launcher AND on the tick, because a grant with
#     no step is a widened contract buying nothing while a step with no grant is an
#     instruction that cannot run — the class agent-tool-allowlist.test.sh was written for.
#   · THE SWITCH IS READ AT TICK TIME, which is the defect this actually closed. `board`
#     was never unread — `install.sh`'s `cfg_bool board true` has gated SNAPSHOT.json
#     seeding since #10 — but it was read only at STAMP time, so `board: false` could not
#     stop a tick rendering once that file existed. The tick's own read is pinned here, as
#     is the fact that it does not replace the installer's. The behavioural half, on the
#     hook that actually runs, is in tests/banner-board-line.test.sh.
#   · THE RENDER IS THE ONE `build-board.sh` CALL THAT OPENS IN A BROWSER. `--standalone`
#     was FORBIDDEN in the publish step (a host supplied the wrapper) and is REQUIRED now
#     (nothing does), so the flag flipping is not cosmetic and is asserted as such.
#   · A RENDER IS NOT A CHANGE. Every tick refreshes the board, so counting it as a change
#     pins `noop` to false forever and retires the streak line that makes an idle loop
#     quiet. That is the difference between a loop a human leaves running and one they
#     turn off, so the rule is pinned rather than left to whoever edits step 3.
#
# As everywhere in this file: these check the INSTRUCTION, not a model's behaviour.
#
# THE URL KEY IS ASSEMBLED AT RUNTIME, which is what lets this file assert BOTH directions
# about it — absent from the launcher, present in the tick — without the string itself
# becoming a fixture nobody can move.
URL_KEY="board""ArtifactUrl"
ok "launcher grants no publish tool"     "$(granted "$LAUNCHER" 'Artifact')" no
ok "…and says so beside the list"        "$(has "$LAUNCHER" 'Why there is no publish grant, and no publish step')" yes
ok "…naming why it could not work"       "$(has "$LAUNCHER" 'account-scoped')" yes
ok "…and naming the second, independent reason: no artifact tool headless" \
  "$(has "$LAUNCHER" 'holds no')" yes
ok "…and where the board goes instead"   "$(has "$LAUNCHER" '.loopd/.board-live/board.html')" yes
# The launcher stays out of the config entirely: the URL is the TICK's read, and two
# readers of one key is how that key went wrong the first time.
ok "launcher names no config URL key"    "$(has "$LAUNCHER" "$URL_KEY")" no

# The step is GONE, not emptied: 2c WAS the publish handoff, and the tick renders and
# reports the path itself, so nothing replaced it.
step2c() { awk '/^2c\. /{p=1; next} p&&/^3\. /{p=0} p' "$1"; }
ok "launcher has no step 2c at all"      "$([ -z "$(step2c "$LAUNCHER")" ] && echo yes || echo no)" yes
# …and the steps that are not about publishing are untouched, so "no 2c" is a deletion
# rather than a file that stopped parsing. (Step 2b, the per-tick advisor, was retired on
# 2026-10-08 — tests/retire-advisor.test.sh pins its absence — so step 2 is the control.)
ok "…while step 2 is still there"        "$(grep -c '^2\. \*\*Wait for it to finish' "$LAUNCHER" | tr -d ' ')" 1
ok "…and step 3 still follows it"        "$(grep -c '^3\. \*\*On completion' "$LAUNCHER" | tr -d ' ')" 1

# The noop rule lives in step 3, where `noop` is defined — not in a note beside it.
step3() { awk '/^3\. \*\*On completion/{p=1; next} p&&/^4\. /{p=0} p' "$LAUNCHER"; }
ok "step 3: a render is not a change" \
  "$(grep -qF 'A board refresh or a render is not a change' <<<"$(step3)" && echo yes || echo no)" yes

# The tick's half: it holds no publish grant, re-checks the switch, renders the one board
# to the one path, and repeats the noop rule where the work happens.
tick_tools() {
  awk '/^---$/{d++; next} d==1 && /^tools:/{print}' "$TICK" | tr ',' '\n' \
    | sed -e 's/^tools:[[:space:]]*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}
ok "tick holds no publish tool"          "$(grep -qx 'Artifact' <<<"$(tick_tools)" && echo yes || echo no)" no
ok "…while still holding Bash to render" "$(grep -qx 'Bash' <<<"$(tick_tools)" && echo yes || echo no)" yes
# Step 8's render half is its own file since ai-bridge-v3/task-024 — the core keeps the
# commit-and-sync half, which runs every tick; the board and the queue only run where
# those artifacts exist.
TICK_RENDER="$REPO/plugin/tick-steps/step-8-render.md"
ok "the render half exists"              "$([ -f "$TICK_RENDER" ] && echo yes || echo no)" yes
ok "tick re-reads board at tick time"    "$(has "$TICK_RENDER" 'Read `board` from `instance.config.json`')" yes
ok "…false skips in silence"             "$(has "$TICK_RENDER" 'skip the rest of this step in silence')" yes
ok "…absent or true renders"             "$(has "$TICK_RENDER" 'Absent or `true`')" yes
ok "…and it does NOT replace the stamp-time reader" "$(has "$TICK_RENDER" 'cfg_bool board true')" yes
ok "…reading the same tracked file"      "$(has "$TICK_RENDER" '**tracked**')" yes
ok "tick renders the board"              "$(has "$TICK_RENDER" 'build-board.sh --standalone')" yes
ok "…to the path watch-board.sh uses"    "$(has "$TICK_RENDER" '.loopd/.board-live/board.html')" yes
# AND IT PASSES NO --out. The hardcoded one that stood here named the pre-3.0 root path
# and overrode the resolver, so the tick rendered where nothing reads it.
ok "…passing no --out, so the resolver decides" \
  "$(has "$TICK_RENDER" 'Pass no `--out`')" yes
ok "…and never the pre-3.0 root literal" \
  "$(grep -c -- '--out[= ]\.board-live' "$TICK_RENDER" | tr -d ' ')" 0
# `--layout` was DELETED, not defaulted away (see build-board.sh's header): a tick that
# still passed it would exit 2 and render nothing, so its absence is the assertion.
# tests/artifact-board.test.sh makes the same claim repo-wide; this one keeps it beside
# the step it is about, where a future edit to the tick would be reviewed.
ok "…and passes no removed --layout flag" "$(has "$TICK_RENDER" '--layout')" no
ok "tick reports the path, once"         "$(has "$TICK_RENDER" 'BOARD: rendered <path>')" yes
ok "…and never claims the page is live"  "$(has "$TICK_RENDER" 'Say the path, never that it is live')" yes
ok "tick: a render is not a change"      "$(has "$TICK_RENDER" 'A render is not a state change')" yes
# THE KEY IS BACK, AND ITS SHAPE IS WHAT IS ASSERTED NOW. This line used to demand the
# tick never name it, because publishing had been deleted. `/<plugin>:board` reinstates
# publishing PER MACHINE, so the tick may name the key — but only to ask WHICH LAYER
# answers, because the tick still cannot publish: measured 2026-09-05 on Claude Code
# 2.1.261, a headless `claude -p` session's tool inventory carries no artifact tool and a
# tool search for one returns nothing. So "never names it" becomes "names it through the
# resolver, acts on `local`, and is told in as many words not to try".
ok "tick asks the resolver which layer holds the URL key" \
  "$(has "$TICK_RENDER" "scripts/resolve-config.sh --source $URL_KEY")" yes
ok "…and prints the refresh line instead of publishing" \
  "$(has "$TICK_RENDER" 'BOARD: run /'"${PN}:"'board publish to refresh the published page')" yes
ok "…and is told not to attempt one"     "$(has "$TICK_RENDER" 'not attempt a publish')" yes
# A `tracked` value is the deleted shape and the banner drops it; the two readers of this
# key must agree, or one of them is publishing a promise the other silently breaks.
ok "…and ignores a tracked value, as the banner does" "$(has "$TICK_RENDER" 'a first field of `tracked`')" yes
# The retired renderer must not come back as the thing the tick runs.
ok "tick names no retired renderer"      "$(has "$TICK" 'build-artifact-board')" no
ok "launcher names no retired renderer"  "$(has "$LAUNCHER" 'build-artifact-board')" no

# NON-VACUITY for the two absence checks above: each must FIND what it looks for when it
# is really there, or "gone" is indistinguishable from "never looked".
printf -- '---\nallowed-tools: Bash(pwd), Agent, Artifact\n---\n\n2c. **Republish the board.**\n   a body\n\n3. **On completion**, schedule\n' \
  > "$TMP/withstep.md"
ok "the grant checker sees a grant that IS there" "$(granted "$TMP/withstep.md" 'Artifact')" yes
ok "the 2c checker sees a 2c that IS there" \
  "$([ -n "$(step2c "$TMP/withstep.md")" ] && echo yes || echo no)" yes
ok "…and the same key grep finds a planted key" \
  "$(printf 'x %s y\n' "$URL_KEY" > "$TMP/withkey.md"; has "$TMP/withkey.md" "$URL_KEY")" yes

# --- non-vacuity: the two mechanical checks must reject a bad file ----------------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/pmloop.XXXXXX")" || {
  echo "pm-loop-launcher.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT
{
  printf -- '---\n'
  printf 'description: fixture\n'
  printf 'allowed-tools: Bash(pwd), Bash(ls:*), Read, Bash(gh:*), Agent\n'
  printf -- '---\n\n'
  printf '## Preconditions\n\n1. one\n2. two\n3. three\n4. read every task doc\n\n'
  printf '## Next\n\n5. not a precondition\n'
} > "$tmp/bad.md"
ok "checker counts the fixture's preconditions" "$(count_preconditions "$tmp/bad.md")" 4
ok "checker flags the fixture's readers"        "$(readers_granted "$tmp/bad.md")" 2
# A bare `Bash` grants every one of those readers at once, so it counts too.
printf -- '---\nallowed-tools: Agent, Bash\n---\n' > "$tmp/bare.md"
ok "checker flags a bare Bash grant"           "$(readers_granted "$tmp/bare.md")" 1
# ...and the good line stays clean, or the check would flag everything.
printf -- '---\nallowed-tools: Bash(pwd), Bash(ls:*), Agent\n---\n' > "$tmp/good.md"
ok "checker passes pwd/ls-only grants"         "$(readers_granted "$tmp/good.md")" 0

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
