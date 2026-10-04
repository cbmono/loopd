#!/usr/bin/env bash
#
# fold-answers.sh — move every ` --- `-answered `open_questions` entry into
# `answered_questions`, stamped `<ISO 8601> by <login> · <entry verbatim>`.
#
#   Usage: fold-answers.sh [--instance DIR] <task-doc>
#          fold-answers.sh --list <task-doc> <frontmatter-key>   # read-only
#
# Exit: 0 done (nothing to move is also 0) · 2 usage · 3 a list it could not round-trip,
# nothing written · 4 the move would leave one entry in BOTH lists, nothing written.
#
# THE MECHANICAL MOVE ONLY. Baking the answer into `# Context` or a criterion is the
# model's, before this runs; this script neither writes nor checks it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '4,6p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "fold-answers: python3 is required" >&2; exit 2; }

inst="."; doc=""; list_key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --list)     [ $# -ge 3 ] || usage; doc="$2"; list_key="$3"; shift 3 ;;
    -h|--help)  usage ;;
    -*)         usage ;;
    *)          [ -z "$doc" ] || usage; doc="$1"; shift ;;
  esac
done
[ -n "$doc" ] && [ -r "$doc" ] || { echo "fold-answers: no readable task document given" >&2; exit 2; }

# **`by <login>` names the human whose answer it was**, and it is never the model's to pick:
# `--author` attributes a reply that arrived as a ` --- ` line in a commit (its git author's
# email resolves through `people`, so a reply pushed from the OTHER clone attributes to the
# other human, not to whoever's loop folded it in), `--self` where the answer was given in
# session. Unattributable prints `<unknown>` and is written as-is — an omitted stamp is
# indistinguishable from a decision nobody made. `SCHEMA.md` → "Decisions name the human".
#
# WHICH OF THE TWO IS DECIDED PER ENTRY, never once for the whole document: one fold can
# carry an answer that arrived in a commit AND one given in this session, and a single
# document-level test stamps the second with the first one's human. The COMMITTED
# `open_questions` is the discriminator — an entry already there belongs to that commit's
# author; one that exists in the working tree alone was answered in this session. An
# unresolvable author stays `<unknown>` rather than being stamped with whoever's loop is
# folding it.
login_self="<unknown>"; login_author="<unknown>"; committed_state="absent"; committed_file=""
if [ -z "$list_key" ] && [ -x "$HERE/decision-stamp.sh" ]; then
  committed_file="$(mktemp -t fold-answers.XXXXXX)"; head_doc="$(mktemp -t fold-answers-head.XXXXXX)"
  trap 'rm -f "$committed_file" "$head_doc"' EXIT
  login_self="$(bash "$HERE/decision-stamp.sh" --instance "$inst" --self 2>/dev/null || true)"
  [ -n "$login_self" ] || login_self="<unknown>"
  if git -C "$(dirname "$doc")" show "HEAD:./$(basename "$doc")" > "$head_doc" 2>/dev/null; then
    # Read through this script's own `--list`, so the committed copy is scanned by the one
    # parser. A list it refuses leaves every entry unattributable rather than mis-attributed.
    if bash "$HERE/$(basename "$0")" --list "$head_doc" open_questions > "$committed_file" 2>/dev/null; then
      committed_state="read"
      login_author="$(bash "$HERE/decision-stamp.sh" --instance "$inst" --author "$doc" 2>/dev/null || true)"
      [ -n "$login_author" ] || login_author="<unknown>"
    else
      committed_state="unknown"
    fi
  fi
fi

python3 - "$doc" "$list_key" "$login_self" "$login_author" "$committed_state" \
         "$committed_file" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" <<'PY'
import os, re, sys, tempfile

ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "/": "/"}

path, list_key = sys.argv[1], sys.argv[2]
login_self, login_author, committed_state, committed_file, stamp = sys.argv[3:8]
src = open(path, encoding="utf-8").read()


def die(code, msg):
    sys.stderr.write("fold-answers: %s\n" % msg)
    sys.exit(code)


def frontmatter(text):
    if not text.startswith("---\n"):
        die(3, "no frontmatter")
    end = text.find("\n---", 3)
    if end < 0:
        die(3, "unterminated frontmatter")
    return 4, end + 1


FM_START, FM_END = frontmatter(src)


def scan_dq(text, i, key=""):
    """The body of a double-quoted scalar, from just past its opening quote."""
    n = len(text)
    buf = []
    while True:
        if i >= n:
            die(3, "unterminated double-quoted entry in %s" % (key or "the list"))
        c = text[i]
        if c == "\\":
            if i + 1 >= n:
                die(3, "trailing escape")
            nxt = text[i + 1]
            # ONLY THE ESCAPES emit() CAN REPRODUCE. A `\u263A` would otherwise read
            # as `u263A` and re-parse to `u263A`, so the round-trip guard — which
            # uses this same scanner — cannot see that the backslash was dropped.
            if nxt not in ESCAPES:
                die(3, "unsupported escape \\%s in %s" % (nxt, key or "the list"))
            buf.append(ESCAPES[nxt])
            i += 2
            continue
        if c == '"':
            return "".join(buf), i + 1
        buf.append(c)
        i += 1


def scan_sq(text, i, key=""):
    """The body of a single-quoted scalar, from just past its opening quote."""
    n = len(text)
    buf = []
    while True:
        if i >= n:
            die(3, "unterminated single-quoted entry in %s" % (key or "the list"))
        if text[i] == "'":
            if i + 1 < n and text[i + 1] == "'":
                buf.append("'")
                i += 2
                continue
            return "".join(buf), i + 1
        buf.append(text[i])
        i += 1


def scan_flow(text, i, key=""):
    """A real scanner for a YAML flow sequence of scalars: returns (entries, end_index).

    `key` is the frontmatter key being scanned, and it is a PARAMETER rather than the
    module global it used to read: the global is set only by `--list`, so on the main
    path every refusal below named the empty string and the operator was told a list
    they could not identify was not a flow list.

    Quoted scalars are consumed by their own grammar, which is the whole point — a
    bracket, a comma or a ` --- ` inside an entry is data, and every hand-rolled
    split on this shape has cut an entry in half on exactly one of the three."""
    n = len(text)
    while i < n and text[i] in " \t\n":
        i += 1
    if i >= n or text[i] != "[":
        die(3, "%s is not a flow list" % (key or "the list"))
    i += 1
    out = []
    while True:
        while i < n and text[i] in " \t\n,":
            i += 1
        if i >= n:
            die(3, "unterminated flow list in %s" % (key or "the list"))
        if text[i] == "]":
            return out, i + 1
        if text[i] == '"':
            v, i = scan_dq(text, i + 1, key)
            out.append(v)
        elif text[i] == "'":
            v, i = scan_sq(text, i + 1, key)
            out.append(v)
        else:
            j = i
            while j < n and text[j] not in ",]\n":
                j += 1
            v = text[i:j].strip()
            if v:
                out.append(v)
            i = j


def scan_block(text, i, key):
    """A block sequence (`key:` then `  - entry` lines): returns (entries, end_index, comment).

    `i` is the rest of the key line. Its comment is returned so a rewrite keeps it. An
    indented line that is not an entry — a continuation, a nested mapping — is a refusal:
    the rewrite would leave it stranded under whatever entry it emits last."""
    line_end = text.find("\n", i)
    if line_end < 0:
        line_end = len(text)
    rest = text[i:line_end].strip()
    if rest and not rest.startswith("#"):
        die(3, "%s is neither a flow nor a block list" % key)
    out, end, pos = [], line_end, line_end + 1
    while pos < FM_END:
        nl = text.find("\n", pos)
        if nl < 0:
            nl = len(text)
        line = text[pos:nl]
        m = re.match(r"[ \t]+-(?:[ \t]+|$)", line)
        if not m:
            if not line.strip():
                pos = nl + 1
                continue
            if line[0] in " \t":
                die(3, "%s has an indented line that is not a list entry" % key)
            break
        k = pos + m.end()
        if k < nl and text[k] in "\"'":
            v, k = (scan_dq if text[k] == '"' else scan_sq)(text, k + 1, key)
            if "\n" in text[pos:k]:
                die(3, "a quoted entry in %s spans lines" % key)
            tail = text[k:nl].strip()
            if tail and not tail.startswith("#"):
                die(3, "text after a quoted entry in %s" % key)
        else:
            v = re.split(r"[ \t]#", text[k:nl], 1)[0].strip()
            if not v:
                die(3, "an empty entry in %s" % key)
        out.append(v)
        end, pos = nl, nl + 1
    return out, end, (rest if rest.startswith("#") else "")


def find_key(key):
    m = re.search(r"(?m)^%s:" % re.escape(key), src[FM_START:FM_END])
    if not m:
        return None
    return FM_START + m.end()


def read(key):
    """(entries, at, end, comment) — `at` is just past the colon, so a rewrite owns the
    whole value whichever form it was, and either form may be written back."""
    at = find_key(key)
    if at is None:
        return None, None, None, ""
    j = at
    while j < FM_END and src[j] in " \t":
        j += 1
    if src[j:j + 1] == "[":
        entries, end = scan_flow(src, j, key)
        return entries, at, end, ""
    entries, end, comment = scan_block(src, j, key)
    return entries, at, end, comment


def emit(entries, comment=""):
    """SCHEMA.md's form: `[ ]` when empty, else one quoted entry per line."""
    head = " [ ]" if not entries else ""
    if comment:
        head += "  " + comment
    lines = []
    for e in entries:
        if "\n" in e:
            die(3, "an entry contains a newline; refusing to write a damaged list")
        lines.append('\n  - "%s"' % e.replace("\\", "\\\\").replace('"', '\\"'))
    return head + "".join(lines)


if list_key:
    entries, _, _, _ = read(list_key)
    for e in entries or []:
        # ONE ENTRY PER LINE IS THE CONTRACT every caller reads this by, and a quoted
        # scalar may legally span lines — so an entry that would print as two records is
        # refused here rather than silently counted twice downstream.
        if "\n" in e:
            die(3, "an entry contains a newline; cannot print one entry per line")
        print(e)
    sys.exit(0)

open_q, o_at, o_end, o_cmt = read("open_questions")
ans_q, a_at, a_end, a_cmt = read("answered_questions")
if open_q is None:
    sys.exit(0)
if ans_q is None:
    ans_q, a_at, a_end = [], None, None

# AN ANSWER MUST HAVE CONTENT. The test was `" --- " in e`, so an entry that merely
# ENDED with the separator — the shape you get when the separator is pre-placed as an
# affordance for the answer, and the shape a template leaves behind — counted as
# answered: it moved to answered_questions carrying nothing, and open_questions
# emptied. Since an empty open_questions IS the promotion signal, that turned "nobody
# has answered this yet" into "this task is ready", which is the worst thing this
# script can do. Measured on three task documents whose every question was written
# that way: ten entries, none answered, all ten would have folded.
# THE LAST SEPARATOR IS THE ANSWER'S, not the first: a question may carry ` --- ` in its
# own text, and a search anywhere in the entry folded `Q: compare a --- b --- ` unanswered.


def answered_entry(entry):
    """True when the text after the FINAL ` --- ` has content."""
    _, sep, answer = entry.rpartition(" --- ")
    return bool(sep) and bool(answer.strip())


answered = [e for e in open_q if answered_entry(e)]
if not answered:
    sys.exit(0)
keep = [e for e in open_q if not answered_entry(e)]

COMMITTED = set()
if committed_state == "read":
    COMMITTED = set(open(committed_file, encoding="utf-8").read().splitlines())


def login_for(entry):
    if committed_state == "unknown":
        return "<unknown>"
    return login_author if entry in COMMITTED else login_self


moved = ["%s by %s · %s" % (stamp, login_for(e), e) for e in answered]
new_ans = ans_q + moved

STAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z by [^\n]*? · ")


def question(entry):
    """An entry's identity: its text before ` --- `, with any stamp prefix removed."""
    return STAMP.sub("", entry, count=1).split(" --- ", 1)[0].strip()


# THE FAILURE THIS SCRIPT EXISTS FOR. An entry left in both lists blocks the draft forever
# and nothing downstream can see it — so refuse rather than write it. WHOLE ENTRIES, never
# substrings: an open question that merely appears inside a longer answered one is not a
# double listing, and `in` refused those folds at exit 4.
answered_ids = {question(a) for a in new_ans}
for e in keep:
    if question(e) in answered_ids:
        die(4, "entry would remain in BOTH lists: %s" % e[:80])
if len(keep) + len(answered) != len(open_q):
    die(4, "entry count does not balance; nothing written")

new = emit(keep, o_cmt)
new_a = emit(new_ans, a_cmt)

if a_at is None:
    die(3, "no answered_questions: key to fold into")

# Highest offset first, so the earlier span's indices stay valid.
edits = sorted([(o_at, o_end, new), (a_at, a_end, new_a)], reverse=True)
out = src
for at, end, text in edits:
    out = out[:at] + text + out[end:]

# THE ROUND TRIP IS THE GUARD: re-read what we are about to write and refuse unless both
# lists parse back to exactly what we meant.
src = out
FM_START, FM_END = frontmatter(out)
back_o, _, _, _ = read("open_questions")
back_a, _, _, _ = read("answered_questions")
if back_o != keep or back_a != new_ans:
    die(3, "the re-parse does not match; nothing written")

# Written beside the document and renamed over it: opening `path` for writing truncates it
# first, so an interrupted write leaves a task document with half its frontmatter.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".fold-answers.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(out)
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
except BaseException:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
print("folded: %d entr%s -> answered_questions" % (len(moved), "y" if len(moved) == 1 else "ies"))
PY
