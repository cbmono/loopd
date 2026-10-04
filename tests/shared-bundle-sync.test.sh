#!/usr/bin/env bash
#
# shared-bundle-sync.test.sh — a tick pulls before it reads and pushes after it
# commits, on a bundle that HAS a remote; a bundle with none does neither, silently;
# a pull conflict STOPS the tick rather than resolving it; and nothing here ever
# force-pushes. Pinned across both files that carry the behaviour: the TICK
# (`project-manager.md`, step 0's pull / step 8's push paragraph) and the LAUNCHER
# (`pm-loop.md`'s standing guardrails), because a reader who edits one without the
# other silently drops half the guarantee.
#
# WHY THIS IS A TEST AND NOT A CONVENTION. `git push` and `git pull` appeared
# NOWHERE in the shipped machinery before this change — not the PM agent, not
# `/pm-loop`, not any of the 14 `plugin/scripts/*.sh`, not a hook. A tick committed
# locally via `commit-as.sh` and stopped. That was harmless while every instance had
# one human; it stopped being harmless the day a second clone started sharing one
# bundle, because the two clones now diverge silently until somebody pushes by hand
# — and the ownership gate (`task-owner.sh`) cannot help, since it reads task
# documents the other clone has not fetched yet.
#
# FOUR PROPERTIES, EACH INDEPENDENTLY DROPPABLE. A future edit that "simplifies" the
# step can keep some of the words and lose the behaviour: "pull" surviving in a
# sentence that no longer runs before the read, or "conflict" surviving in a
# sentence that now resolves one instead of refusing to. So each property below is
# pinned by its OPERATIVE text — the actual git command or the actual refusal — not
# by an incidental noun, and every extraction is proven capable of failing against a
# synthetic fixture that drops exactly that property (a check that can only pass is
# not a check).
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TICK="$REPO/plugin/agents/project-manager.md"
LAUNCHER="$REPO/plugin/skills/dispatch/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sync.XXXXXX")" || {
  echo "shared-bundle-sync.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
DRAFT=""; STRAY=""   # probe files written INSIDE the repo under test — reaped even on a kill
trap 'rm -rf "$TMP"; [ -z "$DRAFT" ] || rm -f "$DRAFT"; [ -z "$STRAY" ] || rm -f "$STRAY"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { # <file> <fixed-string> -> yes|no
  grep -qF -- "$2" "$1" && echo yes || echo no
}
# An ambient GIT_DIR outranks `-C`, so it would answer these reads from another repo.
g() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$REPO" "$@"; }

ok "tick exists"     "$([ -f "$TICK" ] && echo yes || echo no)" yes
ok "launcher exists" "$([ -f "$LAUNCHER" ] && echo yes || echo no)" yes

# --- extraction: the tick's step 0 (sync), its step-8 push paragraph, and the ------
# --- launcher's sync guardrail bullet — the three places the behaviour lives -------
step0_of() { # <file> -> the sync step's body only, stopping at step 0.5
  awk '/^0\. \*\*Sync the bundle first/{p=1;next} /^0\.5\. /{p=0} p' "$1"
}
push_para_of() { # <file> -> the step-8 push paragraph only
  awk '/\*\*Then (push|sync), if this bundle has a remote\.\*\*/{p=1} p&&/\*\*Refresh the awaiting-you queue/{p=0} p' "$1"
}
guardrail_of() { # <file> -> the launcher's standing-guardrail bullet only
  awk '/- \*\*The tick syncs the bundle around its own work/{p=1} p&&/- \*\*An answered question is MOVED/{p=0} p' "$1"
}

S0="$(step0_of "$TICK")"
PUSH="$(push_para_of "$TICK")"
G="$(guardrail_of "$LAUNCHER")"
ok "tick has a step 0 sync section"       "$([ -n "$S0" ]   && echo yes || echo no)" yes
ok "tick has a step 8 sync paragraph"     "$([ -n "$PUSH" ] && echo yes || echo no)" yes
ok "launcher has the sync guardrail bullet" "$([ -n "$G" ]  && echo yes || echo no)" yes

in_str() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; } # <text> <needle>

# =================================================================================
# Property 1 — a bundle WITH a remote pulls --rebase before re-deriving state
# =================================================================================
ok "step 0: pulls with rebase"             "$(in_str "$S0" 'git pull --rebase origin')" yes
ok "step 0: pull precedes the re-derive"     "$(in_str "$S0" 'Why before step 0.5 and not after it')" yes
ok "guardrail: names the pull"               "$(in_str "$G" '--rebase')" yes
ok "guardrail: pull precedes the read"       "$(in_str "$G" 'before it re-derives anything from disk')" yes

# =================================================================================
# Property 2 — the tick pushes after it commits
# =================================================================================
ok "step 8: pushes to origin"                "$(in_str "$PUSH" 'git push origin')" yes
ok "guardrail: names the push"                "$(in_str "$G" 'pushes right after it commits')" yes
# The push paragraph also retries once on rejection, then stops like step 0 does.
ok "step 8: retries once on rejection"        "$(in_str "$PUSH" 'push once more')" yes
ok "step 8: a second conflict stops it too"   "$(in_str "$PUSH" 'stop and report exactly')" yes

# =================================================================================
# Property 3 — a bundle with NO remote does neither, silently (never an error)
# =================================================================================
ok "step 0: gated on a remote existing"           "$(in_str "$S0" 'git remote get-url origin')" yes
ok "step 0: absence is never an error"            "$(in_str "$S0" 'never an error')" yes
ok "step 8: shares step 0's no-remote condition"  "$(in_str "$PUSH" 'Same condition as step 0')" yes
ok "guardrail: no remote -> neither, silently"    "$(in_str "$G" 'does neither, silently')" yes

# =================================================================================
# Property 4 — a pull conflict STOPS the tick; it is never auto-resolved
# =================================================================================
ok "step 0: a conflict STOPS the tick"       "$(in_str "$S0" 'A conflict STOPS the tick')" yes
ok "step 0: aborts rather than resolving"    "$(in_str "$S0" 'git rebase --abort')" yes
ok "step 0: names what a tick must not do"   "$(in_str "$S0" 'Do not resolve it')" yes
ok "guardrail: conflict stops the tick"      "$(in_str "$G" 'stops the tick')" yes
ok "guardrail: reports, never resolves"      "$(in_str "$G" 'a tick never resolves contested')" yes

# =================================================================================
# Property 5 — nothing here ever force-pushes
# =================================================================================
ok "step 8: never force-push"                "$(in_str "$PUSH" 'Never force-push a shared bundle')" yes
ok "guardrail: never force-pushes"           "$(in_str "$G" 'nothing here ever force-pushes')" yes

# =================================================================================
# NON-VACUITY. Each extraction above must be able to FAIL — demonstrated by mutating
# a synthetic copy of the real section and dropping exactly one property, then
# re-running the same extraction + grep over the mutation. A checker that cannot
# fail on any input proves nothing (the whole lesson of "don't grep one word").
# =================================================================================
good_step0() {
  cat <<'EOF'
0. **Sync the bundle first — pull before you read anything.**

   **Only when this bundle has a remote.** `git remote get-url origin` failing means a
   local-only instance: skip this silently and skip the push in step 8 too. Absence is
   the single-machine case behaving exactly as it always has, never an error.

   ```
   git pull --rebase origin <default-branch>
   ```

   **Why before step 0.5 and not after it.** re-derives from disk.

   **A conflict STOPS the tick. Do not resolve it.** Abort (`git rebase --abort`),
   change nothing, and report the conflicting paths for the human.

0.5. next step
EOF
}
ok "fixture: good step 0 passes every check" \
   "$(g="$(good_step0 | awk '/^0\. \*\*Sync the bundle first/{p=1;next} /^0\.5\. /{p=0} p')"; \
      a=$(in_str "$g" 'git pull --rebase origin'); \
      b=$(in_str "$g" 'git remote get-url origin'); \
      c=$(in_str "$g" 'never an error'); \
      d=$(in_str "$g" 'A conflict STOPS the tick'); \
      e=$(in_str "$g" 'git rebase --abort'); \
      [ "$a$b$c$d$e" = "yesyesyesyesyes" ] && echo yes || echo no)" yes

mut_check() { # <mutated-step0-text> <needle-that-should-now-be-absent>
  local body; body="$(printf '%s\n' "$1" | awk '/^0\. \*\*Sync the bundle first/{p=1;next} /^0\.5\. /{p=0} p')"
  in_str "$body" "$2"
}

no_pull="$(good_step0 | grep -v 'git pull --rebase origin')"
ok "…and FAILS when the pull command is dropped" "$(mut_check "$no_pull" 'git pull --rebase origin')" no

no_remote_gate="$(good_step0 | grep -v 'git remote get-url origin')"
ok "…and FAILS when the no-remote gate is dropped" "$(mut_check "$no_remote_gate" 'git remote get-url origin')" no

resolves_conflict="$(good_step0 | sed 's/A conflict STOPS the tick\. Do not resolve it\./A conflict is resolved automatically./')"
ok "…and FAILS when the refusal is replaced by auto-resolving" \
   "$(mut_check "$resolves_conflict" 'A conflict STOPS the tick')" no

good_push_para() {
  cat <<'EOF'
   **Then push, if this bundle has a remote.** `git push origin <default-branch>`.
   Same condition as step 0: no remote => no push, silently. If the push is
   rejected because the remote moved while you worked, `git pull --rebase
   origin <default-branch>` and push once more; if THAT conflicts, stop and report exactly
   as in step 0. **Never force-push a shared bundle.**

   **Refresh the awaiting-you queue**
EOF
}
ok "fixture: good push paragraph passes every check" \
   "$(p="$(good_push_para | awk '/\*\*Then (push|sync), if this bundle has a remote\.\*\*/{p=1} p&&/\*\*Refresh the awaiting-you queue/{p=0} p')"; \
      a=$(in_str "$p" 'git push origin'); \
      b=$(in_str "$p" 'Same condition as step 0'); \
      c=$(in_str "$p" 'Never force-push a shared bundle'); \
      [ "$a$b$c" = "yesyesyes" ] && echo yes || echo no)" yes

no_force_push_rule="$(good_push_para | grep -v 'Never force-push a shared bundle')"
mut_push_check() { # <mutated-push-text> <needle>
  local body; body="$(printf '%s\n' "$1" | awk '/\*\*Then (push|sync), if this bundle has a remote\.\*\*/{p=1} p&&/\*\*Refresh the awaiting-you queue/{p=0} p')"
  in_str "$body" "$2"
}
ok "…and FAILS when the never-force-push rule is dropped" \
   "$(mut_push_check "$no_force_push_rule" 'Never force-push a shared bundle')" no

no_push_cmd="$(good_push_para | grep -v 'git push origin')"
ok "…and FAILS when the push command is dropped" \
   "$(mut_push_check "$no_push_cmd" 'git push origin')" no

# =================================================================================
# Acceptance criterion 5 — the step renumbering left no stale "step 0" cross-
# reference anywhere in the repo. Old step 0 (re-derive the in-flight set) became
# step 0.5; the literal string "step 0" must now appear ONLY in the tick (naming
# its own new sync step) and the launcher (which must cite 0.5 for the property
# that moved there, never a bare "step 0").
# =================================================================================
# The twin-dedup this used to carry is gone with the copies it deduplicated: the
# name swap retired symlink/.claude/agents/, so plugin/agents/ is the only copy and
# every match here is a distinct file again.
#
# THE CANDIDATE SET COMES FROM GIT, never from a filesystem walk. This used to be
# `grep -rl … "$REPO"`, which excluded only `.git/` — so an agent's scratch draft,
# written exactly where CONVENTIONS.md tells it to write one (`<worktree>/tmp/`, a
# path this repo ignores), scored as a third document describing step 0 and turned
# the suite red. `--cached --others --exclude-standard` is tracked files plus
# untracked ones git would offer to add: a new doc carrying a stale reference is
# still caught, and nothing ignored can move the answer.
step0_mentioning_files() {
  local files=() f
  while IFS= read -r -d '' f; do files+=("$f"); done < <(
    g ls-files -z --cached --others --exclude-standard -- '*.md')
  [ ${#files[@]} -gt 0 ] || return 0
  (cd "$REPO" && grep -l "step 0" -- "${files[@]}" 2>/dev/null) | sort
}
S0FILES="$(step0_mentioning_files)"
# The TICK is eight files since ai-bridge-v3/task-024 — the core prompt plus one per
# on-demand step — so "exactly two files" becomes "the tick's own files and the launcher,
# nothing else". Asserted as a count of STRANGERS, which is the property: a third document
# describing step 0 is the drift this catches, and a new step file is not one.
ok "…the tick's core names it"  "$(grep -qx 'plugin/agents/project-manager.md' <<<"$S0FILES" && echo yes || echo no)" yes
ok "…and the launcher does"     "$(grep -qx 'plugin/skills/dispatch/SKILL.md' <<<"$S0FILES" && echo yes || echo no)" yes
ok "…and nothing outside those and the tick-step files" \
   "$(printf '%s\n' "$S0FILES" | grep -vx 'plugin/agents/project-manager.md' \
      | grep -vx 'plugin/skills/dispatch/SKILL.md' | grep -vc '^plugin/tick-steps/' | tr -d ' ')" 0

# REGRESSION: a gitignored scratch .md naming step 0 must not change that answer.
# The path is READ OUT OF the scratch rule rather than spelled here, so renaming the
# scratch directory moves this probe with it instead of quietly retiring it.
# shellcheck disable=SC2016  # the backticks are markdown in the rule, not a substitution
SCRATCH="$(head -1 <<<"$(sed -n 's/^.*Scratch files go in `<worktree>\/\([^`]*\)`.*$/\1/p' \
           "$REPO/plugin/seed/CONVENTIONS.md")")"; SCRATCH="${SCRATCH%/}"
if [ -z "$SCRATCH" ] || ! g check-ignore -q -- "$SCRATCH/probe.md"; then
  echo "shared-bundle-sync.test: no ignored scratch path in plugin/seed/CONVENTIONS.md" >&2; exit 2
fi
mkdir -p "$REPO/$SCRATCH" || exit 2
DRAFT_REL="$SCRATCH/shared-bundle-sync-regression.$$.md"
DRAFT="$REPO/$DRAFT_REL"
printf 'PR body draft — step 0 pulls before the tick reads.\n' > "$DRAFT"
# NON-VACUITY: the walk this test used to do still sees the file, so a green run below
# means the enumeration changed, not that the fixture failed to land.
ok "…the pre-fix filesystem walk DID see an ignored scratch draft" \
   "$(grep -rl "step 0" --include="*.md" "$REPO" 2>/dev/null | grep -cF "$DRAFT" | tr -d ' ')" 1
ok "…and a gitignored scratch .md changes nothing"  "$(step0_mentioning_files | grep -cFx "$DRAFT_REL" | tr -d ' ')" 0
ok "…leaving the stranger count where it was" \
   "$(step0_mentioning_files | grep -vx 'plugin/agents/project-manager.md' \
      | grep -vx 'plugin/skills/dispatch/SKILL.md' | grep -vc '^plugin/tick-steps/' | tr -d ' ')" 0
rm -f "$DRAFT"; DRAFT=""; rmdir "$REPO/$SCRATCH" 2>/dev/null || true

# …and the complement, because narrowing the scan could have made it blind instead of
# correct: an UNTRACKED, unignored .md is still a stranger.
STRAY_REL="shared-bundle-sync-regression.$$.md"
STRAY="$REPO/$STRAY_REL"
printf 'a new doc that names step 0.\n' > "$STRAY"
ok "…while an untracked, unignored .md IS still counted" \
   "$(step0_mentioning_files | grep -vx 'plugin/agents/project-manager.md' \
      | grep -vx 'plugin/skills/dispatch/SKILL.md' | grep -vc '^plugin/tick-steps/' | tr -d ' ')" 1
rm -f "$STRAY"; STRAY=""

# The launcher's citation of the re-derivation property must point at 0.5, the step
# it actually lives in now — not the bare "step 0" that would silently mean the new
# sync step instead.
ok "launcher cites step 0.5 for the re-derive property" \
   "$(has "$LAUNCHER" "project-manager.md\` step 0.5")" yes
# And the old, now-false claim that re-derivation is the tick's literal first step
# must not have survived the renumbering.
ok "launcher no longer claims re-derive is the tick's own first step" \
   "$(has "$LAUNCHER" "is the tick's own first step")" no


# --- REGRESSION: --autostash must never come back -------------------------------
# Measured 2026-08-24: with the rebase clean but the stash re-apply conflicting,
# `git pull --rebase --autostash` EXITS 0 with HEAD already moved and the tree left
# UU-conflicted, and `git rebase --abort` then fails "no rebase in progress". A tick
# trusting that exit code parses task documents full of conflict markers and acts on
# them. So the flag is banned as a COMMAND, the dirty-tree refusal that replaces it is
# required, and the exit code is explicitly not trusted.
# Ban it as a COMMAND, not as a word: step 0's prose names the flag on purpose to
# explain why it is absent, so a bare substring check would fail on its own warning.
S0_CMDS="$(printf '%s\n' "$S0" | grep -E '^\s{3,}git ' || true)"
ok "step 0: no --autostash in any command it tells you to run" \
   "$(in_str "$S0_CMDS" '--autostash')" no
ok "push retry: does NOT pull with --autostash" \
   "$(in_str "$PUSH" '--rebase --autostash')" no
ok "launcher: does NOT describe an --autostash pull" \
   "$(in_str "$G$LAUNCHER" 'pulls `--rebase --autostash`')" no
ok "step 0: checks the tree before pulling" \
   "$(in_str "$S0" 'git status --porcelain')" yes
# A dirty tree must DEFER the pull, never halt the tick: concurrent agents share this
# working tree, so a sibling mid-write is the normal state, not an anomaly. And the
# check must ignore untracked files, which never obstruct a rebase.
ok "step 0: ignores untracked files in that check" \
   "$(in_str "$S0" '--untracked-files=no')" yes
ok "step 0: a dirty tree DEFERS the pull rather than stopping the tick" \
   "$(in_str "$S0" 'never blocks the tick')" yes
ok "step 0: no longer claims a dirty tree is anomalous" \
   "$(in_str "$S0" 'is anomalous anyway')" no
ok "step 8: performs the deferred pull before pushing" \
   "$(in_str "$PUSH" 'deferred its pull')" yes
ok "step 0: says why --autostash is absent (so nobody re-adds it)" \
   "$(in_str "$S0" 'exits 0')" yes
ok "step 0: does not trust the pull exit code" \
   "$(in_str "$S0" 'Do not trust the pull')" yes
# Non-vacuity: each check above must be able to fail.
bad_cmds="$(printf '%s\n' "$S0_CMDS" | sed 's/git pull --rebase origin/git pull --rebase --autostash origin/')"
ok "…and the --autostash ban FAILS on a reintroduced flag" \
   "$(in_str "$bad_cmds" '--autostash')" yes
no_dirty="$(printf '%s\n' "$S0" | grep -v 'git status --porcelain')"
ok "…and the tree check FAILS when the guard is dropped" \
   "$(in_str "$no_dirty" 'git status --porcelain')" no
no_u="$(printf '%s\n' "$S0" | sed 's/ --untracked-files=no//')"
ok "…and the untracked exclusion FAILS when the flag is dropped" \
   "$(in_str "$no_u" '--untracked-files=no')" no


# --- ORDER, not just presence -----------------------------------------------------
# Both commands being present says nothing about which runs first, and the whole
# guard is the ordering: status THEN pull. Compare line numbers inside step 0.
s0_status_ln="$(head -1 <<<"$(printf '%s\n' "$S0" | grep -n -- 'git status --porcelain --untracked-files=no')" | cut -d: -f1)"
s0_pull_ln="$(head -1 <<<"$(printf '%s\n' "$S0" | grep -n -- 'git pull --rebase origin')" | cut -d: -f1)"
ok "step 0: the tree check comes BEFORE the pull" \
   "$([ -n "$s0_status_ln" ] && [ -n "$s0_pull_ln" ] && [ "$s0_status_ln" -lt "$s0_pull_ln" ] && echo yes || echo no)" yes
# Step 8 must re-check the tree itself rather than assuming the commit cleaned it:
# commit-as.sh commits only NAMED paths, so a sibling agent's edits survive it.
p8_status_ln="$(head -1 <<<"$(printf '%s\n' "$PUSH" | grep -n -- 'git status --porcelain --untracked-files=no')" | cut -d: -f1)"
p8_pull_ln="$(head -1 <<<"$(printf '%s\n' "$PUSH" | grep -n -- 'git pull --rebase origin')" | cut -d: -f1)"
ok "step 8: re-checks the tree itself" \
   "$([ -n "$p8_status_ln" ] && echo yes || echo no)" yes
ok "step 8: that check comes BEFORE its pull" \
   "$([ -n "$p8_status_ln" ] && [ -n "$p8_pull_ln" ] && [ "$p8_status_ln" -lt "$p8_pull_ln" ] && echo yes || echo no)" yes
ok "step 8: says why a commit does not imply a clean tree" \
   "$(in_str "$PUSH" 'only the paths you')" yes
# An untracked path can still block a rebase, and the response must never be destructive.
ok "step 0: handles the untracked-path collision the check cannot see" \
   "$(in_str "$S0" 'would be')" yes
ok "step 0: forbids git clean as the response" \
   "$(in_str "$S0" 'never delete the untracked file')" yes
# Non-vacuity for the ordering checks.
swapped="$(printf '%s\n' 'git pull --rebase origin main'; printf '%s\n' 'git status --porcelain --untracked-files=no')"
sw_a="$(head -1 <<<"$(printf '%s\n' "$swapped" | grep -n -- 'git status --porcelain --untracked-files=no')" | cut -d: -f1)"
sw_b="$(head -1 <<<"$(printf '%s\n' "$swapped" | grep -n -- 'git pull --rebase origin')" | cut -d: -f1)"
ok "…and the order check FAILS when the two are swapped" \
   "$([ "$sw_a" -lt "$sw_b" ] && echo yes || echo no)" no
ok "…and the fence carries a language (MD040)" \
   "$(in_str "$S0" '```bash')" yes

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
