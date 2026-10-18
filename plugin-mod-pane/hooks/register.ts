// loopd-mod-pane — the bundle's board, drawn in a pane of the session that opens it.
//
// TWO MODES, decided by the `mode` userConfig field alone (register's `options`):
// operator — the fourth renderer over `.loopd/SNAPSHOT.json` (docs/conventions.md §11), with
// Tick and Refresh; simple — an inbox of open questions, stuck tasks and progress, read from
// the task documents, every button one slash command. What each mode reads is README.md → "What it
// reads", asserted by tests/mods.test.sh. Untrusted text and types: every string through
// clean(), every number through toint(), none truncated (conventions 11d, 11e).
//
// NEVER: a model call, a hook on the permission event, a process, the network, the
// environment, a file write, a walk up from the cwd — tests/mods.test.sh asserts each
// absence on this source, so none of those is spelled here even as a comment.

const PANE = 'loopd-board'
const COMMAND = 'pane'
const TITLE = 'loopd board'
const CONFIG = 'instance.config.json'
const SNAPSHOT = '.loopd/SNAPSHOT.json'
const POLL_MS = 5000
const DISPATCH = 'loopd:dispatch'   // the command, without its slash, as $.command.run names it
// write-snapshot.sh's verb set, minus nothing: the pane names the verb, never the reason.
const VERBS = ['approve', 'answer', 'merge', 'unblock', 'close'] as const
const ANSWER = 'loopd:answer'
const NEW_PROJECT = 'loopd:new-project'
// The simple mode's whole walk. The list and read calls below are derived from these two
// globs, so the README's declaration of them is the declaration of the walk.
const TASK_DOCS = 'projects/*/tasks/*.md'
const PROJECT_DOC = 'projects/*/project.md'
const [PROJECTS_DIR, , TASKS_DIR, TASK_GLOB] = TASK_DOCS.split('/')
const PROJECT_FILE = PROJECT_DOC.split('/')[2]
const TASK_SUFFIX = TASK_GLOB.slice(1)
let MODE: 'operator' | 'simple' = 'operator'

type Kind = 'unread' | 'not-bundle' | 'off' | 'malformed' | 'ok'

type Task = {
  id: string
  title: string
  status: string
  assignee: string
  in_flight: boolean
  pr_mergeable: string
  awaiting: string
  open_questions: number
  prs: number
}
type Project = {
  slug: string
  title: string
  status: string
  awaiting_close: boolean
  phase_done: number
  phase_total: number
  tasks: Task[]
}
type Board = {
  group: string
  generated_at: string
  projects: number
  tasks: number
  awaiting: number
  rows: Project[]
}

// Module state. A reload starts it over, and the next poll or /pane fills it again.
let kind: Kind = 'unread'
let board: Board | null = null
let detail = ''          // the one line a non-ok kind shows
let mtimeMs = -1         // the snapshot's mtime at the last read; -1 = never read
let reads = 0            // how many times the file was actually read (the poll skips an unchanged one)
let timer: { cancel: () => void } | null = null
let tickQueued = false
let tickRefused = ''     // why the last Tick's submit was refused, drawn in the footer; '' = it was not

// ---------------------------------------------------------------- untrusted input
// The TERMINAL sink's one sanitising point, the same rule print-board.sh applies: drop
// every code point in Unicode general category C (ESC, the bidi overrides, surrogates…),
// turn whitespace controls into one space, collapse runs. One rule, not a blocklist.
// The property escape is tried once; an engine without it gets the C0/C1/format fallback.
// Both are built from STRINGS, double-escaped, so this source stays ASCII: a raw U+2028 in
// a regex literal is a line terminator to the parser and ends the literal early.
let CAT_C: RegExp
try { CAT_C = new RegExp('\\p{C}', 'gu') } catch {
  CAT_C = new RegExp('[\\u0000-\\u001f\\u007f-\\u009f\\u00ad\\u200b-\\u200f\\u2028-\\u202e\\u2060-\\u2064\\u2066-\\u206f\\ufeff\\ufff9-\\ufffb]', 'g')
}
function clean(v: unknown): string {
  const s = typeof v === 'string' ? v : (v === null || v === undefined ? '' : String(v))
  return s.replace(/[\t\n\r\f\v]/g, ' ').replace(CAT_C, '').replace(/ {2,}/g, ' ').trim()
}

// Every number off the snapshot goes through here — a `"tasks": "many"` is 0, not a throw.
// Never truncated downstream: the caller prints String(n) whole.
function toint(v: unknown): number {
  if (typeof v === 'number' && isFinite(v)) return Math.max(0, Math.floor(v))
  if (typeof v === 'string' && /^[0-9]+$/.test(v.trim())) return parseInt(v.trim(), 10)
  return 0
}
function str(v: unknown): string { return typeof v === 'string' ? clean(v) : '' }
function obj(v: unknown): Record<string, unknown> | null {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : null
}
function arr(v: unknown): unknown[] { return Array.isArray(v) ? v : [] }

// Presentation over the parsed JSON: shape it once, cleanly, so the render hook is a pure
// function of `board`. Nothing here is derived from the bundle — only from the snapshot.
function shape(json: unknown): Board | null {
  const top = obj(json)
  if (!top) return null
  const counts = obj(top.counts) || {}
  const rows: Project[] = []
  for (const p of arr(top.projects)) {
    const po = obj(p)
    if (!po) continue
    const pp = obj(po.phase_progress) || {}
    const tasks: Task[] = []
    for (const t of arr(po.tasks)) {
      const to = obj(t)
      if (!to) continue
      tasks.push({
        id: str(to.id), title: str(to.title), status: str(to.status), assignee: str(to.assignee),
        in_flight: to.in_flight === true, pr_mergeable: str(to.pr_mergeable), awaiting: str(to.awaiting),
        open_questions: toint(to.open_questions), prs: arr(to.prs).length,
      })
    }
    rows.push({
      slug: str(po.slug), title: str(po.title), status: str(po.status),
      awaiting_close: po.awaiting_close === true,
      phase_done: toint(pp.done), phase_total: toint(pp.total), tasks,
    })
  }
  return {
    group: str(top.group), generated_at: str(top.generated_at),
    projects: toint(counts.projects), tasks: toint(counts.tasks), awaiting: toint(counts.awaiting),
    rows,
  }
}

// ---------------------------------------------------------------- the read
// `force` re-reads regardless of mtime (Refresh, the first open); the poll passes false and
// reads only when stat says the file moved. Every `$` call is caught: a missing or renamed
// field, a vanished file or a refused call costs one line in the pane, never a throw.
async function refresh($: any, force: boolean): Promise<void> {
  let cwd: unknown = null
  try { cwd = await $.session.cwd() } catch { cwd = null }
  if (typeof cwd !== 'string' || !cwd) { kind = 'malformed'; board = null; detail = 'cannot read the working directory'; return }
  const root = cwd.replace(/\/+$/, '')
  let isBundle = false
  try { isBundle = (await $.fs.exists(root + '/' + CONFIG)) === true } catch { isBundle = false }
  if (!isBundle) { kind = 'not-bundle'; board = null; detail = 'not a loopd bundle — no ' + CONFIG + ' in ' + clean(root); mtimeMs = -1; return }
  const path = root + '/' + SNAPSHOT
  let st: any = null
  try { st = await $.fs.stat(path) } catch { st = null }
  if (!st || st.kind !== 'file') {
    kind = 'off'; board = null; mtimeMs = -1
    detail = 'board OFF — no ' + SNAPSHOT + ' here. `touch ' + SNAPSHOT + '` in the bundle root turns it on (absence is the off switch).'
    return
  }
  const m = typeof st.mtimeMs === 'number' ? st.mtimeMs : -2
  if (!force && kind !== 'unread' && m === mtimeMs) return
  let text: unknown = null
  try { text = await $.fs.read(path) } catch { text = null }
  reads += 1
  mtimeMs = m
  if (typeof text !== 'string') { kind = 'malformed'; board = null; detail = 'could not read ' + SNAPSHOT; return }
  let json: unknown
  try { json = JSON.parse(text) } catch { kind = 'malformed'; board = null; detail = SNAPSHOT + ' is not valid JSON — the next write-snapshot.sh run overwrites it'; return }
  const b = shape(json)
  if (!b) { kind = 'malformed'; board = null; detail = SNAPSHOT + ' is not a JSON object — the next write-snapshot.sh run overwrites it'; return }
  kind = 'ok'; board = b; detail = ''
}

function summary(): string {
  if (kind !== 'ok' || !board) return detail
  return 'loopd board: ' + board.projects + ' project(s) · ' + board.tasks + ' task(s) · ' + board.awaiting + ' awaiting you'
}

// ---------------------------------------------------------------- the drawing
// Function-call form (this is a .ts file, so no JSX); Box, Text and Button are the three
// elements every surface draws. Every string passed to Text has been through clean().
function draw($: any, e: any): any {
  const { Box, Text, Button } = $.ui.resolve(e)
  const line = (s: string, props: Record<string, unknown> = {}) => Text({ ...props, children: [s] })
  const rows: any[] = []

  if (kind !== 'ok' || !board) {
    rows.push(line(kind === 'unread' ? 'loopd board: reading…' : detail, { dimColor: kind === 'unread' }))
  } else {
    const b = board
    rows.push(line(TITLE + (b.group ? ' · ' + b.group : '') + ' · ' + b.projects + ' project(s) · ' + b.tasks + ' task(s) · ' + b.awaiting + ' awaiting you', { bold: true }))

    // The need-you rail: the AWAITING verbs, counted off each task's `awaiting` plus one
    // `close` per project whose `awaiting_close` is set — print-board.sh's rule.
    const need: Record<string, number> = {}
    for (const v of VERBS) need[v] = 0
    const inFlight: { slug: string; t: Task }[] = []
    for (const p of b.rows) {
      if (p.awaiting_close) need.close += 1
      for (const t of p.tasks) {
        if ((VERBS as readonly string[]).includes(t.awaiting)) need[t.awaiting] += 1
        if (t.in_flight) inFlight.push({ slug: p.slug, t })
      }
    }
    rows.push(line('need you: ' + VERBS.map(v => v + ' ' + need[v]).join(' · ')))

    rows.push(line(' '))
    rows.push(line('in flight (' + inFlight.length + ')', { bold: true }))
    if (inFlight.length === 0) rows.push(line('nothing in flight', { dimColor: true }))
    for (const { slug, t } of inFlight) {
      rows.push(line('  ' + slug + '/' + t.id + ' · ' + (t.assignee || 'unassigned') + ' · ' + t.status
        + (t.prs ? ' · PR ' + (t.pr_mergeable || 'UNKNOWN') : '') + ' · ' + t.title))
    }

    rows.push(line(' '))
    rows.push(line('projects (' + b.rows.length + ')', { bold: true }))
    for (const p of b.rows) {
      let aw = p.awaiting_close ? 1 : 0
      let fly = 0
      for (const t of p.tasks) { if ((VERBS as readonly string[]).includes(t.awaiting)) aw += 1; if (t.in_flight) fly += 1 }
      rows.push(line('  ' + p.slug + ' · ' + p.status + ' · phases ' + p.phase_done + '/' + p.phase_total
        + ' · tasks ' + p.tasks.length + ' · in flight ' + fly + ' · awaiting ' + aw + ' · ' + p.title))
    }

    rows.push(line(' '))
    rows.push(line('snapshot written ' + (b.generated_at || 'unknown') + (tickQueued ? ' · tick queued' : ''), { dimColor: true }))
  }
  // A refused submit is said, not swallowed: a Tick that silently did nothing is the
  // silent wrong answer convention 12 is about.
  if (tickRefused) rows.push(line('tick refused: ' + tickRefused, { dimColor: true }))

  rows.push(line(' '))
  rows.push(Box({
    flexDirection: 'row', columnGap: 2, children: [
      Button({
        key: 'tick', label: 'Tick', hotkey: 't',
        // The human pressed a key in their own session: one /loopd:dispatch run, queued
        // until the session is idle (the engine's own contract for a plugin's command.run).
        // Not awaited — a handler that waits for the run would block the press. Never on
        // a timer. A COMMAND run, not a prompt: the host refuses a `/` text as a prompt.
        onPress: () => {
          if (tickQueued) return
          tickQueued = true
          tickRefused = ''
          const done = (err?: unknown) => {
            tickQueued = false
            if (err !== undefined) tickRefused = clean(err && (err as any).message ? (err as any).message : String(err)) || 'refused'
            try { $.ui.invalidate('ui.render') } catch { /* no surface to redraw */ }
          }
          let p: any = null
          try { p = $.command.run({ command: DISPATCH }) } catch (err) { done(err); return }
          if (p && typeof p.then === 'function') p.then(() => done(), (err: unknown) => done(err ?? 'refused')); else done()
          try { $.ui.invalidate('ui.render') } catch { /* no surface to redraw */ }
        },
      }),
      Button({
        key: 'refresh', label: 'Refresh', hotkey: 'r',
        onPress: async () => { await refresh($, true); $.ui.invalidate('ui.render') },
      }),
    ],
  }))

  return Box({ flexDirection: 'column', children: rows })
}

// ---------------------------------------------------------------- simple mode
// An inbox, top to bottom: questions, stuck tasks a person can clear, stuck tasks we are
// on, progress. One order rule (docs/operations.md → "The serve-time fill"): oldest task
// `timestamp:` first, then Q<n> within the task, then slug and task id; undated last.
type Question = { label: string; text: string; options: string[]; first: boolean }
type Item = { slug: string; file: string; mtimeMs: number; title: string; status: string; ts: number; stall: number; questions: Question[]; unreadable: boolean }
type Simple = { slug: string; title: string; autonomy: string; ts: number; finished: boolean; done: number; total: number; items: Item[] }
type Doc = { title: string; status: string; autonomy: string; timestamp: string; stall: string; open: string[] | null; body: string } | null
type Held = { kind: 'answer' | 'later'; mtimeMs: number; laterMtime: number; at: number; text: string }
type Entry = { p: Simple; it: Item; q: Question; id: string; later: number }

const UNBLOCK = 'loopd:unblock'
// answer.sh's `later` record, AB_ANSWER_LATER in bundle-paths.sh: one `<task path>#Q<n>` a line.
const LATER = '.loopd/.answer-later'
let simple: Simple[] = []
let docs = new Map<string, { mtimeMs: number; doc: Doc }>()
let sig = ''             // names and mtimes of every file the last scan saw; a change redraws
let later: string[] = []
let laterMtime = -1      // -1 = no file; -2 = a read failed, so the next scan reads again
let sending = ''         // the run that is queued; '' = none, and only then does a key act
let sendLine = ''        // what the open card shows while it is
let sendNote = ''        // the line drawn after a run: a confirmation naming its code, or a refusal
// The run resolves once the command is queued, before answer.sh has written (measured on
// 2.1.300), so an answered question is held until its document's mtime moves (a deferred
// one until the later file's does), or until a turn that started after the press completes
// without moving it (answer.sh refused).
let held = new Map<string, Held>()
// The pane's colours: pink for a row only a person can clear, green for sent and finished
// (loopd-design/cli-theme.json human_pink; plugin/themes/loopd.json success).
const NEEDS_YOU = { color: '#ff7ac2' }
const DONE = { color: '#76d6a4' }
const STUCK_KEYS = ['c', 'd', 'e']

const FIELDS = [['title', 'Title', 'a short name'], ['what', 'What', 'what it should do, in a line'],
  ['whom', 'For whom', 'who needs it'], ['done', 'Done when', 'how you will know; separate several with ;']] as const
let form: Record<string, string> = { title: '', what: '', whom: '', done: '' }
let creating: { at: number; slugs: Set<string>; title: string } | null = null
let createNote = ''

// The YAML subset fold-answers.sh's --list reads (a flow or block list of scalars, its
// escapes only). Anything else is null, drawn as "could not read" — never a guess.
const ESC: Record<string, string> = { n: '\n', t: '\t', '"': '"', '\\': '\\', '/': '/' }
function quoted(s: string, i: number): [string, number] | null {
  const q = s[i]; let out = ''; i += 1
  while (i < s.length) {
    const c = s[i]
    if (q === '"' && c === '\\') { const e = ESC[s[i + 1]]; if (e === undefined) return null; out += e; i += 2; continue }
    if (c === q) { if (q === "'" && s[i + 1] === "'") { out += "'"; i += 2; continue } return [out, i + 1] }
    out += c; i += 1
  }
  return null
}
function scalar(raw: string | undefined): string {
  if (raw === undefined) return ''
  const v = raw.trim()
  if (v[0] === '"' || v[0] === "'") { const r = quoted(v, 0); return r ? r[0] : '' }
  return v.split(/[ \t]#/)[0].trim()
}
function list(fm: string, at: number): string[] | null {
  const rest = fm.slice(at)
  const lead = rest.match(/^[ \t]*/)![0].length
  const out: string[] = []
  if (rest[lead] === '[') {
    let i = lead + 1
    for (;;) {
      while (i < rest.length && /[ \t\n,]/.test(rest[i])) i += 1
      if (i >= rest.length) return null
      if (rest[i] === ']') return out
      if (rest[i] === '"' || rest[i] === "'") { const r = quoted(rest, i); if (!r) return null; out.push(r[0]); i = r[1]; continue }
      let j = i; while (j < rest.length && !/[,\]\n]/.test(rest[j])) j += 1
      const v = rest.slice(i, j).trim(); if (v) out.push(v); i = j
    }
  }
  const lines = rest.split('\n')
  const head = lines[0].trim()
  if (head && head[0] !== '#') return null
  for (const l of lines.slice(1)) {
    const m = l.match(/^[ \t]+-(?:[ \t]+|$)/)
    if (!m) { if (!l.trim()) continue; if (/^[ \t]/.test(l)) return null; break }
    const v = l.slice(m[0].length)
    if (v[0] === '"' || v[0] === "'") { const r = quoted(v, 0); if (!r) return null; out.push(r[0]) } else out.push(v.split(/[ \t]#/)[0].trim())
  }
  return out
}
function parse(text: string): Doc {
  if (!text.startsWith('---\n')) return null
  const end = text.indexOf('\n---', 3)
  if (end < 0) return null
  const fm = text.slice(4, end + 1)
  const oq = fm.match(/^open_questions:/m)
  return {
    title: scalar((fm.match(/^title:(.*)$/m) || [])[1]),
    status: scalar((fm.match(/^status:(.*)$/m) || [])[1]),
    autonomy: scalar((fm.match(/^autonomy:(.*)$/m) || [])[1]),
    timestamp: scalar((fm.match(/^timestamp:(.*)$/m) || [])[1]),
    stall: scalar((fm.match(/^stall_count:(.*)$/m) || [])[1]),
    open: oq ? list(fm, oq.index! + oq[0].length) : [],
    body: text.slice(end + 4),
  }
}
// The `### Q<n>` block, read as answer.sh reads it: lines up to the next h1–h3, a bare
// `Name:` line switches field, options are `n. text` numbered 1 up without a gap.
// Option 1 is the recommendation (SCHEMA.md → "Question details").
function qblock(body: string, label: string): string[] {
  const lines = body.split('\n')
  const at = lines.findIndex(l => /^###\s+/.test(l) && l.replace(/^###\s+/, '').trim() === label)
  const opts: Record<number, string> = {}
  let field = ''
  if (at >= 0) {
    for (const l of lines.slice(at + 1)) {
      if (/^#{1,3}\s/.test(l)) break
      const f = l.match(/^(\w+):\s*$/)
      if (f) { field = f[1]; continue }
      const o = field === 'Options' ? l.match(/^\s*(\d+)\.\s+(.*\S)/) : null
      if (o) opts[parseInt(o[1], 10)] = o[2]
    }
  }
  const options: string[] = []
  while (opts[options.length + 1] !== undefined) options.push(clean(opts[options.length + 1]))
  return options
}
function questions(d: Doc): Question[] {
  const out: Question[] = []
  for (const e of (d && d.open) || []) {
    const cut = e.lastIndexOf(' --- ')
    if (cut >= 0 && e.slice(cut + 5).trim()) continue
    const m = e.match(/^(Q[0-9]+):\s*/)
    const label = m ? m[1] : ''
    const text = clean((m ? e.slice(m[0].length) : e).replace(/ ---\s*$/, ''))
    out.push({ label, text, options: label ? qblock(d!.body, label) : [], first: out.length === 0 })
  }
  return out
}
function when(v: string): number { const t = Date.parse(v); return isFinite(t) ? t : NaN }

// A name that goes into the command line the answer runs as: nothing a shell or the
// skill's argument split could read as more than one word.
const SAFE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/
async function entries($: any, path: string): Promise<{ name: string; kind: string; mtimeMs: number }[]> {
  try { const r = await $.fs.list(path); return Array.isArray(r) ? r : [] } catch { return [] }
}
async function doc($: any, path: string, mtimeMs: number): Promise<Doc> {
  const hit = docs.get(path)
  if (hit && hit.mtimeMs === mtimeMs) return hit.doc
  let text: unknown = null
  try { text = await $.fs.read(path) } catch { text = null }
  reads += 1
  if (typeof text !== 'string') return null
  const d = parse(text)
  docs.set(path, { mtimeMs, doc: d })
  return d
}

async function refreshSimple($: any): Promise<boolean> {
  let cwd: unknown = null
  try { cwd = await $.session.cwd() } catch { cwd = null }
  if (typeof cwd !== 'string' || !cwd) { const was = kind; kind = 'malformed'; detail = 'cannot read the working directory'; return was !== kind }
  const root = cwd.replace(/\/+$/, '')
  let isBundle = false
  try { isBundle = (await $.fs.exists(root + '/' + CONFIG)) === true } catch { isBundle = false }
  if (!isBundle) { const was = kind; kind = 'not-bundle'; detail = 'not a loopd bundle — no ' + CONFIG + ' in ' + clean(root); simple = []; return was !== kind }
  const next: Simple[] = []
  const seen = new Map<string, { mtimeMs: number; doc: Doc }>()
  let s = ''
  for (const p of await entries($, root + '/' + PROJECTS_DIR)) {
    if (p.kind !== 'dir' || !SAFE.test(p.name)) continue
    const pdir = root + '/' + PROJECTS_DIR + '/' + p.name
    const files = await entries($, pdir)
    const pf = files.find(f => f.name === PROJECT_FILE && f.kind === 'file')
    const pd = pf ? await doc($, pdir + '/' + PROJECT_FILE, pf.mtimeMs) : null
    if (pf) { const c = docs.get(pdir + '/' + PROJECT_FILE); if (c) seen.set(pdir + '/' + PROJECT_FILE, c); s += pdir + ':' + pf.mtimeMs + (c ? ';' : '!;') }
    if (pd && pd.status === 'cancelled') continue
    const row: Simple = { slug: p.name, title: (pd && clean(pd.title)) || p.name, autonomy: pd ? pd.autonomy : '', ts: when(pd ? pd.timestamp : ''),
      finished: !!pd && pd.status === 'done', done: 0, total: 0, items: [] }
    next.push(row)
    if (row.finished) continue
    for (const t of await entries($, pdir + '/' + TASKS_DIR)) {
      if (t.kind !== 'file' || !t.name.endsWith(TASK_SUFFIX) || !SAFE.test(t.name)) continue
      const path = pdir + '/' + TASKS_DIR + '/' + t.name
      const d = await doc($, path, t.mtimeMs)
      const c = docs.get(path)
      if (c) seen.set(path, c)
      s += path + ':' + t.mtimeMs + (c ? ';' : '!;')
      const status = d ? d.status : ''
      if (status === 'cancelled') continue
      row.total += 1
      if (status === 'done') row.done += 1
      row.items.push({ slug: p.name, file: t.name, mtimeMs: t.mtimeMs, title: (d && clean(d.title)) || t.name, status, ts: when(d ? d.timestamp : ''),
        stall: toint(d ? d.stall : ''), questions: questions(d), unreadable: !d || d.open === null })
    }
    if (row.total > 0 && row.done === row.total) row.finished = true
  }
  docs = seen
  let st: any = null
  try { st = await $.fs.stat(root + '/' + LATER) } catch { st = null }
  const lm = st && st.kind === 'file' && typeof st.mtimeMs === 'number' ? st.mtimeMs : -1
  if (lm !== laterMtime) {
    let text: unknown = ''
    if (lm >= 0) { try { text = await $.fs.read(root + '/' + LATER) } catch { text = null } reads += 1 }
    later = typeof text === 'string' ? text.split('\n').map(l => clean(l)).filter(Boolean) : []
    laterMtime = typeof text === 'string' ? lm : -2
  }
  s += LATER + ':' + laterMtime + ';'
  const live = new Map<string, Held>()
  for (const r of next) for (const it of r.items) for (const q of it.questions) {
    const id = it.slug + '/' + it.file + '#' + q.label, h = held.get(id)
    if (h && (h.kind === 'later' ? h.laterMtime === laterMtime : h.mtimeMs === it.mtimeMs)) live.set(id, h)
  }
  held = live
  if (creating) {
    const made = next.find(r => r.autonomy && r.title === creating!.title && !creating!.slugs.has(r.slug))
    if (made) {
      createNote = 'Created "' + made.title + '". ' + (made.autonomy === 'yolo' ? 'Its first questions will appear here.' : 'It moves only as far as the operator approves.')
      creating = null
      for (const f of FIELDS) form[f[0]] = ''
    }
  }
  const was = kind
  kind = 'ok'; detail = ''; simple = next
  if (s === sig && was === 'ok') return false
  sig = s
  return true
}

function taskPath(it: Item): string { return PROJECTS_DIR + '/' + it.slug + '/' + TASKS_DIR + '/' + it.file }
// The one order rule. Never a subtraction on qn: Infinity - Infinity is NaN.
function order(a: { ts: number; qn: number; slug: string; file: string }, b: typeof a): number {
  const ad = isNaN(a.ts), bd = isNaN(b.ts)
  if (ad !== bd) return ad ? 1 : -1
  if (!ad && a.ts !== b.ts) return a.ts < b.ts ? -1 : 1
  if (a.qn !== b.qn) return a.qn < b.qn ? -1 : 1
  if (a.slug !== b.slug) return a.slug < b.slug ? -1 : 1
  return a.file < b.file ? -1 : a.file > b.file ? 1 : 0
}
function qn(q: Question): number { return q.label ? parseInt(q.label.slice(1), 10) : Infinity }
// Every open question, in the order the inbox draws them: the rule above, then whatever
// `later` deferred, in the order it was deferred.
function inbox(): Entry[] {
  const out: Entry[] = []
  for (const p of simple) for (const it of p.items) for (const q of it.questions) {
    const id = it.slug + '/' + it.file + '#' + q.label, h = held.get(id)
    const at = q.label ? later.indexOf(taskPath(it) + '#' + q.label) : -1
    out.push({ p, it, q, id, later: h && h.kind === 'later' ? later.length : at })
  }
  const key = (e: Entry) => ({ ts: e.it.ts, qn: qn(e.q), slug: e.it.slug, file: e.it.file })
  return out.sort((a, b) => (a.later < 0) !== (b.later < 0) ? (a.later < 0 ? -1 : 1)
    : a.later >= 0 && a.later !== b.later ? a.later - b.later : order(key(a), key(b)))
}
function tasks(pick: (it: Item) => boolean): { p: Simple; it: Item }[] {
  const out: { p: Simple; it: Item }[] = []
  for (const p of simple) for (const it of p.items) if (pick(it)) out.push({ p, it })
  return out.sort((a, b) => order({ ts: a.it.ts, qn: 0, slug: a.it.slug, file: a.it.file }, { ts: b.it.ts, qn: 0, slug: b.it.slug, file: b.it.file }))
}
const helps = (it: Item) => it.status === 'blocked'
const onIt = (it: Item) => (it.status === 'in-progress' || it.status === 'in-review') && it.stall >= 1

function bar(done: number, total: number): string {
  const w = 10, f = total > 0 ? Math.round((done / total) * w) : 0
  return '█'.repeat(f) + '░'.repeat(w - f) + ' ' + done + '/' + total + ' done'
}
function why(err: unknown): string { return clean(err && (err as any).message ? (err as any).message : String(err)) || 'refused' }

// One slash command per press, and none while another is queued: `sending` is set before
// the first await, so a second key pressed in that window runs nothing.
function run($: any, command: string, args: string, after: (err?: unknown) => void): void {
  const fin = async (err?: unknown) => {
    sending = ''; sendLine = ''
    after(err)
    try { await refreshSimple($) } catch { /* the next poll reads again */ }
    try { $.ui.invalidate('ui.render') } catch { /* no surface to redraw */ }
  }
  let p: any = null
  try { p = $.command.run({ command, args }) } catch (err) { void fin(err); return }
  if (p && typeof p.then === 'function') p.then(() => fin(), (err: unknown) => fin(err ?? 'refused')); else void fin()
  try { $.ui.invalidate('ui.render') } catch { /* no surface to redraw */ }
}

async function send($: any, e: Entry, reply: string): Promise<void> {
  if (sending || !reply) return
  const { p, it, q } = e
  const code = q.label || 'the question'
  sending = e.id
  sendLine = reply === 'later' ? 'Moving ' + code + ' to the end…' : reply === 'more' ? 'Asking for more on ' + code + '…' : 'Sending your answer to ' + code + '…'
  sendNote = ''
  const lm = laterMtime
  let at = 0
  try { at = await $.clock.now() } catch { at = 0 }
  run($, ANSWER, taskPath(it) + (q.label ? ' ' + q.label : '') + ' ' + reply, (err?: unknown) => {
    if (err !== undefined) { sendNote = 'Could not send that answer: ' + why(err); return }
    if (reply === 'more') { sendNote = 'More on ' + code + ' is in the conversation.'; return }
    held.set(e.id, { kind: reply === 'later' ? 'later' : 'answer', mtimeMs: it.mtimeMs, laterMtime: lm, at, text: q.text })
    sendNote = reply === 'later' ? '↷ ' + code + ' moved to the end. We\'ll bring it back after the others.'
      : '✓ Sent your answer to ' + code + ' · ' + p.title + ' · ' + it.title
  })
}

function unblock($: any, p: Simple, it: Item): void {
  if (sending) return
  sending = 'unblock:' + it.slug + '/' + it.file
  sendLine = 'Opening "' + it.title + '" in the conversation…'
  sendNote = ''
  run($, UNBLOCK, taskPath(it), (err?: unknown) => {
    sendNote = err !== undefined ? 'Could not start unblocking "' + it.title + '": ' + why(err)
      : 'Unblocking "' + it.title + '" in ' + p.title + ' — answer in the conversation.'
  })
}

function q(s: string): string { return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"' }

async function create($: any): Promise<void> {
  if (creating) return
  const v: Record<string, string> = {}
  for (const f of FIELDS) v[f[0]] = clean(form[f[0]])
  if (FIELDS.some(f => !v[f[0]])) { createNote = 'Fill in all four fields to create a project.'; $.ui.invalidate('ui.render'); return }
  let at = 0
  try { at = await $.clock.now() } catch { at = 0 }
  creating = { at, slugs: new Set(simple.map(p => p.slug)), title: v.title }
  createNote = ''
  const args = q(v.what) + ' kind=build autonomy=yolo title=' + q(v.title) + ' need=' + q(v.whom) + ' success_criteria=' + q(v.done) + ' --no-ask'
  const failed = (err: unknown) => {
    creating = null
    createNote = 'Could not create the project: ' + (clean(err && (err as any).message ? (err as any).message : String(err)) || 'refused')
    try { $.ui.invalidate('ui.render') } catch { /* no surface to redraw */ }
  }
  let p: any = null
  try { p = $.command.run({ command: NEW_PROJECT, args }) } catch (err) { failed(err); return }
  if (p && typeof p.then === 'function') p.then(() => undefined, (err: unknown) => failed(err ?? 'refused'))
  try { $.ui.invalidate('ui.render') } catch { /* no surface to redraw */ }
}

function drawSimple($: any, e: any): any {
  const { Box, Text, Button, Input } = $.ui.resolve(e)
  const line = (s: string, props: Record<string, unknown> = {}) => Text({ ...props, children: [s] })
  const rows: any[] = []
  if (kind !== 'ok') {
    rows.push(line(kind === 'unread' ? 'loopd: reading…' : detail, { dimColor: kind === 'unread' }))
  } else {
    if (sendNote) rows.push(line(sendNote, sendNote.startsWith('✓') ? DONE : { dimColor: true }))

    rows.push(line('Questions for you', { bold: true }))
    const all = inbox()
    const waiting = all.filter(x => !held.has(x.id) || held.get(x.id)!.kind === 'later')
    const open = sending ? undefined : waiting.find(x => x.q.label || x.q.first)
    if (sendLine) rows.push(line('  ' + sendLine, { dimColor: true }))
    if (open) {
      const { p, it, q } = open
      rows.push(line(' '))
      rows.push(line('  ' + (q.label ? q.label + ' · ' : '') + p.title + ' · ' + it.title, { dimColor: true }))
      rows.push(line('  ' + q.text, { bold: true, ...NEEDS_YOU }))
      q.options.forEach((o, i) => rows.push(Button({ key: 'open-opt' + (i + 1), label: i === 0 ? 'Recommended: ' + o : o,
        ...(i < 9 ? { hotkey: String(i + 1) } : {}), onPress: () => send($, open, String(i + 1)) })))
      if (Input) rows.push(Input({ key: 'open-text', placeholder: 'or type your own answer', submitLabel: 'send',
        onSubmit: (v: string) => { const t = clean(v); if (t) send($, open, '--text ' + t) } }))
      rows.push(Box({ flexDirection: 'row', columnGap: 2, children: [
        Button({ key: 'open-more', label: 'More', hotkey: 'm', onPress: () => send($, open, 'more') }),
        ...(q.label ? [Button({ key: 'open-later', label: 'Later', hotkey: 'l', onPress: () => send($, open, 'later') })] : []),
      ] }))
    }
    const rest = waiting.filter(x => x !== open)
    if (open && rest.length) rows.push(line('  ' + rest.length + ' more ' + (rest.length === 1 ? 'question' : 'questions') + ' after this', { dimColor: true }))
    if (rest.length) rows.push(line(' '))
    for (const x of rest) rows.push(line('  ' + (x.q.label ? x.q.label + ' · ' : '') + x.p.title + ' · ' + x.q.text + (x.later >= 0 ? ' · later' : ''), { dimColor: true }))
    for (const p of simple) for (const it of p.items) if (it.unreadable) rows.push(line('  Could not read the questions in "' + it.title + '" (' + p.title + ').', { dimColor: true }))
    if (all.length === 0) rows.push(line('No open questions.', { dimColor: true }))

    const help = tasks(helps)
    if (help.length) {
      rows.push(line(' '))
      rows.push(line('Stuck — you can help', { bold: true }))
      help.forEach(({ p, it }, i) => {
        rows.push(line('  Unblock "' + it.title + '" in ' + p.title + ': it cannot move until you do.', NEEDS_YOU))
        if (!sending) rows.push(Button({ key: 'unblock-' + (i + 1), label: 'Unblock it', ...(i < STUCK_KEYS.length ? { hotkey: STUCK_KEYS[i] } : {}), onPress: () => unblock($, p, it) }))
      })
    }
    const quiet = tasks(it => !helps(it) && onIt(it))
    if (quiet.length) {
      rows.push(line(' '))
      rows.push(line('Stuck — we\'re on it', { bold: true }))
      for (const { p, it } of quiet) rows.push(line('  "' + it.title + '" in ' + p.title + ': nothing for you to do, we\'re on it.', { dimColor: true }))
    }

    rows.push(line(' '))
    rows.push(line('Progress', { bold: true }))
    const made = [...simple].sort((a, b) => order({ ts: a.ts, qn: 0, slug: a.slug, file: '' }, { ts: b.ts, qn: 0, slug: b.slug, file: '' }))
    if (made.length === 0) rows.push(line('No projects yet.', { dimColor: true }))
    for (const p of made) if (!p.finished) rows.push(line('  ' + bar(p.done, p.total) + ' · ' + p.title))
    const fin = made.filter(p => p.finished)
    if (fin.length) rows.push(line('  ✓ Finished: ' + fin.map(p => p.title).join(', '), DONE))

    rows.push(line(' '))
    rows.push(line('New project', { bold: true }))
    if (creating) rows.push(line('  Creating "' + creating.title + '"…', { dimColor: true }))
    else {
      for (const [k, label, hint] of FIELDS) {
        if (Input) rows.push(Input({ key: 'new-' + k, label, placeholder: hint, value: form[k], submitLabel: 'keep',
          onInput: (v: string) => { form[k] = v }, onSubmit: (v: string) => { form[k] = v; $.ui.invalidate('ui.render') } }))
      }
      rows.push(Button({ key: 'new-create', label: 'Create', onPress: () => create($) }))
    }
    if (createNote) rows.push(line('  ' + createNote, { dimColor: true }))
  }
  rows.push(line(' '))
  rows.push(Button({ key: 'refresh', label: 'Refresh', hotkey: 'r', onPress: async () => { await refreshSimple($); $.ui.invalidate('ui.render') } }))
  return Box({ flexDirection: 'column', children: rows })
}

// A main-loop turn that started after a held answer's press is that answer's turn (a plugin's
// command runs once the session is idle); if it ends with the document unmoved, release it.
async function settle($: any, e: any): Promise<void> {
  if (MODE !== 'simple' || (held.size === 0 && !creating) || (e && e.agentId)) return
  const started = (await $.clock.now()) - toint(e && e.durationMs)
  await refreshSimple($)
  if (creating && started >= creating.at) { creating = null; createNote = 'The project was not created — the conversation says why.' }
  let dropped = ''
  for (const [id, h] of held) if (started >= h.at) { held.delete(id); dropped = h.text }
  if (dropped) sendNote = 'Your answer to "' + dropped + '" did not change the task — see the conversation, then answer again.'
  $.ui.invalidate('ui.render')
}

function summarySimple(): string {
  if (kind !== 'ok') return detail
  return 'loopd: ' + simple.length + ' project(s) · ' + inbox().length + ' question(s) for you · ' + tasks(helps).length + ' blocked'
}

// ---------------------------------------------------------------- hooks
// true when what the pane draws may have changed.
async function reread($: any, force: boolean): Promise<boolean> {
  if (MODE === 'simple') return refreshSimple($)
  const before = reads; await refresh($, force); return reads !== before
}

export function register(on: any, options?: any) {
  MODE = options && options.mode === 'simple' ? 'simple' : 'operator'
  on('session.start', async ($: any, e: any, next: any) => {
    // `immediate` so /pane opens while a turn is streaming. A taken name throws and
    // would skip the rest of this hook, so it is caught and said once, where someone can see it.
    try {
      await $.command.register({ name: COMMAND, description: 'Draw this bundle\'s loopd board in a pane', immediate: true })
    } catch (err: any) {
      if (e && e.isInteractive === true) $.ui.log('/' + COMMAND + ' not registered: ' + clean(err && err.message ? err.message : String(err)))
    }
    return next(e)
  })

  on('command.run', { command: COMMAND }, async ($: any) => {
    await reread($, true)
    let placed = false
    try { const r = await $.ui.open({ id: PANE, title: TITLE }); placed = !!(r && r.isPlaced === true) } catch { placed = false }
    if (!timer) {
      // The poll redraws only when a file it reads moved; it never runs or submits
      // anything. It starts with the pane and ends with it (ui.close below).
      try { timer = $.clock.every(POLL_MS, async () => { if (await reread($, false)) $.ui.invalidate('ui.render') }) } catch { timer = null }
    }
    // Where no surface draws a pane (a narrow terminal, a `-p` run), one transcript line.
    if (!placed) $.ui.log(MODE === 'simple' ? summarySimple() : summary())
    return {}
  }).catch(async (_$: any, e: any, next: any) => next(e))   // fail OPEN: a broken pane never eats the command

  on('turn.complete', async ($: any, e: any, next: any) => {
    try { await settle($, e) } catch { /* the next poll reads again */ }
    return next(e)
  })

  on('ui.close', { id: PANE }, async (_$: any, e: any, next: any) => {
    if (timer) { try { timer.cancel() } catch { /* already gone */ } timer = null }
    return next(e)
  }).catch(async (_$: any, e: any, next: any) => next(e))   // fail OPEN: the pane still closes

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($: any, e: any) => {
    if (kind === 'unread') {
      // Drawn before /pane ran (a reload while the pane stayed up): read, then redraw.
      reread($, true).then(() => $.ui.invalidate('ui.render'), () => $.ui.invalidate('ui.render'))
    }
    return MODE === 'simple' ? drawSimple($, e) : draw($, e)
  })
}
