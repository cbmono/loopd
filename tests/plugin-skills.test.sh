#!/usr/bin/env bash
#
# plugin-skills.test.sh — the plugin skills: shape, safety split, and the pins that
# keep each skill's contract from drifting away from the machinery it fronts.
#
# THE ONE DESIGN DECISION THIS FILE GUARDS: the model-invocation split. The skills that
# CHANGE STATE or act on the world (`capture`, `work`, `dispatch`, `handoff`, `audit`,
# `answer`, `fanout`, `pr-review-request`) carry
# `disable-model-invocation: true` — a human types them; the model never reaches for them
# on its own. The two read-only skills (`brief-me`, `welcome`) stay model-invocable. Both
# directions are asserted, because a `true` added to `brief-me` silently deletes a
# capability and a `true` dropped from `dispatch` silently hands the model the loop.
#
# The per-skill pins assert the PROPERTY each contract exists for (read-only-ness,
# verbatim relay, provenance, the two non-actions), not the prose around it — the wording
# may move; the property may not.
#
# WHERE A NEW PIN GOES — this file reads the skill FILES, so everything it holds is a
# claim about TEXT. That is the right shape for most of the contract and it is where a
# new pin belongs by default: free, offline, runs on every machine.
#   this file            something is WRITTEN in a skill file
#   plugin/evals/        something is true of WHAT THE MODEL DOES with the plugin loaded
#   tests/plugin-eval.test.sh   the eval suite's own shape, and running it
# The split above is why the model-invocation assertions here were kept, not moved, when
# plugin/evals/ arrived: the eval grades the EFFECT of `disable-model-invocation: true`
# for three skills; this file still owns the flag as written, for all ten.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
TPL="$(cd "$HERE/.." && pwd)"
SK="$TPL/plugin/skills"
[ -d "$SK" ] || { echo "plugin-skills.test: missing $SK" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# fm <skill> <key> — a frontmatter value, read from between the first `---` pair only,
# so a `key:` in the body can never satisfy an assertion about the header.
fm() {
  awk -v k="$2" 'NR==1 && $0=="---" {infm=1; next}
                 infm && $0=="---" {exit}
                 infm && index($0, k ":")==1 {sub("^" k ":[ ]*", ""); print; exit}' \
    "$SK/$1/SKILL.md"
}
body() { # <skill> — everything after the closing `---`
  awk 'NR==1 && $0=="---" {infm=1; next} infm && $0=="---" {infm=0; inb=1; next} inb' \
    "$SK/$1/SKILL.md"
}

STATE_CHANGING="capture work dispatch handoff audit answer fanout pr-review-request new-project close-project board init kb-apply prune-wt"
READ_ONLY="brief-me welcome"
ALL="$STATE_CHANGING $READ_ONLY"

# =======================================================================================
echo "== 1. every skill ships, well-formed, and no further skill appears unasserted =="
# =======================================================================================
for s in $ALL; do
  ok "$s/SKILL.md ships"                    "$(yn test -f "$SK/$s/SKILL.md")" yes
  ok "…its name: matches its directory"     "$(fm "$s" name)" "$s"
  ok "…its description is non-empty"        "$([ -n "$(fm "$s" description)" ] && echo yes || echo no)" yes
  ok "…and it has a body, not just a header" "$([ "$(body "$s" | grep -c .)" -ge 3 ] && echo yes || echo no)" yes
done
# A skill added to the directory without being added to this harness is invisible to every
# assertion here — the silence failure mode this repo's checks are written against.
ok "the skill set is exactly the ones this file asserts" \
  "$(ls "$SK" | sort | tr '\n' ' ' | sed 's/ $//')" \
  "$(printf '%s\n' $ALL | sort | tr '\n' ' ' | sed 's/ $//')"

# =======================================================================================
echo "== 2. the model-invocation split — both directions =="
# =======================================================================================
for s in $STATE_CHANGING; do
  ok "$s is human-triggered (disable-model-invocation: true)" "$(fm "$s" disable-model-invocation)" true
done
for s in $READ_ONLY; do
  ok "$s stays model-invocable (no disable-model-invocation)"  "$(fm "$s" disable-model-invocation)" ""
done

# =======================================================================================
echo "== 3. plugin content is generic — it installs from a public marketplace =="
# =======================================================================================
# Same rule as symlink/: no org, user path or host literal in what every installer gets.
# (The plugin README legitimately names the marketplace repo; skills never do.)
for s in $ALL; do
  ok "$s carries no org / clone-path / host literal" \
    "$(grep -c -E 'cbmono|/Users/|github\.com' "$SK/$s/SKILL.md" | tr -d ' ')" 0
done

# =======================================================================================
echo "== 4. welcome — the absorbed /loopd:welcome contract, property by property =="
# =======================================================================================
W="$SK/welcome/SKILL.md"
ok "welcome relays welcome.sh verbatim"                "$(grep -c 'relay its output verbatim' "$W" | tr -d ' ')" 1
ok "…all three forms are named"                          "$(grep -cE '^\| `/welcome( check| fix)?`' "$W" | tr -d ' ')" 3
ok "…its tools are the one script plus read-only inspection" \
  "$(fm welcome allowed-tools)" "Bash(bash \${CLAUDE_PLUGIN_ROOT}/scripts/welcome.sh:*), Bash(pwd), Bash(ls:*), Read, Glob"
# The two non-actions are the reason the contract exists (tests/welcome-command.test.sh
# proves the SCRIPT never acts; this pins that the skill never invites the model to).
ok "…never rewrite config files"                         "$(grep -c 'never revert, stage or rewrite `instance.config.json`' "$W" | tr -d ' ')" 1
ok "…never clear a tick lock"                            "$(grep -c 'never remove or rewrite `.tick-lock`' "$W" | tr -d ' ')" 1
ok "…and no rules recital"                               "$(grep -ci 'always use the pm-loop' "$W" | tr -d ' ')" 0
ok "…outside an instance it stops rather than improvises" "$(grep -c 'never improvise a banner' "$W" | tr -d ' ')" 1

# =======================================================================================
echo "== 5. the other five — one load-bearing property each =="
# =======================================================================================
ge1() { if [ "$1" -ge 1 ]; then echo yes; else echo no; fi; }
ok "brief-me declares itself read-only" \
  "$(ge1 "$(grep -c 'never dispatch, promote, merge' "$SK/brief-me/SKILL.md")")" yes
ok "capture drafts, never promotes" \
  "$(ge1 "$(grep -ci 'never promoted\|never promote' "$SK/capture/SKILL.md")")" yes
ok "…and requires provenance" \
  "$(ge1 "$(grep -ci 'provenance' "$SK/capture/SKILL.md")")" yes
ok "work works ONE task" \
  "$(ge1 "$(grep -ci 'one task' "$SK/work/SKILL.md")")" yes
# dispatch no longer DELEGATES to the loop contract — it IS the loop contract, moved here
# verbatim when `symlink/.claude/commands/pm-loop.md` retired. The property that makes it
# the real launcher is the one it must never lose: it takes the tick lock ITSELF.
ok "dispatch IS the loop contract: it takes the tick lock itself" \
  "$(ge1 "$(grep -c 'scripts/tick-lock.sh acquire --agent project-manager' "$SK/dispatch/SKILL.md")")" yes
# Its ScheduleWakeup prompt is the ONE line the move could not carry verbatim: a wakeup
# naming a retired command re-fires into nothing, so the name it reschedules under is
# pinned rather than left to whoever next edits step 3.
ok "…rescheduling itself under its own name" \
  "$(ge1 "$(grep -c '`prompt` = `/dispatch <gap>`' "$SK/dispatch/SKILL.md")")" yes
ok "…and naming the retired command nowhere" \
  "$(grep -c 'pm-loop' "$SK/dispatch/SKILL.md" | tr -d ' ')" 0
ok "handoff asks for the new owner's github login" \
  "$(ge1 "$(grep -ci 'github-login\|github login' "$SK/handoff/SKILL.md")")" yes
ok "audit never promotes, merges, or dispatches" \
  "$(ge1 "$(grep -c 'never promotes, merges, or dispatches' "$SK/audit/SKILL.md")")" yes
ok "answer works the tasks' open_questions, nothing else" \
  "$(ge1 "$(grep -c 'open_questions' "$SK/answer/SKILL.md")")" yes
ok "…scopes to a project or a single task via \$ARGUMENTS" \
  "$(ge1 "$(grep -c 'ARGUMENTS' "$SK/answer/SKILL.md")")" yes
ok "…never widens scope on a typo" \
  "$(ge1 "$(grep -c 'never fall back to all' "$SK/answer/SKILL.md")")" yes
ok "…offers multiSelect where answers can jointly apply" \
  "$(ge1 "$(grep -c 'multiSelect' "$SK/answer/SKILL.md")")" yes
ok "fanout is for INDEPENDENT asks" \
  "$(ge1 "$(grep -ci 'independent' "$SK/fanout/SKILL.md")")" yes
ok "pr-review-request treats Slack as optional" \
  "$(ge1 "$(grep -ci 'optional' "$SK/pr-review-request/SKILL.md")")" yes
# kb-apply is the ONLY path that writes a reflection proposal into knowledge/, so losing
# either half of that — the apply call, or the human gate before it — is the whole defect.
ok "kb-apply is the one path that applies a report" \
  "$(ge1 "$(grep -c 'scripts/kb-apply.sh' "$SK/kb-apply/SKILL.md")")" yes
ok "…and shows the human the proposals before it does" \
  "$(ge1 "$(grep -c 'Show the human the proposals first' "$SK/kb-apply/SKILL.md")")" yes
ok "new-project keeps the scaffold review's declared fallback" \
  "$(ge1 "$(grep -ci 'fallback' "$SK/new-project/SKILL.md")")" yes
ok "…and the build/research asymmetry (clis from a flag or empty)" \
  "$(ge1 "$(grep -c 'clis' "$SK/new-project/SKILL.md")")" yes
# The stage-1 gate asks ONE question — is the scaffold I just wrote well-formed? An unscoped
# `validate-bundle.sh` also reports every pre-existing warning in the bundle: measured
# 2026-09-25 on a live instance, 281 documents, 0 errors, 290 warnings, 582 lines / 64 KB
# entering a session with no use for it. This asserts the SCOPE, not the prose around it —
# every body invocation must name `projects/<slug>/`, and an unscoped one must fail here.
# The frontmatter `allowed-tools:` line is excluded: it is a permission glob, not a call.
# It must name FILES, not the directory: `validate-bundle.sh` resolves only concept
# documents, so `validate-bundle.sh projects/<slug>` checks 0 documents and exits 0 —
# a scoped gate that passes vacuously, which is worse than the dump it replaced.
nps_unscoped() {
  awk 'NR>1 && /^---$/ { body=1; next } body' "$SK/new-project/SKILL.md" \
    | grep -o 'validate-bundle\.sh[^`]*' \
    | grep -vc 'validate-bundle\.sh projects/<slug>/'
}
ok "new-project's stage-1 gate validates only the project it made" \
  "$(nps_unscoped)" 0
ok "close-project keeps the retain: true freeze route" \
  "$(ge1 "$(grep -c 'retain: true' "$SK/close-project/SKILL.md")")" yes
ok "…and stays human-gated" \
  "$(ge1 "$(grep -ci 'human-gated' "$SK/close-project/SKILL.md")")" yes
# board — the properties that make publishing safe, one assertion each. Its markup
# comes from the renderer, so the pins are about SCOPE and DESTINATION, not about prose.
# THE DEFAULT IS THE ONE EXCEPTION, because it is prose and nothing else carries it: a
# bare call serves, and the argument-hint is where a human reads that before typing.
ok "a bare /${PN}:board serves, and the skill says so" \
  "$(ge1 "$(grep -cF 'no argument means' "$SK/board/SKILL.md")")" yes
ok "…and the argument-hint shows serve as the default" \
  "$(ge1 "$(grep -cF 'argument-hint: "[serve] | publish"' "$SK/board/SKILL.md")")" yes
ok "…while publish stays something the human typed" \
  "$(ge1 "$(grep -cF 'Only ever on an explicit `publish`' "$SK/board/SKILL.md")")" yes
ok "…and the skill refuses outside an instance root in its own words" \
  "$(ge1 "$(grep -cF 'an instance root' "$SK/board/SKILL.md")")" yes
ok "…and no model may invoke it, default or not" \
  "$(ge1 "$(grep -cF 'disable-model-invocation: true' "$SK/board/SKILL.md")")" yes
ok "board renders scoped to THIS instance (the trailing dot)" \
  "$(ge1 "$(grep -cF -- '/artifact-body.html" .' "$SK/board/SKILL.md")")" yes
ok "…and it resolves that path rather than hardcoding one" \
  "$(ge1 "$(grep -cF -- 'bundle-paths.sh AB_BOARD_DIR' "$SK/board/SKILL.md")")" yes
ok "…and never names the pre-3.0 root path" \
  "$(grep -c -- '--out[= ]\.board-live' "$SK/board/SKILL.md" | tr -d ' ')" 0
ok "…as an artifact page BODY, never --standalone" \
  "$(grep -c -- '--standalone --out' "$SK/board/SKILL.md" | tr -d ' ')" 0
ok "…recording the URL under boardArtifactUrl in the per-machine file" \
  "$(ge1 "$(grep -cF 'instance.config.local.json' "$SK/board/SKILL.md")")" yes
ok "…which is the key name the banner reads" \
  "$(ge1 "$(grep -cF 'boardArtifactUrl' "$SK/board/SKILL.md")")" yes
ok "…and forbidding the TRACKED file outright, which is the failure it replaces" \
  "$(ge1 "$(grep -cF 'Never put the URL in `instance.config.json`' "$SK/board/SKILL.md")")" yes
ok "…and updating the SAME artifact rather than making a second one" \
  "$(ge1 "$(grep -c 'update that artifact in place' "$SK/board/SKILL.md")")" yes
# The measured limit, carried where the human running the skill reads it. A skill that
# silently did nothing headless would be indistinguishable from one that was broken.
ok "…and states the measured headless limit" \
  "$(ge1 "$(grep -c 'run /'"${PN}:"'board publish to refresh' "$SK/board/SKILL.md")")" yes
# Publishing is irreversible and recording the URL is not, so the gap between them is the
# one place this skill can strand an artifact nobody can name. Three pins, one per half of
# the fix: the ordering, the failure report that carries the URL out of the session, and
# the named exit from the duplicate state. The last two are what a human acts on, so an
# assertion that only held the ordering would pass over a skill that still loses the URL.
ok "…reporting success only AFTER the URL is recorded" \
  "$(ge1 "$(grep -cF 'only after the URL is recorded' "$SK/board/SKILL.md")")" yes
ok "…and failing LOUDLY with the URL quoted when the record cannot be written" \
  "$(ge1 "$(grep -cF 'BOARD: PUBLISHED BUT NOT RECORDED <url> — add "boardArtifactUrl"' "$SK/board/SKILL.md")")" yes
ok "…and naming the duplicate-artifact state, which only the human can leave" \
  "$(ge1 "$(grep -cF 'Two artifacts, one instance' "$SK/board/SKILL.md")")" yes

# =======================================================================================
echo "== 6. manifest validation, where the CLI exists =="
# =======================================================================================
# CI's runner ships no claude CLI, and the merge-gate tier (AB_TIER=gate, set by
# tests/run.sh) spawns it nowhere; the skip is REPORTED, never silent, and the structural
# assertions above do not depend on it.
if [ "${AB_TIER:-deep}" = deep ] && command -v claude >/dev/null 2>&1; then
  vrc=0; claude plugin validate --strict "$TPL/plugin" >/dev/null 2>&1 || vrc=$?
  ok "claude plugin validate --strict passes"            "$vrc" 0
else
  echo "  SKIP  validate --strict not run here (tier=${AB_TIER:-deep}, CLI $(command -v claude >/dev/null 2>&1 && echo present || echo absent))"
fi

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
