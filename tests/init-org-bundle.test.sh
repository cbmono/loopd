#!/usr/bin/env bash
#
# init-org-bundle.test.sh — `plugin/scripts/init-bundle.sh --org <org> [--name <repo>]`,
# the step that makes a bundle the ORGANISATION'S repo instead of a folder somebody
# pushes wherever they like. Both paths, offline, against bare fixture remotes.
#
# THE FOUR SHAPES, and only two of them stamp anything:
#
#   1. absent + access established   -> create <org>/<name> private, seed, push
#   2. absent + create REFUSED       -> create <me>/<name>, seed, push, print the transfer
#   3. present and a bundle          -> clone; tracked config kept, local file written
#   4. absent + access UNESTABLISHED -> refuse. A 404 from `gh repo view` answers the same
#      for "does not exist" and for "private, and you cannot see it", so shape 4 is the one
#      that matters: taking it for shape 1 seeds a fresh bundle over the org's real one,
#      for the SECOND person, on their first command. The assertions therefore check that
#      nothing was created (the stub logs every call) as well as the exit code.
#
#   …and shape 3's sibling: a repo that EXISTS and is not a bundle is refused BY NAME
#   rather than stamped, because `<org>-okf` may already be somebody's unrelated repo.
#
# `gh` is a stub on PATH and every remote is a local bare repo, so the whole matrix runs
# with no network. ok() compares actual to expected, in that argument order.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

HERE="$(cd "$(dirname "$0")" && pwd)" || { echo "init-org-bundle.test: cannot locate self" >&2; exit 2; }
REPO="$(cd "$HERE/.." && pwd)" || { echo "init-org-bundle.test: cannot locate repo root" >&2; exit 2; }
SCRIPT="$REPO/plugin/scripts/init-bundle.sh"
SKILL="$REPO/plugin/skills/init/SKILL.md"
SHARING="$REPO/docs/sharing.md"
SEED_README="$REPO/plugin/seed/README.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/init-org-bundle.XXXXXX")" || {
  echo "init-org-bundle.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
[ -n "$TMP" ] && [ -d "$TMP" ] || {
  echo "init-org-bundle.test: mktemp -d returned no usable directory — refusing to run." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
saw() { grep -Fq -- "$2" "$1" && echo yes || echo no; }

# A commit identity for the fixtures, so the script's `git commit` has one on a bare CI
# runner. Nothing in the script supplies one — it must never forge a human's.
export GIT_AUTHOR_NAME="init-org-bundle.test" GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="init-org-bundle.test" GIT_COMMITTER_EMAIL="test@example.com"
export GIT_CONFIG_NOSYSTEM=1 HOME="$TMP/home"
mkdir -p "$HOME"
# An ambient GIT_DIR/GIT_CONFIG* redirects every git call below — the fixture bare repos,
# the clones, the script's own first commit — into whatever repo it names.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
      GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

# --- the gh stub ---------------------------------------------------------------------
# Six verbs, each one the script actually calls. State lives in $GHFIX as files, so a case
# sets up the host by touching a path. EVERY invocation is logged, which is how "it never
# entered the create path" is asserted rather than believed.
export GHFIX="$TMP/ghfix"
mkdir -p "$GHFIX/repos" "$GHFIX/member" "$GHFIX/nocreate" "$GHFIX/bare" "$TMP/bin"
echo "example-user-007" > "$GHFIX/me"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GHFIX/calls"
key() { printf '%s' "$1" | tr '/' '_'; }
case "${1:-} ${2:-}" in
  "auth status") echo "github.com: logged in"; exit 0 ;;
  "api user")    cat "$GHFIX/me"; exit 0 ;;
  "api orgs"*)
    org="${2#orgs/}"; org="${org%%/*}"
    [ -e "$GHFIX/member/$org" ] || { echo "HTTP 404" >&2; exit 1; }
    echo active; exit 0 ;;
  "repo view")
    f="$GHFIX/repos/$(key "${3:-}")"
    [ -f "$f" ] || { echo "could not resolve to a Repository with the name '${3:-}'" >&2; exit 1; }
    case "$*" in
      *sshUrl*) cat "$f" ;;
      *)        printf '{"name":"%s"}\n' "${3##*/}" ;;
    esac
    exit 0 ;;
  "repo create")
    slug="${3:-}"; owner="${slug%%/*}"
    [ ! -e "$GHFIX/nocreate/$owner" ] || { echo "HTTP 403: Resource not accessible" >&2; exit 1; }
    bare="$GHFIX/bare/$(key "$slug").git"
    git init --bare --quiet "$bare" >/dev/null 2>&1 || exit 1
    printf '%s\n' "$bare" > "$GHFIX/repos/$(key "$slug")"
    echo "https://github.com/$slug"; exit 0 ;;
  "repo clone")
    f="$GHFIX/repos/$(key "${3:-}")"
    [ -f "$f" ] || exit 1
    git clone --quiet "$(cat "$f")" "${4:-}" >/dev/null 2>&1; exit $? ;;
esac
echo "init-org-bundle.test stub: unhandled gh $*" >&2; exit 99
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

LAST_OUT="$TMP/last-run.out"
run() { # <target> <args…> -> exit code; output lands in $LAST_OUT
  local t="$1"; shift
  bash "$SCRIPT" "$t" "$@" >"$LAST_OUT" 2>&1; echo $?
}
calls_for() { local n; n="$(grep -c -- "$1" "$GHFIX/calls" 2>/dev/null || true)"; echo "${n:-0}"; }

echo "== 1. the repo does not exist, and access is established =="
: > "$GHFIX/calls"
touch "$GHFIX/member/acme"
T1="$TMP/w1/_ai-bridge-acme"; mkdir -p "$T1"
rc="$(run "$T1" --org acme)"
ok "exit 0"                                   "$rc" 0
ok "the default name is <org>-okf"            "$(saw "$LAST_OUT" 'create acme/acme-okf (private)')" yes
ok "…and it names the probe that allowed it"  "$(saw "$LAST_OUT" 'gh api orgs/acme/memberships/example-user-007 -> active')" yes
ok "the seed landed"                          "$([ -f "$T1/$AB_SCHEMA" ] && echo yes || echo no)" yes
ok "it says the bundle is the org's"          "$(saw "$LAST_OUT" "bundle acme/acme-okf is the organisation's")" yes
ok "the first commit is pushed"               "$(git -C "$GHFIX/bare/acme_acme-okf.git" rev-list --count HEAD 2>/dev/null || echo 0)" 1
ok "…and it carries the seed"                 "$(git -C "$GHFIX/bare/acme_acme-okf.git" ls-tree -r --name-only HEAD | grep -cx "$AB_SCHEMA")" 1
ok "…and NOT this clone's local config"       "$(git -C "$GHFIX/bare/acme_acme-okf.git" ls-tree -r --name-only HEAD | grep -cx 'instance.config.local.json')" 0
ok "the local config is this machine's"       "$(saw "$T1/instance.config.local.json" '"ownerGithubUser": "example-user-007"')" yes

echo
echo "== 2. --name overrides the default =="
T2="$TMP/w2/_ai-bridge-acme"; mkdir -p "$T2"
rc="$(run "$T2" --org acme --name shared-brain)"
ok "exit 0"                                   "$rc" 0
ok "it created the name it was given"         "$(saw "$LAST_OUT" 'create acme/shared-brain (private)')" yes
ok "--name without --org is refused"          "$(bash "$SCRIPT" "$TMP/w2b" --name x >/dev/null 2>&1; echo $?)" 2

echo
echo "== 3. creating in the org is refused — the non-admin path, which still stamps =="
touch "$GHFIX/nocreate/globex" "$GHFIX/member/globex"
T3="$TMP/w3/_ai-bridge-globex"; mkdir -p "$T3"
rc="$(run "$T3" --org globex)"
ok "exit 0 — a refused create is not a failed stamp" "$rc" 0
ok "it created under the caller"              "$(saw "$LAST_OUT" 'create example-user-007/globex-okf (private)')" yes
ok "it says which of the two it did"          "$(saw "$LAST_OUT" 'is under YOUR account')" yes
ok "…and prints the transfer command"         "$(saw "$LAST_OUT" 'gh repo transfer example-user-007/globex-okf globex')" yes
ok "the seed landed anyway"                   "$([ -f "$T3/$AB_SCHEMA" ] && echo yes || echo no)" yes
ok "…and was pushed anyway"                   "$(git -C "$GHFIX/bare/example-user-007_globex-okf.git" rev-list --count HEAD 2>/dev/null || echo 0)" 1

echo
echo "== 4. the repo exists and is a bundle — the second person's clone =="
# A fixture remote carrying a bundle: the tracked config both humans share, and nothing
# else. The clone must keep it verbatim rather than re-seeding over it.
BARE4="$GHFIX/bare/initech_initech-okf.git"
git init --bare --quiet "$BARE4"
git -C "$BARE4" symbolic-ref HEAD refs/heads/main
SEEDW="$TMP/seedwork"; mkdir -p "$SEEDW/$AB_DIR"
git -C "$SEEDW" init --quiet
cat > "$SEEDW/instance.config.json" <<'CFG'
{
  "org": "initech",
  "defaultOwner": "example-user-007",
  "people": { "example-user-007": "007@example.com", "example-user-008": "008@example.com" }
}
CFG
echo "# Schema" > "$SEEDW/$AB_SCHEMA"
git -C "$SEEDW" add -A >/dev/null 2>&1
git -C "$SEEDW" commit --quiet -m "the org's bundle" >/dev/null 2>&1
git -C "$SEEDW" push --quiet "$BARE4" HEAD:refs/heads/main >/dev/null 2>&1
printf '%s\n' "$BARE4" > "$GHFIX/repos/initech_initech-okf"

echo "example-user-008" > "$GHFIX/me"
: > "$GHFIX/calls"
T4="$TMP/w4/_ai-bridge-initech"; mkdir -p "$T4"
rc="$(run "$T4" --org initech)"
ok "exit 0"                                   "$rc" 0
ok "it cloned rather than created"            "$(saw "$LAST_OUT" 'clone initech/initech-okf')" yes
ok "…and made NO create call"                 "$(calls_for 'repo create')" 0
ok "the shared tracked config came with it"   "$(saw "$T4/instance.config.json" '"defaultOwner": "example-user-007"')" yes
ok "…verbatim, not re-seeded"                 "$(saw "$T4/instance.config.json" '"008@example.com"')" yes
ok "this clone gets its OWN local config"     "$(saw "$T4/instance.config.local.json" '"ownerGithubUser": "example-user-008"')" yes
ok "…which is gitignored, so it stays theirs" "$(git -C "$T4" check-ignore -q instance.config.local.json && echo yes || echo no)" yes
echo "example-user-007" > "$GHFIX/me"

echo
echo "== 5. a 404 is NOT 'does not exist' when access cannot be established =="
: > "$GHFIX/calls"
T5="$TMP/w5/_ai-bridge-umbrella"; mkdir -p "$T5"
rc="$(run "$T5" --org umbrella)"
ok "exit 3 — it refuses"                      "$rc" 3
ok "it says a 404 is ambiguous"               "$(saw "$LAST_OUT" "'absent' OR 'private, and you cannot see it yet'")" yes
ok "it names the probe that would settle it"  "$(saw "$LAST_OUT" 'gh api orgs/umbrella/memberships/<you>')" yes
ok "NOTHING was created"                      "$(calls_for 'repo create')" 0
ok "…and nothing was stamped"                 "$([ -e "$T5/$AB_SCHEMA" ] && echo yes || echo no)" no

echo
echo "== 6. it exists, and it is not a bundle — refused by name =="
BARE6="$GHFIX/bare/acme_acme-notes.git"
git init --bare --quiet "$BARE6"
git -C "$BARE6" symbolic-ref HEAD refs/heads/main
NOTW="$TMP/notework"; mkdir -p "$NOTW"
git -C "$NOTW" init --quiet
echo "someone else's repo" > "$NOTW/README.md"
git -C "$NOTW" add -A >/dev/null 2>&1
git -C "$NOTW" commit --quiet -m "not a bundle" >/dev/null 2>&1
git -C "$NOTW" push --quiet "$BARE6" HEAD:refs/heads/main >/dev/null 2>&1
printf '%s\n' "$BARE6" > "$GHFIX/repos/acme_acme-notes"

T6="$TMP/w6/_ai-bridge-acme"; mkdir -p "$T6"
rc="$(run "$T6" --org acme --name acme-notes)"
ok "exit 3 — it refuses"                      "$rc" 3
ok "…by name"                                 "$(saw "$LAST_OUT" 'acme/acme-notes exists and is not a loopd bundle')" yes
ok "…naming the two markers it looked for"    "$(saw "$LAST_OUT" "no instance.config.json, no $AB_SCHEMA")" yes
ok "it did NOT stamp the seed over it"        "$([ -e "$T6/$AB_SCHEMA" ] && echo yes || echo no)" no
ok "…and the repo's own content is intact"    "$(saw "$T6/README.md" "someone else's repo")" yes

echo
echo "== 7. an EMPTY repo is seeded, not refused =="
BARE7="$GHFIX/bare/acme_acme-blank.git"
git init --bare --quiet "$BARE7"
printf '%s\n' "$BARE7" > "$GHFIX/repos/acme_acme-blank"
T7="$TMP/w7/_ai-bridge-acme"; mkdir -p "$T7"
rc="$(run "$T7" --org acme --name acme-blank)"
ok "exit 0"                                   "$rc" 0
ok "it said the repo was empty"               "$(saw "$LAST_OUT" 'has no commits')" yes
ok "the seed landed and was pushed"           "$(git -C "$BARE7" rev-list --count HEAD 2>/dev/null || echo 0)" 1

echo
echo "== 8. no --org means no host call at all =="
: > "$GHFIX/calls"
T8="$TMP/w8/_ai-bridge-plain"; mkdir -p "$T8"
rc="$(run "$T8")"
ok "exit 0 — the old behaviour is untouched"  "$rc" 0
ok "no repo was created"                      "$(calls_for 'repo create')" 0
ok "no repo was cloned"                       "$(calls_for 'repo clone')" 0
ok "…and it is not a git repo either"         "$([ -e "$T8/.git" ] && echo yes || echo no)" no

echo
echo "== 9. the refusals and the flag are documented where a human looks =="
ok "--help lists --org"                       "$(bash "$SCRIPT" --help | grep -c -- '--org ORG \[--name REPO\]')" 1
ok "the skill carries the flag"               "$(saw "$SKILL" '## One org, one bundle — `--org <org> [--name <repo>]`')" yes
ok "…and the non-admin path as normal"        "$(saw "$SKILL" 'when creating it in `<org>` is refused because you are not an org admin')" yes
ok "…and carries no host literal (plugin rule)" "$(grep -c -E 'cbmono|/Users/|github\.com' "$SKILL" | tr -d ' ')" 0
ok "sharing.md is the front door"             "$(saw "$SHARING" '# Sharing one bundle — the front door for multi-person use')" yes
ok "…and carries the --org step"              "$(saw "$SHARING" '--org <org>')" yes
ok "the seed README links it"                 "$(saw "$SEED_README" 'https://github.com/cbmono/loopd/blob/main/docs/sharing.md')" yes

echo
printf 'init-org-bundle.test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
