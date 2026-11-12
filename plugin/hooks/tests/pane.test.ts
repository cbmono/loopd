import { expect, mock, test } from 'claude-code/testing'

// Run from the plugin root: `claude plugin test`. No session, no sign-in, no network, no
// file: the files the mod reads are answered by stubs on fs.exists / fs.stat / fs.read / fs.list.
// Each test starts with the module freshly loaded, so `kind` is 'unread'. The usage and
// signal switches are OFF here (ONLY / SIMPLE), so the stubs below are every hook the pane
// mod reaches; switches.test.ts is where all three run together.

const ONLY = { options: { usage: false, signal: false } }
const CWD = '/work/_loopd-example'
const CONFIG = CWD + '/instance.config.json'
const SNAPSHOT = CWD + '/.loopd/SNAPSHOT.json'
const COUNTS = CWD + '/.loopd/counts.json'
const STAMPED = CWD + '/.loopd/seed-base/VERSION'
const PANE_ID = 'loopd-board'

// What Claude Code passes a ui.render hook for this pane, apart from the surface.
const PANE = {
  plugin: 'loopd',
  component: 'Pane',
  requestId: PANE_ID,
  viewport: { columns: 140, rows: 40, isFullscreen: true },
  props: {
    title: 'loopd board',
    isFocused: true,
    bodyColumns: 100,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

// A snapshot of the shape write-snapshot.sh emits (its header is the field list).
const SNAP = {
  _schema: 'loopd board snapshot v1',
  group: 'example',
  generated_at: '2026-10-08T01:02:03Z',
  counts: { projects: 2, tasks: 4, awaiting: 3 },
  projects: [
    {
      slug: 'alpha', title: 'Alpha project', description: 'never drawn', kind: 'build', status: 'active',
      autonomy: 'gated', owner: 'example-user-007', awaiting_close: false,
      phase_progress: { done: 1, total: 3 }, phases: [], deliverable_paths: [],
      tasks: [
        { id: 'task-001', title: 'Ship the widget', kind: 'build', status: 'in-progress', assignee: 'software-engineer',
          phase: '', in_flight: true, pr_mergeable: 'UNKNOWN', awaiting: '', open_questions: 0, open_question_ids: [],
          advisor_notes: 0, depends_on: [], prs: [{ repo: 'o/r', number: 7, url: 'https://github.com/o/r/pull/7' }] },
        { id: 'task-002', title: 'Decide the colour', kind: 'build', status: 'draft', assignee: '',
          phase: '', in_flight: false, pr_mergeable: 'UNKNOWN', awaiting: 'answer', open_questions: 2, open_question_ids: ['Q1', 'Q2'],
          advisor_notes: 0, depends_on: [], prs: [] },
        { id: 'task-003', title: 'Merge me', kind: 'build', status: 'in-review', assignee: 'software-engineer',
          phase: '', in_flight: false, pr_mergeable: 'MERGEABLE', awaiting: 'merge', open_questions: 0, open_question_ids: [],
          advisor_notes: 0, depends_on: [], prs: [{ repo: 'o/r', number: 8, url: 'https://github.com/o/r/pull/8' }] },
      ],
    },
    {
      slug: 'beta', title: 'Beta research', description: 'never drawn', kind: 'research', status: 'active',
      autonomy: 'gated', owner: '', awaiting_close: true,
      phase_progress: { done: 2, total: 2 }, phases: [], deliverable_paths: [],
      tasks: [
        { id: 'task-001', title: 'Done already', kind: 'research', status: 'done', assignee: 'cataloguer',
          phase: '', in_flight: false, pr_mergeable: 'UNKNOWN', awaiting: '', open_questions: 0, open_question_ids: [],
          advisor_notes: 0, depends_on: [], prs: [] },
      ],
    },
    // Listed out of display order: done, paused, active, empty active.
    { slug: 'epsilon', title: 'Epsilon shipped', status: 'done', awaiting_close: false, phase_progress: { done: 0, total: 0 },
      tasks: [{ id: 'task-001', title: 'Shipped', status: 'done', in_flight: false, awaiting: '', prs: [] }] },
    { slug: 'delta', title: 'Delta on hold', status: 'paused', awaiting_close: false, phase_progress: { done: 0, total: 0 },
      tasks: [{ id: 'task-001', title: 'Waiting', status: 'draft', in_flight: false, awaiting: '', prs: [] }] },
    { slug: 'gamma', title: 'Gamma steady', status: 'active', awaiting_close: false, phase_progress: { done: 0, total: 0 },
      tasks: ['done', 'done', 'cancelled', 'in-progress'].map((status, i) => ({ id: 'task-00' + (i + 1), title: 'G' + i, status, in_flight: false, awaiting: '', prs: [] })) },
    { slug: 'zeta', title: 'Zeta empty', status: 'active', awaiting_close: false, phase_progress: { done: 0, total: 0 }, tasks: [] },
  ],
}
const GENERATED = Date.parse(SNAP.generated_at)
// 45 columns of content inside the operator pane's 2-column padding on either side.
const NARROW = { ...PANE, props: { ...PANE.props, bodyColumns: 49 } }

type World = {
  files: Map<string, { text: string; mtimeMs: number }>
  logged: string[]
  submitted: unknown[]
  prompted: unknown[]
  reads: number
  opened: number
  closed: number
  registered: string[]
  onRun?: (e: any) => void
  failReads?: Set<string>
  root?: string
  cwd?: string
}

// Every stub the mod's hooks can reach, registered before the first call on `$`.
// `placed` is what the surface answers $.ui.open with: false is a terminal too narrow.
// `hold` makes the dispatch run stay in flight until the test lets it go (a mock-clock sleep).
function stubs(on: any, w: World, placed = true, hold?: () => Promise<void>) {
  on('session.start', () => ({ cwd: CWD }))
  on('command.register', (_$: any, e: any) => { w.registered.push(e.name); return { value: undefined } })
  on('session.cwd', () => ({ value: w.cwd ?? CWD }))
  on('session.root', () => ({ value: w.root ?? CWD }))
  on('ui.log', (_$: any, e: any) => { w.logged.push(e.text); return { value: undefined } })
  on('ui.open', () => { w.opened += 1; return { value: placed ? { isPlaced: true } : { isPlaced: false, reason: 'the terminal is 80 columns' } } })
  on('ui.close', () => { w.closed += 1; return { value: undefined } })
  // Answer questions runs its COMMAND through the engine (prompt.submit refuses a text that
  // begins with `/`); the stub records what reached it. The prompt.submit stub stays so a
  // regression back to a prompt is counted too (asserted zero).
  on('command.run', async (_$: any, e: any) => { w.submitted.push(e); if (hold) await hold(); if (w.onRun) w.onRun(e); return {} })
  on('turn.complete', () => ({ text: '' }))
  on('prompt.submit', (_$: any, e: any) => { w.prompted.push(e); return { text: e.text } })
  on('fs.exists', (_$: any, e: any) => ({ value: w.files.has(e.path) }))
  on('fs.stat', (_$: any, e: any) => {
    const f = w.files.get(e.path)
    return f ? { value: { kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false } } : { deny: 'ENOENT' }
  })
  on('fs.list', (_$: any, e: any) => {
    const dir = e.path.replace(/\/+$/, '') + '/'
    const out = new Map<string, any>()
    for (const [path, f] of w.files) {
      if (!path.startsWith(dir)) continue
      const rest = path.slice(dir.length), slash = rest.indexOf('/')
      const name = slash < 0 ? rest : rest.slice(0, slash)
      out.set(name, slash < 0 ? { name, kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false } : { name, kind: 'dir', size: 0, mtimeMs: 0, isLink: false })
    }
    return out.size ? { value: [...out.values()] } : { deny: 'ENOENT' }
  })
  on('fs.read', (_$: any, e: any) => {
    const f = w.files.get(e.path)
    w.reads += 1
    if (w.failReads && w.failReads.delete(e.path)) return { deny: 'EACCES' }
    return f ? { value: f.text } : { deny: 'ENOENT' }
  })
}

// The counts.json status-line.sh would write beside a snapshot (counts.sh is its one
// definition): the in-progress task of alpha has a working session, one more is idle.
function countsOf(snap: any): unknown {
  if (!snap || typeof snap !== 'object' || !Array.isArray(snap.projects)) return null
  const tasks = snap.projects.flatMap((p: any) => p.tasks || [])
  const verbs = ['approve', 'answer', 'merge', 'unblock']
  return {
    in_progress: tasks.filter((t: any) => t.status === 'in-progress').length,
    in_review: tasks.filter((t: any) => t.status === 'in-review').length,
    sessions: { working: 1, idle: 1, dead: 0 },
    need_you: tasks.filter((t: any) => verbs.includes(t.awaiting)).length + snap.projects.filter((p: any) => p.awaiting_close).length,
    queue: 'on', task_sessions: { 'projects/alpha/tasks/task-001.md': 'working' }, written_at: snap.generated_at,
  }
}

function world(snapshot: unknown | null, withConfig = true, counts: unknown = countsOf(snapshot)): World {
  const files = new Map<string, { text: string; mtimeMs: number }>()
  if (withConfig) files.set(CONFIG, { text: '{"org": "fixture-org"}', mtimeMs: 1 })
  if (withConfig) files.set(STAMPED, { text: '4.11.0\n', mtimeMs: 1 })
  if (snapshot !== null) files.set(SNAPSHOT, { text: typeof snapshot === 'string' ? snapshot : JSON.stringify(snapshot), mtimeMs: 1000 })
  if (counts !== null) files.set(COUNTS, { text: typeof counts === 'string' ? counts : JSON.stringify(counts), mtimeMs: 500 })
  return { files, logged: [], submitted: [], prompted: [], reads: 0, opened: 0, closed: 0, registered: [] }
}

async function open($: any) {
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: CWD })
  const out = await $.command.run({ command: 'pane', args: '' })
  return out
}

// Every string the drawing shows, joined — the assertions below read the WHOLE pane so a
// line that must be absent (question text, a description) is asserted absent everywhere.
async function shown(ui: any): Promise<string> {
  const all = await ui.findAll({ type: 'Text' })
  return all.map((el: any) => el.text).join('\n')
}
// The pane's rows as drawn: each top-level Text, and each row Box holding a copy Button
// (never the operator buttons' Box), its coloured segments joined.
function flat(n: any): string { return typeof n === 'string' ? n : n && n.children ? n.children.map(flat).join('') : '' }
async function rowsOf(ui: any): Promise<string[]> {
  return (await ui.drawn()).children.filter((c: any) => c.type === 'Text' || (c.type === 'Box' && c.props.key !== 'buttons')).map(flat)
}
const cols = (s: string) => Array.from(s).length
// The banner's mark, the brand line cut to the width beside row 2, the rule to the edge beside row 3.
const LOGO = ['   ▄▄▄▄', '◀━▐    ▌', '  ▝▄▄▄▄▘']
function header(w: number, brand = 'loopd v4.11.0 · example · org: fixture-org'): string[] {
  const room = w - 9
  return [LOGO[0], LOGO[1] + ' ' + (cols(brand) <= room ? brand : Array.from(brand).slice(0, room - 1).join('') + '…'), LOGO[2] + ' ' + '─'.repeat(room)]
}

test('/pane draws the approved layout at 45 columns: header, PROJECTS, IN PROGRESS, IN REVIEW, NEEDS YOU, buttons', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })

  const out = await open($)
  expect(out).toEqual({})
  expect(w.opened).toBe(1)
  expect(w.logged).toEqual([])      // placed, so no transcript fallback line

  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  expect(rows).toEqual([
    ...header(45),
    ' '.repeat(36) + '3 min ago',     // the age alone: the count is NEEDS YOU's
    ' ',
    'PROJECTS (6)',
    ' ',
    '● alpha' + ' '.repeat(28) + '2 need you',
    '  ░░░░░░░░░░  0/3  phases 1/3',
    ' ',
    '✓ beta' + ' '.repeat(35) + 'done',  // awaiting_close: done, and the close is not counted here
    '  ██████████  1/1  phases 2/2',
    ' ',
    '● gamma',
    '  ██████░░░░  2/3',               // cancelled is not counted; floor(10*2/3) = 6 cells
    ' ',
    '● zeta',                          // no tasks: no bar
    ' ',
    '○ delta' + ' '.repeat(32) + 'paused',
    ' ',
    '✓ epsilon' + ' '.repeat(30) + 'closed',
    ' ',
    ' ',
    'IN PROGRESS (2)',
    ' ',
    '   1 working · 1 idle · 0 dead',
    ' ',
    '   software-engineer  Ship the' + ' '.repeat(8) + 'working', ' '.repeat(22) + 'widget',
    '   unassigned  G3' + ' '.repeat(27) + '—',
    ' ',
    ' ',
    'IN REVIEW (1)',
    ' ',
    '   software-engineer  Merge me',
    ' ',
    ' ',
    'NEEDS YOU (3)',
    ' ',
    '1. answer   alpha · Decide the colour',
    '2. merge    alpha · Merge me',
    '3. close    beta',
    ' ',
    '─'.repeat(45),
    ' ',
    ' ',                               // the buttons' Box sits between these two
  ])
  for (const r of rows) expect(cols(r)).toBeLessThanOrEqual(45)
  const text = await shown(ui)
  // No zero counts, no project titles, no ISO timestamp.
  expect(text).not.toMatch(/\b0 need you|approve 0|phases 0\/0|PROJECTS \(0\)/)
  for (const title of ['Alpha project', 'Beta research', 'Gamma steady', 'Zeta empty', 'Delta on hold', 'Epsilon shipped']) expect(text).not.toContain(title)
  expect(text).not.toContain('2026-10-08')
  // The allowlist, from the other side: nothing the snapshot carries that the board must
  // not show is drawn — and the description/owner fields are not drawn either.
  expect(text).not.toContain('never drawn')
  expect(text).not.toContain('example-user-007')
  expect(text).not.toContain('Q1')
  expect(text).not.toContain('github.com')
  // One plain copy Button per PROJECTS name and NEEDS YOU verb, keyed by row index and with
  // no hotkey or autofocus; then the three operator buttons, in order, and no Tick.
  const buttons = await ui.findAll({ type: 'Button' })
  expect(buttons.map((b: any) => [b.key, b.props.label, b.props.hotkey, b.props.plain, b.props.autoFocus])).toEqual([
    ...['alpha', 'beta', 'gamma', 'zeta', 'delta', 'epsilon'].map((s, i) => ['copy-project-' + i, s, undefined, true, undefined]),
    ...['answer', 'merge', 'close'].map((s, i) => ['copy-need-' + i, s, undefined, true, undefined]),
    ['answer', '✎ Answer Questions', undefined, true, undefined], ['refresh', '↻ Refresh', undefined, true, undefined],
    ['close', '✕ Close Pane', undefined, true, undefined]])
  // No hotkey on any button, so the kit draws no `a:`/`r:`/`c:` hint.
  expect(text).not.toMatch(/\b[arc]:/)
  // A blank line, a rule of the pane's width and a blank line above the buttons; one blank line under them.
  const drawn = (await ui.drawn()).children
  const at = drawn.findIndex((c: any) => c.type === 'Box' && c.props.key === 'buttons')
  expect(drawn.slice(at - 3, at).map(flat).concat(drawn.slice(at + 1).map(flat))).toEqual([' ', '─'.repeat(45), ' ', ' '])
  // The pane is padded 2 columns either side; the operator row adds no padding of its own.
  const root = (await ui.drawn()).props
  expect([root.paddingLeft, root.paddingRight]).toEqual([2, 2])
  const row = drawn[at]
  expect([row.props.paddingLeft, row.props.flexDirection, row.props.columnGap]).toEqual([undefined, 'row', 2])
  expect(text).not.toMatch(/tick/i)
  await ui.unmount()
})

test('the layout is coloured with the pastel palette; the buttons take the muted three', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const segs = (await ui.findAll({ type: 'Text' })).filter((el: any) => el.props.color !== undefined)
  const colour = (t: string) => segs.filter((el: any) => el.text === t).map((el: any) => el.props.color)
  // The mark in the banner's own two: pink gate and arrow, blue tube; the brand line bold white.
  expect([colour('▄'), colour('◀━')]).toEqual([['#ff7ac2'], ['#ff7ac2']])
  expect([colour('▄▄▄'), colour('▐    ▌'), colour('▝▄▄▄▄▘')]).toEqual([['#5ea2ff'], ['#5ea2ff'], ['#5ea2ff']])
  const brandSeg = segs.find((el: any) => el.text.startsWith('loopd v4.11.0'))
  expect([brandSeg.props.color, brandSeg.props.bold]).toEqual(['#f5f5f5', true])
  expect(colour('3 min ago')).toEqual(['#6c7488'])
  expect(colour('─'.repeat(36))).toEqual(['#33658A'])              // beside the mark's row 3
  expect(colour('─'.repeat(45))).toEqual(['#33658A'])              // above the buttons
  expect(colour('3 need you')).toEqual([])                 // no header count
  expect(colour('NEEDS YOU')).toEqual(['#DA627D'])
  expect(colour(' (3)')).toEqual(['#DA627D'])
  expect(colour('2. ')).toEqual(['#DA627D'])
  expect(colour('merge')).toEqual(['#DA627D'])             // the copy Button's own Text, as rose as before
  expect(colour('    ')).toEqual(['#DA627D', '#DA627D'])   // merge's and close's padding
  expect(colour('alpha')).toEqual(['#f5f5f5'])             // a PROJECTS name inside its copy Button
  expect(colour('epsilon')).toEqual(['#6c7488'])
  expect(colour('alpha · Merge me')).toEqual(['#f5f5f5'])
  expect(colour('2 need you')).toEqual(['#DA627D'])
  expect(colour('IN PROGRESS')).toEqual(['#86BBD8'])
  expect(colour('IN REVIEW')).toEqual(['#86BBD8'])
  expect(colour('working')).toEqual(['#86BBD8'])          // alpha's row: a session is working
  expect(colour('—')).toEqual(['#6c7488'])                // gamma's row: none recorded
  expect(colour('0 dead')).toEqual(['#DA627D'])
  expect(colour('PROJECTS')).toEqual(['#FCA17D'])
  expect(colour('● ')).toEqual(['#86BBD8', '#86BBD8', '#86BBD8'])
  expect(colour('██████')).toEqual(['#06969A'])
  expect(colour('░░░░')).toEqual(['#33658A'])
  expect(colour('2/3')).toEqual([])                       // inside '  2/3', grey
  expect(colour('  2/3')).toEqual(['#6c7488'])
  expect(colour('○ ')).toEqual(['#6c7488'])
  expect(colour('paused')).toEqual(['#6c7488'])
  expect(colour('✓ ')).toEqual(['#76d6a4', '#6c7488'])    // beta awaits its close; epsilon is closed
  expect(colour('done')).toEqual(['#76d6a4'])
  expect(colour('closed')).toEqual(['#6c7488'])
  expect([...new Set(segs.map((el: any) => el.props.color))].sort()).toEqual(['#06969A', '#33658A', '#5ea2ff', '#6c7488', '#76d6a4', '#86BBD8', '#9A348E', '#DA627D', '#FCA17D', '#f5f5f5', '#ff7ac2'])
  // The kit's Button drops a colour prop, so each operator button's label is a coloured Text
  // child: teal, deep blue, plum — never the bright rose or peach.
  const row = (await ui.drawn()).children.find((c: any) => c.type === 'Box' && c.props.key === 'buttons')
  const tone = row.children.map((b: any) => [b.props.key, b.props.color, b.children.map((t: any) => [flat(t), t.props.color])])
  expect(tone).toEqual([
    ['answer', undefined, [['✎ Answer Questions', '#06969A']]],
    ['refresh', undefined, [['↻ Refresh', '#33658A']]],
    ['close', undefined, [['✕ Close Pane', '#9A348E']]]])
  await ui.unmount()
})

test('HEADER AGE: counts.json with no written_at, so the age reads off the snapshot, and the poll redraws it as it changes', ONLY, async ($, on) => {
  const { written_at: _, ...noStamp } = countsOf(SNAP) as any
  const w = world(SNAP, true, noStamp)
  stubs(on, w)
  const clock = mock.clock(on, { now: GENERATED + 59 * 1000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const head = async () => (await rowsOf(ui))[3]
  expect(await head()).toMatch(/just now$/)
  expect(cols(await head())).toBe(45)
  // No snapshot write, so no mtime change: only the age moved, and the poll redraws it.
  await clock.advance(5000)
  expect(await head()).toMatch(/ 1 min ago$/)
  expect(w.reads).toBe(4)   // the snapshot, counts.json, the config and the stamped VERSION, once each
  const cases: [string, string][] = [
    [new Date(GENERATED + 64000 - 59 * 60000).toISOString(), '59 min ago'],
    [new Date(GENERATED + 64000 - 47 * 3600000).toISOString(), '47 h ago'],
    [new Date(GENERATED + 64000 - 48 * 3600000).toISOString(), '2 d ago'],
    [new Date(GENERATED + 64000 + 60000).toISOString(), 'age unknown'],   // in the future
    ['yesterday', 'age unknown'],
    ['', 'age unknown'],
  ]
  let m = 2000
  for (const [at, want] of cases) {
    w.files.set(SNAPSHOT, { text: JSON.stringify({ ...SNAP, generated_at: at }), mtimeMs: m++ })
    await ui.press({ key: 'refresh' })
    expect(await head()).toMatch(new RegExp(' ' + want + '$'))
  }
  await ui.unmount()
})

test('HEADER LOGO: the banner mark, the brand line cut to the width, the rule to the edge, then the age alone', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  let ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  let rows = await rowsOf(ui)
  expect(rows.slice(0, 5)).toEqual([LOGO[0], LOGO[1] + ' loopd v4.11.0 · example · org: fixt…', LOGO[2] + ' ' + '─'.repeat(36), ' '.repeat(36) + '3 min ago', ' '])
  for (const r of rows.slice(1, 4)) expect(cols(r)).toBe(45)
  await ui.unmount()
  ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  rows = await rowsOf(ui)
  expect(rows[1]).toBe(LOGO[1] + ' loopd v4.11.0 · example · org: fixture-org')   // fits in 96: not cut
  expect(rows[2]).toBe(LOGO[2] + ' ' + '─'.repeat(87))
  // No stamped VERSION, a junk one, no org: each part is left out, never guessed.
  w.files.delete(STAMPED)
  w.files.set(CONFIG, { text: '{}', mtimeMs: 2 })
  await ui.press({ key: 'refresh' })
  expect((await rowsOf(ui))[1]).toBe(LOGO[1] + ' loopd · example')
  w.files.set(STAMPED, { text: '4.11\u001b[2J\n', mtimeMs: 3 })
  await ui.press({ key: 'refresh' })
  expect((await rowsOf(ui))[1]).toBe(LOGO[1] + ' loopd · example')
  await ui.unmount()
})

test('HEADER AGE: a fresh counts.json written_at wins over an old snapshot; an invalid one falls back to the snapshot', ONLY, async ($, on) => {
  const now = GENERATED + 2 * 3600000
  const w = world(SNAP, true, { ...FIXTURE_COUNTS, written_at: new Date(now - 30000).toISOString() })
  stubs(on, w)
  mock.clock(on, { now })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  expect((await rowsOf(ui))[3]).toMatch(/ just now$/)
  w.files.set(COUNTS, { text: JSON.stringify({ ...FIXTURE_COUNTS, written_at: 'yesterday' }), mtimeMs: 900 })
  await ui.press({ key: 'refresh' })
  expect((await rowsOf(ui))[3]).toMatch(/ 2 h ago$/)
  await ui.unmount()
})

test('width comes from bodyColumns, 45 when absent or 0; a 120-character title is cut by code point and its count is not', ONLY, async ($, on) => {
  const snap = JSON.parse(JSON.stringify(SNAP))
  snap.projects[0].slug = 'a' + '😀'.repeat(119)
  snap.projects[0].tasks[1].title = 'Q'.repeat(120)
  const w = world(snap)
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  await open($)
  // The content width: bodyColumns less the 2-column padding either side.
  for (const [props, width] of [[{ bodyColumns: 0 }, 41], [{ bodyColumns: undefined }, 41], [{ bodyColumns: 60 }, 56]] as const) {
    const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, ...props }, surface: 'terminal' })
    const rows = await rowsOf(ui)
    expect(rows.slice(0, 3)).toEqual(header(width))
    for (const r of rows) expect(cols(r)).toBeLessThanOrEqual(width)
    const alpha = rows.find(r => r.startsWith('● a'))!
    expect(cols(alpha)).toBe(width)
    expect(alpha).toMatch(/…  *2 need you$/)
    for (const r of rows) expect(r).not.toMatch(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/)   // no half a pair
    const at = rows.findIndex(r => r.startsWith('1. answer'))
    expect(rows[at + 2]).toMatch(/^ {12}\S.*…$/)          // the third line is the last, and it is cut
    expect(rows[at + 3]).toMatch(/^2\. merge/)
    await ui.unmount()
  }
})

test('PADDING: every row, the buttons and the info line start at column 2 and end by bodyColumns - 2', ONLY, async ($, on) => {
  const w = world(SNAP, true, null)   // no counts.json, so the info line is drawn as well
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  await open($)
  for (const body of [45, 49, 60, 100]) {
    const ui = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: body }, surface: 'terminal' })
    const root = await ui.drawn()
    const left = root.props.paddingLeft
    expect(left).toBeGreaterThanOrEqual(2)
    expect(root.children.at(-1).children.map(flat)).toEqual([HINT])
    for (const c of root.children) {
      const width = c.type === 'Box' && c.props.key === 'buttons'
        ? c.children.reduce((n: number, b: any) => n + cols(flat(b)), 0) + c.props.columnGap * (c.children.length - 1)
        : cols(flat(c))
      expect(left + width).toBeLessThanOrEqual(body - 2)
    }
    await ui.unmount()
  }
})

test('/pane toggles: open, /pane closes through $.ui.close and stops the poll, /pane close on a closed pane does nothing', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  expect([w.opened, w.closed]).toEqual([1, 0])
  await $.command.run({ command: 'pane', args: '' })
  expect([w.opened, w.closed]).toEqual([1, 1])
  // The ui.close hook ran, so the poll is gone: a moved snapshot is not read.
  w.files.set(SNAPSHOT, { text: JSON.stringify(SNAP), mtimeMs: 2000 })
  await clock.advance(5000)
  expect(w.reads).toBe(4)   // the open's four reads: the snapshot, counts.json, the config, the stamped VERSION
  await $.command.run({ command: 'pane', args: 'close' })
  expect([w.opened, w.closed]).toEqual([1, 1])
  await $.command.run({ command: 'pane', args: '' })
  expect([w.opened, w.closed]).toEqual([2, 1])
  await $.command.run({ command: 'pane', args: ' close ' })
  expect([w.opened, w.closed]).toEqual([2, 2])
  expect(w.logged).toEqual([])
})

test('/pane after an unplaced open opens again rather than closing', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w, false)
  mock.clock(on)
  await open($)
  await $.command.run({ command: 'pane', args: '' })
  expect([w.opened, w.closed]).toEqual([2, 0])
})

test('outside a loopd bundle the pane says so and draws nothing else', ONLY, async ($, on) => {
  const w = world(SNAP, false)   // a snapshot, but no instance.config.json: not a bundle
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('not a loopd bundle')
  expect(text).not.toContain('awaiting you')
  expect(text).not.toContain('need you')
  // Never read the snapshot when the cwd is not a bundle: no walk up, no second path.
  expect(w.reads).toBe(0)
  await ui.unmount()
})

// A Bash `cd` moves the session's cwd but not the directory it started in (2026-11-11).
test('started in the bundle, cd-ed elsewhere: the pane still draws the bundle', ONLY, async ($, on) => {
  const w = world(SNAP)
  w.cwd = '/work/loopd'
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).not.toContain('not a loopd bundle')
  expect(text).toContain('PROJECTS')
  await ui.unmount()
})

test('started outside a bundle, cd-ed into one: the pane draws the cwd bundle', ONLY, async ($, on) => {
  const w = world(SNAP)
  w.root = '/work/loopd'
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).not.toContain('not a loopd bundle')
  expect(text).toContain('PROJECTS')
  await ui.unmount()
})

test('neither the start directory nor the cwd is a bundle: the message names the cwd', ONLY, async ($, on) => {
  const w = world(SNAP, false)
  w.root = '/work/elsewhere'
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('not a loopd bundle — no instance.config.json in ' + CWD)
  expect(w.reads).toBe(0)
  await ui.unmount()
})

test('no snapshot: the one off-switch line, with the touch that turns it on', ONLY, async ($, on) => {
  const w = world(null)
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('board OFF')
  expect(text).toContain('touch .loopd/SNAPSHOT.json')
  expect(text).not.toContain('need you')
  expect(w.reads).toBe(0)
  await ui.unmount()
})

test('malformed JSON is one error line and no throw; wrong types draw as 0', ONLY, async ($, on) => {
  const w = world('{ this is not json')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  let text = await shown(ui)
  expect(text).toContain('not valid JSON')
  expect(text).not.toContain('need you')

  // Valid JSON, wrong types (conventions 11d): every number goes through toint().
  w.files.set(SNAPSHOT, { text: JSON.stringify({ counts: { projects: 'many', tasks: null, awaiting: -3 }, projects: 'nope', group: 7 }), mtimeMs: 2000 })
  await ui.press({ key: 'refresh' })
  text = await shown(ui)
  expect(await rowsOf(ui)).toEqual([...header(96, 'loopd v4.11.0 · org: fixture-org'), ' '.repeat(85) + 'age unknown', ' ', 'PROJECTS', ' ', ' ',
    'IN PROGRESS (?)', ' ', '   ? working · ? idle · ? dead', ' ', '   nothing right now', ' ', ' ', 'IN REVIEW (?)', ' ', '   none', ' ', ' ',
    'NEEDS YOU (?)', ' ', '   nothing', ' ', '─'.repeat(96), ' ', ' ', 'counts unavailable — run /loopd:init'])
  await ui.unmount()
})

test('a title carrying a newline, a tab, ESC and a bidi override is drawn without them, and a number is never clipped', ONLY, async ($, on) => {
  const snap = JSON.parse(JSON.stringify(SNAP))
  snap.projects[0].tasks[0].title = 'Ship\nthe\u001b[2Jwidget\u202e now\tplease'
  snap.projects[0].slug = 'alpha\u0000project'
  snap.projects[0].phase_progress = { done: 1234567890, total: '1234567891' }
  const w = world(snap)
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  // print-board.sh's rule, matched exactly: every category-C code point is dropped and
  // the whitespace controls become one space \u2014 so the newline is a space, the tab is a
  // space, ESC and the bidi override are gone, and the `[2J` that followed ESC arrives as
  // inert text (its own docstring says so). A CSI stripper would be a blocklist of known
  // sequences, which conventions 11 rejects; a terminal acts on none of this without ESC.
  expect(text).toContain('Ship the[2Jwidget now please')
  expect(text).toContain('alphaproject')
  expect(text).not.toContain('\u001b')
  expect(text).not.toContain('\u202e')
  expect((await rowsOf(ui)).filter(r => r.startsWith('   software-engineer  Ship the[2Jwidget now please '))).toHaveLength(1)   // one row, not a forged second
  expect(text).toContain('phases 1234567890/1234567891')
  await ui.unmount()
})

test('Answer questions runs exactly /loopd:answer, once per press, never as a prompt', ONLY, async ($, on) => {
  const w = world(SNAP)
  const clock = mock.clock(on)
  // The real engine queues a plugin's command run until the session is idle; the stub
  // stands in for that wait by sleeping on the mock clock until the test advances it.
  stubs(on, w, true, () => clock.sleep(1000))
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'answer' })
  // A refused run is drawn, so a failure here shows the engine's reason in the dump.
  expect(await shown(ui)).not.toContain('answer refused')
  expect(w.submitted.length).toBe(1)
  expect(w.submitted[0]).toMatchObject({ command: 'loopd:answer' })
  expect((w.submitted[0] as any).args ?? '').toBe('')
  expect(w.prompted).toEqual([])            // never as a prompt: the engine refuses a `/` text there
  expect(await shown(ui)).toContain('answer queued')
  // A second press while the first is still in flight is one run, not two.
  await ui.press({ key: 'answer' })
  expect(w.submitted.length).toBe(1)
  // Once the run has gone through, the footer clears and the next press is a new run.
  await clock.advance(1000)
  expect(await shown(ui)).not.toContain('answer queued')
  await ui.press({ key: 'answer' })
  expect(w.submitted.length).toBe(2)
  await ui.unmount()
})

test('a refused Answer run is drawn in the footer, not swallowed', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on)
  w.onRun = () => { throw new Error('busy') }
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'answer' })
  expect(await shown(ui)).toContain('answer refused: ')
  expect(await shown(ui)).not.toContain('answer queued')
  await ui.unmount()
})

test('Close pane closes through $.ui.close, the way /pane close does, and the poll stops', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'close' })
  expect([w.opened, w.closed]).toEqual([1, 1])
  expect(w.submitted).toEqual([])
  w.files.set(SNAPSHOT, { text: JSON.stringify(SNAP), mtimeMs: 2000 })
  await clock.advance(5000)
  expect(w.reads).toBe(4)   // the open's four reads: the snapshot, counts.json, the config, the stamped VERSION
  // Closed, so the next /pane opens again rather than closing.
  await $.command.run({ command: 'pane', args: '' })
  expect([w.opened, w.closed]).toEqual([2, 1])
})

// What reached $.ui.copy, and what the stub answers it with.
function copies(on: any, answer: (e: any) => any = () => ({ value: { isCopied: true } })) {
  const got: any[] = []
  on('ui.copy', (_$: any, e: any) => { got.push({ text: e.text, surface: e.surface }); return answer(e) })
  return got
}
const footer = async (ui: any) => (await shown(ui)).split('\n').filter(l => /^(copied|copy |answer )/.test(l))

test('COPY FROM NEEDS YOU: a verb copies the task path or the close row\'s slug, from the snapshot, not the cut text', ONLY, async ($, on) => {
  const snap = JSON.parse(JSON.stringify(SNAP))
  snap.projects[0].slug = 'alpha-' + 'x'.repeat(60)
  const w = world(snap)
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  const got = copies(on)
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const path = 'projects/' + snap.projects[0].slug + '/tasks/task-002.md'
  await ui.press({ key: 'copy-need-0' })
  expect(got).toEqual([{ text: path, surface: 'terminal' }])
  const [line] = await footer(ui)
  expect(line).toBe(('copied: ' + path).slice(0, 44) + '…')    // fit to 45 columns, the ref whole on the clipboard
  await ui.press({ key: 'copy-need-2' })
  expect(got[1]).toEqual({ text: 'beta', surface: 'terminal' })
  expect(await footer(ui)).toEqual(['copied: beta'])              // replaced, not stacked
  expect(w.submitted).toEqual([])
  await ui.unmount()
})

test('COPY FROM PROJECTS: a name copies its slug, with the same footer line', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  const got = copies(on)
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  await ui.press({ key: 'copy-project-3' })
  expect(got).toEqual([{ text: 'zeta', surface: 'terminal' }])
  expect(await footer(ui)).toEqual(['copied: zeta'])
  await ui.unmount()
})

test('SHAPE GUARD: an empty slug or id, or one with /, .. or whitespace, is never copied; keys stay unique', ONLY, async ($, on) => {
  const bad = ['', 'a/b', '..', 'a..b', 'a b', ' alpha', 'alpha\n']
  const snap = { ...SNAP, projects: [
    ...bad.map(slug => ({ slug, status: 'active', awaiting_close: true, tasks: [] })),
    { slug: 'alpha', status: 'active', awaiting_close: false, tasks: bad.map(id => ({ id, title: 'T', awaiting: 'answer' })) },
    { slug: 'alpha', status: 'active', awaiting_close: false, tasks: [] },
  ] }
  const w = world(snap)
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  const got = copies(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const keys = (await ui.findAll({ type: 'Button' })).map((b: any) => b.key)
  expect(new Set(keys).size).toBe(keys.length)
  const pressable = keys.filter((k: string) => k.startsWith('copy-'))
  expect(pressable.length).toBe(9 + 14)
  // The two good `alpha` rows rank first (it needs you) and last.
  for (const key of pressable.filter((k: string) => k !== 'copy-project-0' && k !== 'copy-project-8')) {
    await ui.press({ key })
    expect(await footer(ui)).toEqual(['copy refused: bad ref'])
  }
  expect(got).toEqual([])
  // The other direction: a good slug on the same board still copies.
  await ui.press({ key: 'copy-project-8' })
  expect(got).toEqual([{ text: 'alpha', surface: 'terminal' }])
  await ui.unmount()
})

test('SHAPE GUARD: a task path under a bad slug is never copied, though its id is good', ONLY, async ($, on) => {
  const task = { id: 'task-001', title: 'T', awaiting: 'answer' }
  const snap = { ...SNAP, projects: ['..', 'a/b', 'alpha'].map(slug => ({ slug, status: 'active', awaiting_close: false, tasks: [task] })) }
  const w = world(snap)
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  const got = copies(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  for (const key of ['copy-need-0', 'copy-need-1']) {
    await ui.press({ key })
    expect(await footer(ui)).toEqual(['copy refused: bad ref'])
  }
  expect(got).toEqual([])
  await ui.press({ key: 'copy-need-2' })
  expect(got).toEqual([{ text: 'projects/alpha/tasks/task-001.md', surface: 'terminal' }])
  await ui.unmount()
})

for (const [channel, answer, want] of [
  ['resolves isCopied: false', () => ({ value: { isCopied: false, reason: 'no-clipboard' } }), /^copy failed: no-clipboard$/],
  ['rejects (a hook denies it)', () => ({ deny: 'not here' }), /^copy failed: \S/],
  ['throws', () => { throw new Error('boom') }, /^copy failed: \S/],
] as const) {
  test('FAILED COPY SHOWN: a copy that ' + channel + ' is drawn, never `copied`', ONLY, async ($, on) => {
    const w = world(SNAP)
    stubs(on, w)
    mock.clock(on, { now: GENERATED })
    copies(on, answer as any)
    await open($)
    const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
    await ui.press({ key: 'copy-project-0' })
    const lines = await footer(ui)
    expect(lines.length).toBe(1)
    expect(lines[0]).toMatch(want)
    expect(cols(lines[0])).toBeLessThanOrEqual(45)
    await ui.unmount()
  })
}

test('FOOTER: a copy replaces the Answer line and an Answer the copy line; a re-read clears it; an unconfirmed copy is `copy sent`', ONLY, async ($, on) => {
  const w = world(SNAP)
  const clock = mock.clock(on, { now: GENERATED })
  stubs(on, w, true, () => clock.sleep(1000))
  let confirm = true
  copies(on, () => ({ value: confirm ? { isCopied: true } : {} }))
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  await ui.press({ key: 'answer' })
  expect(await footer(ui)).toEqual(['answer queued'])
  await ui.press({ key: 'copy-project-1' })
  expect(await footer(ui)).toEqual(['copied: beta'])
  await clock.advance(1000)
  w.onRun = () => { throw new Error('busy') }
  await ui.press({ key: 'answer' })
  expect(await footer(ui)).toEqual(['answer queued'])
  await ui.press({ key: 'copy-project-1' })
  expect(await footer(ui)).toEqual(['copied: beta'])
  await clock.advance(1000)
  expect((await footer(ui)).map(l => l.replace(/:.*/, ':'))).toEqual(['answer refused:'])
  await ui.press({ key: 'copy-project-1' })
  expect(await footer(ui)).toEqual(['copied: beta'])
  await ui.press({ key: 'refresh' })
  expect(await footer(ui)).toEqual([])
  confirm = false
  await ui.press({ key: 'copy-project-1' })
  expect(await footer(ui)).toEqual(['copy sent beta'])
  await ui.unmount()
})

// Two need rows, a closed project, a project waiting on its close, nobody working.
function needSnap(title: string) {
  return {
    ...SNAP, counts: { projects: 3, tasks: 2, awaiting: 2 },
    projects: [
      { slug: 'leaner-prompts', title: 'Leaner prompts', status: 'active', awaiting_close: false, phase_progress: { done: 0, total: 0 },
        tasks: [{ id: 'task-007', title, status: 'blocked', in_flight: false, awaiting: 'unblock', prs: [] }] },
      { slug: 'article-batch-8-hygiene', title: 'Article batch 8', status: 'active', awaiting_close: true, phase_progress: { done: 0, total: 0 },
        tasks: [{ id: 'task-001', title: 'Done', status: 'done', in_flight: false, awaiting: '', prs: [] }] },
      { slug: 'article-evaluation', title: 'Article evaluation', status: 'done', awaiting_close: false, phase_progress: { done: 0, total: 0 }, tasks: [] },
    ],
  }
}

test('NEEDS YOU is numbered, slug-prefixed, last, and wraps under its text to three lines', ONLY, async ($, on) => {
  const title = "Judge the trims' quality over the first 20 PRs after the install, and decide any revert"
  const w = world(needSnap(title))
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  expect(rows).toEqual([
    ...header(45),
    ' '.repeat(36) + '1 min ago',
    ' ',
    'PROJECTS (3)',
    ' ',
    '● leaner-prompts' + ' '.repeat(18) + '1 needs you',
    '  ░░░░░░░░░░  0/1',
    ' ',
    '✓ article-batch-8-hygiene' + ' '.repeat(16) + 'done',
    '  ██████████  1/1',
    ' ',
    '✓ article-evaluation' + ' '.repeat(19) + 'closed',
    ' ',
    ' ',
    'IN PROGRESS (0)',
    ' ',
    '   1 working · 1 idle · 0 dead',
    ' ',
    '   nothing right now',
    ' ',
    ' ',
    'IN REVIEW (0)',
    ' ',
    '   none',
    ' ',
    ' ',
    'NEEDS YOU (2)',
    ' ',
    '1. unblock  leaner-prompts · Judge the trims\'',
    "            quality over the first 20 PRs",
    '            after the install, and decide an…',
    '2. close    article-batch-8-hygiene',
    ' ',
    '─'.repeat(45),
    ' ',
    ' ',
  ])
  for (const r of rows) expect(cols(r)).toBeLessThanOrEqual(45)
  await ui.unmount()

  // A row that fits in two lines is not cut; the header carries the age alone.
  const one = { ...needSnap('Judge the trims'), projects: needSnap('Judge the trims').projects.slice(0, 1) }
  w.files.set(SNAPSHOT, { text: JSON.stringify(one), mtimeMs: 2000 })
  w.files.set(COUNTS, { text: JSON.stringify(countsOf(one)), mtimeMs: 2000 })
  const ui2 = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  await ui2.press({ key: 'refresh' })
  const r2 = await rowsOf(ui2)
  expect(r2[3]).toBe(' '.repeat(36) + '1 min ago')
  expect(r2.slice(-7)).toEqual(['NEEDS YOU (1)', ' ', '1. unblock  leaner-prompts · Judge the trims', ' ', '─'.repeat(45), ' ', ' '])
  await ui2.unmount()
})

// The owner's case: a long IN PROGRESS and IN REVIEW title beside a role, and a short row.
const LONG = 'iPhone capability proof: real text recognition and App Attest in a signed build on a real device, with the evidence attached'
function longSnap() {
  const t = (id: string, title: string, status: string, pr_mergeable = 'MERGEABLE') =>
    ({ id, title, status, assignee: 'software-engineer', in_flight: false, pr_mergeable, awaiting: '', prs: [{ repo: 'o/r', number: 9, url: 'https://github.com/o/r/pull/9' }] })
  return {
    ...SNAP, counts: { projects: 1, tasks: 4, awaiting: 0 },
    projects: [{ slug: 'alpha', title: 'Alpha', status: 'active', awaiting_close: false, phase_progress: { done: 0, total: 0 },
      tasks: [t('task-001', LONG, 'in-progress'), t('task-002', LONG, 'in-review'), t('task-003', LONG, 'in-review', 'CONFLICTING'), t('task-004', 'Merge me', 'in-review')] }],
  }
}
// A section's rows: from the line after its heading's blank to the next blank.
function section(rows: string[], h: string): string[] {
  const at = rows.findIndex(r => r.startsWith(h)) + 2
  const rest = rows.slice(at)
  return rest.slice(0, rest.indexOf(' '))
}

test('IN PROGRESS and IN REVIEW wrap like NEEDS YOU: under the title, the right cell kept on line one, three lines at most', ONLY, async ($, on) => {
  const w = world(longSnap())
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  const prog = rows.slice(rows.indexOf('   1 working · 1 idle · 0 dead') + 2)
  expect(prog.slice(0, prog.indexOf(' '))).toEqual([
    '   software-engineer  iPhone' + ' '.repeat(10) + 'working',
    '                      capability proof: real',
    '                      text recognition and A…',
  ])
  expect(section(rows, 'IN REVIEW')).toEqual([
    '   software-engineer  iPhone capability',
    '                      proof: real text',
    '                      recognition and App At…',
    '   software-engineer  iPhone  PR CONFLICTING',
    '                      capability proof: real',
    '                      text recognition and A…',
    '   software-engineer  Merge me',              // a short row, byte for byte as before
  ])
  await ui.unmount()

  for (const body of [45, 100]) {
    const u = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: body }, surface: 'terminal' })
    const r = await rowsOf(u)
    const left = (await u.drawn()).props.paddingLeft
    for (const x of r) expect(left + cols(x)).toBeLessThanOrEqual(body - 2)
    const p = r.slice(r.indexOf('   1 working · 1 idle · 0 dead') + 2)
    for (const sec of [p.slice(0, p.indexOf(' ')), section(r, 'IN REVIEW')]) {
      expect(sec[0]).toMatch(/^ {3}software-engineer {2}iPhone/)
      for (const x of sec) expect(x).toMatch(/^ {3}software-engineer {2}\S|^ {22}\S/)
    }
    await u.unmount()
  }
})

test('STALE SNAPSHOT: a row sits under the section counts.json counts it in, not the one the snapshot says', ONLY, async ($, on) => {
  const path = 'projects/loopd-update-command/tasks/task-001.md'
  const snap = { ...SNAP, projects: [{ slug: 'loopd-update-command', title: 'Update command', status: 'active', awaiting_close: false, phase_progress: { done: 0, total: 0 },
    tasks: [{ id: 'task-001', title: 'Add /loopd:update', status: 'in-progress', assignee: 'software-engineer', in_flight: true, pr_mergeable: 'MERGEABLE', awaiting: '', prs: [] }] }] }
  const counts = { ...(countsOf(snap) as any), in_progress: 0, in_review: 2, sessions: { working: 0, idle: 1, dead: 0, tick_working: 0 },
    task_sessions: { [path]: 'idle' },
    task_status: { [path]: 'in-review', 'projects/gone/tasks/task-009.md': 'in-review', 'projects/x/tasks/task-1.md': 'done', 'projects/../tasks/t.md': 'in-review' } }
  const w = world(snap, true, counts)
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  expect(rows.slice(rows.indexOf('IN PROGRESS (0)'), rows.indexOf('IN PROGRESS (0)') + 6)).toEqual(['IN PROGRESS (0)', ' ', '   0 working · 1 idle · 0 dead', ' ', '   nothing right now', ' '])
  // The snapshot names the row it has; one it lacks is `<slug> · <task id>`; a bad key or word is dropped.
  expect(section(rows, 'IN REVIEW (2)')).toEqual(['   software-engineer  Add /loopd:update', '   gone · task-009'])
  await ui.unmount()
})

test('with nothing needing you: NEEDS YOU (0) and a dim nothing, never hidden; the two session sections show (0) too', ONLY, async ($, on) => {
  const snap = needSnap('x')
  snap.projects = snap.projects.slice(2)
  const w = world(snap)
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  expect(rows).toEqual([...header(45), ' '.repeat(36) + '1 min ago', ' ', 'PROJECTS (1)', ' ',
    '✓ article-evaluation' + ' '.repeat(19) + 'closed', ' ', ' ', 'IN PROGRESS (0)', ' ', '   1 working · 1 idle · 0 dead', ' ', '   nothing right now', ' ', ' ',
    'IN REVIEW (0)', ' ', '   none', ' ', ' ', 'NEEDS YOU (0)', ' ', '   nothing', ' ', '─'.repeat(45), ' ', ' '])
  expect(await shown(ui)).not.toMatch(/PROJECTS \(0\)|none in /)
  const all = await ui.findAll({ type: 'Text' })
  const look = (t: string) => all.filter((el: any) => el.text === t).map((el: any) => el.props.color)
  expect(look('   nothing')).toEqual(look('   none'))              // the same dim grey
  expect(look('   nothing')).toEqual(['#6c7488'])
  await ui.unmount()
})

test('the poll re-reads each file only when its mtime moved, and Refresh re-reads both', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  const clock = mock.clock(on, { now: GENERATED })
  await open($)
  expect(w.reads).toBe(4)   // the config and the stamped VERSION are read on open and Refresh only
  // Three polls over unchanged files: stat only, no read.
  await clock.advance(5000)
  await clock.advance(5000)
  await clock.advance(5000)
  expect(w.reads).toBe(4)
  // The writer rewrote the snapshot: the next poll reads it alone and the drawing follows.
  const moved = JSON.parse(JSON.stringify(SNAP)); moved.projects[0].slug = 'renamed'
  w.files.set(SNAPSHOT, { text: JSON.stringify(moved), mtimeMs: 2000 })
  await clock.advance(5000)
  expect(w.reads).toBe(5)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('renamed')
  // The status line rewrote counts.json: the next poll reads it alone, and the numbers follow.
  w.files.set(COUNTS, { text: JSON.stringify({ ...(countsOf(SNAP) as any), in_progress: 9 }), mtimeMs: 3000 })
  await clock.advance(5000)
  expect(w.reads).toBe(6)
  expect(await shown(ui)).toContain(' (9)')
  // Refresh reads both, even with no mtime change.
  await ui.press({ key: 'refresh' })
  expect(w.reads).toBe(10)
  // Nothing was run or submitted by a timer or a refresh.
  expect(w.submitted).toEqual([])
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('where no surface places the pane, one transcript line carries the summary', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w, false)   // a narrow terminal: the pane is open but waits undrawn
  mock.clock(on)
  await open($)
  expect(w.logged).toEqual(['loopd board: 2 project(s) · 4 task(s) · 3 awaiting you'])
})

test('a non-interactive session registers the command and says nothing', ONLY, async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on)
  await $.session.start({ surface: 'terminal', isInteractive: false, cwd: CWD })
  expect(w.registered).toEqual(['pane'])
  expect(w.logged).toEqual([])
  expect(w.reads).toBe(0)
  expect(w.submitted).toEqual([])
})

// ---------------------------------------------------------------- simple mode
// The task documents the simple mode reads, shaped as a bundle writes them. Everything an
// operator sees — roles, worktrees, branches, PR links, blocker text — is in them on purpose,
// so the absence assertions below are about what the pane DRAWS, not what the fixture lacks.
const P = CWD + '/projects'
function task(fm: string, body = ''): string { return '---\ntype: Task\n' + fm + '\n---\n\n# Context\n\nx\n' + body }
const DOCS: Record<string, string> = {
  [P + '/alpha/project.md']: '---\ntype: Project\ntitle: "Alpha project"\nstatus: active\n---\n',
  [P + '/alpha/tasks/task-001-widget.md']: task('title: "Ship the widget"\nstatus: in-progress\nassignee: software-engineer\nworktree: /work/_wt/task-001\nbranch: alpha-task-001\nsession: 0e2a071d\npr: [ "https://github.com/o/r/pull/7" ]\nopen_questions: [ ]'),
  [P + '/alpha/tasks/task-002-colour.md']: task(
    'title: "Decide the colour"\nstatus: draft\nopen_questions: [ "Q1: Which colour, given the brand, ships first?", "Q2: Old one? --- already answered" ]',
    '\n## Question details\n\n### Q1\nRecommendation: Blue, the brand colour\nOptions:\n1. Blue, the brand colour\n2. Green\n3. Let the designer pick\nContext:\n- Depth 1: one\n- Depth 2: two\n- Depth 3: three\n'),
  [P + '/alpha/tasks/task-003-stuck.md']: task('title: "Import the archive"\nstatus: blocked\nassignee: devops-engineer\nlast_blocker: "PR checks red in the worktree after round 2 of the agent session"\nopen_questions: [ ]'),
  [P + '/alpha/tasks/task-004-done.md']: task("title: 'Done already'\nstatus: done\nopen_questions: [ ]"),
  [P + '/alpha/tasks/task-005-dropped.md']: task('title: "Dropped"\nstatus: cancelled\nopen_questions: [ ]'),
  [P + '/alpha/tasks/task-006-name.md']: task('title: "Name it"\nstatus: draft\nopen_questions:\n  - "Q1: What should it be called?"'),
  [P + '/beta/project.md']: '---\ntype: Project\ntitle: "Beta closed"\nstatus: done\n---\n',
  [P + '/beta/tasks/task-001-x.md']: task('title: "Never shown"\nstatus: blocked\nopen_questions: [ "Q1: hidden?" ]'),
  [P + '/gamma/tasks/task-001-broken.md']: task('title: "Broken list"\nstatus: draft\nopen_questions: [ "Q1: unterminated'),
}
function bundle(snapshot: unknown | null = SNAP): World {
  const w = world(snapshot)
  for (const [path, text] of Object.entries(DOCS)) w.files.set(path, { text, mtimeMs: 1000 })
  return w
}
const SIMPLE = { options: { usage: false, signal: false, paneMode: 'simple' } }
// Everything the pane shows: Text, and the labels of its Buttons and Inputs.
async function everything(ui: any): Promise<string> {
  const els = [...await ui.findAll({ type: 'Text' }), ...await ui.findAll({ type: 'Button' }), ...await ui.findAll({ type: 'Input' })]
  return els.map((el: any) => [el.text, el.props.label, el.props.placeholder].filter(Boolean).join(' ')).join('\n')
}

test('ONE SWITCH: with no paneMode stored, the manifest default draws the operator board', ONLY, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('NEEDS YOU')
  expect(text).not.toContain('Questions for you')
  await ui.unmount()
})

test('ONE SWITCH: instance.config.json saying simple does not switch the mode — only the option does', ONLY, async ($, on) => {
  const w = bundle()
  w.files.set(CONFIG, { text: '{"paneMode":"simple","pane":{"mode":"simple"}}', mtimeMs: 1 })
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('NEEDS YOU')
  await ui.unmount()
})

test('SIMPLE IS AN INBOX: the open question, the rest as lines, blocked tasks, progress — nothing else', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await everything(ui)
  // Projects: done/total off the task statuses (cancelled is not counted), a closed project left out.
  expect(text).toContain('██░░░░░░░░ 1/5 done · Alpha project')
  expect(text).toContain('0/1 done · gamma')
  expect(text).toContain('✓ Finished: Beta closed')
  expect(text).not.toContain('Never shown')
  // The open question: code and project, its text, the recommendation first, the other
  // options, a text field, More and Later.
  expect(text).toContain('Q1 · Alpha project · Decide the colour')
  expect(text).toContain('Which colour, given the brand, ships first?')
  const labels = (await ui.findAll({ type: 'Button' })).map((b: any) => b.props.label)
  expect(labels.slice(0, 5)).toEqual(['Recommended: Blue, the brand colour', 'Green', 'Let the designer pick', 'More', 'Later'])
  expect(await ui.find({ key: 'open-text' })).toBeDefined()
  // Every other question is one line with its code and project, and opens nothing.
  expect(text).toContain('  Q1 · Alpha project · What should it be called?')
  expect(text).toContain('1 more question after this')
  expect((await ui.findAll({ type: 'Input' })).length).toBe(1)
  // An answered entry is not a question; an unparseable list is said, not guessed at.
  expect(text).not.toContain('Old one?')
  expect(text).toContain('Could not read the questions in "Broken list"')
  // A blocked task: one plain sentence with its verb, and never the blocker text.
  expect(text).toContain('Unblock "Import the archive" in Alpha project: it cannot move until you do.')
  // NOTHING ELSE: no operator vocabulary anywhere the pane draws.
  for (const banned of [/agent/i, /tick/i, /\bPR\b/, /pull/i, /session/i, /usage/i, /\bround/i, /worktree/i, /branch/i, /engineer/i, /snapshot/i, /github/i]) {
    expect(text).not.toMatch(banned)
  }
  // Read from the task documents, never from the snapshot.
  expect(w.files.has(SNAPSHOT)).toBe(true)
  await ui.unmount()
})

test('PINK MEANS YOU, GREEN MEANS DONE: the open question and a blocked task are pink, finished is green', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const coloured = (await ui.findAll({ type: 'Text' })).filter((el: any) => el.props.color !== undefined)
  expect(coloured.map((el: any) => [el.props.color, el.text.trim()])).toEqual([
    ['#DA627D', 'Which colour, given the brand, ships first?'],
    ['#DA627D', 'Unblock "Import the archive" in Alpha project: it cannot move until you do.'],
    ['#76d6a4', '✓ Finished: Beta closed'],
  ])
  await ui.unmount()
})

test('EVERY ACTION IS A COMMAND: option, text and more each run /loopd:answer, one at a time', SIMPLE, async ($, on) => {
  const w = bundle()
  const clock = mock.clock(on)
  stubs(on, w, true, () => clock.sleep(1000))
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'open-more' })
  expect(w.submitted[0]).toMatchObject({ command: 'loopd:answer', args: 'projects/alpha/tasks/task-002-colour.md Q1 more' })
  await clock.advance(1000)
  expect(await shown(ui)).toContain('More on Q1 is in the conversation.')
  await ui.press({ key: 'open-opt2' })
  expect(w.submitted[1]).toMatchObject({ command: 'loopd:answer', args: 'projects/alpha/tasks/task-002-colour.md Q1 2' })
  // While it is queued nothing else can be pressed, and the card says so.
  expect(await shown(ui)).toContain('Sending your answer to Q1…')
  expect(await ui.find({ key: 'open-opt1' })).toBeUndefined()
  expect(await ui.find({ key: 'open-text' })).toBeUndefined()
  await clock.advance(1000)
  // The run is through but the document has not moved: still held, so it cannot be answered
  // twice — the next question is the open one.
  expect(await shown(ui)).toContain('✓ Sent your answer to Q1 · Alpha project · Decide the colour')
  expect(await shown(ui)).not.toContain('Which colour')
  expect(await shown(ui)).toContain('Q1 · Alpha project · Name it')
  await ui.input({ key: 'open-text', text: '  Widget\tPro  ' })
  expect(w.submitted[2]).toMatchObject({ command: 'loopd:answer', args: 'projects/alpha/tasks/task-006-name.md Q1 --text Widget Pro' })
  await clock.advance(1000)
  expect(w.submitted.length).toBe(3)
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('an answered question leaves the pane on the next read; a refused run is said', SIMPLE, async ($, on) => {
  const w = bundle()
  const path = P + '/alpha/tasks/task-002-colour.md'
  w.onRun = () => w.files.set(path, { text: DOCS[path].replace('open_questions: [ "Q1:', 'open_questions: [ ]\nanswered: [ "Q1:'), mtimeMs: 2000 })
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'open-opt1' })
  expect(await shown(ui)).not.toContain('Which colour')
  w.onRun = () => { throw new Error('the command is not available') }
  await ui.press({ key: 'open-more' })
  expect(await shown(ui)).toContain('Could not send that answer: ')
  expect(await shown(ui)).toContain('What should it be called?')
  await ui.unmount()
})

test('the bar follows the task documents: the poll re-reads only a file whose mtime moved', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const first = w.reads
  await clock.advance(5000)
  expect(w.reads).toBe(first)
  const path = P + '/alpha/tasks/task-006-name.md'
  w.files.set(path, { text: DOCS[path].replace('status: draft', 'status: done'), mtimeMs: 3000 })
  await clock.advance(5000)
  expect(w.reads).toBe(first + 1)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('████░░░░░░ 2/5 done · Alpha project')
  expect(w.submitted).toEqual([])
  await ui.unmount()
})

test('a failed read is retried on the next scan, not cached under the unchanged mtime', SIMPLE, async ($, on) => {
  const w = bundle()
  w.failReads = new Set([P + '/alpha/tasks/task-002-colour.md'])
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('Could not read the questions in "task-002-colour.md"')
  await ui.press({ key: 'refresh' })
  expect(await shown(ui)).toContain('Which colour, given the brand, ships first?')
  await ui.unmount()
})

test('a held answer is released when its own turn ends without moving the document', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await clock.advance(10000)
  await ui.press({ key: 'open-opt2' })
  expect(await shown(ui)).not.toContain('Which colour')
  // A turn that was already running before the press is not the answer's turn.
  await clock.advance(1000)
  await $.turn.complete({ turnId: 'before', answer: '', durationMs: 5000, isAborted: false, usage: null, reason: 'answer' })
  expect(await shown(ui)).not.toContain('Which colour')
  // The answer's turn ends and answer.sh wrote nothing (it refused): the controls come back.
  await clock.advance(1000)
  await $.turn.complete({ turnId: 'answer', answer: '', durationMs: 500, isAborted: false, usage: null, reason: 'answer' })
  expect(await shown(ui)).toContain('Which colour')
  expect(await shown(ui)).toContain('did not change the task')
  expect(await ui.find({ key: 'open-opt1' })).toBeDefined()
  await ui.unmount()
})

// ---------------------------------------------------------------- the inbox
// Three projects created out of order, questions on tasks dated out of order, a blocked task
// with a question of its own, one stalled task, one recovered task, one finished project.
function proj(title: string, ts: string, status = 'active'): string {
  return '---\ntype: Project\ntitle: "' + title + '"\nstatus: ' + status + '\n' + (ts ? 'timestamp: ' + ts + '\n' : '') + '---\n'
}
const INBOX: Record<string, string> = {
  [P + '/one/project.md']: proj('One', '2026-10-03T00:00:00Z'),
  [P + '/two/project.md']: proj('Two', '2026-10-01T00:00:00Z'),
  [P + '/three/project.md']: proj('Three', ''),
  [P + '/four/project.md']: proj('Four', '2026-09-01T00:00:00Z', 'done'),
  [P + '/five/project.md']: proj('Five', '2026-09-02T00:00:00Z'),
  [P + '/five/tasks/task-001-a.md']: task('title: "All of it"\nstatus: done\ntimestamp: 2026-09-02T00:00:00Z\nopen_questions: [ ]'),
  [P + '/one/tasks/task-001-old.md']: task('title: "Old task"\nstatus: draft\ntimestamp: 2026-10-01T09:00:00Z\nopen_questions: [ "Q3: Old Q3?" ]',
    '\n## Question details\n\n### Q3\nOptions:\n1. Old yes\n2. Old no\n'),
  [P + '/two/tasks/task-001-new.md']: task('title: "New task"\nstatus: draft\ntimestamp: 2026-10-05T00:00:00Z\nopen_questions: [ "Q2: New Q2?", "Q1: New Q1?" ]',
    '\n## Question details\n\n### Q1\nOptions:\n1. Yes\n2. No\n'),
  [P + '/three/tasks/task-001-undated.md']: task('title: "Undated"\nstatus: draft\nopen_questions: [ "Q1: Undated Q1?" ]'),
  [P + '/one/tasks/task-002-blocked.md']: task('title: "Needs a key"\nstatus: blocked\ntimestamp: 2026-10-04T00:00:00Z\nstall_count: 2\nlast_blocker: "SECRET-BLOCKER-TEXT"\nopen_questions: [ "Q1: Which key?" ]',
    '\n## Question details\n\n### Q1\nOptions:\n1. The staging key\n2. A new one\n'),
  [P + '/three/tasks/task-002-blocked.md']: task('title: "Needs access"\nstatus: blocked\ntimestamp: 2026-10-02T00:00:00Z\nlast_blocker: "SECRET-BLOCKER-TEXT"\nopen_questions: [ ]'),
  [P + '/two/tasks/task-002-stalled.md']: task('title: "Flaky check"\nstatus: in-progress\ntimestamp: 2026-10-02T00:00:00Z\nstall_count: 1\nlast_blocker: "SECRET-BLOCKER-TEXT"\nopen_questions: [ ]'),
  [P + '/one/tasks/task-003-recovered.md']: task('title: "Recovered"\nstatus: in-review\ntimestamp: 2026-10-02T00:00:00Z\nstall_count: 0\nlast_blocker: "SECRET-BLOCKER-TEXT"\nopen_questions: [ ]'),
}
// Inserted in REVERSE: fs.list answers in insertion order, so a fixture listed in the expected
// order passes even with the cross-task sort deleted.
function inboxWorld(): World {
  const w = world(SNAP)
  for (const [path, text] of Object.entries(INBOX).reverse()) w.files.set(path, { text, mtimeMs: 1000 })
  return w
}
const LATER_FILE = CWD + '/.loopd/.answer-later'
// Every line under a heading, up to the next blank line.
function under(text: string, heading: string): string[] {
  const l = text.split('\n'), at = l.findIndex(x => x.trim() === heading)
  const out: string[] = []
  for (const x of l.slice(at + 1)) { if (!x.trim() && out.length) break; if (x.trim()) out.push(x.trim()) }
  return out
}
// A key press: the Button whose hotkey it is, if one is drawn.
async function hot(ui: any, k: string): Promise<boolean> {
  const b = (await ui.findAll({ type: 'Button' })).find((el: any) => el.props.hotkey === k)
  if (!b) return false
  await ui.press({ key: b.key })
  return true
}

test('INBOX ORDER: questions by the one order rule, then stuck you can help, stuck we are on it, progress', SIMPLE, async ($, on) => {
  const w = inboxWorld()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  const at = (h: string) => text.split('\n').indexOf(h)
  expect([at('Questions for you'), at('Stuck — you can help'), at('Stuck — we\'re on it'), at('Progress')].every((v, i, a) => v >= 0 && (i === 0 || v > a[i - 1]))).toBe(true)
  // Oldest task first (a later Q3 on an old task ahead of Q1 on a newer one), Q<n> within a
  // task, undated last; a blocked task's own question stays here.
  expect(text).toContain('Q3 · One · Old task')
  expect(under(text, '4 more questions after this')).toEqual([
    'Q1 · One · Which key?', 'Q1 · Two · New Q1?', 'Q2 · Two · New Q2?', 'Q1 · Three · Undated Q1?'])
  // Blocked, by the same rule; each with one button; never its blocker text, and no card.
  expect(under(text, 'Stuck — you can help')).toEqual([
    'Unblock "Needs access" in Three: it cannot move until you do.',
    'Unblock "Needs a key" in One: it cannot move until you do.'])
  expect(under(text, 'Stuck — we\'re on it')).toEqual(['"Flaky check" in Two: nothing for you to do, we\'re on it.'])
  expect(text).not.toContain('SECRET-BLOCKER-TEXT')
  expect(text).not.toContain('Recovered')
  expect((await ui.findAll({ type: 'Input' })).length).toBe(1)
  // Progress in creation order, undated last; finished projects folded into one green line.
  expect(under(text, 'Progress')).toEqual([
    '░░░░░░░░░░ 0/2 done · Two', '░░░░░░░░░░ 0/3 done · One', '░░░░░░░░░░ 0/2 done · Three', '✓ Finished: Four, Five'])
  await ui.unmount()
})

test('INBOX ORDER: two tasks sharing a timestamp keep their questions together, task by task', SIMPLE, async ($, on) => {
  const w = world(SNAP)
  const at = 'timestamp: 2026-10-07T00:00:00Z\n'
  w.files.set(P + '/same/project.md', { text: proj('Same', '2026-10-07T00:00:00Z'), mtimeMs: 1000 })
  w.files.set(P + '/same/tasks/task-001-a.md', { text: task('title: "A"\nstatus: draft\n' + at + 'open_questions: [ "Q2: A Q2?", "Q1: A Q1?" ]'), mtimeMs: 1000 })
  w.files.set(P + '/same/tasks/task-002-b.md', { text: task('title: "B"\nstatus: draft\n' + at + 'open_questions: [ "Q1: B Q1?" ]'), mtimeMs: 1000 })
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('Q1 · Same · A')
  expect(under(text, '2 more questions after this')).toEqual(['Q2 · Same · A Q2?', 'Q1 · Same · B Q1?'])
  await ui.unmount()
})

test('LATER: runs answer later, the next question opens, and a deferred question is drawn last', SIMPLE, async ($, on) => {
  const w = inboxWorld()
  w.onRun = (e: any) => { if (/ later$/.test(e.args)) w.files.set(LATER_FILE, { text: 'projects/one/tasks/task-001-old.md#Q3\n', mtimeMs: 7000 }) }
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('4 more questions after this')
  expect(await hot(ui, 'l')).toBe(true)
  expect(w.submitted[0]).toMatchObject({ command: 'loopd:answer', args: 'projects/one/tasks/task-001-old.md Q3 later' })
  await clock.advance(1000)
  const text = await shown(ui)
  expect(text).toContain('↷ Q3 moved to the end.')
  expect(text).toContain('Q1 · One · Needs a key')
  expect(text).toContain('4 more questions after this')
  expect(under(text, '4 more questions after this').pop()).toBe('Q3 · One · Old Q3? · later')
  await ui.unmount()
})

test('LATER: a question the later file names is drawn last on a fresh read, in the order deferred', SIMPLE, async ($, on) => {
  const w = inboxWorld()
  w.files.set(LATER_FILE, { text: 'projects/two/tasks/task-001-new.md#Q1\nprojects/one/tasks/task-001-old.md#Q3\nnot a key\n', mtimeMs: 7000 })
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('Q1 · One · Needs a key')
  expect(under(text, '4 more questions after this')).toEqual([
    'Q2 · Two · New Q2?', 'Q1 · Three · Undated Q1?', 'Q1 · Two · New Q1? · later', 'Q3 · One · Old Q3? · later'])
  expect(w.submitted).toEqual([])
  await ui.unmount()
})

test('ONE COMMAND PER BUTTON: hotkeys are unique, a 1 while sending runs nothing, the next 1 answers the next question', SIMPLE, async ($, on) => {
  const w = inboxWorld()
  const clock = mock.clock(on)
  stubs(on, w, true, () => clock.sleep(1000))
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const buttons = await ui.findAll({ type: 'Button' })
  const keys = buttons.map((b: any) => b.props.hotkey).filter((k: unknown) => k !== undefined)
  expect(keys).toEqual(['1', '2', 'm', 'l', 'c', 'd', 'n', 'r'])
  expect(new Set(keys).size).toBe(keys.length)
  // The question keys belong to the open card alone.
  expect(buttons.filter((b: any) => /^[0-9ml]$/.test(String(b.props.hotkey))).every((b: any) => String(b.key).startsWith('open-'))).toBe(true)
  const sent = ['projects/one/tasks/task-001-old.md Q3 1', 'projects/one/tasks/task-002-blocked.md Q1 1', 'projects/two/tasks/task-001-new.md Q1 1']
  const said = ['Q3 · One · Old task', 'Q1 · One · Needs a key', 'Q1 · Two · New task']
  for (let i = 0; i < 3; i++) {
    expect(await hot(ui, '1')).toBe(true)
    expect(w.submitted[i]).toMatchObject({ command: 'loopd:answer', args: sent[i] })
    // Pressed again while that run is still being sent: nothing runs.
    expect(await hot(ui, '1')).toBe(false)
    expect(w.submitted.length).toBe(i + 1)
    await clock.advance(1000)
    expect(await shown(ui)).toContain('✓ Sent your answer to ' + said[i])
  }
  expect(await shown(ui)).toContain('Q2 · Two · New task')
  expect(await shown(ui)).toContain('1 more question after this')
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('UNBLOCK: each stuck-you-can-help row runs /loopd:answer on its task, once', SIMPLE, async ($, on) => {
  const w = inboxWorld()
  const clock = mock.clock(on)
  stubs(on, w, true, () => clock.sleep(1000))
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await hot(ui, 'd')).toBe(true)
  expect(w.submitted[0]).toMatchObject({ command: 'loopd:answer', args: 'projects/one/tasks/task-002-blocked.md' })
  expect(await hot(ui, 'c')).toBe(false)
  await clock.advance(1000)
  expect(await shown(ui)).toContain('Unblocking "Needs a key" in One — answer in the conversation.')
  expect(await shown(ui)).not.toContain('SECRET-BLOCKER-TEXT')
  expect(w.submitted.length).toBe(1)
  await ui.unmount()
})

// ---------------------------------------------------------------- a new project
// The pane only draws the form new-project-form.sh keeps; `skill` stands in for the
// /loopd:new-project turn that writes it, the way tests/new-project-form.test.sh pins it.
const FORM_PATH = CWD + '/.loopd/.new-project/form.json'
const FKEYS = ['title', 'what', 'whom', 'done', 'repo']
const FIX: Record<string, string> = { title: 'Give it a short name.', what: 'Say what it should do, in a line.', whom: 'Say who needs it.',
  done: "Tell us how you'll know it's done. One sentence is enough.", repo: 'Name the repository it changes, as owner/name.' }
// What /loopd:new-project leaves on disk: a project and its one seed task, no questions yet.
function scaffold(w: World, autonomy = 'yolo', title = 'Garden \\"log\\"') {
  w.files.set(P + '/garden-log/project.md', { text: '---\ntype: Project\ntitle: "' + title + '"\nstatus: active\nautonomy: ' + autonomy + '\n---\n', mtimeMs: 4000 })
  w.files.set(P + '/garden-log/tasks/task-001-garden-log.md', { text: task('title: "Garden log"\nstatus: draft\nopen_questions: [ ]'), mtimeMs: 4000 })
}
function skill(w: World, defaultRepo = '', made: (w: World) => void = w => scaffold(w)) {
  let t = 5000
  const put = (f: any) => w.files.set(FORM_PATH, { text: JSON.stringify(f), mtimeMs: (t += 1000) })
  return (e: any) => {
    if (e.command !== 'loopd:new-project') return
    const a = String(e.args), cur = w.files.get(FORM_PATH), f = cur ? JSON.parse(cur.text) : null
    if (a === '') { if (!f) put({ fields: { title: '', what: '', whom: '', done: '', repo: defaultRepo }, errors: {} }); return }
    if (a === 'cancel') { w.files.delete(FORM_PATH); return }
    if (a === 'submit') {
      const errors: Record<string, string> = {}
      for (const k of FKEYS) if (!f.fields[k].trim()) errors[k] = FIX[k]
      put({ fields: f.fields, errors })
      if (Object.keys(errors).length === 0) { made(w); w.files.delete(FORM_PATH) }
      return
    }
    const m = a.match(/^([1-5]) "(.*)"$/)!
    f.fields[FKEYS[parseInt(m[1], 10) - 1]] = m[2].replace(/\\(["\\])/g, '$1')
    delete f.errors[FKEYS[parseInt(m[1], 10) - 1]]
    put(f)
  }
}
const ENTRIES = ['1 Garden "log"', '2 A log of what grows', '3 The allotment group', '4 Every bed has an entry; a weekly summary']
async function fillIn(ui: any, entries: string[]) { for (const v of entries) await ui.input({ key: 'form-text', text: v }) }
function args(w: World): string[] { return w.submitted.map((e: any) => e.command + ' ' + e.args) }
async function lines(ui: any): Promise<string[]> { return (await shown(ui)).split('\n').map(l => l.trim()) }

test('FIELD BY FIELD: n opens an empty form of five fields, the repo prefilled with defaultRepo', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = skill(w, 'widgets')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await hot(ui, 'n')).toBe(true)
  expect(w.submitted[0]).toMatchObject({ command: 'loopd:new-project', args: '' })
  const l = await lines(ui)
  expect(l).toContain('New project · 1 of 5 filled')
  expect(l.filter(x => /^[1-5] (Title|What|For whom|Done when|Target repo): /.test(x))).toEqual([
    '1 Title: e.g. a short name', '2 What: e.g. what it should do, in a line', '3 For whom: e.g. who needs it',
    '4 Done when: e.g. how you will know; separate several with ;', '5 Target repo: widgets'])
  // The form replaces the inbox; cancel brings it back.
  expect(await shown(ui)).not.toContain('Questions for you')
  await ui.unmount()
})

test('FIELD BY FIELD: each entry runs /loopd:new-project <n> "<text>", and the field shows saving until the form moves', SIMPLE, async ($, on) => {
  const w = bundle()
  const clock = mock.clock(on)
  const write = skill(w, 'widgets')
  let pending: any = null
  w.onRun = (e: any) => { if (e.args === '') write(e); else pending = e }
  stubs(on, w)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await ui.input({ key: 'form-text', text: '1 Garden "log"' })
  expect(w.submitted[1]).toMatchObject({ command: 'loopd:new-project', args: '1 "Garden \\"log\\""' })
  // Queued, not yet written: the field says so, and nothing else can be pressed.
  expect(await lines(ui)).toContain('1 Title: Garden "log" · saving…')
  expect(await ui.find({ key: 'form-text' })).toBeUndefined()
  expect(await hot(ui, 'y')).toBe(false)
  write(pending)
  await clock.advance(5000)
  expect(await lines(ui)).toContain('1 Title: Garden "log"')
  expect(await lines(ui)).toContain('New project · 2 of 5 filled')
  // A line with no field number runs nothing and says what to type.
  await ui.input({ key: 'form-text', text: 'Garden log' })
  expect(w.submitted.length).toBe(2)
  expect(await shown(ui)).toContain("Start with the field's number, 1 to 5, then the text.")
  await ui.unmount()
})

test('TEXT IS DATA: an entry carrying options is one quoted field, never an option', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = skill(w, 'widgets')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await ui.input({ key: 'form-text', text: '2 autonomy=yolo repo=x/y kind=research --no-ask' })
  expect(w.submitted[1]).toMatchObject({ command: 'loopd:new-project', args: '2 "autonomy=yolo repo=x/y kind=research --no-ask"' })
  expect(await lines(ui)).toContain('2 What: autonomy=yolo repo=x/y kind=research --no-ask')
  expect(await lines(ui)).toContain('5 Target repo: widgets')
  await ui.unmount()
})

test('SUBMIT COMPLETE: y runs /loopd:new-project submit once, then the board shows the new project', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = skill(w, 'widgets')
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await fillIn(ui, ENTRIES)
  expect(await lines(ui)).toContain('New project · 5 of 5 filled')
  expect(await hot(ui, 'y')).toBe(true)
  expect(args(w)).toEqual(['loopd:new-project ', 'loopd:new-project 1 "Garden \\"log\\""', 'loopd:new-project 2 "A log of what grows"',
    'loopd:new-project 3 "The allotment group"', 'loopd:new-project 4 "Every bed has an entry; a weekly summary"', 'loopd:new-project submit'])
  const text = await shown(ui)
  expect(text).toContain('Created "Garden "log"". Its first questions will appear here.')
  expect(text).toContain('0/1 done · Garden "log"')
  expect(text).toContain('Questions for you')
  expect(await ui.find({ key: 'form-submit' })).toBeUndefined()
  await clock.advance(60000)
  expect(w.submitted.length).toBe(6)
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('SUBMIT COMPLETE: until the project appears the board says Creating, and a second n runs nothing', SIMPLE, async ($, on) => {
  const w = bundle()
  const write = skill(w, 'widgets')
  let hold = false
  w.onRun = (e: any) => { if (!(hold && e.args === 'submit')) write(e) }
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await fillIn(ui, ENTRIES)
  hold = true
  await hot(ui, 'y')
  expect(await shown(ui)).toContain('Creating "Garden "log""…')
  expect(await hot(ui, 'n')).toBe(false)
  await clock.advance(5000)
  expect(await shown(ui)).toContain('Creating "Garden "log""…')
  write({ command: 'loopd:new-project', args: 'submit' })
  await clock.advance(5000)
  expect(await shown(ui)).toContain('Created "Garden "log"".')
  expect(w.submitted.filter((e: any) => e.args === 'submit').length).toBe(1)
  await ui.unmount()
})

test('✗ ON A MISSING FIELD: submit redraws the form with ✗ on each empty field, in pink, and creates nothing', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = skill(w, 'widgets')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await fillIn(ui, [ENTRIES[0], ENTRIES[2]])
  await hot(ui, 'y')
  const l = await lines(ui)
  expect(l).toContain('New project · 2 things to fix')
  expect(l.filter(x => x.startsWith('✗ '))).toEqual(['✗ ' + FIX.what, '✗ ' + FIX.done])
  const pink = (await ui.findAll({ type: 'Text' })).filter((el: any) => el.props.color === '#DA627D').map((el: any) => el.text.trim())
  expect(pink).toEqual(['New project · 2 things to fix', '✗ ' + FIX.what, '✗ ' + FIX.done])
  expect(w.files.has(P + '/garden-log/project.md')).toBe(false)
  expect(await ui.find({ key: 'form-submit' })).toBeDefined()
  // Filling one clears its ✗ only.
  await ui.input({ key: 'form-text', text: ENTRIES[1] })
  expect((await lines(ui)).filter(x => x.startsWith('✗ '))).toEqual(['✗ ' + FIX.done])
  await ui.unmount()
})

test('TARGET REPO: on a bundle with no defaultRepo an empty repo field is a ✗ on that field, and nothing is created', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = skill(w, '')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  expect(await lines(ui)).toContain('5 Target repo: e.g. owner/name')
  await fillIn(ui, ENTRIES)
  await hot(ui, 'y')
  expect((await lines(ui)).filter(x => x.startsWith('✗ '))).toEqual(['✗ ' + FIX.repo])
  expect(w.files.has(P + '/garden-log/project.md')).toBe(false)
  await ui.input({ key: 'form-text', text: '5 acme/widgets' })
  await hot(ui, 'y')
  expect(await shown(ui)).toContain('Created "Garden "log"".')
  await ui.unmount()
})

test('CANCEL: x runs /loopd:new-project cancel and returns to the board with nothing saved', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = skill(w, 'widgets')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const before = [...w.files.keys()].filter(k => k !== FORM_PATH).sort()
  await hot(ui, 'n')
  await fillIn(ui, ENTRIES.slice(0, 2))
  expect(await hot(ui, 'x')).toBe(true)
  expect(w.submitted[w.submitted.length - 1]).toMatchObject({ command: 'loopd:new-project', args: 'cancel' })
  expect(w.files.has(FORM_PATH)).toBe(false)
  expect([...w.files.keys()].sort()).toEqual(before)
  const text = await shown(ui)
  expect(text).toContain('Cancelled — nothing saved.')
  expect(text).toContain('Questions for you')
  expect(await ui.find({ key: 'new-project' })).toBeDefined()
  await ui.unmount()
})

test('EVERY KEY UNIQUE: the form draws y, x and r; the board adds n beside the inbox keys', SIMPLE, async ($, on) => {
  const w = inboxWorld()
  w.onRun = skill(w, 'widgets')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const hotkeys = async () => (await ui.findAll({ type: 'Button' })).map((b: any) => b.props.hotkey).filter((k: unknown) => k !== undefined)
  const board = await hotkeys()
  expect(board).toEqual(['1', '2', 'm', 'l', 'c', 'd', 'n', 'r'])
  await hot(ui, 'n')
  const form = await hotkeys()
  expect(form).toEqual(['y', 'x', 'r'])
  const keys = (await ui.findAll({ type: 'Button' })).map((b: any) => b.key)
  for (const k of [board, form, keys]) expect(new Set(k).size).toBe(k.length)
  await ui.unmount()
})

test('a project the operator must approve step by step says so in one sentence', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = skill(w, 'widgets', w => scaffold(w, 'gated'))
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await fillIn(ui, ENTRIES)
  await hot(ui, 'y')
  expect(await shown(ui)).toContain('Created "Garden "log"". It moves only as far as the operator approves.')
  await ui.unmount()
})

test('NOTHING IS WRITTEN BY THE MOD: a refused run is one line, a turn that ends unmoved is said, nothing retries', SIMPLE, async ($, on) => {
  const w = bundle()
  const write = skill(w, 'widgets')
  w.onRun = write
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await fillIn(ui, ENTRIES)
  w.onRun = () => { throw new Error('the command is not available') }
  await hot(ui, 'y')
  expect((await shown(ui)).split('\n').filter(l => l.includes('Could not create the project: ')).length).toBe(1)
  expect(await ui.find({ key: 'form-submit' })).toBeDefined()
  // Queued, and its turn ended with nothing moved: the form comes back as it was.
  w.onRun = () => undefined
  await clock.advance(10000)
  await hot(ui, 'y')
  await clock.advance(1000)
  await $.turn.complete({ turnId: 'create', answer: '', durationMs: 500, isAborted: false, usage: null, reason: 'answer' })
  expect(await shown(ui)).toContain('The project was not created — the conversation says why.')
  expect(await lines(ui)).toContain('1 Title: Garden "log"')
  await ui.input({ key: 'form-text', text: '3 Someone' })
  await clock.advance(1000)
  await $.turn.complete({ turnId: 'fill', answer: '', durationMs: 500, isAborted: false, usage: null, reason: 'answer' })
  expect(await shown(ui)).toContain('The form did not change — see the conversation.')
  expect(await ui.find({ key: 'form-text' })).toBeDefined()
  await clock.advance(60000)
  expect(w.submitted.length).toBe(8)
  expect(w.files.has(P + '/garden-log/project.md')).toBe(false)
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('a project someone else adds while a create is pending is not taken for it', SIMPLE, async ($, on) => {
  const w = bundle()
  const write = skill(w, 'widgets')
  w.onRun = (e: any) => {
    if (e.args !== 'submit') return write(e)
    w.files.set(P + '/other-thing/project.md', { text: '---\ntype: Project\ntitle: "Other thing"\nstatus: active\nautonomy: gated\n---\n', mtimeMs: 4000 })
  }
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await hot(ui, 'n')
  await fillIn(ui, ENTRIES)
  await hot(ui, 'y')
  await clock.advance(5000)
  let text = await shown(ui)
  expect(text).toContain('Other thing')
  expect(text).not.toContain('Created "')
  expect(text).toContain('Creating "Garden "log""…')
  write({ command: 'loopd:new-project', args: 'submit' })
  await clock.advance(5000)
  text = await shown(ui)
  expect(text).toContain('Created "Garden "log"". Its first questions will appear here.')
  await ui.unmount()
})

// ---------------------------------------------------------------- counts.json and AWAITING items
// One fixture pair, as status-line.sh and write-snapshot.sh write them: every AWAITING.md
// verb, a project row (review, close, continue) with no task, and sessions in all three states.
const ITEMS_SNAP = {
  ...SNAP,
  awaiting_items: [
    { verb: 'grant', slug: 'alpha', task: 'task-002' }, { verb: 'do', slug: 'alpha', task: 'task-001', text: 'SENTINEL never drawn' },
    { verb: 'answer', slug: 'alpha', task: 'task-002' }, { verb: 'review', slug: 'beta', task: '' },
    { verb: 'merge', slug: 'alpha', task: 'task-003' }, { verb: 'close', slug: 'beta', task: '' }, { verb: 'continue', slug: 'gamma', task: '' },
  ],
}
const FIXTURE_COUNTS = {
  in_progress: 2, in_review: 1, sessions: { working: 2, idle: 1, dead: 1 }, need_you: 7, queue: 'on',
  task_sessions: { 'projects/alpha/tasks/task-001.md': 'working', 'projects/gamma/tasks/task-004.md': 'dead' },
  written_at: SNAP.generated_at,
}
const countOf = (rows: string[], h: string) => { const r = rows.find(x => x.startsWith(h)); const m = r && r.match(/\((\d+|\?)\)$/); return m ? m[1] : r === h ? '0' : 'absent' }

test('SAME NUMBERS: every section count is the value counts.json gives, and NEEDS YOU is AWAITING.md, item for item', ONLY, async ($, on) => {
  const w = world(ITEMS_SNAP, true, FIXTURE_COUNTS)
  stubs(on, w)
  copies(on, () => ({ value: { isCopied: true } }))
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  const c = FIXTURE_COUNTS
  expect(countOf(rows, 'IN PROGRESS')).toBe(String(c.in_progress))
  expect(countOf(rows, 'IN REVIEW')).toBe(String(c.in_review))
  expect(countOf(rows, 'NEEDS YOU')).toBe(String(c.need_you))
  expect(rows[3]).toMatch(/^ +3 min ago$/)
  expect(rows).toContain('   ' + c.sessions.working + ' working · ' + c.sessions.idle + ' idle · ' + c.sessions.dead + ' dead')
  expect(rows.slice(rows.indexOf('IN PROGRESS (2)'))).toEqual([
    'IN PROGRESS (2)', ' ', '   2 working · 1 idle · 1 dead', ' ',
    '   software-engineer  Ship the' + ' '.repeat(8) + 'working', ' '.repeat(22) + 'widget',
    '   unassigned  G3' + ' '.repeat(24) + 'dead',
    ' ', ' ', 'IN REVIEW (1)', ' ', '   software-engineer  Merge me',
    ' ', ' ', 'NEEDS YOU (7)', ' ',
    '1. grant     alpha · Decide the colour',
    '2. do        alpha · Ship the widget',
    '3. answer    alpha · Decide the colour',
    '4. review    beta',
    '5. merge     alpha · Merge me',
    '6. close     beta',
    '7. continue  gamma',
    ' ', '─'.repeat(45), ' ', ' ',
  ])
  // A project's count is its AWAITING items; a close is its `done`, not a count.
  expect(rows).toContain('● alpha' + ' '.repeat(28) + '4 need you')
  expect(rows).toContain('✓ beta' + ' '.repeat(21) + '1 needs you · done')
  expect(rows).toContain('● gamma' + ' '.repeat(27) + '1 needs you')
  expect(rows.join('\n')).not.toContain('counts unavailable')
  expect(await shown(ui)).not.toContain('SENTINEL')
  // A task row copies its task path, a project row its slug.
  await ui.press({ key: 'copy-need-1' })
  expect(await footer(ui)).toEqual(['copied: projects/alpha/tasks/task-001.md'])
  await ui.press({ key: 'copy-need-3' })
  expect(await footer(ui)).toEqual(['copied: beta'])
  await ui.unmount()
})

const HINT = 'counts unavailable — run /loopd:init'

test('COUNTS UNAVAILABLE: no counts.json keeps the layout with ? and one hint under the buttons; an older snapshot\'s NEEDS YOU as today', ONLY, async ($, on) => {
  const w = world(SNAP, true, null)
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  expect(rows.slice(0, 6)).toEqual([...header(45), ' '.repeat(36) + '3 min ago', ' ', 'PROJECTS (6)'])
  for (const h of ['IN PROGRESS', 'IN REVIEW', 'NEEDS YOU']) expect(countOf(rows, h)).toBe('?')
  expect(rows).toContain('   ? working · ? idle · ? dead')
  expect(rows).toContain('   software-engineer  Ship the widget' + ' '.repeat(7) + '?')
  expect(rows).toContain('● alpha' + ' '.repeat(28) + '2 need you')      // labels stay with no counts.json, as the bar's
  expect(rows.slice(rows.indexOf('NEEDS YOU (?)'))).toEqual(['NEEDS YOU (?)', ' ',
    '1. answer   alpha · Decide the colour', '2. merge    alpha · Merge me', '3. close    beta', ' ', '─'.repeat(45), ' ', ' ', HINT])
  expect(rows.filter(r => r === HINT)).toHaveLength(1)
  expect(rows.join('\n')).not.toContain('.loopd/counts.json')
  await ui.unmount()
})

test('COUNTS UNAVAILABLE: an unparseable counts.json is the same ? and hint; a null count is ? with no hint', ONLY, async ($, on) => {
  const w = world(SNAP, true, '{ not json')
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  let rows = await rowsOf(ui)
  expect(rows[5]).toBe('PROJECTS (6)')
  expect([countOf(rows, 'IN PROGRESS'), countOf(rows, 'IN REVIEW')]).toEqual(['?', '?'])
  expect(rows).toContain('   ? working · ? idle · ? dead')
  expect(rows[rows.length - 1]).toBe(HINT)

  w.files.set(COUNTS, { text: JSON.stringify({ ...FIXTURE_COUNTS, in_review: null, sessions: { working: 2, idle: null, dead: 1 } }), mtimeMs: GENERATED })
  await ui.press({ key: 'refresh' })
  rows = await rowsOf(ui)
  expect(rows[5]).toBe('PROJECTS (6)')
  expect([countOf(rows, 'IN PROGRESS'), countOf(rows, 'IN REVIEW'), countOf(rows, 'NEEDS YOU')]).toEqual(['2', '?', '7'])
  expect(rows).toContain('   2 working · ? idle · 1 dead')
  expect(rows).not.toContain(HINT)
  await ui.unmount()
})

test('QUEUE OFF: the bar prints no need-you segment, so the pane draws no header count and no NEEDS YOU', ONLY, async ($, on) => {
  const w = world(SNAP, true, { ...FIXTURE_COUNTS, need_you: null, queue: 'off' })
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  expect(rows[3]).toBe(' '.repeat(36) + '3 min ago')
  expect(rows[5]).toBe('PROJECTS (6)')
  expect(countOf(rows, 'NEEDS YOU')).toBe('absent')
  await ui.unmount()
})

test('QUEUE OFF: no project carries a need-you label, on the task-verb fallback or off awaiting_items', ONLY, async ($, on) => {
  // awaiting: false — write-snapshot.sh leaves awaiting_items out, and alpha's tasks still carry their verbs.
  const w = world(SNAP, true, { ...FIXTURE_COUNTS, need_you: null, queue: 'off' })
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  expect(SNAP.projects[0].tasks.some(t => t.awaiting === 'answer')).toBe(true)
  let rows = await rowsOf(ui)
  expect(rows).toContain('● alpha')
  expect(rows.join('\n')).not.toMatch(/need(s)? you/)
  w.files.set(SNAPSHOT, { text: JSON.stringify(ITEMS_SNAP), mtimeMs: 2000 })
  await ui.press({ key: 'refresh' })
  rows = await rowsOf(ui)
  expect(rows).toContain('● alpha')
  expect(rows.join('\n')).not.toMatch(/need(s)? you/)
  await ui.unmount()
})

test('AWAITING READ FAILURE: awaiting_items null is unknown — NEEDS YOU (?) with no rows and no task-verb fallback', ONLY, async ($, on) => {
  const w = world({ ...SNAP, awaiting_items: null }, true, FIXTURE_COUNTS)
  stubs(on, w)
  mock.clock(on, { now: GENERATED + 3 * 60000 })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  expect(rows.slice(rows.indexOf('NEEDS YOU (?)'))).toEqual(['NEEDS YOU (?)', ' ', ' ', '─'.repeat(45), ' ', ' '])
  expect(rows).toContain('● alpha')                      // no fallback count either
  expect(await ui.findAll({ type: 'Button' }).then((b: any[]) => b.filter(x => String(x.key).startsWith('copy-need-')))).toEqual([])
  await ui.unmount()
})

test('COPY TARGET: a validated AWAITING task with no snapshot row still copies its task path', ONLY, async ($, on) => {
  const w = world({ ...SNAP, awaiting_items: [{ verb: 'answer', slug: 'alpha', task: 'task-009' }] }, true, { ...FIXTURE_COUNTS, need_you: 1 })
  stubs(on, w)
  const got = copies(on)
  mock.clock(on, { now: GENERATED })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  expect(await rowsOf(ui)).toContain('1. answer   alpha · task-009')
  await ui.press({ key: 'copy-need-0' })
  expect(got.map(g => g.text)).toEqual(['projects/alpha/tasks/task-009.md'])
  expect(await footer(ui)).toEqual(['copied: projects/alpha/tasks/task-009.md'])
  await ui.unmount()
})

test('INFO LINE: a note is drawn under the buttons, which never move; it is gone after the poll at +10 s, and the hint returns', ONLY, async ($, on) => {
  const w = world(SNAP, true, null)
  stubs(on, w)
  copies(on)
  const clock = mock.clock(on, { now: GENERATED })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const place = async () => {
    const d = (await ui.drawn()).children
    const at = d.findIndex((c: any) => c.type === 'Box' && c.props.key === 'buttons')
    return [at, d.slice(at + 1).map(flat)]
  }
  const [at] = await place()
  expect(await place()).toEqual([at, [' ', HINT]])
  await ui.press({ key: 'copy-project-1' })
  expect(await place()).toEqual([at, [' ', 'copied: beta']])
  // It starts where the buttons do: neither is indented inside the pane's padding.
  expect([(await ui.drawn()).children[at].props.paddingLeft, ((await place())[1] as string[])[1].search(/\S/)]).toEqual([undefined, 0])
  await clock.advance(9000)
  expect(await place()).toEqual([at, [' ', 'copied: beta']])
  await clock.advance(1000)
  expect(await place()).toEqual([at, [' ', HINT]])
  await ui.unmount()
})

test('INFO LINE: answer queued does not expire while the run is in flight', ONLY, async ($, on) => {
  const w = world(SNAP)
  const clock = mock.clock(on, { now: GENERATED })
  stubs(on, w, true, () => clock.sleep(30000))
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  await ui.press({ key: 'answer' })
  await clock.advance(15000)
  expect(await footer(ui)).toEqual(['answer queued'])
  await clock.advance(15000)
  expect(await footer(ui)).toEqual([])
  await ui.unmount()
})

test('TICK: a working tick is named apart from task sessions, and with no task in progress the empty line says so', ONLY, async ($, on) => {
  const idle = needSnap('x')   // no task in progress
  const cases: [any, Record<string, number>, string, string][] = [
    [idle, { working: 1, idle: 0, dead: 0, tick_working: 1 }, '   1 working (tick) · 0 idle · 0 dead', '   no task in progress — tick running'],
    [idle, { working: 0, idle: 1, dead: 0, tick_working: 0 }, '   0 working · 1 idle · 0 dead', '   nothing right now'],
    [SNAP, { working: 1, idle: 1, dead: 0, tick_working: 0 }, '   1 working · 1 idle · 0 dead', '   software-engineer  Ship the' + ' '.repeat(8) + 'working'],
    [SNAP, { working: 2, idle: 1, dead: 0, tick_working: 1 }, '   2 working (1 tick) · 1 idle · 0 dead', '   software-engineer  Ship the' + ' '.repeat(8) + 'working'],
  ]
  const w = world(idle)
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  let m = 2000
  for (const [snap, sessions, line, first] of cases) {
    w.files.set(SNAPSHOT, { text: JSON.stringify(snap), mtimeMs: m++ })
    w.files.set(COUNTS, { text: JSON.stringify({ ...(countsOf(snap) as any), sessions }), mtimeMs: m++ })
    await ui.press({ key: 'refresh' })
    const rows = await rowsOf(ui)
    const at = rows.indexOf(line)
    expect([line, at > -1]).toEqual([line, true])
    expect(rows[at + 2]).toBe(first)
  }
  await ui.unmount()
})

test('a zero in_review still draws IN REVIEW (0)', ONLY, async ($, on) => {
  const w = world(SNAP, true, { ...FIXTURE_COUNTS, in_review: 0 })
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  expect(countOf(await rowsOf(ui), 'IN REVIEW')).toBe('0')
  expect(await rowsOf(ui)).toContain('IN REVIEW (0)')
  await ui.unmount()
})

// Two owners on one bundle: `mine` is write-snapshot.sh's task-owner.sh verdict per project.
function ownersSnap() {
  const t = (id: string, title: string, status: string) =>
    ({ id, title, status, assignee: 'software-engineer', in_flight: false, pr_mergeable: 'MERGEABLE', awaiting: '', prs: [] })
  const p = (slug: string, status: string, owner: string, mine: boolean | undefined, tasks: any[], awaiting_close = false) =>
    ({ slug, title: slug, status, owner, ...(mine === undefined ? {} : { mine }), awaiting_close, phase_progress: { done: 0, total: 0 }, tasks })
  return {
    ...SNAP, counts: { projects: 7, tasks: 12, awaiting: 1 },
    projects: [
      p('agent-identity', 'paused', 'jdoe', false, [t('task-001', 'Wait', 'draft')]),
      p('leadership-offsite', 'done', 'jdoe', false, []),
      p('billing-export-v2', 'active', 'jdoe', false, [t('task-001', 'Export ledger rows as CSV', 'in-progress'), t('task-002', 'Invoice PDF footer', 'in-review'),
        t('task-003', LONG, 'in-progress'), ...[4, 5, 6].map(i => t('task-00' + i, 'x', 'done')), t('task-007', 'y', 'draft')]),
      p('smartphone', 'active', 'me', true, [t('task-001', 'Own work', 'in-progress'), t('task-002', 'z', 'done')]),
      p('claims', 'active', '', undefined, [t('task-001', 'z', 'done')], true),
      p('no-tag', 'active', 'not a login!', false, [t('task-001', 'Shaped badly', 'in-review')]),
      p('dashed', 'active', 'jdoe--x', false, []),
    ],
  }
}
function ownersCounts(snap: any): unknown {
  const status: Record<string, string> = {}
  for (const p of snap.projects) for (const t of p.tasks) if (t.status === 'in-progress' || t.status === 'in-review') status['projects/' + p.slug + '/tasks/' + t.id + '.md'] = t.status
  return { ...(countsOf(snap) as any), task_status: status, task_sessions: { 'projects/billing-export-v2/tasks/task-001.md': 'working' } }
}

test('OTHER OWNERS: own projects first, then a blank line and one dim line each with @login, closed last; their task rows dim and tagged', ONLY, async ($, on) => {
  const snap = ownersSnap()
  const w = world(snap, true, ownersCounts(snap))
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const rows = await rowsOf(ui)
  const at = rows.indexOf('PROJECTS (7)')
  expect(rows.slice(at, rows.indexOf('IN PROGRESS (3)') - 2)).toEqual([
    'PROJECTS (7)',
    ' ',
    '● smartphone',
    '  █████░░░░░  1/2',
    ' ',
    '✓ claims' + ' '.repeat(33) + 'done',          // no `mine` key: an older snapshot, drawn as mine
    '  ██████████  1/1',
    ' ',
    '● billing-export-v2' + ' '.repeat(16) + '@jdoe  3/7',
    '● no-tag' + ' '.repeat(34) + '0/1',          // an owner that is not a login: no tag
    '● dashed',                                    // `jdoe--x` fails the shape; no tasks, no fraction
    '○ agent-identity' + ' '.repeat(16) + '@jdoe  paused',
    ' ',
    '✓ leadership-offsite' + ' '.repeat(19) + 'closed',
  ])
  const prog = rows.slice(rows.indexOf('   1 working · 1 idle · 0 dead') + 2)
  expect(prog.slice(0, prog.indexOf(' '))).toEqual([
    '   software-engineer  Export ledger   working',
    '                      rows as CSV @jdoe',
    '   software-engineer  iPhone capability     —',   // cut at three lines, so the tag with it; the row stays dim
    '                      proof: real text',
    '                      recognition and App At…',
    '   software-engineer  Own work' + ' '.repeat(14) + '—',
  ])
  expect(section(rows, 'IN REVIEW (2)')).toEqual([
    '   software-engineer  Invoice PDF footer',
    '                      @jdoe',
    '   software-engineer  Shaped badly',
  ])
  for (const r of rows) expect(cols(r)).toBeLessThanOrEqual(45)

  // Every segment of another owner's row is the closed grey; own rows keep their colours.
  const texts = await ui.findAll({ type: 'Text' })
  const look = (s: string) => texts.filter((el: any) => el.text === s).map((el: any) => el.props.color)
  for (const s of ['billing-export-v2', 'agent-identity', '○ ', 'Export ledger', 'rows as CSV @jdoe', 'Invoice PDF footer'])
    expect([s, look(s)]).toEqual([s, ['#6c7488']])
  expect(look('● ')).toEqual(['#86BBD8', '#6c7488', '#6c7488', '#6c7488'])
  const tagged = texts.filter((el: any) => el.props.color !== undefined && el.text.includes('@jdoe'))
  expect(tagged.map((el: any) => el.props.color)).toEqual(Array(4).fill('#6c7488'))   // two project tails, two task rows
  expect(look('working')).toEqual(['#6c7488'])
  expect(look('closed')).toEqual(['#6c7488'])
  expect(look('smartphone')).toEqual(['#f5f5f5'])
  expect(look('Own work')).toEqual(['#f5f5f5'])
  expect(look('   software-engineer  ')).toContain('#86BBD8')
  const text = await shown(ui)
  expect(text).not.toContain('@me')
  expect(text).not.toContain('not a login')
  expect(text).not.toContain('jdoe--x')
  // Counts include everyone: the headings are counts.json's, which counts every task.
  expect([countOf(rows, 'IN PROGRESS'), countOf(rows, 'IN REVIEW'), countOf(rows, 'PROJECTS')]).toEqual(['3', '2', '7'])
  await ui.unmount()

  for (const body of [45, 100]) {
    const u = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: body }, surface: 'terminal' })
    const r = await rowsOf(u)
    for (const x of r) expect(2 + cols(x)).toBeLessThanOrEqual(body - 2)
    expect(r.join('\n')).toContain('@jdoe')
    await u.unmount()
  }
})

test('OTHER OWNERS: a bundle with no owner anywhere draws as today — no blank group, no tag, nothing dim', ONLY, async ($, on) => {
  const snap = ownersSnap()
  snap.projects = snap.projects.map((p: any) => ({ ...p, owner: '', mine: true }))
  const w = world(snap, true, ownersCounts(snap))
  stubs(on, w)
  mock.clock(on, { now: GENERATED })
  await open($)
  const ui = await $.ui.mount({ ...NARROW, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).not.toContain('@')
  const rows = await rowsOf(ui)
  expect(rows.filter(r => r.startsWith('● ') || r.startsWith('○ ') || r.startsWith('✓ ')).length).toBe(7)
  for (let i = 1; i < rows.length; i++) if (/^[●○✓] /.test(rows[i])) expect(rows[i - 1]).toBe(' ')
  const own = (await ui.findAll({ type: 'Text' })).filter((el: any) => ['Own work', 'Export ledger', 'rows as CSV', 'billing-export-v2'].includes(el.text))
  expect(own.map((el: any) => el.props.color)).toEqual(Array(4).fill('#f5f5f5'))
  await ui.unmount()
})
