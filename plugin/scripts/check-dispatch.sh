#!/usr/bin/env bash
#
# check-dispatch.sh — did the dispatch produce the artifact it promised?
#
#   Usage: check-dispatch.sh <task-doc>
#
# Run it whenever a dispatched agent reports — from an `/<plugin>:dispatch` tick or from an ad-hoc
# dispatch in a main session. It reads three things and judges nothing else:
#
#   1. did the task's `status:` advance off `ready`/`in-progress`;
#   2. does its `pr:` name a URL;
#   3. does that pull request actually exist, per the host.
#
# WHY IT EXISTS. On 2026-08-28 two role agents finished their work, committed it — one had
# already pushed — then ended their turns waiting on a background job that nothing was left
# running to notify, and **reported as completed**. No PR was ever opened. Every guard in
# the bundle passed them: the 30-40 minute wall-clock rule (one parked at 16 minutes), the
# two-round review cap (neither reached review), and the completion notification itself,
# which is what they sent. The only thing that would have caught it is the question above,
# and nothing was asking it.
#
# IT IS REPORT-ONLY, AND THAT IS THE LOAD-BEARING PROPERTY. It never re-dispatches, never
# writes to the task document, never touches a branch, and asks the host only to READ.
# `/<plugin>:dispatch` step 2 calls re-dispatching an already-finished task sequence the most
# expensive failure a loop of this shape has — a checker that acted on its own reading
# would reintroduce exactly that, and would do it automatically. The verdict goes to a
# human or to the loop's own reasoning; the recovery is usually one message to the parked
# agent ("open the PR on what you already have"), which is cheap, and anything more is a
# decision somebody makes with the whole picture. Not this script's call.
#
# IT IS ALSO DELIBERATELY DUMBER THAN THE DIAGNOSIS. It does not read the diff, judge the
# work, or decide whether the PR is any good — that is the independent reviewer's job
# (SCHEMA.md → "Independent verification gate"). It answers one question a report cannot be
# trusted to answer about itself.
#
# Exit codes — 0 is the only clearance; every other code wants a human's eyes:
#
#   0  the dispatch produced what it promised (or stopped honestly: `blocked`/`cancelled`)
#   1  PARKED — status still `draft`/`ready`/`in-progress` and no PR. THE signature.
#   2  cannot answer: usage, no such file, unreadable frontmatter, a research task (it has
#      no PR by design — read its `artifacts:`), or `gh` missing/unauthenticated when a
#      recorded URL still had to be resolved. Unknown is never reported as fine.
#   3  the claim is not backed: `pr:` names a pull request the host does not resolve, or
#      names something that is not a URL at all.
#   4  the record contradicts itself: `in-review`/`done` with an empty `pr:` on a task
#      that resolves a `target_repo:` (bundle-only work is due no PR), a PR that
#      resolves while `status:` never moved, or a `blocked` reason naming a tool the
#      assignee's own `tools:` list already grants. Usually one edit away from correct.
#
# WHAT IT IS ASKED ABOUT MATTERS: run it on a task you DISPATCHED, when its agent reports.
# A task nobody has dispatched yet reads as exit 1 too — correctly, in the sense that no PR
# exists, and uselessly, in the sense that none was due. The verdict is about a dispatch,
# not about a document sitting in the queue.
#
# IT READS `session:` BUT NEVER JUDGES BY IT. A task dispatched to a `claude --bg` role
# agent records the session id; on the PARKED verdict this adds one line saying what that
# session is doing. The exit codes are exactly the ones above, with or without the field.
#
# THE PARKED CATCH NEEDS NO NETWORK, on purpose: an unmoved status with an empty `pr:` is
# decided from the document alone, before the host is consulted at all, so an offline
# machine, a missing CLI or a rate limit cannot silence the one verdict this exists for.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to edit per
# instance. It reads no org, repo or path literal.
#
# Verified by tests/check-dispatch.test.sh.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

usage() {
  echo "Usage: $(basename "$0") <task-doc>" >&2
  exit 2
}

case "${1:-}" in -h|--help) usage ;; -*) echo "error: unknown option '$1'" >&2; usage ;; esac
[ "$#" -eq 1 ] || usage
TASK="$1"
[ -f "$TASK" ] || { echo "error: no such task document: $TASK" >&2; exit 2; }

# Print the frontmatter block. Exit 3 when the file does not open with `---`, exit 4 when
# it opens but never closes — the same reader validate-bundle.sh and task-owner.sh use, for
# the same reason: an unterminated block would return the whole file, and a `pr:` line in
# the BODY (prose, a note, a quoted example) would be read as the record.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

fm=""; fm_rc=0
fm="$(fm_block "$TASK")" || fm_rc=$?
[ "$fm_rc" -eq 0 ] || {
  echo "error: $TASK has no readable YAML frontmatter, so what the dispatch was" >&2
  echo "       supposed to produce cannot be read. Refusing rather than guessing." >&2
  exit 2
}

# Only the FIRST occurrence of a key counts. A document with the key repeated would
# otherwise be judged from the LATER value — the bug push-state.sh had with `status:`.
field() { # <key> [frontmatter-block, default the task's]
  printf '%s\n' "${2-$fm}" | awk -v key="$1" '
    !got && index($0, key ":") == 1 {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]*#.*$/, "", v)
      sub(/^["'"'"']/, "", v); sub(/["'"'"']$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

# The `pr:` VALUE, which in real task documents is a flow list (`["url"]`, `[ url ]`,
# `[ "url" ]`, two entries comma-separated) or a block sequence on the following lines.
# Everything from the key up to the next column-0 key is the value, per YAML — so this
# reads all of them without caring which spelling was used.
#
# THE WHITESPACE AFTER THE COLON IS KEPT, NOT STRIPPED, and that is load-bearing: the
# comment strip below only treats a `#` as a comment when whitespace precedes it (so a
# URL fragment — `…/pull/42#issuecomment-9` — survives). Consuming the separator here
# would put a `#` at column 1 for `pr: # note`, where that rule cannot see it. Same
# reason write-snapshot.sh's list_region() removes only up to the colon.
pr_region() {
  printf '%s\n' "$fm" | awk '
    !seen && index($0, "pr:") == 1 { seen = 1; blk = 1; v = $0; sub(/^pr:/, "", v); print v; next }
    blk && /^[[:space:]]/ { print; next }
    blk { blk = 0 }'
}

# A genuine trailing YAML comment, removed line by line: a `#` preceded by whitespace and
# outside a quoted scalar starts one, and everything from there to end of line goes.
#
# WHY THIS IS NOT OPTIONAL POLISH. Without it, `pr: [] # https://…/pull/42` — an EMPTY
# list with a URL in a comment — resolves that URL and clears: exit 0 on a task with no
# recorded PR at all, which is the exact false clearance this whole script exists to
# prevent. A commented-out URL is the most natural way for that line to end up written.
#
# WHY IT LIVES AT THE CONSUMER AND NOT IN pr_region(). This is the third time this repo
# has met this defect (ai-bridge#44 fixed it in write-snapshot.sh, where a trailing
# comment flipped an `awaiting:approve` verb and fabricated a `depends_on` edge), and the
# lesson recorded there is that a BLANKET strip inside a shared region reader twice ate
# real `open_questions` entries. `pr:` is a list of URLs, never free text, so the strip is
# safe HERE and is applied only here. The quote tracking is carried over verbatim from
# that fix rather than re-derived: a `#` inside a quoted scalar is not a comment, and
# `pr: [ "…/pull/42" ]  # merged` must lose only the comment.
#
# Deliberately duplicated rather than shared: these are two standalone scripts, sourcing
# one from the other would run it, and write-snapshot.sh already carries two scoped
# copies of this logic for the same reason.
strip_trailing_comment() { # <text, one or more lines>
  awk '
    function ws(x) { return index(" \t\r\n", x) > 0 }
    {
      q = ""; fresh = 1; cut = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q != "") {
          if (q == "\"" && c == "\\") { i++; continue }
          if (c == q) {
            if (q == "'"'"'" && substr($0, i + 1, 1) == "'"'"'") { i++; continue }
            q = ""
          }
          continue
        }
        if (fresh && (c == "\"" || c == "'"'"'")) { q = c; fresh = 0; continue }
        if (c == "#" && i > 1 && ws(substr($0, i - 1, 1))) { cut = i; break }
        fresh = (ws(c) || c == "," || c == "[" || c == "-")
      }
      print (cut > 0 ? substr($0, 1, cut - 1) : $0)
    }
  ' <<<"$1"
}

# --- the blocked-vs-own-tools contradiction ------------------------------------------
# Three primitives and one predicate, kept here with the other readers. Nothing below runs
# unless `status:` is `blocked`, so an ordinary check pays none of it.

# The bundle root, by walking UP from the task document until a directory carrying the
# instance signature appears — `instance.config.json`, the same one marker
# session-banner.sh, push-state.sh and the two plugin enforcement hooks use to decide "is
# this an instance at all". It was a PAIR with `.claude/agents` until the name swap
# retired that directory: the role agents ship in the `loopd` plugin now, so the
# pair would have stopped matching in every instance at its next re-stamp.
# Deliberately not $CLAUDE_PROJECT_DIR and not a path literal: this script ships in the
# plugin, serves every instance and is run from anywhere, and a task document already knows where it
# lives. No signature ⇒ no answer, which is how a fixture outside an instance stays quiet.
bundle_root() { # <task-doc>
  local d
  d="$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P)" || return 1
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/instance.config.json" ]; then
      printf '%s\n' "$d"; return 0
    fi
    d="$(dirname -- "$d")"
  done
  return 1
}

# The shipped agent document for one role. It used to be one path literal inside the
# bundle; the name swap moved the role agents into the `loopd` PLUGIN, which is
# installed per MACHINE and not per instance, so this now has to look outside the bundle.
# Three sources, cheapest first, and EVERY failure is silent — an unresolvable agent file
# leaves the contradiction check saying nothing, exactly as a missing one always did.
#
#   1. the bundle, for an instance stamped before the swap and not yet re-stamped;
#   2. the plugin the CLI records as INSTALLED — `installed_plugins.json` names the exact
#      `installPath`, which is the only source that knows WHICH cached version is live;
#   3. the newest cached version, for a machine whose install record cannot be parsed.
#
# `CLAUDE_CONFIG_DIR` is honoured because `/<plugin>:init` honours it: a machine that moved its
# config dir has its plugins there too.
agent_file() { # <bundle-root> <agent-name>
  local root="$1" agent="$2" cfgdir p
  [ -f "$root/.claude/agents/$agent.md" ] && { printf '%s\n' "$root/.claude/agents/$agent.md"; return 0; }

  cfgdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  [ -d "$cfgdir/plugins" ] || return 1

  # Source 2. A one-line sed rather than jq: this script has no other dependency, and the
  # value wanted is one string under one known key. A parse that finds nothing falls
  # through to source 3 rather than failing.
  if [ -f "$cfgdir/plugins/installed_plugins.json" ]; then
    p="$(tr -d ' \n' < "$cfgdir/plugins/installed_plugins.json" \
         | sed -n 's/.*"'"${PLUGIN_NAME}@${PLUGIN_MARKETPLACE}"'":\[{[^}]*"installPath":"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$p" ] && [ -f "$p/agents/$agent.md" ] && { printf '%s\n' "$p/agents/$agent.md"; return 0; }
  fi

  # Source 3. Newest by version-sort of the directory name, which is what the CLI names
  # the cache entry. A GLOB, not `ls`: the glob's own order is lexical, and lexical order
  # puts 0.2.0 after 0.10.0 — so the version is compared numerically, field by field,
  # rather than taken from the last match.
  local best="" bestv="" cache="$cfgdir/plugins/cache/$PLUGIN_MARKETPLACE/$PLUGIN_NAME" v
  for p in "$cache"/*/agents/"$agent".md; do
    [ -f "$p" ] || continue
    v="${p#"$cache"/}"; v="${v%%/*}"
    if [ -z "$bestv" ] || \
       [ "$(printf '%s\n%s\n' "$bestv" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$v" ]; then
      bestv="$v"; best="$p"
    fi
  done
  [ -n "$best" ] && { printf '%s\n' "$best"; return 0; }
  return 1
}

# The agent's OWN allowlist, one tool per line. Same frontmatter reader as everywhere
# else; empty output means "no `tools:` key", which is a grant of everything and therefore
# not a contradiction anyone can read off the file — so the predicate below stays silent.
granted_tools() { # <agent-file>
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit}
       fm==1 && /^tools:[[:space:]]*/ { sub(/^tools:[[:space:]]*/, ""); gsub(/,/, "\n"); print }' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

task_body() { # <task-doc> — everything after the closing frontmatter delimiter
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {fm=2; next} fm!=1 {print}' "$1"
}

# A tool name only counts inside BACKTICKS, and only on a line that also says something
# was LACKING. Both halves are needed and each removes a different false positive: without
# the backticks, "read the file" and "no bash on the runner" are hits; without the cue, an
# acceptance criterion that merely names a tool is one. Same reasoning, and the same shape,
# as tests/agent-tool-allowlist.test.sh — a mention is a backticked identifier, never a word.
# The curly apostrophe is deliberate and sits beside the straight one: a blocker reason is
# prose an agent typed, and a smart-quoted "can’t" must not slip past the cue. Same
# accommodation tests/agent-tool-allowlist.test.sh makes, for the same reason.
# shellcheck disable=SC1112
LACK_CUE='(^|[^a-z])([Nn]o|[Nn]ot|[Nn]one|[Nn]ever|[Ww]ithout|[Cc]annot|[Cc]an['"'"'’]t|[Dd]on['"'"'’]t|[Dd]oesn['"'"'’]t|[Ll]ack|[Ll]acks|[Ll]acking|[Mm]issing|[Uu]navailable|[Aa]bsent|[Dd]enied|[Uu]nable|[Nn]eed|[Nn]eeds|[Rr]equire|[Rr]equires|[Bb]locked)([^a-z]|$)'

# Prints one report line per contradicting mention and returns 0 when there is at least
# one. Returns 1 — silently — for every case it cannot decide.
blocked_contradiction() { # <task-doc>
  local root agent afile held t pat line found=1
  root="$(bundle_root "$1")" || return 1
  agent="$(field assignee)"
  [ -n "$agent" ] || return 1
  # A path literal out of the document, so it is confined to one directory and cannot
  # escape it: a slash or a `..` in `assignee:` would otherwise read an arbitrary file.
  case "$agent" in */*|*..*|"") return 1 ;; esac
  afile="$(agent_file "$root" "$agent")" || return 1
  [ -f "$afile" ] || return 1
  held="$(granted_tools "$afile")"
  [ -n "$held" ] || return 1

  while IFS= read -r t; do
    [ -n "$t" ] || continue
    # A wildcard grant (`mcp__claude-in-chrome__*`) covers every tool under its prefix, so
    # naming one of them as missing contradicts the grant just as an exact name does.
    case "$t" in
      *\*) pat="\`${t%\*}[A-Za-z0-9_*-]*\`" ;;
      *)   pat="\`$t\`" ;;
    esac
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s\n' "$line" | grep -qE "$LACK_CUE" || continue
      if [ "$found" -ne 0 ]; then
        echo "CONTRADICTION: $1 reports status: blocked for a reason naming a tool that" >&2
        echo "               $agent's own tools: list already grants:" >&2
        found=0
      fi
      printf '               grants `%s` — "%s"\n' \
        "$t" "$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -c1-96)" >&2
    done <<EOF
$(task_body "$1" | grep -E "$pat" || true)
EOF
  done <<EOF
$held
EOF

  [ "$found" -eq 0 ] || return 1
  echo "               A tool you hold is not a blocker. Re-read the allowlist in" >&2
  echo "               $afile before writing a blocker reason." >&2
  echo "               If a tool really is absent, $AB_CONVENTIONS's middle rung applies:" >&2
  echo "               record the request in open_questions and CARRY ON — blocked is not" >&2
  echo "               the response to a missing tool." >&2
  echo "               This is a report, not an instruction. Nothing is re-dispatched." >&2
  return 0
}

# The repo a PR would be opened against. `target_repo:` INHERITS the project default when
# the task omits it (SCHEMA.md), so the task document alone cannot tell a bundle-only task
# from a repo-backed one — reading it without project.md would exempt the second.
resolved_repo() { # prints the repo, `?` when the project doc exists but cannot be read
  local v proj pfm
  v="$(field target_repo)"
  [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
  proj="$(dirname -- "$TASK")/../project.md"
  [ -f "$proj" ] || return 0
  # Unreadable frontmatter is unknown, never "no repo": the exemption below is a pass, and
  # a malformed project document must not be able to grant one.
  pfm="$(fm_block "$proj")" || { printf '?\n'; return 0; }
  field target_repo "$pfm"
}

status="$(field status)"
kind="$(field kind)"
repo="$(resolved_repo)"
region="$(pr_region)"
# Every judgement below is made on the COMMENTED-OUT-FREE value. Nothing a human wrote
# after a `#` is a recorded artifact, and a URL sitting in a comment is the one input that
# could make an empty `pr:` clear.
value="$(strip_trailing_comment "$region")"

# What the field CLAIMS, with the list syntax stripped: empty means the agent recorded no
# artifact at all, which is a different finding from recording an unusable one.
claim="$(printf '%s' "$value" | tr -d '[]",'"'" | tr -d '[:space:]')"
# ...and the URLs inside it. A pull-request URL is the only thing here that can be resolved.
urls="$(printf '%s\n' "$value" | grep -oE 'https?://[^]"'"'"' ,]+/pull/[0-9]+')"

[ -n "$status" ] || {
  echo "error: $TASK records no status:, so whether the dispatch advanced it is" >&2
  echo "       unknown — and unknown is not a pass. Refusing." >&2
  exit 2
}

# A research task produces a deliverable, never a PR (SCHEMA.md), so "is there a PR?" is
# not a question about it. Say so and refuse, rather than inventing a verdict out of an
# absence that is correct.
if [ "$kind" = "research" ]; then
  echo "cannot answer: $TASK is kind: research — it has no PR by design." >&2
  echo "               Check its artifacts: and the deliverable itself instead." >&2
  exit 2
fi

case "$status" in
  draft|ready|in-progress) advanced=no ;;
  blocked|cancelled)       advanced=stopped ;;
  *)                       advanced=yes ;;
esac

# The `claude --bg` session the tick spawned, when the task records one (SCHEMA.md).
# It NEVER moves a verdict: a live agent and a dead one leave the same document behind,
# so the exit code is what it always was. It says WHICH of the two a human is looking at,
# which is the difference between waiting and recovering.
session_note() {
  local sid st here
  sid="$(field session)"
  [ -n "$sid" ] || return 0
  here="$(dirname "${BASH_SOURCE[0]:-$0}")"
  st="$(bash "$here/agent-sessions.sh" state "$sid" 2>/dev/null)" || st="unknown"
  case "$st" in
    working) echo "        SESSION $sid is WORKING — it has not parked; give it time." >&2 ;;
    blocked) echo "        SESSION $sid is BLOCKED on a prompt nobody can answer, and it" >&2
             echo "        holds a maxAgentsInFlight slot until somebody stops it." >&2 ;;
    done)    echo "        SESSION $sid has EXITED without opening the pull request." >&2 ;;
    gone)    echo "        SESSION $sid is not listed: it never started, or was removed." >&2 ;;
    *)       echo "        SESSION $sid: state unknown — the session list did not answer." >&2 ;;
  esac
}

# --- the parked signature, decided from the document alone --------------------------
# Deliberately before the host is consulted: this verdict must survive an offline machine.
if [ "$advanced" = "no" ] && [ -z "$claim" ]; then
  echo "PARKED: $TASK is still at status: $status and names no pull request." >&2
  session_note
  echo "        The agent reported, but nothing it promised is on the host. Read its" >&2
  echo "        final message: the work is often already committed, sometimes already" >&2
  echo "        pushed, and one message asking it to open the PR recovers it." >&2
  echo "        This is a report, not an instruction — deciding what to do with it," >&2
  echo "        including whether anything is dispatched, stays with the human." >&2
  exit 1
fi

# --- resolve every URL the record claims --------------------------------------------
# The host is only needed from here on. A missing or unauthenticated CLI means the claim
# cannot be checked, which is unknown state — never "the PR is not there" (exit 3), and
# never a pass.
missing=""
if [ -n "$urls" ]; then
  command -v gh >/dev/null 2>&1 || {
    echo "cannot answer: gh is not installed, so the pull request(s) $TASK claims" >&2
    echo "               cannot be resolved. Unknown is not a pass — refusing." >&2
    exit 2
  }
  # Both host calls read from /dev/null: this loop's stdin IS the URL list, and a child
  # that consumed any of it would silently drop the PRs after the first — a task may fan
  # out to several (SCHEMA.md), and a swallowed one is a PR nobody checked.
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    if gh pr view "$u" --json url >/dev/null 2>&1 </dev/null; then
      echo "ok: $u exists"
    elif ! gh auth status >/dev/null 2>&1 </dev/null; then
      echo "cannot answer: gh cannot reach the host (not logged in), so whether" >&2
      echo "               $u exists is unknown. Refusing rather than reporting a" >&2
      echo "               missing PR that may be perfectly fine." >&2
      exit 2
    else
      missing="$missing $u"
    fi
  done <<EOF
$urls
EOF
fi

if [ -n "$missing" ]; then
  echo "NOT THERE: $TASK claims a pull request the host does not resolve:" >&2
  # Unquoted on purpose: $missing is a space-joined list of URLs, and a URL contains no
  # space — word splitting is the iteration here.
  # shellcheck disable=SC2086
  for u in $missing; do echo "           $u" >&2; done
  echo "           A deleted branch, a URL written from memory, or a PR opened" >&2
  echo "           against the wrong repository all land here." >&2
  exit 3
fi

# A `pr:` with content but no URL in it — `[ pending ]`, a branch name, a bare number — is
# a claim with nothing resolvable behind it. The report DID say it produced something, so
# this is the unbacked-claim shape, not the parked one.
if [ -n "$claim" ] && [ -z "$urls" ]; then
  echo "NOT A URL: $TASK has pr:$(printf '%s' "$value" | tr '\n' ' ')" >&2
  echo "           which names no pull request URL, so nothing can be resolved." >&2
  exit 3
fi

if [ "$advanced" = "yes" ] && [ -z "$urls" ]; then
  # A task that names no target repo — neither its own nor its project's — has nowhere to
  # open a PR, so an empty `pr:` is its correct shape and not a contradiction. Reported
  # rather than silent: an exemption nobody can see is one nobody can question.
  if [ -z "$repo" ]; then
    echo "ok: $TASK advanced to status: $status and names no pull request — correct:"
    echo "    it records no target_repo:, and neither does its project, so no pull"
    echo "    request was ever due. Skipped: the advanced-with-no-PR rule (exit 4)."
    exit 0
  fi
  echo "MISMATCH: $TASK reads status: $status but names no pull request." >&2
  echo "          One of the two is wrong: either the PR was never opened, or it was" >&2
  echo "          opened and never recorded. Read the agent's report before acting." >&2
  exit 4
fi

if [ "$advanced" = "no" ] && [ -n "$urls" ]; then
  echo "MISMATCH: $TASK names a pull request that exists, but status: is still" >&2
  echo "          $status. The work landed; the record did not move. That is a" >&2
  echo "          document edit, never a reason to dispatch the task again." >&2
  exit 4
fi

if [ "$advanced" = "stopped" ]; then
  # --- the one thing a `blocked` reason can say that is checkable --------------------
  # `blocked` for a reason that NAMES A TOOL THE ASSIGNEE'S OWN `tools:` LIST GRANTS.
  #
  # WHY THIS ONE AND NOTHING WIDER. Whether a blocker is real is a judgement, and this
  # script does not make judgements (see the header). But "I am blocked because I lack
  # `Bash`" from an agent whose frontmatter grants `Bash` is not a judgement — it is the
  # record disagreeing with itself, decidable from two files, and it is the COMMON shape:
  # the default an agent falls into is to report the gap rather than to exhaust what it
  # holds (`CONVENTIONS.md` → "Exhaust your own tools before you hand work back").
  #
  # WHAT IT CANNOT SEE, stated so nobody reads more into a green result: an agent that
  # silently hands instructions back instead of acting leaves no artifact at all, and a
  # blocker that is genuine but was never worth blocking on reads exactly like a real one.
  # This catches the contradiction, not the behaviour.
  #
  # AND IT CAN OVER-REPORT, on purpose. The scan is the whole document body, so a `# Context`
  # sentence naming a held tool next to a negation ("must not use `Bash`") reports too. That
  # direction is the cheap one — the verdict is report-only and costs a human one read of a
  # quoted line — where narrowing to a section heading would go silent whenever an agent
  # wrote its reason somewhere else, and silence is what this whole class of check fails at.
  #
  # SILENT WHEN IT CANNOT DECIDE. No `assignee:`, no bundle root, no agent file, no
  # `tools:` key — every one of those means the question is unanswerable, and an
  # unanswerable question adds nothing to an honest stop. It falls through to exit 0
  # rather than inventing a verdict, which is also what keeps this off a task document
  # checked outside an instance.
  if [ "$status" = "blocked" ]; then
    blocked_contradiction "$TASK" && exit 4
  fi
  echo "ok: $TASK reports status: $status — an honest stop, no PR expected."
  echo "    Read the stated reason; this check has nothing further to say about it."
  exit 0
fi

echo "ok: $TASK advanced to status: $status and every pull request it names exists."
exit 0
