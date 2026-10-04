#!/usr/bin/env bash
# release-bump.sh <major|minor|patch> — move the version ON THE DEFAULT BRANCH, after a merge.
# The ONLY writer of the five places that carry it: VERSION, plugin/VERSION, the two plugin
# manifests, and every tracked doc that DISPLAYS the number (its `─` rule is resized with
# the header) — never docs/releases/, where a shipped note records what shipped. The commit
# also carries `docs/releases/v<new>.md`, the one path this script accepts dirty.
# Refuses on a feature branch or any other dirty path, commits, prints the push.
# `major` ALSO moves every companion plugin to <new major>.0.0: a companion tracks core's
# MAJOR (plugin/README.md), so a v2 core beside a 1.x companion fails main's own suite.
# Exit: 0 bumped · 1 refused (branch, dirty tree, missing file, unverifiable result) · 2 usage.
# Reasoning: ai-bridge-next/task-026 and task-028, docs/conventions.md §20. Verified by tests/release-bump.test.sh.
set -uo pipefail

usage() { sed -n '2,11p' "$0" >&2; exit 2; }
die() { printf 'release-bump: %s\n' "$1" >&2; exit 1; }

FIELD=""; ROOT=""; ROOT_GIVEN=0; COMMIT=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    major|minor|patch) FIELD="$1"; shift ;;
    --repo)       shift; ROOT="${1:-}"; ROOT_GIVEN=1; shift || true ;;
    --repo=*)     ROOT="${1#--repo=}"; ROOT_GIVEN=1; shift ;;
    --no-commit)  COMMIT=0; shift ;;
    --dry-run)    DRY=1; COMMIT=0; shift ;;
    -h|--help)    usage ;;
    *) printf 'release-bump: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done
[ -n "$FIELD" ] || usage
# An empty `--repo` must not fall back to the script's own checkout: that would bump a repo
# the caller never named.
[ "$ROOT_GIVEN" = 0 ] || [ -n "$ROOT" ] || usage

_d="$(dirname "$0")"; if [ -L "$_d" ] && [ ! -f "$(dirname "$_d")/VERSION" ]; then _t="$(readlink "$_d")"; case "$_t" in /*) _d="$_t" ;; *) _d="$(dirname "$_d")/$_t" ;; esac; fi
[ -n "$ROOT" ] || ROOT="$(cd "$_d/../.." && pwd)"
[ -f "$ROOT/VERSION" ] || die "no VERSION under $ROOT — pass --repo <checkout>"
command -v python3 >/dev/null 2>&1 || die "python3 is required: the manifests are JSON, and the banner rule is counted in CHARACTERS"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git checkout"

# The bump belongs to the merge, so it belongs to the branch the merge landed on. This is a
# WRITER, so an unresolvable default branch is a refusal, never a pass.
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
DEFAULT="$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; DEFAULT="${DEFAULT#origin/}"
[ -n "$DEFAULT" ] || die "no origin/HEAD in $ROOT, so the default branch is unknown — 'git remote set-head origin -a' first"
[ "$BRANCH" = "$DEFAULT" ] \
  || die "on '$BRANCH', not the default branch '$DEFAULT' — the bump lands after the merge, never inside a PR"

OLD="$(head -n 1 "$ROOT/VERSION" | tr -d '[:space:]')"
printf '%s' "$OLD" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || die "VERSION is not MAJOR.MINOR.PATCH: '$OLD'"
IFS=. read -r MA MI PA <<EOF
$OLD
EOF
case "$FIELD" in
  major) NEW="$((MA + 1)).0.0" ;;
  minor) NEW="$MA.$((MI + 1)).0" ;;
  patch) NEW="$MA.$MI.$((PA + 1))" ;;
esac

# The release note for the version being cut is the ONE path allowed to be dirty: the bump
# commit carries it, and a dirty tree is otherwise refused, so there is no other route by
# which it could ride along.
NOTE="docs/releases/v$NEW.md"
DIRTY="$(git -C "$ROOT" status --porcelain | cut -c4- | grep -vFx "$NOTE")"
[ -z "$DIRTY" ] \
  || die "the working tree is dirty beyond $NOTE — the bump is its own commit, that note, and nothing else"

# One writer, one verifier: python3 PLANS every file first (in situ, no reformatting), so a
# missing or unparseable target refuses before the first write, then re-reads all five.
CHANGED="$(python3 - "$ROOT" "$NEW" "$DRY" "$FIELD" <<'PY'
import io, json, os, re, subprocess, sys

root, new, dry, field = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
# A companion tracks the core MAJOR, so only a major bump moves one, to <new major>.0.0.
companion_new = new.split(".")[0] + ".0.0" if field == "major" else None
HDR = re.compile(r'(loopd v?)(\d+\.\d+\.\d+)')
RULE = u"─"
changed = []

def read(path):
    try:
        return io.open(path, encoding="utf-8").read()
    except IOError as e:
        refuse("cannot read %s: %s" % (path, e))

def write(path, text, rel):
    changed.append(rel)
    if dry:
        return
    tmp = path + ".release-bump.tmp"
    io.open(tmp, "w", encoding="utf-8").write(text)
    os.replace(tmp, path)

def refuse(msg):
    sys.stderr.write("release-bump: %s\n" % msg)
    sys.exit(1)

def set_version(text, where, value=None):
    value = new if value is None else value
    out, n = re.subn(r'("version"\s*:\s*)"[^"]*"', lambda m: m.group(1) + '"%s"' % value, text, count=1)
    if n != 1:
        refuse("%s carries no \"version\" key" % where)
    return out

def entry_span(text, source):
    """The offsets of the marketplace object with this `source` — found by balancing braces
    outwards, so an edit can never land on the neighbouring entry."""
    m = re.search(r'"source"\s*:\s*"%s"' % re.escape(source), text)
    if not m:
        refuse("marketplace.json has no entry with source %s" % source)
    i, depth = m.start() - 1, 0
    while i >= 0:
        if text[i] == "}":
            depth += 1
        elif text[i] == "{":
            if depth == 0:
                break
            depth -= 1
        i -= 1
    j, depth = i, 0
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    if i < 0 or j >= len(text):
        refuse("marketplace.json: the %s entry's braces do not balance" % source)
    return i, j + 1

planned = []

for rel in ("VERSION", "plugin/VERSION"):
    read(os.path.join(root, rel))
    planned.append((rel, new + "\n"))

rel = "plugin/.claude-plugin/plugin.json"
planned.append((rel, set_version(read(os.path.join(root, rel)), rel)))

rel = ".claude-plugin/marketplace.json"
text = read(os.path.join(root, rel))
try:
    sources = [p.get("source", "") for p in json.loads(text).get("plugins", [])]
except ValueError as e:
    refuse("%s is not JSON: %s" % (rel, e))
for src in ["./plugin"] + ([s for s in sources if s != "./plugin"] if companion_new else []):
    want = new if src == "./plugin" else companion_new
    i, j = entry_span(text, src)
    text = text[:i] + set_version(text[i:j], "the %s entry" % src, want) + text[j:]
planned.append((rel, text))

if companion_new:
    for src in [s for s in sources if s != "./plugin"]:
        rel = os.path.join(os.path.normpath(src), ".claude-plugin", "plugin.json")
        planned.append((rel, set_version(read(os.path.join(root, rel)), rel, companion_new)))

# docs/releases/ is a RECORD, not a display: rewriting the header of a shipped note to the
# new number makes v3.0.0.md claim it is 3.1.0. The note for the version being cut carries
# its own number already and needs no rewrite either.
docs = [d for d in subprocess.check_output(
    ["git", "-C", root, "ls-files", "*.md"]).decode("utf-8").split()
    if not d.startswith("tests/") and not d.startswith("docs/releases/")]
for rel in docs:
    lines, hit = read(os.path.join(root, rel)).splitlines(True), False
    for k, line in enumerate(lines):
        body = line.rstrip("\n")
        if not HDR.search(body):
            continue
        hit = True
        header = HDR.sub(lambda m: m.group(1) + new, body)
        lines[k] = header + ("\n" if line.endswith("\n") else "")
        nxt = lines[k + 1].rstrip("\n") if k + 1 < len(lines) else ""
        if header.startswith("loopd") and nxt and set(nxt) == set(RULE):
            lines[k + 1] = RULE * len(header) + "\n"
    if hit:
        planned.append((rel, "".join(lines)))

for rel, text in planned:
    write(os.path.join(root, rel), text, rel)

if not dry:
    if read(os.path.join(root, "VERSION")).strip() != new or read(os.path.join(root, "plugin/VERSION")).strip() != new:
        refuse("a VERSION file did not take the new number")
    own = json.load(io.open(os.path.join(root, "plugin/.claude-plugin/plugin.json"), encoding="utf-8"))
    mkt = json.load(io.open(os.path.join(root, ".claude-plugin/marketplace.json"), encoding="utf-8"))
    core = [p for p in mkt.get("plugins", []) if p.get("source") == "./plugin"]
    if own.get("version") != new or len(core) != 1 or core[0].get("version") != new:
        refuse("a manifest did not take the new number — `git checkout -- .` to undo")
    for p in (mkt.get("plugins", []) if companion_new else []):
        src = p.get("source", "")
        if src == "./plugin":
            continue
        man = os.path.join(root, os.path.normpath(src), ".claude-plugin", "plugin.json")
        if p.get("version") != companion_new or json.loads(read(man)).get("version") != companion_new:
            refuse("companion %s is not on %s — `git checkout -- .` to undo" % (p.get("name", src), companion_new))
    for rel in docs:
        lines = read(os.path.join(root, rel)).splitlines()
        for k, line in enumerate(lines):
            m = HDR.search(line)
            if not m:
                continue
            nxt = lines[k + 1] if k + 1 < len(lines) else ""
            if m.group(2) != new:
                refuse("%s still displays %s" % (rel, m.group(2)))
            if line.startswith("loopd") and nxt and set(nxt) == set(RULE) and len(nxt) != len(line):
                refuse("%s: the rule under the banner is %d wide, the header is %d" % (rel, len(nxt), len(line)))

print("\n".join(changed))
PY
)" || die "the bump did not complete — check 'git -C $ROOT status', then 'git -C $ROOT checkout -- .'"

if [ "$DRY" = 1 ]; then
  printf 'release-bump: %s -> %s (dry run) would write:\n%s\n' "$OLD" "$NEW" "$CHANGED"
  exit 0
fi
if [ "$COMMIT" = 0 ]; then
  printf 'release-bump: %s -> %s written, not committed:\n%s\n' "$OLD" "$NEW" "$CHANGED"
  exit 0
fi

git -C "$ROOT" add -A || die "git add failed"
git -C "$ROOT" commit -q -m "chore: VERSION $OLD -> $NEW (bumped on $BRANCH after the merge)" \
  || die "git commit failed"
printf 'release-bump: %s -> %s committed on %s. Now push it:\n  git -C %s push origin %s\n' \
  "$OLD" "$NEW" "$BRANCH" "$ROOT" "$BRANCH"
