#!/usr/bin/env bash
#
# new-project-file.sh — create ONE gated build project from a web-queue entry file.
#
#   Usage: new-project-file.sh [--instance DIR] <entry.json>   # {id, title, what, who, doneWhen, repo, from}
#
# Every value is page text and is written as a quoted YAML string, never parsed as an option;
# `autonomy` is always `gated`. One `draft` seed task; stage 1 of the scaffold review runs.
# Exit: 0 created · 1 refused, one line, nothing written · 2 usage or I/O
#       4 created and committed, but the push failed. Reasoning: interactive-board/task-006.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
usage() { sed -n '5p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "new-project-file: python3 is required" >&2; exit 2; }

inst="."
[ "${1:-}" = "--instance" ] && { [ $# -ge 2 ] || usage; inst="$2"; shift 2; }
[ $# -eq 1 ] && [ -r "$1" ] || usage
[ -f "$inst/instance.config.json" ] || { echo "new-project-file: not a loopd bundle: $inst" >&2; exit 2; }
inst="$(cd "$inst" && pwd -P)"
org="$("$HERE/resolve-config.sh" --instance "$inst" org 2>/dev/null)" || org=""

made="$(python3 - "$1" "$inst" "$org" <<'PY'
import datetime, json, os, re, sys
src, inst, org = sys.argv[1:4]
try:
    d = json.load(open(src, encoding="utf-8"))
    f = {k: " ".join(str(d[k]).split()) for k in ("title", "what", "who", "doneWhen", "repo")}
except (OSError, ValueError, KeyError, TypeError):
    print("refused: not a new-project entry", file=sys.stderr); sys.exit(1)
if not all(f.values()) or not re.fullmatch(r"[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?", f["repo"]):
    print("refused: a field is empty or the repo is not owner/name", file=sys.stderr); sys.exit(1)
repo = f["repo"] if "/" in f["repo"] else ("%s/%s" % (org, f["repo"]) if org else "")
if not repo:
    print("refused: the repo has no owner and the bundle names no org", file=sys.stderr); sys.exit(1)
frm = str(d.get("from", ""))
login = frm if re.fullmatch(r"[A-Za-z0-9]+(-[A-Za-z0-9]+)*", frm) else ""
slug = re.sub(r"[^a-z0-9]+", "-", f["title"].lower()).strip("-")[:40].strip("-") or "project"
base = os.path.join(inst, "projects", slug)
if os.path.exists(base):
    print("refused: projects/%s already exists" % slug, file=sys.stderr); sys.exit(1)
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
q = lambda v: json.dumps(v, ensure_ascii=False)
crit = [s.strip() for s in f["doneWhen"].split(";") if s.strip()]
tid = "task-001-%s" % slug
os.makedirs(os.path.join(base, "tasks"))
os.makedirs(os.path.join(base, "sources"))
by = login or "<unknown>"
with open(os.path.join(base, "project.md"), "w", encoding="utf-8") as fh:
    fh.write("---\ntype: Project\ntitle: %s\ndescription: %s\noriginal_request: %s\nkind: build\n"
             "target_repo: %s\nsuccess_criteria: [ %s ]\nneed: %s\ncost_of_not_doing: \"\"\nno_owner: \"\"\n"
             "autonomy: gated\n%sstatus: active\ntimestamp: %s\n---\n\n# Context\n\n"
             "Created from the web board's answer queue by %s. Every value above is the page's text,\n"
             "recorded as written. `autonomy` is `gated` whatever that text says: a project created\n"
             "from the queue never promotes or merges on its own.\n\n[Tasks](index.md) · [Log](log.md)\n"
             % (q(f["title"]), q(f["what"]), q(f["what"]), repo, ", ".join(map(q, crit)), q(f["who"]),
                "owner: %s\n" % login if login else "", ts, by))
with open(os.path.join(base, "tasks", tid + ".md"), "w", encoding="utf-8") as fh:
    fh.write("---\ntype: Task\ntitle: %s\nkind: build\nstatus: draft\nassignee:\noriginal_request: %s\n"
             "acceptance_criteria: []\nopen_questions: []\npr: []\ntimestamp: %s\n---\n\n# Context\n\n"
             "The seed task of a project created from the web board. The project manager refines it;\n"
             "only a person promotes it.\n" % (q(f["title"]), q(f["what"]), ts))
with open(os.path.join(base, "index.md"), "w", encoding="utf-8") as fh:
    fh.write("# %s — tasks\n\n- [%s](tasks/%s.md) — draft\n" % (f["title"], tid, tid))
with open(os.path.join(base, "log.md"), "w", encoding="utf-8") as fh:
    fh.write("# %s — log\n\n## %s\n\n- **Created** %s by %s from the web board queue; autonomy `gated`.\n"
             % (f["title"], ts[:10], ts, by))
with open(os.path.join(base, "sources", "README.md"), "w", encoding="utf-8") as fh:
    fh.write("# Sources\n\nDrop raw context for this project here: notes, images, exports.\n")
print("%s\t%s\t%s\t%s\t%s" % (slug, repo, ts, by, re.sub(r"[\[\]]", "", f["title"])))
PY
)" || { [ $? -eq 1 ] && exit 1; exit 2; }

IFS=$'\t' read -r slug repo ts by title <<<"$made"
base="$inst/projects/$slug"
if ! ( cd "$inst" && bash "$HERE/validate-bundle.sh" "projects/$slug/project.md" "projects/$slug"/tasks/*.md ) >/dev/null 2>&1; then
  rm -rf "$base"
  echo "new-project-file: the scaffold failed validate-bundle.sh, so nothing was kept" >&2
  exit 2
fi
python3 - "$inst/$AB_LEDGER" "$slug" "$repo" "$ts" "$by" "$title" <<'PY' || exit 2
import os, sys
path, slug, repo, ts, by, title = sys.argv[1:7]
try:
    old = open(path, encoding="utf-8").read()
except FileNotFoundError:
    old = ""
with open(path + ".tmp", "w", encoding="utf-8") as fh:
    fh.write("## %s — Project added: %s\n\n* **Project added** — [%s](/projects/%s/project.md), target `%s`, "
             "1 seed task (`draft`), autonomy `gated`, from the web board queue. Added %s by %s.\n\n%s"
             % (ts[:10], slug, title, slug, repo, ts, by, old))
os.replace(path + ".tmp", path)
PY
echo "created projects/$slug (autonomy gated)"
root="$(git -C "$inst" rev-parse --show-toplevel 2>/dev/null)" || exit 0
( cd "$root" && bash "$HERE/commit-as.sh" human "feat: add $slug project" --stage -- "$base" "$inst/$AB_LEDGER" >/dev/null ) ||
  { echo "new-project-file: created, but the commit failed" >&2; exit 4; }
bash "$HERE/push-commit.sh" "$root" >/dev/null
case $? in 0|3) exit 0 ;; *) exit 4 ;; esac
