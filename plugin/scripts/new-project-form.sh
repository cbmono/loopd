#!/usr/bin/env bash
#
# new-project-form.sh — the five-field form behind a no-description `/loopd:new-project`.
#
#   Usage: new-project-form.sh [--instance DIR] [<arguments>...]   (the skill's $ARGUMENTS)
#
# none ⇒ open (an existing form is kept) · `<1-5> <text>` fills that field, verbatim ·
# `submit` checks every field: complete ⇒ one JSON line for the skill to create from ·
# `cancel` removes the form. The form is one untracked file, AB_NEW_PROJECT_FORM.
# Exit: 0 done · 1 submit refused, ✗ written on each missing field · 2 usage or I/O
#       3 not a form command, nothing written. Reasoning: interactive-board/task-004.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
command -v python3 >/dev/null 2>&1 || { echo "new-project-form: python3 is required" >&2; exit 2; }

inst="."
[ "${1:-}" = "--instance" ] && { [ $# -ge 2 ] || { sed -n '5p' "$0" >&2; exit 2; }; inst="$2"; shift 2; }
[ -f "$inst/instance.config.json" ] || { echo "new-project-form: not a loopd bundle: $inst" >&2; exit 2; }
repo="$("$HERE/resolve-config.sh" --instance "$inst" defaultRepo 2>/dev/null)" || repo=""
owner="$("$HERE/decision-stamp.sh" --instance "$inst" --self 2>/dev/null)" || owner=""

python3 - "$inst/$AB_NEW_PROJECT_FORM" "$repo" "$owner" "$*" <<'PY'
import json, os, re, sys
path, default_repo, owner, raw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].strip()
KEYS = ["title", "what", "whom", "done", "repo"]
LABELS = ["Title", "What", "For whom", "Done when", "Target repo"]
FIX = ["Give it a short name.", "Say what it should do, in a line.", "Say who needs it.",
       "Tell us how you'll know it's done. One sentence is enough.",
       "Name the repository it changes, as owner/name."]
REPO = re.compile(r"^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$")

def load():
    try:
        d = json.load(open(path, encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        print("new-project-form: %s is unreadable — /loopd:new-project cancel removes it" % path, file=sys.stderr); sys.exit(2)
    f = d.get("fields") if isinstance(d, dict) else None
    f = f if isinstance(f, dict) else {}
    e = d.get("errors") if isinstance(d, dict) else None
    return {"fields": {k: f[k] if isinstance(f.get(k), str) else "" for k in KEYS},
            "errors": {k: v for k, v in (e if isinstance(e, dict) else {}).items() if k in KEYS and isinstance(v, str)}}

def save(form):
    d = os.path.dirname(path)
    try:
        os.makedirs(d, exist_ok=True)
        ig = os.path.join(d, ".gitignore")
        if not os.path.exists(ig):
            open(ig, "w").write("*\n")
        tmp = "%s.tmp.%d" % (path, os.getpid())
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(form, fh, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError as err:
        print("new-project-form: could not save the form: %s" % err.strerror, file=sys.stderr); sys.exit(2)

def show(form, head):
    filled = sum(1 for k in KEYS if form["fields"][k])
    print("%s — %d of %d filled" % (head, filled, len(KEYS)))
    for i, k in enumerate(KEYS):
        print("%d %-12s %s" % (i + 1, LABELS[i], form["fields"][k] or "(empty)"))
        if k in form["errors"]:
            print("  ✗ " + form["errors"][k])
    print("Fill a field: /loopd:new-project <n> <text> · then /loopd:new-project submit, or cancel")

def unquote(t):
    if len(t) >= 2 and t[0] == t[-1] == '"':
        return re.sub(r'\\(["\\])', r"\1", t[1:-1])
    if len(t) >= 2 and t[0] == t[-1] == "'":
        return t[1:-1]
    return t

form = load()
fresh = {"fields": {k: "" for k in KEYS}, "errors": {}}
fresh["fields"]["repo"] = default_repo if REPO.match(default_repo) else ""

if raw == "":
    if form is None:
        form = fresh
        save(form)
    show(form, "New project")
elif raw == "cancel":
    try:
        os.remove(path)
    except FileNotFoundError:
        pass
    except OSError as err:
        print("new-project-form: could not remove the form: %s" % err.strerror, file=sys.stderr); sys.exit(2)
    print("Cancelled — nothing saved.")
elif raw == "submit":
    if form is None:
        print("No form is open — /loopd:new-project opens one."); sys.exit(1)
    errors = {}
    for i, k in enumerate(KEYS):
        v = form["fields"][k].strip()
        if not v:
            errors[k] = FIX[i]
        elif k == "repo" and not REPO.match(v):
            errors[k] = "That is not a repository name — use owner/name."
    form["errors"] = errors
    save(form)
    if errors:
        show(form, "New project · %d thing%s to fix" % (len(errors), "" if len(errors) == 1 else "s"))
        sys.exit(1)
    f = {k: form["fields"][k].strip() for k in KEYS}
    print(json.dumps({"description": f["what"], "title": f["title"], "need": f["whom"],
                      "success_criteria": [s.strip() for s in f["done"].split(";") if s.strip()],
                      "repo": f["repo"], "kind": "build", "autonomy": "yolo",
                      "owner": owner if re.match(r"^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", owner) else ""},
                     ensure_ascii=False))
else:
    m = re.match(r"^([1-5])(?:[ \t]+(.*))?$", raw, re.S)
    if not m:
        sys.exit(3)
    k = KEYS[int(m.group(1)) - 1]
    if form is None:
        form = fresh
    form["fields"][k] = re.sub(r"\s+", " ", unquote((m.group(2) or "").strip())).strip()
    form["errors"].pop(k, None)
    save(form)
    show(form, "New project")
PY
