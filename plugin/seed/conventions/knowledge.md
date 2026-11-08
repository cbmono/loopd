# Conventions detail: knowledge

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

### Capture knowledge

- **Capture knowledge — a `Finding` only when a later task would plausibly hit the same problem.**
  Write or update it in `knowledge/findings/` (per `SCHEMA.md`), link it from the task,
  and never cite it as evidence: `kb-usage.sh record --task` grades that `SELF` once the task
  has a `DISPATCH` line (without either it stays `UNREAD`). It carries **`provenance: machine`**
  (`SCHEMA.md` → `provenance:`) — never on a document a person wrote. **Run
  `scripts/validate-bundle.sh <path>` on the one you just wrote** — it is the 40-line cap
  and the `lesson:` checked at the moment they are cheap to fix.
  **Where `knowledge/` is MOUNTED from another repository** (`knowledge` in
  `instance.config.json`; `SCHEMA.md` → "A mounted knowledge base"), **you do not write
  into it** — return the `Finding` in your result exactly as you would anyway and the tick
  commits it. There is **one writer per bundle** and it is the tick, so up to
  `maxAgentsInFlight` agents never share one git tree. `commit-as.sh` refuses a path under
  the mount by name, so a stale instruction fails loudly rather than committing nothing.
  **Absent the key nothing changes** and `knowledge/` is the bundle's own folder as before.

### Record a papercut

- **Record a papercut — ONE line, and the bar is "it hurt", not "it is durable".** A
  `Finding` costs 40 lines and a judgement call, so the small stuff never gets written down
  at all: a tool that failed, a doc that misled you, a step you did twice. Those go in the
  bundle's `knowledge/papercuts.md`, one appended line each:

  ```sh
  scripts/papercuts.sh add --task <project>/task-0NN --surface script:validate-bundle.sh \
    --note "exits 0 on an unreadable file, so a dangling ref reads as clean"
  ```

  Run it at the bundle root (where the task document lives), not in your worktree — or pass
  `--file <bundle>/knowledge/papercuts.md`. `--surface` names the file that should CHANGE:
  `skill:`, `agent:` or `script:`, then its name. The note is **15-160 bytes** and the tool
  refuses anything else, which is the whole shape.
  **Append, never edit or delete — including your own lines.** Ten entries naming one
  surface are the evidence that surface needs work, and they only read as ten while nobody
  tidies them; a wrong entry is corrected by a new entry. The `cataloguer` groups the
  record by surface and proposes the concrete edit as a `draft` task, which is what makes
  writing the line worth your ten seconds.

### Cite knowledge by slug

- **Cite knowledge as `[[finding-slug]]`, and only ids your brief actually carried.** A
  bracketed slug is the ONLY thing that counts as a citation — a title in prose, *"as the
  worktree finding notes"*, a bare link: all references, none of them citations, and
  nothing reads them. The slug is the file's name without `.md`, and **document
  frontmatter under `knowledge/` is the id source of truth**: a slug with no file there
  names no document at all, and a doc past the index's cap is still one.
  **Then the citation is checked instead of trusted.** `scripts/cite-check.sh --text-file
  <f> --brief <slugs>` keeps the ids the brief carried, drops the rest, and grades what is
  left — **exit 0** nothing dropped, **exit 3** dropped but every citing line still cites
  something, **exit 1** a citing line ended up with none, which is a claim whose whole
  provenance vanished and is flagged rather than accepted (**exit 2** is unknown: no index
  to judge against). Run it on your own `# Result` before you hand back; the
  `project-manager` runs it again at reflect time.
  **The two ways an id gets dropped are reported apart, and that distinction is the
  point.** An id that IS a document but was not in your brief is **`UNREAD`** — a real
  document nobody read, which is a briefing gap. An id no document carries is **`FABRICATED`** —
  invented provenance, which is a different failure with a different fix. Collapsing them
  into "invalid" loses the only thing the report was for. It is a cheap control and a
  narrow one: it proves an id was in front of you, never that the claim you hung on it is
  true.
