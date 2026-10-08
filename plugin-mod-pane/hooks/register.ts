// loopd-mod-pane — the bundle's board, drawn in a pane of the session that opens it.
//
// THE FOURTH RENDERER over ONE contract. `plugin/scripts/write-snapshot.sh` derives
// `.loopd/SNAPSHOT.json` from the bundle; `build-board.sh`, `print-board.sh` and
// `watch-board.sh` render it. This module is a renderer too: it reads the SNAPSHOT and
// nothing else, so the writer's field allowlist (docs/conventions.md §11) holds here
// without being re-implemented — no question or blocker text, no document body, no author
// identity and no out-of-bundle path can reach this pane because none is in the file.
//
// WHAT IT READS, exactly (README.md → "What it reads", asserted by tests/mods.test.sh in
// cbmono/loopd): `<cwd>/instance.config.json` (exists? — is this a loopd bundle) and
// `<cwd>/.loopd/SNAPSHOT.json` (stat, then read when the mtime moved), where `<cwd>` is
// `$.session.cwd()`. It never walks up, never reads outside the cwd, never writes.
//
// ABSENCE IS THE OFF SWITCH (conventions 3 and 11): no snapshot file ⇒ one line saying so
// and how to enable, nothing else. The snapshot is untrusted TEXT and untrusted TYPES: every
// string is cleaned for the terminal medium (category C dropped, so ESC cannot repaint and a
// newline cannot forge a row), every number goes through toint() so a drifted field costs
// one 0 and never a throw, and a number is never truncated — a clipped count is a wrong
// count (conventions 11d, 11e).
//
// TWO ACTIONS, both the human's, both idle-only by the engine's own contract: Tick submits
// `/loopd:dispatch` in THIS session (`$.prompt.submit` waits for the session to be idle
// before it starts the turn), Refresh re-reads now. No timer ever submits a prompt, and no
// message goes to another session.
//
// NEVER: a model call, a hook on the permission event, a process, the network, the
// environment, a file write, a walk up from the cwd — tests/mods.test.sh asserts each
// absence on this source, so none of those is spelled here even as a comment.

const PANE = 'loopd-board'
const COMMAND = 'board'
const TITLE = 'loopd board'
const CONFIG = 'instance.config.json'
const SNAPSHOT = '.loopd/SNAPSHOT.json'
const POLL_MS = 5000
const DISPATCH = '/loopd:dispatch'
// write-snapshot.sh's verb set, minus nothing: the pane names the verb, never the reason.
const VERBS = ['approve', 'answer', 'merge', 'unblock', 'close'] as const

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

// Module state. A reload starts it over, and the next poll or /board fills it again.
let kind: Kind = 'unread'
let board: Board | null = null
let detail = ''          // the one line a non-ok kind shows
let mtimeMs = -1         // the snapshot's mtime at the last read; -1 = never read
let reads = 0            // how many times the file was actually read (the poll skips an unchanged one)
let timer: { cancel: () => void } | null = null
let tickQueued = false

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

  rows.push(line(' '))
  rows.push(Box({
    flexDirection: 'row', columnGap: 2, children: [
      Button({
        key: 'tick', label: 'Tick', hotkey: 't',
        // The human pressed a key in their own session: one /loopd:dispatch turn, started
        // when the session is idle (the engine queues it until then). Not awaited — a
        // handler that waits for a turn to start would block the press. Never on a timer.
        onPress: () => {
          if (tickQueued) return
          tickQueued = true
          $.ui.invalidate('ui.render')
          let p: any = null
          try { p = $.prompt.submit({ text: DISPATCH, asUser: true }) } catch { p = null }
          const done = () => { tickQueued = false; $.ui.invalidate('ui.render') }
          if (p && typeof p.then === 'function') p.then(done, done); else done()
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

// ---------------------------------------------------------------- hooks
export function register(on: any) {
  on('session.start', async ($: any, e: any, next: any) => {
    // `immediate` so /board opens while a turn is streaming. A taken name throws and
    // would skip the rest of this hook, so it is caught and said once, where someone can see it.
    try {
      await $.command.register({ name: COMMAND, description: 'Draw this bundle\'s loopd board in a pane', immediate: true })
    } catch (err: any) {
      if (e && e.isInteractive === true) $.ui.log('/' + COMMAND + ' not registered: ' + clean(err && err.message ? err.message : String(err)))
    }
    return next(e)
  })

  on('command.run', { command: COMMAND }, async ($: any) => {
    await refresh($, true)
    let placed = false
    try { const r = await $.ui.open({ id: PANE, title: TITLE }); placed = !!(r && r.isPlaced === true) } catch { placed = false }
    if (!timer) {
      // The poll re-reads only when stat's mtime moved (refresh(…, false)); it never
      // submits anything. It starts with the pane and ends with it (ui.close below).
      try { timer = $.clock.every(POLL_MS, async () => { const before = reads; await refresh($, false); if (reads !== before) $.ui.invalidate('ui.render') }) } catch { timer = null }
    }
    // Where no surface draws a pane (a narrow terminal, a `-p` run), one transcript line.
    if (!placed) $.ui.log(summary())
    return {}
  })

  on('ui.close', { id: PANE }, async (_$: any, e: any, next: any) => {
    if (timer) { try { timer.cancel() } catch { /* already gone */ } timer = null }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($: any, e: any) => {
    if (kind === 'unread') {
      // Drawn before /board ran (a reload while the pane stayed up): read, then redraw.
      refresh($, true).then(() => $.ui.invalidate('ui.render'), () => $.ui.invalidate('ui.render'))
    }
    return draw($, e)
  })
}
