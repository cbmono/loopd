#!/usr/bin/env bash
#
# review-route.test.sh — the CodeRabbit-less second opinion must stay CHEAP BY DEFAULT,
# and getting it must never widen a role agent's `tools:` allowlist.
#
# WHY THIS EXISTS. A PR that CodeRabbit did not review used to fan out to `code-architect`
# and `deep-bug-scan` unconditionally. Both declare `model: opus` in their OWN frontmatter,
# so that fan-out is two Opus agents regardless of what model the dispatcher is running —
# on top of an Opus `qa-reviewer`. Measured over one real diff, that pair cost 7.5x the
# input tokens of one Sonnet agent running the built-in `/code-review low`. So the cheap
# review is now the opening move and the expensive pair is an ESCALATION, fired on a
# trigger.
#
# Three things about that arrangement rot silently, which is why they are asserted here
# rather than trusted to prose:
#
#   1. THE ALLOWLIST INVARIANT. No role agent holds `Skill`; the route works because an
#      agent you DISPATCH declares no `tools:` key and so inherits it (rung 2 of
#      knowledge/findings/role-agents-cannot-invoke-skills.md). The tempting "fix" the
#      next time a skill is wanted is to add `Skill` to an allowlist — which injects a
#      mandatory "invoke skills before ANY action" preamble into every dispatch and widens
#      what that agent may do everywhere. That regression is invisible in a diff of prose.
#   2. THE GATING. Cheap-then-escalate saves nothing unless the cheap review is the
#      unconditional default AND the pair is conditional. Both halves have to hold; either
#      one alone reads fine and costs the same as before.
#   3. THE PRICES ON BOTH SIDES. The design rests on the pair being dear (`model: opus` in
#      their own files) and the default being cheap (`model: sonnet`, and exactly ONE
#      agent). Drop either pin and the gate is guarding nothing — which should fail loudly
#      and be reconsidered, not quietly kept as cargo.
#
# HOW THE GATING IS CHECKED, AND WHY NOT BY TEXT ORDER. The first version of this file
# compared the line of the first `/code-review` mention against the first `code-architect`
# mention. An independent review broke it by mutation in both directions: moving the whole
# escalation block ABOVE the cheap route still passed, because one plausible parenthetical
# naming `/code-review low` earlier in the file was enough; and the reverse — copying the
# agent's own frontmatter wording ("escalating to `code-architect` … only on a trigger")
# into the body intro, a perfectly correct edit — FAILED. A check that misses the
# regression and flags the correct edit is worse than none.
#
# So the anchors are the STRUCTURAL MARKERS of the two branches, not incidental mentions:
#
#     "default opening move"   the marker on case (b)   — the cheap route is the default
#     "Escalate when"          the marker on case (c)   — the pair is conditional
#
# and the assertions are: both markers exist, the default marker comes FIRST, the cheap
# literal sits with the default marker, and the pair is named with the escalation marker.
# Reordering the branches moves the markers and fails; mentioning an agent in prose
# elsewhere moves nothing. When the wording of a marker legitimately changes, this file has
# to change with it — deliberately, in the same commit, which is the point.
#
# WHERE A PROPERTY IS ONLY EXPRESSIBLE AS TEXT, the check is a PRESENCE or a PROXIMITY over
# a literal that carries meaning on its own, and section 7 pairs it with input it must
# reject. A text check that has never rejected anything is a comment with a `PASS` next
# to it.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

QA="$REPO/plugin/agents/qa-reviewer.md"

# Everything after the closing frontmatter delimiter. The frontmatter `description:`
# legitimately names both agents and the cheap route, so a body-only view keeps the
# assertions below from being satisfied by a one-line summary.
body() { awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {fm=2; next} fm!=1 {print}' "$1"; }

# `tools_of` and `has_tools_key` are deliberate copies of
# tests/agent-tool-allowlist.test.sh:90-99 — two files is under the threshold for a shared
# library, but if you fix a parsing bug in one, fix it in the other. Both handle only the
# inline comma form; section 1 asserts the parse is non-empty so a YAML block form fails by
# name rather than by every mention suddenly reading as unavailable.
tools_of() { # <file> — the tools: values, one per line; empty means "no key"
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit} fm==1 && /^tools:[[:space:]]*/ {
         sub(/^tools:[[:space:]]*/, ""); gsub(/,/, "\n"); print }' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

# First body line number matching a FIXED string, or 0 when absent. Fixed-string, because
# several needles here contain `/`, `.` or `-`.
first_line_or0() { local n; n="$(head -1 <<<"$(body "$1" | grep -nF -- "$2")" | cut -d: -f1)"; echo "${n:-0}"; }

# Is <regex-b> within <window> body lines of some occurrence of the fixed string <needle-a>?
# Used where what matters is that two things sit TOGETHER — a clause and the case it
# governs. A mention of each at opposite ends of the file is not the same statement.
near() { # <file> <needle-a> <regex-b> <window>
  local f="$1" a="$2" b="$3" w="$4" ln
  body "$f" > "$TMP/body"
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    grep -qiE -- "$b" <<<"$(awk -v c="$ln" -v w="$w" 'NR>=c-w && NR<=c+w' "$TMP/body")" && return 0
  done < <(grep -nF -- "$a" "$TMP/body" | cut -d: -f1)
  return 1
}

# Strict ordering over two markers: both must exist AND the first must come first. Absence
# is a failure, never a vacuous pass — `0 < n` would otherwise read as "in order".
before() { # <file> <needle-first> <needle-second>
  local x y
  x="$(first_line_or0 "$1" "$2")"; y="$(first_line_or0 "$1" "$3")"
  [ "$x" -gt 0 ] && [ "$y" -gt 0 ] && [ "$x" -lt "$y" ]
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/reviewroute.XXXXXX")" || {
  echo "review-route.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok "qa-reviewer.md exists" "$(yn test -f "$QA")" yes

# ================================================ 1. no allowlist was widened to get here
# The invariant criterion 4 of ai-bridge-v3/task-020 states directly. `Skill` is the tool
# the route wants; `SlashCommand` is the other way to reach a slash command and would buy
# the same capability under another name, so both are barred. A future grant is allowed —
# rung 4 of the Finding — but it has to come here and delete an assertion, in the same
# commit, where a reviewer sees it.
echo "== the allowlists stay narrow =="
AGENTS="$(find "$REPO/plugin/agents" -maxdepth 1 -type f -name '*.md' | sort)"
ok "shipped agent files found" "$([ -n "$AGENTS" ] && echo yes || echo no)" yes

# qa-reviewer specifically, because it is the file this harness is about and the one the
# route runs from. Asserted by name rather than by a roster count: a count is defeated by
# deleting the `tools:` line (which makes the file unrestricted, hence skipped) and fails
# spuriously when an agent is legitimately removed. `every shipped agent declares tools:`
# lives in tests/agent-tool-allowlist.test.sh:238, which is its right home.
ok "qa-reviewer declares tools:"              "$([ -n "$(tools_of "$QA")" ] && echo yes || echo no)" yes
ok "…and it is not Skill"                     "$(tools_of "$QA" | grep -cxF Skill)" 0
ok "…nor SlashCommand"                        "$(tools_of "$QA" | grep -cxF SlashCommand)" 0

# ...and the whole roster, so the grant cannot simply move to a sibling.
granted=0; scanned=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  tools_of "$f" > "$TMP/allow"
  [ -s "$TMP/allow" ] || continue          # no tools: key ⇒ unrestricted by design
  scanned=$((scanned+1))
  for t in Skill SlashCommand; do
    if grep -qxF "$t" "$TMP/allow"; then
      granted=$((granted+1))
      printf '        WIDENED  %s grants %s — see this file\x27s header\n' "${f#"$REPO"/}" "$t"
    fi
  done
done <<EOF
$AGENTS
EOF
ok "the scan saw restricted agents at all"      "$([ "$scanned" -gt 0 ] && echo yes || echo no)" yes
ok "no shipped agent grants Skill/SlashCommand" "$granted" 0

# ============================================================ 2. the cheap route is there
echo "== the cheap route =="
# The effort level is the whole point — `/code-review` at a high level is not the cheap
# substitute — so the literal includes it.
ok "qa-reviewer names /code-review low"       "$(yn grep -qF -- '/code-review low' "$QA")" yes
# And it must say how a restricted agent reaches a skill at all, or the next reader
# "fixes" it by granting the tool.
ok "…and points at the dispatch route"        "$(yn grep -qF -- 'role-agents-cannot-invoke-skills' "$QA")" yes

# ============================================ 3. the gating: cheap by default, pair on a trigger
echo "== the gating =="
DEF="$(first_line_or0 "$QA" 'default opening move')"
ESC="$(first_line_or0 "$QA" 'Escalate when')"
RAB="$(first_line_or0 "$QA" '.coderabbit.yaml')"
printf '  ..... body lines: default=%s escalate=%s .coderabbit.yaml=%s\n' "$DEF" "$ESC" "$RAB"
ok "case (b) is marked as the default"        "$([ "$DEF" -gt 0 ] && echo yes || echo no)" yes
ok "case (c) is marked as conditional"        "$([ "$ESC" -gt 0 ] && echo yes || echo no)" yes
ok "the default branch comes first"           "$(yn before "$QA" 'default opening move' 'Escalate when')" yes
# The cheap literal must live IN the default branch, not merely somewhere in the file —
# that gap is what made the first version of this check defeatable.
ok "the cheap route IS the default branch"    "$(yn near "$QA" 'default opening move' '/code-review low' 6)" yes
# ...and the expensive pair must be named WITH the trigger list that gates it.
ok "the pair is named with its trigger list"  "$(yn near "$QA" 'Escalate when' 'code-architect' 14)" yes
ok "both escalation agents are still named"   "$([ "$(first_line_or0 "$QA" 'code-architect')" -gt 0 ] \
                                                 && [ "$(first_line_or0 "$QA" 'deep-bug-scan')" -gt 0 ] \
                                                 && echo yes || echo no)" yes
# The external reviewer decides WHETHER any of this runs, so it is resolved first. Reading
# CodeRabbit after choosing a route is how a PR gets reviewed twice over one diff.
ok "the external reviewer is resolved first"  "$(yn before "$QA" '.coderabbit.yaml' 'default opening move')" yes

# The probes are what make a config-less machine work, and tests/config-layer.test.sh:103-104
# derives its "every probed agent ships" check from these exact strings. Escalation that
# stopped probing would take that check down with it, in another file.
ok "still probes for code-architect"          "$(yn grep -qF -- 'test -f ~/.claude/agents/code-architect.md' "$QA")" yes
ok "still probes for deep-bug-scan"           "$(yn grep -qF -- 'test -f ~/.claude/agents/deep-bug-scan.md' "$QA")" yes

# ============================================================== 4. absent ⇒ unchanged
echo "== the degrade path =="
# An older harness has no `code-review` skill. Anchored on case (d)'s own marker, so
# deleting that case fails these rather than being satisfied by case (b)'s prose about
# `Skill` possession — which is what the first version of this section did.
ok "case (d) exists"                          "$(yn grep -qF -- 'unreachable' "$QA")" yes
ok "…and names the unavailability causes"      "$(yn near "$QA" 'unreachable' 'older harness|skill.{0,10}absent|cannot invoke' 8)" yes
ok "…and is not an error path"                 "$(yn near "$QA" 'unreachable' 'never as an error|never an error|not an error|silent' 6)" yes
# AND the fallback must be UNCONDITIONAL, which is subtler than it looks and was a real
# defect in this file's first draft. The escalation in (c) is trigger-gated; if the degrade
# path merely says "escalate per (c)", then a benign diff on an older harness fires no
# trigger, runs no reviewer, and gets NO second opinion at all — the exact outcome the
# criterion forbids, reached by prose that reads perfectly. So it has to say out loud that
# no trigger is required.
ok "…and its fallback is unconditional"        "$(yn near "$QA" 'unreachable' 'unconditionally|no trigger required' 12)" yes

# ============================================== 5. the gate itself was not delegated away
echo "== the verifier survives the cheaper reviewer =="
# The saving is in the second OPINION. Acceptance-criteria verification and test writing are
# why this agent exists, and a diff review answers neither — so the criteria step must still
# be there AND must still say, next to itself, that the review does not stand in for it.
# Without this, "we already got a review" is the sentence that quietly retires the gate.
ok "the criteria step survives"               "$(yn grep -qF -- 'acceptance_criteria' "$QA")" yes
ok "…and disclaims the diff review"           "$(yn near "$QA" 'acceptance_criteria' 'does not touch it|substitute|never answers|not replaced' 12)" yes

# ================================================= 6. both prices the design depends on
echo "== the prices the gate is arbitrating =="
# THE EXPENSIVE SIDE. If either of these becomes a cheaper model, the gate in front of them
# is guarding nothing. Fail here and reconsider the design rather than keeping the gate as
# cargo. Pinned to exactly `opus`, so a rename or a variant also fails — deliberately.
for a in code-architect deep-bug-scan; do
  f="$REPO/config/required/agents/$a.md"
  ok "$a ships"                               "$(yn test -f "$f")" yes
  ok "…and declares model: opus"              "$(awk 'NR==1&&$0=="---"{fm=1;next} fm==1&&$0=="---"{exit} fm==1&&/^model:/{sub(/^model:[[:space:]]*/,"");print}' "$f")" opus
done
# THE CHEAP SIDE, which is half the design and had no test at all until an independent
# review pointed out that removing `model: sonnet` left every assertion green. A delegate
# that inherits the dispatcher's model is an Opus delegate in this instance, i.e. the
# saving deleted while the prose still describes it.
ok "the delegate is pinned to a cheap tier"   "$(yn near "$QA" 'default opening move' 'model: sonnet' 8)" yes
ok "…and there is exactly ONE of it"          "$(yn near "$QA" 'model: sonnet' 'single agent|ONE cheap|one cheap' 8)" yes
# And the one instruction in case (b) whose violation writes to the PR instead of informing
# a verdict. The reviewer posts; the delegate does not.
ok "the delegate may not write to the PR"     "$(yn near "$QA" '--comment' 'pass \*\*no\*\*|do not pass|never pass' 2)" yes

# ================================================== 7. non-vacuity: the matchers can fail
# Every check above is paired here with input it must reject, EXCEPT the plain presence
# greps (which fail trivially on absent text) — the gaps are named at the end rather than
# left for a reader to assume covered.
echo "== the matchers bite =="
FX="$TMP/fx"; mkdir -p "$FX"
mk() { printf -- '---\nname: fx\ntools: %s\n---\n%s\n' "$1" "$2" > "$FX/a.md"; }

# 7a. the allowlist scan finds a widened list, and a block-form `tools:` reads as empty
# rather than as a narrow list — which is why section 1 asserts the parse is non-empty.
mk 'Agent, Read, Skill' 'body'
ok "scan flags a granted Skill"               "$(tools_of "$FX/a.md" | grep -cxF Skill)" 1
mk 'Agent, Read' 'body'
ok "…and passes a narrow one"                 "$(tools_of "$FX/a.md" | grep -cxF Skill)" 0
printf -- '---\nname: fx\ntools:\n  - Skill\n---\nbody\n' > "$FX/a.md"
ok "a block-form tools: parses as empty"      "$([ -z "$(tools_of "$FX/a.md")" ] && echo yes || echo no)" yes

# 7b. THE MUTATION THAT DEFEATED THE FIRST VERSION. Escalation block above the default
# block, plus an innocuous earlier mention of the cheap route. Text-order comparison passed
# this; marker order rejects it.
mk 'Agent' 'Settle the external reviewer first (it decides whether /code-review low runs).
Escalate when any trigger holds: dispatch code-architect and deep-bug-scan.
Otherwise, ONE cheap review is the default opening move: /code-review low, model: sonnet.'
ok "marker order rejects escalation-first"    "$(yn before "$FX/a.md" 'default opening move' 'Escalate when')" no
# ...and accepts the intended shape.
mk 'Agent' 'Otherwise, ONE cheap review is the default opening move: /code-review low.
Escalate when any trigger holds: dispatch code-architect and deep-bug-scan.'
ok "…and accepts default-first"               "$(yn before "$FX/a.md" 'default opening move' 'Escalate when')" yes
# 7c. `before()` must not pass vacuously when a marker is missing — the failure mode of a
# bare `[ "$x" -lt "$y" ]` with `x=0`.
mk 'Agent' 'Escalate when any trigger holds.'
ok "before() rejects a missing first marker"  "$(yn before "$FX/a.md" 'default opening move' 'Escalate when')" no
mk 'Agent' 'ONE cheap review is the default opening move.'
ok "…and a missing second one"                "$(yn before "$FX/a.md" 'default opening move' 'Escalate when')" no

# 7d. the cheap literal must be IN the default branch: same file, far apart, must fail.
mk 'Agent' "$(printf 'Run /code-review low.\n%s\nONE cheap review is the default opening move.\n' "$(printf '  filler\n%.0s' {1..40})")"
ok "proximity rejects a distant literal"      "$(yn near "$FX/a.md" 'default opening move' '/code-review low' 6)" no
ok "…and accepts a nearby one"                "$(yn near "$FX/a.md" 'default opening move' '/code-review low' 60)" yes

# 7e. the cheap-tier pin: removing `model: sonnet` must fail, as it did not before.
mk 'Agent' 'ONE cheap review is the default opening move: dispatch a single agent.'
ok "a delegate with no tier pin fails"        "$(yn near "$FX/a.md" 'default opening move' 'model: sonnet' 8)" no

# 7f. the degrade anchor: deleting case (d) must fail, and case (b)'s `cannot invoke`
# sentence must not stand in for it. This is the exact vacuity an independent review found.
mk 'Agent' 'You cannot invoke this yourself: no restricted role agent holds Skill.'
ok "case (b) prose does not satisfy (d)"      "$(yn grep -qF -- 'unreachable' "$FX/a.md")" no

# 7g. the model: extractor reads the value, rather than always yielding `opus`.
printf -- '---\nname: fx\nmodel: sonnet\n---\nbody\n' > "$FX/a.md"
ok "the model: extractor reads the real value" \
   "$(awk 'NR==1&&$0=="---"{fm=1;next} fm==1&&$0=="---"{exit} fm==1&&/^model:/{sub(/^model:[[:space:]]*/,"");print}' "$FX/a.md")" sonnet

# NOT PAIRED, stated rather than implied: the plain `grep -qF` presence checks (the
# `/code-review low` literal, the Finding path, the two `test -f` probe strings,
# `acceptance_criteria`, `unreachable`) have no fixture — they fail on absent text by
# construction, so a fixture would only re-test `grep`. The proximity REGEXES in sections
# 4, 5 and 6 are covered as a mechanism (7d, 7f) but each individual alternation is not;
# if you widen one, widen it deliberately.

printf '\n%s passed, %s failed  (%s restricted agent file(s) scanned)\n' "$pass" "$fail" "$scanned"
[ "$fail" -eq 0 ]
