#!/usr/bin/env bash
#
# blocked-vs-own-tools.test.sh — a task that reports `blocked` for a reason naming a tool
# the agent's OWN `tools:` list already grants is the record contradicting itself, and
# `check-dispatch.sh` has to say so instead of clearing it as an honest stop.
#
# WHY THIS EXISTS, AND WHAT IT HONESTLY IS. The rule it backs
# (`seed/CONVENTIONS.md` → "Exhaust your own tools before you hand work back") is a
# BEHAVIOURAL DEFAULT, and this repo has documented six separate rules that were written,
# read as authoritative, and enforced by nothing — the failure only visible when the thing
# the rule forbade happened anyway. A default cannot be fully mechanised: an agent that
# quietly hands instructions back instead of acting leaves no artifact for anything to
# read, and no test here claims otherwise.
#
# ONE PIECE OF IT IS MECHANICAL, AND IT IS THE COMMON FAILURE. "I am blocked because I lack
# `Bash`", written by an agent whose own frontmatter grants `Bash`, is decidable from two
# files with no judgement at all. So that is what is asserted — the contradiction, not the
# behaviour — plus the rule text itself, because a rule deleted in a "shorten this file"
# edit fails silently otherwise and the detector would go on guarding a rule nobody reads.
#
# BOTH ANSWERS, ALWAYS. A detector that fires on everything is as useless as one that fires
# on nothing, and the fixtures below are half negative on purpose: an ungranted tool, a
# document that names a tool without claiming to lack it, prose with no backticks, and
# every shape where the question cannot be decided at all. The CREDULOUS BASELINE section
# is the measuring stick — a checker that always clears passes every positive fixture, so
# the difference between its results and the real script's is exactly what this change buys.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
SCRIPT="$REPO/plugin/scripts/check-dispatch.sh"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
PM="$REPO/plugin/agents/project-manager.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/blocked-vs-own-tools.XXXXXX")" || {
  echo "blocked-vs-own-tools.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# The mutants run from $TMP, and the script sources its sibling resolver
# (ai-bridge-v3/task-031) — without it they exit 2 before reaching their subject.
cp "$(dirname "$SCRIPT")/bundle-paths.sh" "$TMP/bundle-paths.sh"

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

[ -f "$SCRIPT" ] || { echo "blocked-vs-own-tools.test: no $SCRIPT" >&2; exit 2; }

# `gh` is deliberately removed from PATH for every case below. None of these fixtures
# names a pull request, so none of them needs the host — and asserting that here pins a
# property the verdict depends on: the contradiction is decided from two local files, so
# an offline machine, a missing CLI or a rate limit cannot silence it. That is the same
# reason check-dispatch.test.sh pins the parked catch without a network.
mkdir -p "$TMP/bin"
BASH_BIN="$(command -v bash)"
# The stock utility directories and nothing else — MINUS `gh`. `awk`, `sed`, `grep` and
# `dirname` all live in /usr/bin and /bin on both platforms CI runs; `gh` lives there too
# on Debian/Ubuntu (apt installs it to /usr/bin), while Homebrew puts it in
# /opt/homebrew/bin. So the stock directories are copied as a directory of symlinks that
# leaves `gh` out, and that farm is the PATH. Asserted below rather than assumed, because
# a PATH that still carried `gh` would make this section quietly claim a property it never
# tested — which is exactly what the bare `/usr/bin:/bin` did on Linux (2026-10-08).
# `bash` itself is invoked by ABSOLUTE path: the assignment is a command prefix, so a PATH
# without the interpreter's directory would fail the invocation with 127 before the
# script ever ran.
FARM="$TMP/nogh-farm"; mkdir -p "$FARM"
for d in /usr/bin /bin; do
  [ -d "$d" ] || continue
  entries=(); for f in "$d"/*; do [ "${f##*/}" = gh ] || entries+=("$f"); done
  [ "${#entries[@]}" -eq 0 ] || ln -s "${entries[@]}" "$FARM/" 2>/dev/null || true
done
BARE_PATH="$TMP/bin:$FARM"
run() { PATH="$BARE_PATH" "$BASH_BIN" "$SCRIPT" "$1" 2>&1; }
rc_of() { PATH="$BARE_PATH" "$BASH_BIN" "$SCRIPT" "$1" >/dev/null 2>&1; echo $?; }
ok "the offline PATH really has no \`gh\`" \
   "$(PATH="$BARE_PATH" command -v gh >/dev/null 2>&1 && echo no || echo yes)" yes

# ------------------------------------------------------------------ the fixture instance
# The two-part instance signature `check-dispatch.sh` walks up to find, plus one agent file
# whose `tools:` list is copied from the real `software-engineer` — if the shipped list ever
# stops granting `Bash`, this fixture stops testing what it says it tests, so it is asserted.
INST="$TMP/inst"
mkdir -p "$INST/.claude/agents" "$INST/projects/p/tasks"
printf '{\n  "org": "example-org"\n}\n' > "$INST/instance.config.json"
cat > "$INST/.claude/agents/software-engineer.md" <<'EOF'
---
name: software-engineer
description: fixture
tools: Read, Write, Edit, Glob, Grep, Bash, ToolSearch, mcp__claude-in-chrome__*
---

Fixture agent body.
EOF
cat > "$INST/.claude/agents/failure-analyst.md" <<'EOF'
---
name: failure-analyst
description: fixture
tools: Read, Glob, Grep, Bash
---

Fixture agent body.
EOF

mk() { # <name> <assignee> <body...>
  local f="$INST/projects/p/tasks/$1.md" who="$2"; shift 2
  {
    printf -- '---\ntype: Task\ntitle: synthetic\nkind: build\nstatus: blocked\n'
    [ -n "$who" ] && printf 'assignee: %s\n' "$who"
    printf 'target_repo: acme/widgets\nopen_questions: []\npr: [ ]\ntimestamp: 2026-08-30T00:00:00Z\n---\n\n'
    printf '%s\n' "$@"
  } > "$f"
  printf '%s\n' "$f"
}

echo "== the contradiction: blocked for want of a tool the agent already holds =="
HELD="$(mk held software-engineer '# Result' '' 'Blocked: I cannot run the migration without `Bash` access on this machine.')"
ok "blocked naming a granted tool          -> exit 4" "$(rc_of "$HELD")" 4
OUT="$(run "$HELD")"
ok "…the verdict names the task"        "$(grep -qF "held.md" <<<"$OUT" && echo yes || echo no)" yes
ok "…names the tool it already grants"  "$(grep -qF '`Bash`' <<<"$OUT" && echo yes || echo no)" yes
ok "…quotes the line it read it from"   "$(grep -qF 'run the migration' <<<"$OUT" && echo yes || echo no)" yes
ok "…points at the agent's allowlist"   "$(grep -qF "software-engineer.md" <<<"$OUT" && echo yes || echo no)" yes
ok "…names the route that is not blocked" "$(grep -qF 'open_questions' <<<"$OUT" && echo yes || echo no)" yes
# Report-only, same property the rest of this script has: a verdict is never a licence to
# act, and the message has to say so or a reader supplies its own next step.
ok "…and says it is a report, not an instruction" \
   "$(grep -qiF 'report, not an instruction' <<<"$OUT" && echo yes || echo no)" yes

# A wildcard grant covers everything under its prefix, so naming one member as missing
# contradicts the grant exactly as an exact name does. This is the shape that would slip
# past a plain string comparison.
WILD="$(mk wildcard software-engineer '# Result' '' 'Blocked: the `mcp__claude-in-chrome__navigate` tool is missing, so the page never loaded.')"
ok "an mcp__ member under a wildcard grant -> exit 4" "$(rc_of "$WILD")" 4

echo
echo "== and the other answer, four ways — a detector that always fires is not one =="
# 1. A tool the agent genuinely does NOT hold. The whole point of the middle rung.
NOTHELD="$(mk not-held software-engineer '# Result' '' 'Blocked: no `mcp__slack__*` server is connected, so nothing could be posted.')"
ok "blocked for a tool it does NOT hold    -> exit 0" "$(rc_of "$NOTHELD")" 0
# 2. A held tool named where nothing claims to lack it — an ordinary sentence about the
#    work. Without the lack-cue half of the rule this fires, and the check gets deleted.
MENTION="$(mk mention software-engineer '# Context' '' 'The harness uses `Bash` and `Grep` throughout.' '' '# Result' '' 'Blocked: the upstream contract is undecided; waiting on the owner.')"
ok "a held tool merely NAMED               -> exit 0" "$(rc_of "$MENTION")" 0
# 3. Prose, not an identifier. Without the backtick half, "no bash on the runner" fires —
#    and so does every sentence with the word "read" in it.
PROSE="$(mk prose software-engineer '# Result' '' 'Blocked: there is no bash on the runner and I could not read the file.')"
ok "the same words unbackticked            -> exit 0" "$(rc_of "$PROSE")" 0
# 4. A different agent, a narrower list. `failure-analyst` holds no browser tools, so the
#    fixture that contradicts software-engineer is an honest stop for this one.
OTHER="$(mk other-agent failure-analyst '# Result' '' 'Blocked: the `mcp__claude-in-chrome__navigate` tool is missing, so the page never loaded.')"
ok "an agent that really lacks it          -> exit 0" "$(rc_of "$OTHER")" 0

echo
echo "== silent wherever the question cannot be decided — never a guessed verdict =="
NOASSIGNEE="$(mk no-assignee '' '# Result' '' 'Blocked: no `Bash` on this machine.')"
ok "no assignee: to look up                -> exit 0" "$(rc_of "$NOASSIGNEE")" 0
UNKNOWN="$(mk unknown-agent nonexistent-role '# Result' '' 'Blocked: no `Bash` on this machine.')"
ok "an assignee with no agent file         -> exit 0" "$(rc_of "$UNKNOWN")" 0
# A task document outside any instance — a fixture, a scratch copy, another repo. There is
# no allowlist to read, so there is no contradiction to find.
mkdir -p "$TMP/loose"
cp "$HELD" "$TMP/loose/task-001.md"
ok "a task doc outside an instance         -> exit 0" "$(rc_of "$TMP/loose/task-001.md")" 0
# An agent file with no `tools:` key grants everything, which is not a contradiction anyone
# can read off the file.
cat > "$INST/.claude/agents/unrestricted.md" <<'EOF'
---
name: unrestricted
description: fixture with no tools key
---

Fixture agent body.
EOF
UNREST="$(mk unrestricted-assignee unrestricted '# Result' '' 'Blocked: no `Bash` on this machine.')"
ok "an agent with no tools: key            -> exit 0" "$(rc_of "$UNREST")" 0
# `assignee:` is a path component, so it must stay confined to one directory. A traversing
# value reads an arbitrary file otherwise.
TRAVERSE="$(mk traversal '../../../../etc/passwd' '# Result' '' 'Blocked: no `Bash` on this machine.')"
ok "a traversing assignee: is refused      -> exit 0" "$(rc_of "$TRAVERSE")" 0

echo
echo "== the check is scoped to \`blocked\` and does not disturb the other verdicts =="
# `cancelled` is a stop the human made, not a claim about tools, so it clears whatever the
# document says. And a `blocked` document with a clean reason still clears, which is the
# behaviour every existing caller depends on (check-dispatch.test.sh pins it too).
sed 's/^status: blocked$/status: cancelled/' "$HELD" > "$INST/projects/p/tasks/cancelled.md"
ok "cancelled with the same body           -> exit 0" "$(rc_of "$INST/projects/p/tasks/cancelled.md")" 0
CLEAN="$(mk clean-block software-engineer '# Result' '' 'Blocked: the staging database has been down since Tuesday.')"
ok "an ordinary honest stop                -> exit 0" "$(rc_of "$CLEAN")" 0

echo
echo "== CREDULOUS BASELINE: what a checker that believes the report scores =="
# The measuring stick, built the way check-dispatch.test.sh builds its own: a checker that
# clears everything passes every NEGATIVE case above, so those assertions alone prove
# nothing. Only the positives discriminate, and this block is what says so out loud — if
# the positives ever stop discriminating, this comparison is where it shows.
cat > "$TMP/credulous.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cred_rc() { bash "$TMP/credulous.sh" "$1" >/dev/null 2>&1; echo $?; }
ok "credulous clears the contradiction (the gap)" "$(cred_rc "$HELD")" 0
ok "credulous clears the wildcard case too"       "$(cred_rc "$WILD")" 0
ok "…and agrees with the real script everywhere else" \
   "$(if [ "$(cred_rc "$NOTHELD")" = "$(rc_of "$NOTHELD")" ] && \
         [ "$(cred_rc "$MENTION")" = "$(rc_of "$MENTION")" ] && \
         [ "$(cred_rc "$PROSE")" = "$(rc_of "$PROSE")" ]; then echo yes; else echo no; fi)" yes

echo
echo "== the fixture has to keep testing what it claims — pin it to the shipped agents =="
# If the real software-engineer stops granting `Bash`, or failure-analyst starts granting the
# browser tools, the fixtures above quietly stop reproducing the contradiction.
real_tools() { # <agent>
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit}
       fm==1 && /^tools:/ {print}' "$REPO/plugin/agents/$1.md"
}
ok "software-engineer really grants \`Bash\`" \
   "$(grep -qE '(^|[ ,])Bash([ ,]|$)' <<<"$(real_tools software-engineer)" && echo yes || echo no)" yes
ok "software-engineer really holds the browser grant" \
   "$(grep -qF 'mcp__claude-in-chrome__*' <<<"$(real_tools software-engineer)" && echo yes || echo no)" yes
ok "failure-analyst really holds no browser grant" \
   "$(grep -qF 'mcp__claude-in-chrome__' <<<"$(real_tools failure-analyst)" && echo no || echo yes)" yes

echo
echo "== the rule the detector guards must still be in CONVENTIONS.md =="
# A detector outliving its rule is the worse half of "a rule with no reader": the check
# stays green while the sentence it enforces has been edited away, so nobody reads the rule
# and nobody notices. These are the clauses the acceptance criteria name, asserted verbatim.
saw() { grep -qF "$2" "$1" && echo yes || echo no; }
# The same question against a STRING rather than a file, for a live render.
saw_s() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }
# The same question against a whitespace-flattened copy, for a clause the file wraps across
# two lines. Reflowing a paragraph must not turn a rule's assertion red — that is upkeep
# masquerading as a finding — so anything spanning a line break is asserted this way.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
saw_flat() { grep -qF "$2" <<<"$(flat "$1")" && echo yes || echo no; }
ok "the three-rung default is stated"      "$(saw "$CONV" '**Exhaust your own tools before you hand work back — three rungs, in order.**')" yes
ok "rung 1 — do it yourself"               "$(saw "$CONV" '**Do it yourself**, with the tools you hold')" yes
ok "rung 2 — ask for the tool"             "$(saw "$CONV" '**Else ask for access to the tool that would let you.**')" yes
ok "rung 3 — hand back exact instructions" "$(saw "$CONV" '**Only then hand back exact instructions**')" yes
# THE SHIP-BLOCKER. Each half is asserted separately: the scope of the ladder, the class it
# excludes, the examples, the principle that resolves an unlisted case, and the sentence a
# reviewer can point at that refuses the licence reading.
ok "the ladder is scoped to capability"    "$(saw "$CONV" 'THE LADDER COVERS CAPABILITY GAPS ONLY.')" yes
ok "…and authority stays human regardless" "$(saw "$CONV" 'AN AUTHORITY GAP STAYS HUMAN REGARDLESS OF' )" yes
ok "the authority class is exampled"       "$(saw "$CONV" 'promoting a task `draft → ready`; merging a pull')" yes
ok "…destructive and irreversible named"   "$(saw "$CONV" '**any destructive or irreversible action**')" yes
ok "…outward-facing named"                 "$(saw "$CONV" '**anything outward-facing**')" yes
ok "…and carries its PRINCIPLE"            "$(saw "$CONV" 'tool availability was never what made these human')" yes
ok "an unplaceable case resolves human"    "$(saw_flat "$CONV" 'cannot place is an authority gap until a human says otherwise')" yes
ok "THE sentence that refuses the licence" "$(saw "$CONV" '**Nothing in this bullet is licence over the authority class.**')" yes
ok "…and says rung 1 never reaches one"    "$(saw "$CONV" '**it never reaches an authority gap at all**')" yes
ok "…naming the unwatched dispatch"        "$(saw "$CONV" 'a background dispatch tick, hours from anyone watching')" yes
# THE MIDDLE RUNG NEVER BLOCKS (Q1, option b).
ok "the middle rung never blocks"          "$(saw "$CONV" '**The middle rung NEVER BLOCKS: record the tool request, then carry on.**')" yes
ok "…blocked is not the response"          "$(saw_flat "$CONV" '`blocked` is not the response to a missing tool')" yes
ok "…halting turns a gap into a stalled task" "$(saw_flat "$CONV" 'turns a missing CLI into a stalled task')" yes
ok "…records the request and continues"    "$(saw "$CONV" '`open_questions`**, **continue**')" yes
ok "…and reports what it could not reach"  "$(saw "$CONV" '**report exactly what you could not reach**')" yes
ok "the existing mechanism is named"       "$(saw "$CONV" 'Use the mechanism that already exists — nothing new is built for this.')" yes
ok "…the human's --- answer path"          "$(saw "$CONV" 'the human appends ` --- <answer>` to the entry')" yes
# WHY THERE IS NO LIVE CHANNEL — so nobody re-proposes one.
ok "no live channel, with the reason"      "$(saw "$CONV" '**There is no live channel, and here is why, so nobody proposes one.**')" yes
ok "…no upward tool is held"               "$(saw "$CONV" 'holds `AskUserQuestion`, and none is granted a message-sending tool')" yes
ok "…final message on termination"         "$(saw "$CONV" 'final message on termination')" yes
ok "…tool list fixed at dispatch"          "$(saw "$CONV" 'list is fixed at dispatch and MCP servers connect at session start')" yes
ok "…so a mid-flight grant cannot arrive"  "$(saw "$CONV" 'never reaches the running agent')" yes
# The detector is named in the rule, so an agent reading the rule knows what reads it back.
ok "the rule names its reader"             "$(saw_flat "$CONV" '`check-dispatch.sh` — the dispatch-artifact bullet below gives its path — reports that as exit 4')" yes
ok "…and names this file"                  "$(saw "$CONV" 'tests/blocked-vs-own-tools.test.sh')" yes
# CRITERION 5: one statement of the browser rule, not two. The old browser-only wording is
# gone and the paragraph defers to the general rung.
ok "the browser paragraph defers to rung 1" "$(saw "$CONV" '**rung 1 above applies to the browser like any other tool**')" yes
ok "…and says so, so it is not re-added"    "$(saw_flat "$CONV" 'it is the general one now, stated once, so the two cannot drift')" yes
# The old wording, gone from the whole shared bundle rather than from one paragraph — two
# statements of one rule is the thing criterion 5 forbids, so the assertion is tree-wide.
#
# IT WAS NOT TREE-WIDE, AND IT COULD NOT FAIL. The single root was `$REPO/symlink`, retired
# in #122 — `grep -r` over a missing directory exits 2, the `&&` arm never runs, and `yes`
# is exactly what this line expects. Found by tests/harness-read-paths.test.sh on its first
# run over the $REPO-rooted harnesses (ai-bridge-v2/task-029); the roots below are the ones
# approach-critique-trigger.test.sh and subagent-resume-rule.test.sh already sweep, and
# CONVENTIONS.md itself lives under the first of them, so the scan provably can act.
ok "the tree-wide scan can act at all"      "$([ -f "$REPO/plugin/seed/CONVENTIONS.md" ] && echo yes || echo no)" yes
ok "no browser-only restatement survives"   \
  "$(grep -rqF 'browser-first' "$REPO/plugin/seed" "$REPO/docs" "$REPO/README.md" "$REPO/CLAUDE.md" && echo no || echo yes)" yes
ok "…and the missing-browser case defers too" "$(saw_flat "$CONV" 'that is a capability gap, so take the non-browser route, say so, and carry on')" yes

echo
echo "== MUTATION: delete the rule and every assertion above it flips =="
# The edit this file exists to catch is not a rewrite — it is someone shortening
# CONVENTIONS.md and taking the bullet with them. Without this block the assertions above
# could be passing because `grep -qF` matched something incidental.
awk '
  /^- \*\*Exhaust your own tools before you hand work back/ { drop=1 }
  drop && /^- / && !/^- \*\*Exhaust your own tools/ && !/^- \*\*The middle rung NEVER BLOCKS/ { drop=0 }
  !drop { print }
' "$CONV" > "$TMP/conv-mutant.md"
ok "the mutation removed something"        "$([ "$(wc -c < "$TMP/conv-mutant.md")" -lt "$(wc -c < "$CONV")" ] && echo yes || echo no)" yes
ok "CONTROL: the PR-shape bullet survives" "$(saw "$TMP/conv-mutant.md" '**The PR body has a required shape, and it is short — 2,500 characters, hard**')" yes
ok "CONTROL: the browser bullet survives"  "$(saw "$TMP/conv-mutant.md" '**rung 1 above applies to the browser like any other tool**')" yes
ok "mutant: the three rungs are gone"      "$(saw "$TMP/conv-mutant.md" '**Only then hand back exact instructions**')" no
ok "mutant: the capability scope is gone"  "$(saw "$TMP/conv-mutant.md" 'THE LADDER COVERS CAPABILITY GAPS ONLY.')" no
ok "mutant: the licence refusal is gone"   "$(saw "$TMP/conv-mutant.md" '**Nothing in this bullet is licence over the authority class.**')" no
ok "mutant: never-blocks is gone"          "$(saw "$TMP/conv-mutant.md" '**The middle rung NEVER BLOCKS: record the tool request, then carry on.**')" no
ok "mutant: the no-live-channel reason is gone" "$(saw "$TMP/conv-mutant.md" '**There is no live channel, and here is why, so nobody proposes one.**')" no

echo
echo "== AWAITING.md tells 'grant a thing' apart from 'answer a question' =="
# Criterion 12. The queue is RENDERED by build-awaiting.sh since ai-bridge-v3/task-024 —
# the script owns the glyph so the model can never pick one, and the two asks read
# identically without a verb of their own: a request to install a CLI looks like a question
# the human disposes of by typing a sentence. The rows are asserted against a LIVE render
# rather than against the script's source, which is strictly the stronger claim.
QUEUE="$REPO/plugin/scripts/build-awaiting.sh"
ok "the renderer exists"                   "$([ -f "$QUEUE" ] && echo yes || echo no)" yes
Q="$TMP/queue"; mkdir -p "$Q/projects/p/tasks" "$Q/$AB_DIR"
printf '{ "org": "x" }\n' > "$Q/instance.config.json"; printf '# S\n' > "$Q/$AB_SCHEMA"; : > "$Q/$AB_AWAITING"
printf -- '---\ntype: Project\ntitle: "P"\nstatus: active\n---\n' > "$Q/projects/p/project.md"
printf -- '---\ntype: Task\ntitle: "T"\nstatus: draft\nacceptance_criteria: [ "x" ]\nopen_questions: [ "Q1: which colour?", "Q2: install the foo CLI" ]\n---\n' \
  > "$Q/projects/p/tasks/task-001-t.md"
bash "$QUEUE" --instance "$Q" >/dev/null 2>&1
RENDER="$(cat "$Q/$AB_AWAITING" 2>/dev/null || true)"
ok "the queue layout has a grant verb"     "$(saw_s "$RENDER" '* 🧰 **grant** — [T](/projects/p/tasks/task-001-t.md) · ')" yes
ok "…distinct from the answer verb"        "$(saw_s "$RENDER" '* ❓ **answer** — [T](/projects/p/tasks/task-001-t.md) · ')" yes
ok "…and says why they are different asks" "$(saw "$QUEUE" 'are different asks, and that is why `grant` has a glyph of')" yes
ok "…and that the reply mechanism is unchanged" "$(saw "$QUEUE" '**reply mechanism is the same**')" yes
# The banner's contract: it greps the heading and a `* ` marker. A verb glyph sits AFTER
# the marker, so it costs the banner nothing — asserted rather than assumed, because
# getting this wrong empties the startup nudge silently instead of failing.
ok "the grant row keeps the '* ' marker"   "$(printf '%s\n' "$RENDER" | grep -cE '^\* 🧰 \*\*grant\*\*' | tr -d ' ')" 1
ok "…and the heading contract is restated" "$(saw "$QUEUE" 'Keep the `## 🔴 Awaiting you` heading and the `*` marker followed by one space')" yes
ok "…and the marker/verb split is stated"  "$(saw "$QUEUE" '**A new verb is free; a new marker is not**')" yes

echo
echo "== the agent file is resolved from the PLUGIN, not only from the bundle =="
# The name swap moved the eight role agents out of every instance and into the
# `loopd` plugin, which is installed per MACHINE. So the one path literal this check
# used to read is gone, and the resolution has three sources — the ORDER is the contract,
# because a bundle stamped before the swap still has an exact local copy and reading a
# machine-wide one instead would answer for the wrong template.
#
# Driven through a real `CLAUDE_CONFIG_DIR`, never by inspecting the source: the failure
# this guards against is a resolver that finds nothing and stays silent, which reads
# exactly like a task with no contradiction in it.
AF="$TMP/agentfile"; mkdir -p "$AF/cfg/plugins" "$AF/inst"
CACHE="$AF/cfg/plugins/cache/${PMK}/${PN}"
mkdir -p "$CACHE/0.9.0/agents" "$CACHE/0.11.0/agents"
printf 'v0.9.0\n'  > "$CACHE/0.9.0/agents/software-engineer.md"
printf 'v0.11.0\n' > "$CACHE/0.11.0/agents/software-engineer.md"
printf '{}\n' > "$AF/inst/instance.config.json"

# CUT from the shipped script, not copied into this file: a local copy would keep passing
# after the real one broke, which is the whole failure this section is written against.
awk '/^agent_file\(\) \{/{f=1} f{print} f && /^\}/{exit}' "$SCRIPT" > "$AF/fn.sh"
ok "the resolver was extractable (or the rest is vacuous)" \
   "$(bash -n "$AF/fn.sh" 2>/dev/null && grep -c '^agent_file() {' "$AF/fn.sh")" 1

resolve() { # — run the script's own agent_file() against the fixture config dir
  CLAUDE_CONFIG_DIR="$AF/cfg" bash -c '. "$1"; agent_file "$2" software-engineer' \
    _ "$AF/fn.sh" "$AF/inst"
}

# Newest, not last: the glob is lexical, and lexically 0.9.0 sorts after 0.11.0.
ok "no install record -> newest cached version" "$(resolve)" "$CACHE/0.11.0/agents/software-engineer.md"
printf '{"version":2,"plugins":{"'"${PN}@${PMK}"'":[{"scope":"user","installPath":"%s/0.9.0","version":"0.9.0"}]}}\n' \
  "$CACHE" > "$AF/cfg/plugins/installed_plugins.json"
ok "…the install record wins over the newest" "$(resolve)" "$CACHE/0.9.0/agents/software-engineer.md"
mkdir -p "$AF/inst/.claude/agents"; printf 'bundle\n' > "$AF/inst/.claude/agents/software-engineer.md"
ok "…and a pre-swap bundle copy wins over both" "$(resolve)" "$AF/inst/.claude/agents/software-engineer.md"
rm -rf "$AF/inst/.claude" "$AF/cfg/plugins/installed_plugins.json" "$CACHE"
ok "nothing resolvable anywhere -> silence, not an error" "$(resolve)" ""

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
