#!/usr/bin/env bash
#
# plugin-eval.test.sh — the `claude plugin eval` suite under plugin/evals/: its shape,
# its tie back to the skills it grades, and (where the CLI supports it) an actual run.
#
# deep — the run below is a paid model run (~$2, ~10 min), so this harness is the deep
# tier: `tests/run.sh --deep` and the nightly workflow run it, the merge gate never does.
#
# WHY A SECOND PLUGIN HARNESS EXISTS AT ALL. `plugin-skills.test.sh` reads the skill
# FILES: it greps frontmatter and prose, so every pin it holds is a claim about text.
# That is the right shape for most of the contract and it stays exactly as it was — this
# file deletes nothing and replaces nothing. It adds the one class of pin a grep cannot
# express: what a MODEL does when the plugin is loaded. `disable-model-invocation: true`
# is not a string, it is an effect — the model must not reach for `dispatch`, `work` or
# `answer` on its own — and only a real run can see the effect.
#
# THE DIVISION OF LABOUR, so a contributor knows where a new pin goes:
#   tests/plugin-skills.test.sh   the skill files: frontmatter, the model-invocation
#                                 split as WRITTEN, generic content, per-skill prose
#                                 properties. Cheap, offline, runs everywhere.
#   plugin/evals/                 behaviour under a real model run. Costs money and
#                                 needs the CLI; graded by `claude plugin eval`.
#   tests/plugin-eval.test.sh     this file: the eval suite's own shape, always; and
#                                 the run itself, when the CLI supports it.
#
# FIVE OF THE NINE CASES GRADE THE MAIN THREAD, not a skill. One is the reader for a prose
# rule of `launcher-verification-contract` — unverified state — and it exists because the
# previous prose fix for that defect shipped 2026-08-23 with no test and rotted in weeks.
# Section 4 asserts the one property that keeps it from rotting the same way: a grader keyed
# on WORDING passes the next paraphrase, so `regex` over a message is refused there.
# The other four grade an artifact the session hands back — a refined task document, a PR
# body, a reviewer verdict, a tick's three inputs with an instruction planted in each — so a
# deterministic grader can read it and section 4 is not theirs: `refine-fills-criteria-never-ready`
# pins `status: ready` with a regex over the document itself, which is the assertion, not a
# paraphrase of one.
#
# FOUR MORE were RETIRED 2026-09-13 — see $RETIRED and evals/README.md.
#
# THE NON-VACUITY ARM IS NOT OPTIONAL. Three cases asserting "the model never invoked
# this skill" are ALL satisfied by a harness in which no skill is reachable at all —
# nothing invoked, nothing failed, four green ticks and no coverage. So the suite ships
# `skills-are-reachable`, which asserts the OPPOSITE (`min: 1`) through the same Skill
# tool, and this file refuses a suite that has dropped it.
#
# MEASURED 2026-09-05, and the reason the three cases are worth their cost: with
# `disable-model-invocation: true` deleted from `plugin/skills/dispatch/SKILL.md` and
# nothing else changed, `dispatch-is-human-gated` went red on both runs — "Skill called
# 1x (expected 0..0)". The model reaches for the loop the moment the flag stops holding
# it back. A grep over the file cannot produce that verdict.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
PLUGIN="$TPL/plugin"
EVALS="$PLUGIN/evals"

pass=0; fail=0; skip=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# body <file> — everything after the frontmatter. A prompt with no body is no prompt, and
# an `llm` grader with no body has no rubric, so both are asked the same question.
body() {
  awk 'NR==1 && $0=="---" {infm=1; next}
       infm && $0=="---" {infm=0; inb=1; next}
       inb' "$1"
}

# fm <file> <key> — a frontmatter value, read from between the first `---` pair only, so
# a `key:` in the body can never satisfy an assertion about the header. Same reader as
# plugin-skills.test.sh, deliberately: the two files must agree on what a header is.
fm() {
  awk -v k="$2" 'NR==1 && $0=="---" {infm=1; next}
                 infm && $0=="---" {exit}
                 infm && index($0, k ":")==1 {sub("^" k ":[ ]*", ""); print; exit}' "$1"
}

# The three skills this suite grades, and the control arm that keeps them non-vacuous.
# These are PROPERTY GROUPS, not the case list: the case list is discovered from the
# directories that exist (section 1), so a new case is asserted over by section 2 the
# moment it lands, and only a case wanting a group's extra assertions is named here.
GATED="dispatch work answer"
CONTROL="skills-are-reachable"
# RETIRED 2026-09-13 (ai-bridge-v3/task-033): four cases that could only ever pass inside a
# fixture bundle. `scaffold_script` + `--scaffold` runs author-supplied bash on every machine
# that runs this harness, and the bash harnesses named in evals/README.md already pin those
# behaviours for free. Section 6 below refuses a suite that deletes them without the reason.
RETIRED="caveat-outranks-the-launcher comment-is-warranted-or-absent
diagnosis-is-dispatched dormant-side-effect-is-not-a-decision"
# What survives of that group: it grades the MAIN THREAD rather than a skill, so it shares
# none of the assertions in section 3; section 4 is where it is asserted.
PATTERNS="unverified-state-is-unknown"

# =======================================================================================
echo "== 1. the eval suite ships where the CLI looks for it =="
# =======================================================================================
ok "plugin/evals/ exists"                       "$(yn test -d "$EVALS")" yes
[ -d "$EVALS" ] || { printf '\npass=%s fail=%s skip=%s\n' "$pass" "$fail" "$skip"; exit 1; }
# Results are run artifacts (a timestamped dir per run, plus an HTML report); they must
# never be committed, and this repo is public.
#
# ASKED ABOUT A PATH INSIDE THE DIRECTORY, NEVER THE DIRECTORY ITSELF. `.gitignore`'s
# `/plugin/evals/results/` carries a trailing slash, so it matches a DIRECTORY — and
# `git check-ignore plugin/evals/results` answers "not ignored" when that directory does
# not exist yet. It exists on a machine that has run the eval and not on a fresh
# checkout, so the bare form passes locally and fails in CI, which is exactly what it did
# (run 33961927498, the one assertion red in 5,937). A path below it is answered from the
# pattern alone, whether or not anything is there.
ok "…and its results/ output is gitignored" \
  "$(cd "$TPL" && git check-ignore -q plugin/evals/results/RUN/report.html && echo yes || echo no)" yes

# Directories only, and `results/` is a run artifact rather than a case — so the eval
# dir's own README.md (and any other prose beside the cases) is not read as one.
CASES="$(cd "$EVALS" && find . -mindepth 1 -maxdepth 1 -type d ! -name results -exec basename {} \; | sort | tr '\n' ' ' | sed 's/ $//')"
ok "the suite ships cases"                       "$([ -n "$CASES" ] && echo yes || echo no)" yes
# The control arm, by name, because dropping it is the one edit that makes the whole
# suite vacuous: three cases asserting "the model never invoked this skill" all pass in a
# harness where no skill is reachable at all.
case " $CASES " in *" $CONTROL "*) has_control=yes ;; *) has_control=no ;; esac
ok "…including the control arm, which may never be dropped" "$has_control" yes
# The group lists below are not the case list, so a rename would silently take a case out
# of section 3 or 4 rather than out of the suite. This is what makes that loud.
# shellcheck disable=SC2046,SC2086  # deliberate word lists, as in plugin-skills.test.sh
missing=""
for c in $CONTROL $PATTERNS $(for s in $GATED; do echo "$s-is-human-gated"; done); do
  case " $CASES " in *" $c "*) ;; *) missing="$missing $c" ;; esac
done
ok "…and every case this file groups by name is still there" "${missing:-none}" none

# A RETIREMENT CARRIES ITS REASON, or it is indistinguishable from someone deleting a red
# case to get a green run. Both halves are asserted: the case is gone AND the README says
# why it went. Re-adding one without a fixture bundle turns the first half red.
R="$EVALS/README.md"
back=""; unexplained=""
for c in $RETIRED; do
  [ -d "$EVALS/$c" ] && back="$back $c"
  grep -qF "\`$c\`" "$R" || unexplained="$unexplained $c"
done
ok "…and no retired case is back without a fixture bundle" "${back:-none}" none
ok "…each retirement's reason is written in the README"    "${unexplained:-none}" none
ok "…under a heading that says they were retired and why"  \
  "$(grep -c '^## Retired .* the four cases that needed a fixture bundle' "$R" | tr -d ' ')" 1

# =======================================================================================
echo "== 2. every case is well-formed the way the CLI parses it =="
# =======================================================================================
for c in $CASES; do
  P="$EVALS/$c/prompt.md"
  ok "$c/prompt.md ships"                       "$(yn test -f "$P")" yes
  ok "…it grants at least one tool"             "$([ -n "$(fm "$P" allowed_tools)" ] && echo yes || echo no)" yes
  ok "…and it carries a prompt, not just a header" \
    "$([ "$(body "$P" | grep -c .)" -ge 1 ] && echo yes || echo no)" yes
  n_graders=0; for g in "$EVALS/$c/graders"/*.md; do [ -f "$g" ] && n_graders=$((n_graders+1)); done
  ok "…with at least one grader beside it"      "$([ "$n_graders" -ge 1 ] && echo yes || echo no)" yes
  # "Tools follow graders" is the CLI's own hard rule: a `tool_used` grader with a lower
  # bound of 1 can only ever pass if the case granted that tool, so a case that forgets it
  # scores 0 in both arms and reads as "the plugin did nothing" rather than as a mistake.
  ungranted=""
  for g in "$EVALS/$c/graders"/*.md; do
    [ -f "$g" ] || continue
    [ "$(fm "$g" type)" = "tool_used" ] || continue
    # `min: 0` is the "must NOT call it" shape and needs no grant. Everything else —
    # including an ABSENT min, which the CLI defaults to 1 — does.
    case "$(fm "$g" min)" in 0) continue ;; esac
    t="$(fm "$g" tool)"
    case "$(fm "$P" allowed_tools)" in *"$t"*) ;; *) ungranted="$ungranted $t" ;; esac
  done
  ok "…and grants every tool its graders require" "${ungranted:-none}" none
  # Every case says how long it may run. An under-set budget scores 0 rather than timing
  # out, which reads as a red case about the plugin instead of one about the case file.
  ok "…and bounds its own run"                  "$([ -n "$(fm "$P" max_turns)" ] && echo yes || echo no)" yes
done

# The Skill tool is what the original four grade through, so it is asserted for them and
# not for the pattern cases, which grade the main thread's own actions instead.
# shellcheck disable=SC2046,SC2086  # deliberate word lists
for c in $CONTROL $(for s in $GATED; do echo "$s-is-human-gated"; done); do
  ok "$c declares the Skill tool as allowed" \
    "$(fm "$EVALS/$c/prompt.md" allowed_tools | grep -c 'Skill' | tr -d ' ')" 1
done

# Criterion 6 of the task: the README names them all, one line each. A case nobody can
# find in the README is a case the next author duplicates.
R="$EVALS/README.md"
for c in $CASES; do
  ok "the README gives $c exactly one table row" "$(grep -c "^| .$c." "$R" | tr -d ' ')" 1
done

# =======================================================================================
echo "== 3. the gated cases pin the EFFECT of disable-model-invocation, both ends =="
# =======================================================================================
for s in $GATED; do
  G="$EVALS/$s-is-human-gated/graders/$s-not-self-invoked.md"
  ok "$s: its grader ships"                     "$(yn test -f "$G")" yes
  ok "…a tool_used grader, not a paid judge"    "$(fm "$G" type)" "tool_used"
  ok "…graded on the Skill tool"                "$(fm "$G" tool)" "Skill"
  ok "…scoped to this skill by input_match"     "$(fm "$G" input_match)" "$s"
  # min AND max, both zero. `max: 0` alone reads as "1..0" — min defaults to 1 — and a
  # range no run can satisfy fails every time, including on a correct plugin. Measured
  # here 2026-09-05 before the fix: 3 of 4 cases red with "Skill called 0x (expected 1..0)".
  ok "…lower bound is 0, not the default 1"     "$(fm "$G" min)" "0"
  ok "…upper bound is 0 (never self-invoked)"   "$(fm "$G" max)" "0"
  # The tie back to the file harness: the eval grades an effect, and the effect has a
  # cause that plugin-skills.test.sh pins as text. If the two ever name different skills
  # the pair stops being a pair.
  ok "…and the skill it names is human-gated in the plugin" \
    "$(fm "$PLUGIN/skills/$s/SKILL.md" disable-model-invocation)" "true"
done

C_G="$EVALS/$CONTROL/graders/skill-tool-was-reached.md"
ok "the control arm asserts the OPPOSITE (min: 1)" "$(fm "$C_G" min)" "1"
ok "…through the same tool the gated cases watch" "$(fm "$C_G" tool)" "Skill"
ok "…and the same grader type"                    "$(fm "$C_G" type)" "tool_used"
ok "…and targets the requested welcome skill"     "$(fm "$C_G" input_match)" "welcome"
# Deliberately an assertion that an ABSENT key is absent. On its own it would also hold
# if fm() were broken and returned "" for everything — which is why it sits under three
# assertions on the same file that all demand a non-empty value, and never alone.
ok "…and sets no upper bound"                     "$(fm "$C_G" max)" ""

# =======================================================================================
echo "== 4. the pattern cases grade an OBSERVABLE ACTION, never a phrase =="
# =======================================================================================
# THE WHOLE POINT OF THESE THREE, and why the constraint is asserted rather than written
# in the README: a grader that greps a message for wording passes the next paraphrase, so
# it holds for exactly as long as nobody rephrases the rule — which is how the 2026-08-23
# prose fix for this same defect rotted. `regex` is the type that does that, so it is
# refused here; `tool_used` grades an action and an `llm` rubric grades what the session
# DID. Every rubric in these three says so in its own first line.
for c in $PATTERNS; do
  types=""; n=0
  for g in "$EVALS/$c/graders"/*.md; do
    [ -f "$g" ] || continue
    n=$((n+1)); types="$types
$(fm "$g" type)"
  done
  ok "$c: it ships graders"                      "$([ "$n" -ge 1 ] && echo yes || echo no)" yes
  ok "…none of them a wording grader (regex)"    "$(printf '%s\n' "$types" | grep -cx 'regex' | tr -d ' ')" 0
  ok "…each one an action grader or a rubric"    "$(printf '%s\n' "$types" | grep -cxE 'tool_used|llm' | tr -d ' ')" "$n"
  # An `llm` grader's rubric IS its body. Frontmatter alone is a grader that asks the judge
  # nothing and scores whatever the judge feels like — worse than no grader, because it
  # reports a number.
  for g in "$EVALS/$c/graders"/*.md; do
    [ -f "$g" ] || continue
    [ "$(fm "$g" type)" = "llm" ] || continue
    b="$(basename "$g")"
    ok "…$b carries its rubric in the file" \
      "$([ "$(body "$g" | grep -c .)" -ge 3 ] && echo yes || echo no)" yes
    ok "…and focuses on the run, not on the case file" \
      "$(fm "$g" focus | grep -cE '^(last_message|trace)$' | tr -d ' ')" 1
  done
done

# =======================================================================================
echo "== 5. the file harness keeps its pins — this suite replaces none of them =="
# =======================================================================================
# Criterion: nothing is deleted from plugin-skills.test.sh without a same-PR replacement.
# The eval covers ONE property (the effect of the split) for THREE skills; the shell
# harness still owns the written split for all ten state-changing skills, and everything
# else it asserts. These two assertions go red the day someone deletes the overlap
# thinking the eval has taken it over.
PS="$TPL/tests/plugin-skills.test.sh"
ok "plugin-skills.test.sh still ships"           "$(yn test -f "$PS")" yes
ok "…and still asserts the written split itself" \
  "$([ "$(grep -c 'disable-model-invocation' "$PS")" -ge 2 ] && echo yes || echo no)" yes
# This harness is the DEEP tier (ai-bridge-v3/task-038): a paid model run cannot sit on
# the merge gate, so the core must NOT name it, its own header must declare the tier the
# runner selects on, and a nightly workflow must be what runs it. All three are asserted
# — drop any one and the eval either never runs at all or runs on every PR.
RUNNER="$TPL/tests/run.sh"
WF="$TPL/.github/workflows/tests.yml"
DEEP_WF="$TPL/.github/workflows/tests-deep.yml"
ok "the merge-gating core does NOT name this harness" \
  "$(grep -c 'tests/plugin-eval.test.sh' "$RUNNER" | tr -d ' ')" 0
ok "…and this file declares the deep tier in its own header" \
  "$(yn grep -qE '^# deep( |$)' "$TPL/tests/plugin-eval.test.sh")" yes
ok "…and the nightly workflow runs that tier" \
  "$(yn grep -qF 'tests/run.sh --deep' "$DEEP_WF")" yes
ok "…and the PR workflow calls the runner that excludes it" \
  "$(yn grep -qF 'tests/run.sh --ci' "$WF")" yes

# =======================================================================================
echo "== 6. the run itself — where the CLI supports it, and a LOUD skip where it does not =="
# =======================================================================================
# THREE gates, and each one prints WHY. `claude plugin eval` runs ungated on 2.1.270 and was
# early access up to 2.1.263, where it refuses to run unless the account or the session is
# enabled for it — so "the binary is there" is not the question, and the probe stays for
# every build older than the one this was measured on. The probe is free — a --case glob
# that matches nothing makes no model call — and it tells the two states apart by what the
# CLI says.
unavailable=""
if ! command -v claude >/dev/null 2>&1; then
  unavailable="claude CLI not on PATH"
else
  probe="$(claude plugin eval "$PLUGIN" --case '__availability_probe__' --no-publish --ablation none 2>&1)"
  case "$probe" in
    *"early access"*) unavailable="the CLI has \`plugin eval\` gated off in this session (early access)" ;;
  esac
fi

if [ -n "$unavailable" ]; then
  # NEVER a silent pass: this line is the whole point of the gate. A reader scanning CI
  # output for the eval finds either a result or this sentence, never nothing.
  skipped "skipped: plugin eval unavailable — $unavailable"
  skipped "…so plugin/evals/ was NOT run here; its shape above is all that was checked"
else
  # --runs 1 and --ablation none: the shape of the run the harness needs is "did any case
  # go red", not a statistically stable score, and each extra run and each baseline arm is
  # another paid model run. The suite's own prompt.md files declare runs: 2 for a
  # by-hand `claude plugin eval ./plugin`, which is the higher-fidelity form.
  # --max-cost-usd is a ceiling, not a budget: it aborts (exit 2) rather than overrun. 7
  # against a measured $1.31 for the eight cases (2026-09-13, 2.1.270), which leaves room
  # for a case that dispatches a subagent whose own run is billed.
  # --judge-model claude-sonnet-5-5: the default judge is the background-task model (haiku),
  # and the CLI's own authoring guidance is that a small judge misses the distinctions a
  # rubric turns on. The rubrics here turn on one (a conclusion asserted vs. withheld), so
  # the judge is sized to it — and PINNED to a model id, never the `sonnet` alias, which
  # follows the current generation: a score that moved under a new judge reads as a plugin
  # regression. evals/README.md → "Running it" is the one place the pin is explained.
  # --trust-plugin: the first run in an untrusted plugin directory PROMPTS, and a harness
  # that waits for an answer nobody is there to give hangs instead of failing. The plugin
  # is this checkout's own.
  out="$(claude plugin eval "$PLUGIN" --runs 1 --ablation none --no-publish --trust-plugin \
    --judge-model claude-sonnet-5-5 --max-cost-usd 7 2>&1)"
  rc=$?
  # GATE 3 — AUTHENTICATION, and it is readable only AFTER the run. Neither probe above
  # makes a model call, so a logged-out CLI is indistinguishable from a working one until
  # a run is attempted; attempting one is free, because the CLI stops at the first failure
  # and bills $0.00. Measured on run 34787154536, where this gate did not yet exist: with
  # the CLI installed and no credential, `answer-is-human-gated` scored 1.00/100% — a
  # `tool_used` grader reads "Skill called 0x (expected 0..0)" as a PASS on a run that
  # never happened. So a silent fail here is not the worst case; a vacuous GREEN is.
  case "$out" in
    *"Not logged in"*|*"authentication failed"*)
      skipped "skipped: plugin eval unavailable — the claude CLI here is not logged in"
      skipped "…so plugin/evals/ was NOT run here; its shape above is all that was checked" ;;
    *)
      ok "claude plugin eval passes every case in plugin/evals/" "$rc" 0
      [ "$rc" -eq 0 ] || printf '%s\n' "$out" | sed 's/^/        /' ;;
  esac
fi

printf '\npass=%s fail=%s skip=%s\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
