#!/usr/bin/env bash
#
# deny-destructive.sh — PreToolUse hook (loopd PLUGIN). The destructive-action
# deny baseline: the layer an agent cannot talk past.
#
# WHY THIS EXISTS. `permissions.deny` was empty in every live instance while agents ran
# unattended against real credentials. A prose rule ("don't touch the production
# database") is a request an agent may decline; this refuses the tool call before it
# runs, in the harness, the same category as branch protection.
#
# ------------------------------------------------- WHY A HOOK AND NOT `permissions.deny`
# `permissions.deny` matches a command PREFIX. Every shape actually worth denying is
# CONDITIONAL on something a prefix cannot see:
#
#   · `DROP TABLE` matters against a remote host and is routine against a test container;
#   · `kubectl delete pod` is routine, `kubectl delete namespace` is not;
#   · `rm -rf node_modules` is routine, `rm -rf <repo root>` is not — and which is which
#     depends on the session's cwd;
#   · `git push --force` to a feature branch is routine, to the default branch it is not.
#
# Written as prefixes, each of those is either too broad (and gets deleted, which is the
# failure mode of every over-strict lint — a baseline nobody keeps protects nothing) or
# too narrow (and is FALSE COMFORT, which is worse than nothing). A hook sees the whole
# command, the cwd and the repo, so each rule can be narrow enough to keep. It is also
# the only form that can be PROVEN: `tests/deny-baseline.test.sh` feeds this script real
# payloads and asserts both directions per rule.
#
# `settings.json` keeps a short `permissions.deny` block for the handful of shapes that
# ARE unconditional. Those are a redundant second layer, deliberately duplicated by rules
# here; nothing depends on them. See docs/conventions.md §19.
#
# ------------------------------------------------------------------- HOW TO ADD A RULE
# Three edits, no new mechanism:
#   1. write `rule_<name>()` below — print the reason to stdout and `return 0` to DENY,
#      `return 1` to allow. It is handed the full command string;
#   2. add `<name>` to `RULES`;
#   3. add BOTH directions to `tests/deny-baseline.test.sh` — the shape it denies AND a
#      neighbouring legitimate command it must still allow. A rule with only the refusal
#      half would pass while denying everything.
# Rules run in order and the first denial wins, so ordering only affects which reason the
# agent is shown.
#
# --------------------------------------------------------------- THE ESCAPE HATCH IS REAL
# Every rule here can be satisfied by a human running the command in their own terminal,
# outside the harness. That is deliberate: it means no rule has to be widened for a
# legitimate emergency, so no instance has a reason to switch the baseline off. The deny
# message says so, and tells the agent NOT to re-issue a variant that evades the pattern.
#
# --------------------------------------------------------------------- FAIL OPEN, LOUD
# This sits in front of every Bash call in every session, so an infrastructure failure —
# no `jq`, an unparseable payload — logs to stderr and lets the call through. A guard
# that blocks all work because its own plumbing broke is a guard that gets removed. A
# rule that MATCHES always denies; only the plumbing fails open. `set -e` is deliberately
# not used, for the same reason as agent-control.sh: an unexpected non-zero would surface
# as a "non-blocking error" on every tool call.
#
# A refusal is JSON on STDOUT. This script's only exit status is 0 — exit 2 would also
# block, but it routes the reason through stderr where it is mixed with noise.
#
# ------------------------------------------------------------------------ WHAT IT IS NOT
# Pattern matching over a command string. It stops the named shapes, not every route to
# the same outcome: a path built from a variable, SQL read from a file, a wrapper script,
# a language runtime. Paths and branches are judged against the payload's `cwd`, so a `cd`
# earlier in the same command — or a `git -C <elsewhere>` — is not followed; the
# force-push rule still covers the common branch names in that case, and the `rm` rule may
# read a relative path against the wrong directory. It raises the floor.
# THE REAL BOUNDARY IS CREDENTIALS — an agent
# that cannot reach production cannot harm it whatever it decides. This is not a
# substitute for that audit.
set -uo pipefail

# --------------------------------------------------------------- the instance-root guard
# THIS BLOCK IS IDENTICAL IN agent-control.sh — keep them the same. It ships as a PLUGIN
# hook now, so it fires in EVERY session on the machine, not only in a bundle. Three
# things it must hold, each one load-bearing:
#
#   1. CLAUDE_PROJECT_DIR, NEVER the payload's `cwd`. A dispatched agent works inside a
#      worktree of a TARGET repo, so `cwd` is not the instance root. `agent-control.sh`
#      has carried that reasoning since it was an instance hook; it is now load-bearing
#      for this baseline too, and it is what `subagent_push_default` reads below.
#   2. ONE MARKER, and it is `instance.config.json`. `agent-control.sh`'s old guard also
#      tested `SCHEMA.md` and `.claude/agents/`; the third is dropped deliberately,
#      because `.claude/agents/` is a machinery path this very migration retires, so
#      keying on it would make the guard fail exactly when the plugin finishes replacing
#      the symlink farm.
#   3. SILENCE IS THE REQUIREMENT, not merely the behaviour. No stdout, no stderr, no
#      state, exit 0 — before the payload is even read. A line per skipped call would be
#      noise in every unrelated project on this machine.
#   4. A LINKED WORKTREE OF A LINKED REPO IS INSIDE THE INSTANCE. Point 1 was written when
#      a role agent was a subagent of the PM's session, whose project dir WAS the bundle.
#      Since role agents became detached sessions (`cd <worktree> && claude --bg …`,
#      step-3) CLAUDE_PROJECT_DIR is the worktree itself — no instance.config.json there —
#      and this guard exited 0 for every one of them. Measured live 2026-10-04: a `--bg`
#      agent force-pushed a default branch with this hook firing and allowing. The way
#      back is the marker `link-repos.sh` writes into each linked repo's
#      `.git/loopd-bundle` — the common git dir every worktree of that repo shares — so a
#      re-stamp arms existing bundles and no step has to remember anything. `.git` is a
#      FILE only in a linked worktree, which keeps a human's main clone un-armed, and the
#      walk is three reads with builtins, no git process. A marker naming a directory
#      with no instance.config.json is ignored: "absent ⇒ silent" still holds.
INSTANCE_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INSTANCE_ROOT="$(cd "$INSTANCE_ROOT" 2>/dev/null && pwd -P || printf '%s' "$INSTANCE_ROOT")"
if [ ! -f "$INSTANCE_ROOT/instance.config.json" ] && [ -f "$INSTANCE_ROOT/.git" ]; then
  _gd=""; IFS= read -r _gd < "$INSTANCE_ROOT/.git" 2>/dev/null || _gd=""
  _gd="${_gd#gitdir:}"; _gd="${_gd# }"
  case "$_gd" in ""|/*) ;; *) _gd="$INSTANCE_ROOT/$_gd" ;; esac
  _cd="$_gd"
  if [ -n "$_gd" ] && [ -f "$_gd/commondir" ]; then
    _c=""; IFS= read -r _c < "$_gd/commondir" 2>/dev/null || _c=""
    case "$_c" in "") ;; /*) _cd="$_c" ;; *) _cd="$_gd/$_c" ;; esac
  fi
  if [ -n "$_cd" ] && [ -f "$_cd/loopd-bundle" ]; then
    _b=""; IFS= read -r _b < "$_cd/loopd-bundle" 2>/dev/null || _b=""
    if [ -n "$_b" ] && [ -f "$_b/instance.config.json" ]; then
      INSTANCE_ROOT="$(cd "$_b" 2>/dev/null && pwd -P || printf '%s' "$_b")"
    fi
  fi
  unset _gd _cd _c _b
fi
[ -f "$INSTANCE_ROOT/instance.config.json" ] || exit 0

# The layout resolver, from the plugin this hook ships in. Unreachable ⇒ fail OPEN, the
# same direction the missing-jq branch below takes: a guard that cannot read the layout
# must not start denying by accident.
_self="${BASH_SOURCE[0]:-$0}"; case "$_self" in /*) ;; *) _self="$PWD/$_self" ;; esac
[ -L "$_self" ] && _self="$(readlink "$_self" 2>/dev/null || printf '%s' "$_self")"
# shellcheck source=../scripts/bundle-paths.sh
. "${CLAUDE_PLUGIN_ROOT:-${_self%/hooks/*}}/scripts/bundle-paths.sh" 2>/dev/null || exit 0

# ------------------------------------------------------------------------------- payload
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# jq, hard, for the same reason agent-control.sh requires it: `tool_input` is arbitrary
# nested JSON and a grep/sed parser can be fooled by a command that CONTAINS the keys it
# looks for. Absent ⇒ log and fail open.
if ! command -v jq >/dev/null 2>&1; then
  echo "deny-destructive: jq not found — destructive-action baseline is NOT enforced in this session" >&2
  exit 0
fi

tool="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

CMD="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

# `agent_id` and `agent_type` are present on a DISPATCHED subagent's PreToolUse event and
# ABSENT on the parent session's own tool call (measured 2026-08-23; see agent-control.sh's
# WHY agent_id). Most rules below are command-shape rules that apply to every session; the
# session-scoped ones read these two and say so in their own header — `subagent_push_default`
# and `subagent_merge`'s APPROVAL half fire only for a dispatched agent,
# `launcher_diagnoses_nothing` only for the main thread, and `subagent_merge`'s MERGE half
# for every caller in a bundle session, reading `agent_type` as the role rather than as a
# presence test.
AGENT_ID="$(printf '%s' "$payload" | jq -r '.agent_id // ""' 2>/dev/null || true)"
AGENT_TYPE="$(printf '%s' "$payload" | jq -r '.agent_type // ""' 2>/dev/null || true)"

CWD="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
# PHYSICAL, IMMEDIATELY. `git rev-parse --show-toplevel` always answers with symlinks
# resolved, so a session whose cwd is reported through a symlink (on macOS every path under
# `mktemp -d` is: `/var/...` vs `/private/var/...`) would compare a lexical path against a
# resolved one and MISS. This trap has bitten this codebase repeatedly — see
# .claude/rules/tests.md, "Compare resolved paths".
CWD="$(cd "$CWD" 2>/dev/null && pwd -P || printf '%s' "$CWD")"

# ------------------------------------------------------------------------------ plumbing
# bash 3.2 is the floor (macOS ships it, and CI runs macOS): no associative arrays, no
# `${v,,}`, no `mapfile`.
SEP="$(printf '\001')"

lower() { printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'; }

# One command per line. `&&`, `||`, `;` and newline end a command; `|` does NOT, so a
# pipeline stays one line here — the exfiltration rule needs `cat .env | curl …` intact.
segments() {
  local s="$1"
  s="${s//&&/$SEP}"
  s="${s//||/$SEP}"
  s="${s//;/$SEP}"
  s="${s//$'\n'/$SEP}"
  printf '%s' "$s" | tr "$SEP" '\n'
}

# One pipeline STAGE per line — segments split further on `|`. Command-oriented rules use
# this so `terraform destroy | tee log` is still seen as a `terraform` invocation.
stages() {
  local s="$1"
  s="${s//&&/$SEP}"
  s="${s//||/$SEP}"
  s="${s//;/$SEP}"
  s="${s//$'\n'/$SEP}"
  printf '%s' "$s" | tr "$SEP|" '\n\n'
}

# One token per line, surrounding quotes stripped. Redirections, subshell parens, backticks
# and PIPES become separators, so `$(cat .env)` yields `.env` as its own token and
# `cat .env|curl …` — no spaces — does not collapse into the single token `.env|curl`, which
# matched neither the secret list nor the sender list and let the exfiltration through.
# `stages()` already splits on `|` before it tokenises, so this only changes what the
# exfiltration rule sees, which is the one rule that tokenises a whole segment.
tokens_of() {
  printf '%s' "$1" \
    | tr '<>()`|' '      ' \
    | tr ' \t' '\n\n' \
    | sed -e 's/^["'"'"']*//' -e 's/["'"'"']*$//' \
    | grep -v '^[[:space:]]*$'
}

# The command word of a stage: the first token that is not an environment assignment, a
# flag, or a wrapper that takes another command as its argument.
first_word() {
  local w
  while IFS= read -r w; do
    case "$w" in
      [A-Za-z_]*=*) continue ;;
      env|sudo|nohup|time|command|exec|nice|ionice|stdbuf|xargs) continue ;;
      -*) continue ;;
      *) printf '%s' "${w##*/}"; return 0 ;;
    esac
  done <<EOF
$(tokens_of "$1")
EOF
  return 1
}

# Flags whose NEXT token is a value, not a subcommand or an operand. Skipping the flag
# alone was a silent false negative in both directions: `kubectl -n prod delete pvc x` read
# `prod` as the subcommand (so no rule fired at all), and `kubectl delete -n infra pvc x`
# read `infra` as the resource kind (so the irreversible-kind list never matched). Extend
# this list when you teach a rule a new tool.
VALUE_FLAGS="-n --namespace --context --kube-context --kubeconfig -f --filename -l --selector --field-selector -o --output --grace-period --timeout --as --cluster --user --server --token --chunk-size -h --host --hostname -p --port -U --username -d --dbname -c --command -e --execute -S --chdir --set --values --repo --version -var -var-file -state -out -target --match-head-commit --body-file --subject"

# The first non-flag token after <word>, skipping any flag's value. `kubectl delete` ⇒ the
# resource kind. Comparison is on the BASENAME, so `/usr/local/bin/kubectl` is `kubectl`.
word_after() { # <stage> <word>
  local w f seen=0 skipv=0
  while IFS= read -r w; do
    if [ "$seen" = 0 ]; then
      [ "${w##*/}" = "$2" ] && seen=1
      continue
    fi
    if [ "$skipv" = 1 ]; then skipv=0; continue; fi
    case "$w" in
      *=*) case "$w" in -*) continue ;; [A-Za-z_]*) continue ;; esac ;;
    esac
    case "$w" in
      -*) for f in $VALUE_FLAGS; do [ "$w" = "$f" ] && { skipv=1; break; }; done
          continue ;;
      *) printf '%s' "$w"; return 0 ;;
    esac
  done <<EOF
$(tokens_of "$1")
EOF
  return 1
}

has_token() { # <stage> <token>
  local w
  while IFS= read -r w; do
    [ "$w" = "$2" ] && return 0
  done <<EOF
$(tokens_of "$1")
EOF
  return 1
}

# The value of `-x val` / `--flag val` / `--flag=val`.
flag_value() { # <stage> <flag> [flag...]
  local stage="$1"; shift
  local w f want=0
  while IFS= read -r w; do
    if [ "$want" = 1 ]; then printf '%s' "$w"; return 0; fi
    for f in "$@"; do
      case "$w" in
        "$f") want=1; break ;;
        "$f"=*) printf '%s' "${w#*=}"; return 0 ;;
      esac
    done
  done <<EOF
$(tokens_of "$stage")
EOF
  return 1
}

# A generic naming convention, not an org literal: `prod` / `production` / `prd` / `live`
# as a whole dash/underscore/dot-delimited token. Substring matching would fire on
# `reproduce` and on `alive`.
looks_production() { # <string>
  local s; s="$(lower "$1")"
  case "$s" in
    prod|production|prd|live) return 0 ;;
    *[-_.]prod|*[-_.]production|*[-_.]prd|*[-_.]live) return 0 ;;
    prod[-_.]*|production[-_.]*|prd[-_.]*|live[-_.]*) return 0 ;;
    *[-_.]prod[-_.]*|*[-_.]production[-_.]*|*[-_.]prd[-_.]*|*[-_.]live[-_.]*) return 0 ;;
  esac
  return 1
}

# `git` is consulted at most once per rule that needs it, and only when that rule has
# already matched a command shape — a hook in front of every Bash call must not pay for
# two subprocesses it will not use.
_repo_root=""; _repo_root_done=0
repo_root() {
  if [ "$_repo_root_done" = 0 ]; then
    _repo_root_done=1
    _repo_root="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  printf '%s' "$_repo_root"
}

_default_branch=""; _default_branch_done=0
default_branch() {
  if [ "$_default_branch_done" = 0 ]; then
    _default_branch_done=1
    _default_branch="$(git -C "$CWD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    _default_branch="${_default_branch#*/}"
  fi
  printf '%s' "$_default_branch"
}

# Is the SESSION's cwd a control-panel instance root? The `$AB_SCHEMA` +
# `instance.config.json` pair `skills/dispatch/SKILL.md` precondition 1 checks —
# deliberately the payload's `cwd` and NOT `$INSTANCE_ROOT`, which is `$CLAUDE_PROJECT_DIR`
# and stays the bundle even for an agent whose cwd is a worktree. It stays a PAIR rather
# than becoming the hook's own one-marker guard above: a target repo that happens to hold
# an `instance.config.json` would otherwise arm this rule inside it.
# Cached: it is two stats in front of every Bash call.
_cwd_instance=""
cwd_is_instance_root() {
  if [ -z "$_cwd_instance" ]; then
    if [ -f "$CWD/instance.config.json" ] && [ -f "$CWD/$AB_SCHEMA" ]; then _cwd_instance=yes
    else _cwd_instance=no; fi
  fi
  [ "$_cwd_instance" = yes ]
}

# Lexical, not `realpath`: the target of an `rm -rf` may not exist, and resolving symlinks
# is not wanted here — `rm -rf <symlink-to-repo>` is a different command.
norm_path() { # <path>
  local p="$1" out="" part oldopts
  # A LITERAL TILDE IS THE INPUT HERE, not something to expand: the agent's command text
  # contains `~` unexpanded, and this is what resolves it.
  # shellcheck disable=SC2088  # case PATTERNS, matching a tilde in data — not a path to expand
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME/$HOME}"
  case "$p" in /*) ;; *) p="$CWD/$p" ;; esac
  oldopts="$(set +o | grep noglob)"
  set -f
  local IFS=/
  for part in $p; do
    case "$part" in
      ""|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  eval "$oldopts"
  printf '%s' "${out:-/}"
}

# The physical form of a path — symlinks resolved — for the comparison above. Falls back to
# the input when nothing on the path exists, which is the right answer for a target that is
# already gone.
phys() { # <path>
  local d b r
  if [ -d "$1" ]; then
    r="$(cd "$1" 2>/dev/null && pwd -P)" && { printf '%s' "$r"; return 0; }
  fi
  b="${1##*/}"; d="${1%/*}"; [ -n "$d" ] || d="/"
  if [ "$d" != "$1" ] && [ -d "$d" ]; then
    r="$(cd "$d" 2>/dev/null && pwd -P)" && { printf '%s/%s' "${r%/}" "$b"; return 0; }
  fi
  printf '%s' "$1"
}

# 0 when <p> IS <x> or is an ancestor directory of <x>.
covers() { # <p> <x>
  [ -n "$1" ] && [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 0
  [ "$1" = "/" ] && return 0
  case "$2" in "$1"/*) return 0 ;; esac
  return 1
}

# =============================================================================== RULES ==
# Print the reason, `return 0` to DENY. See "HOW TO ADD A RULE" at the top.
#
# EACH RULE OPENS WITH A ONE-LINE `case` PRE-FILTER, and it must be a SUPERSET of what the
# rule can possibly match — it is an optimisation, never a condition. This hook runs in
# front of every Bash call in every session, and the tokenising below costs several
# subprocesses per stage per rule; without the pre-filter an ordinary `npm ci && npm test`
# paid ~160 ms for seven rules that could not have fired. With it, a command naming none of
# the tools falls through in microseconds. Narrowing one of these silently disables part of
# a rule, so derive it from the rule body, and note that the deny half of that rule's tests
# is what proves the filter still lets the real shapes through.
RULES="terraform_destroy k8s_irreversible_delete k8s_production_target sql_destructive_remote rm_rf_repo_root force_push_protected secret_exfiltration subagent_merge subagent_push_default launcher_diagnoses_nothing"

# --- terraform_destroy --------------------------------------------------------------- #
# JUSTIFIED BY: `destroy` deletes real infrastructure and there is no legitimate agent
# task that needs it unattended. NARROW ENOUGH TO KEEP: `terraform plan -destroy` — the
# read-only "what would this remove?" query, which is the thing an agent actually needs —
# is explicitly allowed, as is every other terraform subcommand including `apply`.
rule_terraform_destroy() {
  case "$1" in *destroy*) ;; *) return 1 ;; esac
  local stage c sub
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in terraform|tofu|terragrunt) ;; *) continue ;; esac
    sub="$(word_after "$stage" "$c" || true)"
    [ "$sub" = "plan" ] && continue
    if has_token "$stage" destroy || has_token "$stage" -destroy || has_token "$stage" --destroy; then
      printf '`%s destroy` (or `apply -destroy`) tears down real infrastructure, and a plan file is not consulted here. `%s plan -destroy` answers the same question without acting and is allowed.' "$c" "$c"
      return 0
    fi
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- k8s_irreversible_delete --------------------------------------------------------- #
# JUSTIFIED BY: these kinds cannot be recreated from the cluster. A namespace delete
# cascades to everything in it; a PV/PVC delete destroys data; a CRD delete destroys every
# custom resource of that type; a node delete evicts a machine. `--all` turns any of them
# into a sweep. NARROW ENOUGH TO KEEP: the routine deletes — pod, job, deployment,
# configmap, secret, ingress, `-f manifest.yaml` — are all still allowed, in any namespace.
rule_k8s_irreversible_delete() {
  case "$1" in *delete*) ;; *) return 1 ;; esac
  local stage c sub kind k
  local irreversible="namespace namespaces ns persistentvolume persistentvolumes pv persistentvolumeclaim persistentvolumeclaims pvc customresourcedefinition customresourcedefinitions crd crds node nodes"
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in kubectl|oc) ;; *) continue ;; esac
    sub="$(word_after "$stage" "$c" || true)"
    [ "$sub" = "delete" ] || continue
    if has_token "$stage" --all || has_token "$stage" --all-namespaces || has_token "$stage" -A; then
      printf '`%s delete --all` deletes every matching object in scope at once. Name the objects you mean, or hand this to the human.' "$c"
      return 0
    fi
    kind="$(word_after "$stage" delete || true)"
    kind="$(lower "${kind%%/*}")"
    for k in $irreversible; do
      if [ "$kind" = "$k" ]; then
        printf 'Deleting a `%s` is not recoverable from the cluster — it cascades to the objects (or the data) it owns. Routine deletes (pod, job, deployment, configmap, `-f manifest.yaml`) are still allowed.' "$kind"
        return 0
      fi
    done
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- k8s_production_target ----------------------------------------------------------- #
# JUSTIFIED BY: the namespace or context is the only production signal available in the
# command itself. NARROW ENOUGH TO KEEP: only DESTRUCTIVE verbs are covered (`delete`,
# `drain`, `helm uninstall`) — `get`, `logs`, `describe`, `apply`, `helm upgrade` against
# production are untouched, so reading and deploying still work. The `dev` half of the
# task's "outside a dev namespace" wording is deliberately NOT implemented as
# "deny unless namespace == dev": namespace naming is per-org, and a deny-unless list
# would refuse every routine delete in a namespace whose name this file cannot know.
rule_k8s_production_target() {
  case "$1" in *delete*|*drain*|*uninstall*) ;; *) return 1 ;; esac
  local stage c sub ns ctx target
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in kubectl|oc|helm) ;; *) continue ;; esac
    sub="$(word_after "$stage" "$c" || true)"
    case "$c:$sub" in
      kubectl:delete|kubectl:drain|oc:delete|oc:drain|helm:uninstall|helm:delete) ;;
      *) continue ;;
    esac
    ns="$(flag_value "$stage" -n --namespace || true)"
    ctx="$(flag_value "$stage" --context --kube-context || true)"
    target=""
    looks_production "$ns" && target="namespace \`$ns\`"
    [ -z "$target" ] && looks_production "$ctx" && target="context \`$ctx\`"
    if [ -n "$target" ]; then
      printf '`%s %s` against %s. Read-only verbs and `apply`/`upgrade` against the same target are still allowed; a destructive one belongs to a human at a terminal.' "$c" "$sub" "$target"
      return 0
    fi
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- sql_destructive_remote ---------------------------------------------------------- #
# JUSTIFIED BY: this is the shape the owner named. NARROW ENOUGH TO KEEP: a LOCAL client
# call is untouched, which is where an agent's legitimate database work happens — a test
# container reached over the default unix socket, or explicitly on `localhost`. Only a
# non-local target is refused.
#
# AN UNRESOLVABLE TARGET COUNTS AS NON-LOCAL. `psql "$DATABASE_URL" -c 'DROP TABLE …'` is
# exactly the command that reaches production from a session holding live credentials, and
# reading the variable to find out is not available here. The reason names the fix
# (`-h localhost`) for the case where it really was local.
rule_sql_destructive_remote() {
  case "$1" in *psql*|*mysql*|*mariadb*|*mongo*|*clickhouse*|*cockroach*|*sqlcmd*) ;; *) return 1 ;; esac
  local stage c verb host w unresolved seen
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in psql|mysql|mariadb|mongosh|mongo|clickhouse-client|cockroach|sqlcmd) ;; *) continue ;; esac

    verb=""
    case "$(printf '%s' "$stage" | tr '\n\t' '  ' | tr -s ' ' | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" in
      *"drop database"*) verb="DROP DATABASE" ;;
      *"drop table"*)    verb="DROP TABLE" ;;
      *"drop schema"*)   verb="DROP SCHEMA" ;;
      *truncate*)        verb="TRUNCATE" ;;
    esac
    [ -n "$verb" ] || continue

    # A connection target that is a shell variable cannot be judged.
    unresolved=0; seen=0
    while IFS= read -r w; do
      # BASENAME, matching what first_word returned: `/usr/bin/psql` is `psql`, and a
      # literal comparison here would never find the command word and skip every operand.
      if [ "$seen" = 0 ]; then [ "${w##*/}" = "$c" ] && seen=1; continue; fi
      case "$w" in *'$'*|*'`'*) unresolved=1; break ;; esac
    done <<EOT
$(tokens_of "$stage")
EOT

    host=""
    while IFS= read -r w; do
      # `--url=postgres://…` / `--uri=…` / `--dsn=…` carry the same target as a bare URI and
      # would otherwise slip past the scheme glob below, which is a FALSE NEGATIVE — the one
      # outcome this baseline must not produce.
      case "$w" in --*=*://*) w="${w#*=}" ;; esac
      case "$w" in
        postgres://*|postgresql://*|mysql://*|mongodb://*|mongodb+srv://*|clickhouse://*)
          host="${w#*://}"; host="${host##*@}"; host="${host%%/*}"; host="${host%%\?*}"; host="${host%%:*}"
          break ;;
      esac
    done <<EOT
$(tokens_of "$stage")
EOT
    [ -n "$host" ] || host="$(flag_value "$stage" -h --host --hostname || true)"
    [ -n "$host" ] || host="$(flag_value "$stage" PGHOST MYSQL_HOST MYSQL_TCP_ADDR || true)"
    # SCOPED TO sqlcmd ON PURPOSE. `-S` names the server there, but it is `--single-line`
    # (no argument) to psql and a socket PATH to mysql, so reading it unconditionally would
    # take psql's next flag for a hostname and refuse a local command.
    if [ -z "$host" ] && [ "$c" = sqlcmd ]; then host="$(flag_value "$stage" -S --server || true)"; fi

    if [ -z "$host" ] && [ "$unresolved" = 0 ]; then
      continue   # no host named and nothing hidden ⇒ local socket ⇒ allowed
    fi
    case "$(lower "$host")" in
      localhost|127.0.0.1|0.0.0.0|::1|host.docker.internal|*.localhost|/*) continue ;;
      127.*) continue ;;
    esac

    if [ "$unresolved" = 1 ] && [ -z "$host" ]; then
      printf '`%s` with `%s` and a connection target this guard cannot read (it comes from a variable). A session holding live credentials reaches production exactly this way. If the target really is local, say so — `-h localhost` — and this is allowed.' "$c" "$verb"
    else
      printf '`%s` against the non-local host `%s`. Destructive DDL on a remote database is not something an agent should issue; run it yourself, at a terminal, if it is right. Local targets (`-h localhost`, or the default socket) are allowed.' "$verb" "$host"
    fi
    return 0
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- rm_rf_repo_root ----------------------------------------------------------------- #
# JUSTIFIED BY: a recursive delete at or above the working tree destroys uncommitted and
# unpushed work, and above the repo it takes sibling clones and worktrees with it.
# NARROW ENOUGH TO KEEP: everything BELOW the repo root is allowed — `rm -rf node_modules`,
# `rm -rf dist`, `rm -rf .pnpm-store` — and so is any path outside the repo that is not at
# or above `$HOME`, which keeps every `rm -rf "$TMP"` fixture cleanup working.
#
# A PATH BUILT FROM A VARIABLE IS ALLOWED, not denied: `rm -rf "$TMP"` is the single most
# common legitimate recursive delete in this codebase, and denying what it cannot resolve
# would make this the rule an instance switches the baseline off to escape. `$HOME` and
# `~` are the two it does resolve.
rule_rm_rf_repo_root() {
  case "$1" in *rm*) ;; *) return 1 ;; esac
  local stage c w recursive seen op p root
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    [ "$c" = "rm" ] || continue

    recursive=0
    while IFS= read -r w; do
      case "$w" in
        --recursive) recursive=1 ;;
        --*) ;;
        -*[rR]*) recursive=1 ;;
      esac
    done <<EOT
$(tokens_of "$stage")
EOT
    [ "$recursive" = 1 ] || continue

    root="$(repo_root)"
    seen=0
    while IFS= read -r w; do
      # BASENAME: `/bin/rm -rf /` passed first_word and then matched no token here, so
      # every operand was skipped and the command was allowed.
      if [ "$seen" = 0 ]; then [ "${w##*/}" = "rm" ] && seen=1; continue; fi
      case "$w" in -*) continue ;; esac
      op="$w"
      case "$op" in *'$'*|*'`'*) continue ;; esac
      # A trailing glob means "everything in the parent", so judge the parent.
      case "$op" in
        */\*) op="${op%/\*}" ;;
        \*) op="." ;;
        *\*) continue ;;
      esac
      p="$(phys "$(norm_path "$op")")"
      if [ "$p" = "/" ]; then
        printf '`rm -r /` — refused.'
        return 0
      fi
      if covers "$p" "$(phys "$HOME")"; then
        printf '`rm -r %s` is at or above your home directory.' "$p"
        return 0
      fi
      if [ -n "$root" ] && covers "$p" "$root"; then
        printf '`rm -r %s` is at or above the root of the working tree (`%s`) — it would take uncommitted and unpushed work, and anything alongside it. Deleting a path INSIDE the tree (build output, node_modules, a scratch dir) is allowed.' "$p" "$root"
        return 0
      fi
      # THE BUNDLE'S PLUGIN-OWNED DIRECTORY, AS A PREFIX — not a list of filenames, so a
      # file the layout gains later is covered the day it lands. A recursive delete at or
      # above it takes SCHEMA.md, CONVENTIONS.md, the tick ledger and the roster together.
      # Deleting ONE derived file inside it stays allowed: the seed .gitignore tells a
      # human to do exactly that to turn the queue or the board off.
      if covers "$p" "$(phys "$INSTANCE_ROOT/$AB_DIR")"; then
        printf '`rm -r %s` is at or above `%s`, the bundle'"'"'s plugin-owned directory — it would take SCHEMA.md, CONVENTIONS.md, the tick ledger and the roster with it. Deleting one derived file inside it (the awaiting queue, the board cache) is allowed.' "$p" "$AB_DIR"
        return 0
      fi
    done <<EOT
$(tokens_of "$stage")
EOT
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- force_push_protected ------------------------------------------------------------ #
# JUSTIFIED BY: a force-push or a delete of the default branch discards commits on the one
# ref nothing else can reconstruct, and every role agent in this bundle pushes for a
# living. NARROW ENOUGH TO KEEP: force-pushing a FEATURE branch is normal work after a
# rebase and stays allowed, as does every non-force push, including to the default branch
# (this control panel commits straight to it by design).
rule_force_push_protected() {
  case "$1" in *push*) ;; *) return 1 ;; esac
  local stage c w seen sub skipnext force del args remote r d dst p protected oldopts
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    [ "$c" = "git" ] || continue

    seen=0; sub=""; skipnext=0; force=0; del=0; args=""
    while IFS= read -r w; do
      if [ "$skipnext" = 1 ]; then skipnext=0; continue; fi
      if [ "$seen" = 0 ]; then [ "${w##*/}" = "git" ] && seen=1; continue; fi
      if [ -z "$sub" ]; then
        case "$w" in
          -C|-c|--git-dir|--work-tree|--namespace|--exec-path) skipnext=1; continue ;;
          -*) continue ;;
          *) sub="$w"; continue ;;
        esac
      fi
      case "$w" in
        --force|--force-with-lease|--force-with-lease=*|--force-if-includes) force=1 ;;
        --delete) del=1 ;;
        --*) ;;
        -*) case "$w" in *f*) force=1 ;; esac
            case "$w" in *d*) del=1 ;; esac ;;
        *) args="$args $w" ;;
      esac
    done <<EOT
$(tokens_of "$stage")
EOT
    [ "$sub" = "push" ] || continue

    # First positional is the remote; the rest are refspecs.
    oldopts="$(set +o | grep noglob)"; set -f
    # shellcheck disable=SC2086  # deliberate split; globbing is off for the duration
    set -- $args
    eval "$oldopts"
    remote="${1:-}"; [ "$#" -gt 0 ] && shift

    dst=""
    if [ "$#" -eq 0 ]; then
      d="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      [ "$d" = "HEAD" ] && d=""
      dst="$d"
    else
      for r in "$@"; do
        case "$r" in +*) force=1; r="${r#+}" ;; esac
        case "$r" in :*) del=1 ;; esac
        case "$r" in *:*) r="${r##*:}" ;; esac
        r="${r#refs/heads/}"
        dst="$dst $r"
      done
    fi
    [ -n "${dst// /}" ] || continue
    { [ "$force" = 1 ] || [ "$del" = 1 ]; } || continue

    protected="main master develop trunk production"
    d="$(default_branch)"
    [ -n "$d" ] && protected="$protected $d"
    for r in $dst; do
      for p in $protected; do
        if [ "$r" = "$p" ]; then
          if [ "$del" = 1 ]; then
            printf 'Deleting the protected branch `%s` on `%s`.' "$p" "${remote:-origin}"
          else
            printf 'Force-pushing to the protected branch `%s` on `%s` discards commits nothing else can reconstruct. Force-pushing a FEATURE branch is allowed, and so is a normal (non-force) push to `%s`.' "$p" "${remote:-origin}" "$p"
          fi
          return 0
        fi
      done
    done
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- secret_exfiltration ------------------------------------------------------------- #
# JUSTIFIED BY: this is the one shape where a single command turns a credential the agent
# can legitimately read into a credential someone else holds, and it is irreversible the
# moment it succeeds. NARROW ENOUGH TO KEEP: BOTH halves must be present IN THE SAME
# PIPELINE — reading a `.env` is allowed, and so is any network call. A `&&` chain is two
# commands, not one, so `grep KEY .env && curl …/health` is untouched.
#
# Three carve-outs kill the realistic false positives: `.env.example`/`.sample`/`.template`
# are not secrets; a path that is the operand of `-o`/`--output` is a DOWNLOAD, not an
# upload; and a local target (localhost/127.0.0.1) is not exfiltration.
rule_secret_exfiltration() {
  case "$1" in *env*|*id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*|*.pem*|*.p12*|*.pfx*|*npmrc*|*netrc*|*pgpass*|*credentials*|*kubeconfig*|*.ssh*|*service-account*) ;; *) return 1 ;; esac
  local seg w prev sender secret
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue

    case "$seg" in
      *localhost*|*127.0.0.1*|*0.0.0.0*|*'::1'*|*host.docker.internal*) continue ;;
    esac

    sender=""
    while IFS= read -r w; do
      case "${w##*/}" in
        curl|wget|nc|ncat|netcat|socat|telnet|ssh|scp|sftp|rsync|http|httpie) sender="${w##*/}"; break ;;
      esac
    done <<EOT
$(tokens_of "$seg")
EOT
    [ -n "$sender" ] || continue

    secret=""; prev=""
    while IFS= read -r w; do
      # A KEY PRESENTED TO AUTHENTICATE IS NOT A KEY BEING SENT. `ssh -i ~/.ssh/id_ed25519
      # host` and `curl --cert client.pem …` are ordinary authenticated calls, and refusing
      # them would make this the rule that gets the baseline switched off. The operand of an
      # identity/certificate flag — and of `-o`, which is a DOWNLOAD — is skipped. A secret
      # in POSITIONAL position (`scp id_ed25519 host:/tmp/`) is still the payload, and is
      # still refused.
      case "$prev" in
        -o|--output|-O|--output-dir|--remote-name|-i|--identity-file|--cert|-E|--key|--cacert|--capath|--pubkey|--proxy-cert|--proxy-key)
          prev="$w"; continue ;;
      esac
      prev="$w"
      case "$w" in
        --cert=*|--key=*|--cacert=*|--capath=*|--identity-file=*|--pubkey=*|--proxy-cert=*|--proxy-key=*|--output=*) continue ;;
      esac
      w="${w#@}"
      case "$w" in
        *.env.example|*.env.sample|*.env.template|*.env.dist|*.env.example*) continue ;;
      esac
      case "$w" in
        .env|*/.env|*.env|.env.*|*/.env.*) secret="$w"; break ;;
        *id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*) secret="$w"; break ;;
        *.pem|*.p12|*.pfx) secret="$w"; break ;;
        .npmrc|*/.npmrc|.netrc|*/.netrc|.pgpass|*/.pgpass) secret="$w"; break ;;
        */.aws/credentials|*/.ssh/*|*kubeconfig*|*service-account*.json|*credentials.json) secret="$w"; break ;;
      esac
    done <<EOT
$(tokens_of "$seg")
EOT
    [ -n "$secret" ] || continue

    printf 'This pipeline reads `%s` and hands it to `%s` in the same command — that is credential exfiltration, and it cannot be undone once it lands. Reading the file is allowed, and so is the network call; only the two joined together are refused.' "$secret" "$sender"
    return 0
  done <<EOF
$(segments "$1")
EOF
  return 1
}

# --- subagent_merge ------------------------------------------------------------------ #
# JUSTIFIED BY: under `gated` — the default, fail-closed mode — the human owns the merge and
# the approval, and this is the one place a prose rule ("never merge") was the only thing
# stopping a dispatched agent from running `gh pr merge` itself. NARROW ENOUGH TO KEEP: only
# the three shapes that CONSUMMATE a merge or MANUFACTURE an approval are refused —
# `gh pr merge`, the REST merge endpoints via `gh api` (`.../pulls/N/merge`, `.../merges`),
# and `gh pr review --approve`. Everything else an agent does with `gh` is untouched: opening
# a PR, pushing a branch, `gh pr view`, `gh pr comment`, and `gh pr review --request-changes`
# (the review verbs `qa-reviewer.md` actually tells it to use).
#
# THE MERGE HALF IS NOT AGENT-SCOPED, and that is deliberate (ai-bridge-v3/task-044): a rule
# keyed on `agent_id` never fires for the MAIN thread, which is where task-035's headless
# tick runs the project-manager — so the mode, receipt and SHA checks would be skipped by
# exactly the caller they most need to bind. The approval half stays agent-scoped: an
# approval is the human's to give in their own session. The escape hatch is unchanged and is
# the one every rule here relies on — a human running the command in their own terminal.
#
# WHERE yolo FITS: the ONE permitted shape is the merge `AUTONOMY.md` tells the tick to run,
# `gh pr merge --squash --match-head-commit <sha>`, and `merge-permit.sh` decides it from the
# bundle — the owning project's mode, the caller's role and a clearance record at that exact
# SHA. Nothing in the command, the environment or the PR can assert any of that, and every
# unknown refuses.
GH_MERGE_VALUE_FLAGS="--match-head-commit --body --body-file --subject --author-email -R --repo"

# `<owner>/<name>` for the repo the session's cwd is in — the last two path components of
# origin, for both the SSH and the HTTPS spelling.
_origin_nwo=""; _origin_nwo_done=0
origin_nwo() {
  if [ "$_origin_nwo_done" = 0 ]; then
    _origin_nwo_done=1
    local u o n
    u="$(git -C "$CWD" remote get-url origin 2>/dev/null || true)"
    u="${u%.git}"; u="${u%/}"
    o="${u%/*}"; o="${o##*/}"; o="${o##*:}"
    n="${u##*/}"
    [ -n "$o" ] && [ -n "$n" ] && [ "$o" != "$u" ] && _origin_nwo="$o/$n"
  fi
  printf '%s' "$_origin_nwo"
}

# The PR a `gh pr merge` names, as a number — a URL counts, a flag's value never does.
merge_pr_operand() { # <stage>
  local w f seen=0 skipv=0 op=""
  while IFS= read -r w; do
    if [ "$seen" = 0 ]; then [ "$w" = merge ] && seen=1; continue; fi
    if [ "$skipv" = 1 ]; then skipv=0; continue; fi
    case "$w" in
      -*) for f in $GH_MERGE_VALUE_FLAGS; do [ "$w" = "$f" ] && { skipv=1; break; }; done
          continue ;;
      *) op="$w" ;;
    esac
  done <<EOF
$(tokens_of "$1")
EOF
  op="${op##*/}"
  case "$op" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$op"
}

_merge_why=""
merge_permitted() { # <stage> -> 0 when this exact merge is delegated in this bundle
  local sha pr repo helper
  _merge_why="only \`gh pr merge --squash --match-head-commit <sha> <pr>\` is ever delegated"
  has_token "$1" --squash || return 1
  has_token "$1" --merge && return 1
  has_token "$1" --rebase && return 1
  sha="$(flag_value "$1" --match-head-commit || true)"
  case "$sha" in *[!0-9a-fA-F]*|"") return 1 ;; esac
  [ "${#sha}" -ge 7 ] || return 1
  pr="$(merge_pr_operand "$1")" || return 1
  repo="$(flag_value "$1" --repo -R || true)"
  [ -n "$repo" ] || repo="$(origin_nwo)"
  case "$repo" in */*) ;; *) _merge_why="the repository this merge names cannot be resolved"; return 1 ;; esac
  # Resolved HERE and not at the top of the file: that line would cost a subshell in
  # front of every Bash call in every session on the machine, for a rule that fires on a
  # merge command and nothing else.
  helper="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../scripts" 2>/dev/null && pwd)/merge-permit.sh"
  [ -f "$helper" ] || { _merge_why="merge-permit.sh is not installed beside this hook"; return 1; }
  _merge_why="$(bash "$helper" --bundle "$INSTANCE_ROOT" --repo "$repo" --pr "$pr" \
                     --head "$sha" --role "$AGENT_TYPE" 2>/dev/null)" && return 0
  [ -n "$_merge_why" ] || _merge_why="merge-permit.sh could not answer"
  return 1
}

rule_subagent_merge() {
  case "$1" in *gh*) ;; *) return 1 ;; esac
  local stage c sub next
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    [ "$c" = gh ] || continue
    sub="$(word_after "$stage" gh || true)"
    case "$sub" in
      pr)
        next="$(word_after "$stage" pr || true)"
        if [ "$next" = merge ]; then
          merge_permitted "$stage" && continue
          printf 'Refusing this merge: %s. The merge is the human'"'"'s under `gated` — open the PR and leave it. Where `AUTONOMY.md` delegates it, the project-manager tick merges with `gh pr merge --squash --match-head-commit <sha> <pr>` once every clearance precondition is recorded at that SHA. Running `gh pr merge` yourself in your own terminal is unaffected.' "$_merge_why"
          return 0
        fi
        [ -n "$AGENT_ID" ] || continue     # the approval half stays agent-scoped
        if [ "$next" = review ] && has_token "$stage" --approve; then
          printf '`gh pr review --approve` from a dispatched agent manufactures the approval the merge gate is meant to get from a human or an external reviewer. Post a comment or `--request-changes` instead — an approval is the human'"'"'s to give.'
          return 0
        fi
        ;;
      api)
        # PUT /repos/O/R/pulls/N/merge and POST /repos/O/R/merges both land a merge. The
        # first is refused in every session — it is the way round `gh pr merge`, so leaving
        # it agent-scoped would leave the delegated shape optional. The second stays
        # agent-scoped: merging a branch is not this gate's subject.
        case "$stage" in
          *pulls/*/merge*)
            printf 'The `/pulls/N/merge` endpoint consummates a merge no clearance record can pin — `gh api` carries no `--match-head-commit`. The human merges under `gated`, and where `AUTONOMY.md` delegates it the tick uses `gh pr merge --squash --match-head-commit <sha>`. Open the PR instead.'
            return 0 ;;
        esac
        [ -n "$AGENT_ID" ] || continue
        case "$stage" in
          */merges*)
            printf 'A dispatched agent may not merge via `gh api` — the `/merges` endpoint consummates a merge the human owns under `gated`. Open the PR instead.'
            return 0 ;;
        esac
        ;;
    esac
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- subagent_push_default ----------------------------------------------------------- #
# JUSTIFIED BY: a role agent's work lands on a product repo through a PULL REQUEST — that
# is the whole review gate — and a direct (non-force) push to a protected branch bypasses
# it while `force_push_protected` stays silent, because a plain push to `main` is routine
# FOR THE HUMAN and for the bundle. Agent-scoped like `subagent_merge`: fires only when
# `agent_id` is present. NARROW ENOUGH TO KEEP, in three exemptions the tests pin:
#   · the BUNDLE — the repo whose root IS `$INSTANCE_ROOT` — is exempt: the
#     project-manager tick commits and pushes the instance's own default branch by design
#     (the loop's final step). `$INSTANCE_ROOT` is `$CLAUDE_PROJECT_DIR`, resolved once by
#     the guard at the top of this file — not the payload `cwd`, because a dispatched
#     agent's cwd is the WORKTREE, the same reasoning agent-control.sh records for its root;
#   · a FEATURE branch push is untouched — it is how every PR gets opened.
# THERE IS NO LONGER A THIRD, unset-CLAUDE_PROJECT_DIR exemption. This rule used to read
# the env var itself and fail open when it was unset or gone, because as an INSTANCE hook
# it could not tell "no bundle here" from "plumbing broke". As a PLUGIN hook the guard at
# the top of this file has already exited on exactly that condition, so the branch is
# unreachable and is deleted rather than left to read as live: reaching this line means an
# instance root was found, so a comparison against it is meaningful.
# The branch set is `force_push_protected`'s: the conventional names plus the repo's
# resolved default. `git -C <elsewhere>` shares that rule's documented limitation.
rule_subagent_push_default() {
  [ -n "$AGENT_ID" ] || return 1          # the human's own session is never gated here
  case "$1" in *push*) ;; *) return 1 ;; esac
  local root
  root="$(repo_root)"
  [ -n "$root" ] || return 1
  [ "$root" = "$INSTANCE_ROOT" ] && return 1   # the bundle: the tick pushes it by design

  local stage c w seen sub skipnext args remote r d dst p protected oldopts
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    [ "$c" = "git" ] || continue

    # The same walk force_push_protected uses, minus the force/delete tracking: ANY push
    # shape reaching a protected branch of a product repo is refused for an agent.
    seen=0; sub=""; skipnext=0; args=""
    while IFS= read -r w; do
      if [ "$skipnext" = 1 ]; then skipnext=0; continue; fi
      if [ "$seen" = 0 ]; then [ "${w##*/}" = "git" ] && seen=1; continue; fi
      if [ -z "$sub" ]; then
        case "$w" in
          -C|-c|--git-dir|--work-tree|--namespace|--exec-path) skipnext=1; continue ;;
          -*) continue ;;
          *) sub="$w"; continue ;;
        esac
      fi
      case "$w" in
        --*) ;;
        -*) ;;
        *) args="$args $w" ;;
      esac
    done <<EOT
$(tokens_of "$stage")
EOT
    [ "$sub" = "push" ] || continue

    oldopts="$(set +o | grep noglob)"; set -f
    # shellcheck disable=SC2086  # deliberate split; globbing is off for the duration
    set -- $args
    eval "$oldopts"
    remote="${1:-}"; [ "$#" -gt 0 ] && shift

    dst=""
    if [ "$#" -eq 0 ]; then
      d="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      [ "$d" = "HEAD" ] && d=""
      dst="$d"
    else
      for r in "$@"; do
        case "$r" in +*) r="${r#+}" ;; esac
        case "$r" in *:*) r="${r##*:}" ;; esac
        r="${r#refs/heads/}"
        dst="$dst $r"
      done
    fi
    [ -n "${dst// /}" ] || continue

    protected="main master develop trunk production"
    d="$(default_branch)"
    [ -n "$d" ] && protected="$protected $d"
    for r in $dst; do
      for p in $protected; do
        if [ "$r" = "$p" ]; then
          printf 'A dispatched agent may not push to the protected branch `%s` of a product repo (`%s`) — work lands there through a pull request, which is the review gate this would bypass. Pushing a FEATURE branch is normal and allowed, and the control-panel bundle itself is exempt (the tick pushes that by design).' "$p" "$root"
          return 0
        fi
      done
    done
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- launcher_diagnoses_nothing ------------------------------------------------------ #
# JUSTIFIED BY: five of twelve symptoms in the launcher-verification review were the MAIN
# session reading CI logs, clusters, deployed hosts and build output. That answer is thrown
# away the moment the session dispatches, so it is paid for in the one context that has to
# survive the day, and prose has already had its turn — a slash command's `allowed-tools`
# prevented none of it (bundle Finding "launcher-state-reads-belong-in-the-tick").
# TWO CONDITIONS, AND NEITHER ALONE: `agent_type` EMPTY (the main thread) and a cwd that is
# a control-panel instance root. NARROW ENOUGH TO KEEP: a dispatched role agent — the
# failure-analyst that is the named alternative, and every software/devops agent in a
# worktree — runs all of it untouched, and so does the human's own session in any other
# directory, including a target repo.
# ORDERED LAST in `RULES` on purpose: a command this and a shape rule both match (an agent's
# `kubectl delete namespace`) should be refused with the shape rule's reason.
#
# The reason names the dispatch to make instead, namespaced — a bare role name does not
# resolve — because a refusal with no route is a refusal that gets worked around.
_launcher_reason() { # <what was read> <the shape>
  printf '%s from the control-panel root, in the MAIN session (%s). The answer is discarded the moment this session dispatches, so it is paid for in the context that has to survive the day. Dispatch a background `%s:failure-analyst` — read-only, namespaced — with the ref, the repo and "root cause + ranked next steps", and let it read this. A dispatched agent runs the identical command untouched, as does this session anywhere but a bundle root.' "$1" "$2" "$PLUGIN_NAME"
}

rule_launcher_diagnoses_nothing() {
  # The two session-scope checks come BEFORE the glob — they are cheaper and far more
  # selective than it, the same order `subagent_merge` reads `agent_id` in.
  [ -z "$AGENT_TYPE" ] || return 1        # a dispatched subagent is exactly who should do this
  cwd_is_instance_root || return 1
  # `*oc*` is the superset for both cluster spellings, since "argocd" contains "oc" — so
  # `*argocd*` beside it is a pattern that can never match (shellcheck SC2222).
  case "$1" in *gh*|*kubectl*|*oc*|*curl*|*wget*|*grep*|*cat*|*rg*|*head*|*tail*) ;; *) return 1 ;; esac

  local stage c sub w host pat skipv seen f
  # `-e`/`--include`/`-g`… take a value, so their operand is not a path to judge. Same
  # failure `VALUE_FLAGS` documents for kubectl: read one as a path and the rule fires on a
  # pattern the user typed.
  local grep_value_flags="-e --regexp --include --exclude --exclude-dir --exclude-from -m --max-count -A -B -C --before-context --after-context --context -g --glob -t --type -T --iglob --replace -f --file -d --max-depth"
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in
      # a CI log. `gh run view --log`/`--log-failed`, and the same bytes via the REST API.
      gh)
        sub="$(word_after "$stage" gh || true)"
        if [ "$sub" = run ] && { has_token "$stage" --log || has_token "$stage" --log-failed; }; then
          _launcher_reason 'Reading a CI log' '`gh run view --log`'
          return 0
        fi
        if [ "$sub" = api ]; then
          case "$stage" in
            *actions/runs/*log*|*actions/jobs/*log*|*check-runs/*log*)
              _launcher_reason 'Reading a CI log' '`gh api` on a run'"'"'s logs'
              return 0 ;;
          esac
        fi
        ;;
      # driving a cluster. `oc` is kubectl's other spelling, as everywhere else in this file.
      kubectl|oc|argocd)
        _launcher_reason 'Driving a cluster' "\`$c\`"
        return 0
        ;;
      # probing a deployed host: an http(s) target that is not local. A localhost call is
      # this bundle's own board server, and is not a deployed host.
      curl|wget)
        host=""
        while IFS= read -r w; do
          case "$w" in http://*|https://*) ;; *) continue ;; esac
          host="${w#*://}"; host="${host##*@}"; host="${host%%/*}"; host="${host%%\?*}"
          case "$host" in
            \[*) host="${host%%\]*}"; host="${host#\[}" ;;   # [::1]:3000
            *) host="${host%%:*}" ;;
          esac
          case "$(lower "$host")" in
            localhost|127.0.0.1|0.0.0.0|::1|host.docker.internal|*.localhost|127.*) host="" ;;
            *) break ;;
          esac
        done <<EOT
$(tokens_of "$stage")
EOT
        if [ -n "$host" ]; then
          _launcher_reason 'Probing a deployed host' "\`$c\` at \`$host\`"
          return 0
        fi
        ;;
      # a build artifact. The FIRST operand of a grep-family call is the pattern, not a
      # path, so it is skipped: `grep -rn build plugin/` must not read as a `build/` path.
      cat|head|tail|grep|egrep|fgrep|rg|ag)
        pat=0; skipv=0; seen=0
        case "$c" in grep|egrep|fgrep|rg|ag) ;; *) pat=1 ;; esac
        while IFS= read -r w; do
          # BASENAME, as everywhere else here: `/bin/cat` is `cat`, and a literal compare
          # would never find the command word and would judge it as an operand.
          if [ "$seen" = 0 ]; then [ "${w##*/}" = "$c" ] && seen=1; continue; fi
          if [ "$skipv" = 1 ]; then skipv=0; continue; fi
          case "$w" in
            -*) for f in $grep_value_flags; do [ "$w" = "$f" ] && { skipv=1; break; }; done
                # A pattern given by FLAG means the first operand is already a path.
                # Without this, `grep -e build dist/main.js` skipped `dist/main.js` as the
                # pattern it had just been handed — a silent false negative.
                case "$w" in -e|--regexp|--regexp=*|-f|--file|--file=*) pat=1 ;; esac
                continue ;;
          esac
          if [ "$pat" = 0 ]; then pat=1; continue; fi
          case "$w" in *'$'*|*'`'*) continue ;; esac
          # SEGMENT equality, never a substring: `plugin/scripts/build-board.sh` is not a
          # path under `build/`, and `.next-doc` is not `.next`.
          case "/${w#./}" in
            */dist|*/dist/*|*/build|*/build/*|*/.next|*/.next/*)
              _launcher_reason 'Reading a build artifact' "\`$c $w\`"
              return 0 ;;
          esac
        done <<EOT
$(tokens_of "$stage")
EOT
        ;;
    esac
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# =============================================================================== decide ==
matched=""; reason=""
for _rule in $RULES; do
  if reason="$("rule_$_rule" "$CMD" 2>/dev/null)"; then
    matched="$_rule"
    break
  fi
done
[ -n "$matched" ] || exit 0

# The fence marks the reason as data. It is assembled from literals in this file plus
# fragments of the agent's own command, and lands in the agent's context.
body="loopd destructive-action baseline — rule \`$matched\` refused this command.

$reason

This is enforced by the harness before the tool runs, not by a convention, so it is not
something to argue past. Do NOT re-issue a variant that evades the pattern: if the command
is genuinely right, say so to the human and let them run it in their own terminal, outside
this session. That escape hatch is why this baseline can stay narrow enough to keep."

jq -n --arg r "$body" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
