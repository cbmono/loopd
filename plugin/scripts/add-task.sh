#!/usr/bin/env bash
#
# add-task.sh — write the next draft task into one open project, shaped like a seed task.
#
#   Usage: add-task.sh [--instance DIR] <project-slug> <description> [kind=<build|research>]
#
# kind and target_repo come from project.md; the description is original_request, verbatim.
# Exit: 0 written, committed and pushed (or no origin) · 1 empty description · 2 usage or I/O
#       3 slug is not one folder name · 4 written, but the commit or push failed · 5 no such project
#       6 project is done · 7 kind= differs from the project · 8 failed validate-bundle.sh, removed
# Reasoning: prefer-tasks-in-open-projects/task-001.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '5p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "add-task: python3 is required" >&2; exit 2; }

inst="."
[ "${1:-}" = "--instance" ] && { [ $# -ge 2 ] || usage; inst="$2"; shift 2; }
[ $# -ge 2 ] && [ $# -le 3 ] || usage
slug="$1"; desc="$2"; want=""
if [ $# -eq 3 ]; then
  case "$3" in kind=build|kind=research) want="${3#kind=}" ;; *) usage ;; esac
fi
[ -f "$inst/instance.config.json" ] || { echo "add-task: not a loopd bundle: $inst" >&2; exit 2; }
inst="$(cd "$inst" && pwd -P)"
[ -n "$(printf '%s' "$desc" | tr -d '[:space:]')" ] || { echo "add-task: the description is empty" >&2; exit 1; }
[[ "$slug" =~ ^[A-Za-z0-9._-]+$ ]] && [ "$slug" != . ] && [ "$slug" != .. ] ||
  { echo "add-task: '$slug' is not a project folder name" >&2; exit 3; }

made="$(python3 - "$inst/projects/$slug" "$desc" "$want" <<'PY'
import datetime, glob, json, os, re, sys
base, desc, want = sys.argv[1:4]
def out(code, msg):
    print("add-task: " + msg, file=sys.stderr); sys.exit(code)
if not os.path.isdir(base):
    out(5, "no project folder projects/%s" % os.path.basename(base))
try:
    text = open(os.path.join(base, "project.md"), encoding="utf-8").read()
except OSError:
    out(5, "projects/%s has no project.md" % os.path.basename(base))
lines = text.split("\n")
fm = lines[1:lines.index("---", 1)] if lines[0] == "---" and "---" in lines[1:] else []
def field(k):
    for l in fm:
        m = re.match(r"%s:\s*(.*)$" % k, l)
        if m:
            return re.sub(r"\s+#.*$", "", m.group(1)).strip().strip("\"'")
    return ""
if field("status") == "done":
    out(6, "projects/%s is done; a follow-up is a new project" % os.path.basename(base))
kind = field("kind") or "build"
if want and want != kind:
    out(7, "kind=%s, but projects/%s is %s" % (want, os.path.basename(base), kind))
one = " ".join(desc.split())
title = re.split(r"(?<=[.!?])\s", one, maxsplit=1)[0].rstrip(".") or one
fslug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:40].strip("-") or "task"
nums = [0] + [int(re.match(r"task-(\d*)", os.path.basename(p)).group(1) or 0)
              for p in glob.glob(os.path.join(base, "tasks", "task-*.md"))]
tid = "task-%03d-%s" % (max(nums) + 1, fslug)
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
q = lambda v: json.dumps(v, ensure_ascii=False)
repo = field("target_repo")
extra = ("target_repo: %s\npr: []\n" % repo if repo else "pr: []\n") if kind == "build" else "artifacts: []\n"
os.makedirs(os.path.join(base, "tasks"), exist_ok=True)
path = os.path.join(base, "tasks", tid + ".md")
with open(path, "x", encoding="utf-8") as fh:
    fh.write("---\ntype: Task\ntitle: %s\ndescription: %s\nkind: %s\nstatus: draft\nassignee:\n"
             "original_request: %s\nacceptance_criteria: []\nopen_questions: []\n%stimestamp: %s\n---\n\n"
             "# Context\n\nAdded to this project by /loopd:add-task. The project manager refines it;\n"
             "only a person promotes it.\n" % (q(title), q(one), kind, q(one), extra, ts))
print(tid)
PY
)"; rc=$?
case $rc in 0) ;; 5|6|7) exit $rc ;; *) exit 2 ;; esac

rel="projects/$slug/tasks/$made.md"
if ! ( cd "$inst" && bash "$HERE/validate-bundle.sh" "$rel" ) >/dev/null 2>&1; then
  rm -f "$inst/$rel"
  echo "add-task: $rel failed validate-bundle.sh, so nothing was kept" >&2
  exit 8
fi
echo "added $rel (draft)"
root="$(git -C "$inst" rev-parse --show-toplevel 2>/dev/null)" || exit 0
( cd "$root" && bash "$HERE/commit-as.sh" human "feat: add $(cut -d- -f1-2 <<<"$made") to $slug" --stage -- "$inst/$rel" >/dev/null ) ||
  { echo "add-task: written, but the commit failed — commit it by hand" >&2; exit 4; }
bash "$HERE/push-commit.sh" "$root"; rc=$?
[ ! -f "$inst/instance.config.json" ] || ( cd "$inst" && bash "$HERE/write-snapshot.sh" --quiet >/dev/null )
case $rc in 0|3) exit 0 ;; *) exit 4 ;; esac
