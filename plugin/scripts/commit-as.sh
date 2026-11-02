#!/usr/bin/env bash
#
# commit-as.sh — commit to THIS control-panel instance repo under a per-agent
# author identity, for provenance in the autonomous PM loop.
#
#   Usage: commit-as.sh <role> "<commit message>" [git args...] -- <path>...
#          commit-as.sh <role> "<commit message>" --stage [git args...] -- <path>...
#          commit-as.sh <role> "<commit message>" --all-staged [git args...]
#
# The author NAME is the role; the author EMAIL is shared so the host (e.g.
# GitHub) still links commits to the human's account, while `git log --format=%an`
# / `git shortlog -sn` separate work per agent.
#
# NAME THE PATHS YOU ARE COMMITTING, after a `--`. Several agents run
# concurrently against ONE working tree, so the index is shared state: a role that
# commits "whatever is staged" silently absorbs whatever a sibling agent staged a
# second earlier, and that sibling's work lands under the wrong author. This has
# happened repeatedly in practice. Naming paths commits only those, leaving
# everyone else's staged changes staged and intact.
#
# What gets committed for a named path is the STAGED content — `git add` it first,
# or pass `--stage` to have this script `git add` exactly the named paths (never
# `-A`, never a path you did not name) as its first act. A working-tree edit made
# after that `git add` is not committed and stays a working-tree edit.
#
# So for every role except `human`, one of the two forms above is REQUIRED:
#   - `-- <path>...`  commit exactly these paths (strongly preferred), or
#   - `--all-staged`  commit the whole index, an explicit "I checked, it's all mine".
# `human` is exempt: a person committing interactively can see the index.
# Never `git add -A` in a shared instance — stage by explicit path.
#
# GENERIC PLUGIN FILE — ships inside the `loopd` plugin; nothing to
# edit per instance. The author email is resolved, in order, from:
#   1. $CONTROL_PLANE_AUTHOR_EMAIL                               (explicit override)
#   2. "authorEmail" in <repo-root>/instance.config.local.json   (this machine)
#   3. "people"[<ownerGithubUser>] in instance.config.json       (tracked directory)
#   4. "authorEmail" in <repo-root>/instance.config.json         (tracked, shared)
#   5. `git config user.email`
#
# Most specific first: an explicit env var, then a statement about THIS machine, then
# the shared directory looked up by who this machine is, then the shared default,
# then git's own answer.
#
# WHY 2 AND 3 EXIST. `instance.config.json` is TRACKED, so on a bundle shared by two
# humans a single `authorEmail` there would author BOTH clones' commits as one person
# — destroying the per-agent, per-human provenance this script exists to create.
#
# Step 3 is the shape that scales: `"people": { "<login>": "<email>", ... }` in the
# TRACKED config is a directory of who is who, recorded once by whoever knows the
# addresses, and each clone's local file then needs a single key —
# `{ "ownerGithubUser": "<login>" }` — which the ownership gate (task-owner.sh)
# already requires anyway. So a second human's setup is one line and they never write
# their own address down. Step 2 stays for the machine that wants to state its own
# address outright, and it wins, being the more specific claim.
#
# `people` is read from the TRACKED file only: it is a shared fact, like `defaultOwner`
# (see task-owner.sh), not a per-machine one.
#
# THE ADDRESS IS PER-INSTANCE, NOT PER-PERSON, which is exactly why the map lives in the
# instance's own config and nowhere shared: the same login maps to a different address in
# each group's bundle, because the address says which entity the work belongs to. One
# person working three clients commits as three addresses. Two things follow. (1) Never
# DERIVE it from the login — no `<login>@<domain>` rule, and specifically not
# `<login>@users.noreply.github.com`, which was REJECTED because GitHub requires the
# ID-prefixed `<id>+<login>@…` form for accounts created after 2017-07-18 and a derived
# plain address silently fails to link. The mapping is a business fact, not a naming
# convention. (2) Never move the address into the local file: that file says which login
# this clone IS, and the address for that login in THIS instance comes from the tracked
# map. Reversed, two clones of one instance could disagree about which entity the work
# belongs to and git history would record both.
#
# **Absence changes nothing** at every step: no local file, no `people`, no
# `ownerGithubUser` ⇒ steps 4 and 5 exactly as before. That is what keeps this a no-op
# for every single-human instance.
#
# WHY THIS EXISTS, AND WHY NO FIRST-PARTY FEATURE REPLACES IT (v2 audit, 2026-08).
# Native background sessions commit, push their own branch and open draft PRs — a
# different problem. That is work in an isolated worktree of a TARGET repo under one
# identity. This is work in the shared working tree of ONE bundle repo, by several
# concurrent agents, under per-agent authorship. Three things follow that nothing
# upstream provides:
#   1. `git commit -- <path>` has the wrong semantics: it commits WORKING TREE
#      content for that path, not the staged content. Hence the temporary index
#      (GIT_INDEX_FILE + read-tree + update-index --index-info) — the only way to
#      commit exactly the named staged entries while leaving a sibling agent's
#      staged files untouched. Not cleverness; there is no git primitive for it.
#   2. The promotion guard below reads the INDEX for that same reason. If the commit
#      took its content from the working tree, an uncommitted `status: ready` edit
#      could ride along past the guard.
#   3. Per-agent author identity, which is the bundle's provenance record.
# Verdict: keep, unshrunk. The v2 plan's overlap table guessed "shrink hard,
# possibly delete" and was wrong on all three counts.
#
# SCOPE: this control-panel instance repo ONLY. Target product repos may forbid
# AI attribution — never use this there; commit with the repo's normal identity.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

VALID_ROLES=(project-manager software-engineer devops-engineer qa-reviewer cataloguer human)

usage() {
  echo "Usage: $(basename "$0") <role> \"<commit message>\" [git args...] -- <path>..." >&2
  echo "       $(basename "$0") <role> \"<commit message>\" --stage [git args...] -- <path>..." >&2
  echo "       $(basename "$0") <role> \"<commit message>\" --all-staged [git args...]" >&2
  echo "Roles: ${VALID_ROLES[*]}" >&2
  exit 2
}

[ "$#" -ge 2 ] || usage
role="$1"; shift
message="$1"; shift

case " ${VALID_ROLES[*]} " in
  *" $role "*) ;;
  *) echo "error: unknown role '$role'" >&2; usage ;;
esac

[ -n "$message" ] || { echo "error: empty commit message" >&2; usage; }

# Split the remaining args into: git passthrough args, an --all-staged opt-out,
# and the pathspecs after `--`. Everything after the first `--` is a path, which
# is git's own convention, so callers need no new mental model.
git_args=()
paths=()
all_staged=0
stage=0
seen_dashdash=0
for arg in "$@"; do
  if [ "$seen_dashdash" -eq 1 ]; then
    paths+=("$arg")
  elif [ "$arg" = "--" ]; then
    seen_dashdash=1
  elif [ "$arg" = "--all-staged" ]; then
    all_staged=1
  elif [ "$arg" = "--stage" ]; then
    stage=1
  else
    git_args+=("$arg")
  fi
done

if [ "$seen_dashdash" -eq 1 ] && [ "${#paths[@]}" -eq 0 ]; then
  echo "error: '--' given with no paths after it" >&2
  usage
fi

if [ "$all_staged" -eq 1 ] && [ "${#paths[@]}" -gt 0 ]; then
  echo "error: pass either --all-staged or '-- <path>...', not both" >&2
  usage
fi

if [ "$stage" -eq 1 ] && [ "$all_staged" -eq 1 ]; then
  echo "error: --stage stages the paths it is given, so there is nothing for it to do" >&2
  echo "       with --all-staged. Pass '--stage -- <path>...' or --all-staged, not both." >&2
  usage
fi

if [ "$stage" -eq 1 ] && [ "${#paths[@]}" -eq 0 ]; then
  echo "error: --stage needs the paths to stage: '--stage -- <path>...'" >&2
  usage
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# From a worktree this would commit into the TARGET repo under the role's name.
if [ -z "$repo_root" ] || [ ! -f "$repo_root/instance.config.json" ]; then
  echo "error: ${repo_root:-$PWD} is not a bundle (no instance.config.json at its toplevel)." >&2
  echo "       cd into the bundle first; commit-as.sh commits there and nowhere else." >&2
  exit 2
fi
for rb in rebase-merge rebase-apply; do
  if [ -d "$(git rev-parse --git-path "$rb")" ]; then
    echo "error: a rebase is in progress in $repo_root — not committing into it." >&2
    echo "       Retry once on your next write, or before your final message; then leave it." >&2
    exit 2
  fi
done

# Resolve the author email (see header for the order and the reasoning).
TRACKED_CONFIG="$repo_root/instance.config.json"
LOCAL_CONFIG="$repo_root/instance.config.local.json"

# Portable extraction of a JSON string value (no jq dependency).
json_string() { # <file> <key>
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
}

# people[<login>] from the TRACKED config. Handles both the pretty-printed block form
# and the one-line form, and reads ONLY inside the `people` object — a same-named key
# elsewhere in the file must not answer. awk, not sed: this is a nested object, and a
# line-wise regex over the whole file cannot tell inside from outside.
people_email() { # <login>
  [ -f "$TRACKED_CONFIG" ] || return 0
  awk -v who="$1" '
    BEGIN { want = "\"" who "\"" }
    {
      if (!inb) {
        i = index($0, "\"people\"")
        if (i == 0) next
        inb = 1
        $0 = substr($0, i + 8)
        i = index($0, "{")
        if (i == 0) next            # the opening brace is on a later line
        $0 = substr($0, i + 1)
      }
      e = index($0, "}")
      seg = (e ? substr($0, 1, e - 1) : $0)
      if (match(seg, want "[[:space:]]*:[[:space:]]*\"[^\"]*\"")) {
        m = substr(seg, RSTART, RLENGTH)
        sub(/^[^:]*:[[:space:]]*"/, "", m)
        sub(/"$/, "", m)
        print m; exit
      }
      if (e) exit                   # the object closed without naming this login
    }
  ' "$TRACKED_CONFIG"
}

config_email="$(json_string "$LOCAL_CONFIG" authorEmail)"

if [ -z "$config_email" ]; then
  # Who is this clone? Same resolution as task-owner.sh: local file, then tracked.
  who="$(json_string "$LOCAL_CONFIG" ownerGithubUser)"
  [ -n "$who" ] || who="$(json_string "$TRACKED_CONFIG" ownerGithubUser)"
  # Shape-check before using it in a regex: a GitHub login is 1-39 alphanumerics with
  # single hyphens only between them, so a value carrying regex metacharacters — or a
  # trailing/doubled hyphen — is not a login and must not be matched against the map.
  # Same rule as task-owner.sh's valid_user. Skipping the lookup falls through to the
  # next source; it is never an error.
  if [ ${#who} -le 39 ] && printf '%s' "$who" | grep -qE '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'; then
    config_email="$(people_email "$who")"
  fi
fi

[ -n "$config_email" ] || config_email="$(json_string "$TRACKED_CONFIG" authorEmail)"

AUTHOR_EMAIL="${CONTROL_PLANE_AUTHOR_EMAIL:-${config_email:-$(git config user.email || true)}}"
[ -n "$AUTHOR_EMAIL" ] || {
  echo "error: no author email. Either add \"authorEmail\" to instance.config.local.json" >&2
  echo "       (per-machine), add this clone's login to \"people\" in instance.config.json" >&2
  echo "       and \"ownerGithubUser\" to instance.config.local.json, set" >&2
  echo "       CONTROL_PLANE_AUTHOR_EMAIL, or run: git config user.email \"...\"" >&2
  exit 2
}

# Shared-index guard: an agent must say WHAT it is committing.
#
# Instances are worked by several concurrent agents against one clone, so the git
# index is shared mutable state. `git add -A` (or any commit of "whatever is
# staged") absorbs a sibling agent's in-progress files and commits them under the
# wrong author — silently, since the result looks like a normal commit. The fix is
# to commit pathspecs: `git commit -- <paths>` touches only those and leaves the
# rest of the index alone.
#
# `human` is exempt (a person can inspect the index). Every other role must pass
# `-- <path>...` or explicitly opt out with `--all-staged`.
if [ "$role" != "human" ] && [ "${#paths[@]}" -eq 0 ] && [ "$all_staged" -eq 0 ]; then
  if ! staged_all="$(git diff --cached --name-only)"; then
    echo "error: could not list staged files (git diff failed) — refusing to commit" >&2
    exit 3
  fi
  echo "error: role '$role' must name the paths it is committing." >&2
  echo "       Several agents share this working tree, so committing the whole index" >&2
  echo "       can absorb another agent's staged files under your authorship." >&2
  echo >&2
  if [ -n "$staged_all" ]; then
    echo "       Currently staged:" >&2
    # Read line by line: paths may contain spaces, so word-splitting would lie
    # about which files are in the index.
    while IFS= read -r staged_entry; do
      [ -n "$staged_entry" ] || continue
      printf '         %s\n' "$staged_entry" >&2
    done <<EOF
$staged_all
EOF
    echo >&2
  fi
  echo "       Commit only your own paths:" >&2
  echo "         $(basename "$0") $role \"$message\" -- <path>..." >&2
  echo "       Or, if you have checked that the entire index is yours:" >&2
  echo "         $(basename "$0") $role \"$message\" --all-staged" >&2
  exit 4
fi

# The nothing-staged guard below judges the CALLER'S paths, so snapshot them before the
# knowledge/ route appends one of its own: an index rebuild that changes nothing must not
# refuse a commit over a path the caller never passed.
named_paths=(${paths[@]+"${paths[@]}"})

# The knowledge/ route (SCHEMA.md, "A mounted knowledge base"). Mounted, those paths
# belong to another repository and this script would commit NOTHING for them — silently,
# because the selected index is built from THIS repo's HEAD. So refuse by name. Not
# mounted, knowledge/ is the bundle's own folder and the derived index is regenerated
# here rather than hand-edited by whoever staged a Finding.
kb_paths=()
for p in ${paths[@]+"${paths[@]}"}; do
  case "$p" in knowledge|knowledge/*|./knowledge|./knowledge/*) kb_paths+=("$p") ;; esac
done
if [ "${#kb_paths[@]}" -gt 0 ]; then
  if [ -d "$repo_root/$AB_DIR/kb.git" ]; then
    echo "error: knowledge/ is a MOUNTED knowledge base — these paths are tracked in" >&2
    echo "       another repository, and committing them here would commit nothing:" >&2
    for p in "${kb_paths[@]}"; do printf '         %s\n' "$p" >&2; done
    echo "       The tick is the only KB writer. Use:" >&2
    ab_say_run "        " kb-sync.sh commit --role "$role" --message "\"$message\"" -- '<path>...' >&2
    exit 5
  fi
  kb_index="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)/build-kb-index.sh"
  if [ -x "$kb_index" ] && ( cd "$repo_root" && bash "$kb_index" >/dev/null 2>&1 ); then
    ( cd "$repo_root" && git add -- knowledge/index.md ) >/dev/null 2>&1 || true
    paths+=("knowledge/index.md")
  fi
fi

# Build the SELECTED INDEX: HEAD, plus exactly the staged entries for the named
# paths. This is deliberately NOT `git commit -- <paths>`, git's pathspec commit
# form, for two reasons:
#
#   1. That form commits the WORKING TREE content of each named path, ignoring what
#      was staged for it. A file edited after its `git add` would be committed
#      unreviewed, and the staged version silently overwritten.
#   2. The promotion guard below reads the index. If the commit took its content
#      from the working tree instead, the guard would judge a different blob than
#      the one that lands — a `status: draft` index passing the gate while a
#      `status: ready` working tree gets committed.
#
# One temporary index, used for BOTH the guard and the commit, closes both: what is
# validated is byte-for-byte what lands. The shared index is never written, so a
# sibling agent's staged work survives untouched.
selected_index=""
has_head=0
git rev-parse --verify -q HEAD >/dev/null 2>&1 && has_head=1

if [ "${#paths[@]}" -gt 0 ]; then
  # --stage does the caller's `git add -- <the named paths>` and nothing wider. It is
  # the one thing here that writes the SHARED index — exactly the two-step it replaces,
  # so a sibling's staged entries are untouched and a refusal below leaves these staged.
  # A path `git rm -r` already removed matches nothing, so `git add` would refuse it; it
  # is skipped only on evidence of a staged deletion against HEAD, so a typo still fails.
  to_add=()
  for p in "${paths[@]}"; do
    if [ "$stage" -eq 1 ] && [ "$has_head" -eq 1 ] && [ ! -e "$p" ] && [ ! -L "$p" ] \
       && [ -z "$(git ls-files -- "$p")" ] \
       && [ -n "$(git diff --cached --name-only --diff-filter=D -- "$p")" ]; then
      continue
    fi
    to_add+=("$p")
  done
  if [ "$stage" -eq 1 ] && [ "${#to_add[@]}" -gt 0 ] && ! git add -- "${to_add[@]}"; then
    echo "error: could not stage the named path(s) — refusing to commit as role" >&2
    echo "       '$role' (fail closed)." >&2
    exit 3
  fi

  selected_index="$(mktemp "${TMPDIR:-/tmp}/commit-as-index.XXXXXX")"
  trap 'rm -f "$selected_index"' EXIT

  # Seed from HEAD (empty on an unborn branch) so unselected paths keep the
  # committed state and no sibling's staged change can leak in.
  if [ "$has_head" -eq 1 ]; then seed=HEAD; else seed=--empty; fi
  if ! GIT_INDEX_FILE="$selected_index" git read-tree "$seed"; then
    echo "error: could not seed a temporary index from HEAD — refusing to commit" >&2
    exit 3
  fi

  # Copy the staged entries (exact blob + mode) for the named paths. Piped, not
  # captured: `git ls-files -z` output is NUL-separated and command substitution
  # drops NUL bytes, which would join paths containing spaces into one bad entry.
  if ! git ls-files --stage -z -- "${paths[@]}" \
       | GIT_INDEX_FILE="$selected_index" git update-index -z --index-info; then
    echo "error: could not copy the staged entries for the named paths — refusing" >&2
    echo "       to commit as role '$role' (fail closed)." >&2
    exit 3
  fi

  # A path staged for DELETION is absent from the index, so the copy above left
  # HEAD's version in place; drop those explicitly or the commit would keep the file.
  if [ "$has_head" -eq 1 ] \
     && ! git diff --cached --name-only -z --diff-filter=D -- "${paths[@]}" \
          | GIT_INDEX_FILE="$selected_index" git update-index -z --force-remove --stdin; then
    echo "error: could not stage the deletions for the named paths — refusing to" >&2
    echo "       commit as role '$role' (fail closed)." >&2
    exit 3
  fi

  # Nothing staged under the named paths. Say so plainly: git's own message would
  # describe the shared WORKING TREE ("nothing added to commit…"), which is both
  # confusing and wrong here — the usual cause is a forgotten `git add`.
  #
  # PER PATH, never over the pathspec as a whole: one staged path used to satisfy
  # the guard for all of them, so a commit naming three paths with one staged
  # succeeded while silently dropping the other two.
  allow_empty=0
  for arg in ${git_args[@]+"${git_args[@]}"}; do
    [ "$arg" = "--allow-empty" ] && allow_empty=1
  done
  unstaged=()
  if [ "$allow_empty" -eq 0 ] && [ "$has_head" -eq 1 ]; then
    for p in ${named_paths[@]+"${named_paths[@]}"}; do
      GIT_INDEX_FILE="$selected_index" git diff --cached --quiet HEAD -- "$p" \
        && unstaged+=("$p")
    done
  fi
  if [ "${#unstaged[@]}" -gt 0 ]; then
    echo "error: nothing staged under the named path(s):" >&2
    for p in "${unstaged[@]}"; do printf '         %s\n' "$p" >&2; done
    echo "       Stage your changes by explicit path first, then commit those same paths:" >&2
    echo "         git add -- <path>...   # never 'git add -A' in a shared instance" >&2
    echo "       Or in one command: $(basename "$0") $role \"$message\" --stage -- <path>..." >&2
    exit 4
  fi
fi

# Read the index the commit will actually use: the selected index when we built
# one, the shared index otherwise.
gitx() {
  if [ -n "$selected_index" ]; then
    GIT_INDEX_FILE="$selected_index" git "$@"
  else
    git "$@"
  fi
}

# Two-human-authority guard (SCHEMA.md): draft→ready is the human's gate.
#
# A project may DELEGATE that gate to the loop via `autonomy:` in its project.md —
# but only where the capability exists at all, which is what AUTONOMY.md is (see
# "Delegated authority" in SCHEMA.md). No AUTONOMY.md means no
# modes exist, so every `autonomy` value is inert and every agent-role promotion
# is a violation. Delegation also applies ONLY to `kind: build` tasks, because
# SCHEMA.md keeps research human-driven in every mode. So this guard is decided
# PER TASK from three inputs: the capability file's presence, the owning
# project's autonomy, and the task's own kind — rather than blocking every
# agent-role `status: ready` unconditionally, which contradicted the autonomy
# field and left fully-refined build drafts stranded at `draft`.
#
# Fails CLOSED: anything not clearly (capability present AND autonomy delegated
# AND kind build) is refused; an absent or unparseable field reads as `gated` /
# `unset`.
#
# THE MODE SET IS CLOSED, AND THIS GUARD MIRRORS IT. An earlier version cleared on
# any value that was not `gated`, reasoning that which mode delegates what is
# AUTONOMY.md's distinction — but AUTONOMY.md defines exactly ONE mode ("One mode,
# deliberately": `yolo`), so every other token is a typo or an invention, and
# clearing on it meant `autonomy: delegatedmode` delegated the human's gate to a
# word nothing defines (audit 2026-08-31, finding S2). Only `yolo` clears; adding a
# mode to AUTONOMY.md means adding it here in the same commit, the way a
# deny-baseline rule and its tests move together.
#
# AND THE DELEGATION MUST PRE-DATE THE COMMIT THAT USES IT. AUTONOMY.md: "No agent
# raises `autonomy`" — a rule that had no reader, so a commit could stage the
# `autonomy:` flip on project.md AND the `status: ready` on a task and clear the
# guard on the strength of its own escalation. So any staged change to the owning
# project.md's `autonomy:` line — a project.md born in this commit included —
# refuses the promotion: land the autonomy change first (that edit is the human's),
# promote in the next commit.
#
# WHERE THE CAPABILITY FILE IS LOOKED FOR is `resolve-autonomy.sh`'s question, not this
# script's: the bundle root first (a v1-era bundle's own file always wins), else an
# installed companion plugin from core's own marketplace. That is one lookup with one
# reader, so this guard and the loop cannot come to disagree about whether delegation
# exists. DEGRADE TOWARDS THE OLD BEHAVIOUR, NEVER PAST IT: a missing or unrunnable
# resolver falls back to the root-only check this line used to be, which is strictly
# narrower than the resolver — it can only ever refuse a promotion the resolver would
# have allowed, and never allow one it would have refused.
if [ "$role" != "human" ]; then
  delegation_possible=0
  # `|| true`: with `set -e`, a command substitution that fails takes the ASSIGNMENT's
  # status with it, so an unreadable script directory would abort the commit instead of
  # falling through to the root-only check below.
  autonomy_resolver="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)/resolve-autonomy.sh"
  if [ -x "$autonomy_resolver" ]; then
    "$autonomy_resolver" --bundle "$repo_root" >/dev/null 2>&1 && delegation_possible=1
  else
    [ -f "$repo_root/AUTONOMY.md" ] && delegation_possible=1
  fi
  violations=""
  # Enumerate staged files under projects/ ONCE. Fail CLOSED if git itself errors
  # (corrupt index, disk error): refuse rather than proceed with an empty list, which
  # would let a promotion through unchecked — the one spot that would otherwise fail open.
  # Read through the selected index (when one was built), so this judges exactly
  # what the commit will contain and nothing else: a sibling agent's staged
  # promotion is not this role's to answer for, and its own commit gets checked
  # when it runs. A promotion inside this role's own paths is still refused.
  if ! staged_list="$(gitx diff --cached --name-only -- projects)"; then
    echo "error: could not list staged files (git diff failed) — refusing to commit as" >&2
    echo "       role '$role' (fail closed). Fix the repo state and retry." >&2
    exit 3
  fi
  # Here-doc (not a pipe) so the loop body runs in THIS shell and $violations survives.
  while IFS= read -r staged_file; do
    [ -n "$staged_file" ] || continue

    # Only files whose staged diff ADDS a `status: ready` line.
    if ! gitx diff --cached -U0 -- "$staged_file" \
         | grep -qiE '^\+status:[[:space:]]*ready[[:space:]]*$'; then
      continue
    fi

    # Owning project slug from projects/<slug>/...
    slug="$(printf '%s\n' "$staged_file" | sed -n 's#^projects/\([^/][^/]*\)/.*#\1#p')"

    # Read autonomy from the blob the commit will contain, not the working tree —
    # same source as `kind` below, so the check is consistent with exactly what's
    # being committed (no working-tree/staged TOCTOU). Missing/unparseable → stays
    # `gated` (fail closed).
    autonomy="gated"
    if [ -n "$slug" ]; then
      parsed="$(gitx show ":projects/$slug/project.md" 2>/dev/null \
                | sed -n 's/^autonomy:[[:space:]]*\([A-Za-z][A-Za-z-]*\)[[:space:]]*$/\1/p' | head -n1)"
      [ -n "$parsed" ] && autonomy="$parsed"
    fi

    # Task kind read from the same blob — what is actually being committed.
    kind="$(gitx show ":$staged_file" 2>/dev/null \
            | sed -n 's/^kind:[[:space:]]*\([A-Za-z][A-Za-z-]*\)[[:space:]]*$/\1/p' | head -n1)"
    [ -n "$kind" ] || kind="unset"

    # Does THIS commit move the owning project's `autonomy:` line? Diff header lines
    # start `---`/`+++`, never `[+-]autonomy:`, so the grep cannot match them; a
    # brand-new project.md is all `+` lines and correctly reads as a move.
    autonomy_flip=0
    if [ -n "$slug" ] && gitx diff --cached -U0 -- "projects/$slug/project.md" 2>/dev/null \
         | grep -qiE '^[+-]autonomy:'; then
      autonomy_flip=1
    fi

    if [ "$delegation_possible" -eq 1 ] && [ "$autonomy" = "yolo" ] \
       && [ "$kind" = "build" ] && [ "$autonomy_flip" -eq 0 ]; then
      continue
    fi

    violations="${violations}  - ${staged_file} (project '${slug:-?}': autonomy=${autonomy}, kind=${kind}$([ "$delegation_possible" -eq 1 ] || printf ', no AUTONOMY.md')$([ "$autonomy_flip" -eq 0 ] || printf ', autonomy edited in this same commit'))
"
  done <<EOF
$staged_list
EOF

  if [ -n "$violations" ]; then
    echo "error: role '$role' may not promote these tasks to 'ready':" >&2
    printf '%s' "$violations" >&2
    echo "       draft→ready is the human's authority ($AB_SCHEMA). The loop may promote a task" >&2
    echo "       only where AUTONOMY.md exists (no file = no delegated modes) — at this" >&2
    echo "       bundle's root, or from the yolo companion plugin — the owning" >&2
    echo "       project's 'autonomy' is exactly 'yolo' — the one mode AUTONOMY.md defines;" >&2
    echo "       any other value fails closed — the task is 'kind: build' (research stays" >&2
    echo "       human-driven), AND this commit does not itself edit that 'autonomy:' line:" >&2
    echo "       a promotion may not ride on an escalation it carries. Land the autonomy" >&2
    echo "       change first, promote in the next commit. If the human approved it," >&2
    echo "       commit as 'human'." >&2
    exit 3
  fi
fi

# 'human' commits under the person's configured git name; agents under the role.
if [ "$role" = "human" ]; then
  author_name="$(git config user.name)"
  [ -n "$author_name" ] || {
    echo "error: role 'human' needs git user.name set (git config user.name \"...\")" >&2
    exit 2
  }
else
  author_name="$role"
fi

# Commit the selected index when we built one — the same tree the guard above
# judged. The shared index is left alone, so any other staged change stays staged
# for its own author to commit. No `exec` here: the EXIT trap has to run to remove
# the temporary index.
if [ -n "$selected_index" ]; then
  GIT_INDEX_FILE="$selected_index" git \
    -c "user.name=$author_name" \
    -c "user.email=$AUTHOR_EMAIL" \
    commit --author="$author_name <$AUTHOR_EMAIL>" -m "$message" \
    ${git_args[@]+"${git_args[@]}"}
else
  exec git \
    -c "user.name=$author_name" \
    -c "user.email=$AUTHOR_EMAIL" \
    commit --author="$author_name <$AUTHOR_EMAIL>" -m "$message" \
    ${git_args[@]+"${git_args[@]}"}
fi
