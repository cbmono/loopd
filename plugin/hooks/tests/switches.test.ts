import { expect, test } from 'claude-code/testing'

// Run from the plugin root: `claude plugin test`. The three mods are three switches in the
// plugin's userConfig, read off register's options and nowhere else: absent is ON, an explicit
// `false` is OFF, and an OFF mod registers no hook at all. The other three files here run one
// mod each with the other two off; this one is where they run together, and where off is
// asserted to mean off.

const BUNDLE = '/work/_loopd-example'
const SID = 'cccccccc-1111-2222-3333-444444444444'

type World = { store: Map<string, unknown>; logged: string[]; registered: string[]; sends: unknown[] }

// Every hook any of the three mods can reach from session.start and turn.complete in a
// bundle root, so a test can switch any combination on.
function stubs(on: any, w: World) {
  on('session.start', () => ({ cwd: BUNDLE }))
  on('session.cwd', () => ({ value: BUNDLE }))
  on('session.id', () => ({ value: SID }))
  on('ui.log', (_$: any, e: any) => { w.logged.push(e.text); return { value: undefined } })
  on('command.register', (_$: any, e: any) => { w.registered.push(e.name); return { value: undefined } })
  on('store.get', (_$: any, e: any) => ({ value: w.store.get(e.key) }))
  on('store.set', (_$: any, e: any) => { w.store.set(e.key, e.value); return { value: undefined } })
  on('fs.exists', (_$: any, e: any) => ({ value: e.path === BUNDLE + '/instance.config.json' }))
  on('fs.stat', () => ({ deny: 'ENOENT' }))
  on('fs.read', () => ({ deny: 'ENOENT' }))
  on('fs.list', () => ({ deny: 'ENOENT' }))
  on('session.send', (_$: any, e: any) => { w.sends.push(e); return { isDelivered: true } })
  on('turn.complete', () => ({ text: '' }))
}
function world(): World { return { store: new Map(), logged: [], registered: [], sends: [] } }

async function session($: any) {
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: BUNDLE })
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 10, isAborted: false, usage: { input_tokens: 1, output_tokens: 1 }, reason: 'answer' })
}

test('with no option stored, all three mods are on: usage logs and records, pane registers /pane, signal records the PM', async ($, on) => {
  const w = world()
  stubs(on, w)
  await session($)
  expect(w.logged).toEqual(['recording this session\'s usage in the plugin store as loopd.usage.<session id>'])
  expect(w.registered).toEqual(['pane'])
  expect([...w.store.keys()].sort()).toEqual(['loopd.pm.' + BUNDLE, 'loopd.usage.' + SID])
  expect((w.store.get('loopd.usage.' + SID) as any).turns).toBe(1)
  expect((w.store.get('loopd.pm.' + BUNDLE) as any).sessionId).toBe(SID)
})

test('usage off: no line, no usage record; the other two still run', { options: { usage: false } }, async ($, on) => {
  const w = world()
  stubs(on, w)
  await session($)
  expect(w.logged).toEqual([])
  expect(w.registered).toEqual(['pane'])
  expect([...w.store.keys()]).toEqual(['loopd.pm.' + BUNDLE])
})

test('pane off: /pane is never registered; the other two still run', { options: { pane: false } }, async ($, on) => {
  const w = world()
  stubs(on, w)
  await session($)
  expect(w.registered).toEqual([])
  expect(w.logged.length).toBe(1)
  expect([...w.store.keys()].sort()).toEqual(['loopd.pm.' + BUNDLE, 'loopd.usage.' + SID])
})

test('signal off: no PM record; the other two still run', { options: { signal: false } }, async ($, on) => {
  const w = world()
  stubs(on, w)
  await session($)
  expect(w.registered).toEqual(['pane'])
  expect([...w.store.keys()]).toEqual(['loopd.usage.' + SID])
})

test('all three off: nothing is logged, registered or written — the plugin is the shell hooks alone', { options: { usage: false, pane: false, signal: false } }, async ($, on) => {
  const w = world()
  stubs(on, w)
  await session($)
  expect(w.logged).toEqual([])
  expect(w.registered).toEqual([])
  expect(w.store.size).toBe(0)
  expect(w.sends).toEqual([])
})
