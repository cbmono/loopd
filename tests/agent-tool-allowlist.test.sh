#!/usr/bin/env bash
#
# agent-tool-allowlist.test.sh — an agent file, or a shared conventions doc an agent
# reads, must not name a tool that is absent from the addressed agent's `tools:` list.
#
# WHY THIS IS A TEST AND NOT A CONVENTION. A `tools:` allowlist is invisible from the
# prose it governs: `software-engineer.md` reads perfectly until you notice the agent
# holds no `Agent` tool, at which point "dispatch `code-architect` if it's installed in
# `~/.claude/agents/`" turns out to test the wrong thing entirely — installation, when
# what decides the outcome is tool possession. `code-architect` IS installed, so the
# condition evaluated TRUE and the instruction was still unexecutable. That is the worst
# shape a defect can take: it reads as satisfied. Three more instances existed at
# 178c16f (`Workflow` in `auditor.md`, `qa-reviewer.md`, `software-engineer.md`, plus
# `EnterWorktree` in `CONVENTIONS.md`), and a fifth will appear the next time the harness
# moves a capability into a tool. So the class is asserted here rather than trusted to
# whoever next edits an agent body.
#
# THE RULE, AND WHY IT IS THIS ONE. False positives are the whole difficulty: the first
# manual sweep for this class was fooled by ordinary English — "never *write* to the
# bundle", "the *agent* roster", "*workflow* structure", "the *task* document". A check
# that cries wolf gets deleted, so:
#
#   A mention counts ONLY as a BACKTICKED IDENTIFIER from a vocabulary of harness
#   tool names — `Workflow`, `Agent`, `Skill`, ... plus `mcp__*`.
#
# Backticks are what this codebase already uses to mean "the identifier, not the word"
# (a role agent's "you have `Read`, `Glob` and `Grep` and nothing else" sentence is exactly
# that — the since-retired `advisor.md` was the worked example), so an unbackticked prose
# word can never become a violation. A backticked CAPITALISED one is a different matter and
# the vocabulary is no longer closed against it: it must be CLASSIFIED by one of the four
# rules in the lexicon below, or it fails. Both halves are asserted against fixtures,
# including the four prose words above.
#
# WHO IS "THE ADDRESSED AGENT" FOR A SHARED DOC. `CONVENTIONS.md` is read by
# `software-engineer`, `devops-engineer`, `qa-reviewer` and `failure-analyst` at once, and
# their allowlists differ. This check takes the conservative reading: an instruction in a
# shared doc must be executable by EVERY agent that reads it, so the doc's effective
# allowlist is the INTERSECTION of its readers'. The reader set is derived mechanically
# (which agent bodies reference the doc), not hardcoded, so adding a reader tightens the
# constraint automatically.
#
# THE ESCAPE HATCH, AND WHY THERE HAS TO BE ONE. Naming an absent tool is sometimes the
# correct thing to write — `failure-analyst.md:28-30` names `Skill` precisely to record that
# it must not be reinstated, and the fix for the defects above states the absence rather
# than hiding it. So a file may declare a mention as deliberate:
#
#   <!-- tool-mention: Workflow(2), Agent(2) — why this file names a tool a reader lacks -->
#
# The reason is mandatory (an empty one fails), each name carries a `(N)` budget, and a
# declaration is flagged when it is stale (the tool is no longer mentioned) or redundant
# (the tool IS in the allowlist), so it cannot rot into a rubber stamp. A declaration is
# per-(file, tool) rather than per-mention, so what keeps it from covering the next author's
# NEW unconditional instruction is the pair of conditions at §the-deciding-condition below:
# the budget (a new mention breaks the count) and the prose test (a declared mention must
# state the absence and must not read as an instruction). Both were added because the
# version without them was measurably too weak, and both have their residual gaps stated
# where they are implemented rather than summarised away here.
#
# WHICH FILES ARE SCANNED IS DERIVED, NOT LISTED. The first version named two shared docs
# by hand (`seed/CONVENTIONS.md`, `seed/CLAUDE.md`) and so could only ever check the
# two someone remembered — `seed/SCHEMA.md`'s browser-access section named
# `mcp__claude-in-chrome__*` to five readers whose intersection is `Bash Glob Grep Read`,
# and the check was
# silent because the file was not on the list. A doc addresses an agent when an agent is
# TOLD TO READ IT, so that is what is derived: every `*.md` reference in a restricted
# agent's body, resolved against the trees this repo ships (`symlink/`, then `seed/`).
# Adding a doc reference to an agent body therefore puts the doc in scope by itself.
#
# OUT OF REACH FROM THIS REPO: a live instance's own `CLAUDE.md`. It is a real file in
# each bundle, not a symlink to anything here, so a copy of a rule that drifts into it
# cannot be checked from here — `seed/CLAUDE.md` (the template every new instance is
# stamped from) is covered instead, and `upgrade.sh` is the route for existing ones.
#
# Agents that declare NO `tools:` key inherit the full tool set and are therefore
# unconstrained — every agent shipped under `config/*/agents/` (found dynamically below,
# not by naming a tier, so this stays correct as tiers are added or removed). They are
# skipped, and that skip is asserted rather than assumed: if one of them ever grows a
# `tools:` key, the assertion below fails and points here.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# =================================================================== THE LEXICON
# ONE place classifies every identifier this check reasons about, and it has two halves
# because a name is either a harness tool or it is not. Both halves are maintained here
# and nowhere else.
#
# WHY THIS IS NOT JUST A CLOSED LIST ANY MORE. It was, and the closed list leaked in the
# one direction that cannot be seen: a tool absent from `VOCAB` is not "prose", it is
# INVISIBLE — the check passes, which is indistinguishable from there being nothing to
# find. That is the same shape as the defect this whole file exists to catch, one level
# up. `AskUserQuestion`, `ExitWorktree` and `Artifact` were all missing at once; `Artifact`
# was found only because a PM tick happened to start granting it. So the list is now
# pinned from BOTH sides by two guards below, and neither is a count:
#
#   GUARD A (§0a) — every tool GRANTED by a shipped agent's `tools:` list must appear in
#   `VOCAB`. The bundle adopts a new harness tool by granting it, so this is the moment a
#   new tool exists here at all, and the lexicon fails until it is told. This is the guard
#   that would have caught `Artifact` on the commit that granted it, before any prose.
#
#   GUARD B (§0b) — a backticked capitalised identifier in a scanned file that no
#   classification rule below recognises FAILS as unclassified. So an unrecognised name is
#   loud, not ignored — INCLUDING a single-word one, which is the case this guard was
#   first shipped too narrow to see.
#
# WHY GUARD B COVERS SINGLE WORDS, AND WHAT IT COST TO GET THERE. The first version of this
# guard fired only on MULTI-WORD CamelCase, on the argument that Guard A covered the
# single-word residue. That argument is false for the case that matters most, and it was
# reproduced rather than reasoned about: appending `` Use the `Deploy` tool to ship the
# change. `` to `software-engineer.md` left this harness at 62 passed, 0 failed. `Deploy` is
# ungranted, so Guard A never fires; single-word, so Guard B skipped it. Guard A only ever
# covers a tool some agent ACTUALLY GRANTS — never a hallucinated name granted nowhere,
# which is precisely the case a prose-vs-allowlist check exists to catch. The guard had the
# same shape as the defect it guards, one more level up.
#
# So Guard B now fires on every backticked capitalised identifier, and the false-positive
# population it has to survive is the whole difficulty. Measured over the derived scanned
# set (17 files): 18 distinct non-tool names, 61 mentions. Failing all of them is the
# cry-wolf failure that gets a check deleted, so each is classified by a RULE rather than by
# being listed, and two of the four rules are derived or shape-based — which is the answer
# to "a hand-maintained list of non-tools is the same closed-list problem one level over":
#
#   1. IT IS A HARNESS TOOL — `VOCAB` below, pinned by Guard A. (24 names plus `mcp__*`.)
#   2. IT IS AN OKF DOCUMENT TYPE — DERIVED from `seed/SCHEMA.md`'s own `type:` headings,
#      which is the schema registry itself. Covers 7 distinct / 43 mentions (`Finding`,
#      `Service`, `Runbook`, `Team`, `Reference`, `Project`, `Task`). Self-tightening: a new
#      OKF type is classified by the commit that documents it, with no edit here. This also
#      replaces the hand-written `Task` exclusion with a derivation — see below.
#   3. IT IS A SCREAMING LITERAL — all capitals, no lowercase letter. Covers 10 distinct /
#      17 mentions (`APPROVED`, `DISMISSED`, `KEEP`, `RECLAIMABLE`, `REMOVABLE`, `STALE`,
#      `TICK`, `MERGED`, `UNREGISTERED`, `HEAD`): the board renderers' literal output tokens
#      and a git ref. This is a SHAPE rule, not a list, so a renderer adding a status token
#      does not break the build. It rests on one fact worth stating because it is the
#      residual: NO harness tool has ever been named in all capitals — every name in
#      `VOCAB` carries a lowercase letter, and that is asserted — so a hallucinated
#      `` `DEPLOY` `` would still
#      be missed where `` `Deploy` `` is now caught. Measured, disclosed, not hidden.
#   4. IT IS ON THE `NOT_A_TOOL` LIST, AND IS JUSTIFIED BY USE — the residue rule 1-3 cannot
#      reach, and a hand-maintained list rots the exact way `VOCAB` did if an entry is
#      pre-populated rather than earned. So EVERY entry must have at least one real
#      backticked mention somewhere in the machinery it documents (`symlink/`, `.claude/`,
#      `CLAUDE.md`) or the build fails naming the dead entry — a fourth recognition route,
#      and it is asserted rather than trusted. This is the route a prior pass of this same
#      guard got wrong: it pre-populated the whole Claude Code hook-event family (10 names)
#      on the argument that "the next one documented must not break the build", measured
#      NONE of them against the real tree, and the un-earned 9 were exactly as silent as the
#      closed `VOCAB` this file replaced — `` `Notification` ``, `` `PreToolUse` ``,
#      `` `PreCompact` `` and `` `SubagentStop` `` were all reproduced as invisible.
#      Two names earn their keep today: `SessionStart` (a real hook event, mentioned once in
#      the scanned set) and `Makefile` (mentioned once). Both are asserted, not assumed.
#
# Anything else fails. The upkeep that leaves is real but it points the other way from the
# closed list this guard replaced: a name nobody classified produces a BUILD FAILURE naming
# the file, the line and the four routes — noise, which a maintainer fixes — where the
# closed `VOCAB` produced SILENCE, which nobody can see. That asymmetry is the whole reason
# this direction is acceptable and the other was not — and it now applies to rule 4 itself,
# not only to what rule 4 exempts.
#
# `Task` is DELIBERATELY NOT IN `VOCAB` even though it is the dispatch tool's name in some
# harness versions: OKF's own document type is also `Task`, and this bundle backticks that
# type constantly (`seed/SCHEMA.md:441`, `docs/schema.md:27`, `new-project.md:58`).
# Including it would flag the bundle's core vocabulary as a tool reference. It is now kept
# quiet by rule 2 rather than by a comment, which is stronger: the schema is what says it is
# a document type. `Agent` is the name that decides dispatch here and it is BOTH an OKF type
# and a tool — rule 1 wins, so it stays checked as a tool. `Artifact` is on the list even though
# NOTHING GRANTS IT ANY MORE — the PM tick that published the board was deleted, and a
# name dropped from `VOCAB` stops being checked as a tool and starts being reported as an
# unclassified identifier, which is the silence this whole guard exists to end. A real
# harness tool belongs here whether or not this bundle currently uses it. The collision it
# has to survive is OKF's `artifacts:` field, and it does — that is lowercase and plural,
# and a mention only counts inside backticks as this exact identifier.
VOCAB='Agent|Artifact|AskUserQuestion|Workflow|Skill|Read|Write|Edit|MultiEdit|NotebookEdit|Glob|Grep|Bash|BashOutput|KillShell|KillBash|WebFetch|WebSearch|TodoWrite|ToolSearch|SlashCommand|ExitPlanMode|EnterWorktree|ExitWorktree|mcp__[A-Za-z0-9_*-]+'
MENTION_RE="\`($VOCAB)\`"

# The other half of the lexicon: identifiers this bundle backticks that are NOT tools and
# that no other RULE classifies, so Guard B stays quiet on them. This is a HAND-MAINTAINED
# list, so it is the one route that can rot the way the closed `VOCAB` did — an entry added
# here speculatively, before anything in the tree actually names it, is dead configuration
# that classifies nothing and is indistinguishable from an entry that is doing real work.
# That happened once already: the whole Claude Code hook-EVENT family was pre-populated on
# the argument that "the next one documented must not break the build" — 9 of the 11 names
# below turned out to have ZERO real mentions anywhere in `symlink/`, `.claude/` or
# `CLAUDE.md`, and each is a silent classification route for exactly the shape this file
# exists to catch. GUARD C, below, makes that self-correcting: every entry here must be
# JUSTIFIED BY A REAL MENTION or the build fails naming it, so an entry can only be added in
# the same commit that adds the mention it is for. Add a name here ONLY after checking it is
# not a tool and no other rule can classify it — this list is the residue, and Guard C keeps
# it honest as the tree changes.
# `PreToolUse` was added here by ai-bridge-v5/task-006, in the same commit as the root
# `CLAUDE.md` mention that justifies it (invariant 19, the destructive-action baseline) —
# which is the only way an entry may be added. It is a Claude Code hook EVENT, not a tool,
# and no other rule classifies it. Guard C below fails if that mention is ever removed.
# `UserPromptSubmit` joined them in ai-bridge-v2/task-013, in the same commit as the
# `plugin/README.md` mention that justifies it: `push-state.sh` became a PLUGIN hook, so
# the plugin's own hook table names its event beside `SessionStart` and `PreToolUse`. It
# had zero mentions before that and was correctly absent; it has one now and is correctly
# here. That is the whole mechanism working, in both directions, in one change.
# `Explore` is a harness SUBAGENT TYPE, not a tool: it is dispatched through `Agent`, which
# is already in `VOCAB` and checked. Added with the mentions that justify it —
# `seed/CONVENTIONS.md`'s broad-read rule and `skills/fanout/SKILL.md`.
# `SubagentStop` joined them in ai-bridge-v3/task-003 on exactly the `UserPromptSubmit`
# precedent above: `agent-control.sh` is now registered on that event as well, so
# `plugin/README.md` names it. It had zero mentions before and was correctly a mutant in
# the un-earned group below; it has one now and is correctly here.
# `SubagentStart` joined them in ai-bridge-v3/task-039 on the same precedent again: the
# wall-clock cap needs an exact start time, so `agent-control.sh` is registered on that
# event too and `plugin/README.md` names it.
NOT_A_TOOL='SessionStart|PreToolUse|UserPromptSubmit|SubagentStart|SubagentStop|WorktreeCreate|WorktreeRemove|Makefile|Explore'

# Rule 2, DERIVED: OKF's document types, from the schema that defines them. `seed/SCHEMA.md`
# writes each as a `## type: <Name>` heading, so the registry is machine-readable and a new
# type classifies itself. An empty result would un-classify 43 mentions at once, so it is
# asserted below rather than trusted.
OKF_TYPE_SRC="$REPO/plugin/seed/SCHEMA.md"
OKF_TYPES="$(grep -oE '^#+[[:space:]]+type:[[:space:]]+[A-Za-z]+' "$OKF_TYPE_SRC" 2>/dev/null \
  | awk '{print $NF}' | sort -u | paste -sd'|' - )"
[ -n "$OKF_TYPES" ] || OKF_TYPES='__no_okf_types_derived__'

# Rule 3, a SHAPE: all capitals and no lowercase letter. No harness tool is named this way.
SCREAMING_RE='[A-Z][A-Z0-9_]*'
# Every backticked identifier that starts with a capital is a CANDIDATE for classification —
# single-word included, which is the widening this file was re-dispatched for.
CAND_RE='`[A-Z][A-Za-z0-9_]*`'

# ------------------------------------------------------------------ the primitives
body() { # <file> — everything after the closing frontmatter delimiter
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {fm=2; next} fm!=1 {print}' "$1"
}

tools_of() { # <file> — the tools: values, one per line; empty output means "no key"
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit} fm==1 && /^tools:[[:space:]]*/ {
         sub(/^tools:[[:space:]]*/, ""); gsub(/,/, "\n"); print }' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

has_tools_key() { # <file>
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit} fm==1 && /^tools:/ {found=1}
       END {print (found ? "yes" : "no")}' "$1"
}

mentions_of() { # <file> — unique backticked tool identifiers in the body
  body "$1" | grep -oE "$MENTION_RE" | tr -d '`' | sort -u
}

mention_lines() { # <file> <tool> — line numbers (of the body) naming <tool>
  body "$1" | grep -nF "\`$2\`" | cut -d: -f1 | paste -sd, - 2>/dev/null
}

mention_count() { # <file> <tool> — how many times the body names <tool>
  body "$1" | grep -oF "\`$2\`" | grep -c .
}

# ------------------------------------------------------- the lexicon's two classifiers
in_vocab() { # <name> — is this a harness tool name? (echoes yes/no)
  grep -qxE <<<"$1" "$VOCAB" && echo yes || echo no
}

unclassified_names() { # <file> — backticked capitalised names no rule classifies
  # The four rules, in order: a harness tool, an OKF document type (derived), a SCREAMING
  # literal (shape), the residual list. `VOCAB` is applied FIRST so a name that is both a
  # tool and an OKF type — `Agent` — stays a tool and stays checked against the allowlist.
  body "$1" | grep -oE "$CAND_RE" | tr -d '`' | sort -u \
    | grep -vxE "$VOCAB" \
    | grep -vxE "$OKF_TYPES" \
    | grep -vxE "$SCREAMING_RE" \
    | grep -vxE "$NOT_A_TOOL"
}

# GUARD C's primitive. `NOT_A_TOOL_TREE` is wider than the audited agent+shared-doc set on
# purpose: the machinery this residue documents (hook events, build files) is named all over
# `.claude/rules/` and slash commands that the possession audit never opens, and a name
# earning its keep there is just as real as one earning it in an audited file. Scoped to
# `symlink/`, `.claude/` and `CLAUDE.md` — not `docs/` — to match the measurement this guard
# is pinned to; scoped to `*.md` because that is where a backticked identifier means
# anything here.
# `$REPO/plugin` is in this list because the eight role agents live there: the name swap
# retired `symlink/.claude/agents/`, and a tree that stops at `symlink/` stops seeing every
# backticked mention the agents themselves make — Guard C then declares an entry dead that
# is named ten lines into `software-engineer.md`.
# `symlink/` is gone (ai-bridge-v2/task-013): the machinery moved into `plugin/`, which was
# already scanned, so the set is unchanged in what it covers and one entry shorter.
NOT_A_TOOL_TREE=("$REPO/plugin" "$REPO/.claude" "$REPO/CLAUDE.md")
not_a_tool_uses() { # <name> — count of backticked exact mentions across NOT_A_TOOL_TREE
  # $REPO-anchored, not cwd-relative: this runs the same regardless of where the harness
  # is invoked from, unlike a bare `symlink .claude CLAUDE.md` which resolves against
  # whatever directory the caller happens to be in when it runs `bash tests/*.test.sh`.
  # An ARRAY, expanded quoted — not a space-joined string expanded bare. `$REPO` can
  # contain a space (a common macOS checkout location); unquoted, each path word-splits
  # apart, every lookup silently finds nothing, and Guard C then declares every entry —
  # including the two legitimate ones — dead. Quoting removes the bug rather than just
  # disclosing it.
  grep -rhoE "\`$1\`" --include='*.md' "${NOT_A_TOOL_TREE[@]}" 2>/dev/null | grep -c .
}

dead_not_a_tool_entries() { # <pipe-separated list> — entries with zero real mentions
  local entry
  for entry in $(printf '%s' "$1" | tr '|' ' '); do
    [ "$(not_a_tool_uses "$entry")" -eq 0 ] && printf '%s\n' "$entry"
  done
}

# THE CONDITION THAT DECIDES THE OUTCOME, and the reason this is not a count.
#
# A declaration says "this file names a tool a reader lacks, deliberately". What makes
# that legitimate is never HOW MANY times it does so — it is that the prose STATES THE
# ABSENCE instead of instructing the use. The budget `(N)` cannot see the difference, so
# a reword holding the count constant could swap an honest statement of absence for a
# live instruction and stay green: `tests/` measured the gap and the harness even
# asserted it ("rewording within budget stays green"). The budget is kept — it still
# catches an ADDED mention, which is a different hole — but it is no longer what decides.
#
# So each mention of a declared, unheld tool must SAY SOMETHING ABOUT POSSESSION. The cue
# list below is the presence/absence vocabulary these docs actually use, matched over the
# mention's line and its two neighbours so ordinary reflowing prose does not break it.
# Checked against all ten declared mention sites in the tree, which pass on: "**No role
# agent's allowlist contains `Workflow`**", "you hold neither `Workflow` nor `Agent`",
# "you cannot fan out", "only `qa-reviewer` holds `Agent`", "don't rely on the
# `EnterWorktree` tool", "no restricted role agent holds `Skill`", "the
# `mcp__claude-in-chrome__*` tools are actually present".
#
# `if` IS DELIBERATELY NOT A CUE, and that exclusion is the point of the whole rule: the
# original defect was "dispatch `code-architect` **if it's installed**", a condition on
# INSTALLATION that reads as satisfied while deciding nothing. Accepting `if` would bless
# it. A cue has to be about possession, not about a condition.
#
# A NEGATIVE contraction is spelled out rather than stemmed, and the difference matters:
# a stem of `can` would accept "you **can** author a `Workflow`", which is the instruction
# this rule exists to reject. Only `can't` counts. (Every apostrophe in the scanned set is
# the straight one; the curly form is accepted so a later editor cannot break the check by
# smartening quotes.)
#
# THE CUE ALONE IS NOT ENOUGH, AND THAT WAS REPRODUCED TOO. Requiring a cue is a test of
# ONE HALF of the rule this file states — "states the absence INSTEAD OF instructing the
# use". The second half was never implemented, and a review of #19 defeated the first half
# 0-for-2 with ordinary prose: `` You can author a `Workflow` for wide work — the
# `Workflow` idiom is available for every one of you and is deliberately not written here
# as an option — granting it is a standalone decision `` cleared BOTH mentions on
# "available", "not" and "granting" while instructing the reader to do the thing the rule
# forbids. So the condition is now TWO-SIDED: a declared mention must state the absence
# AND must not be governed by a DIRECTIVE. A directive verb is looked for in the five words
# immediately before the mention, which is where the verb that governs a name sits
# ("**use** the `X` tool", "**author** a `X` fan-out", "escalate **via** `X`"). Two words
# further out is already a different clause: `CONVENTIONS.md` writes "Hold `Agent`? —
# `qa-reviewer` does — dispatch `code-architect`", where the directive verb governs an
# AGENT NAME, not the tool, and must not fire.
#
# A NEGATED directive is not a directive, and this is load-bearing rather than a nicety:
# "don't rely on the `EnterWorktree` tool", "You cannot invoke this yourself", "you can't
# author a `Workflow`" are all correct statements of absence that happen to name the verb.
# So a negator anywhere in the same five-word window disarms the directive.
#
# TWO CUES WERE DELETED FROM THE LIST ON THE SAME EVIDENCE, and the deletions are as much
# of the fix as the addition. `[Oo]nly` masked one of the two mentions in #19's own
# mutation run (a NEIGHBOURING line's "only ... can fan out" vouched for the target line),
# and `[Aa]vailable` cleared one of the two in the review's counter-example above. Neither
# is a statement about possession — "only" is a scoping word and "available" is what the
# original installation-conditioned defect would have said — and neither is needed by any
# of the eleven real declared mentions: the two sites that read "Only `qa-reviewer` holds
# `Agent`" and "may be unavailable" are carried by `holds` and `unavailable`, which are
# about possession. Measured before deleting: the scanned set stays at zero violations.
#
# RESIDUAL GAP, stated honestly and measured rather than argued: this is still a lexical
# test, so a mention that carries a possession cue and is NOT governed by any of the
# directive verbs below can still read as an instruction — `` a `Workflow` fan-out is the
# route for wide work, since nothing else is granted `` is not caught. The gap is in the
# verb list, whose omissions are silent, so it is a DENY list on top of a requirement, not
# the thing that decides on its own: a reword must get past BOTH halves. Criterion 2 of the
# task was narrowed to exactly this promise rather than left claiming more. Per-mention
# markers were rejected upstream as too brittle for reflowing prose.
ABSENCE_CUE='(^|[^a-z])([Nn]o|[Nn]ot|[Nn]one|[Nn]ever|[Nn]either|[Nn]or|[Cc]annot|[Cc]an['"'"'’]t|[Dd]on['"'"'’]t|[Dd]oesn['"'"'’]t|[Ww]on['"'"'’]t|[Ii]sn['"'"'’]t|[Aa]ren['"'"'’]t|[Hh]old|[Hh]olds|[Hh]olding|[Ll]ack|[Ll]acks|[Ll]acking|[Aa]bsent|[Aa]bsence|[Ww]ithout|[Uu]navailable|[Mm]issing|[Dd]ead|[Uu]nexecutable|[Pp]resent|[Gg]rant|[Gg]ranted|[Gg]ranting|allowlist)([^a-z]|$)'

# The verbs that turn a name into an instruction to USE it. Kept to verbs of invocation —
# `add`, `rely`, `inject`, `hold` and `name` are deliberately absent, because the real tree
# uses every one of them while stating an absence.
DIRECTIVE_CUE='(^|[^a-z])([Uu]se|[Uu]ses|[Uu]sing|[Cc]all|[Cc]alls|[Cc]alling|[Ii]nvoke|[Ii]nvokes|[Ii]nvoking|[Aa]uthor|[Aa]uthors|[Aa]uthoring|[Rr]un|[Rr]uns|[Rr]unning|[Ss]pawn|[Ss]pawns|[Ss]pawning|[Dd]ispatch|[Dd]ispatches|[Dd]ispatching|[Tt]rigger|[Tt]riggers|[Ff]ire|[Ff]ires|[Rr]each|[Pp]refer|[Pp]refers|[Ww]ield|via|with|through)([^a-z]|$)'
NEGATOR='(^|[^a-z])([Nn]o|[Nn]ot|[Nn]ever|[Nn]either|[Nn]or|[Cc]annot|[Cc]an['"'"'’]t|[Dd]on['"'"'’]t|[Dd]oesn['"'"'’]t|[Ww]on['"'"'’]t|[Ww]ithout)([^a-z]|$)'

last_words() { # <text> — the last five whitespace-separated words, punctuation intact
  printf '%s' "$1" | tr -s '[:space:]' ' ' \
    | awk '{s=""; for (i=(NF-4>1?NF-4:1); i<=NF; i++) s=s" "$i; print s}'
}

mention_faults() { # <file> <tool> — "<body-line> SILENT|DIRECTIVE" per failing mention
  # The declaration's own reason is blanked (not removed — line numbers must still line up
  # with the other reports), because a cue written inside the waiver would let the waiver
  # vouch for itself. The absence has to be stated in the PROSE a reader reads.
  local file="$1" tool="$2" m n lo prev cur pre seg win
  m="\`$tool\`"
  body "$file" | sed -E 's/<!--[[:space:]]*tool-mention:[^>]*-->//' > "$TMP/mwa.body"
  grep -nF "$m" "$TMP/mwa.body" | cut -d: -f1 | while IFS= read -r n; do
    lo=$(( n > 1 ? n - 1 : 1 ))
    if ! grep -qE "$ABSENCE_CUE" <<<"$(sed -n "${lo},$(( n + 1 ))p" "$TMP/mwa.body" | tr '\n' ' ')"; then
      printf '%s SILENT\n' "$n"; continue
    fi
    # Every occurrence on the line, not just the first: the counter-example that defeated
    # the cue-only rule put two mentions of the same tool on ONE line.
    prev=""; [ "$n" -gt 1 ] && prev="$(sed -n "$((n-1))p" "$TMP/mwa.body") "
    pre="$prev"; cur="$(sed -n "${n}p" "$TMP/mwa.body")"
    while [ "$cur" != "${cur#*"$m"}" ]; do
      seg="${cur%%"$m"*}"
      win="$(last_words "$pre$seg")"
      if grep -qE "$DIRECTIVE_CUE" <<<"$win" \
         && ! grep -qE "$NEGATOR" <<<"$win"; then
        printf '%s DIRECTIVE\n' "$n"; break
      fi
      pre="$pre$seg$m"; cur="${cur#*"$m"}"
    done
  done
}

# A declaration is `<!-- tool-mention: <Tool>(<N>), ... — <reason> -->`, where N is how
# many mentions of that tool the file is declaring. Parse it ONCE, here, and emit
# `ok|<names>` or `bad|<names>` so "which tools are declared" and "is this malformed" can
# never disagree. The separator before the reason is an em-dash or a spaced hyphen.
#
# THE BUDGET `(N)` IS WHAT KEEPS A DECLARATION FROM BECOMING A BLANKET WAIVER, and it
# exists because the first version of this check was measurably too weak: with a bare
# `<!-- tool-mention: Agent -->` on `CONVENTIONS.md`, re-introducing the exact defect this
# whole file was written for ("dispatch code-architect ... using the `Agent` tool") still
# passed. Pinning the count means a NEW mention of an already-declared tool fails until
# someone folds it into the reason deliberately. A declaration with no reason, or with a
# name carrying no `(N)`, is not a declaration and exempts nothing.
parse_declarations() { # <file>
  grep -oE '<!--[[:space:]]*tool-mention:[^>]*-->' "$1" 2>/dev/null | while IFS= read -r d; do
    inner="$(printf '%s' "$d" | sed -E 's/^<!--[[:space:]]*tool-mention:[[:space:]]*//; s/[[:space:]]*-->[[:space:]]*$//')"
    case "$inner" in
      *—*|*" - "*) names="$(printf '%s' "$inner" | sed -E 's/(—| - ).*$//')"
                   reason="$(printf '%s' "$inner" | sed -E 's/^[^—]*—//; s/^.* - //' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" ;;
      *)           names="$inner"; reason="" ;;
    esac
    # Every name must carry a `(N)` budget, or the whole declaration is malformed.
    budgeted=yes
    for n in $(printf '%s' "$names" | tr ',' ' '); do
      case "$n" in *\(*\)) ;; *) budgeted=no ;; esac
    done
    if [ -n "$reason" ] && [ "$budgeted" = yes ]; then printf 'ok|%s\n' "$names"
    else printf 'bad|%s\n' "$names"; fi
  done
}

declared_of() { # <file> — tool names from well-formed declarations, one per line
  parse_declarations "$1" | grep '^ok|' | cut -d'|' -f2- \
    | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -E 's/\([0-9]+\)$//' | grep -v '^$' | sort -u
}

declared_budget() { # <file> <tool> — the N this file declared for <tool> (0 if none)
  parse_declarations "$1" | grep '^ok|' | cut -d'|' -f2- | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk -v t="$2" 'index($0, t"(") == 1 { sub(/^.*\(/, ""); sub(/\).*$/, ""); s+=$0 } END {print s+0}'
}

malformed_declarations() { # <file> — count of declarations with no reason or no budget
  parse_declarations "$1" | grep -c '^bad|'
}

covered() { # <tool> <allowlist-file> — is <tool> granted? honors a trailing `*`
  local tool="$1" entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      *\*) case "$tool" in "${entry%\*}"*) return 0 ;; esac ;;
      *)   [ "$tool" = "$entry" ] && return 0 ;;
    esac
  done < "$2"
  return 1
}

# audit <file> <allowlist-file> <label> — echoes counts as "violations declared stale
# redundant" and APPENDS its findings to the file named by $FINDINGS. It runs inside a
# command substitution, so a shell variable would be discarded with the subshell; a file
# is the only channel that survives, and a lost finding would make the count unreadable.
# A budget mismatch counts as a VIOLATION, not a separate class: an extra undeclared
# mention is the defect this file exists to catch, however it got there.
FINDINGS=""
note() { [ -n "$FINDINGS" ] && printf '%s\n' "$1" >> "$FINDINGS"; }
audit() {
  local file="$1" allow="$2" label="$3"
  local v=0 d=0 s=0 r=0 tool budget actual faults silent directive unknown
  local -a mentioned=() declared=()
  while IFS= read -r tool; do [ -n "$tool" ] && mentioned+=("$tool"); done < <(mentions_of "$file")
  while IFS= read -r tool; do [ -n "$tool" ] && declared+=("$tool"); done < <(declared_of "$file")

  for tool in "${mentioned[@]-}"; do
    [ -n "$tool" ] || continue
    covered "$tool" "$allow" && continue
    if grep -qxF "$tool" <<<"$(printf '%s\n' "${declared[@]-}")"; then
      d=$((d+1))
      budget="$(declared_budget "$file" "$tool")"
      actual="$(mention_count "$file" "$tool")"
      if [ "$actual" != "$budget" ]; then
        v=$((v+1))
        note "        OVER BUDGET  ${label} names \`${tool}\` ${actual}x (body line(s) $(mention_lines "$file" "$tool")) but declares ${budget} — fold the new mention into the reason, or make it executable"
      fi
      # The deciding condition, not the count, and TWO-SIDED: a declared mention has to
      # state the absence AND must not read as an instruction to use the tool. A reword
      # that keeps `budget` intact but turns the sentence back into a directive fails
      # here, which is the hole the budget alone could not see — and the second half is
      # what a cue-only rule could be talked past with ordinary prose.
      faults="$(mention_faults "$file" "$tool")"
      silent="$(printf '%s\n' "$faults" | awk '$2=="SILENT" {print $1}' | paste -sd, - 2>/dev/null)"
      if [ -n "$silent" ]; then
        v=$((v+1))
        note "        NOT AN ABSENCE ${label} names \`${tool}\` at body line(s) ${silent} without saying anywhere near it that a reader may not hold it — a declaration covers a STATEMENT of absence, never an instruction to use the tool"
      fi
      directive="$(printf '%s\n' "$faults" | awk '$2=="DIRECTIVE" {print $1}' | paste -sd, - 2>/dev/null)"
      if [ -n "$directive" ]; then
        v=$((v+1))
        note "        AN INSTRUCTION ${label} names \`${tool}\` at body line(s) ${directive} governed by a verb that TELLS THE READER TO USE IT — a possession cue nearby does not make an instruction a statement of absence; rewrite it as the absence plus the route to take instead"
      fi
    else
      v=$((v+1))
      note "        UNAVAILABLE  ${label} names \`${tool}\` (body line(s) $(mention_lines "$file" "$tool")) — not in the allowlist, not declared"
    fi
  done
  for tool in "${declared[@]-}"; do
    [ -n "$tool" ] || continue
    if covered "$tool" "$allow"; then
      r=$((r+1))
      note "        REDUNDANT    ${label} declares \`${tool}\`, which IS in its allowlist"
    elif ! grep -qxF "$tool" <<<"$(printf '%s\n' "${mentioned[@]-}")"; then
      s=$((s+1))
      note "        STALE        ${label} declares \`${tool}\`, which it no longer names"
    fi
  done
  # GUARD B. A backticked capitalised name — single word included — that no classification
  # rule below recognises is not "prose that happens to look like a tool": it is a name
  # nobody has classified, and the closed list's whole failure mode was treating that case
  # as silence.
  while IFS= read -r unknown; do
    [ -n "$unknown" ] || continue
    v=$((v+1))
    note "        UNCLASSIFIED ${label} names \`${unknown}\` (body line(s) $(mention_lines "$file" "$unknown")) — no classification rule recognises it. Add it to VOCAB if it is a harness tool; if it is not, it should already be an OKF type in seed/SCHEMA.md or a SCREAMING literal, and otherwise add it to NOT_A_TOOL. Do not leave it unclassified: silence here is what let AskUserQuestion, Artifact and a hallucinated single-word \`Deploy\` through"
  done < <(unclassified_names "$file")
  echo "$v $d $s $r"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolallow.XXXXXX")" || {
  echo "agent-tool-allowlist.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
FINDINGS="$TMP/findings"; : > "$FINDINGS"

# ============================================================ 1. the shipped agents
AGENTS="$(find "$REPO/plugin/agents" -maxdepth 1 -type f -name '*.md' | sort)"
ok "shipped agent files found" "$([ -n "$AGENTS" ] && echo yes || echo no)" yes

# GUARD A. The `tools:` lists are the single maintained source the lexicon is pinned to:
# a harness tool becomes real HERE the moment an agent is granted it, so a granted name
# the lexicon does not know is a tool nobody told this file about. It is the guard that
# closes the closed list from the side nobody can see — had it existed, `Artifact` would
# have failed on the commit that granted it to `project-manager`, instead of being noticed
# later by a reviewer reading prose.
UNKNOWN_GRANTS=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    # A grant may be scoped — `Bash(git:*)` is the same tool as `Bash`, and failing on the
    # scope would be a spurious build break rather than a missing lexicon entry.
    t="${t%%(*}"
    if [ "$(in_vocab "$t")" = no ]; then
      UNKNOWN_GRANTS=$((UNKNOWN_GRANTS+1))
      printf '        GRANTED, UNKNOWN  %s grants `%s`, absent from VOCAB — add it, or this file cannot see a mention of it\n' "${f#$REPO/}" "$t"
    fi
  done < <(tools_of "$f")
done <<EOF
$AGENTS
EOF
ok "every granted tool is in the lexicon" "$UNKNOWN_GRANTS" 0

# GUARD C. The residual `NOT_A_TOOL` list is the one route rules 1-3 cannot pin from a
# derivation or a shape, so it is pinned from USE instead: an entry with zero real
# backticked mentions anywhere in the machinery it documents is dead configuration that
# classifies nothing, and is exactly as silent as the closed `VOCAB` this file replaced.
# This is the guard that would have caught the un-earned hook-event pre-population before
# any reviewer had to reproduce it by hand.
DEAD_NOT_A_TOOL="$(dead_not_a_tool_entries "$NOT_A_TOOL")"
if [ -n "$DEAD_NOT_A_TOOL" ]; then
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    printf '        DEAD NOT_A_TOOL ENTRY  `%s` has zero backticked mentions in symlink/, .claude/ or CLAUDE.md — delete it, or add it in the same commit as the mention that justifies it\n' "$entry"
  done <<<"$DEAD_NOT_A_TOOL"
fi
ok "every NOT_A_TOOL entry is justified by a real mention" "$([ -z "$DEAD_NOT_A_TOOL" ] && echo yes || echo no)" yes

V=0; D=0; S=0; R=0; SCANNED=0; SKIPPED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#$REPO/}"
  if [ "$(has_tools_key "$f")" = no ]; then SKIPPED=$((SKIPPED+1)); continue; fi
  tools_of "$f" > "$TMP/allow"
  read -r v d s r <<<"$(audit "$f" "$TMP/allow" "$rel")"
  V=$((V+v)); D=$((D+d)); S=$((S+s)); R=$((R+r)); SCANNED=$((SCANNED+1))
  M=$(( $(malformed_declarations "$f") ))
  if [ "$M" -gt 0 ]; then
    note "        NO REASON    ${rel} has ${M} tool-mention declaration(s) without a reason"
    V=$((V+M))
  fi
done <<EOF
$AGENTS
EOF
ok "every shipped agent declares tools:" "$SKIPPED" 0
ok "shipped agents scanned"              "$([ "$SCANNED" -ge 7 ] && echo yes || echo no)" yes

# =============================================== 2. the shared docs an agent is told to read
# DERIVED, NOT LISTED. Two paths used to be hardcoded here, and a hardcoded list can only
# check what someone remembered to add — `seed/SCHEMA.md` named a browser MCP tool to
# five readers who mostly cannot hold it, and was simply not looked at. So the set is the
# `*.md` references in the restricted agents' own bodies, resolved against the trees this
# repo ships. Adding a doc reference to an agent puts that doc in scope by itself, which
# is the same self-tightening property the reader derivation below already had.
doc_refs_of() { # <agent-file> — every `*.md` reference in its body, normalised
  # `${CLAUDE_PLUGIN_ROOT}/seed/` is stripped FIRST: the braces fall outside the character
  # class below, so an unstripped reference would surface as `seed/CONVENTIONS.md` and
  # resolve against nothing — the shared doc every agent reads, silently out of scope.
  body "$1" | sed 's#\${CLAUDE_PLUGIN_ROOT}/seed/##g' \
    | grep -oE '[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.md' \
    | sed -E 's#^(\.\./)+##; s#^/+##' | sort -u
}

resolve_doc() { # <reference> — repo-relative path of the shipped doc, or nothing
  local ref="$1" cand
  # `plugin/seed/` is where the seed lives since task-022; `symlink/` is the retired tree,
  # kept ahead of it so an agent reference that named a machinery doc still resolves the
  # way it always did on a checkout that still has one.
  for cand in "symlink/$ref" "plugin/seed/$ref"; do
    # An agent file is audited against its OWN allowlist in §1, never as a shared doc, and
    # a slash command is run by the main session, which holds every tool and so cannot
    # have this defect. Both are skipped by path rather than by name.
    case "$cand" in plugin/agents/*|symlink/.claude/agents/*|symlink/.claude/commands/*) continue ;; esac
    [ -f "$REPO/$cand" ] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}

shared_docs() { # — every shipped doc a restricted agent is told to read
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(has_tools_key "$f")" = yes ] || continue
    while IFS= read -r ref; do
      [ -n "$ref" ] && resolve_doc "$ref"
    done < <(doc_refs_of "$f")
  done <<EOF
$AGENTS
EOF
}

readers_of() { # <shared-doc-relpath> — agent files that read it
  # `seed/CLAUDE.md` is the instance-wide contract: it is loaded into EVERY session
  # whether or not an agent body names it, so every restricted agent is a reader and the
  # intersection must not be widened by deriving a smaller set. Every other doc is read by
  # exactly the agents that point at it.
  local doc="$1" f ref
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(has_tools_key "$f")" = yes ] || continue
    if [ "$doc" = plugin/seed/CLAUDE.md ]; then printf '%s\n' "$f"; continue; fi
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      [ "$(resolve_doc "$ref")" = "$doc" ] && { printf '%s\n' "$f"; break; }
    done < <(doc_refs_of "$f")
  done <<EOF
$AGENTS
EOF
}

intersect_tools() { # <agent-file>... — the tools EVERY reader holds, one per line
  local first=1 f
  : > "$TMP/isect"
  for f in "$@"; do
    tools_of "$f" > "$TMP/one"
    if [ "$first" = 1 ]; then cp "$TMP/one" "$TMP/isect"; first=0
    else comm -12 <(sort "$TMP/isect") <(sort "$TMP/one") > "$TMP/isect.new"; mv "$TMP/isect.new" "$TMP/isect"; fi
  done
  cat "$TMP/isect"
}

SHARED_DOCS="$(shared_docs | sort -u)"
SHARED_SCANNED=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  f="$REPO/$rel"
  [ -f "$f" ] || { note "        MISSING      ${rel} not found"; V=$((V+1)); continue; }
  readers=(); while IFS= read -r r; do [ -n "$r" ] && readers+=("$r"); done < <(readers_of "$rel")
  if [ "${#readers[@]}" -eq 0 ]; then
    note "        NO READERS   ${rel} has no derived reader — the derivation broke"
    V=$((V+1)); continue
  fi
  intersect_tools "${readers[@]}" > "$TMP/allow.shared"
  read -r v d s r <<<"$(audit "$f" "$TMP/allow.shared" "$rel [∩ of ${#readers[@]} readers]")"
  V=$((V+v)); D=$((D+d)); S=$((S+s)); R=$((R+r)); SHARED_SCANNED=$((SHARED_SCANNED+1))
  M=$(( $(malformed_declarations "$f") ))
  if [ "$M" -gt 0 ]; then
    note "        NO REASON    ${rel} has ${M} tool-mention declaration(s) without a reason"
    V=$((V+M))
  fi
done <<EOF
$SHARED_DOCS
EOF
ok "shared docs scanned" "$([ "$SHARED_SCANNED" -ge 5 ] && echo yes || echo no)" yes

# The DERIVATION is the check here, so name the docs it must reach. The first two are what
# the hardcoded list used to hold; `seed/SCHEMA.md` is the one it missed, and naming it
# means a derivation that silently narrows back to the old pair fails instead of passing.
for must in plugin/seed/CONVENTIONS.md plugin/seed/CLAUDE.md plugin/seed/SCHEMA.md; do
  ok "derived set reaches $must" "$(printf '%s\n' "$SHARED_DOCS" | grep -cxF "$must")" 1
done

# The reader derivation must find the real set, or the intersection is meaningless.
CONV_READERS="$(readers_of plugin/seed/CONVENTIONS.md | wc -l | tr -d ' ')"
ok "CONVENTIONS.md readers derived"  "$([ "$CONV_READERS" -ge 3 ] && echo yes || echo no)" yes
SCHEMA_READERS="$(readers_of plugin/seed/SCHEMA.md | wc -l | tr -d ' ')"
ok "SCHEMA.md readers derived"       "$([ "$SCHEMA_READERS" -ge 3 ] && echo yes || echo no)" yes

[ -s "$FINDINGS" ] && cat "$FINDINGS"
ok "no unavailable tool named"        "$V" 0
ok "no stale tool-mention"            "$S" 0
ok "no redundant tool-mention"        "$R" 0

# ================================================ 3. rung 2 still holds (the skip is safe)
# The shared review agents must keep declaring NO `tools:` key — that is what makes
# skill- and workflow-shaped capability reachable BY DISPATCH without widening any
# restricted allowlist (knowledge/findings/role-agents-cannot-invoke-skills.md, rung 2).
UNRESTRICTED="$(find "$REPO/config" -type f -path '*/agents/*.md' | sort)"
ok "shared review agents found" "$([ -n "$UNRESTRICTED" ] && echo yes || echo no)" yes
restricted=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ "$(has_tools_key "$f")" = yes ]; then
    restricted=$((restricted+1)); printf '        NOW RESTRICTED %s grew a tools: key — it is no longer unconstrained\n' "${f#$REPO/}"
  fi
done <<EOF
$UNRESTRICTED
EOF
ok "shared review agents stay unrestricted" "$restricted" 0

# ==================================================== 4. non-vacuity: the checker bites
# Every case runs against synthetic fixtures under mktemp. A checker that only passes on
# good input would pass here too, so each guard is paired with the input it must reject.
FX="$TMP/fx"; mkdir -p "$FX"

fixture() { # <name> <tools-line-or-empty> <body>
  { printf -- '---\nname: %s\n' "$1"
    [ -n "$2" ] && printf 'tools: %s\n' "$2"
    printf -- '---\n%s\n' "$3"; } > "$FX/$1.md"
}
run_fx() { # <name> — echoes "violations declared stale redundant"
  : > "$FINDINGS"; tools_of "$FX/$1.md" > "$TMP/allow"; audit "$FX/$1.md" "$TMP/allow" "fx/$1"
}

# 4a. an undeclared mention of an absent tool is a violation.
fixture bad 'Read, Grep' 'For wide work, author a `Workflow` fan-out.'
read -r v d s r <<<"$(run_fx bad)"
ok "checker flags an absent tool"            "$v" 1

# 4b. the four prose words that fooled the first manual sweep must stay green — and so
# must a BACKTICKED `Task`, which is an OKF document type in this bundle, not a tool.
fixture prose 'Read, Grep' 'Never write to the bundle. The agent roster lists each agent.
Keep the workflow structure. Read the task document first, then edit the task file.
A skill is not a tool here; bash it out if you must.
Set the `Task` frontmatter, per the `Task` type in `SCHEMA.md`.'
read -r v d s r <<<"$(run_fx prose)"
ok "checker ignores prose (write/agent/workflow/task)" "$v" 0
ok "checker ignores the OKF \`Task\` type"     "$(printf '%s\n' "$(mentions_of "$FX/prose.md")" | grep -c '^Task$')" 0

# 4c. a backticked tool the agent DOES hold is green — the rule is possession, not the word.
fixture granted 'Read, Grep, Bash' 'Use `Bash` and `Read`; never `Grep` a whole repo blindly.'
read -r v d s r <<<"$(run_fx granted)"
ok "checker allows a granted tool"           "$v" 0

# 4d. a declaration with a reason AND a matching budget exempts the mention.
fixture declared 'Read, Grep' '<!-- tool-mention: Workflow(1) — named to record that it is absent; the route is sequential -->
You hold no `Workflow`, so wide work is sequential.'
read -r v d s r <<<"$(run_fx declared)"
ok "declaration exempts the mention"         "$v" 0
ok "declaration is counted"                  "$d" 1
ok "budget is parsed"                        "$(declared_budget "$FX/declared.md" Workflow)" 1

# 4e. THE BUDGET IS THE TEETH: one more mention than declared fails, so a declaration can
# never become a blanket waiver for the next author. This is the case the first version of
# this check got wrong — it passed while the original defect was re-introduced verbatim.
fixture overbudget 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
You hold no `Workflow`. But for wide work, author a `Workflow` fan-out anyway.'
read -r v d s r <<<"$(run_fx overbudget)"
# TWO violations, and both are the point: the budget catches the added MENTION, and the
# directive rule catches what that mention SAYS. They are separable, which the next fixture
# proves — an added mention that honestly states the absence trips the budget alone, so a
# failure here can never be mistaken for the budget having gone quiet.
ok "an extra mention breaks the budget"      "$v" 2
ok "...and is still counted as declared"     "$d" 1
fixture overbudget_honest 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
You hold no `Workflow`. A second mention of `Workflow` was added later, which still says
no reader holds it, and nobody updated the count to match.'
read -r v d s r <<<"$(run_fx overbudget_honest)"
ok "the budget alone catches an added mention" "$v" 1
# 4e-bis. THE BUDGET IS NOT WHAT DECIDES, and this pair is the proof. Both fixtures
# declare `Workflow(1)` and both name it exactly once, so the count cannot separate them —
# and the count is precisely what a reword holds constant. What separates them is whether
# the prose STATES THE ABSENCE or ISSUES AN INSTRUCTION, so that is what is asserted.
fixture reworded_absence 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
Prose rewritten from scratch: fanning out is not open to you, since no role agent
is granted `Workflow`. Work through the edges in sequence and say so in the PR body.'
read -r v d s r <<<"$(run_fx reworded_absence)"
ok "reword that still states the absence is green" "$v" 0
ok "...and its count is unchanged"            "$(mention_count "$FX/reworded_absence.md" Workflow)" 1
# The same file, same declaration, SAME COUNT — reworded into an instruction. This is the
# mutation the reported gap was about, and it must fail.
fixture reworded_directive 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
Prose rewritten from scratch: for wide, independent work, author a `Workflow` fan-out
and let each subagent take one edge, then synthesize the results yourself.'
read -r v d s r <<<"$(run_fx reworded_directive)"
ok "reword into an instruction fails"        "$v" 1
ok "...on the same count as the green one"   "$(mention_count "$FX/reworded_directive.md" Workflow)" 1
ok "...and its budget still matches"         "$(declared_budget "$FX/reworded_directive.md" Workflow)" 1
# And the verbatim original defect — a condition on INSTALLATION, which reads as satisfied
# and decides nothing — is rejected too, which is why `if` is not an absence cue.
fixture reworded_installed 'Read, Grep' '<!-- tool-mention: Agent(1) — one mention, deliberately -->
Self-review your diff: dispatch `code-architect` with the `Agent` tool if it is installed
in the usual location, else do a careful pass yourself.'
read -r v d s r <<<"$(run_fx reworded_installed)"
ok "the installation-conditioned defect fails" "$v" 1
# A cue has to be NEGATIVE. "you can" is a permission, so it must not clear the mention,
# while "you can't" must — the pair that decides whether the cue list is stemmed or spelt
# out, and a stemmed `can` accepts the exact instruction the rule exists to reject.
fixture reworded_can 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
For wide work you can author a `Workflow` fan-out and split the edges between subagents.'
read -r v d s r <<<"$(run_fx reworded_can)"
ok "a permission is not an absence"          "$v" 1
fixture reworded_cant 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
For wide work you can'"'"'t author a `Workflow` fan-out, so take the edges in sequence.'
read -r v d s r <<<"$(run_fx reworded_cant)"
ok "...but its negation is"                   "$v" 0

# 4e-ter. THE CUE ALONE WAS NOT ENOUGH, and these are the rewords that proved it — kept as
# fixtures because they are the only evidence that the second half of the rule works. Both
# are same-count rewords of the same declared mention, both carry possession cues ("not",
# "granting", "available", "granted"), and both instruct the reader to use the tool. The
# cue-only version of this check passed all three.
#
# (i) VERBATIM from the QA review of ai-bridge#19: two mentions on ONE line, which is also
# why the directive test walks every occurrence of a line rather than only the first.
fixture reworded_review 'Read, Grep' '<!-- tool-mention: Workflow(2) — two mentions, deliberately -->
You can author a `Workflow` for wide work — the `Workflow` idiom is available for every one of you and is deliberately not written here as an option — granting it is a standalone decision.'
read -r v d s r <<<"$(run_fx reworded_review)"
ok "the QA review 0-for-2 counter-example fails" "$v" 1
ok "...on the count it declared"              "$(mention_count "$FX/reworded_review.md" Workflow)" 2
ok "...with its budget intact"                "$(declared_budget "$FX/reworded_review.md" Workflow)" 2
# (ii) A DIFFERENT SHAPE: the cue sits on the NEIGHBOURING line and vouches for a directive
# on the target line. This is the masking that let one of two mentions through in #19's own
# mutation run, and deleting `only` from the cue list is half of why it now fails.
fixture reworded_neighbour 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
Fanning out is a standalone decision and only `qa-reviewer` can dispatch anything at all.
For genuinely wide work, use `Workflow` and give each subagent one edge of the change.'
read -r v d s r <<<"$(run_fx reworded_neighbour)"
ok "a cue on the next line no longer vouches"  "$v" 1
# (iii) A THIRD SHAPE: no imperative at all — a bare permission granted in passing, with the
# possession cue in the same clause.
fixture reworded_permission 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
Nothing in your allowlist stops it, so reach for `Workflow` whenever the work is wide.'
read -r v d s r <<<"$(run_fx reworded_permission)"
ok "a passing permission fails too"           "$v" 1
# ...and the guard must stay quiet on the real tree's shapes, which is the whole risk of a
# second rule. A NEGATED directive verb is a statement of absence, not an instruction —
# `CONVENTIONS.md` writes "don't rely on the `EnterWorktree` tool" and `qa-reviewer.md`
# writes "You cannot invoke this yourself"; both must stay green.
fixture negated_directive 'Read, Grep' '<!-- tool-mention: Workflow(1), Agent(1) — two mentions, deliberately -->
Don'"'"'t use `Workflow` for this: you cannot invoke `Agent` either, so work sequentially.'
read -r v d s r <<<"$(run_fx negated_directive)"
ok "a negated directive is still an absence"  "$v" 0
# And a directive verb governing an AGENT NAME two clauses away must not fire — the exact
# shape of `CONVENTIONS.md`'s "Hold `Agent`? — `qa-reviewer` does — dispatch `code-architect`.
fixture distant_verb 'Read, Grep' '<!-- tool-mention: Agent(1) — one mention, deliberately -->
Hold `Agent`? — `qa-reviewer` does — dispatch `code-architect`. Don'"'"'t hold it? Review by hand.'
read -r v d s r <<<"$(run_fx distant_verb)"
ok "a verb governing an agent name is not one" "$v" 0

# 4f. a declaration missing its reason, or missing its budget, is not a declaration.
fixture noreason 'Read, Grep' '<!-- tool-mention: Workflow(1) -->
You hold no `Workflow`.'
read -r v d s r <<<"$(run_fx noreason)"
ok "reasonless declaration does not exempt"  "$v" 1
ok "reasonless declaration is malformed"     "$(malformed_declarations "$FX/noreason.md")" 1
fixture nobudget 'Read, Grep' '<!-- tool-mention: Workflow — a reason, but no count to pin it to -->
You hold no `Workflow`.'
read -r v d s r <<<"$(run_fx nobudget)"
ok "budgetless declaration does not exempt"  "$v" 1
ok "budgetless declaration is malformed"     "$(malformed_declarations "$FX/nobudget.md")" 1

# 4g. a declaration for a tool no longer named is stale; one for a granted tool is redundant.
fixture stale 'Read, Grep' '<!-- tool-mention: Workflow(1) — the instruction it guarded was deleted -->
Nothing here names a tool.'
read -r v d s r <<<"$(run_fx stale)"
ok "checker flags a stale declaration"       "$s" 1
fixture redundant 'Read, Grep, Bash' '<!-- tool-mention: Bash(1) — pointless, Bash is granted -->
Use `Bash`.'
read -r v d s r <<<"$(run_fx redundant)"
ok "checker flags a redundant declaration"   "$r" 1

# 4h. MCP wildcards: a trailing `*` in the allowlist covers the whole prefix, nothing more.
fixture mcpok 'Read, mcp__claude-in-chrome__*' 'Call `mcp__claude-in-chrome__navigate`, then `mcp__claude-in-chrome__*` as needed.'
read -r v d s r <<<"$(run_fx mcpok)"
ok "wildcard covers its prefix"              "$v" 0
fixture mcpbad 'Read, mcp__claude-in-chrome__*' 'Call `mcp__other__thing`.'
read -r v d s r <<<"$(run_fx mcpbad)"
ok "wildcard does not cover another server"  "$v" 1

# 4i. no `tools:` key ⇒ unconstrained ⇒ nothing to flag, however it is phrased.
fixture inherits '' 'Invoke the `Skill` tool and author a `Workflow`.'
ok "no tools: key means no constraint"       "$(has_tools_key "$FX/inherits.md")" no

# 4j. the shared-doc rule: the intersection binds, so one reader lacking a tool is enough.
fixture reader_with_agent    'Agent, Read, Grep' 'x'
fixture reader_without_agent 'Read, Grep'        'x'
printf 'Dispatch `code-architect` with the `Agent` tool.\n' > "$FX/shared.md"
intersect_tools "$FX/reader_with_agent.md" "$FX/reader_without_agent.md" > "$TMP/allow.fx"
ok "intersection drops the unshared tool"    "$(grep -c '^Agent$' "$TMP/allow.fx")" 0
: > "$FINDINGS"; read -r v d s r <<<"$(audit "$FX/shared.md" "$TMP/allow.fx" "fx/shared")"
ok "shared doc flags a tool one reader lacks" "$v" 1
# ...and stays green once every reader holds it.
intersect_tools "$FX/reader_with_agent.md" "$FX/reader_with_agent.md" > "$TMP/allow.fx2"
: > "$FINDINGS"; read -r v d s r <<<"$(audit "$FX/shared.md" "$TMP/allow.fx2" "fx/shared")"
ok "shared doc green when all readers hold it" "$v" 0

# 4k. GUARD A's classifier, on both answers. The tree-wide assertion above reads 0 today,
# which is exactly the shape that cannot tell "nothing to find" from "not looking", so the
# classifier is exercised directly: a real tool is known, an invented one is not, and the
# three names this task was dispatched to close are known now.
ok "lexicon knows an ungranted harness tool" "$(in_vocab Artifact)" yes
ok "lexicon knows the MCP wildcard grant"    "$(in_vocab 'mcp__claude-in-chrome__*')" yes
ok "lexicon rejects an invented tool"        "$(in_vocab SummonDragon)" no
for t in AskUserQuestion ExitWorktree Artifact; do
  ok "lexicon now knows \`$t\`"              "$(in_vocab "$t")" yes
done
# The OKF document type must still NOT be a tool — the collision that keeps `Task` out.
ok "lexicon still rejects the OKF type"      "$(in_vocab Task)" no

# 4l. GUARD B: an unclassified backticked capitalised name FAILS instead of being ignored.
# This is the hole itself — before this guard, `AskUserQuestion` in an agent body produced
# silence, which is indistinguishable from a clean file.
fixture unknowntool 'Read, Grep' 'When you need the human, ask via `AskUserQuestion` and wait.'
read -r v d s r <<<"$(run_fx unknowntool)"
ok "a name missing from the lexicon is not silent" "$([ "$v" -ge 1 ] && echo yes || echo no)" yes
fixture invented 'Read, Grep' 'Escalate by calling `SummonDragon` on the failing job.'
read -r v d s r <<<"$(run_fx invented)"
ok "an unclassified CamelCase name fails"    "$v" 1
ok "...and is reported as unclassified"      "$(unclassified_names "$FX/invented.md")" SummonDragon
# THE SINGLE-WORD CASE, which is why this guard was re-dispatched. `Deploy` is ungranted, so
# Guard A cannot see it, and it was invisible while Guard B fired on multi-word names only.
# This is the injection that was reproduced live against ai-bridge#19's head, now a fixture.
fixture invented_single 'Read, Grep' 'Use the `Deploy` tool to ship the change.'
read -r v d s r <<<"$(run_fx invented_single)"
ok "a single-word invented tool fails"       "$v" 1
ok "...and is reported as unclassified"      "$(unclassified_names "$FX/invented_single.md")" Deploy
ok "...and Guard A cannot see it"            "$(in_vocab Deploy)" no
# ...while every rule that keeps the 61 real non-tool mentions quiet is asserted on both
# answers, because a rule that exempts everything looks identical to a guard that works.
# Both names used here are the two that survive Guard C's use-check (below): `SessionStart`
# and `Makefile`, not the nine hook events that were pre-populated and never earned it.
fixture hookevent 'Read, Grep' 'The `SessionStart` hook injects the queue; the build runs `Makefile` targets.'
read -r v d s r <<<"$(run_fx hookevent)"
ok "a declared non-tool stays quiet"         "$v" 0
# THE FOUR NAMES THE SECOND REVIEW REPRODUCED LIVE AS INVISIBLE. Each was pre-populated in
# `NOT_A_TOOL` with zero real mentions anywhere this file's tree reaches, a silent
# classification route for exactly the shape this guard exists to catch — worse than
# `Deploy` above, because it was never disclosed at all. Guard C's removal of the 9
# un-earned entries is what makes each of these fail here now; before the fix, all four
# were `86 passed, 0 failed`, reproduced live against ai-bridge#19 at `7a9ecb2`.
# `PreToolUse` used to be the fourth name here and has since EARNED its entry (see
# NOT_A_TOOL above), so it would now classify and could no longer prove anything. It is
# replaced by `SessionEnd` — still un-earned — rather than dropped, because the strength
# of this group is the number of distinct shapes it reproduces, not the names it uses.
# `SubagentStop` was the fourth name here until ai-bridge-v3/task-003 earned its entry, the
# same way `PreToolUse` did before it. `SubagentStart` replaced it and earned its own entry
# in ai-bridge-v3/task-039; `PostToolUse` replaces that one, and is still un-earned.
for hallucinated in Notification SessionEnd PreCompact PostToolUse; do
  body="Use the \`${hallucinated}\` tool to alert the team."
  fixture "hallucinated_${hallucinated}" 'Read, Grep' "$body"
  read -r v d s r <<<"$(run_fx "hallucinated_${hallucinated}")"
  ok "un-earned NOT_A_TOOL candidate \`${hallucinated}\` now fails" "$v" 1
  ok "...and is reported as unclassified, not silent" \
    "$(unclassified_names "$FX/hallucinated_${hallucinated}.md")" "$hallucinated"
done
fixture okftypes 'Read, Grep' 'Write a `Finding`, cite a `Service`, link a `Runbook`, name a `Team`.
The verdict prints `APPROVED` or `DISMISSED`; a worktree may be `RECLAIMABLE`.'
read -r v d s r <<<"$(run_fx okftypes)"
ok "OKF types and SCREAMING tokens stay quiet" "$v" 0
# Rule 2 is DERIVED, so assert the derivation, not the effect: the schema's own `type:`
# headings are the registry, and an empty derivation would silently exempt nothing at all
# (61 mentions would fail at once) — which is loud, but the count is worth pinning anyway.
ok "OKF types derive from the schema"        "$([ "$(printf '%s' "$OKF_TYPES" | tr '|' '\n' | grep -c .)" -ge 8 ] && echo yes || echo no)" yes
for t in Task Finding Service Runbook Team Reference Project; do
  ok "derived types include \`$t\`"          "$(printf '%s\n' "$t" | grep -cxE "$OKF_TYPES")" 1
done
# `Agent` is BOTH an OKF type and a tool, and rule 1 has to win or the tool stops being
# checked. This is the one collision in the derivation and it is the load-bearing one.
ok "the derivation also names \`Agent\`"      "$(printf 'Agent\n' | grep -cxE "$OKF_TYPES")" 1
fixture okf_agent 'Read, Grep' 'Dispatch `code-architect` with the `Agent` tool.'
read -r v d s r <<<"$(run_fx okf_agent)"
ok "...but a tool that is also a type is checked" "$v" 1
# Rule 3 is a SHAPE, so assert both sides of it: SCREAMING is exempt, capitalised is not.
ok "a SCREAMING literal is not a tool name"  "$(printf 'RECLAIMABLE\n' | grep -cxE "$SCREAMING_RE")" 1
ok "a capitalised word is not SCREAMING"     "$(printf 'Deploy\n' | grep -cxE "$SCREAMING_RE")" 0
# ...and the fact the shape rests on: no harness tool is written in all capitals, so the
# exemption cannot swallow one. This is the residual gap, asserted so it stays true.
UPPER_TOOLS="$(printf '%s' "$VOCAB" | tr '|' '\n' | grep -cxE "$SCREAMING_RE")"
ok "no tool in VOCAB is all-capitals"        "$UPPER_TOOLS" 0

# Rule 4 (GUARD C) is a USE-CHECK, so assert both answers directly on the primitive, the
# way rule 3's SHAPE was asserted above — the tree-wide "$DEAD_NOT_A_TOOL" result reading
# empty today is exactly the shape that cannot tell "nothing to find" from "not looking".
ok "a real NOT_A_TOOL entry is justified"    "$([ "$(not_a_tool_uses SessionStart)" -ge 1 ] && echo yes || echo no)" yes
ok "the disclosed Makefile entry is justified" "$([ "$(not_a_tool_uses Makefile)" -ge 1 ] && echo yes || echo no)" yes
# ...and an entry with no real mention is caught, on a name invented for this fixture so
# the assertion cannot pass by accident if this name is ever legitimately documented.
ok "an unearned candidate has zero uses"     "$(not_a_tool_uses TotallyFictitiousHookEventNine)" 0
ok "dead_not_a_tool_entries catches it"      "$(dead_not_a_tool_entries 'SessionStart|TotallyFictitiousHookEventNine|Makefile')" TotallyFictitiousHookEventNine
ok "...and stays silent when every entry is earned" "$(dead_not_a_tool_entries "$NOT_A_TOOL")" ""

# ...and NOT_A_TOOL_TREE itself must survive a path containing a space — common on macOS
# checkouts — plus a glob metacharacter for good measure. A bare space-joined string
# expanded unquoted word-splits apart on the space and then glob-expands the `*`, so the
# lookup below would silently see zero mentions and declare a real entry dead; the array
# form, expanded quoted, is what keeps this honest.
SPACED_TREE_DIR="$TMP/spaced dir with * and [glob]"
mkdir -p "$SPACED_TREE_DIR"
printf 'Uses the `SpacedPathFixtureTool` tool.\n' > "$SPACED_TREE_DIR/note.md"
SAVED_NOT_A_TOOL_TREE=("${NOT_A_TOOL_TREE[@]}")
NOT_A_TOOL_TREE=("$SPACED_TREE_DIR")
ok "a NOT_A_TOOL_TREE entry with a space+glob path is still found" \
  "$(not_a_tool_uses SpacedPathFixtureTool)" 1
NOT_A_TOOL_TREE=("${SAVED_NOT_A_TOOL_TREE[@]}")
# The nine names removed from NOT_A_TOOL by this fix are the reproduced proof: each has
# zero real mentions, which is exactly why they were silent before and unclassified now.
# `UserPromptSubmit` LEFT this list in ai-bridge-v2/task-013 and is in NOT_A_TOOL instead:
# `push-state.sh` became a plugin hook, so `plugin/README.md` now names its event. The
# other seven still have zero mentions, and the pair of changes is the check working as
# designed rather than an exception to it.
for unearned in SessionEnd PostToolUse PreCompact InstructionsLoaded Notification; do
  ok "removed entry \`$unearned\` had zero real mentions" "$(not_a_tool_uses "$unearned")" 0
done

# 4m. the DERIVED scanned set: resolution is what decides which files are looked at, so
# assert the resolver rather than only the list it produced.
ok "resolves a shipped doc"                  "$(resolve_doc SCHEMA.md)" plugin/seed/SCHEMA.md
ok "falls through to plugin/seed/ for CLAUDE.md" "$(resolve_doc CLAUDE.md)" plugin/seed/CLAUDE.md
ok "an instance-only doc resolves to nothing" "$(resolve_doc AWAITING.md)" ""
ok "an agent file is never a shared doc"     "$(resolve_doc .claude/agents/qa-reviewer.md)" ""
ok "a slash command is never a shared doc"   "$(resolve_doc .claude/commands/pm-loop.md)" ""
# Agent bodies write `${CLAUDE_PLUGIN_ROOT}/seed/CONVENTIONS.md`, so the reference
# normaliser is load-bearing: without it the file this whole check was built for leaves
# the derived set silently.
ok "the plugin-root reference an agent writes normalises" \
  "$(doc_refs_of "$REPO/plugin/agents/software-engineer.md" | grep -cx 'CONVENTIONS.md')" 1
ok "…and it is the shipped seed copy it resolves to" \
  "$(resolve_doc CONVENTIONS.md)" plugin/seed/CONVENTIONS.md

printf '\n%s passed, %s failed  (%s agent file(s) + %s shared doc(s); %s declared mention(s))\n' \
  "$pass" "$fail" "$SCANNED" "$SHARED_SCANNED" "$D"
[ "$fail" -eq 0 ]
